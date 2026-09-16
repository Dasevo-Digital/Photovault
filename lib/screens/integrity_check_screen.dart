import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../services/bilddekodierung.dart';
import '../services/integrity_check_service.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/selection_action_bar.dart' show confirmDialog;
import 'asset_viewer_screen.dart';
import '../services/meldungsdienst.dart';

/// Gleicht DB-Zeilen gegen tatsächliche Dateien auf der Platte ab: fehlende
/// Dateien, verwaiste Dateien ohne DB-Zeile, und (optional) Prüfsummen-
/// Abweichungen. Läuft die eigentliche Prüfung in einem eigenen Isolate
/// (siehe [runIntegrityCheck]), damit das Auflisten großer Verzeichnisse die
/// UI nicht blockiert – Muster: DuplicatesScreen.
class IntegrityCheckScreen extends StatefulWidget {
  final LibraryState library;
  const IntegrityCheckScreen({super.key, required this.library});

  @override
  State<IntegrityCheckScreen> createState() => _IntegrityCheckScreenState();
}

class _IntegrityCheckScreenState extends State<IntegrityCheckScreen> {
  bool _loading = true;
  bool _verifyChecksums = false;
  String? _error;
  IntegrityCheckReport? _report;

  /// Je Aufnahme das Vorschaubild und ob sie gesperrt ist.
  ///
  /// **Warum als Karte und nicht je Zeile nachgeschlagen.** Bei einem
  /// fehlenden Original steht die Datenbankzeile noch da – und mit ihr
  /// das Vorschaubild, an dem man erkennt, welches Foto man gleich
  /// austraegt. Nachzuschlagen waere das eine Abfrage je Zeile mitten im
  /// Aufbau; die Prüfung liest die Aufnahmen ohnehin schon einmal
  /// vollstaendig ein (siehe [_load]).
  Map<String, ({String? vorschau, bool gesperrt})> _zurAufnahme = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final assets = await widget.library.db.allAssetsForIntegrityCheck();
      final faces = await widget.library.db.allFaces();
      final masks = await widget.library.db.allDevelopMasks();

      final params = IntegrityCheckParams(
        libraryRootPath: widget.library.paths.root.path,
        assets: [
          for (final a in assets)
            AssetPathSnapshot(
              assetId: a.id,
              relativePath: a.relativePath,
              thumbnailRelativePath: a.thumbnailRelativePath,
              previewRelativePath: a.previewRelativePath,
              developedRelativePath: a.developedRelativePath,
              restoredRelativePath: a.restoredRelativePath,
              trimmedRelativePath: a.trimmedRelativePath,
              checksum: a.checksum,
              isLocked: a.isLocked,
            ),
        ],
        faceCrops: [
          for (final f in faces)
            if (f.cropRelativePath != null)
              FaceCropSnapshot(faceId: f.id, relativePath: f.cropRelativePath!),
        ],
        masks: [
          for (final m in masks) MaskSnapshot(maskId: m.id, relativePath: m.maskRelativePath),
        ],
        verifyChecksums: _verifyChecksums,
      );

      final report = await compute(runIntegrityCheck, params);
      if (!mounted) return;
      setState(() {
        _report = report;
        _zurAufnahme = {
          for (final a in assets)
            a.id: (
              vorschau: a.thumbnailRelativePath ?? a.previewRelativePath,
              gesperrt: a.isLocked,
            ),
        };
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppTexte.of(context).integPruefungFehlgeschlagen('$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Welche Datei die Zeile zeigen kann – oder `null`.
  ///
  /// Zwei Faelle, und sie sind verschieden herum gelagert:
  ///
  /// * Bei einem **fehlenden** Original ist die Datei weg, die
  ///   Datenbankzeile aber noch da. Zu sehen gibt es das Vorschaubild.
  /// * Bei einer **verwaisten** Datei ist es umgekehrt: Die Zeile fehlt,
  ///   die Datei liegt da. Zu sehen gibt es sie selbst.
  ///
  /// Bei einer gesperrten Aufnahme gibt es nichts zu sehen: Das
  /// Vorschaubild ist mitverschluesselt (siehe TresorWaechter), und ein
  /// Entschluesseln allein fuer eine Vorschau waere der falsche Preis.
  ({String pfad, bool gesperrt})? _vorschauFuer(MissingFileIssue issue) {
    if (issue.kind != MissingFileKind.original) return null;
    final eintrag = _zurAufnahme[issue.ownerId];
    final pfad = eintrag?.vorschau;
    if (eintrag == null || pfad == null) return null;
    return (pfad: pfad, gesperrt: eintrag.gesperrt);
  }


  /// Das kleine Bild in der Zeile. Faellt still auf das Zeichen zurueck.
  Widget _zeilenbild(String? pfad, {required bool gesperrt, required IconData ersatz, required Color farbe}) {
    if (pfad == null || gesperrt || !flutterKannAnzeigen(pfad)) {
      return Icon(ersatz, color: farbe);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Image(
        image: begrenztesBild(widget.library.paths.absolute(pfad), kante: 80),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(ersatz, color: farbe),
      ),
    );
  }

  /// Zeigt die Datei gross, bevor irgendetwas geloescht wird.
  Future<void> _sichten(String? pfad, {required bool gesperrt}) async {
    final t = AppTexte.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogKontext) => AlertDialog(
        title: Text(t.integVorschauTitel),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pfad == null || !flutterKannAnzeigen(pfad))
                Text(t.integKeineVorschau)
              else if (gesperrt)
                Text(t.integVorschauVerschluesselt)
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: Image(
                    image: begrenztesBild(
                        widget.library.paths.absolute(pfad), kante: 840),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Text(t.integKeineVorschau),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Text(pfad ?? '',
                  style: Theme.of(dialogKontext).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogKontext).pop(),
            child: Text(t.allgSchliessen),
          ),
        ],
      ),
    );
  }

  /// Der Ansehen-Knopf, oder nichts, wenn es nichts zu sehen gibt.
  Widget? _ansehenKnopf(String? pfad, {required bool gesperrt}) {
    if (pfad == null || gesperrt || !flutterKannAnzeigen(pfad)) return null;
    return TextButton(
      onPressed: () => _sichten(pfad, gesperrt: gesperrt),
      child: Text(AppTexte.of(context).integAnsehen),
    );
  }

  /// Das Bild fuer die Rueckfrage – oder `null`, wenn es keines gibt.
  Widget? _bestaetigungsbild(String? pfad, {required bool gesperrt}) {
    if (pfad == null || gesperrt || !flutterKannAnzeigen(pfad)) return null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Image(
        image: begrenztesBild(widget.library.paths.absolute(pfad), kante: 440),
        height: 220,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _removeMissingFromDb(MissingFileIssue issue) async {
    final sicht = _vorschauFuer(issue);
    final confirmed = await confirmDialog(
      context,
      AppTexte.of(context).integAusDbEntfernenTitel,
      vorschau: _bestaetigungsbild(sicht?.pfad,
          gesperrt: sicht?.gesperrt ?? false),
      switch (issue.kind) {
        MissingFileKind.original =>
          AppTexte.of(context).integOriginalFehlt,
        MissingFileKind.mask => AppTexte.of(context).integMaskeFehlt,
        MissingFileKind.faceCrop =>
          AppTexte.of(context).integCropFehlt,
        _ => AppTexte.of(context).integPfadEntfernt,
      },
    );
    if (!confirmed) return;

    switch (issue.kind) {
      case MissingFileKind.original:
        await widget.library.db.deleteAssetRows([issue.ownerId]);
      case MissingFileKind.thumbnail:
        await widget.library.db.clearMissingThumbnailPath(issue.ownerId);
      case MissingFileKind.preview:
        await widget.library.db.clearMissingPreviewPath(issue.ownerId);
      case MissingFileKind.developed:
        await widget.library.db.clearMissingDevelopedPath(issue.ownerId);
      case MissingFileKind.restored:
        await widget.library.db.clearMissingRestoredPath(issue.ownerId);
      case MissingFileKind.trimmed:
        await widget.library.db.clearMissingTrimmedPath(issue.ownerId);
      case MissingFileKind.faceCrop:
        await widget.library.db.clearMissingFaceCropPath(issue.ownerId);
      case MissingFileKind.mask:
        await widget.library.db.deleteDevelopMask(int.parse(issue.ownerId));
    }
    if (!mounted) return;
    setState(() => _report = _withoutMissing(_report!, issue));
  }

  Future<void> _deleteOrphanedFile(OrphanedFileIssue issue) async {
    final confirmed = await confirmDialog(
      context,
      AppTexte.of(context).integDateiLoeschenTitel,
      AppTexte.of(context).integDateiLoeschenText(issue.relativePath),
      vorschau: _bestaetigungsbild(issue.relativePath, gesperrt: false),
    );
    if (!confirmed) return;
    await widget.library.paths.deletePermanently(issue.relativePath);
    if (!mounted) return;
    setState(() => _report = _withoutOrphan(_report!, issue));
  }

  /// Löscht alle verwaisten Dateien auf einmal.
  ///
  /// Ohne diesen Weg gab es nur den Knopf je Zeile. Das reicht für die
  /// Handvoll Fälle, für die die Prüfung gedacht war – aber ein einziges
  /// „alle Fotos erneut scannen" hinterließ in der Prüfbibliothek 17 643
  /// verwaiste Gesichtsausschnitte (Prüfrunde 8; die Ursache ist inzwischen
  /// behoben, die Altlast bleibt). 17 643 Mal einzeln bestätigen ist kein
  /// Weg, den jemand geht.
  Future<void> _deleteAllOrphaned() async {
    final report = _report;
    if (report == null || report.orphanedFiles.isEmpty) return;
    final t = AppTexte.of(context);
    final bytes = report.orphanedFiles.fold<int>(0, (s, i) => s + i.sizeBytes);
    final confirmed = await confirmDialog(
      context,
      t.integAlleVerwaistenTitel,
      t.integAlleVerwaistenText(report.orphanedFiles.length, _groesse(bytes)),
    );
    if (!confirmed) return;
    var geloescht = 0;
    for (final issue in report.orphanedFiles) {
      try {
        await widget.library.paths.deletePermanently(issue.relativePath);
        geloescht++;
      } catch (e) {
        debugPrint('Verwaiste Datei ${issue.relativePath} nicht löschbar: $e');
      }
    }
    if (!mounted) return;
    setState(() => _report = IntegrityCheckReport(
          missingFiles: report.missingFiles,
          orphanedFiles: const [],
          checksumMismatches: report.checksumMismatches,
          encryptedHeaderIssues: report.encryptedHeaderIssues,
          filesScanned: report.filesScanned,
        ));
    melde.erfolg(AppTexte.of(context).integVerwaisteGeloescht(geloescht));
  }

  static String _groesse(int bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB'
      : '${(bytes / 1024 / 1024).round()} MB';

  IntegrityCheckReport _withoutMissing(IntegrityCheckReport report, MissingFileIssue issue) =>
      IntegrityCheckReport(
        missingFiles: report.missingFiles.where((i) => i != issue).toList(),
        orphanedFiles: report.orphanedFiles,
        checksumMismatches: report.checksumMismatches,
        encryptedHeaderIssues: report.encryptedHeaderIssues,
        filesScanned: report.filesScanned,
      );

  IntegrityCheckReport _withoutOrphan(IntegrityCheckReport report, OrphanedFileIssue issue) =>
      IntegrityCheckReport(
        missingFiles: report.missingFiles,
        orphanedFiles: report.orphanedFiles.where((i) => i != issue).toList(),
        checksumMismatches: report.checksumMismatches,
        encryptedHeaderIssues: report.encryptedHeaderIssues,
        filesScanned: report.filesScanned,
      );

  Future<void> _openAsset(String assetId) async {
    final asset = await widget.library.db.assetById(assetId);
    if (asset == null || !mounted) return;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: [asset],
        initialIndex: 0,
        paths: widget.library.paths,
        db: widget.library.db,
        library: widget.library,
      ),
    ));
  }

  /// Die Art der fehlenden Datei in der Oberflächensprache. Wie beim
  /// Modellkatalog wandert der Text nicht in die Aufzählung selbst –
  /// `MissingFileKind` stammt aus dem Dienst und kennt keinen Kontext.
  String _kindLabel(AppTexte t, MissingFileKind kind) => switch (kind) {
        MissingFileKind.original => t.integArtOriginal,
        MissingFileKind.thumbnail => t.integArtThumbnail,
        MissingFileKind.preview => t.integArtVorschau,
        MissingFileKind.developed => t.integArtEntwickelt,
        MissingFileKind.restored => t.integArtRestauriert,
        MissingFileKind.trimmed => t.integArtVideoZuschnitt,
        MissingFileKind.faceCrop => t.integArtGesichtsCrop,
        MissingFileKind.mask => t.integArtMaske,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppTexte.of(context).werkzIntegritaetTitel),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppTexte.of(context).integErneutPruefen,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppTexte.of(context).integPruefsummen),
              subtitle: Text(
                AppTexte.of(context).integPruefsummenHinweis,
              ),
              value: _verifyChecksums,
              onChanged: _loading
                  ? null
                  : (v) {
                      setState(() => _verifyChecksums = v ?? false);
                      _load();
                    },
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final report = _report;
    if (report == null) return const SizedBox.shrink();
    if (report.isClean) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(AppTexte.of(context).integKeineProbleme(report.filesScanned)),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (report.missingFiles.isNotEmpty)
          _Section(
            title: AppTexte.of(context).integFehlendeDateien(report.missingFiles.length),
            gesamt: report.missingFiles.length,
            children: [
              for (final issue in report.missingFiles.take(_maxZeilenJeAbschnitt))
                Builder(builder: (context) {
                  // Die Datei ist weg, die Zeile steht noch - zu sehen
                  // gibt es das Vorschaubild der Aufnahme.
                  final sicht = _vorschauFuer(issue);
                  final knopf =
                      _ansehenKnopf(sicht?.pfad, gesperrt: sicht?.gesperrt ?? false);
                  return ListTile(
                    leading: _zeilenbild(sicht?.pfad,
                        gesperrt: sicht?.gesperrt ?? false,
                        ersatz: Icons.error_outline,
                        farbe: context.semantik.warnung),
                    title: Text(issue.relativePath),
                    subtitle: Text(_kindLabel(AppTexte.of(context), issue.kind)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (knopf != null) knopf,
                        TextButton(
                          onPressed: () => _removeMissingFromDb(issue),
                          child: Text(AppTexte.of(context).integAusDbEntfernen),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        if (report.orphanedFiles.isNotEmpty)
          _Section(
            title: AppTexte.of(context).integVerwaisteDateien(report.orphanedFiles.length),
            gesamt: report.orphanedFiles.length,
            aktion: TextButton.icon(
              onPressed: _deleteAllOrphaned,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text(AppTexte.of(context).integAlleVerwaistenLoeschen),
            ),
            children: [
              for (final issue in report.orphanedFiles.take(_maxZeilenJeAbschnitt))
                Builder(builder: (context) {
                  // Hier ist es umgekehrt: Die Zeile fehlt, die Datei
                  // liegt da - zu sehen gibt es sie selbst.
                  final knopf =
                      _ansehenKnopf(issue.relativePath, gesperrt: false);
                  return ListTile(
                    leading: _zeilenbild(issue.relativePath,
                        gesperrt: false,
                        ersatz: Icons.help_outline,
                        farbe: context.semantik.warnung),
                    title: Text(issue.relativePath),
                    subtitle: Text('${(issue.sizeBytes / 1024).round()} KB'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (knopf != null) knopf,
                        TextButton(
                          onPressed: () => _deleteOrphanedFile(issue),
                          child: Text(AppTexte.of(context).integDateiLoeschen),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        if (report.checksumMismatches.isNotEmpty)
          _Section(
            title: AppTexte.of(context).integAbweichungen(report.checksumMismatches.length),
            gesamt: report.checksumMismatches.length,
            children: [
              for (final issue in report.checksumMismatches.take(_maxZeilenJeAbschnitt))
                ListTile(
                  leading: Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
                  title: Text(issue.relativePath),
                  subtitle: Text(AppTexte.of(context).integInhaltGeaendert),
                  trailing: TextButton(
                    onPressed: () => _openAsset(issue.assetId),
                    child: Text(AppTexte.of(context).integFotoOeffnen),
                  ),
                ),
            ],
          ),
        if (report.encryptedHeaderIssues.isNotEmpty)
          _Section(
            title: AppTexte.of(context).integHeaderProbleme(report.encryptedHeaderIssues.length),
            gesamt: report.encryptedHeaderIssues.length,
            children: [
              for (final issue in report.encryptedHeaderIssues.take(_maxZeilenJeAbschnitt))
                ListTile(
                  leading: Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
                  title: Text(issue.relativePath),
                  subtitle: Text(AppTexte.of(context).integBeschaedigt),
                ),
            ],
          ),
      ],
    );
  }
}

/// Wie viele Zeilen ein Abschnitt höchstens ausschreibt.
///
/// Die Liste baute bisher jeden Fund als fertige Zeile, auch wenn nur zwölf
/// davon ins Bild passten. Bei 17 643 verwaisten Dateien kostete allein das
/// Zusammenbauen 228 ms gegen 28 ms – ein sichtbares Stocken für Zeilen,
/// die niemand liest (Prüfrunde 8). Wer mehr sehen will, will in Wahrheit
/// nicht scrollen, sondern aufräumen; dafür gibt es den Sammelknopf.
const int _maxZeilenJeAbschnitt = 100;

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  /// Gesamtzahl der Funde – kann größer sein als [children.length], wenn
  /// die Liste gekappt wurde.
  final int gesamt;

  /// Optionale Sammelaktion neben der Überschrift.
  final Widget? aktion;

  const _Section({
    required this.title,
    required this.children,
    required this.gesamt,
    this.aktion,
  });

  @override
  Widget build(BuildContext context) {
    final rest = gesamt - children.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (aktion != null) aktion!,
              ],
            ),
          ),
          Card(
            child: Column(children: [
              ...children,
              if (rest > 0)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    AppTexte.of(context)
                        .integWeitereEintraege(rest, children.length),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
