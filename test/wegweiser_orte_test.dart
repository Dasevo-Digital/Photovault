import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/l10n/app_localizations_en.dart';

/// **Ein Wegweiser muss dorthin zeigen, wo es ist.**
///
/// „Ort noch nicht aufgelöst (Werkzeuge → Orte)“ – unter Werkzeuge → Orte
/// steht nur „Aus einer GPX-Spur verorten“; aufgelöst wird unter
/// Werkzeuge → Aufgaben. Die Hinweise nennen jetzt die Namen, die man in
/// der App auch findet.
void main() {
  for (final t in <AppTexte>[AppTexteDe(), AppTexteEn()]) {
    test('Wegweiser zum Auflösen der Orte (${t.localeName})', () {
      final ziel = '${t.navWerkzeuge} → ${t.aufgTitel}';
      for (final text in [
        t.infoOrtNichtAufgeloest,
        t.erkundenKeineOrte,
        t.suchoptGeoFehlt,
      ]) {
        expect(text, contains(ziel), reason: text);
        expect(text, contains(t.werkzOrteAufloesenTitel), reason: text);
      }
      // Den Datensatz gibt es unter Einstellungen → Standortdaten.
      expect(t.suchoptGeoFehlt, contains(t.aufgWoStandortdaten));
    });

    test('Wegweiser zu den Durchgängen der Suche (${t.localeName})', () {
      final ziel = '${t.navWerkzeuge} → ${t.aufgTitel}';
      expect(t.sucheOhneEmbeddings, contains(ziel));
      expect(t.sucheOhneTexterkennung, contains(ziel));
    });
  }
}
