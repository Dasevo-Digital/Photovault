import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/groessentext.dart';
import '../../services/library_location.dart';
import '../../services/meldungsdienst.dart';
import '../../services/platform/reveal_in_file_manager.dart';
import '../../theme/app_spacing.dart';
import 'einstellungsstand.dart';
import 'gemeinsam.dart';

/// Wo die Bibliothek liegt, was sie belegt, und sie verlegen.
class SpeicherortGruppe extends StatelessWidget {
  const SpeicherortGruppe(this.stand, {super.key});

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
              leading: const Icon(Icons.folder_outlined),
              title: Text(AppTexte.of(context).einstSpeicherort),
              subtitle: Text(stand.library.paths.root.path),
              trailing: IconButton(
                icon: const Icon(Icons.open_in_new),
                tooltip: AppTexte.of(context).einstImFinderAnzeigen,
                onPressed: () =>
                    _openInFinder(stand, stand.library.paths.root.path),
              ),
            ),
            const Divider(height: 1),
            FutureBuilder<bool>(
              future: stand.isCustomLocationFuture,
              builder: (context, snapshot) {
                final isCustom = snapshot.data ?? false;
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _changeLibraryLocation(stand),
                          icon: const Icon(Icons.drive_file_move_outline),
                          label: Text(AppTexte.of(context).einstAendern),
                        ),
                      ),
                      if (isCustom) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _resetLibraryLocation(stand),
                            icon: const Icon(Icons.restart_alt),
                            label: Text(
                              AppTexte.of(context).einstZuruecksetzen,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            // **Aufgeschlüsselt und nicht als eine Zahl.** Hier stand
            // allein die Summe der Originale; im Finder war der Ordner
            // deutlich grösser, und niemand konnte sehen, warum. Die
            // Teile, die die App selbst anlegt – Vorschauen,
            // Miniaturen, Gesichtsausschnitte, die Datenbank – sind
            // gerade die, die man beurteilen will.
            if (stand.belegung == null)
              ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: Text(AppTexte.of(context).einstSpeicherbedarf),
                subtitle: Text(AppTexte.of(context).einstWirdBerechnet),
              )
            else
              ExpansionTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: Text(AppTexte.of(context).einstSpeicherbedarf),
                subtitle: Text(groessentext(stand.belegung!.gesamt)),
                childrenPadding: const EdgeInsets.only(
                  left: AppSpacing.xxl,
                  right: AppSpacing.lg,
                  bottom: AppSpacing.sm,
                ),
                children: [
                  for (final posten in stand.belegung!.posten)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              belegungName(AppTexte.of(context), posten.name),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            groessentext(posten.bytes),
                            // Ziffern in einer Spalte gehören
                            // untereinander.
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    ],
  );
}

Future<void> _openInFinder(Einstellungsstand stand, String path) async {
  final context = stand.kontext;
  final opened = await revealInFileManager(path);
  if (!opened && context.mounted) {
    melde.warnung(AppTexte.of(context).einstOrdnerNichtGeoeffnet(path));
  }
}

Future<void> _changeLibraryLocation(Einstellungsstand stand) async {
  final context = stand.kontext;
  final picked = await LibraryLocation.pickFolder(
    // "Neuer Ordner" im nativen Dialog funktioniert bei ad-hoc-signierten
    // Entwickler-Builds auf macOS 26 nicht (bekannte, von Apple auf
    // XPC-Ebene eingeführte Einschränkung für Apps ohne Entwickler-
    // Zertifikat) – für PhotoVault reicht aber jeder bereits vorhandene
    // Ordner, ein neuer muss also nicht extra im Dialog angelegt werden.
    dialogMessage: AppTexte.of(context).einstSpeicherortWaehlen,
  );
  if (picked == null || !context.mounted) return;

  final fortschritt = ValueNotifier<BibliotheksVerschiebefortschritt?>(null);
  try {
    await verlegeBibliothek(
      stand,
      loadingText: AppTexte.of(context).einstSpeicherortVerschiebenLaeuft,
      progress: fortschritt,
      action: () => LibraryLocation.applyRoot(
        picked,
        beforeMove: () => stand.library.db.close(),
        onProgress: (wert) => fortschritt.value = wert,
      ),
    );
  } finally {
    fortschritt.dispose();
  }
}

Future<void> _resetLibraryLocation(Einstellungsstand stand) async {
  final context = stand.kontext;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppTexte.of(context).einstSpeicherortZuruecksetzenTitel),
      content: Text(AppTexte.of(context).einstSpeicherortZuruecksetzenText),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppTexte.of(context).allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(AppTexte.of(context).einstZuruecksetzen),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final fortschritt = ValueNotifier<BibliotheksVerschiebefortschritt?>(null);
  try {
    await verlegeBibliothek(
      stand,
      loadingText: AppTexte.of(context).einstSpeicherortZuruecksetzenLaeuft,
      progress: fortschritt,
      action: () => stand.library.resetLibraryLocation(
        onProgress: (wert) => fortschritt.value = wert,
      ),
    );
  } finally {
    fortschritt.dispose();
  }
}
