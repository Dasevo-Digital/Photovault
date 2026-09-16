import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';

/// Welche Fotos zu einer Reise oder Aktivität gehören.
///
/// **Ein Raster mit Häkchen statt zweier Wege.** Hinzufügen und Entfernen
/// sind dieselbe Frage – „gehört das dazu?" –, und zwei getrennte
/// Bildschirme dafür wären zwei Orte für eine Sache. Was angehakt ist,
/// gehört dazu; beim Sichern wird der Unterschied gebildet.
///
/// **Der Zeitraum ist nur die Voreinstellung, nicht die Grenze.** Beim
/// Anlegen war er die ganze Eingabe (siehe `frageZeitraum`) – hier geht
/// es gerade um die Ausnahmen: das Foto vom Vorabend, das dazugehört,
/// und das aus der Mittagspause, das nicht.
///
/// **Was nicht im Bild steht, bleibt unangetastet.** Die Arbeitsmenge
/// beginnt bei den bereits zugeordneten Aufnahmen und wird nur durch
/// Antippen geändert. Ein Foto, das ausserhalb des gezeigten Zeitraums
/// liegt und dazugehört, fiele sonst beim Sichern still heraus.
class AufnahmenWaehlenScreen extends StatefulWidget {
  final LibraryState library;
  final String titel;

  /// Was jetzt schon dazugehört.
  final Set<String> vorhanden;

  /// Der Zeitraum der Reise/Aktivität – die Voreinstellung der Ansicht.
  ///
  /// `null` bei etwas, das keinen Zeitraum hat: Ein Album ist eine
  /// Sammlung und keine Zeitspanne. Dann entfällt die Marke, und die
  /// Ansicht steht von Anfang an auf der ganzen Bibliothek.
  final DateTime? von;
  final DateTime? bis;

  const AufnahmenWaehlenScreen({
    super.key,
    required this.library,
    required this.titel,
    required this.vorhanden,
    this.von,
    this.bis,
  });

  /// Ob es überhaupt einen Zeitraum gibt, auf den sich einschränken lässt.
  bool get hatZeitraum => von != null && bis != null;

  @override
  State<AufnahmenWaehlenScreen> createState() => _AufnahmenWaehlenScreenState();
}

/// Welcher Ausschnitt der Bibliothek gezeigt wird.
enum _Umfang { zeitraum, alle }

class _AufnahmenWaehlenScreenState extends State<AufnahmenWaehlenScreen> {
  late final Set<String> _gewaehlt = {...widget.vorhanden};
  late _Umfang _umfang =
      widget.hatZeitraum ? _Umfang.zeitraum : _Umfang.alle;
  /// Schmale Zeilen: Das Raster zeigt Kachel, Name und Datum – die
  /// vollen 56 Spalten dafür zu lesen kostete an der gewachsenen
  /// Bibliothek 80 ms statt 30, und umgewandelt wurden sie hier ohnehin.
  List<Rasterzeile> _gezeigt = const [];
  bool _laedt = true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _laedt = true);
    final db = widget.library.db;
    final gefragt = _umfang;
    // Ein Tag Luft an beiden Enden: Der Zeitraum stammt aus den
    // Aufnahmen selbst, das Foto vom Vorabend liegt also grundsätzlich
    // ausserhalb – und genau um solche geht es hier.
    final liste = gefragt == _Umfang.alle
        ? await db.alleRasterzeilen()
        : await db.rasterzeilenImZeitraum(
            widget.von!.subtract(const Duration(days: 1)),
            widget.bis!.add(const Duration(days: 1)));
    if (!mounted || gefragt != _umfang) return;
    setState(() {
      _gezeigt = liste;
      _laedt = false;
    });
  }

  void _umschalten(_Umfang neu) {
    if (neu == _umfang) return;
    setState(() => _umfang = neu);
    _laden();
  }

  void _tippen(Rasterzeile a) => setState(() {
        if (!_gewaehlt.remove(a.id)) _gewaehlt.add(a.id);
      });

  /// Wie viele der Gewählten gerade gar nicht zu sehen sind.
  ///
  /// Ohne diese Zeile sähe „12 gewählt" bei acht sichtbaren Häkchen wie
  /// ein Fehler aus.
  int get _ausserhalb {
    final sichtbar = {for (final a in _gezeigt) a.id};
    return _gewaehlt.where((id) => !sichtbar.contains(id)).length;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final datum = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titel),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_gewaehlt),
            child: Text(t.allgFertig),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm,
                AppSpacing.md, AppSpacing.xs),
            // Umbrechend und nicht in einer Reihe: Die Zeitraum-Marke
            // trägt zwei ausgeschriebene Daten und ist damit länger als
            // ein schmales Fenster – in einer Reihe lief sie über.
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (widget.hatZeitraum)
                  ChoiceChip(
                    label: Text(t.aufnahmenWahlZeitraum(
                        datum.format(widget.von!), datum.format(widget.bis!))),
                    selected: _umfang == _Umfang.zeitraum,
                    onSelected: (_) => _umschalten(_Umfang.zeitraum),
                  ),
                ChoiceChip(
                  label: Text(t.aufnahmenWahlAlle),
                  selected: _umfang == _Umfang.alle,
                  onSelected: (_) => _umschalten(_Umfang.alle),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [
                  t.aufnahmenWahlGewaehlt(_gewaehlt.length),
                  if (_ausserhalb > 0) t.aufnahmenWahlAusserhalb(_ausserhalb),
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: _laedt
                ? const Center(child: CircularProgressIndicator())
                : _gezeigt.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(t.aufnahmenWahlLeer,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: farben.onSurfaceVariant)),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                        itemCount: _gezeigt.length,
                        itemBuilder: (context, i) => AssetThumbnailTile(
                          asset: _gezeigt[i],
                          paths: widget.library.paths,
                          selected: _gewaehlt.contains(_gezeigt[i].id),
                          onTap: () => _tippen(_gezeigt[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
