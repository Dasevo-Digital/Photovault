import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/asset_display_path.dart';
import '../services/asset_format.dart';
import '../services/bilddekodierung.dart';
import '../services/blur_detection.dart';
import '../services/export_service.dart';
import '../services/rasterauswahl.dart';
import '../services/textstellen.dart';
import '../services/storage_paths.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/bild_zoom_gesten.dart';
import '../widgets/asset_info_sheet.dart';
import '../widgets/gesichtsrahmen.dart';
import '../services/gesicht_von_hand.dart';
import '../widgets/textrahmen.dart';
import '../widgets/live_photo_view.dart';
import '../widgets/metadata_editor_dialog.dart';
import '../widgets/panorama_360_view.dart';
import '../widgets/person_picker_dialog.dart';
import '../widgets/video_playback.dart';
import '../widgets/selection_action_bar.dart' show confirmDialog, runBatchPasteDevelop;
import 'develop_screen.dart';
import 'face_review_screen.dart';
import 'person_detail_screen.dart';
import 'image_editor_screen.dart';
import 'similar_photos_screen.dart';
import 'video_trim_screen.dart';
import '../services/bearbeitung_zuruecknehmen.dart';
import '../services/meldungsdienst.dart';

enum _ContextMenuAction { showInTimeline, showSimilar, editMetadata, faceReview, entwicklungEinfuegen, originalHerstellen }

/// Obergrenze für die Dekodierauflösung (längste Kante) in der
/// Vollbildansicht. Ohne diese Grenze dekodiert `Image`/`PhotoView` ein Foto
/// in seiner vollen Originalauflösung (z.B. 48 MP ≈ 195 MB als RGBA-Bitmap)
/// direkt in Flutters Bild-Cache, dessen Standardgröße nur 100 MB beträgt –
/// schon ein einzelnes solches Foto sprengt den Cache, schnelles Durchwischen
/// führt dann zu ständigem Neu-Dekodieren statt Caching. 4096px liegt über
/// der längsten Kante praktisch aller Consumer-Kamera-/Smartphone-Fotos
/// (meist ≤ 4032-6000px), sodass normale Fotos unangetastet bleiben, während
/// Ausreißer (Panoramen, große Screenshots, 48-MP-Fotos) sinnvoll begrenzt
/// werden – bei aktiviertem Zoom in [PhotoView] bleibt trotzdem genug
/// Auflösung für deutliches Hineinzoomen übrig.
///
/// Die Zahl selbst steht seit der 17. Prüfrunde in
/// [maxDekodierKante]: Drei weitere Stellen zeigten dieselben Dateien
/// ohne Deckel, weil sie hier stand und sonst nirgends.

class AssetViewerScreen extends StatefulWidget {
  final List<AssetData> assets;
  final int initialIndex;
  final StoragePaths paths;
  final AppDatabase db;

  /// Nur nötig, wenn in [assets] gesperrte (verschlüsselte) Fotos vorkommen
  /// können (aktuell nur [LockedFolderScreen]) – wird für [onLock] und zum
  /// On-demand-Entschlüsseln beim Anzeigen gebraucht. Bei unverschlüsselten
  /// Listen kann der Parameter entfallen.
  final LibraryState? library;
  final Future<void> Function(AssetData asset)? onToggleFavorite;
  final Future<void> Function(AssetData asset)? onDelete;
  final Future<void> Function(AssetData asset)? onLock;

  /// Sichtungs-Modus (Culling): zeigt eine kompakte Hinweisleiste statt des
  /// Filmstreifens und schaltet ein Tastenkürzel zum Ablehnen (⌫ → Papierkorb
  /// + automatisch zum nächsten Foto) frei, ohne dabei den ganzen Screen zu
  /// schließen (anders als der reguläre Löschen-Knopf/[onDelete]). Für den
  /// schnellen Durchlauf frisch importierter oder noch unbewerteter Fotos.
  final bool cullingMode;

  const AssetViewerScreen({
    super.key,
    required this.assets,
    required this.initialIndex,
    required this.paths,
    required this.db,
    this.library,
    this.onToggleFavorite,
    this.onDelete,
    this.onLock,
    this.cullingMode = false,
  });

  @override
  State<AssetViewerScreen> createState() => _AssetViewerScreenState();
}

class _AssetViewerScreenState extends State<AssetViewerScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _currentIndex = widget.initialIndex;

  /// Für die Positionierung des Teilen-Dialog-Popovers (siehe _shareAsset)
  /// – auf macOS/iPad erscheint der native Teilen-Dialog als Popover, das
  /// sich an einem Referenz-Rechteck ausrichtet, statt einfach zentriert zu
  /// erscheinen.
  final GlobalKey _shareButtonKey = GlobalKey();

  /// Lokale, veränderliche Kopie von [AssetViewerScreen.assets] – nötig,
  /// damit Bearbeitungen in der Info-Ansicht (Datum/Ort/Beschreibung) und
  /// das Favorit-Umschalten sich sofort in dieser Ansicht widerspiegeln,
  /// statt nur in der DB und erst nach erneutem Öffnen sichtbar zu werden.
  final List<AssetData> _assets = [];

  /// Zeigt die Info-Ansicht als festes Seitenpanel statt als Bottom Sheet,
  /// das das Bild überlappen würde.
  bool _showInfo = false;

  /// Ob die erkannten Gesichter als Rahmen über dem Foto liegen.
  ///
  /// Gilt für die ganze Sitzung dieser Ansicht, also auch beim
  /// Weiterblättern – wer wissen will, wer auf den Fotos ist, will das
  /// meist für mehrere hintereinander und nicht für genau eines.
  bool _gesichterZeigen = false;

  /// Ob gerade ein Rahmen um ein übersehenes Gesicht aufgezogen wird.
  ///
  /// **Warum das hier steht und nicht nur in der Gesichts-Bearbeitung.**
  /// Ein Gesicht nachzutragen hiess bisher: Menü öffnen, in einen zweiten
  /// Bildschirm wechseln, dort dasselbe Foto noch einmal laden. Der Weg
  /// war so lang, dass man ihn nicht geht, während man Fotos ansieht – und
  /// genau dort fällt auf, dass jemand fehlt.
  ///
  /// Solange er an ist, sind die Rahmen zwingend sichtbar (man zieht nicht
  /// blind neben ein Gesicht, das schon einen hat) und PhotoView bekommt
  /// keine Gesten mehr: Ziehen verschiebt sonst das Bild, statt zu malen.
  bool _gesichtAufziehen = false;

  /// Ob die gelesenen Textstellen als Kästen über dem Foto liegen (siehe
  /// [Textrahmen]). Wie bei den Gesichtern eine Sitzungseinstellung: Man
  /// schaltet sie für ein Schild ein und gleich danach wieder aus.
  bool _textZeigen = false;

  /// Fokus-Peaking (nur im Sichtungs-Modus verfügbar, siehe _CullingHintBar):
  /// hebt lokal scharfe Kanten farbig hervor, ergänzt den reinen
  /// Schärfe-Score um eine ortsaufgelöste Rückmeldung.
  bool _focusPeakingEnabled = false;

  /// Schwellenwert für "Augen geschlossen" – siehe EyeStateService, der
  /// Score ist die Wahrscheinlichkeit "Augen offen".
  /// Ob KEIN Gesicht dieses Fotos scharf genug ist (siehe
  /// [gesichtUnscharfSchwelle]).
  ///
  /// Das schärfste zählt, nicht der Durchschnitt: Auf einem Gruppenbild ist
  /// hinten fast immer jemand weich, und das ist kein Grund, die Aufnahme
  /// wegzuwerfen. Erst wenn auch der beste Kopf unscharf ist, hat man ein
  /// Bild ohne brauchbares Gesicht.
  bool _currentGesichterUnscharf = false;

  /// Prüft, ob die Gesichter des aktuellen Fotos alle zu weich sind.
  ///
  /// Hiess bis Fassung 63 `_refreshClosedEyesFlag` und prüfte zusätzlich
  /// den Augenzustand – der steht jetzt im Serienvergleich, neben dem
  /// Gesicht, über das er etwas sagt.
  Future<void> _pruefeGesichtsschaerfe() async {
    if (!widget.cullingMode) return;
    final assetId = _assets[_currentIndex].id;
    final faces = await widget.db.facesForAsset(assetId);
    final gemessen = [
      for (final f in faces)
        if (!f.isIgnored && f.schaerfe != null) f.schaerfe!,
    ];
    final unscharf = gemessen.isNotEmpty &&
        gemessen.reduce((a, b) => a > b ? a : b) < gesichtUnscharfSchwelle;
    if (mounted && _assets[_currentIndex].id == assetId) {
      setState(() => _currentGesichterUnscharf = unscharf);
    }
  }

  /// Diaschau: rückt automatisch alle [_slideshowInterval] zum nächsten
  /// Foto vor, bis manuell gestoppt oder manuell navigiert wird (siehe
  /// _goToPrevious/_goToNext/_jumpToIndex – die stoppen die Diaschau, damit
  /// sie nicht mitten in einer bewussten Interaktion weiterspringt).
  static const _slideshowInterval = Duration(seconds: 4);
  Timer? _slideshowTimer;
  bool _slideshowActive = false;

  @override
  void initState() {
    super.initState();
    _assets.addAll(widget.assets);
    unawaited(_pruefeGesichtsschaerfe());
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    // Der PageController haengt als ChangeNotifier an der PageView; ohne
    // dies blieb er bei jedem geoeffneten Vollbild zurueck.
    _controller.dispose();
    super.dispose();
  }

  AssetData get _currentAsset => _assets[_currentIndex];

  void _replaceAsset(AssetData updated) {
    final index = _assets.indexWhere((a) => a.id == updated.id);
    if (index == -1) return;
    setState(() => _assets[index] = updated);
  }

  Future<void> _refreshCurrentAsset() async {
    final updated = await widget.db.assetById(_currentAsset.id);
    if (updated != null) _replaceAsset(updated);
  }

  void _toggleInfo() => setState(() => _showInfo = !_showInfo);

  bool get _hasPrevious => _currentIndex > 0;
  bool get _hasNext => _currentIndex < _assets.length - 1;

  void _goToPrevious() {
    if (_slideshowActive) _stopSlideshow();
    if (_hasPrevious) {
      _controller.previousPage(
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  void _goToNext() {
    if (_slideshowActive) _stopSlideshow();
    if (_hasNext) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  void _jumpToIndex(int index) {
    if (_slideshowActive) _stopSlideshow();
    _controller.animateToPage(index,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _toggleSlideshow() => _slideshowActive ? _stopSlideshow() : _startSlideshow();

  void _startSlideshow() {
    _slideshowTimer?.cancel();
    setState(() => _slideshowActive = true);
    _slideshowTimer = Timer.periodic(_slideshowInterval, (_) => _advanceSlideshow());
  }

  void _stopSlideshow() {
    _slideshowTimer?.cancel();
    _slideshowTimer = null;
    if (mounted) setState(() => _slideshowActive = false);
  }

  /// Vom Diaschau-Timer aufgerufen – bewusst NICHT über [_goToNext], da das
  /// die Diaschau als "manuelle Interaktion" sofort wieder stoppen würde.
  /// Am Ende der Liste angekommen: von vorn beginnen statt abzubrechen.
  void _advanceSlideshow() {
    if (_hasNext) {
      _controller.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      _controller.animateToPage(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goToPrevious();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _goToNext();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    final rating = bewertungFuerZiffer(event.logicalKey);
    if (rating != null) {
      _setRating(rating);
      return KeyEventResult.handled;
    }
    final farbe = farbmarkeFuerZiffer(event.logicalKey);
    if (farbe != null) {
      _setColorLabel(farbe);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace || event.logicalKey == LogicalKeyboardKey.delete) {
      if (widget.cullingMode) {
        _rejectCurrent();
      } else if (widget.onDelete != null) {
        _confirmAndDeleteCurrent();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF && widget.onToggleFavorite != null) {
      _toggleFavorite();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Verschiebt das aktuelle Foto in den Papierkorb und springt automatisch
  /// zum nächsten weiter, statt (wie der Lösch-Knopf) den ganzen Screen zu
  /// schließen – gemeinsame Grundlage für [_rejectCurrent] (Sichtungs-Modus,
  /// ungefragt) und [_confirmAndDeleteCurrent] (normales Tastenkürzel, mit
  /// Bestätigung). Ist die Liste danach leer, schließt sich der Screen.
  Future<void> _removeCurrentAndAdvance() async {
    final rejectedId = _currentAsset.id;
    final wasLastIndex = _currentIndex == _assets.length - 1;
    await widget.db.moveToTrash([rejectedId]);
    if (!mounted) return;
    setState(() => _assets.removeWhere((a) => a.id == rejectedId));
    if (_assets.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    if (wasLastIndex) {
      final newIndex = _assets.length - 1;
      setState(() => _currentIndex = newIndex);
      _controller.jumpToPage(newIndex);
    }
  }

  /// Nur im Sichtungs-Modus über das Tastenkürzel erreichbar (siehe
  /// [_handleKeyEvent]): bewusst OHNE Bestätigungsdialog. Der ganze Zweck des
  /// Sichtungs-Modus ist ein schneller Tastatur-Durchlauf; ein Dialog pro
  /// Ablehnung würde genau das verhindern (reversibel über den Papierkorb
  /// bleibt es trotzdem).
  Future<void> _rejectCurrent() => _removeCurrentAndAdvance();

  /// Tastenkürzel ⌫/Delete AUSSERHALB des Sichtungs-Modus (siehe
  /// [_handleKeyEvent]): anders als [_rejectCurrent] MIT Bestätigungsdialog,
  /// da eine versehentliche Löschung beim normalen Durchblättern weniger zu
  /// erwarten ist als im dedizierten Sichtungs-Modus. Springt danach (wie
  /// [_rejectCurrent]) zum nächsten Foto weiter statt den Screen zu
  /// schließen – anders als der Maus-Lösch-Knopf, der bewusst schließt (eine
  /// gezielte Einzelaktion statt eines schnellen Tastatur-Durchlaufs).
  Future<void> _confirmAndDeleteCurrent() async {
    final confirmed = await confirmDialog(context, AppTexte.of(context).loeschenTitel(1), AppTexte.of(context).loeschenHinweis(1));
    if (!confirmed) return;
    await _removeCurrentAndAdvance();
  }

  Future<void> _toggleFavorite() async {
    if (widget.onToggleFavorite == null) return;
    await widget.onToggleFavorite!(_currentAsset);
    await _refreshCurrentAsset();
  }

  Future<void> _confirmAndDelete() async {
    if (widget.onDelete == null) return;
    final confirmed = await confirmDialog(context, AppTexte.of(context).loeschenTitel(1), AppTexte.of(context).loeschenHinweis(1));
    if (!confirmed) return;
    await widget.onDelete!(_currentAsset);
  }

  void _showInTimeline() {
    final assetId = _currentAsset.id;
    final library = context.read<LibraryState>();
    library.requestTimelineHighlight(assetId);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showSimilarImages() {
    final library = context.read<LibraryState>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          SimilarPhotosScreen(library: library, sourceAsset: _currentAsset),
    ));
  }

  Future<void> _openMetadataEditor() async {
    final asset = _currentAsset;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => MetadataEditorDialog(asset: asset, db: widget.db),
    );
    if (saved == true) await _refreshCurrentAsset();
  }

  /// Nimmt jede Bearbeitung der gezeigten Aufnahme zurueck – siehe
  /// [originalWiederherstellen]. Mit Rueckfrage, wie in der Info-Ansicht.
  Future<void> _originalWiederherstellen() async {
    final t = AppTexte.of(context);
    if (!await confirmDialog(
        context, t.infoOriginalHerstellen, t.infoOriginalHerstellenFrage,
        bestaetigen: t.infoOriginalHerstellen)) {
      return;
    }
    await originalWiederherstellen(
        db: widget.db, paths: widget.paths, asset: _currentAsset);
    if (!mounted) return;
    melde.erfolg(t.infoOriginalHergestellt);
    await _refreshCurrentAsset();
  }

  Future<void> _showContextMenu(Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<_ContextMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        // Nur, wenn tatsächlich Einstellungen kopiert wurden. Der Weg über
        // die Mehrfachauswahl bleibt daneben bestehen – hier gesucht hatte
        // ihn der erste Bericht (Fehlerbericht).
        if (widget.library?.hatKopierteEntwicklung ?? false)
          PopupMenuItem(
            value: _ContextMenuAction.entwicklungEinfuegen,
            child: Row(children: [
              const Icon(Icons.auto_fix_high_outlined, size: 20),
              const SizedBox(width: 12),
              Text(AppTexte.of(context).viewerEntwicklungAnwenden),
            ]),
          ),
        PopupMenuItem(
          value: _ContextMenuAction.showInTimeline,
          child: Row(children: [
            const Icon(Icons.photo_library_outlined, size: 20),
            const SizedBox(width: 12),
            Text(AppTexte.of(context).viewerInTimelineZeigen),
          ]),
        ),
        PopupMenuItem(
          value: _ContextMenuAction.showSimilar,
          child: Row(children: [
            const Icon(Icons.image_search_outlined, size: 20),
            const SizedBox(width: 12),
            Text(AppTexte.of(context).viewerAehnlicheZeigen),
          ]),
        ),
        // Der Weg zurueck – nur bei einer Aufnahme, an der es etwas
        // zurueckzunehmen gibt. Denselben Knopf traegt die Info-Ansicht;
        // hier steht er, weil das Rechtsklick-Menue der Ort ist, an dem
        // man an einem Foto etwas TUT.
        if (bearbeitungsarten(_currentAsset).isNotEmpty)
          PopupMenuItem(
            value: _ContextMenuAction.originalHerstellen,
            child: Row(children: [
              const Icon(Icons.restore, size: 20),
              const SizedBox(width: 12),
              Text(AppTexte.of(context).infoOriginalHerstellen),
            ]),
          ),
        PopupMenuItem(
          value: _ContextMenuAction.editMetadata,
          child: Row(children: [
            const Icon(Icons.edit_note_outlined, size: 20),
            const SizedBox(width: 12),
            Text(AppTexte.of(context).viewerMetadatenBearbeiten),
          ]),
        ),
        // Nur für Fotos (nicht Videos), nicht gesperrt (FaceReviewScreen
        // liest Original/Vorschau direkt von der Platte, ohne die
        // Entschlüsselungs-/Wiederverschlüsselungs-Logik der Vollbildansicht
        // zu kennen – analog zum Ausschluss in ImageEditorScreen/
        // DevelopScreen) und nur, wenn eine LibraryState-Instanz vorliegt
        // (FaceReviewScreen braucht sie zwingend, siehe dessen Konstruktor).
        if (widget.library != null && _currentAsset.type == 'IMAGE' && !_currentAsset.isLocked)
          PopupMenuItem(
            value: _ContextMenuAction.faceReview,
            child: Row(children: [
              const Icon(Icons.face_retouching_natural_outlined, size: 20),
              const SizedBox(width: 12),
              Text(AppTexte.of(context).viewerGesichterBearbeiten),
            ]),
          ),
      ],
    );
    if (selected == null || !mounted) return;
    switch (selected) {
      case _ContextMenuAction.showInTimeline:
        _showInTimeline();
      case _ContextMenuAction.showSimilar:
        _showSimilarImages();
      case _ContextMenuAction.editMetadata:
        await _openMetadataEditor();
      case _ContextMenuAction.faceReview:
        await _openFaceReview();
      case _ContextMenuAction.entwicklungEinfuegen:
        await runBatchPasteDevelop(context, widget.library!, [_currentAsset.id]);
        await _refreshCurrentAsset();
      case _ContextMenuAction.originalHerstellen:
        await _originalWiederherstellen();
    }
  }

  /// Springt direkt aus der Vollbildansicht in die Gesichts-Bearbeitung für
  /// das aktuelle Foto (bisher nur über den Personen-Tab erreichbar) –
  /// reduziert die Hürde, ein übersehenes oder falsch zugeordnetes Gesicht
  /// direkt beim Ansehen zu korrigieren, statt erst zum Personen-Tab
  /// wechseln und das Foto dort wiederfinden zu müssen.
  Future<void> _openFaceReview() async {
    final library = widget.library;
    if (library == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FaceReviewScreen(
        library: library,
        assets: _assets,
        startIndex: _currentIndex,
      ),
    ));
    if (mounted) await _refreshCurrentAsset();
  }

  Future<void> _editAsset() async {
    final asset = _currentAsset;
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(MaterialPageRoute(
      builder: (_) =>
          ImageEditorScreen(
            asset: asset,
            db: widget.db,
            paths: widget.paths,
            modelsDir: widget.library?.modelsDir,
          ),
    ));
    if (saved == true) await _refreshCurrentAsset();
  }

  Future<void> _setRating(int rating) async {
    await widget.db.setRating(_currentAsset.id, rating);
    await _refreshCurrentAsset();
  }

  /// Farbmarke über die Tasten 6–9 (siehe [farbmarkeFuerZiffer]). Dieselbe
  /// Taste noch einmal nimmt die Marke wieder weg – wie ein zweiter Klick auf
  /// denselben Kreis in der Palette.
  Future<void> _setColorLabel(String farbe) async {
    final aktuell = _currentAsset.colorLabel;
    await widget.db.setColorLabel(_currentAsset.id, aktuell == farbe ? null : farbe);
    await _refreshCurrentAsset();
  }

  Future<void> _developAsset() async {
    final asset = _currentAsset;
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(MaterialPageRoute(
      builder: (_) => DevelopScreen(
        asset: asset,
        db: widget.db,
        paths: widget.paths,
        segmentation: widget.library?.segmentationHalter,
        restoreQueue: widget.library?.restoreQueue,
        onEinstellungenKopieren: widget.library?.setzeKopierteEntwicklung,
        kopierteEinstellungen: () => widget.library?.kopierteEntwicklung,
      ),
    ));
    if (saved == true) await _refreshCurrentAsset();
  }

  Future<void> _trimVideoAsset() async {
    final asset = _currentAsset;
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(MaterialPageRoute(
      builder: (_) =>
          VideoTrimScreen(asset: asset, db: widget.db, paths: widget.paths),
    ));
    if (saved == true) await _refreshCurrentAsset();
  }

  Future<void> _exportAsset() async {
    final asset = _currentAsset;
    final destination = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AppTexte.of(context).viewerExportZielordner,
    );
    if (destination == null || !mounted) return;

    final exporter = ExportService(widget.paths, library: widget.library);
    try {
      final exported = [await exporter.exportAsset(asset, destination)];
      if (asset.linkedAssetId != null) {
        final partner = await widget.db.assetById(asset.linkedAssetId!);
        if (partner != null) {
          exported.add(await exporter.exportAsset(partner, destination));
        }
      }
      if (mounted) {
        melde.erfolg(AppTexte.of(context).viewerExportiert(exported.join(', ')));
      }
    } catch (e) {
      if (mounted) {
        melde.fehler(AppTexte.of(context).viewerExportFehlgeschlagen('$e'));
      }
    }
  }

  /// Öffnet den nativen macOS-Teilen-Dialog (AirDrop/Mail/Nachrichten & Co.)
  /// – im Unterschied zu [_exportAsset] wird dabei keine Kopie in einem vom
  /// Nutzer gewählten Ordner abgelegt, sondern die Datei(en) direkt an eine
  /// andere App übergeben. `fileNameOverrides` sorgt dafür, dass im
  /// Teilen-Dialog der echte Originalname erscheint statt des internen
  /// Entschlüsselungs-Cache-Dateinamens (siehe LibraryState.decryptForViewing).
  Future<void> _shareAsset() async {
    final asset = _currentAsset;
    try {
      final exporter = ExportService(widget.paths, library: widget.library);
      final files = <XFile>[XFile((await exporter.resolveSourceFile(asset)).path)];
      final names = <String>[asset.originalFileName];
      if (asset.linkedAssetId != null) {
        final partner = await widget.db.assetById(asset.linkedAssetId!);
        if (partner != null) {
          files.add(XFile((await exporter.resolveSourceFile(partner)).path));
          names.add(partner.originalFileName);
        }
      }
      final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box != null ? (box.localToGlobal(Offset.zero) & box.size) : null;
      await SharePlus.instance.share(ShareParams(
        files: files,
        fileNameOverrides: names,
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      if (mounted) {
        melde.fehler(AppTexte.of(context).viewerTeilenFehlgeschlagen('$e'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = _currentAsset;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${asset.fileCreatedAt.day}.${asset.fileCreatedAt.month}.${asset.fileCreatedAt.year}',
              ),
              if (assetHasLocation(asset)) ...[
                const SizedBox(width: 8),
                const Icon(Icons.location_on, size: 16, color: Colors.white70),
              ],
              if (assetFormatLabel(asset).isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(AppRadius.xs)),
                  child: Text(
                    assetFormatLabel(asset),
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (_assets.length > 1)
              IconButton(
                icon: Icon(_slideshowActive ? Icons.pause_circle_outline : Icons.slideshow_outlined),
                tooltip: _slideshowActive ? AppTexte.of(context).viewerDiaschauStoppen : AppTexte.of(context).viewerDiaschauStarten,
                onPressed: _toggleSlideshow,
              ),
            IconButton(
              icon: Icon(_showInfo ? Icons.info : Icons.info_outline),
              tooltip: AppTexte.of(context).viewerInfo,
              onPressed: _toggleInfo,
            ),
            // Sichtbar in der Leiste und nicht im Rechtsklick-Menü: Wer
            // wissen will, wer auf einem Foto ist, sucht einen Knopf und
            // keine verborgene Geste. Dasselbe hatte schon die
            // Gesichts-Bearbeitung gelehrt.
            if (asset.type == 'IMAGE' && !asset.isLocked)
              IconButton(
                icon: Icon(_gesichterZeigen
                    ? Icons.face_retouching_natural
                    : Icons.face_retouching_natural_outlined),
                tooltip: _gesichterZeigen
                    ? AppTexte.of(context).viewerGesichterVerbergen
                    : AppTexte.of(context).viewerGesichterZeigen,
                onPressed: () => setState(() {
                  _gesichterZeigen = !_gesichterZeigen;
                  // Rahmen aus heisst auch: nicht mehr aufziehen. Sonst
                  // bliebe ein unsichtbarer Malmodus zurück, in dem sich
                  // das Bild nicht mehr verschieben lässt.
                  if (!_gesichterZeigen) _gesichtAufziehen = false;
                }),
              ),
            // Nur wenn die Rahmen an sind: Wer nachtragen will, muss erst
            // sehen, was schon da ist.
            if (asset.type == 'IMAGE' && !asset.isLocked && _gesichterZeigen)
              IconButton(
                icon: Icon(_gesichtAufziehen
                    ? Icons.person_add
                    : Icons.person_add_outlined),
                color: _gesichtAufziehen
                    ? Theme.of(context).colorScheme.primary
                    : null,
                tooltip: _gesichtAufziehen
                    ? AppTexte.of(context).viewerGesichtAufziehenEnde
                    : AppTexte.of(context).viewerGesichtAufziehen,
                onPressed: () =>
                    setState(() => _gesichtAufziehen = !_gesichtAufziehen),
              ),
            // Neben den Gesichtern und aus demselben Grund sichtbar statt im
            // Menü: 2406 der 7988 Aufnahmen dieser Bibliothek tragen
            // erkannten Text, der bis Schema 60 nirgends zu sehen war.
            if (asset.type == 'IMAGE' && !asset.isLocked)
              IconButton(
                icon: Icon(_textZeigen
                    ? Icons.text_fields
                    : Icons.text_fields_outlined),
                tooltip: _textZeigen
                    ? AppTexte.of(context).viewerTextVerbergen
                    : AppTexte.of(context).viewerTextZeigen,
                onPressed: () => setState(() => _textZeigen = !_textZeigen),
              ),
            IconButton(
              key: _shareButtonKey,
              icon: const Icon(Icons.ios_share),
              tooltip: AppTexte.of(context).viewerTeilen,
              onPressed: _shareAsset,
            ),
            IconButton(
              icon: const Icon(Icons.save_alt_outlined),
              tooltip: AppTexte.of(context).viewerExportieren,
              onPressed: _exportAsset,
            ),
            if (asset.type == 'IMAGE' && !asset.isLocked)
              IconButton(
                icon: const Icon(Icons.exposure),
                tooltip: AppTexte.of(context).viewerEntwickeln,
                onPressed: _developAsset,
              ),
            // Sichtbar in der Leiste statt nur im Rechtsklick-Menü: Dort
            // hatte ihn niemand gefunden, weil in einer Vollbildansicht
            // niemand einen Rechtsklick erwartet (Fehlerbericht).
            if (asset.type == 'IMAGE' &&
                !asset.isLocked &&
                (widget.library?.hatKopierteEntwicklung ?? false))
              IconButton(
                icon: const Icon(Icons.auto_fix_high_outlined),
                tooltip: AppTexte.of(context).viewerEntwicklungAnwendenLang,
                onPressed: () async {
                  await runBatchPasteDevelop(context, widget.library!, [asset.id]);
                  await _refreshCurrentAsset();
                },
              ),
            if (asset.type == 'IMAGE' && !asset.isLocked)
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: AppTexte.of(context).viewerBearbeiten,
                onPressed: _editAsset,
              ),
            if (asset.type == 'VIDEO' && !asset.isLocked)
              IconButton(
                icon: const Icon(Icons.content_cut),
                tooltip: AppTexte.of(context).viewerZuschneiden,
                onPressed: _trimVideoAsset,
              ),
            if (widget.onToggleFavorite != null)
              IconButton(
                icon: Icon(
                    asset.isFavorite ? Icons.favorite : Icons.favorite_border),
                tooltip: asset.isFavorite
                    ? AppTexte.of(context).viewerFavoritEntfernen
                    : AppTexte.of(context).viewerFavoritSetzen,
                onPressed: _toggleFavorite,
              ),
            if (widget.onLock != null)
              IconButton(
                icon: const Icon(Icons.lock_outline),
                tooltip: AppTexte.of(context).viewerInGesperrtenOrdner,
                onPressed: () async {
                  await widget.onLock!(asset);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            if (widget.onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: AppTexte.of(context).viewerInPapierkorb,
                onPressed: () async {
                  await _confirmAndDelete();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onSecondaryTapDown: (details) =>
                              _showContextMenu(details.globalPosition),
                          child: PageView.builder(
                            controller: _controller,
                            itemCount: _assets.length,
                            onPageChanged: (i) {
                              setState(() => _currentIndex = i);
                              unawaited(_pruefeGesichtsschaerfe());
                            },
                            itemBuilder: (context, index) {
                              final a = _assets[index];
                              return _AssetPage(
                                  asset: a,
                                  db: widget.db,
                                  paths: widget.paths,
                                  library: widget.library,
                                  isCurrent: index == _currentIndex,
                                  gesichterZeigen: _gesichterZeigen,
                                  gesichtAufziehen:
                                      _gesichtAufziehen && index == _currentIndex,
                                  beiGesichtAngelegt: () =>
                                      setState(() => _gesichtAufziehen = false),
                                  textZeigen: _textZeigen,
                                  focusPeakingEnabled: _focusPeakingEnabled);
                            },
                          ),
                        ),
                        if (_hasPrevious)
                          Positioned(
                            left: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                                child: _NavArrowButton(
                                    icon: Icons.chevron_left,
                                    tooltip: AppTexte.of(context).viewerVorherigesFoto,
                                    onPressed: _goToPrevious)),
                          ),
                        if (_hasNext)
                          Positioned(
                            right: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                                child: _NavArrowButton(
                                    icon: Icons.chevron_right,
                                    tooltip: AppTexte.of(context).viewerNaechstesFoto,
                                    onPressed: _goToNext)),
                          ),
                      ],
                    ),
                  ),
                  if (_showInfo) ...[
                    const VerticalDivider(width: 1, color: Colors.white24),
                    SizedBox(
                      width: 340,
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: AssetInfoSheet(
                          key: ValueKey(asset.id),
                          asset: asset,
                          db: widget.db,
                          paths: widget.paths,
                          onUpdated: _replaceAsset,
                          onClose: _toggleInfo,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.cullingMode) ...[
              const Divider(height: 1, color: Colors.white24),
              _CullingHintBar(
                current: _currentIndex + 1,
                total: _assets.length,
                focusPeakingEnabled: _focusPeakingEnabled,
                onToggleFocusPeaking: () => setState(() => _focusPeakingEnabled = !_focusPeakingEnabled),
                gesichterUnscharf: _currentGesichterUnscharf,
              ),
            ] else if (_assets.length > 1) ...[
              const Divider(height: 1, color: Colors.white24),
              _Filmstrip(
                assets: _assets,
                currentIndex: _currentIndex,
                paths: widget.paths,
                onSelect: _jumpToIndex,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kompakte Hinweisleiste im Sichtungs-Modus (Culling) – ersetzt den
/// Filmstreifen, da bei einem schnellen Tastatur-Durchlauf frisch
/// importierter Fotos die Miniaturansichten aller übrigen Fotos eher
/// ablenken als helfen; stattdessen ein knapper Fortschritt + die aktiven
/// Tastenkürzel.
class _CullingHintBar extends StatelessWidget {
  final int current;
  final int total;
  final bool focusPeakingEnabled;
  final VoidCallback onToggleFocusPeaking;

  /// Auch das schärfste Gesicht dieses Fotos liegt unter der Schwelle.
  final bool gesichterUnscharf;

  const _CullingHintBar({
    required this.current,
    required this.total,
    required this.focusPeakingEnabled,
    required this.onToggleFocusPeaking,
    required this.gesichterUnscharf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            AppTexte.of(context).sichtungHilfeleiste(current, total),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // **Die Warnung „geschlossene Augen" steht hier nicht
                  // mehr.** Sie behauptete etwas über ein Gesicht, das man
                  // an dieser Stelle nicht sieht – und sie hatte unrecht:
                  // An der echten Bibliothek meldete das Modell für 64,5 %
                  // der grossen Gesichter „geschlossen", und fünf zufällig
                  // herausgegriffene Gesichter mit dem Wert 0,00 hatten
                  // allesamt die Augen offen. In einem Ablauf, an dessen
                  // Ende gelöscht wird, ist eine unprüfbare Falschaussage
                  // schlimmer als keine Aussage.
                  //
                  // Der Wert steht jetzt im Serienvergleich, direkt neben
                  // dem Gesicht, über das er etwas sagt.
                  if (gesichterUnscharf) ...[
                    Tooltip(
                      message: AppTexte.of(context).viewerGesichtUnscharf,
                      child: const Icon(Icons.blur_on,
                          size: 18, color: Colors.orangeAccent),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: Icon(
                Icons.center_focus_strong,
                size: 20,
                color: focusPeakingEnabled ? Theme.of(context).colorScheme.primary : Colors.white70,
              ),
              tooltip: AppTexte.of(context).viewerFokusPeaking,
              onPressed: onToggleFocusPeaking,
            ),
          ),
        ],
      ),
    );
  }
}

/// Halbtransparenter Pfeil-Button links/rechts über dem Bild, für die
/// Maus-Navigation zwischen Fotos (zusätzlich zu den Pfeiltasten und dem
/// Filmstreifen unten).
class _NavArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  const _NavArrowButton({required this.icon, required this.onPressed, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        iconSize: 32,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

/// Filmstreifen-Vorschau unten in der Vollbildansicht ("Dia-Vorschau"): eine
/// horizontal scrollende Reihe kleiner Thumbnails aller Fotos dieser
/// Ansicht, scrollt beim Durchblättern automatisch mit, damit das aktuelle
/// Foto sichtbar bleibt. Antippen eines Thumbnails springt direkt dorthin.
class _Filmstrip extends StatefulWidget {
  final List<AssetData> assets;
  final int currentIndex;
  final StoragePaths paths;
  final ValueChanged<int> onSelect;

  const _Filmstrip({
    required this.assets,
    required this.currentIndex,
    required this.paths,
    required this.onSelect,
  });

  @override
  State<_Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<_Filmstrip> {
  static const _itemWidth = 56.0;
  static const _itemSpacing = 4.0;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToCurrent(animate: false));
  }

  @override
  void didUpdateWidget(covariant _Filmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _scrollToCurrent(animate: true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent({required bool animate}) {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    final target = widget.currentIndex * (_itemWidth + _itemSpacing) -
        viewport / 2 +
        _itemWidth / 2;
    final clamped =
        target.clamp(0.0, _scrollController.position.maxScrollExtent);
    if (animate) {
      _scrollController.animateTo(clamped,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      color: Colors.black,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        itemCount: widget.assets.length,
        separatorBuilder: (_, __) => const SizedBox(width: _itemSpacing),
        itemBuilder: (context, index) {
          final asset = widget.assets[index];
          final selected = index == widget.currentIndex;
          final thumbPath = asset.thumbnailRelativePath;
          return GestureDetector(
            onTap: () => widget.onSelect(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _itemWidth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: thumbPath != null
                  ? Builder(builder: (context) {
                      // Nur eine Kante begrenzen, sonst wird das Bild
                      // gestaucht - siehe [deckendeDekodiermasse].
                      final masse = deckendeDekodiermasse(
                        kachelBreite: _itemWidth,
                        kachelHoehe: _itemWidth,
                        bildBreite: asset.widthPx,
                        bildHoehe: asset.heightPx,
                        pixelverhaeltnis:
                            MediaQuery.of(context).devicePixelRatio,
                      );
                      return Image.file(
                        widget.paths.absolute(thumbPath),
                        fit: BoxFit.cover,
                        cacheWidth: masse.breite,
                        cacheHeight: masse.hoehe,
                        errorBuilder: (_, __, ___) =>
                            Container(color: Colors.grey.shade900),
                      );
                    })
                  : Container(color: Colors.grey.shade900),
            ),
          );
        },
      ),
    );
  }
}

/// Löst die anzuzeigende Datei eines Assets auf – bei gesperrten
/// (verschlüsselten) Assets über [LibraryState.decryptForViewing] in einen
/// temporären Klartext-Zwischenspeicher, sonst direkt den Originalpfad –
/// und rendert je nach Typ Foto, Video oder Live Photo.
class _AssetPage extends StatefulWidget {
  final AssetData asset;
  final AppDatabase db;
  final StoragePaths paths;
  final LibraryState? library;
  final bool isCurrent;

  /// Ob die erkannten Gesichter als Rahmen über dem Foto liegen.
  final bool gesichterZeigen;

  /// Ob ein Rahmen um ein übersehenes Gesicht aufgezogen werden kann.
  /// Immer nur auf der gerade sichtbaren Seite – ein Malmodus auf den
  /// Nachbarseiten des Blätterwerks wäre unsichtbar und würde dort still
  /// die Gesten fangen.
  final bool gesichtAufziehen;

  /// Wird gerufen, sobald ein Gesicht angelegt ist – der Modus endet dann.
  /// Nach jedem Rahmen von Hand, nicht dauerhaft: Es ist die Ausnahme,
  /// nicht die Arbeitsweise.
  final VoidCallback? beiGesichtAngelegt;

  /// Ob die gelesenen Textstellen als Kästen über dem Foto liegen.
  final bool textZeigen;
  final bool focusPeakingEnabled;
  const _AssetPage(
      {required this.asset,
      required this.db,
      required this.paths,
      required this.library,
      required this.isCurrent,
      this.gesichterZeigen = false,
      this.gesichtAufziehen = false,
      this.beiGesichtAngelegt,
      this.textZeigen = false,
      this.focusPeakingEnabled = false});

  @override
  State<_AssetPage> createState() => _AssetPageState();
}

class _AssetPageState extends State<_AssetPage> {
  /// Der Massstab der Vollbildansicht – gebraucht, damit [BildZoomGesten]
  /// ihn setzen kann (siehe dort: eine Magic Mouse kann nicht kneifen).
  final PhotoViewController _zoomsteuerung = PhotoViewController();

  /// Die beiden Ecken, während ein Rahmen aufgezogen wird – in Punkten
  /// der Fotofläche, nicht des Fensters.
  Offset? _zugAnfang;
  Offset? _zugJetzt;

  // Einmalig ermittelt statt inline in build(): PageView.builder ruft
  // itemBuilder bei jedem Rebuild der übergeordneten Ansicht (z.B. nach dem
  // Umschalten eines Favoriten) für alle aktuell aufgebauten Seiten erneut
  // auf – ein dort neu erzeugtes Future würde bei gesperrten Fotos jedes Mal
  // eine erneute Entschlüsselung anstoßen. Dateipfad/Sperrstatus ändern sich
  // nicht, solange dieses Asset in der Vollbildansicht angezeigt wird (beim
  // Sperren wird die Ansicht sofort verlassen, siehe onLock oben).
  late final Future<File> _fileFuture = _resolveFile();

  /// Fokus-Peaking-Overlay (siehe blur_detection.dart), nur berechnet
  /// während widget.focusPeakingEnabled && widget.isCurrent && Bildtyp
  /// IMAGE. `null` heißt "noch nicht fertig/nicht angefordert" – die
  /// Foto-Anzeige wartet NICHT darauf, das Overlay blendet sich nachträglich
  /// ein, sobald es vorliegt.
  Uint8List? _focusPeakingOverlay;
  Timer? _focusPeakingDebounce;

  /// Die erkannten Gesichter dieses Fotos samt den Namen dahinter – erst
  /// geladen, wenn jemand sie sehen will. Ein Foto ohne Rahmen soll
  /// nicht für jede Seite der Blätterliste eine Abfrage kosten.
  List<FaceData> _gesichter = const [];
  Map<String, String> _gesichtsnamen = const {};

  /// Die gelesenen Textstellen dieses Fotos. Anders als die Gesichter
  /// kostet das keine Abfrage – sie stehen in der Asset-Zeile selbst.
  late final List<Textstelle> _stellen = textstellenAusJson(widget.asset.ocrBoxen);

  /// Die Masse des angezeigten Bildes. Gebraucht, weil die Kästen als
  /// Anteile davon gespeichert sind – ohne sie liegt jeder Rahmen falsch.
  Size? _bildmasse;

  /// Für als 360° erkannte Fotos (siehe isEquirectangular360): zeigt per
  /// Default die Kugel-Ansicht, `true` schaltet auf die flache Vorschau um
  /// (falsch erkannt, oder der Nutzer will das Originalbild sehen).
  bool _showFlatPreview = false;

  /// Innerhalb der 360°-Ansicht: echte 3D-Kugel (Default) oder flaches
  /// Pan/Zoom über das equirechteckige Bild.
  Panorama360Mode _panoramaMode = Panorama360Mode.sphere;

  /// Legt die angetippte Zeile in die Zwischenablage und sagt, was drin ist.
  ///
  /// Die Rückmeldung nennt den Text selbst und nicht nur „kopiert": Bei
  /// dicht stehenden Zeilen ist die Frage, welche man getroffen hat, die
  /// einzige, die sich hier stellt.
  Future<void> _zeileKopieren(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    melde.erfolg(AppTexte.of(context).viewerZeileKopiert(text));
  }

  Future<File> _resolveFile() {
    final relativePath = displayRelativePath(widget.asset);
    if (widget.asset.isLocked && widget.library != null) {
      return widget.library!.decryptForViewing(relativePath);
    }
    return Future.value(widget.paths.absolute(relativePath));
  }

  @override
  void initState() {
    super.initState();
    _maybeScheduleFocusPeaking();
    if (widget.gesichterZeigen) unawaited(_gesichterLaden());
  }

  @override
  void didUpdateWidget(covariant _AssetPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ein anderes Foto in derselben Seite: Die alten Rahmen gehören zum
    // vorigen Bild und lägen sonst auf dem neuen.
    if (widget.asset.id != oldWidget.asset.id) {
      _gesichter = const [];
      _gesichtsnamen = const {};
      _bildmasse = null;
      if (widget.gesichterZeigen) unawaited(_gesichterLaden());
    } else if (widget.gesichterZeigen && !oldWidget.gesichterZeigen) {
      unawaited(_gesichterLaden());
    }
    if (widget.focusPeakingEnabled && widget.isCurrent) {
      if (!oldWidget.focusPeakingEnabled || !oldWidget.isCurrent) {
        _maybeScheduleFocusPeaking();
      }
    } else if (_focusPeakingOverlay != null || _focusPeakingDebounce != null) {
      _focusPeakingDebounce?.cancel();
      _focusPeakingDebounce = null;
      setState(() => _focusPeakingOverlay = null);
    }
  }

  @override
  void dispose() {
    _focusPeakingDebounce?.cancel();
    _zoomsteuerung.dispose();
    super.dispose();
  }

  /// Holt die Gesichter dieses Fotos und die Masse des Bildes.
  ///
  /// **Die Masse zuerst aus der Datenbank.** Dort stehen sie beim Import
  /// bereits, und sie zu lesen kostet nichts – dieselbe Reihenfolge wie
  /// in der Gesichts-Bearbeitung, wo sie sich bewährt hat. Fehlen sie
  /// (ältere Einträge, ungewöhnliche Formate), werden sie aus dem
  /// Bildanbieter geholt, der das Foto ohnehin anzeigt; ein zweites Mal
  /// dekodiert wird dabei nichts.
  ///
  /// Ohne Masse kein Rahmen: Der Anteil 0,3 ist für sich genommen kein
  /// Ort.
  Future<void> _gesichterLaden() async {
    final asset = widget.asset;
    if (asset.type != 'IMAGE' || asset.isLocked) return;
    final gesichter = await widget.db.facesForAsset(asset.id);
    if (!mounted) return;
    final personen = await widget.db.peopleForAsset(asset.id);
    if (!mounted || widget.asset.id != asset.id) return;
    final breite = asset.widthPx, hoehe = asset.heightPx;
    setState(() {
      _gesichter = gesichter;
      _gesichtsnamen = {for (final p in personen) p.id: p.name};
      if (breite != null && hoehe != null && breite > 0 && hoehe > 0) {
        _bildmasse = Size(breite.toDouble(), hoehe.toDouble());
      }
    });
    if (_bildmasse == null && gesichter.isNotEmpty) {
      final datei = await _fileFuture;
      if (!mounted || widget.asset.id != asset.id) return;
      final masse = await _masseVon(begrenztesBild(datei));
      if (!mounted || widget.asset.id != asset.id) return;
      setState(() => _bildmasse = masse);
    }
  }

  /// Die Punktmasse eines Bildanbieters, sobald er geladen ist.
  Future<Size?> _masseVon(ImageProvider anbieter) {
    final fertig = Completer<Size?>();
    final strom = anbieter.resolve(ImageConfiguration.empty);
    late final ImageStreamListener horcher;
    horcher = ImageStreamListener(
      (info, _) {
        if (!fertig.isCompleted) {
          fertig.complete(
              Size(info.image.width.toDouble(), info.image.height.toDouble()));
        }
        info.dispose();
        strom.removeListener(horcher);
      },
      onError: (_, __) {
        if (!fertig.isCompleted) fertig.complete(null);
        strom.removeListener(horcher);
      },
    );
    strom.addListener(horcher);
    return fertig.future;
  }

  /// Ein Tipp auf einen Rahmen.
  ///
  /// **Benannt führt zur Person, unbenannt fragt nach dem Namen.** Das
  /// war der eigentliche Mangel: Benennen ging bisher nur über „das erste
  /// unbenannte Gesicht dieses Fotos" in der Info-Ansicht – bei einer
  /// Gruppenaufnahme benannte man damit blind irgendwen.
  Future<void> _gesichtAngetippt(FaceData gesicht) async {
    final person = gesicht.personId;
    final bibliothek = widget.library;
    if (person != null) {
      if (bibliothek == null) return;
      final zeile = await (widget.db.select(widget.db.people)
            ..where((t) => t.id.equals(person)))
          .getSingleOrNull();
      if (!mounted || zeile == null) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PersonDetailScreen(library: bibliothek, person: zeile),
      ));
      await _gesichterLaden();
      return;
    }
    if (gesicht.isIgnored) return;
    final personen = await widget.db.select(widget.db.people).get();
    // Wer könnte das sein? Ohne Bibliothek gibt es keinen Vorschlag – der
    // Betrachter läuft auch ohne sie (siehe [widget.library]).
    final vorschlag = await bibliothek?.personenvorschlag(gesicht.embedding);
    if (!mounted) return;
    final wahl = await showPersonPickerDialog(context, personen,
        paths: widget.paths,
        suggestedPerson: vorschlag,
        title: AppTexte.of(context).viewerGesichtBenennen);
    if (wahl == null) return;
    final id = wahl.newName != null ? const Uuid().v4() : wahl.existingPersonId!;
    if (wahl.newName != null) {
      await widget.db
          .createPerson(PeopleCompanion.insert(id: id, name: wahl.newName!));
    }
    await widget.db.assignFacesToPerson([gesicht.id], id);
    await _gesichterLaden();
  }

  /// Ein aufgezogener Rahmen wird zu einem Gesicht.
  ///
  /// [kasten] steht in Anteilen des Fotos (0..1) – dieselbe Rechnung wie
  /// bei den vorhandenen Rahmen, damit ein neuer dort landet, wo er
  /// aufgezogen wurde.
  Future<void> _rahmenFertig(Rect kasten) async {
    final bibliothek = widget.library;
    setState(() {
      _zugAnfang = null;
      _zugJetzt = null;
    });
    if (bibliothek == null) return;
    if (!rahmenGrossGenug(kasten)) {
      // Ein Tipp statt eines Zuges. Wortlos verwerfen sähe aus, als sei
      // der Modus kaputt.
      if (mounted) melde.hinweis(AppTexte.of(context).viewerRahmenZuKlein);
      return;
    }

    final personen = await widget.db.select(widget.db.people).get();
    if (!mounted) return;
    // Kein Vorschlag: Der Rahmen ist gerade erst entstanden, eine
    // Einbettung dazu gibt es noch nicht – sie entsteht beim Anlegen.
    final wahl = await showPersonPickerDialog(context, personen,
        paths: widget.paths,
        title: AppTexte.of(context).viewerGesichtNachtragen);
    if (wahl == null || !mounted) return;

    final personId = wahl.newName != null ? const Uuid().v4() : wahl.existingPersonId!;
    if (wahl.newName != null) {
      await widget.db
          .createPerson(PeopleCompanion.insert(id: personId, name: wahl.newName!));
    }

    final datei = await _fileFuture;
    final angelegt = await gesichtVonHandAnlegen(
      library: bibliothek,
      assetId: widget.asset.id,
      bilddatei: datei,
      kasten: kasten,
      personId: personId,
      beiEinbettungsfehler: (e) {
        if (mounted) melde.fehler(AppTexte.of(context).gesichtEmbeddingFehler('$e'));
      },
    );
    if (!mounted) return;
    if (angelegt == null) {
      melde.fehler(AppTexte.of(context).viewerRahmenNichtLesbar);
      return;
    }
    widget.beiGesichtAngelegt?.call();
    await _gesichterLaden();
  }

  /// Nur für einfache Fotos (kein Video, kein Live-Photo-Standbild – dessen
  /// eigener Anzeige-/Wiedergabepfad in _LivePhotoPage liegt und hier nicht
  /// mitbehandelt wird). Mit kurzer Verzögerung (Muster: Filmstrip-Debounce),
  /// damit schnelles Durchblättern per Pfeiltasten nicht bei jedem
  /// Zwischenstopp eine Berechnung anstößt, die sofort wieder verworfen wird.
  void _maybeScheduleFocusPeaking() {
    if (!widget.focusPeakingEnabled ||
        !widget.isCurrent ||
        widget.asset.type != 'IMAGE' ||
        widget.asset.linkedAssetId != null) {
      return;
    }
    _focusPeakingDebounce?.cancel();
    _focusPeakingDebounce = Timer(const Duration(milliseconds: 200), _computeFocusPeaking);
  }

  Future<void> _computeFocusPeaking() async {
    final requestedAssetId = widget.asset.id;
    try {
      final file = await _fileFuture;
      final bytes = await file.readAsBytes();
      final overlay = await compute(computeFocusPeakingOverlay, bytes);
      if (!mounted || widget.asset.id != requestedAssetId || !widget.focusPeakingEnabled) return;
      setState(() => _focusPeakingOverlay = overlay);
    } catch (_) {
      // Overlay ist rein visuelles Extra – ein Fehler hier darf die
      // eigentliche Foto-Anzeige nicht stören.
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    return FutureBuilder<File>(
      future: _fileFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final file = snapshot.data!;
        if (asset.type == 'IMAGE' && asset.linkedAssetId != null) {
          return _LivePhotoPage(
            db: widget.db,
            paths: widget.paths,
            library: widget.library,
            imageFile: file,
            videoAssetId: asset.linkedAssetId!,
            isLocked: asset.isLocked,
            isPanorama: isPanorama(asset),
          );
        }
        if (asset.type != 'IMAGE') {
          return _VideoPage(file: file, isCurrent: widget.isCurrent);
        }
        if (isEquirectangular360(asset) && !_showFlatPreview) {
          final isSphere = _panoramaMode == Panorama360Mode.sphere;
          return Stack(
            children: [
              Panorama360View(imageFile: file, mode: _panoramaMode),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    _NavArrowButton(
                      icon: isSphere ? Icons.panorama_horizontal : Icons.threed_rotation,
                      tooltip: isSphere
                          ? AppTexte.of(context).viewerFlachesSchwenken
                          : AppTexte.of(context).viewerKugelSchwenken,
                      onPressed: () => setState(() {
                        _panoramaMode =
                            isSphere ? Panorama360Mode.flat : Panorama360Mode.sphere;
                      }),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _NavArrowButton(
                      icon: Icons.crop_original,
                      tooltip: AppTexte.of(context).viewerFlacheVorschau,
                      onPressed: () => setState(() => _showFlatPreview = true),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        final overlay = _focusPeakingOverlay;
        // Die Rahmen brauchen die Masse des Bildes: Ohne sie ist der
        // Anteil 0,3 kein Ort.
        final masse = _bildmasse;
        final rahmen =
            widget.gesichterZeigen && masse != null && _gesichter.isNotEmpty;
        final textkaesten =
            widget.textZeigen && masse != null && _stellen.isNotEmpty;
        // Der Malmodus zählt mit: Gerade auf einem Foto, auf dem die
        // Erkennung NICHTS gefunden hat, will man nachtragen – und dort ist
        // `rahmen` falsch, weil es keine Rahmen gibt. Ohne diese Zeile wäre
        // Nachtragen genau dort unmöglich, wo es am nötigsten ist.
        final malen = widget.gesichtAufziehen && masse != null;
        // Eine Überlagerung genügt, damit das Kind genau das Bild sein muss.
        final ueberlagert = rahmen || textkaesten || malen;
        if (overlay == null && !ueberlagert) {
          return Stack(
            children: [
              BildZoomGesten(
                steuerung: _zoomsteuerung,
                child: PhotoView(
                  imageProvider: begrenztesBild(file),
                  controller: _zoomsteuerung,
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  initialScale: isPanorama(asset) ? PhotoViewComputedScale.covered : null,
                  minScale: isPanorama(asset) ? PhotoViewComputedScale.covered : null,
                ),
              ),
              // Im Malmodus sagt die Fahne, was zu tun ist. Sie ersetzt die
              // Auskunft „hier ist kein Gesicht" – die ist dann gerade der
              // Anlass und nicht mehr die Nachricht.
              if (malen)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppSpacing.md,
                  child: Center(child: _Hinweisfahne(
                      text: AppTexte.of(context).viewerAufziehenHinweis)),
                )
              else if (widget.gesichterZeigen && _gesichter.isEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppSpacing.md,
                  child: Center(child: _Hinweisfahne(
                      text: AppTexte.of(context).viewerKeineGesichter)),
                ),
              // Zwei verschiedene Auskünfte, und der Unterschied trägt:
              // „kein Text im Bild" ist ein Ergebnis, „noch keine Stellen
              // gespeichert" ist ein Foto aus einem Lauf vor Schema 60, das
              // die Texterkennung noch einmal anfassen muss.
              if (widget.textZeigen && _stellen.isEmpty)
                Positioned(
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  bottom: widget.gesichterZeigen && _gesichter.isEmpty ? 56 : AppSpacing.md,
                  child: Center(
                    child: _Hinweisfahne(
                      text: (widget.asset.ocrText ?? '').trim().isEmpty
                          ? AppTexte.of(context).viewerKeinText
                          : AppTexte.of(context).viewerTextNochNicht,
                    ),
                  ),
                ),
              if (isEquirectangular360(asset))
                Positioned(
                  top: 8,
                  right: 8,
                  child: _NavArrowButton(
                    icon: Icons.public,
                    tooltip: AppTexte.of(context).ansicht360,
                    onPressed: () => setState(() => _showFlatPreview = false),
                  ),
                ),
            ],
          );
        }
        return BildZoomGesten(
          steuerung: _zoomsteuerung,
          child: PhotoView.customChild(
          controller: _zoomsteuerung,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          // Mit Rahmen ist das Kind genau das Bild – nur dann liegt ein
          // Kasten bei 0,3 auch auf drei Zehnteln des Fotos und nicht auf
          // drei Zehnteln des Fensters samt seiner schwarzen Ränder.
          childSize: ueberlagert ? masse : null,
          // Ohne das verschöbe der Zug das Bild, statt einen Rahmen zu
          // malen: PhotoView greift dieselbe Geste ab.
          disableGestures: malen,
          initialScale: isPanorama(asset) ? PhotoViewComputedScale.covered : null,
          minScale: isPanorama(asset) ? PhotoViewComputedScale.covered : null,
          child: GestureDetector(
            // `opaque` nur im Malmodus: Sonst schluckte diese Fläche die
            // Tipps auf die Gesichtsrahmen darunter.
            behavior: malen ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
            onPanStart: malen
                ? (d) => setState(() {
                      _zugAnfang = d.localPosition;
                      _zugJetzt = d.localPosition;
                    })
                : null,
            onPanUpdate:
                malen ? (d) => setState(() => _zugJetzt = d.localPosition) : null,
            onPanEnd: malen
                ? (_) {
                    final a = _zugAnfang, b = _zugJetzt;
                    if (a == null || b == null) return;
                    // Die Umrechnung steht in [kastenAusZug] und nicht
                    // hier: Sie ist die Umkehrung dessen, was
                    // [Gesichtsrahmen] rechnet, und das gehört geprüft.
                    unawaited(_rahmenFertig(kastenAusZug(a, b, masse)));
                  }
                : null,
            child: Stack(
            fit: StackFit.expand,
            children: [
              // Derselbe Deckel wie im Zweig ohne Überlagerung. Er
              // fehlte hier: Die Fokus-Hervorhebung einzuschalten hob
              // dasselbe Foto von 4096 Punkten auf seine volle Grösse –
              // bei der breitesten Aufnahme der Prüfbibliothek von 64 MB
              // auf 317 MB. Das Overlay selbst ist ohnehin begrenzt
              // (siehe computeFocusPeakingOverlay).
              Image(image: begrenztesBild(file), fit: BoxFit.contain),
              if (overlay != null) Image.memory(overlay, fit: BoxFit.contain),
              if (rahmen)
                for (final gesicht in _gesichter)
                  if (!gesicht.isIgnored)
                    Gesichtsrahmen(
                      gesicht: gesicht,
                      personName: _gesichtsnamen[gesicht.personId],
                      flaeche: masse,
                      beiTipp: () => _gesichtAngetippt(gesicht),
                    ),
              if (textkaesten)
                for (final stelle in _stellen)
                  Textrahmen(
                    stelle: stelle,
                    flaeche: masse,
                    beiTipp: _zeileKopieren,
                  ),
              // Der Rahmen, der gerade gezogen wird. Ohne ihn zöge man
              // blind und sähe erst nach dem Loslassen, was man getroffen
              // hat.
              if (malen && _zugAnfang != null && _zugJetzt != null)
                Positioned.fromRect(
                  rect: Rect.fromPoints(_zugAnfang!, _zugJetzt!),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.orangeAccent, width: 2),
                        color: Colors.orangeAccent.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                ),
            ],
            ),
          ),
        ),
        );
      },
    );
  }
}

/// Ein kurzer Satz auf dunklem Grund, über das Foto gelegt.
///
/// Gebraucht für die Auskunft „hier ist kein Gesicht". Ohne sie sähe das
/// Einschalten der Rahmen bei einer Landschaftsaufnahme aus, als sei der
/// Knopf kaputt.
class _Hinweisfahne extends StatelessWidget {
  final String text;
  const _Hinweisfahne({required this.text});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      );
}

/// Lädt den verknüpften Video-Asset-Datensatz (für den Dateipfad) und zeigt
/// dann die Live-Photo-Ansicht mit Press-and-Hold-Wiedergabe.
class _LivePhotoPage extends StatefulWidget {
  final AppDatabase db;
  final StoragePaths paths;
  final LibraryState? library;
  final File imageFile;
  final String videoAssetId;
  final bool isLocked;
  final bool isPanorama;
  const _LivePhotoPage({
    required this.db,
    required this.paths,
    required this.library,
    required this.imageFile,
    required this.videoAssetId,
    required this.isLocked,
    required this.isPanorama,
  });

  @override
  State<_LivePhotoPage> createState() => _LivePhotoPageState();
}

class _LivePhotoPageState extends State<_LivePhotoPage> {
  /// Siehe [BildZoomGesten] – eigene Steuerung, weil dies ein eigener
  /// Zustand ist.
  final PhotoViewController _zoomsteuerung = PhotoViewController();

  @override
  void dispose() {
    _zoomsteuerung.dispose();
    super.dispose();
  }


  late final Future<AssetData?> _videoAssetFuture =
      widget.db.assetById(widget.videoAssetId);
  // Erst berechenbar, sobald _videoAssetFuture aufgelöst ist – deshalb per
  // `??=` einmalig gecacht statt (wie ursprünglich) bei jedem Rebuild neu im
  // FutureBuilder-Callback erzeugt zu werden.
  Future<File>? _videoFileFuture;

  Future<File> _resolveVideoFile(AssetData videoAsset) {
    return _videoFileFuture ??= (widget.isLocked && widget.library != null
        ? widget.library!.decryptForViewing(videoAsset.relativePath)
        : Future.value(widget.paths.absolute(videoAsset.relativePath)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetData?>(
      future: _videoAssetFuture,
      builder: (context, snapshot) {
        final videoAsset = snapshot.data;
        if (videoAsset == null) {
          // Video (noch) nicht geladen oder wurde gelöscht – Standbild ohne
          // Live-Funktion zeigen, statt die Ansicht zu blockieren.
          return BildZoomGesten(
            steuerung: _zoomsteuerung,
            child: PhotoView(
              imageProvider: begrenztesBild(widget.imageFile),
              controller: _zoomsteuerung,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              initialScale:
                  widget.isPanorama ? PhotoViewComputedScale.covered : null,
              minScale:
                  widget.isPanorama ? PhotoViewComputedScale.covered : null,
            ),
          );
        }
        return FutureBuilder<File>(
          future: _resolveVideoFile(videoAsset),
          builder: (context, videoSnapshot) {
            if (!videoSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return LivePhotoView(
                imageFile: widget.imageFile, videoFile: videoSnapshot.data!);
          },
        );
      },
    );
  }
}

class _VideoPage extends StatefulWidget {
  final File file;
  final bool isCurrent;
  const _VideoPage({required this.file, required this.isCurrent});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  // Nicht mehr eager im Feld-Initialisierer erzeugt: PageView.builder kann
  // Nachbarseiten schon vorab aufbauen, bevor zu ihnen geblättert wurde – ein
  // dort sofort erzeugter, initialisierter und abspielender
  // Videocontroller würde dann außerhalb der sichtbaren Seite unnötig
  // Speicher/Decoder-Ressourcen belegen und (bei zwei gleichzeitig
  // abspielenden Videos) sogar doppelten Ton erzeugen. Stattdessen wird der
  // Controller erst erzeugt, sobald diese Seite tatsächlich [isCurrent] ist,
  // und beim Verlassen pausiert statt weiterzulaufen.
  VideoPlaybackController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.isCurrent) _ensureController();
  }

  @override
  void didUpdateWidget(covariant _VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrent && !oldWidget.isCurrent) {
      _ensureController();
      _controller?.play();
    } else if (!widget.isCurrent && oldWidget.isCurrent) {
      _controller?.pause();
    }
  }

  void _ensureController() {
    if (_controller != null) return;
    final controller = VideoPlaybackController();
    _controller = controller;
    controller.open(widget.file, loop: true).then((ok) {
      if (!mounted) return;
      setState(() {});
      if (ok && widget.isCurrent) controller.play();
    });
    // Start/Stopp kommt bei media_kit über einen Strom, nicht über einen
    // ChangeNotifier – ohne dieses Abo bliebe das Play-Symbol stehen.
    controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.isReady) {
      return widget.isCurrent
          ? const Center(child: CircularProgressIndicator())
          : const ColoredBox(color: Colors.black);
    }
    return Center(
      child: GestureDetector(
        onTap: () => setState(() {
          controller.isPlaying ? controller.pause() : controller.play();
        }),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: controller.aspectRatio,
              child: VideoSurface(controller: controller),
            ),
            // Kurz aufblitzendes Play-Symbol, solange pausiert (z.B. direkt
            // nach dem Öffnen oder nach einem Tap zum Pausieren).
            if (!controller.isPlaying)
              const Icon(Icons.play_arrow, color: Colors.white70, size: 72),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressBar(
                controller: controller,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.md),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
