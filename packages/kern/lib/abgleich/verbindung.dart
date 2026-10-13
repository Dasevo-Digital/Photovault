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
  Serververbindung(this.basis, this.token, {http.Client? client})
    : _http = client ?? http.Client();

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

  /// Mit [abbruch] endet die Anfrage, sobald er eintritt – mit
  /// [KeineVerbindung], wie eine abgerissene Leitung.
  Future<Map<String, Object?>> hole(
    String pfad, {
    Map<String, String>? parameter,
    Duration zeitlimit = const Duration(seconds: 30),
    Future<void>? abbruch,
  }) => _json(() async {
    if (abbruch == null) {
      return _http.get(adresse(pfad, parameter), headers: _kopf);
    }
    final r = http.AbortableRequest(
      'GET',
      adresse(pfad, parameter),
      abortTrigger: abbruch,
    )..headers.addAll(_kopf);
    return http.Response.fromStream(await _http.send(r));
  }, zeitlimit);

  Future<Map<String, Object?>> schicke(
    String pfad,
    Object? inhalt, {
    Duration zeitlimit = const Duration(seconds: 60),
  }) => _json(
    () => _http.post(
      adresse(pfad),
      headers: {..._kopf, 'content-type': 'application/json'},
      body: jsonEncode(inhalt),
    ),
    zeitlimit,
  );

  Future<Map<String, Object?>> _json(
    Future<http.Response> Function() anfrage,
    Duration zeitlimit,
  ) async {
    final http.Response r;
    try {
      r = await anfrage().timeout(zeitlimit);
    } on SocketException catch (e) {
      throw KeineVerbindung(e);
    } on TimeoutException catch (e) {
      throw KeineVerbindung(e);
    } on http.ClientException catch (e) {
      throw KeineVerbindung(e);
    }
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
  }) async {
    final r = http.Request(methode, adresse(pfad))
      ..headers.addAll({..._kopf, ...kopf});
    if (inhalt != null) r.bodyBytes = inhalt;
    try {
      return await http.Response.fromStream(
        await _http.send(r).timeout(zeitlimit),
      );
    } on SocketException catch (e) {
      throw KeineVerbindung(e);
    } on TimeoutException catch (e) {
      throw KeineVerbindung(e);
    } on http.ClientException catch (e) {
      throw KeineVerbindung(e);
    }
  }

  /// Lädt [pfad] nach [ziel] – erst in eine Zwischendatei, dann an ihren
  /// Platz, damit nie eine halbe Datei als ganze dasteht.
  Future<void> ladeHerunter(String pfad, File ziel) async {
    final http.StreamedResponse r;
    try {
      r = await _http
          .send(http.Request('GET', adresse(pfad))..headers.addAll(_kopf))
          .timeout(const Duration(seconds: 60));
    } on SocketException catch (e) {
      throw KeineVerbindung(e);
    } on TimeoutException catch (e) {
      throw KeineVerbindung(e);
    } on http.ClientException catch (e) {
      throw KeineVerbindung(e);
    }
    if (r.statusCode != 200) {
      throw Serverfehler(r.statusCode, await r.stream.bytesToString());
    }
    await ziel.parent.create(recursive: true);
    final teil = File('${ziel.path}.teil');
    final aus = teil.openWrite();
    try {
      await r.stream.pipe(aus);
    } catch (e) {
      if (await teil.exists()) await teil.delete();
      throw KeineVerbindung(e);
    }
    await teil.rename(ziel.path);
  }

  void schliesse() => _http.close();
}
