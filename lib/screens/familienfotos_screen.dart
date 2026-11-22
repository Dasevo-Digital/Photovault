import 'package:flutter/material.dart';

import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/pin_dialogs.dart';
import 'asset_viewer_screen.dart';

/// Alle Fotos einer Familie – jedes Bild, auf dem mindestens eine Person
/// aus dem Verwandtschaftsnetz erkannt wurde.
///
/// Eine eigene, einfache Rasteransicht statt einer weiteren Betriebsart
/// der Zeitleiste: Die Liste ist bereits fertig zusammengestellt – sie
/// braucht kein wachsendes Ladefenster, keine Mehrfachauswahl und keinen
/// Zeitstrahl.
///
/// Nach dem Vollbild wird sie aber nachgeführt: Dort lässt sich ein Foto
/// löschen, sperren oder als Favorit markieren. Ohne das stand es weiter
/// im Raster, ein gesperrtes als kaputte Kachel, und ein erneutes Öffnen
/// zeigte ein Foto aus dem Papierkorb samt seinen Aktionen.
class FamilienfotosScreen extends StatefulWidget {
  final LibraryState library;
  final String titel;
  final List<AssetData> assets;

  const FamilienfotosScreen({
    super.key,
    required this.library,
    required this.titel,
    required this.assets,
  });

  @override
  State<FamilienfotosScreen> createState() => _FamilienfotosScreenState();
}

class _FamilienfotosScreenState extends State<FamilienfotosScreen> {
  late List<AssetData> _assets = widget.assets;

  @override
  void didUpdateWidget(covariant FamilienfotosScreen alt) {
    super.didUpdateWidget(alt);
    if (!identical(alt.assets, widget.assets)) _assets = widget.assets;
  }

  /// Ohne Gelöschte und Gesperrte, mit dem frischen Stand der übrigen.
  Future<void> _auffrischen() async {
    final db = widget.library.db;
    final vorher = _assets;
    final frisch = await db.assetsByIds(
      await db.nochSuchbar([for (final a in vorher) a.id]),
    );
    if (mounted && identical(vorher, _assets)) {
      setState(() => _assets = frisch);
    }
  }

  Future<void> _oeffne(int index) async {
    final library = widget.library;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => AssetViewerScreen(
          assets: _assets,
          initialIndex: index,
          paths: library.paths,
          db: library.db,
          library: library,
          onToggleFavorite: (a) =>
              library.db.fuehreAus(FavoritSetzen([a.id], !a.isFavorite)),
          onDelete: (a) => library.db.fuehreAus(InDenPapierkorb([a.id])),
          onLock: (a) async {
            if (await ensureVaultUnlocked(context, library)) {
              await library.lockAsset(a);
            }
          },
        ),
      ),
    );
    await _auffrischen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titel)),
      body: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: _assets.length,
        itemBuilder: (context, index) => AssetThumbnailTile(
          key: ValueKey(_assets[index].id),
          asset: Rasterzeile.aus(_assets[index]),
          paths: widget.library.paths,
          onTap: () => _oeffne(index),
        ),
      ),
    );
  }
}
