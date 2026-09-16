import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/pin_dialogs.dart';
import 'asset_viewer_screen.dart';

/// Alle Fotos einer Familie – jedes Bild, auf dem mindestens eine Person
/// aus dem Verwandtschaftsnetz erkannt wurde.
///
/// Eine eigene, einfache Rasteransicht statt einer weiteren Betriebsart
/// der Zeitleiste: Die Liste ist bereits fertig zusammengestellt und
/// ändert sich nicht mehr – sie braucht kein wachsendes Ladefenster, keine
/// Mehrfachauswahl und keinen Zeitstrahl.
class FamilienfotosScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titel)),
      body: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: assets.length,
        itemBuilder: (context, index) => AssetThumbnailTile(
          asset: Rasterzeile.aus(assets[index]),
          paths: library.paths,
          onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
            builder: (_) => AssetViewerScreen(
              assets: assets,
              initialIndex: index,
              paths: library.paths,
              db: library.db,
              library: library,
              onToggleFavorite: (a) => library.db.setFavorite(a.id, !a.isFavorite),
              onDelete: (a) => library.db.moveToTrash([a.id]),
              onLock: (a) async {
                if (await ensureVaultUnlocked(context, library)) {
                  await library.lockAsset(a);
                }
              },
            ),
          )),
        ),
      ),
    );
  }
}
