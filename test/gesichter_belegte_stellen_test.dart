import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/auswertung/auswertungen.dart';
import 'package:kern/auswertung/modelle.dart';
import 'package:kern/auswertung/rechenhilfe.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// „Gesichter scannen – Alle“ löscht die unbenannten Erkennungen eines
/// Fotos und erkennt neu. Benannte und beiseitegelegte Gesichter bleiben
/// stehen – und ihre Stellen dürfen kein zweites, unbenanntes Gesicht
/// bekommen. Bis zur Prüfung KI-059 galt das nur für beiseitegelegte: Über
/// dem Gesicht von „Person A“ entstand eine neue Erkennung mit demselben
/// Rahmen, dasselbe Gesicht stand als Person A und als Unbekannt da.
void main() {
  late Directory temp;
  late AppDatabase db;
  late Auswertungen auswertungen;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_belegt_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'lib')),
    );
    auswertungen = Auswertungen(db: db, paths: paths, modelle: Modelle());
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'foto',
            originalFileName: 'foto.jpg',
            relativePath: 'originals/foto.jpg',
            checksum: 'foto',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
          ),
        );
    await db.createPerson(PeopleCompanion.insert(id: 'a', name: 'A'));
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<void> gesicht(
    String id,
    double x, {
    String? person,
    bool ignoriert = false,
  }) => db.insertFace(
    FacesCompanion.insert(
      id: id,
      assetId: 'foto',
      personId: Value(person),
      isIgnored: Value(ignoriert),
      boxX: x,
      boxY: 0.2,
      boxW: 0.2,
      boxH: 0.25,
    ),
  );

  Gesichtsfund fund(double x) => Gesichtsfund(
    x: x,
    y: 0.2,
    breite: 0.2,
    hoehe: 0.25,
    schaerfe: 1,
    ausschnitt: Uint8List.fromList([1, 2, 3]),
  );

  test(
    'benannte und beiseitegelegte Stellen bekommen kein zweites Gesicht',
    () async {
      await gesicht('person_a', 0.05, person: 'a');
      await gesicht('plakat', 0.4, ignoriert: true);

      // Wie nach dem Löschen der unbenannten Erkennungen: Die Erkennung
      // findet alle drei Gesichter wieder.
      final foto = (await db.assetById('foto'))!;
      await auswertungen.speichereGesichter(foto, [
        fund(0.05),
        fund(0.4),
        fund(0.75),
      ]);

      final alle = await db.facesForAsset('foto');
      expect(alle, hasLength(3));
      final neue = alle.where((f) => f.id != 'person_a' && f.id != 'plakat');
      expect(neue, hasLength(1));
      expect(neue.single.boxX, 0.75);
      expect(neue.single.personId, isNull);
    },
  );

  test(
    'die belegten Stellen umfassen benannte, beiseitegelegte und unbenannte',
    () async {
      await gesicht('person_a', 0.05, person: 'a');
      await gesicht('plakat', 0.4, ignoriert: true);
      await gesicht('offen', 0.75);
      final stellen = await auswertungen.belegteGesichtsstellen('foto');
      expect(stellen.map((s) => s.x), unorderedEquals([0.05, 0.4, 0.75]));
    },
  );
}
