import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../db/database.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import 'asset_viewer_screen.dart';

/// Zeigt alle Fotos/Videos im gesperrten Ordner (Tab "Fotos") sowie einen
/// eigenen, PIN-geschützten Papierkorb dafür (Tab "Papierkorb") – daraus
/// gelöschte, gesperrte Fotos landen NICHT im normalen, ungeschützten
/// Papierkorb (siehe AppDatabase.watchTrash), sonst könnte jeder ohne PIN
/// ein gesperrtes Foto wiederherstellen oder sogar endgültig löschen.
///
/// Der Zugriff auf diesen Screen selbst wird bereits vorher über die
/// PIN-Abfrage in [SettingsScreen] abgesichert – hier findet keine erneute
/// Prüfung mehr statt, der Master-Key gilt für die laufende App-Sitzung
/// (siehe LibraryState.vaultUnlockedThisSession). Thumbnails und die
/// Vollbildansicht werden hier on-demand entschlüsselt (die Originaldateien
/// auf der Platte bleiben dabei verschlüsselt).
/// Kantenlänge einer Kachel – zugleich die Dekodiergröße der
/// entschlüsselten Vorschau (siehe `cacheWidth` unten).
const double _kachelBreite = 160;

class LockedFolderScreen extends StatefulWidget {
  final LibraryState library;
  const LockedFolderScreen({super.key, required this.library});

  @override
  State<LockedFolderScreen> createState() => _LockedFolderScreenState();
}

class _LockedFolderScreenState extends State<LockedFolderScreen> {
  LibraryState get library => widget.library;

  @override
  void initState() {
    super.initState();
    library.addListener(_aufTresorwechsel);
  }

  /// Fällt der Tresor zu, während dieser Bildschirm offen ist, geht er mit
  /// zu.
  ///
  /// Seit der Wächter beim Verbergen des Fensters sperrt (siehe
  /// `Tresorwaechter`), kann das jederzeit passieren. Ohne diesen Weg
  /// bliebe das Gitter stehen und scheiterte an jeder einzelnen Kachel:
  /// [LibraryState.decryptForViewing] wirft ohne Schlüssel. Ein Bildschirm
  /// voller Fehlerplätze statt einer klaren Rückkehr.
  void _aufTresorwechsel() {
    if (!mounted || library.vaultUnlockedThisSession) return;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    library.removeListener(_aufTresorwechsel);
    // Entschlüsselte Zwischenkopien (Thumbnails/Vollbild) sollen nicht
    // länger als nötig als Klartext im OS-Temp-Verzeichnis liegen bleiben.
    library.clearDecryptCache();
    super.dispose();
  }

  Future<void> _permanentlyDelete(AssetData asset) async {
    await library.deleteAssetFilesFromDisk(asset);
    await library.db.deleteAssetRows([asset.id]);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppTexte.of(context).einstGesperrterOrdner),
          bottom: TabBar(tabs: [
            Tab(text: AppTexte.of(context).gesperrtTabFotos),
            Tab(text: AppTexte.of(context).gesperrtTabPapierkorb),
          ]),
        ),
        body: TabBarView(
          children: [
            _LockedAssetsGrid(library: library),
            _LockedTrashGrid(library: library, onPermanentlyDelete: _permanentlyDelete),
          ],
        ),
      ),
    );
  }
}

class _LockedAssetsGrid extends StatelessWidget {
  final LibraryState library;
  const _LockedAssetsGrid({required this.library});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AssetData>>(
      stream: library.db.watchLockedAssets(),
      builder: (context, snapshot) {
        final assets = snapshot.data ?? [];
        if (assets.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                AppTexte.of(context).gesperrtLeer,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _kachelBreite,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: assets.length,
          itemBuilder: (context, index) {
            final asset = assets[index];
            return Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                      builder: (_) => AssetViewerScreen(
                        assets: assets,
                        initialIndex: index,
                        paths: library.paths,
                        db: library.db,
                        library: library,
                        onToggleFavorite: (a) => library.db.setFavorite(a.id, !a.isFavorite),
                        onDelete: (a) => library.db.moveToTrash([a.id]),
                      ),
                    )),
                    child: _DecryptedThumbnail(asset: asset, library: library),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.lock_open, color: Colors.white, size: 18),
                      tooltip: AppTexte.of(context).gesperrtEntfernen,
                      onPressed: () => library.unlockAsset(asset),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _LockedTrashGrid extends StatelessWidget {
  final LibraryState library;
  final Future<void> Function(AssetData asset) onPermanentlyDelete;
  const _LockedTrashGrid({required this.library, required this.onPermanentlyDelete});

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppTexte.of(context).gesperrtEndgueltigTitel),
        content: Text(
          AppTexte.of(context).gesperrtEndgueltigText,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppTexte.of(context).bestaetigEndgueltigLoeschen),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AssetData>>(
      stream: library.db.watchLockedTrash(),
      builder: (context, snapshot) {
        final assets = snapshot.data ?? [];
        if (assets.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                AppTexte.of(context).gesperrtPapierkorbLeer,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _kachelBreite,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: assets.length,
          itemBuilder: (context, index) {
            final asset = assets[index];
            return Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                      builder: (_) => AssetViewerScreen(
                        assets: assets,
                        initialIndex: index,
                        paths: library.paths,
                        db: library.db,
                        library: library,
                      ),
                    )),
                    child: _DecryptedThumbnail(asset: asset, library: library),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.delete_forever_outlined, color: Colors.white, size: 18),
                      tooltip: AppTexte.of(context).bestaetigEndgueltigLoeschen,
                      onPressed: () async {
                        final confirm = await _confirmDelete(context);
                        if (confirm == true) await onPermanentlyDelete(asset);
                      },
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  top: 4,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.restore_from_trash_outlined, color: Colors.white, size: 18),
                      tooltip: AppTexte.of(context).gesperrtWiederherstellen,
                      onPressed: () => library.ausPapierkorbHolen([asset.id]),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Entschlüsselt das Thumbnail eines gesperrten Assets on-demand (nur
/// einmal pro Sitzung, [LibraryState.decryptForViewing] cacht danach).
class _DecryptedThumbnail extends StatefulWidget {
  final AssetData asset;
  final LibraryState library;
  const _DecryptedThumbnail({required this.asset, required this.library});

  @override
  State<_DecryptedThumbnail> createState() => _DecryptedThumbnailState();
}

class _DecryptedThumbnailState extends State<_DecryptedThumbnail> {
  // Einmalig entschlüsselt statt inline in build(): watchLockedAssets()/
  // watchLockedTrash() lösen bei JEDER Änderung an der assets-Tabelle neu
  // aus (drift invalidiert reaktive Streams pro Tabelle, nicht pro Zeile) –
  // ohne Hoisting würde das komplette sichtbare Raster bei jeder noch so
  // unabhängigen DB-Schreibaktion erneut entschlüsselt.
  Future<File>? _decryptedFuture;

  @override
  void initState() {
    super.initState();
    final thumbPath = widget.asset.thumbnailRelativePath;
    if (thumbPath != null) _decryptedFuture = widget.library.decryptForViewing(thumbPath);
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final thumbPath = asset.thumbnailRelativePath;
    if (thumbPath == null) {
      return Container(
        color: Colors.grey.shade900,
        child: Icon(
          asset.type == 'VIDEO' ? Icons.videocam_outlined : Icons.image_outlined,
          color: Colors.white24,
        ),
      );
    }
    return FutureBuilder<File>(
      future: _decryptedFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            color: Colors.grey.shade900,
            child: const Center(
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        return Image.file(
          snapshot.data!,
          fit: BoxFit.cover,
          // Wie im übrigen Raster auf Kachelgröße dekodieren statt auf die
          // volle Vorschaugröße (Prüfrunde 8). Hier zählt es doppelt: Die
          // Datei kommt frisch aus der Entschlüsselung, jedes gesparte
          // Pixel ist eines weniger im Speicher.
          cacheWidth:
              (_kachelBreite * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey.shade900,
            child: const Icon(Icons.broken_image_outlined, color: Colors.white24),
          ),
        );
      },
    );
  }
}
