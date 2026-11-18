import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:kern/services/model_download_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/home_shell.dart';
import 'package:photo_vault/screens/search_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/tastenkuerzel.dart';

/// Die Tastenkürzel der Hülle: was die Kürzeltafel verspricht, und dass
/// ein Textfeld seine Zeichen behält.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_kuerzel_');
    // Die Einstellungen fragen beim Aufbau nach Ordnern und der Fassung.
    const ablage = MethodChannel('plugins.flutter.io/path_provider');
    const paket = MethodChannel('dev.fluttercommunity.plus/package_info');
    final bote =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    bote.setMockMethodCallHandler(ablage, (_) async => wurzel.path);
    bote.setMockMethodCallHandler(
      paket,
      (_) async => <String, String>{
        'appName': 'Photo Vault',
        'packageName': 'de.dasevo.photovault',
        'version': '3.7.0',
        'buildNumber': '1',
      },
    );
    addTearDown(() {
      bote.setMockMethodCallHandler(ablage, null);
      bote.setMockMethodCallHandler(paket, null);
    });
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'lib')),
      )
      ..modelDownloadService = ModelDownloadService(
        (Directory(
          p.join(wurzel.path, 'models'),
        )..createSync(recursive: true)).path,
      );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// Abgezählte Bilder statt eines Ausschwingens – siehe
  /// menueleiste_test.dart: Die Zeitleiste dreht einen Ladekreis.
  Future<void> ruhe(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  Future<void> huelle(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
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
    await tester.pump();
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> befehl(WidgetTester tester, LogicalKeyboardKey taste) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(taste);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await ruhe(tester);
  }

  testWidgets('⌘0 öffnet die Einstellungen, wie die Kürzeltafel sagt', (
    tester,
  ) async {
    await huelle(tester);
    await befehl(tester, LogicalKeyboardKey.digit0);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(TrashScreen), findsNothing);
    await abbauen(tester);
  });

  testWidgets('„?“ und „_“ in einem Textfeld öffnen die Kürzeltafel nicht', (
    tester,
  ) async {
    await huelle(tester);
    await befehl(tester, LogicalKeyboardKey.digit2);
    expect(find.byType(SearchScreen), findsOneWidget);
    final feld = find.descendant(
      of: find.byType(SearchScreen),
      matching: find.byType(EditableText),
    );
    await tester.tap(feld.first);
    await tester.pump();

    for (final (physisch, logisch, zeichen) in [
      (PhysicalKeyboardKey.slash, LogicalKeyboardKey.slash, '?'),
      (PhysicalKeyboardKey.minus, LogicalKeyboardKey.minus, '_'),
    ]) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final erledigt = await tester.sendKeyDownEvent(
        logisch,
        physicalKey: physisch,
        character: zeichen,
      );
      await tester.sendKeyUpEvent(logisch, physicalKey: physisch);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        erledigt,
        isFalse,
        reason: '„$zeichen“ muss beim Textfeld ankommen',
      );
      expect(find.byType(Tastenkuerzeltafel), findsNothing);
    }

    // Ohne Textfeld im Fokus bleibt „?“ das Kürzel für die Tafel.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(
      LogicalKeyboardKey.slash,
      physicalKey: PhysicalKeyboardKey.slash,
      character: '?',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await ruhe(tester);
    expect(find.byType(Tastenkuerzeltafel), findsOneWidget);
    await abbauen(tester);
  });
}
