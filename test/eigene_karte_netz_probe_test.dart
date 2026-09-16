@Tags(['netz'])
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:photo_vault/services/eigenkarte.dart';

/// Sonde: Stimmen die Zoomgrenzen der mitgelieferten Vorlagen noch?
///
/// Läuft auf Zuruf:
///   flutter test --tags netz --run-skipped test/eigene_karte_netz_probe_test.dart
///
/// **Warum eine Sonde und kein gewöhnlicher Test.** Die Grenze eines
/// Anbieters ändert sich, ohne dass jemand Bescheid sagt – und sie
/// ändert sich nicht so, dass es auffiele: OpenTopoMap und Esri
/// antworten oberhalb ihrer Datenlage mit **HTTP 200** und einer
/// Ersatzkachel. Nur die Grösse verrät es.
(int, int) _xy(double breite, double laenge, int z) {
  final n = 1 << z;
  final x = ((laenge + 180) / 360 * n).floor();
  final r = breite * math.pi / 180;
  final y =
      ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n).floor();
  return (x, y);
}

String _adresse(String vorlage, int z) {
  final (x, y) = _xy(52.3759, 9.7320, z);
  return vorlage
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y')
      .replaceAll('{s}', 'a')
      .replaceAll('{r}', '');
}

void main() {
  test('die Vorlagen ohne Schluessel tragen so weit wie angegeben', () async {
    final client = Client();
    addTearDown(client.close);
    for (final v in kartenvorlagen.where((v) => !v.brauchtSchluessel)) {
      final zeile = StringBuffer('${v.name.padRight(28)} (bis ${v.stufe}) ');
      final groessen = <int, int>{};
      for (final z in [v.stufe - 1, v.stufe, v.stufe + 1]) {
        final antwort = await client.get(Uri.parse(_adresse(v.url, z)),
            headers: const {
              'User-Agent': 'flutter_map (com.example.photoVault)'
            });
        groessen[z] = antwort.statusCode == 200 ? antwort.bodyBytes.length : -1;
        zeile.write('z$z:${antwort.statusCode}/${groessen[z]}B  ');
      }
      // ignore: avoid_print
      print(zeile);
      expect(groessen[v.stufe]! > 0, isTrue,
          reason: '${v.name}: die angegebene Stufe liefert nichts mehr');
      // Die Ersatzkachel ist bei Esri auf jeder zu hohen Stufe dieselbe
      // und deutlich kleiner als eine echte.
      expect(groessen[v.stufe]!, greaterThan(3000),
          reason: '${v.name}: die angegebene Stufe sieht nach Ersatzkachel aus');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Google antwortet ohne Schluessel verstaendlich', () async {
    // Die Erfolgsseite laesst sich hier nicht pruefen – dafuer braucht es
    // einen abrechnungsfaehigen Schluessel. Geprueft wird, dass der
    // Fehlerweg trägt: eine Meldung statt einer Ausnahme.
    final antwort = await googleSitzung('');
    expect(antwort.sitzung, isNull);
    expect(antwort.fehler, isNotNull);
    // ignore: avoid_print
    print('Google ohne Schluessel: ${antwort.fehler}');
  }, timeout: const Timeout(Duration(minutes: 1)));
}
