import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/background_tasks_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// **Ein Verweis, der nur bis zur Tür führt, ist keiner.**
///
/// Die Karten auf dem Gesundheitsbildschirm nennen eine Zahl und öffnen
/// die Aufgabenliste. Die hält zwanzig Karten; „Herkunft der
/// Aufnahmedaten" steht weit unten und wird, weil die Liste faul baut,
/// gar nicht erst erzeugt, solange niemand scrollt. Wer von einer
/// Meldung kommt, die eine Zahl nennt, stünde dann vor derselben Lage
/// wie zuvor – die Arbeit gibt es, nur findet sie niemand.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_hervorheben_');
    db = AppDatabase(NativeDatabase.memory());
    final paths =
        await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester, {String? hervorheben}) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home:
          BackgroundTasksScreen(library: library, hervorheben: hervorheben),
    ));
    await tester.pumpAndSettle();
  }

  const datum = 'Herkunft der Aufnahmedaten';

  testWidgets('ohne Verweis liegt die Aufgabe ausserhalb des Fensters',
      (tester) async {
    await zeige(tester);
    expect(find.text(datum), findsNothing);
  });

  testWidgets('mit Verweis steht sie oben und trägt einen Rahmen',
      (tester) async {
    await zeige(tester, hervorheben: 'datumsherkunft');

    expect(find.text(datum), findsOneWidget);

    // Oben heisst: vor der Karte, die sonst die erste ist.
    final ihre = tester.getTopLeft(find.text(datum)).dy;
    final sonstErste = tester.getTopLeft(find.text('Gesichter scannen')).dy;
    expect(ihre, lessThan(sonstErste));

    // Und der Rahmen sitzt an ihrer Karte, nicht an einer beliebigen.
    final karte = tester.widget<Card>(find
        .ancestor(of: find.text(datum), matching: find.byType(Card))
        .first);
    final rand = (karte.shape! as RoundedRectangleBorder).side;
    expect(rand.width, 2);
    expect(rand.color, buildDarkTheme().colorScheme.primary);

    // Die Nachbarkarte bleibt, wie sie war.
    final nachbar = tester.widget<Card>(find
        .ancestor(
            of: find.text('Gesichter scannen'), matching: find.byType(Card))
        .first);
    expect(nachbar.shape, isNull);
  });

  testWidgets('ein unbekannter Schlüssel ändert nichts', (tester) async {
    await zeige(tester, hervorheben: 'gibtesnicht');
    expect(find.text(datum), findsNothing);
  });
}
