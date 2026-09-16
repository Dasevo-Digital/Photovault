import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/theme/zierbaum_farben.dart';
import 'package:yaml/yaml.dart';

/// Die mitgelieferte Schrift.
///
/// **Warum das einen eigenen Prüfstand verdient.** Eine Schrift, die
/// nicht da ist, fällt nicht auf: Flutter nimmt still die des Systems,
/// und auf dem Rechner des Entwicklers sieht das ordentlich aus. Erst auf
/// einer anderen Plattform – oder auf dem gedruckten Blatt – zeigt sich,
/// dass nie eine eigene Schrift geladen wurde.
///
/// Genau das stand schon im Plan als Falle, und genau so ist es
/// eingetreten: Der Quelltext verlangte `fontFamily: zierschrift`, bevor
/// es die Schrift überhaupt gab.
void main() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final schriften = (pubspec['flutter'] as YamlMap)['fonts'] as YamlList;

  Map<String, String> familien() => {
        for (final eintrag in schriften)
          eintrag['family'] as String:
              (eintrag['fonts'] as YamlList).first['asset'] as String,
      };

  test('beide Familien sind eingetragen', () {
    // Die Namen im Quelltext und die in der pubspec müssen dieselben
    // sein. Ein Tippfehler hier bleibt sonst unbemerkt: Flutter meldet
    // keine unbekannte Schriftfamilie, es zeichnet einfach anders.
    expect(familien().keys, containsAll([zierschrift, zierschriftGross]));
  });

  test('die Dateien liegen wirklich da', () {
    for (final e in familien().entries) {
      final datei = File(e.value);
      expect(datei.existsSync(), isTrue, reason: '${e.key}: ${e.value}');
      expect(datei.lengthSync(), greaterThan(10000),
          reason: 'eine Schrift von wenigen Bytes ist keine');
      // TrueType beginnt mit 0x00010000, OpenType mit "OTTO".
      final kopf = datei.openSync().readSync(4);
      expect(kopf.sublist(0, 4), anyOf(equals([0, 1, 0, 0]), equals('OTTO'.codeUnits)),
          reason: '${e.value} sieht nicht wie eine Schrift aus');
    }
  });

  test('die Lizenztexte werden mit ausgeliefert', () {
    // Die SIL Open Font License verlangt das ausdrücklich. Ohne den
    // Eintrag in der pubspec läge die Datei im Baum und nicht im Paket.
    final assets =
        ((pubspec['flutter'] as YamlMap)['assets'] as YamlList).cast<String>();
    for (final pfad in [
      'assets/fonts/OFL-EBGaramond.txt',
      'assets/fonts/OFL-GreatVibes.txt',
    ]) {
      expect(assets, contains(pfad));
      final text = File(pfad).readAsStringSync();
      expect(text, contains('SIL OPEN FONT LICENSE'));
    }
  });

  testWidgets('das Gewicht kommt über die Achse, nicht über fontWeight',
      (tester) async {
    // EB Garamond ist eine veränderliche Schrift: eine Datei für alle
    // Schnitte. `fontWeight` allein bewegt deren wght-Achse nicht –
    // Flutter legte stattdessen einen künstlichen Fettdruck darüber, und
    // der sieht bei einer Renaissance-Antiqua aus wie ein Druckfehler.
    expect(zierGewicht(700).single.axis, 'wght');
    expect(zierGewicht(700).single.value, 700);

    await tester.pumpWidget(MaterialApp(
      home: Text('Müller',
          style: TextStyle(
              fontFamily: zierschrift, fontVariations: zierGewicht(600))),
    ));
    final stil = tester.widget<Text>(find.byType(Text)).style!;
    expect(stil.fontFamily, zierschrift);
    expect(stil.fontVariations, isNotEmpty);
  });
}
