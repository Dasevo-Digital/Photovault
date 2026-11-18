import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/model_catalog.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/state/library_state.dart';

/// Hinweistexte, die auf Knöpfe, Stufen oder Grössen verweisen, müssen
/// mit dem übereinstimmen, was die App heute zeigt. Die Prüfung KI-031,
/// KI-083, KI-091, KI-094 und KI-095 fand fünf, die stehengeblieben
/// waren, als sich die Oberfläche änderte.
void main() {
  for (final sprache in ['de', 'en']) {
    final t = lookupAppTexte(Locale(sprache));

    group(sprache, () {
      test('der Vokabular-Hinweis nennt den heutigen Weg', () {
        expect(t.einstVokabularText, contains(t.navWerkzeuge));
        expect(t.einstVokabularText, contains('“${t.aufgTitel}”'.anf(t)));
        expect(t.einstVokabularText, contains('“${t.aufgKiTagsTitel}”'.anf(t)));
        expect(t.einstVokabularText, contains('“${t.aufgModusAlle}”'.anf(t)));
      });

      test('„Alle Auswertungen nachholen“ nennt jede Stufe', () {
        final text = t.werkzAllesNachholenText.toLowerCase();
        for (final stufe in Analysestufe.values) {
          expect(
            text,
            contains(analysestufeName(t, stufe).toLowerCase()),
            reason: stufe.name,
          );
        }
      });

      test('der Hinweis zur eigenen Beschreibung nennt den Knopf', () {
        expect(t.infoKiVonHandHinweis, contains('“${t.aufgModusAlle}”'.anf(t)));
      });

      test('der Video-Hinweis kennt die weiteren Standbilder', () {
        // Seit der Stufe Videobilder ruht nur noch die Beschreibung auf
        // dem einen Standbild, nicht mehr alles Erkannte.
        expect(
          t.infoVideoStandbild.toLowerCase(),
          contains(t.stufeSchlagwoerter.toLowerCase()),
        );
      });

      test('die Grösse der Texterkennung stimmt mit dem Katalog', () {
        final bytes = ModelCatalog.ocrPaddle.files.fold<int>(
          0,
          (n, f) => n + f.bytes,
        );
        var mb = (bytes / 1000000).toStringAsFixed(1);
        if (sprache == 'de') mb = mb.replaceAll('.', ',');
        expect(t.modellOcrText, contains('$mb MB'));
      });
    });
  }
}

extension on String {
  /// Die Anführungszeichen der jeweiligen Sprache.
  String anf(AppTexte t) =>
      t.localeName == 'de' ? replaceAll('“', '„').replaceFirst('”', '“') : this;
}
