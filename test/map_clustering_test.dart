import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/map_clustering.dart';

/// Ein Ort, wie ihn die Kartenansicht übergibt.
typedef Ort = ({double breite, double laenge});

Ort ort(double breite, double laenge) => (breite: breite, laenge: laenge);

/// Wie viele Grad ein Bildschirmpunkt bei dieser Zoomstufe abdeckt –
/// unabhängig von [rasterFuerZoom] aus der Web-Mercator-Formel
/// hergeleitet, sonst prüfte der Test sich selbst.
double gradJePunkt(double zoom) => 360.0 / (256.0 * (1 << zoom.toInt()));

void main() {
  group('rasterFuerZoom', () {
    test('halbiert sich mit jeder Zoomstufe', () {
      for (var z = 1.0; z <= 18; z++) {
        expect(rasterFuerZoom(z), closeTo(rasterFuerZoom(z - 1) / 2, 1e-12));
      }
    });

    test('eine Rasterzelle ist genau so breit wie ein Marker', () {
      // Die eigentliche Behauptung der Funktion.
      for (final z in [0.0, 6.0, 12.0, 18.0]) {
        expect(rasterFuerZoom(z) / gradJePunkt(z), closeTo(markerGroesse, 1e-9),
            reason: 'bei Zoom $z');
      }
    });
  });

  group('gruppiereFuerKarte', () {
    test('fasst dicht beieinanderliegende Fotos zusammen', () {
      final raster = rasterFuerZoom(6);
      final punkte = [
        ort(52.0, 10.0),
        ort(52.0 + raster / 10, 10.0 + raster / 10),
        ort(52.0 - raster / 10, 10.0),
      ];
      final gruppen = gruppiereFuerKarte(punkte, 6, (o) => o);
      expect(gruppen, hasLength(1));
      expect(gruppen.values.single, hasLength(3));
    });

    test('trennt sie beim Hineinzoomen wieder', () {
      // Genau der Zweck der zoomabhängigen Rastergröße: Was in der
      // Übersicht ein Punkt ist, muss sich auseinanderziehen lassen.
      final punkte = [ort(52.0, 10.0), ort(52.0, 10.02)];
      expect(gruppiereFuerKarte(punkte, 6, (o) => o), hasLength(1));
      expect(gruppiereFuerKarte(punkte, 14, (o) => o), hasLength(2));
    });

    test('behält die Eingabereihenfolge innerhalb einer Gruppe', () {
      // Der Marker zeigt das Vorschaubild des ersten Eintrags. Ginge die
      // Reihenfolge verloren, zeigte er ein beliebiges Foto der Gruppe
      // statt des jüngsten.
      final punkte = [ort(52.0, 10.0), ort(52.0001, 10.0001), ort(52.0002, 10.0)];
      final gruppe = gruppiereFuerKarte(punkte, 6, (o) => o).values.single;
      expect(gruppe, equals(punkte));
    });

    test('verliert kein Foto', () {
      final punkte = [
        for (var i = 0; i < 500; i++) ort(47 + i % 90 * 0.1, 6 + i % 70 * 0.13),
      ];
      for (final z in [4.0, 8.0, 12.0, 16.0]) {
        final gruppen = gruppiereFuerKarte(punkte, z, (o) => o);
        expect(gruppen.values.fold(0, (n, g) => n + g.length), punkte.length,
            reason: 'bei Zoom $z');
      }
    });

    test('deckelt die Markerdichte auch bei dichter Streuung', () {
      // Die eigentliche Zusicherung (siehe Doku): nicht "keine
      // Überlappung", sondern eine gedeckelte Dichte. Vor der Änderung
      // standen alle 2000 Marker übereinander.
      const zoom = 6.0;
      final raster = rasterFuerZoom(zoom);
      final punkte = [
        for (var i = 0; i < 2000; i++)
          ort(52 + (i % 40) * raster * 2 / 40, 10 + (i ~/ 40) * raster * 2 / 50),
      ];
      final gruppen = gruppiereFuerKarte(punkte, zoom, (o) => o);
      // Zwei mal zwei Zellen, durch das Runden je eine Randzelle mehr.
      expect(gruppen.length, lessThanOrEqualTo(9));
    });
  });

  group('schwerpunktVon', () {
    test('ein einzelnes Foto vertritt sich selbst', () {
      final s = schwerpunktVon([ort(53.55, 9.99)], (o) => o);
      expect(s.breite, closeTo(53.55, 1e-12));
      expect(s.laenge, closeTo(9.99, 1e-12));
    });

    test('liegt in der Mitte und nicht auf dem ersten Eintrag', () {
      // Der eigentliche Fehler auf dem Globus: Der Pin bekam die
      // Koordinate von `gruppe.first`. Bei 0,3 Grad Rasterweite – der
      // Weite beim Überblick – sind das über zwanzig Kilometer daneben.
      final gruppe = [ort(53.4, 9.8), ort(53.6, 10.2)];
      final s = schwerpunktVon(gruppe, (o) => o);
      expect(s.breite, closeTo(53.5, 1e-12));
      expect(s.laenge, closeTo(10.0, 1e-12));
      expect(s.breite, isNot(closeTo(gruppe.first.breite, 1e-6)));
    });

    test('die Reihenfolge der Eingabe ändert nichts', () {
      // Genau das war der Kern des Fehlers: Das Ergebnis hing daran,
      // welches Foto die Abfrage zuerst lieferte. Beim Zoomen ändern sich
      // die Gruppen, damit das erste Foto – und der Pin sprang.
      final a = [ort(48.1, 11.6), ort(52.5, 13.4), ort(50.0, 8.7)];
      final b = [a[2], a[0], a[1]];
      final sa = schwerpunktVon(a, (o) => o);
      final sb = schwerpunktVon(b, (o) => o);
      // Nicht auf das letzte Bit gleich: Eine Summe aus Gleitkommazahlen
      // hängt an der Reihenfolge der Summanden. Der Unterschied liegt bei
      // 1e-15 Grad – ein Milliardstel Millimeter. Was zählt, ist, dass er
      // nicht mehr sichtbar ist.
      expect(sa.breite, closeTo(sb.breite, 1e-12));
      expect(sa.laenge, closeTo(sb.laenge, 1e-12));
    });

    test('der Schwerpunkt liegt innerhalb der Hülle der Gruppe', () {
      final gruppe = [
        for (var i = 0; i < 20; i++) ort(47 + i * 0.31, 6 + i * 0.17)
      ];
      final s = schwerpunktVon(gruppe, (o) => o);
      expect(s.breite, greaterThanOrEqualTo(47));
      expect(s.breite, lessThanOrEqualTo(47 + 19 * 0.31));
      expect(s.laenge, greaterThanOrEqualTo(6));
      expect(s.laenge, lessThanOrEqualTo(6 + 19 * 0.17));
    });

    test('eine Gruppe reicht nie über den Datumswechsel', () {
      // Die Absicherung für die Rechnung: Ein Mittelwert aus 179 und
      // -179 wäre 0 – mitten im Atlantik. Das kann nicht vorkommen, weil
      // die Gruppierung beiderseits von ±180 verschiedene Zellen bildet.
      // Dieser Test hält diese Voraussetzung fest.
      final gruppen = gruppiereFuerKarte(
          [ort(0, 179.99), ort(0, -179.99)], 4.0, (o) => o);
      expect(gruppen.length, 2);
    });

    test('gruppieren und Schwerpunkt greifen ineinander', () {
      // Der Weg, den der Globus geht: erst rastern, dann je Gruppe den
      // vertretenden Punkt. Zwei Fotos einer Zelle geben einen Pin, und
      // der liegt zwischen ihnen.
      final punkte = [ort(53.50, 9.95), ort(53.52, 10.01), ort(40.0, -3.7)];
      final gruppen = gruppiereFuerKarte(punkte, 8.0, (o) => o);
      expect(gruppen.length, 2);
      final hamburg =
          gruppen.values.firstWhere((g) => g.length == 2);
      final s = schwerpunktVon(hamburg, (o) => o);
      expect(s.breite, closeTo(53.51, 1e-9));
      expect(s.laenge, closeTo(9.98, 1e-9));
    });
  });
}