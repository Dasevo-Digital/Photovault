import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/widgets/develop_preview.dart';

/// Ob die Beschneidungswarnung überhaupt ERREICHBAR ist.
///
/// Das ist der Test, der gefehlt hat. `beschneidung_test.dart` prüft, ob
/// richtig gerechnet wird, `develop_uniforms_test.dart`, ob der Schalter
/// im Shader ankommt – beide rufen die Funktionen direkt auf. Dass der
/// Knopf dafür im Bildschirm gar nicht anklickbar war, konnte keiner von
/// beiden sehen.
///
/// Der Fehler: Der Knopf hing daran, dass die Shader-Vorschau gerade
/// läuft, und die lief nur beim ZIEHEN an einem Regler. Man hätte einen
/// Regler loslassen und den Knopf treffen müssen, bevor der native Render
/// fertig ist – 250 ms Entprellung plus Renderzeit. Eine Rechnung, die
/// stimmt, aber niemand auslösen kann, ist keine Funktion.
void main() {
  group('Bedienbarkeit des Knopfes', () {
    test('ohne Masken, mit geladenem Shader: bedienbar', () {
      expect(
        beschneidungBedienbar(
            maskenVorhanden: false, shaderGeladen: true, basisGeladen: true),
        isTrue,
      );
    });

    test('Masken schliessen ihn aus', () {
      // Der Shader zeichnet über einer neutralen Basis ohne
      // Maskenwirkung – die Markierung wäre dort schlicht falsch.
      expect(
        beschneidungBedienbar(
            maskenVorhanden: true, shaderGeladen: true, basisGeladen: true),
        isFalse,
      );
    });

    test('ohne Shader oder ohne Basis: nicht bedienbar', () {
      expect(
        beschneidungBedienbar(
            maskenVorhanden: false, shaderGeladen: false, basisGeladen: true),
        isFalse,
      );
      expect(
        beschneidungBedienbar(
            maskenVorhanden: false, shaderGeladen: true, basisGeladen: false),
        isFalse,
      );
    });

    test('das Ziehen spielt für die Bedienbarkeit KEINE Rolle', () {
      // Der eigentliche Regressionstest. Die Signatur kennt das Ziehen
      // gar nicht mehr – wer es wieder einbaut, muss diesen Test
      // anfassen und stolpert dabei über den Kommentar oben.
      expect(
        beschneidungBedienbar(
            maskenVorhanden: false, shaderGeladen: true, basisGeladen: true),
        isTrue,
        reason: 'ein Knopf, der nur waehrend des Ziehens klickbar ist, '
            'ist nicht klickbar',
      );
    });
  });

  group('Wann die Shader-Vorschau gezeigt wird', () {
    test('beim Ziehen, auch ohne Warnung', () {
      expect(
        shaderVorschauZeigen(bedienbar: true, zieht: true, warnungAn: false),
        isTrue,
      );
    });

    test('bei eingeschalteter Warnung, auch ohne Ziehen', () {
      // Genau der Fall, den es vorher nicht gab: Warnung an, Hand weg
      // vom Regler, Markierung trotzdem im Bild.
      expect(
        shaderVorschauZeigen(bedienbar: true, zieht: false, warnungAn: true),
        isTrue,
      );
    });

    test('weder noch: der native Render bleibt stehen', () {
      // Wichtig, damit die Shader-Naeherung nicht dauerhaft das
      // massgebliche Bild verdraengt.
      expect(
        shaderVorschauZeigen(bedienbar: true, zieht: false, warnungAn: false),
        isFalse,
      );
    });

    test('nicht bedienbar schlaegt beides', () {
      // Mit Masken hilft auch eine eingeschaltete Warnung nicht.
      expect(
        shaderVorschauZeigen(bedienbar: false, zieht: true, warnungAn: true),
        isFalse,
      );
    });
  });

  group('Die Verdrahtung im Bildschirm', () {
    // Die Regel oben ist geprueft, die eine Zeile, die sie BENUTZT, nicht.
    // Genau dort sass der Fehler. Dasselbe Verfahren wie in
    // keine_festen_texte_test.dart: grob, aber es sieht etwas, das weder
    // analyze noch ein Widget-Test sehen kann - der Shader laedt im Test
    // ohnehin nicht, dort waere der Knopf aus dem falschen Grund aus.
    final quelle = File('lib/screens/develop_screen.dart').readAsStringSync();

    test('der Knopf haengt an _shaderMoeglich, nicht am Ziehen', () {
      final knopf = RegExp(
        r'tooltip:[^;]*?entwBeschneidung.*?onPressed:\s*(\w+)',
        dotAll: true,
      ).firstMatch(quelle);

      expect(knopf, isNotNull,
          reason: 'Knopf fuer die Beschneidungswarnung nicht gefunden - '
              'wurde er umbenannt? Dann diesen Test nachziehen.');
      expect(knopf!.group(1), '_shaderMoeglich',
          reason: 'An _zeigeShaderVorschau gehaengt waere der Knopf nur '
              'waehrend des Ziehens klickbar - also nie. Genau das war '
              'der Fehler.');
    });

    test('_shaderMoeglich kennt das Ziehen nicht', () {
      final getter = RegExp(r'bool get _shaderMoeglich =>(.*?);', dotAll: true)
          .firstMatch(quelle);
      expect(getter, isNotNull);
      expect(getter!.group(1), isNot(contains('_dragging')),
          reason: 'Sobald das Ziehen wieder in die Bedienbarkeit einzieht, '
              'ist der Knopf erneut unerreichbar.');
    });
  });
}
