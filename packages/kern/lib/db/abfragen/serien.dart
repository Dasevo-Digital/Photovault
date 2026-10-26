part of '../database.dart';

const variantenstapelPraefix = 'variante:';

/// Varianten sind bewusst normale Stapel mit einer kenntlichen Kennung.
/// Dadurch bleiben Raster, Suche, Synchronisation und Sicherungen ohne
/// zweite Gruppierungslogik kompatibel; nur die Oberfläche benennt den
/// Zweck anders und lässt die Hauptversion wechseln.
bool istVariantenstapel(String? stackId) =>
    stackId?.startsWith(variantenstapelPraefix) ?? false;

String variantenstapelId(String kennung) => '$variantenstapelPraefix$kennung';

/// Ob [asset] die Videohälfte eines Live Photos ist.
///
/// Sie zeigt drei Sekunden um denselben Augenblick wie ihr Standbild und
/// erscheint neben ihm nicht als eigene Aufnahme. Die Gesichtserkennung
/// lässt sie deshalb aus (#226): Sie fand dort dieselben Gesichter ein
/// zweites Mal – bei 77 von 79 solchen Videos in der Prüfbibliothek.
bool istLivePhotoVideo(AssetData asset) =>
    asset.type == 'VIDEO' && asset.linkedAssetId != null;

/// Live Photos und Serien.
extension SerienAbfragen on AppDatabase {
  // ---------------------------------------------------------------------
  // Live Photos (Standbild <-> Video-Verknüpfung)
  // ---------------------------------------------------------------------

  /// Alle noch nicht verknüpften, nicht gelöschten Assets eines Typs – für
  /// den Abgleich beim Import, ob ein passender Live-Photo-Partner (gleicher
  /// Dateiname, anderer Typ) schon in der Bibliothek liegt.
  Future<List<AssetData>> unlinkedAssetsOfType(String type) =>
      (select(assets)..where(
            (t) =>
                t.type.equals(type) &
                t.isTrashed.equals(false) &
                t.linkedAssetId.isNull(),
          ))
          .get();

  /// Zählvariante von [unlinkedAssetsOfType], siehe [countLocationBackfill].
  /// Wie viele Aufnahmen dieser Art es gibt – für die Anzeige „betrifft N"
  /// bei der Prüfung der Dateiarten.
  Future<int> countAssetsOfType(String type, {DateTime? importiertNach}) =>
      _countWhere(assets.type.equals(type) & _importiertNach(importiertNach));

  Future<int> countUnlinkedAssetsOfType(
    String type, {
    DateTime? importiertNach,
  }) => _countWhere(
    assets.type.equals(type) &
        assets.isTrashed.equals(false) &
        assets.linkedAssetId.isNull() &
        _importiertNach(importiertNach),
  );

  /// Nur, was nach [zeitpunkt] importiert wurde – oder alles, wenn er
  /// fehlt. Für die Zähler der Aufgaben, die sich je Aufnahme nichts
  /// merken (siehe [Aufgabenlaeufe]).
  Expression<bool> _importiertNach(DateTime? zeitpunkt) => zeitpunkt == null
      ? const Constant(true)
      : assets.importedAt.isBiggerThanValue(zeitpunkt);

  Future<void> merkeAufgabenlauf(String schluessel) =>
      into(aufgabenlaeufe).insertOnConflictUpdate(
        AufgabenlaeufeCompanion.insert(
          schluessel: schluessel,
          fertigAm: DateTime.now(),
        ),
      );

  Future<DateTime?> aufgabeFertigAm(String schluessel) async =>
      (await (select(
            aufgabenlaeufe,
          )..where((t) => t.schluessel.equals(schluessel))).getSingleOrNull())
          ?.fertigAm;

  /// Die verknüpften Live-Photo-Paare: Video und Foto (#213).
  Future<List<(AssetData video, AssetData foto)>> livePhotoPaare() async {
    final foto = alias(assets, 'foto');
    final zeilen =
        await (select(assets).join([
              innerJoin(foto, foto.id.equalsExp(assets.linkedAssetId)),
            ])..where(
              assets.type.equals('VIDEO') &
                  foto.type.equals('IMAGE') &
                  assets.isTrashed.equals(false),
            ))
            .get();
    return [for (final z in zeilen) (z.readTable(assets), z.readTable(foto))];
  }

  /// Gesichter auf Videohälften von Live Photos, die nichts verlieren,
  /// wenn sie gehen (#226): unbenannte und beiseitegelegte, und benannte,
  /// deren Person auch im Standbild steht.
  ///
  /// Stehen bleibt ein benanntes Gesicht, dessen Person das Standbild
  /// nicht trägt – dort hat die Erkennung sie übersehen oder jemand sie
  /// anders benannt. Das zu entscheiden ist Sache des Nutzers.
  Future<List<String>> doppelteLivePhotoGesichter() async {
    final zeilen = await customSelect(
      'SELECT f.id AS id FROM faces f '
      'JOIN assets v ON v.id = f.asset_id '
      "WHERE v.type = 'VIDEO' AND v.linked_asset_id IS NOT NULL "
      'AND (f.person_id IS NULL OR EXISTS ('
      '  SELECT 1 FROM faces g '
      '  WHERE g.asset_id = v.linked_asset_id AND g.person_id = f.person_id'
      '))',
      readsFrom: {faces, assets},
    ).get();
    return [for (final z in zeilen) z.read<String>('id')];
  }

  /// Vermerkt alle Videohälften von Live Photos als nach Gesichtern
  /// durchsucht – sie werden es nicht mehr (siehe [istLivePhotoVideo]).
  /// Sonst stünden sie als offene Arbeit da, die nie erledigt wird.
  Future<int> livePhotoVideosAlsDurchsucht() =>
      (update(assets)..where(
            (t) =>
                t.type.equals('VIDEO') &
                t.linkedAssetId.isNotNull() &
                t.facesScanned.equals(false),
          ))
          .write(const AssetsCompanion(facesScanned: Value(true)));

  /// Verknüpfte Paare, deren beide Hälften Fotos sind – je Paar einmal.
  ///
  /// Kein Live Photo, sondern ein Rest: Ein Standbild, das unter einem
  /// `.MOV`-Namen ankam, galt bis zur Umstellung auf den Inhalt als Video
  /// und wurde als solches an das gleichnamige Foto gehängt. Seit es als
  /// Foto geführt wird, zeigt das Raster beide Hälften (siehe
  /// `rasterSichtbar`), jede mit dem Live-Zeichen.
  Future<List<(String, String)>> bildpaare() async {
    final partner = alias(assets, 'partner');
    final zeilen = await (select(assets).join(
      [innerJoin(partner, partner.id.equalsExp(assets.linkedAssetId))],
    )..where(assets.type.equals('IMAGE') & partner.type.equals('IMAGE'))).get();
    final gesehen = <String>{};
    return [
      for (final z in zeilen)
        if (gesehen.add(z.readTable(assets).id) &&
            gesehen.add(z.readTable(partner).id))
          (z.readTable(assets).id, z.readTable(partner).id),
    ];
  }

  /// Löst ein Live-Photo-Paar wieder (siehe [linkAssets]).
  Future<void> trenneAssets(String idA, String idB) async {
    await (update(assets)..where((t) => t.id.isIn([idA, idB]))).write(
      const AssetsCompanion(linkedAssetId: Value(null)),
    );
  }

  Future<void> linkAssets(String idA, String idB) async {
    await (update(assets)..where((t) => t.id.equals(idA))).write(
      AssetsCompanion(linkedAssetId: Value(idB)),
    );
    await (update(assets)..where((t) => t.id.equals(idB))).write(
      AssetsCompanion(linkedAssetId: Value(idA)),
    );
  }

  // ---------------------------------------------------------------------
  // Serien-/Burst-Stapel (siehe StackReviewScreen, findBurstGroups)

  Future<Set<String>> verworfeneSerienvorschlaege() async => {
    for (final z in await select(verworfeneSerien).get()) z.schluessel,
  };

  Future<void> verwirfSerienvorschlag(String schluessel) =>
      into(verworfeneSerien).insertOnConflictUpdate(
        VerworfeneSerienCompanion.insert(
          schluessel: schluessel,
          verworfenAm: DateTime.now(),
        ),
      );

  /// Die Einbettungen, die für einen Serienvorschlag überhaupt in Frage
  /// kommen: alles, was nicht schon in einem Stapel liegt.
  ///
  /// Ohne diese Einschränkung fände der nächste Lauf dieselben Gruppen
  /// erneut – die Mitglieder eines Stapels sind aus dem Raster
  /// verschwunden, aus der Einbettungstabelle aber nicht.
  Future<Set<String>> bereitsGestapelt() async {
    final zeilen =
        await (selectOnly(assets)
              ..addColumns([assets.id])
              ..where(assets.stackId.isNotNull()))
            .get();
    return {for (final z in zeilen) z.read(assets.id)!};
  }
  // ---------------------------------------------------------------------

  /// Fasst [assetIds] zu einem neuen Stapel zusammen: [coverAssetId] (muss in
  /// [assetIds] enthalten sein) wird Titelbild (`isStackCover = true`,
  /// `stackSize` = Gesamtzahl) und bleibt allein in Timeline & Co. sichtbar
  /// (siehe die `stackId`/`isStackCover`-Filter dort), die übrigen
  /// Mitglieder werden aus der Rasteransicht ausgeblendet. [stackId] wird
  /// vom Aufrufer erzeugt (Muster wie `createSavedSearch`/`createAlbum`).
  Future<void> createStack(
    String stackId,
    List<String> assetIds,
    String coverAssetId,
  ) async {
    assert(assetIds.contains(coverAssetId));
    await batch((b) {
      for (final id in assetIds) {
        b.update(
          assets,
          AssetsCompanion(
            stackId: Value(stackId),
            isStackCover: Value(id == coverAssetId),
            stackSize: id == coverAssetId
                ? Value(assetIds.length)
                : const Value(null),
          ),
          where: (t) => t.id.equals(id),
        );
      }
    });
  }

  /// Löst einen Stapel wieder auf ("Serie auflösen") – alle Mitglieder
  /// werden wieder einzeln sichtbar.
  Future<void> unstackAssets(String stackId) =>
      (update(assets)..where((t) => t.stackId.equals(stackId))).write(
        const AssetsCompanion(
          stackId: Value(null),
          isStackCover: Value(false),
          stackSize: Value(null),
        ),
      );

  Future<List<AssetData>> assetsInStack(String stackId) =>
      (select(assets)..where((t) => t.stackId.equals(stackId))).get();

  /// Macht ein anderes Mitglied zum sichtbaren Titelbild eines Stapels.
  /// Der Vorgang ist atomar: Es gibt zu keinem Zeitpunkt zwei Titelbilder
  /// oder einen Stapel ohne sichtbares Mitglied.
  Future<void> setStackCover(String stackId, String coverAssetId) async {
    final mitglieder = await assetsInStack(stackId);
    if (!mitglieder.any((a) => a.id == coverAssetId)) {
      throw ArgumentError.value(coverAssetId, 'coverAssetId');
    }
    await batch((b) {
      for (final asset in mitglieder) {
        final istTitel = asset.id == coverAssetId;
        b.update(
          assets,
          AssetsCompanion(
            isStackCover: Value(istTitel),
            stackSize: istTitel ? Value(mitglieder.length) : const Value(null),
          ),
          where: (t) => t.stackId.equals(stackId) & t.id.equals(asset.id),
        );
      }
    });
  }

  /// Alle Assets (Fotos und Videos), die für eine (erneute) Thumbnail-/
  /// Vorschau-Erzeugung infrage kommen. Bei [onlyMissing] nur Assets ohne
  /// Thumbnail (z.B. HEIC-Fotos, die vor Einbindung der nativen
  /// Bildkonvertierung importiert wurden, oder Videos, die vor Einführung
  /// der Video-Thumbnail-Erzeugung importiert wurden).
  /// Assets, für die sich ein Vorschaubild erzeugen lässt.
  ///
  /// Gesperrte bleiben aussen vor. Der Kommentar stand hier früher
  /// andersherum („läuft absichtlich auch über gesperrte, die Ansicht
  /// braucht Thumbnails") – das ging nicht auf: Bei einem gesperrten Foto
  /// ist die Originaldatei verschlüsselt, das Dekodieren scheitert
  /// zwangsläufig, und [ImportService.generateThumbnailAndPreview] kehrt
  /// ohne Ergebnis zurück, bevor überhaupt etwas geschrieben wird. Es kam
  /// also nie ein Vorschaubild dabei heraus – nur für jedes gesperrte Foto
  /// ein vollständiges Lesen der Datei und ein Isolate-Durchlauf ins Leere.
  /// Das Vorschaubild eines gesperrten Fotos ist ohnehin mitverschlüsselt
  /// und wird beim Entsperren wieder lesbar.
  Future<List<AssetData>> assetsForThumbnailRegen({required bool onlyMissing}) {
    final query = select(assets)
      ..where((t) => t.isTrashed.equals(false) & t.isLocked.equals(false));
    if (onlyMissing) {
      query.where(_fehlendeVorschau);
    }
    return query.get();
  }

  /// Zählvariante von [assetsForThumbnailRegen], siehe [countLocationBackfill].
  Future<int> countThumbnailRegen({required bool onlyMissing}) => _countWhere(
    onlyMissing
        ? assets.isTrashed.equals(false) &
              assets.isLocked.equals(false) &
              _fehlendeVorschau(assets)
        : assets.isTrashed.equals(false) & assets.isLocked.equals(false),
  );

  /// „Fehlt hier ein Vorschaubild?"
  ///
  /// Bei einem Video zählt zusätzlich die **Vorschau**, nicht nur die
  /// Miniatur: Erst das grosse Standbild macht es auswertbar (siehe
  /// [_auswertbar]). Die 440 Videos der Prüfbibliothek hatten fast alle
  /// eine Miniatur und keines eine Vorschau – ohne diese Unterscheidung
  /// hätte „Fehlende erzeugen" sie für erledigt gehalten.
  ///
  /// Bei einem Bild dagegen ist eine fehlende Vorschau der Normalfall: Sie
  /// entsteht nur für HEIC und RAW.
  Expression<bool> _fehlendeVorschau($AssetsTable t) =>
      t.thumbnailRelativePath.isNull() |
      (t.type.equals('VIDEO') & t.previewRelativePath.isNull());

  /// Für die Bibliotheks-Integritätsprüfung (IntegrityCheckScreen): bewusst
  /// vollständig ungefiltert (auch gelöscht/gesperrt), da all diese Assets
  /// weiterhin echte Dateien auf der Platte referenzieren, die geprüft
  /// werden müssen.
  Future<List<AssetData>> allAssetsForIntegrityCheck() => select(assets).get();

  /// Löscht NUR den (dann fehlenden) Datei-Pfad einer abgeleiteten Datei,
  /// OHNE die zugehörigen Einstellungen zu verwerfen – anders als
  /// [resetDevelopSettings]/[resetVideoTrim], die bewusst auch die
  /// Regler-Werte zurücksetzen. Für die Bibliotheks-Integritätsprüfung: das
  /// Original ist ja noch da, die Datei lässt sich (mit denselben
  /// Einstellungen) einfach erneut rendern.
  Future<void> clearMissingThumbnailPath(String assetId) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        const AssetsCompanion(thumbnailRelativePath: Value(null)),
      );

  Future<void> clearMissingPreviewPath(String assetId) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        const AssetsCompanion(previewRelativePath: Value(null)),
      );

  Future<void> clearMissingDevelopedPath(String assetId) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        const AssetsCompanion(developedRelativePath: Value(null)),
      );

  Future<void> clearMissingTrimmedPath(String assetId) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        const AssetsCompanion(trimmedRelativePath: Value(null)),
      );

  Future<void> clearMissingRestoredPath(String assetId) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        const AssetsCompanion(restoredRelativePath: Value(null)),
      );

  /// Löscht nur den fehlenden Crop-Pfad eines Gesichts, die Zuordnung zur
  /// Person und das Embedding bleiben erhalten (der Crop ist nur eine
  /// zwischengespeicherte Vorschau).
  Future<void> clearMissingFaceCropPath(String faceId) =>
      (update(faces)..where((t) => t.id.equals(faceId))).write(
        const FacesCompanion(cropRelativePath: Value(null)),
      );

  /// Aufnahmen, die als Video geführt werden – Anwärter dafür, dass der
  /// Name etwas anderes behauptet als die Bytes (siehe
  /// `LibraryState.repariereDateiarten`).
  Future<List<AssetData>> alsVideoGefuehrte() =>
      (select(assets)..where((t) => t.type.equals('VIDEO'))).get();

  /// Trägt für eine Aufnahme die Art ein, die ihre Bytes hergeben, und
  /// nimmt dabei alles zurück, was aus der falschen Annahme entstanden ist.
  ///
  /// Miniatur und Dauer werden ausdrücklich geleert: Die Miniatur kam vom
  /// Videowandler und ist bei diesen Dateien nie entstanden, und eine
  /// Laufzeit hat ein Standbild nicht.
  /// Ein Video, das sich als Foto erweist, verliert dabei seine
  /// Live-Photo-Verknüpfung: Zwei Fotos sind kein Live Photo (siehe
  /// [bildpaare]).
  Future<void> setzeDateiart(
    String assetId,
    String art, {
    required String dateiformat,
  }) => transaction(() async {
    final vorher = await (select(
      assets,
    )..where((t) => t.id.equals(assetId))).getSingleOrNull();
    await (update(assets)..where((t) => t.id.equals(assetId))).write(
      AssetsCompanion(
        type: Value(art),
        dateiformat: Value(dateiformat),
        thumbnailRelativePath: const Value(null),
        previewRelativePath: const Value(null),
        durationSeconds: const Value(null),
      ),
    );
    if (vorher?.linkedAssetId case final partner? when art == 'IMAGE') {
      await trenneAssets(assetId, partner);
    }
  });

  Future<void> updateThumbnailInfo(
    String assetId, {
    String? thumbnailRelativePath,
    String? previewRelativePath,
    int? widthPx,
    int? heightPx,
    double? durationSeconds,
  }) => (update(assets)..where((t) => t.id.equals(assetId))).write(
    AssetsCompanion(
      thumbnailRelativePath: thumbnailRelativePath != null
          ? Value(thumbnailRelativePath)
          : const Value.absent(),
      previewRelativePath: previewRelativePath != null
          ? Value(previewRelativePath)
          : const Value.absent(),
      widthPx: widthPx != null ? Value(widthPx) : const Value.absent(),
      heightPx: heightPx != null ? Value(heightPx) : const Value.absent(),
      durationSeconds: durationSeconds != null
          ? Value(durationSeconds)
          : const Value.absent(),
    ),
  );
}
