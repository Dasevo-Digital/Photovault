import 'package:flutter/material.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/laendernamen.dart';
import 'package:kern/services/ortsuebersicht.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'raster.dart';

/// Die Orte der Bibliothek (Issue #173) – wie im Browser (web/app.js,
/// zeigeOrte) und wie „Orte“ in Immich: die Länder mit Titelbild, darin
/// die Städte. Gerechnet im Kern (ortsuebersicht.dart).
class Orte extends StatefulWidget {
  const Orte({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<Orte> createState() => _OrteState();
}

class _OrteState extends State<Orte> {
  late final Future<List<Land>> _daten = ortsuebersicht(widget.sitzung.db);

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).languageCode;
    return FutureBuilder<List<Land>>(
      future: _daten,
      builder: (context, snap) {
        final laender = snap.data;
        if (laender == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (laender.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(t.orteLeer, textAlign: TextAlign.center),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.74,
          ),
          itemCount: laender.length,
          itemBuilder: (context, i) {
            final l = laender[i];
            final name = landAnzeige(l.land.land, sprache);
            return Ortskachel(
              sitzung: widget.sitzung,
              ort: l.land,
              titel: name,
              zusatz: switch (l.staedte.length) {
                0 => null,
                1 => l.staedte.single.stadt,
                final n => t.orteAnzahlOrte(n),
              },
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OrtSeite(
                    sitzung: widget.sitzung,
                    land: l,
                    landName: name,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Ein Ort als Kachel: Titelbild, Name, Anzahl.
class Ortskachel extends StatelessWidget {
  const Ortskachel({
    super.key,
    required this.sitzung,
    required this.ort,
    required this.titel,
    required this.onTap,
    this.zusatz,
  });

  final Sitzung sitzung;
  final Ort ort;
  final String titel;
  final String? zusatz;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final leise = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Miniatur(paths: sitzung.paths, relativ: ort.miniatur),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            titel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            t.orteAufnahmen(ort.anzahl),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: leise,
          ),
          if (zusatz != null)
            Text(
              zusatz!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: leise,
            ),
        ],
      ),
    );
  }
}

/// Ein Land (oben seine Städte) oder eine Stadt darin, mit den Aufnahmen.
class OrtSeite extends StatelessWidget {
  const OrtSeite({
    super.key,
    required this.sitzung,
    required this.land,
    required this.landName,
    this.stadt,
  });

  final Sitzung sitzung;
  final Land land;
  final String landName;
  final Ort? stadt;

  @override
  Widget build(BuildContext context) {
    final s = stadt;
    final staedte = s == null && land.staedte.length > 1 ? land.staedte : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(s == null ? landName : '${s.stadt}, $landName'),
      ),
      body: FutureBuilder<List<Rasterzeile>>(
        future: aufnahmenAmOrt(
          sitzung.db,
          land: land.land.land,
          stadt: s?.stadt,
        ),
        builder: (context, snap) {
          final zeilen = snap.data;
          if (zeilen == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final raster = AufnahmenRaster(
            sitzung: sitzung,
            zeilen: zeilen,
            nachTagen: true,
          );
          if (staedte == null) return raster;
          return Column(
            children: [
              SizedBox(
                height: 176,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  scrollDirection: Axis.horizontal,
                  itemCount: staedte.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => SizedBox(
                    width: 116,
                    child: Ortskachel(
                      sitzung: sitzung,
                      ort: staedte[i],
                      titel: staedte[i].stadt ?? '',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OrtSeite(
                            sitzung: sitzung,
                            land: land,
                            landName: landName,
                            stadt: staedte[i],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: raster),
            ],
          );
        },
      ),
    );
  }
}
