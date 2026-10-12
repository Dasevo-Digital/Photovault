/// **Kratzer, Knicke und Staub in eingescannten Fotos finden.**
///
/// MyHeritage findet solche Schäden mit einem eigens trainierten Netz.
/// Hier ohne Modell, mit dem Werkzeug, das Scanprogramme seit jeher für
/// Staub nehmen: dem **Zylinderhut** der Bildmorphologie. Ein Öffnen
/// (erst Minimum, dann Maximum über ein kleines Fenster) entfernt alles
/// Helle, das schmaler ist als das Fenster; die Differenz zum Bild ist
/// genau das Schmale – ein weisser Kratzer, ein Staubkorn. Das Schliessen
/// tut dasselbe für Dunkles.
///
/// **Schmal allein ist nicht genug.** Haare, Äste, Schrift und
/// Brillengestelle sind auch schmal. Was übrig bleibt, wird deshalb nach
/// Form sortiert:
///
/// * **Kratzer und Knicke** sind lang und gerade. Gemessen als Verhältnis
///   der beiden Hauptachsen der Punktwolke: Ein Ast verzweigt und biegt
///   sich, ein Kratzer nicht.
/// * **Staub** ist ein kleiner Fleck auf einer sonst ruhigen Fläche –
///   Himmel, Haut, Wand. Ein Lichtpunkt im Auge oder ein Knopf an der
///   Jacke liegt in unruhiger Umgebung und bleibt stehen.
///
/// Das Ergebnis ist ein **Vorschlag**: Er erscheint als Maske im Werkzeug
/// „Objekt entfernen“, wird dort angesehen und erst dann von LaMa
/// gefüllt. Ein Verfahren, das selbst entscheidet, was ein Kratzer ist,
/// läge an jedem dritten Foto falsch – und ein übermalter Ast ist nicht
/// mehr zurückzuholen.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Auf diese Kantenlänge wird verkleinert, bevor gesucht wird. Ein Kratzer
/// bleibt dabei ein Kratzer, und die Rechnung bleibt unter einer Sekunde.
const kratzerArbeitsgroesse = 1600;

/// Fensterbreite des Zylinderhuts in Punkten der Arbeitsgrösse: Was
/// schmaler ist, gilt als „schmal“.
const _fenster = 7;

/// Mindestlänge eines Kratzers in Punkten der Arbeitsgrösse.
const _kratzerMindestlaenge = 80.0;

/// So viel länger als breit muss ein Kratzer sein (Verhältnis der
/// Hauptachsen, nicht der Ausdehnung im Raster – ein schräger Strich ist
/// im Raster quadratisch).
const _kratzerSchlankheit = 25.0;

/// Grösster Staubfleck in Punkten der Arbeitsgrösse.
const _staubHoechstens = 40;

/// Wie ruhig die Umgebung eines Staubkorns sein muss (Standardabweichung
/// der Helligkeit, 0 bis 255).
const _staubRuhe = 12.0;

/// So viel stärker als die Schwelle muss ein Staubkorn anschlagen.
const _staubKontrast = 2.0;

/// Wie weit um ein Staubkorn nichts anderes anschlagen darf.
const _staubAbstand = 12;

typedef Kratzerfund = ({
  /// Maske in der Grösse des Eingangsbildes: 255 = hier füllen.
  img.Image maske,
  int kratzer,
  int staub,
});

/// Sucht in [bild] nach Kratzern und Staub. Läuft gut in einem eigenen
/// Isolat (`compute`): reine Rechnung, keine Plattformkanäle.
Kratzerfund sucheKratzer(img.Image bild) {
  final faktor = math.min(
    1.0,
    kratzerArbeitsgroesse / math.max(bild.width, bild.height),
  );
  final klein = faktor < 1
      ? img.copyResize(
          bild,
          width: (bild.width * faktor).round(),
          height: (bild.height * faktor).round(),
          interpolation: img.Interpolation.average,
        )
      : bild;
  final w = klein.width, h = klein.height;
  final grau = Uint8List(w * h);
  for (final p in klein) {
    grau[p.y * w + p.x] = p.luminance.round().clamp(0, 255);
  }

  // Zylinderhut, hell und dunkel, als ein Wert je Punkt.
  final offen = _max(_min(grau, w, h), w, h);
  final zu = _min(_max(grau, w, h), w, h);
  final antwort = Uint8List(w * h);
  // Das Bild ohne das Schmale: je Punkt die Seite des Zylinderhuts, die
  // angeschlagen hat. Darin wird gemessen, wie ruhig die Umgebung eines
  // Flecks ist – im Original triebe der Fleck seine eigene Umgebung hoch.
  final bereinigt = Uint8List(w * h);
  var summe = 0.0, quadrate = 0.0;
  for (var i = 0; i < grau.length; i++) {
    final hell = grau[i] - offen[i], dunkel = zu[i] - grau[i];
    final a = math.max(hell, dunkel);
    bereinigt[i] = hell >= dunkel ? offen[i] : zu[i];
    antwort[i] = a;
    summe += a;
    quadrate += a * a;
  }
  final mittel = summe / grau.length;
  final streuung = math.sqrt(
    math.max(0, quadrate / grau.length - mittel * mittel),
  );
  // Mindestens 25 Helligkeitsstufen: Auf einem sehr ruhigen Bild läge
  // „vier Streuungen über dem Mittel“ im Rauschen des Scanners.
  final schwelle = math.max(25.0, mittel + 4 * streuung);

  final ruhe = _lokaleStreuung(bereinigt, w, h, 7);
  // Wie viel ringsum ebenfalls angeschlagen hat – als Summentabelle, um
  // je Fleck in einem Zug nachzuzählen.
  final dicht = Int32List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var zeile = 0;
    for (var x = 0; x < w; x++) {
      if (antwort[y * w + x] >= schwelle) zeile++;
      dicht[(y + 1) * (w + 1) + x + 1] = dicht[y * (w + 1) + x + 1] + zeile;
    }
  }
  int ringsum(int x, int y) {
    final x0 = math.max(0, x - _staubAbstand),
        x1 = math.min(w, x + _staubAbstand + 1);
    final y0 = math.max(0, y - _staubAbstand),
        y1 = math.min(h, y + _staubAbstand + 1);
    return dicht[y1 * (w + 1) + x1] -
        dicht[y0 * (w + 1) + x1] -
        dicht[y1 * (w + 1) + x0] +
        dicht[y0 * (w + 1) + x0];
  }

  final treffer = Uint8List(w * h);
  var kratzer = 0, staub = 0;
  final besucht = Uint8List(w * h);
  final stapel = <int>[];
  for (var start = 0; start < antwort.length; start++) {
    if (besucht[start] == 1 || antwort[start] < schwelle) continue;
    // Zusammenhängende Fläche (acht Nachbarn) einsammeln.
    final punkte = <int>[];
    stapel.add(start);
    besucht[start] = 1;
    while (stapel.isNotEmpty) {
      final i = stapel.removeLast();
      punkte.add(i);
      final x = i % w, y = i ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final j = ny * w + nx;
          if (besucht[j] == 1 || antwort[j] < schwelle) continue;
          besucht[j] = 1;
          stapel.add(j);
        }
      }
    }
    final form = _form(punkte, w);
    final istKratzer =
        form.laenge >= _kratzerMindestlaenge &&
        form.schlankheit >= _kratzerSchlankheit;
    var istStaub = false;
    if (!istKratzer && punkte.length <= _staubHoechstens) {
      // Ruhig und allein: Staub liegt vereinzelt. Wo es ringsum ebenso
      // anschlägt – Laub, Kies, Stoffmuster –, ist es Bildinhalt.
      // Und deutlich: Ein Korn auf dem Scanner hebt sich hart ab, ein
      // Vogel am Himmel oder eine Lampe in der Ferne nur wenig.
      final mitte = punkte[punkte.length ~/ 2];
      var staerkste = 0;
      for (final i in punkte) {
        staerkste = math.max(staerkste, antwort[i]);
      }
      istStaub =
          staerkste >= _staubKontrast * schwelle &&
          ruhe[mitte] <= _staubRuhe &&
          ringsum(mitte % w, mitte ~/ w) <= punkte.length + 2;
    }
    if (!istKratzer && !istStaub) continue;
    istKratzer ? kratzer++ : staub++;
    for (final i in punkte) {
      treffer[i] = 255;
    }
  }

  // Etwas breiter als gefunden: LaMa braucht die Ränder, sonst bleibt
  // ein heller Saum stehen.
  final breiter = _max(treffer, w, h, fenster: 5);
  final maske = img.Image(width: w, height: h, numChannels: 1);
  for (var i = 0; i < breiter.length; i++) {
    if (breiter[i] > 0) maske.setPixelRgb(i % w, i ~/ w, 255, 255, 255);
  }
  return (
    maske: faktor < 1
        ? img.copyResize(
            maske,
            width: bild.width,
            height: bild.height,
            interpolation: img.Interpolation.nearest,
          )
        : maske,
    kratzer: kratzer,
    staub: staub,
  );
}

/// Länge (grösste Ausdehnung entlang der Hauptachse) und Schlankheit
/// (Verhältnis der Hauptachsen) einer Punktwolke.
({double laenge, double schlankheit}) _form(List<int> punkte, int w) {
  if (punkte.length < 3) {
    return (laenge: punkte.length.toDouble(), schlankheit: 1);
  }
  var mx = 0.0, my = 0.0;
  for (final i in punkte) {
    mx += i % w;
    my += i ~/ w;
  }
  mx /= punkte.length;
  my /= punkte.length;
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (final i in punkte) {
    final dx = i % w - mx, dy = i ~/ w - my;
    sxx += dx * dx;
    syy += dy * dy;
    sxy += dx * dy;
  }
  sxx /= punkte.length;
  syy /= punkte.length;
  sxy /= punkte.length;
  final spur = sxx + syy;
  final wurzel = math.sqrt(
    math.max(0, (sxx - syy) * (sxx - syy) / 4 + sxy * sxy),
  );
  final gross = spur / 2 + wurzel;
  final klein = math.max(spur / 2 - wurzel, 1 / 12);
  // Eine gleichmässig belegte Strecke der Länge L hat die Varianz L²/12.
  return (laenge: math.sqrt(12 * gross), schlankheit: math.sqrt(gross / klein));
}

Uint8List _min(Uint8List q, int w, int h, {int fenster = _fenster}) =>
    _filter(q, w, h, fenster, math.min);

Uint8List _max(Uint8List q, int w, int h, {int fenster = _fenster}) =>
    _filter(q, w, h, fenster, math.max);

/// Minimum oder Maximum über ein quadratisches Fenster – getrennt nach
/// Zeilen und Spalten, also zwei kurze Durchgänge statt eines langen.
Uint8List _filter(
  Uint8List q,
  int w,
  int h,
  int fenster,
  int Function(int, int) wahl,
) {
  final r = fenster ~/ 2;
  final zeilen = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final o = y * w;
    for (var x = 0; x < w; x++) {
      var v = q[o + x];
      for (var k = math.max(0, x - r); k <= math.min(w - 1, x + r); k++) {
        v = wahl(v, q[o + k]);
      }
      zeilen[o + x] = v;
    }
  }
  final aus = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = zeilen[y * w + x];
      for (var k = math.max(0, y - r); k <= math.min(h - 1, y + r); k++) {
        v = wahl(v, zeilen[k * w + x]);
      }
      aus[y * w + x] = v;
    }
  }
  return aus;
}

/// Standardabweichung der Helligkeit in einem Fenster um jeden Punkt –
/// über Summentabellen, damit die Fenstergrösse nichts kostet.
Float32List _lokaleStreuung(Uint8List q, int w, int h, int radius) {
  final s = Float64List((w + 1) * (h + 1));
  final s2 = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var zeile = 0.0, zeile2 = 0.0;
    for (var x = 0; x < w; x++) {
      final v = q[y * w + x].toDouble();
      zeile += v;
      zeile2 += v * v;
      s[(y + 1) * (w + 1) + x + 1] = s[y * (w + 1) + x + 1] + zeile;
      s2[(y + 1) * (w + 1) + x + 1] = s2[y * (w + 1) + x + 1] + zeile2;
    }
  }
  final aus = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - radius), y1 = math.min(h, y + radius + 1);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - radius), x1 = math.min(w, x + radius + 1);
      final n = (y1 - y0) * (x1 - x0);
      double feld(Float64List t) =>
          t[y1 * (w + 1) + x1] -
          t[y0 * (w + 1) + x1] -
          t[y1 * (w + 1) + x0] +
          t[y0 * (w + 1) + x0];
      final m = feld(s) / n;
      aus[y * w + x] = math.sqrt(math.max(0, feld(s2) / n - m * m));
    }
  }
  return aus;
}
