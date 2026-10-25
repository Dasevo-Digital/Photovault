import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/intelligente_alben.dart';

import '../bilder.dart';
import '../einfuegbares_menue.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'raster.dart';
import 'diashow.dart';
import 'freigaben.dart';

/// Die Alben der Bibliothek, jedes mit seinem Titelbild – darunter die
/// intelligenten Alben, die gemerkten Suchen (#187).
class Alben extends StatelessWidget {
  const Alben({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AlbumData>>(
    stream: sitzung.db.watchAlbums(),
    builder: (context, snap) => StreamBuilder<List<SavedSearchData>>(
      stream: sitzung.db.watchSavedSearches(),
      builder: (context, klug) {
        final t = AppTexte.of(context);
        final alben = snap.data;
        final suchen = klug.data ?? const <SavedSearchData>[];
        if (alben == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (alben.isEmpty && suchen.isEmpty) {
          return Center(child: Text(t.albenLeer));
        }
        const raster = SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
        );
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid.builder(
                gridDelegate: raster,
                itemCount: alben.length,
                itemBuilder: (context, i) =>
                    _AlbumKachel(sitzung: sitzung, album: alben[i]),
              ),
            ),
            if (suchen.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    t.albenIntelligent,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid.builder(
                  gridDelegate: raster,
                  itemCount: suchen.length,
                  itemBuilder: (context, i) =>
                      _KlugeKachel(sitzung: sitzung, suche: suchen[i]),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

/// Fragt nach dem Namen eines intelligenten Albums; `null` heisst
/// abgebrochen.
Future<String?> frageAlbumname(BuildContext context, {String vorgabe = ''}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _Namensfrage(vorgabe: vorgabe),
    );

/// Eigenes Widget, damit das Feld erst mit dem Dialog verschwindet: Gäbe
/// der Aufrufer es frei, sobald die Antwort da ist, liefe die
/// Schliessbewegung noch auf einem freigegebenen Feld.
class _Namensfrage extends StatefulWidget {
  const _Namensfrage({required this.vorgabe});

  final String vorgabe;

  @override
  State<_Namensfrage> createState() => _NamensfrageState();
}

class _NamensfrageState extends State<_Namensfrage> {
  late final _feld = TextEditingController(text: widget.vorgabe);

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  void _fertig() {
    final name = _feld.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(t.sucheAlsAlbum),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.albenIntelligentHinweis),
          const SizedBox(height: 12),
          TextField(
            controller: _feld,
            autofocus: true,
            contextMenuBuilder: einfuegbaresMenue,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: t.albenName,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _fertig(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(onPressed: _fertig, child: Text(t.albenMerken)),
      ],
    );
  }
}

class _KlugeKachel extends StatelessWidget {
  const _KlugeKachel({required this.sitzung, required this.suche});

  final Sitzung sitzung;
  final SavedSearchData suche;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              IntelligentesAlbumSeite(sitzung: sitzung, suche: suche),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [farben.primary, const Color(0xFF6E56CF)],
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.saved_search_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(suche.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Ein intelligentes Album: die gemerkte Suche, frisch gegen die
/// Bibliothek – wie am Rechner und im Browser.
class IntelligentesAlbumSeite extends StatefulWidget {
  const IntelligentesAlbumSeite({
    super.key,
    required this.sitzung,
    required this.suche,
  });

  final Sitzung sitzung;
  final SavedSearchData suche;

  @override
  State<IntelligentesAlbumSeite> createState() =>
      _IntelligentesAlbumSeiteState();
}

class _IntelligentesAlbumSeiteState extends State<IntelligentesAlbumSeite> {
  late final Future<List<AssetData>?> _funde = _lade();

  /// `null`: Sie sucht nach Bildinhalt, und der Server kann den Text nicht
  /// einbetten.
  Future<List<AssetData>?> _lade() async {
    final db = widget.sitzung.db;
    final f = db.decodeSavedSearchFilters(widget.suche.filtersJson);
    if (!brauchtSuchvektor(f)) return intelligentesAlbum(db, f);
    final vektor = await widget.sitzung.textvektor(f.query.trim());
    if (vektor == null) return null;
    return intelligentesAlbum(db, f, vektor: vektor);
  }

  Future<void> _loeschen() async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.albenIntelligentLoeschen(widget.suche.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.albenLoeschen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    await widget.sitzung.db.fuehreAus(SucheVergessen(widget.suche.id));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.suche.name),
        actions: [
          IconButton(
            tooltip: t.diashow,
            icon: const Icon(Icons.slideshow_outlined),
            onPressed: () async {
              final a = await _funde;
              if (a == null || !context.mounted) return;
              await zeigeDiashow(context, widget.sitzung, [
                for (final x in a) Rasterzeile.aus(x),
              ]);
            },
          ),
          IconButton(
            tooltip: t.albenLoeschen,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _loeschen,
          ),
        ],
      ),
      body: FutureBuilder<List<AssetData>?>(
        future: _funde,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final a = s.data;
          if (a == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.hasError ? t.sucheFehler : t.sucheKeinModell,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return AufnahmenRaster(
            sitzung: widget.sitzung,
            zeilen: [for (final x in a) Rasterzeile.aus(x)],
          );
        },
      ),
    );
  }
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
        _OfflineAlbumKnopf(sitzung: sitzung, albumId: album.id),
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

class _OfflineAlbumKnopf extends StatefulWidget {
  const _OfflineAlbumKnopf({required this.sitzung, required this.albumId});

  final Sitzung sitzung;
  final String albumId;

  @override
  State<_OfflineAlbumKnopf> createState() => _OfflineAlbumKnopfState();
}

class _OfflineAlbumKnopfState extends State<_OfflineAlbumKnopf> {
  bool _laedt = false;

  Future<void> _umschalten() async {
    if (_laedt) return;
    final t = AppTexte.of(context);
    final neu = !widget.sitzung.istAlbumOffline(widget.albumId);
    setState(() => _laedt = true);
    try {
      final n = await widget.sitzung.setzeAlbumOffline(widget.albumId, neu);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(neu ? t.albumOfflineFertig(n) : t.albumOfflineEntfernt),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.albumOfflineFehler)));
    } finally {
      if (mounted) setState(() => _laedt = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline = widget.sitzung.istAlbumOffline(widget.albumId);
    final t = AppTexte.of(context);
    return IconButton(
      tooltip: offline ? t.albumOfflineAufheben : t.albumOfflineSpeichern,
      onPressed: _laedt ? null : _umschalten,
      icon: _laedt
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(offline ? Icons.offline_pin : Icons.offline_pin_outlined),
    );
  }
}
