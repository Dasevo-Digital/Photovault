import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../widgets/namens_dialog.dart' show MitTextsteuerung;
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../db/rasterzeile.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../services/search_filters.dart';
import '../widgets/selection_action_bar.dart' show confirmDialog;
import 'album_detail_screen.dart';
import 'search_screen.dart';

class AlbumsScreen extends StatelessWidget {
  final LibraryState library;
  const AlbumsScreen({super.key, required this.library});

  Future<void> _createAlbum(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      // Die Steuerung gehört dem Fenster, nicht diesem Aufruf – siehe
      // [MitTextsteuerung].
      builder: (context) => MitTextsteuerung(
          builder: (context, ctrl) => AlertDialog(
        title: Text(AppTexte.of(context).albumNeu),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: AppTexte.of(context).albumName),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: Text(AppTexte.of(context).allgErstellen)),
                ],
              )),
    );
    if (name != null && name.isNotEmpty) {
      await library.db.createAlbum(AlbumsCompanion.insert(
        id: const Uuid().v4(),
        name: name,
        createdAt: DateTime.now(),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createAlbum(context),
        icon: const Icon(Icons.add),
        label: Text(AppTexte.of(context).albumNeu),
      ),
      body: StreamBuilder<List<AlbumData>>(
        stream: library.db.watchAlbums(),
        builder: (context, alben) {
          return StreamBuilder<List<SavedSearchData>>(
            stream: library.db.watchSavedSearches(),
            builder: (context, gespeicherte) {
              final albums = alben.data ?? const <AlbumData>[];
              final klug = gespeicherte.data ?? const <SavedSearchData>[];
              if (albums.isEmpty && klug.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppTexte.of(context).albenLeer),
                        const SizedBox(height: AppSpacing.md),
                        // Auch hier: sagen, wo das Fehlende herkommt.
                        Text(AppTexte.of(context).albenIntelligentWoher,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                );
              }
              return CustomScrollView(
                slivers: [
                  // Die intelligenten Alben zuerst: Sie sind die kleinere
                  // Gruppe und wuerden unter zwanzig gewoehnlichen Alben
                  // nicht mehr gefunden. Ueberschriften nur, wenn es
                  // wirklich zwei Gruppen gibt - eine einzelne
                  // Ueberschrift ueber allem sagt nichts.
                  if (klug.isNotEmpty) ...[
                    if (albums.isNotEmpty)
                      _Abschnitt(AppTexte.of(context).albenIntelligente),
                    _Kachelfeld(
                      anzahl: klug.length,
                      bauen: (context, i) => _IntelligentesAlbum(
                        eintrag: klug[i],
                        library: library,
                      ),
                    ),
                  ],
                  if (albums.isNotEmpty) ...[
                    if (klug.isNotEmpty)
                      _Abschnitt(AppTexte.of(context).albenGewoehnliche),
                    _Kachelfeld(
                      anzahl: albums.length,
                      bauen: (context, i) => _Albumkachel(
                        album: albums[i],
                        library: library,
                        onTippen: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => AlbumDetailScreen(
                              library: library,
                              albumId: albums[i].id,
                              albumName: albums[i].name),
                        )),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Eine Abschnittsueberschrift zwischen zwei Kachelfeldern.
class _Abschnitt extends StatelessWidget {
  const _Abschnitt(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
      );
}

/// Das Kachelraster – einmal fuer beide Albumarten, damit sie gleich
/// aussehen und gleich gross sind.
class _Kachelfeld extends StatelessWidget {
  const _Kachelfeld({required this.anzahl, required this.bauen});
  final int anzahl;
  final Widget Function(BuildContext, int) bauen;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.1,
          ),
          delegate: SliverChildBuilderDelegate(bauen, childCount: anzahl),
        ),
      );
}

/// Ein intelligentes Album – eine gespeicherte Suche als Kachel.
///
/// **Warum das eine Kachel im Albenreiter ist.** Gespeicherte Suchen gab
/// es laengst, sichtbar aber nur als Chip-Reihe UNTER dem Suchfeld –
/// also erst, wenn man ohnehin schon in der Suche stand. Wer im
/// Albenreiter nach einem intelligenten Album sah, fand nichts, und
/// nichts sagte ihm, dass es so etwas gibt.
///
/// **Und warum das Antippen in die Suche fuehrt statt in eine eigene
/// Ansicht.** Ein intelligentes Album IST die Suche; seine Treffer
/// entstehen jedes Mal neu. Die Trefferansicht gibt es dort schon,
/// samt Mehrfachauswahl, Reihenfolge und allen Sammelaktionen – ein
/// vierter Nachbau (Zeitleiste, Album, Suche) waere ein vierter Ort, an
/// dem dieselben Fehler entstehen. Der Nebeneffekt ist der eigentliche
/// Gewinn: Man kann darin weitersuchen.
class _IntelligentesAlbum extends StatelessWidget {
  const _IntelligentesAlbum({required this.eintrag, required this.library});

  final SavedSearchData eintrag;
  final LibraryState library;

  Future<void> _loeschen(BuildContext context) async {
    final t = AppTexte.of(context);
    if (!await confirmDialog(context, t.albumIntelligentLoeschen,
        t.albumIntelligentLoeschenFrage(eintrag.name))) {
      return;
    }
    await library.db.deleteSavedSearch(eintrag.id);
  }

  void _oeffnen(BuildContext context) {
    final SearchFilters filter =
        library.db.decodeSavedSearchFilters(eintrag.filtersJson);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchScreen(
          library: library, startFilter: filter, titel: eintrag.name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _oeffnen(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: farben.surfaceContainerHighest,
                child: Stack(
                  children: [
                    Center(
                      child: Icon(Icons.auto_awesome_outlined,
                          size: 40, color: farben.primary),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: AppTexte.of(context).albumIntelligentLoeschen,
                        onPressed: () => _loeschen(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text(eintrag.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eine Albumkachel mit Titelbild.
///
/// Bis hierher stand in jeder Kachel dasselbe Symbol: Zwanzig Alben
/// sahen aus wie zwanzigmal dasselbe. Die Spalte für das Titelbild gab
/// es seit jeher, gelesen hat sie niemand.
class _Albumkachel extends StatefulWidget {
  final AlbumData album;
  final LibraryState library;
  final VoidCallback onTippen;

  const _Albumkachel({
    required this.album,
    required this.library,
    required this.onTippen,
  });

  @override
  State<_Albumkachel> createState() => _AlbumkachelState();
}

class _AlbumkachelState extends State<_Albumkachel> {
  /// Einmal geholt und festgehalten: Der Strom der Alben baut die Liste
  /// bei jeder Änderung neu, und ein Future im `build` fragte dann jedes
  /// Mal von vorn.
  late Future<AssetData?> _titelbild =
      widget.library.db.albumTitelbild(widget.album);

  @override
  void didUpdateWidget(_Albumkachel alt) {
    super.didUpdateWidget(alt);
    // Ein neu gesetztes Titelbild soll ankommen, ohne dass man den
    // Bildschirm verlässt.
    if (alt.album.coverAssetId != widget.album.coverAssetId ||
        alt.album.id != widget.album.id) {
      _titelbild = widget.library.db.albumTitelbild(widget.album);
    }
  }

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTippen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FutureBuilder<AssetData?>(
                future: _titelbild,
                builder: (context, schnappschuss) {
                  final bild = schnappschuss.data;
                  if (bild == null) {
                    return ColoredBox(
                      color: farben.surfaceContainerHighest,
                      child: Icon(Icons.photo_album_outlined,
                          size: 40, color: farben.onSurfaceVariant),
                    );
                  }
                  return AssetThumbnailTile(
                    asset: Rasterzeile.aus(bild),
                    paths: widget.library.paths,
                    onTap: widget.onTippen,
                  );
                },
              ),
            ),
            // Rand und eine Grenze für den Namen: Ohne beides stand ein
            // langer Albumname bis an die Kachelkante und lief bei grosser
            // Systemschrift unten heraus (gemessen 7,8 Punkte bei
            // 1,6-facher Schrift).
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text(widget.album.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ],
        ),
      ),
    );
  }
}
