import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/reisefortschritt.dart';
import '../theme/app_spacing.dart';

/// Der Balken samt Zahlen über dem Reisen-Bildschirm.
///
/// Stand früher zusammen mit einer eigenen Länderliste in einer Datei.
/// Die Liste kann jetzt mehr – Hauptstadt, Erdteil, Regionenfortschritt,
/// eigene Marken – und heisst [LaenderlisteScreen]. Zwei Bildschirme, die
/// dieselbe Frage verschieden gut beantworten, wären eine Zumutung für
/// den, der sich zwischen ihnen entscheiden müsste.
class Fortschrittsbalken extends StatelessWidget {
  final Reisefortschritt fortschritt;

  const Fortschrittsbalken({super.key, required this.fortschritt});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.fortschrittLaender(
              fortschritt.laenderBesucht, fortschritt.laenderGesamt),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${t.fortschrittRegionen(fortschritt.regionen)} · '
          '${t.fortschrittOrte(fortschritt.orte)}',
          style: TextStyle(fontSize: 13, color: farben.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: LinearProgressIndicator(
            value: fortschritt.anteil,
            minHeight: 8,
            // Der Balken ist bei vier von zweihundert kaum zu sehen –
            // deshalb steht die Zahl darüber und nicht darin. Ein Balken,
            // der die Auskunft allein tragen müsste, wäre hier der
            // falsche Träger.
            backgroundColor: farben.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}
