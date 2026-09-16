import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';

/// Die Leiste am unteren Rand, sobald in einer Reise oder Aktivität
/// Fotos ausgewählt sind.
///
/// **Warum nicht [SelectionActionBar].** Jene Leiste trägt neun
/// Sammelaktionen, darunter einen Papierkorb – und „Löschen" hiesse dort
/// wirklich löschen. Hier geht es um etwas anderes: das Foto bleibt in
/// der Bibliothek, es gehört nur nicht mehr zu diesem Ausflug. Dieselbe
/// Leiste mit anderer Bedeutung desselben Symbols wäre die schlechteste
/// aller Lösungen.
class ZuordnungAuswahlleiste extends StatelessWidget {
  const ZuordnungAuswahlleiste({
    super.key,
    required this.anzahl,
    required this.beschriftungEntfernen,
    required this.beiAufheben,
    required this.beiEntfernen,
  });

  final int anzahl;

  /// „Aus der Reise entfernen" oder „Aus der Aktivität entfernen" – der
  /// Aufrufer weiss, worum es geht.
  final String beschriftungEntfernen;

  final VoidCallback beiAufheben;
  final VoidCallback beiEntfernen;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: t.auswAufheben,
                  onPressed: beiAufheben,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(t.auswAnzahl(anzahl),
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                FilledButton.tonalIcon(
                  onPressed: anzahl == 0 ? null : beiEntfernen,
                  icon: const Icon(Icons.playlist_remove_outlined),
                  label: Text(beschriftungEntfernen),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
