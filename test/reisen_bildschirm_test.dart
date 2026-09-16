import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/reise_detail_screen.dart';
import 'package:photo_vault/screens/laenderliste_screen.dart';
import 'package:photo_vault/screens/reisen_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/reverse_geocoder.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/ortskachel.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/routenkarte.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';

/// Der Weg vom Vorschlag zur bestätigten Reise.
///
/// Die Erkennung ist in reisen_test.dart geprüft, die Datenbank in
/// reisen_db_test.dart. Hier geht es um den Weg dazwischen — den, den
/// Tests, die die Rechnung unmittelbar aufrufen, nicht sehen: Wird der
/// Vorschlag angezeigt, führt der Knopf zur Rückfrage, und steht danach
/// wirklich eine Reise in der Datenbank?
Future<ReverseGeocoder> _geokodierer(Directory wurzel) async {
  final staedte = File(p.join(wurzel.path, 'cities1000.txt'));
  await staedte.writeAsString(
    '2950159\tBerlin\tBerlin\t\t52.52437\t13.41053\tP\tPPLC\tDE\t\t16\t\t\t\t3426354\t\t74\tEurope/Berlin\t2023\n'
    '3169070\tRoma\tRoma\t\t41.89193\t12.51133\tP\tPPLC\tIT\t\t07\tRM\t\t\t2318895\t\t20\tEurope/Rome\t2023\n',
  );
  final regionen = File(p.join(wurzel.path, 'admin1CodesASCII.txt'));
  await regionen.writeAsString(
      'DE.16\tBerlin\tBerlin\t2950157\nIT.07\tLazio\tLazio\t3174976\n');
  final laender = File(p.join(wurzel.path, 'countryInfo.txt'));
  await laender.writeAsString(
    '# Kopfzeile\n'
    'DE\tDEU\t276\tDE\tGermany\tBerlin\t357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\t\t\n'
    'IT\tITA\t380\tIT\tItaly\tRom\t301230\t60431283\tEU\t.it\tEUR\tEuro\t39\t\t\tit-IT\t3175395\t\t\n'
    'FR\tFRA\t250\tFR\tFrance\tParis\t547030\t67059887\tEU\t.fr\tEUR\tEuro\t33\t\t\tfr-FR\t3017382\t\t\n'
    'ES\tESP\t724\tES\tSpain\tMadrid\t504782\t46723749\tEU\t.es\tEUR\tEuro\t34\t\t\tes-ES\t2510769\t\t\n',
  );
  return ReverseGeocoder.loadFromFiles(
      citiesFile: staedte, admin1File: regionen, countryFile: laender);
}

void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_reisen_');
    db = AppDatabase(NativeDatabase.memory());
    final paths =
        await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths)
      // Ein winziger GeoNames-Auszug: Ohne ihn gibt es keine Laenderzahl,
      // gegen die sich zaehlen liesse.
      ..geocoder = await _geokodierer(tempRoot);

    Future<void> aufnahme(String id, DateTime zeit, double b, double l,
            String stadt, String land) =>
        db.into(db.assets).insert(AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: zeit,
              importedAt: DateTime(2024),
              latitude: Value(b),
              longitude: Value(l),
              locationCity: Value(stadt),
              locationCountry: Value(land),
            ));

    // Hamburg als Wohnort: sechzig verschiedene Tage.
    for (var t = 0; t < 60; t++) {
      await aufnahme('h$t', DateTime(2024, 1, 1).add(Duration(days: t)), 53.55,
          9.99, 'Hamburg', 'Germany');
    }
    // Sechs Tage Rom, je vier Aufnahmen.
    for (var t = 0; t < 6; t++) {
      for (var i = 0; i < 4; i++) {
        await aufnahme('r$t-$i',
            DateTime(2024, 6, 3, 9, i * 10).add(Duration(days: t)), 41.90,
            12.50, 'Roma', 'Italy');
      }
    }
  });

  tearDown(() async {
    // Der Meldungsdienst ist ein Einzelstueck – was hier stehen
    // bleibt, steht im naechsten Test noch da.
    melde.verlaufLeeren();
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      // Der Meldungsstapel gehoert dazu: Seit der Meldungszentrale
      // erscheinen Meldungen dort und nicht mehr als SnackBar im
      // Scaffold.
      builder: (context, kind) => mitMeldungen(kind),
      home: ReisenScreen(library: library),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('der Vorschlag steht da, bevor jemand etwas eintippt',
      (tester) async {
    await zeige(tester);
    expect(find.text('Roma'), findsOneWidget);
    // Zeitraum, Nächte und Zahl der Aufnahmen in einer Zeile.
    expect(find.textContaining('5 Nächte'), findsOneWidget);
    expect(find.textContaining('24 Aufnahmen'), findsOneWidget);
    expect(find.text('War eine Reise'), findsOneWidget);
  });

  testWidgets('vom Vorschlag zur bestaetigten Reise', (tester) async {
    await zeige(tester);
    await tester.tap(find.text('War eine Reise'));
    await tester.pumpAndSettle();

    // Der vorgeschlagene Name steht schon im Feld – meistens stimmt er.
    expect(find.text('Reise benennen'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Roma');
    await tester.enterText(find.byType(TextField), 'Rom im Juni');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    final reisen = await db.alleReisen();
    expect(reisen.single.name, 'Rom im Juni');
    expect(await db.zugeordneteReiseAufnahmen(), hasLength(24));

    // Und der Vorschlag ist weg, weil seine Aufnahmen jetzt zugeordnet sind.
    expect(find.text('War eine Reise'), findsNothing);
    expect(find.text('Rom im Juni'), findsOneWidget);
  });

  testWidgets('abgelehnt heisst abgelehnt', (tester) async {
    // Ein Vorschlag, den man dreimal wegwischen muss, ist eine
    // Belaestigung.
    await zeige(tester);
    await tester.tap(find.text('Keine Reise'));
    await tester.pumpAndSettle();
    expect(find.text('Roma'), findsNothing);
    expect(await db.verworfeneReisevorschlaege(), hasLength(1));

    // Auch nach erneutem Suchen.
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.text('Roma'), findsNothing);
  });

  testWidgets('eine bestaetigte Reise laesst sich oeffnen', (tester) async {
    await zeige(tester);
    await tester.tap(find.text('War eine Reise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Roma'));
    await tester.pumpAndSettle();
    expect(find.byType(ReiseDetailScreen), findsOneWidget);
    expect(find.text('Besuchte Orte'), findsOneWidget);
    // Der Ort steht als Chip und als Titel – deshalb mehrfach.
    expect(find.text('Roma'), findsWidgets);
  });

  testWidgets('zwei Reisen lassen sich zu einer zusammenfuehren',
      (tester) async {
    // **Warum es das braucht.** Die Erkennung trennt bei mehr als zwei
    // Tagen ohne Aufnahme. Bei einem Urlaub ist das richtig; ein
    // zweimonatiger Auslandseinsatz zerfiel dadurch in vier Vorschlaege
    // von 25, 63, 89 und 20 Bildern.
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: 'Einsatz',
        von: DateTime(2024, 6, 3, 9),
        bis: DateTime(2024, 6, 4, 9),
        angelegtAm: DateTime(2024, 7, 1),
      ),
      ['r0-0', 'r0-1'],
    );
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r2',
        name: 'Zweiter Teil',
        von: DateTime(2024, 6, 8, 9),
        bis: DateTime(2024, 6, 8, 9),
        angelegtAm: DateTime(2024, 7, 1),
      ),
      ['r5-0', 'r5-1'],
    );
    await zeige(tester);
    expect(find.text('Einsatz'), findsOneWidget);
    expect(find.text('Zweiter Teil'), findsOneWidget);

    // Das Menue der Reise, die stehenbleiben soll – die Kachel traegt
    // es oben rechts.
    final kachel = find.ancestor(
        of: find.text('Einsatz'),
        matching: find.byType(Reisekachel));
    await tester.tap(find.descendant(
        of: kachel, matching: find.byType(PopupMenuButton<Kachelbefehl>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zusammenführen').last);
    await tester.pumpAndSettle();

    // Die andere Reise steht zur Wahl, die eigene nicht.
    expect(find.widgetWithText(CheckboxListTile, 'Zweiter Teil'),
        findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Einsatz'), findsNothing,
        reason: 'in sich selbst kann nichts aufgehen');

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Zweiter Teil'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Zusammenführen'));
    await tester.pumpAndSettle();

    expect(find.text('Zweiter Teil'), findsNothing);
    expect(find.text('Einsatz'), findsOneWidget);
    final uebrig = await db.alleReisen();
    expect(uebrig, hasLength(1));
    expect(await db.aufnahmenDerReise('r1'), hasLength(4));
  });

  testWidgets('die Art der Reise steht dabei und laesst sich aendern',
      (tester) async {
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: 'Einsatz',
        von: DateTime(2024, 6, 3, 9),
        bis: DateTime(2024, 6, 4, 9),
        angelegtAm: DateTime(2024, 7, 1),
      ),
      ['r0-0'],
    );
    await zeige(tester);
    await tester.tap(find.text('Einsatz'));
    await tester.pumpAndSettle();

    // Vorbelegt ist „Reise" – was jede bestehende der Sache nach war.
    expect(find.widgetWithText(ActionChip, 'Reise'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Reise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unternehmung'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ActionChip, 'Unternehmung'), findsOneWidget);
    expect((await db.alleReisen()).single.art, 'unternehmung');
  });

  testWidgets('eine Notiz laesst sich schreiben und wieder loeschen',
      (tester) async {
    // „Bewertung, Notizen, Tags" gab es bisher je Foto, nicht je Reise.
    await zeige(tester);
    await tester.tap(find.text('War eine Reise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roma'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.notes_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Mit dem Nachtzug hin.');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Mit dem Nachtzug hin.'), findsOneWidget);

    // Leerer Text heisst „keine Notiz" – so nimmt man sie wieder weg.
    await tester.tap(find.byIcon(Icons.notes_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Mit dem Nachtzug hin.'), findsNothing);
    expect((await db.alleReisen()).single.notiz, isNull);
  });

  testWidgets('die Reiseansicht zeigt Route und Tageskapitel',
      (tester) async {
    await zeige(tester);
    await tester.tap(find.text('War eine Reise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roma'));
    await tester.pumpAndSettle();

    // Sechs Tage, sechs Kapitel – ein durchgehendes Raster von 24 Bildern
    // beantwortet die Frage nicht, die man an eine Reise stellt. Gezählt
    // wird nicht auf sechs: Die Kapitel weiter unten sind noch gar nicht
    // gebaut, und ein Test, der das übersieht, prüft die Bildschirmhöhe
    // statt die Gliederung.
    expect(find.text('Montag, 3. Juni 2024 · Roma'), findsOneWidget);
    expect(find.textContaining('4 Aufnahmen'), findsWidgets);

    // Alle Aufnahmen liegen an derselben Stelle – dann gibt es keine
    // Strecke, und das steht auch da.
    expect(find.text('Ohne verortete Aufnahme gibt es keine Strecke.'),
        findsOneWidget);

    // Und das letzte Kapitel ist erreichbar.
    await tester.scrollUntilVisible(
        find.text('Samstag, 8. Juni 2024 · Roma'), 300);
  });

  testWidgets('bei mehreren Orten wird eine Strecke gezeichnet',
      (tester) async {
    // Florenz dazu: Erst wenn sich die Orte unterscheiden, gibt es eine
    // Linie zu zeichnen.
    for (var i = 0; i < 4; i++) {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'f$i',
            originalFileName: 'f$i.jpg',
            relativePath: 'originals/f$i.jpg',
            checksum: 'pruef-f$i',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2024, 6, 5, 14, i * 10),
            importedAt: DateTime(2024),
            latitude: const Value(43.77),
            longitude: const Value(11.26),
            locationCity: const Value('Firenze'),
            locationCountry: const Value('Italy'),
          ));
    }
    await zeige(tester);
    await tester.tap(find.text('War eine Reise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roma – Firenze'));
    await tester.pumpAndSettle();

    expect(find.text('Route'), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(find.text('Ohne verortete Aufnahme gibt es keine Strecke.'),
        findsNothing);
  });

  testWidgets('ein langer Druck macht ein Bild zum Titelbild', (tester) async {
    await zeige(tester);
    await tester.tap(find.text('War eine Reise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roma'));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(AssetThumbnailTile).first);
    await tester.pumpAndSettle();
    // Ein Menue und keine stille Aenderung: Eine Geste, die etwas tut,
    // ohne es zu sagen, findet man nur durch Zufall wieder.
    await tester.tap(find.text('Als Titelbild'));
    await tester.pumpAndSettle();
    // Im Verlauf und nicht auf dem Schirm: `pumpAndSettle` laesst den
    // ablaufenden Balken der Meldung bis zum Ende laufen, die Karte ist
    // danach planmaessig weg.
    expect(melde.verlauf.first.text, 'Titelbild gesetzt.');
    expect((await db.alleReisen()).single.titelbildAssetId, isNotNull);
  });

  testWidgets('der Laenderzaehler steht ueber den Reisen', (tester) async {
    // „41 von 252 Laendern" ist der Zaehler, den andere Tagebuecher von
    // Hand fuettern lassen. Hier stand er laengst in der Datenbank.
    await zeige(tester);
    expect(find.text('2 von 4 Ländern'), findsOneWidget);
    // Zwei Orte, aber keine Region: Die Aufnahmen dieses Tests tragen
    // keine, und das kommt auch echt vor – bei Stadtstaaten und
    // Kleinstaaten laesst die Umkehr-Geokodierung sie leer. Ein Ort ohne
    // Region bleibt trotzdem ein besuchter Ort.
    expect(find.textContaining('2 Orte'), findsOneWidget);
    expect(find.textContaining('0 Regionen'), findsOneWidget);
  });

  testWidgets('der Zaehler fuehrt zur Laenderliste', (tester) async {
    await zeige(tester);
    await tester.tap(find.text('2 von 4 Ländern'));
    await tester.pumpAndSettle();
    expect(find.byType(LaenderlisteScreen), findsOneWidget);
    // Alle vier Laender des Datensatzes, nicht nur die besuchten: Ein
    // Zaehler „2 von 4" ohne die anderen zwei waere eine halbe Auskunft.
    for (final name in ['Deutschland', 'Italien', 'Frankreich', 'Spanien']) {
      expect(find.text(name), findsOneWidget);
    }
    // Und die Zahl, gegen die gezaehlt wird, wird erklaert statt
    // behauptet.
    expect(find.textContaining('195 souveränen Staaten'), findsOneWidget);
  });

  testWidgets('ohne verortete Aufnahmen erklaert der Bildschirm sich selbst',
      (tester) async {
    await db.delete(db.assets).go();
    await zeige(tester);
    expect(find.textContaining('erkennt sie'), findsOneWidget);
  });

  testWidgets('jeder Aufenthaltsort bekommt eine Bildmarke auf der Karte',
      (tester) async {
    // Punkt 5 der Wunschliste: nicht nackte Kreise, sondern das Bild, das
    // dort entstanden ist – und die Zahl, wie viele es sind.
    //
    // Rom liegt schon aus dem setUp bereit (24 Aufnahmen an sechs Tagen).
    // Dazu ein Bild aus Florenz, 230 km entfernt: Das muss ein zweiter
    // Ort werden, sonst faende die Zusammenfassung ueberhaupt keine
    // Grenze.
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: 'flo',
          originalFileName: 'flo.jpg',
          relativePath: 'originals/flo.jpg',
          checksum: 'pruef-flo',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024, 6, 12, 10),
          importedAt: DateTime(2024),
          latitude: const Value(43.7696),
          longitude: const Value(11.2558),
          locationCity: const Value('Firenze'),
          locationCountry: const Value('Italy'),
        ));
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: 'Italien',
        von: DateTime(2024, 6, 3),
        bis: DateTime(2024, 6, 12),
        angelegtAm: DateTime(2024, 7, 1),
      ),
      [
        for (var t = 0; t < 6; t++)
          for (var i = 0; i < 4; i++) 'r$t-$i',
        'flo',
      ],
    );

    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      // Der Meldungsstapel gehoert dazu: Seit der Meldungszentrale
      // erscheinen Meldungen dort und nicht mehr als SnackBar im
      // Scaffold.
      builder: (context, kind) => mitMeldungen(kind),
      home: ReiseDetailScreen(
          library: library, reise: (await db.alleReisen()).single),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Roma · 24 Aufnahmen'), findsOneWidget);
    expect(find.byTooltip('Firenze · eine Aufnahme'), findsOneWidget);
    // Die Zahl steht an der Marke – aber nur, wo mehr als eine ist.
    expect(find.text('24'), findsOneWidget);
  });

  testWidgets('ein Vorschlag ueber zwei Laender heisst deutsch',
      (tester) async {
    // **Der Datensatz kennt Laender nur englisch** – so stehen sie in der
    // Datenbank, und dort gehoeren sie auch hin: Sie sind der Schluessel,
    // ueber den Aufnahme und Katalog zusammenfinden. Der Vorschlag heisst
    // aber nach dem Land, und „Italy – France" ist in einer deutschen
    // Oberflaeche kein Name, sondern eine Panne.
    //
    // Zwei Laender, weil der Name erst dann aus ihnen gebildet wird –
    // sonst heisst ein Vorschlag nach seinen Staedten.
    for (var t = 0; t < 3; t++) {
      for (var i = 0; i < 4; i++) {
        await db.into(db.assets).insert(AssetsCompanion.insert(
              id: 'p$t-$i',
              originalFileName: 'p$t-$i.jpg',
              relativePath: 'originals/p$t-$i.jpg',
              checksum: 'pruef-p$t-$i',
              type: 'IMAGE',
              fileCreatedAt:
                  DateTime(2024, 6, 9, 9, i * 10).add(Duration(days: t)),
              importedAt: DateTime(2024),
              latitude: const Value(48.85),
              longitude: const Value(2.35),
              locationCity: const Value('Paris'),
              locationCountry: const Value('France'),
            ));
      }
    }
    await zeige(tester);
    expect(find.text('Italien – Frankreich'), findsOneWidget);
    expect(find.text('Italy – France'), findsNothing,
        reason: 'der englische Schluessel gehoert nicht auf den Schirm');
  });

  group('Eine GPX-Spur an einer Reise', () {
    Future<String> reiseMitSpur({bool mitSpur = true}) async {
      // Ein zweiter Ort, 230 km entfernt: Ohne ihn liegen alle 24
      // Aufnahmen in Rom innerhalb eines Kilometers, es gibt gar keine
      // Route – und damit auch keine Karte, auf der eine Spur liegen
      // koennte.
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'flo',
            originalFileName: 'flo.jpg',
            relativePath: 'originals/flo.jpg',
            checksum: 'pruef-flo',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2024, 6, 8, 10),
            importedAt: DateTime(2024),
            latitude: const Value(43.7696),
            longitude: const Value(11.2558),
            locationCity: const Value('Firenze'),
            locationCountry: const Value('Italy'),
          ));
      await db.reiseAnlegen(
        ReisenCompanion.insert(
          id: 'r1',
          name: 'Rom im Juni',
          von: DateTime(2024, 6, 3),
          bis: DateTime(2024, 6, 8),
          angelegtAm: DateTime(2024, 7, 1),
        ),
        [
          for (var t = 0; t < 6; t++)
            for (var i = 0; i < 4; i++) 'r$t-$i',
          'flo',
        ],
      );
      if (mitSpur) {
        await db.spurAnlegen(
          SpurenCompanion.insert(
            id: 's1',
            name: 'tag1.gpx',
            quelle: '/tmp/tag1.gpx',
            reiseId: const Value('r1'),
            punktzahl: 12,
            laengeKm: 7.4,
            angelegtAm: DateTime(2024, 7, 1),
          ),
          [
            for (var i = 0; i < 12; i++)
              SpurpunkteCompanion.insert(
                spurId: 's1',
                nummer: i,
                breite: 41.89 + i / 500,
                laenge: 12.49 + i / 500,
              ),
          ],
        );
      }
      return 'r1';
    }

    Future<void> zeigeReise(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        builder: (context, kind) => mitMeldungen(kind),
        home: ReiseDetailScreen(
            library: library, reise: (await db.alleReisen()).single),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('sie liegt als eigene Linie auf der Karte', (tester) async {
      await reiseMitSpur();
      await zeigeReise(tester);
      final karte = tester.widget<Routenkarte>(find.byType(Routenkarte));
      expect(karte.spuren, hasLength(1),
          reason: 'die gemessene Linie gehoert neben die geratene');
      expect(karte.spuren.first, hasLength(12));
      // Und sie steht mit Namen darunter - sonst waere nicht zu sehen,
      // welche Datei da liegt.
      expect(find.textContaining('tag1.gpx'), findsOneWidget);
    });

    testWidgets('ohne Spur liegt auch keine Linie da', (tester) async {
      await reiseMitSpur(mitSpur: false);
      await zeigeReise(tester);
      final karte = tester.widget<Routenkarte>(find.byType(Routenkarte));
      expect(karte.spuren, isEmpty);
      expect(find.textContaining('.gpx'), findsNothing);
    });

    testWidgets('der Knopf daneben nimmt sie wieder weg', (tester) async {
      await reiseMitSpur();
      await zeigeReise(tester);
      await tester.tap(find.byTooltip('Spur entfernen'));
      await tester.pumpAndSettle();
      expect(await db.spurenDerReise('r1'), isEmpty);
      expect(await db.punkteDerSpur('s1'), isEmpty);
      expect(find.textContaining('tag1.gpx'), findsNothing);
    });
  });
}
