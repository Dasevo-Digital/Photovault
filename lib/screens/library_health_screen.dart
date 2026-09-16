import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_paths.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'background_tasks_screen.dart';
import 'home_shell.dart' show Hauptbereich;
import 'integrity_check_screen.dart';
import 'ortsvorschlaege_screen.dart';
import 'vorschlaege_screen.dart';

class LibraryHealthScreen extends StatefulWidget {
  const LibraryHealthScreen({super.key, required this.library});

  final LibraryState library;

  @override
  State<LibraryHealthScreen> createState() => _LibraryHealthScreenState();
}

class _LibraryHealthState {
  const _LibraryHealthState({
    required this.databaseOk,
    required this.backup,
    required this.pendingBackup,
    required this.imageCount,
    required this.videoCount,
    required this.modelsReady,
    required this.modelsTotal,
    required this.ortsvorschlaege,
    required this.offeneGesichter,
    required this.auffaelligeDaten,
    required this.videoZweitblick,
    required this.vorschlaege,
    required this.beiseiteNieVerglichen,
  });

  final bool databaseOk;
  final BackupSettingsData? backup;
  final int pendingBackup;
  final int imageCount;
  final int videoCount;
  final int modelsReady;
  final int modelsTotal;

  /// Was an Arbeit bereitliegt, ohne dass jemand danach fragen muss.
  final int ortsvorschlaege;
  final int offeneGesichter;
  final int auffaelligeDaten;
  final int videoZweitblick;
  final int vorschlaege;

  /// Die stille Luecke: Was beiseiteliegt, sieht der Lauf nach dem
  /// Import nicht an – und ohne Vorschlag gibt es auch keine Karte.
  final int beiseiteNieVerglichen;
}

class _LibraryHealthScreenState extends State<LibraryHealthScreen> {
  late Future<_LibraryHealthState> _state = _load();

  /// **Getrennt geladen, und das ist der Grund.** Alle elf Abfragen an
  /// der Datenbank kosten zusammen 63 ms; das Aufaddieren der Belegung
  /// laeuft ueber die ganze Bibliothek auf der Platte und kostete an der
  /// echten **1372 ms warm und 2788 ms kalt** (91 GB). Beides in einem
  /// `Future.wait` heisst: Der Bildschirm, den man aufschlaegt, um zu
  /// sehen ob etwas nicht stimmt, zeigt anderthalb Sekunden lang einen
  /// Kreisel.
  late Future<Bibliotheksbelegung> _belegung = widget.library.paths.belegung();
  bool _cleaning = false;

  Future<_LibraryHealthState> _load() async {
    final values = await Future.wait<Object?>([
      widget.library.db.databaseQuickCheck(),
      widget.library.db.backupSettingsRow(),
      widget.library.db.countNotAutoBackedUp(),
      widget.library.db.countAssetsOfType('IMAGE'),
      widget.library.db.countAssetsOfType('VIDEO'),
      widget.library.db.countOrtsvorschlagskandidaten(),
      widget.library.db.countOffeneGesichter(),
      widget.library.db.countAuffaelligeAufnahmedaten(),
      widget.library.db.countVideoZweitblick(),
      widget.library.db.countVorschlaege(),
      widget.library.db.countBeiseiteNieVerglichen(),
    ]);
    final models = [
      widget.library.clipAvailable,
      widget.library.faceDetectionAvailable,
      widget.library.faceRecognitionAvailable,
      widget.library.segmentationAvailable,
      widget.library.captioningAvailable,
      widget.library.ocrAvailable,
      widget.library.geoDataAvailable,
    ];
    return _LibraryHealthState(
      databaseOk: values[0] as bool,
      backup: values[1] as BackupSettingsData?,
      pendingBackup: values[2] as int,
      imageCount: values[3] as int,
      videoCount: values[4] as int,
      modelsReady: models.where((ready) => ready).length,
      modelsTotal: models.length,
      ortsvorschlaege: values[5] as int,
      offeneGesichter: values[6] as int,
      auffaelligeDaten: values[7] as int,
      videoZweitblick: values[8] as int,
      vorschlaege: values[9] as int,
      beiseiteNieVerglichen: values[10] as int,
    );
  }

  void _refresh() => setState(() {
        _state = _load();
        _belegung = widget.library.paths.belegung();
      });

  /// Fuehrt zur Aufgabenliste und hebt dort die gemeinte Karte hervor.
  ///
  /// Nach der Rueckkehr wird neu gezaehlt: Wer den Lauf angestossen hat,
  /// soll die Karte hier nicht unveraendert wiederfinden.
  Future<void> _zeigeAufgabe(String schluessel) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BackgroundTasksScreen(
          library: widget.library,
          hervorheben: schluessel,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _cleanTemporaryFiles() async {
    if (_cleaning) return;
    setState(() => _cleaning = true);
    final result = await widget.library.bereinigeTemporareDateien();
    if (!mounted) return;
    setState(() {
      _cleaning = false;
      _state = _load();
      // Aufgeraeumt wurde auf der Platte – die Belegung ist danach eine
      // andere.
      _belegung = widget.library.paths.belegung();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppTexte.of(context)
          .gesundheitBereinigt(result.dateien, _bytes(result.bytes))),
    ));
  }

  String _bytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  String _date(BuildContext context, DateTime date) =>
      DateFormat.yMd(Localizations.localeOf(context).toString())
          .add_Hm()
          .format(date);

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.gesundheitTitel),
        actions: [
          IconButton(
            tooltip: t.gesundheitAktualisieren,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_LibraryHealthState>(
        future: _state,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          final state = snapshot.data;
          if (state == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final backup = state.backup;
          final backupEnabled = backup?.autoBackupEnabled ?? false;
          final backupOk = backupEnabled &&
              backup?.lastAutoBackupAt != null &&
              state.pendingBackup == 0;
          final colors = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(t.gesundheitEinleitung,
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: AppSpacing.lg),
              _StatusCard(
                icon: state.databaseOk
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                color:
                    state.databaseOk ? context.semantik.erfolg : colors.error,
                title: t.gesundheitDatenbank,
                text: state.databaseOk
                    ? t.gesundheitDatenbankOk
                    : t.gesundheitDatenbankFehler,
                action: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          IntegrityCheckScreen(library: widget.library),
                    ),
                  ),
                  child: Text(t.gesundheitIntegritaetOeffnen),
                ),
              ),
              _StatusCard(
                icon: backupOk
                    ? Icons.cloud_done_outlined
                    : Icons.backup_outlined,
                color: backupOk
                    ? context.semantik.erfolg
                    : context.semantik.warnung,
                title: t.gesundheitSicherung,
                text: !backupEnabled
                    ? t.gesundheitSicherungAus
                    : backup?.lastAutoBackupAt == null
                        ? t.gesundheitSicherungNie
                        : '${t.gesundheitLetzteSicherung(_date(context, backup!.lastAutoBackupAt!))}\n'
                            '${t.gesundheitSicherungOffen(state.pendingBackup)}',
              ),
              // Die Zahl der Aufnahmen steht sofort; was auf der Platte
              // liegt, kommt nach. Die Karte wartet nicht auf den
              // Plattendurchlauf – siehe [_belegung].
              FutureBuilder<Bibliotheksbelegung>(
                future: _belegung,
                builder: (context, belegung) => _StatusCard(
                  icon: Icons.storage_outlined,
                  color: colors.primary,
                  title: t.gesundheitSpeicher,
                  text: belegung.hasData
                      ? '${_bytes(belegung.data!.gesamt)} · ${t.gesundheitMedien(state.imageCount, state.videoCount)}'
                      : '${t.gesundheitSpeicherWirdGezaehlt} · ${t.gesundheitMedien(state.imageCount, state.videoCount)}',
                  details: [
                    if (belegung.hasData)
                      for (final part in belegung.data!.posten)
                        '${part.name}: ${_bytes(part.bytes)}',
                  ],
                  action: FilledButton.tonalIcon(
                  onPressed: _cleaning ? null : _cleanTemporaryFiles,
                  icon: _cleaning
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.cleaning_services_outlined),
                    label: Text(t.gesundheitBereinigen),
                  ),
                ),
              ),
              // **Warum das hier steht.** An dieser Bibliothek warteten 408
              // erbbare Orte und 1658 unzugeordnete Gesichter – nicht weil
              // die Werkzeuge fehlten (beide gibt es, und beide arbeiten in
              // Gruppen), sondern weil nirgends stand, dass etwas wartet.
              // Ein Bildschirm, der den Zustand der Bibliothek meldet, ist
              // dafür der richtige Ort.
              if (state.ortsvorschlaege > 0)
                _StatusCard(
                  icon: Icons.add_location_alt_outlined,
                  color: context.semantik.warnung,
                  title: t.gesundheitOrteTitel,
                  text: t.gesundheitOrteOffen(state.ortsvorschlaege),
                  action: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            OrtsvorschlaegeScreen(library: widget.library),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(t.gesundheitOrteAnsehen),
                  ),
                ),
              if (state.offeneGesichter > 0)
                _StatusCard(
                  icon: Icons.face_retouching_natural_outlined,
                  color: context.semantik.warnung,
                  title: t.gesundheitGesichterTitel,
                  text: t.gesundheitGesichterOffen(state.offeneGesichter),
                  action: FilledButton.tonalIcon(
                    // Das Gruppieren lebt im Personen-Bereich und zieht
                    // einen eigenen Fortschritt auf; es hier ein zweites
                    // Mal zu bauen waere dieselbe Maschine zweimal.
                    onPressed: () =>
                        widget.library.zeigeBereich(Hauptbereich.personen),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(t.gesundheitGesichterZuordnen),
                  ),
                ),
              // **Die zweite Hälfte desselben Gedankens.** Die beiden
              // Karten darüber kamen, weil Arbeit bereitlag, von der
              // nirgends stand, dass sie wartet. An derselben Bibliothek
              // hatten von den drei Auswertungen der 7. Auflage genau die
              // beiden ohne Karte **noch nie gelaufen**: kein einziges
              // geschätztes Datum, keine einzige Videoeinbettung – bei
              // 1097 auffälligen Zeitstempeln und 219 langen Videos.
              //
              // Die Zahlen hier sind **enger** als die der Aufgabenliste:
              // Dort steht „betrifft 8098" bzw. „429", weil der Lauf so
              // viele ansieht. Ändern wird er nur bei diesen hier etwas,
              // und eine Zahl, die mehr verspricht als dahinter steht,
              // ist schlimmer als keine.
              // Die Wiedererkennung laeuft von selbst nach jedem Import
              // – gerade deshalb gehoert ihr Ergebnis hierher. Ein
              // Vorschlag, den niemand zu sehen bekommt, ist dasselbe wie
              // kein Vorschlag; genau daran sind die 14.065 von Hand
              // beiseitegelegten Gesichter entstanden.
              if (state.vorschlaege > 0)
                _StatusCard(
                  icon: Icons.person_search_outlined,
                  color: context.semantik.warnung,
                  title: t.gesundheitVorschlaegeTitel,
                  text: t.gesundheitVorschlaegeOffen(state.vorschlaege),
                  action: FilledButton.tonalIcon(
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            VorschlaegeScreen(library: widget.library),
                      ));
                      if (mounted) _refresh();
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(t.gesundheitVorschlaegeAnsehen),
                  ),
                ),
              // **Nur, solange nichts verglichen wurde.** Danach steht
              // das Ergebnis in der Karte darueber – oder es gab keins.
              if (state.vorschlaege == 0 && state.beiseiteNieVerglichen > 0)
                _StatusCard(
                  icon: Icons.visibility_off_outlined,
                  color: colors.primary,
                  title: t.gesundheitBeiseiteTitel,
                  text: t.gesundheitBeiseiteOffen(state.beiseiteNieVerglichen),
                  action: FilledButton.tonalIcon(
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => VorschlaegeScreen(
                            library: widget.library, beiseiteZuerst: true),
                      ));
                      if (mounted) _refresh();
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(t.gesundheitBeiseiteAnsehen),
                  ),
                ),
              if (state.auffaelligeDaten > 0)
                _StatusCard(
                  icon: Icons.event_busy_outlined,
                  color: context.semantik.warnung,
                  title: t.gesundheitDatumTitel,
                  text: t.gesundheitDatumOffen(state.auffaelligeDaten),
                  action: FilledButton.tonalIcon(
                    onPressed: () => _zeigeAufgabe('datumsherkunft'),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(t.gesundheitDatumPruefen),
                  ),
                ),
              if (state.videoZweitblick > 0)
                _StatusCard(
                  icon: Icons.video_library_outlined,
                  color: context.semantik.warnung,
                  title: t.gesundheitVideobilderTitel,
                  text: t.gesundheitVideobilderOffen(state.videoZweitblick),
                  action: FilledButton.tonalIcon(
                    onPressed: () => _zeigeAufgabe('videobilder'),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(t.gesundheitVideobilderHolen),
                  ),
                ),
              _StatusCard(
                icon: state.modelsReady == state.modelsTotal
                    ? Icons.memory_outlined
                    : Icons.downloading_outlined,
                color: state.modelsReady == state.modelsTotal
                    ? context.semantik.erfolg
                    : context.semantik.warnung,
                title: t.gesundheitModelle,
                text: t.gesundheitModelleStand(
                    state.modelsReady, state.modelsTotal),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    this.details = const [],
    this.action,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final List<String> details;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(text),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.xs,
                        children: [
                          // Untereinander stehende Groessen: mit
                          // Tabellenziffern bleiben die Kommastellen in
                          // einer Flucht (siehe [Tabellenziffern]).
                          for (final detail in details)
                            Text(detail,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall!
                                    .mitTabellenziffern),
                        ],
                      ),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      action!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
