import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/home_shell.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Ein Fenster, das jemand ganz klein gezogen hat, darf die App nicht
/// einfrieren.
///
/// **Gesehen unter Windows (3.28.0).** Der Runner stellt die Fenstergrösse
/// des letzten Laufs wieder her, und die war 225 × 150 Punkte. Die
/// Schnellleiste der Zeitleiste rief darin `clamp` mit einer Obergrenze
/// unter der unteren auf. Eine Ausnahme im Layout friert die ausgelieferte
/// App ganz ein: Jedes weitere Bild scheitert am halb gebauten Baum, auch
/// nach dem Vergrössern. Geprüft wird die Hauptansicht mit Fotos aus
/// mehreren Monaten, damit die Leiste wirklich erscheint.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_winzig_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'lib')),
      );
    for (var monat = 1; monat <= 6; monat++) {
      for (var i = 0; i < 4; i++) {
        final id = 'f$monat-$i';
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: id,
                originalFileName: '$id.jpg',
                relativePath: 'originals/$id.jpg',
                checksum: id,
                type: 'IMAGE',
                fileCreatedAt: DateTime(2026, monat, 3 + i),
                importedAt: DateTime(2026, 7),
                fileSizeBytes: const Value(1000),
              ),
            );
      }
    }
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  for (final groesse in const [
    Size(225, 150),
    Size(320, 200),
    Size(480, 300),
    Size(160, 100),
  ]) {
    testWidgets('${groesse.width.toInt()} × ${groesse.height.toInt()} Punkte '
        'wirft nicht', (tester) async {
      tester.view.physicalSize = groesse;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Überläufe zählen nicht: Die gibt es nur im Debug-Bau als
      // Warnstreifen, ausgeliefert wird abgeschnitten. Alles andere wirft
      // auch dort – und friert die Oberfläche ein.
      final fehler = <String>[];
      final vorher = FlutterError.onError;
      FlutterError.onError = (d) {
        final text = d.exceptionAsString();
        if (!text.contains('overflowed')) fehler.add(text);
      };
      addTearDown(() => FlutterError.onError = vorher);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: HomeShell(library: library),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(fehler, isEmpty);
      // Und wieder gross: Das Fenster muss danach zeichnen können.
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pump();
      expect(fehler, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }
}
