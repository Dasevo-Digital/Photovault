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
import '../widgets/histogram_view.dart';
import '../widgets/tone_curve_editor.dart';
import '../theme/app_theme.dart';
import '../services/meldungsdienst.dart';

/// Welche Art von Maske gerade erstellt/bearbeitet wird – KI-Auswahl (SAM-
/// Punkt-Prompts, siehe SegmentationService) oder eine der drei editierbaren
/// Vektorformen (siehe vector_mask_service.dart).
enum _MaskFormType { aiSelect, freehand, ellipse, rectangle, gradient, colorRange }

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

class _DevelopScreenState extends State<DevelopScreen> {
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
  double _temperature = 6500; // Nur Anzeigewert, solange _autoWhiteBalance = true.
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
        widget.paths.absolute(widget.asset.relativePath));
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
      final bytes = await widget.paths.absolute(displayRelativePath(widget.asset)).readAsBytes();
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
        melde.warnung(AppTexte.of(context).entwLutFehlt(p.basename(relativerPfad)));
      }
    }
  }

  /// Wählt eine `.cube`-Datei, kopiert sie in die Bibliothek und aktiviert
  /// sie.
  ///
  /// Kopiert statt verwiesen: Eine Entwicklung, die auf eine Datei im
  /// Download-Ordner zeigt, sähe nach dem nächsten Aufräumen anders aus,
  /// und ein Backup enthielte den Look nicht.
  Future<void> _lutWaehlen() async {
    final auswahl = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cube'],
      dialogTitle: AppTexte.of(context).entwLutWaehlen,
    );
    final quelle = auswahl?.files.single.path;
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
  Future<void> _requestPreview() async {
    final token = ++_requestToken;
    setState(() => _rendering = true);
    final sourceFile = widget.paths.absolute(widget.asset.relativePath);
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

  /// Ob gerade ein nativer Render laeuft, und ob danach gleich noch
  /// einer faellig ist.
  bool _liveRendert = false;
  bool _liveNochmal = false;

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
    final sourceFile = widget.paths.absolute(widget.asset.relativePath);
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
      return Image.memory(_previewBytes!, gaplessPlayback: true, fit: BoxFit.contain);
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
            zeilen.add(ListTile(
              leading: Icon(
                  i == _sitzung.length - 1 ? Icons.circle : Icons.history,
                  size: i == _sitzung.length - 1 ? 12 : 20,
                  color: Colors.white70),
              title: Text(was(vorher, schritt.stand),
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                i == _sitzung.length - 1
                    ? '${zeit(schritt.wann)} · ${t.entwVerlaufJetzt}'
                    : zeit(schritt.wann),
                style: const TextStyle(
                    color: DunkleFlaeche.hinweis, fontSize: 12),
              ),
              onTap: () => Navigator.pop(context, schritt.stand),
            ));
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
            zeilen.add(ListTile(
              leading: const Icon(Icons.history, color: Colors.white70),
              title: Text(was(vorher, _standAus(eintrag)),
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(zeit(eintrag.createdAt),
                  style: const TextStyle(
                      color: DunkleFlaeche.hinweis, fontSize: 12)),
              onTap: () => Navigator.pop(context, _standAus(eintrag)),
            ));
          }
        }

        if (zeilen.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(t.entwKeinVerlauf,
                style: const TextStyle(color: Colors.white70)),
          );
        }
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: ListView(shrinkWrap: true, children: zeilen),
          ),
        );
      },
    );
    if (gewaehlt != null) _ladeSchritt(gewaehlt);
  }

  Widget _verlaufKopf(String titel) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
        child: Text(titel,
            style: const TextStyle(
                color: DunkleFlaeche.hinweis,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
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
              child: Text(t.allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(context, feld.text.trim()),
              child: Text(t.allgSpeichern)),
                ],
              )),
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
    await widget.db.upsertDevelopPreset(DevelopPresetsCompanion.insert(
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
      toneCurveJson: Value(_toneCurve.istNeutral ? null : _toneCurve.encode()),
      colorMixerJson:
          Value(_colorMixer.istNeutral ? null : _colorMixer.encode()),
      erstelltAm: DateTime.now(),
    ));
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
    widget.onEinstellungenKopieren!(DevelopSettingsData(
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
    ));
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

    final developedRelativePath = widget.paths.developedRelativePath(widget.asset.id);
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
            adjustments.toneCurve.istNeutral ? null : adjustments.toneCurve.encode()),
        colorMixerJson: Value(
            adjustments.colorMixer.istNeutral ? null : adjustments.colorMixer.encode()),
        updatedAt: DateTime.now(),
      ),
      developedRelativePath: developedRelativePath,
    );

    // Nur die gerade ausgewählte Maske kann seit dem letzten Speichern
    // geänderte Regler-Werte im Speicher haben (siehe _currentMaskLayers) –
    // alle anderen sind bereits mit der DB konsistent.
    if (_selectedMaskId != null) {
      await widget.db.updateDevelopMaskAdjustments(
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
      );
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    await widget.db.resetDevelopSettings(widget.asset.id);
    final developedFile = widget.paths.absolute(widget.paths.developedRelativePath(widget.asset.id));
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
        content: SizedBox(
          width: 420,
          child: Text(t.restaurWasPassiert),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t.allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t.allgStarten)),
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

  // --- KI-Objektmasken ---------------------------------------------------

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

  void _selectGlobalAdjustments() => setState(() => _selectedMaskId = null);

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
      null => (widget.segmentation?.installiert ?? false) ? _MaskFormType.aiSelect : _MaskFormType.freehand,
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

  /// Der Rand, in dem das Vorschaubild im Maskeneditor sitzt. Muss mit
  /// dem `Padding` in [_buildShapeMaskEditor] und
  /// [_buildAiSelectMaskEditor] übereinstimmen – die Umrechnung von
  /// Zeiger- auf Bildkoordinaten rechnet mit genau diesem Wert.
  static const double _maskenrand = AppSpacing.lg;

  /// Der tatsächlich gerenderte Bildbereich innerhalb eines Widgets, das per
  /// `BoxFit.contain` skaliert/gelettert wird (Muster: BoxFit.contain-Formel).
  /// Gemeinsame Grundlage für [_widgetPointToImagePoint] (Pixel-Koordinaten,
  /// KI-Auswahl) und [_widgetPointToNormalizedImagePoint] ([0,1]-Koordinaten,
  /// Vektorformen).
  ///
  /// [widgetSize] ist die volle Fläche des Editors – der Rand, in dem das
  /// Bild darin sitzt ([_maskenrand]), wird hier abgezogen. Ohne das lag
  /// der berechnete Bildbereich um genau diesen Rand daneben, und jede
  /// Maskengeste traf ein paar Bildpunkte neben der Stelle, auf die
  /// gezeigt wurde.
  Rect _imageDisplayRect(Size widgetSize, double imageWidth, double imageHeight) {
    final flaeche = Rect.fromLTWH(0, 0, widgetSize.width, widgetSize.height)
        .deflate(_maskenrand);
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
        flaeche.left + offsetX, flaeche.top + offsetY, renderedWidth, renderedHeight);
  }

  /// Rechnet eine Tipp-Position innerhalb des Vorschau-Widgets in eine
  /// Pixel-Koordinate des dekodierten Bilds um. `null`, wenn der Tipp im
  /// Letterbox-Rand lag.
  Offset? _widgetPointToImagePoint(Offset local, Size widgetSize, int imageWidth, int imageHeight) {
    final rect = _imageDisplayRect(widgetSize, imageWidth.toDouble(), imageHeight.toDouble());
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
    if (imageWidth == null || imageHeight == null || imageWidth <= 0 || imageHeight <= 0) return null;
    final rect = _imageDisplayRect(widgetSize, imageWidth.toDouble(), imageHeight.toDouble());
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

  void _handleMaskTap(Offset local, Size widgetSize) {
    final decoded = _decodedForMasking;
    if (decoded == null || _computingMask) return;
    final imagePoint = _widgetPointToImagePoint(local, widgetSize, decoded.width, decoded.height);
    if (imagePoint == null) return;
    setState(() => _maskPoints.add((point: imagePoint, isBackground: _backgroundPointMode)));
    _runMaskPrediction();
  }

  /// Nimmt die Farbe unter dem Finger auf und legt daraus eine
  /// Farbauswahl-Form an.
  ///
  /// Gelesen wird aus der Vorschau, die ohnehin im Speicher liegt – das
  /// Original dafür zu dekodieren wäre für drei Zahlen zu teuer, und für
  /// eine Farbe ist die Vorschau genau genug.
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
    setState(() => _draftShape = ColorRangeShape(
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
        ));
  }

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
    if (segmentation == null || embedding == null || _maskPoints.isEmpty) return;
    setState(() => _computingMask = true);
    final foreground = [for (final p in _maskPoints) if (!p.isBackground) p.point];
    final background = [for (final p in _maskPoints) if (p.isBackground) p.point];
    if (foreground.isEmpty) {
      // SAM braucht mindestens einen Vordergrund-Punkt, um sinnvoll zu
      // starten – reine Hintergrund-Punkte allein ergeben keine Maske.
      setState(() => _computingMask = false);
      return;
    }
    final result = await segmentation.decodeMask(embedding, foregroundPoints: foreground, backgroundPoints: background);
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

    await widget.db.createDevelopMask(DevelopMasksCompanion.insert(
      assetId: widget.asset.id,
      maskRelativePath: relativePath,
      label: name,
      createdAt: DateTime.now(),
    ));
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
        widget.paths.absolute(widget.asset.relativePath));
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

    await widget.db.createDevelopMask(DevelopMasksCompanion.insert(
      assetId: widget.asset.id,
      maskRelativePath: relativePath,
      label: name,
      createdAt: DateTime.now(),
    ));
    final frisch = await widget.db.masksForAsset(widget.asset.id);
    if (!mounted) return;
    setState(() => _masks = frisch);
    _selectMask(_masks.last);
    _scheduleRerender();
  }

  // --- Vektor-Masken: Zieh-Gesten -----------------------------------------

  void _handleShapePanStart(DragStartDetails details, Size widgetSize) {
    final point = _widgetPointToNormalizedImagePoint(details.localPosition, widgetSize);
    if (point == null) return;
    switch (_maskFormType) {
      case _MaskFormType.freehand:
        setState(() => _draftShape = FreehandShape(
              points: [point],
              strokeWidth: (_draftShape as FreehandShape?)?.strokeWidth ?? 0.03,
            ));
      case _MaskFormType.ellipse:
      case _MaskFormType.rectangle:
        // Beide werden gleich aufgezogen: von Ecke zu Ecke.
        setState(() => _ellipseDragAnchor = point);
      case _MaskFormType.gradient:
        final feather = (_draftShape as GradientShape?)?.feather ?? 0.3;
        setState(() => _draftShape =
            GradientShape(startX: point.dx, startY: point.dy, endX: point.dx, endY: point.dy, feather: feather));
      case _MaskFormType.aiSelect:
      case _MaskFormType.colorRange:
        // Beide entstehen aus einem Tipp, nicht aus einer Zieh-Geste.
        break;
    }
  }

  void _handleShapePanUpdate(DragUpdateDetails details, Size widgetSize) {
    final point = _widgetPointToNormalizedImagePoint(details.localPosition, widgetSize);
    if (point == null) return;
    switch (_maskFormType) {
      case _MaskFormType.freehand:
        final current = _draftShape;
        if (current is! FreehandShape) return;
        setState(() =>
            _draftShape = FreehandShape(points: [...current.points, point], strokeWidth: current.strokeWidth));
      case _MaskFormType.ellipse:
        final anchor = _ellipseDragAnchor;
        if (anchor == null) return;
        final previous = _draftShape;
        final rotation = previous is EllipseShape ? previous.rotation : 0.0;
        final feather = previous is EllipseShape ? previous.feather : 0.3;
        setState(() => _draftShape = EllipseShape(
              centerX: (anchor.dx + point.dx) / 2,
              centerY: (anchor.dy + point.dy) / 2,
              radiusX: math.max(0.01, (point.dx - anchor.dx).abs() / 2),
              radiusY: math.max(0.01, (point.dy - anchor.dy).abs() / 2),
              rotation: rotation,
              feather: feather,
            ));
      case _MaskFormType.rectangle:
        final anchor = _ellipseDragAnchor;
        if (anchor == null) return;
        final previous = _draftShape;
        final rotation = previous is RectangleShape ? previous.rotation : 0.0;
        final feather = previous is RectangleShape ? previous.feather : 0.2;
        setState(() => _draftShape = RectangleShape(
              centerX: (anchor.dx + point.dx) / 2,
              centerY: (anchor.dy + point.dy) / 2,
              halfWidth: math.max(0.01, (point.dx - anchor.dx).abs() / 2),
              halfHeight: math.max(0.01, (point.dy - anchor.dy).abs() / 2),
              rotation: rotation,
              feather: feather,
            ));
      case _MaskFormType.gradient:
        final current = _draftShape;
        if (current is! GradientShape) return;
        setState(() => _draftShape = GradientShape(
              startX: current.startX,
              startY: current.startY,
              endX: point.dx,
              endY: point.dy,
              feather: current.feather,
            ));
      case _MaskFormType.aiSelect:
      case _MaskFormType.colorRange:
        break;
    }
  }

  bool get _canCommitShape => switch (_maskFormType) {
        _MaskFormType.aiSelect => _pendingMaskResult != null,
        _MaskFormType.freehand => _draftShape is FreehandShape,
        _MaskFormType.ellipse => _draftShape is EllipseShape,
        _MaskFormType.rectangle => _draftShape is RectangleShape,
        _MaskFormType.gradient => _draftShape is GradientShape,
        _MaskFormType.colorRange => _draftShape is ColorRangeShape,
      };

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
            .absolute(widget.asset.previewRelativePath ?? widget.asset.relativePath)
            .path
        : null;
    final pngBytes =
        await compute(rasterizeMaskShapeToPngBytes, (shape, width, height, quellPfad));
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
      await widget.paths.absolute(existing.maskRelativePath).writeAsBytes(pngBytes);
      await widget.db.updateDevelopMaskShape(editingId, shape.encode());
    } else {
      final relativePath = widget.paths.maskRelativePath(const Uuid().v4());
      final file = widget.paths.absolute(relativePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(pngBytes);
      await widget.db.createDevelopMask(DevelopMasksCompanion.insert(
        assetId: widget.asset.id,
        maskRelativePath: relativePath,
        label: name,
        createdAt: DateTime.now(),
        shapeDefinitionJson: Value(shape.encode()),
      ));
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
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: enabled
                            ? DunkleFlaeche.text
                            : DunkleFlaeche.inaktiv,
                        fontSize: 13)),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                value.toStringAsFixed(min.abs() >= 100 ? 0 : 2),
                style: TextStyle(color: enabled ? DunkleFlaeche.zweitText : DunkleFlaeche.linie, fontSize: 12),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            // Während des Ziehens rechnet der Shader live; nach dem
            // Loslassen übernimmt wieder der native Render.
            onChangeStart:
                (enabled && imShader) ? (_) => setState(() => _dragging = true) : null,
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
            onPressed: (_saving || widget.restoreQueue?.restoreHalter?.installiert != true) ? null : _enqueueRestore,
          ),
          IconButton(
            icon: const Icon(Icons.auto_fix_high_outlined),
            tooltip: AppTexte.of(context).entwMaskeHinzufuegen,
            onPressed: (_saving || _maskEditMode) ? null : () => _startMaskCreation(),
          ),
          IconButton(
            icon: const Icon(Icons.blur_on_outlined),
            tooltip: AppTexte.of(context).entwTiefenmaske,
            onPressed:
                (_saving || _maskEditMode) ? null : _tiefenmaskeAnlegen,
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
            child: Text(AppTexte.of(context).einstZuruecksetzen,
                style: const TextStyle(color: Colors.white70)),
          ),
          // Die Beschneidungswarnung gehoert neben das Bild, nicht in die
          // Reglerspalte: Sie beurteilt das Bild, sie stellt nichts ein.
          // Nur bei der Shader-Vorschau anbietbar - die Markierung entsteht
          // im Shader, ein fertig gerendertes JPEG traegt sie nicht.
          // Der Vorher/Nachher-Strich. Wie die Beschneidungswarnung ein
          // Blick auf das Bild, keine Einstellung daran - deshalb hier
          // neben ihr und nicht in der Reglerspalte.
          IconButton(
            icon: Icon(_trennstrich != null
                ? Icons.compare
                : Icons.compare_outlined),
            color: _trennstrich != null ? Colors.amber : Colors.white70,
            tooltip: AppTexte.of(context).entwTrennstrich,
            onPressed: _trennstrichUmschalten,
          ),
          IconButton(
            icon: Icon(_beschneidungZeigen
                ? Icons.report_problem
                : Icons.report_problem_outlined),
            color: _beschneidungZeigen ? Colors.amber : Colors.white70,
            // Nicht an _zeigeShaderVorschau haengen: das waere der
            // Knopf, der genau dann klickbar ist, wenn man ihn nicht
            // treffen kann. Mit Masken bleibt er aus - und sagt, warum.
            tooltip: _shaderMoeglich
                ? AppTexte.of(context).entwBeschneidungWarnung
                : AppTexte.of(context).entwBeschneidungMitMasken,
            onPressed: _shaderMoeglich
                ? () => setState(
                    () => _beschneidungZeigen = !_beschneidungZeigen)
                : null,
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
                                  padding: const EdgeInsets.all(AppSpacing.xxl),
                                  child: Text(_error!, style: const TextStyle(color: Colors.white70)),
                                )
                              : const CircularProgressIndicator())
                          : _maskEditMode
                              ? _buildMaskEditor()
                              : GestureDetector(
                                  onLongPressStart: (_) {
                                    _ensureOriginalPreviewLoaded();
                                    setState(() => _showingOriginal = true);
                                  },
                                  onLongPressEnd: (_) => setState(() => _showingOriginal = false),
                                  onLongPressCancel: () => setState(() => _showingOriginal = false),
                                  child: Stack(
                                    alignment: Alignment.bottomCenter,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(AppSpacing.lg),
                                        child: (_zeigeShaderVorschau && !_showingOriginal)
                                            ? DevelopShaderPreview(
                                                shader: _shader,
                                                image: _shaderBasis!,
                                                adjustments: _currentAdjustments(),
                                                beschneidungZeigen: _beschneidungZeigen,
                                              )
                                            : (_zeigeTrennstrich && !_showingOriginal)
                                                ? _buildTrennstrichVergleich()
                                                : Image.memory(
                                                    (_showingOriginal && _originalPreviewBytes != null)
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
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius: BorderRadius.circular(AppRadius.pill),
                                            ),
                                            child: Text(AppTexte.of(context).entwOriginal,
                                                style: const TextStyle(
                                                    color: Colors.white, fontSize: 12)),
                                          ),
                                        )
                                      else
                                        Positioned(
                                          bottom: 4,
                                          child: Text(
                                            AppTexte.of(context).entwVergleichen,
                                            style: const TextStyle(
                                                color: DunkleFlaeche.hinweis, fontSize: 11),
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
                                                horizontal: 10, vertical: AppSpacing.xs),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                                  BorderRadius.circular(AppRadius.pill),
                                            ),
                                            child: Text(
                                                AppTexte.of(context).entwTrennstrichWartet,
                                                style: const TextStyle(
                                                    color: Colors.white, fontSize: 12)),
                                          ),
                                        ),
                                      // Solange die Warnung an ist, zeigt
                                      // der Shader das Bild - und der
                                      // rechnet unter macOS NICHT dasselbe
                                      // wie Core Image. Vier Regler fehlen
                                      // darin. Wo der Shader ohnehin das
                                      // Ergebnis erzeugt (Linux, Windows),
                                      // gibt es nichts zu vermelden.
                                      if (_beschneidungZeigen &&
                                          !_dragging &&
                                          !_showingOriginal &&
                                          _shaderMoeglich &&
                                          !DevelopRender.istMassgeblich)
                                        Positioned(
                                          top: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: AppSpacing.xs),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                                  BorderRadius.circular(AppRadius.pill),
                                            ),
                                            child: Text(
                                                AppTexte.of(context)
                                                    .entwBeschneidungVorschauHinweis,
                                                style: const TextStyle(
                                                    color: Colors.white, fontSize: 12)),
                                          ),
                                        ),
                                      if (_rendering)
                                        const Padding(
                                          padding: EdgeInsets.only(bottom: AppSpacing.lg),
                                          child: SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                                          ),
                                        ),
                                    ],
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
          widget.asset.id, () => widget.db.watchRestoreJobs()),
      builder: (context, schnappschuss) {
        final auftrag = (schnappschuss.data ?? const <RestoreJobData>[])
            .where((j) =>
                j.assetId == widget.asset.id &&
                (j.status == 'queued' || j.status == 'running'))
            .firstOrNull;
        if (auftrag == null) return const SizedBox.shrink();
        final t = AppTexte.of(context);
        final prozent = fortschrittProzent(auftrag);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.xs, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(t.entwRestaurierungLaeuft,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
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
                    color: DunkleFlaeche.hinweis, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMaskEditor() =>
      _maskFormType == _MaskFormType.aiSelect ? _buildAiSelectMaskEditor() : _buildShapeMaskEditor();

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
            onTapUp: (details) => _handleMaskTap(details.localPosition, widgetSize),
            child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Image.memory(_previewBytes!, gaplessPlayback: true, fit: BoxFit.contain),
              ),
              if (_pendingMaskOverlayPng != null)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Image.memory(_pendingMaskOverlayPng!, gaplessPlayback: true, fit: BoxFit.contain),
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
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
        final displayRect = (assetWidth != null && assetHeight != null && assetWidth > 0 && assetHeight > 0)
            ? _imageDisplayRect(widgetSize, assetWidth.toDouble(), assetHeight.toDouble())
            : Rect.fromLTWH(0, 0, widgetSize.width, widgetSize.height);
        // Siehe [_buildAiSelectMaskEditor]: ohne `SizedBox.expand` meldet
        // der `LayoutBuilder` eine andere Flaeche, als die Geste sie
        // trifft - und keine Form entsteht.
        return SizedBox.expand(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) => _handleShapePanStart(details, widgetSize),
            onPanUpdate: (details) => _handleShapePanUpdate(details, widgetSize),
            // Die Farbauswahl entsteht durch Tippen, nicht durch Ziehen.
            onTapUp: (details) => _handleFarbeAufnehmen(details.localPosition, widgetSize),
            child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Image.memory(_previewBytes!, gaplessPlayback: true, fit: BoxFit.contain),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _ShapeDraftPainter(_draftShape, displayRect)),
                ),
              ),
              if (_computingMask)
                const Positioned(
                  bottom: 16,
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
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
          Text(AppTexte.of(context).entwMaskeErstellen,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
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
                  widget.segmentation?.installiert ?? false
                ),
                (
                  _MaskFormType.freehand,
                  AppTexte.of(context).entwFormPinsel,
                  Icons.brush_outlined,
                  true
                ),
                (
                  _MaskFormType.ellipse,
                  AppTexte.of(context).entwFormEllipse,
                  Icons.circle_outlined,
                  true
                ),
                (
                  _MaskFormType.rectangle,
                  AppTexte.of(context).entwFormRechteck,
                  Icons.crop_square,
                  true
                ),
                (
                  _MaskFormType.gradient,
                  AppTexte.of(context).entwFormVerlauf,
                  Icons.gradient_outlined,
                  true
                ),
                (
                  _MaskFormType.colorRange,
                  AppTexte.of(context).entwFormFarbe,
                  Icons.colorize_outlined,
                  true
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
                    label: Text(beschriftung, style: const TextStyle(fontSize: 12)),
                    avatar: Icon(symbol, size: 15),
                    selected: _maskFormType == typ,
                    visualDensity: VisualDensity.compact,
                    onSelected:
                        bedienbar ? (_) => _switchMaskFormType(typ) : null,
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
                    onPressed: _cancelMaskCreation, child: Text(AppTexte.of(context).allgAbbrechen)),
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
                icon: const Icon(Icons.add)),
            ButtonSegment(
                value: true,
                label: Text(AppTexte.of(context).entwPunktEntfernen),
                icon: const Icon(Icons.remove)),
          ],
          selected: {_backgroundPointMode},
          onSelectionChanged: (s) => setState(() => _backgroundPointMode = s.first),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _maskPoints.isEmpty ? null : _undoLastMaskPoint,
          icon: const Icon(Icons.undo, color: Colors.white70, size: 18),
          label: Text(AppTexte.of(context).entwLetztenPunktEntfernen,
              style: const TextStyle(color: Colors.white70)),
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
        _shapeSlider(AppTexte.of(context).entwStrichbreite, strokeWidth, 0.01, 0.15, (v) {
          setState(() => _draftShape =
              FreehandShape(points: shape is FreehandShape ? shape.points : const [], strokeWidth: v));
        }),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: shape == null ? null : () => setState(() => _draftShape = null),
          icon: const Icon(Icons.undo, color: Colors.white70, size: 18),
          label: Text(AppTexte.of(context).entwNeuZeichnen, style: const TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }

  Widget _buildRectanglePanel() {
    final shape = _draftShape;
    final rotationDeg = shape is RectangleShape ? shape.rotation * 180 / math.pi : 0.0;
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
        _shapeSlider(AppTexte.of(context).entwRotation, rotationDeg, -180, 180, (v) {
          if (shape is! RectangleShape) return;
          setState(() => _draftShape = RectangleShape(
                centerX: shape.centerX,
                centerY: shape.centerY,
                halfWidth: shape.halfWidth,
                halfHeight: shape.halfHeight,
                rotation: v * math.pi / 180,
                feather: shape.feather,
              ));
        }, enabled: shape is RectangleShape),
        _shapeSlider(AppTexte.of(context).entwWeichzeichnung, feather, 0, 1, (v) {
          if (shape is! RectangleShape) return;
          setState(() => _draftShape = RectangleShape(
                centerX: shape.centerX,
                centerY: shape.centerY,
                halfWidth: shape.halfWidth,
                halfHeight: shape.halfHeight,
                rotation: shape.rotation,
                feather: v,
              ));
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
                  color: Color.fromARGB(255, gewaehlt.red, gewaehlt.green, gewaehlt.blue),
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
                  AppTexte.of(context)
                      .entwFarbeAufgenommen(gewaehlt.red, gewaehlt.green, gewaehlt.blue),
                  style: const TextStyle(color: DunkleFlaeche.zweitText, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        _shapeSlider(AppTexte.of(context).entwToleranz, gewaehlt?.tolerance ?? 0.25, 0.01, 1,
            (v) {
          if (gewaehlt == null) return;
          setState(() => _draftShape = ColorRangeShape(
                pointX: gewaehlt.pointX,
                pointY: gewaehlt.pointY,
                red: gewaehlt.red,
                green: gewaehlt.green,
                blue: gewaehlt.blue,
                tolerance: v,
                feather: gewaehlt.feather,
              ));
        }, enabled: gewaehlt != null),
        _shapeSlider(AppTexte.of(context).entwWeichzeichnung, gewaehlt?.feather ?? 0.3, 0, 1,
            (v) {
          if (gewaehlt == null) return;
          setState(() => _draftShape = ColorRangeShape(
                pointX: gewaehlt.pointX,
                pointY: gewaehlt.pointY,
                red: gewaehlt.red,
                green: gewaehlt.green,
                blue: gewaehlt.blue,
                tolerance: gewaehlt.tolerance,
                feather: v,
              ));
        }, enabled: gewaehlt != null),
      ],
    );
  }

  Widget _buildEllipsePanel() {
    final shape = _draftShape;
    final rotationDeg = shape is EllipseShape ? shape.rotation * 180 / math.pi : 0.0;
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
        _shapeSlider(AppTexte.of(context).entwRotation, rotationDeg, -180, 180, (v) {
          if (shape is! EllipseShape) return;
          setState(() => _draftShape = EllipseShape(
                centerX: shape.centerX,
                centerY: shape.centerY,
                radiusX: shape.radiusX,
                radiusY: shape.radiusY,
                rotation: v * math.pi / 180,
                feather: shape.feather,
              ));
        }, enabled: shape is EllipseShape),
        _shapeSlider(AppTexte.of(context).entwWeichzeichnung, feather, 0, 1, (v) {
          if (shape is! EllipseShape) return;
          setState(() => _draftShape = EllipseShape(
                centerX: shape.centerX,
                centerY: shape.centerY,
                radiusX: shape.radiusX,
                radiusY: shape.radiusY,
                rotation: shape.rotation,
                feather: v,
              ));
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
        _shapeSlider(AppTexte.of(context).entwWeichzeichnung, feather, 0, 1, (v) {
          if (shape is! GradientShape) return;
          setState(() => _draftShape = GradientShape(
                startX: shape.startX,
                startY: shape.startY,
                endX: shape.endX,
                endY: shape.endY,
                feather: v,
              ));
        }, enabled: shape is GradientShape),
      ],
    );
  }

  /// Wie [_slider], aber ohne [_scheduleRerender] – die Vektorformen-Werte
  /// wirken erst nach "Fertig" ([_commitShape]) auf das Bild, ein
  /// zwischenzeitlicher nativer Re-Render bei jeder Regler-Bewegung wäre nur
  /// verschwendete Arbeit.
  Widget _shapeSlider(String label, double value, double min, double max, ValueChanged<double> onChanged,
      {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: enabled ? DunkleFlaeche.text : DunkleFlaeche.inaktiv, fontSize: 13)),
              Text(
                value.toStringAsFixed(min.abs() >= 100 ? 0 : 2),
                style: TextStyle(color: enabled ? DunkleFlaeche.zweitText : DunkleFlaeche.linie, fontSize: 12),
              ),
            ],
          ),
          Slider(value: value, min: min, max: max, onChanged: enabled ? onChanged : null),
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
              isStale: _histogramPending || _rendering),
          const SizedBox(height: AppSpacing.lg),
          const Divider(color: Colors.white24),
          const SizedBox(height: AppSpacing.sm),
          if (_masks.isNotEmpty) ...[
            Text(AppTexte.of(context).entwAnpassungFuer,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
    final name = _lutPfad == null ? null : p.basenameWithoutExtension(_lutPfad!);
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
                  color: name == null ? DunkleFlaeche.hinweis : DunkleFlaeche.text,
                  fontSize: 13,
                ),
              ),
            ),
            if (name != null)
              IconButton(
                tooltip: t.entwLutEntfernen,
                icon: const Icon(Icons.close, size: 18, color: DunkleFlaeche.zweitText),
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
              icon: const Icon(Icons.folder_open, size: 18, color: DunkleFlaeche.zweitText),
              onPressed: _lutWaehlen,
            ),
          ],
        ),
        if (name != null)
          _slider(t.entwLutStaerke, _lutStaerke, 0, 1,
              (v) => setState(() => _lutStaerke = v)),
      ],
    );
  }

  List<Widget> _buildGlobalSliders() => [
        _slider(AppTexte.of(context).entwBelichtung, _exposure, -3, 3, (v) => setState(() => _exposure = v)),
        const Divider(color: Colors.white24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(AppTexte.of(context).entwAutoWeissabgleich,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          value: _autoWhiteBalance,
          onChanged: (v) {
            setState(() => _autoWhiteBalance = v);
            _scheduleRerender();
          },
        ),
        _slider(AppTexte.of(context).entwTemperatur, _temperature, 2000, 12000,
            (v) => setState(() => _temperature = v),
            enabled: !_autoWhiteBalance, imShader: _shaderIstGenau),
        _slider(AppTexte.of(context).entwTint, _tint, -100, 100,
            (v) => setState(() => _tint = v),
            enabled: !_autoWhiteBalance, imShader: _shaderIstGenau),
        const Divider(color: Colors.white24),
        _slider(AppTexte.of(context).entwKontrast, _contrast, -1, 1, (v) => setState(() => _contrast = v)),
        _slider(AppTexte.of(context).entwLichter, _highlights, -1, 1, (v) => setState(() => _highlights = v)),
        _slider(AppTexte.of(context).entwSchatten, _shadows, -1, 1, (v) => setState(() => _shadows = v)),
        // Diese vier kennt nur Core Image. Wo der Shader das gespeicherte
        // Ergebnis erzeugt (siehe DevelopRender), tun sie nichts – dann
        // lassen sie sich auch nicht bedienen, statt sich bewegen zu lassen
        // und wirkungslos zu bleiben. Der Hinweis darunter sagt, warum.
        //
        // `imShader: false` heisst: waehrend des Ziehens wird nativ
        // gerechnet. Vorher wurde waehrenddessen gar nichts gerechnet –
        // der Regler bewegte sich, das Bild nicht.
        _slider(AppTexte.of(context).entwSchaerfe, _sharpness, 0, 1,
            (v) => setState(() => _sharpness = v),
            imShader: _shaderIstGenau,
            enabled: !DevelopRender.istMassgeblich),
        _slider(AppTexte.of(context).entwRauschunterdrueckung, _noiseReduction, 0, 1,
            (v) => setState(() => _noiseReduction = v),
            imShader: _shaderIstGenau,
            enabled: !DevelopRender.istMassgeblich),
        _slider(AppTexte.of(context).entwKlarheit, _clarity, -1, 1,
            (v) => setState(() => _clarity = v),
            imShader: _shaderIstGenau,
            enabled: !DevelopRender.istMassgeblich),
        _slider(AppTexte.of(context).entwVignettierung, _vignette, -1, 1,
            (v) => setState(() => _vignette = v),
            imShader: _shaderIstGenau,
            enabled: !DevelopRender.istMassgeblich),
        if (DevelopRender.istMassgeblich)
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
          title: Text(AppTexte.of(context).entwObjektivkorrektur,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
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
            Objektivkorrekturstand.nichtLesbar =>
              null,
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
        Objektivkorrekturstand.nichtLesbar =>
          t.entwObjektivkorrekturNichtLesbar,
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
        _slider(AppTexte.of(context).entwBelichtung, _maskExposure, -3, 3, (v) => setState(() => _maskExposure = v), imShader: false),
        const Divider(color: Colors.white24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(AppTexte.of(context).entwAutoWeissabgleich,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          value: _maskAutoWhiteBalance,
          onChanged: (v) {
            setState(() => _maskAutoWhiteBalance = v);
            _scheduleRerender();
          },
        ),
        _slider(AppTexte.of(context).entwTemperatur, _maskTemperature, 2000, 12000, (v) => setState(() => _maskTemperature = v),
            enabled: !_maskAutoWhiteBalance, imShader: false),
        _slider(AppTexte.of(context).entwTint, _maskTint, -100, 100, (v) => setState(() => _maskTint = v), enabled: !_maskAutoWhiteBalance, imShader: false),
        const Divider(color: Colors.white24),
        _slider(AppTexte.of(context).entwKontrast, _maskContrast, -1, 1, (v) => setState(() => _maskContrast = v), imShader: false),
        _slider(AppTexte.of(context).entwLichter, _maskHighlights, -1, 1,
            (v) => setState(() => _maskHighlights = v), imShader: false),
        _slider(AppTexte.of(context).entwSchatten, _maskShadows, -1, 1, (v) => setState(() => _maskShadows = v), imShader: false),
        _slider(AppTexte.of(context).entwSchaerfe, _maskSharpness, 0, 1, (v) => setState(() => _maskSharpness = v), imShader: false),
        _slider(AppTexte.of(context).entwRauschunterdrueckung, _maskNoiseReduction, 0, 1, (v) => setState(() => _maskNoiseReduction = v), imShader: false),
      ];
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

  Offset _toWidget(double nx, double ny) =>
      Offset(displayRect.left + nx * displayRect.width, displayRect.top + ny * displayRect.height);

  @override
  void paint(Canvas canvas, Size size) {
    final s = shape;
    if (s == null) return;
    const fillColor = Color(0x8C2196F3); // Muster: maskToPreviewOverlay (33,150,243, alpha 140).
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
        final strokeWidthPx = s.strokeWidth * math.max(displayRect.width, displayRect.height);
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
        final rect = Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
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
            punkt, 7, Paint()..color = Color.fromARGB(255, s.red, s.green, s.blue));
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
