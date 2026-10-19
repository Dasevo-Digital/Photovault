import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/storage_paths.dart';

/// Ein Bild der Bibliothek, das erst vom Server kommt, wenn es hier noch
/// fehlt (siehe `StoragePaths.bereit`), und danach hier liegen bleibt.
class BibliotheksBild extends ImageProvider<BibliotheksBild> {
  const BibliotheksBild(this.paths, this.relativ);

  final StoragePaths paths;
  final String relativ;

  @override
  Future<BibliotheksBild> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<BibliotheksBild>(this);

  @override
  ImageStreamCompleter loadImage(
    BibliotheksBild key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _lade(key, decode),
    scale: 1,
    debugLabel: relativ,
  );

  Future<ui.Codec> _lade(
    BibliotheksBild key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final datei = await paths.bereit(relativ);
      return await decode(await ui.ImmutableBuffer.fromFilePath(datei.path));
    } catch (_) {
      // Offline: nicht im Bildspeicher behalten, der nächste Blick holt es.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BibliotheksBild &&
      other.relativ == relativ &&
      identical(other.paths, paths);

  @override
  int get hashCode => Object.hash(relativ, identityHashCode(paths));
}

/// Eine Miniatur im Raster: auf ihre Grösse dekodiert, mit ruhiger Fläche,
/// solange sie lädt oder fehlt.
class Miniatur extends StatelessWidget {
  const Miniatur({
    super.key,
    required this.paths,
    required this.relativ,
    this.zeile,
    this.format = true,
    this.herz = true,
    this.bild,
  });

  final StoragePaths paths;
  final String? relativ;

  /// Statt einer Datei der Bibliothek – etwa eine Miniatur aus der
  /// Fotomediathek des Telefons.
  final ImageProvider? bild;

  /// Die Aufnahme hinter der Kachel: Mit ihr trägt die Kachel dieselben
  /// Marken wie am Rechner (asset_thumbnail_tile.dart) und im Browser
  /// (web/app.js, marken) – Favorit oben links, Ort unten links,
  /// Videolänge oder Live unten rechts, Serie oder Format oben rechts.
  final Rasterzeile? zeile;

  /// Ob oben rechts Format oder Serie stehen darf – dort steht bei noch
  /// nicht gesicherten Fotos schon die Wolke.
  final bool format;

  /// Ob das Herz oben links stehen darf – beim Wählen steht dort der Kreis.
  final bool herz;

  static const _schatten = [Shadow(color: Colors.black54, blurRadius: 4)];

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final flaeche = ColoredBox(color: farben.surfaceContainerHighest);
    final r = relativ;
    final z = zeile;
    return LayoutBuilder(
      builder: (context, c) {
        final breite = (c.maxWidth * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(64, 1024);
        // Auf kleinen Kacheln nur das Nötigste – wie im Browser.
        final klein = c.maxWidth < 72;
        final serie = z != null && z.isStackCover ? (z.stackSize ?? 0) : 0;
        final kuerzel = z?.kuerzel ?? '';
        return Stack(
          fit: StackFit.expand,
          children: [
            if (bild == null && r == null)
              flaeche
            else
              Image(
                image: ResizeImage(
                  bild ?? BibliotheksBild(paths, r!),
                  width: breite,
                ),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => flaeche,
                frameBuilder: (context, kind, frame, sofort) =>
                    frame == null && !sofort ? flaeche : kind,
              ),
            if (z != null && z.type == 'VIDEO')
              Positioned(
                right: 4,
                bottom: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (z.durationSeconds != null && !klein) ...[
                      Text(
                        videodauer(z.durationSeconds!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          shadows: _schatten,
                        ),
                      ),
                      const SizedBox(width: 3),
                    ],
                    const Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                      size: 19,
                      shadows: _schatten,
                    ),
                  ],
                ),
              )
            else if (z != null && z.linkedAssetId != null)
              const Positioned(
                right: 4,
                bottom: 4,
                child: Icon(
                  Icons.motion_photos_on,
                  color: Colors.white,
                  size: 18,
                  shadows: _schatten,
                ),
              ),
            if (herz && z != null && z.isFavorite)
              const Positioned(
                left: 4,
                top: 4,
                child: Icon(
                  Icons.favorite,
                  color: Color(0xFFFF5A5F),
                  size: 16,
                  shadows: _schatten,
                ),
              ),
            if (z != null && z.verortet && !klein)
              const Positioned(
                left: 3,
                bottom: 4,
                child: Icon(
                  Icons.location_on,
                  color: Colors.white,
                  size: 15,
                  shadows: _schatten,
                ),
              ),
            if (format && !klein && (serie > 1 || kuerzel.isNotEmpty))
              Positioned(
                right: 4,
                top: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    child: serie > 1
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.filter_none,
                                color: Colors.white,
                                size: 11,
                              ),
                              const SizedBox(width: 3),
                              Text('$serie', style: _schildschrift),
                            ],
                          )
                        : Text(kuerzel, style: _schildschrift),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static const _schildschrift = TextStyle(
    color: Colors.white,
    fontSize: 10,
    fontWeight: FontWeight.w600,
  );
}

/// „m:ss“, ab einer Stunde „h:mm:ss“ – wie am Rechner.
String videodauer(double sekunden) {
  final g = sekunden.round();
  final h = g ~/ 3600;
  final m = (g % 3600) ~/ 60;
  final s = (g % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Das Gesicht einer Person – oder, ohne Gesichtsbild, ihr Anfangsbuchstabe
/// auf einer Fläche, statt eines leeren grauen Kreises.
class Personenbild extends StatelessWidget {
  const Personenbild({
    super.key,
    required this.paths,
    required this.name,
    required this.relativ,
  });

  final StoragePaths paths;
  final String name;
  final String? relativ;

  @override
  Widget build(BuildContext context) {
    final r = relativ;
    if (r != null) {
      return ClipOval(
        child: Miniatur(paths: paths, relativ: r),
      );
    }
    final farben = Theme.of(context).colorScheme;
    final anfang = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: farben.secondaryContainer,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          anfang,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: farben.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
