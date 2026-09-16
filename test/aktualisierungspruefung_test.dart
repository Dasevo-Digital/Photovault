import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/aktualisierungspruefung.dart';

/// Der Versionsvergleich entscheidet, ob dem Nutzer eine Aktualisierung
/// gemeldet wird. Eine erfundene Meldung wäre ärgerlicher als eine
/// ausgebliebene – im Zweifel gilt deshalb "nicht neuer".
void main() {
  group('Versionsvergleich', () {
    test('erkennt eine höhere Fassung in jeder Stelle', () {
      expect(Aktualisierungspruefung.istNeuer('0.4.1', '0.4.0'), isTrue);
      expect(Aktualisierungspruefung.istNeuer('0.5.0', '0.4.9'), isTrue);
      expect(Aktualisierungspruefung.istNeuer('1.0.0', '0.9.9'), isTrue);
    });

    test('gleiche und ältere Fassungen melden nichts', () {
      expect(Aktualisierungspruefung.istNeuer('0.4.0', '0.4.0'), isFalse);
      expect(Aktualisierungspruefung.istNeuer('0.3.9', '0.4.0'), isFalse);
      expect(Aktualisierungspruefung.istNeuer('0.4.0', '1.0.0'), isFalse);
    });

    test('ein führendes v stört nicht', () {
      expect(Aktualisierungspruefung.istNeuer('v0.5.0', '0.4.0'), isTrue);
      expect(Aktualisierungspruefung.istNeuer('v0.4.0', 'v0.4.0'), isFalse);
    });

    test('fehlende Stellen zählen als null', () {
      expect(Aktualisierungspruefung.istNeuer('0.5', '0.4.9'), isTrue);
      expect(Aktualisierungspruefung.istNeuer('1', '0.9.9'), isTrue);
      expect(Aktualisierungspruefung.istNeuer('0.4', '0.4.0'), isFalse);
    });

    test('Vorabfassungen werden auf ihre Zahlen reduziert', () {
      expect(Aktualisierungspruefung.istNeuer('0.5.0-beta', '0.4.0'), isTrue);
      // Gleiche Zahlen: Eine Vorabfassung gilt nicht als neuer.
      expect(Aktualisierungspruefung.istNeuer('0.4.0-beta', '0.4.0'), isFalse);
      expect(Aktualisierungspruefung.istNeuer('0.4.0+12', '0.4.0'), isFalse);
    });

    test('Unlesbares meldet keine Aktualisierung', () {
      expect(Aktualisierungspruefung.istNeuer('irgendwas', '0.4.0'), isFalse);
      expect(Aktualisierungspruefung.istNeuer('', '0.4.0'), isFalse);
      expect(Aktualisierungspruefung.istNeuer('0.4.x', '0.4.0'), isFalse,
          reason: 'lieber keine Meldung als eine erfundene');
      expect(Aktualisierungspruefung.istNeuer('0.5.0', 'kaputt'), isFalse);
    });
  });

  group('Abfrage', () {
    /// Fängt die Anfrage ab, statt wirklich ins Netz zu gehen – ein Test
    /// darf nicht von einem fremden Dienst abhängen.
    Dio dioMit(List<Map<String, dynamic>> releases) {
      final dio = Dio();
      dio.httpClientAdapter = _FesteAntwort(jsonEncode(releases));
      return dio;
    }

    test('nimmt die höchste Nummer aus der Liste', () async {
      // Die Reihenfolge der Schnittstelle ist nicht garantiert sortiert.
      final p = Aktualisierungspruefung(
        dio: dioMit([
          {'tag_name': 'v0.3.0', 'draft': false, 'html_url': 'https://example.invalid/3'},
          {'tag_name': 'v0.5.0', 'draft': false, 'html_url': 'https://example.invalid/5'},
          {'tag_name': 'v0.4.0', 'draft': false, 'html_url': 'https://example.invalid/4'},
        ]),
      );
      final stand = await p.pruefe('0.4.0');

      expect(stand.neueste, 'v0.5.0');
      expect(stand.istNeuereVerfuegbar, isTrue);
      expect(stand.seitenUrl, 'https://example.invalid/5');
    });

    test('Vorabversionen zählen mit – sonst fände die Prüfung nie etwas', () async {
      // Genau hier lag der Fehler: /releases/latest überspringt
      // Vorabversionen, und alle bisherigen Veröffentlichungen sind so
      // markiert. Die Abfrage lief deshalb in einen 404.
      final p = Aktualisierungspruefung(
        dio: dioMit([
          {'tag_name': 'v0.5.0', 'draft': false, 'prerelease': true},
        ]),
      );
      final stand = await p.pruefe('0.4.0');
      expect(stand.neueste, 'v0.5.0');
      expect(stand.istNeuereVerfuegbar, isTrue);
    });

    test('Entwürfe bleiben aussen vor', () async {
      final p = Aktualisierungspruefung(
        dio: dioMit([
          {'tag_name': 'v0.9.0', 'draft': true},
          {'tag_name': 'v0.4.0', 'draft': false},
        ]),
      );
      final stand = await p.pruefe('0.4.0');
      expect(stand.neueste, 'v0.4.0',
          reason: 'ein Entwurf ist noch nicht veröffentlicht');
      expect(stand.istNeuereVerfuegbar, isFalse);
    });

    test('meldet Gleichstand ohne Aufforderung', () async {
      final p = Aktualisierungspruefung(dio: dioMit([
        {'tag_name': 'v0.4.0', 'draft': false},
      ]));
      final stand = await p.pruefe('0.4.0');
      expect(stand.istNeuereVerfuegbar, isFalse);
    });

    test('eine leere Liste wirft verständlich', () async {
      final p = Aktualisierungspruefung(dio: dioMit([]));
      await expectLater(p.pruefe('0.4.0'), throwsA(isA<Exception>()));
    });
  });
}

class _FesteAntwort implements HttpClientAdapter {
  _FesteAntwort(this.rumpf);
  final String rumpf;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      rumpf,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
