// ignore_for_file: avoid_print
// Übersteht die Karte einen vorübergehenden Fehlschlag?
//
// Anlass war ein Bildschirmfoto mit grauen Löchern in der
// Topografiekarte. Nachgemessen an einer echten Kartenfahrt im
// Alpenraum, mit mitschreibendem HTTP-Client:
//
//   170 Kachelabrufe -> 126 x 200, 44 x 404   (alle auf Stufe 17)
//   dieselben 404-Kacheln Sekunden spaeter -> 200, in 70-90 ms
//   dieselbe Fahrt kurz darauf -> 142 Abrufe, kein einziger Fehler
//
// OpenTopoMap rendert Kacheln bei Bedarf und meldet 404, solange eine
// noch nicht fertig ist. Ohne Nachhelfen wird daraus ein dauerhaftes
// Loch: Der Vorgabe-RetryClient von flutter_map wiederholt allein bei
// 503, und EvictErrorTileStrategy.none behaelt die gescheiterte Kachel
// bis zum Programmende.
//
// Am echten Server laesst sich das nicht pruefen - der 404 kam und ging.
// Deshalb steht hier ein eigener Kachelserver, der ihn auf Kommando
// liefert. Und deshalb steht es unter integration_test: Ohne
// Bildpipeline und ohne Netz gibt es nichts zu beobachten.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Ein 1x1-PNG. Der Inhalt ist gleichgueltig; gemessen wird, ob es
/// ankommt.
final _einPixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  final abrufe = <String, int>{};
  /// Wie oft jede Kachel abgewiesen wird, bevor sie geliefert wird.
  var abweisungen = 1;

  setUp(() async {
    abrufe.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(server.forEach((anfrage) async {
      final pfad = anfrage.uri.path;
      final n = (abrufe[pfad] ?? 0) + 1;
      abrufe[pfad] = n;
      if (n <= abweisungen) {
        anfrage.response.statusCode = HttpStatus.notFound;
      } else {
        anfrage.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('image', 'png')
          ..headers.set('cache-control', 'max-age=60')
          ..headers.set('age', '0')
          ..add(_einPixel);
      }
      await anfrage.response.close();
    }));
  });

  tearDown(() => server.close(force: true));

  /// Baut eine echte Karte gegen den eigenen Server. Die Kennung im Pfad
  /// haelt die Laeufe auseinander - sonst beantwortete der Kachelspeicher
  /// den zweiten Lauf aus dem ersten.
  Future<List<String>> karteLaufenLassen(WidgetTester tester) async {
    final kennung = DateTime.now().microsecondsSinceEpoch;
    final fehler = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 400,
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(51.8355, 10.7825),
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'http://127.0.0.1:${server.port}/$kennung/'
                    '{z}/{x}/{y}.png',
                tileProvider: kartenKachelAnbieter(),
                evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
                errorTileCallback: (kachel, e, _) =>
                    fehler.add('${kachel.coordinates}: $e'),
              ),
            ],
          ),
        ),
      ),
    ));

    // Echte Zeit vergehen lassen: Zwischen den Versuchen wartet der
    // Client, und `pump` allein laesst die Uhr der Welt nicht laufen.
    final ende = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(ende)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return fehler;
  }

  testWidgets('eine einmal abgewiesene Kachel kommt trotzdem an',
      (tester) async {
    abweisungen = 1;
    final fehler = await karteLaufenLassen(tester);

    print('Kacheln angefragt: ${abrufe.length}');
    print('Abrufe je Kachel:  ${abrufe.values.toSet().toList()..sort()}');
    print('Fehlkacheln:       ${fehler.length}');

    expect(abrufe, isNotEmpty, reason: 'sonst misst der Test nichts');
    expect(fehler, isEmpty,
        reason: 'genau das war der Fehler: ein 404 wurde zum Loch');
    // Jede Kachel muss oefter als einmal abgerufen worden sein - sonst
    // hat die Wiederholung gar nicht stattgefunden, und der Test bestuende
    // aus dem falschen Grund.
    expect(abrufe.values.every((n) => n >= 2), isTrue,
        reason: 'ohne zweiten Versuch waere nichts angekommen: $abrufe');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('nach den erlaubten Versuchen bleibt es beim Fehler',
      (tester) async {
    // Die Gegenprobe. Ohne sie belegte der Test oben nur, dass ueberhaupt
    // wiederholt wird - nicht, dass die Zahl der Versuche begrenzt ist.
    // Ein Client, der endlos nachfasst, waere gegenueber einem
    // gespendeten Kachelserver das schlechtere Verhalten.
    abweisungen = 99;
    final fehler = await karteLaufenLassen(tester);

    print('Abrufe je Kachel bei Dauerfehler: '
        '${abrufe.values.toSet().toList()..sort()}');
    expect(fehler, isNotEmpty, reason: 'der Fehlschlag muss sichtbar werden');
    expect(abrufe.values.every((n) => n <= kachelVersuche + 1), isTrue,
        reason: 'hoechstens ein Versuch plus $kachelVersuche '
            'Wiederholungen: $abrufe');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
