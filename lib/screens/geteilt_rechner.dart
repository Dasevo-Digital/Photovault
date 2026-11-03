import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kern/services/import_service.dart' show unterstuetzteEndungen;
import 'package:path/path.dart' as p;
import 'package:teilen_ui/geteilte_alben.dart';

import '../state/library_state.dart';
import '../widgets/video_playback.dart';

// Was am Rechner zu den geteilten Alben (packages/teilen_ui, #289)
// dazukommt: der Dateidialog zum Beitragen und media_kit für Videos.

/// Der Zugang für die geteilten Alben – `null`, solange die Bibliothek
/// nicht mit einem Server verbunden ist.
Teilungszugang? teilungszugang(LibraryState library) {
  final v = library.abgleich?.verbindung;
  if (v == null) return null;
  return Teilungszugang(
    verbindung: v,
    ablage: library.paths.geteiltDir,
    waehle: (_) => waehleDateien(),
    video: (context, video) => _GeteiltesVideo(video),
  );
}

/// Fotos und Videos aus dem Dateisystem, mit ihrer Änderungszeit – sie
/// geht mit, damit der Server ein Datum hat, wo die Datei keines trägt.
Future<List<Beitragsdatei>> waehleDateien() async {
  final gewaehlt = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: [for (final e in unterstuetzteEndungen) e.substring(1)],
  );
  return beitraegeAus([
    for (final f in gewaehlt)
      if (f.path case final pfad?) File(pfad),
  ]);
}

/// [dateien] als Beiträge – getrennt von der Dateiwahl, damit es sich ohne
/// Dialog prüfen lässt.
List<Beitragsdatei> beitraegeAus(List<File> dateien) => [
  for (final f in dateien)
    if (f.existsSync())
      Beitragsdatei(
        name: p.basename(f.path),
        geaendert: f.lastModifiedSync(),
        datei: () async => f,
      ),
];

/// Ein Video aus einem geteilten Album. libmpv spielt HEVC selbst; nur wenn
/// es scheitert, kommt die H.264-Fassung des Servers.
class _GeteiltesVideo extends StatefulWidget {
  const _GeteiltesVideo(this.video);

  final Fernvideo video;

  @override
  State<_GeteiltesVideo> createState() => _GeteiltesVideoState();
}

class _GeteiltesVideoState extends State<_GeteiltesVideo> {
  final _spieler = VideoPlaybackController();
  var _bereit = false;
  var _fehler = false;
  var _weg = false;

  @override
  void initState() {
    super.initState();
    _starte();
  }

  Future<void> _starte() async {
    final v = widget.video;
    var ok = await _spieler.openUrl(v.wiedergabe, kopf: v.kopf);
    if (!ok && !_weg) {
      final fassung = await v.fassung(abgebrochen: () => _weg);
      if (fassung != null && !_weg) {
        ok = await _spieler.openUrl(fassung, kopf: v.kopf);
      }
    }
    if (_weg || !mounted) return;
    setState(() {
      _bereit = ok;
      _fehler = !ok;
    });
    if (ok) await _spieler.play();
  }

  @override
  void dispose() {
    _weg = true;
    _spieler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fehler) {
      return const Center(
        child: Icon(Icons.videocam_off_outlined, color: Colors.white54),
      );
    }
    if (!_bereit) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    return StreamBuilder<void>(
      stream: _spieler.changes,
      builder: (context, _) => Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () =>
                  _spieler.isPlaying ? _spieler.pause() : _spieler.play(),
              child: Center(
                child: AspectRatio(
                  aspectRatio: _spieler.aspectRatio,
                  child: VideoSurface(controller: _spieler),
                ),
              ),
            ),
          ),
          VideoProgressBar(controller: _spieler),
        ],
      ),
    );
  }
}
