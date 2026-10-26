/// Erkennen und Ausschneiden mehrerer Papierfotos aus einem Flachbettscan.
/// Die Quelldatei wird nie verändert; importiert werden erst die
/// ausdrücklich bestätigten Ausschnitte – aus PNG, TIFF und BMP verlustfrei
/// als PNG, aus JPEG als JPEG in hoher Qualität (siehe [scanVerlustfrei]).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class ScanBereich {
  const ScanBereich({
    required this.x,
    required this.y,
    required this.breite,
    required this.hoehe,
  });

  final int x;
  final int y;
  final int breite;
  final int hoehe;
}

class ScanVorschau {
  const ScanVorschau(this.bereich, this.jpeg);

  final ScanBereich bereich;
  final Uint8List jpeg;
}

class ScanAnalyse {
  const ScanAnalyse({
    required this.breite,
    required this.hoehe,
    required this.vorschauen,
  });

  final int breite;
  final int hoehe;
  final List<ScanVorschau> vorschauen;
}

/// Findet durchgehende Flächen, die sich vom an den vier Ecken gemessenen
/// Scannerhintergrund unterscheiden. Lange Hintergrundfugen teilen den
/// Scan rekursiv; damit funktionieren Zeilen, Spalten und gemischte
/// Anordnungen, ohne Bildinhalte anhand von Motiven zu bewerten.
List<ScanBereich> erkenneScanBereiche(img.Image quelle) {
  if (quelle.width < 2 || quelle.height < 2) return const [];
  const maxKante = 1000;
  final faktor = math.min(
    1.0,
    maxKante / math.max(quelle.width, quelle.height),
  );
  final bild = faktor == 1
      ? quelle
      : img.copyResize(
          quelle,
          width: math.max(1, (quelle.width * faktor).round()),
          height: math.max(1, (quelle.height * faktor).round()),
        );

  final hintergrund = _eckfarbe(bild);
  final maske = Uint8List(bild.width * bild.height);
  var anzahl = 0;
  for (var y = 0; y < bild.height; y++) {
    for (var x = 0; x < bild.width; x++) {
      final pixel = bild.getPixel(x, y);
      final abstand = math.sqrt(
        math.pow(pixel.r - hintergrund.r, 2) +
            math.pow(pixel.g - hintergrund.g, 2) +
            math.pow(pixel.b - hintergrund.b, 2),
      );
      if (abstand >= 28) {
        maske[y * bild.width + x] = 1;
        anzahl++;
      }
    }
  }
  if (anzahl < bild.width * bild.height * 0.002) {
    return [
      ScanBereich(x: 0, y: 0, breite: quelle.width, hoehe: quelle.height),
    ];
  }

  final gesamt = _inhaltBegrenzen(
    maske,
    bild.width,
    _Rechteck(0, 0, bild.width, bild.height),
  );
  if (gesamt == null) return const [];
  final teile = <_Rechteck>[];
  _teileRekursiv(maske, bild.width, gesamt, teile, 0);
  final sx = quelle.width / bild.width;
  final sy = quelle.height / bild.height;
  final rand = math.max(1, (math.min(bild.width, bild.height) * 0.004).round());
  final ergebnis = <ScanBereich>[];
  for (final teil in teile) {
    final sauber = _inhaltBegrenzen(maske, bild.width, teil) ?? teil;
    final x0 = math.max(0, sauber.x - rand);
    final y0 = math.max(0, sauber.y - rand);
    final x1 = math.min(bild.width, sauber.rechts + rand);
    final y1 = math.min(bild.height, sauber.unten + rand);
    if ((x1 - x0) * (y1 - y0) < bild.width * bild.height * 0.01) continue;
    ergebnis.add(
      ScanBereich(
        x: (x0 * sx).floor(),
        y: (y0 * sy).floor(),
        breite: math.min(quelle.width, (x1 * sx).ceil()) - (x0 * sx).floor(),
        hoehe: math.min(quelle.height, (y1 * sy).ceil()) - (y0 * sy).floor(),
      ),
    );
  }
  ergebnis.sort((a, b) {
    final gleicheZeile = (a.y - b.y).abs() < math.min(a.hoehe, b.hoehe) * 0.5;
    if (gleicheZeile) return a.x.compareTo(b.x);
    final zeile = a.y.compareTo(b.y);
    return zeile == 0 ? a.x.compareTo(b.x) : zeile;
  });
  return ergebnis.isEmpty
      ? [ScanBereich(x: 0, y: 0, breite: quelle.width, hoehe: quelle.height)]
      : ergebnis;
}

ScanAnalyse analysiereScan(Uint8List bytes) {
  final quelle = img.decodeImage(bytes);
  if (quelle == null) throw const FormatException('Bild nicht lesbar');
  final bereiche = erkenneScanBereiche(quelle);
  return ScanAnalyse(
    breite: quelle.width,
    hoehe: quelle.height,
    vorschauen: [
      for (final bereich in bereiche)
        ScanVorschau(
          bereich,
          Uint8List.fromList(
            img.encodeJpg(
              _verkleinere(rendereScanBereich(quelle, bereich)),
              quality: 78,
            ),
          ),
        ),
    ],
  );
}

img.Image rendereScanBereich(
  img.Image quelle,
  ScanBereich bereich, {
  int vierteldrehungen = 0,
}) {
  var ausschnitt = img.copyCrop(
    quelle,
    x: bereich.x.clamp(0, quelle.width - 1),
    y: bereich.y.clamp(0, quelle.height - 1),
    width: bereich.breite.clamp(1, quelle.width - bereich.x),
    height: bereich.hoehe.clamp(1, quelle.height - bereich.y),
  );
  final drehungen = vierteldrehungen % 4;
  if (drehungen != 0) {
    ausschnitt = img.copyRotate(ausschnitt, angle: drehungen * 90);
  }
  return ausschnitt;
}

/// Ein fertiger Ausschnitt und die Endung, unter der er importiert wird.
class ScanAusschnitt {
  const ScanAusschnitt(this.bytes, this.endung);

  final Uint8List bytes;
  final String endung;
}

/// Ob aus dem Scan [pfad] verlustfrei geschnitten wird.
///
/// **Nur ein JPEG nicht.** Ein Ausschnitt muss neu kodiert werden; aus PNG,
/// TIFF und BMP wird er deshalb ein PNG – ohne Verlust, in der Bittiefe des
/// Scans. Ein JPEG neu als PNG zu speichern, machte die Datei vielfach
/// grösser, ohne einen Bildpunkt zu retten; es bleibt ein JPEG in
/// Qualität 94. Bis 3.48.0 hiess beides „verlustfrei“ und war beides ein
/// JPEG (#218).
bool scanVerlustfrei(String pfad) =>
    !const {'.jpg', '.jpeg'}.contains(p.extension(pfad).toLowerCase());

/// Schneidet alle [auftraege] aus einem Scan, der dafür **einmal**
/// dekodiert wird – vorher dekodierte jeder Ausschnitt den ganzen Scan neu
/// (#218). Das Farbprofil des Scans geht mit.
List<ScanAusschnitt> erzeugeScanAusschnitte(
  Uint8List bytes,
  List<({ScanBereich bereich, int drehungen})> auftraege, {
  required bool verlustfrei,
}) {
  final quelle = img.decodeImage(bytes);
  if (quelle == null) throw const FormatException('Bild nicht lesbar');
  return [
    for (final a in auftraege)
      _kodiere(
        rendereScanBereich(quelle, a.bereich, vierteldrehungen: a.drehungen)
          ..iccProfile = quelle.iccProfile,
        verlustfrei: verlustfrei,
      ),
  ];
}

ScanAusschnitt _kodiere(img.Image bild, {required bool verlustfrei}) =>
    verlustfrei
    ? ScanAusschnitt(img.encodePng(bild), '.png')
    : ScanAusschnitt(
        Uint8List.fromList(img.encodeJpg(bild, quality: 94)),
        '.jpg',
      );

/// Vorder- und Rückseiten in der Reihenfolge der Auswahl (#218):
/// [kennungen] hat je ausgewähltem Ausschnitt einen Eintrag – die neue
/// Aufnahme oder `null`, wenn er nicht neu importiert wurde (Duplikat,
/// Fehler). Ein Paar entsteht nur aus den Ausschnitten 1+2, 3+4 …, wenn
/// beide neu sind. Vorher wurden die neuen Kennungen der Reihe nach
/// gepaart: Fielen zwei Duplikate heraus, rückte alles nach, und es
/// entstanden falsche Paare.
({List<(String, String)> paare, int unvollstaendig}) scanPaare(
  List<String?> kennungen,
) {
  final paare = <(String, String)>[];
  var unvollstaendig = 0;
  for (var i = 0; i + 1 < kennungen.length; i += 2) {
    final (vorne, hinten) = (kennungen[i], kennungen[i + 1]);
    if (vorne != null && hinten != null) {
      paare.add((vorne, hinten));
    } else if (vorne != null || hinten != null) {
      unvollstaendig++;
    }
  }
  return (paare: paare, unvollstaendig: unvollstaendig);
}

Uint8List erzeugeScanVorschau(Uint8List bytes, ScanBereich bereich) {
  final quelle = img.decodeImage(bytes);
  if (quelle == null) throw const FormatException('Bild nicht lesbar');
  return Uint8List.fromList(
    img.encodeJpg(
      _verkleinere(rendereScanBereich(quelle, bereich)),
      quality: 78,
    ),
  );
}

img.Image _verkleinere(img.Image bild) {
  const kante = 420;
  if (bild.width <= kante && bild.height <= kante) return bild;
  return img.copyResize(
    bild,
    width: bild.width >= bild.height ? kante : null,
    height: bild.height > bild.width ? kante : null,
  );
}

({double r, double g, double b}) _eckfarbe(img.Image bild) {
  final kante = math.max(
    1,
    math.min(12, math.min(bild.width, bild.height) ~/ 8),
  );
  var r = 0.0, g = 0.0, b = 0.0, n = 0;
  for (final start in [
    (0, 0),
    (bild.width - kante, 0),
    (0, bild.height - kante),
    (bild.width - kante, bild.height - kante),
  ]) {
    for (var y = start.$2; y < start.$2 + kante; y++) {
      for (var x = start.$1; x < start.$1 + kante; x++) {
        final p = bild.getPixel(x, y);
        r += p.r;
        g += p.g;
        b += p.b;
        n++;
      }
    }
  }
  return (r: r / n, g: g / n, b: b / n);
}

class _Rechteck {
  const _Rechteck(this.x, this.y, this.breite, this.hoehe);
  final int x, y, breite, hoehe;
  int get rechts => x + breite;
  int get unten => y + hoehe;
}

void _teileRekursiv(
  Uint8List maske,
  int bildbreite,
  _Rechteck r,
  List<_Rechteck> aus,
  int tiefe,
) {
  if (tiefe >= 8) {
    aus.add(r);
    return;
  }
  final senkrecht = _besteFuge(maske, bildbreite, r, true);
  final waagerecht = _besteFuge(maske, bildbreite, r, false);
  final fuge = switch ((senkrecht, waagerecht)) {
    (null, null) => null,
    (final a?, null) => a,
    (null, final b?) => b,
    (final a?, final b?) => a.anteil >= b.anteil ? a : b,
  };
  if (fuge == null) {
    aus.add(r);
    return;
  }
  final teile = fuge.senkrecht
      ? [
          _Rechteck(r.x, r.y, fuge.start - r.x, r.hoehe),
          _Rechteck(fuge.ende, r.y, r.rechts - fuge.ende, r.hoehe),
        ]
      : [
          _Rechteck(r.x, r.y, r.breite, fuge.start - r.y),
          _Rechteck(r.x, fuge.ende, r.breite, r.unten - fuge.ende),
        ];
  for (final teil in teile) {
    final begrenzt = _inhaltBegrenzen(maske, bildbreite, teil);
    if (begrenzt != null) {
      _teileRekursiv(maske, bildbreite, begrenzt, aus, tiefe + 1);
    }
  }
}

({bool senkrecht, int start, int ende, double anteil})? _besteFuge(
  Uint8List maske,
  int bildbreite,
  _Rechteck r,
  bool senkrecht,
) {
  final laenge = senkrecht ? r.breite : r.hoehe;
  final quer = senkrecht ? r.hoehe : r.breite;
  final minFuge = math.max(3, (laenge * 0.018).round());
  final minTeil = math.max(12, (laenge * 0.15).round());
  var besteStart = -1, besteEnde = -1;
  var laufStart = -1;
  for (var i = 0; i <= laenge; i++) {
    var leer = false;
    if (i < laenge) {
      var inhalt = 0;
      for (var q = 0; q < quer; q++) {
        final x = senkrecht ? r.x + i : r.x + q;
        final y = senkrecht ? r.y + q : r.y + i;
        inhalt += maske[y * bildbreite + x];
      }
      leer = inhalt <= math.max(1, (quer * 0.004).floor());
    }
    if (leer && laufStart < 0) laufStart = i;
    if ((!leer || i == laenge) && laufStart >= 0) {
      final ende = i;
      final absolutStart = (senkrecht ? r.x : r.y) + laufStart;
      final absolutEnde = (senkrecht ? r.x : r.y) + ende;
      final links = laufStart;
      final rechts = laenge - ende;
      if (ende - laufStart >= minFuge &&
          links >= minTeil &&
          rechts >= minTeil &&
          (besteStart < 0 || ende - laufStart > besteEnde - besteStart)) {
        besteStart = absolutStart;
        besteEnde = absolutEnde;
      }
      laufStart = -1;
    }
  }
  if (besteStart < 0) return null;
  return (
    senkrecht: senkrecht,
    start: besteStart,
    ende: besteEnde,
    anteil: (besteEnde - besteStart) / laenge,
  );
}

_Rechteck? _inhaltBegrenzen(Uint8List maske, int bildbreite, _Rechteck r) {
  var minX = r.rechts, minY = r.unten, maxX = -1, maxY = -1;
  for (var y = r.y; y < r.unten; y++) {
    for (var x = r.x; x < r.rechts; x++) {
      if (maske[y * bildbreite + x] == 0) continue;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
  }
  return maxX < 0
      ? null
      : _Rechteck(minX, minY, maxX - minX + 1, maxY - minY + 1);
}
