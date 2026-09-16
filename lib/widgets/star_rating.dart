import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Reihe von 5 antippbaren Sternen (0-5) – für die Bewertung eines einzelnen
/// Assets (Info-Panel), als "Mindestbewertung"-Schwellenwert im
/// Suchoptionen-Panel, und in der Auswahlleiste für Mehrfachauswahlen.
/// `onChanged: null` macht die Reihe rein anzeigend (nicht antippbar).
class StarRating extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  const StarRating({super.key, required this.value, this.onChanged, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            label: onChanged == null
                ? (i <= value ? AppTexte.of(context).sterneSternVoll(i) : AppTexte.of(context).sterneStern(i))
                : AppTexte.of(context).sterneSetzen(i),
            button: onChanged != null,
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onChanged == null
                  ? null
                  // Erneutes Tippen auf den bereits gesetzten letzten Stern
                  // setzt auf 0 zurück – sonst ließe sich eine Bewertung ohne
                  // Extra-Bedienelement nie wieder entfernen.
                  : () => onChanged!(value == i ? 0 : i),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  i <= value ? Icons.star : Icons.star_border,
                  size: size,
                  color: i <= value ? color : color.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
