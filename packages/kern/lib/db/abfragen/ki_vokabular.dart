part of '../database.dart';

/// KI-Schlagwortvokabular.
extension VokabularAbfragen on AppDatabase {
  // -----------------------------------------------------------------------
  // KI-Tagging-Vokabular (AiTaggingService)
  // -----------------------------------------------------------------------

  /// Für die Einstellungen (reaktiv, damit Änderungen sofort sichtbar sind).
  Stream<List<AiTagVocabularyData>> watchAiTagVocabulary() => (select(
    aiTagVocabulary,
  )..orderBy([(t) => OrderingTerm.asc(t.term)])).watch();

  /// Idempotent (Muster: [ensureTag]) – ein Doppel-Tap auf "Hinzufügen"
  /// erzeugt keinen doppelten Eintrag und keinen UNIQUE-Constraint-Fehler.
  Future<void> addAiTagTerm(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    final existing = await (select(
      aiTagVocabulary,
    )..where((t) => t.term.equals(trimmed))).getSingleOrNull();
    if (existing != null) return;
    await into(
      aiTagVocabulary,
    ).insert(AiTagVocabularyCompanion.insert(term: trimmed));
  }

  Future<void> removeAiTagTerm(int id) =>
      (delete(aiTagVocabulary)..where((t) => t.id.equals(id))).go();

  /// Einmaliger, nicht-reaktiver Read für Aufrufer, die keinen Stream
  /// brauchen (Import-Pipeline, Backfill) – analog zu [tagsForAsset].
  Future<List<String>> aiTagVocabularyTerms() async {
    final rows = await (select(
      aiTagVocabulary,
    )..orderBy([(t) => OrderingTerm.asc(t.term)])).get();
    return rows.map((r) => r.term).toList();
  }

  /// Kombinierte Suche über alle Filter des Suchoptionen-Panels (siehe
  /// [SearchFilters]) – alle aktiven Filter werden UND-verknüpft (z.B.
  /// Person UND Kamera UND Zeitraum), mehrere ausgewählte Personen bzw. Tags
  /// werden untereinander ebenfalls UND-verknüpft ("muss alle enthalten",
  /// nicht "mindestens einen").
  ///
  /// [restrictToIds] schränkt zusätzlich auf eine vorgegebene ID-Menge ein.
  ///
  /// Der "Kontext"-Modus (KI-Bildsuche) nutzt das bewusst NICHT mehr: Er
  /// filtert erst hier und rankt die Treffer danach über [ClipService].
  /// Andersherum – erst ranken, dann filtern – entschied das
  /// bibliotheksweite Top-N darüber, was die Filter überhaupt noch zu sehen
  /// bekamen, und ließ Treffer in kleinen Alben verschwinden (Audit-Fund).
  /// Der Suchtext selbst wird unten im Kontext-Modus absichtlich nicht als
  /// LIKE-Bedingung angewendet – dafür ist gerade das Embedding zuständig.
  /// Die Bedingungen der Suche - einmal gebaut, von beiden Wegen
  /// benutzt.
  ///
  /// **Warum getrennt.** [searchAssets] liefert volle Zeilen, und die KI-
  /// Suche brauchte davon nur die Kennungen, um ihre Kandidaten
  /// einzugrenzen: 7163 Zeilen mit 56 Spalten fuer eine Frage nach
  /// Zugehoerigkeit. Zwei Wege auf denselben Bedingungen sind billiger
  /// als eine zweite Aufzaehlung derselben 24 Filter, die eines Tages
  /// auseinanderliefe.
  List<Expression<bool>> _suchbedingungen(
    SearchFilters filters,
    List<String>? restrictToIds, {
    bool textAlreadyFiltered = false,
  }) {
    final wo = <Expression<bool>>[
      assets.isTrashed.equals(false),
      assets.isLocked.equals(false),
      // Live-Photo-Partner (das .mov zu einem Standbild) und
      // nicht-Titelbild-Stapelmitglieder werden hier wie überall sonst
      // (Timeline, Alben, Kartenansicht) ausgeblendet – sichtbar/
      // abspielbar bleiben sie weiterhin über das verknüpfte Foto bzw.
      // das Titelbild, nur nicht als zusätzlicher, eigenständiger Treffer.
      _isPrimaryGridEntry(assets),
    ];

    if (restrictToIds != null) {
      wo.add(assets.id.isIn(restrictToIds));
    }

    final text = filters.query.trim();
    if (!textAlreadyFiltered &&
        text.isNotEmpty &&
        filters.textMode == SearchTextMode.filename) {
      wo.add(assets.originalFileName.like('%$text%'));
    } else if (!textAlreadyFiltered &&
        text.isNotEmpty &&
        filters.textMode == SearchTextMode.description) {
      wo.add(assets.description.like('%$text%'));
    } else if (!textAlreadyFiltered &&
        text.isNotEmpty &&
        filters.textMode == SearchTextMode.ocr) {
      wo.add(assets.ocrText.like('%$text%'));
    } else if (!textAlreadyFiltered &&
        text.isNotEmpty &&
        filters.textMode == SearchTextMode.caption) {
      // Beide Fassungen: Wer die Übersetzung erst später einschaltet, hat
      // Fotos mit nur englischer und Fotos mit beiden Beschreibungen. Nur
      // in einer zu suchen liesse einen Teil der Bibliothek unauffindbar.
      wo.add(
        assets.aiCaption.like('%$text%') | assets.aiCaptionDe.like('%$text%'),
      );
    } else if (!textAlreadyFiltered &&
        text.isNotEmpty &&
        filters.textMode == SearchTextMode.transkript) {
      wo.add(assets.transkript.like('%$text%'));
    }

    if (filters.cameraMake != null) {
      wo.add(assets.cameraMake.equals(filters.cameraMake!));
    }
    if (filters.cameraModel != null) {
      wo.add(assets.cameraModel.equals(filters.cameraModel!));
    }
    if (filters.lensModel != null) {
      wo.add(assets.lensModel.equals(filters.lensModel!));
    }

    if (filters.locationCountry != null) {
      wo.add(assets.locationCountry.equals(filters.locationCountry!));
    }
    if (filters.locationState != null) {
      wo.add(assets.locationState.equals(filters.locationState!));
    }
    if (filters.locationCity != null) {
      wo.add(assets.locationCity.equals(filters.locationCity!));
    }

    if (filters.startDate != null) {
      final start = filters.startDate!;
      wo.add(
        assets.fileCreatedAt.isBiggerOrEqualValue(
          DateTime(start.year, start.month, start.day),
        ),
      );
    }
    if (filters.endDate != null) {
      final end = filters.endDate!;
      // Enddatum inklusive -> bis zum letzten Millisekunde des gewählten Tages.
      wo.add(
        assets.fileCreatedAt.isSmallerOrEqualValue(
          DateTime(end.year, end.month, end.day, 23, 59, 59, 999),
        ),
      );
    }

    if (filters.mediaType == MediaTypeFilter.image) {
      wo.add(assets.type.equals('IMAGE'));
    } else if (filters.mediaType == MediaTypeFilter.video) {
      wo.add(assets.type.equals('VIDEO'));
    }

    // Leerer Satz heisst „alle" – nicht „keins". Ein `isIn([])` waere
    // sonst eine Bedingung, die nie zutrifft, und die Suche bliebe ohne
    // erkennbaren Grund leer.
    if (filters.formate.isNotEmpty) {
      wo.add(assets.dateiformat.isIn(filters.formate.toList()));
    }

    if (filters.favoritesOnly) {
      wo.add(assets.isFavorite.equals(true));
    }

    if (filters.notInAnyAlbum) {
      wo.add(
        notExistsQuery(
          select(albumAssets)..where((aa) => aa.assetId.equalsExp(assets.id)),
        ),
      );
    }

    if (filters.minRating != null) {
      wo.add(assets.rating.isBiggerOrEqualValue(filters.minRating!));
    }
    if (filters.colorLabels.isNotEmpty) {
      wo.add(assets.colorLabel.isIn(filters.colorLabels));
    }
    if (filters.minIso != null) {
      wo.add(assets.iso.isBiggerOrEqualValue(filters.minIso!));
    }
    if (filters.maxIso != null) {
      wo.add(assets.iso.isSmallerOrEqualValue(filters.maxIso!));
    }
    if (filters.minFNumber != null) {
      wo.add(assets.fNumber.isBiggerOrEqualValue(filters.minFNumber!));
    }
    if (filters.maxFNumber != null) {
      wo.add(assets.fNumber.isSmallerOrEqualValue(filters.maxFNumber!));
    }
    if (filters.minFocalLengthMm != null) {
      wo.add(
        assets.focalLengthMm.isBiggerOrEqualValue(filters.minFocalLengthMm!),
      );
    }
    if (filters.maxFocalLengthMm != null) {
      wo.add(
        assets.focalLengthMm.isSmallerOrEqualValue(filters.maxFocalLengthMm!),
      );
    }
    if (filters.maxSharpnessScore != null) {
      wo.add(
        assets.sharpnessScore.isSmallerOrEqualValue(filters.maxSharpnessScore!),
      );
    }
    if (filters.nurGeschaetztesDatum) {
      wo.add(assets.datumGeschaetzt.equals(true));
    }
    if (filters.herkunft != Aufnahmeherkunft.alle) {
      // `isNotNull` zuerst: Ohne Hersteller wäre `<> ''` NULL, und ein
      // verneintes NULL bliebe NULL – die Aufnahmen ohne Kameradaten
      // fielen dann aus beiden Antworten heraus.
      final kamera =
          assets.cameraMake.isNotNull() &
          assets.cameraMake.equals('').not() &
          CustomExpression<bool>(
            'NOT (${[for (final m in botennamen) "lower(assets.original_file_name) LIKE '$m'"].join(' OR ')})',
          );
      wo.add(
        filters.herkunft == Aufnahmeherkunft.kamera ? kamera : kamera.not(),
      );
    }

    for (final personId in filters.personIds) {
      wo.add(
        existsQuery(
          select(faces)..where(
            (f) => f.assetId.equalsExp(assets.id) & f.personId.equals(personId),
          ),
        ),
      );
    }

    for (final personId in filters.ohnePersonIds) {
      wo.add(
        notExistsQuery(
          select(faces)..where(
            (f) => f.assetId.equalsExp(assets.id) & f.personId.equals(personId),
          ),
        ),
      );
    }
    for (final tagId in filters.ohneTagIds) {
      wo.add(
        notExistsQuery(
          select(assetTags)..where(
            (at) => at.assetId.equalsExp(assets.id) & at.tagId.equals(tagId),
          ),
        ),
      );
    }

    if (filters.noTag) {
      wo.add(
        notExistsQuery(
          select(assetTags)..where((at) => at.assetId.equalsExp(assets.id)),
        ),
      );
    } else {
      for (final tagId in filters.tagIds) {
        wo.add(
          existsQuery(
            select(assetTags)..where(
              (at) => at.assetId.equalsExp(assets.id) & at.tagId.equals(tagId),
            ),
          ),
        );
      }
    }

    return wo;
  }

  Future<List<String>?> _ftsAssetIds(SearchFilters filters) async {
    final text = filters.query.trim();
    if (text.isEmpty) return null;
    final columns = switch (filters.textMode) {
      SearchTextMode.filename => ['original_file_name'],
      SearchTextMode.description => ['description'],
      SearchTextMode.ocr => ['ocr_text'],
      SearchTextMode.caption => ['ai_caption', 'ai_caption_de'],
      SearchTextMode.transkript => ['transkript'],
      _ => const <String>[],
    };
    if (columns.isEmpty) return null;
    // **Jeder Begriff in Anführungszeichen.** Der Ausdruck unten lässt nur
    // Buchstaben, Ziffern und Unterstrich durch, aber das genügt nicht: FTS5
    // liest `AND`, `OR` und `NOT` als Verknüpfung, sobald sie nackt
    // dastehen. Die Suche nach „a AND b" wurde damit zu
    // `(a* AND AND* AND b*)` – ein Syntaxfehler, der im Suchbildschirm als
    // „Suche fehlgeschlagen" landete, statt Treffer zu liefern. In
    // Anführungszeichen ist derselbe Begriff ein Wort wie jedes andere, und
    // das nachgestellte `*` bleibt gültige Präfixsuche.
    final terms = RegExp(r'[\p{L}\p{N}_]+', unicode: true)
        .allMatches(text)
        .map((match) => '"${match.group(0)!.replaceAll('"', '""')}"*')
        .toList();
    if (terms.isEmpty) return const [];
    final query = columns
        .map((column) => '$column : (${terms.join(' AND ')})')
        .join(' OR ');
    final rows = await customSelect(
      'SELECT asset_id FROM asset_search_fts WHERE asset_search_fts MATCH ?',
      variables: [Variable<String>(query)],
    ).get();
    return [for (final row in rows) row.read<String>('asset_id')];
  }

  List<String>? _intersectIds(List<String>? requested, List<String>? fts) {
    if (fts == null) return requested;
    if (requested == null) return fts;
    final allowed = fts.toSet();
    return [
      for (final id in requested)
        if (allowed.contains(id)) id,
    ];
  }

  /// Wie viele Treffer die Filterkombination haette – **ohne** die
  /// Treffer selbst zu laden.
  ///
  /// **Der Anlass ist die Zahl in der Filterleiste.** Sie steht dort
  /// live, und sie wurde bisher aus `searchAssets(...).length` gewonnen:
  /// erst alle Treffer vollstaendig laden, dann zaehlen. Bei einem weiten
  /// Textfilter sind das an der echten Bibliothek **7163 Zeilen mit je
  /// 56 Spalten**, und die Leiste rechnet bei **jedem Tastendruck** neu.
  ///
  /// ```
  /// searchAssets(...).length     88,3 ms
  /// countSearchResults(...)      10,5 ms
  /// ```
  ///
  /// Die Bedingungen kommen aus derselben Quelle wie bei der Suche
  /// ([_suchbedingungen]) – waeren es zwei Kopien, koennte die Zahl
  /// etwas anderes versprechen als die Liste dahinter zeigt.
  Future<int> countSearchResults(
    SearchFilters filters, {
    List<String>? restrictToIds,
  }) async {
    final fts = await _ftsAssetIds(filters);
    final effectiveIds = _intersectIds(restrictToIds, fts);
    // Eine leere Auswahl hat keine Treffer – und `id IN ()` waere eine
    // Abfrage, die ohnehin nichts findet.
    if (effectiveIds != null && effectiveIds.isEmpty) return 0;
    final anzahl = assets.id.count();
    final abfrage = selectOnly(assets)..addColumns([anzahl]);
    for (final b in _suchbedingungen(
      filters,
      effectiveIds,
      textAlreadyFiltered: fts != null,
    )) {
      abfrage.where(b);
    }
    return (await abfrage.getSingle()).read(anzahl) ?? 0;
  }

  Future<List<AssetData>> searchAssets(
    SearchFilters filters, {
    List<String>? restrictToIds,
  }) async {
    final fts = await _ftsAssetIds(filters);
    final effectiveIds = _intersectIds(restrictToIds, fts);
    final query = select(assets);
    for (final b in _suchbedingungen(
      filters,
      effectiveIds,
      textAlreadyFiltered: fts != null,
    )) {
      query.where((_) => b);
    }
    query.orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]);
    return query.get();
  }

  /// Dieselbe Suche, aber nur die Kennungen.
  ///
  /// Fuer die KI-Bildsuche: Die filtert erst hier und rankt danach ueber
  /// die Einbettungen: Aus der Trefferliste werden am Ende 200 gezeigt.
  /// Die vollen Zeilen der 7163 Kandidaten dafuer zu lesen kostete an
  /// dieser Bibliothek 81 ms, die Kennungen kosten 4,3 ms - die 200
  /// Zeilen holt danach [assetsByIds] fuer 2,6 ms.
  ///
  /// **Ohne Reihenfolge**, und das ist Absicht: Wer die Kennungen holt,
  /// ordnet danach selbst (nach Aehnlichkeit). Ein ORDER BY waere hier
  /// eine Sortierung, die niemand liest.
  Future<List<String>> searchAssetIds(
    SearchFilters filters, {
    List<String>? restrictToIds,
  }) async {
    final fts = await _ftsAssetIds(filters);
    final effectiveIds = _intersectIds(restrictToIds, fts);
    final query = selectOnly(assets)..addColumns([assets.id]);
    for (final b in _suchbedingungen(
      filters,
      effectiveIds,
      textAlreadyFiltered: fts != null,
    )) {
      query.where(b);
    }
    return [for (final z in await query.get()) z.read(assets.id)!];
  }

  /// Alle in der Bibliothek tatsächlich vorkommenden, nicht-leeren Werte
  /// einer Text-Spalte – für die Dropdowns im Suchoptionen-Panel (Kamera-
  /// Marke/-Modell/Objektiv), damit dort nur Werte auswählbar sind, die auch
  /// wirklich zu einem Treffer führen können.
  Future<List<String>> _distinctNonNullValues(
    GeneratedColumn<String> column,
  ) async {
    final query = selectOnly(assets, distinct: true)
      ..addColumns([column])
      ..where(column.isNotNull())
      ..orderBy([OrderingTerm.asc(column)]);
    final rows = await query.get();
    return rows.map((r) => r.read(column)!).toList();
  }

  Future<List<String>> distinctCameraMakes() =>
      _distinctNonNullValues(assets.cameraMake);
  Future<List<String>> distinctCameraModels() =>
      _distinctNonNullValues(assets.cameraModel);
  Future<List<String>> distinctLensModels() =>
      _distinctNonNullValues(assets.lensModel);

  /// Alle in der Bibliothek vorkommenden Dateiformate – für die
  /// Auswahlliste im Suchfeld. Bewusst aus dem Bestand statt aus einer
  /// festen Liste: Angeboten wird, was da ist, nicht was die App könnte.
  Future<List<String>> distinctDateiformate() =>
      _distinctNonNullValues(assets.dateiformat);

  /// Alle in der Bibliothek bereits vorkommenden Kamera-Kombinationen
  /// (Hersteller + Modell zusammen, nicht unabhängig wie
  /// [distinctCameraMakes]/[distinctCameraModels]) – als Vorauswahl beim
  /// Anlegen eines Kamera-Presets (siehe CameraPresetsScreen), damit
  /// Tippfehler kein Preset erzeugen, das nie zu einem echten Foto passt.
  Future<List<(String, String)>> distinctCameras() async {
    final query = selectOnly(assets, distinct: true)
      ..addColumns([assets.cameraMake, assets.cameraModel])
      ..where(assets.cameraMake.isNotNull() & assets.cameraModel.isNotNull())
      ..orderBy([
        OrderingTerm.asc(assets.cameraMake),
        OrderingTerm.asc(assets.cameraModel),
      ]);
    final rows = await query.get();
    return [
      for (final row in rows)
        (
          row.read<String>(assets.cameraMake)!,
          row.read<String>(assets.cameraModel)!,
        ),
    ];
  }

  Future<List<String>> distinctCountries() =>
      _distinctNonNullValues(assets.locationCountry);

  /// ALLE vorkommenden Bundesländer/Provinzen, ohne Einschränkung auf ein
  /// Land – für den Satzleser (siehe `suchsatz.dart`), der beim Lesen von
  /// „Toskana" noch nicht weiss, in welchem Land das liegt.
  /// Bis zu [grenze] auswertbare Aufnahmen einer Kamera – für die
  /// Staubsuche (siehe `staubflecken.dart`).
  ///
  /// Nur Bilder, kein Papierkorb, nichts Gesperrtes. Und bewusst über den
  /// ganzen Zeitraum verteilt statt der neuesten: Staub kommt und geht mit
  /// dem Objektivwechsel; vierzig Aufnahmen desselben Nachmittags würden
  /// eine Sensorreinigung von vor drei Jahren als heutigen Befund melden.
  Future<List<AssetData>> aufnahmenDerKamera(String modell, int grenze) async {
    final alle =
        await (select(assets)
              ..where(
                (t) =>
                    t.cameraModel.equals(modell) &
                    t.type.equals('IMAGE') &
                    t.isTrashed.equals(false) &
                    t.isLocked.equals(false),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.fileCreatedAt)]))
            .get();
    if (alle.length <= grenze) return alle;
    final schritt = alle.length / grenze;
    return [for (var i = 0; i < grenze; i++) alle[(i * schritt).floor()]];
  }

  Future<List<String>> distinctAlleStates() =>
      _distinctNonNullValues(assets.locationState);

  /// Wie [distinctAlleStates], für Städte.
  Future<List<String>> distinctAlleCities() =>
      _distinctNonNullValues(assets.locationCity);

  /// Wie [distinctCountries], aber nur Bundesländer/Provinzen innerhalb eines
  /// bestimmten Landes – für das kaskadierende Land->Bundesland->Stadt-Dropdown
  /// im Suchoptionen-Panel (jede Ebene schränkt die darunterliegende ein).
  Future<List<String>> distinctStates(String country) async {
    final query = selectOnly(assets, distinct: true)
      ..addColumns([assets.locationState])
      ..where(
        assets.locationState.isNotNull() &
            assets.locationCountry.equals(country),
      )
      ..orderBy([OrderingTerm.asc(assets.locationState)]);
    final rows = await query.get();
    return rows.map((r) => r.read(assets.locationState)!).toList();
  }

  /// Wie [distinctStates], aber Städte innerhalb eines bestimmten
  /// Bundeslands/einer Provinz.
  Future<List<String>> distinctCities(String state) async {
    final query = selectOnly(assets, distinct: true)
      ..addColumns([assets.locationCity])
      ..where(
        assets.locationCity.isNotNull() & assets.locationState.equals(state),
      )
      ..orderBy([OrderingTerm.asc(assets.locationCity)]);
    final rows = await query.get();
    return rows.map((r) => r.read(assets.locationCity)!).toList();
  }
}
