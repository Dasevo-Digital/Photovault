import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/lebensbaum.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/widgets/lebensbaum_ansicht.dart';
import 'package:photo_vault/widgets/lebensbaum_maler.dart';

/// Der Lebensbaum: eine Linie über mehrere Generationen als gemalter Baum.
///
/// Geprüft wird die Rechnung, nicht das Bild – ob sich zwei Schilder um
/// ein paar Punkte überlappen, sieht man am Bild nicht zuverlässig. Wie es
/// aussieht, zeigt `tool/lebensbaum_bilder_test.dart`.
void main() {
  // ich – Eltern v, m – Grosseltern väterlicherseits gv, gm.
  // ich ⚭ partner, Kinder k1 (gemeinsam) und k2 (nur beim Partner
  // eingetragen), Enkel e1 von k1.
  final reihenfolge = [
    'ich',
    'partner',
    'v',
    'm',
    'gv',
    'gm',
    'k1',
    'k2',
    'e1',
  ];
  int ordnung(String id) => reihenfolge.indexOf(id);
  Verwandtschaftsnetz netz() => Verwandtschaftsnetz([
    kante('ich', 'v', Verwandtschaft.elternteil),
    kante('ich', 'm', Verwandtschaft.elternteil),
    kante('v', 'gv', Verwandtschaft.elternteil),
    kante('v', 'gm', Verwandtschaft.elternteil),
    kante('k1', 'ich', Verwandtschaft.elternteil),
    kante('k1', 'partner', Verwandtschaft.elternteil),
    kante('k2', 'partner', Verwandtschaft.elternteil),
    kante('e1', 'k1', Verwandtschaft.elternteil),
    partnerKanteFuer('ich', 'partner'),
  ]);

  void keineUeberlappung(Lebensbaumplan plan) {
    final schilder = [for (final k in plan.knoten) ...k.schilder];
    for (var i = 0; i < schilder.length; i++) {
      for (var j = i + 1; j < schilder.length; j++) {
        expect(
          schilder[i].overlaps(schilder[j]),
          isFalse,
          reason: 'Schild $i und $j überlappen',
        );
      }
    }
  }

  group('Vorfahren', () {
    late Lebensbaumplan plan;
    setUp(() {
      plan = lebensbaumplan(
        netz(),
        'ich',
        ordnung,
        richtung: Lebensbaumrichtung.vorfahren,
      );
    });

    test('die Person steht am Stamm, ganz unten', () {
      expect(plan.wurzel.personen, ['ich']);
      for (final k in plan.knoten.skip(1)) {
        expect(k.rahmen.center.dy, lessThan(plan.wurzel.rahmen.center.dy));
      }
      expect(plan.stammFuss.dy, greaterThan(plan.wurzel.rahmen.bottom));
    });

    test('jede Generation steht eine Stufe höher, Eltern über dem Kind', () {
      final v = plan.knoten.firstWhere((k) => k.personen.single == 'v');
      final gv = plan.knoten.firstWhere((k) => k.personen.single == 'gv');
      expect(v.stufe, 1);
      expect(gv.stufe, 2);
      expect(gv.rahmen.center.dy, lessThan(v.rahmen.center.dy));
      expect(plan.knotenMit(gv.vorgaenger!)!.personen.single, 'v');
      expect(plan.generationen, 2);
    });

    test('die Eltern stehen in der Reihenfolge der Ahnentafel', () {
      final v = plan.knoten.firstWhere((k) => k.personen.single == 'v');
      final m = plan.knoten.firstWhere((k) => k.personen.single == 'm');
      expect(v.rahmen.center.dx, lessThan(m.rahmen.center.dx));
    });

    test('kein Schild überdeckt ein anderes', () => keineUeberlappung(plan));

    test('ein Ast ist so dick, wie er trägt', () {
      // Der Vater trägt zwei Grosseltern, die Mutter keinen.
      final v = plan.knoten.firstWhere((k) => k.personen.single == 'v');
      final m = plan.knoten.firstWhere((k) => k.personen.single == 'm');
      expect(v.spitzen, 2);
      expect(m.spitzen, 1);
      expect(plan.wurzel.spitzen, 3);
    });

    test('die Tiefe begrenzt die Generationen', () {
      final eine = lebensbaumplan(
        netz(),
        'ich',
        ordnung,
        richtung: Lebensbaumrichtung.vorfahren,
        generationen: 1,
      );
      expect(eine.knoten.map((k) => k.stufe).toSet(), {0, 1});
    });
  });

  group('Nachkommen', () {
    late Lebensbaumplan plan;
    setUp(() {
      plan = lebensbaumplan(
        netz(),
        'ich',
        ordnung,
        richtung: Lebensbaumrichtung.nachkommen,
      );
    });

    test('am Stamm steht das Paar', () {
      expect(plan.wurzel.personen, ['ich', 'partner']);
      expect(plan.wurzel.schilder, hasLength(2));
    });

    test(
      'auch ein Kind, das nur beim Partner eingetragen ist, hängt am Ast',
      () {
        final kinder = plan.knoten.where((k) => k.stufe == 1);
        expect({
          for (final k in kinder) ...k.personen,
        }, containsAll(['k1', 'k2']));
      },
    );

    test('Enkel wachsen eine Stufe höher', () {
      final e1 = plan.knoten.firstWhere((k) => k.personen.contains('e1'));
      expect(e1.stufe, 2);
      expect(plan.knotenMit(e1.vorgaenger!)!.personen, contains('k1'));
    });

    test('kein Schild überdeckt ein anderes', () => keineUeberlappung(plan));

    test('was keinen Platz hat, wird gezählt, nicht verschwiegen', () {
      final eng = lebensbaumplan(
        netz(),
        'ich',
        ordnung,
        richtung: Lebensbaumrichtung.nachkommen,
        hoechstensSchilder: 3,
      );
      expect(eng.verschwiegen, greaterThan(0));
      final gezeigt = {for (final k in eng.knoten) ...k.personen};
      expect(gezeigt.length + eng.verschwiegen, 5);
    });

    test('ein Kreis im Bestand läuft nicht endlos', () {
      final kreis = Verwandtschaftsnetz([
        kante('a', 'b', Verwandtschaft.elternteil),
        kante('b', 'a', Verwandtschaft.elternteil),
      ]);
      final p = lebensbaumplan(
        kreis,
        'a',
        (_) => 0,
        richtung: Lebensbaumrichtung.nachkommen,
        generationen: lebensbaumMaxGenerationen,
      );
      expect(p.knoten.length, lessThanOrEqualTo(2));
    });
  });

  test('ohne Verwandte bleibt nur der Stamm', () {
    final allein = lebensbaumplan(
      Verwandtschaftsnetz(const []),
      'ich',
      (_) => 0,
      richtung: Lebensbaumrichtung.vorfahren,
    );
    expect(allein.knoten, hasLength(1));
    expect(
      allein.breite,
      greaterThanOrEqualTo(const Lebensbaummasse().mindestBreite),
    );
  });

  test('ein Tipp auf die Fläche trifft die Person darunter', () {
    final plan = lebensbaumplan(
      netz(),
      'ich',
      ordnung,
      richtung: Lebensbaumrichtung.vorfahren,
    );
    final gv = plan.knoten.firstWhere((k) => k.personen.single == 'gv');
    expect(plan.personBei(gv.rahmen.center), 'gv');
    expect(plan.personBei(Offset.zero), isNull);
  });

  group('Maler', () {
    for (final stil in Lebensbaumstil.values) {
      for (final richtung in Lebensbaumrichtung.values) {
        test('${stil.name}, ${richtung.name}: malt ohne Fehler', () {
          const masse = Lebensbaummasse();
          final plan = lebensbaumplan(
            netz(),
            'ich',
            ordnung,
            richtung: richtung,
            masse: masse,
          );
          final aufnahme = ui.PictureRecorder();
          LebensbaumMaler(
            plan: plan,
            masse: masse,
            farben: Lebensbaumfarben.fuer(stil),
            beschriftung: (id) => (name: id, lebensspanne: '1900–1980'),
            titel: 'Titel',
          ).paint(ui.Canvas(aufnahme), Size(plan.breite, plan.hoehe));
          aufnahme.endRecording().dispose();
        });
      }
    }
  });

  testWidgets('die Ansicht meldet den Tipp und nennt die Namen', (
    tester,
  ) async {
    const masse = Lebensbaummasse();
    final plan = lebensbaumplan(
      netz(),
      'ich',
      ordnung,
      richtung: Lebensbaumrichtung.vorfahren,
      masse: masse,
    );
    String? getippt;
    tester.view.physicalSize = Size(plan.breite, plan.hoehe);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: LebensbaumAnsicht(
            plan: plan,
            masse: masse,
            farben: Lebensbaumfarben.pergament,
            beschriftung: (id) => (name: 'Name $id', lebensspanne: null),
            titel: 'Titel',
            beiTipp: (id) => getippt = id,
          ),
        ),
      ),
    );
    final gv = plan.knoten.firstWhere((k) => k.personen.single == 'gv');
    await tester.tapAt(gv.rahmen.center);
    expect(getippt, 'gv');
    expect(find.bySemanticsLabel('Name gv'), findsOneWidget);
  });
}
