import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/aktivitaeten.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'aktivitaetsart_anzeige.dart';

/// Das Ergebnis von [frageZeitraum].
typedef Zeitraumangabe = ({
  String name,
  DateTime von,
  DateTime bis,

  /// Die Kennung der Art, wie sie in der Datenbank steht – auch eine
  /// selbst eingetragene. `null`, wenn nicht nach einer Art gefragt
  /// wurde (bei einer Reise).
  String? art,
});

/// Fragt nach Name und Zeitraum – für eine von Hand angelegte Reise oder
/// Aktivität.
///
/// **Warum der Zeitraum die ganze Eingabe ist.** Zugeordnet wird in dieser
/// App über die Fotos und nicht über den Kalender: Der Zeitraum einer
/// Reise ist selbst nur aus ihren Aufnahmen abgeleitet. Wer von Hand
/// anlegt, nennt deshalb den Zeitraum, und die Bilder darin kommen mit.
/// Ein Auswahlraster für einzelne Fotos wäre der zweite Schritt.
///
/// **Die Zahl der Fotos steht schon im Fenster**, und sie zählt bei jeder
/// Änderung neu. Ohne sie legt man eine Reise an und sieht erst danach,
/// dass sie leer ist – und weiss nicht, ob das am Zeitraum liegt oder
/// daran, dass die Fotos noch nicht importiert sind.
///
/// Gibt `null` zurück, wenn abgebrochen wurde.
Future<Zeitraumangabe?> frageZeitraum(
  BuildContext context, {
  required String titel,
  required AppDatabase db,
  bool mitArt = false,
  DateTime? von,
  DateTime? bis,
  String? name,
}) =>
    showDialog<Zeitraumangabe>(
      context: context,
      builder: (dialog) => _ZeitraumDialog(
          titel: titel,
          db: db,
          mitArt: mitArt,
          von: von,
          bis: bis,
          name: name),
    );

class _ZeitraumDialog extends StatefulWidget {
  final String titel;
  final AppDatabase db;
  final bool mitArt;

  /// Vorbelegung – für den Weg aus einer Reise heraus: Dort ist der
  /// Zeitraum schon bekannt, und wer ihn erst eintippen muss, tippt ihn
  /// falsch ab.
  final DateTime? von;
  final DateTime? bis;
  final String? name;

  const _ZeitraumDialog(
      {required this.titel,
      required this.db,
      required this.mitArt,
      this.von,
      this.bis,
      this.name});

  @override
  State<_ZeitraumDialog> createState() => _ZeitraumDialogState();
}

class _ZeitraumDialogState extends State<_ZeitraumDialog> {
  late final _name = TextEditingController(text: widget.name ?? '');
  late DateTime _von = widget.von ?? DateTime.now();
  late DateTime _bis = widget.bis ?? DateTime.now();
  String _art = Aktivitaetsart.wanderung.kennung;
  int? _anzahl;

  @override
  void initState() {
    super.initState();
    _zaehle();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Zählt die Fotos im gewählten Zeitraum.
  ///
  /// Ein Zähler je Änderung und nicht die Liste: Gezeigt wird eine Zahl,
  /// und die vollen Zeilen zu holen wäre bei einem Jahr Zeitraum eine
  /// spürbare Abfrage für nichts. **Genau das stand hier trotzdem** –
  /// `aufnahmenImZeitraum(...).length`, also die halbe Bibliothek für
  /// eine Ziffer, bei jeder Verschiebung des Datums.
  Future<void> _zaehle() async {
    final n = await widget.db.zahlImZeitraum(_von, _bis);
    if (mounted) setState(() => _anzahl = n);
  }

  Future<void> _waehleDatum({required bool anfang}) async {
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: anfang ? _von : _bis,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (gewaehlt == null || !mounted) return;
    setState(() {
      if (anfang) {
        _von = gewaehlt;
        // Ein Ende vor dem Anfang ist keine Eingabe, sondern ein
        // Versehen – es wandert mit statt eine Fehlermeldung zu tragen.
        if (_bis.isBefore(_von)) _bis = gewaehlt;
      } else {
        _bis = gewaehlt;
        if (_bis.isBefore(_von)) _von = gewaehlt;
      }
      _anzahl = null;
    });
    await _zaehle();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final format = DateFormat.yMMMMd(sprache);
    final farben = Theme.of(context).colorScheme;
    final gueltig = _name.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(widget.titel),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: t.zeitraumName,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.mitArt) ...[
              const SizedBox(height: AppSpacing.md),
              // Kein Auswahlfeld mit fester Liste, sondern derselbe
              // Dialog wie in der Aktivität selbst: Nur er kennt die
              // selbst eingetragenen Arten und den Weg zu einer neuen.
              InkWell(
                onTap: () async {
                  final gewaehlt = await frageAktivitaetsart(context,
                      db: widget.db, aktuell: _art);
                  if (!mounted || gewaehlt == null) return;
                  setState(() => _art = gewaehlt);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: t.zeitraumArt,
                    border: const OutlineInputBorder(),
                  ),
                  child: Row(children: [
                    Icon(symbolFuerKennung(_art), size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(nameFuerKennung(t, _art))),
                    const Icon(Icons.arrow_drop_down),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(format.format(_von)),
                  onPressed: () => _waehleDatum(anfang: true),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.arrow_forward, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(format.format(_bis)),
                  onPressed: () => _waehleDatum(anfang: false),
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            Text(
              _anzahl == null
                  ? t.zeitraumZaehlt
                  : t.zeitraumFotos(_anzahl!),
              style: TextStyle(
                fontSize: 12,
                color: _anzahl == 0 ? context.semantik.warnung : farben.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(
          // Ein leerer Name ist der einzige Grund abzulehnen. Null Fotos
          // sind erlaubt: Wer den Zeitraum kennt und die Bilder erst noch
          // importiert, soll den Eintrag schon anlegen dürfen.
          onPressed: gueltig
              ? () => Navigator.pop(
                    context,
                    (
                      name: _name.text.trim(),
                      von: _von,
                      bis: _bis,
                      art: widget.mitArt ? _art : null,
                    ),
                  )
              : null,
          child: Text(t.allgUebernehmen),
        ),
      ],
    );
  }
}
