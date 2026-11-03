import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_localizations.dart';

// Alben zwischen Konten teilen (#105) – wie im Browser (web/app.js,
// zeigeGeteiltesAlbum und oeffneKontenDialog).
//
// Ein Album, das ein anderes Konto teilt, liegt nicht in der Kopie dieses
// Telefons: Es gehört zur Bibliothek des Besitzers. Raster und Betrachter
// holen deshalb alles direkt vom Server, und nur der Bildspeicher hält es
// vor.

String _k(String s) => Uri.encodeComponent(s);

/// Ein Bild vom Server über [verbindung], das nicht in der Bibliothek
/// liegt.
class FernBild extends ImageProvider<FernBild> {
  const FernBild(this.verbindung, this.pfad);

  final Serververbindung verbindung;
  final String pfad;

  @override
  Future<FernBild> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<FernBild>(this);

  @override
  ImageStreamCompleter loadImage(FernBild key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _lade(key, decode),
        scale: 1,
        debugLabel: pfad,
      );

  Future<ui.Codec> _lade(FernBild key, ImageDecoderCallback decode) async {
    try {
      final r = await verbindung.anfrage('GET', pfad);
      if (r.statusCode != 200) throw Serverfehler(r.statusCode, '');
      return await decode(await ui.ImmutableBuffer.fromUint8List(r.bodyBytes));
    } catch (_) {
      // Offline: nicht im Bildspeicher behalten, der nächste Blick holt es.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FernBild &&
      other.pfad == pfad &&
      identical(other.verbindung, verbindung);

  @override
  int get hashCode => Object.hash(pfad, identityHashCode(verbindung));
}

/// Ein Album, das ein anderes Konto mit diesem teilt.
class GeteiltesAlbum {
  const GeteiltesAlbum({
    required this.id,
    required this.name,
    required this.besitzer,
    required this.beitragen,
    required this.anzahl,
    this.titelbild,
    this.titelstand,
  });

  factory GeteiltesAlbum.aus(Map<String, Object?> j) => GeteiltesAlbum(
    id: '${j['id']}',
    name: '${j['name'] ?? ''}',
    besitzer: '${j['besitzer'] ?? ''}',
    beitragen: j['beitragen'] == true,
    anzahl: (j['anzahl'] as num?)?.toInt() ?? 0,
    titelbild: j['titelbild'] as String?,
    titelstand: j['titelstand'] as String?,
  );

  /// Die Kennung der Teilung, nicht die des Albums.
  final String id;
  final String name;
  final String besitzer;
  final bool beitragen;
  final int anzahl;
  final String? titelbild;
  final String? titelstand;

  String datei(String aufnahme, String art, [String? stand]) =>
      'api/v1/geteilt/${_k(id)}/aufnahmen/${_k(aufnahme)}/$art'
      '${stand == null ? '' : '?v=${_k(stand)}'}';
}

/// Eine Aufnahme darin – was die Liste des Servers über sie sagt.
class GeteilteAufnahme {
  const GeteilteAufnahme({
    required this.id,
    required this.video,
    required this.name,
    required this.aufgenommen,
    this.dauer,
    this.von,
    this.stand,
  });

  factory GeteilteAufnahme.aus(Map<String, Object?> j) => GeteilteAufnahme(
    id: '${j['id']}',
    video: j['art'] == 'video',
    name: '${j['name'] ?? ''}',
    aufgenommen:
        DateTime.tryParse('${j['aufgenommen']}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    dauer: (j['dauer'] as num?)?.toDouble(),
    von: j['von'] as String?,
    stand: j['stand'] as String?,
  );

  final String id;
  final bool video;
  final String name;
  final DateTime aufgenommen;
  final double? dauer;

  /// Wer sie beigetragen hat, wenn nicht der Besitzer.
  final String? von;
  final String? stand;
}

/// „Geteilt mit mir“ in der Albenliste: ein Abschnitt mit Überschrift,
/// oder nichts, solange nichts geteilt ist (oder der Server es nicht
/// kann, oder das Telefon offline ist).
class GeteilteAlben extends StatefulWidget {
  const GeteilteAlben({
    super.key,
    required this.verbindung,
    required this.raster,
  });

  final Serververbindung? verbindung;
  final SliverGridDelegate raster;

  @override
  State<GeteilteAlben> createState() => _GeteilteAlbenState();
}

class _GeteilteAlbenState extends State<GeteilteAlben> {
  List<GeteiltesAlbum> _alben = const [];

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    final v = widget.verbindung;
    if (v == null) return;
    try {
      final d = await v.hole('api/v1/geteilt');
      final liste = [
        for (final x in (d['alben'] as List? ?? const []))
          GeteiltesAlbum.aus((x as Map).cast<String, Object?>()),
      ];
      if (mounted) setState(() => _alben = liste);
    } on KeineVerbindung {
      // Offline: Was geteilt ist, kommt beim nächsten Öffnen.
    } on Serverfehler {
      // Ein Server vor 3.53 kennt keine geteilten Alben.
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.verbindung;
    if (v == null || _alben.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              AppTexte.of(context).geteiltMitMir,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid.builder(
            gridDelegate: widget.raster,
            itemCount: _alben.length,
            itemBuilder: (context, i) => _GeteilteKachel(
              verbindung: v,
              album: _alben[i],
              geaendert: _lade,
            ),
          ),
        ),
      ],
    );
  }
}

class _GeteilteKachel extends StatelessWidget {
  const _GeteilteKachel({
    required this.verbindung,
    required this.album,
    required this.geaendert,
  });

  final Serververbindung verbindung;
  final GeteiltesAlbum album;
  final VoidCallback geaendert;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final titel = album.titelbild;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                GeteiltesAlbumSeite(verbindung: verbindung, album: album),
          ),
        );
        geaendert();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(
                child: titel == null
                    ? ColoredBox(color: farben.surfaceContainerHighest)
                    : _FernMiniatur(
                        FernBild(
                          verbindung,
                          album.datei(titel, 'miniatur', album.titelstand),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            t.geteiltVon(album.besitzer),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Eine Miniatur vom Server, auf ihre Grösse dekodiert.
class _FernMiniatur extends StatelessWidget {
  const _FernMiniatur(this.bild);

  final ImageProvider bild;

  @override
  Widget build(BuildContext context) {
    final flaeche = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final breite = (c.maxWidth * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(64, 1024);
        return Image(
          image: ResizeImage(bild, width: breite),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => flaeche,
          frameBuilder: (context, kind, frame, sofort) =>
              frame == null && !sofort ? flaeche : kind,
        );
      },
    );
  }
}

/// Ein Album, das ein anderes Konto teilt: Raster, Betrachter und – mit
/// Recht zum Beitragen – eigene Fotos hinein.
class GeteiltesAlbumSeite extends StatefulWidget {
  const GeteiltesAlbumSeite({
    super.key,
    required this.verbindung,
    required this.album,
    this.waehle,
  });

  final Serververbindung verbindung;
  final GeteiltesAlbum album;

  /// Wer die Fotos zum Beitragen wählt – im Betrieb die Fotomediathek
  /// ([waehleFotos]), in Tests eine feste Liste.
  final Future<List<Beitragsdatei>> Function(BuildContext context)? waehle;

  @override
  State<GeteiltesAlbumSeite> createState() => _GeteiltesAlbumSeiteState();
}

class _GeteiltesAlbumSeiteState extends State<GeteiltesAlbumSeite> {
  late GeteiltesAlbum _album = widget.album;
  List<GeteilteAufnahme>? _aufnahmen;
  Object? _fehler;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final d = await widget.verbindung.hole(
        'api/v1/geteilt/${_k(widget.album.id)}',
      );
      final a = (d['album'] as Map? ?? const {}).cast<String, Object?>();
      final liste = [
        for (final x in (d['aufnahmen'] as List? ?? const []))
          GeteilteAufnahme.aus((x as Map).cast<String, Object?>()),
      ];
      if (!mounted) return;
      setState(() {
        _album = GeteiltesAlbum(
          id: widget.album.id,
          name: '${a['name'] ?? widget.album.name}',
          besitzer: '${a['besitzer'] ?? widget.album.besitzer}',
          beitragen: a['beitragen'] == true,
          anzahl: liste.length,
        );
        _aufnahmen = liste;
        _fehler = null;
      });
    } on Serverfehler catch (e) {
      if (!mounted) return;
      if (e.status == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppTexte.of(context).geteiltNichtMehr)),
        );
        Navigator.of(context).pop();
        return;
      }
      setState(() => _fehler = e);
    } on KeineVerbindung catch (e) {
      if (mounted) setState(() => _fehler = e);
    }
  }

  Future<void> _verlassen() async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.geteiltVerlassenFrage(_album.name, _album.besitzer)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t.abbrechen),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.geteiltVerlassen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    final bote = ScaffoldMessenger.of(context);
    final weg = Navigator.of(context);
    try {
      await widget.verbindung.anfrage(
        'DELETE',
        'api/v1/geteilt/${_k(_album.id)}',
      );
      weg.pop();
    } on KeineVerbindung {
      bote.showSnackBar(SnackBar(content: Text(t.geteiltOffline)));
    }
  }

  Future<void> _hinzufuegen() async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    final dateien = await (widget.waehle ?? waehleFotos)(context);
    if (dateien.isEmpty || !mounted) return;
    final stand = ValueNotifier<(int, double)>((0, 0));
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: ValueListenableBuilder<(int, double)>(
          valueListenable: stand,
          builder: (c, s, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.geteiltLaedtHoch(s.$1 + 1, dateien.length)),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: s.$2),
            ],
          ),
        ),
      ),
    );
    final weg = Navigator.of(context, rootNavigator: true);
    var gut = 0;
    String? meldung;
    for (var i = 0; i < dateien.length; i++) {
      stand.value = (i, 0);
      final d = dateien[i];
      try {
        final datei = await d.datei();
        if (datei == null) {
          meldung = t.geteiltFehler(d.name);
          continue;
        }
        await widget.verbindung.schickeDatei(
          'api/v1/geteilt/${_k(_album.id)}/beitrag',
          datei,
          parameter: {
            'name': d.name,
            'geaendert': '${d.geaendert.millisecondsSinceEpoch}',
          },
          fortschritt: (n, g) => stand.value = (i, g == 0 ? 0 : n / g),
        );
        gut++;
      } on Serverfehler catch (e) {
        if (e.status == 403 || e.status == 404) {
          meldung = t.geteiltNurAnsehen;
          break;
        }
        if (e.status == 507) {
          meldung = t.geteiltSpeicherVoll;
          break;
        }
        meldung = t.geteiltFehler(d.name);
      } on KeineVerbindung {
        meldung = t.geteiltOffline;
        break;
      }
    }
    weg.pop();
    await dialog;
    stand.dispose();
    bote.showSnackBar(
      SnackBar(content: Text(meldung ?? t.geteiltHinzugefuegt(gut))),
    );
    if (gut > 0) await _lade();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final a = _aufnahmen;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              t.geteiltAlbumVon(_album.besitzer),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (_album.beitragen)
            IconButton(
              tooltip: t.geteiltHinzufuegen,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _hinzufuegen,
            ),
          PopupMenuButton<void>(
            itemBuilder: (_) => [
              PopupMenuItem<void>(
                onTap: _verlassen,
                child: Text(t.geteiltVerlassen),
              ),
            ],
          ),
        ],
      ),
      body: a == null
          ? Center(
              child: _fehler == null
                  ? const CircularProgressIndicator()
                  : Text(t.geteiltOffline),
            )
          : RefreshIndicator(
              onRefresh: _lade,
              child: a.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(child: Text(t.geteiltLeer)),
                        ),
                      ],
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(2),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 130,
                            mainAxisSpacing: 2,
                            crossAxisSpacing: 2,
                          ),
                      itemCount: a.length,
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => GeteilterBetrachter(
                              verbindung: widget.verbindung,
                              album: _album,
                              aufnahmen: a,
                              start: i,
                            ),
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _FernMiniatur(
                              FernBild(
                                widget.verbindung,
                                _album.datei(a[i].id, 'miniatur', a[i].stand),
                              ),
                            ),
                            if (a[i].video)
                              const Positioned(
                                right: 4,
                                bottom: 4,
                                child: Icon(
                                  Icons.play_circle_outline,
                                  color: Colors.white,
                                  size: 20,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
    );
  }
}

/// Die Aufnahmen eines geteilten Albums, eine nach der anderen.
class GeteilterBetrachter extends StatefulWidget {
  const GeteilterBetrachter({
    super.key,
    required this.verbindung,
    required this.album,
    required this.aufnahmen,
    required this.start,
  });

  final Serververbindung verbindung;
  final GeteiltesAlbum album;
  final List<GeteilteAufnahme> aufnahmen;
  final int start;

  @override
  State<GeteilterBetrachter> createState() => _GeteilterBetrachterState();
}

class _GeteilterBetrachterState extends State<GeteilterBetrachter> {
  late final _seiten = PageController(initialPage: widget.start);
  late int _index = widget.start;

  @override
  void dispose() {
    _seiten.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final a = widget.aufnahmen[_index];
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final klein = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Colors.white70);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat.yMMMd(
                sprache,
              ).add_Hm().format(a.aufgenommen.toLocal()),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
            Text(
              a.von == null ? a.name : t.geteiltBeigetragenVon(a.von!),
              style: klein,
            ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _seiten,
        itemCount: widget.aufnahmen.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final x = widget.aufnahmen[i];
          if (x.video) {
            return _FernVideo(
              verbindung: widget.verbindung,
              album: widget.album,
              aufnahme: x,
            );
          }
          return InteractiveViewer(
            maxScale: 6,
            child: Center(
              child: Image(
                image: FernBild(
                  widget.verbindung,
                  widget.album.datei(x.id, 'ansicht', x.stand),
                ),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                loadingBuilder: (context, kind, fortschritt) =>
                    fortschritt == null
                    ? kind
                    : Image(
                        image: FernBild(
                          widget.verbindung,
                          widget.album.datei(x.id, 'miniatur', x.stand),
                        ),
                        fit: BoxFit.contain,
                      ),
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Ein Video aus einem geteilten Album: so, wie es ist, sonst die
/// H.264-Fassung des Servers.
class _FernVideo extends StatefulWidget {
  const _FernVideo({
    required this.verbindung,
    required this.album,
    required this.aufnahme,
  });

  final Serververbindung verbindung;
  final GeteiltesAlbum album;
  final GeteilteAufnahme aufnahme;

  @override
  State<_FernVideo> createState() => _FernVideoState();
}

class _FernVideoState extends State<_FernVideo> {
  VideoPlayerController? _spieler;
  var _fehler = false;
  var _weg = false;

  @override
  void initState() {
    super.initState();
    _starte();
  }

  Future<bool> _bereit(VideoPlayerController c) async {
    try {
      await c.initialize();
      if (c.value.size.width > 0) return true;
    } catch (_) {
      // Spielt das Telefon nicht – dann die Fassung.
    }
    await c.dispose();
    return false;
  }

  Future<void> _starte() async {
    final v = widget.verbindung;
    final kopf = {'authorization': 'Bearer ${v.token}'};
    final id = widget.aufnahme.id;
    VideoPlayerController? s = VideoPlayerController.networkUrl(
      v.adresse(widget.album.datei(id, 'wiedergabe')),
      httpHeaders: kopf,
    );
    if (!await _bereit(s)) {
      s = null;
      final pfad = widget.album.datei(id, 'abspielbar');
      for (var i = 0; i < 900 && !_weg; i++) {
        final r = await v.anfrage('GET', '$pfad?pruefen=1');
        if (r.statusCode == 200) {
          final c = VideoPlayerController.networkUrl(
            v.adresse(pfad),
            httpHeaders: kopf,
          );
          if (await _bereit(c)) s = c;
          break;
        }
        if (r.statusCode != 202) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (_weg) {
      await s?.dispose();
      return;
    }
    setState(() {
      _spieler = s;
      _fehler = s == null;
    });
  }

  @override
  void dispose() {
    _weg = true;
    _spieler?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _spieler;
    if (_fehler) {
      return const Center(
        child: Icon(Icons.videocam_off_outlined, color: Colors.white54),
      );
    }
    if (s == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => s.value.isPlaying ? s.pause() : s.play()),
      child: Center(
        child: AspectRatio(
          aspectRatio: s.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(s),
              if (!s.value.isPlaying)
                const Icon(
                  Icons.play_circle_outline,
                  color: Colors.white70,
                  size: 64,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Fotos wählen ----------------------------------------------------------

/// Eine Datei, die in ein geteiltes Album soll. [datei] holt sie erst beim
/// Hochladen – aus der Fotomediathek kann das ein Download aus iCloud sein.
class Beitragsdatei {
  const Beitragsdatei({
    required this.name,
    required this.geaendert,
    required this.datei,
  });

  final String name;
  final DateTime geaendert;
  final Future<File?> Function() datei;
}

/// Die Fotomediathek zum Wählen, die neuesten zuerst.
Future<List<Beitragsdatei>> waehleFotos(BuildContext context) async {
  final zugriff = await PhotoManager.requestPermissionExtend();
  if (!context.mounted) return const [];
  if (!zugriff.hasAccess) {
    final t = AppTexte.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.fotosKeinZugriff),
        action: SnackBarAction(
          label: t.fotosEinstellungen,
          onPressed: PhotoManager.openSetting,
        ),
      ),
    );
    return const [];
  }
  final gewaehlt = await Navigator.of(context).push<List<AssetEntity>>(
    MaterialPageRoute(builder: (_) => const _Fotowahl()),
  );
  return [
    for (final e in gewaehlt ?? const <AssetEntity>[])
      Beitragsdatei(
        // `title` ist unter iOS oft leer; erst `titleAsync` fragt nach.
        name: switch (await e.titleAsync) {
          final n when n.isNotEmpty => n,
          _ => '${e.id}.jpg',
        },
        geaendert: e.createDateTime,
        datei: () => e.originFile,
      ),
  ];
}

class _Fotowahl extends StatefulWidget {
  const _Fotowahl();

  @override
  State<_Fotowahl> createState() => _FotowahlState();
}

class _FotowahlState extends State<_Fotowahl> {
  static const _seite = 120;
  AssetPathEntity? _alle;
  final _eintraege = <AssetEntity>[];
  final _gewaehlt = <AssetEntity>[];
  var _ende = false;
  var _laedt = false;

  @override
  void initState() {
    super.initState();
    _naechste();
  }

  Future<void> _naechste() async {
    if (_laedt || _ende) return;
    _laedt = true;
    try {
      _alle ??= (await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      )).firstOrNull;
      final alle = _alle;
      if (alle == null) {
        _ende = true;
        return;
      }
      final neu = await alle.getAssetListPaged(
        page: _eintraege.length ~/ _seite,
        size: _seite,
      );
      if (!mounted) return;
      setState(() {
        _eintraege.addAll(neu);
        _ende = neu.length < _seite;
      });
    } finally {
      _laedt = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.fotosWaehlen),
        actions: [
          TextButton(
            onPressed: _gewaehlt.isEmpty
                ? null
                : () => Navigator.of(context).pop(_gewaehlt),
            child: Text(t.fotosHinzufuegen(_gewaehlt.length)),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 110,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: _eintraege.length,
        itemBuilder: (context, i) {
          if (i >= _eintraege.length - 30) _naechste();
          final e = _eintraege[i];
          final stelle = _gewaehlt.indexOf(e);
          return GestureDetector(
            onTap: () => setState(
              () => stelle < 0 ? _gewaehlt.add(e) : _gewaehlt.remove(e),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AssetEntityImage(
                  e,
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(240),
                  fit: BoxFit.cover,
                ),
                if (e.type == AssetType.video)
                  const Positioned(
                    right: 4,
                    bottom: 4,
                    child: Icon(
                      Icons.play_circle_outline,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: stelle < 0
                        ? Colors.black38
                        : Theme.of(context).colorScheme.primary,
                    child: stelle < 0
                        ? null
                        : Text(
                            '${stelle + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// --- Für den Besitzer ------------------------------------------------------

/// „Mit Konten teilen“ für das eigene Album [albumId].
Future<void> mitKontenTeilen(
  BuildContext context,
  Serververbindung? verbindung, {
  required String albumId,
  required String titel,
}) async {
  if (verbindung == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        _KontenBlatt(verbindung: verbindung, albumId: albumId, titel: titel),
  );
}

class _Empfaenger {
  const _Empfaenger(this.konto, this.name, this.beitragen);

  final String konto;
  final String name;
  final bool beitragen;
}

class _KontenBlatt extends StatefulWidget {
  const _KontenBlatt({
    required this.verbindung,
    required this.albumId,
    required this.titel,
  });

  final Serververbindung verbindung;
  final String albumId;
  final String titel;

  @override
  State<_KontenBlatt> createState() => _KontenBlattState();
}

class _KontenBlattState extends State<_KontenBlatt> {
  List<_Empfaenger>? _geteilt;
  List<(String, String)> _andere = const [];
  String? _neu;
  var _neuBeitragen = false;
  String? _fehler;

  String get _pfad => 'api/v1/alben/${_k(widget.albumId)}/teilungen';

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final (d, k) = await (
        widget.verbindung.hole(_pfad),
        widget.verbindung.hole('api/v1/konten/andere'),
      ).wait;
      if (!mounted) return;
      final geteilt = [
        for (final x in (d['teilungen'] as List? ?? const []))
          if (x case {'konto': final konto, 'name': final name})
            _Empfaenger('$konto', '$name', x['beitragen'] == true),
      ];
      final schon = {for (final g in geteilt) g.konto};
      setState(() {
        _geteilt = geteilt;
        _andere = [
          for (final x in (k['konten'] as List? ?? const []))
            if (x case {'id': final id, 'name': final name})
              if (!schon.contains('$id')) ('$id', '$name'),
        ];
        _neu = _andere.isEmpty ? null : _andere.first.$1;
        _fehler = null;
      });
    } on ParallelWaitError<dynamic, dynamic> {
      if (mounted) {
        setState(() => _fehler = AppTexte.of(context).geteiltOffline);
      }
    }
  }

  Future<void> _aendere(Future<void> Function() schritt) async {
    try {
      await schritt();
    } on Serverfehler catch (e) {
      if (mounted) setState(() => _fehler = e.text);
      return;
    } on KeineVerbindung {
      if (mounted) {
        setState(() => _fehler = AppTexte.of(context).geteiltOffline);
      }
      return;
    }
    await _lade();
  }

  Future<void> _teile(String konto, bool beitragen) => _aendere(() async {
    final r = await widget.verbindung.anfrage(
      'PUT',
      '$_pfad/${_k(konto)}',
      kopf: {'content-type': 'application/json'},
      inhalt: '{"beitragen":$beitragen}'.codeUnits,
    );
    if (r.statusCode != 200) throw Serverfehler(r.statusCode, r.body);
  });

  Future<void> _entferne(String konto) => _aendere(() async {
    final r = await widget.verbindung.anfrage('DELETE', '$_pfad/${_k(konto)}');
    if (r.statusCode != 204) throw Serverfehler(r.statusCode, r.body);
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final geteilt = _geteilt;
    DropdownButton<bool> recht(bool wert, ValueChanged<bool> neu) =>
        DropdownButton<bool>(
          value: wert,
          underline: const SizedBox.shrink(),
          items: [
            DropdownMenuItem(value: false, child: Text(t.kontenAnsehen)),
            DropdownMenuItem(value: true, child: Text(t.kontenBeitragen)),
          ],
          onChanged: (w) => w == null ? null : neu(w),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.kontenTeilenTitel(widget.titel),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(t.kontenTeilenHinweis),
            const SizedBox(height: 12),
            if (geteilt == null && _fehler == null)
              const Center(child: CircularProgressIndicator())
            else if (geteilt != null) ...[
              if (geteilt.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(t.kontenNiemand),
                ),
              for (final g in geteilt)
                Row(
                  children: [
                    Expanded(child: Text(g.name)),
                    recht(g.beitragen, (w) => _teile(g.konto, w)),
                    IconButton(
                      tooltip: t.entfernen,
                      icon: const Icon(Icons.close),
                      onPressed: () => _entferne(g.konto),
                    ),
                  ],
                ),
              if (_andere.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _neu,
                        items: [
                          for (final (id, name) in _andere)
                            DropdownMenuItem(value: id, child: Text(name)),
                        ],
                        onChanged: (w) => setState(() => _neu = w),
                      ),
                    ),
                    const SizedBox(width: 8),
                    recht(
                      _neuBeitragen,
                      (w) => setState(() => _neuBeitragen = w),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _neu == null
                          ? null
                          : () => _teile(_neu!, _neuBeitragen),
                      child: Text(t.kontenTeilenKnopf),
                    ),
                  ],
                )
              else if (geteilt.isEmpty)
                Text(t.kontenKeineAnderen),
            ],
            if (_fehler case final f?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  f,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              t.kontenBeitragenHinweis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
