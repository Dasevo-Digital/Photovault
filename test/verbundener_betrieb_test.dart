import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/rechenhilfe.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/auswertung/herkunft.dart';
import 'package:kern/auswertung/rechenhilfe.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/textstellen.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/state/hintergrundlauf.dart';
import 'package:photo_vault/state/library_state.dart';

/// Die App als verbundenes Gerät (Issue #86, Stufe 2) – gegen einen echten
/// Server-Prozess aus packages/server.
///
/// Kein Widget-Test: Hier wird über HTTP geredet und auf der Platte
/// gearbeitet, und das kommt in der angehaltenen Zeit eines Widget-Tests
/// nie zurück.
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

  File jpeg(String name, int farbe) {
    final bild = img.Image(width: 64, height: 48);
    img.fill(bild, color: img.ColorRgb8(farbe, 120, 255 - farbe));
    return File(p.join(ordner.path, 'eingang', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(bild));
  }

  Future<void> bis(Future<bool> Function() bedingung, String was) async {
    for (var i = 0; i < 150; i++) {
      if (await bedingung()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('Nicht eingetreten: $was');
  }

  setUpAll(() async {
    ordner = Directory.systemTemp.createTempSync('pv_verbunden_');
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

    // Ein Foto vom anderen Gerät, bevor dieses sich verbindet.
    final anders = Serververbindung(adresse, tokenAnders);
    await TusHochladen(anders).lade(
      jpeg('strand.jpg', 30),
      'api/v1/hochladen',
      {'filename': 'strand.jpg'},
    );
    anders.schliesse();

    // Dieses Gerät: Abzug, Verbindungsdatei, dann die App.
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

  Future<Map<String, Object?>> aufServer(String id) async {
    final v = Serververbindung(adresse, tokenAnders);
    try {
      return await v.hole('api/v1/aufnahmen/$id');
    } finally {
      v.schliesse();
    }
  }

  test(
    'die Kopie öffnet sich verbunden, mit dem Foto vom anderen Gerät',
    () async {
      expect(bib.verbunden, isTrue);
      expect(bib.abgleich, isNotNull);
      final alle = await bib.db.select(bib.db.assets).get();
      expect(alle.map((a) => a.originalFileName), contains('strand.jpg'));
    },
  );

  test('Miniaturen kommen vom Server', () async {
    final a = (await bib.db.select(bib.db.assets).get()).single;
    final datei = await bib.paths.bereit(a.thumbnailRelativePath!);
    expect(await datei.length(), greaterThan(0));
  });

  test('ein Befehl hier landet auf dem Server, einer von dort hier', () async {
    final a = (await bib.db.select(bib.db.assets).get()).single;
    await bib.db.fuehreAus(BewertungSetzen([a.id], 5));
    await bis(
      () async => (await aufServer(a.id))['rating'] == 5,
      'Bewertung auf dem Server',
    );

    final anders = Serververbindung(adresse, tokenAnders);
    await anders.schicke(
      'api/v1/befehle',
      BeschreibungSetzen([a.id], 'Abendlicht').alsJson(),
    );
    anders.schliesse();
    await bis(
      () async =>
          (await bib.db.assetsByIds([a.id])).single.description == 'Abendlicht',
      'Beschreibung hier',
    );
    await bis(
      () async => (bib.abgleichszustand?.ausstehend ?? -1) == 0,
      'nichts mehr ausstehend',
    );
  });

  test('Importieren heisst hochladen', () async {
    final fortschritt = await bib.importFiles([
      jpeg('hafen.jpg', 200).path,
    ]).toList();
    final id = fortschritt.last.assetId;
    expect(id, isNotNull);
    expect(
      (await bib.db.assetsByIds([id!])).single.originalFileName,
      'hafen.jpg',
    );
    expect((await aufServer(id))['originalFileName'], 'hafen.jpg');
  });

  test('was Dateien schreibt, geht verbunden nicht – mit Grund', () async {
    final a = (await bib.db.select(bib.db.assets).get()).first;
    await expectLater(
      bib.lockAsset(a),
      throwsA(predicate((e) => '$e'.contains('pv_nur_ueber_server'))),
    );
    expect(bib.pruefeStart('ocr'), Startabweisung.amServer);
    await expectLater(
      bib.db.setRating(a.id, 1),
      throwsA(predicate((e) => '$e'.contains('pv_nur_ueber_server'))),
      reason: 'das Sicherheitsnetz',
    );
  });

  test('Rechenhilfe: der Rechner rechnet, der Server trägt ein, die Kopie '
      'bekommt es', () async {
    final ablage = Directory(p.join(ordner.path, 'ablage'));
    final gerechnet = <({bool lokal, String datei, String pfad})>[];
    final hilfe = Rechenhilfe(
      bib.abgleich!.verbindung,
      bib.paths,
      arten: () => {Rechenart.texterkennung},
      teile: () => const {},
      rechne: (auftrag, datei) async {
        expect(await datei.length(), greaterThan(0));
        gerechnet.add((
          lokal: bib.paths.absolute(auftrag.datei).path == datei.path,
          datei: auftrag.datei,
          pfad: datei.path,
        ));
        return Rechenergebnis(
          textstellen: const [
            Textstelle(
              text: 'Rechenhilfe',
              links: 0.1,
              oben: 0.1,
              breite: 0.5,
              hoehe: 0.1,
            ),
          ],
          herkunft: {
            Ergebnisart.texterkennung.name: (
              modell: 'Probe',
              geraet: 'Rechner (Test)',
              beschleuniger: 'CPU',
            ),
          },
        );
      },
      ruhe: const Duration(milliseconds: 200),
      zwischenablage: ablage,
    )..starte();
    addTearDown(hilfe.schliesse);

    final ids = [
      for (final a in await bib.db.select(bib.db.assets).get()) a.id,
    ];
    await bis(
      () async => (await bib.db.assetsByIds(
        ids,
      )).every((a) => a.ocrText == 'Rechenhilfe'),
      'erkannter Text in der Kopie',
    );
    await bis(
      () async => (await bib.db.herkunftVon(
        ids.first,
      )).any((h) => h.geraet == 'Rechner (Test)'),
      'Herkunft in der Kopie',
    );
    expect(hilfe.standJetzt.geliefert, ids.length);
    expect(gerechnet, hasLength(ids.length));
    final geholt = gerechnet.where((g) => !g.lokal).toList();
    expect(geholt, isNotEmpty, reason: 'mindestens ein Original fehlte');
    for (final g in geholt) {
      expect(File(g.pfad).existsSync(), isFalse);
      expect(
        bib.paths.absolute(g.datei).existsSync(),
        isFalse,
        reason: 'die Kopie wächst nicht',
      );
    }
  });

  test('der Schalter steht in verbindung.json', () async {
    final wurzel = await LibraryLocation.currentRoot();
    await bib.setzeRechenhilfe(true);
    expect((await Verbindungsdatei.lies(wurzel))!.rechenhilfe, isTrue);
    expect(bib.rechenhilfestand.value, isNotNull);
    await bib.setzeRechenhilfe(false);
    expect((await Verbindungsdatei.lies(wurzel))!.rechenhilfe, isFalse);
    expect(bib.rechenhilfestand.value, isNull);
  });
}
