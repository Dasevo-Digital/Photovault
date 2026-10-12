import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/whisper_service.dart';

/// Was an der Spracherkennung ohne Modell prüfbar ist: der Weg von Token
/// zu Text und die Regeln, nach denen ein Stück verworfen wird.
void main() {
  test('jedes Byte hat genau ein Zeichen im Vokabular', () {
    final bytes = whisperBytesAusZeichen();
    expect(bytes, hasLength(256));
    expect(bytes.values.toSet(), hasLength(256));
    // Das Leerzeichen steht als „Ġ" (U+0120), wie bei GPT-2.
    expect(bytes[0x120], 0x20);
  });

  test('Token werden zu Text, Umlaute über ihre Bytes', () {
    // „ü" ist in UTF-8 C3 BC und steht im Vokabular als „Ã¼".
    final v = WhisperVokabular({'Ġgr': 1, 'Ã¼': 2, 'n': 3, '!': 4});
    expect(v.text([1, 2, 3, 4]), ' grün!');
    // Steuer- und Zeitmarken-Token fallen weg.
    expect(
      v.text([WhisperService.anfang, 1, 2, 3, WhisperService.textEnde]),
      ' grün',
    );
  });

  test('Wiederholungen erkennt das Kompressionsmass', () {
    expect(
      whisperKompression(
        'Wir feiern heute den 70. Geburtstag von Oma Gertrud im Garten.',
      ),
      lessThan(2.4),
    );
    expect(whisperKompression('ლ' * 200), greaterThan(2.4));
    expect(whisperKompression(''), 0);
  });

  test('verworfen wird Stille mit unsicheren Wörtern und jede Schleife', () {
    expect(
      whisperVerwerfen(
        keineSprache: 0.86,
        mittlereLogWkt: -1.6,
        kompression: 0.3,
      ),
      isTrue,
    );
    // Sicher gesprochene Wörter gelten, auch wenn das Modell Stille
    // vermutet hätte.
    expect(
      whisperVerwerfen(
        keineSprache: 0.7,
        mittlereLogWkt: -0.2,
        kompression: 1.1,
      ),
      isFalse,
    );
    expect(
      whisperVerwerfen(
        keineSprache: 0.0,
        mittlereLogWkt: -0.1,
        kompression: 12.5,
      ),
      isTrue,
    );
  });

  test('99 Sprachen, Deutsch an dritter Stelle', () {
    expect(whisperSprachen, hasLength(99));
    expect(whisperSprachen.indexOf('de'), 2);
    expect(whisperSprachen.last, 'su');
  });
}
