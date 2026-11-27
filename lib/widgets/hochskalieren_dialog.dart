import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';

import '../l10n/app_localizations.dart';
import '../services/hochskalieren.dart';
import '../services/meldungsdienst.dart';
import '../services/restore_queue_service.dart';

/// Fragt nach dem Faktor und reiht das Hochskalieren von [asset] ein
/// (#500) – aus dem Rechtsklickmenü des Vollbilds und aus dem Entwickeln.
///
/// Danach geht es ohne den Aufrufer weiter: Der Auftrag liegt in der
/// Warteschlange der Restaurierung und läuft auch, wenn Vollbild oder
/// Entwickeln längst geschlossen sind (siehe
/// [RestoreQueueService.hochskalieren]).
///
/// Die Grösse im Dialog ist die der Vorlage, die die Warteschlange rechnen
/// wird ([RestoreQueueService.hochskalierplan]): nach dem gespeicherten
/// Zuschnitt, oder die des KI-Entrauschens. [ungespeichert] sagt das
/// Entwickeln, wenn dort Änderungen noch nicht gespeichert sind – sie
/// zählen nicht, und der Dialog sagt das.
Future<void> hochskalierenAnbieten(
  BuildContext context, {
  required RestoreQueueService? warteschlange,
  required AssetData asset,
  bool ungespeichert = false,
}) async {
  final queue = warteschlange;
  // Gesperrte Fotos und Videos bietet niemand an; doppelt hält besser,
  // falls ein Menü es doch tut.
  if (queue == null || asset.isLocked || asset.type != 'IMAGE') return;
  Hochskalierplan plan;
  try {
    plan = await queue.hochskalierplan(asset);
  } catch (_) {
    // Ohne Plan wie bisher mit dem Original; die Warteschlange prüft ohnehin
    // noch einmal an dem, was sie wirklich rechnet.
    plan = (
      breite: asset.widthPx,
      hoehe: asset.heightPx,
      quelle: Hochskalierquelle.entwicklung,
      restaurierungUebergangen: false,
    );
  }
  if (!context.mounted) return;
  final faktor = await showDialog<int>(
    context: context,
    builder: (_) => HochskalierenDialog(
      breite: plan.breite,
      hoehe: plan.hoehe,
      modellInstalliert: queue.restoreHalter?.installiert == true,
      quelle: plan.quelle,
      restaurierungUebergangen: plan.restaurierungUebergangen,
      ungespeichert: ungespeichert,
    ),
  );
  if (faktor == null || !context.mounted) return;
  final t = AppTexte.of(context);
  try {
    await queue.hochskalieren(asset.id, faktor);
    melde.erfolg(t.hochskalierenEingereiht);
  } on RestaurierungNichtVerfuegbar {
    melde.warnung(t.hochskalierenModellFehlt);
  } catch (e) {
    melde.fehler(t.entwRestaurierungFehler('$e'));
  }
}

/// Der Dialog: Faktor 2×, 3× oder 4×, je mit der Grösse des Ergebnisses.
/// Gibt den gewählten Faktor zurück, oder `null`.
///
/// Gesperrt ist, was über die Grenzen in hochskalieren.dart ginge; die
/// Zeile sagt dann, welche – ein ausgegrauter Knopf ohne Grund lässt nur
/// raten. Vorausgewählt ist der grösste erlaubte Faktor. Ohne Modell steht
/// der Weg zu den Einstellungen da, und „Starten“ bleibt aus: dieselbe
/// Auskunft wie beim Knopf der Restaurierung im Entwickeln.
class HochskalierenDialog extends StatefulWidget {
  const HochskalierenDialog({
    super.key,
    required this.breite,
    required this.hoehe,
    required this.modellInstalliert,
    this.quelle = Hochskalierquelle.entwicklung,
    this.restaurierungUebergangen = false,
    this.ungespeichert = false,
  });

  /// Grösse der Vorlage – `null`, wenn sie nicht bekannt ist.
  final int? breite;
  final int? hoehe;
  final bool modellInstalliert;

  /// Woraus gerechnet wird, und ob dabei eine Restaurierung übergangen wird
  /// (siehe [Hochskalierplan]).
  final Hochskalierquelle quelle;
  final bool restaurierungUebergangen;

  /// Das Entwickeln hat Änderungen, die noch nicht gespeichert sind.
  final bool ungespeichert;

  @override
  State<HochskalierenDialog> createState() => _HochskalierenDialogState();
}

class _HochskalierenDialogState extends State<HochskalierenDialog> {
  late int? _faktor = switch ((widget.breite, widget.hoehe)) {
    (final b?, final h?) when b > 0 && h > 0 => groessterHochskalierfaktor(
      b,
      h,
    ),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final theme = Theme.of(context);
    final b = widget.breite;
    final h = widget.hoehe;
    final bekannt = b != null && h != null && b > 0 && h > 0;
    final hinweise = [
      if (widget.quelle == Hochskalierquelle.restaurierung)
        t.hochskalierenVorlageRestaurierung,
      if (widget.restaurierungUebergangen)
        t.hochskalierenRestaurierungUebergangen,
      if (widget.ungespeichert) t.hochskalierenUngespeichert,
    ];
    return AlertDialog(
      title: Text(t.hochskalierenTitel),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.hochskalierenText),
              for (final hinweis in hinweise) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(hinweis)),
                  ],
                ),
              ],
              if (!widget.modellInstalliert) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.hochskalierenModellFehlt,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (!bekannt)
                Text(t.restaurGrundAufloesung)
              else ...[
                Text(
                  t.hochskalierenQuelle(b, h, megapixel(b, h)),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                RadioGroup<int>(
                  groupValue: _faktor,
                  onChanged: (f) => setState(() => _faktor = f),
                  child: Column(
                    children: [
                      for (final f in hochskalierFaktoren)
                        _faktorzeile(t, theme, f, hochskalierziel(b, h, f)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(
          onPressed: widget.modellInstalliert && _faktor != null
              ? () => Navigator.pop(context, _faktor)
              : null,
          child: Text(t.allgStarten),
        ),
      ],
    );
  }

  Widget _faktorzeile(
    AppTexte t,
    ThemeData theme,
    int faktor,
    Hochskalierziel ziel,
  ) {
    final groesse = t.hochskalierenZiel(
      ziel.breite,
      ziel.hoehe,
      megapixel(ziel.breite, ziel.hoehe),
    );
    final sperre = switch (ziel.sperre) {
      Hochskaliersperre.kante => t.hochskalierenGesperrtKante(
        hochskalierMaxKante,
      ),
      Hochskaliersperre.pixel => t.hochskalierenGesperrtPixel(
        hochskalierMaxPixel ~/ 1000000,
      ),
      null => null,
    };
    return RadioListTile<int>(
      value: faktor,
      enabled: sperre == null,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(t.hochskalierenFaktor(faktor)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(groesse),
          if (sperre != null)
            Text(sperre, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
    );
  }
}
