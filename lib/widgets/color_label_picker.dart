import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Feste Farbmarkierungs-Palette (Photo-Mechanic-/Lightroom-Konvention) –
/// die Schlüssel werden 1:1 als `Assets.colorLabel` in der DB gespeichert.
const Map<String, Color> colorLabelSwatches = {
  'red': Color(0xFFE53935),
  'yellow': Color(0xFFFDD835),
  'green': Color(0xFF43A047),
  'blue': Color(0xFF1E88E5),
  'purple': Color(0xFF8E24AA),
};

/// Anzeigenamen für VoiceOver-Labels – die Kreise selbst tragen keinen Text,
/// ohne diese Zuordnung wären sie für Screenreader-Nutzer nur nummerierte,
/// nicht unterscheidbare Buttons.
String farbmarkierungName(AppTexte t, String schluessel) => switch (schluessel) {
      'red' => t.farbeRot,
      'yellow' => t.farbeGelb,
      'green' => t.farbeGruen,
      'blue' => t.farbeBlau,
      'purple' => t.farbeViolett,
      _ => schluessel,
    };

/// Reihe von 5 farbigen Kreisen zur Einzelauswahl (Info-Panel) – Tippen auf
/// die bereits ausgewählte Farbe hebt die Markierung wieder auf (`null`).
class ColorLabelPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?>? onChanged;
  final double size;

  const ColorLabelPicker({super.key, required this.value, this.onChanged, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in colorLabelSwatches.entries)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Semantics(
              label: value == entry.key
                  ? AppTexte.of(context).farbeAusgewaehlt(farbmarkierungName(AppTexte.of(context), entry.key))
                  : AppTexte.of(context).farbeSetzen(farbmarkierungName(AppTexte.of(context), entry.key)),
              button: onChanged != null,
              excludeSemantics: true,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onChanged == null ? null : () => onChanged!(value == entry.key ? null : entry.key),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: entry.value,
                    border: Border.all(
                      color: value == entry.key ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: value == entry.key
                        ? [BoxShadow(color: entry.value.withValues(alpha: 0.6), blurRadius: 4)]
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
