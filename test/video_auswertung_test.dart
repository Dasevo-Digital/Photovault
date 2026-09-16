import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/asset_display_path.dart';

/// **Videos nehmen an der Auswertung teil – sobald ein Standbild vorliegt.**
///
/// 440 Videos der Prüfbibliothek hatten null Beschreibungen, null
/// Schlagwörter, null Gesichter, null Einbettungen und null erkannte Texte.
/// Der Grund war kein fehlendes Modell, sondern ein Filter: 23 Abfragen
/// verlangten `type = 'IMAGE'`.
///
/// Massgeblich ist jetzt die **Vorschau**, nicht die Art: Sie ist das, was
/// `LibraryState._decodableFile` liefert, und für ein Video das Standbild
/// aus der ersten Sekunde. Ein Video ohne Standbild bleibt draussen, statt
/// jede Stufe einzeln scheitern zu lassen.
void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_videoausw_');
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<void> lege(
    String id, {
    required String art,
    String? vorschau,
    String? miniatur = 'thumbnails/x.jpg',
  }) =>
      db.insertAsset(AssetsCompanion.insert(
        id: id,
        relativePath: 'originals/$id',
        originalFileName: id,
        type: art,
        checksum: id,
        fileCreatedAt: DateTime(2024),
        importedAt: DateTime(2024),
        thumbnailRelativePath: Value(miniatur),
        previewRelativePath: Value(vorschau),
      ));

  /// Alle Stufen, die aus dem Bildinhalt etwas rechnen – jede mit ihrer
  /// Liste und ihrer Zählung, denn die beiden liefen in diesem Projekt
  /// schon einmal auseinander (siehe background_task_counts_test.dart).
  final stufen = <String, (Future<List<AssetData>> Function(), Future<int> Function())>{
    'Texterkennung': (
      () => db.assetsForOcrBackfill(),
      () => db.countOcrBackfill()
    ),
    'Beschreibung': (
      () => db.assetsForCaptionBackfill(),
      () => db.countCaptionBackfill()
    ),
    'Unschärfe': (
      () => db.assetsForBlurBackfill(),
      () => db.countBlurBackfill()
    ),
    'Gesichter': (
      () => db.assetsForFaceScan(onlyNew: true),
      () => db.countFaceScan(onlyNew: true)
    ),
    'Einbettung': (
      () => db.assetsForEmbeddingBackfill(),
      () => db.countEmbeddingBackfill()
    ),
    'KI-Schlagwörter': (
      () => db.assetsForAiTagging(onlyUntagged: true),
      () => db.countAiTagging(onlyUntagged: true)
    ),
  };

  group('Ein Video mit Standbild', () {
    setUp(() => lege('v', art: 'VIDEO', vorschau: 'previews/v.jpg'));

    stufen.forEach((name, paar) {
      test('$name sieht es an', () async {
        final liste = await paar.$1();
        expect([for (final a in liste) a.id], contains('v'),
            reason: '$name liess Videos bisher aus');
        expect(await paar.$2(), 1, reason: '$name: Zählung und Liste');
      });
    });
  });

  group('Ein Video ohne Standbild', () {
    // Die Extraktion scheitert an beschädigten Dateien – in der
    // Prüfbibliothek bei 33 von 440. Ohne Bild gibt es nichts anzusehen,
    // und jede Stufe einzeln daran scheitern zu lassen wäre der schlechtere
    // Weg: Sie stünde dann bis in alle Ewigkeit als „offen" in der Liste.
    setUp(() => lege('v', art: 'VIDEO', vorschau: null));

    stufen.forEach((name, paar) {
      test('$name lässt es liegen', () async {
        expect(await paar.$1(), isEmpty, reason: name);
        expect(await paar.$2(), 0, reason: name);
      });
    });
  });

  group('Ein gewöhnliches Foto', () {
    // Gegenprobe: Bilder haben in aller Regel keine Vorschau – sie
    // entsteht nur für HEIC und RAW. Die neue Bedingung darf sie nicht
    // aussperren.
    setUp(() => lege('f', art: 'IMAGE', vorschau: null));

    stufen.forEach((name, paar) {
      test('$name sieht es weiterhin an', () async {
        expect([for (final a in await paar.$1()) a.id], contains('f'),
            reason: name);
      });
    });
  });

  group('Der Vorschau-Nachlauf', () {
    test('greift Videos mit Miniatur, aber ohne Standbild auf', () async {
      // Genau der Bestand der Prüfbibliothek: fast alle Videos hatten eine
      // Miniatur und keines eine Vorschau. Ohne die Unterscheidung hätte
      // „Fehlende erzeugen" sie für erledigt gehalten.
      await lege('v', art: 'VIDEO', vorschau: null);
      final offen = await db.assetsForThumbnailRegen(onlyMissing: true);
      expect([for (final a in offen) a.id], ['v']);
      expect(await db.countThumbnailRegen(onlyMissing: true), 1);
    });

    test('lässt ein Video mit Standbild in Ruhe', () async {
      await lege('v', art: 'VIDEO', vorschau: 'previews/v.jpg');
      expect(await db.countThumbnailRegen(onlyMissing: true), 0);
    });

    test('ein Foto ohne Vorschau ist nicht unfertig', () async {
      // Bei einem JPEG ist die fehlende Vorschau der Normalfall.
      await lege('f', art: 'IMAGE', vorschau: null);
      expect(await db.countThumbnailRegen(onlyMissing: true), 0);
    });

    test('eine fehlende Miniatur zählt bei beiden Arten', () async {
      await lege('f', art: 'IMAGE', vorschau: null, miniatur: null);
      expect(await db.countThumbnailRegen(onlyMissing: true), 1);
    });
  });

  group('Der Anzeigepfad', () {
    AssetData bau({required String art, String? vorschau, String? zuschnitt}) =>
        AssetData(
          id: 'a',
          originalFileName: 'a',
          relativePath: 'originals/a',
          previewRelativePath: vorschau,
          trimmedRelativePath: zuschnitt,
          checksum: 'a',
          type: art,
          fileSizeBytes: 0,
          fileCreatedAt: DateTime(2024),
          importedAt: DateTime(2024),
          isFavorite: false,
          isTrashed: false,
          isLocked: false,
          backedUp: false,
          autoBackedUp: false,
          facesScanned: false,
          rating: 0,
          ocrScanned: false,
          aiCaptionScanned: false,
          aiTagsScanned: false,
          aiCaptionEdited: false,
          isStackCover: false,
          faceScanExcluded: false,
          gpsGeprueft: false,
          datumGeschaetzt: false,
          datumGeprueft: false,
          ortGeerbt: false,
          videobilderGeprueft: false,
        );

    test('ein Video wird abgespielt, nicht als Standbild gezeigt', () {
      // Der Fallstrick der ganzen Umstellung: Die Vorschau stand in der
      // Prioritätsliste vor dem Original. Sobald Videos eine bekamen,
      // hätte der Betrachter ein unbewegliches Bild gezeigt.
      expect(
          displayRelativePath(bau(art: 'VIDEO', vorschau: 'previews/a.jpg')),
          'originals/a');
    });

    test('ein Zuschnitt gewinnt weiterhin – das ist ein Film', () {
      expect(
          displayRelativePath(bau(
              art: 'VIDEO',
              vorschau: 'previews/a.jpg',
              zuschnitt: 'trimmed/a.mov')),
          'trimmed/a.mov');
    });

    test('bei einem Foto zählt die Vorschau wie bisher', () {
      expect(displayRelativePath(bau(art: 'IMAGE', vorschau: 'previews/a.jpg')),
          'previews/a.jpg');
    });
  });
}
