part of '../database.dart';

/// Entwickeln, KI-Masken, Restaurierung, Video-Zuschnitt.
extension BearbeitungsAbfragen on AppDatabase {
  Future<List<({String assetId, String pfad, String sha256})>>
  variantenDateienZurPruefung() async => [
    for (final v in await customSelect(
      'SELECT DISTINCT asset_id, relative_path, sha256 FROM develop_variant_files LIMIT 200001',
    ).get())
      (
        assetId: v.read<String>('asset_id'),
        pfad: v.read<String>('relative_path'),
        sha256: v.read<String>('sha256'),
      ),
  ];
  Future<List<DevelopVariantData>> variantenFuer(String assetId) =>
      (select(developVariants)
            ..where((t) => t.assetId.equals(assetId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.updatedAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  Future<void> varianteSpeichern(DevelopVariantData variante) =>
      transaction(() async {
        final a = await assetById(variante.assetId);
        final stand = Entwicklungsstand.decode(variante.stateJson);
        final name = variante.name.trim();
        if (a == null ||
            a.isLocked ||
            a.isTrashed ||
            a.checksum != stand.originalSha256) {
          throw StateError('pv_variante_aufnahme');
        }
        if (name.isEmpty ||
            name.length > 80 ||
            !RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(variante.id) ||
            !erlaubterVariantenpfad(variante.previewRelativePath) ||
            !stand.dateien.containsKey(variante.previewRelativePath)) {
          throw const FormatException('pv_variante_format');
        }
        final vorhandene = await variantenFuer(variante.assetId);
        if (vorhandene.length >= 100 &&
            !vorhandene.any((v) => v.id == variante.id)) {
          throw StateError('pv_variante_umfang');
        }
        final alt = await (select(
          developVariants,
        )..where((t) => t.id.equals(variante.id))).getSingleOrNull();
        if (alt != null && alt.assetId != variante.assetId) {
          throw const FormatException('pv_variante_aufnahme');
        }
        if (alt != null &&
            (alt.stateJson != variante.stateJson ||
                alt.previewRelativePath != variante.previewRelativePath)) {
          throw StateError('pv_variante_unveraenderlich');
        }
        await into(
          developVariants,
        ).insertOnConflictUpdate(variante.copyWith(name: name));
        for (final e in stand.dateien.entries) {
          await into(developVariantFiles).insertOnConflictUpdate(
            DevelopVariantFilesCompanion.insert(
              variantId: variante.id,
              assetId: variante.assetId,
              relativePath: e.key,
              sha256: e.value,
            ),
          );
        }
      });

  Future<void> varianteEntfernen(String assetId, String id) => transaction(
    () async {
      final a = await assetById(assetId);
      if (a == null || a.isLocked) throw StateError('pv_variante_aufnahme');
      await (delete(
        developVariants,
      )..where((t) => t.id.equals(id) & t.assetId.equals(assetId))).go();
      await (delete(
        developVariantFiles,
      )..where((t) => t.variantId.equals(id) & t.assetId.equals(assetId))).go();
    },
  );

  Future<bool> varianteVerwendetDatei(String pfad) async {
    return (await (select(developVariantFiles)
              ..where((t) => t.relativePath.equals(pfad))
              ..limit(1))
            .get())
        .isNotEmpty;
  }

  Future<String> entwicklungsBasis(String assetId) async {
    final a = await assetById(assetId);
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'original': a?.checksum,
              'einstellungen': (await developSettingsForAsset(
                assetId,
              ))?.toJson(),
              'masken': [
                for (final m in await masksForAsset(assetId)) m.toJson(),
              ],
            }),
          ),
        )
        .toString();
  }

  Future<void> varianteAktivieren(
    String assetId,
    String id, {
    String? erwarteterStand,
  }) => transaction(() async {
    final a = await assetById(assetId);
    final v =
        await (select(developVariants)
              ..where((t) => t.id.equals(id) & t.assetId.equals(assetId)))
            .getSingleOrNull();
    if (a == null || a.isLocked || a.isTrashed || v == null) {
      throw StateError('pv_variante_aufnahme');
    }
    if (erwarteterStand != null &&
        await entwicklungsBasis(assetId) != erwarteterStand) {
      throw StateError('pv_offline_konflikt');
    }
    final stand = Entwicklungsstand.decode(v.stateJson);
    if (stand.originalSha256 != a.checksum) {
      throw StateError('pv_variante_original_geaendert');
    }
    await saveDevelopResult(
      assetId,
      settings: stand.einstellungen.copyWith(assetId: assetId),
      developedRelativePath: v.previewRelativePath,
    );
    await (delete(developMasks)..where((t) => t.assetId.equals(assetId))).go();
    for (final maske in stand.masken) {
      await into(developMasks).insert(maske.copyWith(assetId: assetId));
    }
  });
  // -----------------------------------------------------------------------
  // Nicht-destruktive Entwicklung (DevelopScreen)
  // -----------------------------------------------------------------------

  Future<DevelopSettingsData?> developSettingsForAsset(String assetId) =>
      (select(
        developSettings,
      )..where((t) => t.assetId.equals(assetId))).getSingleOrNull();

  /// Speichert die Entwicklungs-Einstellungen und das dazu gerenderte Bild
  /// in einer Transaktion, damit `Assets.developedRelativePath` nie auf
  /// eine DevelopSettings-Zeile zeigt, die (durch einen Fehler mittendrin)
  /// gar nicht existiert. Schiebt den bisherigen Stand (falls vorhanden)
  /// in [DevelopHistory] – ein einfacher, linearer Verlauf ohne
  /// Sonderfall-Restore-Pfad: lädt der Nutzer später einen Verlaufs-Eintrag
  /// in die Regler zurück und speichert erneut, landet der gerade ersetzte
  /// Stand wieder ganz normal hier in der Historie.
  ///
  /// **Nur ein echter Schritt (#288).** Ändert sich an den Einstellungen
  /// nichts – „Entwickelte Fotos neu rendern“ legt nur das Bild neu ab –,
  /// kommt nichts in den Verlauf. Bis 3.54 stand dort nach jedem Neu-Rendern
  /// ein Eintrag „ohne Änderung“, und weil der Verlauf nur zehn behält,
  /// verdrängten zehn Läufe jeden echten früheren Stand.
  ///
  /// **Der ganze Stand.** Klarheit, Vignette und Farbtabelle haben eigene
  /// Spalten im Verlauf, wurden aber bis 3.54 nicht hineingeschrieben: Ein
  /// zurückgeholter Stand kam mit Klarheit 0, ohne Vignette und mit voller
  /// Stärke der Farbtabelle zurück.
  Future<void> saveDevelopResult(
    String assetId, {
    required Insertable<DevelopSettingsData> settings,
    required String developedRelativePath,
  }) => transaction(() async {
    Future<DevelopSettingsData?> stand() => (select(
      developSettings,
    )..where((t) => t.assetId.equals(assetId))).getSingleOrNull();
    final previous = await stand();
    await into(developSettings).insertOnConflictUpdate(settings);
    await (update(assets)..where((t) => t.id.equals(assetId))).write(
      AssetsCompanion(developedRelativePath: Value(developedRelativePath)),
    );
    if (previous == null) return;
    final jetzt = await stand();
    if (jetzt != null &&
        previous.copyWith(updatedAt: jetzt.updatedAt) == jetzt) {
      return;
    }
    await into(developHistory).insert(
      DevelopHistoryCompanion.insert(
        assetId: assetId,
        cropJson: Value(previous.cropJson),
        exposure: previous.exposure,
        temperature: Value(previous.temperature),
        tint: Value(previous.tint),
        contrast: previous.contrast,
        shadows: previous.shadows,
        highlights: Value(previous.highlights),
        sharpness: previous.sharpness,
        noiseReduction: previous.noiseReduction,
        lensCorrectionEnabled: previous.lensCorrectionEnabled,
        clarity: Value(previous.clarity),
        vignette: Value(previous.vignette),
        lutPath: Value(previous.lutPath),
        lutStrength: Value(previous.lutStrength),
        toneCurveJson: Value(previous.toneCurveJson),
        colorMixerJson: Value(previous.colorMixerJson),
        createdAt: DateTime.now(),
      ),
    );
    await _pruneDevelopHistory(assetId);
  });

  /// Begrenzt [DevelopHistory] auf die neuesten [keep] Einträge pro Asset,
  /// damit die Tabelle bei Nutzern, die häufig speichern, nicht unbegrenzt
  /// wächst. Sortiert nach der Auto-Increment-`id` statt `createdAt` – die
  /// steigt garantiert streng mit jedem Insert, während zwei sehr schnell
  /// aufeinanderfolgende Speicher-Vorgänge (z.B. in Tests) denselben
  /// `DateTime.now()`-Millisekundenwert treffen könnten.
  Future<void> _pruneDevelopHistory(String assetId, {int keep = 10}) async {
    final rows =
        await (select(developHistory)
              ..where((t) => t.assetId.equals(assetId))
              ..orderBy([(t) => OrderingTerm.desc(t.id)]))
            .get();
    if (rows.length <= keep) return;
    final idsToDelete = rows.skip(keep).map((r) => r.id).toList();
    await (delete(developHistory)..where((t) => t.id.isIn(idsToDelete))).go();
  }

  /// Vergangene Entwickeln-Stände eines Assets, neueste zuerst (siehe
  /// [_pruneDevelopHistory] zur Sortierung nach `id` statt `createdAt`) –
  /// für den "Verlauf"-Einstieg im DevelopScreen.
  Future<List<DevelopHistoryData>> developHistoryForAsset(String assetId) =>
      (select(developHistory)
            ..where((t) => t.assetId.equals(assetId))
            ..orderBy([(t) => OrderingTerm.desc(t.id)]))
          .get();

  /// Setzt ein Asset auf unentwickelt zurück (Regler-"Zurücksetzen") – der
  /// Aufrufer löscht die zugehörige gerenderte Datei selbst von der Platte.
  Future<void> resetDevelopSettings(String assetId) => transaction(() async {
    await (delete(
      developSettings,
    )..where((t) => t.assetId.equals(assetId))).go();
    await (update(assets)..where((t) => t.id.equals(assetId))).write(
      const AssetsCompanion(developedRelativePath: Value(null)),
    );
  });

  /// Alle entwickelten Assets samt ihrer Einstellungen – für das
  /// "Entwickelte Fotos neu rendern"-Werkzeug (z.B. nach einer Änderung an
  /// der Render-Logik selbst).
  Future<List<(AssetData, DevelopSettingsData)>>
  assetsWithDevelopSettings() async {
    final query =
        select(assets).join([
            innerJoin(
              developSettings,
              developSettings.assetId.equalsExp(assets.id),
            ),
          ])
          // isLocked ausgeschlossen, damit das Bulk-Werkzeug ("Entwickelte
          // Fotos neu rendern") nie versucht, aus der verschlüsselten
          // Originaldatei eines gesperrten Assets zu rendern und das Ergebnis
          // unverschlüsselt in developed/ zu schreiben.
          ..where(
            assets.isTrashed.equals(false) & assets.isLocked.equals(false),
          );
    final rows = await query.get();
    return rows
        .map((r) => (r.readTable(assets), r.readTable(developSettings)))
        .toList();
  }

  /// Zählvariante von [assetsWithDevelopSettings], siehe [countLocationBackfill].
  /// [geaendertNach]: nur Entwicklungen, deren Einstellungen danach
  /// gespeichert wurden – siehe [Aufgabenlaeufe].
  Future<int> countAssetsWithDevelopSettings({DateTime? geaendertNach}) async {
    final countExpr = assets.id.count();
    final query =
        selectOnly(assets).join([
            innerJoin(
              developSettings,
              developSettings.assetId.equalsExp(assets.id),
            ),
          ])
          ..addColumns([countExpr])
          ..where(
            assets.isTrashed.equals(false) &
                assets.isLocked.equals(false) &
                (geaendertNach == null
                    ? const Constant(true)
                    : developSettings.updatedAt.isBiggerThanValue(
                        geaendertNach,
                      )),
          );
    final row = await query.getSingle();
    return row.read<int>(countExpr) ?? 0;
  }

  // -----------------------------------------------------------------------
  // KI-Objektmasken (MaskEditor, SegmentationService)
  // -----------------------------------------------------------------------

  /// Masken eines Assets in Erstellreihenfolge – der native Renderer
  /// (developImage) legt sie in genau dieser Reihenfolge übereinander.
  Future<List<DevelopMaskData>> masksForAsset(String assetId) =>
      (select(developMasks)
            ..where((t) => t.assetId.equals(assetId))
            // Nach dem Anlegen, nicht nach der Kennung: Die ist seit #109
            // zufällig, und die Reihenfolge entscheidet, welche Maske die
            // neueste ist und wie die Ebenen übereinanderliegen.
            ..orderBy([
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  /// Für die Bibliotheks-Integritätsprüfung – ein einzelner Full-Table-Select
  /// statt N+1-Abfragen pro Asset.
  Future<List<DevelopMaskData>> allDevelopMasks() => select(developMasks).get();

  Future<int> createDevelopMask(DevelopMasksCompanion mask) =>
      into(developMasks).insert(mask);

  /// Aktualisiert nur die Regler-Werte einer bereits vorhandenen Maske
  /// (Label/Maskendatei bleiben unverändert) – beim Speichern im
  /// Entwickeln-Screen, analog zu [saveDevelopResult] für die globalen
  /// Regler.
  Future<void> updateDevelopMaskAdjustments(
    int id,
    Insertable<DevelopMaskData> adjustments,
  ) => (update(developMasks)..where((t) => t.id.equals(id))).write(adjustments);

  /// Aktualisiert die Geometrie einer Vektor-Maske nach erneutem Bearbeiten
  /// ihrer Form (siehe MaskShapeDefinition/vector_mask_service.dart) – die
  /// gerenderte PNG-Datei selbst überschreibt der Aufrufer direkt (Muster
  /// wie [createDevelopMask]), hier wird nur die Quelle der Wahrheit
  /// (`shapeDefinitionJson`) aktualisiert.
  ///
  /// Mit [pfad] auch die neu gerechnete Maskendatei (#109).
  Future<void> updateDevelopMaskShape(
    int id,
    String shapeDefinitionJson, {
    String? pfad,
  }) => (update(developMasks)..where((t) => t.id.equals(id))).write(
    DevelopMasksCompanion(
      shapeDefinitionJson: Value(shapeDefinitionJson),
      maskRelativePath: pfad == null ? const Value.absent() : Value(pfad),
    ),
  );

  /// "Maske entfernen" – der Aufrufer löscht die zugehörige PNG-Datei selbst
  /// von der Platte (Muster wie [resetDevelopSettings]/[resetVideoTrim]).
  Future<void> deleteDevelopMask(int id) =>
      (delete(developMasks)..where((t) => t.id.equals(id))).go();

  // -----------------------------------------------------------------------
  // KI-Restaurierung (RestoreQueueService, RestoreService)
  // -----------------------------------------------------------------------

  Future<void> createRestoreJob(RestoreJobsCompanion job) =>
      into(restoreJobs).insert(job);

  /// Alle Aufträge, neueste zuerst – Grundlage für den Warteschlangen-
  /// Indikator (nur `queued`/`running` gefiltert vom Aufrufer) und den
  /// Warteschlangen-Screen (alle Status).
  Stream<List<RestoreJobData>> watchRestoreJobs() => (select(
    restoreJobs,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  /// Der älteste noch wartende Auftrag – FIFO, ein Auftrag gleichzeitig
  /// (siehe RestoreQueueService: parallele ONNX-Inferenzen würden sich nur
  /// um CPU/GPU streiten).
  Future<RestoreJobData?> nextQueuedRestoreJob() =>
      (select(restoreJobs)
            ..where((t) => t.status.equals('queued'))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  /// Bereits wartender/laufender Auftrag für dieses Asset, falls vorhanden
  /// – verhindert in [RestoreQueueService.enqueue] doppelte Aufträge für
  /// dasselbe Foto (z.B. durch einen Doppelklick).
  Future<RestoreJobData?> activeRestoreJobForAsset(String assetId) =>
      (select(restoreJobs)
            ..where(
              (t) =>
                  t.assetId.equals(assetId) &
                  t.status.isIn(['queued', 'running']),
            )
            ..limit(1))
          .getSingleOrNull();

  Future<void> updateRestoreJobProgress(
    String id,
    int tilesDone,
    int tilesTotal,
  ) => (update(restoreJobs)..where((t) => t.id.equals(id))).write(
    RestoreJobsCompanion(
      tilesDone: Value(tilesDone),
      tilesTotal: Value(tilesTotal),
    ),
  );

  /// Setzt einen durch neue Benutzereingabe angehaltenen Auftrag an den
  /// Anfang seines nächsten vollständigen Durchgangs zurück. Teilkacheln
  /// sind bewusst nicht wiederverwendbar: Erst das gesamte Bild ist ein
  /// gültiges Restaurierungsergebnis.
  Future<void> requeueRestoreJob(String id) async {
    await transaction(() async {
      await markRestoreJobStatus(id, 'queued');
      await updateRestoreJobProgress(id, 0, 0);
    });
  }

  Future<void> markRestoreJobStatus(
    String id,
    String status, {
    String? errorMessage,
  }) => (update(restoreJobs)..where((t) => t.id.equals(id))).write(
    RestoreJobsCompanion(
      status: Value(status),
      errorMessage: Value(errorMessage),
      // Beim Anlaufen die Startzeit setzen, beim Zurücksetzen auf
      // „wartet" wieder löschen: Ein hängengebliebener Auftrag wird
      // neu eingereiht (siehe resetStuckRunningRestoreJobs), und
      // seine alte Startzeit ergäbe beim zweiten Anlauf eine
      // Restzeit von mehreren Stunden.
      startedAt: switch (status) {
        'running' => Value(DateTime.now()),
        'queued' => const Value(null),
        _ => const Value.absent(),
      },
      completedAt: Value(
        status == 'queued' || status == 'running' ? null : DateTime.now(),
      ),
    ),
  );

  Future<void> deleteRestoreJob(String id) =>
      (delete(restoreJobs)..where((t) => t.id.equals(id))).go();

  /// Trägt das Ergebnis einer Restaurierung oder des KI-Entrauschens ein
  /// (Befehl RestaurierungSpeichern). Den Auftrag schliesst der Aufrufer
  /// selbst ab: Der Befehl geht an den Server, die Warteschlange nicht.
  Future<void> setzeRestauriert(String assetId, String restoredRelativePath) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(restoredRelativePath: Value(restoredRelativePath)),
      );

  /// Nimmt eine Restaurierung zurück (Befehl RestaurierungZuruecksetzen).
  /// Die Datei löscht der Aufrufer.
  Future<void> verwirfRestaurierung(String assetId) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        const AssetsCompanion(restoredRelativePath: Value(null)),
      );

  /// Crash-Safety: setzt beim App-Start jeden Auftrag, der beim letzten
  /// Beenden noch `running` war (die App wurde mitten in der Verarbeitung
  /// beendet/ist abgestürzt), zurück auf `queued` – ohne Teil-Kacheln zu
  /// persistieren, läuft er beim nächsten Warteschlangen-Durchlauf komplett
  /// neu. Siehe LibraryState.initialize().
  Future<void> resetStuckRunningRestoreJobs() =>
      (update(restoreJobs)..where((t) => t.status.equals('running'))).write(
        const RestoreJobsCompanion(
          status: Value('queued'),
          tilesDone: Value(0),
          tilesTotal: Value(0),
        ),
      );

  // -----------------------------------------------------------------------
  // Nicht-destruktiver Video-Zuschnitt (VideoTrimScreen)
  // -----------------------------------------------------------------------

  Future<VideoTrimData?> videoTrimForAsset(String assetId) => (select(
    videoTrims,
  )..where((t) => t.assetId.equals(assetId))).getSingleOrNull();

  /// Speichert Start/Ende und das dazu geschnittene Video in einer
  /// Transaktion, analog zu [saveDevelopResult] – `Assets.trimmedRelativePath`
  /// zeigt nie auf eine VideoTrims-Zeile, die (durch einen Fehler
  /// mittendrin) gar nicht existiert.
  Future<void> saveVideoTrim(
    String assetId, {
    required double startSeconds,
    required double endSeconds,
    required String trimmedRelativePath,
  }) => transaction(() async {
    await into(videoTrims).insertOnConflictUpdate(
      VideoTrimsCompanion.insert(
        assetId: assetId,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        updatedAt: DateTime.now(),
      ),
    );
    await (update(assets)..where((t) => t.id.equals(assetId))).write(
      AssetsCompanion(trimmedRelativePath: Value(trimmedRelativePath)),
    );
  });

  /// Setzt ein Video auf den Originalausschnitt zurück (Zuschneiden-
  /// "Zurücksetzen") – der Aufrufer löscht die zugehörige geschnittene
  /// Datei selbst von der Platte.
  Future<void> resetVideoTrim(String assetId) => transaction(() async {
    await (delete(videoTrims)..where((t) => t.assetId.equals(assetId))).go();
    await (update(assets)..where((t) => t.id.equals(assetId))).write(
      const AssetsCompanion(trimmedRelativePath: Value(null)),
    );
  });
}
