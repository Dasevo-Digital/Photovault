import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../state/library_state.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/typed_confirm_dialog.dart';
import 'einstellungsstand.dart';
import 'gemeinsam.dart';

/// Die Gefahrenzone: die Bibliothek vollständig löschen – oder, in einer
/// verbundenen Bibliothek, nur deren Kopie hier neu laden (GRU-145).
class GefahrenzoneGruppe extends StatelessWidget {
  const GefahrenzoneGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final verbunden = stand.library.verbunden;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            verbunden ? t.einstResetTextVerbunden : t.einstResetText,
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
            title: Text(t.einstResetTitel),
            subtitle: Text(
              verbunden ? t.einstResetKurzVerbunden : t.einstResetKurz,
            ),
            trailing: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => _resetDatabase(stand),
              child: Text(t.einstResetKnopf),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fragt per Wort-Bestätigung nach (siehe [showTypedConfirmDialog], reicht
/// ein normales Ja/Nein bei so einer unumkehrbaren Aktion nicht) und löscht
/// danach über [LibraryState.eraseLibraryCompletely] wirklich ALLES – jede
/// Original-/Vorschaudatei und die komplette Datenbank. Nutzt denselben
/// Ladeanzeige-/Neustart-Ablauf wie das Verlegen des Speicherorts, da beide
/// Fälle strukturell identisch sind: die laufende DB-Datei wird unter der
/// offenen Verbindung weggenommen, ein Neustart ist deshalb zwingend.
///
/// Verbunden leert es nur die Kopie hier und lädt sie vom Server neu
/// ([LibraryState.ladeKopieVomServerNeu]); die Rückfrage sagt das.
Future<void> _resetDatabase(Einstellungsstand stand) async {
  final context = stand.kontext;
  final t = AppTexte.of(context);
  final verbunden = stand.library.verbunden;
  final confirmed = await showTypedConfirmDialog(
    context,
    title: t.einstResetBestaetigenTitel,
    message: verbunden
        ? t.einstResetBestaetigenTextVerbunden
        : t.einstResetBestaetigenText,
    confirmationWord: t.einstResetWort,
    confirmLabel: t.einstResetEndgueltig,
  );
  if (!confirmed || !context.mounted) return;

  await verlegeBibliothek(
    stand,
    loadingText: verbunden ? t.einstResetLaeuftVerbunden : t.einstResetLaeuft,
    action: verbunden
        ? stand.library.ladeKopieVomServerNeu
        : stand.library.eraseLibraryCompletely,
    restartMessage: verbunden
        ? t.einstResetFertigVerbunden
        : t.einstResetFertig,
    errorPrefix: t.einstResetFehlgeschlagen,
  );
}
