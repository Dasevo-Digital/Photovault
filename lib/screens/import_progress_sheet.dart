import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';

import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart' show unterstuetzteEndungen;
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/camera_source_picker_dialog.dart';
import 'asset_viewer_screen.dart';
import 'import_plan_screen.dart';
import 'package:kern/services/import_plan.dart';
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
      content: Text(AppTexte.of(context).importWasText),
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
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      // Dieselbe Liste wie der Import selbst: Hier fehlten Photoshop und
      // alle Videoformate ausser den fünf ältesten (#232).
      allowedExtensions: [
        for (final ext in unterstuetzteEndungen) ext.substring(1),
      ],
    );
    paths = result.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
  } else if (mode == _ImportMode.folder) {
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: AppTexte.of(context).importOrdnerWaehlen,
    );
    if (folder == null) return;
    if (!context.mounted) return;
    paths = await ImportPlanDienst.dateienImOrdner(folder);
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
    paths = await ImportPlanDienst.dateienImOrdner(dcimPath);
    if (paths.isEmpty) {
      if (context.mounted) {
        melde.hinweis(AppTexte.of(context).importNichtsAufDatentraeger);
      }
      return;
    }
  }

  if (paths.isEmpty || !context.mounted) return;

  final plan = await Navigator.of(context).push<ImportPlan>(
    MaterialPageRoute(
      builder: (_) => ImportPlanScreen(library: library, dateien: paths),
    ),
  );
  if (plan == null || !context.mounted || plan.eintraege.isEmpty) return;
  paths = plan.eintraege.map((e) => e.pfad).toList();

  await showModalBottomSheet(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (context) =>
        _ImportProgressSheet(library: library, filePaths: paths, plan: plan),
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

/// Ein Satz dazu, woran eine Datei scheiterte (#335) – aus dem, was
/// [ImportProgress.grund] mitbringt.
String importFehlertext(AppTexte t, Object? grund) => switch (grund) {
  null || '' => t.importFehlerUnbekannt,
  KeineVerbindung() => t.importFehlerKeineVerbindung,
  Serverfehler(:final status, :final text) => t.importFehlerServer(
    status,
    _kurzerServertext(text),
  ),
  FormatException(:final message)
      when message == 'pv_import_quelle_geaendert' =>
    t.importFehlerQuelleGeaendert,
  FormatException(:final message)
      when message == 'pv_import_regeln_geaendert' =>
    t.importPlanGeaendert,
  FormatException(:final message) => message,
  FileSystemException(:final message, :final osError) =>
    osError == null ? message : '$message (${osError.message})',
  final String text => text,
  _ => '$grund',
};

/// Aus der Antwort eines Servers oder Proxys das Wesentliche: der Titel
/// einer HTML-Fehlerseite, der Text eines JSON-Fehlers, sonst der Anfang.
String _kurzerServertext(String text) {
  final titel = RegExp(
    r'<title>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(text);
  if (titel != null) return titel.group(1)!.trim();
  final json = RegExp(r'"fehler"\s*:\s*"([^"]*)"').firstMatch(text);
  if (json != null) return json.group(1)!;
  final rein = text
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return rein.length > 80 ? '${rein.substring(0, 80)} …' : rein;
}

class _ImportProgressSheet extends StatefulWidget {
  final LibraryState library;
  final List<String> filePaths;
  final ImportPlan plan;
  const _ImportProgressSheet({
    required this.library,
    required this.filePaths,
    required this.plan,
  });

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

  /// Die gescheiterten Dateien mit ihrem Grund – für „Warum?“ und für den
  /// neuen Versuch.
  final _gescheitert = <String, Object?>{};

  @override
  void initState() {
    super.initState();
    _run(widget.filePaths, widget.plan);
  }

  Future<void> _run(List<String> pfade, ImportPlan plan) async {
    final offen = pfade.toSet();
    try {
      await for (final progress in widget.library.importFiles(
        pfade,
        plan: plan,
      )) {
        if (!mounted) return;
        setState(() {
          _done = progress.done;
          _total = progress.total;
          _currentFile = progress.currentFile;
          if (progress.pfad case final pfad?) offen.remove(pfad);
          if (progress.assetId != null) {
            _importedAssetIds.add(progress.assetId!);
          }
          if (progress.duplikat) _duplikate++;
          if (progress.gescheitert) {
            _fehler++;
            if (progress.pfad case final pfad?) {
              _gescheitert[pfad] = progress.grund;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // Was der Lauf nicht mehr erreichte, kam auch nicht herein – und
          // lässt sich so noch einmal versuchen.
          for (final pfad in offen) {
            _gescheitert[pfad] = e;
          }
          _fehler += offen.isEmpty ? 1 : offen.length;
        });
        melde.warnung(AppTexte.of(context).importPlanGeaendert);
      }
    } finally {
      if (mounted) setState(() => _finished = true);
    }
  }

  /// Nur die gescheiterten Dateien noch einmal, mit demselben Plan.
  Future<void> _wiederhole() async {
    final pfade = _gescheitert.keys.toList();
    if (pfade.isEmpty) return;
    setState(() {
      _gescheitert.clear();
      _fehler = 0;
      _finished = false;
      _done = 0;
      _total = pfade.length;
      _currentFile = null;
    });
    await _run(pfade, widget.plan.auswahl(pfade.toSet()));
  }

  /// Gleiche Gründe zusammen: „41 × Server nicht erreichbar“ statt 41
  /// gleicher Zeilen.
  Widget _fehlerliste(AppTexte t) {
    final gruppen = <String, List<String>>{};
    for (final MapEntry(key: pfad, value: grund) in _gescheitert.entries) {
      gruppen
          .putIfAbsent(importFehlertext(t, grund), () => [])
          .add(p.basename(pfad));
    }
    final stil = Theme.of(context).textTheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(t.importFehlerWarum),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final MapEntry(key: grund, value: namen)
                    in gruppen.entries) ...[
                  Text('${namen.length} × $grund', style: stil.bodyMedium),
                  Text(
                    namen.length > 6
                        ? '${namen.take(6).join(', ')} …'
                        : namen.join(', '),
                    style: stil.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _reviewImported() async {
    final assets = <AssetData>[];
    for (final id in _importedAssetIds) {
      final asset = await widget.library.db.assetById(id);
      if (asset != null) assets.add(asset);
    }
    if (!mounted || assets.isEmpty) return;
    Navigator.of(context).pop();
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AssetViewerScreen(
          assets: assets,
          initialIndex: 0,
          paths: widget.library.paths,
          db: widget.library.db,
          library: widget.library,
          cullingMode: true,
        ),
      ),
    );
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
              _finished
                  ? AppTexte.of(context).importAbgeschlossen
                  : AppTexte.of(context).importLaeuft,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              '$_done / $_total${_currentFile != null ? ' — $_currentFile' : ''}',
            ),
            const SizedBox(height: 16),
            // Die Bilanz steht nur da, wenn es etwas zu sagen gibt -
            // "0 uebersprungen" ist keine Nachricht.
            if (_finished && (_duplikate > 0 || _fehler > 0)) ...[
              Text(
                [
                  AppTexte.of(
                    context,
                  ).importBilanzNeu(_importedAssetIds.length),
                  if (_duplikate > 0)
                    AppTexte.of(context).importBilanzDuplikate(_duplikate),
                  if (_fehler > 0)
                    AppTexte.of(context).importBilanzFehler(_fehler),
                ].join(' · '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_gescheitert.isNotEmpty) _fehlerliste(AppTexte.of(context)),
              const SizedBox(height: 16),
            ],
            if (_finished) ...[
              if (_gescheitert.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: _wiederhole,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    AppTexte.of(
                      context,
                    ).importErneutVersuchen(_gescheitert.length),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_importedAssetIds.isNotEmpty) ...[
                FilledButton.icon(
                  onPressed: _reviewImported,
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: Text(AppTexte.of(context).importJetztSichten),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppTexte.of(context).allgFertig),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
