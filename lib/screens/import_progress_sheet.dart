import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../db/database.dart';
import '../services/raw_formats.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/camera_source_picker_dialog.dart';
import 'asset_viewer_screen.dart';
import '../services/meldungsdienst.dart';

/// Fragt zunächst, ob einzelne Dateien, ein ganzer Ordner oder direkt eine
/// angeschlossene Kamera/SD-Karte importiert werden sollen, und importiert
/// die gewählten Fotos/Videos anschließend in die lokale Bibliothek, mit
/// Live-Fortschritt (inkl. Gesichtserkennung + CLIP-Embedding, sofern
/// verfügbar).
Future<void> showImportSheet(BuildContext context, LibraryState library) async {
  final mode = await showDialog<_ImportMode>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppTexte.of(context).importWasTitel),
      content: Text(
        AppTexte.of(context).importWasText,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _ImportMode.files),
          child: Text(AppTexte.of(context).importEinzelneDateien),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, _ImportMode.folder),
          child: Text(AppTexte.of(context).importGanzerOrdner),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _ImportMode.camera),
          icon: const Icon(Icons.photo_camera_outlined, size: 18),
          label: Text(AppTexte.of(context).importVonKamera),
        ),
      ],
    ),
  );
  if (mode == null || !context.mounted) return;

  List<String> paths;
  if (mode == _ImportMode.files) {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'jpg', 'jpeg', 'png', 'heic', 'heif', 'avif', 'avifs', 'webp', 'gif', 'bmp', 'tiff',
        for (final ext in rawImageExtensions) ext.substring(1),
        'mp4', 'mov', 'avi', 'mkv', 'm4v',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    paths = result.files.map((f) => f.path).whereType<String>().toList();
  } else if (mode == _ImportMode.folder) {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AppTexte.of(context).importOrdnerWaehlen,
    );
    if (folder == null) return;
    if (!context.mounted) return;
    paths = await library.importService.collectSupportedFilesInFolder(folder);
    if (paths.isEmpty) {
      if (context.mounted) {
        melde.hinweis(AppTexte.of(context).importNichtsImOrdner);
      }
      return;
    }
  } else {
    final dcimPath = await showCameraSourcePickerDialog(context);
    if (dcimPath == null) return;
    if (!context.mounted) return;
    paths = await library.importService.collectSupportedFilesInFolder(dcimPath);
    if (paths.isEmpty) {
      if (context.mounted) {
        melde.hinweis(AppTexte.of(context).importNichtsAufDatentraeger);
      }
      return;
    }
  }

  if (paths.isEmpty || !context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => _ImportProgressSheet(library: library, filePaths: paths),
  );
}

enum _ImportMode { files, folder, camera }

/// Die Bilanz eines Imports als eine Zeile – oder `null`, wenn es nichts
/// zu sagen gibt.
///
/// **Warum es sie gibt.** Duplikate wurden immer schon übersprungen, nur
/// sagte es niemand. Wer zweihundert Dateien hereinzieht und danach
/// hundertachtzig Fotos vorfindet, sucht den Fehler bei sich.
///
/// Und warum sie meistens `null` ist: Ging alles glatt, steht die Zahl der
/// neuen Aufnahmen ohnehin schon im Fortschritt darüber. „0 übersprungen,
/// 0 Fehler" wäre keine Nachricht, sondern Rauschen.
String? importBilanz(
  AppTexte t, {
  required int neu,
  required int duplikate,
  required int fehler,
}) {
  if (duplikate == 0 && fehler == 0) return null;
  return [
    t.importBilanzNeu(neu),
    if (duplikate > 0) t.importBilanzDuplikate(duplikate),
    if (fehler > 0) t.importBilanzFehler(fehler),
  ].join(' · ');
}

class _ImportProgressSheet extends StatefulWidget {
  final LibraryState library;
  final List<String> filePaths;
  const _ImportProgressSheet({required this.library, required this.filePaths});

  @override
  State<_ImportProgressSheet> createState() => _ImportProgressSheetState();
}

class _ImportProgressSheetState extends State<_ImportProgressSheet> {
  int _done = 0;
  int _total = 0;
  String? _currentFile;
  bool _finished = false;

  /// Asset-IDs aller in diesem Lauf tatsächlich neu importierten Fotos/
  /// Videos (keine Duplikate/Fehler) – für den "Jetzt sichten"-Einstieg in
  /// den Sichtungs-Modus (Culling) direkt nach dem Import.
  final List<String> _importedAssetIds = [];

  /// Was uebersprungen wurde und was gar nicht hereinkam.
  ///
  /// Beides gab es immer schon, gesagt wurde es nie: Wer zweihundert
  /// Dateien hereinzieht und danach hundertachtzig Fotos vorfindet,
  /// sucht den Fehler bei sich.
  int _duplikate = 0;
  int _fehler = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await for (final progress in widget.library.importFiles(widget.filePaths)) {
      if (!mounted) return;
      setState(() {
        _done = progress.done;
        _total = progress.total;
        _currentFile = progress.currentFile;
        if (progress.assetId != null) _importedAssetIds.add(progress.assetId!);
        if (progress.duplikat) _duplikate++;
        if (progress.gescheitert) _fehler++;
      });
    }
    if (mounted) setState(() => _finished = true);
  }

  Future<void> _reviewImported() async {
    final assets = <AssetData>[];
    for (final id in _importedAssetIds) {
      final asset = await widget.library.db.assetById(id);
      if (asset != null) assets.add(asset);
    }
    if (!mounted || assets.isEmpty) return;
    Navigator.of(context).pop();
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: assets,
        initialIndex: 0,
        paths: widget.library.paths,
        db: widget.library.db,
        library: widget.library,
        cullingMode: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total == 0 ? 0.0 : _done / _total;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _finished ? AppTexte.of(context).importAbgeschlossen : AppTexte.of(context).importLaeuft,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text('$_done / $_total${_currentFile != null ? ' — $_currentFile' : ''}'),
            const SizedBox(height: 16),
            // Die Bilanz steht nur da, wenn es etwas zu sagen gibt -
            // "0 uebersprungen" ist keine Nachricht.
            if (_finished && (_duplikate > 0 || _fehler > 0)) ...[
              Text(
                [
                  AppTexte.of(context).importBilanzNeu(_importedAssetIds.length),
                  if (_duplikate > 0)
                    AppTexte.of(context).importBilanzDuplikate(_duplikate),
                  if (_fehler > 0) AppTexte.of(context).importBilanzFehler(_fehler),
                ].join(' · '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            if (_finished) ...[
              if (_importedAssetIds.isNotEmpty) ...[
                FilledButton.icon(
                  onPressed: _reviewImported,
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: Text(AppTexte.of(context).importJetztSichten),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(AppTexte.of(context).allgFertig)),
            ],
          ],
        ),
      ),
    );
  }
}
