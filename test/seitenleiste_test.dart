import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/widgets/seitenleiste.dart';

/// Die Seitenleiste am breiten Fenster (Issue #183) – wie im Browser:
/// schmal, beim Überfahren offen über dem Inhalt, mit der Nadel fest.
void main() {
  const gruppen = [
    Leistengruppe(
      eintraege: [
        Leisteneintrag(text: 'Fotos', icon: Icons.photo_library_outlined),
        Leisteneintrag(text: 'Suche', icon: Icons.search),
      ],
    ),
    Leistengruppe(
      titel: 'Entdecken',
      eintraege: [
        Leisteneintrag(
          text: 'Karte',
          icon: Icons.place_outlined,
          farbe: Color(0xFF30A46C),
        ),
      ],
    ),
    Leistengruppe(
      titel: 'Verwalten',
      eintraege: [
        Leisteneintrag(
          text: 'Papierkorb',
          icon: Icons.delete_outline_rounded,
          farbe: Color(0xFF8B8D98),
        ),
      ],
    ),
  ];

  late List<int> gewaehlt;
  late bool fixiert;

  setUp(() {
    gewaehlt = [];
    fixiert = false;
  });

  Future<void> zeige(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Seitenleiste(
            gruppen: gruppen,
            gewaehlt: 0,
            beiWahl: gewaehlt.add,
            fixiert: fixiert,
            beiFixieren: (f) => setState(() => fixiert = f),
            marke: const FlutterLogo(),
            markeText: 'Photo Vault',
            fixierenText: 'Leiste fixieren',
            loesenText: 'Fixierung lösen',
            inhalt: const _Zaehler(),
          ),
        ),
      ),
    ),
  );

  double breite(WidgetTester tester) => tester
      .getSize(
        find
            .descendant(
              of: find.byType(Seitenleiste),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      )
      .width;

  double inhaltLinks(WidgetTester tester) =>
      tester.getTopLeft(find.byType(_Zaehler)).dx;

  testWidgets('zu: nur Symbole; die Maus öffnet sie über dem Inhalt', (
    tester,
  ) async {
    await zeige(tester);
    expect(breite(tester), Seitenleiste.schmal);
    expect(inhaltLinks(tester), Seitenleiste.schmal);

    final maus = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(maus.removePointer);
    await maus.addPointer(location: Offset.zero);
    await maus.moveTo(tester.getCenter(find.byIcon(Icons.search)));
    await tester.pump(const Duration(milliseconds: 30));
    expect(breite(tester), Seitenleiste.schmal, reason: 'erst nach 60 ms');
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    expect(breite(tester), Seitenleiste.offen);
    expect(
      inhaltLinks(tester),
      Seitenleiste.schmal,
      reason: 'Offen auf Zeit legt sie sich über den Inhalt.',
    );

    await maus.moveTo(const Offset(600, 300));
    await tester.pump(const Duration(milliseconds: 200));
    expect(breite(tester), Seitenleiste.offen, reason: 'mit Nachsicht');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(breite(tester), Seitenleiste.schmal);
  });

  testWidgets('die Nummer eines Ziels zählt über die Gruppen hinweg', (
    tester,
  ) async {
    await zeige(tester);
    await tester.tap(find.byIcon(Icons.place_outlined));
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    expect(gewaehlt, [2, 3]);
  });

  testWidgets('die Nadel hält sie offen und rückt den Inhalt zur Seite – '
      'ohne dessen Zustand zu verlieren', (tester) async {
    await zeige(tester);
    await tester.tap(find.byType(_Zaehler));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.push_pin_outlined));
    await tester.pumpAndSettle();
    expect(fixiert, isTrue);
    expect(breite(tester), Seitenleiste.offen);
    expect(inhaltLinks(tester), Seitenleiste.offen);
    expect(find.text('Fixierung lösen'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'derselbe Inhalt');

    await tester.tap(find.byIcon(Icons.push_pin));
    await tester.pumpAndSettle();
    expect(fixiert, isFalse);
    expect(breite(tester), Seitenleiste.schmal, reason: 'gelöst: gleich zu');
    expect(inhaltLinks(tester), Seitenleiste.schmal);
    expect(find.text('1'), findsOneWidget);
  });
}

class _Zaehler extends StatefulWidget {
  const _Zaehler();

  @override
  State<_Zaehler> createState() => _ZaehlerState();
}

class _ZaehlerState extends State<_Zaehler> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _n++),
    child: Center(child: Text('$_n')),
  );
}
