import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/dokumente_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';

/// Die Liste der Ausweise: alle vorgewählt, und „Nicht mehr vorschlagen“
/// nimmt nur die gewählten heraus.
void main() {
  testWidgets('abgewählte bleiben, verworfene verschwinden', (tester) async {
    final wurzel = Directory.systemTemp.createTempSync('pv_dokumente_');
    final db = AppDatabase(NativeDatabase.memory());
    late final LibraryState library;
    await tester.runAsync(() async {
      // Der Pass ist jünger und steht deshalb vorn.
      for (final (id, text, monat) in [
        ('pass', 'REISEPASS', 2),
        ('fuehrerschein', 'FÜHRERSCHEIN', 1),
      ]) {
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: id,
                originalFileName: '$id.jpg',
                relativePath: 'originals/$id.jpg',
                checksum: 'pruef-$id',
                type: 'IMAGE',
                fileCreatedAt: DateTime(2026, monat),
                importedAt: DateTime(2026),
              ),
            );
        await db.setOcrResult(id, text);
      }
      library = LibraryState()
        ..db = db
        ..paths = await StoragePaths.forTesting(
          Directory(p.join(wurzel.path, 'lib')),
        );
    });
    addTearDown(() async {
      await tester.runAsync(db.close);
      wurzel.deleteSync(recursive: true);
    });

    Future<void> warten() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: DokumenteScreen(library: library),
      ),
    );
    await warten();
    expect(find.text('Reisepass · Aufdruck'), findsOneWidget);
    expect(find.text('Führerschein · Aufdruck'), findsOneWidget);
    expect(find.text('2 Fotos sperren'), findsOneWidget);

    // Den Pass abwählen: Er soll bleiben, also nicht verworfen werden.
    await tester.tap(find.byType(AssetThumbnailTile).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('1 Foto sperren'), findsOneWidget);

    await tester.tap(find.text('Nicht mehr vorschlagen'));
    await warten();
    await warten();
    final rest = await tester.runAsync(() => ladeDokumentvorschlaege(db));
    expect([for (final v in rest!) v.asset.id], ['pass']);
  });
}
