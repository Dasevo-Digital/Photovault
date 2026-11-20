import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/original_referenzen.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/speicherschutz_screen.dart';
import 'package:photo_vault/state/library_state.dart';

void main() {
  late Directory temp;
  late AppDatabase db;
  late LibraryState library;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_schutz_oberflaeche_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(temp);
    paths.referenzen = OriginalReferenzen(File('${temp.path}/orte.json'));
    library = LibraryState()
      ..db = db
      ..paths = paths;
  });
  tearDown(() async {
    library.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });
  for (final breite in [420.0, 1100.0]) {
    testWidgets(
      'Sicherungsassistent verlangt Ziele und Bestätigung bei Breite $breite',
      (tester) async {
        tester.view.physicalSize = Size(breite, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('de'),
            localizationsDelegates: AppTexte.localizationsDelegates,
            supportedLocales: AppTexte.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SpeicherschutzScreen(library: library),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Lokalen Speicher freigeben'), findsNothing);
        final knopf = find.widgetWithText(
          FilledButton,
          'Inhalte prüfen und Plan erstellen',
        );
        await tester.scrollUntilVisible(
          find.text('Inhalte prüfen und Plan erstellen'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.widget<FilledButton>(knopf).onPressed, isNull);
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
