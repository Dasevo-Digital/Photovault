import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../state/library_state.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/typed_confirm_dialog.dart';
import 'einstellungsstand.dart';
import 'gemeinsam.dart';

/// Die Gefahrenzone: die Bibliothek vollständig löschen.
class GefahrenzoneGruppe extends StatelessWidget {
  const GefahrenzoneGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          AppTexte.of(context).einstResetText,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4),
          ),
        ),
        child: ListTile(
          leading: Icon(
            Icons.warning_amber_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(AppTexte.of(context).einstResetTitel),
          subtitle: Text(AppTexte.of(context).einstResetKurz),
          trailing: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _resetDatabase(stand),
            child: Text(AppTexte.of(context).einstResetKnopf),
          ),
        ),
      ),
    ],
  );
}

/// Fragt per Wort-Bestätigung nach (siehe [showTypedConfirmDialog], reicht
/// ein normales Ja/Nein bei so einer unumkehrbaren Aktion nicht) und löscht
/// danach über [LibraryState.eraseLibraryCompletely] wirklich ALLES – jede
/// Original-/Vorschaudatei und die komplette Datenbank. Nutzt denselben
/// Ladeanzeige-/Neustart-Ablauf wie das Verlegen des Speicherorts, da beide
/// Fälle strukturell identisch sind: die laufende DB-Datei wird unter der
/// offenen Verbindung weggenommen, ein Neustart ist deshalb zwingend.
Future<void> _resetDatabase(Einstellungsstand stand) async {
  final context = stand.kontext;
  final confirmed = await showTypedConfirmDialog(
    context,
    title: AppTexte.of(context).einstResetBestaetigenTitel,
    message: AppTexte.of(context).einstResetBestaetigenText,
    confirmationWord: AppTexte.of(context).einstResetWort,
    confirmLabel: AppTexte.of(context).einstResetEndgueltig,
  );
  if (!confirmed || !context.mounted) return;

  await verlegeBibliothek(
    stand,
    loadingText: AppTexte.of(context).einstResetLaeuft,
    action: () => stand.library.eraseLibraryCompletely(),
    restartMessage: AppTexte.of(context).einstResetFertig,
    errorPrefix: AppTexte.of(context).einstResetFehlgeschlagen,
  );
}
