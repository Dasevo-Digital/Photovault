import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/widgets/lupe.dart';

/// Die Lupe beim Entwickeln: Sie folgt dem Zeiger, solange sie an ist,
/// und nimmt den Gesten darunter nichts weg.
void main() {
  Future<void> zeige(
    WidgetTester tester, {
    required bool aktiv,
    VoidCallback? beiLangemDruck,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: Lupenbereich(
            aktiv: aktiv,
            child: GestureDetector(
              onLongPress: beiLangemDruck,
              child: const ColoredBox(key: Key('bild'), color: Colors.teal),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('mit der Maus über dem Bild steht die Lupe am Zeiger', (
    tester,
  ) async {
    await zeige(tester, aktiv: true);
    final maus = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await maus.addPointer(
      location: tester.getCenter(find.byKey(const Key('bild'))),
    );
    await maus.moveBy(const Offset(10, 5));
    await tester.pump();
    expect(find.byType(RawMagnifier), findsOneWidget);
    expect(
      tester.getCenter(find.byType(RawMagnifier)),
      tester.getCenter(find.byKey(const Key('bild'))) + const Offset(10, 5),
    );
    await maus.removePointer();
  });

  testWidgets('ausgeschaltet zeigt sie nichts', (tester) async {
    await zeige(tester, aktiv: false);
    final maus = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await maus.addPointer(
      location: tester.getCenter(find.byKey(const Key('bild'))),
    );
    await maus.moveBy(const Offset(10, 5));
    await tester.pump();
    expect(find.byType(RawMagnifier), findsNothing);
    await maus.removePointer();
  });

  testWidgets('langes Drücken darunter kommt weiter an', (tester) async {
    var gedrueckt = false;
    await zeige(tester, aktiv: true, beiLangemDruck: () => gedrueckt = true);
    await tester.longPress(find.byKey(const Key('bild')));
    expect(gedrueckt, isTrue);
  });
}
