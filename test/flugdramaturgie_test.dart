// Einflug, Fotos entlang der Strecke, Abspann.
//
// Was hier geprüft wird, ist die Dramaturgie: dass der Flug nicht mitten
// in der Landschaft anfängt, dass zum richtigen Zeitpunkt das richtige
// Foto steht, und dass am Ende die Zahlen der Tour kommen. Alles drei
// hat mit dem Gelände nichts zu tun und mit der Frage viel, warum
// jemand einen Überflug überhaupt ansieht.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/gelaendeflug.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/widgets/gelaende.dart';

Gelaendenetz _netz() {
  const n = 24;
  final h = Float32List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      h[y * n + x] = 400 + 60.0 * y;
    }
  }
  return baueNetz(
      Hoehengitter(
          spalten: n, zeilen: n, hoehen: h,
          nord: 51.85, sued: 51.83, west: 10.63, ost: 10.66),
      kante: 24);
}

/// Eine Spur quer durch die Landschaft, mit Höhen und Zeiten.
({List<Raumpunkt> linie, List<Flugwert> werte}) _spur(Gelaendenetz netz) {
  final linie = <Raumpunkt>[];
  final werte = <Flugwert>[];
  final start = DateTime.utc(2026, 8, 30, 9);
  for (var i = 0; i <= 40; i++) {
    final t = i / 40;
    linie.add((
      x: (t - 0.5) * netz.breiteMeter,
      y: (t - 0.5) * netz.hoeheMeter,
      z: 100 * t,
    ));
    // Erst hinauf, dann hinunter – eine Rundtour, bei der die reine
    // Differenz null ergäbe.
    werte.add((
      hoehe: 400 + (t < 0.5 ? 400 * t * 2 : 400 * (1 - t) * 2),
      zeit: start.add(Duration(minutes: i * 3)),
    ));
  }
  return (linie: linie, werte: werte);
}

/// Ein Bild, das nie geladen wird – der Test fragt nur, ob es im Baum
/// steht, nicht wie es aussieht.
class _Attrappe extends ImageProvider<_Attrappe> {
  const _Attrappe(this.name);
  final String name;

  @override
  Future<_Attrappe> obtainKey(ImageConfiguration c) async => this;

  @override
  ImageStreamCompleter loadImage(_Attrappe key, ImageDecoderCallback d) =>
      OneFrameImageStreamCompleter(Completer<ImageInfo>().future);

  @override
  bool operator ==(Object other) => other is _Attrappe && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

void main() {
  group('Die Zahlen der Tour', () {
    test('der Aufstieg zaehlt nur, was hinaufgeht', () {
      final netz = _netz();
      final s = _spur(netz);
      final flug = Gelaendeflug(s.linie, werte: s.werte);
      // Die Spur steigt von 400 auf 800 und faellt zurueck auf 400.
      // Die reine Differenz waere null - der Aufstieg ist 400.
      expect(flug.aufstiegMeter, closeTo(400, 25));
    });

    test('Rauschen zaehlt nicht mit', () {
      // Ohne Schwelle addierte jeder Zentimeter Messrauschen sich zu
      // hunderten Metern Aufstieg auf ebener Strecke.
      final linie = [
        for (var i = 0; i <= 200; i++) (x: i * 10.0, y: 0.0, z: 0.0),
      ];
      final werte = <Flugwert>[
        for (var i = 0; i <= 200; i++)
          (hoehe: 500 + (i.isEven ? 1.0 : -1.0), zeit: null),
      ];
      expect(Gelaendeflug(linie, werte: werte).aufstiegMeter, 0);
    });

    test('ohne Hoehen gibt es keinen Aufstieg – und keine Null', () {
      // Null hiesse „flach", und das ist etwas anderes als „unbekannt".
      final linie = [
        for (var i = 0; i <= 10; i++) (x: i * 10.0, y: 0.0, z: 0.0),
      ];
      final werte = <Flugwert>[
        for (var i = 0; i <= 10; i++) (hoehe: null, zeit: null),
      ];
      expect(Gelaendeflug(linie, werte: werte).aufstiegMeter, isNull);
    });

    test('die Dauer kommt aus den Zeitstempeln', () {
      final netz = _netz();
      final s = _spur(netz);
      expect(Gelaendeflug(s.linie, werte: s.werte).gesamtdauer,
          const Duration(minutes: 120));
    });

    test('eine rueckwaerts laufende Uhr ergibt keine Dauer', () {
      // Kommt in echten Dateien vor.
      final linie = [
        for (var i = 0; i <= 4; i++) (x: i * 10.0, y: 0.0, z: 0.0),
      ];
      final start = DateTime.utc(2026, 8, 30, 9);
      final werte = <Flugwert>[
        for (var i = 0; i <= 4; i++)
          (hoehe: null, zeit: start.subtract(Duration(minutes: i))),
      ];
      expect(Gelaendeflug(linie, werte: werte).gesamtdauer, isNull);
    });
  });

  group('Am Bildschirm', () {
    Widget bildschirm(
        {List<Flugfoto> fotos = const [], Gelaendenetz? netz}) {
      final n = netz ?? _netz();
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
            fotos: fotos,
          ),
        ),
      );
    }

    testWidgets('der Flug faengt nicht mitten in der Landschaft an',
        (tester) async {
      // **Der Einflug beantwortet die Frage, die vor allen anderen
      // kommt: wo sind wir ueberhaupt.** Ohne ihn stand die Kamera im
      // ersten Bild schon am Boden.
      await tester.pumpWidget(bildschirm());
      await tester.pump();
      Gelaendemaler maler() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<Gelaendemaler>()
          .first;
      final uebersicht = maler().kamera.entfernung;

      await tester.tap(find.byIcon(Icons.flight_takeoff));
      await tester.pump();
      // Im ersten Bild des Fluges muss die Kamera noch fast so weit weg
      // stehen wie in der Uebersicht.
      final gleichZuBeginn = maler().kamera.entfernung;
      expect(gleichZuBeginn, closeTo(uebersicht, uebersicht * 0.1),
          reason: 'der Einflug springt statt zu fliegen');

      // Und nach einem Viertel der Vorfuehrung deutlich naeher.
      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.25);
      await tester.pump();
      expect(maler().kamera.entfernung, lessThan(uebersicht * 0.5),
          reason: 'der Einflug kommt nie an');
    });

    testWidgets('am Ende stehen die Zahlen der Tour', (tester) async {
      await tester.pumpWidget(bildschirm());
      await tester.pump();
      await tester.tap(find.byIcon(Icons.flight_takeoff));
      await tester.pump();
      final t = AppTexte.of(
          tester.element(find.byType(Gelaendeansicht)));
      expect(find.text(t.flugAufstieg), findsNothing,
          reason: 'der Abspann gehoert ans Ende, nicht an den Anfang');

      tester.widget<Slider>(find.byType(Slider)).onChanged!(1.0);
      await tester.pump();
      // Auf den Abspann eingegrenzt: „unterwegs" steht auch in der
      // Flugleiste darunter, und der Test soll den Abspann pruefen.
      final abspann = find.byKey(const ValueKey('gelaende-abspann'));
      expect(abspann, findsOneWidget);
      expect(find.descendant(of: abspann, matching: find.text(t.flugAufstieg)),
          findsOneWidget);
      expect(find.descendant(of: abspann, matching: find.text(t.flugUnterwegs)),
          findsOneWidget);
      // Die Laenge der Tour, in Kilometern.
      expect(find.descendant(of: abspann, matching: find.textContaining('km')),
          findsOneWidget);
    });

    testWidgets('das Foto taucht dort auf, wo es entstanden ist – und '
        'bleibt, bis das naechste kommt', (tester) async {
      final n = _netz();
      final s = _spur(n);
      final laenge = Gelaendeflug(s.linie, werte: s.werte).laengeMeter;
      await tester.pumpWidget(bildschirm(netz: n, fotos: [
        (
          meter: laenge * 0.2,
          bild: const _Attrappe('frueh'),
          unterschrift: '09:30'
        ),
        (
          meter: laenge * 0.8,
          bild: const _Attrappe('spaet'),
          unterschrift: '11:00'
        ),
      ]));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.flight_takeoff));
      await tester.pump();

      String? sichtbar() {
        final bilder = tester.widgetList<Image>(find.byType(Image));
        for (final b in bilder) {
          final a = b.image;
          if (a is _Attrappe) return a.name;
        }
        return null;
      }

      // **Vor dem ersten Foto bleibt es leer.** Ein vorgezogenes Bild
      // behauptete eine Stelle, an der es nicht entstanden ist.
      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.10);
      await tester.pump();
      expect(sichtbar(), isNull, reason: 'vor dem ersten Foto steht keines');

      // Der Flugabschnitt liegt zwischen 7 % und 90 % der Uhr; 20 % der
      // Strecke sind also rund 24 % der Vorfuehrung.
      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.26);
      await tester.pump();
      expect(sichtbar(), 'frueh');

      // **Und es bleibt stehen.** Hier stand einmal die umgekehrte
      // Erwartung – „zwischen den Fotos darf keines stehen". Wer nicht
      // gleichmaessig fotografiert, sah damit fast nichts: an einer
      // echten Wanderung 22 % des Fluges mit Bild, die ersten 28 % ohne.
      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.50);
      await tester.pump();
      expect(sichtbar(), 'frueh',
          reason: 'das letzte Bild gilt weiter, bis eines an seine Stelle tritt');

      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.75);
      await tester.pump();
      expect(sichtbar(), 'spaet');

      // Nach dem letzten bleibt das letzte – es wird von nichts abgeloest.
      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.95);
      await tester.pump();
      expect(sichtbar(), 'spaet');
    });

    testWidgets('ohne Fotos steht auch keines da', (tester) async {
      await tester.pumpWidget(bildschirm());
      await tester.pump();
      await tester.tap(find.byIcon(Icons.flight_takeoff));
      await tester.pump();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.5);
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    });
  });
}
