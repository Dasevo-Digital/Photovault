import 'dart:io';

import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/abgleich_api.dart';
import 'package:photo_vault_server/src/anmeldung_api.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Der Abzug der ganzen Bibliothek (#436): Gleichzeitige Anfragen teilen
/// sich eine Kopie, statt dass jede ihre eigene anlegt.
void main() {
  late Directory ordner;
  late Directory ablage;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Abgleichsapi abgleich;
  late Handler api;
  late String token;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_abzug_test_');
    ablage = Directory('${ordner.path}/abzuege')..createSync();
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 4)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    abgleich = Abgleichsapi(
      bibliotheken,
      abzugsordner: ablage,
      ohneLeser: const Duration(milliseconds: 300),
    );
    api = const Pipeline()
        .addMiddleware(anmeldungNoetig(konten, Absender()))
        .addHandler(abgleich.abzug);
    final erika = await konten.legeAn('erika', 'ein langes passwort');
    token = konten.meldeAn(erika.id, 'Rechner', 'x').token;
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<Response> frag() async => api(
    Request(
      'GET',
      Uri.parse('http://server/api/v1/abgleich/abzug'),
      headers: {'authorization': 'Bearer $token'},
    ),
  );

  int kopien() => ablage.listSync().length;

  test('gleichzeitig auf demselben Stand: eine Kopie für alle', () async {
    final antworten = await Future.wait([for (var i = 0; i < 8; i++) frag()]);
    expect(antworten.map((r) => r.statusCode), everyElement(200));
    expect(kopien(), 1);
    final inhalte = await Future.wait([
      for (final r in antworten) r.read().expand((b) => b).toList(),
    ]);
    expect(inhalte.map((b) => b.length).toSet(), {
      int.parse(antworten.first.headers['content-length']!),
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(kopien(), 0);
  });

  test('mehr als zwei verschiedene zugleich: 503', () async {
    final b = (await bibliotheken.fuer(konten.alle().single.id)).bibliothek;
    final erste = await frag();
    // Eine Änderung später ist es ein anderer Stand.
    await b.db.customStatement(
      "INSERT INTO pv_aenderungen (tabelle, schluessel) VALUES ('x', '[1]')",
    );
    final zweite = await frag();
    await b.db.customStatement(
      "INSERT INTO pv_aenderungen (tabelle, schluessel) VALUES ('x', '[2]')",
    );
    final dritte = await frag();
    expect([erste.statusCode, zweite.statusCode], [200, 200]);
    expect(dritte.statusCode, 503);
    expect(kopien(), 2);
    await erste.read().drain<void>();
    await zweite.read().drain<void>();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(kopien(), 0);
    expect((await frag()).statusCode, 200);
  });

  test('eine Antwort, die niemand liest, gibt ihre Kopie frei', () async {
    final r = await frag();
    expect(r.statusCode, 200);
    expect(kopien(), 1);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(kopien(), 0);
  });
}
