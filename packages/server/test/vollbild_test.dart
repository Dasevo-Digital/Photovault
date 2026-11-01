import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/vollbild.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Der Betrachter bekommt jedes Foto in voller Auflösung (#256).
///
/// Bis 3.49.9 zeigten Browser und Handy von HEIC, RAW und DNG nur die
/// Vorschau mit 2048 Punkten an der langen Seite.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late _Wandler wandler;
  late Handler api;
  late String token;
  late Bibliothek b;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_vollbild_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 5)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    wandler = _Wandler();
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      bildwerkzeuge: wandler,
      ruhe: const Duration(hours: 1),
    );
    api = baueApi(konten: konten, bibliotheken: bibliotheken);
    final erika = await konten.legeAn('erika', 'ein langes passwort');
    token = konten.meldeAn(erika.id, 'Telefon', 'x').token;
    b = (await bibliotheken.fuer(erika.id)).bibliothek;
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<Response> voll(String id) async => api(
    Request(
      'GET',
      Uri.parse('http://server/api/v1/aufnahmen/$id/voll'),
      headers: {'authorization': 'Bearer $token'},
    ),
  );

  Future<Uint8List> inhalt(Response r) async =>
      Uint8List.fromList(await r.read().expand((x) => x).toList());

  /// Legt eine Aufnahme mit Datei (und Vorschau) an, ohne den Import.
  Future<String> aufnahme(
    String id,
    String endung, {
    String typ = 'IMAGE',
    bool gesperrt = false,
  }) async {
    final relativ = 'originals/$id.$endung';
    final datei = b.pfade.absolute(relativ);
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(List.filled(100, id.codeUnitAt(0)));
    final vorschau = 'previews/$id.jpg';
    await b.pfade.absolute(vorschau).parent.create(recursive: true);
    await b.pfade.absolute(vorschau).writeAsBytes([1, 2, 3]);
    await b.db
        .into(b.db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.$endung',
            relativePath: relativ,
            checksum: 'c_$id',
            type: typ,
            fileCreatedAt: DateTime(2026, 10, 1),
            importedAt: DateTime(2026, 10, 1),
            previewRelativePath: Value(vorschau),
            isLocked: Value(gesperrt),
          ),
        );
    return id;
  }

  test('ein JPEG geht unverändert hinaus, ohne Wandlung', () async {
    await aufnahme('j', 'jpg');

    final r = await voll('j');

    expect(r.statusCode, 200);
    expect(r.headers['content-type'], 'image/jpeg');
    expect(await inhalt(r), List.filled(100, 'j'.codeUnitAt(0)));
    expect(wandler.auftraege, isEmpty);
  });

  test('ein HEIC kommt in voller Grösse gewandelt, einmal', () async {
    await aufnahme('h', 'heic');

    final r = await voll('h');

    expect(r.statusCode, 200);
    expect(r.headers['content-type'], 'image/jpeg');
    final bild = img.decodeJpg(await inhalt(r))!;
    expect(bild.width, 40);
    expect(wandler.auftraege, [null], reason: 'ohne Grössengrenze');

    // Wer zurückblättert, bekommt dieselbe Fassung.
    expect((await voll('h')).statusCode, 200);
    expect(wandler.auftraege, hasLength(1));

    // Ändert sich die Quelle, wird neu gewandelt.
    await b.pfade
        .absolute('originals/h.heic')
        .setLastModified(DateTime.now().add(const Duration(minutes: 1)));
    expect((await voll('h')).statusCode, 200);
    expect(wandler.auftraege, hasLength(2));
  });

  test('die entwickelte Fassung geht vor dem Original', () async {
    await aufnahme('e', 'dng');
    final entwickelt = b.pfade.absolute('developed/e.jpg');
    await entwickelt.parent.create(recursive: true);
    await entwickelt.writeAsBytes([9, 9, 9]);
    await (b.db.update(b.db.assets)..where((t) => t.id.equals('e'))).write(
      const AssetsCompanion(developedRelativePath: Value('developed/e.jpg')),
    );

    expect(await inhalt(await voll('e')), [9, 9, 9]);
    expect(wandler.auftraege, isEmpty);
  });

  test('Videos, gesperrte und unlesbare Fotos', () async {
    await aufnahme('v', 'mov', typ: 'VIDEO');
    await aufnahme('g', 'heic', gesperrt: true);
    await aufnahme('k', 'cr3');
    wandler.kaputt.add('k.cr3');

    expect((await voll('v')).statusCode, 404);
    expect((await voll('g')).statusCode, 404);
    expect((await voll('k')).statusCode, 422);
    expect((await voll('gibtesnicht')).statusCode, 404);
  });

  test('der Zwischenspeicher bleibt unter seiner Grenze', () async {
    final speicher = Directory('${ordner.path}/speicher');
    final vollbilder = Vollbilder(grenze: 250);
    final quellen = <File>[];
    for (final n in ['a', 'b', 'c']) {
      final q = File('${ordner.path}/$n.heic')..writeAsBytesSync([1]);
      quellen.add(q);
      final f = await vollbilder.bereit(
        speicher,
        n,
        q,
        () async => Uint8List(100),
      );
      // Die Reihenfolge des Alters soll eindeutig sein.
      await f!.setLastModified(DateTime(2026, 1, 1 + quellen.length));
      await q.setLastModified(DateTime(2026));
    }

    final uebrig = speicher.listSync().whereType<File>().toList();
    expect(uebrig, hasLength(2), reason: 'die älteste ging');
    expect(
      await Vollbilder.ziel(speicher, 'a', quellen[0].path).exists(),
      isFalse,
    );
  });
}

/// Wandelt jede Datei in ein JPEG mit 40 × 30 Punkten und merkt sich die
/// verlangte Grösse.
class _Wandler extends KeineBildwerkzeuge {
  final auftraege = <int?>[];
  final kaputt = <String>{};

  @override
  Future<Uint8List?> convertToJpegBytes(
    File file, {
    int? maxDimension = 2048,
    double quality = 0.9,
    bool objektivkorrektur = true,
  }) async {
    if (kaputt.contains(file.uri.pathSegments.last)) return null;
    auftraege.add(maxDimension);
    return Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 30)));
  }
}
