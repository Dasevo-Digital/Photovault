import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/widgets/tastenkuerzel.dart';

/// **Jede Taste, die etwas tut, muss in der Tafel stehen.**
///
/// Die Übersicht gab es seit Langem, ihre eigene Klassendoku begründete sie
/// damit, dass Nutzer die Kürzel sonst „aus dem Quellcode kennen oder
/// erraten" müssten. Fassung 2.5.0 legte dem Raster neun neue Tasten bei –
/// Umschalt-Klick, Strg-Klick, die vier Pfeile, 0–5, 6–9, F, Esc, Eingabe –
/// und trug keine davon dort ein. Dazu kamen im Vollbild die Farbmarken
/// 6–9. Der Befund der 2.5.0-Runde war, dass die Bewertungen brachlagen,
/// weil der Weg dorthin fehlte; der Weg zu ihrem Ersatz fehlte genauso.
///
/// Dieser Prüfstand liest die Tastenbehandlung im Quelltext und verlangt
/// für jede dort behandelte Taste einen Eintrag in der Tafel.
void main() {
  /// Welche Tasten [rasterbedienung.dart] tatsächlich abfängt.
  Set<String> behandelteRastertasten() {
    final quelle = File('lib/widgets/rasterbedienung.dart').readAsStringSync();
    final rumpf = quelle.substring(quelle.indexOf('KeyEventResult rasterTaste'));
    final gefunden = <String>{};
    for (final m
        in RegExp(r'LogicalKeyboardKey\.(\w+)').allMatches(rumpf)) {
      gefunden.add(m.group(1)!);
    }
    // Ziffern kommen nicht als LogicalKeyboardKey vor, sondern über
    // bewertungFuerZiffer/farbmarkeFuerZiffer.
    if (rumpf.contains('bewertungFuerZiffer')) gefunden.add('_ziffern0bis5');
    if (rumpf.contains('farbmarkeFuerZiffer')) gefunden.add('_ziffern6bis9');
    return gefunden;
  }

  /// Was in der Tafel für diese Taste stehen muss.
  const erwartet = <String, String>{
    'arrowLeft': '←',
    'arrowRight': '→',
    'arrowUp': '↑',
    'arrowDown': '↓',
    'escape': 'Esc',
    'enter': '⏎',
    'numpadEnter': '⏎',
    'keyF': 'F',
    '_ziffern0bis5': '0 – 5',
    '_ziffern6bis9': '6 – 9',
  };

  testWidgets('die Tafel nennt jede Taste, die das Raster abfängt',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
          body: SingleChildScrollView(child: Tastenkuerzeltafel())),
    ));
    await tester.pumpAndSettle();

    final gezeigt = [
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        w.data ?? '',
    ].join(' | ');

    final fehlen = <String>[];
    for (final taste in behandelteRastertasten()) {
      final zeichen = erwartet[taste];
      // Eine Taste, die dieser Prüfstand nicht kennt, ist ebenfalls ein
      // Befund: Sie kam dazu, ohne dass jemand an die Tafel dachte.
      if (zeichen == null) {
        fehlen.add('$taste (in diesem Prüfstand nicht eingetragen)');
        continue;
      }
      if (!gezeigt.contains(zeichen)) fehlen.add('$taste -> „$zeichen"');
    }
    expect(fehlen, isEmpty,
        reason: 'Diese Tasten tun etwas, stehen aber in keiner Übersicht:\n'
            '${fehlen.join('\n')}');

    // Und die beiden Mausgriffe, die kein LogicalKeyboardKey sind.
    expect(gezeigt, contains('Umschalt-Klick'));
    expect(gezeigt, contains('Strg-/⌘-Klick'));
  });

  test('die Tafel ist nicht nur über „?" erreichbar', () {
    // Der eigentliche Befund: Eine Übersicht der Tastenkürzel hinter einem
    // Tastenkürzel, das nirgends genannt wird, ist keine Übersicht.
    final einstellungen =
        File('lib/screens/settings_screen.dart').readAsStringSync();
    expect(einstellungen, contains('Tastenkuerzeltafel()'),
        reason: 'die Einstellungen sind der auffindbare Weg dorthin');
  });
}
