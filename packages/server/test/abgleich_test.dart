import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/beilagenangaben.dart';
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
  Future<(AppDatabase, Abgleich)> geraet(
    String name, {
    StoragePaths? ablage,
  }) async {
    final token = konten.meldeAn(erika.id, name, 'x').token;
    final v = Serververbindung(Uri.parse('http://127.0.0.1:$port/'), token);
    final datei = File('${ordner.path}/$name/library.sqlite');
    await Abgleich.holeAbzug(v, datei);
    final db = AppDatabase(NativeDatabase(datei));
    final a = Abgleich(db, v, ablage: ablage);
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

  test('löscht der Server endgültig, räumt das Gerät seine geholten '
      'Dateien weg (#296)', () async {
    final s = await serverDb();
    await aufnahme(s, 'weg');
    await aufnahme(s, 'bleibt');
    final ablage = await StoragePaths.oeffne(
      Directory('${ordner.path}/Telefon/library'),
    );
    final (db, a) = await geraet('Telefon', ablage: ablage);
    // Was das Gerät geholt hat: Original und Miniatur beider Aufnahmen.
    for (final id in ['weg', 'bleibt']) {
      await s.customStatement(
        'UPDATE assets SET thumbnail_relative_path = ? WHERE id = ?',
        ['thumbnails/$id.jpg', id],
      );
    }
    await a.empfange();
    File datei(String rel) => ablage.absolute(rel)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x');
    final geholt = [
      for (final id in ['weg', 'bleibt']) ...[
        datei('originals/$id.jpg'),
        datei('thumbnails/$id.jpg'),
      ],
    ];

    await s.fuehreAus(const InDenPapierkorb(['weg']));
    expect(
      await leereImBereich(
        await bibliotheken.fuer(erika.id),
        erika.id,
        ids: ['weg'],
      ),
      ['weg'],
    );
    await a.empfange();

    expect(await db.assetsByIds(['weg']), isEmpty);
    expect(geholt[0].existsSync(), isFalse);
    expect(geholt[1].existsSync(), isFalse);
    expect(geholt[2].existsSync(), isTrue);
    expect(geholt[3].existsSync(), isTrue);
  });

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

  test('beim Start nicht „nicht erreichbar“, nach dem Hintergrund gleich '
      'wieder da', () async {
    final (_, a) = await geraet('Telefon');
    // Noch nicht gefragt: weder erreichbar noch nicht erreichbar.
    expect(a.zustandJetzt.ungeklaert, isTrue);
    final zustaende = <Abgleichszustand>[];
    a.zustand.listen(zustaende.add);
    Future<void> bis(bool Function() ok) async {
      for (var i = 0; i < 100 && !ok(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    a.starte();
    await bis(() => a.zustandJetzt.erreichbar);
    expect(a.zustandJetzt.erreichbar, isTrue);
    expect(a.zustandJetzt.ungeklaert, isFalse);
    expect(
      zustaende.where((z) => !z.erreichbar && !z.ungeklaert),
      isEmpty,
      reason: 'kein „nicht erreichbar“ beim Start',
    );

    // Jetzt wartet die lange Abfrage. Zurück aus dem Hintergrund bricht
    // jetzt() sie ab – ohne einen Aussetzer zu melden.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    a.jetzt();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(zustaende.where((z) => !z.erreichbar && !z.ungeklaert), isEmpty);

    // Ein echter Aussetzer wird gemeldet; danach fragt jetzt() sofort neu,
    // statt die (wachsende) Pause abzuwarten.
    await server.close(force: true);
    a.jetzt();
    await bis(() => !a.zustandJetzt.erreichbar);
    expect(a.zustandJetzt.erreichbar, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    await starteServer();
    final los = DateTime.now();
    a.jetzt();
    await bis(() => a.zustandJetzt.erreichbar);
    expect(a.zustandJetzt.erreichbar, isTrue);
    expect(
      DateTime.now().difference(los),
      lessThan(const Duration(seconds: 1)),
    );
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

  test('Long-Poll endet beim Schließen ohne Datenbankfehler', () async {
    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    final token = konten.meldeAn(erika.id, 'Rechner', 'x').token;
    final stand = await b.protokoll.stand();
    final antwort = http.get(
      Uri.parse(
        'http://127.0.0.1:$port/api/v1/abgleich/aenderungen'
        '?nach=$stand&warten=20',
      ),
      headers: {'authorization': 'Bearer $token'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await bibliotheken.schliesseAlle();
    expect((await antwort).statusCode, 503);
  });

  test(
    'ungültige Zeilenschlüssel werden als Anfragefehler abgewiesen',
    () async {
      final token = konten.meldeAn(erika.id, 'Rechner', 'x').token;
      final adresse = Uri.parse(
        'http://127.0.0.1:$port/api/v1/abgleich/zeilen',
      );
      for (final koerper in <Object?>[
        {
          'schluessel': ['kein Objekt'],
        },
        {
          'schluessel': [
            {'t': 'assets', 's': 'keine Liste'},
          ],
        },
        {
          'schluessel': [
            {'t': 'assets', 's': <Object?>[]},
          ],
        },
        {
          'schluessel': [
            {
              't': 'assets',
              's': [
                {'b': 42},
              ],
            },
          ],
        },
      ]) {
        final antwort = await http.post(
          adresse,
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode(koerper),
        );
        expect(antwort.statusCode, 400, reason: '$koerper');
      }
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
    'eine Bearbeitung vom Rechner legt sich über ihr Original (#302)',
    () async {
      final token = konten.meldeAn(erika.id, 'Rechner', 'x').token;
      final v = Serververbindung(Uri.parse('http://127.0.0.1:$port/'), token);
      addTearDown(v.schliesse);
      File bild(String name, int rot) {
        final b = img.Image(width: 64, height: 48);
        img.fill(b, color: img.ColorRgb8(rot, 90, 200 - rot));
        return File('${ordner.path}/$name')..writeAsBytesSync(img.encodeJpg(b));
      }

      final tus = TusHochladen(v);
      final erst = await tus.lade(bild('foto.jpg', 30), 'api/v1/hochladen', {
        'filename': 'foto.jpg',
      });
      final id = erst['pv-aufnahme']!;
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      final vorher = (await db.assetById(id))!;

      final neu = await tus.lade(bild('foto2.jpg', 180), 'api/v1/hochladen', {
        'filename': 'foto.jpg',
        'bearbeitungVon': vorher.checksum,
      });
      expect(neu['pv-ausgang'], 'imported');
      expect(neu['pv-aufnahme'], id);
      final nachher = (await db.assetById(id))!;
      expect(nachher.checksum, isNot(vorher.checksum));
      // Das Original liegt als eigene Aufnahme dahinter.
      expect(await db.select(db.assets).get(), hasLength(2));
      expect(nachher.stackId, isNotNull);
    },
  );

  test('Fotokammer: hochladen, ansehen, freigeben, verwerfen (#336)', () async {
    final token = konten.meldeAn(erika.id, 'Rechner', 'x').token;
    final v = Serververbindung(Uri.parse('http://127.0.0.1:$port/'), token);
    addTearDown(v.schliesse);
    expect(
      ((await v.hole('api/v1/zustand'))['funktionen'] as Map)['fotokammer'],
      greaterThanOrEqualTo(1),
    );
    File bild(String name, int rot) {
      final b = img.Image(width: 640, height: 480);
      img.fill(b, color: img.ColorRgb8(rot, 90, 200 - rot));
      return File('${ordner.path}/$name')..writeAsBytesSync(img.encodeJpg(b));
    }

    final tus = TusHochladen(v);
    final eins = bild('kammer1.jpg', 30);
    final zwei = bild('kammer2.jpg', 160);
    const kammer = {'kammer': '1'};
    final k1 = await tus.lade(eins, 'api/v1/hochladen', {
      'filename': 'kammer1.jpg',
      ...kammer,
    });
    expect(k1['pv-ausgang'], 'kammer');
    expect(k1['pv-kammer'], isNotNull);
    expect(k1['pv-aufnahme'], isNull);
    final k2 = await tus.lade(zwei, 'api/v1/hochladen', {
      'filename': 'kammer2.jpg',
      ...kammer,
    });
    expect(k2['pv-ausgang'], 'kammer');

    // Noch nicht in der Bibliothek – nirgends.
    final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    expect(await db.select(db.assets).get(), isEmpty);

    // Dieselbe Datei noch einmal: schon in der Kammer.
    final nochmal = await tus.lade(eins, 'api/v1/hochladen', {
      'filename': 'kammer1.jpg',
      ...kammer,
    });
    expect(nochmal['pv-ausgang'], 'duplicateSkipped');

    final liste = await v.hole('api/v1/kammer');
    final eintraege = (liste['eintraege'] as List).cast<Map>();
    expect(eintraege.map((e) => e['name']), ['kammer1.jpg', 'kammer2.jpg']);
    expect(liste['anzahl'], 2);
    expect(eintraege.first.containsKey('sha256'), isFalse);
    // Die Schärfe ist beim Ankommen gemessen (#348).
    expect(eintraege.first['schaerfe'], isA<num>());
    final id1 = k1['pv-kammer']!;
    final id2 = k2['pv-kammer']!;
    for (final art in ['miniatur', 'vorschau']) {
      final r = await v.anfrage('GET', 'api/v1/kammer/$id1/$art');
      expect(r.statusCode, 200, reason: art);
      expect(r.headers['content-type'], 'image/jpeg');
      expect(img.decodeJpg(r.bodyBytes), isNotNull);
    }
    expect(
      (await v.anfrage('GET', 'api/v1/kammer/nicht-da/miniatur')).statusCode,
      404,
    );
    final voll = await v.anfrage('GET', 'api/v1/kammer/$id1/vollbild');
    expect(voll.statusCode, 200);
    expect(voll.bodyBytes, eins.readAsBytesSync());
    expect(
      (await v.anfrage('GET', 'api/v1/kammer/nicht-da/vollbild')).statusCode,
      404,
    );

    // Sichten: das Urteil steht danach in der Liste.
    expect(
      (await v.schicke('api/v1/kammer/sichten', {
        'ids': [id1, 'nicht-da'],
        'sterne': 4,
      }))['geaendert'],
      1,
    );
    await v.schicke('api/v1/kammer/sichten', {
      'ids': [id2],
      'abgelehnt': true,
    });
    final gesichtet = {
      for (final e in ((await v.hole('api/v1/kammer'))['eintraege'] as List))
        (e as Map)['id']: e,
    };
    expect(gesichtet[id1]!['sterne'], 4);
    expect(gesichtet[id1]!['abgelehnt'], isFalse);
    expect(gesichtet[id2]!['abgelehnt'], isTrue);
    await expectLater(
      v.schicke('api/v1/kammer/sichten', {
        'ids': [id1],
        'sterne': 9,
      }),
      throwsA(isA<Serverfehler>()),
    );

    // Nur Abgelehntes verwerfen (#358): Hat ein anderes Gerät die Ablehnung
    // aufgehoben, bleibt das Foto, auch wenn ein alter Stand es verwerfen
    // wollte.
    final nicht = await v.schicke('api/v1/kammer/verwerfen', {
      'ids': [id1],
      'nurAbgelehnte': true,
    });
    expect(nicht['verworfen'], 0);
    expect((await v.hole('api/v1/kammer'))['anzahl'], 2);
    // Ein falsch geschriebener Schalter verwirft nicht still alles (#382).
    for (final falsch in ['true', 1]) {
      await expectLater(
        v.schicke('api/v1/kammer/verwerfen', {
          'ids': [id1],
          'nurAbgelehnte': falsch,
        }),
        throwsA(isA<Serverfehler>()),
        reason: '$falsch',
      );
    }
    expect((await v.hole('api/v1/kammer'))['anzahl'], 2);

    // Freigeben: in die Bibliothek, aus der Kammer heraus.
    final f = await v.schicke('api/v1/kammer/freigeben', {
      'ids': [id1],
    });
    final e = (f['ergebnisse'] as List).single as Map;
    expect(e['ausgang'], 'imported');
    final aufnahmen = await db.select(db.assets).get();
    expect(aufnahmen.single.id, e['aufnahme']);
    expect(aufnahmen.single.originalFileName, 'kammer1.jpg');
    // Die Sterne aus der Sichtung gehen mit.
    expect(aufnahmen.single.rating, 4);

    // Was in der Bibliothek liegt, kommt nicht wieder in die Kammer.
    final dublette = await tus.lade(eins, 'api/v1/hochladen', {
      'filename': 'kammer1.jpg',
      ...kammer,
    });
    expect(dublette['pv-ausgang'], 'duplicateSkipped');
    expect(dublette['pv-aufnahme'], e['aufnahme']);

    // Verwerfen: fort, ohne Spur in der Bibliothek.
    final w = await v.schicke('api/v1/kammer/verwerfen', {
      'ids': [id2, 'nicht-da'],
    });
    expect(w['verworfen'], 1);
    expect((await v.hole('api/v1/kammer'))['anzahl'], 0);
    expect(await db.select(db.assets).get(), hasLength(1));
    expect(
      (await v.anfrage('GET', 'api/v1/kammer/$id2/miniatur')).statusCode,
      404,
    );

    // Auch auf dem geraden Weg in die Bibliothek (#346).
    final gerade = await tus.lade(bild('gerade.jpg', 111), 'api/v1/hochladen', {
      'filename': 'gerade.jpg',
      'xmp': const Beilagenangaben(sterne: 3, abgelehnt: true).alsText(),
    });
    expect(gerade['pv-ausgang'], 'imported');
    final dbG = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    final zeileG = (await dbG.assetById(gerade['pv-aufnahme']!))!;
    expect(zeileG.rating, 3);
    expect(zeileG.isTrashed, isFalse);

    // Ohne `kammer` geht ein Upload wie bisher gleich in die Bibliothek.
    final direkt = await tus.lade(zwei, 'api/v1/hochladen', {
      'filename': 'kammer2.jpg',
    });
    expect(direkt['pv-ausgang'], 'imported');

    // Was neben dem Foto auf dem Rechner lag, kommt mit (#346).
    final mitBeilage = await tus.lade(
      bild('beilage.jpg', 70),
      'api/v1/hochladen',
      {
        'filename': 'beilage.jpg',
        ...kammer,
        'xmp': const Beilagenangaben(
          sterne: 2,
          beschreibung: 'am Fluss',
          schlagwoerter: ['Fluss'],
        ).alsText(),
      },
    );
    final idBeilage = mitBeilage['pv-kammer']!;
    final inListe =
        (((await v.hole('api/v1/kammer'))['eintraege'] as List).cast<Map>())
            .firstWhere((e) => e['id'] == idBeilage);
    expect(inListe['sterne'], 2);
    expect(inListe.containsKey('beilage'), isFalse);
    await v.schicke('api/v1/kammer/sichten', {
      'ids': [idBeilage],
      'sterne': 5,
    });
    final mitB = await v.schicke('api/v1/kammer/freigeben', {
      'ids': [idBeilage],
    });
    final neuB = ((mitB['ergebnisse'] as List).single as Map)['aufnahme'];
    final dbB = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    final zeile = (await dbB.assetById(neuB as String))!;
    // Die Sichtung hat das letzte Wort, der Rest kommt aus der Beilage.
    expect(zeile.rating, 5);
    expect(zeile.description, 'am Fluss');
    expect((await dbB.tagsForAsset(neuB)).map((t) => t.name), ['Fluss']);

    // Ein Foto, das heisst wie die eigene Vorschau, bleibt das Foto.
    final vorschauName = bild('vorschau.jpg', 44);
    final inhalt = vorschauName.readAsBytesSync();
    final namens = await tus.lade(vorschauName, 'api/v1/hochladen', {
      'filename': 'vorschau.jpg',
      ...kammer,
    });
    final volle = await v.anfrage(
      'GET',
      'api/v1/kammer/${namens['pv-kammer']}/vollbild',
    );
    expect(volle.bodyBytes, inhalt);

    // Schnelle Urteile überholen sich nicht.
    final reihe = <Future<Object?>>[
      for (var s = 1; s <= 5; s++)
        v.schicke('api/v1/kammer/sichten', {
          'ids': [namens['pv-kammer']],
          'sterne': s,
        }),
    ];
    await Future.wait(reihe);
    final amEnde = ((await v.hole('api/v1/kammer'))['eintraege'] as List)
        .cast<Map>()
        .firstWhere((e) => e['id'] == namens['pv-kammer']);
    expect(amEnde['sterne'], inInclusiveRange(1, 5));
    expect(
      Directory(
        '${(await bibliotheken.fuer(erika.id)).bibliothek.ordner.path}'
        '/fotokammer/${namens['pv-kammer']}',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.neu')),
      isEmpty,
    );
    await v.schicke('api/v1/kammer/verwerfen', {
      'ids': [namens['pv-kammer']],
    });

    // Freigeben mit Ziel (#349): dasselbe Album über mehrere Stapel.
    for (final (n, name) in [(120, 'ziel1.jpg'), (121, 'ziel2.jpg')]) {
      final k = await tus.lade(bild(name, n), 'api/v1/hochladen', {
        'filename': name,
        ...kammer,
      });
      final f = await v.schicke('api/v1/kammer/freigeben', {
        'ids': [k['pv-kammer']],
        'ziel': {
          'album': 'Spiel',
          'schlagwoerter': ['Fussball'],
          'breite': 47.1,
          'laenge': 8.2,
        },
      });
      expect(((f['ergebnisse'] as List).single as Map)['ausgang'], 'imported');
    }
    final dbZ = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    final alben = (await dbZ.alleAlben()).where((a) => a.name == 'Spiel');
    expect(alben, hasLength(1));
    expect(await dbZ.select(dbZ.albumAssets).get(), hasLength(2));
    final imAlbum = await dbZ.assetById(
      (await dbZ.select(dbZ.albumAssets).get()).first.assetId,
    );
    expect(imAlbum!.latitude, 47.1);
    expect(
      (await dbZ.tagsForAsset(imAlbum.id)).map((t) => t.name),
      contains('Fussball'),
    );

    // Ein Standbild aus einem Video trägt dessen Angaben (#302).
    final dbV = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    final quelle = (await dbV.select(dbV.assets).get()).first;
    await dbV.fuehreAus(OrtSetzen([quelle.id], 47.5, 8.5));
    final standbild = await tus.lade(
      bild('standbild.jpg', 13),
      'api/v1/hochladen',
      {
        'filename': 'standbild.jpg',
        'videoVon': quelle.id,
        'videoZeit': '${DateTime.utc(2021, 3, 4, 5, 6).millisecondsSinceEpoch}',
      },
    );
    final zeileV = (await dbV.assetById(standbild['pv-aufnahme']!))!;
    expect(zeileV.fileCreatedAt.toUtc(), DateTime.utc(2021, 3, 4, 5, 6));
    expect(zeileV.latitude, 47.5);

    // Ein anderes Konto sieht die Kammer nicht.
    final otto = await konten.legeAn('otto', 'ein anderes passwort');
    final v2 = Serververbindung(
      Uri.parse('http://127.0.0.1:$port/'),
      konten.meldeAn(otto.id, 'Rechner', 'x').token,
    );
    addTearDown(v2.schliesse);
    final k3 = await TusHochladen(v2).lade(
      bild('otto.jpg', 90),
      'api/v1/hochladen',
      {'filename': 'otto.jpg', ...kammer},
    );
    expect(k3['pv-ausgang'], 'kammer');
    expect((await v.hole('api/v1/kammer'))['anzahl'], 0);
    expect(
      (await v.anfrage(
        'GET',
        'api/v1/kammer/${k3['pv-kammer']}/miniatur',
      )).statusCode,
      404,
    );
    final fremd = await v.schicke('api/v1/kammer/verwerfen', {
      'ids': [k3['pv-kammer']],
    });
    expect(fremd['verworfen'], 0);
  });

  test(
    'Fotokammer: Fotos der Bibliothek hinein und unverändert zurück (#337)',
    () async {
      final token = konten.meldeAn(erika.id, 'Rechner', 'x').token;
      final v = Serververbindung(Uri.parse('http://127.0.0.1:$port/'), token);
      addTearDown(v.schliesse);
      expect(
        ((await v.hole('api/v1/zustand'))['funktionen'] as Map)['fotokammer'],
        4,
      );
      File bild(String name, int rot) {
        final b = img.Image(width: 640, height: 480);
        img.fill(b, color: img.ColorRgb8(rot, 120, 40));
        return File('${ordner.path}/$name')..writeAsBytesSync(img.encodeJpg(b));
      }

      final tus = TusHochladen(v);
      final eins = (await tus.lade(
        bild('zurueck1.jpg', 10),
        'api/v1/hochladen',
        {'filename': 'zurueck1.jpg'},
      ))['pv-aufnahme']!;
      final zwei = (await tus.lade(
        bild('zurueck2.jpg', 220),
        'api/v1/hochladen',
        {'filename': 'zurueck2.jpg'},
      ))['pv-aufnahme']!;
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      // Etwas, das beim Zurückholen erhalten bleiben muss.
      await db.fuehreAus(BewertungSetzen([eins], 4));

      final r = await v.schicke('api/v1/kammer/aufnehmen', {
        'ids': [eins, zwei, 'gibt-es-nicht'],
      });
      final ergebnisse = (r['ergebnisse'] as List).cast<Map>();
      expect(ergebnisse.map((e) => e['ausgang']), [
        'kammer',
        'kammer',
        'unbekannt',
      ]);
      // In den Papierkorb, also aus der Zeitleiste – überall.
      expect((await holeAufnahme(db, eins)).isTrashed, isTrue);
      expect((await holeAufnahme(db, zwei)).isTrashed, isTrue);
      final liste = await v.hole('api/v1/kammer');
      expect(liste['anzahl'], 2);
      final k1 = ergebnisse[0]['kammer'] as String;
      final k2 = ergebnisse[1]['kammer'] as String;
      final mini = await v.anfrage('GET', 'api/v1/kammer/$k1/miniatur');
      expect(mini.statusCode, 200);
      // Schon im Papierkorb: nicht ein zweites Mal.
      final nochmal = await v.schicke('api/v1/kammer/aufnehmen', {
        'ids': [eins],
      });
      expect(
        ((nochmal['ergebnisse'] as List).single as Map)['ausgang'],
        'unbekannt',
      );

      // Freigeben holt dieselbe Aufnahme zurück, mit ihrer Bewertung.
      final f = await v.schicke('api/v1/kammer/freigeben', {
        'ids': [k1],
      });
      final e = (f['ergebnisse'] as List).single as Map;
      expect(e['ausgang'], 'imported');
      expect(e['aufnahme'], eins);
      final zurueck = await holeAufnahme(db, eins);
      expect(zurueck.isTrashed, isFalse);
      expect(zurueck.rating, 4);
      expect(await db.select(db.assets).get(), hasLength(2));

      // Verwerfen: aus der Kammer, die Aufnahme bleibt im Papierkorb.
      final w = await v.schicke('api/v1/kammer/verwerfen', {
        'ids': [k2],
      });
      expect(w['verworfen'], 1);
      expect((await holeAufnahme(db, zwei)).isTrashed, isTrue);
      expect((await v.hole('api/v1/kammer'))['anzahl'], 0);
    },
  );

  test(
    'Hochladen versucht es nach vorübergehenden Fehlern erneut (#335)',
    () async {
      final token = konten.meldeAn(erika.id, 'Rechner', 'x').token;
      // Der Proxy davor weist die erste Anlage mit einer Fehlerseite ab,
      // und das erste Stück mit 503 – wie ein Proxy, der kurz nicht will.
      final stoerung = _Stoerung({('POST', 1): 502, ('PATCH', 1): 503});
      final v = Serververbindung(
        Uri.parse('http://127.0.0.1:$port/'),
        token,
        client: stoerung,
      );
      addTearDown(v.schliesse);
      final bild = img.Image(width: 300, height: 200);
      img.fill(bild, color: img.ColorRgb8(200, 60, 30));
      final datei = File('${ordner.path}/abend.jpg')
        ..writeAsBytesSync(img.encodeJpg(bild));
      final gewartet = <Duration>[];
      final kopf = await TusHochladen(v, stueck: 200).ladeBeharrlich(
        datei,
        'api/v1/hochladen',
        const {'filename': 'abend.jpg'},
        warte: (d) async => gewartet.add(d),
      );
      expect(kopf['pv-ausgang'], 'imported');
      expect(gewartet, TusHochladen.wiederholungsabstaende.take(2));
      // Nach dem 503 ging es am selben Upload weiter, nicht an einem neuen.
      expect(stoerung.anfragen.where((a) => a == 'POST'), hasLength(2));
      expect(stoerung.anfragen, contains('HEAD'));

      // Was beim zweiten Mal genauso scheitert, wird nicht wiederholt.
      final psd = File('${ordner.path}/ebene.xyz')..writeAsBytesSync([1, 2]);
      await expectLater(
        TusHochladen(v).ladeBeharrlich(psd, 'api/v1/hochladen', const {
          'filename': 'ebene.xyz',
        }, warte: (_) async => fail('kein neuer Versuch')),
        throwsA(isA<Serverfehler>().having((e) => e.status, 'status', 415)),
      );

      // Ohne Abstände genau ein Versuch.
      final ohne = _Stoerung({('POST', 1): 503});
      final v2 = Serververbindung(
        Uri.parse('http://127.0.0.1:$port/'),
        token,
        client: ohne,
      );
      addTearDown(v2.schliesse);
      await expectLater(
        TusHochladen(v2).ladeBeharrlich(datei, 'api/v1/hochladen', const {
          'filename': 'abend.jpg',
        }, abstaende: const []),
        throwsA(isA<Serverfehler>()),
      );
      expect(ohne.anfragen, ['POST']);
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

  test('neue Wiederherstellungscodes: nur mit TOTP-Code, die alten gelten '
      'danach nicht mehr', () async {
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
    final einrichten =
        await anmeldung.anmelden('max', 'noch ein passwort', geraet: 'Telefon')
            as AnmeldungTotpEinrichten;
    final geheimnis = base32Zurueck(einrichten.geheimnis);
    final schritt = Totp.schritt(DateTime.now());
    final fertig =
        await anmeldung.bestaetige(
              einrichten.vorgang,
              Totp.code(geheimnis, schritt),
            )
            as AnmeldungFertig;
    final alt = fertig.wiederherstellungscodes!;
    final v = Serververbindung(
      Uri.parse('http://127.0.0.1:$port/'),
      fertig.token,
    );
    await expectLater(
      v.schicke('api/v1/konto/wiederherstellungscodes', {'code': '000000'}),
      throwsA(isA<Serverfehler>().having((f) => f.status, 'status', 403)),
    );
    final neu =
        (await v.schicke('api/v1/konto/wiederherstellungscodes', {
              'code': Totp.code(geheimnis, schritt + 1),
            }))['wiederherstellungscodes']!
            as List;
    expect(neu, hasLength(10));
    expect(neu.toSet().intersection(alt.toSet()), isEmpty);
    expect((await v.hole('api/v1/konto'))['wiederherstellungscodes'], 10);
    // Ein alter Code meldet nicht mehr an, ein neuer schon.
    final s1 =
        await anmeldung.anmelden('max', 'noch ein passwort', geraet: 'Rechner')
            as AnmeldungCode;
    expect(
      await anmeldung.bestaetige(s1.vorgang, alt.first),
      isA<AnmeldungAbgewiesen>(),
    );
    final s2 =
        await anmeldung.anmelden('max', 'noch ein passwort', geraet: 'Rechner')
            as AnmeldungCode;
    expect(
      await anmeldung.bestaetige(s2.vorgang, '${neu.first}'),
      isA<AnmeldungFertig>(),
    );
    v.schliesse();
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

/// Ein Client, der die n-te Anfrage einer Methode mit einem Status
/// beantwortet, statt sie durchzulassen – wie ein Proxy mit Launen.
class _Stoerung extends http.BaseClient {
  _Stoerung(this.regeln);
  final Map<(String, int), int> regeln;
  final _innen = http.Client();
  final anfragen = <String>[];
  final _zaehler = <String, int>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    anfragen.add(request.method);
    final n = _zaehler.update(request.method, (n) => n + 1, ifAbsent: () => 1);
    if (regeln[(request.method, n)] case final status?) {
      await request.finalize().drain<void>();
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            '<html>\r\n<head><title>$status Bad Gateway</title></head>\r\n'
            '<body>\r\n<center><h1>$status</h1></center>\r\n'
            '<hr><center>openresty</center>\r\n</body>\r\n</html>\r\n',
          ),
        ),
        status,
      );
    }
    return _innen.send(request);
  }

  @override
  void close() => _innen.close();
}
