import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Kontrast lässt sich ausrechnen statt einschätzen.
///
/// Diese Prüfung gibt es, weil zweimal hintereinander dasselbe passiert
/// ist: Farben, die auf dunklem Grund entworfen wurden, standen später auf
/// hellem (Colors.orange, 2,05:1) – und Farben für abgeschaltete Elemente
/// standen unter erklärendem Text (Colors.white38, 3,44:1). Beide Male fiel
/// es erst beim Nachrechnen auf.
double _linear(double kanal) => kanal <= 0.03928
    ? kanal / 12.92
    : math.pow((kanal + 0.055) / 1.055, 2.4).toDouble();

double _leuchtdichte(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

/// Halbdurchsichtiges Weiss auf einem Grund – das ist, was jemand sieht.
Color _ueberlagert(Color vorn, Color grund) => Color.from(
      alpha: 1,
      red: vorn.r * vorn.a + grund.r * (1 - vorn.a),
      green: vorn.g * vorn.a + grund.g * (1 - vorn.a),
      blue: vorn.b * vorn.a + grund.b * (1 - vorn.a),
    );

double kontrast(Color vorn, Color grund) {
  final a = _leuchtdichte(_ueberlagert(vorn, grund));
  final b = _leuchtdichte(grund);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  group('dunkle Arbeitsflächen', () {
    const grund = DunkleFlaeche.grund;

    test('Text, den jemand lesen soll, schafft 4,5:1', () {
      for (final e in {
        'text': DunkleFlaeche.text,
        'zweitText': DunkleFlaeche.zweitText,
        'hinweis': DunkleFlaeche.hinweis,
      }.entries) {
        final wert = kontrast(e.value, grund);
        expect(wert, greaterThanOrEqualTo(4.5),
            reason: '${e.key} kommt nur auf ${wert.toStringAsFixed(2)}:1');
      }
    });

    test('die Rollen sind nach Kontrast geordnet', () {
      // Wäre ein Hinweis heller als der Haupttext, stimmte die Hierarchie
      // nicht mehr – und jemand hätte die Rollen vertauscht.
      expect(kontrast(DunkleFlaeche.text, grund),
          greaterThan(kontrast(DunkleFlaeche.zweitText, grund)));
      expect(kontrast(DunkleFlaeche.zweitText, grund),
          greaterThan(kontrast(DunkleFlaeche.hinweis, grund)));
      expect(kontrast(DunkleFlaeche.hinweis, grund),
          greaterThan(kontrast(DunkleFlaeche.inaktiv, grund)));
      expect(kontrast(DunkleFlaeche.inaktiv, grund),
          greaterThan(kontrast(DunkleFlaeche.linie, grund)));
    });

    test('inaktiv und linie tragen bewusst keinen Text', () {
      // Sie stehen absichtlich unter 4,5:1. Der Test hält fest, dass das
      // eine Entscheidung ist und kein Versehen: Wer sie für Text benutzt,
      // soll hier stolpern, wenn er die Werte anhebt.
      expect(kontrast(DunkleFlaeche.inaktiv, grund), lessThan(4.5));
      expect(kontrast(DunkleFlaeche.linie, grund), lessThan(4.5));
    });
  });

  group('helle und dunkle Oberfläche', () {
    test('Warnung und Erfolg schaffen 4,5:1 in beiden Helligkeiten', () {
      for (final theme in [buildLightTheme(), buildDarkTheme()]) {
        final semantik = theme.extension<AppSemantik>()!;
        final grund = theme.colorScheme.surface;
        for (final e in {
          'warnung': semantik.warnung,
          'erfolg': semantik.erfolg,
        }.entries) {
          final wert = kontrast(e.value, grund);
          expect(wert, greaterThanOrEqualTo(4.5),
              reason: '${e.key} auf ${theme.brightness.name} kommt nur auf '
                  '${wert.toStringAsFixed(2)}:1');
        }
      }
    });

    test('der Loeschknopf traegt die Fehlerfarbe des Themas', () {
      // `Colors.red` mit weisser Schrift ergibt 3,68:1 – ausgerechnet an
      // dem Knopf, bei dem man sicher sein muss, was man drueckt.
      for (final theme in [buildLightTheme(), buildDarkTheme()]) {
        final s = theme.colorScheme;
        expect(kontrast(s.onError, s.error), greaterThanOrEqualTo(4.5),
            reason: 'Knopfschrift auf ${theme.brightness.name}');
        expect(kontrast(Colors.white, Colors.red), lessThan(4.5),
            reason: 'die Gegenprobe: warum es nicht Colors.red ist');
      }
    });
  });

  /// Eine Quelltext-Pruefung nach dem Muster von
  /// `keine_festen_texte_test.dart`.
  ///
  /// [AppSemantik] wurde in Pruefrunde 4 genau dafuer angelegt, dass
  /// `Colors.green` und `Colors.orange` aus dem Quelltext verschwinden –
  /// sie sind fuer dunklen Grund gemacht und kommen auf heller Flaeche
  /// auf 2,65:1 bzw. 2,05:1, wo ein bedeutungstragendes Symbol 3:1
  /// braucht. In Pruefrunde 15 standen sie noch an fuenf Stellen: Die
  /// Umstellung hatte die Datei erwischt, in der sie oft vorkamen, und
  /// die uebrigen nicht.
  group('die Ampelfarben stehen nicht mehr im Quelltext', () {
    /// Bildschirme, die bewusst dauerhaft dunkel sind – dort gilt
    /// [DunkleFlaeche], und dort sind diese Farben richtig.
    const dunkleFlaechen = [
      'develop_screen.dart',
      'image_editor_screen.dart',
      'asset_viewer_screen.dart',
      'video_trim_screen.dart',
      'tone_curve_editor.dart',
      'histogram_view.dart',
      'color_mixer_panel.dart',
      'develop_preview.dart',
      'live_photo_view.dart',
      // Sternchen auf schwarzem Halbton ueber dem Foto.
      'stack_review_screen.dart',
    ];

    final verdaechtig = RegExp(r'Colors\.(green|orange|red)\b');

    test('nicht als Farbe auf einer Flaeche, die dem Thema folgt', () {
      final treffer = <String>[];
      for (final datei in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (datei.path.contains('/theme/')) continue;
        if (dunkleFlaechen.any(datei.path.endsWith)) continue;
        final zeilen = datei.readAsLinesSync();
        for (var i = 0; i < zeilen.length; i++) {
          // Kommentare duerfen die Farben nennen – sie erklaeren dort
          // gerade, warum sie nicht benutzt werden.
          final z = zeilen[i].trimLeft();
          if (z.startsWith('//') || z.startsWith('///')) continue;
          if (verdaechtig.hasMatch(zeilen[i])) {
            treffer.add('${datei.path}:${i + 1}: ${z.trim()}');
          }
        }
      }
      expect(treffer, isEmpty,
          reason: 'AppSemantik.erfolg/.warnung bzw. colorScheme.error '
              'sind die Farben dieser App:\n${treffer.join('\n')}');
    });
  });

  /// **Und dasselbe fuer das feste Grau.**
  ///
  /// `Colors.grey` besteht auf dunklem Grund (6,90:1) und faellt im
  /// hellen durch (2,55:1 auf der Grundflaeche, 2,07:1 auf einer Karte)
  /// – gerechnet in kontrast_pruefung_test.dart. Es stand an zwoelf
  /// Stellen als Farbe von Beschriftungen bei 10 bis 12 Punkten.
  ///
  /// `Colors.grey.shade###` bleibt erlaubt: Das sind Fuellfarben fuer
  /// leere Kacheln und Platzhalter, kein Text.
  test('Colors.grey steht nicht mehr als Textfarbe im Quelltext', () {
    final verdaechtig = RegExp(r'Colors\.grey\s*[,)]');
    final treffer = <String>[];
    for (final datei in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (datei.path.contains('/theme/')) continue;
      final zeilen = datei.readAsLinesSync();
      for (var i = 0; i < zeilen.length; i++) {
        final z = zeilen[i].trimLeft();
        if (z.startsWith('//') || z.startsWith('///')) continue;
        if (verdaechtig.hasMatch(zeilen[i])) {
          treffer.add('${datei.path}:${i + 1}: ${z.trim()}');
        }
      }
    }
    expect(treffer, isEmpty,
        reason: 'colorScheme.onSurfaceVariant ist die Farbe des Themas '
            'fuer zweitrangigen Text:\n${treffer.join('\n')}');
  });
}
