import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../screens/einstellungen/gemeinsam.dart' show fehlertext;
import '../theme/app_theme.dart';

/// Zeigt den Fortschritt eines Streams (z.B. Backup, Restore, Gesichts-Scan)
/// in einem nicht schließbaren Dialog mit Fortschrittsbalken und Text.
class ProgressDialog extends StatelessWidget {
  final String title;
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
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: stream,
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
