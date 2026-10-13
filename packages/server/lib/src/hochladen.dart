import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/import_service.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import 'bibliothek.dart';

/// Hochladen in Stücken, die sich nach einem Abbruch fortsetzen lassen –
/// nach dem tus-Protokoll 1.0.0 (Kern und „creation“, „termination“).
///
/// In Stücken, weil Reverse Proxys die Grösse einer Anfrage begrenzen
/// (nginx ohne eigene Einstellung auf 1 MB) und Videos mehrere Gigabyte
/// haben. Nach tus, weil es dafür fertige Clients gibt und das Protokoll
/// genau das festlegt, was hier nötig ist: anlegen, Stand abfragen, an der
/// richtigen Stelle weiterschreiben.
///
/// Ist die letzte Stelle angekommen, geht die Datei durch denselben Import
/// und dieselbe Nachbearbeitung wie in der App (Live Photos, Vorgaben,
/// Regeln, Ortsnamen); danach meldet [nachImport], dass die Auswertung
/// fällig ist. Die Antwort trägt dann `Pv-Ausgang` (`imported`,
/// `duplicateSkipped`, `failed`) und `Pv-Aufnahme` (die Kennung, auch bei
/// einer Dublette).
///
/// Zu den Metadaten (`Upload-Metadata`) gehören `filename` und, von uns
/// dazu, `geaendert` – die Änderungszeit der Datei in Millisekunden. Fehlen
/// Aufnahmedaten in der Datei, ist das der letzte Anhalt für ihr Datum;
/// ohne sie wäre es der Zeitpunkt des Hochladens.
class Hochladen {
  Hochladen(
    this.eingang,
    this.bibliothek, {
    this.hoechstens = 64 * 1024 * 1024 * 1024,
    this.nachImport,
    this.pfad = '/api/v1/hochladen',
    this.abschluss,
  });

  final Directory eingang;

  /// Wohin importiert wird; nur ohne [abschluss] gebraucht.
  final Bibliothek? bibliothek;

  /// Unter welchem Pfad die Uploads liegen (`Location`).
  final String pfad;

  /// Was mit einer vollständigen Datei geschieht, statt sie zu importieren
  /// (der Umzug legt sie an ihren Pfad). Gibt zurück, was in der Antwort
  /// steht: `ausgang` und gegebenenfalls `fehler`. Mit [abschluss] braucht
  /// ein Upload statt eines Dateinamens den Pfad (`pfad`) in den
  /// Metadaten.
  final Future<Map<String, Object?>> Function(
    File datei,
    Map<String, Object?> angaben,
  )?
  abschluss;

  /// Grösste Datei, die angenommen wird.
  final int hoechstens;

  /// Nach jeder neu aufgenommenen Datei.
  final void Function()? nachImport;

  static const _fassung = '1.0.0';
  static final _kennungMuster = RegExp(r'^[0-9a-f-]{36}$');

  /// Je Upload eine Warteschlange: Zwei Stücke derselben Datei gleichzeitig
  /// würden durcheinander geschrieben.
  final _laeufe = <String, Future<void>>{};

  Map<String, String> get _tus => const {'tus-resumable': _fassung};

  File _teil(String id) => File(p.join(eingang.path, '$id.teil'));
  File _angaben(String id) => File(p.join(eingang.path, '$id.json'));

  Future<Map<String, Object?>?> _lies(String id) async {
    if (!_kennungMuster.hasMatch(id)) return null;
    final f = _angaben(id);
    if (!await f.exists()) return null;
    return (jsonDecode(await f.readAsString()) as Map).cast<String, Object?>();
  }

  Future<void> _schreib(String id, Map<String, Object?> angaben) =>
      _angaben(id).writeAsString(jsonEncode(angaben), flush: true);

  Response optionen(Request anfrage) => Response(
    204,
    headers: {
      ..._tus,
      'tus-version': _fassung,
      'tus-extension': 'creation,termination',
      'tus-max-size': '$hoechstens',
    },
  );

  Future<Response> anlegen(Request anfrage) async {
    if (anfrage.headers['tus-resumable'] != _fassung) {
      return Response(412, headers: {'tus-version': _fassung});
    }
    final laenge = int.tryParse(anfrage.headers['upload-length'] ?? '');
    if (laenge == null || laenge < 0) {
      return Response(400, body: 'Upload-Length fehlt', headers: _tus);
    }
    if (laenge > hoechstens) return Response(413, headers: _tus);
    final meta = _metadaten(anfrage.headers['upload-metadata']);
    final zielpfad = meta['pfad'];
    if (abschluss != null &&
        (zielpfad == null ||
            zielpfad.isEmpty ||
            p.isAbsolute(zielpfad) ||
            p.split(zielpfad).any((t) => t == '..' || t == '.'))) {
      return Response(400, body: 'pfad fehlt oder taugt nicht', headers: _tus);
    }
    final name = p.basename(zielpfad ?? meta['filename'] ?? meta['name'] ?? '');
    if (name.isEmpty || name == '.' || name == '..') {
      return Response(400, body: 'Dateiname fehlt', headers: _tus);
    }
    final id = const Uuid().v4();
    await eingang.create(recursive: true);
    await _teil(id).writeAsBytes(const [], flush: true);
    await _schreib(id, {
      'laenge': laenge,
      'name': name,
      'geaendert': int.tryParse(meta['geaendert'] ?? ''),
      'pfad': ?zielpfad,
      'sha256': ?meta['sha256'],
      'art': ?meta['art'],
      'angelegt': DateTime.now().toUtc().toIso8601String(),
    });
    return Response(
      201,
      headers: {..._tus, 'location': '$pfad/$id', 'upload-offset': '0'},
    );
  }

  Future<Response> stand(Request anfrage, String id) async {
    final a = await _lies(id);
    if (a == null) return Response.notFound(null, headers: _tus);
    final versatz = a['ergebnis'] != null
        ? a['laenge']! as int
        : await _teil(id).length();
    return Response.ok(
      null,
      headers: {
        ..._tus,
        'upload-offset': '$versatz',
        'upload-length': '${a['laenge']}',
        'cache-control': 'no-store',
      },
    );
  }

  /// Der Stand als JSON, samt Ergebnis des Imports.
  Future<Response> status(Request anfrage, String id) async {
    final a = await _lies(id);
    if (a == null) return Response.notFound(null);
    return Response.ok(
      jsonEncode({
        'id': id,
        'name': a['name'],
        'laenge': a['laenge'],
        'erhalten': a['ergebnis'] != null
            ? a['laenge']
            : await _teil(id).length(),
        'ergebnis': a['ergebnis'],
      }),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> anhaengen(Request anfrage, String id) {
    final vorher = _laeufe[id] ?? Future<void>.value();
    final fertig = Completer<void>();
    _laeufe[id] = fertig.future;
    return vorher.then((_) => _anhaengen(anfrage, id)).whenComplete(() {
      fertig.complete();
      if (identical(_laeufe[id], fertig.future)) _laeufe.remove(id);
    });
  }

  Future<Response> _anhaengen(Request anfrage, String id) async {
    if (anfrage.headers['tus-resumable'] != _fassung) {
      return Response(412, headers: {'tus-version': _fassung});
    }
    if (anfrage.headers['content-type'] != 'application/offset+octet-stream') {
      return Response(415, headers: _tus);
    }
    final a = await _lies(id);
    if (a == null) return Response.notFound(null, headers: _tus);
    if (a['ergebnis'] != null) return Response(409, headers: _tus);
    final laenge = a['laenge']! as int;
    final teil = _teil(id);
    final ist = await teil.length();
    if (int.tryParse(anfrage.headers['upload-offset'] ?? '') != ist) {
      return Response(409, headers: {..._tus, 'upload-offset': '$ist'});
    }

    final ziel = teil.openWrite(mode: FileMode.append);
    var geschrieben = 0;
    var zuViel = false;
    try {
      await for (final stueck in anfrage.read()) {
        final platz = laenge - ist - geschrieben;
        if (stueck.length > platz) {
          ziel.add(stueck.sublist(0, platz));
          geschrieben += platz;
          zuViel = true;
          break;
        }
        ziel.add(stueck);
        geschrieben += stueck.length;
      }
    } finally {
      await ziel.flush();
      await ziel.close();
    }
    final versatz = ist + geschrieben;
    if (zuViel) {
      return Response(413, headers: {..._tus, 'upload-offset': '$versatz'});
    }
    final kopf = {..._tus, 'upload-offset': '$versatz'};
    if (versatz < laenge) return Response(204, headers: kopf);

    final fertig = abschluss;
    final ergebnis = fertig == null
        ? await _importiere(id, a)
        : await fertig(_teil(id), a);
    await _schreib(id, {...a, 'ergebnis': ergebnis});
    return Response(
      204,
      headers: {
        ...kopf,
        'pv-ausgang': ergebnis['ausgang']! as String,
        if (ergebnis['aufnahme'] != null)
          'pv-aufnahme': ergebnis['aufnahme']! as String,
      },
    );
  }

  /// Die vollständige Datei unter ihrem Namen in einen eigenen Ordner
  /// legen – der Import nimmt den Namen aus dem Pfad – und importieren.
  Future<Map<String, Object?>> _importiere(
    String id,
    Map<String, Object?> a,
  ) async {
    final ordner = Directory(p.join(eingang.path, id));
    await ordner.create();
    final datei = await _teil(
      id,
    ).rename(p.join(ordner.path, a['name']! as String));
    try {
      final geaendert = a['geaendert'] as int?;
      if (geaendert != null) {
        await datei.setLastModified(
          DateTime.fromMillisecondsSinceEpoch(geaendert),
        );
      }
      final b = bibliothek!;
      final r = await b.importe.importFile(datei.path);
      var aufnahme = r.assetId;
      if (r.outcome == ImportOutcome.imported && aufnahme != null) {
        // Wie in der App: Scheitert die Nachbearbeitung, ist die Datei
        // trotzdem aufgenommen – das darf dem Client nicht als Fehler
        // erscheinen, sonst lädt er sie noch einmal hoch.
        try {
          await b.nachbearbeitung.neueAufnahme(aufnahme);
        } catch (e) {
          protokoll('Nachbearbeitung von ${a['name']} gescheitert: $e');
        }
        nachImport?.call();
      }
      if (r.outcome == ImportOutcome.duplicateSkipped) {
        final summe = await sha256.bind(datei.openRead()).first;
        aufnahme = await b.kennungFuer(summe.toString());
      }
      if (r.outcome == ImportOutcome.failed) {
        protokoll('Import von ${a['name']} gescheitert: ${r.error}');
      }
      return {
        'ausgang': r.outcome.name,
        'aufnahme': aufnahme,
        'fehler': r.error,
      };
    } finally {
      await ordner.delete(recursive: true);
    }
  }

  Future<Response> verwerfen(Request anfrage, String id) async {
    final a = await _lies(id);
    if (a == null) return Response.notFound(null, headers: _tus);
    await _loesche(id);
    return Response(204, headers: _tus);
  }

  Future<void> _loesche(String id) async {
    for (final f in [_teil(id), _angaben(id)]) {
      if (await f.exists()) await f.delete();
    }
  }

  /// Räumt Uploads weg, die seit [alter] nicht weitergingen, und Angaben
  /// zu fertigen, die so lange niemand abgefragt hat.
  ///
  /// Zählt die letzte Änderung an Angaben **oder** Teil: Die Angaben
  /// schreibt nur das Anlegen und der Abschluss. Eine Sicherung, die ein
  /// grosses Video über Tage in Hintergrundläufen fortsetzt, wäre sonst
  /// eine Woche nach dem Anlegen mitten im Hochladen verworfen worden.
  Future<int> raeumeAuf({Duration alter = const Duration(days: 7)}) async {
    if (!await eingang.exists()) return 0;
    var weg = 0;
    final grenze = DateTime.now().subtract(alter);
    await for (final e in eingang.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final id = p.basenameWithoutExtension(e.path);
      if ((await e.lastModified()).isAfter(grenze)) continue;
      final teil = _teil(id);
      if (await teil.exists() && (await teil.lastModified()).isAfter(grenze)) {
        continue;
      }
      await _loesche(id);
      weg++;
    }
    return weg;
  }

  /// `Upload-Metadata`: Paare aus Schlüssel und Base64-Wert, durch Kommas
  /// getrennt.
  static Map<String, String> _metadaten(String? kopf) {
    final aus = <String, String>{};
    for (final paar in (kopf ?? '').split(',')) {
      final teile = paar.trim().split(' ');
      if (teile.isEmpty || teile.first.isEmpty) continue;
      try {
        aus[teile.first] = teile.length > 1
            ? utf8.decode(base64.decode(teile[1]))
            : '';
      } on FormatException {
        // Ein unlesbarer Wert ist kein Grund, den Upload abzulehnen –
        // fehlt dadurch der Name, sagt das die Prüfung danach.
      }
    }
    return aus;
  }
}
