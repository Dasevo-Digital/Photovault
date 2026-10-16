import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/rasterzeile.dart';

import '../bilder.dart';
import '../lokal/lokalbetrachter.dart';
import '../lokal/ungesichert.dart';
import '../sitzung.dart';
import 'auswahl.dart';
import 'betrachter.dart';

/// Aufnahmen als Raster – auf Wunsch nach Tagen gegliedert, wie in der
/// Zeitleiste. Ein Tipp öffnet den Betrachter mit genau dieser Liste;
/// langes Drücken beginnt eine Auswahl (Issue #128), dann sammelt jeder
/// Tipp weitere ein, und unten erscheint die Leiste mit den Aktionen.
class AufnahmenRaster extends StatefulWidget {
  const AufnahmenRaster({
    super.key,
    required this.sitzung,
    required this.zeilen,
    this.nachTagen = false,
    this.kopf,
    this.lokal = const {},
  });

  final Sitzung sitzung;
  final List<Rasterzeile> zeilen;
  final bool nachTagen;

  /// Zeilen aus [zeilen], die nur auf dem Telefon liegen (Issue #127),
  /// nach ihrer Kennung – sie zeigen die Fotomediathek, nicht die
  /// Bibliothek, und lassen sich nicht auswählen.
  final Map<String, LokaleAufnahme> lokal;

  /// Etwas über dem Raster (z. B. das Suchfeld), das mitscrollt.
  final Widget? kopf;

  @override
  State<AufnahmenRaster> createState() => _AufnahmenRasterState();
}

class _AufnahmenRasterState extends State<AufnahmenRaster> {
  static const _spalten = 4;

  final _auswahl = <String>{};

  bool get _waehlt => _auswahl.isNotEmpty;

  @override
  void didUpdateWidget(AufnahmenRaster alt) {
    super.didUpdateWidget(alt);
    // Was aus der Liste verschwand (Papierkorb, anderer Filter), ist auch
    // nicht mehr ausgewählt.
    final da = {for (final z in widget.zeilen) z.id};
    _auswahl.removeWhere((id) => !da.contains(id));
  }

  void _oeffne(int index) {
    final z = widget.zeilen[index];
    final l = widget.lokal[z.id];
    final Widget seite;
    if (l != null) {
      // Nur die vom Telefon, in der Reihenfolge des Rasters.
      final lokale = [for (final x in widget.zeilen) ?widget.lokal[x.id]];
      seite = Lokalbetrachter(
        sitzung: widget.sitzung,
        aufnahmen: lokale,
        start: lokale.indexOf(l),
      );
    } else {
      final server = [
        for (final x in widget.zeilen)
          if (!widget.lokal.containsKey(x.id)) x,
      ];
      seite = Betrachter(
        sitzung: widget.sitzung,
        zeilen: server,
        start: server.indexWhere((x) => x.id == z.id),
      );
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => seite));
  }

  void _schalte(String id) {
    if (widget.lokal.containsKey(id)) return;
    setState(() {
      if (!_auswahl.remove(id)) _auswahl.add(id);
    });
  }

  Widget _kachel(int i) {
    final z = widget.zeilen[i];
    final l = widget.lokal[z.id];
    final gewaehlt = _auswahl.contains(z.id);
    final farben = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _waehlt && l == null ? _schalte(z.id) : _oeffne(i),
      onLongPress: () => _schalte(z.id),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedPadding(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.all(gewaehlt ? 8 : 0),
            child: Miniatur(
              paths: widget.sitzung.paths,
              relativ: z.thumbnailRelativePath,
              bild: l?.bild,
              video: z.type == 'VIDEO',
              favorit: z.isFavorite,
            ),
          ),
          if (l != null)
            const Positioned(
              right: 4,
              top: 4,
              child: Icon(
                Icons.cloud_off_outlined,
                color: Colors.white,
                size: 18,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          if (gewaehlt) ...[
            ColoredBox(color: farben.primary.withValues(alpha: 0.15)),
            Positioned(
              left: 4,
              top: 4,
              child: Icon(
                Icons.check_circle,
                color: farben.primary,
                shadows: const [Shadow(color: Colors.white, blurRadius: 4)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  SliverGrid _gitter(int von, int bis) => SliverGrid(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: _spalten,
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
    ),
    delegate: SliverChildBuilderDelegate(
      (context, i) => _kachel(von + i),
      childCount: bis - von,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final zeilen = widget.zeilen;
    final slivers = <Widget>[
      if (widget.kopf != null) SliverToBoxAdapter(child: widget.kopf),
    ];
    if (!widget.nachTagen) {
      slivers.add(_gitter(0, zeilen.length));
    } else {
      final sprache = Localizations.localeOf(context).toLanguageTag();
      final format = DateFormat.yMMMMEEEEd(sprache);
      var von = 0;
      while (von < zeilen.length) {
        final tag = DateUtils.dateOnly(zeilen[von].fileCreatedAt.toLocal());
        var bis = von + 1;
        while (bis < zeilen.length &&
            DateUtils.dateOnly(zeilen[bis].fileCreatedAt.toLocal()) == tag) {
          bis++;
        }
        slivers
          ..add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                child: Text(
                  format.format(tag),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
          )
          ..add(_gitter(von, bis));
        von = bis;
      }
    }
    // Unter dem letzten Rand bleibt Platz für die Leiste.
    slivers.add(
      SliverToBoxAdapter(child: SizedBox(height: _waehlt ? 120 : 24)),
    );
    return Stack(
      children: [
        CustomScrollView(slivers: slivers),
        if (_waehlt)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Auswahlleiste(
              sitzung: widget.sitzung,
              zeilen: [
                for (final z in zeilen)
                  if (_auswahl.contains(z.id)) z,
              ],
              aufheben: () => setState(_auswahl.clear),
            ),
          ),
      ],
    );
  }
}
