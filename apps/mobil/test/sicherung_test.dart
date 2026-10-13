import 'dart:io';
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
