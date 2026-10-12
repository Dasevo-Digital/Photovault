import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../widgets/namens_dialog.dart' show MitTextsteuerung;
import '../services/asset_display_path.dart';
import '../services/bilddekodierung.dart';
import '../services/cube_lut.dart';
import '../services/develop_color.dart';
import '../services/develop_render.dart';
import '../services/entwicklungsverlauf.dart';
import '../services/histogram.dart';
import '../services/modell_halter.dart';
import '../services/native_image_converter.dart';
import '../services/restore_queue_service.dart';
import '../services/segmentation_service.dart';
import '../services/storage_paths.dart';
import '../services/vector_mask_service.dart';
import 'restore_queue_screen.dart' show restaurLaufText;
import '../state/library_state.dart' show decodeImageBytes;
import '../theme/app_spacing.dart';
import '../widgets/stromhalter.dart';
import '../utils/debouncer.dart';
import '../widgets/color_mixer_panel.dart';
import '../widgets/develop_preview.dart';
import '../widgets/lupe.dart';
import '../widgets/histogram_view.dart';
import '../widgets/tone_curve_editor.dart';
import '../theme/app_theme.dart';
import '../services/meldungsdienst.dart';

part 'entwickeln/vorschau.dart';
part 'entwickeln/verlauf_und_vorgaben.dart';
part 'entwickeln/masken.dart';
part 'entwickeln/bedienfelder.dart';

/// Welche Art von Maske gerade erstellt/bearbeitet wird – KI-Auswahl (SAM-
/// Punkt-Prompts, siehe SegmentationService) oder eine der drei editierbaren
/// Vektorformen (siehe vector_mask_service.dart).
enum _MaskFormType {
  aiSelect,
  freehand,
  ellipse,
  rectangle,
  gradient,
  colorRange,
}

/// Nicht-destruktive Bildentwicklung (Belichtung, Weißabgleich, Kontrast,
/// Schatten, Schärfe, Rauschunterdrückung, Objektivkorrektur) – anders als
/// [ImageEditorScreen] wird nie die Originaldatei verändert: die
/// Einstellungen landen in [DevelopSettings], das gerenderte Ergebnis als
/// separate Datei unter `Assets.developedRelativePath`. Arbeitet für
/// RAW-Dateien über CIRAWFilter-Eigenschaften (arbeitet auf den Rohdaten
/// vor dem Demosaicing) und für alle anderen Formate über eine
/// äquivalente CIFilter-Kette (siehe ImageConverter.swift `developImage`).
/// Nur für Fotos, nicht für gesperrte (verschlüsselte) Assets – wie
/// [ImageEditorScreen], um Wiederverschlüsselung nach dem Speichern nicht
/// mit abdecken zu müssen.
///
/// Masken (siehe DevelopMasks) gibt es in zwei Arten: KI-Auswahl per
/// SAM-Punkt-Prompt (nur verfügbar, wenn [segmentation] installiert ist –
/// `null`/`installiert == false`, solange das Segmentierungs-Modell nicht
/// heruntergeladen ist) und editierbare Vektorformen (Pinsel/Ellipse/
/// Verlauf, siehe vector_mask_service.dart), die kein Modell benötigen und
/// jederzeit verfügbar sind. Die eigentliche ONNX-Sitzung wird erst beim
/// Öffnen des KI-Auswahl-Werkzeugs geliehen ([_ensureEmbedding]) und beim
/// Verlassen des Bildschirms wieder zurückgegeben (siehe [dispose]).
///
/// [restoreQueue] schaltet die KI-Restaurierung frei (Hochskalieren +
/// Entrauschen, läuft im Hintergrund und dauert mehrere Minuten, siehe
/// RestoreQueueService) – `null`, solange das zugehörige Modell nicht
/// heruntergeladen ist.
class DevelopScreen extends StatefulWidget {
  final AssetData asset;
  final AppDatabase db;
  final StoragePaths paths;
  final ModellHalter<SegmentationService>? segmentation;
  final RestoreQueueService? restoreQueue;

  /// Legt die gespeicherten Einstellungen dieses Fotos in die
  /// Zwischenablage, um sie danach auf andere Fotos zu übertragen (siehe
  /// LibraryState.kopiereEntwicklungVon). Als Rückruf statt als
  /// LibraryState-Abhängigkeit, damit dieser Bildschirm weiterhin nur mit
  /// Datenbank und Pfaden auskommt.
  /// Legt den aktuellen Reglerstand in die Zwischenablage (siehe
  /// LibraryState.setzeKopierteEntwicklung).
  final void Function(DevelopSettingsData werte)? onEinstellungenKopieren;

  /// Liefert zuvor kopierte Einstellungen, oder `null`, wenn nichts in der
  /// Zwischenablage liegt. Hier werden sie in die Regler gesetzt statt
  /// stapelweise angewandt: In diesem Bildschirm geht es um genau ein
  /// Foto, und der Nutzer soll das Ergebnis sehen und noch nachjustieren
  /// können, bevor er speichert.
  final DevelopSettingsData? Function()? kopierteEinstellungen;

  const DevelopScreen({
    super.key,
    required this.asset,
    required this.db,
    required this.paths,
    this.segmentation,
    this.onEinstellungenKopieren,
    this.kopierteEinstellungen,
    this.restoreQueue,
  });

  @override
  State<DevelopScreen> createState() => _DevelopScreenState();
}

/// Der Zustand des Entwickeln-Bildschirms – alle Felder an einer Stelle.
///
/// **Aufbau (#41).** Die Klasse war mit 3.500 Zeilen eine einzige
/// State-Klasse. Ihre Abläufe stehen jetzt nach Themen in Mixins unter
/// entwickeln/ (Vorschau, Verlauf und Vorgaben, Masken, Bedienfelder), die
/// alle auf dieser Basis aufsetzen; [_DevelopScreenState] fügt sie
/// zusammen. Es bleibt ein einziges State-Objekt mit einem setState –
/// verteilt ist nur der Quelltext, nicht der Zustand. Abschnitts-Widgets mit
/// eigenem Zustand hätten das Verhalten geändert: Vorschau, Gesten und
/// Regler hängen hier eng aneinander.
abstract class _EntwickelnBasis extends State<DevelopScreen> {
  final _debouncer = Debouncer(const Duration(milliseconds: 250));
  int _requestToken = 0;

  bool _loading = true;
  bool _rendering = false;
  bool _saving = false;
  String? _error;
  Uint8List? _previewBytes;

  /// Für den Vorher/Nachher-Vergleich (Gedrückt-Halten) – einmalig beim
  /// ersten Halten mit neutralen Reglerwerten gerendert und danach gecacht,
  /// damit wiederholtes Halten keine erneute native Konvertierung auslöst.
  Uint8List? _originalPreviewBytes;
  bool _loadingOriginalPreview = false;
  bool _showingOriginal = false;

  /// Position des Vorher/Nachher-Trennstrichs, 0…1 auf dem dargestellten
  /// Bild. `null` heisst „aus".
  ///
  /// Bewusst nicht gespeichert – ein Vergleich ist eine Handlung, kein
  /// Zustand des Fotos. Dasselbe Argument wie bei
  /// [_beschneidungZeigen].
  double? _trennstrich;

  /// Seitenverhältnis der aktuellen Vorschau, aus [BildAuswertung]. Ohne
  /// das sässe der Trennstrich auf dem Widget statt auf dem Bild – bei
  /// `BoxFit.contain` zwei verschiedene Rechtecke.
  double? _vorschauSeitenverhaeltnis;

  /// Ob beschnittene Stellen im Bild markiert werden. Bewusst NICHT
  /// gespeichert: Das ist ein Blick beim Arbeiten, keine Eigenschaft des
  /// Fotos - und beim naechsten Oeffnen will man das Bild sehen, nicht die
  /// Warnfarben.
  bool _beschneidungZeigen = false;

  /// Ob die Lupe über der Vorschau liegt. Wie die Beschneidungswarnung ein
  /// Blick beim Arbeiten, nicht gespeichert.
  bool _lupe = false;

  // --- Live-Vorschau per GPU-Shader ------------------------------------
  // Während des Regler-Ziehens rechnet der Shader sofort auf der
  // neutralen Basis; nach dem Loslassen ersetzt der native Render das Bild
  // und ist maßgeblich (siehe shaders/develop_adjustments.frag).
  ui.FragmentShader? _shader;
  ui.Image? _shaderBasis;
  bool _dragging = false;

  /// Der Strom der Restaurierungs-Auftraege, festgehalten ueber Neubauten
  /// hinweg. Der Entwickeln-Bildschirm baut bei jedem Reglerzug neu auf;
  /// ohne den Halter faenge die Abfrage jedes Mal von vorn an (siehe
  /// [Stromhalter]).
  final _restaurierungen = Stromhalter<List<RestoreJobData>>();

  /// Der Verlauf **dieser Sitzung** – jeder Stand, der sich gesetzt hat.
  ///
  /// Bis hierher entstand ein Eintrag erst beim Speichern. Wer eine halbe
  /// Stunde probierte und dabei zweimal einen Stand hatte, den er lieber
  /// behalten hätte, kam nicht mehr zurück.
  List<Verlaufsschritt> _sitzung = const [];

  /// Ob der Ausgangsstand schon in der Reihe steht. Er ist der einzige
  /// Weg ganz zurück und muss deshalb der erste Schritt sein – aber erst,
  /// wenn er wirklich geladen ist (siehe [_load]).
  bool _sitzungBegonnen = false;

  /// Ob der Shader die Vorschau überhaupt zeichnen KANN: Basis und
  /// Programm geladen – und ohne Masken, da die neutrale Basis keine
  /// Maskenwirkung enthält und sonst alle Masken verschwinden und danach
  /// wieder auftauchen würden.
  /// Ob der Shader **genau** rechnet, was gespeichert wird.
  ///
  /// Wo er selbst der Renderweg ist (Linux, Windows), per Definition ja.
  /// Unter macOS ist Core Image massgeblich, und dort weicht er bei sechs
  /// Reglern ab (siehe [_slider]).
  static bool get _shaderIstGenau => DevelopRender.istMassgeblich;

  /// Tonwertverteilung der aktuell angezeigten Vorschau (siehe
  /// [_recomputeHistogram]). `null`, solange noch nichts berechnet wurde.
  HistogramData? _histogram;
  WaveformData? _waveform;

  /// Verwirft spät eintreffende Histogramm-Berechnungen, wenn inzwischen
  /// eine neuere Vorschau vorliegt – dasselbe Muster wie [_requestToken]
  /// für die Vorschau selbst.
  int _histogramToken = 0;
  bool _histogramPending = false;

  double _exposure = 0;
  bool _autoWhiteBalance = true;
  double _temperature =
      6500; // Nur Anzeigewert, solange _autoWhiteBalance = true.
  double _tint = 0;
  double _contrast = 0;
  double _shadows = 0;
  double _highlights = 0;
  double _sharpness = 0;
  double _noiseReduction = 0;
  double _clarity = 0;
  double _vignette = 0;

  /// Die importierte Farbtabelle: der Pfad in der Bibliothek, die bereits
  /// eingelesene Tabelle und wie stark sie wirkt.
  ///
  /// Die eingelesene Fassung wird mitgeführt, damit nicht bei jedem
  /// Reglerzug erneut eine Datei gelesen und geparst wird – bei einer
  /// 64er-Tabelle sind das eine Viertelmillion Zahlen.
  String? _lutPfad;
  CubeLut? _lut;
  double _lutStaerke = 1;
  bool _lensCorrectionEnabled = true;

  /// Was die Objektivkorrektur für DIESE Datei überhaupt leisten kann –
  /// nativ erfragt, nicht an der Dateiendung geraten. Bis die Antwort da
  /// ist, steht sie auf `unbekannt` und der Schalter verhält sich wie
  /// bisher.
  Objektivkorrekturstand _korrekturstand = Objektivkorrekturstand.unbekannt;

  /// Tonwertkurve und Farbmischer (siehe develop_color.dart). Anders als
  /// die Regler darüber tragen sie keinen einzelnen Zahlenwert, sondern
  /// eine ganze Punktfolge bzw. acht Bänder – und gelten nur fürs ganze
  /// Bild, nicht je Maske.
  ToneCurve _toneCurve = ToneCurve.neutral;
  ColorMixer _colorMixer = ColorMixer.neutral;

  // --- KI-Objektmasken -------------------------------------------------
  List<DevelopMaskData> _masks = [];

  /// `null` = die globalen Regler oben sind aktiv/sichtbar; sonst die
  /// Auto-Increment-`id` der gerade zum Bearbeiten ausgewählten Maske.
  int? _selectedMaskId;

  // Entwurfswerte der aktuell ausgewählten Maske (siehe _selectMask) –
  // dasselbe Muster wie die globalen Regler-Felder oben, nur ohne
  // Objektivkorrektur (die gilt nur für RAW-Rohdaten, nicht pro Maske).
  double _maskExposure = 0;
  bool _maskAutoWhiteBalance = true;
  double _maskTemperature = 6500;
  double _maskTint = 0;
  double _maskContrast = 0;
  double _maskShadows = 0;
  double _maskHighlights = 0;
  double _maskSharpness = 0;
  double _maskNoiseReduction = 0;

  bool _maskEditMode = false;
  bool _computingEmbedding = false;

  /// Beim ersten Mal wird das Segmentierungsmodell (101 MB) geladen –
  /// das dauert deutlich länger als das blosse Vorbereiten des Bildes
  /// und verdient eine eigene Erklärung.
  bool _ladeSegmentierungsmodell = false;
  bool _computingMask = false;
  SamImageEmbedding? _embedding;
  img.Image? _decodedForMasking;

  /// Ein laufender Dekodierlauf, damit er nur einmal stattfindet.
  Future<img.Image?>? _dekodierung;

  /// Die von [widget.segmentation] geliehene Sitzung (siehe
  /// [_ensureEmbedding]) – nicht-null bedeutet zugleich "muss in [dispose]
  /// zurückgegeben werden".
  SegmentationService? _segmentation;

  /// Punkte im Koordinatenraum des für die Maskierung dekodierten Bilds
  /// ([_decodedForMasking]), in Tipp-Reihenfolge – `isBackground: true` =
  /// "hier NICHT auswählen"-Punkt (SAM-Konvention Label 0).
  final List<({Offset point, bool isBackground})> _maskPoints = [];
  bool _backgroundPointMode = false;
  SamMaskResult? _pendingMaskResult;
  Uint8List? _pendingMaskOverlayPng;

  // --- Vektor-Masken (Pinsel/Ellipse/Verlauf) ---------------------------
  _MaskFormType _maskFormType = _MaskFormType.aiSelect;

  /// Nur gesetzt, während die Form einer bereits gespeicherten Vektor-Maske
  /// erneut bearbeitet wird (siehe "Form bearbeiten" in _buildAdjustmentsPanel)
  /// – steuert, ob [_commitShape] ein neues DevelopMasks-Row anlegt oder ein
  /// bestehendes aktualisiert. `null` beim Erstellen einer neuen Maske.
  int? _editingMaskId;

  /// Entwurf der gerade gezeichneten/bearbeiteten Vektorform, in Bild-
  /// normalisierten [0,1]-Koordinaten – erst bei "Fertig" ([_commitShape])
  /// tatsächlich rasterisiert und gespeichert.
  MaskShapeDefinition? _draftShape;

  /// Temporärer Anker für die Ellipse-Zieh-Geste (Gegenstück zu Start-/
  /// Endpunkt beim Verlauf, die direkt im GradientShape-Entwurf leben).
  Offset? _ellipseDragAnchor;

  /// Ob gerade ein nativer Render laeuft, und ob danach gleich noch
  /// einer faellig ist.
  bool _liveRendert = false;
  bool _liveNochmal = false;

  /// Der Rand, in dem das Vorschaubild im Maskeneditor sitzt. Muss mit
  /// dem `Padding` in [_buildShapeMaskEditor] und
  /// [_buildAiSelectMaskEditor] übereinstimmen – die Umrechnung von
  /// Zeiger- auf Bildkoordinaten rechnet mit genau diesem Wert.
  static const double _maskenrand = AppSpacing.lg;

  // Was die Mixins voneinander brauchen. Die Umsetzung steht im jeweiligen
  // Mixin unter entwickeln/; hier nur, damit ein Mixin das eines anderen
  // rufen kann (#41).
  Future<void> _ladeLut(String? relativerPfad);
  Future<void> _lutWaehlen();
  DevelopAdjustments _currentAdjustments();
  List<MaskAdjustmentLayer> _currentMaskLayers();
  Future<void> _requestPreview();
  Future<void> _liveNativ();
  void _scheduleRerender();
  void _selectMask(DevelopMaskData mask);
  void _selectGlobalAdjustments();
  Future<void> _deleteMask(DevelopMaskData mask);
  Future<void> _startMaskCreation({DevelopMaskData? editingMask});
  void _switchMaskFormType(_MaskFormType type);
  void _cancelMaskCreation();
  Rect _imageDisplayRect(
    Size widgetSize,
    double imageWidth,
    double imageHeight,
  );
  void _handleMaskTap(Offset local, Size widgetSize);
  Future<void> _handleFarbeAufnehmen(Offset local, Size widgetSize);
  void _undoLastMaskPoint();
  void _handleShapePanStart(DragStartDetails details, Size widgetSize);
  void _handleShapePanUpdate(DragUpdateDetails details, Size widgetSize);
  bool get _canCommitShape;
  Future<void> _commitCurrentMask();
}

/// Der Bildschirm selbst: Lebenszyklus und Aufbau. Felder stehen in
/// [_EntwickelnBasis], die Abläufe nach Themen in den Mixins unter entwickeln/.
class _DevelopScreenState extends _EntwickelnBasis
    with _Vorschau, _Verlauf, _Masken, _Bedienfelder {
  @override
  void initState() {
    super.initState();
    // _initShaderVorschau() bewusst NICHT hier: _init() lehnt gesperrte
    // Fotos ab, bevor irgendetwas die noch verschlüsselte Originaldatei
    // anfasst. Ein paralleler Aufruf würde genau daran vorbeilaufen. Der
    // Start erfolgt daher am Ende von _init(), wo Sperre und Vorschau
    // bereits geklärt sind.
    _init();
  }

  @override
  void dispose() {
    _debouncer.dispose();
    // GPU-Ressourcen gehören ausdrücklich freigegeben – der Garbage
    // Collector räumt sie nicht ab.
    _shader?.dispose();
    _shaderBasis?.dispose();
    if (_segmentation != null) widget.segmentation?.zurueckgeben();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(AppTexte.of(context).entwTitel),
        actions: [
          if (widget.asset.restoredRelativePath != null)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: AppTexte.of(context).entwRestaurierungEntfernen,
              onPressed: _saving ? null : _removeRestoredResult,
            ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: widget.restoreQueue?.restoreHalter?.installiert != true
                ? AppTexte.of(context).entwRestaurierungModellFehlt
                : AppTexte.of(context).entwRestaurierungAnwenden,
            onPressed:
                (_saving ||
                    widget.restoreQueue?.restoreHalter?.installiert != true)
                ? null
                : _enqueueRestore,
          ),
          IconButton(
            icon: const Icon(Icons.auto_fix_high_outlined),
            tooltip: AppTexte.of(context).entwMaskeHinzufuegen,
            onPressed: (_saving || _maskEditMode)
                ? null
                : () => _startMaskCreation(),
          ),
          IconButton(
            icon: const Icon(Icons.blur_on_outlined),
            tooltip: AppTexte.of(context).entwTiefenmaske,
            onPressed: (_saving || _maskEditMode) ? null : _tiefenmaskeAnlegen,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: AppTexte.of(context).entwVerlauf,
            onPressed: _saving ? null : _showHistory,
          ),
          if (widget.onEinstellungenKopieren != null)
            IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: AppTexte.of(context).entwEinstellungenKopieren,
              onPressed: _saving ? null : _kopiereEinstellungen,
            ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: AppTexte.of(context).entwAutomatisch,
            onPressed: _saving ? null : _automatisch,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: AppTexte.of(context).entwVorgabeSichern,
            onPressed: _saving ? null : _alsVorgabeSichern,
          ),
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: AppTexte.of(context).entwVorgabeAnwenden,
            onPressed: _saving ? null : _vorgabeAnwenden,
          ),
          if (widget.kopierteEinstellungen?.call() != null)
            IconButton(
              icon: const Icon(Icons.content_paste_go_outlined),
              tooltip: AppTexte.of(context).entwEinstellungenEinsetzen,
              onPressed: _saving ? null : _setzeKopierteEinstellungen,
            ),
          TextButton(
            onPressed: _saving ? null : _reset,
            child: Text(
              AppTexte.of(context).einstZuruecksetzen,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          // Die Beschneidungswarnung gehoert neben das Bild, nicht in die
          // Reglerspalte: Sie beurteilt das Bild, sie stellt nichts ein.
          // Nur bei der Shader-Vorschau anbietbar - die Markierung entsteht
          // im Shader, ein fertig gerendertes JPEG traegt sie nicht.
          // Der Vorher/Nachher-Strich. Wie die Beschneidungswarnung ein
          // Blick auf das Bild, keine Einstellung daran - deshalb hier
          // neben ihr und nicht in der Reglerspalte.
          IconButton(
            icon: Icon(
              _trennstrich != null ? Icons.compare : Icons.compare_outlined,
            ),
            color: _trennstrich != null ? Colors.amber : Colors.white70,
            tooltip: AppTexte.of(context).entwTrennstrich,
            onPressed: _trennstrichUmschalten,
          ),
          IconButton(
            icon: Icon(_lupe ? Icons.zoom_in : Icons.zoom_in_outlined),
            color: _lupe ? Colors.amber : Colors.white70,
            tooltip: AppTexte.of(context).entwLupe,
            onPressed: () => setState(() => _lupe = !_lupe),
          ),
          IconButton(
            icon: Icon(
              _beschneidungZeigen
                  ? Icons.report_problem
                  : Icons.report_problem_outlined,
            ),
            color: _beschneidungZeigen ? Colors.amber : Colors.white70,
            // Nicht an _zeigeShaderVorschau haengen: das waere der
            // Knopf, der genau dann klickbar ist, wenn man ihn nicht
            // treffen kann. Mit Masken bleibt er aus - und sagt, warum.
            tooltip: _shaderMoeglich
                ? AppTexte.of(context).entwBeschneidungWarnung
                : AppTexte.of(context).entwBeschneidungMitMasken,
            onPressed: _shaderMoeglich
                ? () =>
                      setState(() => _beschneidungZeigen = !_beschneidungZeigen)
                : null,
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: AppTexte.of(context).allgSpeichern,
              onPressed: _save,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Row(
                children: [
                  Expanded(
                    child: Center(
                      child: _previewBytes == null
                          ? (_error != null
                                ? Padding(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.xxl,
                                    ),
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  )
                                : const CircularProgressIndicator())
                          : _maskEditMode
                          ? _buildMaskEditor()
                          : Lupenbereich(
                              aktiv: _lupe,
                              child: GestureDetector(
                                onLongPressStart: (_) {
                                  _ensureOriginalPreviewLoaded();
                                  setState(() => _showingOriginal = true);
                                },
                                onLongPressEnd: (_) =>
                                    setState(() => _showingOriginal = false),
                                onLongPressCancel: () =>
                                    setState(() => _showingOriginal = false),
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(
                                        AppSpacing.lg,
                                      ),
                                      child:
                                          (_zeigeShaderVorschau &&
                                              !_showingOriginal)
                                          ? DevelopShaderPreview(
                                              shader: _shader,
                                              image: _shaderBasis!,
                                              adjustments:
                                                  _currentAdjustments(),
                                              beschneidungZeigen:
                                                  _beschneidungZeigen,
                                            )
                                          : (_zeigeTrennstrich &&
                                                !_showingOriginal)
                                          ? _buildTrennstrichVergleich()
                                          : Image.memory(
                                              (_showingOriginal &&
                                                      _originalPreviewBytes !=
                                                          null)
                                                  ? _originalPreviewBytes!
                                                  : _previewBytes!,
                                              gaplessPlayback: true,
                                              fit: BoxFit.contain,
                                            ),
                                    ),
                                    if (_showingOriginal)
                                      Positioned(
                                        top: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: AppSpacing.xs,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.pill,
                                            ),
                                          ),
                                          child: Text(
                                            AppTexte.of(context).entwOriginal,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      Positioned(
                                        bottom: 4,
                                        child: Text(
                                          AppTexte.of(context).entwVergleichen,
                                          style: const TextStyle(
                                            color: DunkleFlaeche.hinweis,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    // Der Strich ist an, aber das
                                    // unbearbeitete Bild wird noch
                                    // gerechnet. Ohne diesen Hinweis
                                    // sähe der Knopf wirkungslos aus -
                                    // und man suchte den Fehler dort.
                                    if (_trennstrich != null &&
                                        _originalPreviewBytes == null)
                                      Positioned(
                                        top: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: AppSpacing.xs,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.pill,
                                            ),
                                          ),
                                          child: Text(
                                            AppTexte.of(
                                              context,
                                            ).entwTrennstrichWartet,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (_rendering)
                                      const Padding(
                                        padding: EdgeInsets.only(
                                          bottom: AppSpacing.lg,
                                        ),
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
                            ),
                    ),
                  ),
                  // `Material` und nicht `Container(color:)`: Die
                  // Reglerspalte enthaelt Listenzeilen, und die malen
                  // ihren Grund und ihr Aufleuchten auf das naechste
                  // Material darueber. Unter einer eingefaerbten Flaeche
                  // sind beide unsichtbar - Flutter sagt das sogar
                  // ausdruecklich, sobald man hinsieht.
                  Material(
                    color: const Color(0xFF1A1A1A),
                    child: SizedBox(
                      width: 300,
                      child: Column(
                        children: [
                          _restaurierungsfortschritt(),
                          Expanded(
                            child: _maskEditMode
                                ? _buildMaskCreationPanel()
                                : _buildAdjustmentsPanel(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Zeichnet [shape] live über die Vorschau, in Widget-Koordinaten
/// (Muster: _CropMaskPainter in image_editor_screen.dart) – reine
/// Editier-Vorschau, NICHT die tatsächlich gespeicherte Maske (die entsteht
/// erst bei "Fertig" per [rasterizeMaskShape] auf voller Auflösung).
/// Wie ein Werkzeug in der Oberfläche heisst.
///
/// Hier und nicht in der Aufzählung: [Entwicklungswerkzeug] gehört zum
/// Dienst und kennt keine Sprache – dieselbe Trennung wie beim
/// Modellkatalog.
String werkzeugName(AppTexte t, Entwicklungswerkzeug w) => switch (w) {
  Entwicklungswerkzeug.belichtung => t.entwWerkzBelichtung,
  Entwicklungswerkzeug.weissabgleich => t.entwWerkzWeissabgleich,
  Entwicklungswerkzeug.temperatur => t.entwWerkzTemperatur,
  Entwicklungswerkzeug.tint => t.entwWerkzTint,
  Entwicklungswerkzeug.kontrast => t.entwWerkzKontrast,
  Entwicklungswerkzeug.lichter => t.entwWerkzLichter,
  Entwicklungswerkzeug.schatten => t.entwWerkzSchatten,
  Entwicklungswerkzeug.schaerfe => t.entwWerkzSchaerfe,
  Entwicklungswerkzeug.rauschunterdrueckung => t.entwWerkzRauschen,
  Entwicklungswerkzeug.klarheit => t.entwWerkzKlarheit,
  Entwicklungswerkzeug.vignettierung => t.entwWerkzVignettierung,
  Entwicklungswerkzeug.tonwertkurve => t.entwWerkzKurve,
  Entwicklungswerkzeug.farbmischer => t.entwWerkzFarbmischer,
  Entwicklungswerkzeug.farbtabelle => t.entwWerkzFarbtabelle,
  Entwicklungswerkzeug.objektivkorrektur => t.entwWerkzObjektiv,
};

class _ShapeDraftPainter extends CustomPainter {
  final MaskShapeDefinition? shape;
  final Rect displayRect;
  _ShapeDraftPainter(this.shape, this.displayRect);

  Offset _toWidget(double nx, double ny) => Offset(
    displayRect.left + nx * displayRect.width,
    displayRect.top + ny * displayRect.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final s = shape;
    if (s == null) return;
    const fillColor = Color(
      0x8C2196F3,
    ); // Muster: maskToPreviewOverlay (33,150,243, alpha 140).
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    switch (s) {
      case FreehandShape():
        if (s.points.isEmpty) return;
        final path = Path();
        final first = _toWidget(s.points.first.dx, s.points.first.dy);
        path.moveTo(first.dx, first.dy);
        for (final p in s.points.skip(1)) {
          final w = _toWidget(p.dx, p.dy);
          path.lineTo(w.dx, w.dy);
        }
        final strokeWidthPx =
            s.strokeWidth * math.max(displayRect.width, displayRect.height);
        canvas.drawPath(
          path,
          Paint()
            ..color = fillColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidthPx
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      case EllipseShape():
        final center = _toWidget(s.centerX, s.centerY);
        final rx = s.radiusX * displayRect.width;
        final ry = s.radiusY * displayRect.height;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(s.rotation);
        final rect = Rect.fromCenter(
          center: Offset.zero,
          width: rx * 2,
          height: ry * 2,
        );
        canvas.drawOval(rect, Paint()..color = fillColor);
        canvas.drawOval(rect, strokePaint);
        canvas.restore();
      case RectangleShape():
        final center = _toWidget(s.centerX, s.centerY);
        final w = s.halfWidth * 2 * displayRect.width;
        final h = s.halfHeight * 2 * displayRect.height;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(s.rotation);
        final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
        canvas.drawRect(rect, Paint()..color = fillColor);
        canvas.drawRect(rect, strokePaint);
        canvas.restore();
      case ColorRangeShape():
        // Nur die Marke, wo aufgenommen wurde: Welche Bildpunkte die
        // Auswahl trifft, hängt vom Foto ab und lässt sich hier nicht
        // ohne die Bilddaten zeichnen. Ein erfundener Umriss wäre
        // irreführend.
        final punkt = _toWidget(s.pointX, s.pointY);
        canvas.drawCircle(punkt, 9, strokePaint);
        canvas.drawCircle(
          punkt,
          7,
          Paint()..color = Color.fromARGB(255, s.red, s.green, s.blue),
        );
      case GradientShape():
        final start = _toWidget(s.startX, s.startY);
        final end = _toWidget(s.endX, s.endY);
        canvas.drawLine(start, end, strokePaint);
        canvas.drawCircle(start, 6, Paint()..color = Colors.white);
        canvas.drawCircle(end, 6, Paint()..color = Colors.white);
        final dir = end - start;
        if (dir.distance > 0) {
          final normal = Offset(-dir.dy, dir.dx) / dir.distance * 40;
          final band = Path()
            ..moveTo((start + normal).dx, (start + normal).dy)
            ..lineTo((start - normal).dx, (start - normal).dy)
            ..lineTo((end - normal).dx, (end - normal).dy)
            ..lineTo((end + normal).dx, (end + normal).dy)
            ..close();
          canvas.drawPath(band, Paint()..color = fillColor);
        }
    }
  }

  @override
  bool shouldRepaint(covariant _ShapeDraftPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.displayRect != displayRect;
}
