import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../services/export_service.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/pin_dialogs.dart';
import '../widgets/rasterbedienung.dart';
import '../widgets/selection_action_bar.dart';
import 'asset_viewer_screen.dart';
import 'aufnahmen_waehlen_screen.dart';
import '../services/meldungsdienst.dart';
import '../widgets/stromhalter.dart';

class AlbumDetailScreen extends StatefulWidget {
  final LibraryState library;
  final String albumId;
  final String albumName;

  const AlbumDetailScreen({
    super.key,
    required this.library,
    required this.albumId,
    required this.albumName,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen>
    with Rasterbedienung<AlbumDetailScreen, AssetData> {
  final Set<String> _selected = {};

  /// Siehe [Stromhalter]: sonst eine frische Abfrage bei jedem Neubau, und
  /// die löst hier jeder Pfeiltastendruck und jeder Klick in der
  /// Mehrfachauswahl aus.
  final _albumstrom = Stromhalter<List<AssetData>>();

  /// Siehe [Rasterbedienung]: Beim Tastendruck gibt es weder den Datenstrom
  /// noch die Constraints, beides wird deshalb beim Bauen festgehalten.
  List<AssetData> _geladen = const [];
  int _spalten = 1;

  @override
  Set<String> get auswahl => _selected;

  @override
  AppDatabase get rasterDb => widget.library.db;

  @override
  List<AssetData> get rasterAssets => _geladen;

  @override
  String rasterKennung(AssetData zeile) => zeile.id;

  @override
  ({bool favorit, String? farbe}) rasterMerkmale(AssetData zeile) =>
      (favorit: zeile.isFavorite, farbe: zeile.colorLabel);

  @override
  int get rasterSpalten => _spalten;

  @override
  void rasterOeffne(AssetData asset) {
    final index = _geladen.indexWhere((a) => a.id == asset.id);
    if (index >= 0) _openViewer(_geladen, index);
  }

  /// Siehe [Rasterbedienung.rasterUmschalten]: Der Anker gehoert dazu.
  void _toggle(String id) => rasterUmschalten(id);

  void _openViewer(List<AssetData> assets, int index) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: assets,
        initialIndex: index,
        paths: widget.library.paths,
        db: widget.library.db,
        library: widget.library,
        onToggleFavorite: (a) => widget.library.db.setFavorite(a.id, !a.isFavorite),
        onDelete: (a) async {
          await widget.library.db.removeAssetFromAlbum(widget.albumId, a.id);
          await widget.library.db.moveToTrash([a.id]);
        },
        onLock: (a) async {
          if (await ensureVaultUnlocked(context, widget.library)) {
            await widget.library.lockAsset(a);
          }
        },
      ),
    ));
  }

  /// Entfernt die Auswahl aus dem Album UND verschiebt sie in den
  /// Papierkorb – dieselbe Doppelbedeutung von "Löschen" wie beim
  /// Einzelfoto in der Vollbildansicht (siehe [_openViewer]'s `onDelete`).
  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    final confirmed = await confirmDialog(
      context,
      AppTexte.of(context).albumFotosLoeschenTitel(ids.length),
      AppTexte.of(context).albumFotosLoeschenText,
    );
    if (!confirmed) return;
    for (final id in ids) {
      await widget.library.db.removeAssetFromAlbum(widget.albumId, id);
    }
    await widget.library.db.moveToTrash(ids);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _exportAlbum(BuildContext context, List<AssetData> assets) async {
    final destination = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AppTexte.of(context).albumZielordner(widget.albumName),
    );
    if (destination == null || !context.mounted) return;

    final exporter = ExportService(widget.library.paths, library: widget.library);
    var done = 0;
    void Function(void Function())? setDialogState;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(builder: (context, setState) {
        setDialogState = setState;
        return AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 16),
              Expanded(child: Text(AppTexte.of(context).auswExportiereLaeuft(done, assets.length))),
            ],
          ),
        );
      }),
    );

    var exported = 0;
    for (final asset in assets) {
      try {
        await exporter.exportAsset(asset, destination);
        exported++;
      } catch (_) {
        // Einzelne fehlgeschlagene Datei überspringen, Rest weiter exportieren.
      }
      done++;
      setDialogState?.call(() {});
    }

    if (context.mounted) {
      Navigator.of(context).pop(); // Ladeanzeige schließen
      melde.erfolg(AppTexte.of(context).auswExportFertig(exported, assets.length, destination));
    }
  }

  /// Waehlt Aufnahmen aus der Bibliothek und legt sie ins Album.
  ///
  /// Der Waehler kennt keinen Zeitraum – ein Album ist eine Sammlung und
  /// keine Zeitspanne, deshalb steht er von Anfang an auf der ganzen
  /// Bibliothek.
  Future<void> _fotosHinzufuegen(List<AssetData> vorhanden) async {
    final vorher = {for (final a in vorhanden) a.id};
    final gewaehlt = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => AufnahmenWaehlenScreen(
          library: widget.library,
          titel: AppTexte.of(context).albumFotosWaehlenTitel(widget.albumName),
          vorhanden: vorher,
        ),
      ),
    );
    if (gewaehlt == null || !mounted) return;
    final dazu = gewaehlt.difference(vorher).toList();
    final weg = vorher.difference(gewaehlt);
    if (dazu.isNotEmpty) {
      await widget.library.db.addAssetsToAlbum(widget.albumId, dazu);
    }
    // Abwaehlen zaehlt auch: Der Waehler zeigt das Vorhandene angehakt,
    // und ein entferntes Haekchen ist eine Ansage.
    for (final id in weg) {
      await widget.library.db.removeAssetFromAlbum(widget.albumId, id);
    }
  }

  Future<void> _titelbildSetzen(String assetId) async {
    await widget.library.db.setzeAlbumTitelbild(widget.albumId, assetId);
    if (!mounted) return;
    melde.hinweis(AppTexte.of(context).albumTitelbildGesetzt);
    setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AssetData>>(
      stream: _albumstrom.hole(widget.albumId,
          () => widget.library.db.watchAlbumAssets(widget.albumId)),
      builder: (context, snapshot) {
        final assets = snapshot.data ?? [];
        _geladen = assets;
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.albumName),
            actions: [
              // Aus dem Album heraus, nicht nur von aussen ueber "Zu
              // Album hinzufuegen": Wer ein Album offen hat und es
              // fuellen will, sucht den Knopf hier.
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                tooltip: AppTexte.of(context).albumFotosHinzufuegen,
                onPressed: () => _fotosHinzufuegen(assets),
              ),
              if (_selected.length == 1)
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  tooltip: AppTexte.of(context).albumTitelbildSetzen,
                  onPressed: () => _titelbildSetzen(_selected.first),
                ),
              if (assets.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.ios_share),
                  tooltip: AppTexte.of(context).albumExportieren,
                  onPressed: () => _exportAlbum(context, assets),
                ),
            ],
          ),
          body: assets.isEmpty
              ? Center(child: Text(AppTexte.of(context).albumLeer))
              : mitTastatur(
                  kind: Stack(
                  children: [
                    LayoutBuilder(builder: (context, constraints) {
                      _spalten = flachesRasterSpalten(constraints.maxWidth,
                          seitenpolster: AppSpacing.md * 2);
                      return GridView.builder(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                        itemCount: assets.length,
                        itemBuilder: (context, index) {
                          final asset = assets[index];
                          final kachel = AssetThumbnailTile(
                            asset: Rasterzeile.aus(asset),
                            paths: widget.library.paths,
                            selected: _selected.contains(asset.id),
                            onLongPress: () => _toggle(asset.id),
                            onTap: () => rasterKlick(asset),
                          );
                          return asset.id == aktiveKachel
                              ? AktiveKachelRahmen(child: kachel)
                              : kachel;
                        },
                      );
                    }),
                    if (_selected.isNotEmpty)
                      SelectionActionBar(
                        count: _selected.length,
                        onClear: () => setState(_selected.clear),
                        onCompare: vergleichsAktion(context, widget.library, _selected.toList()),

                        onPasteDevelop: widget.library.hatKopierteEntwicklung

                            ? () async {

                                await runBatchPasteDevelop(context, widget.library, _selected.toList());

                                if (mounted) setState(_selected.clear);

                              }

                            : null,
                        onApplyPreset: () =>
                            runBatchApplyPreset(context, widget.library, _selected.toList()),
                        onFavorite: () async {
                          await runBatchFavorite(widget.library, _selected.toList());
                          if (mounted) setState(_selected.clear);
                        },
                        onAddToAlbum: () async {
                          await runBatchAddToAlbumDialog(context, widget.library, _selected.toList());
                          if (mounted) setState(_selected.clear);
                        },
                        onTag: () async {
                          await runBatchTagDialog(context, widget.library, _selected.toList());
                          if (mounted) setState(_selected.clear);
                        },
                        onSetRating: () async {
                          await runBatchSetRating(context, widget.library, _selected.toList());
                          if (mounted) setState(_selected.clear);
                        },
                        onSetColorLabel: () async {
                          await runBatchSetColorLabel(context, widget.library, _selected.toList());
                          if (mounted) setState(_selected.clear);
                        },
                        onEditMetadata: () async {
                          await runBatchEditMetadataDialog(context, widget.library, _selected.toList());
                          if (mounted) setState(_selected.clear);
                        },
                        onExport: () async {
                          final selectedAssets = assets.where((a) => _selected.contains(a.id)).toList();
                          await runBatchExport(context, widget.library, selectedAssets);
                          if (mounted) setState(_selected.clear);
                        },
                        onDelete: _deleteSelected,
                      ),
                  ],
                )),
        );
      },
    );
  }
}
