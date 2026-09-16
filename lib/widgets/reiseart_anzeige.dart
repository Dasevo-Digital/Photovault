/// Wie eine Reiseart aussieht und heisst.
///
/// An einer Stelle, aus demselben Grund wie bei
/// `aktivitaetsart_anzeige.dart`: Ein Symbol, das in der Liste ein
/// Koffer und in der Reise ein Flugzeug ist, macht aus einer Ordnung
/// ein Rätsel.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/reisen.dart';
import '../theme/app_spacing.dart';

IconData symbolFuerReiseart(Reiseart art) => switch (art) {
      Reiseart.reise => Icons.luggage_outlined,
      Reiseart.unternehmung => Icons.flag_outlined,
      Reiseart.geschaeftlich => Icons.work_outline,
      Reiseart.besuch => Icons.family_restroom_outlined,
      Reiseart.sonstiges => Icons.explore_outlined,
    };

String nameFuerReiseart(AppTexte t, Reiseart art) => switch (art) {
      Reiseart.reise => t.reiseartReise,
      Reiseart.unternehmung => t.reiseartUnternehmung,
      Reiseart.geschaeftlich => t.reiseartGeschaeftlich,
      Reiseart.besuch => t.reiseartBesuch,
      Reiseart.sonstiges => t.reiseartSonstiges,
    };

/// Symbol und Name zu einer Kennung aus der Datenbank.
IconData symbolFuerReiseartKennung(String kennung) =>
    symbolFuerReiseart(Reiseart.aus(kennung));

String nameFuerReiseartKennung(AppTexte t, String kennung) =>
    nameFuerReiseart(t, Reiseart.aus(kennung));

/// Fragt nach der Art einer Reise und gibt ihre Kennung zurück.
///
/// **Anders als bei den Aktivitäten gibt es hier keine eigenen Arten.**
/// Dort trägt jemand „Konzert" ein, weil es tausend Sorten Unternehmung
/// gibt; eine Reise dagegen ist eine Handvoll Fälle, und eine offene
/// Liste hiesse nur, dass dieselbe Reise beim nächsten Mal anders heisst.
///
/// `null` heisst „abgebrochen".
Future<String?> frageReiseart(
  BuildContext context, {
  String? aktuell,
}) {
  final t = AppTexte.of(context);
  return showDialog<String>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: Text(t.reisenArtAendern),
      children: [
        for (final art in Reiseart.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialog).pop(art.kennung),
            child: Row(
              children: [
                Icon(symbolFuerReiseart(art)),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(nameFuerReiseart(t, art))),
                if (art.kennung == aktuell) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
    ),
  );
}
