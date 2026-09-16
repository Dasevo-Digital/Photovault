import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/personenvorschlag.dart';

/// **Wer könnte das sein?**
///
/// Die Rechnung gab es längst – sie stand fest in der Sammelzuordnung des
/// Personen-Tabs, und deshalb schlugen die häufigen Wege (ein Gesicht im
/// Vollbild antippen, Gesichter durchsehen, das Info-Blatt) gar nichts vor.
///
/// Geprüft wird hier vor allem das Schweigen: Ein Vorschlag, der zu leicht
/// kommt, ist schlimmer als keiner. Wer ihn übersieht und bestätigt, hat
/// eine falsche Zuordnung, die niemand mehr sucht.
void main() {
  /// Ein Vektor auf dem Einheitskreis – so lässt sich die Ähnlichkeit über
  /// den Winkel steuern, statt Zahlen zu raten.
  Float32List richtung(double grad) {
    final b = grad * math.pi / 180;
    return Float32List.fromList([math.cos(b), math.sin(b)]);
  }

  Gesichtseinbettung e(String person, double grad) =>
      (personId: person, vektor: richtung(grad));

  test('der Kern liegt zwischen den Gesichtern einer Person', () {
    final kerne = personenkerne([e('anna', -30), e('anna', 30)]);
    expect(kerne, hasLength(1));
    // Der Mittelwert zweier Richtungen um ±30° zeigt nach 0°.
    expect(kerne.single.kern[0], closeTo(1.0, 1e-6));
    expect(kerne.single.kern[1], closeTo(0.0, 1e-6));
  });

  test('jede Person bekommt genau einen Kern', () {
    final kerne = personenkerne([
      e('anna', 0),
      e('anna', 10),
      e('bernd', 90),
    ]);
    expect(kerne.map((k) => k.personId).toSet(), {'anna', 'bernd'});
  });

  test('ohne Einbettungen gibt es keinen Kern', () {
    expect(personenkerne(const []), isEmpty);
  });

  test('der nächste Kern gewinnt', () {
    final kerne = personenkerne([e('anna', 0), e('bernd', 90)]);
    final treffer =
        besterTreffer(richtung(10), kerne, schwelleFuer: (_) => 0.5);
    expect(treffer!.personId, 'anna');
    expect(treffer.aehnlichkeit, greaterThan(0.9));
  });

  test('wer die Schwelle nicht erreicht, wird nicht vorgeschlagen', () {
    // Der wichtigste Fall: ein fremdes Gesicht. Hier zu schweigen ist die
    // Aufgabe, nicht das Versagen.
    final kerne = personenkerne([e('anna', 0)]);
    expect(besterTreffer(richtung(80), kerne, schwelleFuer: (_) => 0.5),
        isNull);
  });

  test('die Schwelle gilt je Person, nicht für alle', () {
    // Darin steckt das Gelernte: Wer bisher zu oft fälschlich
    // vorgeschlagen wurde, braucht jetzt mehr Ähnlichkeit. Eine
    // gemeinsame Schwelle für alle ebnete genau diese Korrektur ein.
    final kerne = personenkerne([e('anna', 0), e('bernd', 40)]);
    // Bernd ist ähnlicher (30° gegen 40°) und gewinnt zuerst …
    expect(
        besterTreffer(richtung(30), kerne, schwelleFuer: (_) => 0.5)!.personId,
        'bernd');
    // … aber mit seiner eigenen, strengeren Schwelle reicht es nicht mehr,
    // und dann wird auch nicht auf Anna ausgewichen: Gefragt war, wer am
    // ähnlichsten ist, und das bleibt Bernd.
    expect(
        besterTreffer(richtung(30), kerne,
            schwelleFuer: (id) => id == 'bernd' ? 0.99 : 0.1),
        isNull,
        reason: 'der Zweitähnlichste ist keine Antwort auf „wer ist das?"');
  });

  test('ohne Kerne gibt es keinen Vorschlag', () {
    expect(besterTreffer(richtung(0), const [], schwelleFuer: (_) => 0.0),
        isNull);
  });
}
