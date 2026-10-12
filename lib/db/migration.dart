part of 'database.dart';

/// Anlegen und Aufstufen des Schemas: Indizes, Volltextsuche, Hilfen der Migration.
extension Migrationsschritte on AppDatabase {
  Future<void> _createAssetSearchFts() async {
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS asset_search_fts USING fts5(
        asset_id UNINDEXED,
        original_file_name,
        description,
        ocr_text,
        ai_caption,
        ai_caption_de,
        tokenize = 'unicode61 remove_diacritics 2'
      )
    ''');
    await customStatement('DELETE FROM asset_search_fts');
    await customStatement('''
      INSERT INTO asset_search_fts
        (asset_id, original_file_name, description, ocr_text, ai_caption, ai_caption_de)
      SELECT id, original_file_name, coalesce(description, ''),
             coalesce(ocr_text, ''), coalesce(ai_caption, ''),
             coalesce(ai_caption_de, '')
      FROM assets
    ''');
    await _createAssetSearchTriggers();
  }

  /// Die drei Auslöser, die den Volltextindex mitführen.
  ///
  /// Eigene Methode, weil die Wanderung auf 84 **nur sie** neu setzt: Der
  /// Index selbst bleibt gültig, ihn dabei neu aufzubauen wäre für 8098
  /// Aufnahmen umsonst getane Arbeit.
  Future<void> _createAssetSearchTriggers() async {
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS assets_fts_insert AFTER INSERT ON assets BEGIN
        INSERT INTO asset_search_fts
          (asset_id, original_file_name, description, ocr_text, ai_caption, ai_caption_de)
        VALUES (new.id, new.original_file_name, coalesce(new.description, ''),
                coalesce(new.ocr_text, ''), coalesce(new.ai_caption, ''),
                coalesce(new.ai_caption_de, ''));
      END
    ''');
    // **`UPDATE OF` genügt nicht.** Es feuert, sobald eine der Spalten in
    // der SET-Klausel STEHT – nicht erst, wenn sich ihr Wert ändert. drift
    // schreibt bei `update(...).write(...)` regelmässig ganze Zeilen zurück,
    // und die Durchgänge (Texterkennung, Bildbeschreibung) tun das für die
    // ganze Bibliothek. Gemessen kostet ein Zeilen-UPDATE mit Auslöser
    // 1,56 ms gegen 0,03 ms ohne – das Zweiundfünfzigfache, und eine
    // Transaktion hilft kaum, weil der Preis das Neuschreiben des Index ist
    // und nicht das Sichern auf die Platte. Über 8098 Aufnahmen sind das
    // rund neun Sekunden je Durchgang, für lauter unveränderten Text.
    //
    // `IS NOT` und nicht `<>`: Nur `IS NOT` vergleicht NULL richtig. Mit
    // `<>` wäre jeder Übergang von oder nach NULL unbemerkt geblieben – und
    // genau so sieht das erste Beschreiben eines leeren Feldes aus.
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS assets_fts_update
      AFTER UPDATE OF original_file_name, description, ocr_text, ai_caption, ai_caption_de
      ON assets
      WHEN new.original_file_name IS NOT old.original_file_name
        OR new.description IS NOT old.description
        OR new.ocr_text IS NOT old.ocr_text
        OR new.ai_caption IS NOT old.ai_caption
        OR new.ai_caption_de IS NOT old.ai_caption_de
      BEGIN
        DELETE FROM asset_search_fts WHERE asset_id = old.id;
        INSERT INTO asset_search_fts
          (asset_id, original_file_name, description, ocr_text, ai_caption, ai_caption_de)
        VALUES (new.id, new.original_file_name, coalesce(new.description, ''),
                coalesce(new.ocr_text, ''), coalesce(new.ai_caption, ''),
                coalesce(new.ai_caption_de, ''));
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS assets_fts_delete AFTER DELETE ON assets BEGIN
        DELETE FROM asset_search_fts WHERE asset_id = old.id;
      END
    ''');
  }

  /// Bestückt AiTagVocabulary mit dem ursprünglichen, festen Begriffs-Array
  /// – für Neuinstallationen ([onCreate], das NICHT durch [onUpgrade] läuft)
  /// ebenso wie für das Upgrade bestehender Installationen auf v24.
  Future<void> _seedAiTagVocabulary() => batch(
    (b) => b.insertAll(aiTagVocabulary, [
      for (final term in defaultAiTagVocabulary)
        AiTagVocabularyCompanion.insert(term: term),
    ]),
  );

  /// Indizes für die im Betrieb häufigsten Filter/Sortierungen – ohne sie
  /// degenerieren mehrere Abfragen (Timeline/Alben/Personen-Ansicht, die
  /// Personen-/Album-Filter in [searchAssets]) bei wachsender Bibliothek zu
  /// vollständigen Tabellen-Scans, siehe die einzelnen Abfragen weiter unten.
  /// In einer eigenen Methode, damit sowohl frisch angelegte Datenbanken
  /// ([onCreate]) als auch bestehende (Migration `from < 11`) dieselben
  /// Indizes bekommen.
  /// Der Index für „gehört diese Aufnahme schon zu einer Reise?".
  ///
  /// In einer eigenen Routine und aus **beiden** Wegen aufgerufen – aus
  /// [onCreate] wie aus der Migration. Ein Index, den nur bestehende
  /// Bibliotheken bekommen, fehlt genau dort, wo niemand ihn vermisst:
  /// bei der Neuinstallation.
  Future<void> _createIndicesV51(Migrator m) => customStatement(
    'CREATE INDEX IF NOT EXISTS idx_reise_aufnahme_asset '
    'ON reise_aufnahmen (asset_id)',
  );

  Future<void> _createIndicesV55(Migrator m) async {
    // Die Punkte einer Spur werden immer am Stück und in ihrer
    // Reihenfolge geholt; ohne Index wäre das bei zehntausend Punkten je
    // Spur ein Durchlauf über alle Spuren.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_spurpunkte_spur '
      'ON spurpunkte (spur_id, nummer)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_spuren_aktivitaet '
      'ON spuren (aktivitaet_id)',
    );
  }

  Future<void> _createIndicesV54(Migrator m) async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_aktivitaet_aufnahme_asset '
      'ON aktivitaet_aufnahmen (asset_id)',
    );
    // Die Aktivitäten einer Reise werden bei jedem Öffnen einer Reise
    // geholt; ohne Index ist das ein Durchlauf über alle.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_aktivitaeten_reise '
      'ON aktivitaeten (reise_id)',
    );
  }

  Future<void> _createPerformanceIndices(Migrator m) async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_assets_trashed_locked_created '
      'ON assets (is_trashed, is_locked, file_created_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_assets_location '
      'ON assets (location_country, location_state, location_city)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_faces_asset_id ON faces (asset_id)',
    );
    // Teilindex, nicht vollständig: Nur ein kleiner Teil aller Gesichter ist
    // beiseitegelegt, und genau danach wird gefragt. Gemessen an 17.836
    // Gesichtern / 7.988 Fotos: ohne Index 8,3 ms, mit Teilindex 0,49 ms.
    // Ein vollständiger Index über is_ignored brachte nichts – der Planer
    // benutzt ihn nicht, weil die Spalte für den Regelfall (0) nichts
    // eingrenzt.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_faces_ignored '
      'ON faces (is_ignored) WHERE is_ignored = 1',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_faces_person_id ON faces (person_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_album_assets_asset_id ON album_assets (asset_id)',
    );
  }

  /// Zusätzliche Indizes ab Version 14: Papierkorb-Sortierung nach Alter
  /// (für den automatischen Ablauf sowie die Papierkorb-Ansichten),
  /// Kartenansicht (nur Fotos mit GPS-Koordinaten) und Backup-Status – alle
  /// drei filtern bei einer sehr großen Bibliothek sonst auf einem
  /// Großteil der Tabelle, ohne dass die bestehenden Indizes (siehe
  /// [_createPerformanceIndices]) dafür etwas hergeben. Die Teilindizes
  /// ("WHERE ...") halten die jeweils indexierte Zeilenmenge klein (nur
  /// GPS-Fotos bzw. noch nicht gesicherte Fotos) statt die komplette
  /// Tabelle zu indexieren.
  Future<void> _createIndicesV14(Migrator m) async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_assets_trashed_at '
      'ON assets (is_trashed, trashed_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_assets_gps '
      'ON assets (latitude, longitude) WHERE latitude IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_assets_not_backed_up '
      'ON assets (is_trashed, is_locked) WHERE backed_up = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_assets_not_auto_backed_up '
      'ON assets (is_trashed, is_locked) WHERE auto_backed_up = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_assets_camera '
      'ON assets (camera_make, camera_model)',
    );
  }

  /// Füllt [Assets.dateiformat] für den Bestand aus dem Dateinamen.
  ///
  /// **Eine einzige Anweisung, nicht ein Aufruf je Foto.** Bei 8.000
  /// Fotos wäre der Unterschied noch zu verschmerzen; bei 100.000 wäre es
  /// eine Migration, bei der man denkt, die App sei hängen geblieben.
  ///
  /// Die Endung ist alles hinter dem LETZTEN Punkt – `rindex` statt
  /// `instr`. Ein Dateiname wie `Urlaub.2019.jpg` hat zwei Punkte, und
  /// `2019.jpg` wäre kein Format.
  ///
  /// Namen ohne Punkt bleiben `NULL`: Sie haben kein Format, und das ist
  /// etwas anderes als ein unbekanntes.
  Future<void> _trageDateiformateNach() => customStatement(
    'UPDATE assets SET dateiformat = nullif(lower(substr('
    '  original_file_name,'
    '  length(rtrim(original_file_name,'
    "    replace(original_file_name, '.', ''))) + 1)), '') "
    'WHERE dateiformat IS NULL '
    "  AND instr(original_file_name, '.') > 0",
  );

  /// Index für den Formatfilter. Teilindex: Fotos ohne Format sind der
  /// seltene Fall und werden nie gesucht.
  Future<void> _createIndicesV48(Migrator m) => customStatement(
    'CREATE INDEX IF NOT EXISTS idx_assets_dateiformat '
    'ON assets (dateiformat) WHERE dateiformat IS NOT NULL',
  );

  /// Legt [spalte] nur an, wenn sie in [tabellenName] noch fehlt.
  ///
  /// Bestimmt für vorhandene Zuordnungen nachträglich die Herkunft.
  ///
  /// **Das ist eine Vermutung, und sie muss eine bleiben.** Bis Fassung 56
  /// stand nirgends, wer ein Schlagwort vergeben hat; rückwirkend lässt es
  /// sich nur erschliessen. Die Regel ist bewusst eng:
  ///
  /// Als `ki` gilt eine Zuordnung nur, wenn **beides** zutrifft – der
  /// Begriff steht im Vokabular der Bilderkennung, **und** das Foto ist
  /// nachweislich durch die Verschlagwortung gelaufen (`ai_tags_scanned`).
  /// Nur solche Zeilen kann die Bilderkennung überhaupt erzeugt haben.
  ///
  /// **Was schiefgehen kann, und was es kostet:** Wer selbst „Strand" an
  /// ein Foto geschrieben hat, das später durch die Verschlagwortung lief,
  /// bekommt seine Zuordnung als `ki` gestempelt. Beim Sperren dieses Fotos
  /// verschwindet sie dann – und kommt beim Entsperren zurück, sofern die
  /// Bilderkennung sie erneut vorschlägt. Der Schaden trifft also nur, wer
  /// ein Foto sperrt, und auch dort nur einen Begriff, den das Programm
  /// ohnehin für passend hält.
  ///
  /// Andersherum wäre der Schaden dauerhaft: Alles auf `hand` zu stempeln
  /// hiesse, dass in jeder gewachsenen Bibliothek genau die Schlagwörter
  /// weiter im Klartext stehen, deretwegen diese Spalte angelegt wurde.
  Future<void> _bestimmeTagquelleNachtraeglich() => customUpdate(
    'UPDATE asset_tags SET quelle = ? '
    'WHERE tag_id IN (SELECT t.id FROM tags t '
    '                 JOIN ai_tag_vocabulary v ON v.term = t.name) '
    '  AND asset_id IN (SELECT a.id FROM assets a '
    '                   WHERE a.ai_tags_scanned = 1)',
    variables: const [Variable<String>(Tagquelle.ki)],
    updates: {assetTags},
  );

  /// Schützt gegen den Fall, dass eine Datenbank bereits auf eine
  /// Schemaversion gestempelt wurde, deren Migration die Spalte gar nicht
  /// angelegt hat – dann würde ein blindes addColumn beim Nachholen mit
  /// "duplicate column" scheitern und der Start bräche ab.
  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo table,
    GeneratedColumn spalte,
    String tabellenName,
    String spaltenName,
  ) async {
    final vorhanden = await customSelect(
      'PRAGMA table_info($tabellenName)',
    ).get();
    final namen = vorhanden.map((r) => r.data['name'] as String).toSet();
    if (namen.contains(spaltenName)) return;
    await m.addColumn(table, spalte);
  }

  /// **Die Schritte stehen aufsteigend, und das ist eine Zusage.**
  ///
  /// Ein Schritt darf voraussetzen, was die niedrigeren angelegt
  /// haben – Schritt 65 biegt Zuordnungen in `aktivitaet_aufnahmen`
  /// um, und diese Tabelle entsteht in Schritt 54.
  ///
  /// Ab Schritt 48 standen sie einmal absteigend: 71, 70, 69 … 48.
  /// Fuer eine Bibliothek ab Fassung 54 fiel das nie auf, weil die
  /// betroffenen Schritte dort gar nicht mehr laufen. Eine aeltere
  /// liess sich dagegen **gar nicht mehr oeffnen** – Schritt 65
  /// schrieb in eine Tabelle, die Schritt 54 erst spaeter anlegte,
  /// und die Migration brach mit „no such table" ab. Gefunden an
  /// einer Bibliothek der Fassung 27 (30.08. angelegt, nie wieder
  /// geoeffnet), nicht durch Codelesen.
  ///
  /// `pruefstand_migration_reihenfolge_test.dart` haelt die
  /// Reihenfolge fest, damit ein neuer Schritt nicht wieder oben
  /// einsortiert wird.
  Future<void> stufeAuf(Migrator m, int from, int to) async {
    if (from < 2) {
      await m.addColumn(assets, assets.facesScanned);
    }
    if (from < 3) {
      await m.addColumn(assets, assets.previewRelativePath);
    }
    if (from < 4) {
      await m.addColumn(assets, assets.linkedAssetId);
    }
    if (from < 5) {
      await m.addColumn(assets, assets.latitude);
      await m.addColumn(assets, assets.longitude);
    }
    if (from < 6) {
      await m.addColumn(assets, assets.isLocked);
      await m.createTable(privacySettings);
    }
    if (from < 7) {
      await m.addColumn(privacySettings, privacySettings.kdfSalt);
      await m.addColumn(privacySettings, privacySettings.wrappedMasterKeyNonce);
      await m.addColumn(privacySettings, privacySettings.wrappedMasterKey);
      // Das alte Schema (Version 6) hat "gesperrte" Fotos nie
      // tatsächlich verschlüsselt, nur aus den normalen Ansichten
      // gefiltert. Ein bestehender PIN-Hash lässt sich nicht sicher
      // ins neue Master-Key-Schema übernehmen (der Klartext-PIN ist
      // aus einem Hash nicht rekonstruierbar) – deshalb hier
      // zurückgesetzt. Da unter Version 6 ohnehin nie verschlüsselt
      // wurde, ist "entsperren" das einzig korrekte Verhalten (es
      // geht nichts verloren, nur der PIN-Schutz muss neu
      // eingerichtet werden, jetzt mit echter Verschlüsselung).
      await (update(assets)..where((t) => t.isLocked.equals(true))).write(
        const AssetsCompanion(isLocked: Value(false)),
      );
      await delete(privacySettings).go();
    }
    if (from < 8) {
      await m.addColumn(assets, assets.autoBackedUp);
      await m.createTable(backupSettings);
    }
    if (from < 9) {
      await m.addColumn(assets, assets.cameraMake);
      await m.addColumn(assets, assets.cameraModel);
      await m.addColumn(assets, assets.lensModel);
      await m.addColumn(assets, assets.focalLengthMm);
      await m.addColumn(assets, assets.fNumber);
      await m.addColumn(assets, assets.iso);
      await m.addColumn(assets, assets.exposureTimeSeconds);
    }
    if (from < 10) {
      await m.addColumn(assets, assets.locationCountry);
      await m.addColumn(assets, assets.locationState);
      await m.addColumn(assets, assets.locationCity);
    }
    if (from < 11) {
      await _createPerformanceIndices(m);
    }
    if (from < 12) {
      await m.createTable(savedSearches);
    }
    if (from < 13) {
      await m.createTable(trashSettings);
    }
    if (from < 14) {
      await _createIndicesV14(m);
    }
    if (from < 15) {
      await m.createTable(cameraPresets);
      await m.createTable(cameraPresetTags);
    }
    if (from < 16) {
      await m.addColumn(assets, assets.developedRelativePath);
      await m.createTable(developSettings);
    }
    if (from < 17) {
      await m.addColumn(assets, assets.rating);
      await m.addColumn(assets, assets.colorLabel);
      await m.addColumn(assets, assets.ocrText);
      await m.addColumn(assets, assets.ocrScanned);
      await m.addColumn(assets, assets.sharpnessScore);
    }
    if (from < 18) {
      await m.createTable(developHistory);
    }
    if (from < 19) {
      await m.addColumn(assets, assets.trimmedRelativePath);
      await m.createTable(videoTrims);
    }
    if (from < 20) {
      await m.addColumn(assets, assets.stackId);
      await m.addColumn(assets, assets.isStackCover);
      await m.addColumn(assets, assets.stackSize);
    }
    if (from < 21) {
      await m.createTable(developMasks);
    }
    if (from < 22) {
      await m.addColumn(assets, assets.aiCaption);
      await m.addColumn(assets, assets.aiCaptionScanned);
    }
    if (from < 23) {
      await m.createTable(appSettings);
    }
    if (from < 24) {
      await m.createTable(aiTagVocabulary);
      await _seedAiTagVocabulary();
    }
    if (from < 25) {
      await m.addColumn(faces, faces.eyeOpenScore);
    }
    if (from < 26) {
      await m.addColumn(developMasks, developMasks.shapeDefinitionJson);
    }
    if (from < 27) {
      await m.addColumn(assets, assets.restoredRelativePath);
      await m.createTable(restoreJobs);
    }
    if (from < 28) {
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.autoAnalyzeAfterImport,
        'app_settings',
        'auto_analyze_after_import',
      );
    }
    if (from < 29) {
      // Beide bewusst nachgeholt: Eine fehlerhafte Zwischenfassung hat
      // Datenbanken als Version 28 gestempelt, ohne die zugehörige
      // Spalte anzulegen. Ohne dieses Nachholen bliebe eine so
      // markierte Datenbank dauerhaft unbrauchbar, weil Drift die
      // Migration für erledigt hält und nie erneut ausführt.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.autoAnalyzeAfterImport,
        'app_settings',
        'auto_analyze_after_import',
      );
      await _addColumnIfMissing(
        m,
        backupSettings,
        backupSettings.autoBackupMaxMbPerRun,
        'backup_settings',
        'auto_backup_max_mb_per_run',
      );
    }
    if (from < 30) {
      await m.createTable(automationRules);
      await m.createTable(automationRuleTags);
    }
    if (from < 31) {
      await _addColumnIfMissing(
        m,
        assets,
        assets.aiTagsScanned,
        'assets',
        'ai_tags_scanned',
      );
    }
    if (from < 32) {
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.watchedFolderPath,
        'app_settings',
        'watched_folder_path',
      );
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.watchedFolderToken,
        'app_settings',
        'watched_folder_token',
      );
    }
    if (from < 33) {
      // Tonwertkurve und Farbmischer. Beide nullable, `null` = neutral
      // – vorhandene Entwicklungen bleiben dadurch unverändert
      // gültig, es ist nichts nachzutragen.
      await _addColumnIfMissing(
        m,
        developSettings,
        developSettings.toneCurveJson,
        'develop_settings',
        'tone_curve_json',
      );
      await _addColumnIfMissing(
        m,
        developSettings,
        developSettings.colorMixerJson,
        'develop_settings',
        'color_mixer_json',
      );
      await _addColumnIfMissing(
        m,
        developHistory,
        developHistory.toneCurveJson,
        'develop_history',
        'tone_curve_json',
      );
      await _addColumnIfMissing(
        m,
        developHistory,
        developHistory.colorMixerJson,
        'develop_history',
        'color_mixer_json',
      );
    }
    if (from < 34) {
      // Lernende Gesichtserkennung. Ohne Rückmeldungen verhält sich
      // alles wie bisher: Die persönliche Schwelle bleibt null, es
      // gilt die allgemeine.
      await m.createTable(faceMatchFeedback);
      await _addColumnIfMissing(
        m,
        people,
        people.similarityThreshold,
        'people',
        'similarity_threshold',
      );
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.faceSimilarityThreshold,
        'app_settings',
        'face_similarity_threshold',
      );
    }
    if (from < 35) {
      // Übersetzung. Beide Schalter stehen auf aus, vorhandene
      // englische Beschreibungen bleiben unangetastet – erst wer die
      // Modelle installiert und den Schalter umlegt, bekommt Deutsch.
      await _addColumnIfMissing(
        m,
        assets,
        assets.aiCaptionDe,
        'assets',
        'ai_caption_de',
      );
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.translateCaptions,
        'app_settings',
        'translate_captions',
      );
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.translateSearchAndTags,
        'app_settings',
        'translate_search_and_tags',
      );
    }
    if (from < 36) {
      // Oberflächensprache. Standard 'system' – für bestehende
      // Installationen ändert sich damit nichts, solange das System
      // auf Deutsch steht.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.sprache,
        'app_settings',
        'sprache',
      );
    }
    if (from < 37) {
      // Export-Voreinstellungen. Eine neue, anfangs leere Tabelle –
      // ohne eine einzige gespeicherte Vorgabe verhält sich der Export
      // wie bisher, die vier festen Grössen bleiben erhalten.
      await m.createTable(exportPresets);
    }
    if (from < 38) {
      // Ignorierte Gesichter. Ein Merkmal an der bestehenden Tabelle,
      // keine eigene: Die Alternative wäre eine Ausschlussliste
      // gewesen, die bei jeder Abfrage mitgejoint werden müsste – für
      // eine Eigenschaft, die genau ein Gesicht betrifft.
      await _addColumnIfMissing(
        m,
        faces,
        faces.isIgnored,
        'faces',
        'is_ignored',
      );
      // Erst nach der Spalte – ein Index auf eine noch nicht
      // existierende Spalte scheitert.
      await _createPerformanceIndices(m);
    }
    if (from < 39) {
      // Klarheit, Vignettierung und importierte Farbtabellen – in
      // beiden Tabellen, damit der Verlauf nichts fallen lässt.
      // Ausgeschrieben statt in einer Schleife: Über beide Tabellen zu
      // laufen verliert deren konkreten Typ und damit die Spalten.
      await _addColumnIfMissing(
        m,
        developSettings,
        developSettings.clarity,
        'develop_settings',
        'clarity',
      );
      await _addColumnIfMissing(
        m,
        developSettings,
        developSettings.vignette,
        'develop_settings',
        'vignette',
      );
      await _addColumnIfMissing(
        m,
        developSettings,
        developSettings.lutPath,
        'develop_settings',
        'lut_path',
      );
      await _addColumnIfMissing(
        m,
        developSettings,
        developSettings.lutStrength,
        'develop_settings',
        'lut_strength',
      );
      await _addColumnIfMissing(
        m,
        developHistory,
        developHistory.clarity,
        'develop_history',
        'clarity',
      );
      await _addColumnIfMissing(
        m,
        developHistory,
        developHistory.vignette,
        'develop_history',
        'vignette',
      );
      await _addColumnIfMissing(
        m,
        developHistory,
        developHistory.lutPath,
        'develop_history',
        'lut_path',
      );
      await _addColumnIfMissing(
        m,
        developHistory,
        developHistory.lutStrength,
        'develop_history',
        'lut_strength',
      );
    }
    if (from < 40) {
      // Stammbaum: Verwandtschaften und Lebensdaten. Beides ist rein
      // additiv – eine leere Beziehungstabelle und zwei leere Spalten
      // verhalten sich wie zuvor, der Stammbaum einer Person ohne
      // Einträge ist schlicht leer.
      await m.createTable(personBeziehungen);
      await _addColumnIfMissing(
        m,
        people,
        people.geburtsdatum,
        'people',
        'geburtsdatum',
      );
      await _addColumnIfMissing(
        m,
        people,
        people.sterbedatum,
        'people',
        'sterbedatum',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_beziehung_andere ON person_beziehungen (andere_id)',
      );
    }
    if (from < 41) {
      // Geschlecht, nur für die Verwandtschaftsbezeichnungen. Leer
      // bedeutet „nicht angegeben" – der Stammbaum zeigt dann die
      // geschlechtsneutrale Form.
      await _addColumnIfMissing(
        m,
        people,
        people.geschlecht,
        'people',
        'geschlecht',
      );
    }
    if (from < 42) {
      // Lebensereignisse. Eine neue, anfangs leere Tabelle – ohne
      // einen einzigen Eintrag verhält sich alles wie zuvor.
      await m.createTable(lebensereignisse);
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_ereignis_person '
        'ON lebensereignisse (person_id)',
      );
    }
    if (from < 43) {
      // Belichtungskorrektur und Kleinbild-Brennweite. Beide bleiben
      // für bestehende Fotos leer, bis „Kameradaten einlesen" läuft –
      // die Info-Ansicht lässt eine fehlende Angabe einfach weg.
      await _addColumnIfMissing(
        m,
        assets,
        assets.exposureBiasEv,
        'assets',
        'exposure_bias_ev',
      );
      await _addColumnIfMissing(
        m,
        assets,
        assets.focalLength35mm,
        'assets',
        'focal_length35mm',
      );
    }
    if (from < 44) {
      // Merkmal für eine von Hand geänderte Bildunterschrift. Für
      // bestehende Fotos falsch – vorher liess sie sich gar nicht
      // ändern.
      await _addColumnIfMissing(
        m,
        assets,
        assets.aiCaptionEdited,
        'assets',
        'ai_caption_edited',
      );
    }
    if (from < 45) {
      // Ausnahmen der Duplikatsuche. Neue, anfangs leere Tabelle –
      // ohne einen einzigen Eintrag verhält sich die Suche wie zuvor.
      await m.createTable(duplikatAusnahmen);
    }
    if (from < 46) {
      // Der Lichter-Regler. Vorgabe 0 heisst neutral: Jede bereits
      // gespeicherte Entwicklung sieht nach der Migration genauso
      // aus wie davor – niemand findet sein Bild verändert vor.
      await _addColumnIfMissing(
        m,
        developSettings,
        developSettings.highlights,
        'develop_settings',
        'highlights',
      );
      await _addColumnIfMissing(
        m,
        developMasks,
        developMasks.highlights,
        'develop_masks',
        'highlights',
      );
      await _addColumnIfMissing(
        m,
        developHistory,
        developHistory.highlights,
        'develop_history',
        'highlights',
      );
    }
    if (from < 47) {
      // Benannte Entwicklungs-Vorgaben. Neue, anfangs leere Tabelle –
      // ohne einen einzigen Eintrag verhält sich alles wie zuvor.
      await m.createTable(developPresets);
    }
    if (from < 48) {
      // Dateiformat als eigene, indexierte Spalte – Suche nach
      // „nur DNG" ohne Tabellen-Scan.
      await _addColumnIfMissing(
        m,
        assets,
        assets.dateiformat,
        'assets',
        'dateiformat',
      );
      await _trageDateiformateNach();
      await _createIndicesV48(m);
    }
    if (from < 49) {
      // Die zuletzt gewählte Kartenansicht überdauert jetzt das
      // Schliessen des Bildschirms.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.kartenansicht,
        'app_settings',
        'kartenansicht',
      );
    }
    if (from < 50) {
      // Lebensereignisse bekommen eine Koordinate zum Ortsnamen.
      // Beide Spalten leer: Das Nachtragen läuft nicht hier,
      // sondern beim ersten Start mit geladenem GeoNames-Auszug
      // (siehe LibraryState.trageEreignisorteNach) – ohne den
      // Datensatz gäbe es nichts einzutragen, und eine Migration,
      // die auf einen optionalen Download wartet, wäre eine
      // Migration, die manchmal nicht fertig wird.
      await _addColumnIfMissing(
        m,
        lebensereignisse,
        lebensereignisse.ortBreite,
        'lebensereignisse',
        'ort_breite',
      );
      await _addColumnIfMissing(
        m,
        lebensereignisse,
        lebensereignisse.ortLaenge,
        'lebensereignisse',
        'ort_laenge',
      );
    }
    if (from < 51) {
      // Reisen. Drei neue, anfangs leere Tabellen – ohne einen
      // einzigen Eintrag verhält sich alles wie zuvor.
      await m.createTable(reisen);
      await m.createTable(reiseAufnahmen);
      await m.createTable(verworfeneReisen);
      await _createIndicesV51(m);
    }
    if (from < 52) {
      // Selbst gesetzte Ortsmarken. Neue, anfangs leere Tabelle –
      // solange niemand einen Haken setzt, zählt die Weltkarte
      // genau wie vorher nur die Fotos.
      await m.createTable(ortsmarken);
    }
    if (from < 53) {
      // Die Startzeit der KI-Restaurierung. Ohne sie liess sich
      // keine ehrliche Restzeit rechnen; laufende Auftraege gibt
      // es beim Start ohnehin keine (siehe
      // resetStuckRunningRestoreJobs), die Spalte darf also leer
      // beginnen.
      await _addColumnIfMissing(
        m,
        restoreJobs,
        restoreJobs.startedAt,
        'restore_jobs',
        'started_at',
      );
    }
    if (from < 54) {
      // Aktivitäten. Drei neue, anfangs leere Tabellen – ohne
      // einen einzigen Eintrag verhält sich alles wie zuvor.
      await m.createTable(aktivitaeten);
      await m.createTable(aktivitaetAufnahmen);
      await m.createTable(verworfeneAktivitaeten);
      await _createIndicesV54(m);
    }
    if (from < 55) {
      // Aufgezeichnete Spuren. Zwei neue, anfangs leere Tabellen –
      // ohne einen einzigen Eintrag verhält sich alles wie zuvor.
      await m.createTable(spuren);
      await m.createTable(spurpunkte);
      await _createIndicesV55(m);
    }
    if (from < 56) {
      // Woher ein Schlagwort stammt (siehe [Tagquelle]).
      await _addColumnIfMissing(
        m,
        assetTags,
        assetTags.quelle,
        'asset_tags',
        'quelle',
      );
      await _bestimmeTagquelleNachtraeglich();
    }
    if (from < 57) {
      // Von der Gesichtssuche ausgenommen (siehe die Spalte).
      await _addColumnIfMissing(
        m,
        assets,
        assets.faceScanExcluded,
        'assets',
        'face_scan_excluded',
      );
    }
    if (from < 58) {
      // Der eigene CARTO-Schlüssel (siehe die Spalte). Null heisst
      // „keiner" und damit invertierte OSM-Kacheln – die dunkle
      // Karte funktioniert also ohne jedes Zutun weiter, nur ohne
      // das Wasserzeichen.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.cartoSchluessel,
        'app_settings',
        'carto_schluessel',
      );
    }
    if (from < 59) {
      // Wie viele schwere Aufgaben nebeneinander laufen dürfen
      // (siehe die Spalte). Vorgabe eins = das bisherige Verhalten.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.maxGleichzeitig,
        'app_settings',
        'max_gleichzeitig',
      );
    }
    if (from < 60) {
      // Wo der erkannte Text im Bild steht (siehe die Spalte). Leer
      // fuer alles Bisherige; die Texterkennung holt es nach.
      await _addColumnIfMissing(
        m,
        assets,
        assets.ocrBoxen,
        'assets',
        'ocr_boxen',
      );
    }
    if (from < 61) {
      // Schaerfe des Gesichtsausschnitts (siehe die Spalte). Leer
      // fuer alles Bisherige; der Nachlauf holt es aus den bereits
      // gespeicherten Ausschnitten, ohne ein Foto neu zu dekodieren.
      await _addColumnIfMissing(m, faces, faces.schaerfe, 'faces', 'schaerfe');
    }
    if (from < 62) {
      // Abgelehnte Serienvorschlaege – bis hierher verschwand ein
      // „nein" mit dem Schliessen des Bildschirms.
      await m.createTable(verworfeneSerien);
    }
    if (from < 63) {
      // Die alten Augenwerte entstanden mit falscher Normierung und
      // sagten „geschlossen" zu offenen Augen. `null` heisst laut
      // Spaltendoku „noch nicht berechnet" – das ist die ehrliche
      // Auskunft, bis ein Gesichtsdurchlauf sie neu ermittelt.
      await m.database.customStatement(
        'UPDATE faces SET eye_open_score = NULL',
      );
    }
    if (from < 64) {
      // „Schon nachgesehen" beim Ortsnachtrag (siehe die Spalte).
      // `false` fuer alles Bestehende ist Absicht: Der erste Lauf
      // nach dem Umstieg geht noch einmal ueber alles – und findet
      // dabei die Videos, an die er vorher nie herankam.
      await _addColumnIfMissing(
        m,
        assets,
        assets.gpsGeprueft,
        'assets',
        'gps_geprueft',
      );
    }
    if (from < 65) {
      // Zuordnungen, die auf die VIDEOHÄLFTE eines Live Photos
      // zeigen, auf das Foto umbiegen.
      //
      // Wie es dazu kam: Die Reise-/Aktivitätserkennung sah bis
      // hierher auch die Videohälften, weil ihr die Einschränkung
      // fehlte, die überall sonst gilt (siehe
      // [aufnahmenFuerReiseerkennung]). Was daraus entstand, hing
      // davon ab, welche Hälfte gerade Datum und Ort trug – und die
      // wurden beim Videodatum (Fassung 64) und beim CR3-Nachtrag
      // nachträglich berichtigt.
      //
      // An der gewachsenen Bibliothek: 19 Zuordnungen zeigten auf
      // eine Videohälfte, nur 5 der zugehörigen Fotos waren
      // ebenfalls zugeordnet. Zwei Aktivitäten – „Gifhorn -
      // Mühlenmuseum" und „Eiluhmer Horn" – bestanden damit aus
      // sieben Videoschnipseln und keinem einzigen Foto.
      //
      // `insertOrIgnore`, dann löschen: Ist das Foto schon drin,
      // bleibt es bei ihm, und die Videozeile fällt trotzdem weg.
      // Andersherum stünde beides da und jedes Live Photo zählte
      // doppelt.
      for (final tabelle in ['aktivitaet_aufnahmen', 'reise_aufnahmen']) {
        final spalte = tabelle == 'aktivitaet_aufnahmen'
            ? 'aktivitaet_id'
            : 'reise_id';
        await m.database.customStatement('''
                INSERT OR IGNORE INTO $tabelle ($spalte, asset_id)
                SELECT z.$spalte, a.linked_asset_id
                FROM $tabelle z JOIN assets a ON a.id = z.asset_id
                WHERE a.type != 'IMAGE' AND a.linked_asset_id IS NOT NULL
              ''');
        await m.database.customStatement('''
                DELETE FROM $tabelle WHERE asset_id IN (
                  SELECT id FROM assets
                  WHERE type != 'IMAGE' AND linked_asset_id IS NOT NULL
                )
              ''');
      }
    }
    if (from < 66) {
      // Die eigene Kartenquelle (siehe die Spalten). Alles leer und
      // nicht zugestimmt = genau das bisherige Verhalten: Der
      // Eintrag taucht im Kartenmenue erst auf, wenn er ausgefuellt
      // ist.
      for (final spalte in [
        appSettings.eigeneKarteName,
        appSettings.eigeneKarteUrl,
        appSettings.eigeneKarteNennung,
        appSettings.eigeneKarteStufe,
        appSettings.eigeneKarteZugestimmt,
      ]) {
        await _addColumnIfMissing(
          m,
          appSettings,
          spalte,
          'app_settings',
          spalte.name,
        );
      }
    }
    if (from < 67) {
      // Vorgabe true = genau das bisherige Verhalten.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.karteHochaufloesend,
        'app_settings',
        'karte_hochaufloesend',
      );
    }
    if (from < 68) {
      // Beides leer = genau das bisherige Verhalten: Der Baum
      // beginnt bei der Person mit den meisten Verwandten.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.stammbaumAnsicht,
        'app_settings',
        'stammbaum_ansicht',
      );
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.stammbaumPerson,
        'app_settings',
        'stammbaum_person',
      );
      // Die mittlere Stufe ist genau die Groesse, die es vorher
      // als einzige gab.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.zeitleisteKachelstufe,
        'app_settings',
        'zeitleiste_kachelstufe',
      );
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.listenspalten,
        'app_settings',
        'listenspalten',
      );
    }
    if (from < 69) {
      // Vorgabe = Quadrate, also genau das bisherige Bild. Wer
      // nichts umstellt, merkt von der zweiten Form nichts.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.zeitleisteFormNr,
        'app_settings',
        'zeitleiste_form_nr',
      );
    }
    if (from < 70) {
      // Vorgabe an. Die Spalte ist neu, also hat noch niemand eine
      // Wahl getroffen - und wer die Bewegung nicht will, findet
      // den Schalter in den Einstellungen.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.schwebeVorschau,
        'app_settings',
        'schwebe_vorschau',
      );
    }
    if (from < 71) {
      // Vorgabe Mittag - genau die Beleuchtung, die es vorher als
      // einzige gab.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.gelaendeStimmungNr,
        'app_settings',
        'gelaende_stimmung_nr',
      );
    }
    if (from < 72) {
      // Die Wanderobjekte aus OpenStreetMap und die Liste der
      // schon erfragten Ausschnitte.
      await m.createTable(wanderpunkte);
      await m.createTable(wanderabfragen);
      // Die vier Spalten der Geländeauflage. Die Vorgaben stehen
      // bei den Spalten selbst; sie aendern das Bild sichtbar, und
      // das ist Absicht (siehe [AppSettings.gelaendeGrundNr]).
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.gelaendeGrundNr,
        'app_settings',
        'gelaende_grund_nr',
      );
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.gelaendeWege,
        'app_settings',
        'gelaende_wege',
      );
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.gelaendeBeschriftung,
        'app_settings',
        'gelaende_beschriftung',
      );
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.gelaendeHoehenlinien,
        'app_settings',
        'gelaende_hoehenlinien',
      );
    }
    if (from < 73) {
      // Der Schalter fuer die Schilder. Vorgabe an - sie sind der
      // Grund, warum die Landschaft mehr sagt als eine Karte.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.gelaendeWanderobjekte,
        'app_settings',
        'gelaende_wanderobjekte',
      );
    }
    if (from < 74) {
      // Eine Spur darf jetzt auch an einer Reise haengen. Die
      // Spalte bleibt bei allen vorhandenen Spuren leer - die
      // gehoeren zu Aktivitaeten.
      await _addColumnIfMissing(
        m,
        spuren,
        spuren.reiseId,
        'spuren',
        'reise_id',
      );
    }
    if (from < 75) {
      // Woher der Aufnahmezeitpunkt stammt (siehe die beiden
      // Spalten). BEIDE `false` fuer alles Bestehende, und das ist
      // die vorsichtige Wahl:
      //
      // Es waere verlockend, hier gleich `datum_geschaetzt` fuer
      // alles zu setzen, was auf einer vollen Stunde liegt - an der
      // echten Bibliothek traefe das 1097 Aufnahmen und damit fast
      // genau die richtigen. Aber eben nur fast: Ein Foto, das
      // wirklich um Punkt 18 Uhr entstand, bekaeme eine Marke, die
      // eine Falschaussage waere. Statt einer Vermutung ueber alle
      // laeuft der Nachtrag einmal ueber die Bibliothek und sieht
      // in JEDER Datei nach, ob ein Aufnahmedatum darin steht.
      await _addColumnIfMissing(
        m,
        assets,
        assets.datumGeschaetzt,
        'assets',
        'datum_geschaetzt',
      );
      await _addColumnIfMissing(
        m,
        assets,
        assets.datumGeprueft,
        'assets',
        'datum_geprueft',
      );
    }
    if (from < 76) {
      // Ein geerbter Ort ist kein gemessener (siehe die Spalte),
      // und abgelehnte Vorschlaege sollen abgelehnt bleiben -
      // dieselbe Machart wie bei Reisen, Aktivitaeten und Serien.
      await _addColumnIfMissing(
        m,
        assets,
        assets.ortGeerbt,
        'assets',
        'ort_geerbt',
      );
      await m.createTable(verworfeneOrtsvorschlaege);
    }
    if (from < 77) {
      // Ein Video war bis hierher ein einziges Standbild (siehe
      // die Spalte und die Tabelle). `false` fuer alles
      // Bestehende: Der Nachtrag sieht sich jedes Video einmal an.
      await _addColumnIfMissing(
        m,
        assets,
        assets.videobilderGeprueft,
        'assets',
        'videobilder_geprueft',
      );
      await m.createTable(videoeinbettungen);
    }
    if (from < 78) {
      // Der Zeitzonenversatz aus der Datei (siehe die Spalte). Er
      // wird vom selben Nachtrag mitgelesen, der nach der Herkunft
      // des Datums sieht - die Datei ist dann ohnehin offen.
      await _addColumnIfMissing(
        m,
        assets,
        assets.zeitversatzMinuten,
        'assets',
        'zeitversatz_minuten',
      );
    }
    if (from < 79) {
      // Vorgabe = neueste Aufnahme oben, also genau die
      // Reihenfolge, die es vorher als einzige gab. Wer nichts
      // umstellt, merkt von der Wahl nichts.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.zeitleisteSortierungNr,
        'app_settings',
        'zeitleiste_sortierung_nr',
      );
    }
    if (from < 80) {
      // Neue Tabelle, also nichts umzuschreiben: Wer nichts
      // schreibt, hat keine Tagesnotizen, und die Ansicht sieht
      // aus wie bisher.
      await m.createTable(reisetagnotizen);
    }
    if (from < 81) {
      // Jede bestehende Reise wird über den Vorgabewert eine
      // „Reise" – was sie bisher der Sache nach war. Wer eine als
      // Einsatz oder Dienstreise führen will, sagt es danach.
      await _addColumnIfMissing(m, reisen, reisen.art, 'reisen', 'art');
    }
    if (from < 82) {
      await _createAssetSearchFts();
    }
    if (from < 83) {
      await _addColumnIfMissing(
        m,
        privacySettings,
        privacySettings.protectMetadata,
        'privacy_settings',
        'protect_metadata',
      );
    }
    if (from < 84) {
      // Der Auslöser bekommt eine Bedingung (siehe
      // [_createAssetSearchFts]). `CREATE TRIGGER IF NOT EXISTS`
      // liesse den alten stehen – er muss weg, bevor der neue kommt.
      await customStatement('DROP TRIGGER IF EXISTS assets_fts_update');
      await _createAssetSearchTriggers();
    }
    if (from < 85) {
      // Drei neue Spalten, alle leer: Vor dem ersten Lauf gibt es
      // keine Vorschlaege, und genau so sieht die App danach aus.
      for (final (spalte, name) in [
        (faces.vorschlagPersonId, 'vorschlag_person_id'),
        (faces.vorschlagWert, 'vorschlag_wert'),
        (faces.vorschlagGeprueftAm, 'vorschlag_geprueft_am'),
      ]) {
        await _addColumnIfMissing(m, faces, spalte, 'faces', name);
      }
    }
    if (from < 86) {
      // Vorgabe aus, also genau das bisherige Bild.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.zeitleisteMitTagen,
        'app_settings',
        'zeitleiste_mit_tagen',
      );
    }
    if (from < 87) {
      // Alle drei leer = die Vorgabe des Lebensbaums.
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.lebensbaumRichtung,
        'app_settings',
        'lebensbaum_richtung',
      );
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.lebensbaumStil,
        'app_settings',
        'lebensbaum_stil',
      );
      await _addColumnIfMissing(
        m,
        appSettings,
        appSettings.lebensbaumGenerationen,
        'app_settings',
        'lebensbaum_generationen',
      );
    }
    if (from < 88) {
      // Leer: Abgelehnt hat noch niemand etwas.
      await m.createTable(verworfeneDokumente);
    }
    if (from < 89) {
      await m.createTable(gemerkteErinnerungen);
    }
    if (from < 90) {
      // Leer: Bis zum ersten Lauf zählen die Karten wie bisher alles.
      await m.createTable(aufgabenlaeufe);
    }
    if (from < 91) {
      // Alle drei leer = der ganze Baum, wie bisher.
      for (final (spalte, name) in [
        (appSettings.lebensbaumFamilieOben, 'lebensbaum_familie_oben'),
        (appSettings.lebensbaumFamilieUnten, 'lebensbaum_familie_unten'),
        (appSettings.lebensbaumFamilieKreis, 'lebensbaum_familie_kreis'),
      ]) {
        await _addColumnIfMissing(m, appSettings, spalte, 'app_settings', name);
      }
    }
  }
}
