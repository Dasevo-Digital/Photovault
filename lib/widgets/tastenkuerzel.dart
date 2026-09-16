import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';

/// Die Tafel aller Tastaturkürzel – an zwei Stellen gezeigt und deshalb
/// hier zu Hause: im Fenster, das „?" öffnet, und als Gruppe in den
/// Einstellungen.
///
/// **Warum sie zweimal auftaucht.** Die Tafel gab es schon; erreichbar war
/// sie ausschliesslich über „?" – eine Taste, die nirgends genannt wurde.
/// Eine Übersicht der Tastenkürzel hinter einem unbekannten Tastenkürzel
/// ist dieselbe Sackgasse, die die Bewertungen bis 2.5.0 ungenutzt liess:
/// die Funktion war da, der Weg dorthin nicht.
class Tastenkuerzeltafel extends StatelessWidget {
  const Tastenkuerzeltafel({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Abschnitt(titel: t.kuerzelNavigation, kuerzel: [
          ('⌘1 – ⌘0', t.kuerzelBereicheWechseln),
          ('⌘K / Ctrl+K', t.kuerzelBefehlspalette),
          ('—', t.kuerzelReisenOhne),
          ('?', t.kuerzelUebersichtOeffnen),
        ]),
        const SizedBox(height: AppSpacing.md),
        // Neu in 2.5.0 – und bis hierher in keiner Übersicht genannt.
        _Abschnitt(titel: t.kuerzelRaster, kuerzel: [
          (t.kuerzelUmschaltKlick, t.kuerzelBereichWaehlen),
          (t.kuerzelStrgKlick, t.kuerzelEinzelnWaehlen),
          ('← ↑ ↓ →', t.kuerzelRahmenBewegen),
          (t.kuerzelUmschaltPfeil, t.kuerzelAuswahlZiehen),
          ('0 – 5', t.kuerzelBewertungSetzen),
          ('6 – 9', t.kuerzelFarbmarkeSetzen),
          ('F', t.kuerzelFavoritUmschalten),
          ('Esc', t.kuerzelAuswahlLeeren),
          ('⏎', t.kuerzelFotoOeffnen),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text(t.kuerzelWirktAuf,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.md),
        _Abschnitt(titel: t.kuerzelVollbild, kuerzel: [
          ('← / →', t.kuerzelVorherigesNaechstes),
          (t.kuerzelLeertaste, t.kuerzelNaechstesFoto),
          ('0 – 5', t.kuerzelBewertungSetzen),
          ('6 – 9', t.kuerzelFarbmarkeSetzen),
          ('F', t.kuerzelFavoritUmschalten),
          ('⌫ / Delete', t.kuerzelPapierkorbMitBestaetigung),
          // Eine Magic Mouse kann nicht kneifen - siehe
          // [BildZoomGesten]. Ohne diese Zeile waere der Zoom dort eine
          // Geste, die niemand findet.
          (t.kuerzelZoomWischen, t.kuerzelZoomImBild),
          ('Esc', t.allgSchliessen),
        ]),
        const SizedBox(height: AppSpacing.md),
        _Abschnitt(titel: t.kuerzelSichtung, kuerzel: [
          ('⌫ / Delete', t.kuerzelSofortAblehnen),
        ]),
      ],
    );
  }
}

class _Abschnitt extends StatelessWidget {
  final String titel;
  final List<(String, String)> kuerzel;
  const _Abschnitt({required this.titel, required this.kuerzel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titel, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        for (final (taste, was) in kuerzel)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Feste Spalte, damit die Beschreibungen eine Kante bilden.
                // 132 statt der früheren 110: „Umschalt-Klick" passte sonst
                // schon bei gewöhnlicher Schriftgrösse nicht.
                SizedBox(
                  width: 132,
                  child: Text(
                    taste,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                    child: Text(was,
                        style: Theme.of(context).textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
