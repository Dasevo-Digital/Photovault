import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kern/services/storage_paths.dart';

/// Ein Bild aus der Bibliothek, das in einer verbundenen Bibliothek erst
/// vom Server geholt wird, wenn es hier noch fehlt (siehe
/// [StoragePaths.beschaffe]).
///
/// Ohne Server bleibt es bei [FileImage]: Für eine Bibliothek auf diesem
/// Rechner ändert sich nichts, auch nicht der Schlüssel im Bildspeicher.
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
      // Offline oder nicht da: nicht im Bildspeicher behalten, damit der
      // nächste Versuch es noch einmal holt.
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

/// Wie `Image.file(paths.absolute(relativ), …)` – in einer verbundenen
/// Bibliothek mit [BibliotheksBild].
///
/// Reicht `cacheWidth` und `cacheHeight` nur weiter: Die Regeln „nie ohne
/// Deckel“ und „nicht beide Kanten“ gelten an den Aufrufstellen und werden
/// dort geprüft (test/bilddekodierung_test.dart,
/// test/deckende_dekodiermasse_test.dart).
Widget bibliotheksbild(
  StoragePaths paths,
  String relativ, {
  BoxFit? fit,
  double? width,
  double? height,
  int? cacheWidth,
  int? cacheHeight,
  ImageErrorWidgetBuilder? errorBuilder,
}) => paths.beschaffe == null
    ? Image.file(
        paths.absolute(relativ),
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        errorBuilder: errorBuilder,
      )
    : Image(
        image: ResizeImage.resizeIfNeeded(
          cacheWidth,
          cacheHeight,
          BibliotheksBild(paths, relativ),
        ),
        fit: fit,
        width: width,
        height: height,
        errorBuilder: errorBuilder,
      );
