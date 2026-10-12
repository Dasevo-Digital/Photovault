part of '../database.dart';

/// CLIP-Bildeinbettungen für die Suche.
extension EinbettungsAbfragen on AppDatabase {
  // -----------------------------------------------------------------------
  // CLIP-Bild-Embeddings (KI-Suche)
  // -----------------------------------------------------------------------

  Future<void> saveEmbedding(String assetId, Float32List vector) async {
    await into(imageEmbeddings).insertOnConflictUpdate(
      ImageEmbeddingsCompanion.insert(
        assetId: assetId,
        vector: blobFromEmbeddingFloats(vector),
      ),
    );
    _embeddingsGeneration++;
  }

  /// Einzelnes gespeichertes CLIP-Embedding (falls vorhanden) – für das
  /// automatische KI-Tagging, das das beim Import ohnehin berechnete
  /// Bild-Embedding wiederverwendet, statt das Bild erneut zu dekodieren.
  Future<Float32List?> embeddingForAsset(String assetId) async {
    final row = await (select(
      imageEmbeddings,
    )..where((t) => t.assetId.equals(assetId))).getSingleOrNull();
    if (row == null) return null;
    return floatsFromEmbeddingBlob(row.vector);
  }

  /// Fotos, deren Aufnahmezeit nur geraten ist ([Assets.datumGeschaetzt]),
  /// oder die ein Scanner geschrieben hat, samt ihrem Bildvektor – der
  /// Stoff für `schaetzeDatierung`.
  ///
  /// **Scans zählen mit.** Ein Flachbettscanner schreibt EXIF wie eine
  /// Kamera, und als Aufnahmezeit steht dort der Tag des Scannens. Das
  /// Datum ist dann nicht geraten, aber genauso falsch – und genau diese
  /// Fotos sind die alten. Erkannt am Gerät: „scan“ im Modell (CanoScan,
  /// ScanSnap, OpticFilm-Scanner tragen es) oder Epson, das bis auf eine
  /// Messsucherkamera von 2004 nur Scanner baut.
  ///
  /// Nur die mit Vektor: Ohne ihn gibt es nichts zu schätzen, und das
  /// Bild dafür eigens zu öffnen hiesse, die Bildsuche ein zweites Mal
  /// zu rechnen.
  Future<List<({AssetData asset, Float32List vektor})>>
  datierungskandidaten() async {
    final zeilen =
        await (select(assets).join([
                innerJoin(
                  imageEmbeddings,
                  imageEmbeddings.assetId.equalsExp(assets.id),
                ),
              ])
              ..where(
                assets.type.equals('IMAGE') &
                    assets.isLocked.equals(false) &
                    assets.isTrashed.equals(false) &
                    (assets.datumGeschaetzt.equals(true) |
                        assets.cameraModel.lower().like('%scan%') |
                        assets.cameraModel.lower().like('%perfection%') |
                        assets.cameraMake.lower().like('%epson%')),
              )
              ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)]))
            .get();
    return [
      for (final z in zeilen)
        (
          asset: z.readTable(assets),
          vektor: floatsFromEmbeddingBlob(z.readTable(imageEmbeddings).vector),
        ),
    ];
  }

  /// Setzt die Aufnahmezeit auf die Mitte von [jahr] – und lässt sie als
  /// geschätzt markiert, denn das ist sie weiterhin.
  ///
  /// Der 1. Juli statt des 1. Januar: Ein Foto „um 1965" an den Neujahrstag
  /// zu legen, behauptet einen Tag, den niemand kennt, und es fiele in
  /// jeden Jahresrückblick auf genau diesen Tag.
  Future<void> setzeGeschaetztesJahr(String assetId, int jahr) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(
          fileCreatedAt: Value(DateTime(jahr, 7, 1, 12)),
          datumGeschaetzt: const Value(true),
          datumGeprueft: const Value(true),
        ),
      );

  /// Fotos ohne CLIP-Embedding – z.B. weil sie importiert wurden, bevor das
  /// CLIP-Modell installiert war (Embeddings werden sonst automatisch beim
  /// Import berechnet). Für das nachträgliche Berechnen in den Werkzeugen.
  /// [alle] nimmt auch Fotos mit, die schon ein Embedding haben – nötig,
  /// wenn sich die Bildvorverarbeitung geändert hat: Ein Vektor aus einem
  /// gestauchten Bild und einer aus einem mittig zugeschnittenen lassen
  /// sich nicht sinnvoll gegeneinander rechnen (siehe `_aufClipGroesse` in
  /// clip_service.dart).
  Future<List<AssetData>> assetsForEmbeddingBackfill({
    bool alle = false,
  }) async {
    final query =
        select(assets).join([
          leftOuterJoin(
            imageEmbeddings,
            imageEmbeddings.assetId.equalsExp(assets.id),
          ),
        ])..where(
          _auswertbar(assets) &
              assets.isTrashed.equals(false) &
              // Gesperrte Fotos ausgenommen, siehe [assetsForOcrBackfill]: Ein
              // CLIP-Embedding beschreibt den Bildinhalt und ist damit ebenso
              // wenig für die unverschlüsselte Datenbank gedacht.
              assets.isLocked.equals(false) &
              (alle ? const Constant(true) : imageEmbeddings.assetId.isNull()),
        );
    final rows = await query.get();
    return rows.map((r) => r.readTable(assets)).toList();
  }

  /// Zählvariante von [assetsForEmbeddingBackfill], siehe [countLocationBackfill].
  Future<int> countEmbeddingBackfill() async {
    final countExpr = assets.id.count();
    final query =
        selectOnly(assets).join([
            leftOuterJoin(
              imageEmbeddings,
              imageEmbeddings.assetId.equalsExp(assets.id),
            ),
          ])
          ..addColumns([countExpr])
          ..where(
            _auswertbar(assets) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false) &
                imageEmbeddings.assetId.isNull(),
          );
    final row = await query.getSingle();
    return row.read<int>(countExpr) ?? 0;
  }

  /// Bild-Assets, die für automatisches KI-Tagging infrage kommen (nicht
  /// gelöscht/gesperrt – gesperrte Fotos werden bewusst nicht verarbeitet,
  /// solange sie versteckt sind).
  ///
  /// Bei [onlyUntagged] nur Fotos, die noch nie durch die Verschlagwortung
  /// gelaufen sind ([Assets.aiTagsScanned]) UND noch keinen Tag tragen.
  /// Das Flag ist dabei das entscheidende Kriterium: Ein Foto, zu dem CLIP
  /// keinen passenden Begriff gefunden hat, bleibt für immer ohne Tags und
  /// wäre ohne das Flag bei jedem Lauf erneut Kandidat – siehe dort.
  /// Die zusätzliche Tag-Prüfung hält Fotos draussen, die vor Einführung
  /// des Flags bereits verschlagwortet wurden.
  ///
  /// Wer stattdessen "Alle" wählt, ergänzt passende KI-Tags auch bei
  /// bereits getaggten Fotos, ohne vorhandene (auch manuelle) Tags zu
  /// entfernen.
  Future<List<AssetData>> assetsForAiTagging({
    required bool onlyUntagged,
  }) async {
    if (!onlyUntagged) {
      return (select(assets)..where(
            (t) =>
                _auswertbar(t) &
                t.isTrashed.equals(false) &
                t.isLocked.equals(false),
          ))
          .get();
    }
    final query =
        select(assets).join([
          leftOuterJoin(assetTags, assetTags.assetId.equalsExp(assets.id)),
        ])..where(
          _auswertbar(assets) &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false) &
              assets.aiTagsScanned.equals(false) &
              assetTags.assetId.isNull(),
        );
    final rows = await query.get();
    return rows.map((r) => r.readTable(assets)).toList();
  }

  /// Vermerkt, dass ein Foto die Verschlagwortung durchlaufen hat –
  /// unabhängig davon, ob dabei Tags heraussprangen.
  Future<void> markAiTagsScanned(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        const AssetsCompanion(aiTagsScanned: Value(true)),
      );

  /// Zählvariante von [assetsForAiTagging], siehe [countLocationBackfill].
  Future<int> countAiTagging({required bool onlyUntagged}) async {
    if (!onlyUntagged) {
      return _countWhere(
        _auswertbar(assets) &
            assets.isTrashed.equals(false) &
            assets.isLocked.equals(false),
      );
    }
    final countExpr = assets.id.count();
    final query =
        selectOnly(assets).join([
            leftOuterJoin(assetTags, assetTags.assetId.equalsExp(assets.id)),
          ])
          ..addColumns([countExpr])
          ..where(
            _auswertbar(assets) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false) &
                // Muss deckungsgleich mit assetsForAiTagging bleiben, sonst zeigt
                // die Hintergrundaufgaben-Übersicht Wartende an, die keine sind.
                assets.aiTagsScanned.equals(false) &
                assetTags.assetId.isNull(),
          );
    final row = await query.getSingle();
    return row.read<int>(countExpr) ?? 0;
  }

  /// Lädt alle gespeicherten Embeddings (assetId -> Vektor) für die
  /// Brute-Force-Ähnlichkeitssuche im ClipService (KI-Suche & Duplikate).
  /// Über einen Join gegen Assets gefiltert, damit gelöschte oder gesperrte
  /// Fotos dort nicht auftauchen können.
  /// **Nur die zwei Spalten, die gebraucht werden.**
  ///
  /// Ein `join` in drift holt **jede Spalte jeder beteiligten Tabelle** und
  /// baut daraus Zeilenobjekte. Hier hing an jeder der 7475 Einbettungen
  /// eine vollständige Aufnahme mit 56 Spalten, die niemand ansieht. An der
  /// gewachsenen Bibliothek gemessen: **105 ms gegen 19,3 ms**, dasselbe
  /// Ergebnis.
  ///
  /// Der Verbund selbst bleibt – er ist die Bedingung („nicht im
  /// Papierkorb, nicht gesperrt"), nicht die Auskunft. Und `rawData` statt
  /// `read(spalte)`, aus demselben Grund wie in [assetsOnThisDay]: Der
  /// bequeme Weg schlägt jede Spalte über ihren Typ-Umsetzer nach.
  /// Videos, bei denen noch nicht nach weiteren Standbildern gesehen
  /// wurde (siehe [Assets.videobilderGeprueft]).
  ///
  /// Ohne Papierkorb und ohne Tresor, wie ueberall bei der Auswertung:
  /// Was im Bildinhalt steckt, hat in der unverschluesselten Datenbank
  /// nichts zu suchen.
  Expression<bool> _videobilderOffen(bool alle) =>
      assets.type.equals('VIDEO') &
      assets.isTrashed.equals(false) &
      assets.isLocked.equals(false) &
      (alle
          ? const CustomExpression<bool>('1')
          : assets.videobilderGeprueft.equals(false));

  Future<List<AssetData>> assetsFuerVideobilder({bool alle = false}) =>
      (select(assets)..where((_) => _videobilderOffen(alle))).get();

  /// Zaehlvariante von [assetsFuerVideobilder], siehe [countLocationBackfill].
  Future<int> countVideobilder({bool alle = false}) =>
      _countWhere(_videobilderOffen(alle));

  /// Nur die Videos, bei denen der zweite Blick etwas bringt: die ab
  /// [videoZweitblickAb].
  ///
  /// [countVideobilder] zaehlt alle 429 Videos der Produktivbibliothek,
  /// obwohl [videostandbildstellen] fuer 210 davon eine leere Liste
  /// liefert – bei einem Live-Photo-Fetzen von zwei Sekunden ist das eine
  /// vorhandene Standbild das ganze Video. Auf dem Gesundheitsbildschirm
  /// steht deshalb die kleinere, ehrliche Zahl (**219**).
  Future<int> countVideoZweitblick() => _countWhere(
    _videobilderOffen(false) &
        assets.durationSeconds.isBiggerOrEqualValue(
          videoZweitblickAb.inSeconds.toDouble(),
        ),
  );

  /// Schreibt die Einbettungen der zusaetzlichen Standbilder eines Videos
  /// – **die alten fallen dabei weg**.
  ///
  /// Ein zweiter Lauf ueber dasselbe Video soll es ersetzen und nicht
  /// verdoppeln; die Stellen koennen sich mit der Laufzeit aendern.
  Future<void> setzeVideoeinbettungen(
    String assetId,
    List<({double stelle, Uint8List vector})> bilder,
  ) async {
    await transaction(() async {
      await (delete(
        videoeinbettungen,
      )..where((t) => t.assetId.equals(assetId))).go();
      for (final b in bilder) {
        await into(videoeinbettungen).insert(
          VideoeinbettungenCompanion.insert(
            assetId: assetId,
            stelle: (b.stelle * 1000).round(),
            vector: b.vector,
          ),
        );
      }
      await (update(assets)..where((t) => t.id.equals(assetId))).write(
        const AssetsCompanion(videobilderGeprueft: Value(true)),
      );
    });
    _embeddingsGeneration++;
  }

  /// Merkt „nachgesehen" fuer Videos, bei denen nichts zu holen war –
  /// zu kurz, oder das Standbild liess sich nicht greifen.
  Future<void> markVideobilderGeprueft(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        const AssetsCompanion(videobilderGeprueft: Value(true)),
      );

  /// Die zusaetzlichen Einbettungen, nach Aufnahme gebuendelt – fuer die
  /// Suche, und nur fuer sie (siehe [Videoeinbettungen]).
  Future<Map<String, List<Float32List>>> alleVideoeinbettungen() async {
    final query =
        selectOnly(videoeinbettungen).join([
            innerJoin(assets, assets.id.equalsExp(videoeinbettungen.assetId)),
          ])
          ..addColumns([videoeinbettungen.assetId, videoeinbettungen.vector])
          ..where(
            assets.isTrashed.equals(false) & assets.isLocked.equals(false),
          );
    final out = <String, List<Float32List>>{};
    for (final z in await query.get()) {
      out
          .putIfAbsent(
            z.rawData.read<String>('videoeinbettungen.asset_id'),
            () => [],
          )
          .add(
            floatsFromEmbeddingBlob(
              z.rawData.read<Uint8List>('videoeinbettungen.vector'),
            ),
          );
    }
    return out;
  }

  Future<Map<String, Float32List>> allEmbeddings() async {
    final query =
        selectOnly(imageEmbeddings).join([
            innerJoin(assets, assets.id.equalsExp(imageEmbeddings.assetId)),
          ])
          ..addColumns([imageEmbeddings.assetId, imageEmbeddings.vector])
          ..where(
            assets.isTrashed.equals(false) & assets.isLocked.equals(false),
          );
    final out = <String, Float32List>{};
    for (final z in await query.get()) {
      out[z.rawData.read<String>(
        'image_embeddings.asset_id',
      )] = floatsFromEmbeddingBlob(
        z.rawData.read<Uint8List>('image_embeddings.vector'),
      );
    }
    return out;
  }
}
