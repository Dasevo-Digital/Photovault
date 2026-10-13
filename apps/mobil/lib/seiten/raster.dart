import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/rasterzeile.dart';

import '../bilder.dart';
import '../sitzung.dart';
import 'betrachter.dart';

/// Aufnahmen als Raster – auf Wunsch nach Tagen gegliedert, wie in der
/// Zeitleiste. Ein Tipp öffnet den Betrachter mit genau dieser Liste.
class AufnahmenRaster extends StatelessWidget {
  const AufnahmenRaster({
    super.key,
    required this.sitzung,
    required this.zeilen,
    this.nachTagen = false,
    this.kopf,
  });

  final Sitzung sitzung;
  final List<Rasterzeile> zeilen;
  final bool nachTagen;

  /// Etwas über dem Raster (z. B. das Suchfeld), das mitscrollt.
  final Widget? kopf;

  static const _spalten = 4;

  void _oeffne(BuildContext context, int index) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          Betrachter(sitzung: sitzung, zeilen: zeilen, start: index),
    ),
  );

  Widget _kachel(BuildContext context, int i) {
    final z = zeilen[i];
    return GestureDetector(
      onTap: () => _oeffne(context, i),
      child: Miniatur(
        paths: sitzung.paths,
        relativ: z.thumbnailRelativePath,
        video: z.type == 'VIDEO',
        favorit: z.isFavorite,
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
      (context, i) => _kachel(context, von + i),
      childCount: bis - von,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final slivers = <Widget>[if (kopf != null) SliverToBoxAdapter(child: kopf)];
    if (!nachTagen) {
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
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return CustomScrollView(slivers: slivers);
  }
}
