import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Der Befund vom 04.09.2026: im Raster tat keine Taste etwas.**
///
/// Zwei `Focus`-Knoten liegen ineinander, beide mit `autofocus: true` –
/// `HomeShell` legt einen über den ganzen Bildschirm (für ⌘1…⌘0 und „?"),
/// `Rasterbedienung.mitTastatur` einen weiteren um das Raster (für Pfeile,
/// Ziffern, F, Esc). Beide bitten im selben Bereich um den Fokus.
///
/// Wer gewinnt, entscheidet darüber, ob die Ziffern eine Bewertung setzen
/// oder nur piepen.
void main() {
  Widget baue({
    required List<String> aussen,
    required List<String> innen,
    FocusNode? innerKnoten,
    bool innenAutofocus = true,
  }) =>
      MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) aussen.add(event.logicalKey.keyLabel);
            return KeyEventResult.ignored;
          },
          child: Focus(
            focusNode: innerKnoten,
            autofocus: innenAutofocus,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) innen.add(event.logicalKey.keyLabel);
              return KeyEventResult.ignored;
            },
            child: const Scaffold(body: Text('Raster')),
          ),
        ),
      );

  testWidgets('so wie es war: der innere Knoten sieht die Taste nicht',
      (tester) async {
    final aussen = <String>[], innen = <String>[];
    await tester.pumpWidget(baue(aussen: aussen, innen: innen));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(aussen, ['3'], reason: 'Die Hülle bekommt die Taste.');
    expect(innen, isEmpty,
        reason: 'Und das Raster geht leer aus – das ist der Fehler.');
  });

  testWidgets('mit ausdrücklicher Fokusanforderung sehen sie beide',
      (tester) async {
    final aussen = <String>[], innen = <String>[];
    final knoten = FocusNode(debugLabel: 'Raster');
    addTearDown(knoten.dispose);
    await tester.pumpWidget(baue(
        aussen: aussen, innen: innen, innerKnoten: knoten, innenAutofocus: false));
    await tester.pump();
    knoten.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(innen, ['3'], reason: 'Das Raster sieht die Taste zuerst …');
    expect(aussen, ['3'], reason: '… und die Hülle danach immer noch.');
  });

  testWidgets('⌘2 erreicht die Hülle auch dann', (tester) async {
    final aussen = <String>[], innen = <String>[];
    final knoten = FocusNode(debugLabel: 'Raster');
    addTearDown(knoten.dispose);
    await tester.pumpWidget(baue(
        aussen: aussen, innen: innen, innerKnoten: knoten, innenAutofocus: false));
    await tester.pump();
    knoten.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(aussen.contains('2'), isTrue,
        reason: 'Der Bereichswechsel muss oben ankommen.');
  });
}
