part of '../develop_screen.dart';

/// Die Bedienfelder: Regler, Masken- und Formpanels, LUT, Restaurierungsfortschritt.
mixin _Bedienfelder on _EntwickelnBasis {
  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    bool enabled = true,

    /// Ob der Shader diesen Regler **richtig** zeigt.
    ///
    /// Wo ja, laeuft die Live-Vorschau ueber ihn – das ist der Regelfall
    /// und kostet nichts. Wo nein, wird waehrend des Ziehens nativ
    /// gerechnet (siehe [_liveNativ]).
    ///
    /// **Nein gilt fuer sechs Regler, und zwar nur unter macOS**, wo Core
    /// Image massgeblich ist: Schaerfe und Rauschunterdrueckung brauchen
    /// Nachbarpixel, die ein Fragment-Shader nicht sieht; Klarheit und
    /// Vignettierung sind reine Core-Image-Filter; Weissabgleich und
    /// Farbstich bildet der Shader nur genaehert nach (gemessen bis
    /// 6,1 % Abweichung bei 3200 K, gegenueber 0,1 % bei der Belichtung),
    /// und ausgerechnet an diesem Regler beurteilt man die Farbe. Wo der
    /// Shader selbst der Renderweg ist (Linux, Windows), ist er per
    /// Definition genau, und es gibt nichts zu unterscheiden.
    ///
    /// Vorher stand hier `liveVorschau: false`, und das hiess: waehrend
    /// des Ziehens passiert **gar nichts**. Der Regler bewegte sich, das
    /// Bild nicht.
    bool imShader = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Die Beschriftung nimmt, was uebrig ist, und kuerzt zur
              // Not. Ohne das laeuft „Rauschunterdrueckung" in der 300
              // Punkte breiten Spalte um 33 Punkte ueber ihren Rand –
              // und die Zahl daneben wird abgeschnitten.
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? DunkleFlaeche.text : DunkleFlaeche.inaktiv,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                value.toStringAsFixed(min.abs() >= 100 ? 0 : 2),
                style: TextStyle(
                  color: enabled
                      ? DunkleFlaeche.zweitText
                      : DunkleFlaeche.linie,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            // Während des Ziehens rechnet der Shader live; nach dem
            // Loslassen übernimmt wieder der native Render.
            onChangeStart: (enabled && imShader)
                ? (_) => setState(() => _dragging = true)
                : null,
            // Bewusst NICHT hier _dragging zurücksetzen: der native Render
            // ist erst nach Debounce + Renderzeit da. Sofortiges Umschalten
            // würde für diese Zeitspanne den ALTEN Stand zeigen, das Bild
            // also sichtbar zurückspringen. Zurückgesetzt wird in
            // _requestPreview(), sobald das neue Bild vorliegt.
            onChangeEnd: null,
            onChanged: enabled
                ? (v) {
                    onChanged(v);
                    // Was der Shader nicht zeigt, wird waehrend des
                    // Ziehens nativ gerechnet - sonst bewegt sich der
                    // Regler und das Bild nicht.
                    if (imShader) {
                      _scheduleRerender();
                    } else {
                      unawaited(_liveNativ());
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }

  /// Wie weit die KI-Restaurierung dieses Fotos ist.
  ///
  /// **Warum das hierhin gehört.** Der Knopf sagte „eingereiht" und
  /// danach nichts mehr. Ein Vorgang, der an einer echten Aufnahme rund
  /// hundert Sekunden dauert (20 Kacheln zu je fünf), verschwand damit
  /// aus dem Blick genau des Bildschirms, auf dem man ihn ausgelöst hat –
  /// zu sehen war er nur, wer den Warteschlangen-Bildschirm kannte.
  ///
  /// Gezeigt wird nur der Auftrag **dieses** Fotos. Die Warteschlange
  /// bleibt der Ort für alle.
  Widget _restaurierungsfortschritt() {
    return StreamBuilder<List<RestoreJobData>>(
      stream: _restaurierungen.hole(
        widget.asset.id,
        () => widget.db.watchRestoreJobs(),
      ),
      builder: (context, schnappschuss) {
        final auftrag = (schnappschuss.data ?? const <RestoreJobData>[])
            .where(
              (j) =>
                  j.assetId == widget.asset.id &&
                  (j.status == 'queued' || j.status == 'running'),
            )
            .firstOrNull;
        if (auftrag == null) return const SizedBox.shrink();
        final t = AppTexte.of(context);
        final prozent = fortschrittProzent(auftrag);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.entwRestaurierungLaeuft,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: Colors.white70,
                    tooltip: t.allgAbbrechen,
                    onPressed: () => widget.restoreQueue?.cancel(auftrag.id),
                  ),
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: LinearProgressIndicator(
                  // Solange die Kachelzahl nicht feststeht, laeuft der
                  // Balken unbestimmt - eine Null waere die Behauptung,
                  // es gehe nicht voran.
                  value: auftrag.status == 'running' && prozent != null
                      ? prozent / 100
                      : null,
                  minHeight: 5,
                  backgroundColor: Colors.white24,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                auftrag.status == 'queued'
                    ? t.restaurWartet
                    : restaurLaufText(t, auftrag),
                style: const TextStyle(
                  color: DunkleFlaeche.hinweis,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMaskEditor() => _maskFormType == _MaskFormType.aiSelect
      ? _buildAiSelectMaskEditor()
      : _buildShapeMaskEditor();

  Widget _buildAiSelectMaskEditor() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
        // `SizedBox.expand`: Der Editor haengt unter einem `Center` und
        // bekommt dort lockere Zwaenge. Ohne dieses Ausfuellen meldet der
        // `LayoutBuilder` die ganze freie Flaeche, der Stapel darunter
        // schrumpft aber auf das Bild - und dann rechnet die Umrechnung
        // Zeiger -> Bild mit einer anderen Flaeche, als die Geste
        // ankommt. Bei querformatigem Bild in hochformatiger Flaeche kam
        // dabei fuer jeden Punkt "ausserhalb" heraus: Das Werkzeug tat
        // gar nichts.
        return SizedBox.expand(
          child: GestureDetector(
            // Damit auch ein Tipp im Letterbox-Rand beim Werkzeug
            // ankommt und nicht ins Leere faellt.
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) =>
                _handleMaskTap(details.localPosition, widgetSize),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Image.memory(
                    _previewBytes!,
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                  ),
                ),
                if (_pendingMaskOverlayPng != null)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Image.memory(
                      _pendingMaskOverlayPng!,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                    ),
                  ),
                if (_computingEmbedding)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white70),
                      const SizedBox(height: 12),
                      Text(
                        _ladeSegmentierungsmodell
                            ? AppTexte.of(context).entwModellLaedt
                            : AppTexte.of(context).entwBildWirdVorbereitet,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  )
                else if (_computingMask)
                  const Positioned(
                    bottom: 16,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Editor für Pinsel/Ellipse/Verlauf: zeichnet [_draftShape] live über
  /// einen [CustomPainter] in Widget-Koordinaten (schnell, keine erneute
  /// Rasterisierung bei jeder Zeigerbewegung) – die tatsächliche, präzise
  /// Rasterisierung auf Originalauflösung passiert erst einmalig bei
  /// "Fertig" (siehe [_commitShape]).
  Widget _buildShapeMaskEditor() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
        final assetWidth = widget.asset.widthPx;
        final assetHeight = widget.asset.heightPx;
        final displayRect =
            (assetWidth != null &&
                assetHeight != null &&
                assetWidth > 0 &&
                assetHeight > 0)
            ? _imageDisplayRect(
                widgetSize,
                assetWidth.toDouble(),
                assetHeight.toDouble(),
              )
            : Rect.fromLTWH(0, 0, widgetSize.width, widgetSize.height);
        // Siehe [_buildAiSelectMaskEditor]: ohne `SizedBox.expand` meldet
        // der `LayoutBuilder` eine andere Flaeche, als die Geste sie
        // trifft - und keine Form entsteht.
        return SizedBox.expand(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) => _handleShapePanStart(details, widgetSize),
            onPanUpdate: (details) =>
                _handleShapePanUpdate(details, widgetSize),
            // Die Farbauswahl entsteht durch Tippen, nicht durch Ziehen.
            onTapUp: (details) =>
                _handleFarbeAufnehmen(details.localPosition, widgetSize),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Image.memory(
                    _previewBytes!,
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ShapeDraftPainter(_draftShape, displayRect),
                    ),
                  ),
                ),
                if (_computingMask)
                  const Positioned(
                    bottom: 16,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMaskCreationPanel() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppTexte.of(context).entwMaskeErstellen,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // Umbrechende Chips statt einer Segmentleiste: Sechs Werkzeuge
          // nebeneinander passen nicht in ein 300 Punkte breites Bedienfeld,
          // dort bliebe von jeder Beschriftung ein Buchstabe übrig.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (typ, beschriftung, symbol, bedienbar) in [
                (
                  _MaskFormType.aiSelect,
                  AppTexte.of(context).entwFormKi,
                  Icons.auto_awesome_outlined,
                  widget.segmentation?.installiert ?? false,
                ),
                (
                  _MaskFormType.freehand,
                  AppTexte.of(context).entwFormPinsel,
                  Icons.brush_outlined,
                  true,
                ),
                (
                  _MaskFormType.ellipse,
                  AppTexte.of(context).entwFormEllipse,
                  Icons.circle_outlined,
                  true,
                ),
                (
                  _MaskFormType.rectangle,
                  AppTexte.of(context).entwFormRechteck,
                  Icons.crop_square,
                  true,
                ),
                (
                  _MaskFormType.gradient,
                  AppTexte.of(context).entwFormVerlauf,
                  Icons.gradient_outlined,
                  true,
                ),
                (
                  _MaskFormType.colorRange,
                  AppTexte.of(context).entwFormFarbe,
                  Icons.colorize_outlined,
                  true,
                ),
              ])
                // Ein grauer Knopf ohne Grund ist eine Sackgasse: Die
                // KI-Auswahl bleibt ohne Segmentierungsmodell stumm, und
                // wer das nicht weiss, haelt das Werkzeug fuer kaputt.
                Tooltip(
                  message: bedienbar
                      ? beschriftung
                      : AppTexte.of(context).entwFormKiFehlt,
                  child: ChoiceChip(
                    label: Text(
                      beschriftung,
                      style: const TextStyle(fontSize: 12),
                    ),
                    avatar: Icon(symbol, size: 15),
                    selected: _maskFormType == typ,
                    visualDensity: VisualDensity.compact,
                    onSelected: bedienbar
                        ? (_) => _switchMaskFormType(typ)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildMaskFormTypePanel()),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelMaskCreation,
                  child: Text(AppTexte.of(context).allgAbbrechen),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _canCommitShape ? _commitCurrentMask : null,
                  child: Text(AppTexte.of(context).allgFertig),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMaskFormTypePanel() => switch (_maskFormType) {
    _MaskFormType.aiSelect => _buildAiSelectPanel(),
    _MaskFormType.freehand => _buildFreehandPanel(),
    _MaskFormType.ellipse => _buildEllipsePanel(),
    _MaskFormType.rectangle => _buildRectanglePanel(),
    _MaskFormType.gradient => _buildGradientPanel(),
    _MaskFormType.colorRange => _buildColorRangePanel(),
  };

  Widget _buildAiSelectPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppTexte.of(context).entwKiHinweis,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text(AppTexte.of(context).entwPunktHinzufuegen),
              icon: const Icon(Icons.add),
            ),
            ButtonSegment(
              value: true,
              label: Text(AppTexte.of(context).entwPunktEntfernen),
              icon: const Icon(Icons.remove),
            ),
          ],
          selected: {_backgroundPointMode},
          onSelectionChanged: (s) =>
              setState(() => _backgroundPointMode = s.first),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _maskPoints.isEmpty ? null : _undoLastMaskPoint,
          icon: const Icon(Icons.undo, color: Colors.white70, size: 18),
          label: Text(
            AppTexte.of(context).entwLetztenPunktEntfernen,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Widget _buildFreehandPanel() {
    final shape = _draftShape;
    final strokeWidth = shape is FreehandShape ? shape.strokeWidth : 0.03;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppTexte.of(context).entwPinselHinweis,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _shapeSlider(
          AppTexte.of(context).entwStrichbreite,
          strokeWidth,
          0.01,
          0.15,
          (v) {
            setState(
              () => _draftShape = FreehandShape(
                points: shape is FreehandShape ? shape.points : const [],
                strokeWidth: v,
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: shape == null
              ? null
              : () => setState(() => _draftShape = null),
          icon: const Icon(Icons.undo, color: Colors.white70, size: 18),
          label: Text(
            AppTexte.of(context).entwNeuZeichnen,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Widget _buildRectanglePanel() {
    final shape = _draftShape;
    final rotationDeg = shape is RectangleShape
        ? shape.rotation * 180 / math.pi
        : 0.0;
    final feather = shape is RectangleShape ? shape.feather : 0.2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppTexte.of(context).entwRechteckHinweis,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _shapeSlider(
          AppTexte.of(context).entwRotation,
          rotationDeg,
          -180,
          180,
          (v) {
            if (shape is! RectangleShape) return;
            setState(
              () => _draftShape = RectangleShape(
                centerX: shape.centerX,
                centerY: shape.centerY,
                halfWidth: shape.halfWidth,
                halfHeight: shape.halfHeight,
                rotation: v * math.pi / 180,
                feather: shape.feather,
              ),
            );
          },
          enabled: shape is RectangleShape,
        ),
        _shapeSlider(AppTexte.of(context).entwWeichzeichnung, feather, 0, 1, (
          v,
        ) {
          if (shape is! RectangleShape) return;
          setState(
            () => _draftShape = RectangleShape(
              centerX: shape.centerX,
              centerY: shape.centerY,
              halfWidth: shape.halfWidth,
              halfHeight: shape.halfHeight,
              rotation: shape.rotation,
              feather: v,
            ),
          );
        }, enabled: shape is RectangleShape),
      ],
    );
  }

  Widget _buildColorRangePanel() {
    final shape = _draftShape;
    final gewaehlt = shape is ColorRangeShape ? shape : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppTexte.of(context).entwFarbauswahlHinweis,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (gewaehlt != null)
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Color.fromARGB(
                    255,
                    gewaehlt.red,
                    gewaehlt.green,
                    gewaehlt.blue,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: DunkleFlaeche.linie),
                ),
              ),
              const SizedBox(width: 10),
              // Die aufgenommene Farbe steht als "R 120, G 140, B 160"
              // da und passt in der 300 Punkte schmalen Bedienspalte
              // nicht immer neben das Farbfeld. Ohne [Expanded] lief die
              // Zeile ueber - zu sehen war das bisher nie, weil der
              // Farbwaehler ueberhaupt keine Farbe aufnahm.
              Expanded(
                child: Text(
                  AppTexte.of(context).entwFarbeAufgenommen(
                    gewaehlt.red,
                    gewaehlt.green,
                    gewaehlt.blue,
                  ),
                  style: const TextStyle(
                    color: DunkleFlaeche.zweitText,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        _shapeSlider(
          AppTexte.of(context).entwToleranz,
          gewaehlt?.tolerance ?? 0.25,
          0.01,
          1,
          (v) {
            if (gewaehlt == null) return;
            setState(
              () => _draftShape = ColorRangeShape(
                pointX: gewaehlt.pointX,
                pointY: gewaehlt.pointY,
                red: gewaehlt.red,
                green: gewaehlt.green,
                blue: gewaehlt.blue,
                tolerance: v,
                feather: gewaehlt.feather,
              ),
            );
          },
          enabled: gewaehlt != null,
        ),
        _shapeSlider(
          AppTexte.of(context).entwWeichzeichnung,
          gewaehlt?.feather ?? 0.3,
          0,
          1,
          (v) {
            if (gewaehlt == null) return;
            setState(
              () => _draftShape = ColorRangeShape(
                pointX: gewaehlt.pointX,
                pointY: gewaehlt.pointY,
                red: gewaehlt.red,
                green: gewaehlt.green,
                blue: gewaehlt.blue,
                tolerance: gewaehlt.tolerance,
                feather: v,
              ),
            );
          },
          enabled: gewaehlt != null,
        ),
      ],
    );
  }

  Widget _buildEllipsePanel() {
    final shape = _draftShape;
    final rotationDeg = shape is EllipseShape
        ? shape.rotation * 180 / math.pi
        : 0.0;
    final feather = shape is EllipseShape ? shape.feather : 0.3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppTexte.of(context).entwEllipseHinweis,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _shapeSlider(
          AppTexte.of(context).entwRotation,
          rotationDeg,
          -180,
          180,
          (v) {
            if (shape is! EllipseShape) return;
            setState(
              () => _draftShape = EllipseShape(
                centerX: shape.centerX,
                centerY: shape.centerY,
                radiusX: shape.radiusX,
                radiusY: shape.radiusY,
                rotation: v * math.pi / 180,
                feather: shape.feather,
              ),
            );
          },
          enabled: shape is EllipseShape,
        ),
        _shapeSlider(AppTexte.of(context).entwWeichzeichnung, feather, 0, 1, (
          v,
        ) {
          if (shape is! EllipseShape) return;
          setState(
            () => _draftShape = EllipseShape(
              centerX: shape.centerX,
              centerY: shape.centerY,
              radiusX: shape.radiusX,
              radiusY: shape.radiusY,
              rotation: shape.rotation,
              feather: v,
            ),
          );
        }, enabled: shape is EllipseShape),
      ],
    );
  }

  Widget _buildGradientPanel() {
    final shape = _draftShape;
    final feather = shape is GradientShape ? shape.feather : 0.3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppTexte.of(context).entwVerlaufHinweis,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _shapeSlider(AppTexte.of(context).entwWeichzeichnung, feather, 0, 1, (
          v,
        ) {
          if (shape is! GradientShape) return;
          setState(
            () => _draftShape = GradientShape(
              startX: shape.startX,
              startY: shape.startY,
              endX: shape.endX,
              endY: shape.endY,
              feather: v,
            ),
          );
        }, enabled: shape is GradientShape),
      ],
    );
  }

  /// Wie [_slider], aber ohne [_scheduleRerender] – die Vektorformen-Werte
  /// wirken erst nach "Fertig" ([_commitShape]) auf das Bild, ein
  /// zwischenzeitlicher nativer Re-Render bei jeder Regler-Bewegung wäre nur
  /// verschwendete Arbeit.
  Widget _shapeSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: enabled ? DunkleFlaeche.text : DunkleFlaeche.inaktiv,
                  fontSize: 13,
                ),
              ),
              Text(
                value.toStringAsFixed(min.abs() >= 100 ? 0 : 2),
                style: TextStyle(
                  color: enabled
                      ? DunkleFlaeche.zweitText
                      : DunkleFlaeche.linie,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustmentsPanel() {
    final editingMask = _selectedMaskId != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ganz oben: das Histogramm zeigt immer die gesamte Vorschau, also
          // das Ergebnis aller Anpassungen zusammen – auch beim Bearbeiten
          // einer einzelnen Maske.
          HistogramView(
            data: _histogram,
            waveform: _waveform,
            isStale: _histogramPending || _rendering,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(color: Colors.white24),
          const SizedBox(height: AppSpacing.sm),
          if (_masks.isNotEmpty) ...[
            Text(
              AppTexte.of(context).entwAnpassungFuer,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text(AppTexte.of(context).entwGanzesBild),
                  selected: !editingMask,
                  onSelected: (_) => _selectGlobalAdjustments(),
                ),
                for (final mask in _masks)
                  InputChip(
                    label: Text(mask.label),
                    selected: mask.id == _selectedMaskId,
                    onPressed: () => _selectMask(mask),
                    onDeleted: () => _deleteMask(mask),
                    deleteIcon: const Icon(Icons.close, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
          ],
          if (editingMask) ..._buildEditShapeButtonIfVector(),
          if (editingMask) ..._buildMaskSliders() else ..._buildGlobalSliders(),
        ],
      ),
    );
  }

  /// Zeigt "Form bearbeiten" nur für Masken, die als Vektorform angelegt
  /// wurden (`shapeDefinitionJson != null`) – SAM-Masken haben keine
  /// nachträglich editierbare Geometrie, nur ihre Regler-Werte.
  List<Widget> _buildEditShapeButtonIfVector() {
    DevelopMaskData? mask;
    for (final m in _masks) {
      if (m.id == _selectedMaskId) mask = m;
    }
    // Verteidigung: _selectedMaskId kann theoretisch veraltet sein, falls
    // sich _masks und die Auswahl je auseinander entwickeln (firstWhere()
    // ohne Treffer würde sonst abstürzen).
    if (mask == null || mask.shapeDefinitionJson == null) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: OutlinedButton.icon(
          onPressed: () => _startMaskCreation(editingMask: mask),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(AppTexte.of(context).entwFormBearbeiten),
        ),
      ),
    ];
  }

  /// Die Farbtabelle: auswählen, Stärke einstellen, entfernen.
  Widget _lutBedienfeld() {
    final t = AppTexte.of(context);
    final name = _lutPfad == null
        ? null
        : p.basenameWithoutExtension(_lutPfad!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name ?? t.entwLutKeine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: name == null
                      ? DunkleFlaeche.hinweis
                      : DunkleFlaeche.text,
                  fontSize: 13,
                ),
              ),
            ),
            if (name != null)
              IconButton(
                tooltip: t.entwLutEntfernen,
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: DunkleFlaeche.zweitText,
                ),
                onPressed: () {
                  setState(() {
                    _lut = null;
                    _lutPfad = null;
                  });
                  _scheduleRerender();
                },
              ),
            IconButton(
              tooltip: t.entwLutWaehlen,
              icon: const Icon(
                Icons.folder_open,
                size: 18,
                color: DunkleFlaeche.zweitText,
              ),
              onPressed: _lutWaehlen,
            ),
          ],
        ),
        if (name != null)
          _slider(
            t.entwLutStaerke,
            _lutStaerke,
            0,
            1,
            (v) => setState(() => _lutStaerke = v),
          ),
      ],
    );
  }

  List<Widget> _buildGlobalSliders() => [
    _slider(
      AppTexte.of(context).entwBelichtung,
      _exposure,
      -3,
      3,
      (v) => setState(() => _exposure = v),
    ),
    const Divider(color: Colors.white24),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        AppTexte.of(context).entwAutoWeissabgleich,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      value: _autoWhiteBalance,
      onChanged: (v) {
        setState(() => _autoWhiteBalance = v);
        _scheduleRerender();
      },
    ),
    _slider(
      AppTexte.of(context).entwTemperatur,
      _temperature,
      2000,
      12000,
      (v) => setState(() => _temperature = v),
      enabled: !_autoWhiteBalance,
      imShader: _EntwickelnBasis._shaderIstGenau,
    ),
    _slider(
      AppTexte.of(context).entwTint,
      _tint,
      -100,
      100,
      (v) => setState(() => _tint = v),
      enabled: !_autoWhiteBalance,
      imShader: _EntwickelnBasis._shaderIstGenau,
    ),
    const Divider(color: Colors.white24),
    _slider(
      AppTexte.of(context).entwKontrast,
      _contrast,
      -1,
      1,
      (v) => setState(() => _contrast = v),
    ),
    _slider(
      AppTexte.of(context).entwLichter,
      _highlights,
      -1,
      1,
      (v) => setState(() => _highlights = v),
    ),
    _slider(
      AppTexte.of(context).entwSchatten,
      _shadows,
      -1,
      1,
      (v) => setState(() => _shadows = v),
    ),
    // Die vier Nachbarpixel-Regler folgen im Desktop-Renderer nach dem
    // Shader. Während des Ziehens wird deshalb ein gedrosselter Render
    // angefordert; gespeichert wirken sie auf allen Desktop-Systemen.
    _slider(
      AppTexte.of(context).entwSchaerfe,
      _sharpness,
      0,
      1,
      (v) => setState(() => _sharpness = v),
      imShader: _EntwickelnBasis._shaderIstGenau,
    ),
    _slider(
      AppTexte.of(context).entwRauschunterdrueckung,
      _noiseReduction,
      0,
      1,
      (v) => setState(() => _noiseReduction = v),
      imShader: _EntwickelnBasis._shaderIstGenau,
    ),
    _slider(
      AppTexte.of(context).entwKlarheit,
      _clarity,
      -1,
      1,
      (v) => setState(() => _clarity = v),
      imShader: _EntwickelnBasis._shaderIstGenau,
    ),
    _slider(
      AppTexte.of(context).entwVignettierung,
      _vignette,
      -1,
      1,
      (v) => setState(() => _vignette = v),
      imShader: _EntwickelnBasis._shaderIstGenau,
    ),
    if (DevelopRender.ohneWirkung.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          AppTexte.of(context).entwNurMitCoreImage,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ),
    const Divider(color: Colors.white24),
    _lutBedienfeld(),
    const Divider(color: Colors.white24),
    ToneCurveEditor(
      curve: _toneCurve,
      histogram: _histogram,
      // Wie beim Regler-Ziehen: Während der Geste rechnet der Shader
      // live, nach dem Loslassen übernimmt der native Render.
      onChanged: (kurve) => setState(() {
        _toneCurve = kurve;
        _dragging = true;
      }),
      onChangeEnd: _scheduleRerender,
    ),
    const SizedBox(height: AppSpacing.md),
    const Divider(color: Colors.white24),
    ColorMixerPanel(
      mixer: _colorMixer,
      onChanged: (mischer) => setState(() {
        _colorMixer = mischer;
        _dragging = true;
      }),
      onChangeEnd: _scheduleRerender,
    ),
    const Divider(color: Colors.white24),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        AppTexte.of(context).entwObjektivkorrektur,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      subtitle: Text(
        _objektivkorrekturHinweis(AppTexte.of(context)),
        style: const TextStyle(color: DunkleFlaeche.hinweis, fontSize: 11),
      ),
      // Ein Schalter, der nachweislich nichts bewirkt, wird
      // ausgegraut statt still ins Leere zu greifen. Solange der
      // Stand noch geladen wird, bleibt er bedienbar – die Abfrage
      // dauert Millisekunden, aber ein kurz gesperrter Schalter wäre
      // irritierender als einer, der einmal zu viel reagiert.
      value: _lensCorrectionEnabled,
      onChanged: switch (_korrekturstand) {
        Objektivkorrekturstand.keinRaw ||
        Objektivkorrekturstand.nichtInDatenbank ||
        Objektivkorrekturstand.nichtLesbar => null,
        _ => (v) {
          setState(() => _lensCorrectionEnabled = v);
          _scheduleRerender();
        },
      },
    ),
  ];

  /// Der Satz unter dem Objektivkorrektur-Schalter, passend zu dem, was für
  /// diese Datei wirklich gilt.
  String _objektivkorrekturHinweis(AppTexte t) => switch (_korrekturstand) {
    Objektivkorrekturstand.keinRaw => t.entwObjektivkorrekturKeinRaw,
    Objektivkorrekturstand.verfuegbar => t.entwObjektivkorrekturVerfuegbar,
    Objektivkorrekturstand.nichtInDatenbank =>
      t.entwObjektivkorrekturUnbekanntesObjektiv,
    Objektivkorrekturstand.nichtLesbar => t.entwObjektivkorrekturNichtLesbar,
    Objektivkorrekturstand.unbekannt => t.entwObjektivkorrekturHinweis,
  };

  /// Die Regler einer Maske.
  ///
  /// Alle mit `imShader: false`: Sobald eine Maske im Spiel ist, zeigt
  /// der Bildschirm nie die Shader-Vorschau (siehe [_shaderMoeglich]) –
  /// dort waere „live" ein Wort ohne Deckung, und waehrend des Ziehens
  /// passierte gar nichts.
  List<Widget> _buildMaskSliders() => [
    Text(
      AppTexte.of(context).entwMaskenHinweis,
      style: const TextStyle(color: DunkleFlaeche.hinweis, fontSize: 11),
    ),
    const SizedBox(height: 8),
    _slider(
      AppTexte.of(context).entwBelichtung,
      _maskExposure,
      -3,
      3,
      (v) => setState(() => _maskExposure = v),
      imShader: false,
    ),
    const Divider(color: Colors.white24),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        AppTexte.of(context).entwAutoWeissabgleich,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      value: _maskAutoWhiteBalance,
      onChanged: (v) {
        setState(() => _maskAutoWhiteBalance = v);
        _scheduleRerender();
      },
    ),
    _slider(
      AppTexte.of(context).entwTemperatur,
      _maskTemperature,
      2000,
      12000,
      (v) => setState(() => _maskTemperature = v),
      enabled: !_maskAutoWhiteBalance,
      imShader: false,
    ),
    _slider(
      AppTexte.of(context).entwTint,
      _maskTint,
      -100,
      100,
      (v) => setState(() => _maskTint = v),
      enabled: !_maskAutoWhiteBalance,
      imShader: false,
    ),
    const Divider(color: Colors.white24),
    _slider(
      AppTexte.of(context).entwKontrast,
      _maskContrast,
      -1,
      1,
      (v) => setState(() => _maskContrast = v),
      imShader: false,
    ),
    _slider(
      AppTexte.of(context).entwLichter,
      _maskHighlights,
      -1,
      1,
      (v) => setState(() => _maskHighlights = v),
      imShader: false,
    ),
    _slider(
      AppTexte.of(context).entwSchatten,
      _maskShadows,
      -1,
      1,
      (v) => setState(() => _maskShadows = v),
      imShader: false,
    ),
    _slider(
      AppTexte.of(context).entwSchaerfe,
      _maskSharpness,
      0,
      1,
      (v) => setState(() => _maskSharpness = v),
      imShader: false,
    ),
    _slider(
      AppTexte.of(context).entwRauschunterdrueckung,
      _maskNoiseReduction,
      0,
      1,
      (v) => setState(() => _maskNoiseReduction = v),
      imShader: false,
    ),
  ];
}
