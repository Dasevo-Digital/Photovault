import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';

/// Zeigt einen fehlgeschlagenen Programmstart als bedienbaren Zustand.
/// Ohne diese Ansicht blieb `isReady` falsch und der Ladekreis stand für
/// immer, obwohl der eigentliche Fehler längst feststand.
class InitialisierungsfehlerScreen extends StatefulWidget {
  const InitialisierungsfehlerScreen({
    super.key,
    required this.fehler,
    required this.erneutVersuchen,
  });

  final String fehler;
  final Future<void> Function() erneutVersuchen;

  @override
  State<InitialisierungsfehlerScreen> createState() => _InitialisierungsfehlerScreenState();
}

class _InitialisierungsfehlerScreenState extends State<InitialisierungsfehlerScreen> {
  bool _laeuft = false;

  Future<void> _erneut() async {
    if (_laeuft) return;
    setState(() => _laeuft = true);
    await widget.erneutVersuchen();
    if (mounted) setState(() => _laeuft = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: AppSpacing.lg),
                Text(t.startFehlerTitel, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(t.startFehlerText, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.lg),
                SelectableText(widget.fehler,
                    style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: _laeuft ? null : _erneut,
                  icon: _laeuft
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(t.startFehlerErneut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
