import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

import '../db/rasterzeile.dart';
import '../services/bilddekodierung.dart';
import '../services/schwebevorschau.dart';
import '../services/storage_paths.dart';
import 'schwebevorschau.dart';
import '../theme/app_spacing.dart';

/// Kantenlaenge eines Gesichts-Ausschnitts in [LocalImageTile].
const double _ausschnittKante = 160;

/// Eine Kachel im Raster.
///
/// **Warum zustandsbehaftet.** Traegt die Aufnahme ein Video – ein
/// eigenstaendiges oder die zweite Haelfte eines Live Photos –, laeuft es
/// an, wenn die Maus einen Augenblick darauf stehen bleibt. Dafuer
/// braucht die Kachel eine Uhr, die sie beim Verlassen wieder anhaelt
/// (siehe [schwebeVerzoegerung]). Alle anderen Kacheln verhalten sich
/// wie zuvor: ohne Bereich darueber, ohne Video im Datensatz gibt es
/// weder [MouseRegion] noch Uhr.
class AssetThumbnailTile extends StatefulWidget {
  final Rasterzeile asset;
  final StoragePaths paths;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;

  /// Zeigt ein abdunkelndes Overlay mit Häkchen, analog zu [LocalImageTile]
  /// – für die Mehrfachauswahl in Timeline/Suche/Alben (siehe
  /// SelectionActionBar).
  final bool selected;

  const AssetThumbnailTile({
    super.key,
    required this.asset,
    required this.paths,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.selected = false,
  });

  @override
  State<AssetThumbnailTile> createState() => _AssetThumbnailTileState();
}

class _AssetThumbnailTileState extends State<AssetThumbnailTile> {
  /// Laeuft, sobald der Zeiger die Kachel betritt; loest die Wiedergabe
  /// aus, wenn er lange genug bleibt.
  Timer? _uhr;
  Schwebevorschau? _vorschau;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _vorschau = Schwebevorschau.maybeOf(context);
  }

  @override
  void didUpdateWidget(covariant AssetThumbnailTile alt) {
    super.didUpdateWidget(alt);
    // Beim Scrollen wird dieselbe Kachel mit einer anderen Aufnahme
    // weiterverwendet. Was fuer die alte lief, gilt fuer die neue nicht.
    if (alt.asset.id != widget.asset.id) {
      _uhr?.cancel();
      _vorschau?.beende(alt.asset.id);
    }
  }

  @override
  void dispose() {
    _uhr?.cancel();
    // Aus dem Bild gescrollt heisst: nicht mehr angesehen. Sieht der
    // Bereich inzwischen eine andere Kachel, tut das hier nichts.
    _vorschau?.beende(widget.asset.id);
    super.dispose();
  }

  void _zeigerEin() {
    _uhr?.cancel();
    _uhr = Timer(schwebeVerzoegerung, () {
      if (!mounted) return;
      unawaited(_vorschau?.starte(widget.asset) ?? Future.value());
    });
  }

  void _zeigerAus() {
    _uhr?.cancel();
    _uhr = null;
    _vorschau?.beende(widget.asset.id);
  }

  /// Sprechendes Label für VoiceOver, da die Kachel sonst nur als
  /// unbeschriftetes Bild-Icon vorgelesen würde – Favorit-/Bewertungsstatus
  /// fließen mit ein, damit sie auch ohne den Info-Bereich hörbar sind.
  String _semanticLabel(BuildContext context) {
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).toString();
    final parts = <String>[
      t.kachelBeschreibung(
        widget.asset.type == 'VIDEO' ? t.allgVideo : t.allgFoto,
        widget.asset.originalFileName,
        DateFormat.yMMMMd(sprache).format(widget.asset.fileCreatedAt),
      ),
    ];
    if (widget.asset.type == 'VIDEO' && widget.asset.durationSeconds != null) {
      parts.add(_formatDuration(widget.asset.durationSeconds!));
    }
    if (widget.asset.isFavorite) parts.add(t.kachelFavorisiert);
    if (widget.asset.rating > 0) parts.add(t.sterneBewertungAnzeige(widget.asset.rating));
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final thumbPath = widget.asset.thumbnailRelativePath;
    // Nur Kacheln, hinter denen ueberhaupt ein Video steckt, bekommen eine
    // Maus-Region und einen Zuhoerer. In einer Bibliothek aus 8098
    // Aufnahmen sind das 440 - alle anderen bleiben so leichtgewichtig
    // wie zuvor.
    final schwebt = _vorschau != null && schwebeVideoId(widget.asset) != null;
    return Semantics(
      label: _semanticLabel(context),
      button: true,
      selected: widget.selected,
      child: ExcludeSemantics(
        child: MouseRegion(
        onEnter: schwebt ? (_) => _zeigerEin() : null,
        onExit: schwebt ? (_) => _zeigerAus() : null,
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          onLongPress: widget.onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
          if (thumbPath != null)
            // Die dekodierte Bitmap wird auf die tatsächliche Kachelgröße
            // (× Pixelverhältnis) begrenzt, statt immer die volle, auf der
            // Platte hinterlegte 400px-Vorschau zu dekodieren und zu
            // cachen – in dichten Rasteransichten (Timeline, Kalender,
            // Alben) sind Kacheln oft deutlich kleiner als 400px.
            //
            // **In Stufen und nicht auf den Punkt** – siehe
            // [dekodierbreite]. Die Kachelbreite ändert sich mit jedem
            // Punkt Fensterbreite; ohne die Stufen bekäme jeder
            // Zwischenschritt eines Ziehens am Fenster einen eigenen
            // Schlüssel im Bildspeicher, und jede sichtbare Kachel würde
            // dabei neu dekodiert.
            //
            // **Und nur eine der beiden Kanten** – siehe
            // [deckendeDekodiermasse]. Beide zusammen stauchen das Bild.
            LayoutBuilder(
              builder: (context, constraints) {
                final masse = deckendeDekodiermasse(
                  kachelBreite: constraints.maxWidth,
                  kachelHoehe: constraints.maxHeight,
                  bildBreite: widget.asset.widthPx,
                  bildHoehe: widget.asset.heightPx,
                  pixelverhaeltnis:
                      MediaQuery.of(context).devicePixelRatio,
                );
                return Image.file(
                  widget.paths.absolute(thumbPath),
                  fit: BoxFit.cover,
                  cacheWidth: masse.breite,
                  cacheHeight: masse.hoehe,
                  errorBuilder: (_, __, ___) => _placeholder(),
                );
              },
            )
          else
            _placeholder(),
          // Ueber dem Standbild, unter den Abzeichen: Waehrend das Video
          // laeuft, sollen Favoritenherz und Ortsnadel nicht verschwinden.
          if (schwebt)
            ListenableBuilder(
              listenable: _vorschau!,
              builder: (context, _) =>
                  _vorschau!.bildFuer(widget.asset.id) ?? const SizedBox(),
            ),
          if (widget.asset.type == 'VIDEO')
            Positioned(
              right: 4,
              bottom: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.asset.durationSeconds != null) ...[
                    Text(
                      _formatDuration(widget.asset.durationSeconds!),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                      ),
                    ),
                    const SizedBox(width: 3),
                  ],
                  const Icon(Icons.play_circle_fill, color: Colors.white, size: 20),
                ],
              ),
            ),
          if (widget.asset.type == 'IMAGE' && widget.asset.linkedAssetId != null)
            const Positioned(
              right: 4,
              bottom: 4,
              child: Icon(Icons.motion_photos_on, color: Colors.white, size: 18),
            ),
          if (widget.asset.isFavorite)
            const Positioned(
              left: 4,
              top: 4,
              child: Icon(Icons.favorite, color: Colors.redAccent, size: 16),
            ),
          if (widget.asset.verortet)
            const Positioned(
              left: 4,
              bottom: 4,
              child: Icon(
                Icons.location_on,
                color: Colors.white,
                size: 14,
                shadows: [Shadow(color: Colors.black, blurRadius: 3)],
              ),
            ),
          // Stapel-Abzeichen hat Vorrang vor dem Format-Kürzel in derselben
          // Ecke – bei einem Serien-Titelbild ist "wie viele Fotos stecken
          // dahinter" wichtiger für die Kachel-Ansicht als das Dateiformat.
          if (widget.asset.isStackCover && widget.asset.stackSize != null)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.filter_none, color: Colors.white, size: 11),
                    const SizedBox(width: 3),
                    Text(
                      '${widget.asset.stackSize}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
          else if (widget.asset.kuerzel.isNotEmpty)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                child: Text(
                  widget.asset.kuerzel,
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (widget.selected)
            Container(
              color: Colors.black45,
              child: const Icon(Icons.check_circle, color: Colors.white),
            ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// Formatiert Sekunden als "m:ss" (bzw. "h:mm:ss" für Videos ab einer
  /// Stunde Länge), analog zur Anzeige in Apple Fotos/Google Fotos.
  String _formatDuration(double seconds) {
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  Widget _placeholder() => Container(
        color: Colors.grey.shade900,
        child: Icon(
          widget.asset.type == 'VIDEO' ? Icons.videocam_outlined : Icons.image_outlined,
          color: Colors.white24,
        ),
      );
}

/// Für Fälle außerhalb der Tabelle (z.B. Gesichts-Crops), bei denen nur ein
/// absoluter Dateipfad statt eines Assets vorliegt.
class LocalImageTile extends StatelessWidget {
  final File file;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final bool selected;

  const LocalImageTile({
    super.key,
    required this.file,
    this.onTap,
    this.onDoubleTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            file,
            fit: BoxFit.cover,
            // Ein Gesichts-Ausschnitt ist klein, aber es sind viele: Die
            // Gesichtspruefung zeigt hunderte davon nebeneinander.
            cacheWidth: (_ausschnittKante *
                    MediaQuery.devicePixelRatioOf(context))
                .round(),
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey.shade900,
              child: const Icon(Icons.face_outlined, color: Colors.white24),
            ),
          ),
          if (selected)
            Container(
              color: Colors.black45,
              child: const Icon(Icons.check_circle, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
