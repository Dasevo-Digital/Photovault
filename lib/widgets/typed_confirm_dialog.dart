import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'namens_dialog.dart' show MitTextsteuerung;

/// Bestätigungsdialog für besonders folgenschwere, unumkehrbare Aktionen
/// (z.B. "Datenbank zurücksetzen") – ein normales Ja/Nein reicht hier nicht,
/// weil ein versehentlicher Klick zu echtem, endgültigem Datenverlust führen
/// würde. Der Bestätigen-Button bleibt deaktiviert, bis [confirmationWord]
/// exakt (Groß-/Kleinschreibung inklusive) eingetippt wurde. Gibt `true`
/// zurück, wenn bestätigt wurde, sonst `false`.
Future<bool> showTypedConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmationWord,
  String? confirmLabel,
}) async {
  // Vorgabewert erst hier: im Kopf gibt es noch keinen Kontext.
  confirmLabel ??= AppTexte.of(context).bestaetigEndgueltigLoeschen;
  // Die Steuerung gehört dem Fenster und nicht diesem Aufruf: Wer sie
  // gleich nach `showDialog` wegwirft, zieht sie dem Textfeld während der
  // Ausblendung unter den Fingern weg (siehe [MitTextsteuerung]).
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => MitTextsteuerung(
      builder: (context, ctrl) => StatefulBuilder(
        builder: (context, setState) {
          final matches = ctrl.text == confirmationWord;
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 16),
                Text.rich(
                  TextSpan(
                    text: AppTexte.of(context).bestaetigTippeVor,
                    children: [
                      TextSpan(
                          text: confirmationWord,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: AppTexte.of(context).bestaetigTippeNach),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(hintText: confirmationWord),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(AppTexte.of(context).allgAbbrechen)),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: matches ? () => Navigator.pop(context, true) : null,
                child: Text(confirmLabel!),
              ),
            ],
          );
        },
      ),
    ),
  );
  return result ?? false;
}
