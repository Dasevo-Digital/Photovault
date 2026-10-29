import 'package:flutter/material.dart';
import 'package:kern/db/database.dart' show NeuereBibliothek;

import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Die Kopie der Bibliothek ging beim Start nicht auf – wie
/// `InitialisierungsfehlerScreen` am Desktop.
///
/// Abmelden steht hier absichtlich nicht: Es löschte die Kopie samt den
/// Änderungen, die noch nicht beim Server sind.
class Startfehler extends StatefulWidget {
  const Startfehler({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<Startfehler> createState() => _StartfehlerState();
}

class _StartfehlerState extends State<Startfehler> {
  var _laeuft = false;

  Future<void> _erneut() async {
    if (_laeuft) return;
    setState(() => _laeuft = true);
    await widget.sitzung.erneutStarten();
    if (mounted) setState(() => _laeuft = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final fehler = widget.sitzung.startfehler ?? '';
    // Aus dem Hintergrund-Isolat kommt die Ausnahme nur als Text an.
    final neuer = fehler.contains(NeuereBibliothek.kennung);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  neuer ? t.startfehlerNeuerTitel : t.startfehlerTitel,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  neuer ? t.startfehlerNeuerText : t.startfehlerText,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SelectableText(
                  fehler,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _laeuft ? null : _erneut,
                  icon: _laeuft
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(t.startfehlerErneut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
