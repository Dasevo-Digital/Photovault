import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kern/db/database.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/bearbeitung_speichern.dart';
import 'package:kern/services/import_service.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import 'bibliothek.dart';
import 'package:kern/services/import_plan.dart';

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
///
/// `bearbeitungVon` (die SHA-256 eines Originals) kennzeichnet eine in der
/// Fotos-App des Telefons bearbeitete Fassung (#271): Sie wird nicht als
/// eigene Aufnahme aufgenommen, sondern über das Original gelegt – siehe
/// [_bearbeitung].
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

  /// Uploads, deren Datei gerade importiert wird: Die `.teil`-Datei ist dann
  /// schon fort, das Ergebnis noch nicht da.
  final _importierend = <String>{};

  /// Ein Upload, der angekommen ist und nie ein Ergebnis bekommen wird: Der
  /// Server fiel beim Import aus, oder der warf. Bis 3.58 meldete er sich
  /// als vollständig, und das Telefon wartete bei jedem Lauf vergeblich
  /// darauf, ohne je zu den Fotos dahinter zu kommen.
  Future<bool> _verwaist(String id, Map<String, Object?> a) async =>
      a['ergebnis'] == null &&
      !_importierend.contains(id) &&
      !await _teil(id).exists();

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
    for (final schluessel in ['sha256', 'bearbeitungVon']) {
      if (meta[schluessel] != null &&
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(meta[schluessel]!)) {
        return Response(400, body: schluessel, headers: _tus);
      }
    }
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
    // Was der Import nicht kennt, braucht nicht erst anzukommen: Fünf
    // PSD-Dateien einer Kamerarolle gingen dreimal vollständig hoch, nur
    // um jedes Mal abgelehnt zu werden. (Der Umzug trägt eigene Dateien.)
    if (abschluss == null && !unterstuetztesFormat(name)) {
      return Response(
        415,
        body: 'Format nicht unterstützt: ${p.extension(name)}',
        headers: _tus,
      );
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
      'bearbeitungVon': ?meta['bearbeitungVon'],
      'art': ?meta['art'],
      'regelstand': ?meta['regelstand'],
      'angelegt': DateTime.now().toUtc().toIso8601String(),
    });
    return Response(
      201,
      headers: {..._tus, 'location': '$pfad/$id', 'upload-offset': '0'},
    );
  }

  /// Eine ganze Datei in einer einzigen Anfrage (`PUT /api/v1/sofort`, #308):
  /// Der Körper ist die Datei, `?name=` ihr Name, `?geaendert=` ihre
  /// Aufnahmezeit in Millisekunden.
  ///
  /// So kommen Fotos an, wenn die Handy-App nicht läuft: Unter iOS gibt die
  /// Erweiterung `Sofortsicherung` nur einen Auftrag auf, und das System
  /// schickt die Datei selbst, wann es ihm passt und in einem Stück – tus
  /// beherrscht es nicht. Reisst die Verbindung ab, bleibt hier nichts
  /// liegen: Das System versucht es erneut, und sonst holt die App das
  /// Foto beim nächsten Lauf nach.
  ///
  /// → 201 `{ausgang, aufnahme}`, auch für eine Dublette: Das Foto ist
  /// dann ja auf dem Server. 422, wenn der Import scheitert.
  Future<Response> inEinemStueck(Request anfrage) async {
    final q = anfrage.url.queryParameters;
    final name = p.basename(q['name'] ?? '');
    if (name.isEmpty || name == '.' || name == '..') {
      return _antwort(400, {'fehler': 'Dateiname fehlt'});
    }
    if (!unterstuetztesFormat(name)) {
      return _antwort(415, {
        'fehler': 'Format nicht unterstützt: ${p.extension(name)}',
      });
    }
    final laenge = anfrage.contentLength;
    if (laenge != null && laenge > hoechstens) {
      return _antwort(413, {'fehler': 'Datei zu gross'});
    }
    final id = const Uuid().v4();
    final angaben = <String, Object?>{
      'laenge': laenge,
      'name': name,
      'geaendert': int.tryParse(q['geaendert'] ?? ''),
      'angelegt': DateTime.now().toUtc().toIso8601String(),
    };
    await eingang.create(recursive: true);
    // Die Angaben zuerst: Nach einem Absturz findet [raeumeAuf] den Rest
    // nur über sie.
    await _schreib(id, angaben);
    try {
      var geschrieben = 0;
      final senke = _teil(id).openWrite();
      try {
        // addStream statt add: Es wartet auf die Platte. Sonst landet bei
        // schnellem Netz und langsamem Speicher die ganze Datei im
        // Arbeitsspeicher.
        await senke.addStream(
          anfrage.read().takeWhile((stueck) {
            geschrieben += stueck.length;
            return geschrieben <= hoechstens;
          }),
        );
      } finally {
        await senke.close();
      }
      if (geschrieben > hoechstens) {
        return _antwort(413, {'fehler': 'Datei zu gross'});
      }
      if (geschrieben == 0 || (laenge != null && geschrieben != laenge)) {
        return _antwort(400, {'fehler': 'unvollständig'});
      }
      final ergebnis = await _importiere(id, angaben);
      // Wann das Telefon liefert, bestimmt das System; ohne diese Spur liesse
      // sich auf dem Server nicht sehen, ob überhaupt etwas ankommt.
      protokoll('Sofortsicherung: ${ergebnis['ausgang']}');
      if (ergebnis['ausgang'] == 'failed') {
        return _antwort(422, {'fehler': ergebnis['fehler']});
      }
      return _antwort(201, {
        'ausgang': ergebnis['ausgang'],
        'aufnahme': ergebnis['aufnahme'],
      });
    } finally {
      await _loesche(id);
    }
  }

  static Response _antwort(int status, Map<String, Object?> inhalt) => Response(
    status,
    body: jsonEncode(inhalt),
    headers: {'content-type': 'application/json'},
  );

  /// Wie viel von [id] angekommen ist. Nach dem letzten Stück legt
  /// [_importiere] die Datei unter ihrem Namen in einen eigenen Ordner, und
  /// bis das Ergebnis dasteht, gibt es die `.teil`-Datei nicht mehr. Bis
  /// 3.53 warf das jede Abfrage in dieser Zeit als 500 (#262) – ein HEAD
  /// vom Telefon während des Imports einer grossen DNG. Angekommen ist in
  /// dem Moment alles.
  Future<int> _erhalten(String id, Map<String, Object?> a) async {
    final laenge = a['laenge']! as int;
    if (a['ergebnis'] != null) return laenge;
    try {
      return await _teil(id).length();
    } on PathNotFoundException {
      return laenge;
    }
  }

  Future<Response> stand(Request anfrage, String id) async {
    final a = await _lies(id);
    if (a == null) return Response.notFound(null, headers: _tus);
    if (await _verwaist(id, a)) {
      await _loesche(id);
      return Response.notFound(null, headers: _tus);
    }
    final versatz = await _erhalten(id, a);
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
    if (await _verwaist(id, a)) {
      await _loesche(id);
      return Response.notFound(null);
    }
    return Response.ok(
      jsonEncode({
        'id': id,
        'name': a['name'],
        'laenge': a['laenge'],
        'erhalten': await _erhalten(id, a),
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
    if (await _verwaist(id, a)) {
      await _loesche(id);
      return Response.notFound(null, headers: _tus);
    }
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
    final Map<String, Object?> ergebnis;
    _importierend.add(id);
    try {
      ergebnis = fertig == null
          ? await _importiere(id, a)
          : await fertig(_teil(id), a);
      await _schreib(id, {...a, 'ergebnis': ergebnis});
    } finally {
      _importierend.remove(id);
    }
    return Response(
      204,
      headers: {
        ...kopf,
        'pv-ausgang': ergebnis['ausgang']! as String,
        if (ergebnis['aufnahme'] != null)
          'pv-aufnahme': ergebnis['aufnahme']! as String,
        // Warum nicht – sonst sah der Rechner nur „failed“ (#335).
        // Kodiert, weil eine Kopfzeile nur ASCII tragen darf.
        if (ergebnis['fehler'] case final String fehler)
          'pv-fehler': Uri.encodeComponent(fehler),
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
      if (a['bearbeitungVon'] case final String von) {
        final r = await _bearbeitung(b, datei, von);
        if (r != null) {
          nachImport?.call();
          return r;
        }
        // Kein Original dazu: wie jede andere Datei aufnehmen.
      }
      if (a['regelstand'] != null &&
          a['regelstand'] !=
              await ImportPlanDienst(b.db, b.importe).aktuellerRegelstand()) {
        return {'ausgang': 'failed', 'fehler': 'pv_import_regeln_geaendert'};
      }
      final dienst = ImportPlanDienst(b.db, b.importe);
      final plan = a['regelstand'] == null
          ? null
          : await dienst.erstelle([datei.path]);
      if (plan != null && plan.regelstand != a['regelstand']) {
        return {'ausgang': 'failed', 'fehler': 'pv_import_regeln_geaendert'};
      }
      final eintrag = plan?.eintraege.single;
      final r = await b.importe.importFile(
        datei.path,
        erwartetePruefsumme: a['sha256'] as String?,
        erwarteteAngaben: eintrag?.angaben,
        beiEintrag: plan == null
            ? null
            : (id) => dienst.uebernehme(plan, eintrag!, id),
      );
      var aufnahme = r.assetId;
      if (r.outcome == ImportOutcome.imported && aufnahme != null) {
        // Wie in der App: Scheitert die Nachbearbeitung, ist die Datei
        // trotzdem aufgenommen – das darf dem Client nicht als Fehler
        // erscheinen, sonst lädt er sie noch einmal hoch.
        try {
          await b.nachbearbeitung.neueAufnahme(
            aufnahme,
            regelnAnwenden: plan == null,
          );
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

  /// Legt eine in der Fotos-App des Telefons bearbeitete Fassung über ihr
  /// Original (#271), wie eine Bearbeitung am Rechner (siehe
  /// [speichereBearbeitung]): Die Aufnahme behält Kennung, Alben,
  /// Schlagwörter, Personen und Sterne und zeigt danach die Bearbeitung;
  /// das bisherige Original liegt als Variante dahinter.
  ///
  /// Bis 3.50.3 sicherte das Telefon nur das Original – jede Bearbeitung
  /// aus der Fotos-App fehlte in Photo Vault.
  ///
  /// [vonSumme] ist die Prüfsumme des Originals. Wurde das Foto schon
  /// einmal bearbeitet, liegt das Original als Variante hinter der ersten
  /// Bearbeitung; die neue gehört dann auf die Hauptversion, und die erste
  /// rückt ebenfalls als Variante dahinter. `null`, wenn es kein passendes
  /// Original gibt oder die Datei kein JPEG ist – dann wird sie gewöhnlich
  /// aufgenommen.
  Future<Map<String, Object?>?> _bearbeitung(
    Bibliothek b,
    File datei,
    String vonSumme,
  ) async {
    final bytes = await datei.readAsBytes();
    // Das Telefon liefert die Bearbeitung als JPEG (photo_manager rendert
    // sie so); speichereBearbeitung legt sie als .jpg ab.
    if (bytes.length < 3 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    final summe = sha256.convert(bytes).toString();
    final schon = await b.kennungFuer(summe);
    if (schon != null) {
      return {'ausgang': 'duplicateSkipped', 'aufnahme': schon};
    }
    final kennung = await b.kennungFuer(vonSumme);
    if (kennung == null) return null;
    var ziel = await b.db.assetById(kennung);
    final stapel = ziel?.stackId;
    if (ziel != null &&
        stapel != null &&
        istVariantenstapel(stapel) &&
        !ziel.isStackCover) {
      for (final m in await b.db.assetsInStack(stapel)) {
        if (m.isStackCover) ziel = m;
      }
    }
    if (ziel == null ||
        ziel.type != 'IMAGE' ||
        ziel.isLocked ||
        ziel.isTrashed) {
      return null;
    }
    await speichereBearbeitung(
      db: b.db,
      paths: b.pfade,
      asset: ziel,
      jpeg: bytes,
      importe: b.importe,
    );
    protokoll('Bearbeitung vom Telefon über ${ziel.originalFileName} gelegt');
    return {'ausgang': 'imported', 'aufnahme': ziel.id};
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
      // Der Ordner eines Imports, den ein Neustart abgebrochen hat.
      if (e is Directory) {
        final id = p.basename(e.path);
        if (_kennungMuster.hasMatch(id) && !_importierend.contains(id)) {
          await e.delete(recursive: true);
          weg++;
        }
        continue;
      }
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
