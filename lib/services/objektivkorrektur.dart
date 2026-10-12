import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Verzeichnungskorrektur aus den Daten, die Sony-Kameras selbst in jede
/// ARW-Datei schreiben – für Linux und Windows, wo es kein CIRAWFilter
/// gibt.
///
/// **Warum keine Objektivdatenbank.** Gemessen (#5): Unter macOS
/// korrigiert CIRAWFilter weder Canon-CR3 mit RF-S-Objektiv noch Apples
/// ProRAW-DNGs – bei ProRAW steckt die Korrektur schon in den Bilddaten,
/// eine Anweisungsliste (DNG-Opcodes) gibt es dort nicht. Korrigiert
/// werden Sony-ARW, und genau dafür braucht es keine Datenbank: Die
/// Kamera legt die Korrektur als Stützstellen in den Tag
/// `DistortionCorrParams` (0x7037 im Verzeichnis der Rohdaten) – dieselben
/// Daten, die darktable nutzt.
///
/// **Abgleich mit macOS** an zwei öffentlichen Beispieldateien
/// (raw.pixls.us, CC0; Sigma 30 mm und Sony E PZ 18-105 mm, tonnen- und
/// kissenförmig): Die Verschiebung, die CIRAWFilter anwendet, folgt der
/// Kurve aus diesen Stützstellen, Radius in halben Bilddiagonalen, mal
/// einem Maßstab je Bild. Nach dem Modell sinkt die mittlere Abweichung
/// zum macOS-Bild auf ein Neuntel. Den Maßstab wählt Apple so, dass keine
/// leeren Ränder entstehen ([SonyVerzeichnung.massstab]); bei der
/// kissenförmigen Datei schneidet Apple 1,4 % mehr ab als diese Regel.
/// Die Vignettierung korrigiert CIRAWFilter bei Sony nicht (gemessen:
/// ±0,02 Blenden auf allen Radien) – hier deshalb auch nicht.
class SonyVerzeichnung {
  SonyVerzeichnung(List<int> werte)
    : _faktoren = [for (final w in werte) 1 + w / 16384];

  /// Der Faktor je Stützstelle; Stützstelle i liegt bei i/(n−1) halben
  /// Diagonalen.
  final List<double> _faktoren;

  /// Um wie viel weiter aussen im unkorrigierten Bild der Punkt im
  /// Abstand [r] (halbe Diagonalen) liegt – linear zwischen den
  /// Stützstellen, jenseits der letzten fortgesetzt.
  double faktor(double r) {
    final n = _faktoren.length;
    final pos = r * (n - 1);
    final i = pos.floor().clamp(0, n - 2);
    final t = pos - i;
    return _faktoren[i] + (_faktoren[i + 1] - _faktoren[i]) * t;
  }

  /// Der Maßstab, mit dem das korrigierte Bild den Rahmen füllt.
  ///
  /// Ein Punkt am Rand des Ergebnisses kommt aus `Maßstab · faktor(r)`
  /// mal so weit aussen; das darf nicht über den Rand der Aufnahme
  /// hinausgehen. Der Rand des Ergebnisses überstreicht die Radien von
  /// der Mitte der kurzen Kante bis zur Ecke. Bei tonnenförmiger
  /// Verzeichnung bindet die Kantenmitte, bei kissenförmiger die Ecke.
  double massstab(int breite, int hoehe) {
    final halbeDiagonale = math.sqrt(breite * breite + hoehe * hoehe) / 2;
    final innen = math.min(breite, hoehe) / 2 / halbeDiagonale;
    var groesster = 0.0;
    for (var k = 0; k <= 200; k++) {
      final f = faktor(innen + (1 - innen) * k / 200);
      if (f > groesster) groesster = f;
    }
    return 1 / groesster;
  }
}

/// Liest die Verzeichnungsdaten aus einer Sony-ARW, oder `null`, wenn die
/// Datei keine trägt (andere Hersteller, ältere Kameras, Korrektur aus).
///
/// ARW ist TIFF. Der Tag steht im Unterverzeichnis der Rohdaten (0x014A,
/// SubIFDs); gesucht wird in allen Verzeichnissen der Kette und ihren
/// Unterverzeichnissen. Format: erster Wert = Zahl der Stützstellen, dann
/// die Stützstellen in Einheiten von 2⁻¹⁴, Rest Nullen.
SonyVerzeichnung? leseSonyVerzeichnung(Uint8List daten) {
  if (daten.length < 8) return null;
  final Endian ordnung;
  if (daten[0] == 0x49 && daten[1] == 0x49) {
    ordnung = Endian.little;
  } else if (daten[0] == 0x4D && daten[1] == 0x4D) {
    ordnung = Endian.big;
  } else {
    return null;
  }
  final b = ByteData.sublistView(daten);
  if (b.getUint16(2, ordnung) != 42) return null;

  final offen = <int>[b.getUint32(4, ordnung)];
  final besucht = <int>{};
  while (offen.isNotEmpty && besucht.length < 64) {
    final ifd = offen.removeLast();
    if (ifd <= 0 || ifd + 2 > daten.length || !besucht.add(ifd)) continue;
    final anzahl = b.getUint16(ifd, ordnung);
    if (anzahl > 4096 || ifd + 2 + anzahl * 12 + 4 > daten.length) continue;
    for (var e = 0; e < anzahl; e++) {
      final p = ifd + 2 + e * 12;
      final tag = b.getUint16(p, ordnung);
      final typ = b.getUint16(p + 2, ordnung);
      final menge = b.getUint32(p + 4, ordnung);
      if (tag == 0x014A && (typ == 4 || typ == 13)) {
        // SubIFDs: ein Versatz steht direkt im Eintrag, mehrere dahinter.
        if (menge == 1) {
          offen.add(b.getUint32(p + 8, ordnung));
        } else {
          final ziel = b.getUint32(p + 8, ordnung);
          for (var k = 0; k < menge && ziel + 4 * k + 4 <= daten.length; k++) {
            offen.add(b.getUint32(ziel + 4 * k, ordnung));
          }
        }
      } else if (tag == 0x7037 && (typ == 8 || typ == 3) && menge >= 3) {
        final ort = menge * 2 <= 4 ? p + 8 : b.getUint32(p + 8, ordnung);
        if (ort + menge * 2 > daten.length) return null;
        int wert(int k) => typ == 8
            ? b.getInt16(ort + 2 * k, ordnung)
            : b.getUint16(ort + 2 * k, ordnung);
        final n = wert(0);
        if (n < 2 || n > 16 || n + 1 > menge) return null;
        final werte = [for (var k = 1; k <= n; k++) wert(k)];
        // Lauter Nullen heisst: nichts zu korrigieren.
        if (werte.every((w) => w == 0)) return null;
        return SonyVerzeichnung(werte);
      }
    }
    offen.add(b.getUint32(ifd + 2 + anzahl * 12, ordnung));
  }
  return null;
}

/// Entzerrt [bild] nach [v]: Jeder Punkt des Ergebnisses holt seine Farbe
/// aus dem unkorrigierten Bild, `Maßstab · faktor(r)` mal so weit von der
/// Mitte, bilinear gemittelt.
img.Image entzerre(img.Image bild, SonyVerzeichnung v) {
  final breite = bild.width;
  final hoehe = bild.height;
  final quelle = bild
      .convert(numChannels: 3)
      .getBytes(order: img.ChannelOrder.rgb);
  final ziel = Uint8List(breite * hoehe * 3);
  final cx = (breite - 1) / 2;
  final cy = (hoehe - 1) / 2;
  final halbeDiagonale = math.sqrt(cx * cx + cy * cy);
  final s = v.massstab(breite, hoehe);
  for (var y = 0; y < hoehe; y++) {
    final dy = y - cy;
    for (var x = 0; x < breite; x++) {
      final dx = x - cx;
      final r = math.sqrt(dx * dx + dy * dy) / halbeDiagonale;
      final f = s * v.faktor(r);
      final qx = (cx + dx * f).clamp(0.0, breite - 1.001);
      final qy = (cy + dy * f).clamp(0.0, hoehe - 1.001);
      final x0 = qx.floor();
      final y0 = qy.floor();
      final fx = qx - x0;
      final fy = qy - y0;
      final i00 = (y0 * breite + x0) * 3;
      final i10 = i00 + 3;
      final i01 = i00 + breite * 3;
      final i11 = i01 + 3;
      final o = (y * breite + x) * 3;
      for (var c = 0; c < 3; c++) {
        final oben = quelle[i00 + c] + (quelle[i10 + c] - quelle[i00 + c]) * fx;
        final unten =
            quelle[i01 + c] + (quelle[i11 + c] - quelle[i01 + c]) * fx;
        ziel[o + c] = (oben + (unten - oben) * fy).round();
      }
    }
  }
  return img.Image.fromBytes(
    width: breite,
    height: hoehe,
    bytes: ziel.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
}
