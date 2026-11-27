import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/hochskalieren_ablegen.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/state/library_state.dart';

/// Hochskalieren in einer verbundenen Kopie (#500) – gegen einen echten
/// Server-Prozess aus packages/server, wie `verbundener_betrieb_test.dart`:
/// Die Datei geht über tus hoch, mit der Kennung des Originals, die
/// Gesichtssuche ist ausgenommen, und der Stapel entsteht am Server.
void main() {
  late Directory ordner;
  late Process server;
  late Uri adresse;
  late String tokenAnders;
  late LibraryState bib;

  Future<String> anmelden(String geraet) async {
    final a = Anmeldung(adresse);
    final s = await a.anmelden('erika', 'ein langes passwort', geraet: geraet);
    a.schliesse();
    return (s as AnmeldungFertig).token;
  }

  Future<Map<String, Object?>> aufServer(String id) async {
    final v = Serververbindung(adresse, tokenAnders);
    try {
      return await v.hole('api/v1/aufnahmen/$id');
    } finally {
      v.schliesse();
    }
  }

  Future<void> bis(Future<bool> Function() bedingung, String was) async {
    for (var i = 0; i < 150; i++) {
      if (await bedingung()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('Nicht eingetreten: $was');
  }

  setUpAll(() async {
    ordner = Directory.systemTemp.createTempSync('pv_hochskaliert_verbunden_');
    final daten = p.join(ordner.path, 'server');
    final umgebung = {'PV_DATEN': daten, 'PV_PORT': '0', 'PV_TOTP': 'frei'};
    const serverOrdner = 'packages/server';
    final anlegen = await Process.start(
      'dart',
      [
        'run',
        'bin/photo_vault_server.dart',
        'konto',
        'anlegen',
        'erika',
        '--totp-spaeter',
      ],
      workingDirectory: serverOrdner,
      environment: umgebung,
    );
    anlegen.stdin.writeln('ein langes passwort');
    await anlegen.stdin.close();
    expect(await anlegen.exitCode, 0);

    server = await Process.start(
      'dart',
      ['run', 'bin/photo_vault_server.dart'],
      workingDirectory: serverOrdner,
      environment: umgebung,
    );
    final bereit = Completer<Uri>();
    server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((z) {
          final m = RegExp(r'auf (http://127\.0\.0\.1:\d+)').firstMatch(z);
          if (m != null && !bereit.isCompleted) {
            bereit.complete(Uri.parse('${m.group(1)}/'));
          }
        });
    server.stderr.drain<void>();
    adresse = await bereit.future.timeout(const Duration(seconds: 60));
    tokenAnders = await anmelden('Telefon');

    final bild = img.Image(width: 48, height: 32);
    img.fill(bild, color: img.ColorRgb8(30, 120, 220));
    final foto = File(p.join(ordner.path, 'eingang', 'strand.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(bild));
    final anders = Serververbindung(adresse, tokenAnders);
    await TusHochladen(
      anders,
    ).lade(foto, 'api/v1/hochladen', {'filename': 'strand.jpg'});
    anders.schliesse();

    final hier = Directory(p.join(ordner.path, 'hier'))..createSync();
    final token = await anmelden('Rechner');
    final v = Serververbindung(adresse, token);
    await Abgleich.holeAbzug(v, File(p.join(hier.path, 'library.sqlite')));
    v.schliesse();
    await Verbindungsdatei(
      server: adresse,
      konto: 'erika',
      geraet: 'Rechner',
      token: token,
    ).schreibe(hier);
    LibraryLocation.nutzeFuerTests(anker: hier);
    bib = LibraryState();
    await bib.initialize();
  });

  tearDownAll(() async {
    bib.dispose();
    LibraryLocation.zuruecksetzenFuerTests();
    server.kill(ProcessSignal.sigint);
    await server.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        server.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    ordner.deleteSync(recursive: true);
  });

  test(
    'das Ergebnis geht hoch und steht am Server im Stapel des Originals',
    () async {
      expect(bib.verbunden, isTrue);
      final original = (await bib.db.select(bib.db.assets).get()).single;
      final gross = img.Image(width: 96, height: 64);
      img.fill(gross, color: img.ColorRgb8(30, 120, 220));
      final jpeg = mitHochskalierangaben(img.encodeJpg(gross), original);
      final orte = <String>[];

      final id = await bib.restoreQueue.hochskaliertAblegen!(
        Hochskalierablage(
          originalId: original.id,
          jpeg: jpeg,
          faktor: 2,
          hochladeortMerken: orte.add,
        ),
      );

      expect(id, isNotNull);
      expect(orte, hasLength(1), reason: 'der Ort für ein Fortsetzen');
      final neu = (await bib.db.assetById(id!))!;
      expect(neu.originalFileName, 'strand (2×).jpg');
      expect(neu.faceScanExcluded, isTrue);
      await bis(() async {
        final a = await aufServer(id);
        final o = await aufServer(original.id);
        return a['stackId'] != null && a['stackId'] == o['stackId'];
      }, 'Stapel am Server');
      await bis(
        () async => (bib.abgleichszustand?.ausstehend ?? -1) == 0,
        'nichts mehr ausstehend',
      );
    },
  );
}
