part of '../develop_screen.dart';

/// Die Vorschau: Shader und Live-Bild, LUT, Histogramm, Vorher/Nachher.
mixin _Vorschau on _EntwickelnBasis {
  bool get _shaderMoeglich => beschneidungBedienbar(
    maskenVorhanden: _masks.isNotEmpty,
    shaderGeladen: _shader != null,
    basisGeladen: _shaderBasis != null,
  );

  /// Ob sie auch gezeigt wird. Zwei Anlässe, und der zweite ist der
  /// Grund für die Trennung von [_shaderMoeglich]:
  ///
  /// - **Beim Ziehen**, damit die Regler live wirken.
  /// - **Solange die Beschneidungswarnung an ist** – die Markierung
  ///   entsteht im Shader, ein fertig gerendertes JPEG trägt sie nicht.
  ///   Hinge das weiter am Ziehen, wäre der Knopf dafür nur in dem
  ///   Sekundenbruchteil zwischen Loslassen und fertigem Render
  ///   anklickbar, also praktisch gar nicht.
  bool get _zeigeShaderVorschau => shaderVorschauZeigen(
    bedienbar: _shaderMoeglich,
    zieht: _dragging,
    warnungAn: _beschneidungZeigen,
  );

  /// Ob der Vorher/Nachher-Trennstrich gerade zu sehen ist. Getrennt vom
  /// Umschalter, weil „eingeschaltet" und „zeigbar" zwei Dinge sind –
  /// dieselbe Lehre wie bei der Beschneidungswarnung.
  bool get _zeigeTrennstrich => trennstrichZeigen(
    eingeschaltet: _trennstrich != null,
    originalDa: _originalPreviewBytes != null,
    shaderLaeuft: _zeigeShaderVorschau,
  );

  /// Lädt Shader-Programm und neutrale Basis für die Live-Vorschau.
  ///
  /// Wird am Ende von [_init] aufgerufen, also erst nachdem die Sperre
  /// geprüft und die Vorschau geladen ist. Beides ist optional: Schlägt es
  /// fehl (Plattform ohne Shader, Foto nicht renderbar), bleibt schlicht
  /// das bisherige Verhalten – nach jedem Reglerstopp ein nativer Render.
  Future<void> _initShaderVorschau({required bool unbearbeitet}) async {
    final shader = await ladeDevelopShader();
    if (!mounted) return;
    if (shader != null) setState(() => _shader = shader);

    // Bei einem unbearbeiteten Foto IST die angezeigte Vorschau bereits der
    // neutrale Stand – die lässt sich direkt als Shader-Basis verwenden.
    // Ein zusätzlicher nativer Render wäre reine Verschwendung und würde
    // die Optimierung aus _init() (kein CIRAWFilter-Durchlauf für
    // unveränderte Fotos) wieder zunichtemachen.
    Uint8List? bytes = unbearbeitet ? _previewBytes : null;
    if (bytes == null) {
      await _ensureOriginalPreviewLoaded();
      bytes = _originalPreviewBytes;
    }
    if (bytes == null || !mounted) return;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      // Der Dekoder selbst haelt nativen Speicher und wird hier nicht mehr
      // gebraucht - das Bild aus dem Einzelbild lebt unabhaengig weiter.
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _shaderBasis = frame.image);
    } catch (_) {
      // Ohne Basis keine Live-Vorschau – kein Grund, den Screen zu stören.
    }
  }

  Future<void> _init() async {
    // Redundant zur Sperre in asset_viewer_screen.dart (der einzige
    // Einstiegspunkt): schützt auch dann, falls diese Ansicht je aus einem
    // anderen Kontext heraus geöffnet würde, bevor überhaupt ein nativer
    // Renderversuch auf der noch verschlüsselten Originaldatei unternommen
    // wird.
    if (widget.asset.isLocked) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppTexte.of(context).entwGesperrt;
        });
      }
      return;
    }

    final settings = await widget.db.developSettingsForAsset(widget.asset.id);
    if (settings != null) {
      _exposure = settings.exposure;
      _contrast = settings.contrast;
      _shadows = settings.shadows;
      _highlights = settings.highlights;
      _sharpness = settings.sharpness;
      _noiseReduction = settings.noiseReduction;
      _clarity = settings.clarity;
      _vignette = settings.vignette;
      _lutStaerke = settings.lutStrength;
      await _ladeLut(settings.lutPath);
      _lensCorrectionEnabled = settings.lensCorrectionEnabled;
      _toneCurve = toneCurveAus(settings.toneCurveJson);
      _colorMixer = colorMixerAus(settings.colorMixerJson);
      if (settings.temperature != null) {
        _autoWhiteBalance = false;
        _temperature = settings.temperature!;
        _tint = settings.tint ?? 0;
      }
    }
    _masks = await widget.db.masksForAsset(widget.asset.id);
    // Der Ausgangsstand ist der erste Schritt: der einzige Weg ganz
    // zurueck.
    _sitzungBegonnen = true;
    _sitzung = mitSchritt(const [], _currentAdjustments());
    if (mounted) setState(() => _loading = false);

    // Nach dem Anzeigen, nicht davor: Der Bildschirm soll nicht auf eine
    // Auskunft warten, die nur eine Beschriftung betrifft.
    final stand = await NativeImageConverter.lensCorrectionStatus(
      await widget.paths.bereit(widget.asset.relativePath),
    );
    if (mounted) setState(() => _korrekturstand = stand);

    if (settings == null && _masks.isEmpty) {
      // Unverändertes Foto: die bereits vorhandene Vorschau/Originaldatei
      // direkt anzeigen statt beim bloßen Öffnen unnötig einmal nativ neu zu
      // rendern (mit DevelopAdjustments.neutral käme ohnehin dasselbe Bild
      // heraus) – erspart bei RAW-Dateien einen vollen CIRAWFilter-Durchlauf,
      // nur um exakt das zu zeigen, was schon auf der Platte liegt.
      await _showExistingPreview();
      unawaited(_initShaderVorschau(unbearbeitet: true));
    } else {
      await _requestPreview();
      unawaited(_initShaderVorschau(unbearbeitet: false));
    }
  }

  Future<void> _showExistingPreview() async {
    try {
      final bytes = await widget.paths
          .absolute(displayRelativePath(widget.asset))
          .readAsBytes();
      if (!mounted) return;
      setState(() => _previewBytes = bytes);
      unawaited(_recomputeHistogram());
    } catch (_) {
      // Vorschaudatei fehlt/unlesbar – auf den nativen Renderpfad zurückfallen.
      await _requestPreview();
    }
  }

  /// Liest die gespeicherte Farbtabelle ein.
  ///
  /// Eine fehlende oder beschädigte Datei darf den Bildschirm nicht
  /// aufhalten: Der Look fällt dann weg, das Foto erscheint trotzdem, und
  /// der Nutzer bekommt einen Hinweis. Ohne diesen Zweig bliebe das
  /// Entwickeln für ein Foto dauerhaft unerreichbar, nur weil eine
  /// Zusatzdatei fehlt.
  @override
  Future<void> _ladeLut(String? relativerPfad) async {
    if (relativerPfad == null) {
      _lutPfad = null;
      _lut = null;
      return;
    }
    try {
      final datei = widget.paths.absolute(relativerPfad);
      _lut = parseCubeLut(await datei.readAsString());
      _lutPfad = relativerPfad;
    } catch (_) {
      _lut = null;
      _lutPfad = null;
      if (mounted) {
        melde.warnung(
          AppTexte.of(context).entwLutFehlt(p.basename(relativerPfad)),
        );
      }
    }
  }

  /// Wählt eine `.cube`-Datei, kopiert sie in die Bibliothek und aktiviert
  /// sie.
  ///
  /// Kopiert statt verwiesen: Eine Entwicklung, die auf eine Datei im
  /// Download-Ordner zeigt, sähe nach dem nächsten Aufräumen anders aus,
  /// und ein Backup enthielte den Look nicht.
  @override
  Future<void> _lutWaehlen() async {
    final auswahl = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['cube'],
      dialogTitle: AppTexte.of(context).entwLutWaehlen,
    );
    final quelle = auswahl?.path;
    if (quelle == null) return;

    try {
      final inhalt = await File(quelle).readAsString();
      final tabelle = parseCubeLut(inhalt);

      final name = p.basename(quelle);
      final ziel = widget.paths.absolute(widget.paths.lutRelativePath(name));
      await ziel.parent.create(recursive: true);
      await ziel.writeAsString(inhalt);

      if (!mounted) return;
      setState(() {
        _lut = tabelle;
        _lutPfad = widget.paths.lutRelativePath(name);
        _lutStaerke = 1;
        _dragging = false;
      });
      _scheduleRerender();
    } on CubeAusnahme catch (e) {
      if (!mounted) return;
      melde.fehler(_lutFehlertext(AppTexte.of(context), e));
    } catch (e) {
      if (!mounted) return;
      melde.fehler(AppTexte.of(context).entwLutNichtLesbar('$e'));
    }
  }

  /// Übersetzt den Grund aus [CubeAusnahme] in einen Satz. Die Dienstschicht
  /// liefert bewusst nur den Typ – welche Sprache gesprochen wird, weiss
  /// erst die Oberfläche.
  String _lutFehlertext(AppTexte t, CubeAusnahme e) => switch (e.grund) {
    CubeFehler.nurEindimensional => t.entwLutEindimensional,
    CubeFehler.keineGroesse => t.entwLutOhneGroesse,
    CubeFehler.ungueltigeGroesse => t.entwLutGroesse(e.zeile),
    CubeFehler.falscheZeilenzahl => t.entwLutZeilenzahl,
    CubeFehler.unlesbareZeile => t.entwLutZeile(e.zeile),
  };

  @override
  DevelopAdjustments _currentAdjustments() => DevelopAdjustments(
    exposure: _exposure,
    temperature: _autoWhiteBalance ? null : _temperature,
    tint: _autoWhiteBalance ? null : _tint,
    contrast: _contrast,
    shadows: _shadows,
    highlights: _highlights,
    sharpness: _sharpness,
    noiseReduction: _noiseReduction,
    clarity: _clarity,
    vignette: _vignette,
    lensCorrectionEnabled: _lensCorrectionEnabled,
    toneCurve: _toneCurve,
    colorMixer: _colorMixer,
    lut: _lut,
    lutStrength: _lutStaerke,
  );

  /// Baut die Masken-Ebenen für den nativen Renderaufruf: für die gerade
  /// ausgewählte Maske werden die LIVE-Entwurfswerte verwendet (damit
  /// Regler-Änderungen sofort sichtbar werden), für alle anderen die
  /// zuletzt gespeicherten Werte aus der DB.
  @override
  List<MaskAdjustmentLayer> _currentMaskLayers() {
    return _masks.map((mask) {
      final adjustments = mask.id == _selectedMaskId
          ? DevelopAdjustments(
              exposure: _maskExposure,
              temperature: _maskAutoWhiteBalance ? null : _maskTemperature,
              tint: _maskAutoWhiteBalance ? null : _maskTint,
              contrast: _maskContrast,
              shadows: _maskShadows,
              highlights: _maskHighlights,
              sharpness: _maskSharpness,
              noiseReduction: _maskNoiseReduction,
            )
          : DevelopAdjustments(
              exposure: mask.exposure,
              temperature: mask.temperature,
              tint: mask.tint,
              contrast: mask.contrast,
              shadows: mask.shadows,
              highlights: mask.highlights,
              sharpness: mask.sharpness,
              noiseReduction: mask.noiseReduction,
            );
      return MaskAdjustmentLayer(
        maskFilePath: widget.paths.absolute(mask.maskRelativePath).path,
        adjustments: adjustments,
      );
    }).toList();
  }

  /// Rendert eine Vorschau über den nativen Kanal – immer aus der echten
  /// Originaldatei (nicht aus previewRelativePath/developedRelativePath),
  /// da nur die Originaldatei bei RAW-Formaten die vollen Rohdaten für
  /// CIRAWFilter enthält. [_requestToken] verwirft spät eintreffende
  /// Antworten auf schnelles Regler-Ziehen, damit nie eine neuere Vorschau
  /// von einer älteren, langsameren Anfrage überschrieben wird.
  @override
  Future<void> _requestPreview() async {
    final token = ++_requestToken;
    setState(() => _rendering = true);
    final sourceFile = await widget.paths.bereit(widget.asset.relativePath);
    final bytes = await NativeImageConverter.developImage(
      sourceFile,
      adjustments: _currentAdjustments(),
      masks: _currentMaskLayers(),
      maxDimension: 1600,
      quality: 0.85,
    );
    if (token != _requestToken || !mounted) return;
    setState(() {
      _rendering = false;
      // Jetzt erst ist der native Render da – ab hier darf die
      // Shader-Vorschau abgelöst werden (siehe onChangeEnd im _slider).
      _dragging = false;
      if (bytes != null) {
        _previewBytes = bytes;
        _error = null;
      } else {
        _error = AppTexte.of(context).entwVorschauFehlt;
      }
    });
    if (bytes != null) unawaited(_recomputeHistogram());
  }

  /// Rechnet **waehrend** des Ziehens nativ – fuer die Regler, die der
  /// Shader nicht zeigen kann.
  ///
  /// **Warum das geht.** Ein Render der Vorschau kostet an einer
  /// Aufnahme von 6000×4000 Punkten gemessen 42 ms (Kante 1600; 1200
  /// bringt nichts, 2048 kostet 44). Das sind rund zwanzig Bilder je
  /// Sekunde – genug, dass ein Regler sich anfuehlt wie einer.
  ///
  /// **Warum ohne feste Taktrate.** Ein RAW geht durch CIRAWFilter und
  /// braucht ein Vielfaches; unter Linux und Windows rechnet an dieser
  /// Stelle der Shader das ganze Bild samt Kodierung (siehe
  /// [DevelopRender]), und auch das dauert laenger. Eine feste
  /// Drosselung waere dort eine Warteschlange, die nie leer wird.
  /// Stattdessen laeuft immer nur **ein** Render; was waehrenddessen an
  /// Bewegung anfaellt, wird zu einem einzigen Nachzuegler
  /// zusammengefasst. Schnelle Dateien bekommen dadurch viele Bilder,
  /// langsame wenige – von selbst, ohne dass irgendwo eine Zahl steht.
  @override
  Future<void> _liveNativ() async {
    if (_liveRendert) {
      _liveNochmal = true;
      return;
    }
    _liveRendert = true;
    try {
      do {
        _liveNochmal = false;
        await _requestPreview();
      } while (_liveNochmal && mounted);
      // Erst wenn nichts mehr nachkommt: Der Verlauf soll einen Schritt
      // je Zug bekommen, nicht einen je Zwischenbild. Ohne diese Zeile
      // fehlten die Regler, die nicht ueber den Entpreller laufen, im
      // Verlauf ganz.
      _merkeSchritt();
    } finally {
      _liveRendert = false;
    }
  }

  @override
  void _scheduleRerender() => _debouncer.run(() {
    // **Hier und nicht im Regler**: Der Entprelle laesst genau einen
    // Durchgang je gesetzter Aenderung durch. Am Regler selbst waere
    // jeder Punkt Reglerweg ein Schritt, und der Verlauf haette nach
    // einem Zug zweihundert Eintraege.
    _merkeSchritt();
    _requestPreview();
  });

  /// Haelt den aktuellen Stand als Schritt fest, wenn er neu ist.
  void _merkeSchritt() {
    if (!_sitzungBegonnen) return;
    final vorher = _sitzung.length;
    _sitzung = mitSchritt(_sitzung, _currentAdjustments());
    if (_sitzung.length != vorher && mounted) setState(() {});
  }

  /// Berechnet das Histogramm zur aktuellen Vorschau neu – ausgelagert über
  /// `compute()`, da Dekodieren + Auswerten des Vorschaubilds sonst bei
  /// jedem Regler-Loslassen den UI-Thread blockieren würde.
  ///
  /// Fehler werden bewusst verschluckt: das Histogramm ist eine reine
  /// Zusatzanzeige und darf die Entwicklung nie stören.
  Future<void> _recomputeHistogram() async {
    final bytes = _previewBytes;
    if (bytes == null) return;
    final token = ++_histogramToken;
    setState(() => _histogramPending = true);
    try {
      final auswertung = await compute(computeBildAuswertung, bytes);
      if (token != _histogramToken || !mounted) return;
      setState(() {
        _histogram = auswertung?.histogramm;
        _waveform = auswertung?.waveform;
        // Fällt beim Dekodieren ohnehin an (siehe BildAuswertung) – der
        // Trennstrich braucht es, um auf dem Bild zu sitzen und nicht auf
        // dem Widget.
        _vorschauSeitenverhaeltnis = auswertung?.seitenverhaeltnis;
        _histogramPending = false;
      });
    } catch (_) {
      if (token != _histogramToken || !mounted) return;
      setState(() => _histogramPending = false);
    }
  }

  /// Rendert die unbearbeitete Vorschau (neutrale Regler) einmalig und
  /// cached sie – für das Gedrückt-Halten-"Vorher"-Bild. Kein zusätzlicher
  /// nativer Aufruf bei wiederholtem Halten.
  Future<void> _ensureOriginalPreviewLoaded() async {
    if (_originalPreviewBytes != null || _loadingOriginalPreview) return;
    _loadingOriginalPreview = true;
    final sourceFile = await widget.paths.bereit(widget.asset.relativePath);
    final bytes = await NativeImageConverter.developImage(
      sourceFile,
      adjustments: DevelopAdjustments.neutral,
      maxDimension: 1600,
      quality: 0.85,
    );
    _loadingOriginalPreview = false;
    if (mounted && bytes != null) setState(() => _originalPreviewBytes = bytes);
  }

  /// Schaltet den Vorher/Nachher-Trennstrich um.
  ///
  /// Beim Einschalten muss das unbearbeitete Bild angefordert werden –
  /// bisher geschah das nur beim Gedrueckt-Halten. Ohne diesen Aufruf
  /// bliebe der Strich stumm aus (siehe [trennstrichZeigen]), und man
  /// suchte den Fehler beim Knopf.
  void _trennstrichUmschalten() {
    if (_trennstrich == null) {
      _ensureOriginalPreviewLoaded();
      setState(() => _trennstrich = 0.5);
    } else {
      setState(() => _trennstrich = null);
    }
  }

  /// Vorher und Nachher nebeneinander, getrennt durch einen ziehbaren
  /// Strich.
  ///
  /// Beide Bilder liegen bereits vor – links das unbearbeitete, rechts das
  /// entwickelte. Es entsteht kein zusaetzlicher Render.
  Widget _buildTrennstrichVergleich() {
    final verhaeltnis = _vorschauSeitenverhaeltnis;
    // Ohne bekanntes Seitenverhaeltnis waere die Lage des Strichs geraten.
    // Dann lieber das normale Bild zeigen, bis die Auswertung da ist.
    if (verhaeltnis == null) {
      return Image.memory(
        _previewBytes!,
        gaplessPlayback: true,
        fit: BoxFit.contain,
      );
    }

    return VorherNachherVergleich(
      original: _originalPreviewBytes!,
      bearbeitet: _previewBytes!,
      seitenverhaeltnis: verhaeltnis,
      anteil: _trennstrich!,
      beiVerschieben: (a) => setState(() => _trennstrich = a),
      vorherText: AppTexte.of(context).entwVorher,
      nachherText: AppTexte.of(context).entwNachher,
    );
  }
}
