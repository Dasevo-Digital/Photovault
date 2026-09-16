import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/embedding_codec.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Derselbe Vorschlag, jedes Mal neu gerechnet.**
///
/// `personenvorschlag()` laeuft bei jedem Tippen auf ein Gesicht, beim
/// Oeffnen des Infoblatts und bei jedem Schritt durch die
/// Gesichter-Durchsicht. Sie bildete dafuer jedes Mal die Kerne aller
/// benannten Personen neu – an der echten Bibliothek 2366 Einbettungen
/// zu je 512 Zahlen, **62 ms warm und 507 ms beim ersten Mal**.
///
/// Gemerkt werden darf so etwas nur, wenn es auch wieder verfaellt. Die
/// Frage dieses Tests ist deshalb nicht „ist es schneller", sondern:
/// Sieht der naechste Vorschlag, was eben zugeordnet wurde?
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;
  var laufend = 0;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_kerne_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));
  });

  tearDown(() async {
    library.dispose();
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Uint8List vektor(List<double> werte) =>
      blobFromEmbeddingFloats(Float32List.fromList(werte));

  Future<void> foto(String id) => db.into(db.assets).insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 5, 1),
          importedAt: DateTime(2026, 5, 1),
        ),
      );

  Future<String> gesicht(String assetId, List<double> einbettung,
      {String? personId}) async {
    final id = 'g${laufend++}';
    await db.into(db.faces).insert(FacesCompanion.insert(
          id: id,
          assetId: assetId,
          boxX: 0,
          boxY: 0,
          boxW: 1,
          boxH: 1,
          personId: Value(personId),
          embedding: Value(vektor(einbettung)),
        ));
    return id;
  }

  Future<String> person(String name) async {
    final id = 'p_$name';
    await db
        .into(db.people)
        .insert(PeopleCompanion.insert(id: id, name: name));
    return id;
  }

  test('ohne benannte Person gibt es nichts vorzuschlagen', () async {
    await foto('a');
    await gesicht('a', [1, 0, 0]);
    expect(await library.personenvorschlag(vektor([1, 0, 0])), isNull);
  });

  test('der naechste Vorschlag sieht, was eben zugeordnet wurde', () async {
    final anna = await person('Anna');
    await foto('a');
    final neues = await gesicht('a', [1, 0, 0]);

    // Noch gehoert das Gesicht niemandem: kein Kern, kein Vorschlag.
    expect(await library.personenvorschlag(vektor([1, 0, 0])), isNull);

    await db.assignFacesToPerson([neues], anna);

    // Ohne Verfall stuende hier weiter „niemand" – der Vorrat ist aber
    // mit der Zuordnung weggefallen.
    final vorschlag = await library.personenvorschlag(vektor([0.99, 0.01, 0]));
    expect(vorschlag?.id, anna);
  });

  test('eine weggenommene Zuordnung verschwindet auch aus den Kernen',
      () async {
    final anna = await person('Anna');
    await foto('a');
    final eines = await gesicht('a', [1, 0, 0], personId: anna);
    expect((await library.personenvorschlag(vektor([1, 0, 0])))?.id, anna);

    await (db.update(db.faces)..where((t) => t.id.equals(eines)))
        .write(const FacesCompanion(personId: Value(null)));

    expect(await library.personenvorschlag(vektor([1, 0, 0])), isNull,
        reason: 'ohne Einbettung gibt es keinen Kern mehr');
  });

  test('ein umgehaengtes Gesicht aendert die Zahl nicht – und wird bemerkt',
      () async {
    final anna = await person('Anna');
    final berta = await person('Berta');
    await foto('a');
    final eines = await gesicht('a', [1, 0, 0], personId: anna);
    await gesicht('a', [0, 0, 1], personId: berta);

    expect((await library.personenvorschlag(vektor([1, 0, 0])))?.id, anna);

    // Dieselbe Anzahl zugeordneter Gesichter, dieselben Zeilen – nur
    // gehoert das eine jetzt jemand anderem.
    await db.assignFacesToPerson([eines], berta);

    expect((await library.personenvorschlag(vektor([1, 0, 0])))?.id, berta,
        reason: 'der Vorrat haette das Umhaengen sonst verschlafen');
  });

  test('eine verschobene Schwelle wird bemerkt, ohne dass ein Gesicht '
      'angefasst wird', () async {
    final anna = await person('Anna');
    await foto('a');
    await gesicht('a', [1, 0, 0], personId: anna);

    // Weit entfernt, aber ueber der allgemeinen Vorgabe von 0,363.
    expect((await library.personenvorschlag(vektor([0.8, 0.6, 0])))?.id, anna);

    // Eine Ablehnung schiebt die persoenliche Schwelle hoch – und
    // ruehrt dabei kein einziges Gesicht an.
    await (db.update(db.people)..where((t) => t.id.equals(anna)))
        .write(const PeopleCompanion(similarityThreshold: Value(0.95)));

    expect(await library.personenvorschlag(vektor([0.8, 0.6, 0])), isNull,
        reason: 'die neue Schwelle muss sofort gelten');
  });

  test('ein umbenannter Vorschlag traegt den neuen Namen', () async {
    final anna = await person('Anna');
    await foto('a');
    await gesicht('a', [1, 0, 0], personId: anna);
    expect((await library.personenvorschlag(vektor([1, 0, 0])))?.name, 'Anna');

    await (db.update(db.people)..where((t) => t.id.equals(anna)))
        .write(const PeopleCompanion(name: Value('Anna Meier')));

    expect((await library.personenvorschlag(vektor([1, 0, 0])))?.name,
        'Anna Meier',
        reason: 'der Name gehoert nicht in den Vorrat');
  });

  test('[ausser] laesst genau eine Person aus, ohne den Vorrat zu leeren',
      () async {
    final anna = await person('Anna');
    final berta = await person('Berta');
    await foto('a');
    await gesicht('a', [1, 0, 0], personId: anna);
    await gesicht('a', [0, 1, 0], personId: berta);

    expect((await library.personenvorschlag(vektor([1, 0, 0])))?.id, anna);
    expect(
        await library.personenvorschlag(vektor([1, 0, 0]), ausser: anna),
        isNull,
        reason: 'Berta ist nicht aehnlich genug');
    // Und danach gilt der Vorrat unveraendert weiter.
    expect((await library.personenvorschlag(vektor([1, 0, 0])))?.id, anna);
  });
}
