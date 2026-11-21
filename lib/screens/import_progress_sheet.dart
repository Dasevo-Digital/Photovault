import '../services/umzugsquelle.dart';
import 'dart:io';
import 'dart:async';

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
import 'home_shell.dart' show Hauptbereich;
import 'import_plan_screen.dart';
import 'importquittungen_screen.dart';
import '../services/importquittungen.dart';
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
          onPressed: () => Navigator.pop(context, _ImportMode.umzug),
          child: Text(AppTexte.of(context).umzugTitel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ImportMode.quittungen),
          child: Text(AppTexte.of(context).importQuittungenTitel),
        ),
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
  if (mode == _ImportMode.quittungen) {
    await zeigeImportquittungen(context, library);
    return;
  }

  Umzugsquelle? quelle;
  try {
    List<String> paths;
    if (mode == _ImportMode.umzug) {
      final t = AppTexte.of(context);
      final zip = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(t.umzugTitel),
          content: Text(t.umzugQuellenHinweis),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t.umzugOrdner),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t.umzugArchive),
            ),
          ],
        ),
      );
      if (zip == null || !context.mounted) return;
      if (zip) {
        final dateien = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
        final pfade = dateien.map((f) => f.path).whereType<String>().toList();
        if (pfade.isEmpty) return;
        if (!context.mounted) return;
        quelle = await _leseUmzugsquelle(
          context,
          (abbruch, fortschritt) => Umzugsquelle.archive(
            pfade,
            abbruch: abbruch,
            fortschritt: fortschritt,
          ),
        );
      } else {
        final pfad = await FilePicker.getDirectoryPath(
          dialogTitle: t.umzugOrdner,
        );
        if (pfad == null) return;
        if (!context.mounted) return;
        quelle = await _leseUmzugsquelle(
          context,
          (abbruch, fortschritt) => Umzugsquelle.ordner(
            pfad,
            abbruch: abbruch,
            fortschritt: fortschritt,
          ),
        );
      }
      paths = quelle.dateien;
    } else if (mode == _ImportMode.files) {
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
        builder: (_) =>
            ImportPlanScreen(library: library, dateien: paths, umzug: quelle),
      ),
    );
    if (plan == null ||
        !context.mounted ||
        (plan.eintraege.isEmpty && plan.ausgelassen.isEmpty)) {
      return;
    }
    paths = plan.eintraege.map((e) => e.pfad).toList();

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (context) =>
          _ImportProgressSheet(library: library, filePaths: paths, plan: plan),
    );
  } on UmzugAbgebrochen {
    return;
  } on Object catch (fehler) {
    if (context.mounted) {
      final t = AppTexte.of(context);
      melde.warnung(
        fehler is FormatException &&
                fehler.message == 'pv_umzug_metadaten_budget'
            ? t.umzugBudgetFehler
            : t.umzugQuellenFehler,
      );
    }
  } finally {
    await quelle?.schliesse();
  }
}

enum _ImportMode { files, folder, camera, quittungen, umzug }

Future<Umzugsquelle> _leseUmzugsquelle(
  BuildContext context,
  Future<Umzugsquelle> Function(Umzugsabbruch, void Function(int)) lesen,
) async {
  final abbruch = Umzugsabbruch();
  final fortschritt = ValueNotifier<int>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: fortschritt,
                builder: (c, n, _) => Text(
                  n == 0
                      ? AppTexte.of(c).umzugQuelleLesen
                      : AppTexte.of(c).umzugQuelleDateien(n),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: abbruch.abbrechen,
            child: Text(AppTexte.of(c).allgAbbrechen),
          ),
        ],
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    return await lesen(abbruch, (n) => fortschritt.value = n);
  } finally {
    if (route.isActive) navigator.removeRoute(route);
    // Die Route kann noch ausblenden und auf den Zähler zugreifen.
    unawaited(route.completed.then((_) => fortschritt.dispose()));
  }
}

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

/// Ein Satz dazu, woran eine Datei oder ein ganzer Lauf scheiterte (#335) –
/// aus dem, was [ImportProgress.grund] mitbringt.
///
/// Eine Kennung kann als Ausnahme kommen oder als Text: als Text etwa vom
/// Server, der den Grund in einer Kopfzeile weiterreicht. Beides wird
/// gleich übersetzt (IMP-028).
String importFehlertext(AppTexte t, Object? grund) => switch (grund) {
  null || '' => t.importFehlerUnbekannt,
  KeineVerbindung() => t.importFehlerKeineVerbindung,
  Serverfehler(:final status, :final text) => t.importFehlerServer(
    status,
    _kurzerServertext(text),
  ),
  FormatException(:final message) => _kennungstext(t, message),
  FileSystemException(:final message, :final osError) =>
    osError == null ? message : '$message (${osError.message})',
  final String text => _kennungstext(t, text),
  _ => '$grund',
};

/// Bekannte Kennungen als Satz, alles andere unverändert. Ältere Server
/// schicken die Kennung noch mit dem Namen der Ausnahme davor; gelesen wird
/// deshalb die Kennung am Ende des Textes.
String _kennungstext(AppTexte t, String text) {
  final kennung = RegExp(r'pv_[a-z0-9_]+$').firstMatch(text)?.group(0);
  return switch (kennung) {
    'pv_import_quelle_geaendert' => t.importFehlerQuelleGeaendert,
    'pv_import_regeln_geaendert' ||
    'pv_import_auswahl' => t.importPlanGeaendert,
    'pv_import_server_zu_alt' => t.importPlanServerAlt,
    _ => text,
  };
}

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
  String? _quittungId;

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

  /// Wie viele in der Fotokammer liegen (#336).
  int _inKammer = 0;

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
    _quittungId = null;
    try {
      final ablage = await Importquittungen.fuer(widget.library.paths.root);
      await for (final progress in ablage.protokolliere(
        plan,
        pfade.isEmpty
            ? const Stream.empty()
            : widget.library.importFiles(pfade, plan: plan),
        begonnen: (id) => _quittungId = id,
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
          if (progress.kammer) _inKammer++;
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
        // Der wirkliche Grund: Vorher stand hier für jeden Abbruch „…
        // haben sich geändert“, auch wenn der Server weg oder zu alt war
        // (IMP-087).
        final t = AppTexte.of(context);
        melde.warnung(
          e is QuittungSchreibfehler
              ? t.quittungSchreibfehler
              : importFehlertext(t, e),
        );
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
    final progress = _total == 0 ? (_finished ? 1.0 : 0.0) : _done / _total;
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
            if (_finished &&
                (_duplikate > 0 || _fehler > 0 || _inKammer > 0)) ...[
              Text(
                [
                  if (_inKammer == 0 || _importedAssetIds.isNotEmpty)
                    AppTexte.of(
                      context,
                    ).importBilanzNeu(_importedAssetIds.length),
                  if (_inKammer > 0)
                    AppTexte.of(context).importBilanzKammer(_inKammer),
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
              if (_inKammer > 0) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.library.zeigeBereich(Hauptbereich.fotokammer);
                  },
                  icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                  label: Text(AppTexte.of(context).importZurKammer),
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
              if (_quittungId case final id?)
                TextButton.icon(
                  onPressed: () =>
                      zeigeImportquittungen(context, widget.library, id: id),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(AppTexte.of(context).quittungTitel),
                ),
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
