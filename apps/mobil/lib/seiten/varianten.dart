import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Varianten wie am Rechner (#219): mehrere Fassungen derselben Aufnahme
/// unter einer Hauptversion – ein gewöhnlicher Stapel mit der Kennung
/// `variante:…` (kern/db/abfragen/serien.dart), mit denselben Befehlen.

/// Stapelt [zeilen] als Varianten, nachdem die Hauptversion gewählt ist.
/// Gibt zurück, ob es geschah.
Future<bool> variantenBilden(
  BuildContext context,
  Sitzung sitzung,
  List<Rasterzeile> zeilen,
) async {
  if (zeilen.length < 2) return false;
  final t = AppTexte.of(context);
  final bote = ScaffoldMessenger.of(context);
  // Ein Foto gehört höchstens zu einem Stapel – Serie oder Varianten.
  if (zeilen.any((z) => z.stackId != null)) {
    bote.showSnackBar(SnackBar(content: Text(t.variantenSchonGestapelt)));
    return false;
  }
  final haupt = await hauptversionWaehlen(context, [
    for (final z in zeilen) (id: z.id, name: z.originalFileName),
  ], jetzt: zeilen.first.id);
  if (haupt == null) return false;
  final variantenId = const Uuid().v4();
  await sitzung.db.fuehreAus(
    VariantenBilden(variantenId, [for (final z in zeilen) z.id], haupt),
  );
  bote.showSnackBar(
    SnackBar(
      content: Text(t.variantenGebildet(zeilen.length)),
      action: SnackBarAction(
        label: t.variantenRueckgaengig,
        onPressed: () => sitzung.db.fuehreAus(
          VariantenAufloesen(variantenstapelId(variantenId)),
        ),
      ),
    ),
  );
  return true;
}

/// Fragt nach der Hauptversion unter [fassungen]; [jetzt] ist vorgewählt.
/// `null` heisst abgebrochen.
Future<String?> hauptversionWaehlen(
  BuildContext context,
  List<({String id, String name})> fassungen, {
  required String jetzt,
}) {
  var gewaehlt = jetzt;
  return showDialog<String>(
    context: context,
    builder: (context) {
      final t = AppTexte.of(context);
      return StatefulBuilder(
        builder: (context, setze) => AlertDialog(
          title: Text(t.variantenHauptWaehlen),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.variantenHauptText),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in fassungen)
                        ListTile(
                          leading: Icon(
                            f.id == gewaehlt
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(f.name),
                          selected: f.id == gewaehlt,
                          onTap: () => setze(() => gewaehlt = f.id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.abbrechen),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, gewaehlt),
              child: Text(t.speichern),
            ),
          ],
        ),
      );
    },
  );
}

/// Wechselt die Hauptversion des Variantenstapels [stackId], dessen
/// Fassungen [mitglieder] sind. Gibt zurück, ob sich etwas änderte.
Future<bool> hauptversionWechseln(
  BuildContext context,
  Sitzung sitzung,
  String stackId,
  List<AssetData> mitglieder,
) async {
  final jetzt = mitglieder
      .firstWhere((a) => a.isStackCover, orElse: () => mitglieder.first)
      .id;
  final neu = await hauptversionWaehlen(context, [
    for (final a in mitglieder) (id: a.id, name: a.originalFileName),
  ], jetzt: jetzt);
  if (neu == null || neu == jetzt) return false;
  await sitzung.db.fuehreAus(VariantenHauptbildSetzen(stackId, neu));
  return true;
}

/// Zeigt die Fassungen von [stackId] wieder einzeln – nach Rückfrage.
/// Gibt zurück, ob es geschah.
Future<bool> variantenAufloesen(
  BuildContext context,
  Sitzung sitzung,
  String stackId,
  int anzahl,
) async {
  final ja = await showDialog<bool>(
    context: context,
    builder: (context) {
      final t = AppTexte.of(context);
      return AlertDialog(
        content: Text(t.variantenEinzelnFrage(anzahl)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.variantenEinzeln),
          ),
        ],
      );
    },
  );
  if (ja != true) return false;
  await sitzung.db.fuehreAus(VariantenAufloesen(stackId));
  return true;
}
