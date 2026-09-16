import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/exif_camera.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/search_filters.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:uuid/uuid.dart';

/// Prüft die kombinierte Suchabfrage des Suchoptionen-Panels: jeder Filter
/// einzeln, dann in Kombination (UND-Verknüpfung über Kategorien hinweg,
/// UND-Verknüpfung innerhalb von Personen/Tags bei Mehrfachauswahl), sowie
/// dass gelöschte/gesperrte Assets nie auftauchen.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;
  var nextByte = 0;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_search_test_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    import = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<AssetData> importPhoto(String name) async {
    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
    final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3, nextByte++]);
    final result = await import.importFile(file.path);
    expect(result.outcome, ImportOutcome.imported);
    return (await db.assetById(result.assetId!))!;
  }

  Future<String> createPersonWithFace(String name, String assetId) async {
    final personId = const Uuid().v4();
    await db.createPerson(PeopleCompanion.insert(id: personId, name: name));
    // Bewusst nur die eine neu eingefügte Gesichts-ID zuweisen: würde man
    // stattdessen (wie ein früherer Entwurf dieses Helpers) ALLE Gesichter
    // des Assets neu zuweisen, würde ein zweiter Aufruf für dasselbe Asset
    // die Zuordnung des ersten Aufrufs überschreiben.
    final faceId = const Uuid().v4();
    await db.insertFace(FacesCompanion.insert(
      id: faceId,
      assetId: assetId,
      personId: const Value.absent(),
      boxX: 0,
      boxY: 0,
      boxW: 0.1,
      boxH: 0.1,
    ));
    await db.assignFacesToPerson([faceId], personId);
    return personId;
  }

  test('Dateiname-Filter findet nur passende Dateinamen', () async {
    final a = await importPhoto('urlaub_strand.jpg');
    await importPhoto('geburtstag.jpg');

    final results = await db.searchAssets(
      const SearchFilters(textMode: SearchTextMode.filename, query: 'strand'),
    );

    expect(results.map((r) => r.id), [a.id]);
  });

  test('Beschreibung-Filter durchsucht nur die Beschreibung, nicht den Dateinamen', () async {
    final a = await importPhoto('foto1.jpg');
    await db.setDescription(a.id, 'Sonnenaufgang am Strand');
    await importPhoto('strand.jpg'); // Dateiname enthält "strand", Beschreibung nicht

    final results = await db.searchAssets(
      const SearchFilters(textMode: SearchTextMode.description, query: 'sonnenaufgang'),
    );

    expect(results.map((r) => r.id), [a.id]);
  });

  test('KI-Beschreibung-Filter durchsucht nur die Caption, nicht Dateiname/Beschreibung', () async {
    final a = await importPhoto('foto1.jpg');
    await db.setAiCaption(a.id, 'a dog running on a beach');
    final b = await importPhoto('dog.jpg'); // Dateiname enthält den Begriff, aiCaption nicht
    await db.setAiCaption(b.id, '');

    final results = await db.searchAssets(
      const SearchFilters(textMode: SearchTextMode.caption, query: 'dog'),
    );

    expect(results.map((r) => r.id), [a.id]);
  });

  test('Kamera-Filter (Marke/Modell/Objektiv) filtert auf Gleichheit', () async {
    final canon = await importPhoto('a.jpg');
    await db.setCameraMetadata(canon.id, const CameraInfo(make: 'Canon', model: 'EOS R5'));
    final fuji = await importPhoto('b.jpg');
    await db.setCameraMetadata(fuji.id, const CameraInfo(make: 'FUJIFILM', model: 'X-T5'));

    final byMake = await db.searchAssets(const SearchFilters(cameraMake: 'Canon'));
    expect(byMake.map((r) => r.id), [canon.id]);

    final byModel = await db.searchAssets(const SearchFilters(cameraModel: 'X-T5'));
    expect(byModel.map((r) => r.id), [fuji.id]);
  });

  test('Zeitraum-Filter ist beidseitig inklusiv', () async {
    final inRange = await importPhoto('a.jpg');
    await db.setFileCreatedAt(inRange.id, DateTime(2026, 6, 15));
    final tooEarly = await importPhoto('b.jpg');
    await db.setFileCreatedAt(tooEarly.id, DateTime(2026, 5, 31, 23, 59));
    final tooLate = await importPhoto('c.jpg');
    await db.setFileCreatedAt(tooLate.id, DateTime(2026, 7, 1, 0, 1));
    final onBoundary = await importPhoto('d.jpg');
    await db.setFileCreatedAt(onBoundary.id, DateTime(2026, 6, 30, 23, 0));

    final results = await db.searchAssets(
      SearchFilters(startDate: DateTime(2026, 6, 1), endDate: DateTime(2026, 6, 30)),
    );

    expect(results.map((r) => r.id).toSet(), {inRange.id, onBoundary.id});
  });

  test('Favoriten-Filter findet nur markierte Favoriten', () async {
    final favImage = await importPhoto('a.jpg');
    await db.setFavorite(favImage.id, true);
    await importPhoto('b.jpg'); // kein Favorit

    final favorites = await db.searchAssets(const SearchFilters(favoritesOnly: true));
    expect(favorites.map((r) => r.id), [favImage.id]);
  });

  test('Medientyp-Filter "Bild" schließt Videos aus (hier: findet alle importierten Bilder)', () async {
    final a = await importPhoto('a.jpg');
    final b = await importPhoto('b.jpg');

    final images = await db.searchAssets(const SearchFilters(mediaType: MediaTypeFilter.image));

    expect(images.map((r) => r.id).toSet(), {a.id, b.id});
    expect(images.every((r) => r.type == 'IMAGE'), isTrue);
  });

  test('"In keinem Album" findet nur Fotos ohne Album-Zuordnung', () async {
    final inAlbum = await importPhoto('a.jpg');
    final notInAlbum = await importPhoto('b.jpg');
    await db.createAlbum(AlbumsCompanion.insert(id: 'album-1', name: 'Test', createdAt: DateTime.now()));
    await db.addAssetsToAlbum('album-1', [inAlbum.id]);

    final results = await db.searchAssets(const SearchFilters(notInAnyAlbum: true));

    expect(results.map((r) => r.id), [notInAlbum.id]);
  });

  test('Personen-Filter: mehrere ausgewählte Personen verlangen alle gemeinsam auf einem Foto', () async {
    final both = await importPhoto('both.jpg');
    final onlyAId = await importPhoto('only_a.jpg');

    final personA = await createPersonWithFace('A', both.id);
    final personB = await createPersonWithFace('B', both.id);
    await createPersonWithFace('A-again', onlyAId.id); // andere Person, nur um Gesicht zu haben

    // "only_a.jpg" bekommt zusätzlich ein Gesicht von personA, damit der
    // Test wirklich prüft: nur "both.jpg" hat BEIDE (personA und personB).
    await db.insertFace(FacesCompanion.insert(
      id: const Uuid().v4(),
      assetId: onlyAId.id,
      personId: const Value.absent(),
      boxX: 0,
      boxY: 0,
      boxW: 0.1,
      boxH: 0.1,
    ));
    final newFace = (await db.facesForAsset(onlyAId.id)).firstWhere((f) => f.personId == null);
    await db.assignFacesToPerson([newFace.id], personA);

    final singlePerson = await db.searchAssets(SearchFilters(personIds: [personA]));
    expect(singlePerson.map((r) => r.id).toSet(), {both.id, onlyAId.id});

    final bothPersons = await db.searchAssets(SearchFilters(personIds: [personA, personB]));
    expect(bothPersons.map((r) => r.id), [both.id]);
  });

  test('Tag-Filter: mehrere Tags verlangen alle gemeinsam, "Ohne Tag" findet nur untaggte Fotos', () async {
    final both = await importPhoto('both.jpg');
    final onlyUrlaub = await importPhoto('only_urlaub.jpg');
    final untagged = await importPhoto('untagged.jpg');

    await db.tagAsset(both.id, 'urlaub');
    await db.tagAsset(both.id, 'strand');
    await db.tagAsset(onlyUrlaub.id, 'urlaub');

    final urlaubTagId = (await db.tagsForAsset(both.id)).firstWhere((t) => t.name == 'urlaub').id;
    final strandTagId = (await db.tagsForAsset(both.id)).firstWhere((t) => t.name == 'strand').id;

    final singleTag = await db.searchAssets(SearchFilters(tagIds: [urlaubTagId]));
    expect(singleTag.map((r) => r.id).toSet(), {both.id, onlyUrlaub.id});

    final bothTags = await db.searchAssets(SearchFilters(tagIds: [urlaubTagId, strandTagId]));
    expect(bothTags.map((r) => r.id), [both.id]);

    final noTag = await db.searchAssets(const SearchFilters(noTag: true));
    expect(noTag.map((r) => r.id), [untagged.id]);
  });

  test('gelöschte und gesperrte Fotos tauchen nie in Suchergebnissen auf', () async {
    final normal = await importPhoto('normal.jpg');
    final trashed = await importPhoto('trashed.jpg');
    final locked = await importPhoto('locked.jpg');
    await db.moveToTrash([trashed.id]);
    await db.setAssetsLocked([locked.id], true);

    final results = await db.searchAssets(const SearchFilters(mediaType: MediaTypeFilter.all));

    expect(results.map((r) => r.id), [normal.id]);
  });

  test('restrictToIds schränkt zusätzlich zu den übrigen Filtern ein (für die KI-Suche)', () async {
    final a = await importPhoto('a.jpg');
    final b = await importPhoto('b.jpg');
    await db.setFavorite(a.id, true);
    await db.setFavorite(b.id, true);

    final results = await db.searchAssets(
      const SearchFilters(favoritesOnly: true),
      restrictToIds: [a.id],
    );

    expect(results.map((r) => r.id), [a.id]);
  });

  test('kombinierte Filter über mehrere Kategorien werden UND-verknüpft', () async {
    final match = await importPhoto('match.jpg');
    await db.setCameraMetadata(match.id, const CameraInfo(make: 'Canon'));
    await db.setFavorite(match.id, true);
    await db.tagAsset(match.id, 'urlaub');

    final wrongCamera = await importPhoto('wrong_camera.jpg');
    await db.setCameraMetadata(wrongCamera.id, const CameraInfo(make: 'Nikon'));
    await db.setFavorite(wrongCamera.id, true);
    await db.tagAsset(wrongCamera.id, 'urlaub');

    final notFavorite = await importPhoto('not_favorite.jpg');
    await db.setCameraMetadata(notFavorite.id, const CameraInfo(make: 'Canon'));
    await db.tagAsset(notFavorite.id, 'urlaub');

    final tagId = (await db.tagsForAsset(match.id)).first.id;
    final results = await db.searchAssets(SearchFilters(
      cameraMake: 'Canon',
      favoritesOnly: true,
      tagIds: [tagId],
    ));

    expect(results.map((r) => r.id), [match.id]);
  });

  test('distinctCameraMakes/-Models/-LensModels liefern sortierte, eindeutige, nicht-leere Werte', () async {
    final a = await importPhoto('a.jpg');
    await db.setCameraMetadata(a.id, const CameraInfo(make: 'Nikon', model: 'Z8', lensModel: '24-70mm'));
    final b = await importPhoto('b.jpg');
    await db.setCameraMetadata(b.id, const CameraInfo(make: 'Canon', model: 'R5'));
    final c = await importPhoto('c.jpg');
    await db.setCameraMetadata(c.id, const CameraInfo(make: 'Canon', model: 'R5')); // Duplikat

    expect(await db.distinctCameraMakes(), ['Canon', 'Nikon']);
    expect(await db.distinctCameraModels(), ['R5', 'Z8']);
    expect(await db.distinctLensModels(), ['24-70mm']);
  });

  test('Orts-Filter (Land/Bundesland/Stadt) filtert auf Gleichheit', () async {
    final paris = await importPhoto('paris.jpg');
    await db.setLocationNames(paris.id, country: 'France', state: 'Île-de-France', city: 'Paris');
    final berlin = await importPhoto('berlin.jpg');
    await db.setLocationNames(berlin.id, country: 'Deutschland', state: 'Berlin', city: 'Berlin');

    final byCountry = await db.searchAssets(const SearchFilters(locationCountry: 'France'));
    expect(byCountry.map((r) => r.id), [paris.id]);

    final byCity = await db.searchAssets(const SearchFilters(locationCity: 'Berlin'));
    expect(byCity.map((r) => r.id), [berlin.id]);
  });

  test('distinctCountries/-States/-Cities sind kaskadierend gefiltert', () async {
    final paris = await importPhoto('paris.jpg');
    await db.setLocationNames(paris.id, country: 'France', state: 'Île-de-France', city: 'Paris');
    final lyon = await importPhoto('lyon.jpg');
    await db.setLocationNames(lyon.id, country: 'France', state: 'Auvergne-Rhône-Alpes', city: 'Lyon');
    final berlin = await importPhoto('berlin.jpg');
    await db.setLocationNames(berlin.id, country: 'Deutschland', state: 'Berlin', city: 'Berlin');

    expect(await db.distinctCountries(), ['Deutschland', 'France']);
    expect(await db.distinctStates('France'), ['Auvergne-Rhône-Alpes', 'Île-de-France']);
    expect(await db.distinctStates('Deutschland'), ['Berlin']);
    expect(await db.distinctCities('Île-de-France'), ['Paris']);
    expect(await db.distinctCities('Auvergne-Rhône-Alpes'), ['Lyon']);
  });

  test('Mindestbewertungs-Filter findet nur Fotos mit Bewertung >= Schwellenwert', () async {
    final low = await importPhoto('a.jpg');
    await db.setRating(low.id, 2);
    final high = await importPhoto('b.jpg');
    await db.setRating(high.id, 4);
    await importPhoto('c.jpg'); // Bewertung 0 (Default)

    final results = await db.searchAssets(const SearchFilters(minRating: 3));

    expect(results.map((r) => r.id), [high.id]);
  });

  test('Farbmarkierungs-Filter verknüpft mehrere ausgewählte Farben mit ODER', () async {
    final red = await importPhoto('a.jpg');
    await db.setColorLabel(red.id, 'red');
    final blue = await importPhoto('b.jpg');
    await db.setColorLabel(blue.id, 'blue');
    await importPhoto('c.jpg'); // keine Farbe

    final results = await db.searchAssets(const SearchFilters(colorLabels: {'red', 'blue'}));

    expect(results.map((r) => r.id).toSet(), {red.id, blue.id});
  });

  test('ISO-/Blenden-/Brennweiten-Bereichsfilter sind beidseitig inklusiv', () async {
    final match = await importPhoto('a.jpg');
    await db.setCameraMetadata(match.id, const CameraInfo(iso: 400, fNumber: 2.8, focalLengthMm: 50));
    final tooLowIso = await importPhoto('b.jpg');
    await db.setCameraMetadata(tooLowIso.id, const CameraInfo(iso: 100, fNumber: 2.8, focalLengthMm: 50));
    final tooHighFNumber = await importPhoto('c.jpg');
    await db.setCameraMetadata(tooHighFNumber.id, const CameraInfo(iso: 400, fNumber: 11, focalLengthMm: 50));

    final results = await db.searchAssets(const SearchFilters(
      minIso: 200,
      maxIso: 800,
      minFNumber: 1.4,
      maxFNumber: 4.0,
      minFocalLengthMm: 24,
      maxFocalLengthMm: 70,
    ));

    expect(results.map((r) => r.id), [match.id]);
  });

  test('OCR-Textsuche durchsucht nur den erkannten Text, nicht Dateiname/Beschreibung', () async {
    final a = await importPhoto('foto1.jpg');
    await db.setOcrResult(a.id, 'Willkommen im Hotel');
    final b = await importPhoto('willkommen.jpg'); // Dateiname enthält den Begriff, ocrText nicht
    await db.setOcrResult(b.id, '');

    final results = await db.searchAssets(
      const SearchFilters(textMode: SearchTextMode.ocr, query: 'willkommen'),
    );

    expect(results.map((r) => r.id), [a.id]);
  });

  test('"Nur unscharfe Fotos anzeigen" filtert auf sharpnessScore <= Schwellenwert', () async {
    final blurry = await importPhoto('a.jpg');
    await db.setSharpnessScore(blurry.id, 50.0);
    final sharp = await importPhoto('b.jpg');
    await db.setSharpnessScore(sharp.id, 500.0);
    await importPhoto('c.jpg'); // kein Score berechnet

    final results = await db.searchAssets(const SearchFilters(maxSharpnessScore: 100.0));

    expect(results.map((r) => r.id), [blurry.id]);
  });

  test('assetsForLocationNameBackfill findet nur Fotos mit GPS-Ort, aber ohne aufgelösten Orts-Namen', () async {
    final needsResolve = await importPhoto('a.jpg');
    await db.setLocation(needsResolve.id, 48.85, 2.35);
    final alreadyResolved = await importPhoto('b.jpg');
    await db.setLocation(alreadyResolved.id, 48.85, 2.35);
    await db.setLocationNames(alreadyResolved.id, country: 'France', state: 'Île-de-France', city: 'Paris');
    await importPhoto('c.jpg'); // kein GPS-Ort bekannt

    final results = await db.assetsForLocationNameBackfill();

    expect(results.map((r) => r.id), [needsResolve.id]);
  });
}
