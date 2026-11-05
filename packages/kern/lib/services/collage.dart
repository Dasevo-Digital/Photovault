/// Collagen (#301): zwei bis neun Fotos in einer Vorlage, als ein neues
/// Foto – am Rechner, und am Server für Browser und Handy.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../berechne.dart';

/// So viele Fotos nimmt eine Collage.
const collageMindestens = 2;
const collageHoechstens = 9;

/// Ein Feld der Vorlage, in Anteilen der Fläche (0..1).
class Collagefeld {
  const Collagefeld(this.x, this.y, this.b, this.h);

  final double x;
  final double y;
  final double b;
  final double h;
}

/// Eine Anordnung für eine bestimmte Zahl von Fotos. Das erste Feld ist bei
/// den Vorlagen mit einem grossen Bild das grosse.
class Collagevorlage {
  const Collagevorlage(this.id, this.felder);

  /// `raster`, `reihe`, `stapel`, `gross_links` oder `gross_oben`.
  final String id;
  final List<Collagefeld> felder;
}

/// Das Format der fertigen Collage, in Pixeln.
enum Collageformat {
  quadrat(3000, 3000),
  quer(3600, 2400),
  hoch(2400, 3600),
  story(2160, 3840);

  const Collageformat(this.breite, this.hoehe);

  final int breite;
  final int hoehe;

  static Collageformat? namens(String? name) =>
      values.where((f) => f.name == name).firstOrNull;
}

/// [n] Felder auf [reihen] Reihen verteilt, die unteren bekommen den Rest:
/// 5 auf 2 → [2, 3].
List<int> _verteile(int n, int reihen) {
  final r = reihen.clamp(1, n);
  final je = n ~/ r;
  final rest = n % r;
  return [for (var i = 0; i < r; i++) je + (i >= r - rest ? 1 : 0)];
}

/// Reihen gleicher Höhe in der Fläche ab ([x0], [y0]) mit [b] × [h]; in
/// jeder Reihe sind die Felder gleich breit.
List<Collagefeld> _reihen(
  List<int> je, {
  double x0 = 0,
  double y0 = 0,
  double b = 1,
  double h = 1,
}) {
  final hoehe = h / je.length;
  return [
    for (var r = 0; r < je.length; r++)
      for (var s = 0; s < je[r]; s++)
        Collagefeld(x0 + s * b / je[r], y0 + r * hoehe, b / je[r], hoehe),
  ];
}

/// Die Vorlagen für [n] Fotos, die gewöhnlichste zuerst. Leer, wenn [n]
/// ausserhalb von [collageMindestens]..[collageHoechstens] liegt.
List<Collagevorlage> collagevorlagen(int n) {
  if (n < collageMindestens || n > collageHoechstens) return const [];
  final reihen = math.sqrt(n).round();
  final v = <Collagevorlage>[
    Collagevorlage('raster', _reihen(_verteile(n, reihen))),
  ];
  // Bei zwei Fotos ist das Raster schon eine Reihe.
  if (n > 2 && n <= 4) v.add(Collagevorlage('reihe', _reihen([n])));
  if (n <= 4) v.add(Collagevorlage('stapel', _reihen(List.filled(n, 1))));
  if (n >= 3) {
    final rest = n - 1;
    v
      ..add(
        Collagevorlage('gross_links', [
          const Collagefeld(0, 0, 0.6, 1),
          ..._reihen(
            _verteile(rest, rest <= 3 ? rest : math.sqrt(rest).ceil()),
            x0: 0.6,
            b: 0.4,
          ),
        ]),
      )
      ..add(
        Collagevorlage('gross_oben', [
          const Collagefeld(0, 0, 1, 0.6),
          ..._reihen(_verteile(rest, rest <= 4 ? 1 : 2), y0: 0.6, h: 0.4),
        ]),
      );
  }
  return v;
}

/// Die Vorlage [id] für [n] Fotos – sonst das Raster.
Collagevorlage collagevorlage(int n, String? id) {
  final alle = collagevorlagen(n);
  return alle.where((v) => v.id == id).firstOrNull ?? alle.first;
}

/// Was eine Collage braucht. Alles lässt sich an ein Isolate schicken.
class Collageauftrag {
  const Collageauftrag({
    required this.bilder,
    required this.vorlage,
    required this.breite,
    required this.hoehe,
    this.abstand = 0.01,
    this.ecken = 0,
    this.hintergrund = 0xFFFFFF,
    this.qualitaet = 90,
    this.zeit,
  });

  /// Die Fotos als JPEG (oder PNG), in der Reihenfolge der Felder.
  final List<Uint8List> bilder;
  final Collagevorlage vorlage;
  final int breite;
  final int hoehe;

  /// Lücke zwischen den Feldern und am Rand, als Anteil der kürzeren
  /// Seite (0 bis 0,05).
  final double abstand;

  /// Rundung der Ecken, als Anteil der kürzeren Seite (0 bis 0,1).
  final double ecken;

  /// Die Farbe der Lücken als 0xRRGGBB.
  final int hintergrund;
  final int qualitaet;

  /// Wann die Collage aufgenommen sein soll – so steht sie in der
  /// Zeitleiste bei ihren Fotos. Ohne: jetzt.
  final DateTime? zeit;

  /// Wie gross ein Quellbild höchstens sein muss: die längere Seite des
  /// grössten Felds.
  int get kante {
    var k = 1.0;
    for (final f in vorlage.felder) {
      k = math.max(k, math.max(f.b * breite, f.h * hoehe));
    }
    return k.ceil();
  }
}

/// Zeichnet die Collage in einem eigenen Isolate und gibt das JPEG.
Future<Uint8List> zeichneCollage(Collageauftrag a) =>
    berechne(zeichneCollageJetzt, a);

/// Wie [zeichneCollage], im selben Isolate – für Tests.
Uint8List zeichneCollageJetzt(Collageauftrag a) {
  final w = a.breite;
  final h = a.hoehe;
  final kurz = math.min(w, h);
  final luecke = (a.abstand.clamp(0, 0.05) * kurz).round();
  final radius = (a.ecken.clamp(0, 0.1) * kurz).round();
  final farbe = img.ColorRgb8(
    (a.hintergrund >> 16) & 0xFF,
    (a.hintergrund >> 8) & 0xFF,
    a.hintergrund & 0xFF,
  );
  final bild = img.Image(width: w, height: h);
  img.fill(bild, color: farbe);
  // Aussen dieselbe Lücke wie zwischen den Feldern.
  final iw = w - 2 * luecke;
  final ih = h - 2 * luecke;
  final halb = luecke / 2;
  for (var i = 0; i < a.vorlage.felder.length && i < a.bilder.length; i++) {
    final f = a.vorlage.felder[i];
    final links = luecke + f.x * iw + (f.x > 0.001 ? halb : 0);
    final rechts = luecke + (f.x + f.b) * iw - (f.x + f.b < 0.999 ? halb : 0);
    final oben = luecke + f.y * ih + (f.y > 0.001 ? halb : 0);
    final unten = luecke + (f.y + f.h) * ih - (f.y + f.h < 0.999 ? halb : 0);
    final x0 = links.round();
    final y0 = oben.round();
    final zw = rechts.round() - x0;
    final zh = unten.round() - y0;
    if (zw <= 0 || zh <= 0) continue;
    final roh = img.decodeImage(a.bilder[i]);
    if (roh == null) continue;
    final q = img.bakeOrientation(roh);
    // Füllen und mittig zuschneiden, wie eine Kachel.
    final massstab = math.max(zw / q.width, zh / q.height);
    final cw = (zw / massstab).round().clamp(1, q.width);
    final ch = (zh / massstab).round().clamp(1, q.height);
    final zuschnitt = img.copyCrop(
      q,
      x: (q.width - cw) ~/ 2,
      y: (q.height - ch) ~/ 2,
      width: cw,
      height: ch,
    );
    final passend = img.copyResize(
      zuschnitt,
      width: zw,
      height: zh,
      interpolation: massstab < 1
          ? img.Interpolation.average
          : img.Interpolation.linear,
    );
    img.compositeImage(bild, passend, dstX: x0, dstY: y0);
    final r = math.min(radius, math.min(zw, zh) ~/ 2);
    if (r > 0) _runde(bild, x0, y0, zw, zh, r, farbe);
  }
  final jpeg = img.encodeJpg(bild, quality: a.qualitaet.clamp(1, 100));
  return mitAufnahmezeit(jpeg, a.zeit ?? DateTime.now());
}

/// Übermalt die vier Ecken des Felds ausserhalb des Radius [r].
void _runde(img.Image bild, int x0, int y0, int w, int h, int r, img.Color f) {
  final rr = r * r;
  for (var dy = 0; dy < r; dy++) {
    for (var dx = 0; dx < r; dx++) {
      final ax = r - dx - 0.5;
      final ay = r - dy - 0.5;
      if (ax * ax + ay * ay <= rr) continue;
      bild
        ..setPixel(x0 + dx, y0 + dy, f)
        ..setPixel(x0 + w - 1 - dx, y0 + dy, f)
        ..setPixel(x0 + dx, y0 + h - 1 - dy, f)
        ..setPixel(x0 + w - 1 - dx, y0 + h - 1 - dy, f);
    }
  }
}

/// Schreibt [zeit] als Aufnahmezeit in das JPEG – sonst stünde die
/// Collage beim Einlesen am Tag, an dem die Datei entstand.
Uint8List mitAufnahmezeit(Uint8List jpeg, DateTime zeit) {
  final t = zeit.toLocal();
  String zwei(int n) => n.toString().padLeft(2, '0');
  final text =
      '${t.year.toString().padLeft(4, '0')}:${zwei(t.month)}:${zwei(t.day)} '
      '${zwei(t.hour)}:${zwei(t.minute)}:${zwei(t.second)}';
  try {
    final exif = img.ExifData();
    exif.imageIfd.orientation = 1;
    exif.imageIfd['DateTime'] = img.IfdValueAscii(text);
    exif.imageIfd['Software'] = img.IfdValueAscii('Photo Vault Collage');
    exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(text);
    exif.exifIfd['DateTimeDigitized'] = img.IfdValueAscii(text);
    return img.injectJpgExif(jpeg, exif) ?? jpeg;
  } catch (_) {
    return jpeg;
  }
}

/// Der Dateiname einer neuen Collage: der Tag ihres jüngsten Fotos und
/// eine Zahl, damit zwei Collagen desselben Tags sich nicht treffen.
String collageDateiname(DateTime zeit) {
  final t = zeit.toLocal();
  String zwei(int n) => n.toString().padLeft(2, '0');
  return 'Collage ${t.year}-${zwei(t.month)}-${zwei(t.day)} '
      '${DateTime.now().millisecondsSinceEpoch % 100000}.jpg';
}

/// Liest „#rrggbb“ als 0xRRGGBB – sonst Weiss.
int collagefarbe(String? text) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(text ?? '');
  return m == null ? 0xFFFFFF : int.parse(m[1]!, radix: 16);
}
