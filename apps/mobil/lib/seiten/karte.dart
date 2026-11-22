import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/kartengruppen.dart';
import 'package:kern/services/kartenstil.dart' show osmKachelUrl;
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
        kartenkacheln(context, widget.sitzung),
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
        Kartenhinweis(sitzung: widget.sitzung),
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
///
/// Geholt nur über den eigenen Server (#180, #469, siehe
/// [Sitzung.kachelnetz]); liefert er keine, bleibt die Karte leer bis auf
/// das, was schon auf dem Telefon liegt ([Kartenhinweis]). Die Adresse
/// bleibt die von OpenStreetMap: So gilt der Kachelspeicher des Telefons
/// auch ohne Netz.
///
/// Liefert der Server wieder Kacheln, wird die Schicht neu gebaut und lädt
/// gleich, was vorher abgewiesen wurde – sonst blieben diese Stellen leer,
/// bis man die Karte verschiebt.
Widget kartenkacheln(BuildContext context, Sitzung sitzung) =>
    ListenableBuilder(
      listenable: sitzung,
      builder: (context, _) {
        final kacheln = TileLayer(
          key: ValueKey(sitzung.kartenUeberServer),
          urlTemplate: osmKachelUrl,
          userAgentPackageName: 'de.dasevo.photovault',
          tileProvider: NetworkTileProvider(httpClient: sitzung.kachelnetz),
        );
        return Theme.of(context).brightness == Brightness.dark
            ? ColorFiltered(
                colorFilter: const ColorFilter.matrix(_dunkleKarte),
                child: kacheln,
              )
            : kacheln;
      },
    );

/// Ein Satz oben auf der Karte, solange der Server keine Kacheln liefert
/// (#469) – sonst sähe die leere Karte kaputt aus. Gehört in jede Karte,
/// die [kartenkacheln] zeigt.
class Kartenhinweis extends StatelessWidget {
  const Kartenhinweis({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sitzung,
    builder: (context, _) => sitzung.kartenUeberServer
        ? const SizedBox.shrink()
        : Hinweisband(AppTexte.of(context).karteNurUeberServer),
  );
}

/// Ein kurzer Hinweis oben mittig über einer Karte oder Landschaft. Er
/// nimmt keine Berührung an, damit die Karte darunter bedienbar bleibt.
class Hinweisband extends StatelessWidget {
  const Hinweisband(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            color: farben.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 16,
                    color: farben.onSurface,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      style: TextStyle(fontSize: 12, color: farben.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _dunkleKarte = <double>[
  0.574, -1.430, -0.144, 0, 255, //
  -0.426, -0.430, -0.144, 0, 255, //
  -0.426, -1.430, 0.856, 0, 255, //
  0, 0, 0, 1, 0, //
];
