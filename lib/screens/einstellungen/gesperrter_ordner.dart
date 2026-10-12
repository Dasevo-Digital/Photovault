import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kern/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/pin_dialogs.dart';
import '../locked_folder_screen.dart';
import 'einstellungsstand.dart';

/// Der gesperrte Ordner: PIN einrichten, ändern, entfernen, öffnen.
class GesperrterOrdnerGruppe extends StatelessWidget {
  const GesperrterOrdnerGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Card(
        child: FutureBuilder<bool>(
          future: stand.hasPinSetFuture,
          builder: (context, snapshot) {
            final hasPin = snapshot.data ?? false;
            if (!hasPin) {
              return ListTile(
                leading: const Icon(Icons.enhanced_encryption_outlined),
                title: Text(AppTexte.of(context).einstPinEinrichten),
                subtitle: Text(AppTexte.of(context).einstGesperrtText),
                isThreeLine: true,
                trailing: FilledButton(
                  onPressed: () => _setupPin(stand),
                  child: Text(AppTexte.of(context).allgEinrichten),
                ),
              );
            }
            final unlocked = stand.library.vaultUnlockedThisSession;
            return Column(
              children: [
                ListTile(
                  leading: Icon(
                    unlocked ? Icons.lock_open_outlined : Icons.lock_outline,
                  ),
                  title: Text(AppTexte.of(context).einstGesperrterOrdner),
                  subtitle: Text(
                    unlocked
                        ? AppTexte.of(context).einstGesperrtEntsperrt
                        : AppTexte.of(context).einstPinEingerichtet,
                  ),
                  trailing: FilledButton.icon(
                    onPressed: () => _openLockedFolder(stand),
                    icon: const Icon(Icons.lock_open_outlined),
                    label: Text(AppTexte.of(context).einstGesperrtOeffnen),
                  ),
                ),
                const Divider(height: 1),
                FutureBuilder<PrivacySettingsData?>(
                  future: stand.einmal(
                    EinstellungsAbfrage.datenschutz,
                    stand.library.db.privacySettingsRow,
                  ),
                  builder: (context, privacy) => SwitchListTile(
                    secondary: const Icon(Icons.visibility_off_outlined),
                    title: Text(
                      AppTexte.of(context).einstPrivateMetadatenTitel,
                    ),
                    subtitle: Text(
                      AppTexte.of(context).einstPrivateMetadatenText,
                    ),
                    value: privacy.data?.protectMetadata ?? true,
                    onChanged: (value) async {
                      await stand.library.db.setProtectPrivateMetadata(value);
                      if (stand.aktiv) {
                        stand.neuFragen(EinstellungsAbfrage.datenschutz);
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _changePin(stand),
                          child: Text(AppTexte.of(context).einstPinAendern),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _removePin(stand),
                          child: Text(AppTexte.of(context).einstPinEntfernen),
                        ),
                      ),
                    ],
                  ),
                ),
                if (unlocked)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () => _lockVaultSession(stand),
                        icon: const Icon(Icons.lock_clock_outlined),
                        label: Text(AppTexte.of(context).einstSitzungSperren),
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

Future<void> _setupPin(Einstellungsstand stand) async {
  final context = stand.kontext;
  final ok = await ensureVaultUnlocked(context, stand.library);
  if (ok && context.mounted) stand.reloadPinState();
}

Future<void> _openLockedFolder(Einstellungsstand stand) async {
  final context = stand.kontext;
  final ok = await ensureVaultUnlocked(context, stand.library);
  if (!ok || !context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => LockedFolderScreen(library: stand.library),
    ),
  );
}

Future<void> _changePin(Einstellungsstand stand) async {
  final context = stand.kontext;
  final unlocked = await ensureVaultUnlocked(context, stand.library);
  if (!unlocked || !context.mounted) return;
  final newPin = await showSetPinDialog(context);
  if (newPin == null) return;
  await stand.library.changeVaultPin(newPin);
}

Future<void> _removePin(Einstellungsstand stand) async {
  final context = stand.kontext;
  final unlocked = await ensureVaultUnlocked(context, stand.library);
  if (!unlocked || !context.mounted) return;
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppTexte.of(context).einstGesperrtAufloesenTitel),
      content: Text(AppTexte.of(context).einstGesperrtAufloesenText),
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
    await stand.library.removeVaultPin();
    if (context.mounted) stand.reloadPinState();
  }
}

Future<void> _lockVaultSession(Einstellungsstand stand) async {
  await stand.library.sperreTresor();
  if (stand.aktiv) stand.aendere(() {});
}
