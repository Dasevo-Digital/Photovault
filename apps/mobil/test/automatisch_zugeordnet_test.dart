// Automatisch zugeordnete Gesichter sind zu sehen (PER-074): Die
// Kennzeichnung kommt über den Abgleich aufs Telefon; der Rahmen zeigt sie,
// und ein Tipp auf das Zeichen bestätigt.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/betrachter.dart';
import 'package:photo_vault_mobil/sitzung.dart';

void main() {
  testWidgets('der Rahmen trägt das Zeichen, ein Tipp darauf bestätigt', (
    tester,
  ) async {
    final ordner = Directory.systemTemp.createTempSync('pv_automatisch_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: 'g1',
          originalFileName: 'g1.jpg',
          relativePath: 'originals/g1.jpg',
          checksum: 'pruef-g1',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2025),
          importedAt: DateTime(2026),
          widthPx: const Value(400),
          heightPx: const Value(400),
        ),
      );
      await db
          .into(db.people)
          .insert(PeopleCompanion.insert(id: 'anna', name: 'Anna'));
      await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: 'f1',
              assetId: 'g1',
              personId: const Value('anna'),
              boxX: 0.2,
              boxY: 0.2,
              boxW: 0.5,
              boxH: 0.5,
              automatischZugeordnet: const Value(true),
            ),
          );
    });
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
        home: Betrachter(
          sitzung: sitzung,
          zeilen: [
            Rasterzeile(
              id: 'g1',
              type: 'IMAGE',
              originalFileName: 'g1.jpg',
              relativePath: 'originals/g1.jpg',
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
              widthPx: 400,
              heightPx: 400,
              latitude: null,
              longitude: null,
              cameraMake: null,
              isLocked: false,
            ),
          ],
          start: 0,
        ),
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

    await ruhe();
    final t = AppTexte.of(tester.element(find.byType(Betrachter)));
    await tester.tap(find.byTooltip(t.betrachterMehr));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.betrachterGesichterZeigen));
    await tester.pumpAndSettle();
    await ruhe();

    final zeichen = find.byTooltip(t.gesichtAutomatischBestaetigen);
    expect(zeichen, findsOneWidget);
    await tester.tap(zeichen);
    // Der Tipp gilt erst, wenn kein zweiter mehr kommt: Das Foto liegt in
    // PhotoView, und das wartet auf einen Doppeltipp.
    await tester.pump(const Duration(milliseconds: 400));
    await ruhe();
    final f = (await tester.runAsync(() => db.facesForAsset('g1')))!.single;
    expect(f.personId, 'anna');
    expect(f.automatischZugeordnet, isFalse);
    expect(find.text(t.gesichtAutomatischBestaetigt), findsOneWidget);
    // Bestätigt: kein Zeichen mehr, und das Benennen ging nicht auf.
    expect(zeichen, findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
