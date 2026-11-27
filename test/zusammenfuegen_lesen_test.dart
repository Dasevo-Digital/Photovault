import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/zusammenfuegen/raster.dart';
import 'package:kern/services/zusammenfuegen/zusammenfuegen.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/zusammenfuegen_dienst.dart';
import 'package:photo_vault/state/library_state.dart';

/// Was das Isolat des Zusammenfügens (#498) überhaupt liest: Der Kopf
/// einer Datei entscheidet, bevor Speicher für ihre Punkte angelegt wird.
void main() {
  /// Ein PNG, das nur aus seinem Kopf besteht: [ihdr] Abschnitte mit
  /// [breite] × [hoehe], Farbart [farbe] und [tiefe] Bit, dazu ein leeres
  /// IDAT. Die Prüfsummen stimmen nicht – bis zu ihnen darf es gar nicht
  /// kommen.
  Uint8List pngKopf(
    int breite,
    int hoehe, {
    int farbe = 6,
    int tiefe = 16,
    int ihdr = 1,
  }) {
    final b = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
    void abschnitt(String typ, List<int> daten) {
      b
        ..add([
          daten.length >> 24,
          daten.length >> 16 & 255,
          daten.length >> 8 & 255,
          daten.length & 255,
        ])
        ..add(typ.codeUnits)
        ..add(daten)
        ..add([0, 0, 0, 0]);
    }

    List<int> be32(int v) => [
      v >> 24 & 255,
      v >> 16 & 255,
      v >> 8 & 255,
      v & 255,
    ];
    for (var i = 0; i < ihdr; i++) {
      abschnitt('IHDR', [
        ...be32(breite),
        ...be32(hoehe),
        tiefe,
        farbe,
        0,
        0,
        0,
      ]);
    }
    abschnitt('IDAT', [120, 156, 3, 0, 0, 0, 0, 1]);
    abschnitt('IEND', []);
    return b.toBytes();
  }

  /// Ein echtes kleines JPEG, dessen SOF-Abschnitt [breite] × [hoehe]
  /// behauptet.
  Uint8List jpegMitMassen(int breite, int hoehe) {
    final bytes = img.encodeJpg(img.Image(width: 16, height: 16));
    for (var o = 2; o + 9 < bytes.length;) {
      final marke = bytes[o + 1];
      final laenge = bytes[o + 2] << 8 | bytes[o + 3];
      if (marke == 0xC0 || marke == 0xC2) {
        bytes[o + 5] = hoehe >> 8;
        bytes[o + 6] = hoehe & 255;
        bytes[o + 7] = breite >> 8;
        bytes[o + 8] = breite & 255;
        return bytes;
      }
      o += 2 + laenge;
    }
    throw StateError('kein SOF');
  }

  Matcher scheitertAn(Fuegegrund grund) => throwsA(
    isA<Zusammenfuegefehler>().having((f) => f.grund, 'grund', grund),
  );

  test('ein PNG, das mehr Speicher verlangt, als erlaubt ist, wird am Kopf '
      'abgewiesen – ohne zu dekodieren', () {
    // 16 000 × 16 000 in 16 Bit mit Alpha: 2 GB, die `package:image` sonst
    // anzulegen versuchte (seine eigene Grenze liegt bei 268 MP).
    final bombe = pngKopf(16000, 16000);
    expect(leseBildkopf(bombe)!.pixel, 256000000);
    expect(
      () => dekodiereBild(bombe, quelle: 2),
      scheitertAn(Fuegegrund.zuGross),
    );
    // Gegenprobe: dieselbe Fläche in 8 Bit Grau liegt unter der Grenze des
    // Speichers, wohl aber über der Punktzahl – und ein echtes PNG wird
    // gelesen.
    expect(
      lesbarNachKopf(leseBildkopf(pngKopf(4000, 4000, farbe: 0, tiefe: 8))!),
      isTrue,
    );
    final echt = img.encodePng(img.Image(width: 30, height: 20));
    expect(dekodiereBild(echt).breite, 30);
  });

  test('ein PNG mit zwei IHDR gilt als kaputt', () {
    expect(leseBildkopf(pngKopf(10, 10, ihdr: 2)), isNull);
    expect(
      () => dekodiereBild(pngKopf(10, 10, ihdr: 2)),
      scheitertAn(Fuegegrund.unlesbar),
    );
  });

  test('ein JPEG über der Grenze wird verkleinert gelesen, eines mit mehr '
      'als 200 MP abgewiesen', () {
    final gross = leseBildkopf(jpegMitMassen(12000, 8000))!;
    expect(jpegLeseteiler(gross), 2);
    expect(jpegLeseteiler(leseBildkopf(jpegMitMassen(6000, 4000))!), 1);
    expect(jpegLeseteiler(leseBildkopf(jpegMitMassen(16000, 12000))!), 2);
    expect(
      () => dekodiereBild(jpegMitMassen(20000, 15000)),
      scheitertAn(Fuegegrund.zuGross),
    );
    expect(
      dekodierteGroesse(jpegMitMassen(12000, 8000), hoechstensPixel: 24000000),
      (breite: 6000, hoehe: 4000),
    );
  });

  test('die Grösse aus dem Kopf ist die, die das Lesen liefert – gedreht '
      'und begrenzt', () {
    final bild = img.Image(width: 120, height: 80);
    bild.exif.imageIfd.orientation = 6;
    final bytes = img.encodeJpg(bild);
    final gelesen = dekodiereBild(bytes, hoechstensPixel: 5000);
    expect(dekodierteGroesse(bytes, hoechstensPixel: 5000), (
      breite: gelesen.breite,
      hoehe: gelesen.hoehe,
    ));
    expect(gelesen.hoehe, greaterThan(gelesen.breite));
  });

  test('fehlt die Grösse in der Datenbank, entscheidet der Kopf der Datei – '
      'der Lauf scheitert verständlich statt mit vollem Speicher', () async {
    final temp = await Directory.systemTemp.createTemp('pv_fuegen_lesen_');
    addTearDown(() => temp.delete(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    final library = LibraryState()
      ..db = db
      ..paths = pfade
      ..importService = ImportService(db, pfade);
    final quellen = <AssetData>[];
    for (final (i, bytes) in [
      (0, pngKopf(16000, 16000)),
      (1, img.encodePng(img.Image(width: 30, height: 20))),
    ]) {
      final rel = 'originale/q$i.png';
      File(pfade.absolute(rel).path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'q$i',
              originalFileName: 'q$i.png',
              relativePath: rel,
              checksum: 'pruef-$i',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2024, 1, 1, 0, 0, i),
              importedAt: DateTime(2024),
              widthPx: const Value(null),
            ),
          );
      quellen.add((await db.assetById('q$i'))!);
    }
    await expectLater(
      zusammenfuegenLauf(
        library,
        quellen: quellen,
        art: Fuegeart.hdr,
      ).drain<void>(),
      throwsA(
        isA<Zusammenfuegefehler>()
            .having((f) => f.grund, 'grund', Fuegegrund.zuGross)
            .having((f) => f.quelle, 'quelle', 0),
      ),
    );
  });
}
