import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';

/// Ein Foto von der Gesichtssuche ausnehmen.
///
/// **Warum das nicht dasselbe ist wie ein ignoriertes Gesicht:** Ein
/// einzelnes Gesicht beiseitezulegen hilft nur, solange der nächste
/// Durchlauf dieselbe Stelle findet. Auf einer Gemäldewand, einem
/// Zeitungsfoto oder einem Plakat findet er jedes Mal andere – und legt
/// sie als neue, unbenannte Gesichter ab.
/// Die Fassung, auf die diese App migriert – aus einer frisch angelegten
/// Datenbank abgelesen statt als Zahl hingeschrieben.
///
/// Eine feste Nummer im Test bricht bei jedem Schemaschritt, und zwar an
/// einer Stelle, die mit dem Schritt nichts zu tun hat (so geschehen bei
/// 56 -> 57).
Future<int> aktuelleFassung() async {
  final frisch = AppDatabase(NativeDatabase.memory());
  final v = await frisch
      .customSelect('PRAGMA user_version')
      .map((r) => r.read<int>('user_version'))
      .getSingle();
  await frisch.close();
  return v;
}

void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pv_ausnahme_');
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<void> foto(String id, {bool gescannt = false, bool gesperrt = false}) =>
      db.insertAsset(AssetsCompanion.insert(
        id: id,
        relativePath: 'originals/$id.jpg',
        originalFileName: '$id.jpg',
        type: 'IMAGE',
        checksum: id,
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
        facesScanned: Value(gescannt),
        isLocked: Value(gesperrt),
      ));

  Future<Set<String>> zumScan({required bool nurNeue}) async =>
      {for (final a in await db.assetsForFaceScan(onlyNew: nurNeue)) a.id};

  test('die Vorgabe nimmt niemanden aus', () async {
    await foto('a');
    expect((await db.assetById('a'))!.faceScanExcluded, isFalse);
    expect(await zumScan(nurNeue: false), {'a'});
  });

  test('ein ausgenommenes Foto faellt aus BEIDEN Laeufen', () async {
    // **Der Kern.** Bei „nur neue" half schon `facesScanned`; die Ausnahme
    // wird erst bei „alle erneut durchsuchen" gebraucht – dort setzte sich
    // der Lauf bisher ueber alles hinweg.
    await foto('gemaeldewand', gescannt: true);
    await foto('normal', gescannt: true);
    await db.setzeGesichtssucheAusgenommen('gemaeldewand', true);

    expect(await zumScan(nurNeue: false), {'normal'},
        reason: 'auch beim vollstaendigen Durchlauf uebersprungen');
    expect(await zumScan(nurNeue: true), isEmpty,
        reason: 'beide sind bereits gescannt');

    expect(await db.countFaceScan(onlyNew: false), 1,
        reason: 'die Zaehlung muss dieselbe Menge meinen wie die Abfrage');
  });

  test('die Ausnahme laesst sich zuruecknehmen', () async {
    await foto('a', gescannt: true);
    await db.setzeGesichtssucheAusgenommen('a', true);
    expect(await zumScan(nurNeue: false), isEmpty);

    await db.setzeGesichtssucheAusgenommen('a', false);
    expect(await zumScan(nurNeue: false), {'a'});
  });

  test('sie trifft nur das gemeinte Foto', () async {
    // Gegenprobe gegen ein `where`, das fuer alle Zeilen gilt.
    await foto('a');
    await foto('b');
    await db.setzeGesichtssucheAusgenommen('a', true);
    expect(await zumScan(nurNeue: false), {'b'});
  });

  test('erkannte Gesichter bleiben stehen', () async {
    // Die Ausnahme gilt dem Suchen, nicht dem Gefundenen – wer sie setzt,
    // will keine Zuordnungen verlieren.
    await foto('a');
    await db.insertFace(FacesCompanion.insert(
      id: 'f1', assetId: 'a', boxX: .1, boxY: .1, boxW: .2, boxH: .2,
    ));
    await db.setzeGesichtssucheAusgenommen('a', true);
    expect(await db.facesForAsset('a'), hasLength(1));
  });

  test('Migration 56 auf 57 an einer bestehenden Datenbank', () async {
    final datei = File(p.join(temp.path, 'library.sqlite'));
    var alt = AppDatabase(NativeDatabase(datei));
    await alt.insertAsset(AssetsCompanion.insert(
      id: 'a', relativePath: 'o/a.jpg', originalFileName: 'a.jpg',
      type: 'IMAGE', checksum: 'a',
      fileCreatedAt: DateTime(2026), importedAt: DateTime(2026),
    ));
    await alt.customStatement('ALTER TABLE assets DROP COLUMN face_scan_excluded');
    await alt.customStatement('PRAGMA user_version = 56');
    await alt.close();

    final neu = AppDatabase(NativeDatabase(datei));
    final fassung = await neu.customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version')).getSingle();
    expect(fassung, await aktuelleFassung());
    expect((await neu.assetById('a'))!.faceScanExcluded, isFalse,
        reason: 'vorhandene Fotos bleiben in der Suche – die Ausnahme ist '
            'eine Entscheidung, keine Vorgabe');
    await neu.close();
  });
}
