import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../services/library_location.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';

/// Steht anstelle der Bibliothek, wenn eine andere Instanz sie hält (siehe
/// [Bibliothekssperre]).
///
/// **Ein Bildschirm, kein Dialog.** Dahinter ist nichts – die Datenbank
/// wurde absichtlich nicht geöffnet. Ein Dialog über einer leeren Fläche
/// sähe aus, als liesse sich etwas wegklicken, hinter dem etwas wartet.
///
/// Drei Wege hinaus, in der Reihenfolge ihrer Wahrscheinlichkeit: Das andere
/// Fenster schliessen und **erneut versuchen**, eine **andere Bibliothek**
/// öffnen, oder **beenden**. Der erste ist der häufigste Fall – jemand hat
/// das Programm zweimal gestartet – und steht deshalb vorn.
class BibliothekBelegtScreen extends StatefulWidget {
  final LibraryState library;
  const BibliothekBelegtScreen({super.key, required this.library});

  @override
  State<BibliothekBelegtScreen> createState() => _BibliothekBelegtScreenState();
}

class _BibliothekBelegtScreenState extends State<BibliothekBelegtScreen> {
  bool _laeuft = false;
  bool _nochBelegt = false;

  /// Nimmt den Anlauf noch einmal. [LibraryState.initialize] hat beim ersten
  /// Mal abgebrochen, BEVOR es irgendetwas gesetzt hat – deshalb ist ein
  /// zweiter Aufruf unbedenklich und braucht keinen Neustart.
  Future<void> _erneut() async {
    setState(() {
      _laeuft = true;
      _nochBelegt = false;
    });
    await widget.library.initialize();
    if (!mounted) return;
    setState(() {
      _laeuft = false;
      _nochBelegt = widget.library.bibliothekBelegt;
    });
  }

  Future<void> _andere() async {
    final texte = AppTexte.of(context);
    final belegt = widget.library.belegterOrt;
    final bekannt = await LibraryLocation.bekannte();
    final andere = [
      for (final b in bekannt)
        if (belegt == null || !p.equals(b.eintrag.path, belegt)) b,
    ];
    if (!mounted) return;

    final ziel = await showDialog<BibliothekMitZustand>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(texte.sperreAuswahlTitel),
        children: andere.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl, vertical: AppSpacing.sm),
                  child: Text(texte.sperreAuswahlLeer),
                ),
              ]
            : [
                for (final b in andere)
                  SimpleDialogOption(
                    onPressed:
                        b.erreichbar ? () => Navigator.pop(context, b) : null,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      enabled: b.erreichbar,
                      title: Text(b.eintrag.name),
                      subtitle: Text(b.erreichbar
                          ? b.eintrag.path
                          : texte.einstBibNichtGefunden),
                    ),
                  ),
              ],
      ),
    );
    if (ziel == null || !mounted) return;

    setState(() => _laeuft = true);
    await LibraryLocation.wechsleZu(ziel.eintrag);
    await widget.library.initialize();
    if (!mounted) return;
    setState(() {
      _laeuft = false;
      _nochBelegt = widget.library.bibliothekBelegt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final texte = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final ort = widget.library.belegterOrt;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline,
                    size: 48, color: farben.onSurfaceVariant),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  texte.sperreTitel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  texte.sperreText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (ort != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: farben.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(texte.sperreOrt,
                            style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: AppSpacing.xs),
                        SelectableText(ort,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
                if (_nochBelegt) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    texte.sperreNochBelegt,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: farben.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.xxl),
                FilledButton.icon(
                  onPressed: _laeuft ? null : _erneut,
                  icon: _laeuft
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(texte.sperreErneut),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _laeuft ? null : _andere,
                  child: Text(texte.sperreAndere),
                ),
                TextButton(
                  // Nichts läuft und nichts ist offen – die Datenbank wurde
                  // nie geöffnet. Es gibt hier nichts zu retten und deshalb
                  // auch keinen Grund für eine Rückfrage.
                  onPressed: _laeuft ? null : () => exit(0),
                  child: Text(texte.sperreBeenden),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
