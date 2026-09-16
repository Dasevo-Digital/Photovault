// **Was der Start kostet, bevor das erste Bild steht.**
//
// `main()` bereitet vor `runApp` die Datumsnamen vor – und zwar für
// ALLE Sprachen, weil die Oberfläche zur Laufzeit umschaltbar ist. Die
// App kennt aber genau zwei: Deutsch und Englisch.
//
//   flutter test tool/messe_start_test.dart
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  test('Datumsnamen vorbereiten', () async {
    final alle = Stopwatch()..start();
    await initializeDateFormatting();
    alle.stop();
    print('alle Sprachen: ${alle.elapsedMilliseconds} ms');
  });

  test('nur die beiden, die es gibt', () async {
    final zwei = Stopwatch()..start();
    await initializeDateFormatting('de');
    await initializeDateFormatting('en');
    zwei.stop();
    print('nur de und en: ${zwei.elapsedMilliseconds} ms');
  });
}
