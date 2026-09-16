import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:photo_vault/services/kachelmitschnitt.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Ein Kachelserver auf der eigenen Maschine.
///
/// Kein Netz nach draussen: Die Frage ist, ob das Messgerät stimmt, und
/// die lässt sich nicht an einem Server beantworten, dessen Verhalten
/// niemand kennt.
class Pruefserver {
  Pruefserver(this._server, {required this.schliesst}) {
    _server.listen((anfrage) async {
      _verbindungen.add(anfrage.connectionInfo!.remotePort);
      abrufe++;
      anfrage.response
        ..statusCode = 200
        ..headers.contentType = ContentType('image', 'png');
      if (schliesst) anfrage.response.persistentConnection = false;
      anfrage.response.add(List.filled(120, 0));
      await anfrage.response.close();
    });
  }

  static Future<Pruefserver> starte({bool schliesst = false}) async =>
      Pruefserver(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        schliesst: schliesst,
      );

  final HttpServer _server;

  /// Ob der Server nach jeder Kachel zumacht.
  final bool schliesst;

  final _verbindungen = <int>{};
  int abrufe = 0;

  /// Verschiedene Gegenstellen-Ports – die Zahl der TCP-Verbindungen,
  /// gezählt von der anderen Seite. Das ist der Massstab, an dem sich
  /// der Mitschnitt messen lassen muss.
  int get verbindungen => _verbindungen.length;

  Uri kachel(int z, int x, int y) =>
      Uri.parse('http://${_server.address.host}:${_server.port}/$z/$x/$y.png');

  Future<void> schliesse() => _server.close(force: true);
}

/// Holt [anzahl] verschiedene Kacheln, eine nach der anderen.
Future<void> hole(HttpClient client, Pruefserver server, int anzahl) async {
  final http = MitschnittClient(IOClient(client), Kachelmitschnitt.instanz);
  for (var i = 0; i < anzahl; i++) {
    final antwort = await http.get(server.kachel(8, 134, i));
    expect(antwort.statusCode, 200);
    expect(antwort.bodyBytes, hasLength(120));
  }
  http.close();
}

void main() {
  setUp(Kachelmitschnitt.instanz.starte);
  tearDown(() {
    Kachelmitschnitt.instanz
      ..halteAn()
      ..leere();
  });

  test('der Zähler trifft genau die Zahl, die der Server sieht', () async {
    final server = await Pruefserver.starte();
    addTearDown(server.schliesse);

    await hole(kachelHttpClient(), server, 12);

    final bilanz = Kachelmitschnitt.instanz.bilanz;
    expect(server.abrufe, 12);
    expect(bilanz.abrufe, 12);
    // Zwölf Abrufe über eine offen gehaltene Verbindung. Genau darum
    // geht es: Abrufe und Verbindungen sind zwei verschiedene Zahlen.
    expect(server.verbindungen, 1);
    expect(bilanz.verbindungen, server.verbindungen);
    expect(bilanz.verbindungenJeAbruf, lessThan(0.2));
    expect(bilanz.abrufeJeAdresse, 1.0);
    expect(bilanz.ohneDauerverbindung, 0);
  });

  test('die Verbindungsfabrik ändert nichts – nachgemessen, nicht behauptet',
      () async {
    // Der Einwand gegen jedes eingebautes Messgerät: Es könnte das
    // verändern, was es messen soll. Also beide Wege am selben Server.
    final ohne = await Pruefserver.starte();
    addTearDown(ohne.schliesse);
    await hole(HttpClient()..maxConnectionsPerHost = kachelVerbindungen, ohne, 12);

    final mit = await Pruefserver.starte();
    addTearDown(mit.schliesse);
    await hole(kachelHttpClient(), mit, 12);

    expect(mit.abrufe, ohne.abrufe);
    expect(mit.verbindungen, ohne.verbindungen);
  });

  test('macht der Server nach jeder Kachel zu, kostet jede eine Verbindung',
      () async {
    // **Der Verdacht in Reinform.** Von aussen waren 5702 Verbindungen
    // für 496 Kacheln zu sehen. Wenn ein Server so antwortet, sieht der
    // Mitschnitt genau das – und sagt mit `ohneDauerverbindung` auch,
    // woran es liegt.
    final server = await Pruefserver.starte(schliesst: true);
    addTearDown(server.schliesse);

    await hole(kachelHttpClient(), server, 10);

    final bilanz = Kachelmitschnitt.instanz.bilanz;
    expect(bilanz.abrufe, 10);
    expect(server.verbindungen, 10);
    expect(bilanz.verbindungen, 10);
    expect(bilanz.verbindungenJeAbruf, 1.0);
    expect(bilanz.ohneDauerverbindung, 10);
  });

  test('gleichzeitige Abrufe sprengen die Deckelung nicht', () async {
    // [kachelVerbindungen] ist die Zusage, dass wir gespendeten Servern
    // nicht sechzig Handschläge auf einmal zumuten. Ohne Messung wäre es
    // eine Zusage auf dem Papier.
    final server = await Pruefserver.starte();
    addTearDown(server.schliesse);
    final http =
        MitschnittClient(IOClient(kachelHttpClient()), Kachelmitschnitt.instanz);
    addTearDown(http.close);

    await Future.wait([
      for (var i = 0; i < 40; i++) http.get(server.kachel(8, 200, i)),
    ]);

    expect(server.abrufe, 40);
    expect(server.verbindungen, lessThanOrEqualTo(kachelVerbindungen));
    expect(Kachelmitschnitt.instanz.bilanz.verbindungen, server.verbindungen);
  });

  test('ein Server, den es nicht gibt, steht als Fehler im Mitschnitt',
      () async {
    final server = await Pruefserver.starte();
    final adresse = server.kachel(8, 1, 1);
    await server.schliesse();

    final http =
        MitschnittClient(IOClient(kachelHttpClient()), Kachelmitschnitt.instanz);
    addTearDown(http.close);
    await expectLater(http.get(adresse), throwsA(isA<Object>()));

    final bilanz = Kachelmitschnitt.instanz.bilanz;
    expect(bilanz.abrufe, 1);
    expect(bilanz.fehlgeschlagen, 1);
    expect(bilanz.nachFehler, isNotEmpty);
  });
}
