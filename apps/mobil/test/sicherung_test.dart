import 'dart:io';

import 'package:drift/native.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault_mobil/lokal/ungesichert.dart';
import 'package:photo_vault_mobil/sicherung/freigabe.dart';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_mobil/sicherung/kamerarolle.dart';
import 'package:photo_vault_mobil/sicherung/lauf.dart';
import 'package:photo_vault_mobil/sicherung/serien.dart';
import 'package:photo_vault_mobil/sicherung/stand.dart';
import 'package:photo_vault_mobil/sicherung/telefonloeschung.dart';

import 'hilfen/testserver.dart';

/// Eine Kamerarolle aus Dateien – was `photo_manager` am Telefon liefert,
/// ohne Telefon.
class _Rolle implements Kamerarolle {
  final eintraege_ = <Rolleneintrag>[];
  var aufgeraeumt = 0;

  /// Läuft, wenn der Lauf die Dateien eines Eintrags anfordert.
  void Function(String id)? beimBereitstellen;

  void foto(String id, File datei, {DateTime? geaendert}) =>
      eintraege_.insert(0, _eintrag(id, [('bild', datei)], geaendert));

  /// Ein in der Fotos-App bearbeitetes Foto: Original und Bearbeitung,
  /// wie [PhotoManagerRolle] sie liefert (#271).
  void bearbeitetesFoto(
    String id,
    File original,
    File bearbeitung, {
    DateTime? geaendert,
  }) {
    eintraege_.removeWhere((x) => x.id == id);
    eintraege_.insert(
      0,
      _eintrag(id, [
        ('bild', original),
        ('bearbeitet', bearbeitung),
      ], geaendert),
    );
  }

  void livePhoto(String id, File bild, File film) => eintraege_.insert(
    0,
    _eintrag(id, [('bild', bild), ('video', film)], null),
  );

  void fehlt(String id) => eintraege_.insert(
    0,
    Rolleneintrag(
      id: id,
      geaendert: DateTime(2025),
      aufgenommen: DateTime(2025),
      video: false,
      dateien: () async => null,
    ),
  );

  /// Ein Bild einer Serie (#314).
  void zusatz(String id, File datei, {String? serie, bool titel = false}) =>
      eintraege_.insert(
        0,
        Rolleneintrag(
          id: id,
          geaendert: DateTime(2025, 6, 1),
          aufgenommen: DateTime(2025, 6, 1, 12),
          video: false,
          dateien: () async => [
            Rollendatei(
              teil: 'bild',
              name: p.basename(datei.path),
              datei: datei,
            ),
          ],
          serie: serie,
          serientitel: titel,
        ),
      );

  void bearbeite(String id) {
    final i = eintraege_.indexWhere((x) => x.id == id);
    final alt = eintraege_[i];
    eintraege_[i] = Rolleneintrag(
      id: id,
      geaendert: alt.geaendert.add(const Duration(minutes: 1)),
      aufgenommen: alt.aufgenommen,
      video: alt.video,
      dateien: alt.dateien,
    );
  }

  Rolleneintrag _eintrag(
    String id,
    List<(String, File)> teile,
    DateTime? geaendert,
  ) => Rolleneintrag(
    id: id,
    geaendert: geaendert ?? DateTime(2025, 6, 1),
    aufgenommen: DateTime(2025, 6, 1, 12),
    video: false,
    dateien: () async {
      beimBereitstellen?.call(id);
      return [
        for (final (teil, datei) in teile)
          Rollendatei(teil: teil, name: p.basename(datei.path), datei: datei),
      ];
    },
  );

  @override
  Future<List<Rolleneintrag>> eintraege({required bool videos}) async => [
    ...eintraege_,
  ];

  @override
  Future<void> aufraeumen() async => aufgeraeumt++;

  @override
  Future<List<String>> vorhanden(List<String> ids) async => [
    for (final id in ids)
      if (eintraege_.any((x) => x.id == id)) id,
  ];

  @override
  Future<int> loesche(List<String> ids) async {
    final vorher = eintraege_.length;
    eintraege_.removeWhere((x) => ids.contains(x.id));
    return vorher - eintraege_.length;
  }
}

void main() {
  late Testserver server;
  late Serververbindung telefon;
  late Directory ordner;

  setUpAll(() async {
    server = await Testserver.starte('pv_sicherung_');
    telefon = await server.verbinde('Telefon');
  });

  tearDownAll(() async {
    telefon.schliesse();
    await server.beende();
  });

  late Sicherungsstand stand;
  late _Rolle rolle;

  setUp(() {
    ordner = Directory(
      p.join(
        server.ordner.path,
        'telefon-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    stand = Sicherungsstand.oeffne(ordner)
      ..einstellungen = const Sicherungseinstellungen(an: true);
    rolle = _Rolle();
  });

  tearDown(() => stand.schliesse());

  File zufall(String name, int laenge, int saat) {
    final r = Random(saat);
    return File(p.join(server.ordner.path, 'rolle', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.generate(laenge, (_) => r.nextInt(256)));
  }

  Sicherungslauf lauf({
    String wer = 'app',
    int stueck = 32 * 1024 * 1024,
    int gruppeBytes = 256 * 1024 * 1024,
  }) => Sicherungslauf(
    rolle: rolle,
    verbindung: telefon,
    stand: stand,
    wer: wer,
    stueck: stueck,
    gruppeBytes: gruppeBytes,
  );

  Future<List<Map>> aufServer() async =>
      ((await telefon.hole('api/v1/aufnahmen'))['aufnahmen']! as List)
          .cast<Map>();

  /// Der Testserver ist für alle Tests derselbe.
  Future<List<Map>> eigene(String vorsatz) async => [
    for (final a in await aufServer())
      if ('${a['name']}'.startsWith(vorsatz)) a,
  ];

  test('kennt das Foto des Telefons zu einer Aufnahme (#330)', () {
    final zeit = DateTime(2026, 3, 4, 5);
    stand
      ..erledige('p1', zeit, ausgang: 'hochgeladen', aufnahme: 'a1')
      ..erledige('p2', zeit, ausgang: 'vorhanden', aufnahme: 'a2')
      ..erledige('p3', zeit, ausgang: 'abgelehnt', aufnahme: 'a3');
    final g = stand.gesichertAls('a1');
    expect(g?.lokal, 'p1');
    expect(g?.geaendert, zeit.millisecondsSinceEpoch);
    expect(stand.gesichertAls('a2')?.lokal, 'p2');
    expect(stand.gesichertAls('a3'), isNull, reason: 'nicht gesichert');
    expect(stand.gesichertAls('fehlt'), isNull);
  });

  test('der erste Lauf lädt alles hoch, der zweite nichts', () async {
    rolle
      ..foto('a', server.jpeg('IMG_0101.JPG', 10))
      ..foto('b', server.jpeg('IMG_0102.JPG', 20))
      ..livePhoto(
        'c',
        server.jpeg('IMG_0103.JPG', 30),
        zufall('IMG_0103.MOV', 4096, 1),
      );
    final erster = await lauf().laufe();
    expect(erster.gesamt, 3);
    expect(erster.hochgeladen, 3);
    expect(erster.offen, 0);
    expect(erster.vollstaendig, isTrue);

    final namen = {for (final z in await aufServer()) z['name']: z['id']};
    expect(namen.keys, containsAll(['IMG_0101.JPG', 'IMG_0102.JPG']));
    final live = await telefon.hole(
      'api/v1/aufnahmen/${namen['IMG_0103.JPG']}',
    );
    expect(live['linkedAssetId'], isNotNull, reason: 'Bild und Film ein Paar');

    final zweiter = await lauf().laufe();
    expect(zweiter.hochgeladen + zweiter.vorhanden, 0);
    expect(zweiter.offen, 0);
    expect(stand.letzterLauf!.gesamt, 3);
  });

  test('was der Server schon hat, geht nicht noch einmal hoch', () async {
    final datei = server.jpeg('IMG_0201.JPG', 77);
    final rechner = await server.verbinde('Rechner');
    final vom = await Testserver.hochladen(rechner, datei);
    rechner.schliesse();
    rolle.foto('d', datei);

    final r = await lauf().laufe();
    expect(r.vorhanden, 1);
    expect(r.hochgeladen, 0);
    expect(stand.bekannt().erledigt.keys, ['d']);

    // Bearbeitet: noch einmal prüfen – das Original ist dasselbe.
    rolle.bearbeite('d');
    final nachher = await lauf().laufe();
    expect(nachher.vorhanden, 1);
    expect(nachher.hochgeladen, 0);
    expect(vom['pv-ausgang'], 'imported');
  });

  test(
    'ein Format, das der Server nicht kennt: abgelehnt, ohne ein Byte',
    () async {
      // Der Server ist für alle Tests derselbe – gezählt wird, was dazukommt.
      final vorher = (await aufServer()).length;
      rolle.foto('p', zufall('IMG_0401.xyz', 1000, 3));
      final r = await lauf().laufe();
      expect(r.fehlgeschlagen, 1);
      expect(r.hochgeladen, 0);
      expect(stand.bekannt().abgelehnt.keys, ['p']);
      expect(stand.abgelehnteGruende['p'], contains('.xyz'));
      // Beim nächsten Lauf wird nicht einmal mehr gefragt …
      expect((await lauf().laufe()).fehlgeschlagen, 1);
      // … und „Erneut versuchen“ kostet nur die eine Anfrage, kein Hochladen.
      stand.vergissFehler();
      expect((await lauf().laufe()).fehlgeschlagen, 1);
      expect(await aufServer(), hasLength(vorher));
    },
  );

  test(
    'was noch nicht gesichert ist: Neues und seither Bearbeitetes',
    () async {
      rolle.foto('g1', server.jpeg('IMG_0601.JPG', 61));
      rolle.foto('g2', server.jpeg('IMG_0602.JPG', 62));
      await lauf().laufe();
      final alle = await rolle.eintraege(videos: true);
      expect(nochNichtGesichert(alle, stand.bekannt().erledigt), isEmpty);
      rolle.bearbeite('g1');
      rolle.foto('g3', server.jpeg('IMG_0603.JPG', 63));
      final danach = nochNichtGesichert(
        await rolle.eintraege(videos: true),
        stand.bekannt().erledigt,
      );
      expect(danach.map((a) => a.id), unorderedEquals(['g1', 'g3']));
      expect(danach.first.entity, isNull);
    },
  );

  test(
    'Speicher freigeben: nur Unverändertes, das am Server noch da ist',
    () async {
      rolle.foto('f1', server.jpeg('IMG_0501.JPG', 51));
      rolle.foto('f2', server.jpeg('IMG_0502.JPG', 52));
      rolle.foto('offen', zufall('IMG_0503.xyz', 100, 9));
      await lauf().laufe();
      final amServer = {for (final a in await aufServer()) a['name']: a['id']};
      // Die Kopie der Bibliothek auf dem Telefon, wie der Abgleich sie füllt.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (final name in ['IMG_0501.JPG', 'IMG_0502.JPG']) {
        await db.insertAsset(
          AssetsCompanion.insert(
            id: amServer[name]! as String,
            originalFileName: name,
            relativePath: 'originals/$name',
            checksum: 'pruef-$name',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2025),
            importedAt: DateTime(2026),
          ),
        );
      }
      final f = Speicherfreigabe(stand: stand, rolle: rolle, db: db);
      expect(await f.kandidaten(), unorderedEquals(['f1', 'f2']));

      // Seit der Sicherung bearbeitet: bleibt.
      rolle.bearbeite('f1');
      expect(await f.kandidaten(), ['f2']);
      // Am Server im Papierkorb: bleibt ebenfalls.
      await db.moveToTrash([amServer['IMG_0502.JPG']! as String]);
      expect(await f.kandidaten(), isEmpty);
      await db.restoreFromTrash([amServer['IMG_0502.JPG']! as String]);

      expect(await f.gib(await f.kandidaten()), 1);
      expect(
        (await rolle.eintraege(videos: true)).map((x) => x.id),
        isNot(contains('f2')),
      );
      expect(await f.kandidaten(), isEmpty);
    },
  );

  Future<AppDatabase> kopieMit(Iterable<Map> aufnahmen) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (final a in aufnahmen) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: a['id']! as String,
          originalFileName: a['name']! as String,
          relativePath: 'originals/${a['name']}',
          checksum: 'pruef-${a['name']}',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2025),
          importedAt: DateTime(2026),
        ),
      );
    }
    return db;
  }

  test(
    'Serie: alle Bilder gesichert, gestapelt, nichts davon zum Löschen (#314)',
    () async {
      rolle
        ..zusatz('s1', server.jpeg('BURST_01.JPG', 71), serie: 'B', titel: true)
        ..zusatz('s2', server.jpeg('BURST_02.JPG', 72), serie: 'B')
        ..zusatz('s3', server.jpeg('BURST_03.JPG', 73), serie: 'B')
        ..foto('f1', server.jpeg('BURST_04.JPG', 74));
      final bericht = await lauf().laufe();
      expect(bericht.hochgeladen, 4);

      final amServer = await eigene('BURST_0');
      final zuName = {for (final a in amServer) a['name']: a['id'] as String};
      final alle = await rolle.eintraege(videos: true);

      // In der Zeitleiste steht von der Serie nur das Titelbild.
      expect(alle.where((e) => e.eigenesBild).map((e) => e.id).toSet(), {
        's1',
        'f1',
      });

      // Kennt die Kopie noch nicht alle Bilder, wartet der Stapel.
      final teilweise = await kopieMit(
        amServer.where((a) => a['name'] != 'BURST_03.JPG'),
      );
      expect(await Serienstapel(stand: stand, db: teilweise).bilde(alle), 0);

      final db = await kopieMit(amServer);
      final stapel = Serienstapel(stand: stand, db: db);
      expect(await stapel.bilde(alle), 1);
      Future<AssetData> zeile(String name) => (db.select(
        db.assets,
      )..where((t) => t.id.equals(zuName[name]!))).getSingle();
      final titel = await zeile('BURST_01.JPG');
      expect(titel.isStackCover, isTrue);
      expect(titel.stackSize, 3);
      expect((await zeile('BURST_02.JPG')).stackId, titel.stackId);
      expect((await zeile('BURST_04.JPG')).stackId, isNull);

      // Einmal je Serie: Wer sie auflöst, behält das.
      await db.unstackAssets(titel.stackId!);
      expect(await stapel.bilde(alle), 0);

      // Speicher freigeben: nur das Foto ausserhalb der Serie.
      final f = Speicherfreigabe(stand: stand, rolle: rolle, db: db);
      expect(await f.kandidaten(), ['f1']);
    },
  );

  test('Serie: ein Stapel von Hand bleibt, wie er ist (#314)', () async {
    rolle
      ..zusatz('h1', server.jpeg('BURST_11.JPG', 75), serie: 'C', titel: true)
      ..zusatz('h2', server.jpeg('BURST_12.JPG', 76), serie: 'C');
    await lauf().laufe();
    final amServer = await eigene('BURST_1');
    final db = await kopieMit(amServer);
    await db.createStack('von-hand', [
      for (final a in amServer) a['id']! as String,
    ], amServer.first['id']! as String);
    final stapel = Serienstapel(stand: stand, db: db);
    expect(await stapel.bilde(await rolle.eintraege(videos: true)), 0);
    expect(stand.gestapelteSerien(), {'C'});
  });

  test(
    'auch vom Telefon löschen: was dazu gehört, und was im Papierkorb liegt (#205)',
    () async {
      rolle.foto('t1', server.jpeg('IMG_0601.JPG', 61));
      rolle.foto('t2', server.jpeg('IMG_0602.JPG', 62));
      rolle.foto('t3', server.jpeg('IMG_0603.JPG', 63));
      await lauf().laufe();
      final amServer = {for (final a in await aufServer()) a['name']: a['id']};
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      // t3 hat der Abgleich noch nicht gebracht.
      for (final name in ['IMG_0601.JPG', 'IMG_0602.JPG']) {
        await db.insertAsset(
          AssetsCompanion.insert(
            id: amServer[name]! as String,
            originalFileName: name,
            relativePath: 'originals/$name',
            checksum: 'pruef-$name',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2025),
            importedAt: DateTime(2026),
          ),
        );
      }
      final l = Telefonloeschung(stand: stand, rolle: rolle, db: db);
      final eins = amServer['IMG_0601.JPG']! as String;
      expect(await l.zu([eins]), ['t1']);
      expect(await l.zu(['gibt-es-nicht']), isEmpty);

      // Auf einem anderen Gerät gelöscht: liegt im Papierkorb der Kopie.
      expect(await l.ausDemPapierkorb(), isEmpty);
      await db.moveToTrash([eins]);
      expect(await l.ausDemPapierkorb(), ['t1']);

      // Was ganz fehlt, kann auch nur noch nicht abgeglichen sein: bleibt.
      expect(await l.loesche(await l.ausDemPapierkorb()), 1);
      expect(
        (await rolle.eintraege(videos: true)).map((x) => x.id),
        unorderedEquals(['t2', 't3']),
      );
      expect(await l.ausDemPapierkorb(), isEmpty, reason: 'schon weg');
      expect(await l.zu([eins]), isEmpty);
    },
  );

  test(
    'abgebrochen geht es beim nächsten Lauf an derselben Stelle weiter',
    () async {
      final film = zufall('VID_0301.MOV', 600 * 1024, 2);
      rolle.foto('e', film);
      var angekommen = 0;
      final erster = await lauf(stueck: 100 * 1024).laufe(
        abbrechen: () => angekommen >= 300 * 1024,
        meldung: (f) => angekommen = f.bytes ?? angekommen,
      );
      expect(erster.vollstaendig, isFalse);
      expect(erster.offen, 1);

      final stellen = <int>[];
      final zweiter = await lauf(stueck: 100 * 1024).laufe(
        meldung: (f) {
          if (f.bytes != null) stellen.add(f.bytes!);
        },
      );
      expect(stellen.first, 400 * 1024, reason: 'drei Stücke waren schon da');
      expect(zweiter.hochgeladen, 1);
      expect(zweiter.vollstaendig, isTrue);
    },
  );

  test('ein Fehler der Plattform trifft nur dieses Foto (#311)', () async {
    // So meldet photo_manager ein Original, das sich nicht holen lässt.
    rolle.eintraege_.add(
      Rolleneintrag(
        id: 'kaputt',
        geaendert: DateTime(2025),
        aufgenommen: DateTime(2025),
        video: false,
        dateien: () async =>
            throw PlatformException(code: 'pm', message: 'iCloud'),
      ),
    );
    rolle.foto('heil', server.jpeg('IMG_HEIL.JPG', 11));
    final b = await lauf().laufe();
    expect(b.hochgeladen, 1);
    expect(b.fehlgeschlagen, 1);
    expect(stand.fehler.keys, ['kaputt']);
  });

  test('nie zwei Läufe zugleich', () async {
    rolle.foto('f', server.jpeg('IMG_0401.JPG', 140));
    expect(stand.sperre('hintergrund'), isTrue);
    await expectLater(lauf().laufe(), throwsA(isA<Gesperrt>()));
    stand.gibFrei('hintergrund');
    expect((await lauf().laufe()).hochgeladen, 1);
  });

  test('wer die Sperre verliert, hört auf und räumt nichts weg', () async {
    rolle
      ..foto('m1', server.jpeg('IMG_0411.JPG', 141))
      ..foto('m2', server.jpeg('IMG_0412.JPG', 142))
      ..foto('m3', server.jpeg('IMG_0413.JPG', 143));
    // Während der Lauf bereitstellt, läuft seine Sperre ab und der Lauf im
    // Hintergrund nimmt sie – so, wie es eine lange Gruppe erlaubte.
    rolle.beimBereitstellen = (_) {
      stand.gibFrei('app');
      stand.sperre('hintergrund');
      rolle.beimBereitstellen = null;
    };
    final r = await lauf().laufe();
    expect(r.hochgeladen, 0);
    expect(r.fehlgeschlagen, 0, reason: 'kein Fehlschlag zählt zur Pause');
    expect(stand.fehler, isEmpty);
    expect(
      rolle.aufgeraeumt,
      0,
      reason: 'die Dateien im Zwischenspeicher braucht jetzt der andere',
    );
    expect(stand.sperre('app'), isFalse, reason: 'die Sperre bleibt drüben');

    stand.gibFrei('hintergrund');
    expect((await lauf().laufe()).hochgeladen, 3);
  });

  test('fehlt eine Datei, weil der andere übernahm, zählt das nicht', () async {
    final datei = server.jpeg('IMG_0421.JPG', 144);
    rolle.foto('n1', datei);
    // Angehalten, übernommen, Zwischenspeicher geleert: Beim Weiterlaufen
    // ist die Datei weg und die Sperre beim anderen.
    rolle.beimBereitstellen = (_) {
      stand.gibFrei('app');
      stand.sperre('hintergrund');
      datei.deleteSync();
    };
    final r = await lauf().laufe();
    expect(r.fehlgeschlagen, 0);
    expect(stand.fehler, isEmpty);
  });

  test(
    'ein Fehler trifft nur seinen Eintrag; Abgelehntes bleibt liegen',
    () async {
      rolle
        ..fehlt('g')
        ..foto('h', server.jpeg('IMG_0501.JPG', 160))
        ..foto('i', zufall('notiz.txt', 100, 3));
      final r = await lauf().laufe();
      expect(r.hochgeladen, 1);
      expect(r.fehlgeschlagen, 2);
      expect(stand.fehler.keys, ['g']);
      expect(stand.anzahlAbgelehnt, 1);

      // Abgelehntes geht nicht noch einmal hoch; der fehlende Eintrag wird
      // erneut versucht, bis er nach drei Fehlschlägen pausiert.
      for (var i = 0; i < 2; i++) {
        final n = await lauf().laufe();
        expect(n.hochgeladen, 0);
        expect(n.fehlgeschlagen, 2);
      }
      expect(stand.bekannt().pausiert, {'g'});

      stand.vergissFehler();
      expect(stand.bekannt().pausiert, isEmpty);
      expect(stand.anzahlAbgelehnt, 0);
    },
  );

  test('eine Gruppe belegt höchstens so viel Platz wie erlaubt', () async {
    rolle
      ..foto('j', server.jpeg('IMG_0601.JPG', 180))
      ..foto('k', server.jpeg('IMG_0602.JPG', 190))
      ..foto('l', server.jpeg('IMG_0603.JPG', 200));
    final r = await lauf(gruppeBytes: 1).laufe();
    expect(r.hochgeladen, 3);
    expect(rolle.aufgeraeumt, 3, reason: 'nach jedem Eintrag aufgeräumt');
  });

  group('in der Fotos-App bearbeitete Fotos (#271)', () {
    Future<List<int>> original(String id) async {
      final ziel = File(
        p.join(
          ordner.path,
          'geholt-$id-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await telefon.ladeHerunter('api/v1/aufnahmen/$id/original', ziel);
      return ziel.readAsBytesSync();
    }

    Future<Map> zeile(String name) async =>
        (await aufServer()).singleWhere((z) => z['name'] == name);

    test(
      'die Bearbeitung liegt über dem Original, auch beim zweiten Mal',
      () async {
        final roh = server.jpeg('IMG_0701.JPG', 40);
        rolle.foto('g', roh);
        await lauf().laufe();
        final id = (await zeile('IMG_0701.JPG'))['id'] as String;
        expect(await original(id), roh.readAsBytesSync());

        // In der Fotos-App bearbeitet: Das Original bleibt, die Bearbeitung
        // kommt dazu.
        final erste = server.jpeg('IMG_0701_bearbeitet.jpg', 90);
        rolle.bearbeitetesFoto('g', roh, erste, geaendert: DateTime(2025, 7));
        final r = await lauf().laufe();
        expect(r.hochgeladen, 1);
        final nachher = await zeile('IMG_0701.JPG');
        expect(nachher['id'], id, reason: 'dieselbe Aufnahme, mit allem daran');
        expect(await original(id), erste.readAsBytesSync());
        final serie = nachher['serie'] as Map;
        expect(serie['id'], startsWith('variante:'));
        expect(serie['groesse'], 2, reason: 'das Original liegt dahinter');
        expect(
          (await aufServer()).where((z) => z['name'] == 'IMG_0701.JPG'),
          hasLength(1),
          reason: 'im Raster nur die Bearbeitung',
        );
        expect((await lauf().laufe()).hochgeladen, 0, reason: 'nichts doppelt');

        // Noch einmal bearbeitet: wieder auf die Hauptversion.
        final zweite = server.jpeg('IMG_0701_bearbeitet.jpg', 150);
        rolle.bearbeitetesFoto('g', roh, zweite, geaendert: DateTime(2025, 8));
        await lauf().laufe();
        final zuletzt = await zeile('IMG_0701.JPG');
        expect(zuletzt['id'], id);
        expect(await original(id), zweite.readAsBytesSync());
        expect((zuletzt['serie'] as Map)['groesse'], 3);
      },
    );

    test('Original und Bearbeitung im selben Lauf', () async {
      final roh = server.jpeg('IMG_0702.JPG', 60);
      final bearbeitung = server.jpeg('IMG_0702_bearbeitet.jpg', 210);
      rolle.bearbeitetesFoto('h', roh, bearbeitung);
      final r = await lauf().laufe();
      expect(r.hochgeladen, 1);
      final z = await zeile('IMG_0702.JPG');
      expect(await original(z['id'] as String), bearbeitung.readAsBytesSync());
      expect((z['serie'] as Map)['groesse'], 2);
    });

    test(
      'ohne bekanntes Original wird die Datei gewöhnlich aufgenommen',
      () async {
        final datei = server.jpeg('IMG_0703_bearbeitet.jpg', 15);
        final kopf = await TusHochladen(telefon).lade(
          datei,
          'api/v1/hochladen',
          {'filename': 'IMG_0703_bearbeitet.jpg', 'bearbeitungVon': 'a' * 64},
        );
        expect(kopf['pv-ausgang'], 'imported');
        expect((await zeile('IMG_0703_bearbeitet.jpg'))['serie'], isNull);
      },
    );
  });
}
