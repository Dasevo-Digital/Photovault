import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Das Beiseitelegen von Gesichtern.
///
/// Der Sinn der Sache ist, dass eine Fehlerkennung – ein Plakat, eine
/// Spiegelung – dauerhaft aus dem Weg ist. Sie darf also weder im Raster
/// noch in der automatischen Gruppierung wieder auftauchen, und sie muss
/// einen erneuten Gesichts-Scan überleben. Genau das prüft diese Datei;
/// jeder einzelne dieser Wege hat schon einmal ein Ignorieren stillschweigend
/// rückgängig gemacht.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> asset(String id, {bool geloescht = false, bool gesperrt = false}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: id,
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
            isTrashed: Value(geloescht),
            isLocked: Value(gesperrt),
          ));

  Future<void> gesicht(String id, String assetId, {String? person}) =>
      db.insertFace(FacesCompanion.insert(
        id: id,
        assetId: assetId,
        personId: Value(person),
        boxX: 0.1,
        boxY: 0.1,
        boxW: 0.2,
        boxH: 0.2,
        cropRelativePath: Value('faces/$id.jpg'),
      ));

  test('ein beiseitegelegtes Gesicht verlässt das Raster', () async {
    await asset('a1');
    await gesicht('f1', 'a1');
    await gesicht('f2', 'a1');

    expect(await db.unassignedFaces(), hasLength(2));

    await db.setFacesIgnored(['f1'], true);

    expect((await db.unassignedFaces()).map((f) => f.id), ['f2']);
    expect((await db.ignoredFaces()).map((f) => f.id), ['f1']);
    expect(await db.ignoredFacesCount(), 1);
  });

  test('die automatische Gruppierung sieht es ebenfalls nicht mehr', () async {
    // allUnassignedFaces ist die Quelle des Clustering-Laufs. Liefe sie
    // ungefiltert, käme dieselbe Fehlerkennung bei jedem Lauf erneut als
    // Vorschlag zurück – und das Ignorieren wäre wirkungslos.
    await asset('a1');
    await gesicht('f1', 'a1');
    await gesicht('f2', 'a1');
    await db.setFacesIgnored(['f1'], true);

    expect((await db.allUnassignedFaces()).map((f) => f.id), ['f2']);
  });

  test('zurückholen stellt den vorherigen Zustand her', () async {
    await asset('a1');
    await gesicht('f1', 'a1');
    await db.setFacesIgnored(['f1'], true);
    await db.setFacesIgnored(['f1'], false);

    expect((await db.unassignedFaces()).map((f) => f.id), ['f1']);
    expect(await db.ignoredFaces(), isEmpty);
    expect(await db.ignoredFacesCount(), 0);
  });

  test('wer einem ignorierten Gesicht einen Namen gibt, holt es zurück', () async {
    // Sonst verschwände es unmittelbar nach dem Benennen wieder – die
    // Person hätte ein Foto, das nirgends auftaucht.
    await asset('a1');
    await gesicht('f1', 'a1');
    await db.setFacesIgnored(['f1'], true);
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));

    await db.assignFacesToPerson(['f1'], 'p1');

    final f = (await db.facesForAsset('a1')).single;
    expect(f.isIgnored, isFalse);
    expect(f.personId, 'p1');
    expect(await db.ignoredFacesCount(), 0);
  });

  test('beiseitelegen löst eine bestehende Zuordnung', () async {
    // Ein Gesicht, das zugleich „Anna" und „ignoriert" wäre, hinge zwischen
    // beiden Zuständen: gelistet unter Ignoriert, aber weiter in Annas
    // Fotos.
    await asset('a1');
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
    await gesicht('f1', 'a1', person: 'p1');

    await db.setFacesIgnored(['f1'], true);

    expect((await db.facesForPerson('p1')), isEmpty);
    expect(await db.ignoredFacesCount(), 1);
  });

  test('ein erneuter Scan löscht beiseitegelegte Gesichter nicht', () async {
    // deleteUnassignedFacesForAsset räumt vor einem Neu-Scan auf. Ohne die
    // Ausnahme wäre das Ignorieren beim ersten „alle Fotos erneut scannen"
    // spurlos weg.
    await asset('a1');
    await gesicht('f1', 'a1');
    await gesicht('f2', 'a1');
    await db.setFacesIgnored(['f1'], true);

    await db.deleteUnassignedFacesForAsset('a1');

    expect((await db.facesForAsset('a1')).map((f) => f.id), ['f1']);
  });

  test('gelöschte und gesperrte Fotos bleiben auch hier aussen vor', () async {
    // Dieselbe Absicherung wie im Raster: Sonst würde über den neuen Tab
    // ein Ausschnitt aus einem gesperrten Foto beiläufig sichtbar.
    await asset('a1', geloescht: true);
    await asset('a2', gesperrt: true);
    await asset('a3');
    await gesicht('f1', 'a1');
    await gesicht('f2', 'a2');
    await gesicht('f3', 'a3');
    await db.setFacesIgnored(['f1', 'f2', 'f3'], true);

    expect((await db.ignoredFaces()).map((f) => f.id), ['f3']);
    expect(await db.ignoredFacesCount(), 1);
  });

  test('die Zahl am Tab zählt mehr als die Liste zeigt', () async {
    // Die Liste ist bei 200 gedeckelt. Stünde die Listenlänge am Tab, hiesse
    // es dort „200", egal wie viel dort wirklich liegt.
    await asset('a1');
    for (var i = 0; i < 210; i++) {
      await gesicht('f$i', 'a1');
    }
    await db.setFacesIgnored([for (var i = 0; i < 210; i++) 'f$i'], true);

    expect(await db.ignoredFaces(), hasLength(200));
    expect(await db.ignoredFacesCount(), 210);
  });

  test('eine leere Liste ändert nichts', () async {
    await asset('a1');
    await gesicht('f1', 'a1');
    await db.setFacesIgnored([], true);
    expect(await db.ignoredFacesCount(), 0);
  });

  test('eine Datenbank von Schema 37 bekommt die Spalte nachgereicht', () async {
    final ordner = Directory.systemTemp.createTempSync('pv_ignoriert');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final datei = File(p.join(ordner.path, 'alt.sqlite'));

    // Vollständige Datenbank anlegen, mit Daten füllen, dann auf den Stand
    // vor der Änderung zurückversetzen: Spalte weg, Version zurückgestempelt.
    var alt = AppDatabase(NativeDatabase(datei));
    await alt.into(alt.assets).insert(AssetsCompanion.insert(
          id: 'a1',
          originalFileName: 'a1.jpg',
          relativePath: 'originals/a1.jpg',
          checksum: 'a1',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 1, 1),
          importedAt: DateTime(2026, 1, 1),
        ));
    await alt.insertFace(FacesCompanion.insert(
      id: 'f1',
      assetId: 'a1',
      boxX: 0.1,
      boxY: 0.1,
      boxW: 0.2,
      boxH: 0.2,
    ));
    await alt.close();

    final roh = sqlite.sqlite3.open(datei.path);
    // Der Teilindex hängt an der Spalte – erst er, dann sie.
    roh.execute('DROP INDEX IF EXISTS idx_faces_ignored;');
    roh.execute('ALTER TABLE faces DROP COLUMN is_ignored;');
    roh.execute('PRAGMA user_version = 37;');
    roh.close();

    // Öffnen löst die Migration auf 38 aus.
    final neu = AppDatabase(NativeDatabase(datei));
    final vorher = await neu.facesForAsset('a1');
    await neu.setFacesIgnored(['f1'], true);
    final anzahl = await neu.ignoredFacesCount();
    await neu.close();

    expect(vorher.single.isIgnored, isFalse,
        reason: 'bestehende Gesichter gelten als nicht beiseitegelegt');
    expect(anzahl, 1);
  });

  test('der Teilindex für die Zählung entsteht auch bei der Migration', () async {
    // Ohne ihn läuft die Zählung über alle Fotos statt über die wenigen
    // beiseitegelegten Gesichter – gemessen 8,3 ms statt 0,49 ms, und das
    // wächst mit der Bibliothek.
    final ordner = Directory.systemTemp.createTempSync('pv_ignoriert_idx');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final datei = File(p.join(ordner.path, 'alt.sqlite'));

    // Eine echte Abfrage, nicht nur öffnen und schliessen: Ohne sie legt
    // drift das Schema noch gar nicht an, und der Aufbau prüfte nichts.
    var alt = AppDatabase(NativeDatabase(datei));
    await alt.ignoredFacesCount();
    await alt.close();

    final roh = sqlite.sqlite3.open(datei.path);
    roh.execute('DROP INDEX IF EXISTS idx_faces_ignored;');
    roh.execute('ALTER TABLE faces DROP COLUMN is_ignored;');
    roh.execute('PRAGMA user_version = 37;');
    roh.close();

    final neu = AppDatabase(NativeDatabase(datei));
    await neu.ignoredFacesCount();
    await neu.close();

    final pruefung = sqlite.sqlite3.open(datei.path);
    final indizes = pruefung
        .select("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='faces';")
        .map((r) => r['name'] as String)
        .toList();
    pruefung.close();

    expect(indizes, contains('idx_faces_ignored'));
  });

  group('Massenaktionen aus dem Kontextmenü', () {
    test('alle ignorieren lässt benannte Gesichter unberührt', () async {
      // Der Sinn der Sache: Wer hunderte Fehlerkennungen wegräumt, darf
      // dabei nicht die Arbeit verlieren, die er schon investiert hat.
      await asset('a1');
      await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
      await gesicht('f1', 'a1', person: 'p1');
      await gesicht('f2', 'a1');
      await gesicht('f3', 'a1');

      expect(await db.ignoriereAlleUnbenannten(), 2);

      expect((await db.facesForPerson('p1')).map((f) => f.id), ['f1']);
      expect(await db.unassignedFaces(), isEmpty);
      expect(await db.ignoredFacesCount(), 2);
    });

    test('alle ignorieren meldet 0, wenn nichts offen ist', () async {
      await asset('a1');
      expect(await db.ignoriereAlleUnbenannten(), 0);
    });

    test('Erkennungen löschen nimmt auch die schon ignorierten mit', () async {
      // „Alle Erkennungen löschen" heisst alle – auch die, die vorher
      // aussortiert wurden. Sonst bliebe der Reiter „Ignoriert" nach dem
      // Löschen voll stehen.
      await asset('a1');
      await gesicht('f1', 'a1');
      await gesicht('f2', 'a1');
      await db.setFacesIgnored(['f1'], true);

      final ergebnis = await db.loescheAlleUnbenanntenErkennungen();

      expect(ergebnis.anzahl, 2);
      expect(await db.facesForAsset('a1'), isEmpty);
    });

    test('Erkennungen löschen lässt benannte Gesichter stehen', () async {
      await asset('a1');
      await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
      await gesicht('f1', 'a1', person: 'p1');
      await gesicht('f2', 'a1');

      final ergebnis = await db.loescheAlleUnbenanntenErkennungen();

      expect(ergebnis.anzahl, 1);
      expect((await db.facesForAsset('a1')).map((f) => f.id), ['f1']);
    });

    test('gezählt werden Erkennungen, geliefert nur vorhandene Ausschnitte',
        () async {
      // Ohne Embedding-Modell entsteht eine Zeile ohne Ausschnitt. Würde
      // der Aufrufer die Pfade zählen, meldete er zu wenige gelöschte
      // Erkennungen.
      await asset('a1');
      await gesicht('f1', 'a1');
      await db.insertFace(FacesCompanion.insert(
        id: 'f2',
        assetId: 'a1',
        boxX: 0.5,
        boxY: 0.5,
        boxW: 0.2,
        boxH: 0.2,
      ));

      final ergebnis = await db.loescheAlleUnbenanntenErkennungen();

      expect(ergebnis.anzahl, 2);
      expect(ergebnis.pfade, hasLength(1));
    });

    test('gesperrte und gelöschte Fotos bleiben von beidem verschont', () async {
      // Sonst räumte eine Massenaktion im gesperrten Ordner auf, ohne dass
      // dieser überhaupt entsperrt wäre.
      await asset('a1', gesperrt: true);
      await asset('a2', geloescht: true);
      await gesicht('f1', 'a1');
      await gesicht('f2', 'a2');

      expect(await db.ignoriereAlleUnbenannten(), 0);
      expect((await db.loescheAlleUnbenanntenErkennungen()).anzahl, 0);
      expect(await db.facesForAsset('a1'), hasLength(1));
      expect(await db.facesForAsset('a2'), hasLength(1));
    });

    test('die Zahl für die Rückfrage geht über das Anzeigelimit hinaus', () async {
      await asset('a1');
      for (var i = 0; i < 250; i++) {
        await gesicht('f$i', 'a1');
      }
      expect(await db.unassignedFaces(), hasLength(200));
      expect(await db.unassignedFacesCount(), 250);
    });
  });
}
