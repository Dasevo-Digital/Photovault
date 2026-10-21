import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_localizations.dart';
import '../seiten/sicherung.dart';
import '../sitzung.dart';
import 'ungesichert.dart';

/// Aufnahmen, die nur auf dem Telefon liegen, eine nach der anderen –
/// direkt aus der Fotomediathek, mit dem Hinweis, dass sie noch nicht
/// gesichert sind, und dem Knopf, es jetzt zu tun.
class Lokalbetrachter extends StatefulWidget {
  const Lokalbetrachter({
    super.key,
    required this.sitzung,
    required this.aufnahmen,
    required this.start,
  });

  final Sitzung sitzung;
  final List<LokaleAufnahme> aufnahmen;
  final int start;

  @override
  State<Lokalbetrachter> createState() => _LokalbetrachterState();
}

class _LokalbetrachterState extends State<Lokalbetrachter> {
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat.yMMMd(sprache).format(a.aufgenommen.toLocal()),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
            Text(
              t.lokalNochNichtGesichert,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (widget.sitzung.sicherung case final d?)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(t.lokalJetztSichern),
              onPressed: d.laeuft
                  ? null
                  : () => jetztSichern(context, d, db: widget.sitzung.db),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _seiten,
        itemCount: widget.aufnahmen.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final x = widget.aufnahmen[i];
          final e = x.entity;
          if (e == null) {
            return const ColoredBox(color: Colors.black26);
          }
          if (x.video) return _LokalesVideo(x);
          return InteractiveViewer(
            maxScale: 6,
            child: Center(
              child: AssetEntityImage(e, isOriginal: true, fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
  }
}

/// Ein Video vom Telefon: aus der Datei, Tipp startet und hält an.
class _LokalesVideo extends StatefulWidget {
  const _LokalesVideo(this.aufnahme);

  final LokaleAufnahme aufnahme;

  @override
  State<_LokalesVideo> createState() => _LokalesVideoState();
}

class _LokalesVideoState extends State<_LokalesVideo> {
  VideoPlayerController? _spieler;
  var _fehler = false;

  @override
  void initState() {
    super.initState();
    _starte();
  }

  Future<void> _starte() async {
    try {
      final datei = await widget.aufnahme.entity!.file;
      if (datei == null) throw StateError('keine Datei');
      final s = VideoPlayerController.file(datei);
      await s.initialize();
      if (!mounted) {
        await s.dispose();
        return;
      }
      setState(() => _spieler = s);
    } catch (_) {
      if (mounted) setState(() => _fehler = true);
    }
  }

  @override
  void dispose() {
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
