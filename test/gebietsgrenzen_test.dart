import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gebietsgrenzen.dart';

/// Der Umrissdatensatz, so wie er ausgeliefert wird.
///
/// **Gegen die echte Datei und nicht gegen ein Beispiel.** Ein selbst
/// geschriebenes Dreieck würde beweisen, dass das Strahlverfahren
/// rechnet – nicht, dass Flensburg in Schleswig-Holstein liegt. Genau das
/// war die Beschwerde.
Gebietsgrenzen _laden() => Gebietsgrenzen.ausGepackt(
    File('assets/geo/gebiete.bin.gz').readAsBytesSync());

void main() {
  late Gebietsgrenzen g;
  setUpAll(() => g = _laden());

  group('einlesen', () {
    test('kennt Länder und Regionen', () {
      // 236 Länder und 3304 Regionen. Die Zahl steht hier, damit ein
      // neuer Lauf von tool/gebiete_bauen.py auffällt, statt still
      // weniger auszuliefern.
      expect(g.anzahl, 3540);
    });

    test('ein Umriss hat mehrere Ringe, wenn das Land Inseln hat', () {
      // Griechenland ohne Inseln wäre kein Griechenland.
      expect(g.land('GR')!.ringe.length, greaterThan(5));
      // Ein Binnenland kommt mit einem aus.
      expect(g.land('CH')!.ringe.length, 1);
    });

    test('unbekannte Schlüssel geben null statt zu werfen', () {
      expect(g.land('XX'), isNull);
      expect(g.region('DE.99'), isNull);
    });

    test('Kleinschreibung führt zum selben Land', () {
      expect(g.land('de')!.schluessel, g.land('DE')!.schluessel);
    });
  });

  group('welches Gebiet liegt unter dem Punkt', () {
    test('Flensburg liegt in Schleswig-Holstein', () {
      // Der Fall aus der Beschwerde. Über die nächstgelegene Stadt
      // gemessen ist das eine Vermutung; im Umriss ist es eine Antwort.
      expect(g.landBei(54.7836, 9.4321), 'DE');
      expect(g.regionBei(54.7836, 9.4321, imLand: 'DE'), 'DE.10');
    });

    test('Hannover liegt in Niedersachsen', () {
      expect(g.regionBei(52.3705, 9.7332, imLand: 'DE'), 'DE.06');
    });

    test('Berlin gewinnt gegen Brandenburg', () {
      // Die Umrisse haben keine Löcher: Brandenburgs Ring umschliesst
      // Berlin mit. Ohne die Regel „die kleinere Fläche gewinnt" käme
      // hier je nach Reihenfolge in der Datei mal das eine, mal das
      // andere heraus.
      expect(g.regionBei(52.52, 13.405, imLand: 'DE'), 'DE.16');
      expect(g.region('DE.11')!.enthaelt(52.52, 13.405), isTrue,
          reason: 'Brandenburg enthält den Punkt ebenfalls');
    });

    test('Lesotho gewinnt gegen Südafrika', () {
      expect(g.landBei(-29.31, 27.48), 'LS');
      expect(g.land('ZA')!.enthaelt(-29.31, 27.48), isTrue);
    });

    test('auf offener See liegt kein Land', () {
      // Die Umkehr-Geokodierung liefert hier noch eine Stadt in
      // dreihundert Kilometern Entfernung. Ein Haken auf einem Land, in
      // dem man nie war, ist schlimmer als kein Haken.
      expect(g.landBei(55.5, 4.0), isNull);
      expect(g.landBei(-30.0, -30.0), isNull);
    });

    test('ohne Einengung auf ein Land findet die Region trotzdem', () {
      expect(g.regionBei(52.3705, 9.7332), 'DE.06');
    });

    test('Italien und Frankreich haben ihre Regionen', () {
      // Der Fall, der die Zuordnung über Ortsnamen erzwungen hat: Für
      // Italien, Frankreich und Grossbritannien laufen die
      // GeoNames-Kennungen in Natural Earth ins Leere – Frankreich hat
      // seine Regionen 2016 neu geschnitten, Italien führt Natural Earth
      // als 107 Provinzen. Über die enthaltenen Orte gefunden stimmen
      // sie wieder.
      expect(g.regionBei(41.9028, 12.4964, imLand: 'IT'), 'IT.07'); // Latium
      expect(g.regionBei(45.4642, 9.19, imLand: 'IT'), 'IT.09'); // Lombardei
      expect(g.regionBei(48.8566, 2.3522, imLand: 'FR'), 'FR.11'); // Île-de-France
      expect(g.regionBei(51.5074, -0.1278, imLand: 'GB'), 'GB.ENG');
    });

    test('die Einengung schliesst fremde Regionen aus', () {
      // Ein Punkt in Polen, aber nach deutschen Regionen gefragt: Die
      // Antwort ist „keine" und nicht „die nächstbeste".
      expect(g.regionBei(50.0647, 19.945, imLand: 'PL'), 'PL.77');
      expect(g.regionBei(50.0647, 19.945, imLand: 'DE'), isNull);
    });
  });

  group('was fehlt, fehlt sichtbar', () {
    test('der Vatikan hat keinen Umriss', () {
      // Natural Earth zeichnet ihn als Fünfeck rund anderthalb Kilometer
      // westlich seiner GeoNames-Koordinate: eine Fläche, die den
      // eigenen Mittelpunkt nicht enthält. Das Bauskript lässt Gebiete
      // unter 0,05 Grad Ausdehnung deshalb weg – siebzehn der 252
      // GeoNames-Länder haben aus diesem und ähnlichen Gründen keinen
      // Umriss und bleiben ein Punkt auf der Karte.
      expect(g.land('VA'), isNull);
      expect(g.land('GI'), isNull); // Gibraltar, 6,8 km²
      expect(g.landBei(41.9029, 12.4534), 'IT');
    });

    test('Taiwan trägt seinen eigenen Code', () {
      // Natural Earth schreibt „CN-TW" in die Spalte ISO_A2. Ohne die
      // Prüfung auf genau zwei Buchstaben läge Taiwan unter einem
      // Schlüssel, den die App nie abfragt.
      expect(g.land('TW'), isNotNull);
    });
  });

  group('Hilfsmasse', () {
    test('die Hülle umschliesst das Gebiet', () {
      final h = Gebietsgrenzen.huelle(g.land('DE')!);
      expect(h.sued, closeTo(47.3, 0.5));
      expect(h.nord, closeTo(55.0, 0.5));
      expect(h.west, closeTo(5.9, 0.5));
      expect(h.ost, closeTo(15.0, 0.5));
    });

    test('der Mittelpunkt liegt im Land', () {
      final m = Gebietsgrenzen.mittelpunkt(g.land('DE')!);
      expect(g.land('DE')!.enthaelt(m.breite, m.laenge), isTrue);
    });
  });
}
