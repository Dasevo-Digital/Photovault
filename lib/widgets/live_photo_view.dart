import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../services/bilddekodierung.dart';
import '../theme/app_spacing.dart';
import 'video_playback.dart';

/// Zeigt ein Live-Photo-Standbild an. Zwei Wege, das verknüpfte Video
/// abzuspielen: Gedrückt halten (Press-and-Hold, wie in Apple Fotos) zeigt es
/// nur, solange der Finger/die Maustaste gehalten wird, oder der Play-Button
/// unten rechts, der es in Dauerschleife laufen lässt, bis man erneut tippt.
class LivePhotoView extends StatefulWidget {
  final File imageFile;
  final File videoFile;
  const LivePhotoView({super.key, required this.imageFile, required this.videoFile});

  @override
  State<LivePhotoView> createState() => _LivePhotoViewState();
}

class _LivePhotoViewState extends State<LivePhotoView> {
  VideoPlaybackController? _controller;
  bool _playing = false;
  bool _initializing = false;

  /// true, solange die Wiedergabe über den Play-Button (Dauerschleife)
  /// läuft statt über Gedrückt-Halten – verhindert, dass Loslassen des
  /// Press-and-Hold-Gestus eine per Button gestartete Wiedergabe abbricht.
  bool _loopMode = false;

  Future<VideoPlaybackController?> _ensureController() async {
    if (_controller != null) return _controller;
    setState(() => _initializing = true);
    final controller = VideoPlaybackController();
    if (!await controller.open(widget.videoFile)) {
      await controller.dispose();
      if (mounted) setState(() => _initializing = false);
      return null;
    }
    if (!mounted) {
      await controller.dispose();
      return null;
    }
    _controller = controller;
    setState(() => _initializing = false);
    return controller;
  }

  Future<void> _startPlayback({required bool loop}) async {
    if (_playing && _loopMode == loop) return;
    final controller = await _ensureController();
    if (controller == null || !mounted) return;
    setState(() {
      _playing = true;
      _loopMode = loop;
    });
    await controller.setLooping(loop);
    await controller.seekToStart();
    await controller.play();
  }

  Future<void> _stopPlayback() async {
    if (!_playing) return;
    setState(() {
      _playing = false;
      _loopMode = false;
    });
    await _controller?.pause();
  }

  void _onHoldStart() {
    if (_loopMode) return; // Play-Button hat Vorrang, Halten soll nichts abbrechen.
    _startPlayback(loop: false);
  }

  void _onHoldEnd() {
    if (_loopMode) return;
    _stopPlayback();
  }

  void _togglePlayButton() {
    if (_loopMode) {
      _stopPlayback();
    } else {
      _startPlayback(loop: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showVideo = _playing && _controller != null && _controller!.isReady;
    return GestureDetector(
      onLongPressStart: (_) => _onHoldStart(),
      onLongPressEnd: (_) => _onHoldEnd(),
      onLongPressCancel: _onHoldEnd,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          Image(
            image: begrenztesBild(widget.imageFile),
            fit: BoxFit.contain,
          ),
          if (showVideo)
            AspectRatio(
              aspectRatio: _controller!.aspectRatio,
              child: VideoSurface(controller: _controller!),
            ),
          if (_initializing)
            const CircularProgressIndicator(color: Colors.white),
          if (!_playing)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.motion_photos_on, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          if (!_playing)
            Positioned(
              bottom: 24,
              child: Text(
                AppTexte.of(context).livePhotoHalten,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          Positioned(
            bottom: 16,
            right: 16,
            child: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              icon: Icon(_loopMode ? Icons.pause : Icons.play_arrow, color: Colors.white),
              tooltip: _loopMode
                  ? AppTexte.of(context).liveWiedergabeStoppen
                  : AppTexte.of(context).liveDauerschleife,
              onPressed: _togglePlayButton,
            ),
          ),
        ],
      ),
    );
  }
}
