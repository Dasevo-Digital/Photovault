import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/wasserzeichen.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/export_service.dart';
import 'package:photo_vault/services/library_location.dart';

import 'hilfen/datenbanken.dart';

/// Das Wasserzeichen einer Exportvorgabe beim Export (#497).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late Directory ziel;

  Uint8List grauesJpeg() {
    final bild = img.Image(width: 200, height: 100)
      ..clear(img.ColorRgb8(90, 90, 90));
    return Uint8List.fromList(img.encodeJpg(bild, quality: 95));
  }

  final rotesLogo = Uint8List.fromList(
    img.encodePng(
      img.Image(width: 40, height: 20, numChannels: 4)
        ..clear(img.ColorRgba8(255, 0, 0, 255)),
    ),
  );

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_wasserzeichen_');
    LibraryLocation.nutzeFuerTests(anker: tempRoot);
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(tempRoot.path, 'lib')),
    );
    ziel = Directory(p.join(tempRoot.path, 'ziel'))..createSync();
    // Der Bildwandler gibt die Datei zurück, die er bekommt.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('photo_vault/image_convert'),
          (aufruf) async => switch (aufruf.method) {
            'convertToJpeg' => File(
              (aufruf.arguments as Map)['path'] as String,
            ).readAsBytesSync(),
            _ => null,
          },
        );
  });

  tearDown(() async {
    LibraryLocation.zuruecksetzenFuerTests();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('photo_vault/image_convert'),
          null,
        );
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<AssetData> foto() async {
    final rein = File(p.join(tempRoot.path, 'turm.jpg'))
      ..writeAsBytesSync(grauesJpeg());
    final r = await ImportService(db, paths).importFile(rein.path);
    return (await db.assetById(r.assetId!))!;
  }

  img.Image lies(String name) =>
      img.decodeJpg(File(p.join(ziel.path, name)).readAsBytesSync())!;

  Future<ExportPresetData> gespeichert({
    required bool nachJpeg,
    Wasserzeichen? wasserzeichen,
  }) async {
    await db.fuehreAus(
      ExportvorgabeSpeichern(
        ExportPresetsCompanion.insert(
          name: 'Mit Zeichen',
          nachJpeg: Value(nachJpeg),
          wasserzeichen: Value(wasserzeichen?.kodiert()),
          erstelltAm: DateTime(2026, 11, 27),
        ),
      ),
    );
    return (await db.alleExportPresets()).single;
  }

  test('ein Logo landet unten rechts im exportierten Bild', () async {
    final vorgabe = await gespeichert(
      nachJpeg: true,
      wasserzeichen: Wasserzeichen(
        art: Wasserzeichenart.bild,
        bild: rotesLogo,
        deckkraft: 1,
        rand: 0,
      ),
    );
    final name = await ExportService(paths).exportAsset(
      await foto(),
      ziel.path,
      vorgabe: Exportvorgabe.ausPreset(vorgabe),
    );
    final bild = lies(name);
    // 20 % von 200 px: 40 × 20 in der Ecke unten rechts.
    final ecke = bild.getPixel(185, 92);
    expect(ecke.r, greaterThan(200));
    expect(ecke.g, lessThan(60));
    final mitte = bild.getPixel(100, 50);
    expect(mitte.r, inInclusiveRange(80, 100), reason: 'sonst unverändert');
    // Die Aufnahmeangaben kommen danach dazu, wie ohne Zeichen.
    expect(bild.exif.exifIfd['DateTimeOriginal'], isNotNull);
  });

  test('ein Text wird gezeichnet und eingerechnet', () async {
    final vorgabe = await gespeichert(
      nachJpeg: true,
      wasserzeichen: const Wasserzeichen(
        text: '© 2026',
        lage: Wasserzeichenlage.obenLinks,
        groesse: 0.5,
        deckkraft: 1,
        rand: 0,
      ),
    );
    final name = await ExportService(paths).exportAsset(
      await foto(),
      ziel.path,
      vorgabe: Exportvorgabe.ausPreset(vorgabe),
    );
    final bild = lies(name);
    // Weisser Text oben links: Irgendwo dort ist es deutlich heller als der
    // graue Grund; unten rechts bleibt es grau.
    var hellste = 0;
    for (var y = 0; y < 40; y++) {
      for (var x = 0; x < 100; x++) {
        final r = bild.getPixel(x, y).r.toInt();
        if (r > hellste) hellste = r;
      }
    }
    expect(hellste, greaterThan(200));
    expect(bild.getPixel(190, 95).r, inInclusiveRange(80, 100));
  });

  test('eine Vorgabe ohne „Nach JPEG rendern“ kopiert unverändert', () async {
    // Das Zeichen steht in der Zeile, gilt aber nicht: Unverändert kopiert
    // heisst Bit für Bit (Exportvorgabe.wasserzeichen).
    final vorgabe = await gespeichert(
      nachJpeg: false,
      wasserzeichen: const Wasserzeichen(text: '© 2026'),
    );
    expect(Exportvorgabe.ausPreset(vorgabe).wasserzeichen, isNull);
    final a = await foto();
    final name = await ExportService(
      paths,
    ).exportAsset(a, ziel.path, vorgabe: Exportvorgabe.ausPreset(vorgabe));
    expect(
      File(p.join(ziel.path, name)).readAsBytesSync(),
      File(p.join(tempRoot.path, 'turm.jpg')).readAsBytesSync(),
    );
    expect(
      const Exportvorgabe(
        wasserzeichen: Wasserzeichen(text: 'x'),
      ).wasserzeichen,
      isNull,
    );
  });

  test('eine Vorgabe von vor Schema 104 hat kein Wasserzeichen', () async {
    final alt = await gespeichert(nachJpeg: true);
    expect(alt.wasserzeichen, isNull);
    expect(Exportvorgabe.ausPreset(alt).wasserzeichen, isNull);
    // Ein leerer Text beschreibt nichts Einrechenbares.
    expect(
      vorgabeWasserzeichen(
        alt.copyWith(wasserzeichen: const Value('{"art":"text","text":"  "}')),
      ),
      isNull,
    );
  });

  test('ein Video wird ausgelassen statt ohne Zeichen kopiert', () async {
    final datei = paths.absolute('originals/film.mov');
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(utf8.encode('kein echtes Video'));
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'film',
            originalFileName: 'film.mov',
            relativePath: 'originals/film.mov',
            checksum: 'pruef-film',
            type: 'VIDEO',
            fileCreatedAt: DateTime(2025),
            importedAt: DateTime(2026),
          ),
        );
    final video = (await db.assetById('film'))!;
    await expectLater(
      ExportService(paths).exportAsset(
        video,
        ziel.path,
        vorgabe: const Exportvorgabe(
          nachJpeg: true,
          wasserzeichen: Wasserzeichen(text: '© 2026'),
        ),
      ),
      throwsA(isA<WasserzeichenNichtMoeglich>()),
    );
    expect(ziel.listSync(), isEmpty, reason: 'keine halbe Kopie am Ziel');
    // Ohne Zeichen geht dasselbe Video unverändert hinaus, wie bisher.
    await ExportService(paths).exportAsset(
      video,
      ziel.path,
      vorgabe: const Exportvorgabe(nachJpeg: true, xmpDaneben: false),
    );
    expect(ziel.listSync(), hasLength(1));
  });

  test(
    'ein unlesbares Logo bricht ab, statt ohne Zeichen zu exportieren',
    () async {
      await expectLater(
        ExportService(paths).exportAsset(
          await foto(),
          ziel.path,
          vorgabe: Exportvorgabe(
            nachJpeg: true,
            wasserzeichen: Wasserzeichen(
              art: Wasserzeichenart.bild,
              bild: Uint8List.fromList([1, 2, 3, 4]),
            ),
          ),
        ),
        throwsA(isA<WasserzeichenNichtMoeglich>()),
      );
      expect(ziel.listSync(), isEmpty);
    },
  );

  test('das Wasserzeichen reist mit dem Befehl zum anderen Gerät', () async {
    final dort = ZweiteDatenbank(NativeDatabase.memory());
    addTearDown(dort.close);
    final w = Wasserzeichen(
      art: Wasserzeichenart.bild,
      bild: rotesLogo,
      lage: Wasserzeichenlage.unten,
    );
    final befehl = ExportvorgabeSpeichern(
      ExportPresetsCompanion.insert(
        name: 'Logo',
        nachJpeg: const Value(true),
        wasserzeichen: Value(w.kodiert()),
        erstelltAm: DateTime(2026, 11, 27),
      ),
    );
    await dort.fuehreAus(
      Befehl.ausJson(jsonDecode(jsonEncode(befehl.alsJson()))),
    );
    final angekommen = vorgabeWasserzeichen(
      (await dort.alleExportPresets()).single,
    )!;
    expect(angekommen.bild, rotesLogo);
    expect(angekommen.lage, Wasserzeichenlage.unten);
  });
}
