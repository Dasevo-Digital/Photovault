/// Sensorstaub finden.
///
/// **Was fehlte.** Das Wegrechnen gibt es längst – LaMa und der
/// Reparaturpinsel im Bildeditor. Was fehlte, ist das Finden: Wer 1208
/// RAW-Dateien aus einer EOS 60D hat, hat denselben Fleck auf hunderten
/// Aufnahmen und müsste ihn hundertmal von Hand suchen.
///
/// **Warum kein Modell.** Sensorstaub sieht immer gleich aus: ein dunkler,
/// runder, weicher Fleck in einer sonst glatten Fläche. Das ist mit einer
/// Differenz gegen ein weichgezeichnetes Abbild zu finden und braucht weder
/// Training noch eine Modelldatei.
///
/// **Der eigentliche Trick steht nicht im Einzelbild.** Eine einzelne
/// Aufnahme liefert zu viele Fehlalarme – jeder Vogel am Himmel, jede
/// Steinsprenkel im Weg sieht aus wie Staub. Was Staub von allem anderen
/// unterscheidet, ist, dass er **an derselben Stelle bleibt**. Erst der
/// Abgleich über eine Serie derselben Kamera macht aus einem Verdacht einen
/// Befund (siehe [bestaetigeUeberSerie]).
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Ein Fleckverdacht in einem einzelnen Bild.
class Staubverdacht {
  /// Mitte, als Anteil der Bildkante (0..1) – wie überall sonst, damit
  /// Aufnahmen verschiedener Grösse vergleichbar bleiben.
  final double x, y;

  /// Radius, als Anteil der kürzeren Bildkante.
  final double radius;

  /// Wie dunkel der Fleck gegenüber seiner Umgebung ist, in Grauwerten
  /// (0..255). Je grösser, desto deutlicher.
  final double tiefe;

  const Staubverdacht({
    required this.x,
    required this.y,
    required this.radius,
    required this.tiefe,
  });

  @override
  String toString() =>
      'Staubverdacht(${x.toStringAsFixed(3)}/${y.toStringAsFixed(3)}, '
      'r=${radius.toStringAsFixed(4)}, t=${tiefe.toStringAsFixed(1)})';
}

/// Eine über mehrere Aufnahmen bestätigte Stelle.
class Staubstelle {
  final double x, y, radius;

  /// Auf wie vielen der untersuchten Aufnahmen die Stelle auftauchte.
  final int treffer;

  /// Wie viele Aufnahmen untersucht wurden.
  final int untersucht;

  const Staubstelle({
    required this.x,
    required this.y,
    required this.radius,
    required this.treffer,
    required this.untersucht,
  });

  double get anteil => untersucht == 0 ? 0 : treffer / untersucht;
}

/// Kantenlänge, auf die für die Suche verkleinert wird.
///
/// Ein Staubkorn ist auf einem 20-Megapixel-Bild ein paar Dutzend Pixel
/// gross und bleibt bei 1024 Punkten deutlich sichtbar. Auf der vollen
/// Auflösung zu suchen kostete das Zwanzigfache und fände dieselben Flecken.
const int staubSuchkante = 1024;

/// Radius der Weichzeichnung, die den „staubfreien" Hintergrund schätzt.
///
/// Muss deutlich grösser sein als ein Fleck und deutlich kleiner als ein
/// Bildmerkmal. Bei 1024 Punkten Kantenlänge sind acht Punkte beides.
const int staubHintergrundradius = 8;

/// Kleinster und grösster Fleck, in Punkten der verkleinerten Fassung.
const int staubMindestflaeche = 6;
const int staubHoechstflaeche = 400;

/// Wie viel dunkler als der geschätzte Hintergrund ein Punkt sein muss.
///
/// An einer Serie von 40 Aufnahmen einer EOS 60D gemessen: Mit 6 kamen 646
/// Verdachte je Aufnahme heraus – jede Blattkante, jeder Kiesel. Mit 14
/// bleiben Grössenordnungen weniger übrig, und das sind die, die man sich
/// überhaupt ansehen will.
const double staubMindesttiefe = 14.0;

/// Wie unruhig die Umgebung eines Flecks höchstens sein darf
/// (Standardabweichung der Grauwerte im Ring um ihn herum).
///
/// **Das ist das eigentliche Unterscheidungsmerkmal.** Sensorstaub sitzt in
/// einer glatten Fläche – Himmel, Wand, Wasser. Ein dunkler runder Punkt
/// mitten im Laub ist ein Blatt. Ohne diese Prüfung liefert schon eine
/// einzige Landschaftsaufnahme hunderte Verdachte, und die Bestätigung über
/// die Serie fischt daraus zufällige Übereinstimmungen heraus statt Staub.
const double staubHoechsteUnruhe = 6.0;

/// Wie rund ein Fleck sein muss (Fläche gegen die Fläche seines
/// umschliessenden Rechtecks). Ein Ast ist lang und dünn und fällt hier
/// heraus, ein Staubkorn füllt sein Kästchen zu gut drei Vierteln.
const double staubMindestrundheit = 0.55;

/// Sucht Fleckverdachte in einem Bild.
///
/// Das Verfahren in einem Satz: Was deutlich dunkler ist als eine stark
/// weichgezeichnete Fassung desselben Bildes, klein ist und rund, ist ein
/// Verdacht.
List<Staubverdacht> findeStaubverdacht(img.Image bild) {
  final lang = math.max(bild.width, bild.height);
  final faktor = lang > staubSuchkante ? staubSuchkante / lang : 1.0;
  final klein = faktor < 1.0
      ? img.copyResize(bild,
          width: (bild.width * faktor).round(),
          height: (bild.height * faktor).round(),
          interpolation: img.Interpolation.average)
      : bild;
  final grau = img.grayscale(klein);
  final breite = grau.width, hoehe = grau.height;
  if (breite < 32 || hoehe < 32) return const [];

  final hintergrund = img.gaussianBlur(
      img.Image.from(grau), radius: staubHintergrundradius);

  // Wie viel dunkler als der Hintergrund, Punkt für Punkt.
  final tiefe = Float64List(breite * hoehe);
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      final ist = grau.getPixel(x, y).r.toDouble();
      final soll = hintergrund.getPixel(x, y).r.toDouble();
      final d = soll - ist;
      tiefe[y * breite + x] = d > 0 ? d : 0;
    }
  }

  final gesehen = List<bool>.filled(breite * hoehe, false);
  final gefunden = <Staubverdacht>[];
  final kurzeKante = math.min(breite, hoehe);

  for (var start = 0; start < tiefe.length; start++) {
    if (gesehen[start] || tiefe[start] < staubMindesttiefe) continue;
    // Zusammenhängender Fleck über die vier Nachbarn.
    var minx = breite, maxx = -1, miny = hoehe, maxy = -1;
    var flaeche = 0;
    var summeTiefe = 0.0;
    var summeX = 0.0, summeY = 0.0;
    final schlange = Queue<int>()..add(start);
    gesehen[start] = true;
    while (schlange.isNotEmpty) {
      final punkt = schlange.removeFirst();
      final x = punkt % breite, y = punkt ~/ breite;
      flaeche++;
      summeTiefe += tiefe[punkt];
      summeX += x;
      summeY += y;
      if (x < minx) minx = x;
      if (x > maxx) maxx = x;
      if (y < miny) miny = y;
      if (y > maxy) maxy = y;
      // Über der Grenze abbrechen: Ein Fleck, der halb ins Bild reicht, ist
      // kein Staub, und ihn zu Ende zu verfolgen kostet nur Zeit.
      if (flaeche > staubHoechstflaeche) break;
      for (final nachbar in [
        if (x > 0) punkt - 1,
        if (x < breite - 1) punkt + 1,
        if (y > 0) punkt - breite,
        if (y < hoehe - 1) punkt + breite,
      ]) {
        if (!gesehen[nachbar] && tiefe[nachbar] >= staubMindesttiefe) {
          gesehen[nachbar] = true;
          schlange.add(nachbar);
        }
      }
    }
    if (flaeche < staubMindestflaeche || flaeche > staubHoechstflaeche) continue;

    final kastenBreite = maxx - minx + 1, kastenHoehe = maxy - miny + 1;
    final rundheit = flaeche / (kastenBreite * kastenHoehe);
    if (rundheit < staubMindestrundheit) continue;
    // Kein langes Gebilde: Ein Ast erfüllt die Rundheit im Kästchen
    // durchaus, ist aber viermal so lang wie breit.
    final streckung = math.max(kastenBreite, kastenHoehe) /
        math.min(kastenBreite, kastenHoehe);
    if (streckung > 2.0) continue;

    final mitteX = (summeX / flaeche).round();
    final mitteY = (summeY / flaeche).round();

    // Ein Fleck am äussersten Rand ist ein Randartefakt der Weichzeichnung,
    // kein Staub. Gemessen: Der einzige „Befund" des ersten Laufs sass bei
    // y = 0,988.
    const randabstand = staubHintergrundradius * 2;
    if (mitteX < randabstand ||
        mitteY < randabstand ||
        mitteX >= breite - randabstand ||
        mitteY >= hoehe - randabstand) {
      continue;
    }

    if (_unruhe(grau, mitteX, mitteY, math.max(kastenBreite, kastenHoehe)) >
        staubHoechsteUnruhe) {
      continue;
    }

    gefunden.add(Staubverdacht(
      x: mitteX / breite,
      y: mitteY / hoehe,
      radius: math.sqrt(flaeche / math.pi) / kurzeKante,
      tiefe: summeTiefe / flaeche,
    ));
  }
  return gefunden;
}

/// Standardabweichung der Grauwerte im Ring um einen Fleck.
///
/// Der Ring und nicht das Quadrat: Der Fleck selbst ist ja dunkel und
/// erhöhte die Streuung, egal wie glatt seine Umgebung ist.
double _unruhe(img.Image grau, int mx, int my, int fleckkante) {
  final innen = fleckkante;
  final aussen = fleckkante * 3;
  var n = 0;
  var summe = 0.0, summeQuadrate = 0.0;
  for (var dy = -aussen; dy <= aussen; dy++) {
    final y = my + dy;
    if (y < 0 || y >= grau.height) continue;
    for (var dx = -aussen; dx <= aussen; dx++) {
      if (dx.abs() <= innen && dy.abs() <= innen) continue;
      final x = mx + dx;
      if (x < 0 || x >= grau.width) continue;
      final wert = grau.getPixel(x, y).r.toDouble();
      n++;
      summe += wert;
      summeQuadrate += wert * wert;
    }
  }
  if (n < 8) return double.infinity;
  final mittel = summe / n;
  final varianz = summeQuadrate / n - mittel * mittel;
  return varianz <= 0 ? 0 : math.sqrt(varianz);
}

/// Ab welchem Anteil der untersuchten Aufnahmen eine Stelle als Staub gilt.
///
/// 0,6 – Staub sitzt auf JEDER Aufnahme derselben Sitzung, aber er ist nicht
/// auf jeder sichtbar: In einer dunklen oder unruhigen Fläche verschwindet
/// er. Wer 90 % verlangte, fände nur die gröbsten Körner; wer 30 % nähme,
/// bekäme jede Straßenlaterne, die in einer Serie zweimal an derselben
/// Stelle stand.
const double staubMindestanteil = 0.6;

/// Wie weit zwei Stellen auseinanderliegen dürfen, um als dieselbe zu
/// gelten – als Anteil der Bildkante. Zwei Prozent sind bei 6000 Punkten
/// gut hundert Pixel; enger angesetzt zerfiele ein Korn wegen der
/// Verkleinerung in mehrere Gruppen.
const double staubNaehe = 0.02;

/// Führt die Verdachte mehrerer Aufnahmen zusammen und behält, was
/// wiederkehrt.
///
/// [proAufnahme] ist je eine Verdachtsliste. Zurück kommen die Stellen, die
/// auf mindestens [mindestanteil] der Aufnahmen auftauchten – nach Häufigkeit
/// sortiert.
///
/// Reine Funktion ohne Bilder: Genau diese Zusammenführung ist der Teil, den
/// man nachrechnen kann, und der Teil, an dem sich entscheidet, ob aus
/// Fehlalarmen ein Befund wird.
List<Staubstelle> bestaetigeUeberSerie(
  List<List<Staubverdacht>> proAufnahme, {
  double mindestanteil = staubMindestanteil,
  double naehe = staubNaehe,
}) {
  if (proAufnahme.isEmpty) return const [];

  // Gruppen über alle Aufnahmen hinweg. Je Aufnahme zählt eine Gruppe
  // höchstens einmal – zwei Körner dicht nebeneinander in einem Bild dürfen
  // die Häufigkeit nicht verdoppeln.
  final mittenX = <double>[];
  final mittenY = <double>[];
  final radien = <double>[];
  final gewicht = <int>[];
  final aufnahmen = <Set<int>>[];

  for (var i = 0; i < proAufnahme.length; i++) {
    for (final v in proAufnahme[i]) {
      var ziel = -1;
      var besteEntfernung = naehe;
      for (var g = 0; g < mittenX.length; g++) {
        final d = math.sqrt(math.pow(mittenX[g] - v.x, 2) + math.pow(mittenY[g] - v.y, 2));
        if (d < besteEntfernung) {
          besteEntfernung = d;
          ziel = g;
        }
      }
      if (ziel < 0) {
        mittenX.add(v.x);
        mittenY.add(v.y);
        radien.add(v.radius);
        gewicht.add(1);
        aufnahmen.add({i});
      } else {
        // Laufender Mittelwert, damit die Gruppenmitte nicht am ersten
        // Fund klebt.
        final n = gewicht[ziel];
        mittenX[ziel] = (mittenX[ziel] * n + v.x) / (n + 1);
        mittenY[ziel] = (mittenY[ziel] * n + v.y) / (n + 1);
        radien[ziel] = (radien[ziel] * n + v.radius) / (n + 1);
        gewicht[ziel] = n + 1;
        aufnahmen[ziel].add(i);
      }
    }
  }

  final stellen = <Staubstelle>[];
  for (var g = 0; g < mittenX.length; g++) {
    final treffer = aufnahmen[g].length;
    if (treffer / proAufnahme.length < mindestanteil) continue;
    stellen.add(Staubstelle(
      x: mittenX[g],
      y: mittenY[g],
      radius: radien[g],
      treffer: treffer,
      untersucht: proAufnahme.length,
    ));
  }
  stellen.sort((a, b) => b.treffer.compareTo(a.treffer));
  return stellen;
}

