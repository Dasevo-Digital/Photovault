import 'dart:typed_data';

/// Ein JPEG ohne Ortsangaben, sonst Byte für Byte wie [jpeg] (#463).
///
/// **Wofür.** Ein Konto, dem ein anderes ein Album oder die ganze Bibliothek
/// zeigt, bekommt die Fotos ohne Ort, solange der Besitzer es nicht anders
/// eingestellt hat. Die Ansicht eines gewöhnlichen JPEGs ist das Original
/// selbst, ältere Miniaturen und Vorschauen tragen dessen EXIF (bis 3.67.5,
/// siehe `jpegOhneAngaben` im Kern). Neu zu rechnen hiesse, jedes Bild zu
/// dekodieren – bei einer ganzen Bibliothek Tausende, nur um einen Block
/// Angaben zu entfernen. Hier wird nichts dekodiert: Drehung, Farbprofil,
/// Aufnahmezeit und Kamera bleiben, wie sie sind.
///
/// **Was geht.**
/// - Der GPS-Teil des EXIF: jeder Eintrag samt seinen Werten genullt und
///   die Anzahl auf null gesetzt. Wer ihn liest, findet ihn leer.
/// - XMP (auch das erweiterte): Es kann den Ort noch einmal tragen, etwa
///   nach Lightroom.
/// - Photoshop/IPTC (APP13): Stadt, Land und Ortsangaben in Worten.
/// - Weitere Bilder hinter dem ersten (MPF, etwa die Tiefen- oder
///   HDR-Karte eines Telefons) und alles nach dessen Ende: Sie haben
///   eigene Anhänge, die hier niemand prüft.
///
/// Wirft [FormatException], wenn [jpeg] kein lesbares JPEG ist; der Aufrufer
/// wandelt es dann ganz neu.
Uint8List jpegOhneOrt(Uint8List jpeg) {
  final ein = jpeg;
  if (ein.length < 4 || ein[0] != 0xFF || ein[1] != 0xD8) {
    throw const FormatException('kein JPEG');
  }
  final aus = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  var i = 2;
  while (true) {
    if (i + 2 > ein.length || ein[i] != 0xFF) {
      throw const FormatException('Marker erwartet');
    }
    final marker = ein[i + 1];
    if (marker == 0xFF) {
      // Füllbyte vor einem Marker.
      i++;
      continue;
    }
    if (marker == 0xD9) {
      aus.add(const [0xFF, 0xD9]);
      return aus.takeBytes();
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      aus.add(Uint8List.sublistView(ein, i, i + 2));
      i += 2;
      continue;
    }
    if (i + 4 > ein.length) {
      throw const FormatException('Segment abgeschnitten');
    }
    final laenge = (ein[i + 2] << 8) | ein[i + 3];
    final ende = i + 2 + laenge;
    if (laenge < 2 || ende > ein.length) {
      throw const FormatException('Segment zu lang');
    }
    if (marker == 0xDA) {
      // Ab dem ersten Scan bis zum Ende des ersten Bildes: alles, wie es
      // ist – auch weitere Scans eines progressiven JPEGs. Was danach
      // kommt, bleibt draussen.
      final schluss = _endeDesBildes(ein, i);
      aus.add(Uint8List.sublistView(ein, i, schluss));
      return aus.takeBytes();
    }
    final segment = Uint8List.sublistView(ein, i, ende);
    if (marker == 0xE1 && _beginntMit(ein, i + 4, _exif)) {
      final kopie = Uint8List.fromList(segment);
      _leereGps(Uint8List.sublistView(kopie, 4 + _exif.length));
      aus.add(kopie);
    } else if (!_weglassen(ein, i, marker)) {
      aus.add(segment);
    }
    i = ende;
  }
}

const _exif = [0x45, 0x78, 0x69, 0x66, 0, 0]; // „Exif\0\0“
final _xmp = 'http://ns.adobe.com/xap/1.0/\u0000'.codeUnits;
final _xmpErweitert = 'http://ns.adobe.com/xmp/extension/\u0000'.codeUnits;
const _mpf = [0x4D, 0x50, 0x46, 0]; // „MPF\0“

/// XMP, MPF und Photoshop/IPTC – was den Ort tragen oder auf weitere
/// Bilder zeigen kann.
bool _weglassen(Uint8List b, int i, int marker) => switch (marker) {
  0xE1 => _beginntMit(b, i + 4, _xmp) || _beginntMit(b, i + 4, _xmpErweitert),
  0xE2 => _beginntMit(b, i + 4, _mpf),
  0xED => true,
  _ => false,
};

bool _beginntMit(Uint8List b, int ab, List<int> vorne) {
  if (ab + vorne.length > b.length) return false;
  for (var k = 0; k < vorne.length; k++) {
    if (b[ab + k] != vorne[k]) return false;
  }
  return true;
}

/// Hinter dem Marker EOI des Bildes, dessen erster Scan bei [sos] beginnt.
int _endeDesBildes(Uint8List b, int sos) {
  var i = sos;
  while (true) {
    // [i] steht auf einem Marker. Füllbytes 0xFF davor überspringen.
    while (i + 1 < b.length && b[i] == 0xFF && b[i + 1] == 0xFF) {
      i++;
    }
    if (i + 2 > b.length || b[i] != 0xFF) {
      throw const FormatException('ohne Ende');
    }
    final marker = b[i + 1];
    if (marker == 0xD9) return i + 2;
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    // Ein Segment mit Länge: SOS, DHT, DQT, DRI, COM …
    if (i + 4 > b.length) throw const FormatException('ohne Ende');
    final laenge = (b[i + 2] << 8) | b[i + 3];
    if (laenge < 2) throw const FormatException('Segment zu kurz');
    i += 2 + laenge;
    if (i > b.length) throw const FormatException('Segment zu lang');
    if (marker == 0xDA) i = _naechsterMarker(b, i);
  }
}

/// Der nächste Marker in entropiekodierten Daten ab [ab]: 0xFF 0x00 ist ein
/// Datenbyte, 0xFF 0xD0–D7 ein Neustart, alles andere ein Marker.
int _naechsterMarker(Uint8List b, int ab) {
  var i = ab;
  while (i + 1 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final m = b[i + 1];
    if (m == 0x00 || (m >= 0xD0 && m <= 0xD7)) {
      i += 2;
    } else if (m == 0xFF) {
      i++;
    } else {
      return i;
    }
  }
  throw const FormatException('ohne Ende');
}

/// Grösse eines Werts je TIFF-Typ in Bytes.
const _typgroesse = {
  1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, //
  12: 8, 13: 4,
};

/// Leert in [t] (TIFF-Kopf und IFDs des EXIF, veränderbar) den GPS-Teil.
void _leereGps(Uint8List t) {
  if (t.length < 8) return;
  final bool klein;
  if (t[0] == 0x49 && t[1] == 0x49) {
    klein = true;
  } else if (t[0] == 0x4D && t[1] == 0x4D) {
    klein = false;
  } else {
    return;
  }
  int u16(int o) => klein ? t[o] | (t[o + 1] << 8) : (t[o] << 8) | t[o + 1];
  int u32(int o) => klein
      ? t[o] | (t[o + 1] << 8) | (t[o + 2] << 16) | (t[o + 3] << 24)
      : (t[o] << 24) | (t[o + 1] << 16) | (t[o + 2] << 8) | t[o + 3];
  final ifd0 = u32(4);
  if (ifd0 + 2 > t.length) return;
  final anzahl = u16(ifd0);
  for (var k = 0; k < anzahl; k++) {
    final e = ifd0 + 2 + 12 * k;
    if (e + 12 > t.length) return;
    if (u16(e) != 0x8825) continue;
    final gps = u32(e + 8);
    if (gps + 2 > t.length) return;
    final n = u16(gps);
    for (var g = 0; g < n; g++) {
      final ge = gps + 2 + 12 * g;
      if (ge + 12 > t.length) break;
      final groesse = (_typgroesse[u16(ge + 2)] ?? 1) * u32(ge + 4);
      if (groesse > 4) {
        final wert = u32(ge + 8);
        if (wert >= 0 && wert + groesse <= t.length) {
          t.fillRange(wert, wert + groesse, 0);
        }
      }
      t.fillRange(ge, ge + 12, 0);
    }
    // Keine Einträge mehr; dahinter steht, wo es welche gab, nur noch Null
    // – also auch kein Verweis auf ein weiteres Verzeichnis.
    t[gps] = 0;
    t[gps + 1] = 0;
  }
}
