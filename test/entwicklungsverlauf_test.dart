import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/develop_color.dart';
import 'package:photo_vault/services/entwicklungsverlauf.dart';
import 'package:photo_vault/services/native_image_converter.dart';

/// **Der Verlauf sagte nur, wann.**
///
/// Er zeigte eine Liste von Zeitpunkten – „05.03.2026, 14:30" und
/// darunter noch einer. Was an jedem davon getan wurde, stand nirgends;
/// man musste einen Eintrag laden und das Bild ansehen, um es
/// herauszufinden.
///
/// Und er entstand erst beim **Speichern**: Alles, was man während einer
/// Sitzung ausprobierte, war verloren, sobald man darüber hinweg war.
void main() {
  const neutral = DevelopAdjustments();

  group('Was sich geaendert hat', () {
    test('ein Regler wird beim Namen genannt', () {
      expect(
        geaenderteWerkzeuge(neutral, const DevelopAdjustments(exposure: 0.5)),
        [Entwicklungswerkzeug.belichtung],
      );
    });

    test('mehrere Regler in der Reihenfolge der Aufzaehlung', () {
      // Damit dieselbe Aenderung zweimal dieselbe Auskunft ergibt und
      // nicht einmal „Kontrast, Belichtung" und einmal andersherum.
      final a = geaenderteWerkzeuge(neutral,
          const DevelopAdjustments(contrast: 0.3, exposure: 0.5));
      final b = geaenderteWerkzeuge(neutral,
          const DevelopAdjustments(exposure: 0.5, contrast: 0.3));
      expect(a, [Entwicklungswerkzeug.belichtung, Entwicklungswerkzeug.kontrast]);
      expect(b, a);
    });

    test('gleiche Staende ergeben nichts', () {
      expect(geaenderteWerkzeuge(neutral, neutral), isEmpty);
      expect(istAnders(neutral, neutral), isFalse);
    });

    test('eine Rundung in der zwoelften Stelle ist keine Aenderung', () {
      // Ein Stand, der durch die Datenbank gegangen ist, traegt gerundete
      // Zahlen. Ein Verlauf, der bei jedem Eintrag alles nennt, nennt
      // nichts.
      expect(
        geaenderteWerkzeuge(
            const DevelopAdjustments(exposure: 0.5),
            const DevelopAdjustments(exposure: 0.5000000001)),
        isEmpty,
      );
    });

    test('der Weissabgleich wird vom Wert unterschieden', () {
      // Von der Automatik auf einen Wert zu wechseln ist ein anderer
      // Vorgang als den Wert zu verschieben.
      expect(
        geaenderteWerkzeuge(
            neutral, const DevelopAdjustments(temperature: 5000, tint: 0)),
        [Entwicklungswerkzeug.weissabgleich],
      );
      expect(
        geaenderteWerkzeuge(
            const DevelopAdjustments(temperature: 5000, tint: 0),
            const DevelopAdjustments(temperature: 6500, tint: 0)),
        [Entwicklungswerkzeug.temperatur],
      );
    });

    test('Kurve und Mischer werden erkannt', () {
      const kurve = ToneCurve(zusammen: [
        CurvePoint(0, 0),
        CurvePoint(0.5, 0.7),
        CurvePoint(1, 1),
      ]);
      expect(geaenderteWerkzeuge(neutral, const DevelopAdjustments(toneCurve: kurve)),
          [Entwicklungswerkzeug.tonwertkurve]);

      final mischer = ColorMixer.neutral
          .mitBand(ColorBand.rot, const BandAnpassung(saettigung: 0.4));
      expect(
          geaenderteWerkzeuge(neutral, DevelopAdjustments(colorMixer: mischer)),
          [Entwicklungswerkzeug.farbmischer]);
    });

    test('die Objektivkorrektur zaehlt als Aenderung', () {
      expect(
        geaenderteWerkzeuge(
            neutral, const DevelopAdjustments(lensCorrectionEnabled: false)),
        [Entwicklungswerkzeug.objektivkorrektur],
      );
    });
  });

  group('Die Reihe der Sitzung', () {
    test('der erste Schritt ist der Stand beim Oeffnen', () {
      final reihe = mitSchritt(const [], neutral);
      expect(reihe, hasLength(1));
      expect(reihe.first.stand, neutral);
    });

    test('ein Regler, der bewegt und zurueckgelegt wird, ist kein Schritt', () {
      var reihe = mitSchritt(const [], neutral);
      reihe = mitSchritt(reihe, const DevelopAdjustments(exposure: 0.5));
      final vorher = reihe.length;
      reihe = mitSchritt(reihe, const DevelopAdjustments(exposure: 0.5));
      expect(reihe.length, vorher);
    });

    test('die Reihe wird gedeckelt, der Ausgangsstand bleibt', () {
      // Er ist der einzige Weg ganz zurueck.
      var reihe = mitSchritt(const [], neutral);
      for (var i = 1; i <= maxSitzungsschritte + 20; i++) {
        reihe = mitSchritt(reihe, DevelopAdjustments(exposure: i * 0.01));
      }
      expect(reihe, hasLength(maxSitzungsschritte));
      expect(reihe.first.stand.exposure, 0);
      expect(reihe.last.stand.exposure,
          closeTo((maxSitzungsschritte + 20) * 0.01, 1e-9));
    });

    test('jeder Schritt traegt seine Zeit', () {
      final reihe = mitSchritt(const [], neutral, wann: DateTime(2026, 3, 5));
      expect(reihe.first.wann, DateTime(2026, 3, 5));
    });
  });
}
