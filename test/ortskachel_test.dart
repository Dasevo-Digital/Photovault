import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/reisen_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/ortskachel.dart';

/// Die Kachel der Reise- und Aktivitätenübersicht.
///
/// **Was sie gegenüber der alten Zeile kann.** Die `ListTile` zeigte
/// Namen und Zeitraum. Wo etwas stattfand, stand nirgends – dabei ist
/// das die Frage, mit der man eine Reiseliste öffnet.
void main() {
  late Directory temp;
  late StoragePaths paths;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_kachel_');
    paths =
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'library')));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<AppTexte> texte(WidgetTester tester) async {
    late AppTexte t;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Builder(builder: (context) {
        t = AppTexte.of(context);
        return const SizedBox.shrink();
      }),
    ));
    return t;
  }

  Future<void> zeige(WidgetTester tester, Widget kind) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(body: kind),
    ));
    await tester.pumpAndSettle();
  }

  group('die Ortszeile', () {
    testWidgets('Ort, Region und Land in einer Zeile', (tester) async {
      final t = await texte(tester);
      expect(
        ortszeile(t, (
          ort: 'Rom',
          region: 'Latium',
          land: 'Italien',
          weitereOrte: 0,
          aufnahmen: 12
        ), sprache: 'de'),
        'Rom, Latium, Italien',
      );
    });

    testWidgets('ohne Ort gibt es keine Zeile', (tester) async {
      final t = await texte(tester);
      // Und nicht „Unbekannt": Das behauptete, es sei nachgesehen worden.
      // In Wahrheit trug keine Aufnahme eine Koordinate.
      expect(
        ortszeile(t, (
          ort: null,
          region: null,
          land: null,
          weitereOrte: 0,
          aufnahmen: 3
        ), sprache: 'de'),
        isNull,
      );
      expect(ortszeile(t, null, sprache: 'de'), isNull);
    });

    testWidgets('fehlende Region setzt kein Komma ins Leere', (tester) async {
      final t = await texte(tester);
      expect(
        ortszeile(t, (
          ort: 'Oslo',
          region: null,
          land: 'Norwegen',
          weitereOrte: 0,
          aufnahmen: 4
        ), sprache: 'de'),
        'Oslo, Norwegen',
      );
    });

    testWidgets('eine Region gleichen Namens steht nicht doppelt da',
        (tester) async {
      // Stadtstaaten: GeoNames führt Berlin als Ort UND als Region.
      // „Berlin, Berlin, Deutschland" sähe aus wie ein Fehler.
      final t = await texte(tester);
      expect(
        ortszeile(t, (
          ort: 'Berlin',
          region: 'Berlin',
          land: 'Deutschland',
          weitereOrte: 0,
          aufnahmen: 9
        ), sprache: 'de'),
        'Berlin, Deutschland',
      );
    });

    testWidgets('weitere Orte werden genannt', (tester) async {
      // Ohne diese Zahl sähe eine dreiwöchige Rundreise aus wie ein
      // Wochenende an einem Ort.
      final t = await texte(tester);
      final zeile = ortszeile(t, (
        ort: 'Rom',
        region: null,
        land: 'Italien',
        weitereOrte: 4,
        aufnahmen: 80
      ), sprache: 'de');
      expect(zeile, contains('Rom, Italien'));
      expect(zeile, contains('4'));
    });
  });

  group('die Kachel', () {
    testWidgets('zeigt Name, Kennzeichen, Zeitraum und Ort', (tester) async {
      await zeige(
        tester,
        Ortskachel(
          bild: null,
          paths: paths,
          symbol: Icons.luggage_outlined,
          name: 'Toskana',
          kennzeichen: '7 Nächte',
          zeitraum: '2024',
          ort: 'Florenz, Toskana, Italien',
          onTippen: () {},
        ),
      );
      expect(find.text('Toskana'), findsOneWidget);
      expect(find.text('7 Nächte'), findsOneWidget);
      expect(find.text('2024'), findsOneWidget);
      expect(find.text('Florenz, Toskana, Italien'), findsOneWidget);
      // Das Sinnbild steht auf der Fläche, weil kein Titelbild da ist -
      // eine leere graue Kachel sähe nach einem Ladefehler aus.
      expect(find.byIcon(Icons.luggage_outlined), findsWidgets);
    });

    testWidgets('ohne Ort bleibt die Ortszeile ganz weg', (tester) async {
      await zeige(
        tester,
        Ortskachel(
          bild: null,
          paths: paths,
          symbol: Icons.hiking,
          name: 'Hausrunde',
          kennzeichen: 'Wanderung',
          zeitraum: '3.6.2024',
          ort: null,
          onTippen: () {},
        ),
      );
      expect(find.text('Hausrunde'), findsOneWidget);
      expect(find.byIcon(Icons.place_outlined), findsNothing);
    });

    testWidgets('das Antippen öffnet', (tester) async {
      var geoeffnet = 0;
      await zeige(
        tester,
        Ortskachel(
          bild: null,
          paths: paths,
          symbol: Icons.luggage_outlined,
          name: 'Rom',
          kennzeichen: '3 Nächte',
          zeitraum: '2024',
          ort: 'Rom, Italien',
          onTippen: () => geoeffnet++,
        ),
      );
      await tester.tap(find.text('Rom'));
      await tester.pumpAndSettle();
      expect(geoeffnet, 1);
    });

    testWidgets('das ⋯-Menü führt aus, was drinsteht', (tester) async {
      var umbenannt = 0;
      await zeige(
        tester,
        Ortskachel(
          bild: null,
          paths: paths,
          symbol: Icons.luggage_outlined,
          name: 'Rom',
          kennzeichen: '3 Nächte',
          zeitraum: '2024',
          ort: null,
          onTippen: () {},
          befehle: [
            (
              symbol: Icons.drive_file_rename_outline,
              text: 'Umbenennen',
              tun: () => umbenannt++
            ),
          ],
        ),
      );
      await tester.tap(find.byType(PopupMenuButton<Kachelbefehl>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Umbenennen'));
      await tester.pumpAndSettle();
      expect(umbenannt, 1);
    });

    testWidgets('ohne Befehle steht kein Menüknopf da', (tester) async {
      await zeige(
        tester,
        Ortskachel(
          bild: null,
          paths: paths,
          symbol: Icons.hiking,
          name: 'Hausrunde',
          kennzeichen: 'Wanderung',
          zeitraum: '2024',
          ort: null,
          onTippen: () {},
        ),
      );
      expect(find.byType(PopupMenuButton<Kachelbefehl>), findsNothing);
    });
  });

  group('das Raster', () {
    testWidgets('legt im breiten Fenster mehrere Spalten nebeneinander',
        (tester) async {
      // Der Sinn des Rasters: Auf einem 1200 Punkte breiten Fenster
      // stehen drei Kacheln in einer Reihe, nicht drei untereinander.
      await zeige(
        tester,
        CustomScrollView(slivers: [
          Kachelraster(kacheln: [
            for (var i = 0; i < 6; i++)
              Ortskachel(
                key: ValueKey('k$i'),
                bild: null,
                paths: paths,
                symbol: Icons.luggage_outlined,
                name: 'Reise $i',
                kennzeichen: '1 Nacht',
                zeitraum: '2024',
                ort: null,
                onTippen: () {},
              ),
          ]),
        ]),
      );
      final erste = tester.getTopLeft(find.text('Reise 0'));
      final zweite = tester.getTopLeft(find.text('Reise 1'));
      expect(zweite.dy, erste.dy, reason: 'gleiche Reihe');
      expect(zweite.dx, greaterThan(erste.dx));
    });

    testWidgets('keine Kachel wird breiter als vorgesehen', (tester) async {
      // Ohne Obergrenze zöge eine einzelne Reise ihre Kachel über die
      // ganze Fensterbreite - ein Titelbild von 1200 Punkten Breite für
      // eine Zeile Text.
      await zeige(
        tester,
        CustomScrollView(slivers: [
          Kachelraster(kacheln: [
            Ortskachel(
              bild: null,
              paths: paths,
              symbol: Icons.luggage_outlined,
              name: 'Einzeln',
              kennzeichen: '1 Nacht',
              zeitraum: '2024',
              ort: null,
              onTippen: () {},
            ),
          ]),
        ]),
      );
      expect(tester.getSize(find.byType(Card)).width,
          lessThanOrEqualTo(kachelBreite));
    });
  });

  group('nichts läuft über', () {
    // **Der Fehler, den diese Gruppe verhindert.** Die Kachelhöhe steht
    // fest, damit die Reihen bündig sind. Feste Höhe und beliebig langer
    // Text vertragen sich aber nicht: Ein zweizeiliger Name neben einer
    // zweizeiligen Ortsangabe, dazu vergrösserte Systemschrift - und
    // Flutter zeichnet den roten Balken quer über die Kachel.
    //
    // Gefunden wurde er beim Nachrechnen, nicht beim Ansehen: Bei 340
    // Punkten Spaltenbreite kam der Inhalt auf 328 Punkte, die feste
    // Höhe stand auf 300. Im schmalen Testfenster fiel das nie auf.
    Future<void> raster(WidgetTester tester, double breite,
        double schrift) async {
      tester.view.physicalSize = Size(breite, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(schrift)),
          child: Scaffold(
            body: CustomScrollView(slivers: [
              Kachelraster(kacheln: [
                for (var i = 0; i < 4; i++)
                  Ortskachel(
                    key: ValueKey('k$i'),
                    bild: null,
                    paths: paths,
                    symbol: Icons.luggage_outlined,
                    // Lang genug für zwei Zeilen, beides.
                    name: 'Grosse Rundreise durch die Toskana im Sommer',
                    kennzeichen: '14 Nächte',
                    zeitraum: '2024–2025',
                    ort: 'Castelnuovo di Garfagnana, Toskana, '
                        'Italien · 11 weitere Orte',
                    onTippen: () {},
                    befehle: [
                      (
                        symbol: Icons.delete_outline,
                        text: 'Entfernen',
                        tun: () {}
                      ),
                    ],
                  ),
              ]),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    for (final breite in [420.0, 760.0, 1200.0, 1800.0]) {
      for (final schrift in [1.0, 1.3, 1.8]) {
        testWidgets('${breite.toInt()} Punkte breit, Schrift $schrift',
            (tester) async {
          await raster(tester, breite, schrift);
          // Ein Überlauf meldet sich in Flutter als Ausnahme - die
          // fängt der Testlauf von selbst ab. Hier steht sie noch
          // einmal ausdrücklich da, damit klar ist, worauf geprüft wird.
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('der Kopf', () {
    testWidgets('verbindet die Zahlen und lässt leere weg', (tester) async {
      await zeige(
        tester,
        const Uebersichtskopf(
          symbol: Icons.luggage_outlined,
          titel: 'Reisen',
          zahlen: ['12 Reisen', '', '8 Orte'],
        ),
      );
      expect(find.text('Reisen'), findsOneWidget);
      expect(find.text('12 Reisen • 8 Orte'), findsOneWidget);
    });

    testWidgets('ohne Zahlen bleibt die Unterzeile weg', (tester) async {
      await zeige(
        tester,
        const Uebersichtskopf(
          symbol: Icons.hiking,
          titel: 'Aktivitäten',
          zahlen: [],
        ),
      );
      expect(find.text('Aktivitäten'), findsOneWidget);
      expect(find.textContaining('•'), findsNothing);
    });
  });

  group('die beiden Rechnungen auf dem Schildchen', () {
    test('Nächte zählen Kalendertage, keine Stunden', () {
      // Freitagabend los, Sonntagmorgen zurück: zwei Nächte. Die
      // Stundenrechnung käme auf eine.
      expect(
        naechteZwischen(
            von: DateTime(2024, 6, 7, 19), bis: DateTime(2024, 6, 9, 9)),
        2,
      );
      expect(
        naechteZwischen(
            von: DateTime(2024, 6, 7, 8), bis: DateTime(2024, 6, 7, 20)),
        0,
      );
    });

    test('über den Jahreswechsel stehen zwei Jahre da', () {
      expect(jahresspanne(DateTime(2024, 6, 1), DateTime(2024, 6, 9)), '2024');
      expect(jahresspanne(DateTime(2024, 12, 27), DateTime(2025, 1, 3)),
          '2024–2025');
    });
  });
}
