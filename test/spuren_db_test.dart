import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/aktivitaeten.dart';
import 'package:photo_vault/services/gpx.dart';

/// Aufgezeichnete Spuren in der Datenbank.
///
/// Bis Fassung 55 wurde eine GPX-Datei gelesen und weggeworfen – sie
/// diente einmalig dem Verorten von Fotos. Hier geht es um das, was
/// danach von ihr bleibt.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aktivitaet(String id) => db.aktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: id,
          name: 'Brocken',
          art: Aktivitaetsart.wanderung.kennung,
          von: DateTime(2024, 6, 3, 9),
          bis: DateTime(2024, 6, 3, 14),
          angelegtAm: DateTime(2024, 7, 1),
        ),
        const [],
      );

  Future<void> spur(String id,
      {String? aktivitaetId,
      String? reiseId,
      int punkte = 5,
      bool hoehen = true}) {
    final roh = <Rohpunkt>[
      for (var i = 0; i < punkte; i++)
        (
          zeit: DateTime.utc(2024, 6, 3, 9).add(Duration(minutes: i * 10)),
          breite: 52.37,
          laenge: 9.73 + i / 68.0,
          hoehe: hoehen ? 100.0 + i * 20 : null,
        ),
    ];
    final z = spurkennzahlen(roh);
    return db.spurAnlegen(
      SpurenCompanion.insert(
        id: id,
        name: 'wanderung.gpx',
        quelle: '/tmp/wanderung.gpx',
        aktivitaetId: Value(aktivitaetId),
        reiseId: Value(reiseId),
        von: Value(z.von),
        bis: Value(z.bis),
        punktzahl: z.punktzahl,
        laengeKm: z.laengeKm,
        aufstieg: Value(z.aufstieg),
        abstieg: Value(z.abstieg),
        angelegtAm: DateTime(2024, 7, 1),
      ),
      [
        for (final (i, p) in roh.indexed)
          SpurpunkteCompanion.insert(
            spurId: id,
            nummer: i,
            breite: p.breite,
            laenge: p.laenge,
            hoehe: Value(p.hoehe),
            zeit: Value(p.zeit),
          ),
      ],
    );
  }

  test('die Datenbank steht auf der Fassung, die der Quelltext angibt',
      () async {
    final fassung = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(fassung, db.schemaVersion);
    expect(fassung, greaterThanOrEqualTo(55),
        reason: 'Die Spur-Tabellen kamen mit Fassung 55.');
  });

  test('die Indizes der Fassung 55 stehen auf einer frischen Datenbank',
      () async {
    final namen = {
      for (final z in await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
          .get())
        z.data['name'] as String
    };
    expect(namen, contains('idx_spurpunkte_spur'));
    expect(namen, contains('idx_spuren_aktivitaet'));
  });

  test('eine Spur entsteht samt ihren Punkten', () async {
    await spur('s1');
    final s = (await db.alleSpuren()).single;
    expect(s.punktzahl, 5);
    expect(s.laengeKm, closeTo(4.0, 0.2));
    expect(s.aufstieg, isNotNull);
    expect(await db.punkteDerSpur('s1'), hasLength(5));
  });

  test('die Punkte kommen in der Reihenfolge der Datei zurück', () async {
    // Nach der Nummer und nicht nach der Zeit: Eine geplante Route hat
    // gar keine Zeit.
    await spur('s1');
    final punkte = await db.punkteDerSpur('s1');
    expect(punkte.map((p) => p.nummer), [0, 1, 2, 3, 4]);
    expect(punkte.first.laenge, lessThan(punkte.last.laenge));
  });

  test('sie darf ohne Aktivität dastehen und zu einer gehören', () async {
    await aktivitaet('k1');
    await spur('frei');
    await spur('gebunden', aktivitaetId: 'k1');

    expect((await db.spurenDerAktivitaet('k1')).map((s) => s.id),
        ['gebunden']);
    expect(await db.alleSpuren(), hasLength(2));
  });

  test('ohne Höhen bleibt der Aufstieg leer', () async {
    // Null Meter und „keine Angabe" sind zweierlei.
    await spur('s1', hoehen: false);
    final s = (await db.alleSpuren()).single;
    expect(s.aufstieg, isNull);
    expect(s.abstieg, isNull);
    expect(s.laengeKm, greaterThan(0));
  });

  test('Löschen räumt die Punkte mit weg', () async {
    await spur('s1');
    await db.spurLoeschen('s1');
    expect(await db.alleSpuren(), isEmpty);
    expect(await db.punkteDerSpur('s1'), isEmpty);
  });

  test('zehntausend Punkte gehen als Stapel durch', () async {
    // Eine Aufzeichnung hat schnell so viele; zehntausend einzelne
    // Einfügungen wären zehntausend Schreibvorgänge.
    final uhr = Stopwatch()..start();
    await db.spurAnlegen(
      SpurenCompanion.insert(
        id: 'gross',
        name: 'lang.gpx',
        quelle: '/tmp/lang.gpx',
        punktzahl: 10000,
        laengeKm: 42,
        angelegtAm: DateTime(2024, 7, 1),
      ),
      [
        for (var i = 0; i < 10000; i++)
          SpurpunkteCompanion.insert(
            spurId: 'gross',
            nummer: i,
            breite: 52.37 + i * 0.00001,
            laenge: 9.73,
            hoehe: Value(100.0 + (i % 50)),
          ),
      ],
    );
    uhr.stop();
    expect(await db.punkteDerSpur('gross'), hasLength(10000));
    // Kein Zeitlimit als Zusicherung – die Zahl steht hier, damit ein
    // Einbruch auffällt, wenn jemand den Stapel auflöst.
    // ignore: avoid_print
    print('10.000 Punkte in ${uhr.elapsedMilliseconds} ms geschrieben');
  });

  test('eine halb angelegte Spur gibt es nicht', () async {
    await expectLater(
      db.spurAnlegen(
        SpurenCompanion.insert(
          id: 's1',
          name: 'x.gpx',
          quelle: '/tmp/x.gpx',
          punktzahl: 2,
          laengeKm: 1,
          angelegtAm: DateTime(2024, 7, 1),
        ),
        [
          SpurpunkteCompanion.insert(
              spurId: 's1', nummer: 0, breite: 52.0, laenge: 9.0),
          SpurpunkteCompanion.insert(
              spurId: 's1', nummer: 0, breite: 52.1, laenge: 9.1),
        ],
      ),
      throwsA(anything),
    );
    expect(await db.alleSpuren(), isEmpty);
  });

  group('Eine Spur an einer Reise', () {
    Future<void> reise(String id) => db.reiseAnlegen(
          ReisenCompanion.insert(
            id: id,
            name: 'Harz',
            von: DateTime(2024, 6, 1),
            bis: DateTime(2024, 6, 8),
            angelegtAm: DateTime(2024, 7, 1),
          ),
          const [],
        );

    test('sie haengt an der Reise und nicht an einer Aktivitaet', () async {
      await reise('r1');
      await spur('s1', reiseId: 'r1');
      final anDerReise = await db.spurenDerReise('r1');
      expect(anDerReise, hasLength(1));
      expect(anDerReise.first.aktivitaetId, isNull);
    });

    test('eine Reise darf mehrere tragen - eine je Tag', () async {
      // Der Grund fuer die Mehrzahl: Eine Wanderung hat eine Spur, eine
      // Reise ueber zehn Tage hat zehn Dateien.
      await reise('r1');
      await spur('s1', reiseId: 'r1');
      await spur('s2', reiseId: 'r1');
      expect(await db.spurenDerReise('r1'), hasLength(2));
    });

    test('die beiden Sorten zaehlen einander nicht mit', () async {
      // Das ist der ganze Grund fuer zwei Spalten statt einer mit einer
      // Artangabe daneben: Wer die zweite Bedingung vergisst, bekommt
      // sonst die Spuren der jeweils anderen Sorte dazu.
      await reise('r1');
      await aktivitaet('k1');
      await spur('s1', reiseId: 'r1');
      await spur('s2', aktivitaetId: 'k1');
      expect(await db.spurenDerReise('r1'), hasLength(1));
      expect(await db.spurenDerAktivitaet('k1'), hasLength(1));
      expect((await db.spurenDerReise('r1')).first.id, 's1');
      expect((await db.spurenDerAktivitaet('k1')).first.id, 's2');
    });

    test('eine Spur ohne beides gehoert zu keinem von beiden', () async {
      await reise('r1');
      await aktivitaet('k1');
      await spur('s1');
      expect(await db.spurenDerReise('r1'), isEmpty);
      expect(await db.spurenDerAktivitaet('k1'), isEmpty);
    });

    test('das Loeschen nimmt die Punkte mit', () async {
      await reise('r1');
      await spur('s1', reiseId: 'r1', punkte: 7);
      expect(await db.punkteDerSpur('s1'), hasLength(7));
      await db.spurLoeschen('s1');
      expect(await db.spurenDerReise('r1'), isEmpty);
      expect(await db.punkteDerSpur('s1'), isEmpty);
    });
  });
}
