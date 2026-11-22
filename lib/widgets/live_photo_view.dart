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

  /// Legt den Spieler an – nur für Prüfungen austauschbar.
  @visibleForTesting
  final VideoPlaybackController Function() neuerSpieler;

  const LivePhotoView({
    super.key,
    required this.imageFile,
    required this.videoFile,
    this.neuerSpieler = VideoPlaybackController.new,
  });

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

  /// Was gerade gewünscht ist: `null` nichts, `false` Abspielen beim
  /// Halten, `true` Dauerschleife.
  ///
  /// Das Öffnen des Videos dauert (Dauer und Bildmasse müssen bekannt
  /// sein). Wer in der Zeit losliess, bekam das Video trotzdem einmal
  /// abgespielt, und es blieb auf dem letzten Bild stehen. Nach jedem
  /// `await` zählt deshalb, was jetzt gewünscht ist (#433).
  bool? _gewuenscht;

  /// Der laufende Öffnungsvorgang. Vorher öffnete ein zweiter Aufruf
  /// während des ersten einen zweiten Spieler; der erste wurde nie
  /// entsorgt und spielte mit Ton im Hintergrund weiter (#433).
  Future<VideoPlaybackController?>? _oeffnen;

  Future<VideoPlaybackController?> _ensureController() {
    final vorhanden = _controller;
    if (vorhanden != null) return Future.value(vorhanden);
    return _oeffnen ??= _oeffneController().whenComplete(() => _oeffnen = null);
  }

  Future<VideoPlaybackController?> _oeffneController() async {
    setState(() => _initializing = true);
    final controller = widget.neuerSpieler();
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
    _gewuenscht = loop;
    if (_playing && _loopMode == loop) return;
    final controller = await _ensureController();
    bool giltNoch() => mounted && _gewuenscht == loop;
    if (controller == null || !giltNoch()) return;
    setState(() {
      _playing = true;
      _loopMode = loop;
    });
    await controller.setLooping(loop);
    if (!giltNoch()) return;
    await controller.seekToStart();
    if (!giltNoch()) return;
    await controller.play();
    // Während des Startens losgelassen: Das Anhalten kam dann vor dem
    // Abspielen an.
    if (mounted && !_playing) await controller.pause();
  }

  Future<void> _stopPlayback() async {
    _gewuenscht = null;
    if (!_playing) return;
    setState(() {
      _playing = false;
      _loopMode = false;
    });
    await _controller?.pause();
  }

  /// Ob die Dauerschleife läuft oder gerade startet. Nach dem Wunsch und
  /// nicht nach [_loopMode]: Der steht erst, wenn das Video offen ist, und
  /// ein Loslassen in der Zwischenzeit brach die Schleife sonst ab.
  bool get _schleife => _gewuenscht == true;

  void _onHoldStart() {
    if (_schleife) {
      return; // Play-Button hat Vorrang, Halten soll nichts abbrechen.
    }
    _startPlayback(loop: false);
  }

  void _onHoldEnd() {
    if (_schleife) return;
    _stopPlayback();
  }

  void _togglePlayButton() {
    if (_schleife) {
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
          Image(image: begrenztesBild(widget.imageFile), fit: BoxFit.contain),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.motion_photos_on, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
              icon: Icon(
                _loopMode ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
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
