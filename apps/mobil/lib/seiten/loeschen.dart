import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../sicherung/telefonloeschung.dart';
import '../sitzung.dart';

/// Was von einer Auswahl auch in der Fotomediathek dieses Telefons liegt.
typedef Telefonteil = ({Telefonloeschung loeschung, List<String> lokal});

/// Welche der Aufnahmen [ids] auch in der Fotomediathek dieses Telefons
/// liegen (#205) – `null`, wenn keine, ohne Sicherung oder ohne Zugriff.
Future<Telefonteil?> aufDemTelefon(Sitzung sitzung, List<String> ids) async {
  final d = sitzung.sicherung;
  if (d == null) return null;
  try {
    final l = d.loeschung(sitzung.db);
    final lokal = await l.zu(ids);
    return lokal.isEmpty ? null : (loeschung: l, lokal: lokal);
  } catch (_) {
    return null; // ohne Zugriff auf die Fotos oder ohne Telefon (Tests)
  }
}

/// Die Rückfrage vor dem Papierkorb. Liegt etwas davon auch auf dem
/// Telefon ([telefon]), steht darunter „Auch vom Telefon löschen“ – mit
/// der zuletzt getroffenen Wahl. `null` heisst abgebrochen, sonst ob auch
/// vom Telefon gelöscht werden soll.
Future<bool?> fragePapierkorb(
  BuildContext context, {
  required Sitzung sitzung,
  required String titel,
  required String text,
  required String knopf,
  Telefonteil? telefon,
}) async {
  final t = AppTexte.of(context);
  final d = sitzung.sicherung;
  var auchTelefon = telefon != null && (d?.einstellungen.vomTelefon ?? true);
  final ja = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setze) => AlertDialog(
        title: Text(titel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            if (telefon != null) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: auchTelefon,
                onChanged: (an) => setze(() => auchTelefon = an ?? false),
                title: Text(t.loeschenAuchTelefon(telefon.lokal.length)),
                subtitle: Text(
                  Platform.isIOS
                      ? t.loeschenAuchTelefonHinweisIos
                      : t.loeschenAuchTelefonHinweis,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(knopf),
          ),
        ],
      ),
    ),
  );
  if (ja != true) return null;
  if (telefon != null &&
      d != null &&
      d.einstellungen.vomTelefon != auchTelefon) {
    await d.setze(d.einstellungen.mit(vomTelefon: auchTelefon));
  }
  return auchTelefon;
}

/// Löscht [telefon] aus der Fotomediathek – das System fragt dabei selbst
/// noch einmal – und sagt, wie viele gingen.
Future<void> loescheVomTelefon(
  ScaffoldMessengerState bote,
  AppTexte t,
  Sitzung sitzung,
  Telefonteil telefon,
) async {
  final n = await telefon.loeschung.loesche(telefon.lokal);
  bote
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t.vomTelefonGeloescht(n))));
  unawaited(sitzung.sicherung?.zaehleUngesicherte());
}
