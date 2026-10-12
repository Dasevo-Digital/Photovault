part of '../database.dart';

/// Entwicklungs- und Export-Vorgaben, Kamera-Presets, Automatisierung.
extension VorgabenAbfragen on AppDatabase {
  // -----------------------------------------------------------------------
  // Entwicklungs-Vorgaben (benannte Reglerstände)
  // -----------------------------------------------------------------------

  Stream<List<DevelopPresetData>> watchDevelopPresets() => (select(
    developPresets,
  )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Future<List<DevelopPresetData>> alleDevelopPresets() => (select(
    developPresets,
  )..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  /// Legt eine Vorgabe an oder aktualisiert sie – wie
  /// [upsertExportPreset], samt derselben Begründung: Der Konflikt wird
  /// über die Nummer aufgelöst, nicht über den Namen. Ein zweiter Eintrag
  /// mit belegtem Namen soll nicht stillschweigend den ersten
  /// überschreiben.
  Future<void> upsertDevelopPreset(DevelopPresetsCompanion vorgabe) =>
      into(developPresets).insertOnConflictUpdate(vorgabe);

  /// Ob [name] schon vergeben ist – [ausserId] nimmt die gerade
  /// bearbeitete Vorgabe aus.
  Future<bool> developPresetNameVergeben(String name, {int? ausserId}) async {
    final abfrage = select(developPresets)..where((t) => t.name.equals(name));
    if (ausserId != null) {
      abfrage.where((t) => t.id.equals(ausserId).not());
    }
    return (await abfrage.get()).isNotEmpty;
  }

  Future<void> deleteDevelopPreset(int id) =>
      (delete(developPresets)..where((t) => t.id.equals(id))).go();

  // -----------------------------------------------------------------------
  // Export-Voreinstellungen (benannte Ausgabe-Vorgaben)
  // -----------------------------------------------------------------------

  Stream<List<ExportPresetData>> watchExportPresets() => (select(
    exportPresets,
  )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Future<List<ExportPresetData>> alleExportPresets() =>
      (select(exportPresets)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  /// Legt eine Vorgabe an oder aktualisiert sie. Der Aufrufer setzt [id] nur
  /// beim Bearbeiten; ohne [id] vergibt SQLite eine neue.
  ///
  /// Der Konflikt wird über die Nummer aufgelöst, nicht über den Namen: Ein
  /// zweiter Eintrag mit belegtem Namen soll NICHT stillschweigend den
  /// ersten überschreiben, sondern an der `unique`-Spalte scheitern. Wer
  /// speichert, fragt vorher [exportPresetNameVergeben] und sagt es dem
  /// Nutzer – siehe ExportPresetsScreen.
  Future<void> upsertExportPreset(ExportPresetsCompanion vorgabe) =>
      into(exportPresets).insertOnConflictUpdate(vorgabe);

  /// Ob [name] schon vergeben ist – [ausserId] nimmt die gerade bearbeitete
  /// Vorgabe aus, sonst kollidierte jede Vorgabe mit sich selbst.
  Future<bool> exportPresetNameVergeben(String name, {int? ausserId}) async {
    final abfrage = select(exportPresets)..where((t) => t.name.equals(name));
    if (ausserId != null) {
      abfrage.where((t) => t.id.equals(ausserId).not());
    }
    return (await abfrage.get()).isNotEmpty;
  }

  Future<void> deleteExportPreset(int id) =>
      (delete(exportPresets)..where((t) => t.id.equals(id))).go();

  // -----------------------------------------------------------------------
  // Kamera-Presets (automatische Aktionen beim Import je erkannter Kamera)
  // -----------------------------------------------------------------------

  Stream<List<CameraPresetData>> watchCameraPresets() =>
      (select(cameraPresets)..orderBy([
            (t) => OrderingTerm.asc(t.cameraMake),
            (t) => OrderingTerm.asc(t.cameraModel),
          ]))
          .watch();

  /// Tag-Zuordnungen ALLER Presets auf einmal (presetId -> Tag-IDs), reaktiv
  /// – für die Presets-Liste, die sonst pro sichtbarer Kachel eine eigene
  /// Abfrage bräuchte (N+1, und bei einem einfachen `FutureBuilder` pro
  /// Kachel entweder bei jedem Rebuild neu abgefragt oder – bei
  /// zwischengespeichertem Future – nach einer Tag-Änderung veraltet
  /// stehenbleibt). Die Tabelle selbst ist immer klein (Presets × Tags pro
  /// Preset), ein voller Select ist hier günstiger als N Einzelabfragen.
  Stream<Map<String, List<String>>> watchAllCameraPresetTagIds() {
    return select(cameraPresetTags).watch().map((rows) {
      final map = <String, List<String>>{};
      for (final row in rows) {
        map.putIfAbsent(row.presetId, () => []).add(row.tagId);
      }
      return map;
    });
  }

  Future<void> upsertCameraPreset(CameraPresetsCompanion preset) =>
      into(cameraPresets).insertOnConflictUpdate(preset);

  Future<void> deleteCameraPreset(String id) async {
    await (delete(cameraPresetTags)..where((t) => t.presetId.equals(id))).go();
    await (delete(cameraPresets)..where((t) => t.id.equals(id))).go();
  }

  Future<List<String>> tagIdsForCameraPreset(String presetId) async {
    final rows = await (select(
      cameraPresetTags,
    )..where((t) => t.presetId.equals(presetId))).get();
    return rows.map((r) => r.tagId).toList();
  }

  /// Ersetzt die komplette Tag-Zuordnung eines Presets auf einmal (statt
  /// einzelner Hinzufügen-/Entfernen-Aufrufe) – der Editor übergibt bei
  /// jedem Speichern die vollständige, gewünschte Tag-Menge.
  Future<void> setCameraPresetTags(String presetId, List<String> tagIds) async {
    await (delete(
      cameraPresetTags,
    )..where((t) => t.presetId.equals(presetId))).go();
    if (tagIds.isEmpty) return;
    await batch((b) {
      b.insertAll(
        cameraPresetTags,
        tagIds.map(
          (tagId) => CameraPresetTagsCompanion.insert(
            presetId: presetId,
            tagId: tagId,
          ),
        ),
      );
    });
  }

  /// Das Preset für eine erkannte Kamera, falls eines existiert – `null`,
  /// solange Hersteller/Modell unbekannt sind (z.B. Videos ohne EXIF-Kamera)
  /// oder kein Preset für genau diese Kombination angelegt wurde. Bewusst
  /// über `.get()` + erste Zeile statt `getSingleOrNull()`, damit ein aus
  /// Versehen doppelt angelegtes Preset für dieselbe Kamera nicht den
  /// gesamten Importvorgang mit einer Exception abbricht.
  Future<CameraPresetData?> cameraPresetFor(
    String? cameraMake,
    String? cameraModel,
  ) async {
    if (cameraMake == null || cameraModel == null) return null;
    final rows =
        await (select(cameraPresets)
              ..where(
                (t) =>
                    t.cameraMake.equals(cameraMake) &
                    t.cameraModel.equals(cameraModel),
              )
              ..limit(1))
            .get();
    return rows.isEmpty ? null : rows.first;
  }

  // -----------------------------------------------------------------------
  // Automatisierungs-Regelwerk (Verallgemeinerung der Kamera-Presets auf
  // Ort/Datum/KI-Tag, siehe AutomationRules-Tabelle)
  // -----------------------------------------------------------------------

  Stream<List<AutomationRuleData>> watchAutomationRules() => (select(
    automationRules,
  )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  /// Alle Regeln auf einmal statt eines gezielten Lookups (anders als
  /// [cameraPresetFor]): die Bedingungen sind zu unterschiedlich geformt
  /// (Umkreis/Datumsbereich/KI-Tag), um sie in einem einzelnen SQL-WHERE
  /// zusammenzufassen – die Tabelle ist wie CameraPresets klein, ein voller
  /// Scan mit Auswertung in Dart (siehe LibraryState.applyAutomationRules)
  /// ist hier güngstiger als der Aufwand einer typspezifischen Abfrage.
  Future<List<AutomationRuleData>> allAutomationRules() =>
      select(automationRules).get();

  /// Tag-Zuordnungen ALLER Regeln auf einmal, reaktiv – siehe
  /// [watchAllCameraPresetTagIds] für die Begründung (N+1/Veralten
  /// vermeiden).
  Stream<Map<String, List<String>>> watchAllAutomationRuleTagIds() {
    return select(automationRuleTags).watch().map((rows) {
      final map = <String, List<String>>{};
      for (final row in rows) {
        map.putIfAbsent(row.ruleId, () => []).add(row.tagId);
      }
      return map;
    });
  }

  Future<void> upsertAutomationRule(AutomationRulesCompanion rule) =>
      into(automationRules).insertOnConflictUpdate(rule);

  Future<void> deleteAutomationRule(String id) async {
    await (delete(automationRuleTags)..where((t) => t.ruleId.equals(id))).go();
    await (delete(automationRules)..where((t) => t.id.equals(id))).go();
  }

  Future<List<String>> tagIdsForAutomationRule(String ruleId) async {
    final rows = await (select(
      automationRuleTags,
    )..where((t) => t.ruleId.equals(ruleId))).get();
    return rows.map((r) => r.tagId).toList();
  }

  /// Ersetzt die komplette Tag-Zuordnung einer Regel auf einmal, siehe
  /// [setCameraPresetTags].
  Future<void> setAutomationRuleTags(String ruleId, List<String> tagIds) async {
    await (delete(
      automationRuleTags,
    )..where((t) => t.ruleId.equals(ruleId))).go();
    if (tagIds.isEmpty) return;
    await batch((b) {
      b.insertAll(
        automationRuleTags,
        tagIds.map(
          (tagId) =>
              AutomationRuleTagsCompanion.insert(ruleId: ruleId, tagId: tagId),
        ),
      );
    });
  }

  Future<List<TagData>> tagsForAsset(String assetId) async {
    final query = select(tags).join([
      innerJoin(assetTags, assetTags.tagId.equalsExp(tags.id)),
    ])..where(assetTags.assetId.equals(assetId));
    final rows = await query.get();
    return rows.map((r) => r.readTable(tags)).toList();
  }

  /// Tag-Namen ALLER Assets in einer einzigen Abfrage (assetId -> Tag-Namen)
  /// – für den Metadaten-Export beim Backup, damit nicht pro Foto eine
  /// eigene Datenbankabfrage nötig ist ([tagsForAsset] wäre dort ein
  /// N+1-Problem, das bei großen Bibliotheken spürbar Zeit kostet).
  Future<Map<String, List<String>>> allTagNamesByAssetId() async {
    // Nur die zwei Spalten – siehe [allEmbeddings]. Hier sind es 25.761
    // Zeilen, aus denen sonst ebenso viele Paare von Zeilenobjekten
    // entstehen: 55 ms gegen 23 ms.
    final query = selectOnly(assetTags).join([
      innerJoin(tags, tags.id.equalsExp(assetTags.tagId)),
    ])..addColumns([assetTags.assetId, tags.name]);
    final result = <String, List<String>>{};
    for (final z in await query.get()) {
      result
          .putIfAbsent(z.rawData.read<String>('asset_tags.asset_id'), () => [])
          .add(z.rawData.read<String>('tags.name'));
    }
    return result;
  }

  /// Die BENANNTEN Gesichter aller Assets in einer einzigen Abfrage
  /// (assetId -> Regionen) – für den XMP-Export, aus demselben Grund wie
  /// [allTagNamesByAssetId]: pro Foto zwei Abfragen wären bei 8000
  /// Aufnahmen der teuerste Teil des Laufs.
  ///
  /// Nur benannte und nicht beiseitegelegte. Eine Region ohne Namen sagt
  /// dem Zielprogramm nur „hier ist irgendein Kopf", und das findet dessen
  /// eigene Erkennung selbst.
  Future<Map<String, List<Gesichtsregion>>> alleGesichtsregionen() async {
    // Nur die sechs Spalten, die gebraucht werden – siehe [allEmbeddings].
    // An jedem Gesicht hängt sonst seine 512er-Einbettung, zwei Kilobyte je
    // Zeile, die der XMP-Export nie ansieht: 11,2 ms gegen 3,9 ms.
    final abfrage =
        selectOnly(
            faces,
          ).join([innerJoin(people, people.id.equalsExp(faces.personId))])
          ..addColumns([
            faces.assetId,
            people.name,
            faces.boxX,
            faces.boxY,
            faces.boxW,
            faces.boxH,
          ])
          ..where(faces.personId.isNotNull() & faces.isIgnored.equals(false));
    final ergebnis = <String, List<Gesichtsregion>>{};
    for (final z in await abfrage.get()) {
      ergebnis
          .putIfAbsent(z.rawData.read<String>('faces.asset_id'), () => [])
          .add(
            Gesichtsregion(
              name: z.rawData.read<String>('people.name'),
              links: z.rawData.read<double>('faces.box_x'),
              oben: z.rawData.read<double>('faces.box_y'),
              breite: z.rawData.read<double>('faces.box_w'),
              hoehe: z.rawData.read<double>('faces.box_h'),
            ),
          );
    }
    return ergebnis;
  }

  /// Die benannten Gesichter EINES Fotos – für den Einzelexport, wo eine
  /// Abfrage über die ganze Bibliothek Verschwendung wäre.
  Future<List<Gesichtsregion>> gesichtsregionenVon(String assetId) async {
    final alle =
        await (select(faces)..where(
              (f) =>
                  f.assetId.equals(assetId) &
                  f.personId.isNotNull() &
                  f.isIgnored.equals(false),
            ))
            .get();
    if (alle.isEmpty) return const [];
    final namen = {
      for (final p in await (select(
        people,
      )..where((p) => p.id.isIn([for (final f in alle) f.personId!]))).get())
        p.id: p.name,
    };
    return [
      for (final f in alle)
        if (namen[f.personId] case final name?)
          Gesichtsregion(
            name: name,
            links: f.boxX,
            oben: f.boxY,
            breite: f.boxW,
            hoehe: f.boxH,
          ),
    ];
  }

  /// Wie [allTagNamesByAssetId], aber nur die Vorschläge der
  /// Bilderkennung – für die Sicherung.
  ///
  /// **Ohne diese Auskunft verlöre eine Rücksicherung die Herkunft.** Die
  /// Sicherung führt Schlagwörter als blosse Namen; alles käme als
  /// Handvergabe zurück, und der gesperrte Ordner stünde wieder da, wo er
  /// vor Fassung 56 stand – nur eben nach einem Umweg über eine Sicherung.
  Future<Map<String, Set<String>>> kiTagNamesByAssetId() async {
    // Nur die zwei Spalten – siehe [allEmbeddings].
    final query =
        selectOnly(
            assetTags,
          ).join([innerJoin(tags, tags.id.equalsExp(assetTags.tagId))])
          ..addColumns([assetTags.assetId, tags.name])
          ..where(assetTags.quelle.equals(Tagquelle.ki));
    final result = <String, Set<String>>{};
    for (final z in await query.get()) {
      result
          .putIfAbsent(
            z.rawData.read<String>('asset_tags.asset_id'),
            () => <String>{},
          )
          .add(z.rawData.read<String>('tags.name'));
    }
    return result;
  }
}
