import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/library_state.dart';

/// Fragt nach, bevor die App mit noch laufender Auswertung beendet wird.
///
/// Nennt beim Namen, was läuft: „es läuft noch etwas" allein liesse offen,
/// ob es um Sekunden oder um eine Stunde geht. Gibt `true` zurück, wenn
/// trotzdem beendet werden soll.
Future<bool> zeigeBeendenFrage(BuildContext context, LibraryState library) async {
  final t = AppTexte.of(context);

  final offen = <String>[
    if (library.analyseLaeuft) t.werkzAllesNachholenTitel,
    for (final lauf in library.laufendeAufgaben) lauf.titel,
  ];

  final antwort = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.beendenTitel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.beendenText),
          const SizedBox(height: 12),
          for (final name in offen)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $name',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.beendenTrotzdem),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.beendenWeiterlaufen),
        ),
      ],
    ),
  );
  return antwort ?? false;
}
