import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/gesichtsuebersicht.dart';

/// **Ein abgelehnter Vorschlag kam wieder** (PER-063, WEB-129).
///
/// Wer bei „Weitere Fotos“ ein Gesicht abwählte, hinterliess eine
/// Rückmeldung für die Schwelle der Person. Die Schwelle steigt aber
/// höchstens um 0,15 über die allgemeine, und die Suche nahm alle
/// unbenannten Gesichter darüber: Ein abgewähltes Gesicht mit hoher
/// Ähnlichkeit stand beim nächsten Mal wieder da – und der Lauf der
/// Wiedererkennung merkte es erneut für dieselbe Person vor.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'a1',
            originalFileName: 'a1.jpg',
            relativePath: 'originals/a1.jpg',
            checksum: 'c1',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026),
            importedAt: DateTime(2026),
          ),
        );
    await db.createPerson(PeopleCompanion.insert(id: 'anna', name: 'Anna'));
  });

  tearDown(() => db.close());

  var richtung = 2;
  Uint8List vektor(double aehnlichkeit) {
    final v = Float32List(128);
    v[1] = aehnlichkeit;
    v[richtung++] = math.sqrt(1 - aehnlichkeit * aehnlichkeit);
    return Uint8List.view(v.buffer);
  }

  Future<void> gesicht(String id, String? person, double s) => db
      .into(db.faces)
      .insert(
        FacesCompanion.insert(
          id: id,
          assetId: 'a1',
          personId: Value(person),
          boxX: 0.1,
          boxY: 0.1,
          boxW: 0.2,
          boxH: 0.2,
          embedding: Value(vektor(s)),
        ),
      );

  Future<void> abgelehnt(String faceId, double s) =>
      db.merkeGesichtsEntscheidungen('anna', [
        (faceId: faceId, accepted: false, similarity: s),
      ], allgemeineSchwelle: 0.36);

  test('„Weitere Fotos“ lässt das abgelehnte Gesicht aus', () async {
    await gesicht('f-anna', 'anna', 1);
    await gesicht('nah', null, 0.97);
    await gesicht('auch', null, 0.95);
    await abgelehnt('nah', 0.97);

    final w = await weitereFotosVon(db, 'anna');
    expect([for (final v in w!.vorschlaege) v.gesicht.id], ['auch']);
  });

  test(
    'ein später angenommenes Gesicht gilt nicht mehr als abgelehnt',
    () async {
      await gesicht('f', null, 0.9);
      await abgelehnt('f', 0.9);
      await db.merkeGesichtsEntscheidungen('anna', [
        (faceId: 'f', accepted: true, similarity: 0.9),
      ], allgemeineSchwelle: 0.36);
      expect(await db.abgelehnteGesichterFuer('anna'), isEmpty);
    },
  );

  test('die Wiedererkennung merkt es nicht wieder vor', () async {
    await gesicht('nah', null, 0.97);
    await gesicht('auch', null, 0.95);
    await abgelehnt('nah', 0.97);

    await db.merkeVorschlaege([
      (faceId: 'nah', personId: 'anna', wert: 0.97),
      (faceId: 'auch', personId: 'anna', wert: 0.95),
    ], uebernehmen: false);

    final vorgemerkt = await db.vorschlaegeFuerPerson('anna');
    expect([for (final v in vorgemerkt) v.gesicht.id], ['auch']);
  });
}
