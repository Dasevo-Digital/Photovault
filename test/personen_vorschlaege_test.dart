import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/face_suggestions.dart';

/// Vorschläge für eine bereits benannte Person.
///
/// Die Rechnung entscheidet, wem der Nutzer Fotos zuordnet – sie darf weder
/// zu grosszügig sein (dann klebt man fremde Gesichter an eine Person) noch
/// zu streng (dann bringt die Funktion nichts).
void main() {
  /// Ein Einheitsvektor unter dem Winkel [grad] – so kommen SFace-
  /// Embeddings an, und die Kosinus-Ähnlichkeit ist dann der Kosinus des
  /// Winkelabstands. Damit lassen sich Erwartungswerte von Hand ausrechnen.
  Float32List v(double grad) {
    final r = grad * math.pi / 180;
    return Float32List.fromList([math.cos(r), math.sin(r)]);
  }

  test('nur was über der Schwelle liegt, wird vorgeschlagen', () {
    // cos(30°) = 0,866 – über 0,8. cos(60°) = 0,5 – darunter.
    final ergebnis = vorschlaegeFuerPerson(VorschlagsEingabe(
      bekannt: [v(0)],
      kandidaten: {'nah': v(30), 'fern': v(60)},
      schwelle: 0.8,
    ));
    expect(ergebnis.map((e) => e.faceId), ['nah']);
  });

  test('sortiert wird nach Ähnlichkeit, die besten zuerst', () {
    final ergebnis = vorschlaegeFuerPerson(VorschlagsEingabe(
      bekannt: [v(0)],
      kandidaten: {'c': v(25), 'a': v(5), 'b': v(15)},
      schwelle: 0.0,
    ));
    expect(ergebnis.map((e) => e.faceId), ['a', 'b', 'c']);
  });

  test('verglichen wird gegen das ähnlichste bekannte Gesicht, nicht gegen '
      'den Mittelwert', () {
    // Der Kern der Sache: Die Person ist einmal unter 0° und einmal unter
    // 180° bekannt (Brille/keine Brille, jung/alt). Ihr Mittelwert ist der
    // Nullvektor und gliche keinem der beiden. Ein Kandidat bei 175° gehört
    // trotzdem eindeutig zum zweiten Bild.
    final ergebnis = vorschlaegeFuerPerson(VorschlagsEingabe(
      bekannt: [v(0), v(180)],
      kandidaten: {'beim zweiten': v(175)},
      schwelle: 0.9,
    ));
    expect(ergebnis, hasLength(1));
    expect(ergebnis.single.aehnlichkeit, closeTo(math.cos(5 * math.pi / 180), 1e-6));
  });

  test('die gemeldete Ähnlichkeit ist die höchste, nicht irgendeine', () {
    final ergebnis = vorschlaegeFuerPerson(VorschlagsEingabe(
      bekannt: [v(0), v(20)],
      kandidaten: {'x': v(25)},
      schwelle: 0.0,
    ));
    // 5° zum zweiten Bekannten, nicht 25° zum ersten.
    expect(ergebnis.single.aehnlichkeit,
        closeTo(math.cos(5 * math.pi / 180), 1e-6));
  });

  test('es kommen höchstens so viele Vorschläge wie erlaubt', () {
    final ergebnis = vorschlaegeFuerPerson(VorschlagsEingabe(
      bekannt: [v(0)],
      kandidaten: {for (var i = 0; i < 200; i++) 'f$i': v(i * 0.1)},
      schwelle: 0.0,
      hoechstens: 10,
    ));
    expect(ergebnis, hasLength(10));
    // Und es sind die besten, nicht die ersten zehn aus der Map.
    expect(ergebnis.first.aehnlichkeit,
        greaterThanOrEqualTo(ergebnis.last.aehnlichkeit));
    expect(ergebnis.first.faceId, 'f0');
  });

  test('ohne bekannte Gesichter oder ohne Kandidaten kommt nichts', () {
    expect(
        vorschlaegeFuerPerson(VorschlagsEingabe(
            bekannt: const [], kandidaten: {'a': v(0)}, schwelle: 0)),
        isEmpty);
    expect(
        vorschlaegeFuerPerson(
            VorschlagsEingabe(bekannt: [v(0)], kandidaten: const {}, schwelle: 0)),
        isEmpty);
  });

  group('Die Stichprobe der bekannten Gesichter', () {
    test('kleine Mengen bleiben vollständig', () {
      expect(stichprobe([1, 2, 3], 40), [1, 2, 3]);
    });

    test('grosse Mengen werden über den ganzen Bestand gezogen', () {
      // Nicht die ersten n: Die könnten alle vom selben Tag stammen und die
      // Bandbreite an Aussehen ginge verloren – genau das, wofür der
      // Vergleich gegen das ähnlichste Einzelbild da ist.
      final gezogen = stichprobe(List.generate(400, (i) => i), 4);
      expect(gezogen, [0, 100, 200, 300]);
    });

    test('die Obergrenze wird eingehalten', () {
      expect(stichprobe(List.generate(1000, (i) => i), 40), hasLength(40));
    });
  });

  test('der Deckel auf die bekannten Gesichter verfälscht das Ergebnis nicht '
      'grob', () {
    // 400 bekannte Gesichter, fein über 40° gestreut. Der Deckel zieht 40
    // davon; ein Kandidat mitten drin muss trotzdem gefunden werden.
    final ergebnis = vorschlaegeFuerPerson(VorschlagsEingabe(
      bekannt: [for (var i = 0; i < 400; i++) v(i * 0.1)],
      kandidaten: {'mittendrin': v(20.05)},
      schwelle: 0.99,
    ));
    expect(ergebnis, hasLength(1),
        reason: 'die Stichprobe muss dicht genug bleiben');
  });
}
