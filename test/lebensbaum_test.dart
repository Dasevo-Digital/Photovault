import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/lebensbaum.dart';
import 'package:photo_vault/services/lebensbaum_bild.dart';
import 'package:photo_vault/services/lebensbaum_vorlage.dart';
import 'package:photo_vault/services/zierbaum.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/widgets/lebensbaum_ansicht.dart';
import 'package:photo_vault/widgets/lebensbaum_maler.dart';

/// Der Lebensbaum: eine Linie über mehrere Generationen auf einem
/// gemalten Baum.
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

  group('Vorlagen', () {
    test('jedes Schild liegt im Bild und überlappt kein anderes', () {
      for (final v in [
        for (final stil in Lebensbaumstil.values) ...lebensbaumvorlagen(stil),
      ]) {
        final stil = v.stil;
        final bild = Offset.zero & v.groesse;
        final alle = [v.wurzel, ...v.felder];
        for (final (i, f) in alle.indexed) {
          expect(bild.contains(f.rahmen.topLeft), isTrue, reason: stil.name);
          expect(bild.contains(f.rahmen.bottomRight), isTrue);
          // Die Schrift bleibt im Schild.
          expect(f.rahmen.intersect(f.schrift), f.schrift, reason: '$i');
          for (final g in alle.skip(i + 1)) {
            expect(
              f.rahmen.deflate(2).overlaps(g.rahmen.deflate(2)),
              isFalse,
              reason: '${stil.name}: ${f.rahmen} und ${g.rahmen}',
            );
          }
        }
      }
    });

    test('vier Generationen Vorfahren passen in jedes Bild', () {
      for (final stil in Lebensbaumstil.values) {
        expect(lebensbaumvorlage(stil).felder.length, greaterThanOrEqualTo(14));
      }
    });
  });

  group('Belegung', () {
    // Eine volle Ahnentafel über drei Generationen über p1.
    Verwandtschaftsnetz voll() => Verwandtschaftsnetz([
      for (var n = 1; n < 8; n++) ...[
        kante('p$n', 'p${2 * n}', Verwandtschaft.elternteil),
        kante('p$n', 'p${2 * n + 1}', Verwandtschaft.elternteil),
      ],
    ]);
    int nummer(String id) => int.parse(id.substring(1));

    for (final stil in Lebensbaumstil.values) {
      test('${stil.name}: jede Person einmal, die Väterlinie links', () {
        final vorlage = lebensbaumvorlage(stil);
        final plan = lebensbaumplan(
          voll(),
          'p1',
          nummer,
          richtung: Lebensbaumrichtung.vorfahren,
          generationen: 3,
        );
        final b = belegeVorlage(plan, vorlage);
        expect(b.wurzel, ['p1']);
        expect(b.verschwiegen, 0);
        expect(b.felder.values.toSet(), {for (var n = 2; n < 16; n++) 'p$n'});
        final mitte = vorlage.wurzel.rahmen.center.dx;
        final nachPerson = {
          for (final e in b.felder.entries) e.value: vorlage.felder[e.key],
        };
        // Die Vorfahren des Vaters (p2) tragen in jeder Generation die
        // kleinere Hälfte der Nummern.
        for (final MapEntry(key: id, value: f) in nachPerson.entries) {
          final n = nummer(id);
          final stufe = n.bitLength - 1;
          final vaeterlich = n < (3 << (stufe - 1));
          final x = f.rahmen.center.dx;
          expect(
            vaeterlich ? x <= mitte + 8 : x >= mitte - 8,
            isTrue,
            reason: '$id steht auf der falschen Seite',
          );
        }
        // Eltern stehen nicht unter ihrem Kind.
        for (final MapEntry(key: id, value: f) in nachPerson.entries) {
          final kind = nummer(id) ~/ 2;
          final unten = kind == 1 ? vorlage.wurzel : nachPerson['p$kind']!;
          expect(
            f.rahmen.center.dy,
            lessThan(unten.rahmen.center.dy + 31),
            reason: '$id unter p$kind',
          );
        }
      });
    }

    test('die kleine Tafel, solange alle Platz finden, sonst die grosse', () {
      for (final (generationen, schilder) in [(3, 14), (4, 30)]) {
        final plan = lebensbaumplan(
          Verwandtschaftsnetz([
            for (var n = 1; n < 16; n++) ...[
              kante('p$n', 'p${2 * n}', Verwandtschaft.elternteil),
              kante('p$n', 'p${2 * n + 1}', Verwandtschaft.elternteil),
            ],
          ]),
          'p1',
          nummer,
          richtung: Lebensbaumrichtung.vorfahren,
          generationen: generationen,
        );
        for (final stil in Lebensbaumstil.values) {
          final (:vorlage, :belegung) = passendeVorlage(plan, stil);
          expect(belegung.verschwiegen, 0, reason: stil.name);
          expect(belegung.felder, hasLength(schilder));
          final tafeln = lebensbaumvorlagen(stil);
          expect(vorlage, same(generationen == 3 ? tafeln.first : tafeln.last));
        }
      }
    });

    test('Wer keinen Platz hat, wird gezählt', () {
      final kanten = [
        for (var n = 1; n < 32; n++) ...[
          kante('p$n', 'p${2 * n}', Verwandtschaft.elternteil),
          kante('p$n', 'p${2 * n + 1}', Verwandtschaft.elternteil),
        ],
      ];
      final plan = lebensbaumplan(
        Verwandtschaftsnetz(kanten),
        'p1',
        nummer,
        richtung: Lebensbaumrichtung.vorfahren,
        generationen: 5,
      );
      final vorlage = lebensbaumvorlage(Lebensbaumstil.pergament);
      final b = belegeVorlage(plan, vorlage);
      expect(b.felder, hasLength(vorlage.felder.length));
      expect(b.verschwiegen, 62 - vorlage.felder.length);
      // Die nahen Generationen sind vollständig.
      for (var n = 2; n < 8; n++) {
        expect(b.felder.values, contains('p$n'));
      }
    });

    test('in den Nachkommen steht das Paar am Stamm', () {
      final plan = lebensbaumplan(
        netz(),
        'ich',
        ordnung,
        richtung: Lebensbaumrichtung.nachkommen,
      );
      final vorlage = lebensbaumvorlage(Lebensbaumstil.wappen);
      final b = belegeVorlage(plan, vorlage);
      expect(b.wurzel, ['ich', 'partner']);
      expect(b.felder.values.toSet(), {'k1', 'k2', 'e1'});
      final flaechen = vorlage.wurzelflaechen(b);
      expect(vorlage.personBei(b, flaechen[1].center), 'partner');
      expect(vorlage.personBei(b, Offset.zero), isNull);
    });
  });

  test('in den Nachkommen steht das Kind innen, sein Partner aussen', () {
    final n = Verwandtschaftsnetz([
      kante('links', 'ich', Verwandtschaft.elternteil),
      kante('rechts', 'ich', Verwandtschaft.elternteil),
      partnerKanteFuer('links', 'lp'),
      partnerKanteFuer('rechts', 'rp'),
    ]);
    const folge = ['ich', 'links', 'rechts', 'lp', 'rp'];
    final plan = lebensbaumplan(
      n,
      'ich',
      folge.indexOf,
      richtung: Lebensbaumrichtung.nachkommen,
    );
    double x(String id) {
      final k = plan.knoten.firstWhere((k) => k.personen.contains(id));
      return k.schilder[k.personen.indexOf(id)].center.dx;
    }

    final mitte = plan.wurzel.rahmen.center.dx;
    expect(x('lp'), lessThan(x('links')));
    expect(x('links'), lessThan(mitte));
    expect(x('rechts'), lessThan(x('rp')));
    expect(x('rechts'), greaterThan(mitte));
  });

  group('Paar', () {
    test('am Stamm das Paar, links ihre, rechts seine Seite', () {
      final n = Verwandtschaftsnetz([
        kante('ich', 'v', Verwandtschaft.elternteil),
        kante('ich', 'm', Verwandtschaft.elternteil),
        kante('schw', 'v', Verwandtschaft.elternteil),
        kante('p', 'pv', Verwandtschaft.elternteil),
        kante('p', 'pm', Verwandtschaft.elternteil),
        kante('pb', 'pv', Verwandtschaft.elternteil),
        partnerKanteFuer('ich', 'p'),
      ]);
      const folge = ['ich', 'p', 'v', 'm', 'pv', 'pm', 'schw', 'pb'];
      final plan = lebensbaumplan(
        n,
        'ich',
        folge.indexOf,
        richtung: Lebensbaumrichtung.paar,
      );
      expect(plan.wurzel.personen, ['ich', 'p']);
      double x(String id) => plan.knoten
          .firstWhere((k) => k.personen.contains(id))
          .rahmen
          .center
          .dx;
      int stufe(String id) =>
          plan.knoten.firstWhere((k) => k.personen.contains(id)).stufe;
      expect(stufe('schw'), 1);
      expect(stufe('pb'), 1);
      expect(stufe('v'), 2);
      expect(stufe('pv'), 2);
      // Aussen die Geschwister, innen die Eltern; ihre Seite links.
      expect(x('schw'), lessThan(x('v')));
      expect(x('m'), lessThan(x('pv')));
      expect(x('pm'), lessThan(x('pb')));
      keineUeberlappung(plan);
    });
  });

  group('Familie', () {
    for (final stil in Lebensbaumstil.values) {
      test('${stil.name}: jede Person ein Schild in der Krone', () {
        final n = Verwandtschaftsnetz([
          kante('ich', 'v', Verwandtschaft.elternteil),
          kante('ich', 'm', Verwandtschaft.elternteil),
          kante('schw', 'v', Verwandtschaft.elternteil),
          kante('schw', 'm', Verwandtschaft.elternteil),
          kante('neffe', 'schw', Verwandtschaft.elternteil),
          kante('neffe', 'schwager', Verwandtschaft.elternteil),
          kante('p', 'pv', Verwandtschaft.elternteil),
          kante('kind', 'ich', Verwandtschaft.elternteil),
          partnerKanteFuer('ich', 'p'),
          partnerKanteFuer('schw', 'schwager'),
        ]);
        final geflecht = geflechtUm(n, 'ich', [
          'ich',
          'p',
          'v',
          'm',
          'schw',
          'schwager',
          'neffe',
          'pv',
          'kind',
        ]);
        final vorlage = grosseLebensbaumvorlage(stil);
        final bild = familienbild(zierbaumplan(geflecht), vorlage);
        expect(bild.hintergrund, vorlage.leeresBild);
        expect(bild.personen.toSet(), geflecht.personen);
        final krone = vorlage.krone!.inflate(1);
        final rahmen = [for (final p in bild.plaetze) p.rahmen];
        for (final (i, r) in rahmen.indexed) {
          expect(krone.contains(r.topLeft), isTrue);
          expect(krone.contains(r.bottomRight), isTrue);
          for (final o in rahmen.skip(i + 1)) {
            expect(r.overlaps(o), isFalse, reason: '$r und $o');
          }
        }
        // Die Eltern stehen über der Person, der Neffe darunter.
        double y(String id) => bild.plaetze
            .firstWhere((p) => p.personen.contains(id))
            .rahmen
            .center
            .dy;
        expect(y('v'), lessThan(y('ich')));
        // Der Angeheiratete steht aussen, der Verwandte zum Stamm hin.
        double x(String id) => bild.plaetze
            .firstWhere((p) => p.personen.contains(id))
            .rahmen
            .center
            .dx;
        final stamm = vorlage.krone!.center.dx;
        if (x('schw') < stamm) {
          expect(x('schwager'), lessThan(x('schw')));
        } else {
          expect(x('schwager'), greaterThan(x('schw')));
        }
        expect(y('neffe'), greaterThan(y('schw')));
        expect(
          bild.personBei(
            bild.plaetze
                .firstWhere((p) => p.personen.contains('pv'))
                .rahmen
                .center,
          ),
          'pv',
        );
      });
    }
  });

  testWidgets('die Ansicht meldet den Tipp und nennt die Namen', (
    tester,
  ) async {
    final plan = lebensbaumplan(
      netz(),
      'ich',
      ordnung,
      richtung: Lebensbaumrichtung.vorfahren,
    );
    final vorlage = lebensbaumvorlage(Lebensbaumstil.pergament);
    final belegung = belegeVorlage(plan, vorlage);
    final inhalt = bildAusBelegung(vorlage, belegung);
    String? getippt;
    tester.view.physicalSize = vorlage.groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: LebensbaumAnsicht(
            inhalt: inhalt,
            beschriftung: (id) =>
                (name: 'Name $id', lebensspanne: null, bezeichnung: 'Grad'),
            titel: 'Titel',
            beiTipp: (id) => getippt = id,
          ),
        ),
      ),
    );
    final feld = belegung.felder.entries.firstWhere((e) => e.value == 'gv');
    await tester.tapAt(vorlage.felder[feld.key].rahmen.center);
    expect(getippt, 'gv');
    expect(find.bySemanticsLabel('Grad, Name gv'), findsOneWidget);
  });

  test('der Maler schreibt ohne Fehler in jedes Bild', () {
    for (final stil in Lebensbaumstil.values) {
      for (final richtung in Lebensbaumrichtung.values.where(
        (r) => r != Lebensbaumrichtung.familie,
      )) {
        final plan = lebensbaumplan(netz(), 'ich', ordnung, richtung: richtung);
        final vorlage = lebensbaumvorlage(stil);
        final aufnahme = ui.PictureRecorder();
        LebensbaumMaler(
          inhalt: bildAusBelegung(vorlage, belegeVorlage(plan, vorlage)),
          beschriftung: (id) => (
            name: 'Ein sehr langer Name $id',
            lebensspanne: '1900–1980',
            bezeichnung: 'Urgroßmutter',
          ),
          titel: 'Titel',
          untertitel: 'Untertitel',
        ).paint(ui.Canvas(aufnahme), vorlage.groesse);
        aufnahme.endRecording().dispose();
      }
    }
  });
}
