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
import 'package:photo_vault/services/lebensbaum_vorlage.dart';
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
  const bezeichnungen = {
    'mann': 'Partner',
    'v': 'Vater',
    'm': 'Mutter',
    'gv1': 'Großvater',
    'gm1': 'Großmutter',
    'gv2': 'Großvater',
    'gm2': 'Großmutter',
    'ugv': 'Urgroßvater',
    'ugm': 'Urgroßmutter',
    'k1': 'Sohn',
    'k1p': 'Schwiegertochter',
    'k2': 'Tochter',
    'k3': 'Sohn',
    'e1': 'Enkel',
    'e2': 'Enkelin',
    'e3': 'Enkelin',
    'e4': 'Enkel',
    'e5': 'Enkel',
  };
  Lebensbaumschild schild(String id) {
    final (name, geburt, tod) = namen[id]!;
    return (
      name: name,
      lebensspanne: tod == null ? '*$geburt' : '$geburt–$tod',
      bezeichnung: bezeichnungen[id],
    );
  }

  Future<void> male(
    WidgetTester tester,
    Lebensbaumplan plan,
    Lebensbaumstil stil,
    Lebensbaumschild Function(String) beschriftung,
    String datei,
  ) async {
    final (:vorlage, :belegung) = passendeVorlage(plan, stil);
    final ziel = Platform.environment['PV_BILDER'];
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        File(vorlage.bild).readAsBytesSync(),
      );
      final bild = (await codec.getNextFrame()).image;
      const faktor = 2.0;
      final groesse = vorlage.groesse * faktor;
      final aufnahme = ui.PictureRecorder();
      LebensbaumMaler(
        vorlage: vorlage,
        belegung: belegung,
        beschriftung: beschriftung,
        titel: 'Stammbaum der Familie Wyrsch',
        untertitel: 'Die Vorfahren von Johanna Wyrsch',
        bild: bild,
      ).paint(ui.Canvas(aufnahme), groesse);
      final pixel = await aufnahme.endRecording().toImage(
        groesse.width.round(),
        groesse.height.round(),
      );
      if (ziel == null) return;
      final png = await pixel.toByteData(format: ui.ImageByteFormat.png);
      File('$ziel/$datei').writeAsBytesSync(png!.buffer.asUint8List());
    });
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
        final plan = lebensbaumplan(
          netz,
          'ich',
          ordnung,
          richtung: richtung,
          generationen: 3,
        );
        await male(
          tester,
          plan,
          stil,
          schild,
          'lebensbaum_${richtung.name}_${stil.name}.png',
        );
      });
    }
  }

  // Eine volle Ahnentafel über fünf Generationen: 31 Personen, die
  // oberste Reihe mit sechzehn – das füllt die grosse Tafel genau.
  for (final stil in Lebensbaumstil.values) {
    testWidgets('volle Ahnentafel – ${stil.name}', (tester) async {
      await schriften(tester);
      final kanten = <Kante>[];
      for (var n = 1; n < 16; n++) {
        kanten
          ..add(kante('p$n', 'p${2 * n}', Verwandtschaft.elternteil))
          ..add(kante('p$n', 'p${2 * n + 1}', Verwandtschaft.elternteil));
      }
      const vornamen = ['Anna', 'Josef', 'Maria', 'Kaspar', 'Rosa', 'Alois'];
      final plan = lebensbaumplan(
        Verwandtschaftsnetz(kanten),
        'p1',
        (id) => int.parse(id.substring(1)),
        richtung: Lebensbaumrichtung.vorfahren,
        generationen: 4,
      );
      expect(plan.knoten, hasLength(31));
      await male(tester, plan, stil, (id) {
        final n = int.parse(id.substring(1));
        return (
          name: '${vornamen[n % vornamen.length]} Wyrsch',
          lebensspanne: '${2000 - n * 9}–${2060 - n * 9}',
          bezeichnung: 'Nr. $n',
        );
      }, 'lebensbaum_voll_${stil.name}.png');
    });
  }
}
