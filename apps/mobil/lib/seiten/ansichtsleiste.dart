import 'package:flutter/material.dart';
import 'package:kern/services/listengliederung.dart';
import 'package:kern/services/listenspalten.dart';
import 'package:kern/services/rasterstufen.dart';
import 'package:kern/services/sortierung.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'rueckblick.dart';

/// Die Leiste über der Zeitleiste (Issues #194, #195) – wie am Rechner und
/// im Browser: Raster oder Liste, die Reihenfolge, und je nach Ansicht
/// Tage/Monate, Form und Grösse oder Gliederung und Spalten. Die Wahl gilt
/// für dieses Gerät.
class Ansichtsleiste extends StatelessWidget {
  const Ansichtsleiste({super.key, required this.sitzung});

  final Sitzung sitzung;

  static String sortierungText(AppTexte t, Rastersortierung s) => switch (s) {
    Rastersortierung.aufnahmeNeu => t.sortAufnahmeNeu,
    Rastersortierung.aufnahmeAlt => t.sortAufnahmeAlt,
    Rastersortierung.importNeu => t.sortImportNeu,
    Rastersortierung.name => t.sortName,
    Rastersortierung.bewertung => t.sortBewertung,
    Rastersortierung.groesse => t.sortGroesse,
  };

  static String gliederungText(AppTexte t, ListenGruppierung g) => switch (g) {
    ListenGruppierung.monat => t.gruppeMonat,
    ListenGruppierung.tag => t.gruppeTag,
    ListenGruppierung.kamera => t.gruppeKamera,
    ListenGruppierung.keine => t.gruppeKeine,
  };

  static String spaltenText(AppTexte t, Listenspalte s) => switch (s) {
    Listenspalte.dateiname => t.listeSpalteDateiname,
    Listenspalte.datum => t.listeSpalteDatum,
    Listenspalte.kamera => t.listeSpalteKamera,
    Listenspalte.objektiv => t.listeSpalteObjektiv,
    Listenspalte.belichtung => t.listeSpalteBelichtung,
    Listenspalte.bewertung => t.listeSpalteBewertung,
    Listenspalte.farbe => t.listeSpalteFarbe,
    Listenspalte.masse => t.listeSpalteMasse,
    Listenspalte.groesse => t.listeSpalteGroesse,
    Listenspalte.art => t.listeSpalteArt,
    Listenspalte.ort => t.listeSpalteOrt,
  };

  /// Die Spalten an- und abschalten – die letzte bleibt (siehe
  /// [Listenspaltenwahl.umgeschaltet]).
  Future<void> _spaltenWaehlen(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => ListenableBuilder(
          listenable: sitzung,
          builder: (context, _) {
            final t = AppTexte.of(context);
            final wahl = sitzung.listenspalten;
            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        t.listeSpalten,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    for (final s in Listenspalte.values)
                      CheckboxListTile(
                        dense: true,
                        value: wahl.zeigt(s),
                        title: Text(spaltenText(t, s)),
                        onChanged: (_) => sitzung.setzeAnsicht(
                          listenspalten: wahl.umgeschaltet(s),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sitzung,
    builder: (context, _) {
      final t = AppTexte.of(context);
      final s = sitzung;
      final liste = s.alsListe;
      final reihen = s.form == Zeitleistenform.reihen;
      final spalten = s.rasterspalten;
      final nachDatum = nachAufnahmedatum(s.sortierung);
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
        child: Row(
          children: [
            // Die Jahre auf einen Blick (Issue #196), wie am Rechner: der
            // Kalender, ein Tipp führt zu den Monaten.
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: t.ansichtJahre,
              icon: const Icon(Icons.calendar_view_month_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(t.ansichtJahre)),
                    body: Kalender(sitzung: s),
                  ),
                ),
              ),
            ),
            SegmentedButton<bool>(
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.grid_view, size: 18),
                  tooltip: t.ansichtRaster,
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.view_list_outlined, size: 18),
                  tooltip: t.ansichtListe,
                ),
              ],
              selected: {liste},
              onSelectionChanged: (w) => s.setzeAnsicht(alsListe: w.first),
            ),
            const Spacer(),
            // Als Menü und nicht als Auswahlliste: Neben den Knöpfen wäre für
            // den Namen der Reihenfolge auf dem Telefon kaum Platz.
            PopupMenuButton<Rastersortierung>(
              tooltip: t.ansichtReihenfolge,
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.sort),
              initialValue: s.sortierung,
              onSelected: (x) => s.setzeAnsicht(sortierung: x),
              itemBuilder: (context) => [
                for (final x in Rastersortierung.values)
                  CheckedPopupMenuItem(
                    value: x,
                    checked: x == s.sortierung,
                    child: Text(sortierungText(t, x)),
                  ),
              ],
            ),
            if (liste) ...[
              // Gliedern lässt sich nur, was nach dem Datum geordnet ist.
              if (nachDatum)
                PopupMenuButton<ListenGruppierung>(
                  padding: EdgeInsets.zero,
                  tooltip: t.ansichtGliederung,
                  icon: const Icon(Icons.segment),
                  initialValue: s.gliederung,
                  onSelected: (g) => s.setzeAnsicht(gliederung: g),
                  itemBuilder: (context) => [
                    for (final g in ListenGruppierung.values)
                      CheckedPopupMenuItem(
                        value: g,
                        checked: g == s.gliederung,
                        child: Text(gliederungText(t, g)),
                      ),
                  ],
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: t.listeSpalten,
                icon: const Icon(Icons.view_column_outlined),
                onPressed: () => _spaltenWaehlen(context),
              ),
            ] else ...[
              // Monate und Tage gibt es nur nach dem Aufnahmedatum.
              if (nachDatum)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: s.nurMonate
                      ? t.ansichtNachTagen
                      : t.ansichtNurMonate,
                  isSelected: !s.nurMonate,
                  icon: const Icon(Icons.calendar_view_day_outlined),
                  selectedIcon: const Icon(Icons.calendar_view_day),
                  onPressed: () => s.setzeAnsicht(nurMonate: !s.nurMonate),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: reihen ? t.ansichtQuadrate : t.ansichtReihen,
                icon: Icon(
                  reihen
                      ? Icons.grid_view_outlined
                      : Icons.view_stream_outlined,
                ),
                onPressed: () => s.setzeAnsicht(
                  form: reihen
                      ? Zeitleistenform.quadrate
                      : Zeitleistenform.reihen,
                ),
              ),
              // Kleiner heisst mehr Fotos nebeneinander.
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: t.ansichtKleiner,
                icon: const Icon(Icons.zoom_out),
                onPressed: spalten >= 6
                    ? null
                    : () => s.setzeRasterspalten(spalten + 1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: t.ansichtGroesser,
                icon: const Icon(Icons.zoom_in),
                onPressed: spalten <= 2
                    ? null
                    : () => s.setzeRasterspalten(spalten - 1),
              ),
            ],
          ],
        ),
      );
    },
  );
}
