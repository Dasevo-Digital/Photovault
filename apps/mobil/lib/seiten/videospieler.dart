import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kern/db/database.dart';
import 'package:video_player/video_player.dart';

import '../sitzung.dart';

/// Ein fertig geladener Spieler für das Video [a] – wie im Browser: was der
/// Betrachter abspielt (gekürzt, sonst das Original), von hier, wenn es
/// hier liegt, sonst vom Server mit Teilabruf.
///
/// **Spielt das Telefon es nicht** – HEVC auf älteren Android-Geräten –,
/// holt es die H.264-Fassung des Servers (`abspielbar`). Die entsteht beim
/// ersten Mal; [wandelt] meldet, dass gewartet wird, und solange
/// [abgebrochen] nicht `true` sagt, fragt der Spieler jede Sekunde nach.
Future<VideoPlayerController> videospieler(
  Sitzung sitzung,
  AssetData a, {
  VoidCallback? wandelt,
  bool Function()? abgebrochen,
}) async {
  final rel = a.trimmedRelativePath ?? a.relativePath;
  final hier = sitzung.paths.absolute(rel);
  if (await hier.exists()) {
    final c = VideoPlayerController.file(File(hier.path));
    if (await _bereit(c)) return c;
  }
  final abgleich = sitzung.abgleich;
  final v = sitzung.verbindung;
  if (abgleich == null || v == null) throw StateError('ohne Server');
  final kopf = {'authorization': 'Bearer ${v.token}'};
  final direkt = VideoPlayerController.networkUrl(
    abgleich.verbindung.adresse(
      'api/v1/dateien/${rel.split('/').map(Uri.encodeComponent).join('/')}',
    ),
    httpHeaders: kopf,
  );
  if (await _bereit(direkt)) return direkt;

  wandelt?.call();
  final pfad = 'api/v1/aufnahmen/${Uri.encodeComponent(a.id)}/abspielbar';
  for (var i = 0; i < 900; i++) {
    if (abgebrochen?.call() ?? false) throw StateError('abgebrochen');
    final r = await abgleich.verbindung.anfrage('GET', '$pfad?pruefen=1');
    if (r.statusCode == 200) {
      final c = VideoPlayerController.networkUrl(
        abgleich.verbindung.adresse(pfad),
        httpHeaders: kopf,
      );
      if (await _bereit(c)) return c;
      break;
    }
    if (r.statusCode != 202) break;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('nicht abspielbar');
}

/// Lädt [c]; ein Video ohne Bild (Breite 0) zählt wie ein Fehler – so
/// zeigt sich ein Format, das das Gerät nicht dekodiert.
Future<bool> _bereit(VideoPlayerController c) async {
  try {
    await c.initialize();
    if (c.value.size.width > 0) return true;
  } catch (_) {
    // Nicht abspielbar – der nächste Weg.
  }
  await c.dispose();
  return false;
}
