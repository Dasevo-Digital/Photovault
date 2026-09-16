/// Die Route einer Reise oder einer Aktivität als kleine Karte.
///
/// **Bedienbar, aber nicht über das Rad.** Die erste Fassung war
/// vollständig unbeweglich, und der Grund dafür gilt weiter: Eine Karte,
/// die das Mausrad annimmt, verschluckt inmitten einer rollbaren Seite
/// jeden zweiten Wisch – man will die Seite scrollen und zoomt
/// stattdessen die Karte. Deshalb bedient sie sich über **Knöpfe**:
///
/// * `+` und `−` zoomen,
/// * ein Knopf passt den Ausschnitt wieder auf die Strecke ein,
/// * ein vierter macht die Karte höher und wieder kleiner.
///
/// Ziehen mit der Maus verschiebt trotzdem – das ist die eine Geste, die
/// sich mit dem Rollen der Seite nicht in die Quere kommt, und ohne sie
/// wäre Hineinzoomen sinnlos: Man landete in einer Ecke, aus der man
/// nicht herauskäme.
///
/// **Ausdrücklich ohne `WischZoom`** (siehe `kartenzoom_test.dart`). Die
/// Regel dort verlangt für jede bedienbare Karte Knöpfe **und** Wischen,
/// weil eine Magic Mouse kein Rad hat. Ihr Zweck ist erfüllt: Zoomen
/// geht hier auf jedem Gerät, nämlich über die Knöpfe. Das Wischen
/// hinzuzunehmen kehrte dagegen genau den Schaden zurück, den die
/// unbewegliche Karte vermeiden sollte – auf einer Tastfläche ist der
/// Zweifingerwisch die Geste zum Rollen der Seite.
/// zoomregel: nur Knoepfe (Karte in einer rollbaren Seite)
///
/// Herausgelöst aus `reise_detail_screen.dart`, weil eine Wanderung
/// dieselbe Karte verdient wie eine Reise: dieselbe Strecke, dieselben
/// Ortsbilder, nur ein kleinerer Ausschnitt.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/reiseroute.dart';
import '../services/storage_paths.dart';
import '../theme/app_spacing.dart';
import 'mini_location_map.dart'
    show Kachelschicht, buildMapAttribution, kartenHoechsteStufe;
import 'zoomsteuerung.dart';

class Routenkarte extends StatefulWidget {
  final List<Routenpunkt> route;
  final List<Aufenthaltsort> orte;
  final Map<String, AssetData> nachId;
  final StoragePaths paths;
  final void Function(Aufenthaltsort) beiOrt;

  /// Wie hoch die Karte sein darf. Eine Reise über drei Länder braucht
  /// mehr Fläche als eine Wanderung über zwölf Kilometer.
  final double hoehe;

  /// Aufgezeichnete Spuren, über die Foto-Route gelegt.
  ///
  /// **Zwei Sorten Linien und nicht eine.** Die Route aus den Fotos ist
  /// eine Vermutung – zwischen zwei Bildern wird geradeaus gegangen. Eine
  /// Spur ist eine Messung. Sie ineinander zu rechnen hiesse, den
  /// Unterschied zu verwischen.
  ///
  /// **Mehrere und nicht eine.** Eine Wanderung hat eine Spur, eine Reise
  /// hat je Tag eine. Alle Punkte in eine Liste zu werfen zöge zwischen
  /// dem Ende des einen Tages und dem Anfang des nächsten eine gerade
  /// Linie quer über die Karte – eine Strecke, die niemand gegangen ist.
  final List<List<({double breite, double laenge})>> spuren;

  /// Der Punkt der Spur, auf den gerade gezeigt wird – aus dem
  /// Höhenprofil daneben.
  final ({double breite, double laenge})? stelle;

  const Routenkarte({
    super.key,
    required this.route,
    required this.orte,
    required this.nachId,
    required this.paths,
    required this.beiOrt,
    this.hoehe = 240,
    this.spuren = const [],
    this.stelle,
  });

  /// Die Stufen, um die sich die Karte vergrössern lässt – Vielfache von
  /// [hoehe].
  ///
  /// Drei und nicht stufenlos: Ein Regler für eine Höhe wäre Bedienung
  /// für etwas, das man einmal einstellt. Der grösste Schritt ist so
  /// gewählt, dass die Karte auf einem gewöhnlichen Fenster noch nicht
  /// die ganze Seite verdrängt.
  static const stufen = [1.0, 1.8, 2.8];

  @override
  State<Routenkarte> createState() => _RoutenkarteState();
}

class _RoutenkarteState extends State<Routenkarte> {
  final _steuerung = MapController();

  /// Welche der [Routenkarte.stufen] gerade gilt.
  int _stufe = 0;

  /// Der Ausschnitt, auf den „einpassen" zurückführt – derselbe, mit dem
  /// die Karte aufgemacht hat.
  CameraFit? _anfang;

  @override
  void dispose() {
    _steuerung.dispose();
    super.dispose();
  }

  void _zoom(double schritte) {
    final kamera = _steuerung.camera;
    final ziel = (kamera.zoom + schritte)
        .clamp(kamera.minZoom ?? 1.0, kamera.maxZoom ?? 20.0);
    _steuerung.move(kamera.center, ziel);
  }

  void _einpassen() {
    if (_anfang case final fit?) _steuerung.fitCamera(fit);
  }

  void _groesse() {
    setState(() => _stufe = (_stufe + 1) % Routenkarte.stufen.length);
    // Der Ausschnitt bleibt, die Fläche wächst – die Karte zeigt dann
    // mehr Umgebung, nicht einen anderen Ort.
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final route = widget.route;
    final orte = widget.orte;
    final nachId = widget.nachId;
    final paths = widget.paths;
    final beiOrt = widget.beiOrt;
    final stelle = widget.stelle;
    final punkte = [for (final p in route) ll.LatLng(p.breite, p.laenge)];
    final spurlinien = [
      for (final s in widget.spuren)
        [for (final p in s) ll.LatLng(p.breite, p.laenge)],
    ];
    _anfang ??= CameraFit.coordinates(
      coordinates: [...punkte, for (final l in spurlinien) ...l],
      padding: const EdgeInsets.all(AppSpacing.xxl),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        height: widget.hoehe * Routenkarte.stufen[_stufe],
        child: Stack(children: [
        FlutterMap(
          mapController: _steuerung,
          options: MapOptions(
            // Der Ausschnitt wird auf die Strecke gelegt, nicht auf eine
            // geratene Mitte mit geratener Zoomstufe.
            // Beides einpassen: Eine Spur, die weiter reicht als die
            // Fotos, liefe sonst aus dem Bild.
            initialCameraFit: _anfang,
            // Nur Ziehen. Kein Rad und kein Kneifen: Beides ist auf
            // dieser Seite die Geste zum Rollen, und die Karte darf sie
            // der Seite nicht wegnehmen.
            interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag),
            // Das Einpassen auf die Strecke kann bei zwei dicht
            // beieinanderliegenden Punkten über die höchste Stufe hinaus
            // rechnen, für die es Kacheln gibt.
            maxZoom: kartenHoechsteStufe(context),
          ),
          children: [
            const Kachelschicht(),
            PolylineLayer(polylines: [
              Polyline(
                points: punkte,
                strokeWidth: 3,
                color: farben.primary,
              ),
              for (final linie in spurlinien)
                if (linie.length > 1)
                  Polyline(
                    points: linie,
                    strokeWidth: 4,
                    color: farben.tertiary,
                  ),
            ]),
            MarkerLayer(markers: [
              for (final (i, p) in punkte.indexed)
                Marker(
                  point: p,
                  width: 14,
                  height: 14,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Anfang und Ende betont: Eine Strecke ohne
                      // erkennbare Richtung ist nur ein Strich.
                      color: i == 0 || i == punkte.length - 1
                          ? farben.primary
                          : farben.surface,
                      border: Border.all(color: farben.primary, width: 2),
                    ),
                  ),
                ),
            ]),
            // Die Bilder liegen ueber der Strecke: Sie sind das, wonach man
            // auf einer Reisekarte sucht.
            MarkerLayer(markers: [
              for (final ort in orte)
                if (nachId[ort.aufnahmeIds.first] case final bild?)
                  Marker(
                    point: ll.LatLng(ort.breite, ort.laenge),
                    width: 52,
                    height: 52,
                    child: _Ortsbild(
                      bild: bild,
                      paths: paths,
                      anzahl: ort.aufnahmeIds.length,
                      name: ort.name,
                      beiTippen: () => beiOrt(ort),
                    ),
                  ),
            ]),
            if (stelle case final s?)
              MarkerLayer(markers: [
                Marker(
                  point: ll.LatLng(s.breite, s.laenge),
                  width: 18,
                  height: 18,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: farben.error,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ]),
            buildMapAttribution(context),
          ],
        ),
        Positioned(
          right: AppSpacing.sm,
          top: AppSpacing.sm,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Zoomsteuerung(
                beiNaeher: () => _zoom(1),
                beiWeiter: () => _zoom(-1),
                beiEinpassen: _einpassen,
              ),
              const SizedBox(height: AppSpacing.sm),
              // Die Fläche der Karte ist keine Sache des Zooms, sondern
              // des Platzes auf der Seite – deshalb ein eigener Knopf und
              // nicht ein vierter in der Zoomleiste.
              Material(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(AppRadius.md),
                clipBehavior: Clip.antiAlias,
                child: Tooltip(
                  message: _stufe == Routenkarte.stufen.length - 1
                      ? t.routeVerkleinern
                      : t.routeVergroessern,
                  child: InkResponse(
                    onTap: _groesse,
                    radius: 22,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        _stufe == Routenkarte.stufen.length - 1
                            ? Icons.close_fullscreen
                            : Icons.open_in_full,
                        size: 20,
                        color: farben.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ]),
      ),
    );
  }
}

/// Ein Aufenthaltsort als Bild auf der Karte.
///
/// Die Karte selbst bleibt unbeweglich (siehe [Routenkarte]) – ein
/// Tippen kommt trotzdem an, weil die Marke ein gewöhnliches Widget ist.
/// Genau das ist der Grund für die Aufteilung: Eine Karte, die sich
/// schieben lässt, würde inmitten einer rollbaren Seite jeden zweiten
/// Wisch verschlucken.
class _Ortsbild extends StatelessWidget {
  final AssetData bild;
  final StoragePaths paths;
  final int anzahl;
  final String? name;
  final VoidCallback beiTippen;

  const _Ortsbild({
    required this.bild,
    required this.paths,
    required this.anzahl,
    required this.name,
    required this.beiTippen,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final pfad = bild.thumbnailRelativePath;
    return Tooltip(
      message: [
        if (name case final n?) n,
        t.reisenAufnahmen(anzahl),
      ].join(' · '),
      child: GestureDetector(
        onTap: beiTippen,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 4),
                  ],
                  color: farben.surfaceContainerHighest,
                ),
                clipBehavior: Clip.antiAlias,
                child: pfad == null
                    ? Icon(Icons.image_outlined,
                        size: 18, color: farben.onSurfaceVariant)
                    : Image.file(
                        paths.absolute(pfad),
                        fit: BoxFit.cover,
                        // Die Marke ist 44 Punkte gross; die Vorschau auf
                        // der Platte ist 400. Ohne diese Grenze läge bei
                        // zwanzig Orten das Zwanzigfache im Speicher.
                        cacheWidth: 132,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.image_not_supported_outlined,
                            size: 18,
                            color: farben.onSurfaceVariant),
                      ),
              ),
              if (anzahl > 1)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs, vertical: 1),
                    decoration: BoxDecoration(
                      color: farben.primary,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Text('$anzahl',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: farben.onPrimary)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
