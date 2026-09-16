import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/state/library_state.dart';

/// Was vor dem ersten Bild passiert – und was nicht mehr.
///
/// **Die Messung.** `cities1000.txt` ist 31 MB gross; es zu lesen dauert
/// an der echten Datei **376 ms**. Das lag vor `_ready`, also vor dem
/// ersten Bild: Jeder Start begann mit einer reichlichen Drittelsekunde
/// Ladeanzeige für ein Verzeichnis, das für das erste Bild niemand
/// braucht.
///
/// Es lädt jetzt nebenher. Der Preis wäre ein Import in genau dieser
/// halben Sekunde, der still ohne Ortsnamen bliebe – deshalb warten die
/// zwei Stellen, die die Auflösung wirklich brauchen, auf [geoBereit].
/// Dieser Prüfstand hält beides fest, denn beides ist leicht wieder
/// wegzuräumen.
void main() {
  test('ohne Geodaten ist die Wartestelle sofort durch', () async {
    // Ohne `initialize()` – der öffnet Datenbank und Ordner. Geprüft wird
    // die Zusage: Auf `geoBereit` zu warten hängt nie.
    final bib = LibraryState();
    await bib.geoBereit.timeout(const Duration(seconds: 1));
    expect(bib.geocoder, isNull);
  });

  test('der Import wartet auf das Verzeichnis, die Ansichten nicht', () {
    // Eine Prüfung am Quelltext, weil sich der Unterschied nur dort
    // zeigt: Ein `await geoBereit` im Bildaufbau würde das erste Bild
    // wieder anhalten – genau das, was die Änderung abgeschafft hat.
    final quelle = _quelle('lib/state/library_state.dart');
    expect(quelle, contains('await geoBereit;'),
        reason: 'der Import muss warten');
    expect(quelle, isNot(contains('await _loadGeoDataIfPresent();')),
        reason: 'im Start darf nicht mehr darauf gewartet werden');

    for (final pfad in [
      'lib/screens/weltkarte_screen.dart',
      'lib/screens/reisen_screen.dart',
      'lib/screens/ortsansicht_screen.dart',
      'lib/screens/laenderliste_screen.dart',
    ]) {
      expect(_quelle(pfad), isNot(contains('geoBereit')),
          reason: '$pfad soll nicht warten, sondern zeigen, was da ist');
    }
  });
}

String _quelle(String pfad) => File(pfad).readAsStringSync();
