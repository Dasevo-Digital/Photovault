import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/auswertung/auswertungen.dart';
import 'package:kern/auswertung/modelle.dart';
import 'package:kern/auswertung/nachbearbeitung.dart';
import 'package:kern/auswertung/rechenhilfe.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Live Photos werden über Name **und** Zeit verknüpft (#213). Das iPhone
/// zählt `IMG_0001` bis `IMG_9999` und beginnt dann von vorn; bis 3.47
/// gewann das erste unverknüpfte Foto gleichen Namens – auch eines aus
/// einem anderen Jahrzehnt.
void main() {
  late Directory temp;
  late AppDatabase db;
  late Nachbearbeitung nb;
  late StoragePaths paths;
  late Auswertungen auswertungen;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_livephoto_zeit_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
    auswertungen = Auswertungen(db: db, paths: paths, modelle: Modelle());
    nb = Nachbearbeitung(
      db: db,
      paths: paths,
      importe: () => ImportService(db, paths),
      auswertungen: auswertungen,
    );
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<AssetData> lege(
    String id,
    String name,
    String typ,
    DateTime zeit, {
    bool geschaetzt = false,
    String? verknuepft,
  }) async {
    await db.insertAsset(
      AssetsCompanion.insert(
        id: id,
        originalFileName: name,
        relativePath: 'originals/$id',
        checksum: id,
        type: typ,
        fileCreatedAt: zeit,
        importedAt: zeit,
        datumGeschaetzt: Value(geschaetzt),
        linkedAssetId: Value(verknuepft),
      ),
    );
    return (await db.assetById(id))!;
  }

  Future<String?> partner(String id) async =>
      (await db.assetById(id))!.linkedAssetId;

  final alt = DateTime(2013, 8, 3, 18, 31, 39);
  final neu = DateTime(2023, 5, 9, 18, 59, 19);

  test('gleicher Name: das zeitlich passende Foto gewinnt', () async {
    await lege('foto-2013', 'IMG_1712.JPG', 'IMAGE', alt);
    await lege('foto-2023', 'IMG_1712.JPG', 'IMAGE', neu);
    final video = await lege(
      'video',
      'IMG_1712.MOV',
      'VIDEO',
      neu.add(const Duration(seconds: 1)),
    );
    await nb.verknuepfeLivePhoto(video);
    expect(await partner('video'), 'foto-2023');
    expect(await partner('foto-2013'), isNull);
  });

  test('gleicher Name, aber Jahre auseinander: kein Paar', () async {
    await lege('foto-2013', 'IMG_1712.JPG', 'IMAGE', alt);
    final video = await lege('video', 'IMG_1712.MOV', 'VIDEO', neu);
    await nb.verknuepfeLivePhoto(video);
    expect(await partner('video'), isNull);
  });

  test('geschätztes Datum: dann zählt der Name allein', () async {
    await lege('foto', 'IMG_0042.HEIC', 'IMAGE', alt);
    final video = await lege(
      'video',
      'IMG_0042.MOV',
      'VIDEO',
      DateTime(2025, 8, 20, 8, 24),
      geschaetzt: true,
    );
    await nb.verknuepfeLivePhoto(video);
    expect(await partner('video'), 'foto');
  });

  test('die Reparatur löst falsche Paare und verknüpft richtig', () async {
    await lege('foto-2013', 'IMG_1712.JPG', 'IMAGE', alt, verknuepft: 'video');
    await lege('foto-2023', 'IMG_1712.JPG', 'IMAGE', neu);
    await lege('video', 'IMG_1712.MOV', 'VIDEO', neu, verknuepft: 'foto-2013');
    // Ein richtiges Paar bleibt, wie es ist.
    await lege(
      'ok-foto',
      'IMG_0100.HEIC',
      'IMAGE',
      neu,
      verknuepft: 'ok-video',
    );
    await lege('ok-video', 'IMG_0100.MOV', 'VIDEO', neu, verknuepft: 'ok-foto');

    expect(await nb.repariereLivePhotoPaare(), 1);
    expect(await partner('video'), 'foto-2023');
    expect(await partner('foto-2023'), 'video');
    expect(await partner('foto-2013'), isNull);
    expect(await partner('ok-video'), 'ok-foto');
  });

  // Ein Standbild unter einem `.MOV`-Namen galt früher als Video und hing
  // am gleichnamigen Foto. Seit es als Foto geführt wird, zeigte das
  // Raster beide – zwei Kacheln mit Live-Zeichen.
  test('zwei Fotos sind kein Live Photo: die Reparatur löst sie', () async {
    await lege('jpg', 'IMG_1712.JPG', 'IMAGE', neu, verknuepft: 'heic');
    await lege('heic', 'IMG_1712.MOV', 'IMAGE', neu, verknuepft: 'jpg');
    await lege(
      'ok-foto',
      'IMG_0100.HEIC',
      'IMAGE',
      neu,
      verknuepft: 'ok-video',
    );
    await lege('ok-video', 'IMG_0100.MOV', 'VIDEO', neu, verknuepft: 'ok-foto');

    expect(await nb.repariereLivePhotoPaare(), 1);
    expect(await partner('jpg'), isNull);
    expect(await partner('heic'), isNull);
    expect(await partner('ok-foto'), 'ok-video');
  });

  test('wer zum Foto wird, verliert seine Live-Photo-Verknüpfung', () async {
    await lege('foto', 'IMG_0042.JPG', 'IMAGE', neu, verknuepft: 'mov');
    await lege('mov', 'IMG_0042.MOV', 'VIDEO', neu, verknuepft: 'foto');

    await db.setzeDateiart('mov', 'IMAGE', dateiformat: 'heic');
    expect(await partner('mov'), isNull);
    expect(await partner('foto'), isNull);
  });

  group('Gesichter auf der Videohälfte (#226)', () {
    /// Ein Gesicht mit Ausschnitt auf der Platte.
    Future<File> gesicht(
      String id,
      String asset, {
      String? person,
      bool ignoriert = false,
    }) async {
      final relativ = paths.faceRelativePath(id);
      final datei = paths.absolute(relativ);
      await datei.create(recursive: true);
      await datei.writeAsBytes([1, 2, 3]);
      await db.insertFace(
        FacesCompanion.insert(
          id: id,
          assetId: asset,
          personId: Value(person),
          boxX: 0.4,
          boxY: 0.2,
          boxW: 0.2,
          boxH: 0.25,
          cropRelativePath: Value(relativ),
          isIgnored: Value(ignoriert),
        ),
      );
      return datei;
    }

    Future<void> paar() async {
      await lege('foto', 'IMG_5032.HEIC', 'IMAGE', neu, verknuepft: 'video');
      await lege('video', 'IMG_5032.MOV', 'VIDEO', neu, verknuepft: 'foto');
    }

    test('Doppel gehen, eine eigene Person bleibt', () async {
      await paar();
      for (final (id, name) in [('anna', 'Anna'), ('ben', 'Ben')]) {
        await db.createPerson(PeopleCompanion.insert(id: id, name: name));
      }
      final imFoto = await gesicht('f1', 'foto', person: 'anna');
      final doppel = await gesicht('v1', 'video', person: 'anna');
      final unbenannt = await gesicht('v2', 'video');
      final ignoriert = await gesicht('v3', 'video', ignoriert: true);
      // Ben steht nur im Video – das Standbild hat ihn übersehen.
      final eigen = await gesicht('v4', 'video', person: 'ben');
      await db.setPersonCoverIfUnset('anna', paths.faceRelativePath('v1'));

      expect(await nb.entferneLivePhotoVideoGesichter(), 3);

      final uebrig = {for (final f in await db.facesForAsset('video')) f.id};
      expect(uebrig, {'v4'});
      expect(await db.facesForAsset('foto'), hasLength(1));
      for (final weg in [doppel, unbenannt, ignoriert]) {
        expect(weg.existsSync(), isFalse, reason: 'Ausschnitt ohne Zeile');
      }
      expect(imFoto.existsSync(), isTrue);
      expect(eigen.existsSync(), isTrue);
      final anna = await (db.select(
        db.people,
      )..where((t) => t.id.equals('anna'))).getSingle();
      expect(
        anna.coverFaceCropPath,
        paths.faceRelativePath('f1'),
        reason: 'das Profilbild kommt aus dem Standbild',
      );
      expect((await db.assetById('video'))!.facesScanned, isTrue);
    });

    test('die Videohälfte bekommt keine neuen Gesichter', () async {
      await paar();
      expect(
        (await db.assetsForFaceScan(onlyNew: false)).map((a) => a.id),
        isNot(contains('video')),
      );
      expect(
        (await db.assetsForFaceScan(onlyNew: false)).map((a) => a.id),
        contains('foto'),
      );

      // Auch nicht, was ein anderer Rechner für sie gefunden hat.
      await auswertungen.speichereGesichter((await db.assetById('video'))!, [
        Gesichtsfund(
          x: 0.4,
          y: 0.2,
          breite: 0.2,
          hoehe: 0.25,
          schaerfe: 1,
          ausschnitt: Uint8List.fromList([1, 2, 3]),
        ),
      ]);
      expect(await db.facesForAsset('video'), isEmpty);
      expect((await db.assetById('video'))!.facesScanned, isTrue);
    });
  });
}
