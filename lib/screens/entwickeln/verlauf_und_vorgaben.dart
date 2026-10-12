part of '../develop_screen.dart';

/// Verlauf, Vorgaben, Kopieren, Speichern und Restaurierung.
mixin _Verlauf on _EntwickelnBasis {
  /// Der Stand einer gespeicherten Zeile als [DevelopAdjustments] – damit
  /// sich gespeicherte und Sitzungsschritte mit **derselben** Rechnung
  /// vergleichen lassen.
  ///
  /// Die Farbtabelle fehlt darin: Die Verlaufszeile hält nur ihre Stärke
  /// fest, nicht die Datei. Ein Unterschied allein in der Tabelle bliebe
  /// deshalb unbenannt – lieber das, als eine erfundene Auskunft.
  DevelopAdjustments _standAus(DevelopHistoryData e) => DevelopAdjustments(
    exposure: e.exposure,
    temperature: e.temperature,
    tint: e.tint,
    contrast: e.contrast,
    shadows: e.shadows,
    highlights: e.highlights,
    sharpness: e.sharpness,
    noiseReduction: e.noiseReduction,
    clarity: e.clarity,
    vignette: e.vignette,
    lensCorrectionEnabled: e.lensCorrectionEnabled,
    toneCurve: toneCurveAus(e.toneCurveJson),
    colorMixer: colorMixerAus(e.colorMixerJson),
    lutStrength: e.lutStrength,
  );

  /// Übernimmt einen Sitzungsschritt zurück in die Regler.
  void _ladeSchritt(DevelopAdjustments stand) {
    setState(() {
      _exposure = stand.exposure;
      _contrast = stand.contrast;
      _shadows = stand.shadows;
      _highlights = stand.highlights;
      _sharpness = stand.sharpness;
      _noiseReduction = stand.noiseReduction;
      _clarity = stand.clarity;
      _vignette = stand.vignette;
      _lutStaerke = stand.lutStrength;
      _lensCorrectionEnabled = stand.lensCorrectionEnabled;
      _toneCurve = stand.toneCurve;
      _colorMixer = stand.colorMixer;
      _autoWhiteBalance = stand.temperature == null;
      _temperature = stand.temperature ?? _temperature;
      _tint = stand.tint ?? 0;
    });
    _scheduleRerender();
  }

  Future<void> _showHistory() async {
    final t = AppTexte.of(context);
    final history = await widget.db.developHistoryForAsset(widget.asset.id);
    if (!mounted) return;
    final sprache = Localizations.localeOf(context).toString();
    String zeit(DateTime wann) =>
        DateFormat.yMd(sprache).add_Hms().format(wann);

    /// Was ein Schritt gegenüber seinem Vorgänger geändert hat.
    String was(DevelopAdjustments? vorher, DevelopAdjustments nachher) {
      if (vorher == null) return t.entwVerlaufAusgangsstand;
      final werkzeuge = geaenderteWerkzeuge(vorher, nachher);
      if (werkzeuge.isEmpty) return t.entwVerlaufOhneAenderung;
      return [for (final w in werkzeuge) werkzeugName(t, w)].join(', ');
    }

    final gewaehlt = await showModalBottomSheet<DevelopAdjustments>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (context) {
        final zeilen = <Widget>[];

        // **Erst die Sitzung.** Sie ist das, was gerade auf dem Bildschirm
        // passiert ist, und damit das, wonach man sucht. Die gespeicherte
        // Reihe steht darunter.
        if (_sitzung.length > 1) {
          zeilen.add(_verlaufKopf(t.entwVerlaufSitzung));
          for (var i = _sitzung.length - 1; i >= 0; i--) {
            final schritt = _sitzung[i];
            final vorher = i == 0 ? null : _sitzung[i - 1].stand;
            zeilen.add(
              ListTile(
                leading: Icon(
                  i == _sitzung.length - 1 ? Icons.circle : Icons.history,
                  size: i == _sitzung.length - 1 ? 12 : 20,
                  color: Colors.white70,
                ),
                title: Text(
                  was(vorher, schritt.stand),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  i == _sitzung.length - 1
                      ? '${zeit(schritt.wann)} · ${t.entwVerlaufJetzt}'
                      : zeit(schritt.wann),
                  style: const TextStyle(
                    color: DunkleFlaeche.hinweis,
                    fontSize: 12,
                  ),
                ),
                onTap: () => Navigator.pop(context, schritt.stand),
              ),
            );
          }
        }

        if (history.isNotEmpty) {
          zeilen.add(_verlaufKopf(t.entwVerlaufGespeichert));
          for (var i = 0; i < history.length; i++) {
            final eintrag = history[i];
            // Die Reihe kommt neueste zuerst; der Vorgaenger eines
            // Eintrags steht deshalb HINTER ihm.
            final vorher = i + 1 < history.length
                ? _standAus(history[i + 1])
                : null;
            zeilen.add(
              ListTile(
                leading: const Icon(Icons.history, color: Colors.white70),
                title: Text(
                  was(vorher, _standAus(eintrag)),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  zeit(eintrag.createdAt),
                  style: const TextStyle(
                    color: DunkleFlaeche.hinweis,
                    fontSize: 12,
                  ),
                ),
                onTap: () => Navigator.pop(context, _standAus(eintrag)),
              ),
            );
          }
        }

        if (zeilen.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              t.entwKeinVerlauf,
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: ListView(shrinkWrap: true, children: zeilen),
          ),
        );
      },
    );
    if (gewaehlt != null) _ladeSchritt(gewaehlt);
  }

  Widget _verlaufKopf(String titel) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xs,
    ),
    child: Text(
      titel,
      style: const TextStyle(
        color: DunkleFlaeche.hinweis,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  /// Legt den AKTUELLEN Reglerstand in die Zwischenablage – nicht den
  /// zuletzt gespeicherten. Andernfalls käme man nie zum Kopieren: Das
  /// Speichern schliesst diesen Bildschirm (Fehlerbericht).
  /// Setzt Belichtung und Kontrast auf das, was das Histogramm nahelegt.
  ///
  /// Bewusst kein Modus, sondern ein Griff an die Regler: Man sieht
  /// danach, was die Automatik getan hat, kann nachjustieren und findet es
  /// im Verlauf wieder. Der „Auto-Weissabgleich" daneben ist etwas
  /// anderes – ein Schalter, der den Weissabgleich dem Dekoder überlässt.
  ///
  /// Rechnet auf dem Histogramm des ZULETZT gerenderten Standes. Wer
  /// zweimal hintereinander drückt, bekommt beim zweiten Mal kaum noch
  /// eine Änderung – das ist richtig so und nicht etwa ein Fehler.
  void _automatisch() {
    final daten = _histogram;
    if (daten == null || daten.isEmpty) {
      melde.hinweis(AppTexte.of(context).entwAutomatikOhneHistogramm);
      return;
    }
    final werte = automatikAus(daten);
    setState(() {
      // Auf den bisherigen Stand aufgesetzt, nicht ersetzt: Das Histogramm
      // beschreibt das Bild MIT den aktuellen Reglern.
      _exposure = (_exposure + werte.belichtung).clamp(-3.0, 3.0);
      _contrast = (_contrast + werte.kontrast).clamp(-1.0, 1.0);
    });
    _scheduleRerender();
  }

  /// Legt den AKTUELLEN Reglerstand als benannte Vorgabe ab.
  ///
  /// Wie beim Kopieren der aktuelle und nicht der gespeicherte Stand: Das
  /// Speichern schliesst diesen Bildschirm, man käme sonst nie dazu.
  Future<void> _alsVorgabeSichern() async {
    final t = AppTexte.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => MitTextsteuerung(
        builder: (context, feld) => AlertDialog(
          title: Text(t.entwVorgabeSichern),
          content: TextField(
            controller: feld,
            autofocus: true,
            decoration: InputDecoration(hintText: t.entwVorgabeName),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.allgAbbrechen),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, feld.text.trim()),
              child: Text(t.allgSpeichern),
            ),
          ],
        ),
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    // Der Name ist eindeutig. Ein zweiter Eintrag darf den ersten nicht
    // stillschweigend ersetzen - gefragt wird vorher, nicht hinterher.
    if (await widget.db.developPresetNameVergeben(name)) {
      if (!mounted) return;
      melde.warnung(t.entwVorgabeNameVergeben(name));
      return;
    }

    final a = _currentAdjustments();
    await widget.db.fuehreAus(
      EntwicklungsvorgabeSpeichern(
        DevelopPresetsCompanion.insert(
          name: name,
          exposure: Value(a.exposure),
          temperature: Value(a.temperature),
          tint: Value(a.tint),
          contrast: Value(a.contrast),
          shadows: Value(a.shadows),
          highlights: Value(a.highlights),
          sharpness: Value(a.sharpness),
          noiseReduction: Value(a.noiseReduction),
          lensCorrectionEnabled: Value(a.lensCorrectionEnabled),
          clarity: Value(a.clarity),
          vignette: Value(a.vignette),
          lutPath: Value(_lutPfad),
          lutStrength: Value(a.lutStrength),
          toneCurveJson: Value(
            _toneCurve.istNeutral ? null : _toneCurve.encode(),
          ),
          colorMixerJson: Value(
            _colorMixer.istNeutral ? null : _colorMixer.encode(),
          ),
          erstelltAm: DateTime.now(),
        ),
      ),
    );
    if (!mounted) return;
    melde.erfolg(t.entwVorgabeGesichert(name));
  }

  /// Setzt eine Vorgabe in die Regler – wie beim Einsetzen aus der
  /// Zwischenablage: sichtbar und nachjustierbar, nicht sofort gespeichert.
  Future<void> _vorgabeAnwenden() async {
    final t = AppTexte.of(context);
    final vorgaben = await widget.db.alleDevelopPresets();
    if (!mounted) return;
    if (vorgaben.isEmpty) {
      melde.hinweis(t.entwKeineVorgaben);
      return;
    }
    final gewaehlt = await showDialog<DevelopPresetData>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(t.entwVorgabeWaehlen),
        children: [
          for (final v in vorgaben)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, v),
              child: Text(v.name),
            ),
        ],
      ),
    );
    if (gewaehlt == null || !mounted) return;
    await _ladeLut(gewaehlt.lutPath);
    if (!mounted) return;
    setState(() {
      _exposure = gewaehlt.exposure;
      _autoWhiteBalance = gewaehlt.temperature == null;
      _temperature = gewaehlt.temperature ?? _temperature;
      _tint = gewaehlt.tint ?? _tint;
      _contrast = gewaehlt.contrast;
      _shadows = gewaehlt.shadows;
      _highlights = gewaehlt.highlights;
      _sharpness = gewaehlt.sharpness;
      _noiseReduction = gewaehlt.noiseReduction;
      _clarity = gewaehlt.clarity;
      _vignette = gewaehlt.vignette;
      _lensCorrectionEnabled = gewaehlt.lensCorrectionEnabled;
      _lutStaerke = gewaehlt.lutStrength;
      _toneCurve = toneCurveAus(gewaehlt.toneCurveJson);
      _colorMixer = colorMixerAus(gewaehlt.colorMixerJson);
    });
    _scheduleRerender();
  }

  void _kopiereEinstellungen() {
    final a = _currentAdjustments();
    widget.onEinstellungenKopieren!(
      DevelopSettingsData(
        assetId: widget.asset.id,
        exposure: a.exposure,
        temperature: a.temperature,
        tint: a.tint,
        contrast: a.contrast,
        shadows: a.shadows,
        highlights: a.highlights,
        sharpness: a.sharpness,
        noiseReduction: a.noiseReduction,
        clarity: a.clarity,
        vignette: a.vignette,
        lutPath: _lutPfad,
        lutStrength: a.lutStrength,
        lensCorrectionEnabled: a.lensCorrectionEnabled,
        toneCurveJson: a.toneCurve.istNeutral ? null : a.toneCurve.encode(),
        colorMixerJson: a.colorMixer.istNeutral ? null : a.colorMixer.encode(),
        updatedAt: DateTime.now(),
      ),
    );
    melde.erfolg(AppTexte.of(context).entwKopiert);
  }

  /// Setzt die kopierten Werte in die Regler. Bewusst ohne sofortiges
  /// Speichern: Der Nutzer sieht die Vorschau, kann nachjustieren und
  /// entscheidet selbst – anders als beim Stapellauf über die Auswahl, wo
  /// eine Vorschau je Foto gar nicht möglich wäre.
  Future<void> _setzeKopierteEinstellungen() async {
    final w = widget.kopierteEinstellungen?.call();
    if (w == null) return;
    setState(() {
      _exposure = w.exposure;
      _autoWhiteBalance = w.temperature == null;
      if (w.temperature != null) _temperature = w.temperature!;
      if (w.tint != null) _tint = w.tint!;
      _contrast = w.contrast;
      _shadows = w.shadows;
      _highlights = w.highlights;
      _sharpness = w.sharpness;
      _noiseReduction = w.noiseReduction;
      _clarity = w.clarity;
      _vignette = w.vignette;
      _lutStaerke = w.lutStrength;
      _lensCorrectionEnabled = w.lensCorrectionEnabled;
      _toneCurve = toneCurveAus(w.toneCurveJson);
      _colorMixer = colorMixerAus(w.colorMixerJson);
    });
    await _requestPreview();
    if (!mounted) return;
    melde.erfolg(AppTexte.of(context).entwEingesetzt);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final adjustments = _currentAdjustments();
    final maskLayers = _currentMaskLayers();
    final sourceFile = widget.paths.absolute(widget.asset.relativePath);
    final bytes = await NativeImageConverter.developImage(
      sourceFile,
      adjustments: adjustments,
      masks: maskLayers,
      maxDimension: 4096,
      quality: 0.92,
    );
    if (bytes == null) {
      if (mounted) {
        setState(() => _saving = false);
        melde.fehler(AppTexte.of(context).entwSpeichernFehlgeschlagen);
      }
      return;
    }

    final developedRelativePath = widget.paths.developedRelativePath(
      widget.asset.id,
    );
    final targetFile = widget.paths.absolute(developedRelativePath);
    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsBytes(bytes);

    // Derselbe Pfad wie beim vorigen Entwickeln – Flutter merkt sich
    // dekodierte Bilder danach. Ohne dieses Vergessen zeigt die
    // Vollbildansicht das Ergebnis von vorhin.
    vergissAlleBilder();

    await widget.db.saveDevelopResult(
      widget.asset.id,
      settings: DevelopSettingsCompanion.insert(
        assetId: widget.asset.id,
        exposure: Value(adjustments.exposure),
        temperature: Value(adjustments.temperature),
        tint: Value(adjustments.tint),
        contrast: Value(adjustments.contrast),
        shadows: Value(adjustments.shadows),
        highlights: Value(adjustments.highlights),
        sharpness: Value(adjustments.sharpness),
        noiseReduction: Value(adjustments.noiseReduction),
        clarity: Value(adjustments.clarity),
        vignette: Value(adjustments.vignette),
        lutPath: Value(_lutPfad),
        lutStrength: Value(adjustments.lutStrength),
        lensCorrectionEnabled: Value(adjustments.lensCorrectionEnabled),
        toneCurveJson: Value(
          adjustments.toneCurve.istNeutral
              ? null
              : adjustments.toneCurve.encode(),
        ),
        colorMixerJson: Value(
          adjustments.colorMixer.istNeutral
              ? null
              : adjustments.colorMixer.encode(),
        ),
        updatedAt: DateTime.now(),
      ),
      developedRelativePath: developedRelativePath,
    );

    // Nur die gerade ausgewählte Maske kann seit dem letzten Speichern
    // geänderte Regler-Werte im Speicher haben (siehe _currentMaskLayers) –
    // alle anderen sind bereits mit der DB konsistent.
    if (_selectedMaskId != null) {
      await widget.db.fuehreAus(
        MaskeneinstellungAendern(
          _selectedMaskId!,
          DevelopMasksCompanion(
            exposure: Value(_maskExposure),
            temperature: Value(_maskAutoWhiteBalance ? null : _maskTemperature),
            tint: Value(_maskAutoWhiteBalance ? null : _maskTint),
            contrast: Value(_maskContrast),
            shadows: Value(_maskShadows),
            highlights: Value(_maskHighlights),
            sharpness: Value(_maskSharpness),
            noiseReduction: Value(_maskNoiseReduction),
          ),
        ),
      );
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    await widget.db.fuehreAus(EntwicklungZuruecksetzen(widget.asset.id));
    final developedFile = widget.paths.absolute(
      widget.paths.developedRelativePath(widget.asset.id),
    );
    if (await developedFile.exists()) await developedFile.delete();
    if (mounted) Navigator.of(context).pop(true);
  }

  // --- KI-Restaurierung (RestoreQueueService, Hintergrund-Warteschlange) --

  /// Stößt nur an – läuft im Hintergrund weiter, auch nachdem dieser
  /// Screen geschlossen wurde (siehe RestoreQueueService, HomeShell-
  /// Warteschlangen-Indikator). Kein Warten in der UI.
  Future<void> _enqueueRestore() async {
    final queue = widget.restoreQueue;
    if (queue == null) return;
    // Erst erklären, dann rechnen. Ein Knopf, der ein Foto minutenlang
    // durch ein Modell schickt, ohne vorher zu sagen, was dabei
    // herauskommt, ist ein Knopf, den man einmal drückt und danach nicht
    // mehr – aus Unsicherheit, nicht aus Ablehnung.
    final t = AppTexte.of(context);
    final los = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.modellEsrganTitel),
        content: SizedBox(width: 420, child: Text(t.restaurWasPassiert)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t.allgStarten),
          ),
        ],
      ),
    );
    if (los != true || !mounted) return;
    try {
      await queue.enqueue(widget.asset.id);
      if (mounted) {
        melde.erfolg(AppTexte.of(context).entwRestaurierungEingereiht);
      }
    } on RestaurierungNichtVerfuegbar {
      // Der Dienst kennt keine Oberflächensprache und wirft deshalb einen
      // eigenen Typ statt eines fertigen Satzes.
      if (mounted) {
        melde.warnung(AppTexte.of(context).restaurNichtVerfuegbar);
      }
    } catch (e) {
      if (mounted) {
        melde.fehler(AppTexte.of(context).entwRestaurierungFehler('$e'));
      }
    }
  }

  /// Entfernt ein vorhandenes Restaurierungs-Ergebnis (Muster: [_reset]) –
  /// betrifft nur die Datei-Referenz, die globalen Entwickeln-Regler und
  /// Masken bleiben unangetastet.
  Future<void> _removeRestoredResult() async {
    final relativePath = widget.asset.restoredRelativePath;
    if (relativePath == null) return;
    await widget.db.clearMissingRestoredPath(widget.asset.id);
    final file = widget.paths.absolute(relativePath);
    if (await file.exists()) await file.delete();
    if (mounted) Navigator.of(context).pop(true);
  }
}
