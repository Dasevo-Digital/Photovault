import 'dart:async';
import 'dart:convert';
import 'package:photo_vault_server/src/anfragegrenzen.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  Request anfrage(
    Object body, {
    String pfad = 'api/v1/anmelden',
    String method = 'POST',
    Map<String, String>? headers,
  }) => Request(
    method,
    Uri.parse('http://localhost/$pfad'),
    body: body,
    headers: headers,
  );
  Handler api({
    int parallel = 16,
    Duration frist = const Duration(seconds: 1),
  }) => anfragegrenzen(
    gleichzeitig: parallel,
    frist: frist,
    jsonBytes: 64,
    anmeldungBytes: 16,
  )((r) async => Response.ok(await r.readAsString()));
  test(
    'deklarierte Übergröße wird vor dem ersten Lesezugriff abgewiesen',
    () async {
      var gelesen = false;
      Stream<List<int>> quelle() async* {
        gelesen = true;
        yield [1];
      }

      final r = await api()(
        anfrage(quelle(), headers: {'content-length': '1000'}),
      );
      expect(r.statusCode, 413);
      expect(gelesen, isFalse);
    },
  );
  test(
    'chunked und falscher Content-Type umgehen das Bytebudget nicht',
    () async {
      var teile = 0;
      Stream<List<int>> quelle() async* {
        for (var i = 0; i < 100; i++) {
          teile++;
          yield List.filled(8, 32);
          await Future<void>.delayed(Duration.zero);
        }
      }

      final r = await api()(
        anfrage(quelle(), headers: {'content-type': 'text/plain'}),
      );
      expect(r.statusCode, 413);
      expect(teile, lessThan(5));
      expect(r.headers['connection'], 'close');
    },
  );
  test('Gesamtfrist beendet auch einen nie abgeschlossenen Körper', () async {
    final controller = StreamController<List<int>>();
    final r = await api(frist: const Duration(milliseconds: 30))(
      anfrage(controller.stream),
    );
    expect(r.statusCode, 408);
    await controller.close();
  });
  test(
    'gleichzeitige Körper werden begrenzt und Slots nach Abbruch freigegeben',
    () async {
      final controller = StreamController<List<int>>();
      final handler = api(parallel: 1, frist: const Duration(milliseconds: 50));
      final erste = handler(anfrage(controller.stream));
      expect((await handler(anfrage('{}'))).statusCode, 503);
      expect((await erste).statusCode, 408);
      await controller.close();
      expect((await handler(anfrage('{}'))).statusCode, 200);
    },
  );
  test(
    'kleines Anmelde-JSON und größeres Befehls-JSON behalten ihren Inhalt',
    () async {
      expect(await (await api()(anfrage('{}'))).readAsString(), '{}');
      final daten = jsonEncode({
        'befehle': ['x' * 24],
      });
      final r = await api()(anfrage(daten, pfad: 'api/v1/befehle'));
      expect(r.statusCode, 200);
      expect(await r.readAsString(), daten);
    },
  );
  test('nur definierte binäre Routen bleiben gestreamt', () async {
    for (final (method, pfad) in [
      ('PATCH', 'api/v1/hochladen/id'),
      ('PATCH', 'api/v1/umzug/hochladen/id'),
      ('PUT', 'api/v1/dateien/originals/foto.jpg'),
      ('POST', 'api/v1/teilen/link/beitrag'),
    ]) {
      final r = await api()(anfrage('x' * 100, pfad: pfad, method: method));
      expect(r.statusCode, 200);
    }
    expect(
      (await api()(anfrage('x' * 100, pfad: 'api/v1/hochladen'))).statusCode,
      413,
    );
  });
}
