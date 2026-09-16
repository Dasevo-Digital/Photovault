import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/familienorte.dart';
import '../services/map_clustering.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/zoomsteuerung.dart';
import '../widgets/mini_location_map.dart';
import '../widgets/wisch_zoom.dart';
import '../widgets/pin_dialogs.dart';
import '../services/lebenslauf.dart';
import 'asset_viewer_screen.dart';
import 'lebenslauf_screen.dart';

/// Ein verortetes Foto samt der Gruppe, nach der es eingefärbt wird.
typedef Familienort = ({AssetData asset, Ortsgruppe gruppe});

/// Ein verortetes Lebensereignis samt der Person, zu der es gehört.
///
/// Eigener Typ und nicht in [Familienort] hineingezwängt: Ein Ereignis
/// ist kein Foto. Es hat keine Datei, kein Vorschaubild und nichts zum
/// Öffnen — es hat einen Namen, ein Datum und eine Art.
typedef Ereignisort = ({
  LebensereignisseData ereignis,
  String personName,
});

/// Die Orte einer Familie – wo sich die Verwandtschaft über die
/// Generationen aufgehalten hat.
///
/// Dieselbe Kartengrundlage und dieselbe zoomabhängige Gruppierung wie in
/// der allgemeinen Kartenansicht; der Unterschied ist die Auswahl der
/// Fotos und ihre Einfärbung nach Verwandtschaftsrichtung.
class FamilienorteScreen extends StatefulWidget {
  final LibraryState library;
  final String titel;
  final List<Familienort> orte;

  /// Verortete Lebensereignisse derselben Familie. Leer, solange keines
  /// einen auflösbaren Ort hat.
  final List<Ereignisort> ereignisse;

  const FamilienorteScreen({
    super.key,
    required this.library,
    required this.titel,
    required this.orte,
    this.ereignisse = const [],
  });

  @override
  State<FamilienorteScreen> createState() => _FamilienorteScreenState();
}

class _FamilienorteScreenState extends State<FamilienorteScreen> {
  static const _standardZoom = 5.0;
  double _zoom = _standardZoom;

  /// Gebraucht für die Zoomknöpfe und den Wisch-Zoom; die Karte kam
  /// vorher ohne Steuerung aus, weil sie sich nur ums Zeichnen kümmerte.
  final _steuerung = MapController();

  /// Welche Gruppen gerade gezeigt werden. Anfangs alle – die Karte soll
  /// zuerst zeigen, was da ist, und sich erst auf Wunsch verengen.
  final Set<Ortsgruppe> _sichtbar = {...Ortsgruppe.values};

  /// Ob die Lebensereignisse mitgezeichnet werden. Eigener Schalter und
  /// nicht Teil von [_sichtbar]: Ereignisse sind keine
  /// Verwandtschaftsrichtung, sondern eine andere Art Sache.
  bool _ereignisseZeigen = true;

  Color _farbe(BuildContext context, Ortsgruppe g) {
    final f = Theme.of(context).colorScheme;
    return switch (g) {
      Ortsgruppe.ich => f.primary,
      Ortsgruppe.vorfahren => f.tertiary,
      Ortsgruppe.nachkommen => f.secondary,
      Ortsgruppe.seitenlinie => f.onSurfaceVariant,
      Ortsgruppe.angeheiratet => f.outline,
    };
  }

  String _name(AppTexte t, Ortsgruppe g) => switch (g) {
        Ortsgruppe.ich => t.orteIch,
        Ortsgruppe.vorfahren => t.orteVorfahren,
        Ortsgruppe.nachkommen => t.orteNachkommen,
        Ortsgruppe.seitenlinie => t.orteSeitenlinie,
        Ortsgruppe.angeheiratet => t.orteAngeheiratet,
      };

  /// Der Mittelpunkt, auf den die Karte beim Öffnen zeigt.
  ///
  /// Ereignisse zählen mit: Ein Stammbaum kann verortete Ereignisse
  /// haben, ohne dass ein einziges Foto verortet wäre – dann zeigte die
  /// Karte sonst auf einen Mittelwert aus nichts.
  ll.LatLng _mitte(List<Familienort> orte) {
    var lat = 0.0, lng = 0.0, anzahl = 0;
    for (final o in orte) {
      lat += o.asset.latitude!;
      lng += o.asset.longitude!;
      anzahl++;
    }
    if (_ereignisseZeigen) {
      for (final e in widget.ereignisse) {
        lat += e.ereignis.ortBreite!;
        lng += e.ereignis.ortLaenge!;
        anzahl++;
      }
    }
    if (anzahl == 0) return const ll.LatLng(51.1657, 10.4515);
    return ll.LatLng(lat / anzahl, lng / anzahl);
  }

  void _oeffne(List<AssetData> gruppe) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: gruppe,
        initialIndex: 0,
        paths: widget.library.paths,
        db: widget.library.db,
        library: widget.library,
        onToggleFavorite: (a) =>
            widget.library.db.setFavorite(a.id, !a.isFavorite),
        onDelete: (a) => widget.library.db.moveToTrash([a.id]),
        onLock: (a) async {
          if (await ensureVaultUnlocked(context, widget.library)) {
            await widget.library.lockAsset(a);
          }
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final gezeigt =
        widget.orte.where((o) => _sichtbar.contains(o.gruppe)).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.titel)),
      body: Column(
        children: [
          _legende(context, t),
          Expanded(
            child: gezeigt.isEmpty
                ? Center(child: Text(t.orteNichtsGewaehlt))
                : _karte(gezeigt),
          ),
        ],
      ),
    );
  }

  /// Die Legende ist zugleich der Filter – eine Farberklärung, die man
  /// nur lesen kann, wäre eine verschenkte Fläche.
  Widget _legende(BuildContext context, AppTexte t) {
    final vorhanden = {for (final o in widget.orte) o.gruppe};
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          for (final g in Ortsgruppe.values)
            if (vorhanden.contains(g))
              FilterChip(
                selected: _sichtbar.contains(g),
                onSelected: (an) => setState(
                    () => an ? _sichtbar.add(g) : _sichtbar.remove(g)),
                avatar: CircleAvatar(
                    backgroundColor: _farbe(context, g), radius: 7),
                label: Text(
                    '${_name(t, g)} (${widget.orte.where((o) => o.gruppe == g).length})'),
              ),
          if (widget.ereignisse.isNotEmpty)
            FilterChip(
              selected: _ereignisseZeigen,
              onSelected: (an) => setState(() => _ereignisseZeigen = an),
              // Ein Symbol statt eines Farbpunkts: Ereignisse gehören
              // nicht in dieselbe Farbreihe wie die
              // Verwandtschaftsrichtungen, sonst läse man sie als eine
              // weitere davon.
              avatar: const Icon(Icons.event_outlined, size: 16),
              label: Text('${t.orteEreignisse} (${widget.ereignisse.length})'),
            ),
        ],
      ),
    );
  }

  Widget _karte(List<Familienort> gezeigt) {
    final gruppen = gruppiereFuerKarte(gezeigt, _zoom,
        (o) => (breite: o.asset.latitude!, laenge: o.asset.longitude!));
    final hoechsteStufe = Kartenstil.dunkel.hoechsteAnzeigeStufe.toDouble();
    return Stack(children: [
      Positioned.fill(
        child: WischZoom(
          steuerung: _steuerung,
          groesserZoom: hoechsteStufe,
          child: FlutterMap(
      mapController: _steuerung,
      options: MapOptions(
        initialCenter: _mitte(gezeigt),
        initialZoom: _standardZoom,
        // Sonst zoomt die Karte ueber die vorhandenen Kacheln hinaus ins
        // Leere – siehe Kartenstil.hoechsteAnzeigeStufe.
        maxZoom: Kartenstil.dunkel.hoechsteAnzeigeStufe.toDouble(),
        onPositionChanged: (kamera, _) {
          final stufe = kamera.zoom.roundToDouble();
          if (stufe != _zoom) setState(() => _zoom = stufe);
        },
      ),
      children: [
        const Kachelschicht(stil: Kartenstil.dunkel),
        buildMapAttribution(context, stil: Kartenstil.dunkel),
        // Die Ereignisse liegen UNTER den Fotomarken: Wo beides am
        // selben Ort ist, soll das Foto obenauf liegen – es lässt sich
        // öffnen, das Ereignis nicht.
        if (_ereignisseZeigen)
          MarkerLayer(
            markers: [
              for (final e in widget.ereignisse)
                Marker(
                  point: ll.LatLng(
                      e.ereignis.ortBreite!, e.ereignis.ortLaenge!),
                  width: markerGroesse,
                  height: markerGroesse,
                  child: Tooltip(
                    message: [
                      e.personName,
                      if (e.ereignis.ort != null && e.ereignis.ort!.isNotEmpty)
                        e.ereignis.ort!,
                    ].join(' · '),
                    child: _Ereignismarke(
                      farbe: Theme.of(context).colorScheme.primaryContainer,
                      symbol: LebenslaufScreen.symbol(Lebenszeile(
                        ereignisId: e.ereignis.id,
                        art: ereignisartAusText(e.ereignis.art),
                      )),
                    ),
                  ),
                ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final gruppe in gruppen.values)
              Marker(
                point: ll.LatLng(
                  gruppe.map((o) => o.asset.latitude!).reduce((a, b) => a + b) /
                      gruppe.length,
                  gruppe.map((o) => o.asset.longitude!).reduce((a, b) => a + b) /
                      gruppe.length,
                ),
                width: markerGroesse,
                height: markerGroesse,
                child: GestureDetector(
                  onTap: () => _oeffne([for (final o in gruppe) o.asset]),
                  child: _Ortsmarke(
                    farbe: _farbe(context, gruppe.first.gruppe),
                    anzahl: gruppe.length,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
        ),
      ),
      Positioned(
        right: 8,
        bottom: 40,
        child: Zoomsteuerung(
          beiNaeher: () => _zoomen(1),
          beiWeiter: () => _zoomen(-1),
        ),
      ),
    ]);
  }

  /// Ein Zoomschritt über die Knöpfe – selbst geklemmt, weil `move` die
  /// Grenze aus den Kartenoptionen nicht kennt.
  void _zoomen(double schritt) {
    final kamera = _steuerung.camera;
    final grenze = Kartenstil.dunkel.hoechsteAnzeigeStufe.toDouble();
    final neu = (kamera.zoom + schritt).clamp(kamera.minZoom ?? 0.0, grenze);
    if (neu == kamera.zoom) return;
    _steuerung.move(kamera.center, neu);
  }
}

/// Ein Punkt auf der Familienkarte: farbig nach Verwandtschaftsrichtung,
/// mit der Zahl der Fotos.
///
/// Kein Vorschaubild wie auf der allgemeinen Karte – hier trägt die Farbe
/// die Aussage, und ein Foto darüber würde sie verdecken.
class _Ortsmarke extends StatelessWidget {
  final Color farbe;
  final int anzahl;
  const _Ortsmarke({required this.farbe, required this.anzahl});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: anzahl > 1 ? 30 : 20,
        height: anzahl > 1 ? 30 : 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: farbe,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
        ),
        child: anzahl > 1
            ? Text('$anzahl',
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold))
            : null,
      ),
    );
  }
}

/// Ein Lebensereignis auf der Familienkarte.
///
/// Bewusst anders geformt als [_Ortsmarke]: eine Raute mit dem Symbol
/// der Ereignisart statt eines Kreises mit einer Zahl. Ein Ereignis und
/// ein Foto sind zwei verschiedene Dinge, und zwei Dinge in derselben
/// Form wären eine Behauptung — man läse die Ereignisse als eine weitere
/// Verwandtschaftsrichtung.
class _Ereignismarke extends StatelessWidget {
  final Color farbe;
  final IconData symbol;
  const _Ereignismarke({required this.farbe, required this.symbol});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: farbe,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
          ),
          // Das Symbol zurückdrehen: Die Raute ist gekippt, ein
          // mitgekipptes Herz oder Auto wäre schlicht schief.
          child: Transform.rotate(
            angle: -math.pi / 4,
            child: Icon(symbol,
                size: 12, color: Theme.of(context).colorScheme.onPrimaryContainer),
          ),
        ),
      ),
    );
  }
}
