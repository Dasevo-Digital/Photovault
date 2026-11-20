import 'dart:typed_data';

/// ICC-Profile in JPEG bestehen aus nummerierten APP2-Teilen. Andere
/// Metadaten und die komprimierten Bilddaten bleiben hier unverändert.
class JpegIcc {
  static const maxProfil = 8 * 1024 * 1024;
  static const _kennung = <int>[73, 67, 67, 95, 80, 82, 79, 70, 73, 76, 69, 0];

  static Iterable<({int start, int ende, int marker, int daten})> _segmente(
    Uint8List bytes,
  ) sync* {
    if (bytes.length < 4 || bytes[0] != 255 || bytes[1] != 216) {
      throw const FormatException('pv_jpeg');
    }
    var i = 2;
    while (i < bytes.length) {
      final start = i;
      if (bytes[i++] != 255) throw const FormatException('pv_jpeg_marker');
      while (i < bytes.length && bytes[i] == 255) {
        i++;
      }
      if (i >= bytes.length) throw const FormatException('pv_jpeg_marker');
      final marker = bytes[i++];
      if (marker == 217) return;
      if (marker == 0 ||
          marker == 216 ||
          marker == 1 ||
          (marker >= 208 && marker <= 215)) {
        throw const FormatException('pv_jpeg_marker');
      }
      if (i + 2 > bytes.length) throw const FormatException('pv_jpeg_laenge');
      final n = (bytes[i] << 8) | bytes[i + 1];
      if (n < 2 || n > bytes.length - i) {
        throw const FormatException('pv_jpeg_laenge');
      }
      yield (start: start, ende: i + n, marker: marker, daten: i + 2);
      if (marker == 218) return;
      i += n;
    }
  }

  static bool _istIcc(Uint8List bytes, int start, int ende) {
    if (ende - start < _kennung.length) return false;
    for (var i = 0; i < _kennung.length; i++) {
      if (bytes[start + i] != _kennung[i]) return false;
    }
    return true;
  }

  static Uint8List? lesen(Uint8List bytes) {
    final teile = <int, Uint8List>{};
    var anzahl = 0, laenge = 0;
    for (final s in _segmente(bytes)) {
      if (s.marker != 226 || !_istIcc(bytes, s.daten, s.ende)) continue;
      if (s.ende - s.daten < 14) throw const FormatException('pv_icc_teile');
      final nummer = bytes[s.daten + 12], gesamt = bytes[s.daten + 13];
      if (gesamt == 0 ||
          nummer == 0 ||
          nummer > gesamt ||
          (anzahl != 0 && anzahl != gesamt) ||
          teile.containsKey(nummer)) {
        throw const FormatException('pv_icc_teile');
      }
      anzahl = gesamt;
      final teil = Uint8List.sublistView(bytes, s.daten + 14, s.ende);
      laenge += teil.length;
      if (laenge > maxProfil) throw const FormatException('pv_icc_groesse');
      teile[nummer] = teil;
    }
    if (anzahl == 0) return null;
    if (teile.length != anzahl) throw const FormatException('pv_icc_teile');
    final aus = BytesBuilder(copy: false);
    for (var i = 1; i <= anzahl; i++) {
      aus.add(teile[i]!);
    }
    return aus.takeBytes();
  }

  static Uint8List schreiben(Uint8List bytes, Uint8List? profil) {
    if (profil != null && (profil.isEmpty || profil.length > maxProfil)) {
      throw const FormatException('pv_icc_groesse');
    }
    final aus = BytesBuilder(copy: false)..add(bytes.sublist(0, 2));
    if (profil != null) {
      const portion = 65519;
      final gesamt = (profil.length + portion - 1) ~/ portion;
      for (var i = 0; i < gesamt; i++) {
        final start = i * portion,
            ende = ((i + 1) * portion).clamp(0, profil.length);
        final n = ende - start + 16;
        aus.add([255, 226, n >> 8, n & 255, ..._kennung, i + 1, gesamt]);
        aus.add(Uint8List.sublistView(profil, start, ende));
      }
    }
    var kopiert = 2;
    for (final s in _segmente(bytes)) {
      if (s.marker == 226 && _istIcc(bytes, s.daten, s.ende)) {
        aus.add(Uint8List.sublistView(bytes, kopiert, s.start));
        kopiert = s.ende;
      }
    }
    aus.add(Uint8List.sublistView(bytes, kopiert));
    return aus.takeBytes();
  }

  static ({int breite, int hoehe}) masse(
    Uint8List bytes, {
    int maxPixel = 32000000,
  }) {
    if (bytes.length > 128 * 1024 * 1024) {
      throw const FormatException('pv_jpeg_groesse');
    }
    for (final s in _segmente(bytes)) {
      if (s.marker >= 192 &&
          s.marker <= 207 &&
          ![196, 200, 204].contains(s.marker)) {
        if (s.ende - s.daten < 6) throw const FormatException('pv_jpeg_masse');
        final h = (bytes[s.daten + 1] << 8) | bytes[s.daten + 2];
        final w = (bytes[s.daten + 3] << 8) | bytes[s.daten + 4];
        if (w == 0 || h == 0 || w * h > maxPixel) {
          throw const FormatException('pv_jpeg_masse');
        }
        return (breite: w, hoehe: h);
      }
    }
    throw const FormatException('pv_jpeg_masse');
  }
}
