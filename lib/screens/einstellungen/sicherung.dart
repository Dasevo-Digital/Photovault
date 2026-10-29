import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:kern/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../services/backup_service.dart';
import '../../services/backup_verification_service.dart';
import '../../services/meldungsdienst.dart';
import '../../services/platform/folder_access.dart';
import '../../services/sicherungsziel.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pin_dialogs.dart';
import '../../widgets/progress_dialog.dart';
import 'einstellungsstand.dart';
import 'gemeinsam.dart';
import 'backup_probe_status.dart';

/// Die Passphrase, mit der Sicherungen verschlüsselt werden.
class SicherungsschluesselGruppe extends StatelessWidget {
  const SicherungsschluesselGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Card(
        child: FutureBuilder<bool>(
          future: stand.hasBackupKeyFuture,
          builder: (context, snapshot) {
            final hasKey = snapshot.data ?? false;
            if (!hasKey) {
              return ListTile(
                leading: const Icon(Icons.enhanced_encryption_outlined),
                title: Text(AppTexte.of(context).einstPassphraseEinrichten),
                subtitle: Text(
                  AppTexte.of(context).einstBackupVerschluesselungText,
                ),
                isThreeLine: true,
                trailing: FilledButton(
                  onPressed: () => _setupBackupPassphrase(stand),
                  child: Text(AppTexte.of(context).allgEinrichten),
                ),
              );
            }
            final unlocked = stand.library.backupKeyAvailableThisSession;
            return Column(
              children: [
                ListTile(
                  leading: Icon(
                    unlocked ? Icons.lock_open_outlined : Icons.lock_outline,
                  ),
                  title: Text(AppTexte.of(context).einstBackupPassphrase),
                  subtitle: Text(
                    unlocked
                        ? AppTexte.of(context).einstBackupEntsperrt
                        : AppTexte.of(context).einstBackupGesperrt,
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _changeBackupPassphrase(stand),
                          child: Text(AppTexte.of(context).einstBackupAendern),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _removeBackupEncryption(stand),
                          child: Text(AppTexte.of(context).allgEntfernen),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

/// Sichern, Wiederherstellen und Prüfen von Hand.
class SicherungVonHandGruppe extends StatelessWidget {
  const SicherungVonHandGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(AppTexte.of(context).einstLetztesBackup),
              subtitle: Text(
                stand.lastBackup == null
                    ? AppTexte.of(context).einstBackupNieGesichert
                    : AppTexte.of(context).einstBackupZusammenfassung(
                        datumText(context, stand.lastBackup!.performedAt),
                        stand.lastBackup!.fileCount,
                        stand.lastBackup!.destinationPath,
                      ),
              ),
            ),
            const Divider(height: 1),
            CheckboxListTile(
              value: stand.encryptManualBackup,
              onChanged: (v) =>
                  stand.aendere(() => stand.encryptManualBackup = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(AppTexte.of(context).einstBackupVerschluesseln),
              subtitle: Text(AppTexte.of(context).einstBackupPassphraseAbfrage),
            ),
            // Was mitkommt und was nicht. Der Hinweis stand nirgends, und
            // der Unterschied ist erheblich: Ohne Passphrase liegt kein
            // Schnappschuss der Datenbank in der Sicherung, und damit
            // kämen Personen, Stammbaum, Reisen und Aktivitäten beim
            // Zurückspielen nicht wieder (Befund der 19. Prüfrunde).
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                AppTexte.of(context).einstBackupManuellHinweis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _runBackup(stand),
                      icon: const Icon(Icons.backup_outlined),
                      label: Text(AppTexte.of(context).einstJetztSichern),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _runRestore(stand),
                      icon: const Icon(Icons.settings_backup_restore),
                      label: Text(AppTexte.of(context).einstWiederherstellen),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _pruefeBackup(stand),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(AppTexte.of(context).einstBackupPruefen),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _pruefeWiederherstellung(stand),
              icon: const Icon(Icons.restore_outlined),
              label: Text(AppTexte.of(context).backupProbeStarten),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Text(
                AppTexte.of(context).einstBackupZielHinweis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Die automatische Sicherung: Ziel, Abstand, Menge je Lauf.
class AutomatischeSicherungGruppe extends StatelessWidget {
  const AutomatischeSicherungGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          AppTexte.of(context).einstBackupAutoHinweis,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Card(
        child: FutureBuilder<BackupSettingsData?>(
          future: stand.backupSettingsFuture,
          builder: (context, snapshot) {
            final config = snapshot.data;
            final enabled = config?.autoBackupEnabled ?? false;
            final destination = config?.autoBackupDestination;
            final intervalHours = config?.autoBackupIntervalHours ?? 24;
            final maxMbPerRun = config?.autoBackupMaxMbPerRun ?? 0;
            final lastRun = config?.lastAutoBackupAt;
            final keyReady = stand.library.backupKeyAvailableThisSession;

            return Column(
              children: [
                SwitchListTile(
                  value: enabled,
                  onChanged: destination == null
                      ? null
                      : (v) async {
                          await stand.library.db.setAutoBackupConfig(
                            enabled: v,
                          );
                          if (stand.aktiv) stand.reloadBackupSettings();
                        },
                  title: Text(AppTexte.of(context).allgAktiv),
                  subtitle: Text(
                    destination ?? AppTexte.of(context).einstBackupZuerstZiel,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(AppTexte.of(context).einstZielordner),
                  subtitle: Text(
                    destination ?? AppTexte.of(context).einstBackupKeinOrdner,
                  ),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      // Mit Merkmal: Unter macOS hielt der Zugriff auf
                      // einen nur per Pfad gemerkten Ordner bis zum
                      // nächsten Start (#211, siehe Sicherungsziel).
                      final picked = await FolderAccess.forCurrentPlatform()
                          .pickFolder(
                            message: AppTexte.of(
                              context,
                            ).einstBackupAutoZielWaehlen,
                          );
                      if (picked == null) return;
                      await Sicherungsziel.merke(picked.path, picked.token);
                      await stand.library.db.setAutoBackupConfig(
                        enabled: enabled,
                        destination: picked.path,
                      );
                      if (stand.aktiv) stand.reloadBackupSettings();
                    },
                    child: Text(AppTexte.of(context).einstWaehlen),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: Text(AppTexte.of(context).einstIntervall),
                  trailing: DropdownButton<int>(
                    value: intervalHours,
                    items: [
                      DropdownMenuItem(
                        value: 1,
                        child: Text(AppTexte.of(context).einstStuendlich),
                      ),
                      DropdownMenuItem(
                        value: 6,
                        child: Text(
                          AppTexte.of(context).einstIntervallSechsStunden,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 24,
                        child: Text(AppTexte.of(context).einstTaeglich),
                      ),
                      DropdownMenuItem(
                        value: 168,
                        child: Text(AppTexte.of(context).einstWoechentlich),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      await stand.library.db.setAutoBackupConfig(
                        enabled: enabled,
                        intervalHours: v,
                      );
                      if (stand.aktiv) stand.reloadBackupSettings();
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: Text(
                    AppTexte.of(context).einstBackupGenerationenTitel,
                  ),
                  subtitle: Text(
                    AppTexte.of(context).einstBackupGenerationenText,
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.speed_outlined),
                  title: Text(AppTexte.of(context).einstMengeJeLauf),
                  subtitle: Text(
                    AppTexte.of(context).einstBackupGrenzeText,
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                  trailing: DropdownButton<int>(
                    value: maxMbPerRun,
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(AppTexte.of(context).einstUnbegrenzt),
                      ),
                      const DropdownMenuItem(value: 500, child: Text('500 MB')),
                      const DropdownMenuItem(value: 2000, child: Text('2 GB')),
                      const DropdownMenuItem(
                        value: 10000,
                        child: Text('10 GB'),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      await stand.library.db.setAutoBackupMaxMbPerRun(v);
                      if (stand.aktiv) stand.reloadBackupSettings();
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(AppTexte.of(context).einstLetzterLauf),
                  subtitle: Text(
                    lastRun == null
                        ? AppTexte.of(context).einstNieAusgefuehrt
                        : datumZeitText(context, lastRun),
                  ),
                ),
                if (destination != null)
                  BackupProbeStatus(
                    dienst: stand.library.backupService,
                    ziel: destination,
                    letzterLauf: lastRun,
                  ),
                if (enabled && !keyReady)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xs,
                    ),
                    child: Text(
                      AppTexte.of(context).einstBackupPassphraseGesperrt,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.semantik.warnung,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: destination == null
                          ? null
                          : () => _runAutoBackupNow(stand),
                      icon: const Icon(Icons.sync),
                      label: Text(
                        AppTexte.of(context).einstJetztSynchronisieren,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

/// Die Zeile im Fortschrittsfenster der Wiederherstellung.
///
/// Die Übernahme aus dem Datenbank-Schnappschuss muss dastehen: Sie ist
/// der Unterschied zwischen „die Fotos sind zurück" und „die Bibliothek
/// ist zurück", und ohne ein Wort dazu bemerkt man erst Tage später, dass
/// die Namen an den Gesichtern fehlen.
String _wiederherstellZeile(AppTexte t, BackupProgress p) {
  if (p.uebernommeneZeilen != null) {
    return t.backupUebernommen(p.uebernommeneZeilen!);
  }
  if (p.ausschnitteNeu) {
    return '${t.backupAusschnitteNeu}  ${p.done} / ${p.total}';
  }
  return '${p.done} / ${p.total}'
      '${p.currentFile != null ? ' — ${p.currentFile}' : ''}';
}

/// Eine Zeile Backup-Fortschritt.
///
/// Der Dienst meldet nur Zahlen und Dateinamen; ob die Mengenbegrenzung
/// gegriffen hat, steht als Zahl in [BackupProgress.grenzeOffen] und wird
/// erst hier zu einem Satz.
String _backupZeile(AppTexte t, BackupProgress p) {
  if (p.wiederherstellungsprobe case final probe?) {
    return backupProbeTextMit(
      t,
      probe,
      (d) => DateFormat.yMd().add_Hm().format(d),
    );
  }
  if (p.fehlgeschlagen != null) {
    return t.backupNichtGesichert(p.fehlgeschlagen!);
  }
  if (p.grenzeOffen != null) return t.backupGrenzeErreicht(p.grenzeOffen!);
  return '${p.done} / ${p.total}'
      '${p.currentFile != null ? ' — ${p.currentFile}' : ''}';
}

String _backupPruefZeile(AppTexte t, BackupPrueffortschritt p) {
  if (p.abgeschlossen) {
    return p.erfolgreich
        ? t.einstBackupPruefungErfolgreich(p.gueltig)
        : t.einstBackupPruefungFehler(p.gueltig, p.fehlend, p.beschaedigt);
  }
  return '${p.erledigt} / ${p.gesamt}'
      '${p.datei != null ? ' — ${p.datei}' : ''}';
}

Future<void> _runBackup(Einstellungsstand stand) async {
  final context = stand.kontext;
  if (stand.encryptManualBackup) {
    final ok = await ensureBackupKeyAvailable(context, stand.library);
    if (!ok || !context.mounted) return;
  }
  final destination = await FilePicker.getDirectoryPath(
    dialogTitle: AppTexte.of(context).einstBackupZielWaehlen,
  );
  if (destination == null || !context.mounted) return;
  final t = AppTexte.of(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ProgressDialog(
      title: AppTexte.of(context).einstBackupSichertLaeuft,
      stream: stand.library
          .runManualBackup(destination, encrypt: stand.encryptManualBackup)
          .map((p) => _backupZeile(t, p)),
    ),
  );
  stand.refresh();
}

Future<void> _runRestore(Einstellungsstand stand) async {
  final context = stand.kontext;
  final source = await FilePicker.getDirectoryPath(
    dialogTitle: AppTexte.of(context).einstBackupOrdnerWaehlen,
  );
  if (source == null || !context.mounted) return;

  final wurzel = await BackupPruefdienst.findeBackupWurzel(source);
  String? passphrase;
  if (await File(p.join(wurzel, 'vault.key')).exists()) {
    if (!context.mounted) return;
    passphrase = await showEnterPassphraseDialog(
      context,
      title: AppTexte.of(context).einstBackupPassphraseEingeben,
    );
    if (passphrase == null) return;
  }

  final generationen = await stand.library.backupService.autoBackupGenerations(
    wurzel,
  );
  if (!context.mounted) return;
  final generation = await _waehleWiederherstellungspunkt(stand, generationen);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      // Die Texte einmal hier holen und nicht im Rückruf des Stroms: Der
      // läuft später, und der Prüfer nimmt den Kontext dann zu Recht
      // nicht mehr an.
      final t = AppTexte.of(dialogContext);
      return ProgressDialog(
        title: t.einstBackupWiederherstellenLaeuft,
        fehlerText: (e) => fehlertext(dialogContext, e),
        stream: stand.library.backupService
            .restoreFromBackup(
              wurzel,
              stand.library.importService,
              passphrase: passphrase,
              generationSnapshotPath: generation?.snapshotPath,
            )
            .map((p) => _wiederherstellZeile(t, p)),
      );
    },
  );
  stand.refresh();
}

/// Gibt `null` für den aktuellen Datenbankstand zurück. Bei manuellen
/// Backups existieren keine Generationen; dann bleibt der zusätzliche
/// Dialog bewusst aus dem Weg.
Future<BackupGeneration?> _waehleWiederherstellungspunkt(
  Einstellungsstand stand,
  List<BackupGeneration> generationen,
) async {
  final context = stand.kontext;
  if (generationen.isEmpty) return null;
  final t = AppTexte.of(context);
  return showModalBottomSheet<BackupGeneration?>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              t.einstBackupWiederherstellungspunktTitel,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: Text(t.einstBackupAktuellerStand),
            subtitle: Text(t.einstBackupAktuellerStandText),
            onTap: () => Navigator.pop(sheetContext),
          ),
          const Divider(),
          for (final generation in generationen)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                t.einstBackupGenerationZeit(
                  datumZeitText(context, generation.createdAt),
                ),
              ),
              subtitle: Text(t.einstBackupGenerationText),
              onTap: () => Navigator.pop(sheetContext, generation),
            ),
        ],
      ),
    ),
  );
}

Future<void> _pruefeBackup(Einstellungsstand stand) async {
  final context = stand.kontext;
  final source = await FilePicker.getDirectoryPath(
    dialogTitle: AppTexte.of(context).einstBackupOrdnerWaehlen,
  );
  if (source == null || !context.mounted) return;
  final wurzel = await BackupPruefdienst.findeBackupWurzel(source);
  String? passphrase;
  if (await File(p.join(wurzel, 'vault.key')).exists()) {
    if (!context.mounted) return;
    passphrase = await showEnterPassphraseDialog(
      context,
      title: AppTexte.of(context).einstBackupPassphraseEingeben,
    );
    if (passphrase == null) return;
  }
  if (!context.mounted) return;
  final t = AppTexte.of(context);
  BackupPrueffortschritt? letzter;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => ProgressDialog(
      title: t.einstBackupPruefungLaeuft,
      fehlerText: (e) => fehlertext(dialog, e),
      stream: BackupPruefdienst().pruefe(wurzel, passphrase: passphrase).map((
        fortschritt,
      ) {
        letzter = fortschritt;
        return _backupPruefZeile(t, fortschritt);
      }),
    ),
  );
  if (!context.mounted || letzter == null) return;
  if (letzter!.erfolgreich) {
    melde.erfolg(t.einstBackupPruefungErfolgreich(letzter!.gueltig));
  } else {
    melde.warnung(
      t.einstBackupPruefungFehler(
        letzter!.gueltig,
        letzter!.fehlend,
        letzter!.beschaedigt,
      ),
    );
  }
}

Future<void> _setupBackupPassphrase(Einstellungsstand stand) async {
  final context = stand.kontext;
  final ok = await ensureBackupKeyAvailable(context, stand.library);
  if (ok && context.mounted) stand.reloadBackupKeyState();
}

Future<void> _changeBackupPassphrase(Einstellungsstand stand) async {
  final context = stand.kontext;
  final unlocked = await ensureBackupKeyAvailable(context, stand.library);
  if (!unlocked || !context.mounted) return;
  final newPass = await showSetPassphraseDialog(context);
  if (newPass == null) return;
  await stand.library.changeBackupPassphrase(newPass);
}

Future<void> _removeBackupEncryption(Einstellungsstand stand) async {
  final context = stand.kontext;
  final unlocked = await ensureBackupKeyAvailable(context, stand.library);
  if (!unlocked || !context.mounted) return;
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppTexte.of(context).einstBackupEntschluesselnTitel),
      content: Text(AppTexte.of(context).einstBackupEntschluesselnText),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppTexte.of(context).allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(AppTexte.of(context).allgEntfernen),
        ),
      ],
    ),
  );
  if (confirm == true) {
    await stand.library.removeBackupEncryption();
    if (context.mounted) stand.reloadBackupKeyState();
  }
}

Future<void> _runAutoBackupNow(Einstellungsstand stand) async {
  final context = stand.kontext;
  final ok = await ensureBackupKeyAvailable(context, stand.library);
  if (!ok || !context.mounted) return;
  final config = await stand.library.db.backupSettingsRow();
  final destination = config?.autoBackupDestination;
  if (destination == null || !context.mounted) return;
  // Vorher auflösen: Der Mapper unten läuft bei jedem Fortschritts-Ereignis,
  // also lange nach dem Aufbau des Dialogs. Einen BuildContext so lange
  // festzuhalten ist genau das, wovor `use_build_context_synchronously`
  // warnt – der Text selbst ändert sich in dieser Zeit ohnehin nicht.
  final keineNeuen = AppTexte.of(context).einstBackupKeineNeuen;
  final t = AppTexte.of(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ProgressDialog(
      title: AppTexte.of(context).einstBackupLaeuft,
      stream: stand.library
          .runAutoBackupNow(destination)
          .map(
            (p) => p.total == 0 && p.wiederherstellungsprobe == null
                ? keineNeuen
                : _backupZeile(t, p),
          )
          // Lesbar statt „PathAccessException … errno = 1“ (#211).
          .handleError(
            (Object _) => throw t.backupZielGesperrt,
            test: (e) => e is BackupZielGesperrt,
          ),
    ),
  );
  if (context.mounted) stand.reloadBackupSettings();
}

Future<void> _pruefeWiederherstellung(Einstellungsstand stand) async {
  final context = stand.kontext;
  final t = AppTexte.of(context);
  final source = await FilePicker.getDirectoryPath(
    dialogTitle: t.einstBackupOrdnerWaehlen,
  );
  if (source == null || !context.mounted) return;
  final wurzel = await BackupPruefdienst.findeBackupWurzel(source);
  String? passphrase;
  if (await File(p.join(wurzel, 'vault.key')).exists()) {
    if (!context.mounted) return;
    passphrase = await showEnterPassphraseDialog(
      context,
      title: t.einstBackupPassphraseEingeben,
    );
    if (passphrase == null) return;
  }
  if (!context.mounted) return;
  BackupProbeErgebnis? ergebnis;
  final format = DateFormat.yMd(
    Localizations.localeOf(context).toString(),
  ).add_Hm();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => ProgressDialog(
      title: t.backupProbeTitel,
      fehlerText: (e) => fehlertext(dialog, e),
      stream:
          Stream.fromFuture(
            stand.library.backupService.pruefeWiederherstellung(
              wurzel,
              passphrase: passphrase,
            ),
          ).map((r) {
            ergebnis = r;
            return backupProbeTextMit(t, r, format.format);
          }),
    ),
  );
  if (context.mounted && ergebnis != null) {
    final text = backupProbeText(context, ergebnis!);
    if (ergebnis!.erfolgreich) {
      melde.erfolg(text);
    } else {
      melde.warnung(text);
    }
  }
}
