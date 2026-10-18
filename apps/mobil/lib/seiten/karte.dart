import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/kartengruppen.dart';
import 'package:latlong2/latlong.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'betrachter.dart';
import 'raster.dart';

/// Die Aufnahmen mit Ort auf der Karte – nahe beieinander liegende zu
/// einem Punkt zusammengefasst, damit die Karte bei tausend Fotos lesbar
/// bleibt. Ein Tipp öffnet die Fotos dieses Punkts.
class Karte extends StatefulWidget {
  const Karte({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<Karte> createState() => _KarteState();
}

class _KarteState extends State<Karte> {
  List<Rasterzeile>? _orte;
  LatLng? _mitte;
  double _zoom = 4;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    final db = widget.sitzung.db;
    final alle = await db.assetsWithLocation();
    final s = await db.schwerpunktVerorteterFotos();
    if (!mounted) return;
    setState(() {
      _orte = [
        for (final a in alle)
          if (!a.isLocked && !a.isTrashed) Rasterzeile.aus(a),
      ];
      _mitte = s == null ? const LatLng(51, 10) : LatLng(s.breite, s.laenge);
    });
  }

  void _oeffne(List<Rasterzeile> gruppe) {
    final sitzung = widget.sitzung;
    final sortiert = [...gruppe]
      ..sort((a, b) => b.fileCreatedAt.compareTo(a.fileCreatedAt));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => sortiert.length == 1
            ? Betrachter(sitzung: sitzung, zeilen: sortiert, start: 0)
            : Scaffold(
                appBar: AppBar(
                  title: Text(AppTexte.of(context).karteFotos(sortiert.length)),
                ),
                body: AufnahmenRaster(
                  sitzung: sitzung,
                  zeilen: sortiert,
                  nachTagen: true,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orte = _orte;
    if (orte == null) return const Center(child: CircularProgressIndicator());
    if (orte.isEmpty) {
      return Center(child: Text(AppTexte.of(context).karteLeer));
    }
    final gruppen = kartengruppen(orte, _zoom.roundToDouble());
    return FlutterMap(
      options: MapOptions(
        initialCenter: _mitte!,
        initialZoom: _zoom,
        maxZoom: 18,
        onPositionChanged: (kamera, _) {
          if (kamera.zoom.round() != _zoom.round()) {
            setState(() => _zoom = kamera.zoom);
          }
        },
      ),
      children: [
        kartenkacheln(context),
        MarkerLayer(
          markers: [
            for (final g in gruppen)
              Marker(
                point: LatLng(
                  g.map((z) => z.latitude!).reduce((a, b) => a + b) / g.length,
                  g.map((z) => z.longitude!).reduce((a, b) => a + b) / g.length,
                ),
                width: 52,
                height: 52,
                child: GestureDetector(
                  onTap: () => _oeffne(g),
                  child: _Punkt(sitzung: widget.sitzung, gruppe: g),
                ),
              ),
          ],
        ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
        ),
      ],
    );
  }
}

class _Punkt extends StatelessWidget {
  const _Punkt({required this.sitzung, required this.gruppe});

  final Sitzung sitzung;
  final List<Rasterzeile> gruppe;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Miniatur(
            paths: sitzung.paths,
            relativ: gruppe.first.thumbnailRelativePath,
          ),
        ),
      ),
      if (gruppe.length > 1)
        Positioned(
          right: -6,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${gruppe.length}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 11,
              ),
            ),
          ),
        ),
    ],
  );
}

/// Umkehren (invert) und Farbton um 180° drehen, in einer Matrix: Die
/// Helligkeit kippt, die Farben bleiben, wo sie waren.
/// Die Kacheln von OpenStreetMap – im dunklen Erscheinungsbild umgekehrt
/// und im Farbton zurückgedreht, so bleibt Wasser blau und Grün grün, nur
/// hell wird dunkel. Kein zweiter Kartendienst, kein Schlüssel.
Widget kartenkacheln(BuildContext context) {
  final kacheln = TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'de.dasevo.photovault',
  );
  return Theme.of(context).brightness == Brightness.dark
      ? ColorFiltered(
          colorFilter: const ColorFilter.matrix(_dunkleKarte),
          child: kacheln,
        )
      : kacheln;
}

const _dunkleKarte = <double>[
  0.574, -1.430, -0.144, 0, 255, //
  -0.426, -0.430, -0.144, 0, 255, //
  -0.426, -1.430, 0.856, 0, 255, //
  0, 0, 0, 1, 0, //
];
