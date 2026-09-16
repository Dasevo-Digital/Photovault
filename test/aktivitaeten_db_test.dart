import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/aktivitaeten.dart';

/// Aktivitäten in der Datenbank.
///
/// Der Dienst in aktivitaeten_test.dart erkennt sie; hier geht es um das,
/// was erst zusammen sichtbar wird – und vor allem um die eine Stelle,
/// an der sie sich von den Reisen unterscheiden: Eine Aktivität **darf**
/// ohne Reise dastehen.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(String id, DateTime zeit,
          {bool papierkorb = false, bool gesperrt = false}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: zeit,
            importedAt: DateTime(2024),
            isTrashed: Value(papierkorb),
            isLocked: Value(gesperrt),
          ));

  Future<void> aktivitaetMit(
    String id,
    List<String> assetIds, {
    String name = 'Brocken',
    Aktivitaetsart art = Aktivitaetsart.wanderung,
    String? reiseId,
    DateTime? von,
  }) =>
      db.aktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: id,
          name: name,
          art: art.kennung,
          von: von ?? DateTime(2024, 6, 3, 9),
          bis: (von ?? DateTime(2024, 6, 3, 9)).add(const Duration(hours: 5)),
          reiseId: Value(reiseId),
          angelegtAm: DateTime(2024, 7, 1),
        ),
        assetIds,
      );

  test('die Datenbank steht auf der Fassung, die der Quelltext angibt',
      () async {
    final fassung = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(fassung, db.schemaVersion);
    expect(fassung, greaterThanOrEqualTo(54),
        reason: 'Die Aktivitäten-Tabellen kamen mit Fassung 54.');
  });

  test('die Indizes der Fassung 54 stehen auf einer frischen Datenbank',
      () async {
    // Rohes SQL – ein Tippfehler darin fällt `flutter analyze` nicht auf.
    final namen = {
      for (final z in await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
          .get())
        z.data['name'] as String
    };
    expect(namen, contains('idx_aktivitaet_aufnahme_asset'));
    expect(namen, contains('idx_aktivitaeten_reise'));
  });

  test('eine Aktivität entsteht samt ihren Aufnahmen', () async {
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await aufnahme('a2', DateTime(2024, 6, 3, 12));
    await aktivitaetMit('k1', ['a1', 'a2']);

    final k = (await db.alleAktivitaeten()).single;
    expect(k.name, 'Brocken');
    expect(Aktivitaetsart.aus(k.art), Aktivitaetsart.wanderung);
    expect((await db.aufnahmenDerAktivitaet('k1')).map((a) => a.id),
        ['a1', 'a2']);
  });

  test('eine halb angelegte Aktivität gibt es nicht', () async {
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await expectLater(
      aktivitaetMit('k1', ['a1', 'a1']),
      throwsA(anything),
    );
    expect(await db.alleAktivitaeten(), isEmpty);
    expect(await db.zugeordneteAktivitaetsAufnahmen(), isEmpty);
  });

  test('sie darf ohne Reise dastehen – das ist der Unterschied', () async {
    // Die Sonntagswanderung vor der Haustür braucht keine Reise.
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await aktivitaetMit('k1', ['a1']);
    expect((await db.alleAktivitaeten()).single.reiseId, isNull);
    expect((await db.aktivitaetenOhneReise()).map((k) => k.id), ['k1']);
  });

  test('mit Reise steht sie in deren Liste und nicht mehr in der freien',
      () async {
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await aufnahme('a2', DateTime(2024, 6, 5, 10));
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: 'Harz',
        von: DateTime(2024, 6, 1),
        bis: DateTime(2024, 6, 8),
        angelegtAm: DateTime(2024, 7, 1),
      ),
      ['a1', 'a2'],
    );
    await aktivitaetMit('k1', ['a1'], reiseId: 'r1');
    await aktivitaetMit('k2', ['a2'], von: DateTime(2024, 8, 1, 9));

    expect((await db.aktivitaetenDerReise('r1')).map((k) => k.id), ['k1']);
    expect((await db.aktivitaetenOhneReise()).map((k) => k.id), ['k2']);
  });

  test('innerhalb einer Reise stehen sie vorwärts, in der freien Liste rückwärts',
      () async {
    // Innerhalb einer Reise liest man vorwärts – erster Tag zuerst, wie
    // die Tageskapitel daneben. In einer Liste über Jahre will man das
    // Jüngste oben.
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await aufnahme('a2', DateTime(2024, 6, 5, 10));
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: 'Harz',
        von: DateTime(2024, 6, 1),
        bis: DateTime(2024, 6, 8),
        angelegtAm: DateTime(2024, 7, 1),
      ),
      ['a1', 'a2'],
    );
    await aktivitaetMit('frueh', ['a1'],
        reiseId: 'r1', von: DateTime(2024, 6, 3, 9));
    await aktivitaetMit('spaet', ['a2'],
        reiseId: 'r1', von: DateTime(2024, 6, 5, 9));
    expect((await db.aktivitaetenDerReise('r1')).map((k) => k.id),
        ['frueh', 'spaet']);

    await aufnahme('b1', DateTime(2025, 1, 1, 10));
    await aufnahme('b2', DateTime(2025, 2, 1, 10));
    await aktivitaetMit('alt', ['b1'], von: DateTime(2025, 1, 1, 9));
    await aktivitaetMit('neu', ['b2'], von: DateTime(2025, 2, 1, 9));
    expect((await db.aktivitaetenOhneReise()).map((k) => k.id), ['neu', 'alt']);
  });

  test('Papierkorb und gesperrte Bilder fallen aus der Liste', () async {
    await aufnahme('gut', DateTime(2024, 6, 3, 10));
    await aufnahme('weg', DateTime(2024, 6, 3, 11), papierkorb: true);
    await aufnahme('zu', DateTime(2024, 6, 3, 12), gesperrt: true);
    await aktivitaetMit('k1', ['gut', 'weg', 'zu']);
    expect((await db.aufnahmenDerAktivitaet('k1')).map((a) => a.id), ['gut']);
    expect((await db.ersteAufnahmeDerAktivitaet('k1'))?.id, 'gut');
  });

  test('Löschen räumt die Zuordnungen mit weg', () async {
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await aktivitaetMit('k1', ['a1']);
    await db.aktivitaetLoeschen('k1');
    expect(await db.alleAktivitaeten(), isEmpty);
    expect(await db.zugeordneteAktivitaetsAufnahmen(), isEmpty);
    // Das Foto selbst bleibt – eine Aktivität ist eine Sicht auf Bilder,
    // kein Behälter für sie.
    expect(await db.assetById('a1'), isNotNull);
  });

  test('ein abgelehnter Vorschlag bleibt abgelehnt', () async {
    await db.verwirfAktivitaetsvorschlag('a1');
    expect(await db.verworfeneAktivitaetsvorschlaege(), {'a1'});
    // Zweimal ablehnen ist kein Fehler.
    await db.verwirfAktivitaetsvorschlag('a1');
    expect(await db.verworfeneAktivitaetsvorschlaege(), {'a1'});
  });

  test('reiseJeAufnahme liefert die Zuordnung, die der Dienst braucht',
      () async {
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await aufnahme('a2', DateTime(2024, 6, 5, 10));
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: 'Harz',
        von: DateTime(2024, 6, 1),
        bis: DateTime(2024, 6, 8),
        angelegtAm: DateTime(2024, 7, 1),
      ),
      ['a1'],
    );
    expect(await db.reiseJeAufnahme(), {'a1': 'r1'});
  });

  test('eine unbekannte Art wird zu „Sonstiges" statt zu werfen', () async {
    // Eine Zeile aus einer neueren Fassung soll nicht die ganze Liste
    // zum Absturz bringen.
    await aufnahme('a1', DateTime(2024, 6, 3, 10));
    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: 'k1',
        name: 'Etwas',
        art: 'gleitschirmflug',
        von: DateTime(2024, 6, 3, 9),
        bis: DateTime(2024, 6, 3, 14),
        angelegtAm: DateTime(2024, 7, 1),
      ),
      ['a1'],
    );
    expect(Aktivitaetsart.aus((await db.alleAktivitaeten()).single.art),
        Aktivitaetsart.sonstiges);
  });
}
