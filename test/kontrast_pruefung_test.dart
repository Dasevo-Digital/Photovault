import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Lesbarkeit kleiner Beschriftungen.
///
/// Anlass: In der App stehen mehrere Beschriftungen in `Colors.grey` auf
/// dunklem Grund, teils bei 9 oder 10 Punkten. Ob das reicht, laesst sich
/// rechnen statt schaetzen - WCAG verlangt 4,5:1 fuer kleinen Text, 3:1
/// fuer grossen (ab 18,66 px fett bzw. 24 px).
double _kanal(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double helligkeit(Color f) =>
    0.2126 * _kanal(f.r) + 0.7152 * _kanal(f.g) + 0.0722 * _kanal(f.b);

double kontrast(Color a, Color b) {
  final ha = helligkeit(a), hb = helligkeit(b);
  final hell = math.max(ha, hb), dunkel = math.min(ha, hb);
  return (hell + 0.05) / (dunkel + 0.05);
}

void main() {
  final dunkel = buildDarkTheme().colorScheme;

  test('die gemessenen Werte, zum Nachlesen', () {
    // ignore: avoid_print
    print('Grundflaeche: ${dunkel.surface}');
    for (final (name, farbe) in [
      ('onSurface', dunkel.onSurface),
      ('onSurfaceVariant', dunkel.onSurfaceVariant),
      ('outline', dunkel.outline),
      ('Colors.grey', Colors.grey),
      ('Colors.white', Colors.white),
    ]) {
      // ignore: avoid_print
      print('  $name: ${kontrast(farbe, dunkel.surface).toStringAsFixed(2)}:1');
    }
  });

  test('die Grundfarben des dunklen Themas tragen', () {
    expect(kontrast(dunkel.onSurface, dunkel.surface), greaterThan(4.5),
        reason: 'Fliesstext auf der Grundflaeche');
    expect(kontrast(dunkel.onSurfaceVariant, dunkel.surface),
        greaterThan(4.5),
        reason: 'die zweite Textfarbe, in der die meisten Beschriftungen '
            'stehen');
  });

  /// **Dieselbe Halbblindheit wie beim Umriss, eine Runde spaeter.**
  ///
  /// Die alte Pruefung stand allein gegen das dunkle Thema – dort
  /// besteht `Colors.grey` mit 6,90:1, und damit war die Sache erledigt.
  /// Im hellen Thema sind es 2,55:1 auf der Grundflaeche und 2,07:1 auf
  /// einer Karte. Das ist weniger als die Haelfte des Verlangten, und es
  /// betraf zwoelf Beschriftungen bei 10 bis 12 Punkten.
  ///
  /// Gefunden in der 23. Pruefrunde, mit demselben Rechenweg, den die
  /// Gruppe darunter fuer `outline` gegangen ist.
  group('Colors.grey ist keine Beschriftungsfarbe', () {
    for (final (name, schema) in [
      ('hell', buildLightTheme().colorScheme),
      ('dunkel', buildDarkTheme().colorScheme),
    ]) {
      for (final (wo, grund) in [
        ('Grundflaeche', schema.surface),
        ('Karte', schema.surfaceContainerHighest),
      ]) {
        test('die Farbe des Themas traegt, $name, auf der $wo', () {
          final wert = kontrast(schema.onSurfaceVariant, grund);
          expect(wert, greaterThan(4.5),
              reason: 'onSurfaceVariant ergibt hier '
                  '${wert.toStringAsFixed(2)}:1');
        });
      }
    }

    test('und das feste Grau taugt im hellen Thema nachweislich nicht', () {
      // Die Gegenprobe: Sie haelt fest, WARUM getauscht wurde.
      final hell = buildLightTheme().colorScheme;
      expect(kontrast(Colors.grey, hell.surface), lessThan(4.5));
      expect(kontrast(Colors.grey, hell.surfaceContainerHighest), lessThan(4.5));
    });
  });

  /// **Diese Pruefung gab es schon – und sie sah nur die Haelfte.**
  ///
  /// Sie stand allein gegen das dunkle Thema, und dort besteht `outline`
  /// mit 5,85:1. Im hellen Thema sind es 4,28:1, und auf einer Karte –
  /// wo die meisten dieser Beschriftungen tatsaechlich stehen – 3,48:1.
  /// Der Satz im alten Kommentar war richtig, nur ungeprueft: `outline`
  /// ist fuer Linien gedacht, nicht fuer Schrift.
  ///
  /// Gefunden in der 15. Pruefrunde an 41 Stellen im Quelltext.
  group('der Umriss ist keine Textfarbe', () {
    for (final (name, schema) in [
      ('hell', buildLightTheme().colorScheme),
      ('dunkel', buildDarkTheme().colorScheme),
    ]) {
      // Zwei Gruende, nicht einer: Die Grundflaeche und die Karte, auf der
      // in dieser App die allermeisten Hinweistexte liegen.
      for (final (wo, grund) in [
        ('Grundflaeche', schema.surface),
        ('Karte', schema.surfaceContainerHighest),
      ]) {
        test('zweitrangiger Text, $name, auf der $wo', () {
          final ausweich = kontrast(schema.onSurfaceVariant, grund);
          expect(ausweich, greaterThan(4.5),
              reason: 'onSurfaceVariant ist die Farbe des Themas fuer '
                  'zweitrangigen Text und ergibt hier '
                  '${ausweich.toStringAsFixed(2)}:1');
        });
      }
    }

    test('und outline taugt im hellen Thema nachweislich nicht dafuer', () {
      // Die Gegenprobe zum Obigen: Sie haelt fest, WARUM getauscht wurde.
      // Sollte Material die Palette einmal aendern, faellt dieser Test –
      // und dann darf man neu entscheiden.
      final hell = buildLightTheme().colorScheme;
      expect(kontrast(hell.outline, hell.surface), lessThan(4.5));
      expect(kontrast(hell.outline, hell.surfaceContainerHighest),
          lessThan(4.5));
    });
  });
}
