import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/reiseuebersicht.dart';
import 'package:latlong2/latlong.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'betrachter.dart';
import 'karte.dart';
import 'raster.dart';

/// Reisen und Aktivitäten – dieselbe Gliederung wie im Browser (web/app.js,
/// zeigeReisen): oben die Reisen, darunter die Aktivitäten; eine Reise
/// zeigt ihre Aktivitäten über den Aufnahmen, eine Aktivität ihre Route.
/// Gerechnet wird im Kern (reiseuebersicht.dart), wie auf dem Server.
class ReisenSeite extends StatefulWidget {
  const ReisenSeite({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<ReisenSeite> createState() => _ReisenSeiteState();
}

class _ReisenSeiteState extends State<ReisenSeite> {
  late final Future<(List<Reisekarte>, List<Aktivitaetskarte>)> _daten =
      _lade();

  Future<(List<Reisekarte>, List<Aktivitaetskarte>)> _lade() async {
    final db = widget.sitzung.db;
    return (await reisekarten(db), await aktivitaetskarten(db));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return FutureBuilder(
      future: _daten,
      builder: (context, snap) {
        final daten = snap.data;
        if (daten == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final (reisen, aktivitaeten) = daten;
        final sitzung = widget.sitzung;
        return CustomScrollView(
          slivers: [
            if (reisen.isEmpty) _leer(context, t.reisenLeer),
            _Kartengitter(
              karten: [
                for (final r in reisen) reisekarteFuer(context, sitzung, r),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                child: Text(
                  t.aktivitaetenTitel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            if (aktivitaeten.isEmpty) _leer(context, t.aktivitaetenLeer),
            _Kartengitter(
              karten: [
                for (final a in aktivitaeten)
                  aktivitaetskarteFuer(context, sitzung, a, inReise: false),
              ],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }

  Widget _leer(BuildContext context, String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

/// Eine Reise, wie die Liste sie zeigt.
Widget reisekarteFuer(BuildContext context, Sitzung sitzung, Reisekarte r) {
  final t = AppTexte.of(context);
  final sprache = Localizations.localeOf(context).toLanguageTag();
  final datum = datumMittel(sprache);
  return _Karte(
    sitzung: sitzung,
    bild: r.titelbild,
    titel: r.reise.name,
    untertitel:
        '${datum.format(r.reise.von.toLocal())} – '
        '${datum.format(r.reise.bis.toLocal())} · ${t.anzahlAufnahmen(r.anzahl)}',
    zusatz: ortszeileText(r.ort, sprache, t.ortWeitere),
    onTap: () => _oeffne(
      context,
      r.reise.name,
      ReiseSeite(sitzung: sitzung, reiseId: r.reise.id),
    ),
  );
}

/// Eine Aktivität, wie die Liste sie zeigt – in ihrer Reise ohne den
/// Hinweis, zu welcher Reise sie gehört.
Widget aktivitaetskarteFuer(
  BuildContext context,
  Sitzung sitzung,
  Aktivitaetskarte a, {
  required bool inReise,
}) {
  final t = AppTexte.of(context);
  final sprache = Localizations.localeOf(context).toLanguageTag();
  final k = a.aktivitaet;
  final zusatz = [
    ?ortszeileText(a.ort, sprache, t.ortWeitere),
    if (!inReise && a.reisename != null) t.gehoertZu(a.reisename!),
  ].join(' · ');
  return _Karte(
    sitzung: sitzung,
    bild: a.titelbild,
    titel: k.name,
    untertitel:
        '${datumMittel(sprache).format(k.von.toLocal())} · '
        '${t.anzahlAufnahmen(a.anzahl)}',
    zusatz: zusatz.isEmpty ? null : zusatz,
    kennzeichen: (symbolFuerArt(k.art), nameFuerArt(t, k.art)),
    onTap: () => _oeffne(
      context,
      k.name,
      AktivitaetSeite(sitzung: sitzung, aktivitaetId: k.id),
    ),
  );
}

void _oeffne(BuildContext context, String titel, Widget inhalt) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(titel)),
          body: inhalt,
        ),
      ),
    );

/// Das Datum wie im Browser (`dateStyle: 'medium'`): „30.08.2026“ bzw.
/// „Aug 30, 2026“.
DateFormat datumMittel(String sprache) => sprache.startsWith('de')
    ? DateFormat('dd.MM.yyyy', sprache)
    : DateFormat.yMMMd(sprache);

IconData symbolFuerArt(String kennung) => switch (kennung) {
  'spaziergang' => Icons.directions_walk,
  'wanderung' => Icons.hiking,
  'radtour' => Icons.directions_bike,
  'ausflug' => Icons.directions_car_outlined,
  'besichtigung' => Icons.museum_outlined,
  'bootsfahrt' => Icons.directions_boat_outlined,
  _ => Icons.explore_outlined,
};

/// Der Name der Art; eine selbst eingetragene ist ihr eigener Name.
String nameFuerArt(AppTexte t, String kennung) => switch (kennung) {
  'spaziergang' => t.aktArtSpaziergang,
  'wanderung' => t.aktArtWanderung,
  'radtour' => t.aktArtRadtour,
  'ausflug' => t.aktArtAusflug,
  'besichtigung' => t.aktArtBesichtigung,
  'bootsfahrt' => t.aktArtBootsfahrt,
  'sonstiges' => t.aktArtSonstiges,
  _ => kennung,
};

String dauerText(AppTexte t, Duration d) {
  final minuten = d.inMinutes;
  return minuten < 60
      ? t.dauerMinuten(minuten)
      : t.dauerStunden(minuten ~/ 60, minuten % 60);
}

/// Eine Reise mit ihren Aktivitäten über den Aufnahmen, nach Tagen.
class ReiseSeite extends StatefulWidget {
  const ReiseSeite({super.key, required this.sitzung, required this.reiseId});

  final Sitzung sitzung;
  final String reiseId;

  @override
  State<ReiseSeite> createState() => _ReiseSeiteState();
}

class _ReiseSeiteState extends State<ReiseSeite> {
  late final _daten = _lade();

  Future<(ReisenData?, List<AssetData>, List<Aktivitaetskarte>)> _lade() async {
    final db = widget.sitzung.db;
    return (
      await db.reise(widget.reiseId),
      await db.aufnahmenDerReise(widget.reiseId),
      await aktivitaetskarten(db, reiseId: widget.reiseId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return FutureBuilder(
      future: _daten,
      builder: (context, snap) {
        final daten = snap.data;
        if (daten == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final (reise, aufnahmen, aktivitaeten) = daten;
        if (reise == null) return const SizedBox.shrink();
        final sprache = Localizations.localeOf(context).toLanguageTag();
        final datum = datumMittel(sprache);
        final farben = Theme.of(context).colorScheme;
        return AufnahmenRaster(
          sitzung: widget.sitzung,
          zeilen: [for (final a in aufnahmen) Rasterzeile.aus(a)],
          nachTagen: true,
          kopf: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${datum.format(reise.von.toLocal())} – '
                  '${datum.format(reise.bis.toLocal())} · '
                  '${t.anzahlAufnahmen(aufnahmen.length)}',
                  style: TextStyle(color: farben.onSurfaceVariant),
                ),
                if ((reise.notiz ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(reise.notiz!),
                  ),
                if (aktivitaeten.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    t.aktivitaetenTitel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 236,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: aktivitaeten.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) => SizedBox(
                        width: 160,
                        child: aktivitaetskarteFuer(
                          context,
                          widget.sitzung,
                          aktivitaeten[i],
                          inReise: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Eine Aktivität: Art, Tag, Uhrzeit, Dauer, Strecke, Ort, Reise, Notiz,
/// die Route aus den verorteten Aufnahmen und die Aufnahmen selbst.
class AktivitaetSeite extends StatefulWidget {
  const AktivitaetSeite({
    super.key,
    required this.sitzung,
    required this.aktivitaetId,
  });

  final Sitzung sitzung;
  final String aktivitaetId;

  @override
  State<AktivitaetSeite> createState() => _AktivitaetSeiteState();
}

class _AktivitaetSeiteState extends State<AktivitaetSeite> {
  late final _daten = aktivitaetsansicht(
    widget.sitzung.db,
    widget.aktivitaetId,
  );

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return FutureBuilder(
      future: _daten,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final a = snap.data;
        if (a == null) return const SizedBox.shrink();
        final k = a.aktivitaet;
        final sprache = Localizations.localeOf(context).toLanguageTag();
        final uhr = DateFormat.Hm(sprache);
        final farben = Theme.of(context).colorScheme;
        final leise = TextStyle(color: farben.onSurfaceVariant);
        final zeilen = [for (final x in a.aufnahmen) Rasterzeile.aus(x)];
        final ort = ortszeileText(a.ort, sprache, t.ortWeitere);
        final reise = a.reise;
        final fakten = [
          nameFuerArt(t, k.art),
          datumMittel(sprache).format(k.von.toLocal()),
          '${uhr.format(k.von.toLocal())}–${uhr.format(k.bis.toLocal())}',
          dauerText(t, k.bis.difference(k.von)),
          if (a.streckeKm > 0)
            t.streckeKm(
              NumberFormat.decimalPatternDigits(
                locale: sprache,
                decimalDigits: 1,
              ).format(a.streckeKm),
            ),
          t.anzahlAufnahmen(a.aufnahmen.length),
        ].join(' · ');
        return AufnahmenRaster(
          sitzung: widget.sitzung,
          zeilen: zeilen,
          kopf: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(symbolFuerArt(k.art), size: 18, color: farben.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(fakten, style: leise)),
                  ],
                ),
                if (ort != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 16,
                          color: farben.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: Text(ort, style: leise)),
                      ],
                    ),
                  ),
                if (reise != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: InkWell(
                      onTap: () => _oeffne(
                        context,
                        reise.name,
                        ReiseSeite(sitzung: widget.sitzung, reiseId: reise.id),
                      ),
                      child: Text(
                        t.gehoertZu(reise.name),
                        style: TextStyle(color: farben.primary),
                      ),
                    ),
                  ),
                if ((k.notiz ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(k.notiz!),
                  ),
                if (a.route.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _Routenkarte(
                      route: a.route,
                      oeffne: (id) {
                        final i = zeilen.indexWhere((z) => z.id == id);
                        if (i < 0) return;
                        Navigator.of(context).push(
                          betrachterWeg(
                            Betrachter(
                              sitzung: widget.sitzung,
                              zeilen: zeilen,
                              start: i,
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else if (a.aufnahmen.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(t.keineRoute, style: leise),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Die Route: Linie durch die verorteten Aufnahmen in ihrer Zeitfolge, ein
/// Punkt je Aufnahme – ein Tipp darauf öffnet sie.
class _Routenkarte extends StatelessWidget {
  const _Routenkarte({required this.route, required this.oeffne});

  final List<Routenpunkt> route;
  final void Function(String id) oeffne;

  @override
  Widget build(BuildContext context) {
    final farbe = Theme.of(context).colorScheme.primary;
    final punkte = [for (final p in route) LatLng(p.breite, p.laenge)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 260,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.coordinates(
              coordinates: punkte,
              padding: const EdgeInsets.all(28),
              maxZoom: 16,
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            kartenkacheln(context),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: punkte,
                  color: farbe.withValues(alpha: 0.85),
                  strokeWidth: 4,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                for (final (i, p) in route.indexed)
                  Marker(
                    point: LatLng(p.breite, p.laenge),
                    width: 28,
                    height: 28,
                    child: GestureDetector(
                      onTap: () => oeffne(p.id),
                      child: Center(
                        child: Container(
                          width: i == 0 || i == route.length - 1 ? 14 : 8,
                          height: i == 0 || i == route.length - 1 ? 14 : 8,
                          decoration: BoxDecoration(
                            color: farbe,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SimpleAttributionWidget(
              source: Text('OpenStreetMap contributors'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Die Karten der Liste, so viele nebeneinander, wie Platz haben – auf
/// dem Telefon zwei, wie im schmalen Browser.
class _Kartengitter extends StatelessWidget {
  const _Kartengitter({required this.karten});

  final List<Widget> karten;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    sliver: SliverLayoutBuilder(
      builder: (context, c) {
        const abstand = 14.0;
        final spalten = (c.crossAxisExtent / 200).floor().clamp(2, 8);
        final breite = (c.crossAxisExtent - abstand * (spalten - 1)) / spalten;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: spalten,
            mainAxisSpacing: abstand,
            crossAxisSpacing: abstand,
            mainAxisExtent: breite + 76,
          ),
          delegate: SliverChildListDelegate(karten),
        );
      },
    ),
  );
}

/// Eine Karte: Titelbild (mit der Art darauf, bei Aktivitäten), Name,
/// Zeitraum und Anzahl, darunter der Ort.
class _Karte extends StatelessWidget {
  const _Karte({
    required this.sitzung,
    required this.bild,
    required this.titel,
    required this.untertitel,
    required this.onTap,
    this.zusatz,
    this.kennzeichen,
  });

  final Sitzung sitzung;
  final AssetData? bild;
  final String titel;
  final String untertitel;
  final String? zusatz;
  final (IconData, String)? kennzeichen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final klein = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: farben.onSurfaceVariant);
    final k = kennzeichen;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Miniatur(
                    paths: sitzung.paths,
                    relativ: bild?.thumbnailRelativePath,
                  ),
                  if (k != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(k.$1, size: 14, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                k.$2,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            titel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            untertitel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: klein,
          ),
          if (zusatz != null)
            Text(
              zusatz!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: klein,
            ),
        ],
      ),
    );
  }
}
