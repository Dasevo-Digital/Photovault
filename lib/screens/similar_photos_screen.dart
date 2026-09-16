import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../services/clip_service.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/pin_dialogs.dart';
import 'asset_viewer_screen.dart';

/// Zeigt Fotos, die dem übergebenen Ausgangsfoto laut CLIP-Bild-Embedding
/// am ähnlichsten sind (Kosinus-Ähnlichkeit, brute-force über alle
/// gespeicherten Embeddings) – aufgerufen über "Ähnliche Bilder anzeigen"
/// im Kontextmenü der Vollbildansicht. Nutzt dieselbe Rangfolge-Logik wie
/// die KI-Bildsuche und die Duplikatsuche, nur mit einem Bild statt einem
/// Text als Anfrage.
class SimilarPhotosScreen extends StatefulWidget {
  final LibraryState library;
  final AssetData sourceAsset;

  const SimilarPhotosScreen({super.key, required this.library, required this.sourceAsset});

  @override
  State<SimilarPhotosScreen> createState() => _SimilarPhotosScreenState();
}

class _SimilarPhotosScreenState extends State<SimilarPhotosScreen> {
  static const _maxResults = 60;

  late final Future<List<AssetData>> _resultsFuture = _computeSimilar();

  Future<List<AssetData>> _computeSimilar() async {
    final sourceEmbedding = await widget.library.db.embeddingForAsset(widget.sourceAsset.id);
    if (sourceEmbedding == null) return [];
    final embeddings = await widget.library.cachedEmbeddings();
    final ranked = ClipService.rankBySimilarity(sourceEmbedding, embeddings,
        topK: _maxResults + 1);
    final ids = ranked.map((e) => e.key).where((id) => id != widget.sourceAsset.id).take(_maxResults).toList();
    return widget.library.db.assetsByIds(ids);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.library.clipAvailable) {
      return Scaffold(
        appBar: AppBar(title: Text(AppTexte.of(context).aehnlTitel)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              AppTexte.of(context).aehnlClipFehlt,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppTexte.of(context).aehnlTitel)),
      body: FutureBuilder<List<AssetData>>(
        future: _resultsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final results = snapshot.data ?? [];
          if (results.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(
                  AppTexte.of(context).aehnlKeineTreffer,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: results.length,
            itemBuilder: (context, index) {
              final asset = results[index];
              return AssetThumbnailTile(
                asset: Rasterzeile.aus(asset),
                paths: widget.library.paths,
                onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                  builder: (_) => AssetViewerScreen(
                    assets: results,
                    initialIndex: index,
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
                )),
              );
            },
          );
        },
      ),
    );
  }
}
