import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Einheitlicher Leerzustand (Icon + Text + optionale Aktion) für Screens,
/// die bisher nur nackten, zentrierten Text zeigten (Audit-Fund: 13 geprüfte
/// Stellen, alle auf demselben niedrigen Gestaltungsniveau) – bewusst als
/// gemeinsamer Baustein statt pro Screen neu gebaut, damit künftige
/// Leerzustände automatisch demselben Muster folgen.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
