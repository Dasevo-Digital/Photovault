import '../services/umzugsquelle.dart';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';

import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart' show unterstuetzteEndungen;
import '../state/importlauf.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/camera_source_picker_dialog.dart';
import 'asset_viewer_screen.dart';
import 'home_shell.dart' show Hauptbereich;
import 'import_plan_screen.dart';
import 'importquittungen_screen.dart';
import 'package:kern/services/import_plan.dart';
import '../services/meldungsdienst.dart';
import '../services/importfehler.dart';

export '../services/importfehler.dart' show importFehlertext;

/// Fragt zunächst, ob einzelne Dateien, ein ganzer Ordner oder direkt eine
/// angeschlossene Kamera/SD-Karte importiert werden sollen, und importiert
/// die gewählten Fotos/Videos anschließend in die lokale Bibliothek, mit
/// Live-Fortschritt (inkl. Gesichtserkennung + CLIP-Embedding, sofern
/// verfügbar).
Future<void> showImportSheet(BuildContext context, LibraryState library) async {
  // Ein Import auf einmal: Läuft schon einer, kommt sein Blatt wieder,
  // statt dass ein zweiter dieselben Dateien prüft und hereinholt.
  if (library.importlauf case final lauf? when lauf.laeuft) {
    await zeigeImportblatt(context, lauf);
    return;
  }
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
    // Der Import gehört dem Zustand, nicht dem Blatt (IMP-039): Das Blatt
    // darf weg, der Lauf läuft in der Aufgabenleiste weiter. „Anzeigen“
    // an der Schlussmeldung öffnet es über den obersten Navigator wieder –
    // der Bildschirm, aus dem der Import kam, kann dann längst weg sein.
    final wurzel = Navigator.of(context, rootNavigator: true).context;
    // Die entpackten Archive eines Umzugs gehören ab hier dem Lauf: Er
    // braucht sie, bis nichts mehr erneut zu versuchen ist – auch wenn
    // das Blatt längst weg ist.
    final umzug = quelle;
    quelle = null;
    final lauf = Importlauf(
      library: library,
      plan: plan,
      texte: AppTexte.of(context),
      zeigen: (l) {
        if (wurzel.mounted) unawaited(zeigeImportblatt(wurzel, l));
      },
      aufraeumen: umzug?.schliesse,
    );
    library.setzeImportlauf(lauf);
    unawaited(lauf.starte());
    await zeigeImportblatt(context, lauf);
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

/// Zeigt das Fortschrittsblatt eines Imports (IMP-039).
///
/// Das Blatt ist eine Ansicht auf [lauf] und lässt sich wegschieben – nach
/// unten ziehen, daneben klicken oder „Im Hintergrund weiter“. Der Import
/// läuft dann in der Aufgabenleiste weiter, mit „Anzeigen“ und
/// „Abbrechen“; dorthin kommt man auch zurück. Vorher war das Blatt modal
/// und ohne Abbrechen, und die App blieb während des ganzen Imports
/// gesperrt.
///
/// Auf dem obersten Navigator: Das Blatt liegt dann über dem ganzen
/// Fenster, gleich ob es aus der Leiste oder aus der Zeitleiste kommt.
Future<void> zeigeImportblatt(BuildContext context, Importlauf lauf) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _ImportProgressSheet(lauf: lauf),
    );

class _ImportProgressSheet extends StatefulWidget {
  final Importlauf lauf;
  const _ImportProgressSheet({required this.lauf});

  @override
  State<_ImportProgressSheet> createState() => _ImportProgressSheetState();
}

class _ImportProgressSheetState extends State<_ImportProgressSheet> {
  Importlauf get _lauf => widget.lauf;
  LibraryState get _library => _lauf.library;

  @override
  void initState() {
    super.initState();
    _lauf.angezeigt();
  }

  @override
  void dispose() {
    _lauf.verborgen();
    super.dispose();
  }

  /// Gleiche Gründe zusammen: „41 × Server nicht erreichbar“ statt 41
  /// gleicher Zeilen.
  Widget _fehlerliste(AppTexte t) {
    final gruppen = <String, List<String>>{};
    for (final MapEntry(key: pfad, value: grund) in _lauf.gescheitert.entries) {
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
    for (final id in _lauf.importierteIds) {
      final asset = await _library.db.assetById(id);
      if (asset != null) assets.add(asset);
    }
    if (!mounted || assets.isEmpty) return;
    Navigator.of(context).pop();
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AssetViewerScreen(
          assets: assets,
          initialIndex: 0,
          paths: _library.paths,
          db: _library.db,
          library: _library,
          cullingMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _lauf, builder: (context, _) => _baue());

  Widget _baue() {
    final t = AppTexte.of(context);
    final l = _lauf;
    final fertig = l.fertig;
    final progress = l.gesamt == 0
        ? (fertig ? 1.0 : 0.0)
        : l.erledigt / l.gesamt;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              !fertig
                  ? t.importLaeuft
                  : l.abgebrochen
                  ? t.importAbgebrochen
                  : t.importAbgeschlossen,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              '${l.erledigt} / ${l.gesamt}'
              '${l.datei != null ? ' — ${l.datei}' : ''}',
            ),
            const SizedBox(height: 16),
            if (!fertig)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: l.abbrechen,
                    child: Text(t.allgAbbrechen),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t.importImHintergrund),
                  ),
                ],
              ),
            // Die Bilanz steht nur da, wenn es etwas zu sagen gibt -
            // "0 uebersprungen" ist keine Nachricht.
            if (fertig &&
                (l.duplikate > 0 ||
                    l.fehler > 0 ||
                    l.inKammer > 0 ||
                    l.abgebrochen)) ...[
              Text(l.bilanz(t), style: Theme.of(context).textTheme.bodyMedium),
              if (l.gescheitert.isNotEmpty) _fehlerliste(t),
              const SizedBox(height: 16),
            ],
            if (fertig) ...[
              if (l.gescheitert.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: l.wiederhole,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(t.importErneutVersuchen(l.gescheitert.length)),
                ),
                const SizedBox(height: 8),
              ],
              if (l.inKammer > 0) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _library.zeigeBereich(Hauptbereich.fotokammer);
                  },
                  icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                  label: Text(t.importZurKammer),
                ),
                const SizedBox(height: 8),
              ],
              if (l.importierteIds.isNotEmpty) ...[
                FilledButton.icon(
                  onPressed: _reviewImported,
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: Text(t.importJetztSichten),
                ),
                const SizedBox(height: 8),
              ],
              if (l.quittungId case final id?)
                TextButton.icon(
                  onPressed: () =>
                      zeigeImportquittungen(context, _library, id: id),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(t.quittungTitel),
                ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t.allgFertig),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
