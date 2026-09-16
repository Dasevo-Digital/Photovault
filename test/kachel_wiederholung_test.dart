import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Der zweite Versuch für gescheiterte Kacheln.
///
/// Anlass war ein Bildschirmfoto mit grauen Löchern in der
/// Topografiekarte. An einer echten Kartenfahrt nachgemessen: 44 von 170
/// Abrufen kamen mit **HTTP 404** zurück, dieselben Kacheln Sekunden
/// später mit 200 in unter 90 ms. OpenTopoMap rendert bei Bedarf und
/// meldet 404, solange die Kachel nicht fertig ist.
///
/// Ohne Nachhelfen bleibt daraus ein dauerhaftes Loch: Der
/// Vorgabe-RetryClient von flutter_map wiederholt allein bei 503, und
/// `EvictErrorTileStrategy.none` behält die gescheiterte Kachel.
void main() {
  group('Welche Antworten einen zweiten Versuch bekommen', () {
    test('404 gehoert dazu - das ist der ganze Anlass', () {
      // Der überraschende Fall. Ein 404 heisst hier nicht „gibt es
      // nicht", sondern „ist noch nicht gerendert".
      expect(kachelNochmalVersuchen(404), isTrue);
    });

    test('Serverfehler und Ueberlast ebenso', () {
      for (final s in [408, 429, 500, 502, 503, 504]) {
        expect(kachelNochmalVersuchen(s), isTrue, reason: 'Status $s');
      }
    });

    test('Erfolg wird nicht wiederholt', () {
      for (final s in [200, 204, 304]) {
        expect(kachelNochmalVersuchen(s), isFalse, reason: 'Status $s');
      }
    });

    test('eigene Fehler auch nicht', () {
      // 401/403 hiessen: falsch angefragt. Ein zweiter Versuch änderte
      // daran nichts und belastete nur einen gespendeten Server.
      for (final s in [400, 401, 403, 410, 414]) {
        expect(kachelNochmalVersuchen(s), isFalse, reason: 'Status $s');
      }
    });
  });

  group('Welche Fehler einen zweiten Versuch bekommen', () {
    test('Netzprobleme ja', () {
      expect(kachelFehlerNochmalVersuchen(const SocketException('weg')), isTrue);
      expect(kachelFehlerNochmalVersuchen(TimeoutException('zu lang')), isTrue);
      expect(
          kachelFehlerNochmalVersuchen(
              ClientException('Connection closed before full header')),
          isTrue);
    });

    test('ein Abbruch NICHT', () {
      // flutter_map bricht selbst ab, wenn eine Kachel beim schnellen
      // Ziehen nicht mehr gebraucht wird. Die zu wiederholen hiesse,
      // Arbeit für Bilder anzufordern, die niemand mehr sieht - und
      // ausgerechnet beim schnellen Ziehen entstehen die meisten davon.
      expect(kachelFehlerNochmalVersuchen(ClientException('Request cancelled')),
          isFalse);
      expect(kachelFehlerNochmalVersuchen(ClientException('aborted by client')),
          isFalse);
    });

    test('alles Uebrige nicht', () {
      expect(kachelFehlerNochmalVersuchen(const FormatException('krumm')), isFalse);
      expect(kachelFehlerNochmalVersuchen(ArgumentError('falsch')), isFalse);
    });
  });

  group('Die Wartezeit dazwischen', () {
    test('waechst, bleibt aber im Rahmen einer Kartenbewegung', () {
      final erste = kachelWartezeit(0);
      final zweite = kachelWartezeit(1);
      expect(zweite, greaterThan(erste));
      // Über zwei Sekunden hinaus ist die Kachel meist längst aus dem
      // Bild gescrollt - dann kommt sie an, wenn sie keiner mehr sieht.
      expect(erste + zweite, lessThan(const Duration(seconds: 3)));
      // Und sofort nachfassen hiesse, dem Renderer keine Zeit zu geben.
      expect(erste, greaterThanOrEqualTo(const Duration(milliseconds: 300)));
    });

    test('zwei Versuche, nicht mehr', () {
      // Die Kachelserver werden gespendet. Bei 44 Fehlschlägen sind das
      // 88 zusätzliche Abrufe - vertretbar; das Dreifache wäre es nicht.
      expect(kachelVersuche, 2);
    });
  });

  test('der Anbieter ist wirklich ein Einzelstueck', () {
    expect(identical(kartenKachelAnbieter(), kartenKachelAnbieter()), isTrue,
        reason: 'ein neuer Anbieter je Aufbau waere ein offener '
            'HTTP-Client je Aufbau');
  });
}
