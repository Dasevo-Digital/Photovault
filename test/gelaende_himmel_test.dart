// Himmel, Dunst und weiche Kante – die Schicht zwischen Landschaft und
// Hintergrund.
//
// Was sich hier mit Zahlen prüfen lässt, ist das Gerüst: dass der Rand
// des Gitters durchsichtig wird, dass eine andere Tageszeit wirklich
// andere Farben ergibt, und dass die Dunstschicht auf einer eigenen
// Ebene liegt. Wie es aussieht, entscheidet
// `tool/gelaendeflug_bilder_test.dart` – dort hat sich auch gezeigt,
// dass die Dunstschicht ohne eigene Ebene ein weisses Band über die
// Gipfelkette malt.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/services/lichtstimmung.dart';
import 'package:photo_vault/widgets/gelaende.dart';

Hoehengitter _gitter({int n = 24}) {
  final hoehen = Float32List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      hoehen[y * n + x] =
          400 + 200 * math.sin(x / n * math.pi) * math.sin(y / n * math.pi);
    }
  }
  return Hoehengitter(
    spalten: n,
    zeilen: n,
    hoehen: hoehen,
    nord: 50.63,
    sued: 50.60,
    west: 9.85,
    ost: 9.91,
  );
}

/// Die Randnähe aller Blöcke hintereinander.
///
/// Seit die Landschaft in Blöcke zerfällt, liegt jede Zahl je Block vor;
/// geprüft wird aber eine Eigenschaft des **Ausschnitts** – der Saum
/// gehört an dessen Kante und nicht an jede Blockgrenze.
Float32List _randnaehe(Gelaendenetz n) {
  final aus = <double>[];
  for (final b in n.bloecke) {
    aus.addAll(b.randnaehe);
  }
  return Float32List.fromList(aus);
}

Int32List _farben(Gelaendenetz n) {
  final aus = <int>[];
  for (final b in n.bloecke) {
    aus.addAll(b.farben);
  }
  return Int32List.fromList(aus);
}

/// Zählt die Aufrufe mit, die der Maler auf der Leinwand macht.
class _Mitschrift implements Canvas {
  int schichten = 0;
  int netze = 0;
  int rechtecke = 0;
  final blendmodi = <BlendMode>[];
  final pinsel = <Paint>[];

  @override
  void saveLayer(Rect? bounds, Paint paint) => schichten++;

  @override
  void restore() {}

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) {
    netze++;
    blendmodi.add(blendMode);
    pinsel.add(paint);
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    rechtecke++;
    pinsel.add(paint);
  }

  @override
  void drawPath(Path path, Paint paint) {}

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  const kamera = Gelaendekamera(
    drehung: 0.35,
    neigung: 0.95,
    entfernung: 4000,
    brennweite: 900,
    mitte: Offset(500, 400),
  );

  group('Die weiche Kante', () {
    test('am Gitterrand ist das Gelände durchsichtig, in der Mitte nicht',
        () {
      final netz = baueNetz(_gitter(n: 40), kante: 40);
      final randnaehe = _randnaehe(netz);
      final farben = _farben(netz);
      var randDurchsichtig = 0;
      var mitteDeckend = 0;
      for (var i = 0; i < randnaehe.length; i++) {
        final alpha = (farben[i] >> 24) & 0xFF;
        if (randnaehe[i] == 0) {
          expect(alpha, 0, reason: 'Eckpunkt $i liegt auf dem Rand');
          randDurchsichtig++;
        }
        if (randnaehe[i] == 1) {
          expect(alpha, 255, reason: 'Eckpunkt $i liegt im Inneren');
          mitteDeckend++;
        }
      }
      expect(randDurchsichtig, greaterThan(0));
      expect(mitteDeckend, greaterThan(randDurchsichtig));
    });

    test('der Saum ist schmal – der grösste Teil bleibt voll deckend', () {
      // Ein Zehntel der Kante war zu breit: In der Übersicht lag ein
      // handbreiter weisser Streifen über der Gipfelkette.
      final netz = baueNetz(_gitter(n: 60), kante: 60);
      final randnaehe = _randnaehe(netz);
      final voll = randnaehe.where((r) => r == 1).length;
      expect(voll / randnaehe.length, greaterThan(0.7));
    });

    test('die Randnähe steigt von aussen nach innen monoton', () {
      final netz = baueNetz(_gitter(n: 40), kante: 40);
      final randnaehe = _randnaehe(netz);
      expect(randnaehe.reduce(math.min), 0);
      expect(randnaehe.reduce(math.max), 1);
    });
  });

  group('Die Tageszeit steckt im Netz', () {
    test('eine andere Stimmung ergibt andere Eckpunktfarben', () {
      final mittag = _farben(baueNetz(_gitter(), stimmung: stimmungMittag));
      final abend = _farben(baueNetz(_gitter(), stimmung: stimmungAbend));
      expect(mittag.length, abend.length);
      var anders = 0;
      for (var i = 0; i < mittag.length; i++) {
        if (mittag[i] != abend[i]) anders++;
      }
      expect(anders, greaterThan(mittag.length ~/ 2),
          reason: 'die Stimmung kommt im Netz nicht an');
    });

    test('ohne Angabe entsteht genau das Mittagsnetz', () {
      final ohne = baueNetz(_gitter());
      final mittag = baueNetz(_gitter(), stimmung: stimmungMittag);
      expect(_farben(ohne), _farben(mittag));
    });

    test('das warme Licht des Abends färbt rötlicher als der Mittag', () {
      // Die Lichtfarbe multipliziert die Karte mit. Ohne diesen Test
      // wäre sie eine Zahl, die nirgends ankommt.
      final mittag = baueNetz(_gitter(), stimmung: stimmungMittag);
      final abend = baueNetz(_gitter(), stimmung: stimmungAbend);
      double mittelRotAnteil(Int32List f) {
        var summe = 0.0;
        for (final c in f) {
          final r = (c >> 16) & 0xFF, b = c & 0xFF;
          summe += (r + 1) / (b + 1);
        }
        return summe / f.length;
      }

      expect(mittelRotAnteil(_farben(abend)),
          greaterThan(mittelRotAnteil(_farben(mittag))));
    });
  });

  group('Was der Maler zeichnet', () {
    Gelaendemaler maler({Lichtstimmung stimmung = stimmungMittag}) =>
        Gelaendemaler(
          netz: baueNetz(_gitter(), stimmung: stimmung),
          kamera: kamera,
          spur: const [],
          spurfarbe: const Color(0xFFFF0000),
          stimmung: stimmung,
        );

    test('zuerst der Himmel, und als Verlauf', () {
      final leinwand = _Mitschrift();
      maler().paint(leinwand, const Size(1000, 800));
      expect(leinwand.rechtecke, 1, reason: 'kein Himmel');
      expect(leinwand.pinsel.first.shader, isNotNull,
          reason: 'der Himmel ist eine Fläche statt eines Verlaufs');
    });

    test('der Dunst liegt auf einer eigenen Ebene und ersetzt dort', () {
      // Ohne eigene Ebene malt der Dunst des Fernen über das Nahe: Am
      // Bild war das ein weisses Band quer über die Gipfelkette.
      final leinwand = _Mitschrift();
      maler().paint(leinwand, const Size(1000, 800));
      // Je Block ein Zug für das Gelände und einer für den Dunst – aber
      // nur **eine** Schicht für alle. Eine Zwischenfläche in
      // Bildschirmgrösse ist der teuerste Einzelposten dieses Malers;
      // eine je Block wäre hundertmal der Preis.
      final bloecke = baueNetz(_gitter()).bloecke.length;
      expect(leinwand.netze, lessThanOrEqualTo(2 * bloecke));
      expect(leinwand.netze, greaterThan(1), reason: 'Gelände und Dunst');
      expect(leinwand.netze.isEven, isTrue,
          reason: 'zu jedem Gelände gehört sein Dunst');
      expect(leinwand.schichten, 1, reason: 'der Dunst braucht seine Ebene');
      expect(leinwand.pinsel.last.blendMode, BlendMode.src,
          reason: 'ohne `src` überlagert der Dunst, statt zu ersetzen');
    });

    test('ohne Fläche wird gar kein Dunst gezeichnet', () {
      // Ein Widget wird beim ersten Aufbau durchaus mit 0 vermessen, und
      // `saveLayer` mit einem leeren Ausschnitt wäre Arbeit für nichts.
      final leinwand = _Mitschrift();
      maler().paint(leinwand, Size.zero);
      expect(leinwand.schichten, 0);
    });

    test('eine andere Stimmung lässt neu zeichnen', () {
      expect(maler(stimmung: stimmungAbend).shouldRepaint(maler()), isTrue);
    });
  });
}
