import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Jeder gebaute Bildschirm muss von irgendwo aus zu öffnen sein.**
///
/// Anlass ist der Befund der 16. Prüfrunde: `TrashScreen` war seit dem
/// ersten Commit vollständig da – Raster, Wiederherstellen, endgültiges
/// Löschen, leerer Zustand, alle Texte übersetzt – und wurde von **keiner
/// einzigen Stelle** aufgerufen. Gelöschte Fotos lagen damit in einem
/// Behälter, den niemand öffnen konnte, bis die automatische Leerung sie
/// nach dreissig Tagen endgültig entfernte. Die Duplikatsuche versprach
/// dabei wörtlich „über den Papierkorb wiederherstellbar".
///
/// Weder `analyze` noch die übrige Suite konnten das melden: Die Klasse
/// ist öffentlich, syntaktisch in Ordnung, und ein Bildschirm, den
/// niemand baut, bricht auch nichts. Nur diese Zählung findet es.
void main() {
  test('kein Bildschirm ohne Aufrufer', () {
    final bildschirme = Directory('lib/screens')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(bildschirme.length, greaterThan(20), reason: 'Ordner gefunden?');

    // Nur die Inhalte, nicht die Pfade als Schlüssel: Unter Windows
    // liefert `listSync` Rückstriche, und ein Pfad aus dem einen
    // Verzeichnisdurchlauf traf dann den Schlüssel aus dem anderen
    // nicht. Der Test fiel dort mit „Null check operator used on a null
    // value" - auf dem Mac lief er durch. Aufgefallen ist es erst beim
    // Bau von 2.2.1 auf der Windows-Maschine.
    final quellen = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          f.readAsStringSync(),
    ];

    /// Erklärt diese Zeile den Bildschirm, statt ihn zu benutzen?
    bool nurErklaerung(String zeile, String name) =>
        zeile.startsWith('class $name extends ') ||
        zeile.startsWith('class _${name}State extends ') ||
        zeile.contains('const $name({') ||
        zeile.contains('State<$name> createState') ||
        zeile.contains('_${name}State createState');

    final klasse = RegExp(r'^class (\w*Screen) extends ', multiLine: true);
    final ohneAufrufer = <String>[];

    for (final datei in bildschirme) {
      for (final treffer in klasse.allMatches(datei.readAsStringSync())) {
        final name = treffer.group(1)!;
        // Auch eine Stelle in derselben Datei zählt: Der Kalender öffnet
        // seine Jahresansicht von nebenan, und die ist damit erreichbar.
        final benutzt = RegExp('\\b$name\\s*\\(');
        final gefunden = quellen.any((quelle) => quelle
            .split('\n')
            .map((z) => z.trimLeft())
            .any((z) => !nurErklaerung(z, name) && benutzt.hasMatch(z)));
        if (!gefunden) ohneAufrufer.add('$name (${datei.path})');
      }
    }

    expect(ohneAufrufer, isEmpty,
        reason: 'Bildschirme, die niemand öffnen kann:\n'
            '${ohneAufrufer.join('\n')}');
  });
}
