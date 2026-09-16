import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Wächter gegen `setState` nach einem `await`, ohne vorher zu prüfen, ob
/// der Bildschirm überhaupt noch da ist.
///
/// Der Fehler sieht harmlos aus und ist es nicht: Wer während einer langen
/// Auswertung – Integritätsprüfung, Duplikatsuche, KI-Suche – zurückgeht,
/// bekommt beim Eintreffen des Ergebnisses ein `setState` auf ein
/// weggeräumtes Widget. Im Debug-Bau ist das eine Zusicherung mit klarer
/// Meldung, im ausgelieferten Bau ein Absturz: Dort bleibt nur der Zugriff
/// auf das nicht mehr vorhandene Element übrig.
///
/// Die Suche geht vom `setState` rückwärts bis zur **Funktionsgrenze** –
/// dem Anfang der Methode oder des Rückrufs, in dem es steht. Findet sie
/// dazwischen ein `await`, aber kein `mounted`, wird gemeldet.
///
/// Dass an der Funktionsgrenze Schluss ist und nicht am nächsten `{`, ist
/// der Kern: Ein `if (…) {` oder `try {` dazwischen ändert nichts an der
/// Frage, ein Rückruf dagegen schon. `onPressed: () => setState(…)` läuft
/// erst auf eine Eingabe hin, und wer etwas anklicken kann, sieht es auch.
/// Steht das `await` aber INNERHALB desselben Rückrufs, zählt es sehr wohl –
/// eine erste Fassung dieses Wächters nahm ganze Rückrufe aus und übersah
/// damit genau die Stellen, für die er gebaut wurde.
void main() {
  /// Öffnet [zeile] eine Funktion? Also eine Methode, einen Rückruf oder
  /// einen Abschluss – erkennbar an der Parameterliste vor `{` oder `=>`.
  ///
  /// Kontrollstrukturen sehen genauso aus (`if (x) {`) und sind ausdrücklich
  /// keine Funktionsgrenze.
  bool istFunktionsgrenze(String zeile) {
    final rumpf = RegExp(r'\)\s*(async\s*\*?\s*)?(\{|=>)').hasMatch(zeile);
    if (!rumpf) return false;
    final kontrolle = RegExp(r'\b(if|for|while|switch|catch)\s*\(').hasMatch(zeile);
    return !kontrolle;
  }

  /// Ohne Zeilenkommentar – sonst zählt „// Vor dem await auflösen" als
  /// echtes `await` und der Wächter meldet eine Stelle, die in Ordnung ist.
  String ohneKommentar(String zeile) {
    final i = zeile.indexOf('//');
    return i < 0 ? zeile : zeile.substring(0, i);
  }

  int klammersaldo(String zeile) =>
      '{'.allMatches(zeile).length - '}'.allMatches(zeile).length;

  test('kein setState nach einem await ohne mounted-Prüfung', () {
    final beanstandet = <String>[];

    final dateien = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final datei in dateien) {
      final zeilen = datei.readAsLinesSync();

      for (var i = 0; i < zeilen.length; i++) {
        if (!zeilen[i].contains('setState(')) continue;
        // Nur, was VOR dem Aufruf steht: `setState(() {` öffnet selbst eine
        // Closure und sähe sonst aus wie eine Funktionsgrenze – womit sich
        // der Wächter genau um die Fälle brächte, für die er da ist.
        final vorAufruf = zeilen[i].substring(0, zeilen[i].indexOf('setState('));
        // `onDeleted: () => setState(…)` – Rückruf und Aufruf in einer Zeile.
        if (istFunktionsgrenze(vorAufruf)) continue;
        // `if (mounted) setState(…)` – die Prüfung steht oft daneben.
        if (zeilen[i].contains('mounted')) continue;

        // Rückwärts bis zum nächsten `await` ODER zur Funktionsgrenze –
        // je nachdem, was zuerst kommt.
        //
        // Maßgeblich ist allein die Strecke zwischen dem letzten `await`
        // und dem `setState`. Eine frühere Prüfung in derselben Methode
        // schützt nicht: Nach jedem weiteren `await` kann der Bildschirm
        // erneut verschwunden sein. Eine Fassung, die irgendein `mounted`
        // in der Methode gelten liess, übersah 15 von 50 eingebauten
        // Fehlern.
        var tiefe = 0;
        var awaitGesehen = false;
        var mountedGesehen = false;

        for (var j = i - 1; j >= 0; j--) {
          final zeile = ohneKommentar(zeilen[j]);

          // Ein Fangblock beginnt: Eine Prüfung im davorliegenden Versuch
          // gilt hier nicht – dorthin springt man ja gerade wegen eines
          // Fehlers, möglicherweise vor der Prüfung.
          if (RegExp(r'^\s*\}\s*(catch|finally|on)\b').hasMatch(zeile)) {
            mountedGesehen = false;
            continue;
          }

          // Ein Block, der hier endet, liegt NEBEN uns, nicht um uns herum.
          // Über ihn hinweglesen und nur seine Kopfzeile beurteilen: Ein
          // `if (!mounted) { … return; }` davor schützt uns, ein `await`
          // tief darin geht uns nichts an.
          if (RegExp(r'^\s*\}').hasMatch(zeile) && klammersaldo(zeile) < 0) {
            var saldo = klammersaldo(zeile);
            while (j > 0 && saldo < 0) {
              j--;
              saldo += klammersaldo(ohneKommentar(zeilen[j]));
            }
            final kopf = ohneKommentar(zeilen[j]);
            if (kopf.contains('mounted')) {
              mountedGesehen = true;
              break;
            }
            // Die Kopfzeile gehört noch zum geraden Ablauf: `await for (…) {`
            // oder `if (await …) {`. Sie nur auf `mounted` zu prüfen und das
            // `await` darin zu übersehen war der Grund, warum acht von 110
            // eingebauten Fehlern durchrutschten.
            if (RegExp(r'\bawait\b').hasMatch(kopf)) {
              awaitGesehen = true;
              break;
            }
            continue;
          }

          // Ein case-Zweig: Was in den Geschwister-Zweigen steht, läuft nie
          // zusammen mit diesem. Rückwärts über sie hinweg bis zum switch
          // selbst – der Code DAVOR ist wieder gemeinsamer Ablauf und zählt.
          // Ohne diesen Schritt meldete der Wächter jedes setState in einem
          // switch, sobald irgendein anderer Zweig ein await enthielt.
          if (RegExp(r'^\s*(case\b|default\s*:)').hasMatch(zeile)) {
            while (j > 0 &&
                !RegExp(r'^\s*switch\s*\(').hasMatch(ohneKommentar(zeilen[j]))) {
              j--;
            }
            continue;
          }

          if (zeile.contains('mounted')) {
            mountedGesehen = true;
            break;
          }
          if (RegExp(r'\bawait\b').hasMatch(zeile)) {
            awaitGesehen = true;
            break;
          }

          // Anfang einer Deklaration auf Klassenebene – auch ohne Klammer,
          // etwa `void _neuLaden() =>` über zwei Zeilen.
          if (RegExp(r'^  [A-Za-z@_]').hasMatch(zeile)) break;

          tiefe += klammersaldo(zeile);
          if (tiefe > 0) {
            if (istFunktionsgrenze(zeile)) break;
            tiefe = 0;
          }
        }

        if (awaitGesehen && !mountedGesehen) {
          beanstandet.add('${datei.path}:${i + 1}  ${zeilen[i].trim()}');
        }
      }
    }

    expect(beanstandet, isEmpty,
        reason: 'setState nach await ohne mounted-Prüfung:\n'
            '${beanstandet.join('\n')}');
  });
}
