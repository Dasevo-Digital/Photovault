import 'dart:io';

import 'package:flutter/material.dart';
import 'package:panorama_viewer/panorama_viewer.dart';

import '../services/bilddekodierung.dart';

/// Darstellungsart für ein equirechteckiges 360°-Foto (siehe
/// [Panorama360View]).
enum Panorama360Mode {
  /// Echte Kugelprojektion – das Foto wird als Textur auf eine 3D-Kugel
  /// gelegt, betrachtet aus deren Mittelpunkt ("Umschauen").
  sphere,

  /// Flaches Pan/Zoom über das rohe, equirechteckige Bild.
  flat,
}

/// Zeigt ein equirechteckiges 360°-Foto (siehe isEquirectangular360 in
/// asset_format.dart), je nach [mode] als echte 3D-Kugel oder als flaches
/// Pan/Zoom.
///
/// Die Kugelansicht nutzt `panorama_viewer` (auf `flutter_cube` aufbauend).
/// Bewusst NICHT `flutter_earth_globe` (das Paket bleibt für den 3D-Globus
/// in MapScreen zuständig): dessen Kugel rendert auf diesem Gerät real
/// nachweislich nichts Sichtbares, sobald die Textur nicht aus einem
/// gebündelten Asset stammt. Per RenderRepaintBoundary.toImage()-
/// Pixelerfassung mit identischem Bildinhalt gemessen: `AssetImage` 64,7 %
/// nicht-schwarze Pixel, `FileImage` und `MemoryImage` jeweils 0,0 %. Fotos
/// aus der Bibliothek sind immer Dateien, nie gebündelte Assets – damit ist
/// jenes Paket für diese Ansicht grundsätzlich unbrauchbar.
/// `panorama_viewer` löst den ImageProvider dagegen selbst über Flutters
/// normalen ImageStream zu einem `ui.Image` auf und übergibt erst das
/// fertig dekodierte Bild an die 3D-Schicht – damit real verifiziert
/// 97,3 % nicht-schwarze Pixel mit demselben Foto aus der Bibliothek.
class Panorama360View extends StatefulWidget {
  final File imageFile;
  final Panorama360Mode mode;

  const Panorama360View({
    super.key,
    required this.imageFile,
    this.mode = Panorama360Mode.sphere,
  });

  @override
  State<Panorama360View> createState() => _Panorama360ViewState();
}

class _Panorama360ViewState extends State<Panorama360View> {
  final _transformController = TransformationController();
  final _viewerKey = GlobalKey();

  static const _initialScale = 1.8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialZoom());
  }

  @override
  void didUpdateWidget(covariant Panorama360View oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Beim Zurückschalten auf die flache Ansicht ist der InteractiveViewer
    // frisch aufgebaut und stünde sonst wieder bei Faktor 1.
    if (oldWidget.mode != widget.mode && widget.mode == Panorama360Mode.flat) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialZoom());
    }
  }

  /// Zoomt einmalig, mittig um den Sichtbereich, direkt nach dem Layout ein –
  /// [InteractiveViewer] startet sonst bei Faktor 1 (ganzes, stark
  /// verzerrtes Panorama auf einen Blick).
  void _applyInitialZoom() {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    final dx = -size.width * (_initialScale - 1) / 2;
    final dy = -size.height * (_initialScale - 1) / 2;
    _transformController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(_initialScale, _initialScale, 1, 1);
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: widget.mode == Panorama360Mode.sphere ? _buildSphere() : _buildFlat(),
    );
  }

  Widget _buildSphere() {
    return PanoramaViewer(
      // Sensorsteuerung bleibt aus: Am Mac gibt es keine sinnvollen
      // Lage-Sensoren, gedreht wird ausschließlich per Maus/Trackpad.
      sensorControl: SensorControl.none,
      // Begrenzt dekodieren. Ausgerechnet hier fehlte der Deckel, und
      // ausgerechnet hier sind die Dateien am groessten: Eine
      // 360°-Aufnahme ist zwei zu eins, die der Prüfbibliothek misst
      // 7578 × 3788 und belegt als Bitmap 110 MB. Die Vollbildansicht
      // desselben Fotos begrenzt seit jeher auf 4096.
      child: Image(
        image: begrenztesBild(widget.imageFile),
        gaplessPlayback: true,
      ),
    );
  }

  Widget _buildFlat() {
    return InteractiveViewer(
      key: _viewerKey,
      transformationController: _transformController,
      minScale: 1.0,
      maxScale: 6.0,
      child: Image(
        image: begrenztesBild(widget.imageFile),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}
