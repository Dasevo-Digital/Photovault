part of '../develop_screen.dart';

/// Masken anlegen: KI-Auswahl, Formen, Farbbereich, Tiefe, und die Gesten dazu.
mixin _Masken on _EntwickelnBasis {
  // --- KI-Objektmasken ---------------------------------------------------

  @override
  void _selectMask(DevelopMaskData mask) {
    setState(() {
      _selectedMaskId = mask.id;
      _maskExposure = mask.exposure;
      _maskContrast = mask.contrast;
      _maskShadows = mask.shadows;
      _maskHighlights = mask.highlights;
      _maskSharpness = mask.sharpness;
      _maskNoiseReduction = mask.noiseReduction;
      _maskAutoWhiteBalance = mask.temperature == null;
      _maskTemperature = mask.temperature ?? 6500;
      _maskTint = mask.tint ?? 0;
    });
  }

  @override
  void _selectGlobalAdjustments() => setState(() => _selectedMaskId = null);

  @override
  Future<void> _deleteMask(DevelopMaskData mask) async {
    await widget.db.deleteDevelopMask(mask.id);
    final file = widget.paths.absolute(mask.maskRelativePath);
    if (await file.exists()) await file.delete();
    if (!mounted) return;
    setState(() {
      _masks = _masks.where((m) => m.id != mask.id).toList();
      if (_selectedMaskId == mask.id) _selectedMaskId = null;
    });
    _scheduleRerender();
  }

  /// Öffnet den Masken-Editor. Ohne [editingMask] startet ein neuer Entwurf
  /// (Formtyp: KI-Auswahl, falls [SegmentationService] verfügbar, sonst
  /// Pinsel als sinnvollste Standardwahl). Mit [editingMask] wird stattdessen
  /// dessen gespeicherte Vektorform zum Weiterbearbeiten geladen (nur möglich
  /// für Masken mit `shapeDefinitionJson`, siehe "Form bearbeiten" in
  /// _buildAdjustmentsPanel).
  @override
  Future<void> _startMaskCreation({DevelopMaskData? editingMask}) async {
    MaskShapeDefinition? shape;
    if (editingMask?.shapeDefinitionJson != null) {
      shape = MaskShapeDefinition.decode(editingMask!.shapeDefinitionJson!);
    }
    final formType = switch (shape) {
      FreehandShape() => _MaskFormType.freehand,
      EllipseShape() => _MaskFormType.ellipse,
      RectangleShape() => _MaskFormType.rectangle,
      GradientShape() => _MaskFormType.gradient,
      ColorRangeShape() => _MaskFormType.colorRange,
      null =>
        (widget.segmentation?.installiert ?? false)
            ? _MaskFormType.aiSelect
            : _MaskFormType.freehand,
    };
    setState(() {
      _maskEditMode = true;
      _maskFormType = formType;
      _editingMaskId = editingMask?.id;
      _draftShape = shape;
      _ellipseDragAnchor = null;
      _maskPoints.clear();
      _backgroundPointMode = false;
      _pendingMaskResult = null;
      _pendingMaskOverlayPng = null;
    });
    if (formType == _MaskFormType.aiSelect) await _ensureEmbedding();
  }

  /// Wechselt den Formtyp innerhalb des offenen Masken-Editors – verwirft
  /// dabei immer einen eventuell geladenen Bearbeiten-Entwurf ([_editingMaskId]),
  /// da eine Form bei ihrem eigentlichen Typ bleibt und ein Typwechsel somit
  /// automatisch eine NEUE Maske anlegt statt die alte zu ersetzen.
  @override
  void _switchMaskFormType(_MaskFormType type) {
    setState(() {
      _maskFormType = type;
      _draftShape = null;
      _editingMaskId = null;
      _ellipseDragAnchor = null;
      _maskPoints.clear();
      _pendingMaskResult = null;
      _pendingMaskOverlayPng = null;
    });
    if (type == _MaskFormType.aiSelect) _ensureEmbedding();
    // Vorgriff: Dann steht das Bild meist schon bereit, wenn der erste
    // Tipp kommt.
    if (type == _MaskFormType.colorRange) unawaited(_ensureDekodiert());
  }

  @override
  void _cancelMaskCreation() {
    setState(() {
      _maskEditMode = false;
      _maskPoints.clear();
      _pendingMaskResult = null;
      _pendingMaskOverlayPng = null;
      _draftShape = null;
      _editingMaskId = null;
      _ellipseDragAnchor = null;
    });
  }

  /// Berechnet das (teure) Bild-Embedding einmalig beim Öffnen des
  /// Maskier-Modus – aus der bereits vorhandenen Vorschau (nicht dem
  /// RAW-Original: das `image`-Paket kann RAW nicht dekodieren, die
  /// Vorschau ist für die interaktive Punktauswahl auflösungsmäßig mehr
  /// als ausreichend).
  Future<void> _ensureEmbedding() async {
    final halter = widget.segmentation;
    final previewBytes = _previewBytes;
    if (halter == null || previewBytes == null || _embedding != null) return;
    setState(() {
      _computingEmbedding = true;
      _ladeSegmentierungsmodell = !halter.istGeladen;
    });

    SegmentationService? segmentation;
    try {
      segmentation = await halter.leihen();
    } catch (e) {
      if (mounted) {
        setState(() => _computingEmbedding = false);
        melde.fehler(AppTexte.of(context).entwKiAuswahlLadefehler('$e'));
      }
      return;
    }
    if (segmentation == null) {
      if (mounted) setState(() => _computingEmbedding = false);
      return;
    }

    // Ab hier ist die Leihe offen und MUSS auf jedem Weg wieder heraus –
    // ausser im Erfolgsfall, wo dieser Bildschirm sie bis zu seinem
    // dispose() behält. Vorher lagen `compute` und `encodeImage` ohne
    // try/finally dazwischen: Warf eines von beiden (ONNX-Inferenz kann
    // das), blieb der Nutzerzähler für immer auf 1, das
    // Segmentierungsmodell (101 MB) liess sich bis zum Programmende nicht
    // mehr freigeben, und der Ladekringel drehte sich endlos weiter.
    // dispose() half dabei nicht: Es prüft `_segmentation`, das erst im
    // Erfolgsfall gesetzt wird (Audit-Fund).
    var behalten = false;
    try {
      final decoded = await compute(decodeImageBytes, previewBytes);
      if (decoded == null) {
        if (mounted) {
          setState(() => _computingEmbedding = false);
          melde.warnung(AppTexte.of(context).entwVorschauNichtDekodiert);
        }
        return;
      }
      final embedding = await segmentation.encodeImage(decoded);
      // Bildschirm inzwischen verlassen? Dann gibt das finally die Leihe
      // zurück – dispose() kann sie nicht kennen, dieser Aufruf war ja
      // noch nicht fertig.
      if (!mounted) return;
      setState(() {
        _decodedForMasking = decoded;
        _embedding = embedding;
        _segmentation = segmentation;
        _computingEmbedding = false;
      });
      behalten = true;
    } catch (e) {
      if (mounted) {
        setState(() => _computingEmbedding = false);
        melde.fehler(AppTexte.of(context).entwKiAuswahlFehler('$e'));
      }
    } finally {
      if (!behalten) halter.zurueckgeben();
    }
  }

  /// Der tatsächlich gerenderte Bildbereich innerhalb eines Widgets, das per
  /// `BoxFit.contain` skaliert/gelettert wird (Muster: BoxFit.contain-Formel).
  /// Gemeinsame Grundlage für [_widgetPointToImagePoint] (Pixel-Koordinaten,
  /// KI-Auswahl) und [_widgetPointToNormalizedImagePoint] ([0,1]-Koordinaten,
  /// Vektorformen).
  ///
  /// [widgetSize] ist die volle Fläche des Editors – der Rand, in dem das
  /// Bild darin sitzt ([_EntwickelnBasis._maskenrand]), wird hier abgezogen. Ohne das lag
  /// der berechnete Bildbereich um genau diesen Rand daneben, und jede
  /// Maskengeste traf ein paar Bildpunkte neben der Stelle, auf die
  /// gezeigt wurde.
  @override
  Rect _imageDisplayRect(
    Size widgetSize,
    double imageWidth,
    double imageHeight,
  ) {
    final flaeche = Rect.fromLTWH(
      0,
      0,
      widgetSize.width,
      widgetSize.height,
    ).deflate(_EntwickelnBasis._maskenrand);
    // Ein Editor, der schmaler ist als sein eigener Rand, hat keinen
    // Bildbereich – ohne diese Rückfallebene käme eine negative Breite
    // heraus, und jede Umrechnung darauf wäre Unsinn.
    if (flaeche.width <= 0 || flaeche.height <= 0) return Rect.zero;
    final imageAspect = imageWidth / imageHeight;
    final widgetAspect = flaeche.width / flaeche.height;
    double renderedWidth, renderedHeight, offsetX, offsetY;
    if (imageAspect > widgetAspect) {
      renderedWidth = flaeche.width;
      renderedHeight = flaeche.width / imageAspect;
      offsetX = 0;
      offsetY = (flaeche.height - renderedHeight) / 2;
    } else {
      renderedHeight = flaeche.height;
      renderedWidth = flaeche.height * imageAspect;
      offsetY = 0;
      offsetX = (flaeche.width - renderedWidth) / 2;
    }
    return Rect.fromLTWH(
      flaeche.left + offsetX,
      flaeche.top + offsetY,
      renderedWidth,
      renderedHeight,
    );
  }

  /// Rechnet eine Tipp-Position innerhalb des Vorschau-Widgets in eine
  /// Pixel-Koordinate des dekodierten Bilds um. `null`, wenn der Tipp im
  /// Letterbox-Rand lag.
  Offset? _widgetPointToImagePoint(
    Offset local,
    Size widgetSize,
    int imageWidth,
    int imageHeight,
  ) {
    final rect = _imageDisplayRect(
      widgetSize,
      imageWidth.toDouble(),
      imageHeight.toDouble(),
    );
    final dx = local.dx - rect.left;
    final dy = local.dy - rect.top;
    if (dx < 0 || dy < 0 || dx > rect.width || dy > rect.height) return null;
    return Offset(dx / rect.width * imageWidth, dy / rect.height * imageHeight);
  }

  /// Wie [_widgetPointToImagePoint], aber bild-normalisiert ([0,1]) und ohne
  /// ein dekodiertes Bitmap zu brauchen (nutzt direkt Assets.widthPx/heightPx)
  /// – für die Vektorformen-Editoren, die (anders als die KI-Auswahl) kein
  /// SAM-Embedding und damit auch keine Dekodierung des Vorschaubilds
  /// benötigen.
  Offset? _widgetPointToNormalizedImagePoint(Offset local, Size widgetSize) {
    final imageWidth = widget.asset.widthPx;
    final imageHeight = widget.asset.heightPx;
    if (imageWidth == null ||
        imageHeight == null ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      return null;
    }
    final rect = _imageDisplayRect(
      widgetSize,
      imageWidth.toDouble(),
      imageHeight.toDouble(),
    );
    final dx = local.dx - rect.left;
    final dy = local.dy - rect.top;
    if (dx < 0 || dy < 0 || dx > rect.width || dy > rect.height) return null;
    return Offset(dx / rect.width, dy / rect.height);
  }

  /// Sorgt dafür, dass das Vorschaubild dekodiert vorliegt.
  ///
  /// Bis hierher füllte [_decodedForMasking] **nur** der KI-Weg
  /// ([_ensureEmbedding]). Wer die Farbmaske wählte, ohne vorher die
  /// KI-Auswahl geöffnet zu haben – und ohne installiertes
  /// Segmentierungsmodell geht das gar nicht –, tippte ins Leere:
  /// [_handleFarbeAufnehmen] kehrt ohne dekodiertes Bild wortlos zurück.
  /// Der Farbwähler braucht kein SAM, nur Bildpunkte.
  Future<img.Image?> _ensureDekodiert() {
    final vorhanden = _decodedForMasking;
    if (vorhanden != null) return Future.value(vorhanden);
    // Ein laufender Lauf wird geteilt: Zwei Tipps kurz nacheinander
    // sollen nicht zweimal dasselbe Bild dekodieren.
    return _dekodierung ??= _dekodiereVorschau();
  }

  Future<img.Image?> _dekodiereVorschau() async {
    final bytes = _previewBytes;
    if (bytes == null) {
      _dekodierung = null;
      return null;
    }
    final decoded = await compute(decodeImageBytes, bytes);
    if (!mounted) return decoded;
    if (decoded == null) {
      // Beim nächsten Versuch neu probieren: Ein gescheiterter Lauf ist
      // kein Ergebnis, das man festhalten will.
      _dekodierung = null;
      melde.warnung(AppTexte.of(context).entwVorschauNichtDekodiert);
      return null;
    }
    setState(() => _decodedForMasking = decoded);
    return decoded;
  }

  @override
  void _handleMaskTap(Offset local, Size widgetSize) {
    final decoded = _decodedForMasking;
    if (decoded == null || _computingMask) return;
    final imagePoint = _widgetPointToImagePoint(
      local,
      widgetSize,
      decoded.width,
      decoded.height,
    );
    if (imagePoint == null) return;
    setState(
      () => _maskPoints.add((
        point: imagePoint,
        isBackground: _backgroundPointMode,
      )),
    );
    _runMaskPrediction();
  }

  /// Nimmt die Farbe unter dem Finger auf und legt daraus eine
  /// Farbauswahl-Form an.
  ///
  /// Gelesen wird aus der Vorschau, die ohnehin im Speicher liegt – das
  /// Original dafür zu dekodieren wäre für drei Zahlen zu teuer, und für
  /// eine Farbe ist die Vorschau genau genug.
  @override
  Future<void> _handleFarbeAufnehmen(Offset local, Size widgetSize) async {
    if (_maskFormType != _MaskFormType.colorRange) return;
    final punkt = _widgetPointToNormalizedImagePoint(local, widgetSize);
    if (punkt == null) return;
    final decoded = await _ensureDekodiert();
    if (decoded == null || !mounted) return;
    // Der Werkzeugwechsel während des Dekodierens verwirft den Tipp:
    // Sonst entstünde eine Farbmaske, obwohl längst ein anderes
    // Werkzeug gewählt ist.
    if (_maskFormType != _MaskFormType.colorRange) return;

    final x = (punkt.dx * decoded.width).floor().clamp(0, decoded.width - 1);
    final y = (punkt.dy * decoded.height).floor().clamp(0, decoded.height - 1);
    final pixel = decoded.getPixel(x, y);
    final maxWert = pixel.maxChannelValue;
    final faktor = maxWert > 0 ? 255.0 / maxWert : 1.0;

    final vorher = _draftShape;
    setState(
      () => _draftShape = ColorRangeShape(
        pointX: punkt.dx,
        pointY: punkt.dy,
        red: (pixel.r * faktor).round().clamp(0, 255),
        green: (pixel.g * faktor).round().clamp(0, 255),
        blue: (pixel.b * faktor).round().clamp(0, 255),
        // Toleranz und Weichzeichnung überleben ein erneutes Aufnehmen:
        // Wer die Werte eingestellt hat und dann daneben getroffen hat,
        // will nicht von vorn anfangen.
        tolerance: vorher is ColorRangeShape ? vorher.tolerance : 0.25,
        feather: vorher is ColorRangeShape ? vorher.feather : 0.3,
      ),
    );
  }

  @override
  void _undoLastMaskPoint() {
    if (_maskPoints.isEmpty) return;
    setState(() => _maskPoints.removeLast());
    if (_maskPoints.isEmpty) {
      setState(() {
        _pendingMaskResult = null;
        _pendingMaskOverlayPng = null;
      });
    } else {
      _runMaskPrediction();
    }
  }

  /// EIN Forward-Pass durch den Masken-Decoder pro Punkt-Änderung (siehe
  /// SegmentationService.decodeMask) – kein Mehrschritt-Loop, daher auch
  /// bei mehreren Punkten hintereinander noch interaktiv genug.
  Future<void> _runMaskPrediction() async {
    final segmentation = _segmentation;
    final embedding = _embedding;
    if (segmentation == null || embedding == null || _maskPoints.isEmpty) {
      return;
    }
    setState(() => _computingMask = true);
    final foreground = [
      for (final p in _maskPoints)
        if (!p.isBackground) p.point,
    ];
    final background = [
      for (final p in _maskPoints)
        if (p.isBackground) p.point,
    ];
    if (foreground.isEmpty) {
      // SAM braucht mindestens einen Vordergrund-Punkt, um sinnvoll zu
      // starten – reine Hintergrund-Punkte allein ergeben keine Maske.
      setState(() => _computingMask = false);
      return;
    }
    final result = await segmentation.decodeMask(
      embedding,
      foregroundPoints: foreground,
      backgroundPoints: background,
    );
    // Über compute() ausgelagert (Audit-Fund: Hochskalieren/Einfärben/PNG-
    // Kodieren lief vorher synchron im Haupt-Isolate bei JEDEM Punkt-Tap).
    final overlayPng = await compute(renderMaskPreviewPng, result);
    if (!mounted) return;
    setState(() {
      _pendingMaskResult = result;
      _pendingMaskOverlayPng = overlayPng;
      _computingMask = false;
    });
  }

  Future<void> _commitMask() async {
    final result = _pendingMaskResult;
    if (result == null) return;
    // Vor dem ersten await auflösen – danach ist der Kontext nicht mehr
    // verlässlich. Der Name wird gespeichert und bleibt deshalb in der
    // Sprache stehen, in der die Maske entstanden ist; das ist gewollt,
    // Masken lassen sich wie Alben umbenennen.
    final name = AppTexte.of(context).entwMaskeNummer(_masks.length + 1);
    final pngBytes = await compute(renderMaskPngBytes, result);
    final relativePath = widget.paths.maskRelativePath(const Uuid().v4());
    final file = widget.paths.absolute(relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(pngBytes);

    await widget.db.createDevelopMask(
      DevelopMasksCompanion.insert(
        assetId: widget.asset.id,
        maskRelativePath: relativePath,
        label: name,
        createdAt: DateTime.now(),
      ),
    );
    final refreshedMasks = await widget.db.masksForAsset(widget.asset.id);

    if (!mounted) return;
    setState(() {
      _masks = refreshedMasks;
      _maskEditMode = false;
      _maskPoints.clear();
      _pendingMaskResult = null;
      _pendingMaskOverlayPng = null;
    });
    _selectMask(_masks.last);
    _scheduleRerender();
  }

  /// Legt eine Maske aus der Tiefenkarte des Fotos an.
  ///
  /// Der Unterschied zu allem anderen im Maskeneditor: Hier wird nichts
  /// gezeichnet und nichts angeklickt. Die Kamera hat beim Auslösen
  /// gemessen, wie weit jeder Punkt entfernt war – das liegt als
  /// Hilfsbild in der Datei und wird hier zur Maske. Hell ist nah, also
  /// das Motiv; wer den Hintergrund treffen will, kehrt die Maske um.
  ///
  /// Nur unter macOS (siehe [Tiefenmaskenstand]). Der Knopf steht
  /// trotzdem überall – und sagt, warum er hier nicht kann, statt zu
  /// fehlen.
  Future<void> _tiefenmaskeAnlegen() async {
    final t = AppTexte.of(context);
    setState(() => _computingMask = true);
    final ergebnis = await NativeImageConverter.tiefenmaske(
      widget.paths.absolute(widget.asset.relativePath),
    );
    if (!mounted) return;
    setState(() => _computingMask = false);

    if (ergebnis.stand != Tiefenmaskenstand.verfuegbar) {
      // Als Warnung: Der Knopf ist gedrückt worden und hat nichts
      // bewirkt. Die sechs Sekunden von früher braucht es nicht mehr –
      // eine Warnung steht ohnehin acht.
      melde.warnung(switch (ergebnis.stand) {
        Tiefenmaskenstand.nichtAufDieserPlattform => t.entwTiefenNurMacos,
        Tiefenmaskenstand.nichtLesbar => t.entwTiefenNichtLesbar,
        _ => t.entwTiefenKeine,
      });
      return;
    }

    final name = t.entwTiefenmaskeName;
    final relativePath = widget.paths.maskRelativePath(const Uuid().v4());
    final datei = widget.paths.absolute(relativePath);
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(ergebnis.png!);

    await widget.db.createDevelopMask(
      DevelopMasksCompanion.insert(
        assetId: widget.asset.id,
        maskRelativePath: relativePath,
        label: name,
        createdAt: DateTime.now(),
      ),
    );
    final frisch = await widget.db.masksForAsset(widget.asset.id);
    if (!mounted) return;
    setState(() => _masks = frisch);
    _selectMask(_masks.last);
    _scheduleRerender();
  }

  // --- Vektor-Masken: Zieh-Gesten -----------------------------------------

  @override
  void _handleShapePanStart(DragStartDetails details, Size widgetSize) {
    final point = _widgetPointToNormalizedImagePoint(
      details.localPosition,
      widgetSize,
    );
    if (point == null) return;
    switch (_maskFormType) {
      case _MaskFormType.freehand:
        setState(
          () => _draftShape = FreehandShape(
            points: [point],
            strokeWidth: (_draftShape as FreehandShape?)?.strokeWidth ?? 0.03,
          ),
        );
      case _MaskFormType.ellipse:
      case _MaskFormType.rectangle:
        // Beide werden gleich aufgezogen: von Ecke zu Ecke.
        setState(() => _ellipseDragAnchor = point);
      case _MaskFormType.gradient:
        final feather = (_draftShape as GradientShape?)?.feather ?? 0.3;
        setState(
          () => _draftShape = GradientShape(
            startX: point.dx,
            startY: point.dy,
            endX: point.dx,
            endY: point.dy,
            feather: feather,
          ),
        );
      case _MaskFormType.aiSelect:
      case _MaskFormType.colorRange:
        // Beide entstehen aus einem Tipp, nicht aus einer Zieh-Geste.
        break;
    }
  }

  @override
  void _handleShapePanUpdate(DragUpdateDetails details, Size widgetSize) {
    final point = _widgetPointToNormalizedImagePoint(
      details.localPosition,
      widgetSize,
    );
    if (point == null) return;
    switch (_maskFormType) {
      case _MaskFormType.freehand:
        final current = _draftShape;
        if (current is! FreehandShape) return;
        setState(
          () => _draftShape = FreehandShape(
            points: [...current.points, point],
            strokeWidth: current.strokeWidth,
          ),
        );
      case _MaskFormType.ellipse:
        final anchor = _ellipseDragAnchor;
        if (anchor == null) return;
        final previous = _draftShape;
        final rotation = previous is EllipseShape ? previous.rotation : 0.0;
        final feather = previous is EllipseShape ? previous.feather : 0.3;
        setState(
          () => _draftShape = EllipseShape(
            centerX: (anchor.dx + point.dx) / 2,
            centerY: (anchor.dy + point.dy) / 2,
            radiusX: math.max(0.01, (point.dx - anchor.dx).abs() / 2),
            radiusY: math.max(0.01, (point.dy - anchor.dy).abs() / 2),
            rotation: rotation,
            feather: feather,
          ),
        );
      case _MaskFormType.rectangle:
        final anchor = _ellipseDragAnchor;
        if (anchor == null) return;
        final previous = _draftShape;
        final rotation = previous is RectangleShape ? previous.rotation : 0.0;
        final feather = previous is RectangleShape ? previous.feather : 0.2;
        setState(
          () => _draftShape = RectangleShape(
            centerX: (anchor.dx + point.dx) / 2,
            centerY: (anchor.dy + point.dy) / 2,
            halfWidth: math.max(0.01, (point.dx - anchor.dx).abs() / 2),
            halfHeight: math.max(0.01, (point.dy - anchor.dy).abs() / 2),
            rotation: rotation,
            feather: feather,
          ),
        );
      case _MaskFormType.gradient:
        final current = _draftShape;
        if (current is! GradientShape) return;
        setState(
          () => _draftShape = GradientShape(
            startX: current.startX,
            startY: current.startY,
            endX: point.dx,
            endY: point.dy,
            feather: current.feather,
          ),
        );
      case _MaskFormType.aiSelect:
      case _MaskFormType.colorRange:
        break;
    }
  }

  @override
  bool get _canCommitShape => switch (_maskFormType) {
    _MaskFormType.aiSelect => _pendingMaskResult != null,
    _MaskFormType.freehand => _draftShape is FreehandShape,
    _MaskFormType.ellipse => _draftShape is EllipseShape,
    _MaskFormType.rectangle => _draftShape is RectangleShape,
    _MaskFormType.gradient => _draftShape is GradientShape,
    _MaskFormType.colorRange => _draftShape is ColorRangeShape,
  };

  @override
  Future<void> _commitCurrentMask() =>
      _maskFormType == _MaskFormType.aiSelect ? _commitMask() : _commitShape();

  /// Rasterisiert [_draftShape] auf die tatsächliche Original-Bildauflösung
  /// (Muster: maskToOriginalResolution in segmentation_service.dart nutzt für
  /// KI-Masken dieselbe Zielauflösung) und legt eine neue DevelopMasks-Zeile
  /// an – oder, falls [_editingMaskId] gesetzt ist (erneutes Bearbeiten einer
  /// bestehenden Vektor-Maske über "Form bearbeiten"), überschreibt die
  /// vorhandene Maskendatei und aktualisiert nur ihre Geometrie.
  Future<void> _commitShape() async {
    final shape = _draftShape;
    if (shape == null) return;
    final width = widget.asset.widthPx;
    final height = widget.asset.heightPx;
    if (width == null || height == null || width <= 0 || height <= 0) {
      if (mounted) {
        melde.warnung(AppTexte.of(context).entwAufloesungUnbekannt);
      }
      return;
    }
    final name = AppTexte.of(context).entwMaskeNummer(_masks.length + 1);
    setState(() => _computingMask = true);
    // Der Quellpfad wird nur von der Farbauswahl gebraucht; die anderen
    // Formen fassen die Datei gar nicht an.
    final quellPfad = shape is ColorRangeShape
        ? widget.paths
              .absolute(
                widget.asset.previewRelativePath ?? widget.asset.relativePath,
              )
              .path
        : null;
    final pngBytes = await compute(rasterizeMaskShapeToPngBytes, (
      shape,
      width,
      height,
      quellPfad,
    ));
    var editingId = _editingMaskId;

    // Verteidigung gegen eine seit dem Öffnen des Editors zwischenzeitlich
    // gelöschte Maske (z.B. über einen anderen Weg entfernt) – ohne diese
    // Prüfung würde firstWhere() ohne Treffer abstürzen. Fällt in diesem
    // seltenen Fall auf "neu anlegen" zurück, statt die Bearbeitung zu
    // verwerfen.
    DevelopMaskData? existing;
    if (editingId != null) {
      for (final m in _masks) {
        if (m.id == editingId) existing = m;
      }
      if (existing == null) editingId = null;
    }

    if (editingId != null && existing != null) {
      await widget.paths
          .absolute(existing.maskRelativePath)
          .writeAsBytes(pngBytes);
      await widget.db.updateDevelopMaskShape(editingId, shape.encode());
    } else {
      final relativePath = widget.paths.maskRelativePath(const Uuid().v4());
      final file = widget.paths.absolute(relativePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(pngBytes);
      await widget.db.createDevelopMask(
        DevelopMasksCompanion.insert(
          assetId: widget.asset.id,
          maskRelativePath: relativePath,
          label: name,
          createdAt: DateTime.now(),
          shapeDefinitionJson: Value(shape.encode()),
        ),
      );
    }
    final refreshedMasks = await widget.db.masksForAsset(widget.asset.id);

    if (!mounted) return;
    setState(() {
      _masks = refreshedMasks;
      _maskEditMode = false;
      _computingMask = false;
      _draftShape = null;
    });
    DevelopMaskData? committedMask;
    if (editingId != null) {
      for (final m in refreshedMasks) {
        if (m.id == editingId) committedMask = m;
      }
    }
    committedMask ??= refreshedMasks.isEmpty ? null : refreshedMasks.last;
    _editingMaskId = null;
    if (committedMask != null) _selectMask(committedMask);
    _scheduleRerender();
  }
}
