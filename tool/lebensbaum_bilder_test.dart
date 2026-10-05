// Rendert den Lebensbaum in allen Stilen und beiden Richtungen als PNG,
// damit man ihn ansehen kann, ohne die App zu starten.
//
//   PV_BILDER=/pfad/zum/ordner flutter test tool/lebensbaum_bilder_test.dart
//
// Ohne PV_BILDER läuft der Test nur durch und prüft, dass das Malen nicht
// wirft. Die Namen sind ausgedacht.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/lebensbaum.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/widgets/lebensbaum_maler.dart';

void main() {
  // Vier Generationen: Ur-Grosseltern bis Enkel.
  final namen = {
    'ich': ('Johanna Wyrsch', 1952, null),
    'mann': ('Peter Wyrsch', 1949, 2019),
    'v': ('Anton Wyrsch', 1921, 1990),
    'm': ('Agatha Wyrsch', 1925, 2004),
    'gv1': ('Josef Wyrsch', 1890, 1961),
    'gm1': ('Maria Christen', 1894, 1970),
    'gv2': ('Alois Kaiser', 1888, 1944),
    'gm2': ('Rosa Kaiser', 1897, 1980),
    'ugv': ('Kaspar Wyrsch', 1860, 1931),
    'ugm': ('Elisabeth Remigi', 1864, 1938),
    'k1': ('Franz Wyrsch', 1975, null),
    'k1p': ('Nadja Meier', 1977, null),
    'k2': ('Louise Wyrsch', 1978, null),
    'k3': ('Adolf Wyrsch', 1981, null),
    'e1': ('Jakob Wyrsch', 2004, null),
    'e2': ('Dorothea Wyrsch', 2007, null),
    'e3': ('Mia Wyrsch', 2010, null),
    'e4': ('Ben Wyrsch', 2012, null),
    'e5': ('Leo Wyrsch', 2015, null),
  };
  final netz = Verwandtschaftsnetz([
    for (final (kind, elternteil) in [
      ('ich', 'v'),
      ('ich', 'm'),
      ('v', 'gv1'),
      ('v', 'gm1'),
      ('m', 'gv2'),
      ('m', 'gm2'),
      ('gv1', 'ugv'),
      ('gv1', 'ugm'),
      ('k1', 'ich'),
      ('k1', 'mann'),
      ('k2', 'ich'),
      ('k2', 'mann'),
      ('k3', 'ich'),
      ('e1', 'k1'),
      ('e1', 'k1p'),
      ('e2', 'k1'),
      ('e3', 'k2'),
      ('e4', 'k2'),
      ('e5', 'k3'),
    ])
      kante(kind, elternteil, Verwandtschaft.elternteil),
    partnerKanteFuer('ich', 'mann'),
    partnerKanteFuer('k1', 'k1p'),
  ]);
  int ordnung(String id) => namen.keys.toList().indexOf(id);
  Lebensbaumschild schild(String id) {
    final (name, geburt, tod) = namen[id]!;
    return (
      name: name,
      lebensspanne: tod == null ? '*$geburt' : '$geburt–$tod',
    );
  }

  Future<void> schriften(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final (familie, pfad) in [
        ('Zierschrift', 'assets/fonts/EBGaramond-Variable.ttf'),
        ('Zierschrift Gross', 'assets/fonts/GreatVibes-Regular.ttf'),
      ]) {
        final bytes = await File(pfad).readAsBytes();
        await (FontLoader(
          familie,
        )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
      }
    });
  }

  for (final richtung in Lebensbaumrichtung.values) {
    for (final stil in Lebensbaumstil.values) {
      testWidgets('${richtung.name} – ${stil.name}', (tester) async {
        await schriften(tester);
        const masse = Lebensbaummasse();
        final plan = lebensbaumplan(
          netz,
          'ich',
          ordnung,
          richtung: richtung,
          generationen: 3,
          masse: masse,
        );
        final aufnahme = ui.PictureRecorder();
        final leinwand = ui.Canvas(aufnahme);
        LebensbaumMaler(
          plan: plan,
          masse: masse,
          farben: Lebensbaumfarben.fuer(stil),
          beschriftung: schild,
          titel: 'Stammbaum der Familie Wyrsch',
        ).paint(leinwand, ui.Size(plan.breite, plan.hoehe));
        final bild = aufnahme.endRecording();

        final ziel = Platform.environment['PV_BILDER'];
        if (ziel == null) return;
        await tester.runAsync(() async {
          final pixel = await bild.toImage(
            plan.breite.round(),
            plan.hoehe.round(),
          );
          final png = await pixel.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$ziel/lebensbaum_${richtung.name}_${stil.name}.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        });
      });
    }
  }

  // Eine volle Ahnentafel über vier Generationen: 31 Schilder, die
  // oberste Reihe mit sechzehn. So voll wird es selten, aber so muss es
  // noch lesbar bleiben.
  testWidgets('volle Ahnentafel', (tester) async {
    await schriften(tester);
    final kanten = <Kante>[];
    for (var n = 1; n < 16; n++) {
      kanten
        ..add(kante('p$n', 'p${2 * n}', Verwandtschaft.elternteil))
        ..add(kante('p$n', 'p${2 * n + 1}', Verwandtschaft.elternteil));
    }
    final voll = Verwandtschaftsnetz(kanten);
    const vornamen = ['Anna', 'Josef', 'Maria', 'Kaspar', 'Rosa', 'Alois'];
    const masse = Lebensbaummasse();
    final plan = lebensbaumplan(
      voll,
      'p1',
      (id) => int.parse(id.substring(1)),
      richtung: Lebensbaumrichtung.vorfahren,
      generationen: 4,
      masse: masse,
    );
    expect(plan.knoten, hasLength(31));
    final aufnahme = ui.PictureRecorder();
    LebensbaumMaler(
      plan: plan,
      masse: masse,
      farben: Lebensbaumfarben.pergament,
      beschriftung: (id) {
        final n = int.parse(id.substring(1));
        return (
          name: '${vornamen[n % vornamen.length]} Wyrsch',
          lebensspanne: '${2000 - n * 9}–${2060 - n * 9}',
        );
      },
      titel: 'Stammbaum der Familie Wyrsch',
    ).paint(ui.Canvas(aufnahme), ui.Size(plan.breite, plan.hoehe));
    final bild = aufnahme.endRecording();
    final ziel = Platform.environment['PV_BILDER'];
    if (ziel == null) return;
    await tester.runAsync(() async {
      final pixel = await bild.toImage(plan.breite.round(), plan.hoehe.round());
      final png = await pixel.toByteData(format: ui.ImageByteFormat.png);
      File(
        '$ziel/lebensbaum_voll.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
