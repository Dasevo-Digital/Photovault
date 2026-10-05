import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/library_location.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';

/// Steht anstelle der Bibliothek, wenn sich die eingestellte nicht öffnen
/// lässt (siehe [LibraryLocation.wurzelMitBefund]).
///
/// Bisher fiel die App in diesem Fall still auf den Standardordner zurück –
/// und zeigte damit eine andere, meist leere Bibliothek, ohne es zu sagen.
/// Zwei Fälle führen hierher: ein nicht angeschlossenes Laufwerk, und unter
/// macOS ein Ordner, dessen Freigabe nach dem Wechsel der Programmkennung
/// nicht mehr gilt.
///
/// Wie [BibliothekBelegtScreen] ein Bildschirm und kein Dialog: Dahinter
/// ist nichts geöffnet.
/// Ob in [pfad] eine Bibliothek liegt. Ein Ordner ohne `library.sqlite`
/// wäre beim Öffnen eine neue, leere.
@visibleForTesting
Future<bool> enthaeltBibliothek(String pfad) =>
    File('$pfad${Platform.pathSeparator}library.sqlite').exists();

class BibliothekUnerreichbarScreen extends StatefulWidget {
  final LibraryState library;
  const BibliothekUnerreichbarScreen({super.key, required this.library});

  @override
  State<BibliothekUnerreichbarScreen> createState() =>
      _BibliothekUnerreichbarScreenState();
}

class _BibliothekUnerreichbarScreenState
    extends State<BibliothekUnerreichbarScreen> {
  bool _laeuft = false;
  bool _nochImmer = false;
  bool _keineBibliothek = false;

  Future<void> _lauf(Future<void> Function() schritt) async {
    setState(() {
      _laeuft = true;
      _nochImmer = false;
      _keineBibliothek = false;
    });
    await schritt();
    if (!mounted) return;
    setState(() {
      _laeuft = false;
      _nochImmer = widget.library.unerreichbar != null;
    });
  }

  /// Der Ordnerdialog erneuert unter macOS das Security-Scoped-Bookmark.
  /// [LibraryLocation.fuegeHinzu] ersetzt dabei den Eintrag mit demselben
  /// Pfad, der Name bleibt.
  ///
  /// Nur ein Ordner, in dem schon eine Bibliothek liegt: Wer hier aus
  /// Versehen den Ordner darüber wählt, bekäme sonst still eine neue,
  /// leere Bibliothek angelegt und geöffnet – genau das, wovor dieser
  /// Bildschirm schützen soll.
  Future<void> _freigeben(Bibliothekseintrag eintrag) async {
    final texte = AppTexte.of(context);
    final gewaehlt = await LibraryLocation.pickFolder(
      dialogMessage: texte.unerreichbarDialog(eintrag.name),
    );
    if (gewaehlt == null || !mounted) return;
    if (!await enthaeltBibliothek(gewaehlt.path)) {
      if (mounted) setState(() => _keineBibliothek = true);
      return;
    }
    await _lauf(() async {
      final neu = await LibraryLocation.fuegeHinzu(
        gewaehlt,
        name: eintrag.name,
      );
      await LibraryLocation.wechsleZu(neu);
      await widget.library.initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final texte = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final eintrag = widget.library.unerreichbar;
    if (eintrag == null) return const SizedBox.shrink();

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
                Icon(
                  Icons.folder_off_outlined,
                  size: 48,
                  color: farben.onSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  texte.unerreichbarTitel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  texte.unerreichbarText(eintrag.name),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
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
                      Text(
                        texte.sperreOrt,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      SelectableText(
                        eintrag.path,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_keineBibliothek) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    texte.unerreichbarKeineBibliothek,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: farben.error),
                  ),
                ],
                if (_nochImmer) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    texte.unerreichbarNochImmer,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: farben.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.xxl),
                FilledButton.icon(
                  onPressed: _laeuft ? null : () => _freigeben(eintrag),
                  icon: _laeuft
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(texte.unerreichbarFreigeben),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _laeuft
                      ? null
                      : () => _lauf(widget.library.initialize),
                  icon: const Icon(Icons.refresh),
                  label: Text(texte.sperreErneut),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _laeuft
                      ? null
                      : () => _lauf(widget.library.oeffneStandardordner),
                  child: Text(texte.unerreichbarStandard),
                ),
                TextButton(
                  // Nichts ist geöffnet – kein Grund für eine Rückfrage.
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
