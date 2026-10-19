import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'raster.dart';
import 'diashow.dart';
import 'freigaben.dart';

/// Die Alben der Bibliothek, jedes mit seinem Titelbild.
class Alben extends StatelessWidget {
  const Alben({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AlbumData>>(
    stream: sitzung.db.watchAlbums(),
    builder: (context, snap) {
      final alben = snap.data;
      if (alben == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (alben.isEmpty) {
        return Center(child: Text(AppTexte.of(context).albenLeer));
      }
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: alben.length,
        itemBuilder: (context, i) =>
            _AlbumKachel(sitzung: sitzung, album: alben[i]),
      );
    },
  );
}

class _AlbumKachel extends StatelessWidget {
  const _AlbumKachel({required this.sitzung, required this.album});

  final Sitzung sitzung;
  final AlbumData album;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumSeite(sitzung: sitzung, album: album),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FutureBuilder<AssetData?>(
              future: sitzung.db.albumTitelbild(album),
              builder: (context, snap) => Miniatur(
                paths: sitzung.paths,
                relativ: snap.data?.thumbnailRelativePath,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

/// Ein Album als Raster.
class AlbumSeite extends StatelessWidget {
  const AlbumSeite({super.key, required this.sitzung, required this.album});

  final Sitzung sitzung;
  final AlbumData album;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(album.name),
      actions: [
        IconButton(
          tooltip: AppTexte.of(context).diashow,
          icon: const Icon(Icons.slideshow_outlined),
          onPressed: () async {
            final a = await sitzung.db.watchAlbumAssets(album.id).first;
            if (!context.mounted) return;
            await zeigeDiashow(context, sitzung, [
              for (final x in a)
                if (!x.isLocked && !x.isTrashed) Rasterzeile.aus(x),
            ]);
          },
        ),
        IconButton(
          tooltip: AppTexte.of(context).albumAlsLink,
          icon: const Icon(Icons.link_rounded),
          onPressed: () => alsLinkTeilen(
            context,
            sitzung.abgleich?.verbindung,
            albumId: album.id,
            titel: album.name,
          ),
        ),
      ],
    ),
    body: StreamBuilder<List<AssetData>>(
      stream: sitzung.db.watchAlbumAssets(album.id),
      builder: (context, snap) {
        final a = snap.data;
        if (a == null) return const Center(child: CircularProgressIndicator());
        return AufnahmenRaster(
          sitzung: sitzung,
          zeilen: [for (final x in a) Rasterzeile.aus(x)],
        );
      },
    ),
  );
}
