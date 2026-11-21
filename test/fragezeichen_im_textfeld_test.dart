import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/screens/home_shell.dart';
import 'package:photo_vault/state/library_state.dart';

/// **„?" in einem Textfeld ist ein Zeichen.**
///
/// Die Hülle öffnet mit „?" die Tafel der Tastenkürzel. Sie fing die Taste
/// aber auch ab, während in ein Feld geschrieben wurde – das Fragezeichen
/// kam nie an, stattdessen ging die Tafel auf. Derselbe Fehler wie in der
/// Info-Leiste der Einzelansicht (ANS-045).
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;
  final de = AppTexteDe();

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_fragezeichen_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'lib')),
      );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> fragezeichen(WidgetTester tester) async {
    // Umschalt + die Taste rechts neben dem Punkt, wie im US-Layout.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('im Suchfeld öffnet „?" die Tafel nicht, daneben schon', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: HomeShell(library: library),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    // Zur Suche, dort steht ein Textfeld.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 200));
    final feld = find.byType(TextField).first;
    await tester.tap(feld);
    await tester.pump();

    await fragezeichen(tester);
    expect(find.text(de.kuerzelTitel), findsNothing);

    // Ohne Fokus im Feld bleibt das Kürzel, wie es war.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await fragezeichen(tester);
    expect(find.text(de.kuerzelTitel), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
