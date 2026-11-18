// Auswahl: behobene Befunde aus dem Prüfkatalog der Handy-App (MOB,
// Issue #418): je Befund ein Test, der ohne die Korrektur scheitert.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/auswahl.dart';
import 'package:photo_vault_mobil/sitzung.dart';

Rasterzeile _zeile(String id) => Rasterzeile(
  id: id,
  type: 'IMAGE',
  originalFileName: '$id.jpg',
  relativePath: 'originals/$id.jpg',
  thumbnailRelativePath: null,
  fileCreatedAt: DateTime(2025),
  durationSeconds: null,
  isFavorite: false,
  isStackCover: false,
  stackId: null,
  stackSize: null,
  linkedAssetId: null,
  rating: 0,
  colorLabel: null,
  widthPx: null,
  heightPx: null,
  latitude: null,
  longitude: null,
  cameraMake: null,
  isLocked: false,
);

void main() {
  testWidgets('MOB-043 gemischte Auswahl archivieren: „Rückgängig“ stellt '
      'nur die geänderte zurück, die Meldung geht von selbst', (tester) async {
    final ordner = Directory.systemTemp.createTempSync('pv_archiv_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (final id in ['alt', 'neu']) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2025),
          importedAt: DateTime(2026),
        ),
      );
    }
    await db.fuehreAus(const ArchivSetzen(['alt'], true));
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    final sitzung = Sitzung()
      ..db = db
      ..paths = pfade;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomSheet: Auswahlleiste(
            sitzung: sitzung,
            zeilen: [_zeile('alt'), _zeile('neu')],
            aufheben: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Auswahlleiste)));
    Future<bool> archiviert(String id) async =>
        (await db.assetById(id))!.isArchived;

    await tester.tap(find.text(t.auswahlArchiv));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t.auswahlArchiviert(2)), findsOneWidget);
    expect(await archiviert('alt'), isTrue);
    expect(await archiviert('neu'), isTrue);

    await tester.tap(find.text(t.variantenRueckgaengig));
    await tester.pumpAndSettle();
    expect(await archiviert('neu'), isFalse);
    expect(
      await archiviert('alt'),
      isTrue,
      reason: 'lag schon vorher im Archiv',
    );

    // Ohne Tipp verschwindet die Meldung nach ihrer Zeit.
    await tester.tap(find.text(t.auswahlArchiv));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t.auswahlArchiviert(2)), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text(t.auswahlArchiviert(2)), findsNothing);
  });
}
