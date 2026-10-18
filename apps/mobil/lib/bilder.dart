import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    this.video = false,
    this.favorit = false,
    this.serie = 0,
    this.bild,
  });

  final StoragePaths paths;
  final String? relativ;

  /// Statt einer Datei der Bibliothek – etwa eine Miniatur aus der
  /// Fotomediathek des Telefons.
  final ImageProvider? bild;
  final bool video;
  final bool favorit;

  /// Steht die Kachel für eine Serie, wie viele Aufnahmen dazugehören –
  /// oben rechts „⧉ 5“, wie im Browser.
  final int serie;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final flaeche = ColoredBox(color: farben.surfaceContainerHighest);
    final r = relativ;
    return LayoutBuilder(
      builder: (context, c) {
        final breite = (c.maxWidth * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(64, 1024);
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
            if (video)
              const Positioned(
                right: 4,
                bottom: 4,
                child: Icon(
                  Icons.play_circle_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            if (favorit)
              const Positioned(
                left: 4,
                bottom: 4,
                child: Icon(Icons.favorite, color: Colors.white, size: 16),
              ),
            if (serie > 1)
              Positioned(
                right: 4,
                top: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    child: Text(
                      '⧉ $serie',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
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
