import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';

/// **Texte, die einen Weg nennen, nennen ihn mit den Namen, die dort
/// stehen.**
///
/// Zwei Hinweise wiesen auf Einträge, die es nicht mehr gab: „Werkzeuge →
/// KI-Bildsuche → CLIP-Embeddings berechnen“ und „Werkzeuge → Vorschaubilder
/// neu erstellen“ (IMP-152, IMP-211). Beides liegt unter Werkzeuge →
/// Aufgaben. Geprüft wird gegen die Texte der Seitenleiste, der Werkzeugkarte
/// und der Aufgaben selbst – benennt jemand eine davon um, fällt der Hinweis
/// hier auf.
void main() {
  for (final sprache in ['de', 'en']) {
    test('Wegweiser auf die Aufgaben ($sprache)', () async {
      final t = await AppTexte.delegate.load(Locale(sprache));
      final weg = '${t.navWerkzeuge} → ${t.aufgTitel}';
      for (final (text, aufgabe) in [
        (t.aehnlKeineTreffer, t.aufgEmbeddingsTitel),
        (t.integPfadEntfernt, t.aufgVorschauTitel),
      ]) {
        expect(text, contains(weg));
        expect(text, contains(aufgabe));
      }
    });
  }
}
