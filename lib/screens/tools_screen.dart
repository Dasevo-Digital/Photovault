import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../l10n/app_localizations.dart';
import '../services/native_image_converter.dart';
import '../services/export_service.dart';
import '../services/secure_share_service.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'asset_viewer_screen.dart';
import 'automation_rules_screen.dart';
import 'background_tasks_screen.dart';
import 'camera_presets_screen.dart';
import 'export_presets_screen.dart';
import 'staubsuche_screen.dart';
import 'duplicates_screen.dart';
import 'integrity_check_screen.dart';
import 'library_health_screen.dart';
import 'ortsvorschlaege_screen.dart';
import 'stack_review_screen.dart';
import 'gpx_verortung_screen.dart';
import 'statistics_screen.dart';
import 'xmp_import_screen.dart';
import '../services/meldungsdienst.dart';
import '../widgets/pin_dialogs.dart';

/// Eigenständiger Bereich für Werkzeuge, die nicht Teil des normalen
/// Durchstöberns der Bibliothek sind: manueller Gesichts-Scan (inkl. der
/// Ähnlichkeitsschwelle für "Ähnliche mit auswählen" im Personen-Tab) sowie
/// die Duplikat-/Ähnlichkeitssuche.
class ToolsScreen extends StatefulWidget {
  final LibraryState library;
  const ToolsScreen({super.key, required this.library});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  late double _threshold = widget.library.faceSimilarityThreshold;
  // Ändert sich nie während der Laufzeit (native Fähigkeit des Rechners) –
  // einmalig statt inline in build() abgefragt, damit ein FutureBuilder
  // nicht bei jedem Rebuild neu in den Ladezustand zurückfällt.
  late final Future<({bool bereit, List<String> fehlende})>
      _bildwerkzeugstandFuture = NativeImageConverter.bildwerkzeugstand();

  /// Wie viele Serien darauf warten, zu Stapeln zu werden.
  ///
  /// **Warum die Zahl hier steht.** Die Erkennung findet an der echten
  /// Bibliothek 286 brauchbare Gruppen – und es gab null Stapel. Nicht
  /// weil die Erkennung nichts fände, sondern weil nirgends stand, dass
  /// da etwas wartet. Derselbe Befund wie bei den Bewertungen: die
  /// Maschinerie vollständig, der Weg dorthin unsichtbar.
  ///
  /// Der Lauf kostet an 6930 Einbettungen 240 ms in einem eigenen Isolat
  /// und läuft einmal beim Öffnen dieses Bildschirms.
  Future<int>? _serienzahl;

  /// Wie viele Buendel Ortsvorschlaege offen sind. Anders als bei den
  /// Serien ohne Vorrat: Die Rechnung kostet an der echten Bibliothek
  /// 2 ms, ein Zwischenspeicher waere hier nur eine zweite Wahrheit.
  Future<int>? _ortsvorschlagszahl;
  bool _shareImporting = false;

  @override
  void initState() {
    super.initState();
    _serienzahl = _zaehleSerien();
    _ortsvorschlagszahl = _zaehleOrtsvorschlaege();
  }

  Future<int> _zaehleOrtsvorschlaege() async {
    try {
      return (await widget.library.ortsvorschlagsbuendel()).length;
    } catch (e) {
      debugPrint('Ortsvorschlaege nicht ermittelt: $e');
      return 0;
    }
  }

  Future<int> _zaehleSerien() async {
    if (!widget.library.clipAvailable) return 0;
    try {
      // Aus dem Vorrat, nicht neu gerechnet: Die Zahl hier und die
      // Liste im Serienbildschirm sind dieselbe Auskunft, und sie
      // kostete bis hierher zweimal 260 ms je Rundgang.
      final gruppen = await widget.library.serienvorschlaegeGecacht();
      return gruppen.length;
    } catch (e) {
      debugPrint('Serienzahl nicht ermittelt: $e');
      return 0;
    }
  }

  /// Lädt alle noch unbewerteten Fotos/Videos und öffnet sie im Vollbild-
  /// Sichtungs-Modus (Culling). Zweiter Einstiegspunkt neben dem "Jetzt
  /// sichten"-Vorschlag direkt nach dem Import (siehe ImportProgressSheet).
  Future<void> _openCulling() async {
    final assets = await widget.library.db.assetsForCulling();
    if (!mounted) return;
    if (assets.isEmpty) {
      melde.hinweis(AppTexte.of(context).werkzKeineUnbewerteten);
      return;
    }
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: assets,
        initialIndex: 0,
        paths: widget.library.paths,
        db: widget.library.db,
        library: widget.library,
        onToggleFavorite: (a) =>
            widget.library.db.setFavorite(a.id, !a.isFavorite),
        cullingMode: true,
      ),
    ));
  }

  Future<void> _importSecurePackage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pvshare'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    final passphrase = await showEnterPassphraseDialog(context,
        title: AppTexte.of(context).sicherTeilenImportPassphrase);
    if (passphrase == null || !mounted) return;
    setState(() => _shareImporting = true);
    try {
      final service = SecureShareService(
          ExportService(widget.library.paths, library: widget.library));
      final imported = await service.importPackage(
          File(path), passphrase, widget.library.importService);
      if (mounted) {
        melde.erfolg(AppTexte.of(context)
            .sicherTeilenImportFertig(imported.imported, imported.duplicates));
      }
    } catch (error) {
      if (mounted) {
        melde.warnung(
            AppTexte.of(context).sicherTeilenImportFehler(error.toString()));
      }
    } finally {
      if (mounted) setState(() => _shareImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.navWerkzeuge)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // **Der Weg zu den Aufgaben steht ganz oben, und das ist der
          // Punkt dieser Seite.** Bis Fassung 2.2.4 standen fünfzehn
          // Durchgänge über die ganze Bibliothek doppelt in der App: hier
          // als Listeneinträge und in der Aufgabenverwaltung als Karten.
          // Zwei Oberflächen für dieselbe Arbeit heisst zwei Wege, sie zu
          // starten, zwei Orte, an denen ein Zusatz vergessen werden kann,
          // und für den Menschen die Frage, ob das hier dasselbe ist wie
          // dort. Was bleibt, sind Werkzeuge im Wortsinn: Ansichten,
          // Vorgaben, Prüfungen – nichts davon startet einen Durchgang.
          Card(
            child: ListTile(
              leading: const Icon(Icons.playlist_play_outlined),
              title: Text(t.aufgTitel),
              subtitle: Text(t.werkzZuAufgabenText),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BackgroundTasksScreen(library: widget.library),
              )),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: Text(t.gesundheitTitel),
              subtitle: Text(t.gesundheitWerkzeugText),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LibraryHealthScreen(library: widget.library),
              )),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_open_outlined),
              title: Text(t.sicherTeilenImportTitel),
              subtitle: Text(t.sicherTeilenImportText),
              isThreeLine: true,
              trailing: _shareImporting
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_open_outlined),
              onTap: _shareImporting ? null : _importSecurePackage,
            ),
          ),
          const SizedBox(height: 20),
          Text(t.werkzAbschnittStatistik,
              style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: Text(t.werkzAnalyseseiteTitel),
              subtitle: Text(t.werkzAnalyseseiteText),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => StatisticsScreen(library: widget.library)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(t.werkzAbschnittGesichtserkennung,
              style: Theme.of(context).textTheme.titleMedium),
          // Nur noch der Regler: Das Scannen selbst ist eine Aufgabe. Der
          // Regler dagegen ist eine Einstellung, die entscheidet, wie
          // gefundene Gesichter zu Personen zusammengelegt werden.
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(t.werkzSchwelleLabel,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Slider(
                          value: _threshold,
                          min: 0.15,
                          max: 0.6,
                          divisions: 18,
                          label: _threshold.toStringAsFixed(2),
                          onChanged: (v) => setState(() => _threshold = v),
                          // Erst beim Loslassen speichern: Das Schreiben
                          // rechnet zugleich die persönlichen Schwellen
                          // aller Personen neu (siehe
                          // AppDatabase.setFaceSimilarityThreshold) – bei
                          // jeder Reglerbewegung wäre das eine Datenbank-
                          // Transaktion pro Bild.
                          onChangeEnd: (v) =>
                              widget.library.setFaceSimilarityThreshold(v),
                        ),
                      ),
                      SizedBox(
                          width: 36,
                          child: Text(_threshold.toStringAsFixed(2))),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                  child: Text(
                    t.werkzSchwelleErklaerung,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(t.werkzAbschnittVorschau,
              style: Theme.of(context).textTheme.titleMedium),
          // Eine Auskunft, kein Vorgang: ob die Umwandlung für HEIC und RAW
          // überhaupt einsatzbereit ist. Das Erzeugen der Vorschaubilder
          // selbst ist eine Aufgabe.
          Card(
            child: FutureBuilder<({bool bereit, List<String> fehlende})>(
              future: _bildwerkzeugstandFuture,
              builder: (context, snapshot) {
                final stand = snapshot.data;
                final bereit = stand?.bereit ?? false;
                // Ausserhalb von macOS hängt die Umwandlung an externen
                // Werkzeugen, nicht an einer nativen Anbindung – dann muss
                // die Auskunft auch die Werkzeuge nennen statt auf eine
                // Swift-Datei zu verweisen, die es hier gar nicht gibt.
                final ueberWerkzeuge = !Platform.isMacOS;
                final text = bereit
                    ? (ueberWerkzeuge
                        ? t.werkzHeicWerkzeugeAktiv
                        : t.werkzHeicAktiv)
                    : (ueberWerkzeuge
                        ? t.werkzHeicWerkzeugeFehlen(
                            (stand?.fehlende ?? const <String>[]).join(', '))
                        : t.werkzHeicInaktiv);
                return ListTile(
                  leading: Icon(
                    bereit ? Icons.check_circle_outline : Icons.error_outline,
                    color: bereit
                        ? context.semantik.erfolg
                        : context.semantik.warnung,
                  ),
                  title: Text(t.werkzHeicTitel),
                  subtitle: Text(text),
                  isThreeLine: true,
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Text(t.werkzAbschnittOrte,
              style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: ListTile(
              leading: const Icon(Icons.route_outlined),
              title: Text(t.werkzGpxTitel),
              subtitle: Text(t.werkzGpxText),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GpxVerortungScreen(library: widget.library),
              )),
            ),
          ),
          const SizedBox(height: 20),
          Text(t.werkzAbschnittKamera,
              style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: Text(t.werkzPresetsTitel),
                  subtitle: Text(t.werkzPresetsText),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            CameraPresetsScreen(library: widget.library)),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_size_select_large_outlined),
                  title: Text(t.werkzExportVorgabenTitel),
                  subtitle: Text(t.werkzExportVorgabenText),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            ExportPresetsScreen(library: widget.library)),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.blur_circular_outlined),
                  title: Text(t.staubTitel),
                  subtitle: Text(t.werkzStaubText),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            StaubsucheScreen(library: widget.library)),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.rule_outlined),
                  title: Text(t.werkzRegelnTitel),
                  subtitle: Text(t.werkzRegelnText),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            AutomationRulesScreen(library: widget.library)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(t.werkzAbschnittBibliothek,
              style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.rate_review_outlined),
                  title: Text(t.werkzSichtenTitel),
                  subtitle: Text(t.werkzSichtenText),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openCulling,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.compare_outlined),
                  title: Text(t.werkzDuplikateTitel),
                  subtitle: Text(t.werkzDuplikateText),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            DuplicatesScreen(library: widget.library)),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.filter_none_outlined),
                  title: Text(t.werkzStapelTitel),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.werkzStapelText),
                      // Die Zahl als Zeichen rechts ist auf einen Blick zu
                      // sehen; was sie bedeutet, muss trotzdem dastehen.
                      FutureBuilder<int>(
                        future: _serienzahl,
                        builder: (context, schnappschuss) {
                          final zahl = schnappschuss.data ?? 0;
                          if (zahl == 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              t.werkzStapelGefunden(zahl),
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FutureBuilder<int>(
                        future: _serienzahl,
                        builder: (context, schnappschuss) {
                          final zahl = schnappschuss.data;
                          if (zahl == null || zahl == 0) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding:
                                const EdgeInsets.only(right: AppSpacing.sm),
                            child: Badge(label: Text('$zahl')),
                          );
                        },
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            StackReviewScreen(library: widget.library)));
                    if (mounted) setState(() => _serienzahl = _zaehleSerien());
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.where_to_vote_outlined),
                  title: Text(t.ortVorschlagWerkzTitel),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.ortVorschlagWerkzText),
                      FutureBuilder<int>(
                        future: _ortsvorschlagszahl,
                        builder: (context, schnappschuss) {
                          final zahl = schnappschuss.data ?? 0;
                          if (zahl == 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              t.ortVorschlagAlleUebernehmen(zahl),
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FutureBuilder<int>(
                        future: _ortsvorschlagszahl,
                        builder: (context, schnappschuss) {
                          final zahl = schnappschuss.data;
                          if (zahl == null || zahl == 0) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding:
                                const EdgeInsets.only(right: AppSpacing.sm),
                            child: Badge(label: Text('$zahl')),
                          );
                        },
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            OrtsvorschlaegeScreen(library: widget.library)));
                    if (mounted) {
                      setState(
                          () => _ortsvorschlagszahl = _zaehleOrtsvorschlaege());
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text(t.werkzIntegritaetTitel),
                  subtitle: Text(t.werkzIntegritaetText),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            IntegrityCheckScreen(library: widget.library)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(t.werkzAbschnittInterop,
              style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: Text(t.werkzXmpLesenTitel),
              subtitle: Text(t.werkzXmpLesenText),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => XmpImportScreen(library: widget.library)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
