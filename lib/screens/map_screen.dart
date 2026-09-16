import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_earth_globe/flutter_earth_globe.dart';
import 'package:flutter_earth_globe/flutter_earth_globe_controller.dart';
import 'package:flutter_earth_globe/globe_coordinates.dart';
import 'package:flutter_earth_globe/point.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/bilddekodierung.dart';
import '../services/map_clustering.dart';
import '../services/native_image_converter.dart';
import '../services/lebenslauf.dart';
import '../services/storage_paths.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/wisch_zoom.dart';
import '../widgets/zoomsteuerung.dart';
import '../widgets/mini_location_map.dart';
import '../widgets/pin_dialogs.dart';
import 'asset_viewer_screen.dart';
import 'lebenslauf_screen.dart';
import '../services/meldungsdienst.dart';

/// Die vier Darstellungen der Kartenansicht: helle, dunkle oder
/// topografische flache Karte oder ein interaktiver 3D-Globus. Bewusst als
/// eigener, vom Nutzer gewählter Zustand statt am App-Theme (siehe
/// [buildMapTileLayer]) – die App ist permanent dunkel eingefärbt, ohne
/// diesen Umschalter gäbe es also nie helle Kacheln zu sehen.
enum Kartenansicht {
  hell('hell'),
  dunkel('dunkel'),
  topo('topo'),

  /// Die selbst eingetragene Quelle (siehe [Eigenkarte]). Steht nur im
  /// Menü, wenn eine eingerichtet ist – sonst wäre es ein Eintrag, der
  /// eine leere Karte zeigt.
  eigene('eigene'),
  globus('globus');

  const Kartenansicht(this.alsText);

  /// Wie die Wahl in der Datenbank steht.
  ///
  /// Ein eigener Text statt `name` oder des Index: Der Index verschöbe
  /// sich, sobald jemand einen Eintrag dazwischenschiebt, und aus einer
  /// gemerkten Topografiekarte würde stillschweigend eine andere Ansicht.
  final String alsText;

  /// Liest die gemerkte Wahl zurück.
  ///
  /// Unbekanntes fällt auf [dunkel] zurück statt zu werfen – dasselbe
  /// Muster wie bei `themeMode` und `sprache`: Eine Angabe aus einer
  /// neueren Fassung darf den Start nicht verhindern.
  static Kartenansicht ausText(String? text) => values
      .where((a) => a.alsText == text)
      .followedBy([dunkel]).first;

  /// Die Ansichten, die gerade zur Wahl stehen.
  ///
  /// [eigene] fällt heraus, solange keine Quelle eingerichtet ist. Das
  /// gilt auch für eine **gemerkte** Wahl: Wer die eigene Karte
  /// einstellt und sie später wieder löscht, fände sonst beim nächsten
  /// Start eine leere Karte ohne Hinweis vor.
  static List<Kartenansicht> verfuegbar({required bool mitEigener}) =>
      [for (final a in values) if (a != eigene || mitEigener) a];
}

/// Zoomstufe beim Öffnen der flachen Karte ohne bestimmtes Ziel.
const double _standardZoom = 6;

/// Ab dieser Globus-Zoomstufe erscheint der Hinweis, dass weiteres
/// Heranzoomen kein zusätzliches Detail mehr bringt.
///
/// Nicht geraten: Bis Stufe 3 wächst die gemessene Schärfe der 8K-Textur
/// noch mit (596 → 307 → 174 → 200), danach fällt sie ab und bricht zur
/// Höchststufe hin ganz ein (182 → 11). Ab hier vergrössert die Ansicht
/// also nur noch, statt mehr zu zeigen.
const double zoomHinweisAb = 3;

/// Scrollbare Kartenansicht (OpenStreetMap) über alle Fotos/Videos mit
/// bekanntem Ort – aus EXIF-GPS-Daten beim Import übernommen oder manuell in
/// der Info-Ansicht eines Assets gesetzt (siehe [AssetInfoSheet]).
class MapScreen extends StatefulWidget {
  final LibraryState library;
  const MapScreen({super.key, required this.library});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<AssetData>? _located;

  /// Verortete Lebensereignisse aus dem Stammbaum.
  ///
  /// Sie liegen auf derselben Karte wie die Fotos, weil sie dieselbe
  /// Frage beantworten: wo jemand war. Bei einer Bibliothek ohne
  /// Stammbaum bleibt die Liste leer, und dann ist auch nichts
  /// umzuschalten — der Schalter erscheint erst, wenn es etwas zu
  /// schalten gibt.
  List<({LebensereignisseData ereignis, String personName})> _ereignisse =
      const [];
  bool _ereignisseZeigen = true;

  Kartenansicht _mode = Kartenansicht.dunkel;

  // Lazy angelegt (GPU-Shader-Ressourcen) und nur befüllt, solange der
  // Globus-Modus tatsächlich schon einmal aktiv war – wer nie in den
  // Globus-Modus wechselt, zahlt dafür auch keine Rendering-Kosten.
  FlutterEarthGlobeController? _globeController;
  bool _globePointsSynced = false;
  double? _lastGroupedZoomBucket;

  /// Aktuelle Globus-Zoomstufe – für den Hinweis oben und die Knöpfe.
  double _globusZoom = 0;

  /// Steuert die flache Karte von aussen (Zoomknöpfe, Standortsprung).
  final MapController _flacheKarte = MapController();

  /// Läuft gerade eine Standortabfrage? Der Knopf zeigt dann einen
  /// Kreisel und nimmt keinen zweiten Auftrag an.
  bool _standortLaeuft = false;

  // Zuletzt genutzte flache Kartenansicht (Hell/Dunkel) – Ziel, wenn man
  // vom Globus über einen Pin "auf die Karte springt" (siehe
  // [_jumpToFlatMap]), statt dafür immer Dunkel zu erzwingen.
  Kartenansicht _lastFlatMode = Kartenansicht.dunkel;

  // Von [_jumpToFlatMap] gesetzt, um die nächste flache Karte auf einen
  // bestimmten Ort statt auf den Durchschnitt aller Fotos zu zentrieren –
  // der Globus zeigt selbst bei starkem Reinzoomen keine Straßendetails
  // (siehe _ensureGlobeController), ein Pin-Tap springt deshalb direkt in
  // die kachelbasierte OSM-Karte an genau dieser Stelle.
  ll.LatLng? _pendingFlatFocus;
  double? _pendingFlatZoom;

  // Der Zoom, mit dem die flache Karte gerade gruppiert ist – gerundet auf
  // ganze Stufen, damit nicht jede Pixelbewegung einer laufenden Zoomgeste
  // die komplette Markerliste neu aufbaut (dasselbe Vorgehen wie
  // [_onGlobeZoomChanged]).
  double _flacherZoom = _standardZoom;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Kein `_globeController?.dispose()` hier: `RotatingGlobeState.dispose()`
    // (im FlutterEarthGlobe-Widget selbst) räumt dessen internen
    // rotationController bereits auf, sobald das Widget beim Tab-Wechsel
    // aus dem Baum entfernt wird. Ein zusätzlicher Aufruf hier würde genau
    // diesen AnimationController ein zweites Mal disposen ("disposed more
    // than once") – reproduzierbar beim Verlassen der Kartenansicht, nachdem
    // der Globus-Modus einmal genutzt wurde.
    super.dispose();
  }

  Future<void> _load() async {
    // Erst die gemerkte Ansicht, dann die Orte: Sonst baute der Bildschirm
    // kurz die dunkle Karte auf und schaltete sichtbar um.
    var gemerkt = Kartenansicht.ausText(await widget.library.db.kartenansicht());
    // Eine gemerkte eigene Karte, die es nicht mehr gibt, führte sonst in
    // eine leere Ansicht ohne jeden Hinweis – siehe
    // [Kartenansicht.verfuegbar].
    if (!Kartenansicht.verfuegbar(mitEigener: eigeneKarte != null)
        .contains(gemerkt)) {
      gemerkt = Kartenansicht.dunkel;
    }
    final assets = await widget.library.db.assetsWithLocation();
    final ereignisse = await widget.library.db.ereignisseMitKoordinateUndName();
    if (!mounted) return;
    setState(() {
      _mode = gemerkt;
      if (gemerkt != Kartenansicht.globus) _lastFlatMode = gemerkt;
      _located = assets;
      _ereignisse = ereignisse;
    });
    _globePointsSynced = false;
    if (_mode == Kartenansicht.globus) _syncGlobePoints(focus: true);
  }

  void _openAsset(List<AssetData> assets, AssetData asset) {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(
          builder: (_) => AssetViewerScreen(
            assets: assets,
            initialIndex: assets.indexOf(asset),
            paths: widget.library.paths,
            db: widget.library.db,
            library: widget.library,
            onToggleFavorite: (a) => widget.library.db.setFavorite(a.id, !a.isFavorite),
            onDelete: (a) => widget.library.db.moveToTrash([a.id]),
            onLock: (a) async {
              if (await ensureVaultUnlocked(context, widget.library)) {
                await widget.library.lockAsset(a);
              }
            },
          ),
        ))
        // Nach Rückkehr neu laden – der Ort könnte in der Info-Ansicht
        // geändert oder entfernt worden sein.
        .then((_) => _load());
  }

  ll.LatLng _averageCenter(List<AssetData> assets) {
    final s = schwerpunktVon(assets, _koordinateVon);
    return ll.LatLng(s.breite, s.laenge);
  }

  static ({double breite, double laenge}) _koordinateVon(AssetData a) =>
      (breite: a.latitude!, laenge: a.longitude!);

  /// Rastergröße (in Grad) für die Gruppierung auf dem Globus – abhängig
  /// vom aktuellen Zoom, damit dicht beieinanderliegende Fotos beim Reinzoomen sichtbar
  /// auseinanderrücken statt für immer an einem Punkt zu kleben. Grob
  /// 33km beim Herausgezoomten Überblick (verhindert hunderte überlappende
  /// Punkte auf der kleinen Kugelfläche), bis knapp über GPS-Genauigkeit
  /// (~55m) beim tiefsten unterstützten Zoom.
  double _gridDegreesForZoom(double zoom) {
    // Nicht feiner rastern, als der Globus zeigen kann. Ab
    // [zoomHinweisAb] kommt kein zusätzliches Detail mehr dazu (siehe
    // dort) – ein feineres Raster erzeugt dann nur noch mehr Pins, und
    // jeder Pin ist ein eigenes Flutter-Widget mit Gestenerkennung.
    //
    // Gemessen an 1092 verorteten Fotos, wie sie eine echte Bibliothek
    // hat: ohne diese Deckelung wuchs die Pinzahl beim Hereinzoomen von
    // 222 auf 910, und das Einzelbild brauchte am Ende 262 ms. Bei vier
    // Bildern je Sekunde wirkt der Globus nicht langsam, sondern kaputt –
    // Zoomgesten scheinen dann gar nichts zu tun.
    final wirksam = math.min(zoom, zoomHinweisAb);
    final scale = math.pow(2.0, wirksam).toDouble();
    return (0.3 / scale).clamp(0.0005, 0.3);
  }

  Map<String, List<AssetData>> _gruppiereNachRaster(List<AssetData> assets, double gridDegrees) {
    final groups = <String, List<AssetData>>{};
    for (final a in assets) {
      final latKey = (a.latitude! / gridDegrees).round();
      final lngKey = (a.longitude! / gridDegrees).round();
      final key = '$latKey,$lngKey';
      groups.putIfAbsent(key, () => []).add(a);
    }
    return groups;
  }

  FlutterEarthGlobeController _ensureGlobeController() {
    return _globeController ??= FlutterEarthGlobeController(
      surface: const AssetImage('assets/globe/8k_earth_daymap.jpg'),
      background: const AssetImage('assets/globe/2k_stars_milky_way.jpg'),
      isRotating: false,
      // 0 statt des Standards 1 – der gerenderte Radius ist
      // `radius * 2^zoom` (siehe RotatingGlobe.convertedRadius), Zoom 1
      // würde den Globus also schon beim Öffnen auf die doppelte Größe
      // vergrößern und nur einen Ausschnitt statt der ganzen Erde zeigen.
      zoom: 0,
      // Deutlich höher als der Bibliotheks-Standard (2.5): einzelne Fotos
      // innerhalb einer Stadt lassen sich erst bei starkem Reinzoomen
      // auseinanderhalten (siehe _gridDegreesForZoom). Straßen-/Gebäude-
      // Detailgrad zeigt aber selbst dieser Zoom nicht – die Erdtextur ist
      // ein einzelnes Bild ohne Kachel-Nachladen wie bei der flachen
      // Karte; dafür bleibt die Hell/Dunkel-Kartenansicht (echte
      // OSM-Kacheln) die richtige Wahl.
      //
      // Die Textur ist 8192×4096 statt vormals 2048×1024. Gemessen auf
      // echter GPU (Laplace-Schärfe der Bildmitte über den Alpen, weil
      // 0°/0° auf offenen Atlantik zeigt und dort jede Auflösung gleich
      // strukturlos ist):
      //
      //   Zoom      0      1      2      3      4      6
      //   2K      316    186     94     84     72    4,6
      //   8K      596    307    174    200    182   11,0
      //
      // Also rund doppelt so scharf auf jeder Stufe. Ab [zoomHinweisAb]
      // bringt weiteres Heranzoomen trotzdem nichts mehr an Detail –
      // darauf weist die Ansicht dann hin, statt es den Nutzer selbst
      // herausfinden zu lassen.
      maxZoom: 6,
    );
  }

  /// [focus] zentriert den Globus einmalig auf den Fotos (beim ersten
  /// Aktivieren des Globus-Modus bzw. nach einem Reload) – beim erneuten
  /// Gruppieren wegen eines Zoom-Wechsels (siehe [_onGlobeZoomChanged])
  /// bewusst false, sonst würde jede Neugruppierung die eigene
  /// Zoom-/Dreh-Position des Nutzers wieder zurücksetzen.
  void _syncGlobePoints({double zoom = 0, bool focus = false}) {
    final located = _located;
    if (located == null) return;
    final controller = _ensureGlobeController();
    controller.points.clear();
    final groups = _gruppiereNachRaster(located, _gridDegreesForZoom(zoom));
    for (final entry in groups.entries) {
      final group = entry.value;
      // Der Schwerpunkt und nicht das erste Foto der Gruppe: Bei 0,3 Grad
      // Rasterweite lag der Pin sonst bis zu zwanzig Kilometer daneben und
      // sprang beim Zoomen auf ein anderes Foto, weil sich mit dem Raster
      // auch die Gruppen ändern. Dieselbe Rechnung wie auf der flachen
      // Karte, die den Schwerpunkt seit jeher benutzt.
      final mitte = schwerpunktVon(group, _koordinateVon);
      controller.addPoint(Point(
        id: entry.key,
        coordinates: GlobeCoordinates(mitte.breite, mitte.laenge),
        // Der GPU-gezeichnete Punkt selbst bleibt unsichtbar (Alpha 0) –
        // die eigentliche Pin-Nadel ist unten ein normales Flutter-Widget
        // (siehe labelBuilder), das sich exakt an dieselbe Position
        // ankert, aber gestochen scharf bleibt statt als Kugel-Ellipse
        // verzerrt zu werden.
        style: const PointStyle(color: Colors.transparent, size: 0.1),
        // Die Bibliothek rechnet `oben = Ort − labelOffset.dy − Höhe`,
        // setzt also die Unterkante auf den Ort. Ein negativer Wert
        // schiebt das Widget genau um diesen Betrag wieder nach unten,
        // bis die Spitze auf dem Ort steht.
        labelOffset: const Offset(0, -pinSpitzeUeberKante),
        labelBuilder: (context, point, isHovering, isVisible) => GestureDetector(
          // Der Globus selbst zeigt keine Straßendetails (siehe
          // _ensureGlobeController) – ein Pin-Tap springt deshalb zur
          // flachen Karte an dieser Stelle statt direkt das Foto zu
          // öffnen; von dort öffnet der bekannte Foto-Marker das Bild.
          onTap: () => _jumpToFlatMap(group),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: _GlobePin(count: group.length),
          ),
        ),
      ));
    }
    if (_ereignisseZeigen) {
      for (final e in _ereignisse) {
        controller.addPoint(Point(
          // Eigener Namensraum für die Kennung: Die Fotogruppen oben
          // nummerieren nach Rasterzelle, und zwei Punkte mit derselben
          // Kennung überschrieben einander.
          id: 'ereignis-${e.ereignis.id}',
          coordinates: GlobeCoordinates(
              e.ereignis.ortBreite!, e.ereignis.ortLaenge!),
          style: const PointStyle(color: Colors.transparent, size: 0.1),
          // Die Raute soll mit ihrer Mitte auf dem Ereignis sitzen, nicht
          // mit ihrer Unterkante — siehe [rauteHalb].
          labelOffset: const Offset(0, -rauteHalb),
          labelBuilder: (context, point, isHovering, isVisible) => Tooltip(
            message: [
              e.personName,
              if (e.ereignis.ort != null && e.ereignis.ort!.isNotEmpty)
                e.ereignis.ort!,
            ].join(' · '),
            child: _GlobusEreignis(
              symbol: LebenslaufScreen.symbol(Lebenszeile(
                ereignisId: e.ereignis.id,
                art: ereignisartAusText(e.ereignis.art),
              )),
            ),
          ),
        ));
      }
    }
    if (focus && groups.isNotEmpty) {
      final center = _averageCenter(located);
      controller.focusOnCoordinates(GlobeCoordinates(center.latitude, center.longitude));
    }
    _globePointsSynced = true;
  }

  void _onGlobeZoomChanged(double zoom) {
    // Nur bei ganzen Zoom-Schritten neu gruppieren statt bei jedem Frame
    // einer laufenden Zoomgeste – sonst würde bei jedem Pixel Scroll-Delta
    // die komplette Punktliste neu aufgebaut.
    final bucket = zoom.roundToDouble();
    if (bucket == _lastGroupedZoomBucket) {
      // Der Hinweis hängt an derselben gerundeten Stufe: Ohne diese
      // Rückkehr bliebe er beim Feinzoom innerhalb einer Stufe stehen,
      // mit einem setState je Einzelbild.
      return;
    }
    _lastGroupedZoomBucket = bucket;
    if ((bucket >= zoomHinweisAb) != (_globusZoom >= zoomHinweisAb)) {
      setState(() => _globusZoom = bucket);
    } else {
      _globusZoom = bucket;
    }
    _syncGlobePoints(zoom: bucket);
  }

  void _setMode(Kartenansicht mode) {
    // Absichtlich ohne `await`: Das Umschalten soll sofort geschehen, das
    // Merken darf hinterherlaufen.
    unawaited(widget.library.db.setzeKartenansicht(mode.alsText));
    _zoomAufStilGrenzeZiehen(mode);
    setState(() {
      _mode = mode;
      if (mode != Kartenansicht.globus) {
        _lastFlatMode = mode;
        // Explizite Auswahl über das Menü statt eines Pin-Sprungs (siehe
        // [_jumpToFlatMap]) -> normale Übersicht statt eines noch aus
        // einem früheren Sprung übrig gebliebenen Zielorts.
        _pendingFlatFocus = null;
        _pendingFlatZoom = null;
        _flacherZoom = _standardZoom;
        // Sonst stünde der Zoomhinweis beim nächsten Öffnen des Globus
        // sofort da, obwohl der wieder bei Stufe 0 beginnt.
        _globusZoom = 0;
        _lastGroupedZoomBucket = null;
        // Den Globus-Regler loslassen, sobald die Ansicht verlassen wird.
        //
        // Die Erdtextur ist 8192×4096 und damit dekodiert 134 MB. Flutters
        // Bildspeicher fasst 105 MB, sie passt also nicht hinein –
        // gemessen: „0 Bilder gehalten". Behalten wird sie trotzdem,
        // nämlich von diesem Regler, und der lag bisher bis zum
        // Programmende herum. Dazu legt die Bibliothek in `loadSurface`
        // unbedingt eine zweite Kopie als Uint32List an (für ihren
        // CPU-Zeichenweg, den der Desktop gar nicht nimmt) – zusammen rund
        // 268 MB, dauerhaft, nach einem einzigen Blick auf den Globus.
        //
        // Kein `dispose()`: Den internen AnimationController räumt
        // `RotatingGlobeState.dispose()` bereits ab, ein zweiter Aufruf
        // führte reproduzierbar zu „disposed more than once". Die Referenz
        // fallen zu lassen genügt.
        //
        // Preis: Beim nächsten Öffnen wird die Textur neu dekodiert.
        _globeController = null;
        _globePointsSynced = false;
      }
    });
    if (mode == Kartenansicht.globus && !_globePointsSynced) {
      _syncGlobePoints(focus: true);
    }
  }

  /// Springt von einem Globus-Pin direkt in die flache, kachelbasierte
  /// Karte an dieser Stelle (siehe Doku bei [_pendingFlatFocus]) – der
  /// Globus selbst kann Straßenebene nicht darstellen.
  void _jumpToFlatMap(List<AssetData> group) {
    setState(() {
      _pendingFlatFocus = _averageCenter(group);
      _pendingFlatZoom = 16;
      _flacherZoom = 16;
      _mode = _lastFlatMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final located = _located;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppTexte.of(context).karteTitel),
        actions: [
          PopupMenuButton<Kartenansicht>(
            tooltip: AppTexte.of(context).karteAnsicht,
            icon: Icon(switch (_mode) {
              Kartenansicht.hell => Icons.light_mode_outlined,
              Kartenansicht.dunkel => Icons.dark_mode_outlined,
              Kartenansicht.topo => Icons.terrain_outlined,
              Kartenansicht.eigene => Icons.travel_explore_outlined,
              Kartenansicht.globus => Icons.public,
            }),
            onSelected: _setMode,
            itemBuilder: (context) => [
              _modeMenuItem(Kartenansicht.hell, Icons.light_mode_outlined,
                  AppTexte.of(context).karteHell),
              _modeMenuItem(Kartenansicht.dunkel, Icons.dark_mode_outlined,
                  AppTexte.of(context).karteDunkel),
              _modeMenuItem(Kartenansicht.topo, Icons.terrain_outlined,
                  AppTexte.of(context).karteTopografie),
              if (eigeneKarte case final k?)
                _modeMenuItem(Kartenansicht.eigene,
                    Icons.travel_explore_outlined, k.name),
              _modeMenuItem(Kartenansicht.globus, Icons.public,
                  AppTexte.of(context).karteGlobus),
            ],
          ),
        ],
      ),
      body: _buildBody(located),
    );
  }

  PopupMenuItem<Kartenansicht> _modeMenuItem(Kartenansicht mode, IconData icon, String label) {
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
          if (mode == _mode) ...[
            const Spacer(),
            const Icon(Icons.check, size: 18),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(List<AssetData>? located) {
    if (located == null) return const Center(child: CircularProgressIndicator());
    if (located.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            AppTexte.of(context).karteKeineOrteLang,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_mode == Kartenansicht.globus) {
      return Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final radius = math.min(constraints.maxWidth, constraints.maxHeight) / 2 - 16;
                return Center(
                  child: FlutterEarthGlobe(
                    controller: _ensureGlobeController(),
                    radius: radius.clamp(60.0, 400.0),
                    onZoomChanged: _onGlobeZoomChanged,
                  ),
                );
              },
            ),
          ),
          // Der Hinweis steht oben und nicht unten: Unten sitzt schon der
          // Texturnachweis, und beim Zoomen schaut man auf die Mitte.
          if (_globusZoom >= zoomHinweisAb)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          AppTexte.of(context).karteGlobusZoomHinweis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Zoomsteuerung(
              beiNaeher: _globusZoom >= (_globeController?.maxZoom ?? 6)
                  ? null
                  : () => _globusZoomen(1),
              beiWeiter: _globusZoom <= (_globeController?.minZoom ?? -1)
                  ? null
                  : () => _globusZoomen(-1),
              beiStandort: NativeImageConverter.standortMoeglich
                  ? _zumStandort
                  : null,
              standortLaeuft: _standortLaeuft,
              beiEreignisse: _ereignisse.isEmpty ? null : _ereignisseUmschalten,
              ereignisseAn: _ereignisseZeigen,
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Text(
              AppTexte.of(context).karteTexturNachweis,
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    // Der Kartenstil folgt der Nutzerwahl, nicht dem App-Theme: Die App
    // ist permanent dunkel, das Theme lieferte also nie helle Kacheln.
    final stil = switch (_mode) {
      Kartenansicht.hell => Kartenstil.hell,
      Kartenansicht.topo => Kartenstil.topo,
      Kartenansicht.eigene => Kartenstil.eigene,
      // Der Globus zeichnet keine Kacheln; der Wert wird dann nicht
      // benutzt, muss aber existieren.
      Kartenansicht.dunkel || Kartenansicht.globus => Kartenstil.dunkel,
    };
    // Ein Marker je Gruppe statt je Foto. Vorher stand für jedes verortete
    // Foto ein eigener Marker auf der Karte, jeder mit seiner vollen
    // 400×300-Vorschau: Bei 1140 Fotos waren das 498 MB dekodierte Bitmaps
    // für 40 Punkte große Kreise – weit über Flutters Bildspeicher von
    // 100 MB. Sichtbar wurde das als graues Platzhalter-Symbol statt eines
    // Vorschaubilds, und zwar auf den meisten Markern.
    final gruppen = gruppiereFuerKarte(located, _flacherZoom,
        (a) => (breite: a.latitude!, laenge: a.longitude!));
    // Die flache Karte bekommt dieselbe Leiste – deshalb ein Stack um
    // sie herum. FlutterMap selbst kann keine festen Aufsätze.
    return Stack(
      children: [
        Positioned.fill(child: _flacheKarteBauen(located, gruppen, stil)),
        Positioned(
          right: 8,
          bottom: 24,
          child: Zoomsteuerung(
            beiNaeher: () => _flachZoomen(1),
            beiWeiter: () => _flachZoomen(-1),
            beiStandort:
                NativeImageConverter.standortMoeglich ? _zumStandort : null,
            standortLaeuft: _standortLaeuft,
            beiEreignisse: _ereignisse.isEmpty ? null : _ereignisseUmschalten,
            ereignisseAn: _ereignisseZeigen,
          ),
        ),
      ],
    );
  }

  Widget _flacheKarteBauen(List<AssetData> located,
      Map<String, List<AssetData>> gruppen, Kartenstil stil) {
    // Der Wisch-Zoom sitzt aussen herum, damit eine Maus ohne Rad
    // (Magic Mouse) und ein Trackpad ueberhaupt zoomen koennen – die
    // Kartenbibliothek verschiebt bei solchen Gesten nur. Siehe
    // [WischZoom], dort steht auch, warum die Reihenfolge stimmt.
    final hoechsteStufe = stil.hoechsteAnzeigeStufe.toDouble();
    return WischZoom(
      steuerung: _flacheKarte,
      groesserZoom: hoechsteStufe,
      child: FlutterMap(
        mapController: _flacheKarte,
        options: MapOptions(
          initialCenter: _pendingFlatFocus ?? _averageCenter(located),
          initialZoom: _pendingFlatZoom ?? _standardZoom,
          // Ohne diese Grenze zoomt die Karte ins Nichts – siehe
          // [Kartenstil.hoechsteAnzeigeStufe]. Sie gilt für ALLE Wege
          // hinein: Rad, Kneifen, Doppelklick-Ziehen und Wischen.
          maxZoom: hoechsteStufe,
          onPositionChanged: _onFlatPositionChanged,
        ),
        children: [
          Kachelschicht(stil: stil),
          // **Der Massstab.** Bis hierher liess sich ueber Kartentiefe nur
          // in Zoomstufen reden, und „Stufe 17" sagt niemandem etwas. Mit
          // der Leiste steht die Antwort auf „wie nah komme ich heran"
          // unmittelbar im Bild – und ein Bericht darueber, wo es klemmt,
          // hat eine gemeinsame Sprache.
          Scalebar(
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.only(
                left: AppSpacing.md, bottom: AppSpacing.xxl),
            lineColor: Theme.of(context).colorScheme.onSurface,
            textStyle: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface,
              shadows: [
                Shadow(
                    blurRadius: 3,
                    color: Theme.of(context).colorScheme.surface),
              ],
            ),
          ),
          buildMapAttribution(context, stil: stil),
          // Unter den Fotomarken: Wo beides am selben Ort liegt, gehört
          // das Foto obenauf – es lässt sich öffnen, das Ereignis nicht.
          if (_ereignisseZeigen && _ereignisse.isNotEmpty)
            MarkerLayer(
              markers: [
                for (final e in _ereignisse)
                  Marker(
                    point: ll.LatLng(
                        e.ereignis.ortBreite!, e.ereignis.ortLaenge!),
                    width: markerGroesse,
                    height: markerGroesse,
                    alignment: Alignment.center,
                    child: Tooltip(
                      message: [
                        e.personName,
                        if (e.ereignis.ort != null &&
                            e.ereignis.ort!.isNotEmpty)
                          e.ereignis.ort!,
                      ].join(' · '),
                      child: _GlobusEreignis(
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
                  point: _averageCenter(gruppe),
                  width: markerGroesse,
                  height: markerGroesse,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: () => _openAsset(gruppe, gruppe.first),
                    child: _MapThumbMarker(
                      asset: gruppe.first,
                      anzahl: gruppe.length,
                      paths: widget.library.paths,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Knöpfe ----------------------------------------------------------

  /// Ein Zoomschritt auf dem Globus.
  ///
  /// Selbst geklemmt und nicht `setZoom` überlassen: Dessen Klemmung ist
  /// wirkungslos – liegt der Wert ausserhalb, setzt die Bibliothek eine
  /// lokale Variable und lässt `zoom` unverändert. Ausserdem greift im
  /// Debug-Bau vorher eine Zusicherung.
  void _globusZoomen(double schritt) {
    final c = _ensureGlobeController();
    final neu = (c.zoom + schritt).clamp(c.minZoom, c.maxZoom);
    if (neu == c.zoom) return;
    c.setZoom(neu);
    _onGlobeZoomChanged(neu);
  }

  /// Holt den Zoom zurück, wenn der neue Stil weniger weit reicht.
  ///
  /// Die Stile hören unterschiedlich früh auf – CARTO trägt bis 20,
  /// OpenTopoMap nur bis 17. Wer in der dunklen Karte weit hineingezoomt
  /// hat und dann auf Topografie umschaltet, stünde sonst oberhalb der
  /// neuen Grenze: Die Kartenoptionen lassen dort zwar nichts Neues mehr
  /// zu, holen den bestehenden Stand aber nicht von selbst zurück.
  void _zoomAufStilGrenzeZiehen(Kartenansicht neueAnsicht) {
    if (neueAnsicht == Kartenansicht.globus) return;
    final grenze = switch (neueAnsicht) {
      Kartenansicht.hell => Kartenstil.hell,
      Kartenansicht.topo => Kartenstil.topo,
      Kartenansicht.eigene => Kartenstil.eigene,
      Kartenansicht.dunkel || Kartenansicht.globus => Kartenstil.dunkel,
    }
        .hoechsteAnzeigeStufe
        .toDouble();
    if (_flacherZoom > grenze) _flacherZoom = grenze;
    if (_pendingFlatZoom != null && _pendingFlatZoom! > grenze) {
      _pendingFlatZoom = grenze;
    }
  }

  void _ereignisseUmschalten() {
    setState(() => _ereignisseZeigen = !_ereignisseZeigen);
    // Der Globus hält seine Punkte im Steuergerät, nicht im Widgetbaum –
    // ein `setState` allein bewegt dort nichts.
    if (_mode == Kartenansicht.globus) _syncGlobePoints(zoom: _globusZoom);
  }

  void _flachZoomen(double schritt) {
    final kamera = _flacheKarte.camera;
    // Die Obergrenze kommt aus den Kartenoptionen und damit vom
    // gewählten Stil. Vorher stand hier fest 18 – das passte zu keiner
    // der drei Quellen und war zugleich die EINZIGE Grenze in der
    // Karte: Rad, Kneifen und Wischen kannten gar keine.
    final neu = (kamera.zoom + schritt)
        .clamp(kamera.minZoom ?? 1.0, kamera.maxZoom ?? 19.0);
    if (neu == kamera.zoom) return;
    _flacheKarte.move(kamera.center, neu);
  }

  /// Springt auf den eigenen Standort – auf beiden Kartenarten.
  ///
  /// Nur auf Plattformen mit Ortungsanbindung überhaupt aufrufbar (siehe
  /// [NativeImageConverter.standortMoeglich]); der Knopf fehlt sonst.
  Future<void> _zumStandort() async {
    setState(() => _standortLaeuft = true);
    final ort = await NativeImageConverter.aktuellerStandort();
    if (!mounted) return;
    setState(() => _standortLaeuft = false);
    if (ort == null) {
      melde.warnung(AppTexte.of(context).karteStandortNichtErmittelbar);
      return;
    }
    if (_mode == Kartenansicht.globus) {
      final c = _ensureGlobeController();
      c.focusOnCoordinates(GlobeCoordinates(ort.breite, ort.laenge),
          animate: true);
      // Nah genug, um die Gegend zu erkennen, aber nicht so nah, dass nur
      // noch verwaschene Textur zu sehen ist (siehe [zoomHinweisAb]).
      final ziel = math.min(zoomHinweisAb, c.maxZoom);
      if (c.zoom < ziel) {
        c.setZoom(ziel);
        _onGlobeZoomChanged(ziel);
      }
    } else {
      _flacheKarte.move(ll.LatLng(ort.breite, ort.laenge), 14);
      setState(() => _flacherZoom = 14);
    }
  }

  /// Gruppiert neu, sobald sich die Zoomstufe um einen ganzen Schritt
  /// geändert hat.
  ///
  /// Auf ganze Stufen gerundet, weil `onPositionChanged` bei einer
  /// laufenden Zoomgeste in jedem Frame feuert – ohne diese Rundung würde
  /// die komplette Markerliste dutzendfach pro Sekunde neu aufgebaut.
  void _onFlatPositionChanged(MapCamera camera, bool hasGesture) {
    final stufe = camera.zoom.roundToDouble();
    if (stufe == _flacherZoom) return;
    setState(() => _flacherZoom = stufe);
  }
}

/// Die Knopfleiste, die auf beiden Kartenarten rechts unten sitzt.
///
/// Bewusst ein gemeinsames Widget für Globus und flache Karte: Zwei
/// Leisten, die gleich aussehen sollen, laufen sonst früher oder später
/// auseinander. Was sie tun, unterscheidet sich – wie sie aussehen und
/// wo sie sitzen, nicht.
/// Ein Marker auf der flachen Karte: das Vorschaubild des jüngsten Fotos
/// seiner Gruppe, bei mehreren zusätzlich deren Anzahl.
class _MapThumbMarker extends StatelessWidget {
  final AssetData asset;

  /// Wie viele Fotos an diesem Punkt zusammengefasst sind.
  final int anzahl;
  final StoragePaths paths;
  const _MapThumbMarker({
    required this.asset,
    required this.anzahl,
    required this.paths,
  });

  @override
  Widget build(BuildContext context) {
    final thumbPath = asset.thumbnailRelativePath;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final masse = deckendeDekodiermasse(
      kachelBreite: 40,
      kachelHoehe: 40,
      bildBreite: asset.widthPx,
      bildHoehe: asset.heightPx,
      pixelverhaeltnis: dpr,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
          ),
          child: ClipOval(
            child: thumbPath != null
                ? Image.file(
                    paths.absolute(thumbPath),
                    fit: BoxFit.cover,
                    // Auf Markergröße dekodieren statt auf die volle
                    // Vorschaugröße – derselbe Grund wie bei
                    // [AssetThumbnailTile]: Der Kreis ist 40 Punkte groß,
                    // die Datei auf der Platte 400 Pixel breit. Und aus
                    // demselben Grund nur eine Kante: Beide zusammen
                    // stauchten das Bild, siehe [deckendeDekodiermasse].
                    cacheWidth: masse.breite,
                    cacheHeight: masse.hoehe,
                    errorBuilder: (_, __, ___) => _fallbackIcon(),
                  )
                : _fallbackIcon(),
          ),
        ),
        if (anzahl > 1)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Text(
                '$anzahl',
                style: const TextStyle(
                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fallbackIcon() => Container(
        color: Colors.grey.shade800,
        alignment: Alignment.center,
        child: Icon(
          asset.type == 'VIDEO' ? Icons.videocam : Icons.image,
          color: Colors.white70,
          size: 18,
        ),
      );
}

/// Pin-Nadel für den Globus-Modus (statt einer vom Bibliotheks-eigenen
/// Kugel-Renderer gezeichneten, bei Zoom leicht überdimensionierten
/// Ellipse) – ein normales, gestochen scharfes Flutter-Icon, das über
/// [Point.labelBuilder] exakt an der Foto-Koordinate verankert wird
/// (Spitze der Nadel = Position). Bei mehreren Fotos am selben
/// Raster-Punkt zeigt ein kleines Badge die Anzahl.
/// Wie weit die Spitze von [Icons.location_pin] über der Unterkante ihres
/// Kastens sitzt, bei [pinGroesse] Punkt Schriftgröße.
///
/// **Gemessen und nicht geschätzt** (siehe `globus_pin_test.dart`): Die
/// Glyphe füllt ihren Kasten nicht aus, ihre Tinte endet bei 25,75 von 34
/// Punkten. Die Bibliothek setzt aber die **Unterkante** des Widgets auf
/// den Ort — die Spitze zeigte damit 8,25 Punkte zu weit nach Norden. Auf
/// dem herausgezoomten Globus (Radius 400 Punkte) sind das 1,18 Grad oder
/// rund 130 Kilometer: Flensburg landete im Kattegat.
const double pinSpitzeUeberKante = 8.25;

/// Die Kantenlänge des Pins. Muss mit der Schriftgröße übereinstimmen —
/// ein schmalerer Kasten quetscht die Glyphe aus der Mitte, und dann
/// stimmt auch die Ost-West-Lage nicht mehr. Gemessen: im 30 Punkte
/// breiten Kasten saß die Tinte 1,9 Punkte rechts der Mitte, im 34 Punkte
/// breiten nur noch 0,1.
const double pinGroesse = 34;

/// Die halbe Höhe der Ereignisraute.
///
/// Bei einer Raute ist die **Mitte** die Aussage und nicht die Unterkante:
/// Sie zeigt auf einen Ort, sie steht nicht auf ihm. Ohne diese
/// Verschiebung säße die ganze Raute nördlich des Ereignisses.
const double rauteHalb = 8;

class _GlobePin extends StatelessWidget {
  final int count;
  const _GlobePin({required this.count});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: pinGroesse,
      height: pinGroesse,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.location_pin,
            color: Colors.redAccent,
            size: pinGroesse,
            shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
          ),
          if (count > 1)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ein Lebensereignis auf dem Globus.
///
/// Dieselbe Raute wie auf der Familienkarte, nur kleiner: Der Globus
/// zeigt die halbe Welt auf einmal, und eine Marke in Kartengrösse deckte
/// dort ganze Länder zu.
class _GlobusEreignis extends StatelessWidget {
  final IconData symbol;
  const _GlobusEreignis({required this.symbol});

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: rauteHalb * 2,
        height: rauteHalb * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: farben.primaryContainer,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Transform.rotate(
          angle: -math.pi / 4,
          child: Icon(symbol, size: 9, color: farben.onPrimaryContainer),
        ),
      ),
    );
  }
}
