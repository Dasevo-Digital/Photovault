import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kern/db/database.dart';
import 'package:kern/berechne.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/asset_display_path.dart';
import 'package:kern/services/import_service.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import 'bibliothek.dart';
import 'bibliotheken.dart';
import 'anmeldung_api.dart';
import 'dateiantwort.dart';
import 'vollbild.dart';

/// Die Fotokammer eines Kontos (#336): Fotos, die schon auf dem Server
/// liegen, aber noch nicht in der Bibliothek – bis man sie freigibt oder
/// verwirft.
///
/// **Wozu.** Von einer Speicherkarte kommen 55 Fotos eines Fussballspiels,
/// von denen zehn taugen. Gingen alle gleich in die Bibliothek, stünden die
/// 45 anderen in der Zeitleiste, in der Suche, auf der Karte und auf dem
/// Handy, bis man sie wieder loswird. In der Kammer liegen sie schon auf dem
/// Server, aber nirgends sonst zu sehen. Die nächtliche Sicherung nimmt sie
/// trotzdem mit, in einem eigenen Ordner (`FotokammerSicherung`, #341).
///
/// **Warum neben der Bibliothek statt darin.** Eine Aufnahme in der
/// Bibliothek, die nur nicht erscheinen soll, bräuchte an jeder der über
/// hundert Stellen, die heute gesperrte Fotos ausblenden, eine zweite
/// Bedingung – und Handy, Browser und Rechner müssten sie alle kennen. Eine
/// vergessene Stelle zeigte genau die Fotos, die man noch nicht wollte.
/// Hier liegt nur die Datei mit zwei kleinen Bildern daneben; erst
/// „Freigeben“ führt sie durch denselben Import wie jeden Upload, samt
/// Regeln, Vorgaben und Auswertung.
///
/// Je Eintrag ein Ordner `fotokammer/<Kennung>/` mit der Datei unter ihrem
/// Namen, `miniatur.jpg`, `vorschau.jpg` und `angaben.json`. Die Angaben
/// werden zuletzt geschrieben: Ein Ordner ohne sie ist ein abgebrochener
/// Rest und zählt nicht.
class Fotokammer {
  Fotokammer(this.bibliothek)
    : ordner = Directory(p.join(bibliothek.ordner.path, 'fotokammer'));

  final Bibliothek bibliothek;
  final Directory ordner;

  /// Nimmt eine Datei in die Bibliothek auf wie jeden Upload – gesetzt von
  /// [Hochladen], dessen Import das ist. Die Datei liegt dabei allein in
  /// einem Ordner, unter ihrem Namen.
  late Future<Map<String, Object?>> Function(
    File datei,
    Map<String, Object?> angaben,
  )
  importiere;

  static final _kennungMuster = RegExp(r'^[0-9a-f-]{36}$');

  /// Kantenlänge der Vorschau: dieselbe wie in der Bibliothek.
  static const vorschauKante = 2048;

  final _inArbeit = <String>{};

  Directory _platz(String id) => Directory(p.join(ordner.path, id));
  File _angaben(String id) => File(p.join(_platz(id).path, 'angaben.json'));
  File miniatur(String id) => File(p.join(_platz(id).path, 'miniatur.jpg'));
  File vorschau(String id) => File(p.join(_platz(id).path, 'vorschau.jpg'));
  File _sichtung(String id) => File(p.join(_platz(id).path, 'sichtung.json'));

  static bool gueltig(String id) => _kennungMuster.hasMatch(id);

  /// Legt [datei] in die Kammer – vollständig angekommen, mit Namen und
  /// Änderungszeit. Was die Bibliothek oder die Kammer schon hat, kommt
  /// nicht noch einmal hinein; die Antwort gleicht dann der eines Imports
  /// (`duplicateSkipped`).
  Future<Map<String, Object?>> lege(File datei) async {
    final b = bibliothek;
    final ImportDateiangaben a;
    try {
      a = await b.importe.untersucheDatei(datei.path);
    } on Object catch (e) {
      return {'ausgang': 'failed', 'fehler': '$e'};
    }
    if (await b.kennungFuer(a.pruefsumme) case final schon?) {
      return {'ausgang': 'duplicateSkipped', 'aufnahme': schon};
    }
    for (final e in await liste()) {
      if (e['sha256'] == a.pruefsumme) {
        return {'ausgang': 'duplicateSkipped', 'kammer': e['id']};
      }
    }
    final id = const Uuid().v4();
    final platz = _platz(id);
    await platz.create(recursive: true);
    try {
      final ziel = await _verschiebe(
        datei,
        File(p.join(platz.path, p.basename(datei.path))),
      );
      final (breite, hoehe) = await _bilder(ziel, id, istBild: a.istBild);
      await _angaben(id).writeAsString(
        jsonEncode({
          'id': id,
          'name': p.basename(ziel.path),
          'groesse': a.bytes,
          'sha256': a.pruefsumme,
          'geaendert':
              (a.geaendert ?? await ziel.lastModified()).millisecondsSinceEpoch,
          'datum': a.datum.toUtc().toIso8601String(),
          'kamera': ?a.kamera,
          'modell': ?a.modell,
          'art': a.istBild ? 'IMAGE' : 'VIDEO',
          'breite': ?breite,
          'hoehe': ?hoehe,
          'angelegt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
      return {'ausgang': 'kammer', 'kammer': id};
    } on Object catch (e) {
      await platz.delete(recursive: true);
      return {'ausgang': 'failed', 'fehler': '$e'};
    }
  }

  /// Legt die Aufnahme [kennung] der Bibliothek zurück in die Kammer
  /// (#337) – etwa die 14 Fotos einer Karte, die schon hereinkamen, damit
  /// sie mit den übrigen gesichtet werden.
  ///
  /// **Warum über den Papierkorb.** Die Aufnahme verschwindet so sofort
  /// überall, auf jedem Gerät, ohne dass eine Abfrage etwas Neues lernen
  /// muss – und sie behält alles: Alben, Bewertungen, Personen,
  /// Bearbeitungen. „Freigeben“ holt sie aus dem Papierkorb zurück statt sie
  /// neu zu importieren. Leert sich der Papierkorb vorher, bleibt die Datei
  /// in der Kammer, und Freigeben importiert sie neu.
  ///
  /// Die Datei liegt als harter Link in der Kammer, wo das geht: kein
  /// zusätzlicher Platz, und sie überlebt das endgültige Löschen der
  /// Aufnahme.
  Future<Map<String, Object?>> ausDerBibliothek(String kennung) async {
    final b = bibliothek;
    final a = await b.db.assetById(kennung);
    if (a == null || a.isTrashed) {
      return {'aufnahme': kennung, 'ausgang': 'unbekannt'};
    }
    if (a.isLocked) return {'aufnahme': kennung, 'ausgang': 'gesperrt'};
    final quelle = b.pfade.absolute(a.relativePath);
    if (!await quelle.exists()) {
      return {
        'aufnahme': kennung,
        'ausgang': 'failed',
        'fehler': 'Original fehlt',
      };
    }
    // Schon einmal hierher gelegt (und der Papierkorb kam nicht mehr dazu)?
    String? id;
    for (final e in await liste()) {
      if (e['aufnahme'] == kennung) id = e['id'] as String?;
    }
    if (id == null) {
      id = const Uuid().v4();
      final platz = _platz(id);
      await platz.create(recursive: true);
      try {
        final name = p.basename(a.originalFileName);
        final ziel = File(p.join(platz.path, name.isEmpty ? 'foto' : name));
        await _verknuepfe(quelle, ziel);
        final (breite, hoehe) = await _bilderAus(a, ziel, id);
        await _angaben(id).writeAsString(
          jsonEncode({
            'id': id,
            'name': p.basename(ziel.path),
            'groesse': await ziel.length(),
            'sha256': a.checksum,
            'geaendert': (await ziel.lastModified()).millisecondsSinceEpoch,
            'datum': a.fileCreatedAt.toUtc().toIso8601String(),
            'kamera': ?a.cameraMake,
            'modell': ?a.cameraModel,
            'art': a.type == 'VIDEO' ? 'VIDEO' : 'IMAGE',
            'breite': ?breite,
            'hoehe': ?hoehe,
            'angelegt': DateTime.now().toUtc().toIso8601String(),
            // Woher es kam: Freigeben holt diese Aufnahme zurück.
            'aufnahme': kennung,
          }),
          flush: true,
        );
      } on Object catch (e) {
        await platz.delete(recursive: true);
        return {'aufnahme': kennung, 'ausgang': 'failed', 'fehler': '$e'};
      }
    }
    await b.db.fuehreAus(InDenPapierkorb([kennung]));
    return {'aufnahme': kennung, 'ausgang': 'kammer', 'kammer': id};
  }

  /// Ein harter Link, sonst eine Kopie; die Änderungszeit bleibt.
  static Future<void> _verknuepfe(File von, File nach) async {
    if (!Platform.isWindows) {
      try {
        final r = await Process.run('ln', [von.path, nach.path]);
        if (r.exitCode == 0) return;
      } on ProcessException {
        // Kein ln – dann kopieren.
      }
    }
    final zeit = await von.lastModified();
    await von.copy(nach.path);
    await nach.setLastModified(zeit);
  }

  /// Vorschau und Miniatur einer Aufnahme: die vorhandenen, wo es sie
  /// gibt, sonst neu aus der Datei.
  Future<(int?, int?)> _bilderAus(AssetData a, File datei, String id) async {
    final pf = bibliothek.pfade;
    final vorhanden = a.previewRelativePath;
    if (vorhanden == null || !await pf.absolute(vorhanden).exists()) {
      return _bilder(datei, id, istBild: a.type != 'VIDEO');
    }
    await pf.absolute(vorhanden).copy(vorschau(id).path);
    final klein = a.thumbnailRelativePath;
    if (klein != null && await pf.absolute(klein).exists()) {
      await pf.absolute(klein).copy(miniatur(id).path);
    } else {
      final m = await berechne(
        decodeAndResizeThumbnail,
        await vorschau(id).readAsBytes(),
      );
      if (m != null) await miniatur(id).writeAsBytes(m.jpegBytes, flush: true);
    }
    return (a.widthPx, a.heightPx);
  }

  /// Umbenennen, über Dateisysteme hinweg kopieren.
  static Future<File> _verschiebe(File von, File nach) async {
    try {
      return await von.rename(nach.path);
    } on FileSystemException {
      final zeit = await von.lastModified();
      final kopie = await von.copy(nach.path);
      await kopie.setLastModified(zeit);
      await von.delete();
      return kopie;
    }
  }

  /// Vorschau und Miniatur; gibt die Masse der Vorschau zurück. Ohne
  /// Wandler bleibt es bei der Datei – die Kammer zeigt dann ein Zeichen.
  Future<(int?, int?)> _bilder(
    File datei,
    String id, {
    required bool istBild,
  }) async {
    final w = bibliothek.bildwerkzeuge;
    Uint8List? gross;
    try {
      gross = istBild
          ? await w.convertToJpegBytes(datei, maxDimension: vorschauKante)
          : (await w.generateVideoThumbnail(
              datei,
              maxDimension: vorschauKante,
            ))?.jpegBytes;
    } on Object catch (e) {
      protokoll('Fotokammer: keine Vorschau für ${p.basename(datei.path)}: $e');
    }
    if (gross == null) return (null, null);
    await vorschau(id).writeAsBytes(gross, flush: true);
    final klein = await berechne(decodeAndResizeThumbnail, gross);
    if (klein == null) return (null, null);
    await miniatur(id).writeAsBytes(klein.jpegBytes, flush: true);
    return (klein.width, klein.height);
  }

  /// Sterne und Ablehnung von [id]; leer, solange niemand gesichtet hat.
  /// In einer eigenen Datei: Die Angaben ändern sich nie, darauf verlässt
  /// sich die Sicherung (#345).
  Future<Map<String, Object?>> _sichtungVon(String id) async {
    try {
      final j = jsonDecode(await _sichtung(id).readAsString());
      if (j is Map) return j.cast<String, Object?>();
    } on Object {
      // Noch nicht gesichtet.
    }
    return const {};
  }

  /// Merkt sich das Urteil über [id]. Was nicht angegeben ist, bleibt.
  Future<bool> sichte(String id, {int? sterne, bool? abgelehnt}) async {
    if (await eintrag(id) == null || _inArbeit.contains(id)) return false;
    final alt = await _sichtungVon(id);
    final teil = File('${_sichtung(id).path}.neu');
    await teil.writeAsString(
      jsonEncode({
        'sterne': sterne ?? alt['sterne'] ?? 0,
        'abgelehnt': abgelehnt ?? alt['abgelehnt'] ?? false,
      }),
      flush: true,
    );
    await teil.rename(_sichtung(id).path);
    return true;
  }

  /// Die Sterne aus der Sichtung gehen mit in die Bibliothek.
  Future<void> _uebertrageSterne(int? sterne, String? aufnahme) async {
    if (sterne == null || sterne <= 0 || aufnahme == null) return;
    await bibliothek.db.fuehreAus(BewertungSetzen([aufnahme], sterne));
  }

  /// Die Datei von [id], wenn es ein Foto ist.
  Future<File?> original(String id) async {
    final e = await eintrag(id);
    if (e == null || e['art'] != 'IMAGE') return null;
    final f = File(p.join(_platz(id).path, p.basename('${e['name']}')));
    return await f.exists() ? f : null;
  }

  /// Wo die gewandelte Fassung von [id] liegt: im Ordner des Eintrags, also
  /// fort, sobald der Eintrag fort ist. Ein Unterordner, denn [Vollbilder]
  /// räumt in seinem Ordner auf und darf dabei nie das Original treffen.
  Directory vollbildOrdner(String id) =>
      Directory(p.join(_platz(id).path, 'vollbild'));

  /// Alle vollständigen Einträge, nach Aufnahmedatum.
  Future<List<Map<String, Object?>>> liste() async {
    if (!await ordner.exists()) return [];
    final r = <Map<String, Object?>>[];
    await for (final e in ordner.list(followLinks: false)) {
      if (e is! Directory || !gueltig(p.basename(e.path))) continue;
      final f = File(p.join(e.path, 'angaben.json'));
      try {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) {
          r.add({
            ...j.cast<String, Object?>(),
            ...await _sichtungVon(p.basename(e.path)),
          });
        }
      } on Object {
        // Noch nicht fertig oder kaputt: kein Eintrag.
      }
    }
    r.sort(
      (x, y) =>
          '${x['datum']}${x['name']}'.compareTo('${y['datum']}${y['name']}'),
    );
    return r;
  }

  Future<Map<String, Object?>?> eintrag(String id) async {
    if (!gueltig(id)) return null;
    try {
      final j = jsonDecode(await _angaben(id).readAsString());
      return j is Map ? j.cast<String, Object?>() : null;
    } on Object {
      return null;
    }
  }

  /// Nimmt [id] in die Bibliothek auf. Danach ist der Eintrag fort – auch
  /// wenn die Bibliothek das Foto schon hatte. Scheitert der Import, bleibt
  /// er liegen.
  Future<Map<String, Object?>> freigeben(String id) async {
    final e = await eintrag(id);
    if (e == null || !_inArbeit.add(id)) {
      return {'id': id, 'ausgang': 'unbekannt'};
    }
    final sterne = (await _sichtungVon(id))['sterne'] as int?;
    try {
      // Kam es aus der Bibliothek (#337) und liegt es noch im Papierkorb,
      // kehrt es zurück – mit allem, was daran hing.
      if (e['aufnahme'] case final String kennung) {
        final a = await bibliothek.db.assetById(kennung);
        if (a != null) {
          if (a.isTrashed) {
            await bibliothek.db.fuehreAus(AusDemPapierkorb([kennung]));
          }
          await _uebertrageSterne(sterne, kennung);
          await _platz(id).delete(recursive: true);
          return {'id': id, 'ausgang': 'imported', 'aufnahme': kennung};
        }
      }
      final datei = File(p.join(_platz(id).path, e['name']! as String));
      final ergebnis = await importiere(datei, {
        'name': e['name'],
        'geaendert': e['geaendert'],
      });
      final ausgang = ergebnis['ausgang'];
      if (ausgang == 'imported' || ausgang == 'duplicateSkipped') {
        if (ausgang == 'imported') {
          await _uebertrageSterne(sterne, ergebnis['aufnahme'] as String?);
        }
        await _platz(id).delete(recursive: true);
      }
      return {'id': id, ...ergebnis};
    } on Object catch (x) {
      return {'id': id, 'ausgang': 'failed', 'fehler': '$x'};
    } finally {
      _inArbeit.remove(id);
    }
  }

  /// Löscht [id] samt Datei. Endgültig: Die Kammer hat keinen Papierkorb –
  /// die Oberfläche fragt vorher. Kam das Foto aus der Bibliothek, liegt die
  /// Aufnahme danach weiter im Papierkorb, bis der sich leert.
  Future<bool> verwerfen(String id) async {
    if (!gueltig(id) || _inArbeit.contains(id)) return false;
    final platz = _platz(id);
    if (!await platz.exists()) return false;
    await platz.delete(recursive: true);
    return true;
  }

  /// Reste abgebrochener Einträge (ohne Angaben) wegräumen.
  Future<int> raeumeAuf({Duration alter = const Duration(days: 1)}) async {
    if (!await ordner.exists()) return 0;
    var n = 0;
    final grenze = DateTime.now().subtract(alter);
    await for (final e in ordner.list(followLinks: false)) {
      if (e is! Directory) continue;
      if (await File(p.join(e.path, 'angaben.json')).exists()) continue;
      if ((await e.stat()).modified.isAfter(grenze)) continue;
      await e.delete(recursive: true);
      n++;
    }
    return n;
  }
}

/// Die Fotokammer über HTTP: `GET /api/v1/kammer`, die Bilder je Eintrag,
/// `POST /api/v1/kammer/freigeben` und `…/verwerfen` mit `{ids}`.
class Fotokammerapi {
  Fotokammerapi(this.bibliotheken, this.vollbilder);
  final Bibliotheken bibliotheken;

  /// Dieselben wie für die Bibliothek: immer nur eine Wandlung auf einmal.
  final Vollbilder vollbilder;

  Future<Fotokammer> _kammer(Request r) async =>
      (await bibliotheken.fuer(kontoVon(r).id)).kammer;

  /// → `{eintraege: [...], anzahl, bytes}`.
  Future<Response> liste(Request r) async {
    final l = await (await _kammer(r)).liste();
    return _json({
      'eintraege': [
        for (final e in l) {...e}..remove('sha256'),
      ],
      'anzahl': l.length,
      'bytes': l.fold<int>(0, (n, e) => n + ((e['groesse'] as int?) ?? 0)),
    });
  }

  Future<Response> miniatur(Request r, String id) async =>
      _bild((await _kammer(r)), id, klein: true);

  Future<Response> vorschau(Request r, String id) async =>
      _bild((await _kammer(r)), id, klein: false);

  /// Das Foto in voller Auflösung (#342): In der Vorschau lässt sich die
  /// Schärfe eines 24-MP-Fotos nicht beurteilen, und genau darum geht es
  /// in der Kammer. `422`, wenn es sich nicht wandeln lässt.
  Future<Response> vollbild(Request r, String id) async {
    final k = await _kammer(r);
    final quelle = await k.original(id);
    if (quelle == null) return Response.notFound(null);
    if (istDirektAnzeigbar(quelle.path)) return dateiAntwort(r, quelle);
    final fertig = await vollbilder.bereit(
      k.vollbildOrdner(id),
      id,
      quelle,
      () => k.bibliothek.bildwerkzeuge.convertToJpegBytes(
        quelle,
        maxDimension: null,
      ),
    );
    if (fertig == null) {
      return _json({'fehler': 'nicht umwandelbar'}, status: 422);
    }
    return dateiAntwort(r, fertig);
  }

  Future<Response> _bild(Fotokammer k, String id, {required bool klein}) async {
    if (!Fotokammer.gueltig(id)) return Response.notFound(null);
    final f = klein ? k.miniatur(id) : k.vorschau(id);
    if (!await f.exists()) return Response.notFound(null);
    return Response.ok(
      f.openRead(),
      headers: {
        'content-type': 'image/jpeg',
        'content-length': '${await f.length()}',
        // Der Inhalt zu einer Kennung ändert sich nie.
        'cache-control': 'private, max-age=86400',
      },
    );
  }

  /// `{ids}` → `{ergebnisse: [{id, ausgang, aufnahme?, fehler?}]}`. Der
  /// Import dauert je Foto einige Sekunden – Clients schicken wenige auf
  /// einmal.
  Future<Response> freigeben(Request r) async {
    final ids = await _ids(r);
    if (ids == null) return _json({'fehler': 'ids fehlt'}, status: 400);
    final k = await _kammer(r);
    final ergebnisse = <Map<String, Object?>>[];
    for (final id in ids) {
      ergebnisse.add(await k.freigeben(id));
    }
    return _json({'ergebnisse': ergebnisse});
  }

  /// `{ids}` mit Kennungen der Bibliothek → `{ergebnisse: [{aufnahme,
  /// ausgang, kammer?, fehler?}]}`; `ausgang` ist `kammer`, `unbekannt`
  /// (nicht in dieser Bibliothek oder schon im Papierkorb), `gesperrt`
  /// oder `failed` (#337).
  Future<Response> aufnehmen(Request r) async {
    final ids = await _ids(r);
    if (ids == null) return _json({'fehler': 'ids fehlt'}, status: 400);
    final k = await _kammer(r);
    final ergebnisse = <Map<String, Object?>>[];
    for (final id in ids) {
      ergebnisse.add(await k.ausDerBibliothek(id));
    }
    return _json({'ergebnisse': ergebnisse});
  }

  /// `{ids, sterne?, abgelehnt?}` → `{geaendert}`: das Urteil beim Sichten
  /// (#345).
  Future<Response> sichten(Request r) async {
    final Object? k;
    try {
      k = jsonDecode(await r.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    if (k is! Map || k['ids'] is! List) {
      return _json({'fehler': 'ids fehlt'}, status: 400);
    }
    final ids = (k['ids'] as List).whereType<String>().toList();
    final sterne = k['sterne'], abgelehnt = k['abgelehnt'];
    if (ids.length > 500 ||
        (sterne != null && (sterne is! int || sterne < 0 || sterne > 5)) ||
        (abgelehnt != null && abgelehnt is! bool)) {
      return _json({'fehler': 'ungültig'}, status: 400);
    }
    final kammer = await _kammer(r);
    var n = 0;
    for (final id in ids) {
      if (await kammer.sichte(
        id,
        sterne: sterne as int?,
        abgelehnt: abgelehnt as bool?,
      )) {
        n++;
      }
    }
    return _json({'geaendert': n});
  }

  /// `{ids}` → `{verworfen}`.
  Future<Response> verwerfen(Request r) async {
    final ids = await _ids(r);
    if (ids == null) return _json({'fehler': 'ids fehlt'}, status: 400);
    final k = await _kammer(r);
    var n = 0;
    for (final id in ids) {
      if (await k.verwerfen(id)) n++;
    }
    return _json({'verworfen': n});
  }

  static Future<List<String>?> _ids(Request r) async {
    try {
      final k = jsonDecode(await r.readAsString());
      if (k is! Map || k['ids'] is! List) return null;
      final ids = (k['ids'] as List).whereType<String>().toList();
      return ids.length > 500 ? null : ids;
    } on FormatException {
      return null;
    }
  }
}

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {'content-type': 'application/json; charset=utf-8'},
);
