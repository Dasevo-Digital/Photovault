/// Das eine Videobild, das über der Kachelwand läuft.
///
/// **Warum genau eines.** Jede Wiedergabe ist ein eigener mpv-Prozess mit
/// eigenem Dekoder. Liesse man jede überstrichene Kachel ihre eigene
/// starten, hätte man nach einer Handbewegung ein Dutzend davon offen.
/// Deshalb gibt es hier eine einzige Stelle, die weiss, was gerade läuft,
/// und die das alte beendet, bevor das neue beginnt.
///
/// **Warum als Bereich und nicht als Wert in jeder Kachel.** Die Kachel
/// steht an zwanzig Stellen der App. Sie fragt hier nach, ob über ihr ein
/// Bereich liegt; findet sie keinen – etwa in einem Test –, verhält sie
/// sich wie vorher. So kostet die Neuerung keinen einzigen geänderten
/// Aufrufer.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../services/schwebevorschau.dart';
import '../services/storage_paths.dart';
import 'video_playback.dart';

/// Was eine Kachel von der Vorschau wissen muss.
///
/// Abstrakt, damit ein Test sie nachstellen kann, ohne dass ein echter
/// Abspieler entsteht – siehe die Notiz in
/// `docs/` zu Widget-Tests und echter Ein-/Ausgabe.
abstract class Schwebevorschau extends ChangeNotifier {
  /// Die Kachel, die gerade läuft oder gerade anläuft – oder `null`.
  String? get aktivesAsset;

  /// Lässt das Video zu [asset] anlaufen und beendet ein etwaiges
  /// vorheriges. Tut nichts, wenn [asset] gar keines trägt.
  Future<void> starte(Rasterzeile asset);

  /// Beendet die Wiedergabe, sofern gerade [assetId] läuft. Die Kennung
  /// ist Absicht: Ist die Maus inzwischen weitergewandert, darf das
  /// verspätete Verlassen der alten Kachel die neue nicht abwürgen.
  void beende(String assetId);

  /// Das laufende Bild für [assetId] – oder `null`, wenn dort gerade
  /// nichts läuft oder es noch nicht so weit ist.
  Widget? bildFuer(String assetId);

  /// Der Bereich über [context], falls es einen gibt.
  static Schwebevorschau? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SchwebevorschauScope>()
      ?.vorschau;
}

/// Hängt eine [Schwebevorschau] über [child]. Einmal in `main.dart`.
class SchwebevorschauBereich extends StatefulWidget {
  const SchwebevorschauBereich({
    super.key,
    required this.db,
    required this.paths,
    required this.child,
  });

  final AppDatabase db;
  final StoragePaths paths;
  final Widget child;

  @override
  State<SchwebevorschauBereich> createState() => _SchwebevorschauBereichState();
}

class _SchwebevorschauBereichState extends State<SchwebevorschauBereich> {
  late final _Videovorschau _vorschau =
      _Videovorschau(db: widget.db, paths: widget.paths);

  @override
  void dispose() {
    _vorschau.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SchwebevorschauScope(vorschau: _vorschau, child: widget.child);
}

/// Hängt eine bestimmte [Schwebevorschau] über [child].
///
/// Getrennt von [SchwebevorschauBereich], damit ein Test eine
/// nachgestellte Fassung einhängen kann: Der echte Abspieler wäre ein
/// mpv-Prozess, und ein Widget-Test hätte davon nichts als Wartezeit.
class SchwebevorschauScope extends InheritedWidget {
  const SchwebevorschauScope({
    super.key,
    required this.vorschau,
    required super.child,
  });

  final Schwebevorschau vorschau;

  @override
  bool updateShouldNotify(SchwebevorschauScope alt) => alt.vorschau != vorschau;
}

/// Die echte Fassung: ein Abspieler, eine laufende Kachel.
class _Videovorschau extends Schwebevorschau {
  _Videovorschau({required this.db, required this.paths});

  final AppDatabase db;
  final StoragePaths paths;

  VideoPlaybackController? _regler;
  String? _aktiv;
  bool _bereit = false;

  /// Zählt jeden Auftrag mit. Öffnen und Schliessen eines Videos dauern
  /// beide, und in der Zwischenzeit kann die Maus längst woanders sein –
  /// ohne diesen Zähler käme ein spät fertig gewordenes Video über einer
  /// Kachel hoch, die niemand mehr ansieht.
  int _lauf = 0;
  bool _weg = false;

  @override
  String? get aktivesAsset => _aktiv;

  @override
  Widget? bildFuer(String assetId) {
    if (!_bereit || _aktiv != assetId || _regler == null) return null;
    return VideoSurface(controller: _regler!, fit: BoxFit.cover);
  }

  @override
  Future<void> starte(Rasterzeile asset) async {
    if (_weg || !schwebevorschauAn) return;
    final videoId = schwebeVideoId(asset);
    if (videoId == null) return;
    if (_aktiv == asset.id) return;

    final lauf = ++_lauf;
    await _raeumeAuf();
    if (lauf != _lauf || _weg) return;

    _aktiv = asset.id;
    _bereit = false;
    notifyListeners();

    final datei = await _datei(videoId);
    if (lauf != _lauf || _weg) return;
    if (datei == null) {
      _aktiv = null;
      notifyListeners();
      return;
    }

    final regler = VideoPlaybackController();
    // In Dauerschleife: Ein Live Photo ist drei Sekunden lang, und ein
    // Standbild, das nach drei Sekunden wieder einfriert, sähe nach einem
    // Fehler aus.
    final offen = await regler.open(datei, loop: true);
    if (lauf != _lauf || _weg || !offen) {
      await regler.dispose();
      if (lauf == _lauf && !_weg) {
        _aktiv = null;
        notifyListeners();
      }
      return;
    }
    // Still. Siehe AppSettings.schwebeVorschau.
    await regler.setVolume(0);
    await regler.play();
    if (lauf != _lauf || _weg) {
      await regler.dispose();
      return;
    }
    _regler = regler;
    _bereit = true;
    notifyListeners();
  }

  @override
  void beende(String assetId) {
    if (_aktiv != assetId) return;
    _lauf++;
    _aktiv = null;
    _bereit = false;
    notifyListeners();
    unawaited(_raeumeAuf());
  }

  /// Wo das Video liegt – oder `null`, wenn es den Datensatz nicht mehr
  /// gibt oder er gesperrt ist.
  Future<File?> _datei(String videoId) async {
    final video = await db.assetById(videoId);
    // Die zweite Hälfte eines Live Photos kann für sich gesperrt sein;
    // [schwebeVideoId] sieht nur die erste.
    if (video == null || video.isLocked) return null;
    final datei = paths.absolute(video.relativePath);
    return await datei.exists() ? datei : null;
  }

  Future<void> _raeumeAuf() async {
    final alt = _regler;
    _regler = null;
    _bereit = false;
    await alt?.dispose();
  }

  @override
  void dispose() {
    _weg = true;
    _lauf++;
    unawaited(_raeumeAuf());
    super.dispose();
  }
}
