import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../screens/einstellungen/gemeinsam.dart' show fehlertext;
import '../theme/app_theme.dart';

/// Zeigt den Fortschritt eines Streams (z.B. Backup, Restore, Gesichts-Scan)
/// in einem nicht schließbaren Dialog mit Fortschrittsbalken und Text.
///
/// Das Fenster abonniert den Strom genau einmal, den aus dem ersten
/// Aufbau. Der Builder von `showDialog` läuft nämlich bei jedem Neuaufbau
/// der `MaterialApp` noch einmal (der Navigator meldet den Routen dann
/// `changedExternalState`), und die App baut sie bei jeder Meldung des
/// Bibliothekszustands neu – verbunden bei jedem Befehl. Als
/// StatelessWidget mit `StreamBuilder(stream: stream)` kündigte das Fenster
/// dann den laufenden Strom und abonnierte den frisch erzeugten: Die Arbeit
/// begann von vorn, „Entwicklung übertragen“ wurde verbunden nie fertig,
/// und eine Wiederherstellung mit Erinnerungsfilter stieß sich selbst
/// immer wieder an (#423). Spätere Ströme übergeht es deshalb.
class ProgressDialog extends StatefulWidget {
  final String title;

  /// Der Strom, dessen Fortschritt das Fenster zeigt. Nur der aus dem
  /// ersten Aufbau zählt; die Aufrufer erzeugen ihn trotzdem vor
  /// `showDialog`, damit ein erneuter Builder-Lauf nichts anstößt.
  final Stream<String> stream;

  /// Macht aus einem Stream-Fehler einen lesbaren Satz.
  ///
  /// Ohne Angabe gilt die gemeinsame Übersetzung [fehlertext]. Vorher
  /// stand dann der Name der Ausnahmeklasse da – im Fenster des
  /// automatischen Backups etwa „Instance of 'BackupLaeuftBereits'“ statt
  /// „Eine automatische Sicherung läuft bereits.“ (SIC-041): Dienste
  /// werfen für alles, was der Nutzer lesen soll, einen eigenen Typ, und
  /// nicht jeder Aufrufer dachte daran, ihn übersetzen zu lassen.
  final String Function(Object fehler)? fehlerText;

  const ProgressDialog({
    super.key,
    required this.title,
    required this.stream,
    this.fehlerText,
  });

  @override
  State<ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<ProgressDialog> {
  late final Stream<String> _strom = widget.stream;

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final fehlerText = widget.fehlerText;
    return StreamBuilder<String>(
      stream: _strom,
      builder: (context, snapshot) {
        final done = snapshot.connectionState == ConnectionState.done;
        final failed = snapshot.hasError;
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!done)
                const LinearProgressIndicator()
              else if (failed)
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                )
              else
                Icon(Icons.check_circle, color: context.semantik.erfolg),
              const SizedBox(height: 12),
              // Ein Stream-Fehler (z.B. ein Modell, das sich nicht laden
              // ließ) darf hier nie als Erfolg durchgehen – vorher wurde nur
              // `snapshot.data` gelesen, das bei einem Fehler VOR dem ersten
              // `yield` schlicht leer blieb und trotzdem den grünen Haken
              // zeigte (Audit-Fund).
              Text(
                failed
                    ? AppTexte.of(context).fortschrittFehlgeschlagen(
                        (fehlerText ?? (e) => fehlertext(context, e))(
                          snapshot.error!,
                        ),
                      )
                    : (snapshot.data ?? '…'),
              ),
            ],
          ),
          actions: [
            if (done)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppTexte.of(context).allgSchliessen),
              ),
          ],
        );
      },
    );
  }
}
