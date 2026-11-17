// ignore_for_file: avoid_print
// Zweite Prüfrunde, Prüfer r2-ki: ORT-Einträge, die in der ersten Runde
// teilweise oder ungeprüft blieben (pruefkatalog/teile/ORT.json).
//
// Das Netz der App geht hier an die Attrappe aus katalog_r2_ki_test.dart
// (künstliche Kacheln und Geländehöhen auf 127.0.0.1) – kein Abruf der App
// verlässt den Rechner. Kartenkacheln von OpenStreetMap holt nur der
// Wegwerf-Server der Warteschlange (PV_E2E_KARTEN=an), und auch der nur für
// die ersten acht Kacheln von ORT-054; den Rest beantwortet der
// Vermittler selbst, OpenTopoMap immer.
//
// Laufen lassen nur über die Warteschlange:
//   PV_E2E_REPO=…/pruefrunde2 PV_E2E_SERVER=1 PV_E2E_KARTEN=an \
//   …/pruefkatalog/tools/e2e_queue.sh r2-ki \
//     integration_test/katalog_r2_ki_ort_test.dart \
//     integration_test/katalog_r2_ki_neustart_test.dart
// (die Neustart-Datei danach: ORT-175 „nach dem Neustart“ braucht einen
// neuen Prozess).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_earth_globe/flutter_earth_globe.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gelaende/gelaende.dart' show Gelaendeansicht;
import 'package:gelaende/gelaende_screen.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/eigenkarte.dart';
import 'package:kern/services/gelaendeebenen.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/screens/kachelmitschnitt_screen.dart';
import 'package:photo_vault/screens/laenderliste_screen.dart';
import 'package:photo_vault/screens/ortsansicht_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/services/kachelmitschnitt.dart';
import 'package:photo_vault/services/meldungsdienst.dart' show melde;

import 'katalog_ki_test.dart' as ki;
import 'katalog_kit.dart';
import 'katalog_ort_test.dart' as ort;
import 'katalog_r2_ki_test.dart' as r2;

// --- Gelände (auch für katalog_r2_ki_neustart_test.dart) ----------------------

final gt = ort.gt;

/// Versatz dieses Laufs: Der Kachelspeicher eines Testplatzes überlebt die
/// Läufe (und nimmt Kacheln ohne Frischeangabe für sieben Tage) – an einer
/// je Lauf neuen Stelle und mit einem je Lauf neuen Namen der eigenen Quelle
/// kommt keine Kachel aus einem früheren Lauf.
final _zufall = math.Random(DateTime.now().microsecondsSinceEpoch);
final versatz = (
  (_zufall.nextDouble() - 0.5) * 0.8,
  (_zufall.nextDouble() - 0.5) * 4.0,
);
final eigenerHost = 'kacheln-${_zufall.nextInt(1 << 30)}.test';

ort.Ort verschoben(double b, double l) => (b + versatz.$1, l + versatz.$2);

/// Eine eigene Spur an einer Stelle, für die im Kachelspeicher des
/// Testplatzes nichts liegt (die GPX-Fixture der Warteschlange liegt im
/// Ammergebirge, dort hat die erste Runde echte Kacheln hinterlassen).
File eigeneStrecke() {
  final f = File(p.join(eingang.path, 'r2strecke.gpx'));
  const punkte = [
    (47.1200, 13.1500, 1500, '08'),
    (47.1240, 13.1550, 1650, '09'),
    (47.1290, 13.1600, 1800, '10'),
    (47.1330, 13.1650, 1950, '11'),
  ];
  f.writeAsStringSync(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<gpx version="1.1" creator="pruefkatalog" '
    'xmlns="http://www.topografix.com/GPX/1/1"><trk><name>Testtour</name>'
    '<trkseg>${[for (final (b, l, h, s) in punkte) '<trkpt lat="${(b + versatz.$1).toStringAsFixed(5)}" lon="${(l + versatz.$2).toStringAsFixed(5)}"><ele>$h</ele><time>2024-07-10T$s:00:00Z</time></trkpt>'].join()}'
    '</trkseg></trk></gpx>',
  );
  return f;
}

/// Zwei Aktivitäten mit Fotos entlang [eigeneStrecke].
Future<void> zweiTouren(WidgetTester tester) async {
  await importiereDirekt(tester, [
    ort.fotoBei(
      'a1.jpg',
      verschoben(47.1240, 13.1550),
      DateTime(2024, 7, 10, 10),
    ),
    ort.fotoBei(
      'a2.jpg',
      verschoben(47.1290, 13.1600),
      DateTime(2024, 7, 10, 11),
    ),
    ort.fotoBei(
      'b1.jpg',
      verschoben(47.1240, 13.1550),
      DateTime(2024, 7, 11, 10),
    ),
    ort.fotoBei(
      'b2.jpg',
      verschoben(47.1290, 13.1600),
      DateTime(2024, 7, 11, 11),
    ),
  ]);
  final id = {for (final a in await ort.alle(tester)) a.originalFileName: a.id};
  await ort.aktivitaetAnlegen(
    tester,
    'Tour A',
    DateTime(2024, 7, 10, 8),
    DateTime(2024, 7, 10, 12),
    [id['a1.jpg']!, id['a2.jpg']!],
  );
  await ort.aktivitaetAnlegen(
    tester,
    'Tour B',
    DateTime(2024, 7, 11, 8),
    DateTime(2024, 7, 11, 12),
    [id['b1.jpg']!, id['b2.jpg']!],
  );
}

/// Wartet, bis das Gelände geladen ist und die Landschaft steht.
Future<void> gelaendeGeladen(WidgetTester tester) async {
  await waitFor(tester, find.byType(GelaendeScreen));
  await ki.pumpe(tester, 500);
  await waitGone(
    tester,
    find.text(gt.gelaendeLaedt),
    timeout: const Duration(minutes: 2),
  );
  if (r2.findet(find.text(gt.gelaendeNichts))) {
    throw StateError('Keine Landschaft: ${onScreen(tester)}');
  }
  await waitFor(
    tester,
    find.byType(Gelaendeansicht),
    timeout: const Duration(seconds: 60),
  );
  await ki.pumpe(tester, 2500);
}

Future<void> gelaendeOeffnen(WidgetTester tester, String name) async {
  await ort.aktivitaetenOeffnen(tester);
  await ort.stille(tester);
  await ort.klick(tester, ort.aktivitaetskachel(name));
  await waitFor(tester, find.byTooltip(de.aktivitaetenLoeschen));
  if (find.byTooltip(de.gelaendeOeffnen).evaluate().isEmpty) {
    dialog.dateien = [eigeneStrecke()];
    await ort.klick(tester, find.byTooltip(de.spurHinzufuegen));
    await waitFor(tester, find.byTooltip(de.gelaendeOeffnen));
  }
  await ort.klick(tester, find.byTooltip(de.gelaendeOeffnen));
  await gelaendeGeladen(tester);
}

Future<void> gelaendeZu(WidgetTester tester) async {
  await ort.zurueck(tester);
  await waitGone(tester, find.byType(GelaendeScreen));
}

/// Das Symbol des Flugstils oben in der Leiste.
bool stilSymbol(WidgetTester tester, IconData symbol) => r2.findet(
  find.descendant(
    of: find.byTooltip(gt.flugStil),
    matching: find.byIcon(symbol),
  ),
);

// --- Hilfen ---------------------------------------------------------------------

/// Stellt den GeoNames-Datensatz aus dem Zwischenspeicher des Platzes
/// bereit (nur wenn er dort fehlt, einmal aus dem Netz).
Future<void> geodaten(WidgetTester tester) async {
  r2.netzweiche.offen = !ort.geoZwischenspeicherVoll;
  try {
    await ort.geonamesBereitstellen(tester);
  } finally {
    r2.netzweiche.offen = false;
  }
}

/// Wie viele Kachelbilder die Karte gerade zeigt.
int sichtbareKacheln(WidgetTester tester) => find
    .descendant(of: find.byType(FlutterMap), matching: find.byType(RawImage))
    .evaluate()
    .where((e) => (e.widget as RawImage).image != null)
    .length;

/// Öffnet „Einstellungen“ und klappt die Gruppe [titel] auf – gesucht nur
/// im Einstellungsbildschirm („Karte“ steht auch in der Seitenleiste).
Future<void> gruppe(WidgetTester tester, String titel) async {
  await ki.bereich(tester, Hauptbereich.einstellungen);
  await waitFor(tester, find.byType(SettingsScreen));
  final f = find.descendant(
    of: find.byType(SettingsScreen),
    matching: find.text(titel),
  );
  await ki.sichtbar(tester, f, SettingsScreen);
  await tester.tap(f.first);
  await settle(tester, max: const Duration(seconds: 2));
}

double perzentil(List<double> werte, double q) {
  if (werte.isEmpty) return double.nan;
  final s = [...werte]..sort();
  return s[math.min(s.length - 1, (q * (s.length - 1)).round())];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  r2.netzAufAttrappe();
  setUp(() {
    melde.alleSchliessen();
    melde.verlaufLeeren();
  });

  // ------------------------------------------------------------------ Globus

  testWidgets(
    timeout: r2.lang,
    'ORT-024 Globus mit 1000 Fotos: Pinzahl, Antwortzeit, Bildzeiten',
    (tester) async {
      await startApp(tester);
      await importiereDirekt(tester, [
        ort.fotoBei('stadt.jpg', ort.leipzig, DateTime(2024, 3, 1, 10)),
      ]);
      final basis = await ort.aufnahme(tester, 'stadt.jpg');
      final zufall = math.Random(7);
      await tester.runAsync(
        () => bibliothek.db.batch((b) {
          b.insertAll(bibliothek.db.assets, [
            for (var i = 1; i < 1000; i++)
              basis.copyWith(
                id: 'stadt-$i',
                checksum: '${basis.checksum}-$i',
                originalFileName: 'stadt-$i.jpg',
                latitude: Value(
                  ort.leipzig.$1 + (zufall.nextDouble() - 0.5) * 0.1,
                ),
                longitude: Value(
                  ort.leipzig.$2 + (zufall.nextDouble() - 0.5) * 0.1,
                ),
              ),
          ]);
        }),
      );
      await ort.karteOeffnen(tester);
      await waitFor(
        tester,
        ort.fotomarker,
        timeout: const Duration(seconds: 30),
      );
      await ort.kartenansicht(tester, de.karteGlobus);
      await ort.globusLabelsAbwarten(tester, ort.globusPins);

      final zeiten = <FrameTiming>[];
      void sammle(List<FrameTiming> t) => zeiten.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(sammle);
      final globus = find.byType(FlutterEarthGlobe);
      double zoom() => tester.widget<FlutterEarthGlobe>(globus).controller.zoom;
      final zahlen = <int, int>{};
      final antwort = <double>[];
      for (var stufe = 1; stufe <= 6; stufe++) {
        await ort.meldungenWeg(tester);
        final vorher = zoom();
        final knopf = find.byTooltip(de.karteHineinzoomen);
        final uhr = Stopwatch()..start();
        await tester.tap(knopf.first);
        // Bis zum ersten Bild mit der neuen Stufe.
        await tester.pump();
        while (zoom() == vorher && uhr.elapsedMilliseconds < 3000) {
          await tester.pump();
        }
        antwort.add(uhr.elapsedMicroseconds / 1000);
        await tester.pump(const Duration(milliseconds: 300));
        await settle(tester);
        zahlen[stufe] = ort.globusPins.evaluate().length;
      }
      // Drehen auf Stufe 6, mit der Maus, eine Sekunde lang.
      await tester.timedDrag(
        globus,
        const Offset(-300, 80),
        const Duration(seconds: 1),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final nachDrehen = ort.globusPins.evaluate().length;
      // Die Bildzeiten kommen gebündelt (spätestens nach einer Sekunde).
      await ki.pumpe(tester, 1600);
      SchedulerBinding.instance.removeTimingsCallback(sammle);
      final bau = [
        for (final t in zeiten) t.buildDuration.inMicroseconds / 1000,
      ];
      final raster = [
        for (final t in zeiten) t.rasterDuration.inMicroseconds / 1000,
      ];
      final gesamt = [
        for (final t in zeiten)
          (t.buildDuration + t.rasterDuration).inMicroseconds / 1000,
      ];
      String f(double x) => x.toStringAsFixed(1);
      print(
        'ORT-024 Pins je Stufe: $zahlen, nach dem Drehen $nachDrehen; '
        'Antwort je Zoomschritt (ms): ${antwort.map(f).toList()}; '
        'Bilder: ${zeiten.length}, Bauen p50 ${f(perzentil(bau, .5))} '
        'p90 ${f(perzentil(bau, .9))} max ${f(perzentil(bau, 1))}, '
        'Rastern p50 ${f(perzentil(raster, .5))} p90 ${f(perzentil(raster, .9))} '
        'max ${f(perzentil(raster, 1))}, über 16,7 ms: '
        '${gesamt.where((x) => x > 16.7).length}, über 33 ms: '
        '${gesamt.where((x) => x > 33).length}',
      );
      for (var stufe = 4; stufe <= 6; stufe++) {
        expect(zahlen[stufe]!, lessThanOrEqualTo(zahlen[3]!), reason: '$stufe');
      }
      expect(nachDrehen, lessThanOrEqualTo(zahlen[3]!));
      for (final a in antwort) {
        expect(a, lessThan(500), reason: 'Zoom reagiert sofort');
      }
      await finish(tester);
    },
  );

  // ----------------------------------------------------- Kacheln über Server

  testWidgets(
    timeout: r2.lang,
    'ORT-054 Serverpruefung Kacheln ueber den eigenen Server',
    skip: serverAdresse.isEmpty,
    (tester) async {
      final v = r2.Vermittler(Uri.parse(serverAdresse));
      var osmWeiter = 0;
      v.selbst = (r) async {
        final pfad = r.uri.path;
        if (!pfad.startsWith('/api/v1/karte/')) return false;
        // OSM: die ersten acht holt der Server bei OpenStreetMap, den Rest
        // liefert der Vermittler (sparsam). OpenTopoMap holt der Server hier
        // nie – keine weiteren Kartendienste.
        if (pfad.startsWith('/api/v1/karte/osm/') && osmWeiter < 8) {
          osmWeiter++;
          return false;
        }
        await r.drain<void>();
        final png = r2.kartenkachel(
          pfad.contains('/topo/') ? 'topo.vermittler' : 'osm.vermittler',
          ueberlagerung: false,
        );
        r.response.headers.contentType = ContentType('image', 'png');
        r.response.headers.set('cache-control', 'max-age=86400');
        // Wie der Server: mit Date, sonst legt der Kachelspeicher nichts ab.
        r.response.headers.set(
          HttpHeaders.dateHeader,
          HttpDate.format(DateTime.now()),
        );
        r.response.contentLength = png.length;
        r.response.add(png);
        await r.response.close();
        return true;
      };
      await tester.runAsync(v.starte);
      addTearDown(v.halteAn);
      final zustand = await tester.runAsync(() async {
        final c = HttpClient();
        try {
          final a = await (await c.getUrl(
            Uri.parse('$serverAdresse/api/v1/zustand'),
          )).close();
          return await a.transform(const SystemEncoding().decoder).join();
        } finally {
          c.close();
        }
      });
      print('ORT-054 Server: $zustand');
      expect(zustand, contains('"karte"'));
      await startApp(tester, groesse: const Size(1100, 760));
      await r2.verbinde(tester, v.adresse);
      // Nach dem Neustart fragt die App einmal, ob der Server Kacheln
      // liefert (LibraryState._pruefeKarte).
      try {
        await eventually(
          tester,
          () async =>
              v.abrufe.where((a) => a.pfad == '/api/v1/zustand').length >= 2,
          timeout: const Duration(seconds: 30),
        );
      } on TimeoutException {
        print('ORT-054 keine zweite Zustandsabfrage gesehen');
      }
      // Ein verortetes Foto – ohne zeigt die Karte keine FlutterMap.
      await importiereDirekt(tester, [
        ort.fotoBei('ort.jpg', ort.leipzig, DateTime(2024, 3, 1, 10)),
      ]);
      final m = Kachelmitschnitt.instanz;

      // Kachel-Mitschnitt starten.
      await gruppe(tester, de.einstAbschnittKarte);
      await ki.sichtbar(
        tester,
        find.text(de.einstMitschnittTitel),
        SettingsScreen,
      );
      await ki.tippe(tester, find.text(de.einstMitschnittTitel));
      await waitFor(tester, find.byType(KachelmitschnittScreen));
      if (!m.laeuft) await ki.tippe(tester, find.text(de.mitschnittStarten));
      await ki.tippe(tester, find.text(de.mitschnittLeeren));
      expect(m.laeuft, isTrue);
      await ort.zurueck(tester);

      List<String> adressen() => [for (final e in m.eintraege) e.adresse];

      // Karte in „Dunkel“ (ohne CARTO-Schlüssel OSM-Kacheln) …
      await ort.karteOeffnen(tester);
      await ort.kartenansicht(tester, de.karteDunkel);
      await ort.schwenke(tester, ort.leipzig, zoom: 12);
      await ki.pumpe(tester, 5000);
      final dunkel = adressen();
      print('ORT-054 Dunkel: ${dunkel.take(5).toList()} … (${dunkel.length})');
      expect(dunkel.where((a) => a.contains('/api/v1/karte/osm/')), isNotEmpty);
      expect(
        dunkel.where((a) => a.contains('openstreetmap.org')),
        isEmpty,
        reason: 'nichts direkt an OpenStreetMap',
      );
      expect(
        dunkel
            .where((a) => a.contains('/api/v1/karte/'))
            .every((a) => a.startsWith(v.adresse)),
        isTrue,
      );
      // … und in „Topografie“.
      final vorTopo = m.eintraege.length;
      await ort.kartenansicht(tester, de.karteTopografie);
      await ki.pumpe(tester, 5000);
      final topo = adressen().skip(vorTopo).toList();
      print('ORT-054 Topografie: ${topo.take(5).toList()} … (${topo.length})');
      expect(topo.where((a) => a.contains('/api/v1/karte/topo/')), isNotEmpty);
      expect(topo.where((a) => a.contains('opentopomap.org')), isEmpty);
      // Am Vermittler: mit Anmeldung, und der Server lieferte.
      final karte = v.abrufe.where((a) => a.pfad.startsWith('/api/v1/karte/'));
      print(
        'ORT-054 Kartenabrufe am Server: ${karte.length}, ohne Anmeldung '
        '${karte.where((a) => !a.anmeldung).length}, vom Server geliefert '
        '${karte.where((a) => !a.selbst && a.status == 200).length}',
      );
      expect(karte.every((a) => a.anmeldung), isTrue);
      expect(
        karte.where((a) => !a.selbst && a.status == 200),
        isNotEmpty,
        reason: 'der Server liefert OSM-Kacheln',
      );

      // Eigene Quelle: direkt, ohne Anmeldedaten.
      final eigen = Eigenkarte(
        name: 'Testkarte',
        url: 'https://$eigenerHost/{z}/{x}/{y}.png',
        nennung: '© Testkarte',
        stufe: 18,
        zugestimmt: true,
      );
      await ort.db(tester, () => bibliothek.db.setzeEigeneKarteWert(eigen));
      await ort.karteOeffnen(tester);
      final vorEigen = r2.attrappe.abrufe.length;
      final vorEigenM = m.eintraege.length;
      await ort.kartenansicht(tester, 'Testkarte');
      await ki.pumpe(tester, 4000);
      final eigenM = adressen().skip(vorEigenM).toList();
      final eigenA = r2.attrappe
          .seit(vorEigen)
          .where((a) => a.host == eigenerHost);
      print('ORT-054 eigene Quelle: ${eigenM.take(3).toList()}; $eigenA');
      expect(
        eigenM.where((a) => a.startsWith('https://$eigenerHost/')),
        isNotEmpty,
      );
      expect(eigenA, isNotEmpty);
      expect(eigenA.any((a) => a.anmeldung), isFalse);

      // Esri (Luftbild im Gelände, an einer Stelle ohne Kacheln im
      // Speicher): direkt, ohne Anmeldedaten, nicht über den Server.
      await zweiTouren(tester);
      final vorEsri = r2.attrappe.abrufe.length;
      final vorEsriServer = v.abrufe.length;
      await gelaendeOeffnen(tester, 'Tour A');
      if ((await bibliothek.db.gelaendeKarteWert()).grund !=
          Gelaendegrund.luftbild) {
        await ort.stille(tester);
        await tester.tap(find.byTooltip(gt.gelaendeKarte));
        await ki.pumpe(tester, 700);
        await tester.tap(find.text(gt.karteLuftbild).last);
        await ki.pumpe(tester, 300);
        await gelaendeGeladen(tester);
      }
      final esri = r2.attrappe
          .seit(vorEsri)
          .where(
            (a) =>
                a.host == 'server.arcgisonline.com' &&
                a.pfad.contains('World_Imagery'),
          )
          .toList();
      print(
        'ORT-054 Esri: ${esri.length} Abrufe, mit Anmeldung '
        '${esri.where((a) => a.anmeldung).length}',
      );
      expect(esri, isNotEmpty);
      expect(esri.any((a) => a.anmeldung), isFalse);
      expect(
        v.abrufe.skip(vorEsriServer).where((a) => a.pfad.contains('arcgis')),
        isEmpty,
        reason: 'Esri geht nicht über den Server',
      );
      await gelaendeZu(tester);
      await ort.zurueck(tester);

      // Mitschnitt ansehen.
      await gruppe(tester, de.einstAbschnittKarte);
      await ki.sichtbar(
        tester,
        find.text(de.einstMitschnittTitel),
        SettingsScreen,
      );
      await ki.tippe(tester, find.text(de.einstMitschnittTitel));
      await waitFor(tester, find.byType(KachelmitschnittScreen));
      await ki.pumpe(tester, 1200);
      print('ORT-054 Mitschnitt: ${onScreen(tester)}');
      await ort.zurueck(tester);

      // Server anhalten und die Karte bewegen.
      await tester.runAsync(v.halteAn);
      final vorHalt = m.eintraege.length;
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await ort.karteOeffnen(tester);
      await ort.kartenansicht(tester, de.karteDunkel);
      await ort.schwenke(tester, ort.leipzig, zoom: 12);
      await ki.pumpe(tester, 4000);
      await ort.schwenke(tester, (
        ort.leipzig.$1 + 0.01,
        ort.leipzig.$2,
      ), zoom: 12);
      await ki.pumpe(tester, 4000);
      await ort.schwenke(tester, ort.leipzig, zoom: 12);
      await eventually(
        tester,
        () async => sichtbareKacheln(tester) >= 4,
        timeout: const Duration(seconds: 60),
        was: 'Kacheln von der Platte',
      );
      await ki.pumpe(tester, 3000);
      final danach = m.eintraege.skip(vorHalt).toList();
      final gescheitert = danach.where((e) => e.fehler != null).length;
      print(
        'ORT-054 ohne Server: ${danach.length} Abrufe, gescheitert '
        '$gescheitert, Kacheln im Bild ${sichtbareKacheln(tester)}',
      );
      final ueberServer = danach.where(
        (e) => e.adresse.contains('/api/v1/karte/'),
      );
      expect(ueberServer, isNotEmpty);
      expect(ueberServer.where((e) => e.geglueckt), isEmpty);
      expect(sichtbareKacheln(tester), greaterThanOrEqualTo(4));
      await finish(tester);
    },
  );

  // Befund (zweimal nachgestellt, je 157 Abrufe direkt bei
  // tile.opentopomap.org, keiner über den Server):
  // Verbunden holt das Gelände (Topografie = OpenTopoMap, Hell/Dunkel = OSM)
  // seine Kacheln trotzdem selbst beim Anbieter: aktivitaet_detail_screen.dart
  // gibt GelaendeScreen kein `netz` mit, gelaende_screen.dart nimmt dann
  // http.Client() (Zeilen 397/448), blocktexturen.dart:439 ebenso – am
  // Kachelclient mit Kachelumleitung (mini_location_map.dart:590) vorbei.
  testWidgets(
    timeout: r2.lang,
    'ORT-054 Befundpruefung Gelaende holt OSM und OpenTopoMap am Server vorbei',
    skip: true,
    (tester) async {
      final v = r2.Vermittler(Uri.parse(serverAdresse));
      await tester.runAsync(v.starte);
      addTearDown(v.halteAn);
      await startApp(tester);
      await r2.verbinde(tester, v.adresse);
      await ki.pumpe(tester, 3000);
      await zweiTouren(tester);
      final vorher = r2.attrappe.abrufe.length;
      final vorherServer = v.abrufe.length;
      await gelaendeOeffnen(tester, 'Tour A');
      final grund = (await bibliothek.db.gelaendeKarteWert()).grund;
      await tester.tap(find.byTooltip(gt.gelaendeKarte));
      await ki.pumpe(tester, 700);
      await tester.tap(find.text(gt.karteHell).last);
      await ki.pumpe(tester, 300);
      await gelaendeGeladen(tester);
      final direkt = [
        for (final a in r2.attrappe.seit(vorher))
          if (a.host == 'tile.opentopomap.org' ||
              a.host == 'tile.openstreetmap.org')
            a,
      ];
      final ueberServer = v.abrufe
          .skip(vorherServer)
          .where((a) => a.pfad.startsWith('/api/v1/karte/'))
          .length;
      print(
        'ORT-054 Gelände verbunden (Grund ab Werk $grund): direkt beim '
        'Anbieter ${direkt.length} (${direkt.take(3).toList()}), über den '
        'Server $ueberServer',
      );
      expect(direkt, isEmpty, reason: 'Kacheln am eigenen Server vorbei');
      await gelaendeZu(tester);
      await finish(tester);
    },
  );

  // ------------------------------------------------------------ Länderliste

  testWidgets(timeout: r2.lang, 'ORT-094 Laenderliste: langer Druck markiert', (
    tester,
  ) async {
    await startApp(tester);
    await geodaten(tester);
    await importiereDirekt(tester, [
      ort.fotoBei('de1.jpg', ort.hamburg, DateTime(2024, 4, 1, 10)),
    ]);
    await ort.bereich(tester, Hauptbereich.orte);
    await waitFor(tester, find.byType(LaenderlisteScreen));
    final kopf = find.textContaining(' Länder · ');
    await waitFor(tester, kopf);
    final kopfVorher = ort.textVon(tester, kopf);
    final island = ort.landname('IS');
    await ort.laenderSuchen(tester, island);
    await ort.meldungenWeg(tester);
    final zeile = ort.landzeile(island).first;
    final blatt = find.text(de.laenderHinweisMarke);
    final ereignisse = <String>[];
    void route(PointerEvent e) {
      if (e is PointerHoverEvent) return;
      ereignisse.add('${e.runtimeType}/${e.kind.name}/${e.buttons}');
    }

    Future<void> aufraeumen() async {
      if (r2.findet(blatt)) {
        Navigator.of(tester.element(blatt.first)).pop();
        await ki.pumpe(tester, 700);
      }
      if (r2.findet(find.byType(OrtsansichtScreen))) {
        await ort.zurueck(tester);
        await ki.pumpe(tester, 500);
      }
    }

    // Jede Variante auf einem frisch geöffneten Bildschirm.
    Future<void> frisch() async {
      await aufraeumen();
      await ort.bereich(tester, Hauptbereich.orte);
      await waitFor(tester, find.byType(LaenderlisteScreen));
      await waitFor(tester, kopf);
      await ort.laenderSuchen(tester, island);
      await ort.meldungenWeg(tester);
      await tester.ensureVisible(zeile);
      await ki.pumpe(tester, 500);
    }

    GestureBinding.instance.pointerRouter.addGlobalRoute(route);
    final ergebnis = <String, bool>{};
    Future<void> variante(
      String name,
      Future<void> Function(Offset mitte) druck,
    ) async {
      await frisch();
      ereignisse.clear();
      final mitte = tester.getCenter(zeile);
      await druck(mitte);
      await ki.pumpe(tester, 800);
      ergebnis[name] = r2.findet(blatt);
      print(
        'ORT-094 $name bei $mitte: Blatt ${ergebnis[name]}, Ortsansicht '
        '${r2.findet(find.byType(OrtsansichtScreen))}, Ereignisse $ereignisse',
      );
    }

    Future<void> mausEcht(Offset mitte) async {
      final g = await tester.startGesture(mitte, kind: PointerDeviceKind.mouse);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)),
      );
      await tester.pump();
      await g.up();
    }

    await variante('Maus, echte 0,9 s', mausEcht);
    await variante('Maus, pump 0,9 s (wie Runde 1)', (mitte) async {
      final g = await tester.startGesture(mitte, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 900));
      await g.up();
    });
    await variante('Finger, echte 0,9 s', (mitte) async {
      final g = await tester.startGesture(mitte);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)),
      );
      await tester.pump();
      await g.up();
    });
    await variante(
      'tester.longPress (Finger)',
      (mitte) => tester.longPressAt(mitte),
    );
    GestureBinding.instance.pointerRouter.removeGlobalRoute(route);
    print('ORT-094 langer Druck: $ergebnis');
    expect(ergebnis.values, contains(true), reason: '$ergebnis');
    // Für den Rest: langer Druck mit der Maus, sonst mit dem Finger.
    await frisch();
    await (ergebnis['Maus, echte 0,9 s']!
        ? mausEcht(tester.getCenter(zeile))
        : tester.longPressAt(tester.getCenter(zeile)));
    await ki.pumpe(tester, 800);
    await waitFor(tester, blatt);

    // Das Blatt nennt das Land und erklärt die Handmarke.
    expect(
      find.ancestor(of: blatt, matching: find.byType(ListTile)),
      findsOneWidget,
    );
    final blattZeile = tester.widget<ListTile>(
      find.ancestor(of: blatt, matching: find.byType(ListTile)).first,
    );
    expect((blattZeile.title! as Text).data, island);
    await ort.klick(tester, find.text(de.laenderMarkeBesucht));
    await settle(tester);
    final zeileIs = ort.landzeile(island);
    expect(
      find.descendant(
        of: zeileIs,
        matching: find.byTooltip(de.laenderNurVonHand),
      ),
      findsOneWidget,
    );
    expect(ort.unterzeile(tester, zeileIs), contains(de.laenderVonHand));
    final kopfNachher = ort.textVon(tester, kopf);
    print('ORT-094 Kopf vorher „$kopfVorher“, nachher „$kopfNachher“');
    int besucht(String k) =>
        int.parse(RegExp(r'· (\d+) besucht').firstMatch(k)![1]!);
    expect(besucht(kopfNachher), besucht(kopfVorher) + 1);
    // Ein einfacher Klick öffnet die Ortsansicht – auf der frisch geöffneten
    // Liste: Nach dem nachgestellten langen Druck kommt das Loslassen im
    // Prüfstand nicht an, und dieselbe Zeile nimmt keinen Klick mehr an.
    await frisch();
    expect(ort.unterzeile(tester, zeile), contains(de.laenderVonHand));
    await ort.klick(tester, zeile);
    await waitFor(tester, find.byType(OrtsansichtScreen));
    await finish(tester);
  });

  // ------------------------------------------------------------------ Reisen

  testWidgets(
    timeout: r2.lang,
    'ORT-126 Reisen: Erneut suchen bei 3000 Aufnahmen',
    (tester) async {
      await startApp(tester);
      await importiereDirekt(tester, [
        ort.fotoBei('heim.jpg', ort.hamburg, DateTime(2024, 1, 5, 12)),
      ]);
      final basis = await ort.aufnahme(tester, 'heim.jpg');
      final ziele = [ort.rom, ort.paris, ort.madrid, ort.wien, ort.muenchen];
      final start = DateTime(2023, 1, 1, 9);
      await tester.runAsync(
        () => bibliothek.db.batch((b) {
          b.insertAll(bibliothek.db.assets, [
            for (var i = 1; i < 3000; i++)
              () {
                // Jede zehnte Woche eine Reise, sonst zu Hause.
                final tag = i ~/ 4;
                final woche = tag ~/ 7;
                final weg = woche % 10 == 3;
                final o = weg
                    ? ziele[(woche ~/ 10) % ziele.length]
                    : ort.hamburg;
                final zeit = start.add(Duration(days: tag, hours: (i % 4) * 3));
                return basis.copyWith(
                  id: 'r-$i',
                  checksum: '${basis.checksum}-$i',
                  originalFileName: 'r-$i.jpg',
                  fileCreatedAt: zeit,
                  latitude: Value(o.$1 + (i % 7) * 0.001),
                  longitude: Value(o.$2 + (i % 5) * 0.001),
                );
              }(),
          ]);
        }),
      );
      final uhr = Stopwatch()..start();
      await ort.reisenOeffnen(tester);
      print('ORT-126 erste Suche: ${uhr.elapsedMilliseconds} ms');
      for (final t in [
        de.reisenSelbstAnlegen,
        de.weltkarteOeffnen,
        de.laenderTitel,
        de.aktivitaetenOeffnen,
        de.reisenAktualisieren,
      ]) {
        expect(find.byTooltip(t), findsOneWidget, reason: t);
      }
      final knopf = find
          .ancestor(
            of: find.byTooltip(de.reisenAktualisieren),
            matching: find.byType(IconButton),
          )
          .first;
      expect(tester.widget<IconButton>(knopf).onPressed, isNotNull);
      await ort.meldungenWeg(tester);
      uhr.reset();
      await tester.tap(knopf);
      var sucht = false;
      var aus = false;
      var bilder = 0;
      for (var i = 0; i < 40 && !sucht; i++) {
        await tester.pump();
        bilder++;
        sucht = r2.findet(find.text(de.reisenSuchtNoch));
        if (sucht) aus = tester.widget<IconButton>(knopf).onPressed == null;
      }
      print(
        'ORT-126 nach $bilder Bild(ern), ${uhr.elapsedMilliseconds} ms: '
        '„Sucht nach Reisen …“ $sucht, Knopf aus $aus',
      );
      expect(sucht, isTrue);
      expect(aus, isTrue);
      await waitGone(
        tester,
        find.text(de.reisenSuchtNoch),
        timeout: const Duration(minutes: 2),
      );
      print('ORT-126 Suche fertig nach ${uhr.elapsedMilliseconds} ms');
      expect(tester.widget<IconButton>(knopf).onPressed, isNotNull);
      await finish(tester);
    },
  );

  // ----------------------------------------------------------------- Gelände

  testWidgets(
    timeout: r2.lang,
    'ORT-164 ORT-175 Gelaende mit Hoehen und Karten aus der Attrappe',
    (tester) async {
      await startApp(tester);
      await zweiTouren(tester);
      final a = r2.attrappe;
      int hoehen() =>
          a.abrufe.where((x) => x.pfad.contains('/terrarium/')).length;

      bool passt(Kartenebene e, r2.Abruf x) {
        final u = Uri.parse(e.urlVorlage.split('{').first);
        return x.host == u.host && x.pfad.startsWith(u.path);
      }

      Future<void> karteWaehlen(String eintrag) async {
        await ort.stille(tester);
        await tester.tap(find.byTooltip(gt.gelaendeKarte));
        await ki.pumpe(tester, 700);
        await tester.tap(find.text(eintrag).last);
        await ki.pumpe(tester, 300);
        await gelaendeGeladen(tester);
      }

      // Nach einem Wechsel: Höhen nicht neu geholt, geholt nur die
      // sichtbaren Quellen, und die Nennung nennt genau sie.
      Future<void> pruefeWechsel(
        String was,
        int vorher,
        int hoehenVorher, {
        Kartenebene? muss,
      }) async {
        final auflage = await bibliothek.db.gelaendeKarteWert();
        final neu = a.seit(vorher);
        final karten = [
          for (final x in neu)
            if (!x.pfad.contains('/terrarium/') && !x.host.contains('overpass'))
              x,
        ];
        final quellen = {
          for (final x in karten)
            for (final e in [
              luftbildEbene,
              wanderwegeEbene,
              strassenEbene,
              orteEbene,
              for (final g in Gelaendegrund.values)
                if (g != Gelaendegrund.eigene ||
                    auflage.grund == Gelaendegrund.eigene)
                  g.ebene,
            ])
              if (passt(e, x)) e.nennung,
        };
        final nennung = '${gt.gelaendeNamensnennung} · ${auflage.nennung}';
        print(
          'ORT-164 $was: ${karten.length} Kartenabrufe von $quellen, '
          'Höhen ${hoehen() - hoehenVorher}, Nennung „${auflage.nennung}“',
        );
        expect(hoehen(), hoehenVorher, reason: '$was: Höhen neu geholt');
        expect(find.text(nennung), findsWidgets, reason: '$was: Nennung');
        // Geholt wird nur, was im Bild ist (und genannt wird).
        expect(
          quellen.difference({for (final e in auflage.ebenen) e.nennung}),
          isEmpty,
          reason: '$was: nicht genannte Quelle geholt',
        );
        for (final x in karten) {
          expect(
            auflage.ebenen.any((e) => passt(e, x)),
            isTrue,
            reason: '$was: $x gehört zu keiner sichtbaren Quelle',
          );
        }
        if (muss != null) {
          expect(
            karten.any((x) => passt(muss, x)),
            isTrue,
            reason: '$was: ${muss.name} nicht geholt',
          );
        }
      }

      await gelaendeOeffnen(tester, 'Tour A');
      final hoehen0 = hoehen();
      print(
        'ORT-164 erste Landschaft: ${a.abrufe.length} Abrufe, Höhen $hoehen0',
      );
      expect(hoehen0, greaterThan(0));
      final ab = await bibliothek.db.gelaendeKarteWert();
      expect(
        find.text('${gt.gelaendeNamensnennung} · ${ab.nennung}'),
        findsWidgets,
      );

      // Ab Werk: Luftbild mit Wegen und Beschriftung. Grund wechseln:
      // Hell, Dunkel, Topografie, Luftbild.
      print(
        'ORT-164 ab Werk: ${ab.grund}, Wege ${ab.wege}, '
        'Beschriftung ${ab.beschriftung}, Höhenlinien ${ab.hoehenlinien}, '
        'Schilder ${ab.wanderobjekte}',
      );
      for (final (eintrag, grund, muss) in [
        (gt.karteHell, Gelaendegrund.hell, Gelaendegrund.hell.ebene),
        (gt.karteDunkel, Gelaendegrund.dunkel, null),
        (
          gt.karteTopografie,
          Gelaendegrund.wanderkarte,
          Gelaendegrund.wanderkarte.ebene,
        ),
        (gt.karteLuftbild, Gelaendegrund.luftbild, null),
      ]) {
        final vorher = a.abrufe.length;
        await karteWaehlen(eintrag);
        expect((await bibliothek.db.gelaendeKarteWert()).grund, grund);
        await pruefeWechsel(eintrag, vorher, hoehen0, muss: muss);
      }
      // Jede Ebene zweimal umschalten (hin und zurück) und dazwischen im
      // Menü nachsehen: Kästchen an der Ebene, der Grund farbig.
      final primaer = Theme.of(
        tester.element(find.byType(GelaendeScreen)),
      ).colorScheme.primary;
      Finder zeileVon(String eintrag) => find
          .ancestor(of: find.text(eintrag).last, matching: find.byType(Row))
          .first;
      Future<void> menuePruefen(String was) async {
        final auflage = await bibliothek.db.gelaendeKarteWert();
        await ort.stille(tester);
        await tester.tap(find.byTooltip(gt.gelaendeKarte));
        await ki.pumpe(tester, 700);
        for (final (eintrag, an) in [
          (gt.gelaendeEbeneWege, auflage.wege),
          (gt.gelaendeEbeneBeschriftung, auflage.beschriftung),
          (gt.gelaendeEbeneHoehenlinien, auflage.hoehenlinien),
          (gt.gelaendeEbeneWanderobjekte, auflage.wanderobjekte),
        ]) {
          expect(
            find.descendant(
              of: zeileVon(eintrag),
              matching: find.byIcon(
                an ? Icons.check_box_outlined : Icons.check_box_outline_blank,
              ),
            ),
            findsOneWidget,
            reason: '$was: Kästchen $eintrag',
          );
        }
        final farbig = [
          for (final t in [
            gt.karteLuftbild,
            gt.karteTopografie,
            gt.karteHell,
            gt.karteDunkel,
          ])
            if (tester
                    .widget<Icon>(
                      find
                          .descendant(
                            of: zeileVon(t),
                            matching: find.byType(Icon),
                          )
                          .first,
                    )
                    .color ==
                primaer)
              t,
        ];
        expect(farbig, [gt.karteLuftbild], reason: '$was: Grund farbig');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await ki.pumpe(tester, 500);
      }

      for (final eintrag in [
        gt.gelaendeEbeneWege,
        gt.gelaendeEbeneBeschriftung,
        gt.gelaendeEbeneHoehenlinien,
        gt.gelaendeEbeneWanderobjekte,
      ]) {
        for (var mal = 1; mal <= 2; mal++) {
          final vorher = a.abrufe.length;
          await karteWaehlen(eintrag);
          await pruefeWechsel('$eintrag $mal', vorher, hoehen0);
          if (mal == 1) await menuePruefen('$eintrag umgeschaltet');
        }
      }
      // Gipfel, Hütten, Quellen kommen einmal von Overpass und liegen danach
      // in der Bibliothek (wanderobjekteAusBibliothek).
      expect(
        a.abrufe.where((x) => x.host.contains('overpass')),
        isNotEmpty,
        reason: 'Gipfel, Hütten, Quellen fragt Overpass',
      );
      final gemerkt = await bibliothek.db.gelaendeKarteWert();
      expect(gemerkt.grund, Gelaendegrund.luftbild);
      expect(
        [gemerkt.wege, gemerkt.beschriftung, gemerkt.hoehenlinien],
        [ab.wege, ab.beschriftung, ab.hoehenlinien],
      );
      // Zum Merken etwas anderes als ab Werk: Topografie, Höhenlinien an.
      await karteWaehlen(gt.karteTopografie);
      await karteWaehlen(gt.gelaendeEbeneHoehenlinien);
      final gewaehlt = await bibliothek.db.gelaendeKarteWert();
      expect(gewaehlt.grund, Gelaendegrund.wanderkarte);
      expect(gewaehlt.hoehenlinien, isNot(ab.hoehenlinien));
      await gelaendeZu(tester);
      await ort.zurueck(tester);

      // Wieder öffnen: Grund und Ebenen gelten weiter.
      await gelaendeOeffnen(tester, 'Tour A');
      expect(
        find.text('${gt.gelaendeNamensnennung} · ${gewaehlt.nennung}'),
        findsWidgets,
      );
      expect(await bibliothek.db.gelaendeKarteWert(), gewaehlt);
      final beimOeffnen = a.abrufe.length;

      // Eigene Quelle im Menü.
      await gelaendeZu(tester);
      await ort.zurueck(tester);
      final karte = Eigenkarte(
        name: 'Testkarte',
        url: 'https://$eigenerHost/{z}/{x}/{y}.png',
        nennung: '© Testkarte',
        stufe: 18,
        zugestimmt: true,
      );
      await ort.db(tester, () => bibliothek.db.setzeEigeneKarteWert(karte));
      await gelaendeOeffnen(tester, 'Tour A');
      final hoehen1 = hoehen();
      final vorEigen = a.abrufe.length;
      await karteWaehlen('Testkarte');
      await pruefeWechsel('eigene Quelle', vorEigen, hoehen1);
      expect(a.seit(vorEigen).where((x) => x.host == eigenerHost), isNotEmpty);
      print(
        'ORT-164 Abrufe gesamt ${a.abrufe.length} (beim Öffnen $beimOeffnen)',
      );

      // ORT-175: „Nah dran“ gilt für die Sitzung und steht nirgends in der
      // Bibliothek.
      Future<String> einstellungen() async =>
          (await ki.sql(tester, 'SELECT * FROM app_settings')).toString();
      expect(stilSymbol(tester, Icons.flight_outlined), isTrue);
      final vorStil = await einstellungen();
      await ort.stille(tester);
      await tester.tap(find.byTooltip(gt.flugStil));
      await ki.pumpe(tester, 700);
      await tester.tap(find.text(gt.flugStilNahDran).last);
      await ki.pumpe(tester, 300);
      await gelaendeGeladen(tester);
      expect(stilSymbol(tester, Icons.directions_walk), isTrue);
      expect(await einstellungen(), vorStil, reason: 'Stil nicht gespeichert');
      await gelaendeZu(tester);
      await ort.zurueck(tester);
      await gelaendeOeffnen(tester, 'Tour B');
      expect(
        stilSymbol(tester, Icons.directions_walk),
        isTrue,
        reason: 'in derselben Sitzung „Nah dran“',
      );
      // Mit Absicht nicht zurückgestellt: Die Neustart-Datei prüft im
      // nächsten Prozess.
      await gelaendeZu(tester);
      await finish(tester);
    },
  );
}
