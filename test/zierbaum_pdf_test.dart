import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/tafel_pdf.dart';
import 'package:photo_vault/theme/zierbaum_farben.dart';
import 'package:photo_vault/widgets/zierbaum_ansicht.dart';

/// Die Tafel zum Aufhaengen.
///
/// **Warum das ein eigener Pruefstand ist.** Auf dem Bildschirm sind die
/// Schilder Widgets, auf dem Blatt werden sie gemalt - zwei
/// Darstellungen desselben Baums. Dass die zweite ueberhaupt zustande
/// kommt, sieht man dem Quelltext nicht an: `toImage` braucht einen
/// echten Zeichendurchgang, und der laeuft im Test nur innerhalb von
/// `runAsync`.
void main() {
  testWidgets('aus dem Zierbaum wird ein PDF', (tester) async {
    final netz = Verwandtschaftsnetz([
      kante('vater', 'opa', Verwandtschaft.elternteil),
      partnerKanteFuer('opa', 'oma'),
      partnerKanteFuer('vater', 'mutter'),
      kante('ich', 'vater', Verwandtschaft.elternteil),
      kante('ich', 'mutter', Verwandtschaft.elternteil),
      kante('anna', 'vater', Verwandtschaft.elternteil),
      partnerKanteFuer('anna', 'schwager'),
      kante('neffe', 'anna', Verwandtschaft.elternteil),
      kante('schwager', 'schwagersVater', Verwandtschaft.elternteil),
    ]);
    const namen = {
      'opa': 'Hans Müller', 'oma': 'Grete Müller', 'vater': 'Karl Müller',
      'mutter': 'Erika Müller', 'ich': 'Martin Müller', 'anna': 'Anna Weber',
      'schwager': 'Michael Weber', 'neffe': 'Tim Weber',
      'schwagersVater': 'Kurt Weber',
    };
    final g = geflechtUm(netz, 'ich', namen.keys.toList());

    Uint8List? bytes;
    await tester.runAsync(() async {
      bytes = await baueZierbaumPdf(
        geflecht: g,
        beschriftung: (id) => Schildinhalt(
          name: namen[id]!,
          verwandtschaft: id == 'ich' ? null : 'Verwandt',
          lebensspanne: '1931–2004',
        ),
        familienname: haeufigsterNachname(namen.values),
        farben: Zierbaumfarben.dunkel,
        textRichtung: TextDirection.ltr,
      );
    });

    // Ein PDF, und zwar eines mit Inhalt. Die Zahl ist grob: Es geht
    // darum, dass wirklich ein Bild darin steckt und nicht ein leeres
    // Blatt - gemessen sind es rund 550 kB.
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
    expect(bytes!.length, greaterThan(100000));

    // Der Familienname wird aus den Namen erschlossen, nicht behauptet.
    expect(haeufigsterNachname(namen.values), 'Müller');
  });
}
