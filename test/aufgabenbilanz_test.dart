import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/state/hintergrundlauf.dart';

/// **„Aufgabe lief ohne Fehlermeldung durch, genannt wurde nichts."**
///
/// Aus dem Erstlauf-Bericht (A08). Am Ende eines Laufs stand „Fertig – N
/// bearbeitet", und N war die Zahl der **angesehenen** Dinge. Wie viele
/// Dateien wirklich umgelegt wurden, stand nur im Entwicklerprotokoll.
void main() {
  late AppTexte de;

  setUpAll(() async {
    de = await AppTexte.delegate.load(const Locale('de'));
  });

  Hintergrundlauf lauf({String Function(int, int)? bilanztext}) =>
      Hintergrundlauf(
        schluessel: 'ablage',
        titel: 'Ablage ordnen',
        leermeldung: 'Alles liegt richtig',
        bilanztext: bilanztext,
        strom: () => const Stream<ImportProgress>.empty(),
      );

  test('ohne gemeldete Zahl bleibt die Bilanz leer', () {
    final l = lauf();
    expect(l.getan, isNull);
  });

  test('die zuletzt gemeldete Zahl gilt', () {
    // So macht es LibraryState beim Durchreichen: Ein spaeteres `null`
    // darf die Zahl nicht wieder loeschen.
    final l = lauf();
    for (final p in [
      ImportProgress(1, 3),
      ImportProgress(2, 3, getan: 2),
      ImportProgress(3, 3),
    ]) {
      if (p.getan != null) l.getan = p.getan;
    }
    expect(l.getan, 2);
  });

  test('der Bilanztext nennt beide Zahlen', () {
    final text = de.werkzAblageBilanz(7, 12);
    expect(text, contains('7'));
    expect(text, contains('12'));
  });

  test('getan und gesamt sind nicht dasselbe', () {
    // Der eigentliche Punkt: Von zwoelf angesehenen Dateien liessen sich
    // sieben umlegen. „Fertig - 12 bearbeitet" waere die falsche Auskunft.
    final fortschritt = ImportProgress(12, 12, getan: 7);
    expect(fortschritt.done, 12);
    expect(fortschritt.getan, 7);
  });
}
