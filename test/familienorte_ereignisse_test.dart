import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/familienorte_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// **Nur Ereignisse, keine verorteten Fotos** (PER-184).
///
/// „Orte der Familie“ öffnet auch dann, wenn nur Lebensereignisse einen
/// Ort haben. Die Karte entstand aber nur mit mindestens einer Fotomarke;
/// sonst stand „Keine Gruppe ausgewählt.“ da – obwohl es etwas zu zeigen
/// gab.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState bib;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_familienorte_');
    db = AppDatabase(NativeDatabase.memory());
    bib = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'lib')),
      );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('die Karte zeigt die Ereignismarke', (tester) async {
    const hochzeit = LebensereignisseData(
      id: 'e1',
      personId: 'p1',
      art: 'hochzeit',
      ort: 'Musterstadt',
      ortBreite: 50.1,
      ortLaenge: 8.6,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: FamilienorteScreen(
          library: bib,
          titel: 'Orte der Familie',
          orte: const [],
          ereignisse: [(ereignis: hochzeit, personName: 'Person A')],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Keine Gruppe ausgewählt.'), findsNothing);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byTooltip('Person A · Musterstadt'), findsOneWidget);
  });
}
