part of '../database.dart';

/// Alben, Schlagwörter und Textsuche.
extension AlbenAbfragen on AppDatabase {
  // -----------------------------------------------------------------------
  // Alben
  // -----------------------------------------------------------------------

  Stream<List<AlbumData>> watchAlbums() => (select(
    albums,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  Future<void> createAlbum(AlbumsCompanion album) => into(albums).insert(album);

  Future<void> addAssetsToAlbum(String albumId, List<String> assetIds) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        albumAssets,
        assetIds.map(
          (id) => AlbumAssetsCompanion.insert(albumId: albumId, assetId: id),
        ),
      );
    });
  }

  /// Setzt das Titelbild eines Albums – `null` nimmt die Wahl zurück.
  ///
  /// Die Spalte gab es seit jeher, gelesen und geschrieben hat sie
  /// niemand: Ein Album war in der Übersicht ein Symbol und ein Name.
  Future<void> setzeAlbumTitelbild(String albumId, String? assetId) =>
      (update(albums)..where((t) => t.id.equals(albumId))).write(
        AlbumsCompanion(coverAssetId: Value(assetId)),
      );

  /// Das Bild, mit dem ein Album in der Übersicht steht.
  ///
  /// Erst das gewählte Titelbild; ist keines gewählt – oder liegt das
  /// gewählte inzwischen im Papierkorb, ist gesperrt oder gar nicht mehr
  /// im Album –, die neueste Aufnahme darin. `null` nur bei einem leeren
  /// Album. Ein Titelbild, das aus dem Album entfernt wurde, würde sonst
  /// weiter dafür werben.
  Future<AssetData?> albumTitelbild(AlbumData album) async {
    final gewaehlt = album.coverAssetId;
    if (gewaehlt != null) {
      final treffer =
          await (select(assets).join([
                innerJoin(
                  albumAssets,
                  albumAssets.assetId.equalsExp(assets.id),
                ),
              ])..where(
                albumAssets.albumId.equals(album.id) &
                    assets.id.equals(gewaehlt) &
                    assets.isTrashed.equals(false) &
                    assets.isLocked.equals(false),
              ))
              .getSingleOrNull();
      final zeile = treffer?.readTableOrNull(assets);
      if (zeile != null) return zeile;
    }
    final erste =
        await (select(assets).join([
                innerJoin(
                  albumAssets,
                  albumAssets.assetId.equalsExp(assets.id),
                ),
              ])
              ..where(
                albumAssets.albumId.equals(album.id) &
                    assets.isTrashed.equals(false) &
                    assets.isLocked.equals(false),
              )
              ..orderBy([OrderingTerm.desc(assets.fileCreatedAt)])
              ..limit(1))
            .getSingleOrNull();
    return erste?.readTableOrNull(assets);
  }

  Future<void> removeAssetFromAlbum(String albumId, String assetId) => (delete(
    albumAssets,
  )..where((t) => t.albumId.equals(albumId) & t.assetId.equals(assetId))).go();

  Stream<List<AssetData>> watchAlbumAssets(String albumId) {
    final query =
        select(assets).join([
            innerJoin(albumAssets, albumAssets.assetId.equalsExp(assets.id)),
          ])
          ..where(albumAssets.albumId.equals(albumId))
          ..where(assets.isTrashed.equals(false))
          ..where(assets.isLocked.equals(false))
          ..where(_isPrimaryGridEntry(assets))
          ..orderBy([OrderingTerm.desc(assets.fileCreatedAt)]);
    return _gedrosselt(
      () => query.map((r) => r.readTable(assets)),
      TableUpdateQuery.allOf([
        TableUpdateQuery.onTable(assets),
        TableUpdateQuery.onTable(albumAssets),
      ]),
    );
  }

  /// Einmalige (nicht-reaktive) Variante von [watchAlbumAssets], u.a. für den
  /// Metadaten-Export beim Backup und die Album-Vorschau im Erkunden-Tab –
  /// deshalb ebenfalls ohne gelöschte/gesperrte Assets, analog zu
  /// [watchAlbumAssets].
  Future<List<AssetData>> assetsInAlbumOnce(String albumId) async {
    final query =
        select(assets).join([
          innerJoin(albumAssets, albumAssets.assetId.equalsExp(assets.id)),
        ])..where(
          albumAssets.albumId.equals(albumId) &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false) &
              _isPrimaryGridEntry(assets),
        );
    final rows = await query.get();
    return rows.map((r) => r.readTable(assets)).toList();
  }

  // -----------------------------------------------------------------------
  // Tags & Textsuche
  // -----------------------------------------------------------------------

  Future<String> ensureTag(String name) async {
    final existing = await (select(
      tags,
    )..where((t) => t.name.equals(name))).getSingleOrNull();
    if (existing != null) return existing.id;
    final id =
        name.hashCode.toRadixString(36) +
        DateTime.now().microsecondsSinceEpoch.toString();
    await into(tags).insert(TagsCompanion.insert(id: id, name: name));
    return id;
  }

  /// Hängt ein Schlagwort an ein Foto.
  ///
  /// **Hand schlägt KI, nie andersherum** (siehe [Tagquelle]). Wer einen
  /// Begriff selbst vergibt, übernimmt ihn damit – auch wenn ihn zuvor die
  /// Bilderkennung vorgeschlagen hatte; die Zeile wird zu `hand` und bleibt
  /// beim Sperren stehen. Läuft umgekehrt die Bilderkennung über einen
  /// Begriff, den der Nutzer schon selbst vergeben hat, lässt sie ihn in
  /// Ruhe: Sie darf eine Handvergabe nicht zu ihrer eigenen erklären und
  /// sie damit löschbar machen.
  Future<void> tagAsset(
    String assetId,
    String tagName, {
    String quelle = Tagquelle.hand,
  }) async {
    final tagId = await ensureTag(tagName);
    if (quelle == Tagquelle.ki) {
      // `insertOnConflictUpdate` würde eine vorhandene Handvergabe
      // überschreiben – hier ist genau das der Fehler.
      await into(assetTags).insert(
        AssetTagsCompanion.insert(
          assetId: assetId,
          tagId: tagId,
          quelle: const Value(Tagquelle.ki),
        ),
        mode: InsertMode.insertOrIgnore,
      );
      return;
    }
    await into(assetTags).insertOnConflictUpdate(
      AssetTagsCompanion.insert(
        assetId: assetId,
        tagId: tagId,
        quelle: Value(quelle),
      ),
    );
  }

  /// Hängt denselben Tag an mehrere Assets. Der Tag wird einmal angelegt
  /// (statt je Foto nachgeschlagen), die Zuordnungen gehen als ein Stapel
  /// in einer Transaktion hinaus.
  Future<void> tagAssetsBulk(List<String> assetIds, String tagName) async {
    final tagId = await ensureTag(tagName);
    await batch(
      (b) => b.insertAllOnConflictUpdate(assetTags, [
        for (final id in assetIds)
          // Die Quelle ausdrücklich: Ohne sie liess das Überschreiben eine
          // Vergabe der Bilderkennung stehen, und der Nutzer hatte das
          // Schlagwort von Hand vergeben, ohne es zu übernehmen – beim
          // Sperren wäre es mit den KI-Schlagwörtern verschwunden. Dieselbe
          // Regel wie in [tagAsset]: Hand schlägt KI.
          AssetTagsCompanion.insert(
            assetId: id,
            tagId: tagId,
            quelle: const Value(Tagquelle.hand),
          ),
      ]),
    );
  }

  /// Wie viele Schlagwörter die Bilderkennung vergeben hat.
  ///
  /// Für die Rückfrage vor dem Zurücknehmen: Eine Zahl zu nennen ist der
  /// Unterschied zwischen einer Warnung und einer Behauptung.
  Future<int> kiTagAnzahl() async {
    final zeile = await customSelect(
      'SELECT COUNT(*) AS anzahl FROM asset_tags WHERE quelle = ?',
      variables: const [Variable<String>(Tagquelle.ki)],
      readsFrom: {assetTags},
    ).getSingle();
    return zeile.read<int>('anzahl');
  }

  /// Nimmt **alle** von der Bilderkennung vergebenen Schlagwörter zurück.
  ///
  /// **Von Hand vergebene bleiben unangetastet** – das ist der ganze Grund,
  /// warum in `asset_tags` seit Schema 56 die Herkunft steht (siehe
  /// [Tagquelle]). Wer einen Begriff selbst vergeben hat, hat ihn damit
  /// übernommen; die Zeile steht auf `hand` und fällt hier nicht mit.
  ///
  /// Zusätzlich wird der Vermerk „schon durchgesehen" an den Aufnahmen
  /// gelöscht. Ohne ihn bliebe die Bibliothek nach dem Zurücknehmen leer:
  /// Die Bilderkennung überspringt jede Aufnahme, die den Vermerk trägt,
  /// und würde die Schlagwörter deshalb nie neu vergeben.
  ///
  /// Verwaiste Schlagwörter, die danach an keiner Aufnahme mehr hängen,
  /// werden mit entfernt – sonst bliebe die Auswahlliste in der Suche voll
  /// von Begriffen ohne ein einziges Foto.
  Future<int> nimmKiTagsZurueck() async {
    return transaction(() async {
      final anzahl = await kiTagAnzahl();
      await (delete(
        assetTags,
      )..where((t) => t.quelle.equals(Tagquelle.ki))).go();
      await customUpdate(
        'UPDATE assets SET ai_tags_scanned = 0',
        updates: {assets},
        updateKind: UpdateKind.update,
      );
      await customUpdate(
        'DELETE FROM tags WHERE id NOT IN (SELECT tag_id FROM asset_tags)',
        updates: {tags},
        updateKind: UpdateKind.delete,
      );
      return anzahl;
    });
  }

  Future<void> untagAsset(String assetId, String tagId) => (delete(
    assetTags,
  )..where((t) => t.assetId.equals(assetId) & t.tagId.equals(tagId))).go();

  /// Alle Tags der Bibliothek – für die Mehrfachauswahl im
  /// Suchoptionen-Panel.
  Stream<List<TagData>> watchAllTags() =>
      (select(tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  /// Dasselbe als einmalige Abfrage.
  ///
  /// Ein `watch(...).first` sieht danach aus, als täte es dasselbe, tut es
  /// aber nicht: Es hängt einen Beobachter an die Tabelle, lässt bei
  /// Abbruch einen Zeitgeber zurück und wirft in einer frisch angelegten
  /// Datenbank „Bad state: No element". Dieselbe Lehre wie bei
  /// [alleAufnahmen].
  Future<List<TagData>> alleTags() =>
      (select(tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  /// Direkte Tag-Zuordnung per ID statt per Name (anders als [tagAsset], das
  /// den Tag bei Bedarf erst per Name anlegt) – für das Anwenden eines
  /// Kamera-Presets, dessen Tags bereits als IDs gespeichert sind, ohne
  /// zusätzlichen Namens-Lookup.
  Future<void> tagAssetById(String assetId, String tagId) =>
      into(assetTags).insertOnConflictUpdate(
        AssetTagsCompanion.insert(assetId: assetId, tagId: tagId),
      );
}
