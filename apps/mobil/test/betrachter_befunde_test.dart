// Betrachter: behobene Befunde aus dem Prüfkatalog der Handy-App (MOB,
// Issue #418): je Befund ein Test, der ohne die Korrektur scheitert.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/bilder.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/betrachter.dart';
import 'package:photo_vault_mobil/seiten/entwickeln.dart';
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
  testWidgets('MOB-134 nach dem Entwickeln zeigt der Betrachter gleich die '
      'neue Fassung', (tester) async {
    final ordner = Directory.systemTemp.createTempSync('pv_betrachter_bef_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'e1',
        originalFileName: 'e1.jpg',
        relativePath: 'originals/e1.jpg',
        checksum: 'pruef-e1',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2025),
        importedAt: DateTime(2026),
      ),
    );
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
        home: Betrachter(sitzung: sitzung, zeilen: [_zeile('e1')], start: 0),
      ),
    );
    Future<void> ruhe() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
    }

    Set<String> gezeigt() => {
      for (final w in tester.widgetList<Image>(find.byType(Image)))
        switch (w.image) {
          ResizeImage(imageProvider: BibliotheksBild(:final relativ)) =>
            relativ,
          BibliotheksBild(:final relativ) => relativ,
          _ => '',
        },
    }..remove('');

    await ruhe();
    expect(gezeigt(), contains('originals/e1.jpg'));

    // Entwickeln öffnen; gespeichert wird hier am Befehl vorbei – wie es
    // „Speichern“ in der Kopie hinterlässt.
    final t = AppTexte.of(tester.element(find.byType(Betrachter)));
    await tester.tap(find.byTooltip(t.betrachterMehr));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.entwTitel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Entwickeln), findsOneWidget);
    await tester.runAsync(
      () => (db.update(db.assets)..where((a) => a.id.equals('e1'))).write(
        const AssetsCompanion(
          developedRelativePath: Value('developed/e1-1.jpg'),
        ),
      ),
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await ruhe();
    expect(find.byType(Entwickeln), findsNothing);
    expect(gezeigt(), contains('developed/e1-1.jpg'));
    expect(gezeigt(), isNot(contains('originals/e1.jpg')));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
