import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/wasserzeichen.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/fotobuch.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/fotobuch_export.dart';
import 'package:photo_vault/widgets/wasserzeichen_editor.dart';

/// Das Wasserzeichen im Fotobuch (#497): eingerechnet in die Bilder, nicht
/// als eigenes Objekt über ihnen – und im Dialog aus einer Exportvorgabe
/// oder eigens eingestellt.
void main() {
  final de = AppTexteDe();
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  final rotesLogo = Uint8List.fromList(
    img.encodePng(
      img.Image(width: 40, height: 20, numChannels: 4)
        ..clear(img.ColorRgba8(255, 0, 0, 255)),
    ),
  );

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_fotobuch_zeichen_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<List<AssetData>> fotos(int anzahl) async {
    for (var i = 0; i < anzahl; i++) {
      final datei = library.paths.absolute('originals/f$i.jpg');
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(
        img.encodeJpg(
          img.Image(width: 30, height: 20)..clear(img.ColorRgb8(90, 90, 90)),
        ),
      );
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'f$i',
              originalFileName: 'f$i.jpg',
              relativePath: 'originals/f$i.jpg',
              checksum: 'pruef-$i',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2025, 3, 12),
              importedAt: DateTime(2026),
              widthPx: const Value(30),
              heightPx: const Value(20),
            ),
          );
    }
    return db.select(db.assets).get();
  }

  /// Die eingebetteten JPEG eines PDF: Sie stehen dort unverändert, von
  /// SOI bis EOI.
  List<img.Image> bilderIm(Uint8List pdf) {
    final bilder = <img.Image>[];
    for (var i = 0; i + 3 < pdf.length; i++) {
      if (pdf[i] == 0xFF && pdf[i + 1] == 0xD8 && pdf[i + 2] == 0xFF) {
        final bild = img.decodeJpg(Uint8List.sublistView(pdf, i));
        if (bild != null) bilder.add(bild);
      }
    }
    return bilder;
  }

  Future<({int seiten, int bilder})?> buch(
    List<AssetData> aufnahmen,
    File ziel, {
    Wasserzeichen? wasserzeichen,
  }) => erstelleFotobuch(
    library,
    aufnahmen,
    (titel: '', format: Fotobuchformat.a4Quer, jeSeite: 1, angaben: const {}),
    ziel: ziel,
    untertitel: null,
    datum: (_) => '',
    sprache: 'de',
    fortschritt: (_) {},
    abbruch: () => false,
    // Statt des nativen Wandlers: ein graues Bild in Druckgrösse.
    wandle: (datei, {maxDimension}) async => Uint8List.fromList(
      img.encodeJpg(
        img.Image(width: 600, height: 400)..clear(img.ColorRgb8(90, 90, 90)),
        quality: 95,
      ),
    ),
    wasserzeichen: wasserzeichen,
  );

  test('das Zeichen steckt in den Pixeln jedes Bildes', () async {
    final ziel = File(p.join(wurzel.path, 'buch.pdf'));
    final ergebnis = await buch(
      await fotos(2),
      ziel,
      wasserzeichen: Wasserzeichen(
        art: Wasserzeichenart.bild,
        bild: rotesLogo,
        deckkraft: 1,
        rand: 0,
      ),
    );
    expect(ergebnis, (seiten: 2, bilder: 2));
    final bilder = bilderIm(await ziel.readAsBytes());
    expect(bilder, hasLength(2));
    for (final b in bilder) {
      // 20 % von 600 px: 120 × 60 unten rechts.
      expect(b.getPixel(590, 390).r, greaterThan(200));
      expect(b.getPixel(590, 390).g, lessThan(60));
      expect(b.getPixel(300, 200).r, inInclusiveRange(80, 100));
    }
  });

  test('ohne Zeichen bleibt das Bild, wie es war', () async {
    final ziel = File(p.join(wurzel.path, 'buch.pdf'));
    await buch(await fotos(1), ziel);
    final b = bilderIm(await ziel.readAsBytes()).single;
    expect(b.getPixel(590, 390).r, inInclusiveRange(80, 100));
  });

  test('wo das Zeichen nicht hineingeht, bleibt das Bild draussen', () async {
    // Ein Logo, das sich nicht lesen lässt: Ohne Zeichen käme das Bild ins
    // Buch (siehe oben) – mit einem, das nicht hineingeht, nicht.
    final ziel = File(p.join(wurzel.path, 'buch.pdf'));
    final ergebnis = await buch(
      await fotos(1),
      ziel,
      wasserzeichen: Wasserzeichen(
        art: Wasserzeichenart.bild,
        bild: Uint8List.fromList([1, 2, 3]),
      ),
    );
    expect(ergebnis, (seiten: 0, bilder: 0));
  });

  testWidgets('im Dialog: aus einer Vorgabe oder eigenes', (tester) async {
    await db.upsertExportPreset(
      ExportPresetsCompanion.insert(
        name: 'Fotoclub',
        nachJpeg: const Value(true),
        wasserzeichen: Value(const Wasserzeichen(text: '© Club').kodiert()),
        erstelltAm: DateTime(2026),
      ),
    );
    // Ohne „Nach JPEG rendern“ gilt das Zeichen nicht – also keine Wahl.
    await db.upsertExportPreset(
      ExportPresetsCompanion.insert(
        name: 'Kopie',
        wasserzeichen: Value(const Wasserzeichen(text: '© Kopie').kodiert()),
        erstelltAm: DateTime(2026),
      ),
    );
    final aufnahmen = await tester.runAsync(() => fotos(1));

    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => fotobuchExportieren(
                context,
                library,
                aufnahmen!,
                dateiname: 'buch.pdf',
              ),
              child: const Text('x'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    // Die Vorgaben kommen aus der Datenbank.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text(de.fotobuchGestalten), findsOneWidget);

    final erstellen = find.widgetWithText(FilledButton, de.fotobuchErstellen);
    expect(tester.widget<FilledButton>(erstellen).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('fotobuchWasserzeichen')));
    await tester.pumpAndSettle();
    expect(
      find.text(de.fotobuchWasserzeichenAusVorgabe('Fotoclub')),
      findsWidgets,
    );
    expect(
      find.text(de.fotobuchWasserzeichenAusVorgabe('Kopie')),
      findsNothing,
    );

    // Eigenes: erst mit einem Text lässt sich das Buch erstellen.
    await tester.tap(find.text(de.fotobuchWasserzeichenEigenes).last);
    await tester.pumpAndSettle();
    expect(find.byType(WasserzeichenEditor), findsOneWidget);
    expect(tester.widget<FilledButton>(erstellen).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, de.wasserzeichenText),
      '© 2026',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(erstellen).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(TextButton, de.allgAbbrechen));
    await tester.pumpAndSettle();
  });
}
