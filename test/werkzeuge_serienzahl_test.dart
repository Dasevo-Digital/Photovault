import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/tools_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Unter „Serienbilder gruppieren“ steht, wie viele Serien warten – und
/// ohne Serien „Keine Serien gefunden“. Die Zeile fiel bei 0 ganz weg;
/// der Fall „=0“ des Textes erschien nie (IMP-154).
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_serienzahl_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('ohne Serien steht „Keine Serien gefunden“', (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildLightTheme(),
        home: Scaffold(body: ToolsScreen(library: library)),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    final de = AppTexte.of(tester.element(find.byType(ToolsScreen)));
    expect(find.text(de.werkzStapelTitel), findsOneWidget);
    expect(find.text(de.werkzStapelGefunden(0)), findsOneWidget);
  });
}
