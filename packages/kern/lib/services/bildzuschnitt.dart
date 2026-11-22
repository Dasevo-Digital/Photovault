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

  /// Rechnet einen Punkt des **angezeigten** Bildes (nach Zuschnitt und
  /// Drehung, je 0..1) in das unbeschnittene Bild um, in dem Masken
  /// gespeichert sind.
  ///
  /// Die Drehung ist dieselbe wie in [schneideBild]: [drehungen] Viertel
  /// im Uhrzeigersinn. Punkte ausserhalb von 0..1 bleiben gültig und
  /// landen ausserhalb des Zuschnitts.
  (double, double) insOriginal(double x, double y) {
    final (zx, zy) = switch (drehungen) {
      1 => (y, 1 - x),
      2 => (1 - x, 1 - y),
      3 => (1 - y, x),
      _ => (x, y),
    };
    return (links + zx * breite, oben + zy * hoehe);
  }

  /// Die Umkehrung von [insOriginal]: wo ein Punkt des unbeschnittenen
  /// Bildes in der Anzeige liegt.
  (double, double) inDieAnzeige(double x, double y) {
    final zx = (x - links) / breite;
    final zy = (y - oben) / hoehe;
    return switch (drehungen) {
      1 => (1 - zy, zx),
      2 => (1 - zx, 1 - zy),
      3 => (zy, 1 - zx),
      _ => (zx, zy),
    };
  }

  /// Breite und Höhe des angezeigten Bildes, aus denen des unbeschnittenen
  /// (in beliebiger Einheit). Bei einer ungeraden Zahl von Vierteldrehungen
  /// tauschen sie die Rollen.
  (double, double) masseDerAnzeige(double bildBreite, double bildHoehe) {
    final b = bildBreite * breite;
    final h = bildHoehe * hoehe;
    return drehungen.isOdd ? (h, b) : (b, h);
  }

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
  final aus = schneideBild(bild, werte.$2);
  aus.iccProfile = null;
  return JpegIcc.schreiben(
    Uint8List.fromList(img.encodeJpg(aus, quality: 95)),
    profil,
  );
}

/// Der Ausschnitt in Bildpunkten – auf einen Punkt genau so gerundet, wie
/// [schneideBild] schneidet.
({int x, int y, int breite, int hoehe}) _ausschnitt(
  Bildzuschnitt z,
  int breite,
  int hoehe,
) {
  final x = (z.links * breite).round().clamp(0, breite - 1);
  final y = (z.oben * hoehe).round().clamp(0, hoehe - 1);
  return (
    x: x,
    y: y,
    breite: (z.breite * breite).round().clamp(1, breite - x),
    hoehe: (z.hoehe * hoehe).round().clamp(1, hoehe - y),
  );
}

/// Schneidet [bild] zu und dreht es – die Rechnung hinter jeder
/// zugeschnittenen Entwicklung, auf jedem Renderweg.
img.Image schneideBild(img.Image bild, Bildzuschnitt z) {
  if (z.istGanz) return bild;
  final a = _ausschnitt(z, bild.width, bild.height);
  var aus = img.copyCrop(
    bild,
    x: a.x,
    y: a.y,
    width: a.breite,
    height: a.hoehe,
  );
  if (z.drehungen != 0) aus = img.copyRotate(aus, angle: z.drehungen * 90);
  return aus;
}

/// Die Umkehrung von [schneideBild] für eine Maske, die auf dem
/// angezeigten (zugeschnittenen, gedrehten) Bild entstanden ist: Sie wird
/// zurückgedreht und an ihre Stelle im unbeschnittenen Bild gelegt. Was
/// ausserhalb des Zuschnitts liegt, bleibt schwarz, also unmaskiert.
///
/// Masken werden immer über das ganze unbeschnittene Bild gelegt; eine
/// Maske im Format des Ausschnitts träfe die falsche Stelle.
img.Image maskeInsOriginal(img.Image maske, Bildzuschnitt z) {
  if (z.istGanz) return maske;
  final gedreht = z.drehungen == 0
      ? maske
      : img.copyRotate(maske, angle: (4 - z.drehungen) * 90);
  final breite = (gedreht.width / z.breite).round().clamp(1, 1 << 15);
  final hoehe = (gedreht.height / z.hoehe).round().clamp(1, 1 << 15);
  final a = _ausschnitt(z, breite, hoehe);
  final teil = a.breite == gedreht.width && a.hoehe == gedreht.height
      ? gedreht
      : img.copyResize(
          gedreht,
          width: a.breite,
          height: a.hoehe,
          interpolation: img.Interpolation.nearest,
        );
  final aus = img.Image(
    width: breite,
    height: hoehe,
    numChannels: maske.numChannels,
  );
  for (var y = 0; y < a.hoehe; y++) {
    for (var x = 0; x < a.breite; x++) {
      aus.setPixel(a.x + x, a.y + y, teil.getPixel(x, y));
    }
  }
  return aus;
}
