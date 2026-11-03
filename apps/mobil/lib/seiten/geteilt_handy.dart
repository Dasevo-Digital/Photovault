import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:teilen_ui/geteilte_alben.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';

// Was am Telefon zu den geteilten Alben (packages/teilen_ui) dazukommt:
// die Fotomediathek zum Beitragen und video_player für Videos.

/// Der Zugang für die geteilten Alben – `null` ohne Server.
Teilungszugang? teilungszugang(Sitzung sitzung) {
  final v = sitzung.abgleich?.verbindung;
  if (v == null) return null;
  return Teilungszugang(
    verbindung: v,
    ablage: sitzung.paths.geteiltDir,
    waehle: waehleFotos,
    video: (context, video) => _GeteiltesVideo(video),
  );
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

/// Ein Video aus einem geteilten Album: so, wie es ist, sonst die
/// H.264-Fassung des Servers.
class _GeteiltesVideo extends StatefulWidget {
  const _GeteiltesVideo(this.video);

  final Fernvideo video;

  @override
  State<_GeteiltesVideo> createState() => _GeteiltesVideoState();
}

class _GeteiltesVideoState extends State<_GeteiltesVideo> {
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
    final v = widget.video;
    VideoPlayerController? s = VideoPlayerController.networkUrl(
      v.wiedergabe,
      httpHeaders: v.kopf,
    );
    if (!await _bereit(s)) {
      s = null;
      final fassung = await v.fassung(abgebrochen: () => _weg);
      if (fassung != null) {
        final c = VideoPlayerController.networkUrl(
          fassung,
          httpHeaders: v.kopf,
        );
        if (await _bereit(c)) s = c;
      }
    }
    if (_weg || !mounted) {
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
