import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/face_threshold.dart';

/// Das Gedächtnis der Wiedererkennung auf Datenbankseite: Entscheidungen
/// festhalten und die persönliche Schwelle daraus nachführen.
///
/// Die Herleitung selbst ist getrennt geprüft (face_threshold_test.dart);
/// hier geht es um das Zusammenspiel – vor allem darum, dass die
/// gespeicherte Zahl immer zu den Rückmeldungen passt, mit denen sie in der
/// Oberfläche begründet wird.
void main() {
  const allgemein = 0.363;
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> person(String id, String name) async {
    await db.createPerson(PeopleCompanion.insert(id: id, name: name));
    return id;
  }

  Future<PersonData> lies(String id) =>
      (db.select(db.people)..where((t) => t.id.equals(id))).getSingle();

  test('ohne Rückmeldungen hat eine Person keine eigene Schwelle', () async {
    await person('p1', 'Anna');
    expect((await lies('p1')).similarityThreshold, isNull);
    expect(await db.gesichtsRueckmeldungen('p1'), isEmpty);
  });

  test('Entscheidungen werden festgehalten und die Schwelle nachgeführt', () async {
    await person('p1', 'Anna');
    await db.merkeGesichtsEntscheidungen(
      'p1',
      [
        (faceId: 'f1', accepted: true, similarity: 0.5),
        (faceId: 'f2', accepted: true, similarity: 0.7),
        (faceId: 'f3', accepted: false, similarity: 0.4),
      ],
      allgemeineSchwelle: allgemein,
    );

    expect(await db.gesichtsRueckmeldungen('p1'), hasLength(3));
    // Saubere Trennung zwischen 0,4 und 0,5 – die Mitte ist 0,45.
    expect((await lies('p1')).similarityThreshold, closeTo(0.45, 1e-9));
  });

  test('die gespeicherte Zahl stimmt mit der angezeigten Herleitung überein',
      () async {
    // Wären das zwei getrennte Rechnungen, könnte die Oberfläche eine
    // andere Zahl begründen als die, nach der entschieden wird.
    await person('p1', 'Anna');
    await db.merkeGesichtsEntscheidungen(
      'p1',
      [
        (faceId: 'f1', accepted: true, similarity: 0.55),
        (faceId: 'f2', accepted: false, similarity: 0.3),
        (faceId: 'f3', accepted: false, similarity: 0.35),
      ],
      allgemeineSchwelle: allgemein,
    );

    final gespeichert = (await lies('p1')).similarityThreshold;
    final hergeleitet =
        leiteSchwelleAb(await db.gesichtsRueckmeldungen('p1'), allgemein);
    expect(gespeichert, hergeleitet);
  });

  test('widersprüchliche Belege lassen die Person bei der allgemeinen Schwelle',
      () async {
    await person('p1', 'Anna');
    await db.merkeGesichtsEntscheidungen(
      'p1',
      [
        (faceId: 'f1', accepted: true, similarity: 0.45),
        (faceId: 'f2', accepted: false, similarity: 0.6),
        (faceId: 'f3', accepted: true, similarity: 0.7),
      ],
      allgemeineSchwelle: allgemein,
    );

    expect((await lies('p1')).similarityThreshold, isNull,
        reason: 'genau die allgemeine Schwelle wird als "nichts Eigenes" '
            'gespeichert, damit sie später mitwandert');
  });

  test('Personen lernen unabhängig voneinander', () async {
    await person('p1', 'Anna');
    await person('p2', 'Bert');
    await db.merkeGesichtsEntscheidungen(
      'p1',
      [
        (faceId: 'f1', accepted: false, similarity: 0.5),
        (faceId: 'f2', accepted: false, similarity: 0.45),
        (faceId: 'f3', accepted: false, similarity: 0.2),
      ],
      allgemeineSchwelle: allgemein,
    );

    expect((await lies('p1')).similarityThreshold, isNotNull);
    expect((await lies('p2')).similarityThreshold, isNull);
    expect(await db.gesichtsRueckmeldungen('p2'), isEmpty);
  });

  test('spätere Entscheidungen verschieben die Schwelle weiter', () async {
    await person('p1', 'Anna');
    await db.merkeGesichtsEntscheidungen(
      'p1',
      [
        (faceId: 'f1', accepted: true, similarity: 0.5),
        (faceId: 'f2', accepted: true, similarity: 0.6),
        (faceId: 'f3', accepted: false, similarity: 0.3),
      ],
      allgemeineSchwelle: allgemein,
    );
    final vorher = (await lies('p1')).similarityThreshold;

    // Eine neue Ablehnung dicht unter der schwächsten Bestätigung.
    await db.merkeGesichtsEntscheidungen(
      'p1',
      [(faceId: 'f4', accepted: false, similarity: 0.48)],
      allgemeineSchwelle: allgemein,
    );

    expect(await db.gesichtsRueckmeldungen('p1'), hasLength(4));
    expect((await lies('p1')).similarityThreshold, greaterThan(vorher!));
  });

  test('Verwerfen löscht die Rückmeldungen und die eigene Schwelle', () async {
    await person('p1', 'Anna');
    await db.merkeGesichtsEntscheidungen(
      'p1',
      [
        (faceId: 'f1', accepted: true, similarity: 0.5),
        (faceId: 'f2', accepted: true, similarity: 0.6),
        (faceId: 'f3', accepted: false, similarity: 0.3),
      ],
      allgemeineSchwelle: allgemein,
    );
    expect((await lies('p1')).similarityThreshold, isNotNull);

    await db.vergissGesichtsEntscheidungen('p1');

    expect(await db.gesichtsRueckmeldungen('p1'), isEmpty);
    expect((await lies('p1')).similarityThreshold, isNull);
  });

  test('eine leere Liste schreibt nichts', () async {
    await person('p1', 'Anna');
    await db.merkeGesichtsEntscheidungen('p1', const [], allgemeineSchwelle: allgemein);
    expect(await db.gesichtsRueckmeldungen('p1'), isEmpty);
    expect((await lies('p1')).similarityThreshold, isNull);
  });

  group('Die allgemeine Schwelle', () {
    test('wird gespeichert und überlebt damit den Programmstart', () async {
      // Vorher lag sie nur im Speicher – der Regler stand nach jedem Start
      // wieder auf dem Ausgangswert, ohne dass das irgendwo stand.
      expect(await db.faceSimilarityThresholdWert(), closeTo(0.363, 1e-9));
      await db.setFaceSimilarityThreshold(0.45);
      expect(await db.faceSimilarityThresholdWert(), closeTo(0.45, 1e-9));
    });

    test('zieht die persönlichen Schwellen mit', () async {
      // Sonst hätte der Regler in den Werkzeugen für bereits gelernte
      // Personen keine Wirkung mehr.
      await person('p1', 'Anna');
      await db.merkeGesichtsEntscheidungen(
        'p1',
        [
          (faceId: 'f1', accepted: false, similarity: 0.9),
          (faceId: 'f2', accepted: false, similarity: 0.2),
          (faceId: 'f3', accepted: false, similarity: 0.1),
        ],
        allgemeineSchwelle: 0.363,
      );
      // Gedeckelt auf allgemein + 0,15.
      expect((await lies('p1')).similarityThreshold, closeTo(0.513, 1e-9));

      await db.setFaceSimilarityThreshold(0.5);
      expect((await lies('p1')).similarityThreshold, closeTo(0.65, 1e-9),
          reason: 'der Deckel bezieht sich auf die neue allgemeine Schwelle');
    });
  });

  test('das Zuordnen selbst schreibt keine Rückmeldung', () async {
    // Nur ein Vorschlag, über den entschieden wurde, ist eine Aussage über
    // die Erkennung. Eine von Hand benannte Person sagt nichts darüber,
    // ab welcher Ähnlichkeit hätte zugegriffen werden dürfen.
    await person('p1', 'Anna');
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: 'a1',
          originalFileName: 'a1.jpg',
          relativePath: 'originals/a1.jpg',
          checksum: 'c1',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024, 1, 1),
          importedAt: DateTime(2024, 1, 1),
        ));
    await db.insertFace(FacesCompanion.insert(
      id: 'f1',
      assetId: 'a1',
      boxX: 0,
      boxY: 0,
      boxW: 0.5,
      boxH: 0.5,
      personId: const Value(null),
    ));

    await db.assignFacesToPerson(['f1'], 'p1');

    expect(await db.gesichtsRueckmeldungen('p1'), isEmpty);
    expect((await lies('p1')).similarityThreshold, isNull);
  });
}
