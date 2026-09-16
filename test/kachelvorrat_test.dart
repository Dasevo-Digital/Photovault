import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/kachelvorrat.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// **Was muss geladen werden, damit meine Fotogebiete auf der Platte
/// liegen?**
///
/// Die Rechnung steht hier getrennt vom Herunterladen, weil sie sich
/// sonst nicht prüfen liesse – und weil ein Fehler darin teuer ist: Eine
/// Stufe zu viel vervierfacht die Zahl der Kacheln.
void main() {
  group('Gebiete aus Fotoorten', () {
    test('nahe beieinander wird ein Gebiet', () {
      final g = gebieteAus([
        (breite: 51.9, laenge: 10.4),
        (breite: 52.0, laenge: 10.5),
      ]);
      expect(g.length, 1);
    });

    test('weit auseinander werden zwei', () {
      final g = gebieteAus([
        (breite: 51.9, laenge: 10.4), // Goslar
        (breite: 36.0, laenge: 68.0), // Afghanistan
      ]);
      expect(g.length, 2);
    });

    test('jedes Gebiet bekommt einen Rand', () {
      // Ohne ihn endete die Karte genau am letzten Foto, und beim ersten
      // Schieben stünde man im Ungeladenen.
      final g = gebieteAus([(breite: 51.9, laenge: 10.4)]).single;
      expect(g.sued, lessThan(51.9));
      expect(g.nord, greaterThan(51.9));
      expect(g.west, lessThan(10.4));
      expect(g.ost, greaterThan(10.4));
    });

    test('bleibt in den Grenzen der Erde', () {
      final g = gebieteAus([(breite: 84.99, laenge: 179.99)]).single;
      expect(g.nord, lessThanOrEqualTo(85.0));
      expect(g.ost, lessThanOrEqualTo(180.0));
    });

    test('ohne Fotos gibt es nichts zu laden', () {
      expect(gebieteAus(const []), isEmpty);
    });
  });

  group('Die Kachelliste', () {
    test('deckt das Gebiet auf jeder Stufe ab', () {
      final gebiet = [
        (sued: 51.8, west: 10.3, nord: 52.0, ost: 10.6)
      ];
      final kacheln = kachelListe(gebiet, von: 6, bis: 8);
      expect(kacheln.where((k) => k.z == 6), isNotEmpty);
      expect(kacheln.where((k) => k.z == 7), isNotEmpty);
      expect(kacheln.where((k) => k.z == 8), isNotEmpty);
    });

    test('zählt eine Kachel nur einmal, auch bei Überlappung', () {
      // Zwei Gebiete, die sich auf niedriger Stufe dieselbe Kachel
      // teilen. Ohne Entdopplung lüde man sie zweimal.
      final kacheln = kachelListe([
        (sued: 51.0, west: 10.0, nord: 51.2, ost: 10.2),
        (sued: 51.1, west: 10.1, nord: 51.3, ost: 10.3),
      ], von: 4, bis: 4);
      final schluessel = {for (final k in kacheln) '${k.z}/${k.x}/${k.y}'};
      expect(kacheln.length, schluessel.length);
    });

    test('der Norden bekommt die kleinere Nummer', () {
      // Die y-Achse zeigt nach unten. Wer das verwechselt, lädt ein
      // leeres Rechteck.
      final kacheln = kachelListe([
        (sued: 40.0, west: 10.0, nord: 55.0, ost: 11.0)
      ], von: 5, bis: 5);
      final ys = kacheln.map((k) => k.y).toSet();
      expect(ys.length, greaterThan(1),
          reason: 'fünfzehn Breitengrade sind mehr als eine Kachel');
    });

    test('die Zahl bleibt beherrschbar', () {
      // Ein Gebiet von rund 100 km Kantenlänge bis Stufe 14.
      final kacheln = kachelListe([
        (sued: 51.5, west: 10.0, nord: 52.4, ost: 11.4)
      ]);
      expect(kacheln.length, lessThan(20000),
          reason: 'sonst ist die obere Stufe zu hoch gewählt');
      // ignore: avoid_print
      print('ein Gebiet von 100 km: ${kacheln.length} Kacheln');
    });
  });

  group('Die Adresse', () {
    test('setzt Stufe und Lage ein', () {
      final url = kachelAdresse(Kartenstil.topo, (z: 7, x: 68, y: 44));
      expect(url, 'https://tile.opentopomap.org/7/68/44.png');
    });

    test('lässt keinen Platzhalter stehen', () {
      // Ein übrig gebliebenes {r} oder {s} führte zu einer Adresse, die
      // der Server nicht kennt – und die Kachel läge unter einem
      // Schlüssel, den die Karte später nie anfragt.
      for (final stil in Kartenstil.values) {
        final url = kachelAdresse(stil, (z: 5, x: 1, y: 2));
        expect(url, isNot(contains('{')), reason: stil.name);
      }
    });
  });
}
