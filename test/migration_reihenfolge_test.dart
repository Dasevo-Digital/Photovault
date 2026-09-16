// **Die Migrationsschritte müssen aufsteigend stehen.**
//
// Ein Schritt darf voraussetzen, was die niedrigeren angelegt haben.
// Schritt 65 biegt Zuordnungen in `aktivitaet_aufnahmen` um; diese
// Tabelle entsteht in Schritt 54. Standen die Schritte absteigend, lief
// 65 vor 54 – und eine ältere Bibliothek liess sich gar nicht mehr
// öffnen, weil die Migration mit „no such table" abbrach.
//
// **Warum am Quelltext und nicht an einer Datenbank.** Um es an einer
// Datenbank zu zeigen, bräuchte man je Fassung eine gewachsene Kopie;
// die gibt es nur für ein paar (siehe `migration_echt_test.dart`, das
// `PV_MIGRATION_DIR` braucht). Die Reihenfolge ist dagegen eine
// Eigenschaft des Quelltextes, und genau die ist verrutscht.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('die Schritte in onUpgrade stehen aufsteigend', () {
    final quelle = File('lib/db/database.dart');
    expect(quelle.existsSync(), isTrue, reason: 'aus dem Projektordner starten');
    final text = quelle.readAsStringSync();

    final anfang = text.indexOf('onUpgrade: (m, from, to) async {');
    expect(anfang, greaterThan(0), reason: 'onUpgrade nicht gefunden');

    final nummern = RegExp(r'if \(from < (\d+)\)')
        .allMatches(text.substring(anfang))
        .map((m) => int.parse(m.group(1)!))
        .toList();

    expect(nummern, isNotEmpty);
    expect(nummern, List.of(nummern)..sort(),
        reason: 'Ein neuer Schritt gehört ans ENDE der Kette, nicht an den '
            'Anfang: Er darf voraussetzen, was die niedrigeren angelegt '
            'haben.');
    // Und lückenlos: Eine übersprungene Nummer wäre eine Fassung, für
    // die niemand etwas tut – eine stille Lücke im Aufstiegsweg.
    for (var i = 1; i < nummern.length; i++) {
      expect(nummern[i], nummern[i - 1] + 1,
          reason: 'zwischen ${nummern[i - 1]} und ${nummern[i]}');
    }
  });
}
