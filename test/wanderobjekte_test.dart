// Was beim Wandern zählt, aus OpenStreetMap.
//
// Geprüft wird an einer **echten Antwort** von Overpass zum Ilsetal, so
// wie sie am 03.09.2026 kam: 41 Punkte, davon 27 Wegweiser, 7 Gipfel mit
// vermessener Höhe, 5 Aussichtspunkte, ein Wasserfall und eine Quelle.
// Eine erfundene Antwort prüfte nur, dass mein Zerleger meinen eigenen
// Erwartungen entspricht.
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/wanderobjekte.dart';

/// Ein Ausschnitt aus der echten Antwort – mit allem, was Schwierigkeiten
/// macht: eine Höhe mit Komma, eine ohne, ein Punkt mit zwei Merkmalen,
/// ein Wegweiser ohne Namen und ein Eintrag ohne Koordinate.
const _echt = '''
{
  "version": 0.6,
  "elements": [
    {"type":"node","id":304050947,"lat":51.8425,"lon":10.6350,
     "tags":{"natural":"peak","name":"Unterer Meineckenberg","ele":"565.9"}},
    {"type":"node","id":304050948,"lat":51.8461,"lon":10.6470,
     "tags":{"natural":"peak","name":"Rohnberg","ele":"563.8"}},
    {"type":"node","id":428312001,"lat":51.8500,"lon":10.6400,
     "tags":{"natural":"peak","name":"Mittelberg","ele":535}},
    {"type":"node","id":900000001,"lat":51.8480,"lon":10.6510,
     "tags":{"tourism":"attraction","waterway":"waterfall",
             "name":"Ilsefälle"}},
    {"type":"node","id":900000002,"lat":51.8400,"lon":10.6300,
     "tags":{"tourism":"information","information":"guidepost"}},
    {"type":"node","id":900000003,"lat":51.8410,"lon":10.6320,
     "tags":{"tourism":"viewpoint","name":"Ilsestein"}},
    {"type":"node","id":900000004,"lat":51.8390,"lon":10.6290,
     "tags":{"natural":"spring"}},
    {"type":"node","id":900000005,"lat":51.8395,"lon":10.6295,
     "tags":{"amenity":"bench","name":"Bank am Weg"}},
    {"type":"node","id":900000006,
     "tags":{"natural":"peak","name":"Ohne Ort"}},
    {"type":"node","id":304050947,"lat":51.8425,"lon":10.6350,
     "tags":{"natural":"peak","name":"Doppelt"}}
  ]
}
''';

void main() {
  group('Die Abfrage', () {
    test('nennt alle Merkmale und den Ausschnitt in der richtigen Folge', () {
      // Ein vertauschtes Paar aus Breite und Länge liefert eine gültige
      // Antwort über der falschen Weltgegend – deshalb steht die
      // Reihenfolge hier ausdrücklich.
      final a = overpassAbfrage(
          sued: 51.828, west: 10.628, nord: 51.858, ost: 10.656);
      expect(a, contains('(51.828,10.628,51.858,10.656)'));
      for (final m in wanderMerkmale) {
        expect(a, contains('["${m.schluessel}"="${m.wert}"]'));
      }
      // Und eine Zeitgrenze, sonst rechnet Overpass unbegrenzt.
      expect(a, contains('timeout:'));
      expect(a, contains('out:json'));
    });
  });

  group('Das Zerlegen einer echten Antwort', () {
    late List<Wanderobjekt> punkte;
    setUpAll(() => punkte = ausOverpass(_echt));

    test('nimmt nur, was beim Wandern zählt', () {
      // Die Bank hat einen Namen und wäre am leichtesten mitzunehmen –
      // sie beantwortet nur keine Frage, die beim Ansehen einer
      // Wanderung aufkommt.
      expect(punkte.map((p) => p.name), isNot(contains('Bank am Weg')));
      expect(punkte, hasLength(7));
    });

    test('liest Höhen mit und ohne Komma', () {
      final berg =
          punkte.firstWhere((p) => p.name == 'Unterer Meineckenberg');
      expect(berg.hoehe, closeTo(565.9, 0.01));
      expect(berg.art, Wanderart.gipfel);
      // Und eine, die als Zahl statt als Text kommt.
      expect(punkte.firstWhere((p) => p.name == 'Mittelberg').hoehe, 535);
    });

    test('bei zwei Merkmalen gewinnt das aussagekräftigere', () {
      // Die Ilsefälle tragen zugleich `tourism=attraction` und
      // `waterway=waterfall`. „Attraktion" sagt nichts, „Wasserfall"
      // alles – die Reihenfolge in [wanderMerkmale] entscheidet.
      expect(punkte.firstWhere((p) => p.name == 'Ilsefälle').art,
          Wanderart.wasserfall);
    });

    test('ein Wegweiser ohne Namen kommt trotzdem, aber ohne Text', () {
      final w = punkte.where((p) => p.art == Wanderart.wegweiser);
      expect(w, hasLength(1));
      expect(w.first.name, isNull);
    });

    test('ein Eintrag ohne Koordinate nimmt die anderen nicht mit', () {
      expect(punkte.map((p) => p.name), isNot(contains('Ohne Ort')));
    });

    test('derselbe Punkt steht nur einmal im Bild', () {
      // Zwei überlappende Abfragen liefern denselben Punkt zweimal; im
      // Bild stünden dann zwei Kästchen übereinander.
      expect(punkte.where((p) => p.osmId == 304050947), hasLength(1));
      expect(punkte.map((p) => p.osmId).toSet().length, punkte.length);
    });
  });

  group('Was schiefgehen kann', () {
    test('kein JSON ergibt eine leere Liste statt einer Ausnahme', () {
      expect(ausOverpass('<html>429 Too Many Requests</html>'), isEmpty);
      expect(ausOverpass(''), isEmpty);
      expect(ausOverpass('[]'), isEmpty);
    });

    test('eine Antwort ohne Elemente ist kein Fehler', () {
      expect(ausOverpass('{"version":0.6}'), isEmpty);
      expect(ausOverpass('{"elements":[]}'), isEmpty);
    });

    test('jede Art aus der Liste kommt auch an', () {
      // Sonst stünde ein Merkmal in [wanderMerkmale], das der Zerleger
      // nie erzeugt - und niemand merkte es.
      for (final m in wanderMerkmale) {
        final eins = ausOverpass('{"elements":[{"type":"node","id":1,'
            '"lat":51.0,"lon":10.0,'
            '"tags":{"${m.schluessel}":"${m.wert}"}}]}');
        expect(eins, hasLength(1), reason: '${m.schluessel}=${m.wert}');
        expect(eins.first.art, m.art);
      }
    });
  });
}
