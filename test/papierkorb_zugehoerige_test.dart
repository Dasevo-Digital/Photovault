import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';

/// Was ohne seine Hauptversion unsichtbar würde, geht mit ihr in den
/// Papierkorb und kommt mit ihr zurück (#254).
///
/// Das Raster zeigt keine Videohälften von Live Photos und von einem
/// Stapel nur das Titelbild. Bis 3.49.8 ging nur, was übergeben wurde: Die
/// übrigen Mitglieder standen danach weder im Papierkorb noch sonst
/// irgendwo, und nach dem Leeren blieben sie für immer verborgen.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(
    String id, {
    String typ = 'IMAGE',
    int tag = 1,
    String? partner,
  }) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.${typ == 'IMAGE' ? 'jpg' : 'mov'}',
          relativePath: 'originals/$id',
          checksum: 'c_$id',
          type: typ,
          fileCreatedAt: DateTime(2026, 1, tag),
          importedAt: DateTime(2026, 1, 1),
          linkedAssetId: Value(partner),
        ),
      );

  Future<List<String>> sichtbar() async =>
      [for (final a in await db.alleAufnahmen()) a.id]..sort();

  Future<List<String>> imPapierkorb() async =>
      [for (final a in await db.papierkorb()) a.id]..sort();

  group('Variantenstapel', () {
    setUp(() async {
      await aufnahme('haupt');
      await aufnahme('original');
      await aufnahme('einzeln');
      await db.fuehreAus(
        const VariantenBilden('v1', ['haupt', 'original'], 'haupt'),
      );
    });

    test('die Hauptversion nimmt ihre Varianten mit', () async {
      await db.fuehreAus(const InDenPapierkorb(['haupt']));

      expect(await sichtbar(), ['einzeln']);
      expect(await imPapierkorb(), ['haupt', 'original']);

      await db.fuehreAus(const AusDemPapierkorb(['haupt']));
      expect(await sichtbar(), ['einzeln', 'haupt']);
      expect(await imPapierkorb(), isEmpty);
    });

    test('eine verdeckte Variante holt ihre Hauptversion mit zurück', () async {
      await db.fuehreAus(const InDenPapierkorb(['haupt']));

      await db.fuehreAus(const AusDemPapierkorb(['original']));

      expect(await sichtbar(), ['einzeln', 'haupt']);
      expect(await imPapierkorb(), isEmpty);
    });

    test('eine schon vorher gelöschte Variante bleibt im Papierkorb', () async {
      await db.fuehreAus(const InDenPapierkorb(['original']));
      // Ein Tag früher: Wer sie einzeln gelöscht hat, wollte sie los sein.
      await (db.update(db.assets)..where((t) => t.id.equals('original'))).write(
        AssetsCompanion(trashedAt: Value(DateTime(2026, 1, 1))),
      );
      await db.fuehreAus(const InDenPapierkorb(['haupt']));

      await db.fuehreAus(const AusDemPapierkorb(['haupt']));

      expect(await sichtbar(), ['einzeln', 'haupt']);
      expect(await imPapierkorb(), ['original']);
    });

    test('nur eine verdeckte Variante zu löschen lässt den Rest', () async {
      await db.fuehreAus(const InDenPapierkorb(['original']));

      expect(await sichtbar(), ['einzeln', 'haupt']);
      expect(await imPapierkorb(), ['original']);
    });
  });

  test('eine Serie behält ihre anderen Bilder; eines rückt nach', () async {
    await aufnahme('a', tag: 1);
    await aufnahme('b', tag: 2);
    await aufnahme('c', tag: 3);
    await db.fuehreAus(const SerieBilden('serie-1', ['a', 'b', 'c'], 'b'));

    await db.fuehreAus(const InDenPapierkorb(['b']));

    expect(await sichtbar(), ['a'], reason: 'das früheste rückt nach');
    expect(await imPapierkorb(), ['b']);
    expect((await db.assetById('c'))!.isTrashed, isFalse);

    await db.fuehreAus(const AusDemPapierkorb(['b']));
    expect(await sichtbar(), ['a'], reason: 'b kommt als Mitglied zurück');
    expect(await db.assetsInStack('serie-1'), hasLength(3));
  });

  test('ein Live Photo geht samt Video und kommt samt Video zurück', () async {
    await aufnahme('foto', partner: 'video');
    await aufnahme('video', typ: 'VIDEO', partner: 'foto');

    await db.fuehreAus(const InDenPapierkorb(['foto']));
    expect(await imPapierkorb(), ['foto', 'video']);

    // Im Papierkorb stehen beide; wer das Video antippt, holt das Foto mit.
    await db.fuehreAus(const AusDemPapierkorb(['video']));
    expect(await imPapierkorb(), isEmpty);
    expect(await sichtbar(), ['foto']);
  });

  test('Zusammenführen von Duplikaten nimmt verdeckte Varianten mit', () async {
    await aufnahme('behalten');
    await aufnahme('haupt');
    await aufnahme('original');
    await db.fuehreAus(
      const VariantenBilden('v1', ['haupt', 'original'], 'haupt'),
    );

    await db.fuehreDuplikateZusammen(
      behaltenId: 'behalten',
      duplikatIds: ['haupt'],
    );

    expect(await sichtbar(), ['behalten']);
    expect(await imPapierkorb(), ['haupt', 'original']);
  });

  group('Reparatur des Bestands', () {
    Future<void> kaputt(String id, {bool papierkorb = false}) =>
        (db.update(db.assets)..where((t) => t.id.equals(id))).write(
          AssetsCompanion(
            isTrashed: Value(papierkorb),
            trashedAt: Value(papierkorb ? DateTime(2026, 10, 20, 19) : null),
          ),
        );

    test('bringt in Ordnung, was frühere Fassungen zurückliessen', () async {
      // Live Photo: Foto im Papierkorb, Video nicht – so wie bisher.
      await aufnahme('foto', partner: 'video');
      await aufnahme('video', typ: 'VIDEO', partner: 'foto');
      await kaputt('foto', papierkorb: true);
      // Ein Video, dessen Foto es nicht mehr gibt.
      await aufnahme('waise', typ: 'VIDEO', partner: 'gibtesnicht');
      // Variante hinter einer Hauptversion im Papierkorb.
      await aufnahme('haupt');
      await aufnahme('original');
      await db.createStack(variantenstapelId('v1'), [
        'haupt',
        'original',
      ], 'haupt');
      await kaputt('haupt', papierkorb: true);
      // Serie, deren Titelbild endgültig gelöscht ist.
      await aufnahme('s1', tag: 2);
      await aufnahme('s2', tag: 3);
      await db.createStack('serie-1', ['s1', 's2'], 's1');
      await db.deleteAssetRows(['s1']);

      expect(await sichtbar(), isEmpty);

      expect(await db.repariereVerdeckteZugehoerige(), 4);

      expect(await sichtbar(), ['s2']);
      expect(await imPapierkorb(), [
        'foto',
        'haupt',
        'original',
        'video',
        'waise',
      ]);
      final video = (await db.assetById('video'))!;
      expect(
        video.trashedAt,
        DateTime(2026, 10, 20, 19),
        reason: 'wie das Foto',
      );

      expect(await db.repariereVerdeckteZugehoerige(), 0, reason: 'nur einmal');
    });
  });
}
