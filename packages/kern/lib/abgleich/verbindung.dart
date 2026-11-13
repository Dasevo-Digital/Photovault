import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Der Server ist nicht zu erreichen – das Gerät arbeitet offline weiter.
class KeineVerbindung implements Exception {
  KeineVerbindung(this.grund);
  final Object grund;
  @override
  String toString() => 'KeineVerbindung($grund)';
}

/// Der Server hat geantwortet, aber abgelehnt.
class Serverfehler implements Exception {
  Serverfehler(this.status, this.text);
  final int status;
  final String text;

  /// Das Token gilt nicht mehr (abgemeldet, abgelaufen).
  bool get abgemeldet => status == 401;

  @override
  String toString() => 'Serverfehler($status): $text';
}

/// Eine angemeldete Verbindung zu einem Photo Vault Server.
class Serververbindung {
  Serververbindung(
    this.basis,
    this.token, {
    http.Client? client,
    this.downloadStille = const Duration(seconds: 60),
  }) : _http = client ?? http.Client();

  /// z. B. `https://fotos.example.de/`
  final Uri basis;
  final String token;
  final http.Client _http;

  Map<String, String> get _kopf => {'authorization': 'Bearer $token'};

  Uri adresse(String pfad, [Map<String, String>? parameter]) {
    final b = basis.path.endsWith('/')
        ? basis
        : basis.replace(path: '${basis.path}/');
    final ziel = b.resolve(pfad.startsWith('/') ? pfad.substring(1) : pfad);
    return parameter == null ? ziel : ziel.replace(queryParameters: parameter);
  }

  /// Die ganze Anfrage, auch ihr Antwortinhalt, endet nach [zeitlimit]
  /// (#391). Bis 3.67.2 galt die Frist an mehreren Stellen nur bis zu den
  /// Kopfzeilen: Ein danach stockender Inhalt hielt Anfrage, Verbindung und
  /// Warteschlange unbegrenzt fest. Nach Ablauf wird die Anfrage selbst
  /// abgebrochen ([lauf] bekommt den Auslöser für `abortTrigger`), nicht nur
  /// das Warten auf sie; ein Client, der das nicht kann, wird zusätzlich nicht
  /// länger abgewartet. Fehler der Verbindung werden zu [KeineVerbindung].
  Future<T> _mitFrist<T>(
    Duration zeitlimit,
    Future<T> Function(Future<void> abbruch) lauf,
  ) async {
    final abbruch = Completer<void>();
    final uhr = Timer(zeitlimit, () {
      if (!abbruch.isCompleted) abbruch.complete();
    });
    try {
      return await lauf(abbruch.future).timeout(zeitlimit);
    } on SocketException catch (e) {
      throw KeineVerbindung(e);
    } on TimeoutException catch (e) {
      throw KeineVerbindung(e);
    } on http.ClientException catch (e) {
      throw KeineVerbindung(e);
    } finally {
      uhr.cancel();
    }
  }

  /// Mit [abbruch] endet die Anfrage, sobald er eintritt – mit
  /// [KeineVerbindung], wie eine abgerissene Leitung.
  Future<Map<String, Object?>> hole(
    String pfad, {
    Map<String, String>? parameter,
    Duration zeitlimit = const Duration(seconds: 30),
    Future<void>? abbruch,
  }) => _json(zeitlimit, (frist) async {
    final r = http.AbortableRequest(
      'GET',
      adresse(pfad, parameter),
      abortTrigger: abbruch == null ? frist : Future.any([frist, abbruch]),
    )..headers.addAll(_kopf);
    return http.Response.fromStream(await _http.send(r));
  });

  Future<Map<String, Object?>> schicke(
    String pfad,
    Object? inhalt, {
    Duration zeitlimit = const Duration(seconds: 60),
  }) => _json(zeitlimit, (frist) async {
    final r = http.AbortableRequest('POST', adresse(pfad), abortTrigger: frist)
      ..headers.addAll({..._kopf, 'content-type': 'application/json'})
      ..body = jsonEncode(inhalt);
    return http.Response.fromStream(await _http.send(r));
  });

  Future<Map<String, Object?>> _json(
    Duration zeitlimit,
    Future<http.Response> Function(Future<void> abbruch) anfrage,
  ) async {
    final r = await _mitFrist(zeitlimit, anfrage);
    if (r.statusCode >= 300) throw Serverfehler(r.statusCode, r.body);
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    return j is Map ? j.cast<String, Object?>() : {'wert': j};
  }

  /// Eine Anfrage ohne JSON (tus): Fehler der Verbindung werden zu
  /// [KeineVerbindung], die Antwort kommt, wie sie ist.
  Future<http.Response> anfrage(
    String methode,
    String pfad, {
    Map<String, String> kopf = const {},
    List<int>? inhalt,
    Duration zeitlimit = const Duration(minutes: 5),
  }) => _mitFrist(zeitlimit, (frist) async {
    final r = http.AbortableRequest(methode, adresse(pfad), abortTrigger: frist)
      ..headers.addAll({..._kopf, ...kopf});
    if (inhalt != null) r.bodyBytes = inhalt;
    return http.Response.fromStream(await _http.send(r));
  });

  /// Wie lange ein Download ohne neue Bytes sein darf, ehe er als
  /// abgerissen gilt. Eine Gesamtfrist passte nicht: Ein grosses Video
  /// braucht über eine langsame Leitung lange, solange etwas kommt.
  final Duration downloadStille;

  /// Lädt [pfad] nach [ziel] – erst in eine Zwischendatei, dann an ihren
  /// Platz, damit nie eine halbe Datei als ganze dasteht. Stockt der Inhalt
  /// länger als [downloadStille], bricht der Download ab und lässt nichts
  /// liegen (#391); ein neuer Versuch holt die Datei von vorn.
  Future<void> ladeHerunter(String pfad, File ziel) async {
    final abbruch = Completer<void>();
    void brichAb() {
      if (!abbruch.isCompleted) abbruch.complete();
    }

    final http.StreamedResponse r;
    try {
      r = await _http
          .send(
            http.AbortableRequest(
              'GET',
              adresse(pfad),
              abortTrigger: abbruch.future,
            )..headers.addAll(_kopf),
          )
          .timeout(downloadStille);
    } on SocketException catch (e) {
      brichAb();
      throw KeineVerbindung(e);
    } on TimeoutException catch (e) {
      brichAb();
      throw KeineVerbindung(e);
    } on http.ClientException catch (e) {
      throw KeineVerbindung(e);
    }
    final inhalt = r.stream.timeout(
      downloadStille,
      onTimeout: (sink) {
        brichAb();
        sink
          ..addError(TimeoutException('Download stockt', downloadStille))
          ..close();
      },
    );
    if (r.statusCode != 200) {
      final String text;
      try {
        text = await http.ByteStream(inhalt).bytesToString();
      } on Object catch (e) {
        throw KeineVerbindung(e);
      }
      throw Serverfehler(r.statusCode, text);
    }
    await ziel.parent.create(recursive: true);
    final teil = File('${ziel.path}.teil');
    final aus = teil.openWrite();
    try {
      await inhalt.pipe(aus);
    } catch (e) {
      brichAb();
      if (await teil.exists()) await teil.delete();
      throw KeineVerbindung(e);
    }
    await teil.rename(ziel.path);
  }

  /// Legt [datei] auf dem Server unter [pfad] ab (`PUT`), als Ganzes –
  /// für abgeleitete Dateien, die klein genug sind, dass ein Abbruch nur
  /// einen neuen Versuch kostet. Die Frist gilt bis zur ganzen Antwort.
  Future<void> legeAb(String pfad, File datei) async {
    final (status, text) = await _mitFrist(const Duration(minutes: 5), (
      frist,
    ) async {
      final anfrage =
          http.AbortableStreamedRequest(
              'PUT',
              adresse(pfad),
              abortTrigger: frist,
            )
            ..headers.addAll(_kopf)
            ..headers['content-type'] = 'application/octet-stream'
            ..contentLength = await datei.length();
      unawaited(
        datei.openRead().pipe(anfrage.sink).catchError((Object e) {
          anfrage.sink.addError(e);
        }),
      );
      final r = await _http.send(anfrage);
      return (r.statusCode, await r.stream.bytesToString());
    });
    if (status != 204) throw Serverfehler(status, text);
  }

  /// Schickt [datei] als Körper an [pfad] (`POST`), Stück für Stück statt
  /// im Speicher – für Fotos und Videos in ein Album, das ein anderes
  /// Konto teilt (#105). [fortschritt] bekommt gesendete und gesamte
  /// Bytes. Die Antwort ist JSON wie bei [schicke].
  Future<Map<String, Object?>> schickeDatei(
    String pfad,
    File datei, {
    Map<String, String>? parameter,
    void Function(int gesendet, int gesamt)? fortschritt,
    Duration zeitlimit = const Duration(minutes: 30),
  }) async {
    final gesamt = await datei.length();
    return _json(zeitlimit, (frist) async {
      final anfrage =
          http.AbortableStreamedRequest(
              'POST',
              adresse(pfad, parameter),
              abortTrigger: frist,
            )
            ..headers.addAll(_kopf)
            ..headers['content-type'] = 'application/octet-stream'
            ..contentLength = gesamt;
      var gesendet = 0;
      unawaited(
        datei
            .openRead()
            .map((stueck) {
              gesendet += stueck.length;
              fortschritt?.call(gesendet, gesamt);
              return stueck;
            })
            .pipe(anfrage.sink)
            .catchError((Object e) => anfrage.sink.addError(e)),
      );
      return http.Response.fromStream(await _http.send(anfrage));
    });
  }

  void schliesse() => _http.close();
}
