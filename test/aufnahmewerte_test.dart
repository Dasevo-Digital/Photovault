import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/asset_format.dart';
import 'package:photo_vault/services/exif_camera.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';

IfdTag _ratios(List<Ratio> werte) =>
    IfdTag(tag: 0, tagType: 'Ratio', printable: '$werte', values: IfdRatios(werte));

IfdTag _ints(List<int> werte) =>
    IfdTag(tag: 0, tagType: 'Short', printable: '$werte', values: IfdInts(werte));

/// Die Info-Ansicht zeigte Zeit/ISO in der einen und Blende/Brennweite in
/// einer zweiten Zeile. Die Belichtungskorrektur fehlte ganz, und als
/// Brennweite stand bei Telefonen die echte (5,7 mm) statt der
/// kleinbild-äquivalenten (26 mm) – also genau die Zahl, die niemand kennt.
void main() {
  group('Belichtungskorrektur', () {
    test('null steht ohne Vorzeichen da', () {
      expect(formatExposureBias(0), '0 ev');
      // Ein Wert knapp neben null kommt von der Rundung des Bruchs, nicht
      // von einer Korrektur am Rad.
      expect(formatExposureBias(0.02), '0 ev');
    });

    test('trägt sonst immer ein Vorzeichen', () {
      expect(formatExposureBias(1), '+1 ev');
      expect(formatExposureBias(-1), '-1 ev');
      expect(formatExposureBias(0.7), '+0.7 ev');
      expect(formatExposureBias(-1 / 3), '-0.3 ev');
    });
  });

  group('EXIF', () {
    test('liest Belichtungskorrektur als vorzeichenbehafteten Bruch', () {
      final info = parseExifCameraInfo({
        'EXIF ExposureBiasValue': _ratios([Ratio(-1, 3)]),
        'EXIF FocalLengthIn35mmFilm': _ints([26]),
      });
      expect(info.exposureBiasEv, closeTo(-1 / 3, 1e-9));
      expect(info.focalLength35mm, 26.0);
    });

    test('ohne die beiden Angaben bleibt es bei null, nicht bei einer Annahme', () {
      final info = parseExifCameraInfo({'EXIF FNumber': _ratios([Ratio(3, 2)])});
      expect(info.exposureBiasEv, isNull);
      expect(info.focalLength35mm, isNull);
      // Ein Screenshot hat keine Belichtungskorrektur von null – er hat gar
      // keine. Der Unterschied entscheidet, ob „0 ev" angezeigt wird.
      expect(info.isEmpty, isFalse);
    });
  });

  group('Werte-Zeile', () {
    late Directory tempRoot;
    late AppDatabase db;
    late StoragePaths paths;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('pv_aufnahme_');
      db = AppDatabase(NativeDatabase.memory());
      paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    });

    tearDown(() async {
      await db.close();
      tempRoot.deleteSync(recursive: true);
    });

    Future<AssetData> lege({
      String name = 'IMG_0042.HEIC',
      String? make,
      String? model,
      String? objektiv,
      double? blende,
      double? brennweite,
      double? brennweite35,
      int? iso,
      double? zeit,
      double? korrektur,
    }) async {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'a',
            originalFileName: name,
            relativePath: 'originals/$name',
            checksum: 'a',
            fileCreatedAt: DateTime(2024, 5, 1),
            importedAt: DateTime(2024, 5, 2),
            type: 'IMAGE',
            widthPx: const Value(3024),
            heightPx: const Value(4032),
            fileSizeBytes: const Value(2202009),
            cameraMake: Value(make),
            cameraModel: Value(model),
            lensModel: Value(objektiv),
            fNumber: Value(blende),
            focalLengthMm: Value(brennweite),
            focalLength35mm: Value(brennweite35),
            iso: Value(iso),
            exposureTimeSeconds: Value(zeit),
            exposureBiasEv: Value(korrektur),
          ));
      return (await db.assetById('a'))!;
    }

    test('Reihenfolge und Kleinbild-Vorrang – an einer echten iPhone-Aufnahme', () async {
      // Die Werte stammen aus einer HEIC-Datei der Bibliothek, gegen
      // package:exif eingelesen: 5,7 mm echte und 26 mm äquivalente
      // Brennweite, f/1,5, ISO 50, 1/588 s, keine Korrektur.
      final asset = await lege(
        make: 'Apple',
        model: 'iPhone 13 Pro',
        objektiv: 'iPhone 13 Pro back triple camera 5.7mm f/1.5',
        blende: 1.5,
        brennweite: 5.7,
        brennweite35: 26,
        iso: 50,
        zeit: 1 / 588,
        korrektur: 0,
      );

      expect(aufnahmewerte(asset), ['ISO 50', '26 mm', '0 ev', 'f/1.5', '1/588 s']);
    });

    test('ohne Kleinbildangabe zählt die echte Brennweite', () async {
      final asset = await lege(make: 'Canon', model: 'Canon EOS R5', brennweite: 85, blende: 1.4);
      expect(aufnahmewerte(asset), ['85 mm', 'f/1.4']);
    });

    test('was die Kamera nicht geschrieben hat, wird weggelassen', () async {
      final asset = await lege();
      expect(aufnahmewerte(asset), isEmpty);
    });

    testWidgets('die Info-Ansicht zeigt Gerät, Objektiv und alle fünf Werte',
        (tester) async {
      final asset = await lege(
        make: 'Apple',
        model: 'iPhone 13 Pro',
        objektiv: 'iPhone 13 Pro back triple camera 5.7mm f/1.5',
        blende: 1.5,
        brennweite: 5.7,
        brennweite35: 26,
        iso: 50,
        zeit: 1 / 588,
        korrektur: 0,
      );

      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: AssetInfoSheet(
            asset: asset,
            db: db,
            paths: paths,
            onUpdated: (_) {},
            onClose: () {},
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Apple iPhone 13 Pro'), findsOneWidget);
      expect(find.text('iPhone 13 Pro back triple camera 5.7mm f/1.5'), findsOneWidget);
      for (final wert in ['ISO 50', '26 mm', '0 ev', 'f/1.5', '1/588 s']) {
        expect(find.text(wert), findsOneWidget, reason: wert);
      }
      // Das Formatkürzel stand bisher nur an der Kachel in der Übersicht.
      expect(find.textContaining('HEIC'), findsWidgets);
    });
  });
}
