import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Eine Zuordnung zurücknehmen.
///
/// Zuordnen ist der meistbenutzte Handgriff der Personenansicht, und
/// „Ähnliche mit auswählen" ordnet eine ganze Gruppe auf einen Klick zu.
/// Dabei ändert sich mehr als eine Spalte: Beiseitegelegtes wird
/// zurückgeholt, das Titelbild der Person gesetzt, Rückmeldungen für die
/// lernende Wiedererkennung abgelegt und deren Schwelle verschoben. Ein
/// Rückgängig, das nur `person_id` leert, ist keines.
void main() {
  const allgemein = 0.363;
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> asset(String id) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: id,
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
          ));

  Future<void> gesicht(String id,
          {String? person, bool ignoriert = false}) async =>
      db.insertFace(FacesCompanion.insert(
        id: id,
        assetId: 'a1',
        personId: Value(person),
        isIgnored: Value(ignoriert),
        boxX: 0.1,
        boxY: 0.1,
        boxW: 0.2,
        boxH: 0.2,
        cropRelativePath: Value('faces/$id.jpg'),
      ));

  Future<FaceData> liesGesicht(String id) =>
      (db.select(db.faces)..where((t) => t.id.equals(id))).getSingle();

  Future<PersonData?> liesPerson(String id) =>
      (db.select(db.people)..where((t) => t.id.equals(id))).getSingleOrNull();

  test('die Gesichter kehren in ihren vorherigen Zustand zurück', () async {
    await asset('a1');
    await gesicht('frei');                       // gehörte niemandem
    await gesicht('fremd', person: 'p9');        // gehörte jemand anderem
    await gesicht('weg', ignoriert: true);       // war beiseitegelegt
    await db.createPerson(PeopleCompanion.insert(id: 'p9', name: 'Berta'));
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anton'));

    final ids = ['frei', 'fremd', 'weg'];
    final vorher = await db.gesichtsstand(ids);
    await db.assignFacesToPerson(ids, 'p1');

    // Zwischenprobe: die Zuordnung hat wirklich gewirkt.
    expect((await liesGesicht('weg')).personId, 'p1');
    expect((await liesGesicht('weg')).isIgnored, isFalse);

    await db.nimmZuordnungZurueck(
      gesichter: vorher,
      personId: 'p1',
      personWarNeu: false,
      titelbildVorher: null,
      rueckmeldungenSeit: null,
      allgemeineSchwelle: allgemein,
    );

    expect((await liesGesicht('frei')).personId, isNull);
    expect((await liesGesicht('fremd')).personId, 'p9',
        reason: 'ein fremdes Gesicht gehört wieder seiner Person');
    expect((await liesGesicht('weg')).personId, isNull);
    expect((await liesGesicht('weg')).isIgnored, isTrue,
        reason: 'beiseitegelegt bleibt beiseitegelegt');
  });

  test('eine eigens angelegte Person verschwindet wieder', () async {
    await asset('a1');
    await gesicht('f1');
    await db.createPerson(PeopleCompanion.insert(id: 'neu', name: 'Caesar'));

    final vorher = await db.gesichtsstand(['f1']);
    await db.assignFacesToPerson(['f1'], 'neu');
    expect(await liesPerson('neu'), isNotNull);

    await db.nimmZuordnungZurueck(
      gesichter: vorher,
      personId: 'neu',
      personWarNeu: true,
      titelbildVorher: null,
      rueckmeldungenSeit: null,
      allgemeineSchwelle: allgemein,
    );

    expect(await liesPerson('neu'), isNull,
        reason: 'sonst bliebe ein leerer Name in der Liste stehen');
    expect((await liesGesicht('f1')).personId, isNull);
  });

  test('das Titelbild einer bestehenden Person bleibt, wie es war', () async {
    await asset('a1');
    await gesicht('f1');
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anton'));
    expect((await liesPerson('p1'))!.coverFaceCropPath, isNull);

    final vorher = await db.gesichtsstand(['f1']);
    await db.assignFacesToPerson(['f1'], 'p1');
    expect((await liesPerson('p1'))!.coverFaceCropPath, 'faces/f1.jpg',
        reason: 'die Zuordnung setzt ein fehlendes Titelbild');

    await db.nimmZuordnungZurueck(
      gesichter: vorher,
      personId: 'p1',
      personWarNeu: false,
      titelbildVorher: null,
      rueckmeldungenSeit: null,
      allgemeineSchwelle: allgemein,
    );

    expect((await liesPerson('p1'))!.coverFaceCropPath, isNull,
        reason: 'sonst zeigte die Person ein Gesicht, das ihr nicht gehört');
  });

  test('die gelernte Schwelle geht mit zurück', () async {
    await asset('a1');
    await gesicht('f1');
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anton'));

    // Eine ältere, echte Rückmeldung, die bleiben muss.
    await db.merkeGesichtsEntscheidungen(
      'p1',
      [(faceId: 'alt', accepted: true, similarity: 0.9)],
      allgemeineSchwelle: allgemein,
    );
    final schwelleVorher = (await liesPerson('p1'))!.similarityThreshold;

    final vorher = await db.gesichtsstand(['f1']);
    await db.assignFacesToPerson(['f1'], 'p1');
    final seit = await db.merkeGesichtsEntscheidungen(
      'p1',
      [(faceId: 'f1', accepted: true, similarity: 0.31)],
      allgemeineSchwelle: allgemein,
    );
    expect(seit, isNotNull);
    expect((await db.gesichtsRueckmeldungen('p1')).length, 2);

    await db.nimmZuordnungZurueck(
      gesichter: vorher,
      personId: 'p1',
      personWarNeu: false,
      titelbildVorher: null,
      rueckmeldungenSeit: seit,
      allgemeineSchwelle: allgemein,
    );

    final rueck = await db.gesichtsRueckmeldungen('p1');
    expect(rueck.length, 1,
        reason: 'nur die zurückgenommene Entscheidung faellt weg');
    expect(rueck.single.aehnlichkeit, 0.9);
    expect((await liesPerson('p1'))!.similarityThreshold, schwelleVorher,
        reason: 'die Schwelle stammt wieder aus den verbliebenen Rückmeldungen');
  });
}
