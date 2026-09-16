import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Wacht darüber, dass ONNX-Tensoren auch dann freigegeben werden, wenn ein
/// Aufruf dazwischen wirft.
///
/// Warum das eine eigene Wache braucht: Ein liegengebliebener [OrtValue] ist
/// nativer Speicher. Der Dart-Sammler holt ihn nie zurück, kein Test schlägt
/// deswegen fehl, und `flutter analyze` sieht nichts – die Freigabe steht ja
/// da, nur eben eine Zeile zu spät. Genau so ist die Lücke nach Prüfrunde 3
/// teilweise zurückgekommen: In `ocr_service` war der Eingabetensor
/// abgesichert, die Ausgaben nicht, und in drei weiteren Diensten stand die
/// Freigabe ganz ohne `finally` hinter dem Aufruf. Aufgefallen ist das erst
/// beim Durchlesen in Prüfrunde 12.
///
/// Das Verfahren ist bewusst grob: Gezählt werden geschweifte Klammern, und
/// jedes `.dispose()` muss innerhalb eines `finally`-Blocks liegen. Dass ein
/// Dienst seine Sitzungen am Ende schliesst, stört dabei nicht – das
/// geschieht über `.close()`, nicht über `.dispose()`.
void main() {
  /// Zwei Dienste geben nicht am Ende eines einzelnen Aufrufs frei, sondern
  /// führen über einen ganzen Lauf mit Schleife eine Menge offener Tensoren
  /// mit und leeren sie im `finally`. Ihre `.dispose()`-Zeile steckt in
  /// einer Hilfsfunktion und liegt damit formal ausserhalb – die Zusage hält
  /// trotzdem, weil der Schlussblock nimmt, was noch offen ist. Für diese
  /// beiden wird deshalb genau dieses Muster geprüft statt der Klammerregel:
  /// der Name der mitgeführten Menge muss in einem `finally` durchlaufen und
  /// freigegeben werden.
  const mitOffenerMenge = {
    'lib/services/florence_captioning_service.dart': 'offen',
    'lib/services/translation_service.dart': 'liveTensors',
  };

  test('die beiden Dienste mit mitgeführter Menge leeren sie im finally', () {
    mitOffenerMenge.forEach((pfad, menge) {
      final quelle = File(pfad).readAsStringSync();
      expect(
        quelle.contains(RegExp(
            r'\}\s*finally\s*\{\s*for\s*\(final\s+\w+\s+in\s+' + menge + r'\)')),
        isTrue,
        reason: '$pfad führt „$menge" mit, leert die Menge aber nicht mehr in '
            'einem finally – damit fällt die Ausnahme unten in sich zusammen.',
      );
    });
  });

  test('jede Tensor-Freigabe steht in einem finally', () {
    final dienste = Directory('lib/services')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('OrtValue'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(dienste, isNotEmpty,
        reason: 'Kein Dienst mit OrtValue gefunden – stimmt der Pfad noch?');

    final verstoesse = <String>[];

    for (final datei in dienste) {
      // Unter Windows liefert Directory.listSync Rückstriche, die Ausnahmen
      // oben stehen mit Schrägstrichen. Ohne das Angleichen greift keine
      // einzige Ausnahme und der Test ist genau dort rot, wo er es nicht
      // sein soll.
      final pfad = datei.path.replaceAll(r'\', '/');
      if (mitOffenerMenge.containsKey(pfad)) continue;
      final zeilen = datei.readAsLinesSync();
      // Stapel je offener Klammerebene: steht die Ebene in einem finally?
      final ebenen = <bool>[];
      var naechsteEbeneIstFinally = false;

      for (var nr = 0; nr < zeilen.length; nr++) {
        final zeile = _ohneKommentar(zeilen[nr]);
        var i = 0;
        while (i < zeile.length) {
          if (zeile.startsWith('finally', i)) {
            naechsteEbeneIstFinally = true;
            i += 'finally'.length;
            continue;
          }
          if (zeile.startsWith('.dispose()', i)) {
            if (!ebenen.contains(true)) {
              verstoesse.add('$pfad:${nr + 1}: ${zeilen[nr].trim()}');
            }
            i += '.dispose()'.length;
            continue;
          }
          final z = zeile[i];
          if (z == '{') {
            ebenen.add(ebenen.contains(true) || naechsteEbeneIstFinally);
            naechsteEbeneIstFinally = false;
          } else if (z == '}') {
            if (ebenen.isNotEmpty) ebenen.removeLast();
          }
          i++;
        }
      }
    }

    expect(
      verstoesse,
      isEmpty,
      reason: 'Diese Freigaben stehen ausserhalb eines finally-Blocks und '
          'unterbleiben deshalb, sobald der Aufruf davor wirft:\n'
          '${verstoesse.join('\n')}',
    );
  });
}

/// Schneidet einen Zeilenkommentar ab, lässt `https://` aber stehen.
String _ohneKommentar(String zeile) {
  for (var i = 0; i < zeile.length - 1; i++) {
    if (zeile[i] == '/' && zeile[i + 1] == '/') {
      if (i > 0 && zeile[i - 1] == ':') continue;
      return zeile.substring(0, i);
    }
  }
  return zeile;
}
