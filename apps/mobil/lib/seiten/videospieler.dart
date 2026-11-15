import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kern/db/database.dart';
import 'package:video_player/video_player.dart';

import '../sitzung.dart';

/// Ab welcher Datenrate ein Original über das Netz als schwer gilt.
///
/// Ein iPhone filmt 4K mit HDR und rund 50 Mbit/s – mehr, als der Upload
/// eines Anschlusses daheim oder ein Mobilnetz verlässlich liefert. Kommt
/// es langsamer, als es abspielt, fängt der Spieler nicht an: Bis 0.19.4
/// blieb die Seite dann schwarz (#393).
const schwerAbBitProSekunde = 20 * 1000 * 1000;

/// Ob das Original von [a] über das Netz zu schwer ist, um verlässlich
/// anzulaufen ([schwerAbBitProSekunde]). Ohne Dauer oder Grösse nicht.
bool istSchweresVideo(AssetData a) {
  final dauer = a.durationSeconds;
  if (dauer == null || dauer <= 0 || a.fileSizeBytes <= 0) return false;
  return a.fileSizeBytes * 8 / dauer > schwerAbBitProSekunde;
}

/// Ob [c] die leichte Fassung des Servers spielt (`abspielbar`: H.264 bis
/// 1080p, HDR auf SDR abgebildet, Index am Anfang) und nicht das Original.
bool spieltLeichteFassung(VideoPlayerController c) =>
    c.dataSourceType == DataSourceType.network &&
    Uri.parse(c.dataSource).path.endsWith('/abspielbar');

/// Ein fertig geladener Spieler für das Video [a] – wie im Browser: was der
/// Betrachter abspielt (gekürzt, sonst das Original), von hier, wenn es
/// hier liegt, sonst vom Server mit Teilabruf.
///
/// Statt des Originals die leichte Fassung des Servers (`abspielbar`):
/// - **wenn das Telefon das Original nicht spielt** – HEVC auf älteren
///   Android-Geräten. Sie entsteht beim ersten Mal; [wandelt] meldet, dass
///   gewartet wird, und solange [abgebrochen] nicht `true` sagt, fragt der
///   Spieler jede Sekunde nach.
/// - **bei einem schweren Original** ([istSchweresVideo]), sobald sie
///   bereitliegt. Liegt sie noch nicht bereit, stösst schon die Frage ihre
///   Umwandlung an; läuft das Original dann nicht an, holt der Betrachter
///   sie mit [leicht] (#393).
/// - **mit [leicht]** gleich und nur sie.
Future<VideoPlayerController> videospieler(
  Sitzung sitzung,
  AssetData a, {
  VoidCallback? wandelt,
  bool Function()? abgebrochen,
  bool leicht = false,
}) async {
  final rel = a.trimmedRelativePath ?? a.relativePath;
  final hier = sitzung.paths.absolute(rel);
  if (!leicht && await hier.exists()) {
    final c = VideoPlayerController.file(File(hier.path));
    if (await _bereit(c)) return c;
  }
  final abgleich = sitzung.abgleich;
  final v = sitzung.verbindung;
  if (abgleich == null || v == null) throw StateError('ohne Server');
  final kopf = {'authorization': 'Bearer ${v.token}'};
  final pfad = 'api/v1/aufnahmen/${Uri.encodeComponent(a.id)}/abspielbar';

  // 200: liegt bereit, 202: entsteht gerade, sonst geht es nicht.
  Future<int?> frage() async {
    try {
      return (await abgleich.verbindung.anfrage(
        'GET',
        '$pfad?pruefen=1',
      )).statusCode;
    } on Object {
      return null;
    }
  }

  Future<VideoPlayerController?> leichteFassung() async {
    final c = VideoPlayerController.networkUrl(
      abgleich.verbindung.adresse(pfad),
      httpHeaders: kopf,
    );
    return await _bereit(c) ? c : null;
  }

  if (!leicht) {
    if (istSchweresVideo(a) && await frage() == 200) {
      if (await leichteFassung() case final c?) return c;
    }
    final direkt = VideoPlayerController.networkUrl(
      abgleich.verbindung.adresse(
        'api/v1/dateien/${rel.split('/').map(Uri.encodeComponent).join('/')}',
      ),
      httpHeaders: kopf,
    );
    if (await _bereit(direkt)) return direkt;
  }

  wandelt?.call();
  for (var i = 0; i < 900; i++) {
    if (abgebrochen?.call() ?? false) throw StateError('abgebrochen');
    final status = await frage();
    if (status == 200) {
      if (await leichteFassung() case final c?) return c;
      break;
    }
    if (status != 202) break;
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
