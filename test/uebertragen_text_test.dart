import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';

/// **Der Übertragen-Dialog nannte nur vier Werkzeuge** (BEA-052).
///
/// „Entwicklung auf n Fotos übertragen?“ sprach von Belichtung,
/// Weissabgleich, Kontrast und Schatten. Übertragen werden aber alle
/// Werte, die für das ganze Bild gelten (siehe
/// `LibraryState.uebertrageEntwicklung`) – wer Lichter oder eine
/// Farbtabelle gesetzt hatte, erfuhr nicht, dass sie mitgehen.
void main() {
  for (final sprache in ['de', 'en']) {
    test('der Text nennt jedes übertragene Werkzeug ($sprache)', () {
      final t = lookupAppTexte(Locale(sprache));
      final text = t.auswUebertragenText.toLowerCase();
      for (final werkzeug in [
        t.entwBelichtung,
        t.entwKontrast,
        t.entwLichter,
        t.entwSchatten,
        t.entwKlarheit,
        t.entwSchaerfe,
        t.entwRauschunterdrueckung,
        t.entwVignettierung,
        t.entwObjektivkorrektur,
        t.entwWerkzFarbtabelle,
        t.entwWerkzKurve,
        t.entwWerkzFarbmischer,
      ]) {
        expect(text, contains(werkzeug.toLowerCase()), reason: werkzeug);
      }
    });
  }
}
