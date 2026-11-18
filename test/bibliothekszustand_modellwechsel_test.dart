import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/background_tasks_screen.dart';
import 'package:photo_vault/screens/library_health_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Eine Bibliothek, deren Bildsuche von einer älteren Modellfassung stammt.
class _Veraltet extends LibraryState {
  _Veraltet(this._veraltet);
  final Set<String> _veraltet;

  @override
  Set<String> get outdatedModelPipelines => _veraltet;

  // Fragt sonst den Modellordner ab, den es in diesem Test nicht gibt.
  @override
  bool get faceRecognitionAvailable => false;
}

/// Die Karte „KI-Ergebnisse aktualisieren“ im Bibliothekszustand.
///
/// „Aufgaben öffnen“ rief zeigeBereich(werkzeuge) – der Bibliothekszustand
/// liegt aber selbst in „Werkzeuge“, also geschah nichts (KI-062).
void main() {
  late Directory wurzel;
  late AppDatabase db;

  setUp(() {
    wurzel = Directory.systemTemp.createTempSync('pv_zustand_');
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  test('jede veraltete Verarbeitung führt zu ihrer Aufgabe', () {
    expect(aufgabeFuerVeralteteVerarbeitung({'clip'}), 'embeddings');
    expect(aufgabeFuerVeralteteVerarbeitung({'faces'}), 'gesichter');
    expect(aufgabeFuerVeralteteVerarbeitung({'ocr'}), 'ocr');
    expect(aufgabeFuerVeralteteVerarbeitung({'captions'}), 'beschreibungen');
    expect(aufgabeFuerVeralteteVerarbeitung({}), isNull);
  });

  testWidgets('„Aufgaben öffnen“ öffnet die Aufgaben mit der Bildsuche oben', (
    tester,
  ) async {
    final library = _Veraltet({'clip'})
      ..db = db
      ..paths = (await tester.runAsync(
        () => StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib'))),
      ))!;
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: LibraryHealthScreen(library: library),
      ),
    );
    final t = lookupAppTexte(const Locale('de'));
    final knopf = find.text(t.gesundheitModellwechselAufgaben);
    for (var i = 0; i < 50 && knopf.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text(t.gesundheitModellwechselTitel), findsOneWidget);

    await tester.ensureVisible(knopf);
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(BackgroundTasksScreen), findsOneWidget);
    expect(
      tester
          .widget<BackgroundTasksScreen>(find.byType(BackgroundTasksScreen))
          .hervorheben,
      'embeddings',
    );
  });
}
