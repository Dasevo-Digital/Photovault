import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../berechne.dart';
import 'jpeg_icc.dart';

/// Zuschnitt im unbeschnittenen entwickelten Bild, vor der abschließenden
/// Vierteldrehung. Masken behalten dadurch ihre Originalkoordinaten.
class Bildzuschnitt {
  const Bildzuschnitt._(
    this.links,
    this.oben,
    this.breite,
    this.hoehe,
    this.drehungen,
  );
  factory Bildzuschnitt({
    double links = 0,
    double oben = 0,
    double breite = 1,
    double hoehe = 1,
    int drehungen = 0,
  }) {
    if ([links, oben, breite, hoehe].any((x) => !x.isFinite) ||
        links < 0 ||
        oben < 0 ||
        breite <= 0 ||
        hoehe <= 0 ||
        links + breite > 1.0000001 ||
        oben + hoehe > 1.0000001 ||
        drehungen < 0 ||
        drehungen > 3) {
      throw const FormatException('pv_zuschnitt');
    }
    return Bildzuschnitt._(links, oben, breite, hoehe, drehungen);
  }
  static const ganz = Bildzuschnitt._(0, 0, 1, 1, 0);
  final double links, oben, breite, hoehe;
  final int drehungen;
  bool get istGanz =>
      links == 0 && oben == 0 && breite == 1 && hoehe == 1 && drehungen == 0;
  String? get json => istGanz
      ? null
      : jsonEncode({
          'l': links,
          'o': oben,
          'b': breite,
          'h': hoehe,
          'd': drehungen,
        });
  static Bildzuschnitt aus(String? json) {
    if (json == null) return ganz;
    if (json.length > 512) throw const FormatException('pv_zuschnitt');
    final j = jsonDecode(json) as Map;
    return Bildzuschnitt(
      links: (j['l'] as num).toDouble(),
      oben: (j['o'] as num).toDouble(),
      breite: (j['b'] as num).toDouble(),
      hoehe: (j['h'] as num).toDouble(),
      drehungen: j['d'] as int,
    );
  }
}

Future<Uint8List> schneideEntwicklung(
  Uint8List jpeg,
  Bildzuschnitt zuschnitt,
) async => zuschnitt.istGanz ? jpeg : berechne(_schneide, (jpeg, zuschnitt));

Uint8List _schneide((Uint8List, Bildzuschnitt) werte) {
  JpegIcc.masse(werte.$1, maxPixel: 40000000);
  final profil = JpegIcc.lesen(werte.$1);
  final bild = img.decodeJpg(werte.$1);
  if (bild == null || bild.width * bild.height > 40000000) {
    throw const FormatException('pv_zuschnitt_bild');
  }
  final z = werte.$2;
  final x = (z.links * bild.width).round().clamp(0, bild.width - 1);
  final y = (z.oben * bild.height).round().clamp(0, bild.height - 1);
  var aus = img.copyCrop(
    bild,
    x: x,
    y: y,
    width: (z.breite * bild.width).round().clamp(1, bild.width - x),
    height: (z.hoehe * bild.height).round().clamp(1, bild.height - y),
  );
  if (z.drehungen != 0) aus = img.copyRotate(aus, angle: z.drehungen * 90);
  aus.iccProfile = null;
  return JpegIcc.schreiben(
    Uint8List.fromList(img.encodeJpg(aus, quality: 95)),
    profil,
  );
}
