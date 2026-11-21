// Texte: behobene Befunde aus dem Prüfkatalog der Handy-App (Issue #419):
// je Befund ein Test, der ohne die Korrektur scheitert.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';

void main() {
  test('ausgenommene Duplikate: Einzahl und Mehrzahl', () {
    final de = lookupAppTexte(const Locale('de'));
    final en = lookupAppTexte(const Locale('en'));
    expect(de.duplAusnahmen(1), 'Ein Paar ist ausgenommen.');
    expect(de.duplAusnahmen(3), '3 Paare sind ausgenommen.');
    expect(en.duplAusnahmen(1), 'One pair is excluded.');
    expect(en.duplAusnahmen(3), '3 pairs are excluded.');
  });
}
