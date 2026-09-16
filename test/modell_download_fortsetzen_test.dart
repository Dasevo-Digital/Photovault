import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/model_catalog.dart';
import 'package:photo_vault/services/model_download_service.dart';

/// Prüft, dass ein abgebrochener Download dort weitermacht, wo er aufhörte –
/// und dass die Prüfsumme die Garantie bleibt, wenn das Fortsetzen schiefgeht.
///
/// Der Server hier ist Absicht: Gegen echte Anbieter liesse sich ein Abbruch
/// nicht verlässlich auslösen, und ein Test, der auf das Netz wartet, sagt am
/// Ende nichts über den eigenen Code aus.
void main() {
  late Directory ordner;
  late HttpServer server;
  late Uint8List daten;
  late String pruefsumme;
  var anfragen = 0;
  var teilbereiche = 0;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('fortsetzen');
    // Etwas grösser als ein Puffer, damit der Abbruch mitten im Strom liegt.
    daten = Uint8List.fromList(
        List<int>.generate(400 * 1024, (i) => (i * 31 + 7) % 251));
    pruefsumme = sha256.convert(daten).toString();
    anfragen = 0;
    teilbereiche = 0;
  });

  tearDown(() async {
    await server.close(force: true);
    if (await ordner.exists()) await ordner.delete(recursive: true);
  });

  ModelCatalogEntry eintrag(String name) => ModelCatalogEntry(
        id: 'probe',
        sourceUrl: 'http://127.0.0.1',
        files: [
          ModelFile(name, 'http://127.0.0.1:${server.port}/$name', pruefsumme,
              daten.length),
        ],
      );

  /// Bedient Bereichsanfragen; die erste Anfrage bricht nach der Hälfte ab.
  Future<void> starteServer({required bool kannBereiche}) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((anfrage) async {
      anfragen++;
      final bereich = anfrage.headers.value('range');
      if (bereich != null && kannBereiche) {
        teilbereiche++;
        final ab = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(bereich)!.group(1)!);
        anfrage.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set('content-range', 'bytes $ab-${daten.length - 1}/${daten.length}')
          ..headers.contentLength = daten.length - ab
          ..add(daten.sublist(ab));
        await anfrage.response.close();
        return;
      }
      if (anfragen == 1) {
        // Vorzeitiges Ende: Länge angekündigt, nur die Hälfte geliefert,
        // dann die Leitung gekappt. Das geht nur an der HttpResponse vorbei –
        // sie lässt sich nach dem ersten Schreiben nicht mehr abtrennen
        // („Headers already sent"), und ein sauberes close() wäre kein
        // Abbruch, sondern ein vollständiges kurzes Ergebnis.
        final leitung = await anfrage.response.detachSocket(writeHeaders: false);
        leitung.add(utf8.encode('HTTP/1.1 200 OK\r\n'
            'content-length: ${daten.length}\r\n'
            'accept-ranges: bytes\r\n'
            '\r\n'));
        leitung.add(daten.sublist(0, daten.length ~/ 2));
        await leitung.flush();
        leitung.destroy();
        return;
      }
      anfrage.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = daten.length
        ..add(daten);
      await anfrage.response.close();
    });
  }

  test('ein Abbruch setzt fort statt neu zu laden', () async {
    await starteServer(kannBereiche: true);
    final dienst = ModelDownloadService(ordner.path,
        verbindungsGrenze: const Duration(seconds: 5),
        datenGrenze: const Duration(seconds: 3));

    await dienst.download(eintrag('modell.bin')).drain<void>();

    final datei = File('${ordner.path}/modell.bin');
    expect(await datei.exists(), isTrue, reason: 'Datei fehlt nach dem Lauf');
    expect(sha256.convert(await datei.readAsBytes()).toString(), pruefsumme);
    expect(teilbereiche, greaterThan(0),
        reason: 'Es wurde keine Bereichsanfrage gestellt – also neu geladen '
            'statt fortgesetzt.');
    expect(File('${ordner.path}/modell.bin.part').existsSync(), isFalse);
  });

  test('lehnt der Server Bereiche ab, wird von vorn geladen', () async {
    await starteServer(kannBereiche: false);
    final dienst = ModelDownloadService(ordner.path,
        verbindungsGrenze: const Duration(seconds: 5),
        datenGrenze: const Duration(seconds: 3));

    await dienst.download(eintrag('modell.bin')).drain<void>();

    final datei = File('${ordner.path}/modell.bin');
    expect(await datei.exists(), isTrue);
    // Die eigentliche Zusage: Nichts wird an den Rumpf angehängt, die
    // Prüfsumme stimmt am Ende trotzdem.
    expect(sha256.convert(await datei.readAsBytes()).toString(), pruefsumme);
    expect(File('${ordner.path}/modell.bin.part').existsSync(), isFalse);
  });

  test('bleibt die Prüfsumme falsch, wird gemeldet und nichts abgelegt', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final falsch = utf8.encode('nicht das erwartete Modell');
    server.listen((anfrage) async {
      anfragen++;
      anfrage.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = falsch.length
        ..add(falsch);
      await anfrage.response.close();
    });

    final dienst = ModelDownloadService(ordner.path,
        verbindungsGrenze: const Duration(seconds: 5),
        datenGrenze: const Duration(seconds: 3));
    Object? fehler;
    try {
      await dienst.download(eintrag('modell.bin')).drain<void>();
    } catch (e) {
      fehler = e;
    }

    expect(fehler, isA<ModellDownloadFehler>());
    expect((fehler as ModellDownloadFehler).erwartet, pruefsumme);
    expect(File('${ordner.path}/modell.bin').existsSync(), isFalse,
        reason: 'Eine Datei mit falscher Prüfsumme darf nicht liegen bleiben.');
    expect(File('${ordner.path}/modell.bin.part').existsSync(), isFalse);
  });
}
