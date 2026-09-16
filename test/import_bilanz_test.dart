import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/import_progress_sheet.dart';

/// **Duplikate wurden stillschweigend uebersprungen.**
///
/// Aus dem Bericht: "Fotos werden nicht doppelt angelegt, jedoch ohne
/// Meldung." Uebersprungen wurden sie immer schon - wer zweihundert
/// Dateien hereinzieht und danach hundertachtzig Fotos vorfindet, sucht
/// den Fehler bei sich.
void main() {
  late AppTexte de;
  late AppTexte en;

  setUpAll(() async {
    de = await AppTexte.delegate.load(const Locale('de'));
    en = await AppTexte.delegate.load(const Locale('en'));
  });

  test('ohne Duplikat und ohne Fehler steht da nichts', () {
    // Die Zahl der neuen Aufnahmen steht ohnehin schon im Fortschritt
    // darueber. "0 uebersprungen, 0 Fehler" waere Rauschen.
    expect(importBilanz(de, neu: 12, duplikate: 0, fehler: 0), isNull);
  });

  test('uebersprungene Dateien werden genannt', () {
    final zeile = importBilanz(de, neu: 180, duplikate: 20, fehler: 0)!;
    expect(zeile, contains('180'));
    expect(zeile, contains('20'));
    expect(zeile, contains('übersprungen'));
  });

  test('die Einzahl ist eine eigene Form', () {
    final zeile = importBilanz(de, neu: 3, duplikate: 1, fehler: 0)!;
    expect(zeile, contains('1 lag schon'));
    expect(zeile, isNot(contains('lagen')));
  });

  test('Fehler stehen daneben, nicht statt dessen', () {
    final zeile = importBilanz(de, neu: 5, duplikate: 2, fehler: 1)!;
    expect(zeile, contains('5'));
    expect(zeile, contains('2'));
    expect(zeile, contains('1'));
  });

  test('ein Fehler allein genuegt fuer die Zeile', () {
    expect(importBilanz(de, neu: 5, duplikate: 0, fehler: 1), isNotNull);
  });

  test('auf Englisch steht dasselbe', () {
    final zeile = importBilanz(en, neu: 180, duplikate: 20, fehler: 0)!;
    expect(zeile, contains('skipped'));
    expect(zeile, contains('20'));
  });
}
