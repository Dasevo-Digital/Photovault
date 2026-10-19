import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/speicher.dart';
import 'package:kern/abgleich/spuren_nachreichen.dart';
import 'package:kern/abgleich/dateibeschaffung.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// Server und verbundene Geräte über echtes HTTP (Stufe 2).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Handler api;
  late HttpServer server;
  late int port;
  late Konto erika;
  final geraete = <(AppDatabase, Abgleich)>[];

  Future<void> starteServer() async {
    server = await shelf_io.serve(api, '127.0.0.1', port);
  }

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_abgleich_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 1)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    api = baueApi(konten: konten, bibliotheken: bibliotheken);
    port = 0;
    await starteServer();
    port = server.port;
    erika = await konten.legeAn('erika', 'ein langes passwort');
  });

  tearDown(() async {
    for (final (db, a) in geraete) {
      await a.beende();
      a.verbindung.schliesse();
      await db.close();
    }
    geraete.clear();
    await server.close(force: true);
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<AppDatabase> serverDb() async =>
      (await bibliotheken.fuer(erika.id)).bibliothek.db;

  Future<void> aufnahme(AppDatabase db, String id) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2025),
          importedAt: DateTime(2026),
        ),
      );

  /// Ein Gerät: angemeldet, mit Abzug, eingerichtet – aber ohne Schleife;
  /// die Schritte ruft der Prüfstand selbst.
  Future<(AppDatabase, Abgleich)> geraet(String name) async {
    final token = konten.meldeAn(erika.id, name, 'x').token;
    final v = Serververbindung(Uri.parse('http://127.0.0.1:$port/'), token);
    final datei = File('${ordner.path}/$name/library.sqlite');
    await Abgleich.holeAbzug(v, datei);
    final db = AppDatabase(NativeDatabase(datei));
    final a = Abgleich(db, v);
    await a.richteEin();
    geraete.add((db, a));
    return (db, a);
  }

  Future<AssetData> holeAufnahme(AppDatabase db, String id) async =>
      (await db.assetsByIds([id])).single;

  Future<int> ausstehend(AppDatabase db) async =>
      (await db
              .customSelect('SELECT count(*) AS n FROM pv_ausgang')
              .getSingle())
          .read<int>('n');

  test('Abzug, danach die Änderungen des Servers', () async {
    final s = await serverDb();
    await aufnahme(s, 'a1');
    final (db, a) = await geraet('Rechner');
    expect((await holeAufnahme(db, 'a1')).rating, 0);

    await s.fuehreAus(const BewertungSetzen(['a1'], 3));
    await aufnahme(s, 'a2');
    await a.empfange();
    expect((await holeAufnahme(db, 'a1')).rating, 3);
    expect((await holeAufnahme(db, 'a2')).relativePath, 'originals/a2.jpg');
  });

  test('ein Befehl wirkt sofort hier, dann auf dem Server und beim anderen '
      'Gerät', () async {
    await aufnahme(await serverDb(), 'a1');
    final (dbA, a) = await geraet('Rechner');
    final (dbB, b) = await geraet('Telefon');

    await dbA.fuehreAus(const BewertungSetzen(['a1'], 5));
    expect((await holeAufnahme(dbA, 'a1')).rating, 5, reason: 'vorweggenommen');
    expect(await ausstehend(dbA), 1);

    await a.sende();
    expect((await holeAufnahme(await serverDb(), 'a1')).rating, 5);
    await b.empfange();
    expect((await holeAufnahme(dbB, 'a1')).rating, 5);
    await a.empfange();
    expect(await ausstehend(dbA), 0, reason: 'bestätigt und angeglichen');
    expect(
      (await dbA
              .customSelect('SELECT count(*) AS n FROM pv_aenderungen')
              .getSingle())
          .read<int>('n'),
      0,
    );
  });

  test('offline: Befehle warten und gehen nach, Schlagwörter mit derselben '
      'Kennung', () async {
    await aufnahme(await serverDb(), 'a1');
    final (db, a) = await geraet('Rechner');
    await server.close(force: true);

    await db.fuehreAus(const FavoritSetzen(['a1'], true));
    await db.fuehreAus(const SchlagwortAnheften(['a1'], 'Leuchtturm'));
    await expectLater(a.sende(), throwsA(isA<KeineVerbindung>()));
    expect((await holeAufnahme(db, 'a1')).isFavorite, isTrue);
    expect(await ausstehend(db), 2);

    await starteServer();
    await a.sende();
    await a.empfange();
    final s = await serverDb();
    expect((await holeAufnahme(s, 'a1')).isFavorite, isTrue);
    final tagsServer = await s.tagsForAsset('a1');
    final tagsHier = await db.tagsForAsset('a1');
    expect(tagsServer.single.id, tagsHier.single.id);
    expect(await ausstehend(db), 0);
  });

  test('was der Server ablehnt, nimmt das Angleichen zurück', () async {
    final (dbA, a) = await geraet('Rechner');
    final (dbB, b) = await geraet('Telefon');
    // Beide legen ein Album mit derselben Kennung an; der Server nimmt nur
    // das erste.
    await dbB.fuehreAus(AlbumAnlegen('al1', 'Sommer', DateTime(2026, 7, 1)));
    await b.sende();
    await dbA.fuehreAus(AlbumAnlegen('al1', 'Winter', DateTime(2026, 1, 1)));
    expect((await dbA.select(dbA.albums).getSingle()).name, 'Winter');

    await a.sende();
    expect(a.zustandJetzt.abgelehnt, isNotEmpty);
    await a.empfange();
    expect((await dbA.select(dbA.albums).getSingle()).name, 'Sommer');
    expect(await ausstehend(dbA), 0);
  });

  test('eine Zeile, die der Server anders nummeriert, gibt es danach nur '
      'einmal', () async {
    final s = await serverDb();
    await s.fuehreAus(const PersonAnlegen('p1', 'Anna'));
    final (db, a) = await geraet('Rechner');
    // Rückmeldungen zur Gesichtserkennung zählen ihre Nummer selbst hoch –
    // hier wie dort anders, sobald der Server schon welche hat.
    await s.fuehreAus(
      const GesichtsEntscheidungenMerken('p1', [
        (faceId: 'g0', accepted: true, similarity: 0.7),
      ], allgemeineSchwelle: 0.4),
    );
    await db.fuehreAus(
      const GesichtsEntscheidungenMerken('p1', [
        (faceId: 'g1', accepted: false, similarity: 0.3),
      ], allgemeineSchwelle: 0.4),
    );
    await a.sende();
    await a.empfange();
    Future<List<String>> rueckmeldungen(AppDatabase d) async => [
      for (final z in await d.select(d.faceMatchFeedback).get())
        '${z.id} ${z.faceId}',
    ]..sort();
    expect(await rueckmeldungen(db), await rueckmeldungen(s));
    expect(await rueckmeldungen(db), hasLength(2));
  });

  test(
    'eine fremde Änderung überschreibt die eigene Vorwegnahme nicht',
    () async {
      final s = await serverDb();
      await aufnahme(s, 'a1');
      final (db, a) = await geraet('Rechner');
      await db.fuehreAus(const BewertungSetzen(['a1'], 5));
      // Bevor die eigene Bewertung hinausgeht, ändert jemand anders die
      // Beschreibung derselben Aufnahme.
      await s.fuehreAus(const BeschreibungSetzen(['a1'], 'Hafen'));
      await a.empfange();
      var hier = await holeAufnahme(db, 'a1');
      expect([hier.rating, hier.description], [5, 'Hafen']);

      await a.sende();
      await a.empfange();
      hier = await holeAufnahme(db, 'a1');
      final dort = await holeAufnahme(s, 'a1');
      expect([dort.rating, dort.description], [5, 'Hafen']);
      expect([hier.rating, hier.description], [5, 'Hafen']);
      expect(await ausstehend(db), 0);
    },
  );

  test('Spuren, die nur in der Kopie liegen, reicht der Rechner nach – '
      'einmal', () async {
    final s = await serverDb();
    final p = [
      (
        breite: 51.80,
        laenge: 10.60,
        hoehe: 300.0,
        zeit: DateTime.utc(2026, 8, 1, 9),
      ),
      (
        breite: 51.81,
        laenge: 10.62,
        hoehe: 410.0,
        zeit: DateTime.utc(2026, 8, 1, 10),
      ),
    ];
    SpurAnlegen spur(String id) => SpurAnlegen(
      id: id,
      name: '$id.gpx',
      quelle: '$id.gpx',
      laengeKm: 2.4,
      aufstieg: 110,
      abstieg: 0,
      angelegtAm: DateTime.utc(2026, 8, 2),
      punkte: p,
    );
    await s.fuehreAus(spur('dort'));

    // Ein Rechner, der die Spur angelegt hat, während sein Abgleich nicht
    // lief: Sie liegt nur bei ihm.
    final token = konten.meldeAn(erika.id, 'Rechner', 'x').token;
    final v = Serververbindung(Uri.parse('http://127.0.0.1:$port/'), token);
    final datei = File('${ordner.path}/Rechner/library.sqlite');
    await Abgleich.holeAbzug(v, datei);
    final db = AppDatabase(NativeDatabase(datei));
    await db.fuehreAus(spur('hier'));
    final a = Abgleich(db, v);
    await a.richteEin();
    geraete.add((db, a));

    expect(await spurenNachreichen(db, v), 1, reason: '„dort“ kennt er');
    await a.sende();
    final aufDemServer = {for (final x in await s.alleSpuren()) x.id: x};
    expect(aufDemServer.keys, unorderedEquals(['dort', 'hier']));
    expect(aufDemServer['hier']!.punktzahl, 2);
    expect((await s.punkteDerSpur('hier')).map((x) => x.hoehe), [300, 410]);

    await a.empfange();
    expect(await spurenNachreichen(db, v), 0);
    expect(await ausstehend(db), 0);
    expect((await db.punkteDerSpur('hier')).length, 2, reason: 'unverändert');
  });

  test('an der Kopie vorbei lässt sich nichts schreiben', () async {
    await aufnahme(await serverDb(), 'a1');
    final (db, a) = await geraet('Rechner');
    await expectLater(
      db.setRating('a1', 2),
      throwsA(predicate((e) => '$e'.contains('pv_nur_ueber_server'))),
      reason: 'direkt, ohne Befehl',
    );
    await expectLater(
      db.deleteAssetRows(['a1']),
      throwsA(predicate((e) => '$e'.contains('pv_nur_ueber_server'))),
    );
    // Was nur diesem Rechner gehört, bleibt frei.
    await db.setThemeMode('dark');
    await db.merkeAufgabenlauf('ordnen');
    // Und über einen Befehl geht es.
    await db.fuehreAus(const BewertungSetzen(['a1'], 2));
    expect((await holeAufnahme(db, 'a1')).rating, 2);
    await a.sende();
    await a.empfange();
    expect((await holeAufnahme(db, 'a1')).rating, 2);
  });

  test(
    'Long-Poll: eine Änderung kommt an, ohne dass das Gerät fragt',
    () async {
      final s = await serverDb();
      await aufnahme(s, 'a1');
      final (db, a) = await geraet('Rechner');
      final uhr = Stopwatch()..start();
      final warten = a.empfange(warten: const Duration(seconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await s.fuehreAus(const BewertungSetzen(['a1'], 2));
      await warten;
      expect(uhr.elapsed, lessThan(const Duration(seconds: 5)));
      expect((await holeAufnahme(db, 'a1')).rating, 2);
    },
  );

  test('derselbe Befehl zweimal geschickt wirkt einmal', () async {
    final s = await serverDb();
    await s.fuehreAus(const PersonAnlegen('p1', 'Anna'));
    final token = konten.meldeAn(erika.id, 'x', 'x').token;
    final v = Serververbindung(Uri.parse('http://127.0.0.1:$port/'), token);
    final befehl = {
      'kennung': 'k1',
      ...const GesichtsEntscheidungenMerken('p1', [
        (faceId: 'g1', accepted: true, similarity: 0.6),
      ], allgemeineSchwelle: 0.4).alsJson(),
    };
    await v.schicke('api/v1/befehle', {
      'befehle': [befehl],
    });
    final zweit = await v.schicke('api/v1/befehle', {
      'befehle': [befehl],
    });
    expect((zweit['ergebnisse']! as List).single['schon'], isTrue);
    expect(await s.select(s.faceMatchFeedback).get(), hasLength(1));
    v.schliesse();
  });

  test('Dateien nach Pfad – nur aus der Bibliothek', () async {
    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    final f = b.pfade.absolute('thumbnails/x.jpg');
    await f.parent.create(recursive: true);
    await f.writeAsBytes([1, 2, 3]);
    final (_, a) = await geraet('Rechner');
    final ziel = File('${ordner.path}/cache/thumbnails/x.jpg');
    await a.verbindung.ladeHerunter('api/v1/dateien/thumbnails/x.jpg', ziel);
    expect(await ziel.readAsBytes(), [1, 2, 3]);
    await expectLater(
      a.verbindung.ladeHerunter(
        'api/v1/dateien/..%2F..%2F..%2Fkonten',
        File('${ordner.path}/cache/x'),
      ),
      throwsA(isA<Serverfehler>()),
    );
  });

  test(
    'im Hintergrund: abgleichen von selbst, abgemeldet heisst aufhören',
    () async {
      final s = await serverDb();
      await aufnahme(s, 'a1');
      final (db, a) = await geraet('Rechner');
      a.starte();
      await db.fuehreAus(const FarbmarkeSetzen(['a1'], 'rot'));
      Future<void> bis(Future<bool> Function() bedingung) async {
        for (var i = 0; i < 100 && !await bedingung(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      await bis(() async => (await holeAufnahme(s, 'a1')).colorLabel == 'rot');
      expect((await holeAufnahme(s, 'a1')).colorLabel, 'rot');
      await s.fuehreAus(const BewertungSetzen(['a1'], 4));
      await bis(() async => (await holeAufnahme(db, 'a1')).rating == 4);
      expect((await holeAufnahme(db, 'a1')).rating, 4);

      final zustaende = <Abgleichszustand>[];
      final abo = a.zustand.listen(zustaende.add);
      konten.alleAbmelden(erika.id);
      await s.fuehreAus(const BewertungSetzen(['a1'], 1));
      await bis(() async => zustaende.any((z) => z.abgemeldet));
      expect(zustaende.any((z) => z.abgemeldet), isTrue);
      await abo.cancel();
    },
  );

  test(
    'beenden bricht die wartende Abfrage ab, ohne Störung zu melden',
    () async {
      final (_, a) = await geraet('Rechner');
      final zustaende = <Abgleichszustand>[];
      final abo = a.zustand.listen(zustaende.add);
      a.starte();
      // Die Schleife hängt jetzt in der Abfrage, die bis zu 25 s wartet.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final uhr = Stopwatch()..start();
      await a.beende();
      expect(uhr.elapsed, lessThan(const Duration(seconds: 3)));
      expect(zustaende.where((z) => !z.erreichbar), isEmpty);
      await abo.cancel();
    },
  );

  test(
    'Hochladen setzt nach einem Neustart fort, wo der Server steht',
    () async {
      final token = konten.meldeAn(erika.id, 'Telefon', 'x').token;
      final v = Serververbindung(Uri.parse('http://127.0.0.1:$port/'), token);
      addTearDown(v.schliesse);
      final bild = img.Image(width: 300, height: 200);
      img.fill(bild, color: img.ColorRgb8(10, 120, 200));
      final datei = File('${ordner.path}/see.jpg')
        ..writeAsBytesSync(img.encodeJpg(bild));
      final laenge = datei.lengthSync();
      expect(laenge, greaterThan(400));
      const meta = {'filename': 'see.jpg'};

      // Erster Lauf: ein Stück, dann ist die Zeit um.
      String? ort;
      var stuecke = 0;
      await expectLater(
        TusHochladen(v, stueck: 200).lade(
          datei,
          'api/v1/hochladen',
          meta,
          angelegt: (o) => ort = o,
          abbrechen: () => stuecke++ >= 1,
        ),
        throwsA(isA<Abgebrochen>()),
      );
      expect(ort, isNotNull);

      // Neuer Lauf, neue Instanz: geht bei 200 weiter, nicht bei 0.
      final stellen = <int>[];
      final kopf = await TusHochladen(v, stueck: 200).lade(
        datei,
        'api/v1/hochladen',
        meta,
        fortsetzen: ort,
        angelegt: (_) => fail('kein neuer Upload'),
        fortschritt: (erledigt, _) => stellen.add(erledigt),
      );
      expect(stellen.first, 400);
      expect(kopf['pv-ausgang'], 'imported');

      // Schon fertig (die Antwort ging verloren): das Ergebnis aus dem Stand.
      final nochmal = await TusHochladen(v).lade(
        datei,
        'api/v1/hochladen',
        meta,
        fortsetzen: ort,
        angelegt: (_) => fail('kein neuer Upload'),
      );
      expect(nochmal['pv-ausgang'], 'imported');
      expect(nochmal['pv-aufnahme'], kopf['pv-aufnahme']);

      // Kennt der Server den Ort nicht mehr, beginnt ein neuer Upload.
      String? neu;
      final dublette = await TusHochladen(v).lade(
        datei,
        'api/v1/hochladen',
        meta,
        fortsetzen: '${ort!.substring(0, ort!.length - 4)}0000',
        angelegt: (o) => neu = o,
      );
      expect(neu, isNot(ort));
      expect(dublette['pv-ausgang'], 'duplicateSkipped');
    },
  );

  test(
    'erreichbar meldet sich gleich, nicht erst nach der langen Abfrage',
    () async {
      final (_, a) = await geraet('Rechner');
      final erster = a.zustand.firstWhere((z) => z.erreichbar);
      final uhr = Stopwatch()..start();
      a.starte();
      await erster.timeout(const Duration(seconds: 10));
      expect(uhr.elapsed, lessThan(const Duration(seconds: 3)));
    },
  );

  test(
    'ein anderes Schema beim Server: kein Abgleich, sondern ein Hinweis',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final anfragen = <String>[];
      final v = Serververbindung(
        Uri.parse('http://server.test/'),
        'pv1_test',
        client: MockClient((r) async {
          anfragen.add(r.url.path);
          return http.Response(
            jsonEncode({'stand': 0, 'schema': db.schemaVersion + 1}),
            200,
          );
        }),
      );
      final a = Abgleich(db, v);
      await a.richteEin();
      final zustand = a.zustand.first;
      a.starte();
      final z = await zustand.timeout(const Duration(seconds: 5));
      expect(z.serverSchema, db.schemaVersion + 1);
      await a.beende();
      expect(anfragen, ['/api/v1/abgleich/stand'], reason: 'sonst nichts');
    },
  );

  test('Dateien bei Bedarf und Miniaturen im Vorrat', () async {
    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    for (final id in ['a1', 'a2']) {
      await b.db
          .into(b.db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/2025/$id.jpg',
              thumbnailRelativePath: Value('thumbnails/$id.jpg'),
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2025),
              importedAt: DateTime(2026),
            ),
          );
      for (final rel in ['originals/2025/$id.jpg', 'thumbnails/$id.jpg']) {
        final f = b.pfade.absolute(rel);
        await f.parent.create(recursive: true);
        await f.writeAsString(rel);
      }
    }
    final (db, a) = await geraet('Rechner');
    final paths = await StoragePaths.oeffne(
      Directory('${ordner.path}/Rechner/library'),
    );
    final beschaffung = Dateibeschaffung(paths, a.verbindung)..binde();
    expect(await Vorrat(db, beschaffung).fuelle(), 2);
    expect(
      await paths.absolute('thumbnails/a2.jpg').readAsString(),
      'thumbnails/a2.jpg',
    );
    expect(await paths.absolute('originals/2025/a1.jpg').exists(), isFalse);
    final original = await paths.bereit('originals/2025/a1.jpg');
    expect(await original.readAsString(), 'originals/2025/a1.jpg');
    expect(await Vorrat(db, beschaffung).fuelle(), 0, reason: 'schon da');
  });

  test('Anmeldung als Client: TOTP einrichten, Code, abgewiesen', () async {
    final pflicht = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 1)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
    );
    await server.close(force: true);
    api = baueApi(konten: pflicht, bibliotheken: bibliotheken);
    await starteServer();
    await pflicht.legeAn('max', 'noch ein passwort');
    final anmeldung = Anmeldung(Uri.parse('http://127.0.0.1:$port'));
    expect((await anmeldung.zustand())['protokoll'], 2);
    expect(
      await anmeldung.anmelden('max', 'falsch falsch falsch', geraet: 'x'),
      isA<AnmeldungAbgewiesen>(),
    );
    final s = await anmeldung.anmelden(
      'max',
      'noch ein passwort',
      geraet: 'Rechner',
    );
    final einrichten = s as AnmeldungTotpEinrichten;
    final geheimnis = base32Zurueck(einrichten.geheimnis);
    final fertig = await anmeldung.bestaetige(
      einrichten.vorgang,
      Totp.code(geheimnis, Totp.schritt(DateTime.now())),
    );
    final f = fertig as AnmeldungFertig;
    expect(f.wiederherstellungscodes, hasLength(10));
    expect(pflicht.pruefeToken(f.token, 'x')!.konto.name, 'max');
    anmeldung.schliesse();
  });

  test('Ersteinrichtung und Konten als Client', () async {
    final leer = Serverdatenbank.imSpeicher();
    addTearDown(leer.schliesse);
    final dienst = Kontodienst(
      leer,
      Tresorschluessel(List.filled(32, 1)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    await server.close(force: true);
    api = baueApi(konten: dienst, bibliotheken: bibliotheken);
    await starteServer();
    final adresse = Uri.parse('http://127.0.0.1:$port');
    final anmeldung = Anmeldung(adresse);
    addTearDown(anmeldung.schliesse);

    // Vom eigenen Rechner: das zählt als Heimnetz.
    expect((await anmeldung.zustand())['einrichten'], isTrue);
    final anna =
        await anmeldung.einrichten(
              'anna',
              'ein langes passwort',
              geraet: 'Rechner',
            )
            as AnmeldungFertig;
    expect((await anmeldung.zustand())['einrichten'], isNull);
    await expectLater(
      anmeldung.einrichten('max', 'noch ein passwort', geraet: 'x'),
      throwsA(isA<Serverfehler>().having((f) => f.status, 'status', 409)),
    );

    final v = Serververbindung(adresse, anna.token);
    addTearDown(v.schliesse);
    final verwaltung = Kontenverwaltung(v);
    expect(await verwaltung.binVerwalter(), isTrue);
    final max = await verwaltung.legeAn('max', 'noch ein passwort');
    expect(
      [for (final k in await verwaltung.liste()) (k.name, k.du)],
      [('anna', true), ('max', false)],
    );

    // Wer nicht Verwalter ist, sieht die Konten nicht.
    final alsMax =
        await anmeldung.anmelden('max', 'noch ein passwort', geraet: 'Tel')
            as AnmeldungFertig;
    final vm = Serververbindung(adresse, alsMax.token);
    addTearDown(vm.schliesse);
    expect(await Kontenverwaltung(vm).binVerwalter(), isFalse);
    await expectLater(
      Kontenverwaltung(vm).liste(),
      throwsA(isA<Serverfehler>().having((f) => f.status, 'status', 403)),
    );

    await verwaltung.setzePasswort(max.id, 'ein ganz neues passwort');
    await expectLater(
      vm.hole('api/v1/konto'),
      throwsA(isA<Serverfehler>().having((f) => f.abgemeldet, 'ab', true)),
    );
    await verwaltung.entferne(max.id);
    expect([for (final k in await verwaltung.liste()) k.name], ['anna']);
  });

  test('der Speicher des Servers, wie das Gerät ihn sieht', () async {
    final v = Serververbindung(
      Uri.parse('http://127.0.0.1:$port'),
      konten.meldeAn(erika.id, 'Rechner', 'x').token,
    );
    addTearDown(v.schliesse);
    // Ohne Wächter: unbekannt, aber kein Fehler.
    expect((await Serverspeicher.hole(v))!.stufe, 'unbekannt');

    await server.close(force: true);
    const gb = 1000 * 1000 * 1000;
    final w = Speicherwaechter(
      ordner,
      messung: (_) async => const Speicherstand(gesamt: 200 * gb, frei: 9 * gb),
    );
    await w.pruefe();
    api = baueApi(konten: konten, bibliotheken: bibliotheken, speicher: w);
    await starteServer();
    final s = (await Serverspeicher.hole(v))!;
    expect(
      (s.stufe, s.knapp, s.gesamt, s.frei),
      ('knapp', true, 200 * gb, 9 * gb),
    );
    expect(Serverspeicher.anders(s, s), isFalse);
    expect(
      Serverspeicher.anders(s, const Serverspeicher(stufe: 'voll')),
      isTrue,
    );
  });
}

/// Base32 zurück in Bytes – wie eine Authenticator-App das Geheimnis liest.
List<int> base32Zurueck(String s) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final aus = <int>[];
  var puffer = 0, bits = 0;
  for (final z in s.split('')) {
    puffer = (puffer << 5) | alphabet.indexOf(z);
    bits += 5;
    if (bits >= 8) {
      aus.add((puffer >> (bits - 8)) & 0xff);
      bits -= 8;
      puffer &= (1 << bits) - 1;
    }
  }
  return aus;
}
