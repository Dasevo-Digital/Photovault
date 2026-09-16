import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Videowiedergabe für die gesamte App – kapselt `media_kit`, damit die
/// Bildschirme nicht mit dessen Player-/Controller-/Stream-Details arbeiten
/// müssen.
///
/// Ersetzt das frühere `video_player`, das nur Android/iOS/macOS/Web
/// unterstützt und damit der einzige Paket-Blocker für Linux und Windows
/// war. `media_kit` deckt alle Zielplattformen ab, deshalb gibt es hier
/// bewusst KEINE plattformabhängigen Varianten – eine Implementierung für
/// alle (siehe docs/plan_linux.md, Phase 1).
///
/// Die Oberfläche ist absichtlich klein gehalten und bildet genau das ab,
/// was die App braucht: öffnen, abspielen, pausieren, an den Anfang
/// springen, Dauerschleife, Dauer und Seitenverhältnis.
class VideoPlaybackController {
  final Player _player;
  late final VideoController _videoController;

  bool _ready = false;
  bool _disposed = false;

  /// Führt die drei relevanten Zustandsströme zu einem zusammen. Bewusst
  /// von Hand statt über rxdart – dafür allein lohnt keine weitere
  /// Abhängigkeit.
  final _changes = StreamController<void>.broadcast();
  final _subs = <StreamSubscription<void>>[];

  VideoPlaybackController() : _player = Player() {
    _videoController = VideoController(_player);
    _subs.addAll([
      _player.stream.playing.listen((_) => _emit()),
      _player.stream.duration.listen((_) => _emit()),
      _player.stream.width.listen((_) => _emit()),
    ]);
  }

  void _emit() {
    if (!_disposed && !_changes.isClosed) _changes.add(null);
  }

  /// Für das [VideoSurface]-Widget.
  VideoController get videoController => _videoController;

  /// Ob Dauer und Bildmaße bekannt sind – vorher lohnt das Anzeigen nicht.
  bool get isReady => _ready;

  Duration get duration => _player.state.duration;
  Duration get position => _player.state.position;
  bool get isPlaying => _player.state.playing;

  /// Nur die Abspielposition – bewusst getrennt von [changes], damit ein
  /// Fortschrittsbalken sich darauf abonnieren kann, ohne dass der ganze
  /// Bildschirm bei jedem Positionswechsel neu baut.
  Stream<Duration> get positionStream => _player.stream.position;

  /// Fällt auf 16:9 zurück, solange die echten Maße noch nicht vorliegen –
  /// [AspectRatio] darf nicht mit 0 oder NaN aufgerufen werden.
  double get aspectRatio {
    final w = _player.state.width;
    final h = _player.state.height;
    if (w == null || h == null || w <= 0 || h <= 0) return 16 / 9;
    return w / h;
  }

  /// Meldet jede Zustandsänderung, die die Anzeige betrifft (Start/Stopp,
  /// Dauer, Bildmaße) – die Bildschirme können sich darauf abonnieren,
  /// statt selbst zu pollen.
  Stream<void> get changes => _changes.stream;

  /// Öffnet [file] und wartet, bis Dauer UND Bildmaße bekannt sind.
  ///
  /// Gibt `false` zurück, wenn die Datei nicht abspielbar ist oder die
  /// Angaben nicht rechtzeitig eintreffen – die Aufrufer zeigen dann eine
  /// Fehlermeldung, statt endlos auf einen Ladeindikator zu starren.
  Future<bool> open(File file, {bool loop = false}) async {
    if (_disposed) return false;
    try {
      await setLooping(loop);
      // Absolut, nicht wie übergeben. libmpv ist eine native Bibliothek
      // mit eigenem Arbeitsverzeichnis; ein relativer Pfad, den Dart
      // klaglos auflöst, kommt dort als nicht vorhanden an – unter Windows
      // gemessen: keine Dauer, keine Wiedergabe, keine Fehlermeldung.
      // Die App reicht heute immer absolute Pfade herein, aber darauf
      // sollte sich diese Stelle nicht verlassen müssen.
      await _player.open(Media(file.absolute.path), play: false);
      await _awaitReady();
      _ready = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Wartet auf die erste sinnvolle Dauer und Breite. Ohne dieses Warten
  /// stünde direkt nach `open()` noch Duration.zero in `state`, und die
  /// Bildschirme würden mit einer Dauer von 0 rechnen.
  Future<void> _awaitReady() async {
    const grenze = Duration(seconds: 10);
    await Future.wait([
      if (_player.state.duration == Duration.zero)
        _player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(grenze)
      else
        Future<void>.value(),
      if (_player.state.width == null)
        _player.stream.width.firstWhere((w) => w != null && w > 0).timeout(grenze)
      else
        Future<void>.value(),
    ]);
  }

  Future<void> play() => _disposed ? Future.value() : _player.play();
  Future<void> pause() => _disposed ? Future.value() : _player.pause();
  Future<void> seek(Duration to) => _disposed ? Future.value() : _player.seek(to);
  Future<void> seekToStart() => seek(Duration.zero);

  /// Lautstärke in Prozent (0 = still, 100 = wie aufgenommen).
  ///
  /// Für die Schwebe-Vorschau: Eine Kachelwand, die beim Überstreichen
  /// zu tönen anfängt, wäre niemandem eine Hilfe.
  Future<void> setVolume(double prozent) =>
      _disposed ? Future.value() : _player.setVolume(prozent);

  Future<void> setLooping(bool loop) => _disposed
      ? Future.value()
      : _player.setPlaylistMode(loop ? PlaylistMode.loop : PlaylistMode.none);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    await _changes.close();
    await _player.dispose();
  }
}

/// Zeigt das Bild von [controller].
///
/// Ohne eigene Bedienelemente (`controls: NoVideoControls`) – die App bringt
/// je Bildschirm ihre eigenen mit, und mpv-Standardregler würden dort nur
/// doppelt erscheinen.
class VideoSurface extends StatelessWidget {
  final VideoPlaybackController controller;
  final BoxFit fit;

  const VideoSurface({super.key, required this.controller, this.fit = BoxFit.contain});

  @override
  Widget build(BuildContext context) {
    return Video(
      controller: controller.videoController,
      controls: NoVideoControls,
      fit: fit,
    );
  }
}

/// Schlanker Fortschrittsbalken mit Ziehen zum Spulen.
///
/// Ersetzt `VideoProgressIndicator` aus `video_player`, für das es bei
/// `media_kit` keine Entsprechung gibt. Baut sich nur bei
/// Positionsänderungen neu auf (eigener [StreamBuilder]), nicht der ganze
/// umgebende Bildschirm.
class VideoProgressBar extends StatelessWidget {
  final VideoPlaybackController controller;
  final EdgeInsets padding;

  const VideoProgressBar({
    super.key,
    required this.controller,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: controller.positionStream,
      initialData: controller.position,
      builder: (context, snapshot) {
        final gesamt = controller.duration.inMilliseconds;
        final jetzt = (snapshot.data ?? Duration.zero).inMilliseconds;
        final anteil = gesamt <= 0 ? 0.0 : (jetzt / gesamt).clamp(0.0, 1.0);

        void spuleZu(double dx, double breite) {
          if (gesamt <= 0 || breite <= 0) return;
          final ziel = (dx / breite).clamp(0.0, 1.0) * gesamt;
          controller.seek(Duration(milliseconds: ziel.round()));
        }

        return Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final breite = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => spuleZu(d.localPosition.dx, breite),
                onHorizontalDragUpdate: (d) => spuleZu(d.localPosition.dx, breite),
                child: SizedBox(
                  // Größer als der sichtbare Balken, damit er sich mit der
                  // Maus überhaupt treffen lässt.
                  height: 24,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: anteil,
                        minHeight: 4,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
