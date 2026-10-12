/// **Motion Photos: das Video im JPEG.**
///
/// Apple legt ein Live Photo als zwei Dateien ab, ein HEIC und ein MOV
/// gleichen Namens; die App verknüpft sie seit Langem. Google (Pixel) und
/// Samsung hängen das Video stattdessen **hinten an das JPEG** an. Für
/// jedes andere Programm ist die Datei ein gewöhnliches Foto – der Film
/// darin bleibt unsichtbar. digiKam liest sie seit 9.1.
///
/// Wo das Video anfängt, steht je nach Hersteller und Jahrgang an einer
/// anderen Stelle:
///
/// * **Google, neu** (Camera XMP, seit 2021): Im XMP steht ein
///   `Container:Directory`; der Eintrag mit `Item:Semantic="MotionPhoto"`
///   nennt die Länge des Videos (`Item:Length`), gezählt vom Dateiende.
/// * **Google, alt** (MicroVideo): `GCamera:MicroVideoOffset` – ebenfalls
///   der Abstand vom Dateiende.
/// * **Samsung:** Vor dem Video steht die Kennung `MotionPhoto_Data`.
///
/// Was davon auch gefunden wird: Erst wenn an der Stelle ein MP4 beginnt
/// (`ftyp` vier Bytes hinter dem Anfang), gilt es. Eine Längenangabe, die
/// nicht stimmt – nach einer Bearbeitung, die das JPEG neu geschrieben
/// hat –, liefert sonst ein kaputtes Video.
library;

import 'dart:convert';
import 'dart:typed_data';

/// So weit vorn wird nach dem XMP gesucht. Es steht im ersten
/// APP1-Abschnitt, und der ist höchstens 64 KB lang.
const motionPhotoKopf = 64 * 1024;

final _samsung = ascii.encode('MotionPhoto_Data');
final _ftyp = ascii.encode('ftyp');

/// So viel vom Dateiende wird angesehen: Samsung schreibt ans Ende ein
/// Verzeichnis seiner Anhänge, in dem der Name `MotionPhoto_Data` steht.
const motionPhotoEnde = 4 * 1024;

/// Ob Anfang ([kopf]) oder Ende ([ende]) einer Datei überhaupt nach Motion
/// Photo aussehen – damit nicht jedes JPEG ganz gelesen werden muss.
bool siehtNachMotionPhotoAus(Uint8List kopf, Uint8List ende) {
  bool enthaelt(Uint8List b) {
    final text = latin1.decode(b, allowInvalid: true);
    return text.contains('MotionPhoto') || text.contains('MicroVideo');
  }

  return enthaelt(kopf) || enthaelt(ende);
}

/// Wo in [datei] das eingebettete Video beginnt, oder `null`.
int? motionPhotoAnfang(Uint8List datei) {
  final kopf = latin1.decode(
    datei.sublist(
      0,
      datei.length < motionPhotoKopf ? datei.length : motionPhotoKopf,
    ),
    allowInvalid: true,
  );

  // Google, neu: die Länge des Eintrags „MotionPhoto“ im Verzeichnis.
  // Die Reihenfolge der Attribute ist nicht festgelegt; gesucht wird im
  // Element, das die Semantik trägt.
  final eintrag = RegExp(
    r'<Container:Item\b[^>]*Item:Semantic="MotionPhoto"[^>]*>',
  ).firstMatch(kopf);
  if (eintrag != null) {
    final laenge = RegExp(r'Item:Length="(\d+)"').firstMatch(eintrag[0]!);
    if (laenge != null) {
      final anfang = datei.length - int.parse(laenge[1]!);
      if (_istMp4(datei, anfang)) return anfang;
    }
  }

  // Google, alt.
  final versatz = RegExp(r'MicroVideoOffset(?:="|>)(\d+)').firstMatch(kopf);
  if (versatz != null) {
    final anfang = datei.length - int.parse(versatz[1]!);
    if (_istMp4(datei, anfang)) return anfang;
  }

  // Samsung: hinter der Kennung. Sie steht zweimal in der Datei – vor dem
  // Video und noch einmal im Verzeichnis am Dateiende. Von hinten
  // gesucht, gilt die erste Stelle, hinter der wirklich ein MP4 beginnt.
  var bis = datei.length;
  while (true) {
    final kennung = _sucheRueckwaerts(datei, _samsung, bis);
    if (kennung == null) return null;
    final anfang = kennung + _samsung.length;
    if (_istMp4(datei, anfang)) return anfang;
    bis = kennung;
  }
}

bool _istMp4(Uint8List d, int anfang) {
  if (anfang <= 0 || anfang + 8 > d.length) return false;
  for (var i = 0; i < 4; i++) {
    if (d[anfang + 4 + i] != _ftyp[i]) return false;
  }
  return true;
}

/// Sucht [muster] von hinten – die Kennung steht hinter dem Bild, also
/// meist näher am Ende als am Anfang.
int? _sucheRueckwaerts(Uint8List d, List<int> muster, int bis) {
  outer:
  for (var i = bis - muster.length; i >= 0; i--) {
    for (var j = 0; j < muster.length; j++) {
      if (d[i + j] != muster[j]) continue outer;
    }
    return i;
  }
  return null;
}
