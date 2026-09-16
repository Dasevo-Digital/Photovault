import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/stammbaum.dart';

/// Die Verwandtschaften in der Datenbank.
///
/// Geprüft wird hier vor allem, was die reine Logik nicht abdeckt: dass die
/// Prüfung auch wirklich vor dem Schreiben greift, dass eine Partnerschaft
/// unabhängig von der Eingaberichtung genau einmal entsteht und wieder
/// verschwindet, und dass das Zusammenführen zweier Personen keine Kanten
/// ins Leere hinterlässt.
void main() {
  late AppDatabase db;

  Future<void> person(String id, String name, {DateTime? geburt}) =>
      db.createPerson(PeopleCompanion.insert(
        id: id,
        name: name,
        geburtsdatum: Value(geburt),
      ));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (final (id, name) in [
      ('opa', 'Opa'),
      ('oma', 'Oma'),
      ('vater', 'Vater'),
      ('mutter', 'Mutter'),
      ('kind', 'Kind'),
    ]) {
      await person(id, name);
    }
  });

  tearDown(() => db.close());

  test('eine Elternkante lässt sich eintragen und wieder entfernen', () async {
    expect(await db.fuegeBeziehungHinzu('kind', 'vater', Verwandtschaft.elternteil), isNull);
    expect(await db.alleBeziehungen(), hasLength(1));

    await db.entferneBeziehung('kind', 'vater', Verwandtschaft.elternteil);
    expect(await db.alleBeziehungen(), isEmpty);
  });

  test('eine Partnerschaft entsteht einmal, egal in welcher Richtung', () async {
    expect(await db.fuegeBeziehungHinzu('vater', 'mutter', Verwandtschaft.partner), isNull);
    // Dieselbe Partnerschaft von der anderen Seite eingegeben.
    expect(await db.fuegeBeziehungHinzu('mutter', 'vater', Verwandtschaft.partner),
        Beziehungsfehler.schonVorhanden);
    expect(await db.alleBeziehungen(), hasLength(1));
  });

  test('und verschwindet auch von der anderen Seite aus wieder', () async {
    await db.fuegeBeziehungHinzu('vater', 'mutter', Verwandtschaft.partner);
    await db.entferneBeziehung('mutter', 'vater', Verwandtschaft.partner);
    expect(await db.alleBeziehungen(), isEmpty);
  });

  test('ein Kreis wird abgewiesen, nicht gespeichert', () async {
    await db.fuegeBeziehungHinzu('vater', 'opa', Verwandtschaft.elternteil);
    await db.fuegeBeziehungHinzu('kind', 'vater', Verwandtschaft.elternteil);

    expect(await db.fuegeBeziehungHinzu('opa', 'kind', Verwandtschaft.elternteil),
        Beziehungsfehler.kreis);
    expect(await db.alleBeziehungen(), hasLength(2),
        reason: 'nichts darf dazugekommen sein');
  });

  test('eine Person kann nicht ihr eigener Elternteil sein', () async {
    expect(await db.fuegeBeziehungHinzu('kind', 'kind', Verwandtschaft.elternteil),
        Beziehungsfehler.mitSichSelbst);
    expect(await db.alleBeziehungen(), isEmpty);
  });

  group('Zusammenführen', () {
    test('nimmt die Verwandtschaften der aufgelösten Person mit', () async {
      await person('vaterDoppelt', 'Vater (doppelt)');
      await db.fuegeBeziehungHinzu('vaterDoppelt', 'opa', Verwandtschaft.elternteil);
      await db.fuegeBeziehungHinzu('kind', 'vaterDoppelt', Verwandtschaft.elternteil);

      await db.mergePeople(keepPersonId: 'vater', removePersonId: 'vaterDoppelt');

      final netz = Verwandtschaftsnetz([
        for (final z in await db.alleBeziehungen())
          kante(z.personId, z.andereId, artAusText(z.art)!),
      ]);
      expect(netz.eltern('vater'), {'opa'});
      expect(netz.eltern('kind'), {'vater'});
      // Keine Kante darf auf die verschwundene Kennung zeigen – sie
      // erschiene im Stammbaum als namenlose Karte.
      final kennungen = await db.alleBeziehungen();
      expect(kennungen.any((z) => z.personId == 'vaterDoppelt' || z.andereId == 'vaterDoppelt'),
          isFalse);
    });

    test('erzeugt dabei keine Selbstbeziehung', () async {
      // Die beiden waren – falsch – als Vater und Kind eingetragen.
      await person('vaterDoppelt', 'Vater (doppelt)');
      await db.fuegeBeziehungHinzu('vaterDoppelt', 'vater', Verwandtschaft.elternteil);

      await db.mergePeople(keepPersonId: 'vater', removePersonId: 'vaterDoppelt');
      expect(await db.alleBeziehungen(), isEmpty);
    });

    test('legt eine bereits vorhandene Kante nicht doppelt an', () async {
      await person('vaterDoppelt', 'Vater (doppelt)');
      await db.fuegeBeziehungHinzu('vater', 'opa', Verwandtschaft.elternteil);
      await db.fuegeBeziehungHinzu('vaterDoppelt', 'opa', Verwandtschaft.elternteil);

      await db.mergePeople(keepPersonId: 'vater', removePersonId: 'vaterDoppelt');
      expect(await db.alleBeziehungen(), hasLength(1));
    });
  });

  test('Lebensdaten lassen sich setzen und wieder löschen', () async {
    await db.setzeLebensdaten('opa', geburt: DateTime(1931, 4, 2), tod: DateTime(2004, 11, 9));
    final geladen = await (db.select(db.people)..where((t) => t.id.equals('opa'))).getSingle();
    expect(geladen.geburtsdatum, DateTime(1931, 4, 2));
    expect(geladen.sterbedatum, DateTime(2004, 11, 9));

    await db.setzeLebensdaten('opa', geburt: null, tod: null);
    final leer = await (db.select(db.people)..where((t) => t.id.equals('opa'))).getSingle();
    expect(leer.geburtsdatum, isNull);
  });

  test('nachAlterSortiert stellt die Älteren voran und Unbekanntes ans Ende', () async {
    await db.setzeLebensdaten('opa', geburt: DateTime(1931), tod: null);
    await db.setzeLebensdaten('vater', geburt: DateTime(1960), tod: null);
    final personen = db.nachAlterSortiert(await db.select(db.people).get());
    expect(personen.first.id, 'opa');
    expect(personen[1].id, 'vater');
    // Der Rest ohne Geburtsdatum, alphabetisch.
    expect(personen.sublist(2).map((p) => p.name), ['Kind', 'Mutter', 'Oma']);
  });
}
