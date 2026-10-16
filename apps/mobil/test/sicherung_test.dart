import 'dart:io';

import 'package:drift/native.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault_mobil/lokal/ungesichert.dart';
import 'package:photo_vault_mobil/sicherung/freigabe.dart';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_mobil/sicherung/kamerarolle.dart';
import 'package:photo_vault_mobil/sicherung/lauf.dart';
import 'package:photo_vault_mobil/sicherung/stand.dart';

import 'hilfen/testserver.dart';

/// Eine Kamerarolle aus Dateien – was `photo_manager` am Telefon liefert,
/// ohne Telefon.
class _Rolle implements Kamerarolle {
  final eintraege_ = <Rolleneintrag>[];
  var aufgeraeumt = 0;

  void foto(String id, File datei, {DateTime? geaendert}) =>
      eintraege_.insert(0, _eintrag(id, [('bild', datei)], geaendert));

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

  static Rolleneintrag _eintrag(
    String id,
    List<(String, File)> teile,
    DateTime? geaendert,
  ) => Rolleneintrag(
    id: id,
    geaendert: geaendert ?? DateTime(2025, 6, 1),
    aufgenommen: DateTime(2025, 6, 1, 12),
    video: false,
    dateien: () async => [
      for (final (teil, datei) in teile)
        Rollendatei(teil: teil, name: p.basename(datei.path), datei: datei),
    ],
  );

  @override
  Future<List<Rolleneintrag>> eintraege({required bool videos}) async => [
    ...eintraege_,
  ];

  @override
  Future<void> aufraeumen() async => aufgeraeumt++;

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

  test('nie zwei Läufe zugleich', () async {
    rolle.foto('f', server.jpeg('IMG_0401.JPG', 140));
    expect(stand.sperre('hintergrund'), isTrue);
    await expectLater(lauf().laufe(), throwsA(isA<Gesperrt>()));
    stand.gibFrei('hintergrund');
    expect((await lauf().laufe()).hochgeladen, 1);
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
}
