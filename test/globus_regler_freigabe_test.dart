import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Der Globus-Regler hält die Erdtextur – und die passt nicht in Flutters
/// Bildspeicher.
///
/// Gemessen (integration_test/globus_textur_speicher_test.dart): 8192×4096
/// sind dekodiert 134,2 MB, der Bildspeicher fasst 104,9 MB, gehalten
/// werden davon 0 Bilder. Wer die Textur trotzdem am Leben hält, ist
/// dieser Regler – und dazu legt die Bibliothek in `loadSurface`
/// unbedingt eine zweite Kopie als Uint32List an. Zusammen rund 268 MB,
/// nach einem einzigen Blick auf den Globus, bis zum Programmende.
///
/// Eine Speicherlebensdauer lässt sich im Widget-Test nicht verlässlich
/// prüfen (der Sammler läuft, wann er will). Geprüft wird deshalb die
/// Stelle im Quelltext, an der die Referenz fällt – dieselbe Technik wie
/// in test/ort_freigabe_test.dart.
void main() {
  test('_setMode lässt den Globus-Regler los, wenn die Ansicht wechselt', () {
    final quelle = File('lib/screens/map_screen.dart').readAsStringSync();
    final start = quelle.indexOf('void _setMode(');
    expect(start, greaterThan(0), reason: '_setMode nicht gefunden');

    // Bis zur nächsten Methode auf derselben Einrückungsebene.
    final ende = quelle.indexOf('\n  }', start);
    expect(ende, greaterThan(start));
    final koerper = quelle.substring(start, ende);

    expect(koerper, contains('_globeController = null'),
        reason: 'Ohne diese Zeile bleiben rund 268 MB Erdtextur bis zum '
            'Programmende belegt, auch wenn der Globus längst zu ist.');
  });
}
