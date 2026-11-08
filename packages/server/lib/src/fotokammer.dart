import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kern/berechne.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/import_service.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import 'bibliothek.dart';
import 'bibliotheken.dart';
import 'anmeldung_api.dart';

/// Die Fotokammer eines Kontos (#336): Fotos, die schon auf dem Server
/// liegen, aber noch nicht in der Bibliothek – bis man sie freigibt oder
/// verwirft.
///
/// **Wozu.** Von einer Speicherkarte kommen 55 Fotos eines Fussballspiels,
/// von denen zehn taugen. Gingen alle gleich in die Bibliothek, stünden die
/// 45 anderen in der Zeitleiste, in der Suche, auf der Karte und auf dem
/// Handy, bis man sie wieder loswird. In der Kammer sind sie schon gesichert
/// (die Karte darf danach gelöscht werden), aber nirgends sonst zu sehen.
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

  /// Alle vollständigen Einträge, nach Aufnahmedatum.
  Future<List<Map<String, Object?>>> liste() async {
    if (!await ordner.exists()) return [];
    final r = <Map<String, Object?>>[];
    await for (final e in ordner.list(followLinks: false)) {
      if (e is! Directory || !gueltig(p.basename(e.path))) continue;
      final f = File(p.join(e.path, 'angaben.json'));
      try {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) r.add(j.cast<String, Object?>());
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
    try {
      final datei = File(p.join(_platz(id).path, e['name']! as String));
      final ergebnis = await importiere(datei, {
        'name': e['name'],
        'geaendert': e['geaendert'],
      });
      final ausgang = ergebnis['ausgang'];
      if (ausgang == 'imported' || ausgang == 'duplicateSkipped') {
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
  /// die Oberfläche fragt vorher.
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
  Fotokammerapi(this.bibliotheken);
  final Bibliotheken bibliotheken;

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
