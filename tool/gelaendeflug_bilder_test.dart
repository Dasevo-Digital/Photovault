/// **Der Flug über echtes Gelände, als Bilder.**
///
/// Kein Teil der Prüfsuite – liegt deshalb unter `tool/` und nicht unter
/// `test/`. Holt echte Höhen- und Kartenkacheln aus dem Netz und schreibt
/// Standbilder des Fluges, damit man beurteilen kann, was er zeigt. Genau
/// das hat beim Bauen drei Dinge aufgedeckt, die keine Rechnung gefunden
/// hätte: die Schlieren aus Dreiecken hinter der Kamera, den zu geringen
/// Abstand bei grober Maschenweite und die vertauschte Bedeutung der
/// Neigung.
///
/// ```sh
/// PV_BILDER=~/Desktop/pv_flug flutter test tool/gelaendeflug_bilder_test.dart
/// ```
///
/// **`flutter test` schiebt einen Attrappen-HTTP-Client unter**, der jede
/// Anfrage mit 400 beantwortet. Deshalb wird er hier für die Dauer des
/// Ladens abgeschaltet – der Grund, warum der erste Lauf „keine Kacheln
/// erreichbar" meldete, obwohl `curl` dieselbe Kachel holte.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart' show DisabledMapCachingProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/gelaende_laden.dart';
import 'package:photo_vault/services/gelaendeflug.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/services/lichtstimmung.dart';
import 'package:photo_vault/widgets/gelaende.dart';

/// Zwei Landschaften, und beide werden gebraucht.
///
/// **Grindelwald** ist der Grenzfall nach oben: 3500 Höhenmeter auf zehn
/// Kilometer, bei dreifacher Überhöhung also Wände von zehn Kilometern.
/// Im Flug steht die Kamera darin wie in einer Schlucht – dort ist nie
/// Himmel zu sehen, und das ist keine Einstellungssache: Bei 0,95, 0,70,
/// 0,50 und 0,35 Neigung durchgemessen, alle vier zeigen eine Wand.
///
/// **Der Harz** ist der Regelfall: eine Tageswanderung mit dreihundert
/// Höhenmetern. Genau die Landschaft aus dem Bild, das den Anlass gab –
/// und die, an der sich entscheidet, ob Himmel und Dunst etwas bringen.
const _landschaften = [
  (
    name: 'harz',
    sued: 51.78,
    nord: 51.89,
    west: 10.58,
    ost: 10.72,
  ),
  (
    name: 'grindelwald',
    sued: 46.60,
    nord: 46.68,
    west: 7.95,
    ost: 8.12,
  ),
];

/// Eine echte Spur aus einer CSV (breite,laenge,hoehe) – oder `null`.
///
/// **Warum eine echte und nicht die gerechnete unten.** Die gerechnete
/// ist eine Sinuswelle: gleichmässig, ohne Kehren, ohne Messrauschen.
/// Genau daran war nicht zu sehen, dass die Kamera auf einem Wanderweg
/// mit Serpentinen umschlägt.
///
/// ```sh
/// sqlite3 -csv kopie.sqlite \
///   "SELECT breite, laenge, hoehe FROM spurpunkte ORDER BY spur_id, nummer" \
///   > /tmp/spur.csv
/// PV_SPUR=/tmp/spur.csv PV_BILDER=~/Desktop/pv_flug \
///   flutter test tool/gelaendeflug_bilder_test.dart
/// ```
List<({double breite, double laenge, double? hoehe})>? _echteSpur() {
  final pfad = Platform.environment['PV_SPUR'];
  if (pfad == null) return null;
  final punkte = <({double breite, double laenge, double? hoehe})>[];
  for (final z in File(pfad).readAsLinesSync()) {
    final t = z.split(',');
    if (t.length < 2) continue;
    final b = double.tryParse(t[0]);
    final l = double.tryParse(t[1]);
    if (b == null || l == null) continue;
    punkte.add((
      breite: b,
      laenge: l,
      hoehe: t.length > 2 ? double.tryParse(t[2]) : null,
    ));
  }
  return punkte.length < 2 ? null : punkte;
}

void main() {
  final echte = _echteSpur();
  final landschaften = echte == null
      ? _landschaften
      : [
          () {
            var sued = 90.0, nord = -90.0, west = 180.0, ost = -180.0;
            for (final p in echte) {
              sued = math.min(sued, p.breite);
              nord = math.max(nord, p.breite);
              west = math.min(west, p.laenge);
              ost = math.max(ost, p.laenge);
            }
            // Etwas Rand, damit die Kamera nicht am Gitterende steht.
            final db = (nord - sued) * 0.25, dl = (ost - west) * 0.25;
            return (
              name: 'echte-spur',
              sued: sued - db,
              nord: nord + db,
              west: west - dl,
              ost: ost + dl,
            );
          }(),
        ];
  for (final ort in landschaften) {
    testWidgets('Flug über echtes Gelände: ${ort.name}', (tester) async {
    final ziel = Directory(Platform.environment['PV_BILDER']!)
      ..createSync(recursive: true);
    tester.view.physicalSize = const Size(1200, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final sued = ort.sued, nord = ort.nord, west = ort.west, ost = ort.ost;

    Hoehengitter? gitter;
    ui.Image? karte;
    await tester.runAsync(() async {
      // flutter_test schiebt eine Attrappe unter, die jede Anfrage mit
      // 400 beantwortet. Für diesen einen Prüfstand echtes Netz.
      final vorher = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = vorher);
      final netz = http.Client();
      gitter = await ladeHoehengitter(
          sued: sued, west: west, nord: nord, ost: ost,
          netz: netz, speicher: const DisabledMapCachingProvider());
      karte = await ladeKartenbild(
          sued: sued, west: west, nord: nord, ost: ost,
          netz: netz, speicher: const DisabledMapCachingProvider());
      netz.close();
    });
    if (gitter == null) {
      markTestSkipped('Keine Höhenkacheln erreichbar');
      return;
    }
    final g = gitter!;
    stdout.writeln('${ort.name}: Gitter ${g.spalten}x${g.zeilen}, '
        'Höhen ${g.spanne.tief.round()}..${g.spanne.hoch.round()} m, '
        'Karte: ${karte != null}');

    final netzDreiecke = baueNetz(g,
        grundfarbe: karte == null ? gelaendeGrundfarbe : const Color(0xFFFFFFFF));

    // Eine plausible Spur: quer durchs Tal, die Höhe aus dem echten
    // Gelände gelesen, mit Zeitstempeln im Wandertempo.
    final start = DateTime.utc(2026, 8, 30, 8, 15);
    final spur = <Gelaendespurpunkt>[];
    if (echte != null) {
      for (final (i, p) in echte.indexed) {
        spur.add((
          breite: p.breite,
          laenge: p.laenge,
          hoehe: p.hoehe ?? g.anOrt(p.breite, p.laenge),
          zeit: start.add(Duration(seconds: i * 12)),
        ));
      }
    }
    for (var i = 0; echte == null && i <= 240; i++) {
      final t = i / 240;
      final breite = sued + (nord - sued) * (0.18 + 0.62 * t);
      final laenge = west + (ost - west) *
          (0.15 + 0.7 * t + 0.08 * math.sin(t * math.pi * 3));
      spur.add((
        breite: breite,
        laenge: laenge,
        hoehe: g.anOrt(breite, laenge),
        zeit: start.add(Duration(seconds: i * 25)),
      ));
    }

    // Wie im Bildschirm: Linie und Werte in einem Zug.
    final kleiner = g;
    final mittel = netzDreiecke.mittlereHoehe;
    final linie = <Raumpunkt>[];
    final werte = <Flugwert>[];
    for (final p in spur) {
      final h = p.hoehe ?? kleiner.anOrt(p.breite, p.laenge);
      if (h == null) continue;
      linie.add((
        x: ((p.laenge - kleiner.west) / (kleiner.ost - kleiner.west) - 0.5) *
            netzDreiecke.breiteMeter,
        y: (0.5 - (kleiner.nord - p.breite) / (kleiner.nord - kleiner.sued)) *
            netzDreiecke.hoeheMeter,
        z: (h + 2 - mittel) * gelaendeUeberhoehung,
      ));
      werte.add((hoehe: p.hoehe, zeit: p.zeit));
    }
    stdout.writeln('Spur: ${linie.length} Punkte, '
        '${(Gelaendeflug(linie).laengeMeter / 1000).toStringAsFixed(1)} km');

    final schluessel = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      locale: const Locale('de'),
      home: Scaffold(
        body: RepaintBoundary(
          key: schluessel,
          child: Gelaendeansicht(
              netz: netzDreiecke, spur: linie, spurwerte: werte, karte: karte),
        ),
      ),
    ));
    await tester.pump();

    Future<void> schiessen(String name) async {
      await tester.runAsync(() async {
        final grenze = schluessel.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final bild = await grenze.toImage(pixelRatio: 1.0);
        final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
        File('${ziel.path}/${ort.name}-$name.png')
            .writeAsBytesSync(daten!.buffer.asUint8List());
        bild.dispose();
      });
    }

    await schiessen('e0-uebersicht');
    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (final (n, stelle) in [(1, 0.08), (2, 0.35), (3, 0.62), (4, 0.9)]) {
      tester.widget<Slider>(find.byType(Slider)).onChanged!(stelle);
      await tester.pump();
      await schiessen('e$n-bei-${(stelle * 100).round()}');
    }
    // Und dieselbe Stelle im Flug unter allen vier Tageszeiten. Hier
    // entscheidet sich, was keine Zahl entscheidet: ob die
    // Kartenbeschriftung noch lesbar ist, wenn das Relief stärker wird.
    for (final stimmung in lichtstimmungen) {
      final gefaerbt = baueNetz(g,
          grundfarbe:
              karte == null ? gelaendeGrundfarbe : const Color(0xFFFFFFFF),
          stimmung: stimmung);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: RepaintBoundary(
            key: schluessel,
            child: Gelaendeansicht(
                // Eigener Schlüssel je Stimmung: Ohne ihn behält die
                // Ansicht ihren Zustand, ist also schon im Flug – und
                // der Startknopf, den wir gleich drücken wollen, ist
                // dann gar nicht mehr da.
                key: ValueKey(stimmung.zeit),
                netz: gefaerbt,
                spur: linie,
                spurwerte: werte,
                karte: karte,
                stimmung: stimmung),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.flight_takeoff));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.35);
      await tester.pump();
      await schiessen('s-${stimmung.zeit.name}');
    }

    karte?.dispose();
    stdout.writeln('Bilder in ${ziel.path}');
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
