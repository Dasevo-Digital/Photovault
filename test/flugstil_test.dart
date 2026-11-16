// **Der Flugstil „Nah dran"** – Kamera, Tempo, Tafeln und die Wahl am
// Bildschirm (#398).
//
// Was hier steht, lässt sich an Zahlen prüfen: wo die Kamera steht, wann
// welche Tafel zu sehen ist, dass die Leuchtspur nur zeigt, was noch
// kommt. Wie es aussieht, zeigt `tool/flugstil_bilder_test.dart` über
// echtem Gelände.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gelaende/flugstil.dart';
import 'package:gelaende/flugtafeln.dart';
import 'package:gelaende/flugvideo.dart';
import 'package:gelaende/gelaende.dart';
import 'package:gelaende/gelaende_screen.dart';
import 'package:gelaende/gelaendeflug.dart';
import 'package:gelaende/gelaendekacheln.dart';
import 'package:gelaende/gelaendeschilder.dart';
import 'package:gelaende/gelaendesicht.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/services/gelaendeebenen.dart';
import 'package:kern/services/wanderobjekte.dart';
import 'package:photo_vault/l10n/app_localizations.dart';

/// Eine gerade Spur nach Norden, [meter] lang, auf flachem Grund.
Gelaendeflug _geradeausNachNorden(double meter) => Gelaendeflug([
  for (var i = 0; i <= 100; i++) (x: 0.0, y: meter * i / 100, z: 0.0),
]);

Gelaendenetz _netz({double ueberhoehung = gelaendeUeberhoehung}) {
  const n = 24;
  final h = Float32List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      h[y * n + x] = 400 + 20.0 * y;
    }
  }
  return baueNetz(
    Hoehengitter(
      spalten: n,
      zeilen: n,
      hoehen: h,
      nord: 51.85,
      sued: 51.83,
      west: 10.63,
      ost: 10.66,
    ),
    kante: 24,
    ueberhoehung: ueberhoehung,
  );
}

({List<Raumpunkt> linie, List<Flugwert> werte}) _spur(Gelaendenetz netz) {
  final linie = <Raumpunkt>[];
  final werte = <Flugwert>[];
  final start = DateTime.utc(2026, 8, 30, 9);
  for (var i = 0; i <= 40; i++) {
    final t = i / 40;
    linie.add((
      x: (t - 0.5) * netz.breiteMeter * 0.8,
      y: (t - 0.5) * netz.hoeheMeter * 0.8,
      z: 20.0 * t,
    ));
    werte.add((hoehe: 400 + 300 * t, zeit: start.add(Duration(minutes: i))));
  }
  return (linie: linie, werte: werte);
}

Future<Uint8List> _terrariumKachel() async {
  const kante = 256;
  final rgba = Uint8List(kante * kante * 4);
  for (var y = 0; y < kante; y++) {
    for (var x = 0; x < kante; x++) {
      final roh = (500 + x / kante * 400 + 32768).round();
      final i = (y * kante + x) * 4;
      rgba[i] = roh >> 8;
      rgba[i + 1] = roh & 255;
      rgba[i + 3] = 255;
    }
  }
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    kante,
    kante,
    ui.PixelFormat.rgba8888,
    fertig.complete,
  );
  final bild = await fertig.future;
  final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
  bild.dispose();
  return daten!.buffer.asUint8List();
}

/// Ein Videoschreiber, der nur sagt, dass es ihn gibt.
class _Schreiber implements Videoschreiber {
  @override
  Future<bool> moeglich() async => true;

  @override
  Future<Videoergebnis> schreibe({
    required File ziel,
    required int breite,
    required int hoehe,
    required Duration dauer,
    required void Function(ui.Canvas leinwand, ui.Size flaeche, double t)
    maleBild,
    Future<void> Function(double t)? vorBild,
    void Function(double anteil)? fortschritt,
    bool Function()? abbruch,
  }) async => (ausgang: Videoausgang.abgebrochen, meldung: null);
}

void main() {
  group('Die Rechnung', () {
    test('der Überblick bleibt, wie er war', () {
      expect(Flugstil.ueberblick.ueberhoehung, gelaendeUeberhoehung);
      expect(Flugstil.ueberblick.gitterkante, gelaendeGitterkante);
      expect(Flugstil.ueberblick.spurAufDemGelaende, isFalse);
      expect(flugAnteile(Flugstil.ueberblick), (einflug: 0.07, abspann: 0.10));
    });

    test('Nah dran ist flacher, feiner und legt die Linie auf den Boden', () {
      expect(Flugstil.nahDran.ueberhoehung, lessThan(gelaendeUeberhoehung));
      expect(Flugstil.nahDran.gitterkante, greaterThan(gelaendeGitterkante));
      expect(Flugstil.nahDran.spurAufDemGelaende, isTrue);
    });

    test('weich schattiert je Gitterpunkt, sonst je Dreieck', () {
      const n = 24;
      final h = Float32List(n * n);
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          h[y * n + x] = 400 + 150 * math.sin(x / 3) * math.cos(y / 4);
        }
      }
      final gitter = Hoehengitter(
        spalten: n,
        zeilen: n,
        hoehen: h,
        nord: 51.85,
        sued: 51.83,
        west: 10.63,
        ost: 10.66,
      );
      // Farben ohne Deckkraft – die trägt den weichen Rand, nicht das
      // Licht.
      int rgb(int farbe) => farbe & 0x00FFFFFF;
      // Ein Block aus der Mitte: Am Rand des Ausschnitts sind die Ecken
      // durchsichtig, und das Licht wäre dort nicht zu vergleichen.
      Blocknetz mitte(Gelaendenetz netz) =>
          netz.bloecke[netz.bloecke.length ~/ 2];

      // Hart: Die drei Ecken eines Dreiecks tragen dieselbe Farbe, und
      // dieselbe Ecke im Nachbardreieck eine andere.
      final hart = mitte(baueNetz(gitter, kante: 24)).farben;
      var gleichImDreieck = 0;
      for (var d = 0; d + 2 < hart.length; d += 3) {
        if (rgb(hart[d]) == rgb(hart[d + 1]) &&
            rgb(hart[d]) == rgb(hart[d + 2])) {
          gleichImDreieck++;
        }
      }
      expect(gleichImDreieck, hart.length ~/ 3);

      // Weich: Dieselbe Ecke (die rechte obere eines Feldes, in beiden
      // Dreiecken an Stelle 1 bzw. 3) hat in beiden Dreiecken dieselbe
      // Farbe, und innerhalb eines Dreiecks wechselt sie.
      final weich = mitte(baueNetz(gitter, kante: 24, weich: true)).farben;
      var geteilt = 0;
      var verlauf = 0;
      for (var feld = 0; feld + 5 < weich.length; feld += 6) {
        if (rgb(weich[feld + 1]) == rgb(weich[feld + 3])) geteilt++;
        if (rgb(weich[feld]) != rgb(weich[feld + 1])) verlauf++;
      }
      expect(geteilt, weich.length ~/ 6);
      expect(verlauf, greaterThan(weich.length ~/ 12));
    });

    test('das Tempo richtet sich nach der Länge – in Grenzen', () {
      // 4,5 km in 45 Sekunden.
      expect(nahDranTempo(4500), closeTo(100, 0.01));
      // Ein Spaziergang schleicht nicht, eine Radtour rast nicht.
      expect(nahDranTempo(800), 60);
      expect(nahDranTempo(80000), 250);
      expect(nahDranTempo(0), 60);
    });

    test('die Kamera steht hinter und über dem Weg, der Punkt liegt '
        'unten im Bild', () {
      final flug = _geradeausNachNorden(4000);
      final stand = flug.bei(0.5);
      final k = verfolgerkamera(
        stand: stand,
        breite: 1080,
        hoehe: 1920,
        tempo: 100,
      );
      final wo = k.standort;
      expect(wo.y, lessThan(stand.blickpunkt.y), reason: 'nicht dahinter');
      expect(wo.z, greaterThan(stand.blickpunkt.z + 50), reason: 'zu tief');
      final abstand = stand.blickpunkt.y - wo.y;
      expect(abstand, inInclusiveRange(150, 400), reason: 'nicht nah dran');

      final punkt = k.projiziere(stand.blickpunkt);
      expect(punkt.stelle.dy / 1920, closeTo(0.72, 0.01));
      expect(punkt.stelle.dx, closeTo(540, 1));
      // Was 800 Meter voraus liegt, steht höher im Bild – der Weg führt
      // in die Tiefe und nicht zur Seite.
      final voraus = k.projiziere(flug.punktBei(2800));
      expect(voraus.tiefe, greaterThan(punkt.tiefe));
      expect(voraus.stelle.dy, lessThan(punkt.stelle.dy - 200));
      expect(voraus.stelle.dx, closeTo(540, 1));
      // Und was hinter der Kamera liegt, ist nicht im Bild.
      expect(k.projiziere(flug.punktBei(1500)).tiefe, lessThan(abstand));
    });

    test('der Rundblick hebt über dem Ziel ab und dreht ein Stück', () {
      final flug = _geradeausNachNorden(4000);
      final k = verfolgerkamera(
        stand: flug.bei(1),
        breite: 1920,
        hoehe: 1080,
        tempo: 100,
      );
      final p = panoramakamera(k);
      expect(p.entfernung, greaterThan(k.entfernung * 2));
      expect(p.standort.z, greaterThan(k.standort.z));
      expect(p.drehung, isNot(closeTo(k.drehung, 0.1)));
      // Das Ziel bleibt der Blickpunkt.
      expect(p.blickpunkt, k.blickpunkt);
    });

    test('die Titeltafel steht am Anfang und geht, wenn der Weg beginnt', () {
      expect(titeltafelDeckkraft(sekunde: -1, einflugEnde: 4), 0);
      expect(titeltafelDeckkraft(sekunde: 0, einflugEnde: 4), 0);
      expect(titeltafelDeckkraft(sekunde: 2, einflugEnde: 4), 1);
      expect(titeltafelDeckkraft(sekunde: 7.4, einflugEnde: 4), 1);
      final ab = titeltafelDeckkraft(sekunde: 7.9, einflugEnde: 4);
      expect(ab, inExclusiveRange(0, 1));
      expect(titeltafelDeckkraft(sekunde: 8.4, einflugEnde: 4), 0);
    });

    test('die Zieltafel kommt erst, wenn die Kamera abgehoben hat', () {
      expect(zieltafelDeckkraft(0), 0);
      expect(zieltafelDeckkraft(0.2), 0);
      expect(zieltafelDeckkraft(0.35), inExclusiveRange(0, 1));
      expect(zieltafelDeckkraft(0.5), 1);
      expect(zieltafelDeckkraft(1), 1);
    });

    test('ein Foto blendet auf, steht und geht wieder', () {
      double d(double meter) => fototafelDeckkraft(
        meter: meter,
        fotoMeter: 1000,
        einblendweg: 50,
        haltMeter: 300,
      );
      expect(d(999), 0, reason: 'vor seiner Stelle');
      expect(d(1025), inExclusiveRange(0, 1));
      expect(d(1050), 1);
      expect(d(1349), 1);
      expect(d(1375), inExclusiveRange(0, 1));
      expect(
        d(1401),
        0,
        reason: 'eine Tafel über einem Drittel des Bildes bleibt nicht stehen',
      );
    });

    test('Start und Ziel heissen nach dem nächsten Namen in der Nähe', () {
      const namen = <Ortsname>[
        (ort: (x: 0, y: 0, z: 0), name: 'Klingenstock'),
        (ort: (x: 50, y: 4000, z: 0), name: 'Fronalpstock'),
        (ort: (x: 600, y: 4000, z: 0), name: 'Nebengipfel'),
      ];
      expect(naechsterName(namen, (x: 10, y: 20, z: 0), 300), 'Klingenstock');
      expect(naechsterName(namen, (x: 0, y: 4000, z: 0), 300), 'Fronalpstock');
      // Zu weit weg ist kein Name besser als ein falscher.
      expect(naechsterName(namen, (x: 0, y: 2000, z: 0), 300), isNull);
    });

    test('ein Rundweg endet, wo er beginnt', () {
      expect(istRundweg(_geradeausNachNorden(4000)), isFalse);
      final runde = Gelaendeflug([
        for (var i = 0; i <= 40; i++)
          (
            x: 1000 * (1 - (i / 40 * 2 - 1).abs()),
            y: i < 20 ? i * 50.0 : (40 - i) * 50.0 + 30,
            z: 0.0,
          ),
      ]);
      expect(istRundweg(runde), isTrue);
    });
  });

  group('Gemalt', () {
    testWidgets('die Leuchtspur zeigt, was kommt, und nicht, was war', (
      tester,
    ) async {
      final netz = _netz();
      // Quer durchs Bild, von Westen nach Osten, von oben gesehen.
      final spur = [
        for (var i = 0; i <= 40; i++)
          (x: (i / 40 - 0.5) * netz.breiteMeter * 0.8, y: 0.0, z: 60.0),
      ];
      final flug = Gelaendeflug(spur);
      final kamera = Gelaendekamera(
        drehung: 0,
        neigung: 1.5,
        entfernung: netz.breiteMeter * 1.2,
        brennweite: 400,
        mitte: const Offset(200, 150),
      );
      final mitte = flug.laengeMeter / 2;
      final rgba = (await tester.runAsync(() async {
        final sammler = ui.PictureRecorder();
        Gelaendemaler(
          netz: netz,
          kamera: kamera,
          spur: spur,
          spurfarbe: const Color(0xFFFF6A00),
          gefahrenBis: mitte,
          streckeJePunkt: flug.streckeJePunkt,
          leuchtspur: true,
          kopf: flug.punktBei(mitte),
        ).paint(ui.Canvas(sammler), const Size(400, 300));
        final bild = await sammler.endRecording().toImage(400, 300);
        final daten = await bild.toByteData();
        bild.dispose();
        return daten!;
      }))!;

      bool orange(Offset o) {
        final i = (o.dy.round() * 400 + o.dx.round()) * 4;
        final r = rgba.getUint8(i), g = rgba.getUint8(i + 1);
        final b = rgba.getUint8(i + 2);
        return r > 200 && b < 120 && r - b > 120 && g < 210;
      }

      final kommt = kamera.projiziere(flug.punktBei(flug.laengeMeter * 0.8));
      final war = kamera.projiziere(flug.punktBei(flug.laengeMeter * 0.2));
      expect(orange(kommt.stelle), isTrue, reason: 'was kommt, leuchtet');
      expect(orange(war.stelle), isFalse, reason: 'was war, ist weg');
    });

    testWidgets('eine Tafel liegt dunkel über dem Bild – und unsichtbar '
        'nicht', (tester) async {
      Future<ByteData> male(double deckkraft) async =>
          (await tester.runAsync(() async {
            final sammler = ui.PictureRecorder();
            final c = ui.Canvas(sammler);
            const size = Size(540, 960);
            c.drawRect(
              Offset.zero & size,
              Paint()..color = const Color(0xFFFFFFFF),
            );
            maleFlugtafeln(
              c,
              size,
              text: (
                titel: 'Stoos Gratweg',
                zeilen: const ['Klingenstock bis Fronalpstock'],
                deckkraft: deckkraft,
              ),
            );
            final bild = await sammler.endRecording().toImage(540, 960);
            final daten = await bild.toByteData();
            bild.dispose();
            return daten!;
          }))!;

      final ecke = texttafelEcke(const Size(540, 960)) + const Offset(6, 6);
      int rot(ByteData d) =>
          d.getUint8((ecke.dy.round() * 540 + ecke.dx.round()) * 4);
      expect(rot(await male(1)), lessThan(150));
      expect(rot(await male(0)), 255);
    });
  });

  group('Am Bildschirm', () {
    Gelaendemaler maler(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<Gelaendemaler>()
        .first;

    Widget ansicht({
      Flugstil stil = Flugstil.nahDran,
      List<Gelaendeschild> schilder = const [],
    }) {
      final n = _netz(ueberhoehung: stil.ueberhoehung);
      final s = _spur(n);
      return MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: Gelaendeansicht(
            netz: n,
            spur: s.linie,
            spurwerte: s.werte,
            stil: stil,
            titel: 'Probetour',
            schilder: schilder,
          ),
        ),
      );
    }

    testWidgets('Nah dran fliegt tief hinter dem Leuchtpunkt, mit Titel '
        'am Anfang und Ziel am Ende', (tester) async {
      final n = _netz(ueberhoehung: Flugstil.nahDran.ueberhoehung);
      final s = _spur(n);
      await tester.pumpWidget(
        ansicht(
          schilder: [
            Gelaendeschild(
              ort: s.linie.first,
              art: Wanderart.huette,
              name: 'Talstation',
            ),
            Gelaendeschild(
              ort: s.linie.last,
              art: Wanderart.gipfel,
              name: 'Gipfelkreuz',
            ),
          ],
        ),
      );
      await tester.pump();
      expect(maler(tester).leuchtspur, isFalse, reason: 'in der Übersicht');

      await tester.tap(find.byIcon(Icons.flight_takeoff));
      await tester.pump();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.02);
      await tester.pump();
      var m = maler(tester);
      expect(m.tafeln?.text?.titel, 'Probetour');
      expect(m.tafeln!.text!.zeilen, contains('Talstation bis Gipfelkreuz'));
      expect(
        m.tafeln!.text!.zeilen.any((z) => z.startsWith('rund ')),
        isTrue,
        reason: 'die Länge der Tour gehört auf die Titeltafel',
      );

      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.5);
      await tester.pump();
      m = maler(tester);
      expect(m.leuchtspur, isTrue);
      expect(m.kopf, isNotNull);
      expect(m.kamera.entfernung, lessThan(700), reason: 'nicht nah dran');
      expect(m.tafeln?.text, isNull, reason: 'mitten im Flug keine Tafel');

      tester.widget<Slider>(find.byType(Slider)).onChanged!(1.0);
      await tester.pump();
      m = maler(tester);
      expect(m.tafeln?.text?.titel, 'Gipfelkreuz');
      expect(
        m.tafeln!.text!.zeilen.first,
        'rund 700 m ü. M.',
        reason: 'die gemessene Höhe am Ende, auf zehn Meter',
      );
      // Die Zahlentafel des Überblicks gibt es hier nicht – die Zahlen
      // stehen auf der Zieltafel.
      expect(find.byKey(const ValueKey('gelaende-abspann')), findsNothing);
    });

    testWidgets('der Überblick bleibt ohne Leuchtspur und Tafeln', (
      tester,
    ) async {
      await tester.pumpWidget(ansicht(stil: Flugstil.ueberblick));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.flight_takeoff));
      await tester.pump();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.5);
      await tester.pump();
      expect(maler(tester).leuchtspur, isFalse);
      expect(maler(tester).tafeln, isNull);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(1.0);
      await tester.pump();
      expect(find.byKey(const ValueKey('gelaende-abspann')), findsOneWidget);
    });
  });

  group('Die Wahl', () {
    late Uint8List kachel;
    setUpAll(() async => kachel = await _terrariumKachel());

    var abrufe = 0;

    /// Wartet, bis die Landschaft (wieder) steht – das Laden läuft über
    /// echte Futures.
    Future<void> geladen(WidgetTester tester, {Flugstil? stil}) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        final da = find.byType(Gelaendeansicht).evaluate();
        if (da.isNotEmpty &&
            (stil == null ||
                (da.first.widget as Gelaendeansicht).stil == stil)) {
          return;
        }
      }
    }

    Future<void> zeige(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: GelaendeScreen(
            spur: const [
              (breite: 50.61, laenge: 9.86, hoehe: 400.0, zeit: null),
              (breite: 50.62, laenge: 9.88, hoehe: 620.0, zeit: null),
              (breite: 50.63, laenge: 9.90, hoehe: 550.0, zeit: null),
            ],
            titel: 'Probetour',
            netz: MockClient((_) async {
              abrufe++;
              return http.Response.bytes(kachel, 200);
            }),
            auflage: const Gelaendekarte(grund: Gelaendegrund.wanderkarte),
            videoschreiber: _Schreiber(),
            videoZiel: (_, _) async => null,
          ),
        ),
      );
      await geladen(tester);
    }

    Gelaendeansicht ansicht(WidgetTester tester) =>
        tester.widget<Gelaendeansicht>(find.byType(Gelaendeansicht));

    Future<void> waehle(WidgetTester tester, Flugstil stil) async {
      await tester.tap(find.byTooltip('Flugstil'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(stil == Flugstil.nahDran ? 'Nah dran' : 'Überblick'),
      );
      // Der Wechsel lädt neu (anderer Ausschnitt) – bis dahin dreht sich
      // ein Kreis, und `pumpAndSettle` käme nie zur Ruhe.
      await tester.pump(const Duration(milliseconds: 400));
      await geladen(tester, stil: stil);
    }

    testWidgets('umschalten lädt einen grösseren Ausschnitt und baut Netz '
        'und Spur neu', (tester) async {
      await zeige(tester);
      expect(ansicht(tester).stil, Flugstil.ueberblick);
      final vorher = ansicht(tester);
      expect(vorher.netz.ueberhoehung, gelaendeUeberhoehung);
      expect(find.textContaining('3-fach'), findsOneWidget);

      final abrufeVorher = abrufe;
      await waehle(tester, Flugstil.nahDran);
      final nach = ansicht(tester);
      expect(nach.stil, Flugstil.nahDran);
      expect(nach.netz.ueberhoehung, Flugstil.nahDran.ueberhoehung);
      expect(nach.netz.dreiecke, greaterThan(vorher.netz.dreiecke));
      expect(
        abrufe,
        greaterThan(abrufeVorher),
        reason: 'kein neuer Ausschnitt',
      );
      // Mehr Landschaft um die Spur: drei Kilometer statt eines Fünftels.
      expect(
        nach.netz.breiteMeter,
        greaterThan(vorher.netz.breiteMeter + 4000),
      );
      expect(nach.spur, hasLength(vorher.spur.length));
      // Die Linie liegt auf dem Gelände: Die Spur meldet am Anfang
      // 400 m, das Gelände dort steht anders – und flacher überhöht.
      expect(nach.spur.first.z, isNot(closeTo(vorher.spur.first.z, 1)));
      expect(find.textContaining('1,5-fach'), findsOneWidget);
      expect(nach.titel, 'Probetour');

      // Zurück, damit die Wahl der Sitzung keinen anderen Test färbt.
      await waehle(tester, Flugstil.ueberblick);
      expect(ansicht(tester).netz.ueberhoehung, gelaendeUeberhoehung);
      expect(ansicht(tester).netz.breiteMeter, vorher.netz.breiteMeter);
    });

    testWidgets('Nah dran schlägt für das Video das Hochformat vor', (
      tester,
    ) async {
      await zeige(tester);
      await waehle(tester, Flugstil.nahDran);
      await tester.tap(find.byIcon(Icons.movie_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Hochformat'), findsOneWidget);
      expect(find.textContaining('1080×1920'), findsWidgets);

      await tester.tap(find.text('Querformat'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1920×1080'), findsWidgets);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      await waehle(tester, Flugstil.ueberblick);
      await tester.tap(find.byIcon(Icons.movie_outlined));
      await tester.pumpAndSettle();
      // Im Überblick bleibt es beim Querformat.
      expect(find.textContaining('1920×1080'), findsWidgets);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
    });
  });
}
