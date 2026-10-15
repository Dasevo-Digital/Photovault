import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/widgets/einfuegbares_menue.dart';

/// In jedes Eingabefeld lässt sich einfügen – per Tastenkürzel und über das
/// Rechtsklickmenü, auch in Passwortfelder.
///
/// Flutters eigenes Menü zeigt „Einfügen“ nur, wenn es die Zwischenablage
/// vorher als einfügbar erkannt hat; unter macOS gelingt das nicht
/// verlässlich. Der Prüfstand stellt genau das nach: Die Zwischenablage hat
/// Text, meldet aber auf die Frage danach „nein“.
void main() {
  void zwischenablage(WidgetTester tester, String text) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => {'text': text},
        'Clipboard.hasStrings' => {'value': false},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  Future<void> rechtsklick(WidgetTester tester, Finder ziel) async {
    final g = await tester.startGesture(
      tester.getCenter(ziel),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await g.up();
    await tester.pumpAndSettle();
  }

  Future<TextEditingController> zeige(
    WidgetTester tester, {
    required bool mitMenue,
  }) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: TextField(
                controller: c,
                obscureText: true,
                contextMenuBuilder: mitMenue ? einfuegbaresMenue : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    return c;
  }

  const desktop = TargetPlatformVariant({
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  });

  testWidgets('Flutters eigenes Menü lässt „Einfügen“ dann weg', (
    tester,
  ) async {
    zwischenablage(tester, 'geheim-123');
    await zeige(tester, mitMenue: false);
    await rechtsklick(tester, find.byType(TextField));
    expect(find.text('Paste'), findsNothing, reason: 'der Fehler selbst');
  }, variant: desktop);

  testWidgets('unser Menü zeigt „Einfügen“ trotzdem', (tester) async {
    zwischenablage(tester, 'geheim-123');
    await zeige(tester, mitMenue: true);
    await rechtsklick(tester, find.byType(TextField));
    expect(find.text('Paste'), findsOneWidget);
  }, variant: desktop);

  testWidgets(
    '„Einfügen“ setzt den Text ins Passwortfeld, Kopieren gibt es dort nicht',
    (tester) async {
      zwischenablage(tester, 'geheim-123');
      final c = await zeige(tester, mitMenue: true);
      await rechtsklick(tester, find.byType(TextField));
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Cut'), findsNothing);
      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();
      expect(c.text, 'geheim-123');
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets('und per Tastenkürzel', (tester) async {
    zwischenablage(tester, 'geheim-123');
    final c = await zeige(tester, mitMenue: true);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(c.text, 'geheim-123');
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  test('jedes Eingabefeld beider Apps hat das Menü', () {
    final muster = RegExp(r'(?<![\w.])(TextField|TextFormField|SearchBar)\(');
    final ohne = <String>[];
    var gezaehlt = 0;
    for (final wurzel in ['lib', 'apps/mobil/lib']) {
      for (final f in Directory(wurzel).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.contains('/l10n/')) continue;
        final s = f.readAsStringSync();
        for (final m in muster.allMatches(s)) {
          gezaehlt++;
          final rumpf = s.substring(m.end, _schliessend(s, m.end - 1));
          if (!rumpf.contains('contextMenuBuilder: einfuegbaresMenue')) {
            final zeile = '\n'.allMatches(s.substring(0, m.start)).length + 1;
            ohne.add('${f.path}:$zeile');
          }
        }
      }
    }
    expect(gezaehlt, greaterThan(60), reason: 'die Suche findet die Felder');
    expect(ohne, isEmpty, reason: 'ohne einfuegbaresMenue');
  });

  test('beide Apps haben dasselbe Menü', () {
    expect(
      File('apps/mobil/lib/einfuegbares_menue.dart').readAsStringSync(),
      File('lib/widgets/einfuegbares_menue.dart').readAsStringSync(),
    );
  });
}

/// Die schliessende Klammer zur öffnenden bei [auf] – Zeichenketten und
/// Kommentare übersprungen.
int _schliessend(String s, int auf) {
  var tiefe = 0;
  String? inText;
  for (var i = auf; i < s.length; i++) {
    final c = s[i];
    if (inText != null) {
      if (c == r'\') {
        i++;
      } else if (s.startsWith(inText, i)) {
        i += inText.length - 1;
        inText = null;
      }
      continue;
    }
    if (s.startsWith("'''", i) || s.startsWith('"""', i)) {
      inText = s.substring(i, i + 3);
      i += 2;
    } else if (c == "'" || c == '"') {
      inText = c;
    } else if (s.startsWith('//', i)) {
      i = s.indexOf('\n', i);
    } else if (c == '(') {
      tiefe++;
    } else if (c == ')' && --tiefe == 0) {
      return i;
    }
  }
  return s.length;
}
