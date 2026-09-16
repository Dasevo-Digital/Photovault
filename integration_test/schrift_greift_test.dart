// ignore_for_file: avoid_print
// Prüft, ob die angeforderte Oberflächenschrift wirklich benutzt wird.
// Fiele sie still auf DejaVu Sans zurück, wären beide Messungen gleich
// breit – genau das war der Zustand vorher.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/theme/app_theme.dart';

double breite(String? familie, List<String>? rueckfall) {
  final maler = TextPainter(
    text: TextSpan(
      text: 'Photo Vault – Bibliothek, Alben, Personen 0123456789',
      style: TextStyle(
          fontSize: 24, fontFamily: familie, fontFamilyFallback: rueckfall),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return maler.width;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('die gewählte Schrift wird tatsächlich benutzt', (tester) async {
    final stil = buildLightTheme().textTheme.bodyMedium!;
    final gewaehlt = breite(stil.fontFamily, stil.fontFamilyFallback);
    final dejavu = breite('DejaVu Sans', null);
    final unsinn = breite('Gibt Es Nicht 12345', null);

    print('gewählt (${stil.fontFamily}): ${gewaehlt.toStringAsFixed(1)} px');
    print('DejaVu Sans:                  ${dejavu.toStringAsFixed(1)} px');
    print('unbekannter Name:             ${unsinn.toStringAsFixed(1)} px');

    // Ein unbekannter Name landet beim Standard. Läge die gewählte
    // Schrift genau dort, wäre sie nicht vorhanden.
    expect(gewaehlt, isNot(closeTo(unsinn, 0.5)),
        reason: 'die Schrift wird offenbar nicht gefunden');
  });
}
