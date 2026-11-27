import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/zusammenfuegen/zusammenfuegen.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/zusammenfuegen_dienst.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/selection_action_bar.dart';
import 'package:photo_vault/widgets/zusammenfuegen_dialog.dart';

/// Die Einträge in der Auswahlleiste und der Dialog des Zusammenfügens
/// (#498).
void main() {
  Widget leiste({void Function(Fuegeart)? zusammenfuegen}) => MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppTexte.localizationsDelegates,
    supportedLocales: AppTexte.supportedLocales,
    home: Scaffold(
      body: Stack(
        children: [
          SelectionActionBar(
            count: 3,
            onClear: () {},
            onFavorite: () {},
            onAddToAlbum: () {},
            onTag: () {},
            onSetRating: () {},
            onSetColorLabel: () {},
            onEditMetadata: () {},
            onExport: () {},
            onDelete: () {},
            onZusammenfuegen: zusammenfuegen,
          ),
        ],
      ),
    ),
  );

  testWidgets('die Auswahlleiste bietet HDR und Panorama an', (tester) async {
    tester.view.physicalSize = const Size(2400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Fuegeart? gewaehlt;
    await tester.pumpWidget(leiste(zusammenfuegen: (a) => gewaehlt = a));
    await tester.tap(find.byIcon(Icons.layers_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Zu HDR zusammenfügen …'), findsOneWidget);
    expect(find.text('Zu Panorama zusammenfügen …'), findsOneWidget);
    await tester.tap(find.text('Zu Panorama zusammenfügen …'));
    await tester.pumpAndSettle();
    expect(gewaehlt, Fuegeart.panorama);
  });

  testWidgets('Gegenprobe: ohne Rückruf kein Eintrag', (tester) async {
    tester.view.physicalSize = const Size(2400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(leiste());
    expect(find.byIcon(Icons.layers_outlined), findsNothing);
  });

  group('Dialog', () {
    late AppDatabase db;
    late LibraryState library;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      library = LibraryState()..db = db;
      Meldungsdienst.zentral.alleSchliessen();
      for (final (id, typ) in [
        ('a', 'IMAGE'),
        ('b', 'IMAGE'),
        ('c', 'IMAGE'),
        ('v', 'VIDEO'),
      ]) {
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: id,
                originalFileName: '$id.jpg',
                relativePath: 'o/$id.jpg',
                checksum: 'pruef-$id',
                type: typ,
                fileCreatedAt: DateTime(2024, 1, 1, 12, 0, id.codeUnitAt(0)),
                importedAt: DateTime(2024),
              ),
            );
      }
    });
    tearDown(() => db.close());

    Future<BuildContext> oeffne(WidgetTester tester) async {
      late BuildContext kontext;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Builder(
            builder: (context) {
              kontext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return kontext;
    }

    testWidgets('zeigt Anzahl, Ausgelassenes und Optionen; Abbrechen reiht '
        'nichts ein', (tester) async {
      final kontext = await oeffne(tester);
      await tester.runAsync(() async {
        // Die Datenbank antwortet ausserhalb der künstlichen Zeit.
        starteZusammenfuegen(kontext, library, [
          'a',
          'b',
          'c',
          'v',
        ], Fuegeart.panorama);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Zu Panorama zusammenfügen'), findsOneWidget);
      expect(find.textContaining('3 Aufnahmen eines Schwenks'), findsOneWidget);
      expect(
        find.textContaining('Eine ausgewählte Aufnahme bleibt außen vor'),
        findsOneWidget,
      );
      expect(
        find.text('Auf das größte volle Rechteck zuschneiden'),
        findsOneWidget,
      );
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(library.lauf(zusammenfuegenSchluessel), isNull);
    });

    testWidgets('zu wenige geeignete Fotos: Hinweis statt Dialog', (
      tester,
    ) async {
      final kontext = await oeffne(tester);
      await tester.runAsync(() async {
        starteZusammenfuegen(kontext, library, ['a', 'v'], Fuegeart.hdr);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final t = lookupAppTexte(const Locale('de'));
      expect(
        Meldungsdienst.zentral.sichtbare.map((m) => m.text),
        contains(t.zusfAnzahl(2, 9)),
      );
    });
  });
}
