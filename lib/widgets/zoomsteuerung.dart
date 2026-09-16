import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';

/// Die Knopfleiste am Rand einer Karte oder des Zierbaums: näher heran,
/// weiter weg, und was die jeweilige Ansicht sonst noch zu schalten hat.
///
/// **Warum es die Leiste überhaupt gibt.** Rad und Kneifen setzen ein
/// Eingabegerät voraus, das beides kann. Eine Magic Mouse hat kein Rad
/// (dafür gibt es `WischZoom`), und wer mit einer einfachen Maus
/// arbeitet, hat gar keine Zoomgeste. Zwei sichtbare Knöpfe sind der
/// einzige Weg, der auf jedem Gerät funktioniert.
///
/// Lag früher als private Klasse im Kartenbildschirm. Herausgezogen,
/// weil die Weltkarte der Reisen, die Familienorte und der Stammbaum
/// dieselbe Leiste brauchen – sie hatten überhaupt keine.
class Zoomsteuerung extends StatelessWidget {
  final VoidCallback? beiNaeher;
  final VoidCallback? beiWeiter;

  /// Alles wieder ins Bild rücken. `null` blendet den Knopf aus – auf
  /// einer Weltkarte gibt es nichts einzupassen, die hört nirgends auf.
  final VoidCallback? beiEinpassen;

  /// `null` blendet den Standortknopf aus – auf Plattformen ohne
  /// Ortungsanbindung. Ein Knopf, der nichts tun kann, wäre schlechter
  /// als keiner.
  final VoidCallback? beiStandort;

  /// Während der Standort ermittelt wird: Kreisel statt Nadel.
  final bool standortLaeuft;

  /// `null` blendet den Ereignisschalter aus – wer keinen Stammbaum
  /// führt, hat nichts umzuschalten. Ein Schalter ohne Wirkung wäre eine
  /// Behauptung, es gäbe dort etwas.
  final VoidCallback? beiEreignisse;
  final bool ereignisseAn;

  const Zoomsteuerung({
    super.key,
    this.beiNaeher,
    this.beiWeiter,
    this.beiEinpassen,
    this.beiStandort,
    this.standortLaeuft = false,
    this.beiEreignisse,
    this.ereignisseAn = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;

    Widget knopf({
      required IconData symbol,
      required String hinweis,
      required VoidCallback? beiDruck,
      Widget? statt,
    }) {
      return Tooltip(
        message: hinweis,
        child: InkResponse(
          onTap: beiDruck,
          radius: 22,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: statt ??
                  Icon(symbol,
                      size: 20,
                      color: beiDruck == null
                          ? farben.onSurfaceVariant.withValues(alpha: 0.4)
                          : farben.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return Material(
      color: farben.surfaceContainerHighest.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          knopf(
              symbol: Icons.add,
              hinweis: t.karteHineinzoomen,
              beiDruck: beiNaeher),
          Divider(height: 1, thickness: 1, color: farben.outlineVariant),
          knopf(
              symbol: Icons.remove,
              hinweis: t.karteHerauszoomen,
              beiDruck: beiWeiter),
          if (beiEinpassen != null) ...[
            Divider(height: 1, thickness: 1, color: farben.outlineVariant),
            knopf(
                symbol: Icons.fit_screen_outlined,
                hinweis: t.zoomEinpassen,
                beiDruck: beiEinpassen),
          ],
          if (beiEreignisse != null) ...[
            Divider(height: 1, thickness: 1, color: farben.outlineVariant),
            knopf(
              symbol: ereignisseAn
                  ? Icons.event_available_outlined
                  : Icons.event_busy_outlined,
              hinweis: ereignisseAn
                  ? t.karteEreignisseAusblenden
                  : t.karteEreignisseEinblenden,
              beiDruck: beiEreignisse,
            ),
          ],
          if (beiStandort != null) ...[
            Divider(height: 1, thickness: 1, color: farben.outlineVariant),
            knopf(
              symbol: Icons.my_location,
              hinweis: standortLaeuft
                  ? t.karteStandortSuche
                  : t.karteStandortZeigen,
              beiDruck: standortLaeuft ? null : beiStandort,
              statt: standortLaeuft
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}
