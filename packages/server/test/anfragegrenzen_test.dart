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
  group('je Absender (#316)', () {
    Handler mitAbsender(Completer<void> halten, {int insgesamt = 128}) =>
        anfragegrenzen(
          gleichzeitig: 2,
          insgesamt: insgesamt,
          absender: (r) => r.headers['x-von'] ?? '',
        )((r) async {
          await halten.future;
          return Response.ok('');
        });
    Request von(String wer) => Request(
      'POST',
      Uri.parse('http://localhost/api/v1/x'),
      body: 'a',
      headers: {'x-von': wer},
    );

    test('einer an der Grenze hält den anderen nicht auf', () async {
      final halten = Completer<void>();
      final h = mitAbsender(halten);
      final laufend = [Future.value(h(von('a'))), Future.value(h(von('a')))];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await h(von('a'))).statusCode, 503);
      final andere = h(von('b'));
      halten.complete();
      expect((await andere).statusCode, 200);
      await Future.wait(laufend);
    });

    test('der Deckel gilt für alle zusammen', () async {
      final halten = Completer<void>();
      final h = mitAbsender(halten, insgesamt: 2);
      final laufend = [Future.value(h(von('a'))), Future.value(h(von('b')))];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await h(von('c'))).statusCode, 503);
      halten.complete();
      await Future.wait(laufend);
    });

    test('nach dem Ende ist der Platz wieder frei', () async {
      final halten = Completer<void>()..complete();
      final h = mitAbsender(halten);
      for (var i = 0; i < 5; i++) {
        expect((await h(von('a'))).statusCode, 200);
      }
    });
  });

  group('Frist je Fortschritt (#316)', () {
    Handler api2(Duration frist, Duration ganz) => anfragegrenzen(
      frist: frist,
      gesamtfrist: ganz,
      jsonBytes: 1024,
    )((r) async => Response.ok(await r.readAsString()));
    Stream<List<int>> troepfelt(int n, Duration abstand) async* {
      for (var i = 0; i < n; i++) {
        await Future<void>.delayed(abstand);
        yield [97];
      }
    }

    Request an(Stream<List<int>> s) =>
        Request('POST', Uri.parse('http://localhost/api/v1/x'), body: s);

    test('wer stetig liefert, darf länger brauchen als die Frist', () async {
      final r = await api2(
        const Duration(milliseconds: 60),
        const Duration(seconds: 5),
      )(an(troepfelt(6, const Duration(milliseconds: 25))));
      expect(r.statusCode, 200);
    });

    test('wer ewig tröpfelt, scheitert an der Gesamtfrist', () async {
      final r = await api2(
        const Duration(milliseconds: 80),
        const Duration(milliseconds: 150),
      )(an(troepfelt(40, const Duration(milliseconds: 25))));
      expect(r.statusCode, 408);
    });
  });

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
