import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Ein einzelner Bildausschnitt aus [splitIntoTiles], inklusive
/// Überlappungsrand. [x]/[y] sind die Koordinaten der linken oberen Ecke im
/// UNSKALIERTEN Quellbild – [processInTiles] nutzt sie, um das (bereits um
/// den Skalierungsfaktor vergrößerte) Inferenz-Ergebnis an der richtigen
/// Stelle im Ausgabebild zu platzieren.
class Tile {
  final int x;
  final int y;
  final img.Image image;
  const Tile({required this.x, required this.y, required this.image});
}

/// Wie ein Bild in Kacheln zerfällt: wo jede Kachel beginnt und wie gross
/// sie ist – alle Kacheln eines Bildes gleich gross.
///
/// **Gleichmässig verteilt statt bündig an den Rand geschoben.** Bis hierher
/// hatte jede Kachel die volle [tileSize], und die letzte jeder Reihe wurde
/// an den Rand geschoben. Sie überdeckte dann fast eine ganze Kachel ein
/// zweites Mal: Bei 4032 × 3024 mit 512er-Kacheln rechnete das Netz
/// 9 × 7 Kacheln mit dem 1,35-Fachen der Bildfläche. Jetzt bleibt die
/// Anzahl dieselbe – die kleinste, mit der sich das Bild bei mindestens
/// [overlap] Überlappung abdecken lässt –, aber die Kacheln werden so klein
/// wie dafür nötig und gleichmässig verteilt: dieselben 63 Kacheln mit je
/// 463 × 446 Pixeln, das 1,07-Fache der Fläche (gemessen in
/// `tile_processor_test.dart`).
///
/// **Eine Kachelgrösse je Bild.** Real-ESRGAN nimmt jede Eingabegrösse
/// (`[1,3,h,w]`) und rechnete schon bisher kleinere Kacheln, wo ein Bild
/// schmaler war als eine Kachel. Wer ein Vielfaches braucht (NAFNet: 16),
/// gibt es als [vielfaches] an; die Kachel wird dann darauf aufgerundet,
/// statt bei jeder Kachel aufgefüllt zu werden.
class Kachelraster {
  const Kachelraster._(this.anfaengeX, this.anfaengeY, this.breite, this.hoehe);

  factory Kachelraster(
    int bildBreite,
    int bildHoehe, {
    required int tileSize,
    required int overlap,
    int vielfaches = 1,
  }) {
    _pruefeKacheln(tileSize, overlap, 1);
    final x = _achse(bildBreite, tileSize, overlap, vielfaches);
    final y = _achse(bildHoehe, tileSize, overlap, vielfaches);
    return Kachelraster._(x.anfaenge, y.anfaenge, x.laenge, y.laenge);
  }

  /// Linke bzw. obere Kante jeder Spalte und Reihe, im Quellbild.
  final List<int> anfaengeX, anfaengeY;

  /// Breite und Höhe jeder Kachel im Quellbild.
  final int breite, hoehe;

  int get anzahl => anfaengeX.length * anfaengeY.length;

  /// Wie viele Quellpixel das Netz insgesamt rechnet.
  int get flaeche => anzahl * breite * hoehe;
}

/// Eine Achse von [Kachelraster]: die kleinste Zahl von Kacheln mit
/// höchstens [tileSize] Kante und mindestens [overlap] Überlappung, die
/// [laenge] abdeckt, und die kleinste Kante, mit der diese Zahl reicht.
({List<int> anfaenge, int laenge}) _achse(
  int laenge,
  int tileSize,
  int overlap,
  int vielfaches,
) {
  if (laenge <= tileSize) return (anfaenge: const [0], laenge: laenge);
  final schritt = tileSize - overlap;
  final n = (laenge - overlap + schritt - 1) ~/ schritt;
  // n Kacheln der Kante t mit je [overlap] Überlappung decken
  // n·t − (n−1)·overlap ab; das muss mindestens [laenge] sein.
  var t = (laenge + (n - 1) * overlap + n - 1) ~/ n;
  if (vielfaches > 1) {
    t = math.min(tileSize, (t + vielfaches - 1) ~/ vielfaches * vielfaches);
  }
  // Gleichmässig von 0 bis bündig an den Rand. Weil t − overlap mindestens
  // (laenge − t) / (n − 1) ist, überlappen Nachbarn um mindestens [overlap].
  final rest = laenge - t;
  final anfaenge = <int>[];
  for (var i = 0; i < n; i++) {
    final a = (i * rest + (n - 1) ~/ 2) ~/ (n - 1);
    // Nur bei entarteten Werten (Überlappung fast so gross wie die
    // Kachel) fielen zwei Anfänge zusammen.
    if (anfaenge.isEmpty || a > anfaenge.last) anfaenge.add(a);
  }
  return (anfaenge: anfaenge, laenge: t);
}

/// Zerlegt [source] in überlappende Kacheln (siehe [Kachelraster]). Für ein
/// reales 12-48-MP-Foto mit 512px-Kacheln typischerweise mehrere Dutzend
/// Kacheln.
List<Tile> splitIntoTiles(
  img.Image source, {
  required int tileSize,
  required int overlap,
}) {
  final raster = Kachelraster(
    source.width,
    source.height,
    tileSize: tileSize,
    overlap: overlap,
  );
  return [
    for (final y in raster.anfaengeY)
      for (final x in raster.anfaengeX)
        Tile(
          x: x,
          y: y,
          image: img.copyCrop(
            source,
            x: x,
            y: y,
            width: raster.breite,
            height: raster.hoehe,
          ),
        ),
  ];
}

/// Gewichte einer Kachel entlang einer Achse (bereits skaliert): volles
/// Gewicht (1.0) im Kern, linearer Abfall zu 0 hin zu jeder Kante, die einen
/// Nachbarn hat – Kanten am tatsächlichen Bildrand behalten volles Gewicht
/// (dort gibt es nichts zum Überblenden).
///
/// Das Gewicht eines Pixels ist das Produkt der Gewichte beider Achsen. Die
/// Zusammensetzung normalisiert am Ende durch die Gewichtssumme; die
/// Gewichte benachbarter Kacheln müssen sich daher NICHT exakt zu 1
/// aufsummieren.
///
/// Weil jede Rampe höchstens so lang ist wie die Überlappung, hat ein Pixel,
/// das nur eine Kachel überdeckt, immer das Gewicht 1 – darauf baut
/// [processInTiles] (siehe dort).
Float64List _achsengewichte(
  int laenge,
  int rampe, {
  required bool amAnfang,
  required bool amEnde,
}) {
  final r = rampe.clamp(0, laenge ~/ 2);
  final w = Float64List(laenge);
  for (var i = 0; i < laenge; i++) {
    var g = 1.0;
    if (!amAnfang && r > 0 && i < r) g = (i + 1) / r;
    if (!amEnde && r > 0 && i >= laenge - r) g = math.min(g, (laenge - i) / r);
    w[i] = g;
  }
  return w;
}

/// Geplanter Speicher für Quelle, Ergebnis, Überblendung und eine Kachel.
/// Der native Modellspeicher ist zusätzlich vom jeweiligen Modell abhängig.
class TileMemoryPlan {
  const TileMemoryPlan(
    this.sourceBytes,
    this.outputBytes,
    this.bandBytes,
    this.tileBytes,
  );
  final int sourceBytes, outputBytes, bandBytes, tileBytes;
  int get totalBytes => sourceBytes + outputBytes + bandBytes + tileBytes;
}

void _pruefeKacheln(int tileSize, int overlap, int scaleFactor) {
  if (tileSize <= 0 || overlap < 0 || overlap >= tileSize || scaleFactor <= 0) {
    throw ArgumentError('pv_kachel_parameter');
  }
}

/// Was [processInTiles] für [source] an Speicher braucht.
///
/// [modellfaktor] ist, wie stark das Netz selbst vergrössert, wenn das
/// Ergebnis jeder Kachel danach auf [scaleFactor] verkleinert wird (2× und
/// 3× beim Hochskalieren, #500): Dann liegt je Kachel noch das grössere
/// Zwischenbild im Speicher. Ohne Angabe ist es [scaleFactor].
TileMemoryPlan tileMemoryPlan(
  img.Image source, {
  required int tileSize,
  required int overlap,
  required int scaleFactor,
  int? modellfaktor,
  int vielfaches = 1,
}) {
  _pruefeKacheln(tileSize, overlap, scaleFactor);
  final raster = Kachelraster(
    source.width,
    source.height,
    tileSize: tileSize,
    overlap: overlap,
    vielfaches: vielfaches,
  );
  final plan = _Ueberblendung(raster, source.width, source.height, scaleFactor);
  final m = math.max(modellfaktor ?? scaleFactor, scaleFactor);
  final s = scaleFactor;
  final px = raster.breite * raster.hoehe;
  return TileMemoryPlan(
    source.data?.lengthInBytes ?? source.width * source.height * 4,
    plan.ausBreite * plan.ausHoehe * 3,
    plan.pufferBytes,
    // Ausschnitt, Eingabetensor (Float32, CHW), Ausgabe des Netzes (Float32)
    // und als Bild; beim Verkleinern dazu dessen Zwischenzeilen (Float32)
    // und die verkleinerte Kachel.
    px * (3 + 12 + m * m * 15) + (m == s ? 0 : px * (m * s * 12 + s * s * 3)),
  );
}

class TileMemoryLimit implements Exception {
  const TileMemoryLimit(this.requiredBytes, this.limitBytes);
  final int requiredBytes, limitBytes;
  @override
  String toString() => 'pv_kachel_speicher:$requiredBytes:$limitBytes';
}

/// Wo im Ergebnis sich Kacheln überlappen – und die Puffer, in denen nur
/// dort überblendet wird.
///
/// **Warum nicht mehr ein ganzes Zeilenband.** Bis hierher lagen
/// Summen und Gewichte für eine ganze Kachelhöhe über die volle
/// Ausgabebreite in Float32 bereit: bei 16384 Pixeln Breite und 4× gut
/// 537 MB, mehr als manches Ergebnis selbst. Überblendet wird aber nur, wo
/// mehrere Kacheln liegen – in Streifen von der Breite der Überlappung.
/// Jedes übrige Pixel stammt aus genau einer Kachel, hat dort das Gewicht 1
/// (siehe [_achsengewichte]) und geht unverändert ins Ergebnis. Summen
/// gibt es nur noch
///
/// * für Zeilen, die mehrere Kachelreihen überdecken, über die volle
///   Breite – umlaufend, so viele, wie eine Kachelreihe davon berührt;
/// * für die übrigen Zeilen der laufenden Kachelreihe nur in den Spalten,
///   die mehrere Kachelspalten überdecken.
///
/// Bei 16384 Pixeln Breite sind das rund 50 MB statt 537. Reihenfolge und
/// Rechnung der Summen sind dieselben wie vorher, das Ergebnis ist
/// bitgleich (geprüft in `tile_processor_test.dart`).
class _Ueberblendung {
  _Ueberblendung(this.raster, int breite, int hoehe, this.s)
    : ausBreite = breite * s,
      ausHoehe = hoehe * s {
    final kb = raster.breite * s, kh = raster.hoehe * s;
    xDeckung = Uint8List(ausBreite);
    for (final x in raster.anfaengeX) {
      for (var i = x * s; i < x * s + kb; i++) {
        if (xDeckung[i] < 255) xDeckung[i]++;
      }
    }
    xStelle = Int32List(ausBreite)..fillRange(0, ausBreite, -1);
    final spalten = <int>[];
    for (var i = 0; i < ausBreite; i++) {
      if (xDeckung[i] > 1) {
        xStelle[i] = spalten.length;
        spalten.add(i);
      }
    }
    mehrfachSpalten = Int32List.fromList(spalten);

    final deckung = Uint8List(ausHoehe);
    letzteReihe = Int32List(ausHoehe);
    for (var r = 0; r < raster.anfaengeY.length; r++) {
      final y = raster.anfaengeY[r];
      for (var i = y * s; i < y * s + kh; i++) {
        if (deckung[i] < 255) deckung[i]++;
        letzteReihe[i] = r;
      }
    }
    yStelle = Int32List(ausHoehe)..fillRange(0, ausHoehe, -1);
    var n = 0;
    for (var i = 0; i < ausHoehe; i++) {
      if (deckung[i] > 1) yStelle[i] = n++;
    }
    // So viele mehrfach überdeckte Zeilen berührt eine Kachelreihe
    // höchstens; sie haben aufeinanderfolgende Stellen, und reihum belegt
    // trifft keine auf eine, die noch offen ist.
    var umlauf = 0;
    for (final y in raster.anfaengeY) {
      var k = 0;
      for (var i = y * s; i < y * s + kh; i++) {
        if (yStelle[i] >= 0) k++;
      }
      umlauf = math.max(umlauf, k);
    }
    bandZeilen = umlauf;
  }

  final Kachelraster raster;
  final int s;
  final int ausBreite, ausHoehe;

  /// Wie viele Kachelspalten jede Ausgabespalte überdecken.
  late final Uint8List xDeckung;

  /// Stelle einer mehrfach überdeckten Spalte in [mehrfachSpalten], sonst -1.
  late final Int32List xStelle;
  late final Int32List mehrfachSpalten;

  /// Laufende Nummer einer mehrfach überdeckten Zeile, sonst -1.
  late final Int32List yStelle;

  /// Die letzte Kachelreihe, die eine Zeile überdeckt.
  late final Int32List letzteReihe;

  /// Wie viele mehrfach überdeckte Zeilen gleichzeitig offen sind.
  late final int bandZeilen;

  /// Je Wert: Summen der drei Kanäle und des Gewichts in Float32 – dieselbe
  /// Genauigkeit wie bisher.
  int get pufferBytes =>
      bandZeilen * ausBreite * 16 +
      raster.hoehe * s * mehrfachSpalten.length * 16 +
      ausBreite * 9 +
      ausHoehe * 12;
}

/// Die Bildpunkte von [b] als RGB-Bytes ohne Kopie, wo das geht.
Uint8List rgbBytes(img.Image b) {
  final d = b.data;
  if (d is img.ImageDataUint8 && d.numChannels == 3 && d.palette == null) {
    return d.data;
  }
  final c = b.convert(format: img.Format.uint8, numChannels: 3);
  return (c.data! as img.ImageDataUint8).data;
}

/// Ein Ausschnitt von [quelle] (RGB-Bytes, [breite] Pixel je Zeile) als
/// eigenes Bild – zeilenweise kopiert statt Pixel für Pixel.
img.Image _ausschnitt(
  Uint8List quelle,
  int breite,
  int x,
  int y,
  int w,
  int h,
) {
  final aus = Uint8List(w * h * 3);
  for (var j = 0; j < h; j++) {
    final von = ((y + j) * breite + x) * 3;
    aus.setRange(j * w * 3, (j + 1) * w * 3, quelle, von);
  }
  return img.Image.fromBytes(
    width: w,
    height: h,
    bytes: aus.buffer,
    numChannels: 3,
  );
}

/// Rundet auf Float32 – so, wie die Gewichte bisher in einer Float32List
/// lagen.
final _f32 = Float32List(1);
double _alsF32(double v) {
  _f32[0] = v;
  return _f32[0];
}

/// Verarbeitet jeweils nur eine Quellkachel (Aufteilung siehe
/// [Kachelraster]). Pixel aus genau einer Kachel gehen sofort ins Ergebnis,
/// überblendet wird nur in den Überlappungen (siehe [_Ueberblendung]). Die
/// Additionsreihenfolge und Überblendung entsprechen der vollständigen
/// Zusammensetzung. Ein abgebrochenes Ergebnis bleibt unvollständig und
/// muss vom Aufrufer verworfen werden.
///
/// [vielfaches] und [modellfaktor] siehe [Kachelraster] und
/// [tileMemoryPlan].
Future<img.Image> processInTiles(
  img.Image source, {
  required int tileSize,
  required int overlap,
  required int scaleFactor,
  required Future<img.Image> Function(img.Image tile) infer,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
  int maxWorkingBytes = 1536 * 1024 * 1024,
  void Function(TileMemoryPlan plan)? onMemoryPlan,
  int vielfaches = 1,
  int? modellfaktor,
}) async {
  final plan = tileMemoryPlan(
    source,
    tileSize: tileSize,
    overlap: overlap,
    scaleFactor: scaleFactor,
    modellfaktor: modellfaktor,
    vielfaches: vielfaches,
  );
  onMemoryPlan?.call(plan);
  if (plan.totalBytes > maxWorkingBytes) {
    throw TileMemoryLimit(plan.totalBytes, maxWorkingBytes);
  }
  final s = scaleFactor;
  final raster = Kachelraster(
    source.width,
    source.height,
    tileSize: tileSize,
    overlap: overlap,
    vielfaches: vielfaches,
  );
  final u = _Ueberblendung(raster, source.width, source.height, s);
  final xs = raster.anfaengeX, ys = raster.anfaengeY;
  final tw = raster.breite, th = raster.hoehe;
  final kb = tw * s, kh = th * s;
  final outWidth = u.ausBreite;
  final result = img.Image(width: outWidth, height: u.ausHoehe);
  final aus = (result.data! as img.ImageDataUint8).data;

  final band = Float32List(math.max(1, u.bandZeilen * outWidth * 4));
  final kx = u.mehrfachSpalten.length;
  final streifen = Float32List(math.max(1, kh * kx * 4));
  final gewichteX = [
    for (final x in xs)
      _achsengewichte(
        kb,
        overlap * s,
        amAnfang: x == 0,
        amEnde: x + tw >= source.width,
      ),
  ];

  final d = source.data;
  final quelle =
      d is img.ImageDataUint8 && d.numChannels == 3 && d.palette == null
      ? d.data
      : null;
  int kanal(double summe, double gewicht) =>
      (summe / gewicht).round().clamp(0, 255);

  var done = 0;
  rows:
  for (var r = 0; r < ys.length; r++) {
    final ty = ys[r];
    final oy = ty * s;
    final wy = _achsengewichte(
      kh,
      overlap * s,
      amAnfang: ty == 0,
      amEnde: ty + th >= source.height,
    );
    for (var c = 0; c < xs.length; c++) {
      if (isCancelled?.call() ?? false) break rows;
      final tx = xs[c];
      final tile = quelle != null
          ? _ausschnitt(quelle, source.width, tx, ty, tw, th)
          : img.copyCrop(source, x: tx, y: ty, width: tw, height: th);
      final processed = await infer(tile);
      if (processed.width != kb || processed.height != kh) {
        throw StateError('pv_kachel_ausgabe');
      }
      final p = rgbBytes(processed);
      final wx = gewichteX[c];
      final ox = tx * s;
      for (var y = 0; y < kh; y++) {
        final zeile = oy + y;
        final quellZeile = y * kb * 3;
        final bandStelle = u.yStelle[zeile];
        if (bandStelle >= 0) {
          // Mehrere Kachelreihen: über die volle Breite summieren.
          final basis = (bandStelle % u.bandZeilen) * outWidth;
          for (var x = 0; x < kb; x++) {
            final w = _alsF32(wx[x] * wy[y]);
            final q = quellZeile + x * 3;
            final i = (basis + ox + x) * 4;
            band[i] += p[q] * w;
            band[i + 1] += p[q + 1] * w;
            band[i + 2] += p[q + 2] * w;
            band[i + 3] += w;
          }
          continue;
        }
        // Nur diese Kachelreihe: Was nur diese Kachel deckt, ist fertig.
        final ziel = zeile * outWidth;
        final streifenZeile = y * kx;
        for (var x = 0; x < kb; x++) {
          final q = quellZeile + x * 3;
          final spalte = ox + x;
          final k = u.xStelle[spalte];
          if (k < 0) {
            final i = (ziel + spalte) * 3;
            aus[i] = p[q];
            aus[i + 1] = p[q + 1];
            aus[i + 2] = p[q + 2];
          } else {
            final w = _alsF32(wx[x] * wy[y]);
            final i = (streifenZeile + k) * 4;
            streifen[i] += p[q] * w;
            streifen[i + 1] += p[q + 1] * w;
            streifen[i + 2] += p[q + 2] * w;
            streifen[i + 3] += w;
          }
        }
      }
      done++;
      onProgress?.call(done, raster.anzahl);
    }

    // Die Kachelreihe ist fertig: ihre Überlappungsspalten ins Ergebnis …
    for (var y = 0; y < kh; y++) {
      final zeile = oy + y;
      if (u.yStelle[zeile] >= 0) continue;
      final ziel = zeile * outWidth;
      for (var k = 0; k < kx; k++) {
        final i = (y * kx + k) * 4;
        final w = streifen[i + 3];
        if (w > 0) {
          final o = (ziel + u.mehrfachSpalten[k]) * 3;
          aus[o] = kanal(streifen[i], w);
          aus[o + 1] = kanal(streifen[i + 1], w);
          aus[o + 2] = kanal(streifen[i + 2], w);
        }
        streifen[i] = 0;
        streifen[i + 1] = 0;
        streifen[i + 2] = 0;
        streifen[i + 3] = 0;
      }
    }
    // … und die Zeilen über mehrere Reihen, die keine spätere mehr berührt.
    for (var y = 0; y < kh; y++) {
      final zeile = oy + y;
      final stelle = u.yStelle[zeile];
      if (stelle < 0 || u.letzteReihe[zeile] != r) continue;
      final basis = (stelle % u.bandZeilen) * outWidth;
      final ziel = zeile * outWidth;
      for (var x = 0; x < outWidth; x++) {
        final i = (basis + x) * 4;
        final w = band[i + 3];
        if (w > 0) {
          final o = (ziel + x) * 3;
          aus[o] = kanal(band[i], w);
          aus[o + 1] = kanal(band[i + 1], w);
          aus[o + 2] = kanal(band[i + 2], w);
        }
        band[i] = 0;
        band[i + 1] = 0;
        band[i + 2] = 0;
        band[i + 3] = 0;
      }
    }
  }
  return result;
}
