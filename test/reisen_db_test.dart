import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/reisen.dart';

/// Reisen in der Datenbank.
///
/// Der Dienst in reisen_test.dart erkennt sie; hier geht es um das, was
/// erst zusammen sichtbar wird: dass eine Reise ohne ihre Aufnahmen gar
/// nicht erst entsteht, dass ein abgelehnter Vorschlag abgelehnt bleibt
/// und dass die Erkennung genau die Aufnahmen bekommt, die sie braucht.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(
    String id,
    DateTime zeit, {
    double? breite,
    double? laenge,
    String? stadt,
    String? land,
    bool papierkorb = false,
  }) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: zeit,
            importedAt: DateTime(2024),
            latitude: Value(breite),
            longitude: Value(laenge),
            locationCity: Value(stadt),
            locationCountry: Value(land),
            isTrashed: Value(papierkorb),
          ));

  Future<void> reiseMit(String id, List<String> assetIds,
          {String name = 'Rom'}) =>
      db.reiseAnlegen(
        ReisenCompanion.insert(
          id: id,
          name: name,
          von: DateTime(2024, 6, 3),
          bis: DateTime(2024, 6, 10),
          angelegtAm: DateTime(2024, 7, 1),
        ),
        assetIds,
      );

  test('die Datenbank steht auf der Fassung, die der Quelltext angibt',
      () async {
    // Gegen [AppDatabase.schemaVersion] und nicht gegen eine
    // hineingeschriebene Zahl: Der Test soll bemerken, wenn eine Migration
    // nicht läuft – nicht, wenn eine neue dazukommt. Vorher stand hier
    // eine 51, und die naechste Fassung liess ihn fallen, obwohl an den
    // Reisen nichts kaputt war.
    final fassung = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(fassung, db.schemaVersion);
    expect(fassung, greaterThanOrEqualTo(51),
        reason: 'Die Reisen-Tabellen kamen mit Fassung 51.');
  });

  test('eine Reise entsteht samt ihren Aufnahmen', () async {
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await aufnahme('a2', DateTime(2024, 6, 4, 10));
    await reiseMit('r1', ['a1', 'a2']);

    expect((await db.alleReisen()).single.name, 'Rom');
    expect((await db.aufnahmenDerReise('r1')).map((a) => a.id), ['a1', 'a2']);
  });

  test('eine halb angelegte Reise gibt es nicht', () async {
    // Eine Reise ohne ihre Aufnahmen saehe aus wie eine leere Reise, und
    // niemand koennte hinterher sagen, ob sie so gemeint war. Hier
    // scheitert die zweite Zuordnung an derselben Kennung.
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await expectLater(
      db.reiseAnlegen(
        ReisenCompanion.insert(
          id: 'r1',
          name: 'Rom',
          von: DateTime(2024, 6, 3),
          bis: DateTime(2024, 6, 4),
          angelegtAm: DateTime(2024, 7, 1),
        ),
        ['a1', 'a1'],
      ),
      throwsA(anything),
    );
    expect(await db.alleReisen(), isEmpty);
    expect(await db.zugeordneteReiseAufnahmen(), isEmpty);
  });

  test('die Aufnahmen kommen chronologisch, ohne Papierkorb', () async {
    // Eine Reise soll nicht auf Bilder verweisen, die es nicht mehr gibt.
    await aufnahme('spaet', DateTime(2024, 6, 8, 10));
    await aufnahme('frueh', DateTime(2024, 6, 3, 10));
    await aufnahme('weg', DateTime(2024, 6, 5, 10), papierkorb: true);
    await reiseMit('r1', ['spaet', 'frueh', 'weg']);

    expect((await db.aufnahmenDerReise('r1')).map((a) => a.id),
        ['frueh', 'spaet']);
  });

  test('Loeschen nimmt die Zuordnungen mit', () async {
    // Sonst bliebe je Reise ein Satz verwaister Zeilen zurueck, und die
    // Aufnahmen zaehlten weiter als „schon zugeordnet".
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await reiseMit('r1', ['a1']);
    await db.reiseLoeschen('r1');

    expect(await db.alleReisen(), isEmpty);
    expect(await db.zugeordneteReiseAufnahmen(), isEmpty);
  });

  test('eine Aufnahme laesst sich nachtragen und wieder herausnehmen',
      () async {
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await aufnahme('a2', DateTime(2024, 6, 4, 10));
    await reiseMit('r1', ['a1']);

    await db.aufnahmenZurReise('r1', ['a2']);
    expect(await db.zugeordneteReiseAufnahmen(), {'a1', 'a2'});
    // Zweimal dasselbe darf nicht werfen – der Nutzer soll nicht wissen
    // muessen, was schon drin ist.
    await db.aufnahmenZurReise('r1', ['a2']);
    expect((await db.aufnahmenDerReise('r1')), hasLength(2));

    await db.aufnahmeAusReise('r1', 'a2');
    expect((await db.aufnahmenDerReise('r1')).single.id, 'a1');
  });

  test('ein abgelehnter Vorschlag bleibt abgelehnt', () async {
    await db.verwirfReisevorschlag('a1');
    expect(await db.verworfeneReisevorschlaege(), {'a1'});
    // Zweimal ablehnen ist kein Fehler.
    await db.verwirfReisevorschlag('a1');
    expect(await db.verworfeneReisevorschlaege(), hasLength(1));
  });

  test('der gesperrte Ordner bleibt aus allen Reise-Abfragen heraus',
      () async {
    // Belegt, bevor es behoben wurde: Eine gesperrte Aufnahme stand im
    // Raster der Reise, nahm an der Erkennung teil und zaehlte im
    // Laenderzaehler mit. Der gesperrte Ordner ist mit einer PIN
    // geschuetzt – was dort liegt, darf ausserhalb nicht auftauchen, und
    // ein Land, das nur auf gesperrten Fotos vorkommt, sagt „da war
    // jemand".
    await aufnahme('offen', DateTime(2024, 6, 3, 10),
        breite: 41.9, laenge: 12.5, stadt: 'Roma', land: 'Italien');
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: 'gesperrt',
          originalFileName: 'gesperrt.jpg',
          relativePath: 'originals/gesperrt.jpg',
          checksum: 'pruef-gesperrt',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024, 6, 4, 10),
          importedAt: DateTime(2024),
          latitude: const Value(41.9),
          longitude: const Value(12.5),
          locationCity: const Value('Roma'),
          locationCountry: const Value('Italien'),
          isLocked: const Value(true),
        ));
    await reiseMit('r1', ['offen', 'gesperrt']);

    expect((await db.aufnahmenDerReise('r1')).map((a) => a.id), ['offen']);
    expect(
        (await db.aufnahmenFuerReiseerkennung()).map((a) => a.id), ['offen']);
    expect((await db.besuchteOrte()).single.anzahl, 1);
  });

  test('auch unverortete gesperrte Aufnahmen bleiben draussen', () async {
    // Sie waeren sonst der Umweg: ueber das Auffuellen erkannter Reisen
    // landeten sie doch im Raster.
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: 'gesperrt',
          originalFileName: 'g.jpg',
          relativePath: 'originals/g.jpg',
          checksum: 'pruef-g',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024, 6, 3),
          importedAt: DateTime(2024),
          isLocked: const Value(true),
        ));
    await aufnahme('offen', DateTime(2024, 6, 3));
    expect((await db.aufnahmenOhneKoordinate()).map((a) => a.id), ['offen']);
  });

  test('die Erkennung bekommt nur verortete, lebende Aufnahmen', () async {
    await aufnahme('mitOrt', DateTime(2024, 6, 3, 10),
        breite: 41.9, laenge: 12.5, stadt: 'Roma', land: 'Italien');
    await aufnahme('ohneOrt', DateTime(2024, 6, 4, 10));
    await aufnahme('imPapierkorb', DateTime(2024, 6, 5, 10),
        breite: 41.9, laenge: 12.5, papierkorb: true);

    final roh = await db.aufnahmenFuerReiseerkennung();
    expect(roh.map((a) => a.id), ['mitOrt']);
    expect(roh.single.stadt, 'Roma');
    expect(roh.single.land, 'Italien');
  });

  test('der ganze Weg: erkennen, bestaetigen, nicht erneut vorschlagen',
      () async {
    // Hamburg als Wohnort, eine Woche Rom.
    for (var t = 0; t < 60; t++) {
      await aufnahme('h$t', DateTime(2024, 1, 1).add(Duration(days: t)),
          breite: 53.55, laenge: 9.99, stadt: 'Hamburg', land: 'Deutschland');
    }
    for (var t = 0; t < 6; t++) {
      for (var i = 0; i < 4; i++) {
        await aufnahme('r$t-$i',
            DateTime(2024, 6, 3, 9, i * 10).add(Duration(days: t)),
            breite: 41.9, laenge: 12.5, stadt: 'Roma', land: 'Italien');
      }
    }

    final roh = await db.aufnahmenFuerReiseerkennung();
    final vorschlaege = erkenneReisen([
      for (final a in roh)
        (
          id: a.id,
          zeit: a.zeit,
          breite: a.breite,
          laenge: a.laenge,
          land: a.land,
          region: a.region,
          stadt: a.stadt,
        ),
    ], ohneOrt: 'Unbekannt');
    expect(vorschlaege, hasLength(1));
    expect(vorschlaege.single.name, 'Roma');
    expect(vorschlaege.single.anzahl, 24);

    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: vorschlaege.single.name,
        von: vorschlaege.single.von,
        bis: vorschlaege.single.bis,
        angelegtAm: DateTime(2024, 7, 1),
      ),
      vorschlaege.single.aufnahmeIds,
    );

    // Zweiter Durchgang: Die bestaetigte Reise darf nicht noch einmal
    // vorgeschlagen werden.
    final erneut = erkenneReisen([
      for (final a in roh)
        (
          id: a.id,
          zeit: a.zeit,
          breite: a.breite,
          laenge: a.laenge,
          land: a.land,
          region: a.region,
          stadt: a.stadt,
        ),
    ],
        ohneOrt: 'Unbekannt',
        bekannteIds: await db.zugeordneteReiseAufnahmen());
    expect(erneut, isEmpty);
  });
}
