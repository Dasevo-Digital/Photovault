import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/aktivitaet_detail_screen.dart';
import 'package:photo_vault/services/aktivitaeten.dart';
import 'package:photo_vault/services/gpx.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';
import 'package:photo_vault/widgets/hoehenprofil.dart';
import 'package:photo_vault/widgets/routenkarte.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/zuordnung_auswahlleiste.dart';

/// Eine einzelne Aktivität am Bildschirm.
///
/// Der Punkt, um den es hier geht: **Dauer und Strecke stehen nicht in
/// der Datenbank.** Sie werden aus den Aufnahmen gerechnet – wer ein
/// Bild herausnimmt, soll die Zahl sofort ohne es sehen.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_aktd_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    melde.verlaufLeeren();
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> aufnahme(String id, int minuten, double kmOst,
          {String? stadt}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 6, 14, 9, minuten),
            importedAt: DateTime(2026),
            latitude: const Value(52.37),
            longitude: Value(9.73 + kmOst / 68.0),
            locationCity: Value(stadt),
          ));

  Future<AktivitaetenData> anlegen({
    Aktivitaetsart art = Aktivitaetsart.wanderung,
    String? reiseId,
  }) async {
    for (var i = 0; i < 5; i++) {
      await aufnahme('w$i', i * 30, i * 2.0, stadt: 'Goslar');
    }
    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: 'k1',
        name: 'Brocken',
        art: art.kennung,
        von: DateTime(2026, 6, 14, 9),
        bis: DateTime(2026, 6, 14, 11),
        reiseId: Value(reiseId),
        angelegtAm: DateTime(2026, 7, 1),
      ),
      ['w0', 'w1', 'w2', 'w3', 'w4'],
    );
    return (await db.alleAktivitaeten()).single;
  }

  Future<void> zeige(WidgetTester tester, AktivitaetenData k) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      builder: (context, kind) => mitMeldungen(kind),
      home: AktivitaetDetailScreen(library: library, aktivitaet: k),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Kopfzeile mit Art, Dauer, Strecke und Zahl', (tester) async {
    await zeige(tester, await anlegen());
    expect(find.textContaining('Wanderung'), findsWidgets);
    expect(find.textContaining('2 h 0 min'), findsOneWidget);
    expect(find.textContaining('8,0 km'), findsOneWidget);
    expect(find.textContaining('5 Fotos'), findsOneWidget);
  });

  testWidgets('die Strecke kommt aus den Bildern, nicht aus der Tabelle',
      (tester) async {
    final k = await anlegen();
    // Ein Bild aus der Aktivität nehmen – die Zeile muss kürzer werden,
    // ohne dass jemand eine gespeicherte Zahl nachführt.
    await (db.delete(db.aktivitaetAufnahmen)
          ..where((t) => t.assetId.equals('w4')))
        .go();
    await zeige(tester, k);
    expect(find.textContaining('6,0 km'), findsOneWidget);
    expect(find.textContaining('4 Fotos'), findsOneWidget);
  });

  testWidgets('eine Strecke bekommt eine Karte', (tester) async {
    await zeige(tester, await anlegen());
    expect(find.byType(Routenkarte), findsOneWidget);
  });

  testWidgets('ein einzelnes Bild bekommt keine Karte, sondern einen Satz',
      (tester) async {
    await aufnahme('e1', 0, 0);
    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: 'k2',
        name: 'Kurz',
        art: Aktivitaetsart.besichtigung.kennung,
        von: DateTime(2026, 6, 14, 9),
        bis: DateTime(2026, 6, 14, 10),
        angelegtAm: DateTime(2026, 7, 1),
      ),
      ['e1'],
    );
    await zeige(tester, (await db.alleAktivitaeten()).single);
    expect(find.byType(Routenkarte), findsNothing);
    expect(find.textContaining('Zu wenige verortete Aufnahmen'),
        findsOneWidget);
  });

  testWidgets('die Art lässt sich ändern', (tester) async {
    // Geraten wird sie beim Erkennen; entschieden wird sie hier.
    await zeige(tester, await anlegen());
    await tester.tap(find.byIcon(Icons.category_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Radtour'));
    await tester.pumpAndSettle();
    expect(Aktivitaetsart.aus((await db.alleAktivitaeten()).single.art),
        Aktivitaetsart.radtour);
    expect(find.byIcon(Icons.directions_bike), findsWidgets);
  });

  testWidgets('umbenennen und Notiz', (tester) async {
    await zeige(tester, await anlegen());
    await tester.tap(find.byIcon(Icons.drive_file_rename_outline));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Auf den Brocken');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect((await db.alleAktivitaeten()).single.name, 'Auf den Brocken');

    await tester.tap(find.byIcon(Icons.notes_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bei Nebel losgegangen.');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Bei Nebel losgegangen.'), findsOneWidget);
  });

  testWidgets('löschen nimmt die Aktivität, nicht die Fotos', (tester) async {
    await zeige(tester, await anlegen());
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Aktivität löschen'));
    await tester.pumpAndSettle();

    expect(await db.alleAktivitaeten(), isEmpty);
    // Die Bilder bleiben, wo sie sind – eine Aktivität ist eine Sicht
    // auf Bilder, kein Behälter für sie.
    expect(await db.assetById('w0'), isNotNull);
  });

  testWidgets('gehört sie zu einer Reise, steht das im Kopf', (tester) async {
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: 'Harz',
        von: DateTime(2026, 6, 13),
        bis: DateTime(2026, 6, 16),
        angelegtAm: DateTime(2026, 7, 1),
      ),
      const [],
    );
    await zeige(tester, await anlegen(reiseId: 'r1'));
    expect(find.text('Gehört zu: Harz'), findsOneWidget);
  });

  group('mit aufgezeichneter Spur', () {
    /// Legt eine Spur an der Aktivität an – zwanzig Punkte über zwei
    /// Kilometer, hundert Höhenmeter hinauf.
    Future<void> spur({bool hoehen = true}) async {
      final roh = <Rohpunkt>[
        for (var i = 0; i < 20; i++)
          (
            zeit: DateTime.utc(2026, 6, 14, 9).add(Duration(minutes: i * 5)),
            breite: 52.37,
            laenge: 9.73 + i * 0.1 / 68.0,
            hoehe: hoehen ? 300.0 + i * 5 : null,
          ),
      ];
      final z = spurkennzahlen(roh);
      await db.spurAnlegen(
        SpurenCompanion.insert(
          id: 's1',
          name: 'brocken.gpx',
          quelle: '/tmp/brocken.gpx',
          aktivitaetId: const Value('k1'),
          von: Value(z.von),
          bis: Value(z.bis),
          punktzahl: z.punktzahl,
          laengeKm: z.laengeKm,
          aufstieg: Value(z.aufstieg),
          abstieg: Value(z.abstieg),
          angelegtAm: DateTime(2026, 7, 1),
        ),
        [
          for (final (i, p) in roh.indexed)
            SpurpunkteCompanion.insert(
              spurId: 's1',
              nummer: i,
              breite: p.breite,
              laenge: p.laenge,
              hoehe: Value(p.hoehe),
              zeit: Value(p.zeit),
            ),
        ],
      );
    }

    testWidgets('die Kennzahlen der Spur stehen da', (tester) async {
      final k = await anlegen();
      await spur();
      await zeige(tester, k);
      expect(find.text('Aufgezeichnete Spur'), findsOneWidget);
      expect(find.textContaining('▲'), findsOneWidget);
      expect(find.textContaining('20 Punkte'), findsOneWidget);
    });

    testWidgets('ein Profil wird gezeichnet', (tester) async {
      final k = await anlegen();
      await spur();
      await zeige(tester, k);
      expect(find.byType(Hoehenprofil), findsOneWidget);
      expect(find.text('Höhenprofil'), findsOneWidget);
    });

    testWidgets('ohne Höhen steht ein Satz statt eines Profils',
        (tester) async {
      // Eine Datei ohne `<ele>` ist kein Fehler – aber ein Profil aus
      // erfundenen Nullen wäre einer.
      final k = await anlegen();
      await spur(hoehen: false);
      await zeige(tester, k);
      expect(find.byType(Hoehenprofil), findsNothing);
      expect(find.textContaining('führt keine Höhen'), findsOneWidget);
      // Die Länge steht trotzdem da, nur ohne Auf- und Abstieg.
      expect(find.textContaining('keine Höhenangaben'), findsOneWidget);
    });

    testWidgets('die Karte bekommt Spur und Marke', (tester) async {
      final k = await anlegen();
      await spur();
      await zeige(tester, k);
      final karte =
          tester.widget<Routenkarte>(find.byType(Routenkarte));
      expect(karte.spuren, hasLength(1));
      expect(karte.spuren.first, hasLength(20));
      // Solange niemand auf das Profil zeigt, gibt es keine Marke.
      expect(karte.stelle, isNull);
    });

    testWidgets('das Zeigen auf das Profil setzt die Marke auf der Karte',
        (tester) async {
      final k = await anlegen();
      await spur();
      await zeige(tester, k);

      final kasten = tester.getRect(find.byType(Hoehenprofil));
      final zeiger = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await zeiger.addPointer(location: Offset.zero);
      addTearDown(zeiger.removePointer);
      await zeiger.moveTo(kasten.center);
      await tester.pump();

      final karte = tester.widget<Routenkarte>(find.byType(Routenkarte));
      expect(karte.stelle, isNotNull);
      // Und zwar auf einem Punkt der Spur, nicht irgendwo dazwischen.
      final punkte = await db.punkteDerSpur('s1');
      expect(punkte.map((p) => p.laenge), contains(karte.stelle!.laenge));
    });

    testWidgets('die Spur lässt sich wieder entfernen', (tester) async {
      final k = await anlegen();
      await spur();
      await zeige(tester, k);
      await tester.tap(find.byIcon(Icons.wrong_location_outlined));
      await tester.pumpAndSettle();

      expect(await db.alleSpuren(), isEmpty);
      expect(await db.punkteDerSpur('s1'), isEmpty);
      expect(find.byType(Hoehenprofil), findsNothing);
      // Die Aktivität selbst bleibt.
      expect(await db.alleAktivitaeten(), hasLength(1));
    });

    testWidgets('ohne Spur steht der Knopf zum Hinzufügen da',
        (tester) async {
      await zeige(tester, await anlegen());
      expect(find.byIcon(Icons.route_outlined), findsOneWidget);
      expect(find.byIcon(Icons.wrong_location_outlined), findsNothing);
    });
  });

  group('Fotos auswaehlen und herausnehmen', () {
    testWidgets('ohne Auswahl gibt es keine Leiste', (tester) async {
      await zeige(tester, await anlegen());
      expect(find.byType(ZuordnungAuswahlleiste), findsNothing);
    });

    testWidgets('langer Druck waehlt aus und zeigt die Leiste',
        (tester) async {
      await zeige(tester, await anlegen());
      await tester.longPress(find.byType(AssetThumbnailTile).first);
      await tester.pumpAndSettle();
      expect(find.byType(ZuordnungAuswahlleiste), findsOneWidget);
      expect(find.text('1 ausgewählt'), findsOneWidget);
      expect(find.text('Aus der Aktivität entfernen'), findsOneWidget);
    });

    testWidgets('bei laufender Auswahl waehlt ein Tipp weitere dazu',
        (tester) async {
      await zeige(tester, await anlegen());
      await tester.longPress(find.byType(AssetThumbnailTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AssetThumbnailTile).at(1));
      await tester.pumpAndSettle();
      expect(find.text('2 ausgewählt'), findsOneWidget);
      // und wieder ab
      await tester.tap(find.byType(AssetThumbnailTile).at(1));
      await tester.pumpAndSettle();
      expect(find.text('1 ausgewählt'), findsOneWidget);
    });

    testWidgets('der Knopf nimmt sie wirklich aus der Aktivitaet',
        (tester) async {
      final k = await anlegen();
      await zeige(tester, k);
      await tester.longPress(find.byType(AssetThumbnailTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AssetThumbnailTile).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aus der Aktivität entfernen'));
      await tester.pumpAndSettle();

      final uebrig = await db.zuordnungenDerAktivitaet(k.id);
      expect(uebrig, hasLength(3));
      expect(uebrig, isNot(contains('w0')));
      expect(uebrig, isNot(contains('w1')));
      // Die Fotos selbst bleiben - herausnehmen ist kein Loeschen.
      expect(await db.select(db.assets).get(), hasLength(5));
      // Und die Kopfzeile rechnet sofort neu.
      expect(find.textContaining('3 Fotos'), findsOneWidget);
      expect(find.byType(ZuordnungAuswahlleiste), findsNothing);
    });

    testWidgets('eine gesperrte Zuordnung ueberlebt das Herausnehmen',
        (tester) async {
      // Der Fall, an dem der Fotowaehler schon einmal Zuordnungen
      // gekostet hat: `_aufnahmen` zeigt Gesperrtes nicht, die
      // Zuordnung besteht aber. Wer die Ausgangsmenge aus dem Bild
      // naehme, loeschte sie beim Neuschreiben mit.
      final k = await anlegen();
      await (db.update(db.assets)..where((t) => t.id.equals('w4')))
          .write(const AssetsCompanion(isLocked: Value(true)));
      await zeige(tester, k);
      expect(find.byType(AssetThumbnailTile), findsNWidgets(4));

      await tester.longPress(find.byType(AssetThumbnailTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aus der Aktivität entfernen'));
      await tester.pumpAndSettle();

      final uebrig = await db.zuordnungenDerAktivitaet(k.id);
      expect(uebrig, contains('w4'),
          reason: 'die gesperrte Zuordnung darf nicht mit verschwinden');
      expect(uebrig, hasLength(4));
    });

    testWidgets('Auswahl aufheben laesst alles stehen', (tester) async {
      final k = await anlegen();
      await zeige(tester, k);
      await tester.longPress(find.byType(AssetThumbnailTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Auswahl aufheben'));
      await tester.pumpAndSettle();
      expect(find.byType(ZuordnungAuswahlleiste), findsNothing);
      expect(await db.zuordnungenDerAktivitaet(k.id), hasLength(5));
    });

    testWidgets('der Knopf zum Hinzufuegen heisst auch so', (tester) async {
      // Bis hierher trug er ein Bibliothekssymbol zwischen sechs
      // anderen und wurde nicht gefunden.
      await zeige(tester, await anlegen());
      expect(find.byTooltip('Fotos hinzufügen'), findsOneWidget);
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
    });
  });
}
