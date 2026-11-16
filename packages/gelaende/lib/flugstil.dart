/// **Zwei Arten, eine Spur abzufliegen.**
///
/// Der Flug, den es seit 3.x gibt, ist ein Überblick: Die Kamera steht
/// hoch über der Spur und zeigt die Gegend, durch die sie führt. Was er
/// nicht kann, ist das Gefühl, selbst auf dem Weg zu sein – dafür steht
/// die Kamera zu weit weg, und die dreifache Überhöhung macht jedes
/// Alpental zur Schlucht, sobald man tiefer geht.
///
/// „Nah dran" ist die andere Antwort, so wie sie Wandervideos in sozialen
/// Netzen zeigen: Die Kamera fliegt tief hinter einem leuchtenden Punkt
/// her, der Weg davor leuchtet, eine Tafel nennt am Anfang die Tour und
/// am Ende das Ziel, und zum Schluss hebt die Kamera zum Rundblick ab.
///
/// Hier steht nur die Rechnung – Kamera, Tempo, wann welche Tafel zu
/// sehen ist. Ohne Uhr und ohne Widget, damit sich jede Zahl prüfen
/// lässt, ohne ein Fenster zu öffnen.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/animation.dart' show Curves;

import 'gelaendeflug.dart';
import 'gelaendesicht.dart';

/// Wie der Flug die Spur zeigt.
enum Flugstil {
  /// Hoch über der Spur, die ganze Gegend im Blick – der bisherige Flug.
  ueberblick,

  /// Tief hinter einem Leuchtpunkt, die Strecke voraus leuchtet.
  nahDran;

  /// Wie stark die Höhe übertrieben wird.
  ///
  /// **Anderthalbfach statt dreifach.** Aus der Nähe wirkt jede
  /// Überhöhung doppelt: Die Hänge stehen nicht nur steiler, sie stehen
  /// auch vor der Kamera. Bei dreifacher Überhöhung zeigte der
  /// Verfolgerflug am Stoos-Grat (Klingenstock–Fronalpstock) einen
  /// Grat wie eine Messerschneide; massstäblich (1,0) sah dagegen eine
  /// Mittelgebirgswanderung im Harz aus wie eine Fahrt über eine Wiese.
  /// 1,5 ist der Wert, bei dem beide noch nach sich selbst aussehen.
  double get ueberhoehung => switch (this) {
    Flugstil.ueberblick => gelaendeUeberhoehung,
    Flugstil.nahDran => 1.5,
  };

  /// Ob die gezeichnete Spur auf dem Gelände liegt statt auf der
  /// gemessenen Höhe.
  ///
  /// **Aus der Nähe sieht man das Rauschen der Höhenmessung.** Ein
  /// Telefon misst die Höhe auf zehn, zwanzig Meter genau; von oben ist
  /// das unsichtbar, von zweihundert Metern hinter dem Weg schwebt die
  /// Linie dann stellenweise über dem Hang und taucht anderswo hinein.
  /// Die **Zahlen** bleiben die gemessenen – nur die Linie folgt dem
  /// Boden, auf dem der Weg ja tatsächlich liegt.
  bool get spurAufDemGelaende => this == Flugstil.nahDran;

  /// Ob das Gelände je Gitterpunkt statt je Dreieck schattiert wird
  /// (siehe `baueNetz`, Schalter `weich`).
  bool get weicheSchattierung => this == Flugstil.nahDran;

  /// Wie fein das Gelände gerechnet wird, über die längere Seite.
  ///
  /// Aus der Nähe wird jede Masche grösser: Bei 96 Maschen über die
  /// zehn Kilometer, die dieser Stil lädt ([mindestrandMeter]), wäre eine
  /// Masche über hundert Meter breit, und am Grat sähe man die Kanten der
  /// Dreiecke. 192 halbiert das; gemessen kostet es 2,8 statt 0,9 ms je
  /// Bild in Dart (siehe [gelaendeGitterkante]).
  int get gitterkante => switch (this) {
    Flugstil.ueberblick => 96,
    Flugstil.nahDran => 192,
  };

  /// Wie viel Landschaft mindestens um die Spur herum geladen wird, in
  /// Metern je Seite.
  ///
  /// **Aus der Nähe sieht man bis zum Horizont.** Der Überblick schaut
  /// von oben auf die Spur, und ein Fünftel ihrer Ausdehnung als Rand
  /// reicht. Der Verfolger schaut nach vorn; am Stoos-Grat stand hinter
  /// jedem Gipfel nur Himmel, weil das Gelände 600 Meter neben dem Weg
  /// aufhörte. Drei Kilometer zeigen den See und die nächsten Berge –
  /// mehr ginge auf Kosten der Feinheit, denn Gitter und Netz haben eine
  /// feste Zahl von Punkten für den ganzen Ausschnitt.
  double get mindestrandMeter => switch (this) {
    Flugstil.ueberblick => 0,
    Flugstil.nahDran => 3000,
  };
}

/// Der Ausschnitt, der für eine Spur in [sued]…[ost] geladen wird.
///
/// Ein Fünftel der Ausdehnung als Rand: Ohne ihn endete die Landschaft
/// genau an der Spur, und ein Weg, der am Abgrund der Welt entlangläuft,
/// sieht falsch aus. Dazu eine Mindestausdehnung, damit eine Spur, die
/// auf der Stelle aufgezeichnet wurde, kein Rechteck von null Grad
/// ergibt – und im Stil „Nah dran" der Rand bis zum Horizont
/// ([Flugstil.mindestrandMeter]).
({double sued, double west, double nord, double ost}) gelaendeAusschnitt({
  required double sued,
  required double west,
  required double nord,
  required double ost,
  Flugstil stil = Flugstil.ueberblick,
}) {
  final mitte = (sued + nord) / 2;
  final randB = math.max(
    math.max((nord - sued) * 0.2, 0.005),
    stil.mindestrandMeter / meterJeGradBreite,
  );
  final randL = math.max(
    math.max((ost - west) * 0.2, 0.005),
    stil.mindestrandMeter / meterJeGradLaenge(mitte),
  );
  return (
    sued: sued - randB,
    west: west - randL,
    nord: nord + randB,
    ost: ost + randL,
  );
}

/// Wie lange der eigentliche Flug „Nah dran" dauern soll.
///
/// Fünfundvierzig Sekunden, so lang wie ein kurzes Video, das man
/// weitergibt. Das Tempo richtet sich danach, aber nur innerhalb von
/// [nahDranTempo] – ein Spaziergang soll nicht schleichen, und eine
/// Radtour nicht vorbeirasen.
const Duration nahDranZiel = Duration(seconds: 45);

/// Das Tempo über Grund, in Metern je Sekunde.
///
/// **Zwischen 60 und 250, und deutlich langsamer als der Überblick**
/// (300). Aus zweihundert Metern Abstand sieht ein Weg bei 300 m/s aus
/// wie ein Streifen; bei 100 erkennt man die Kehren. Eine Tour über
/// 4,5 Kilometer fliegt so in 45 Sekunden, eine über 16 in gut einer
/// Minute.
double nahDranTempo(double laengeMeter) {
  if (!(laengeMeter > 0)) return 60;
  return (laengeMeter / (nahDranZiel.inMilliseconds / 1000)).clamp(60.0, 250.0);
}

/// Über wie viele Meter die Blickrichtung geglättet wird.
///
/// Dieselbe Überlegung wie bei [Gelaendeflug.blickglaettung], nur in
/// Sekunden gedacht: Gut drei Sekunden Flug, damit eine Kehre als Bogen
/// erscheint und nicht als Ruck. Bei 100 m/s sind das 320 Meter – die
/// 900 des Überblicks wären hier neun Sekunden, und die Kamera sähe an
/// jeder Kurve lange am Weg vorbei.
double nahDranBlickglaettung(double tempo) => (tempo * 3.2).clamp(250.0, 900.0);

/// Wie weit die Kamera hinter dem Punkt steht, auf den sie blickt.
///
/// Mit dem Tempo wachsend: Je schneller es geht, desto mehr Vorlauf
/// braucht das Auge. Drei Sekunden Flug – bei 100 m/s also 300 Meter.
/// Näher kommt man dem Gelände, als Höhenmodell und Kacheln es hergeben:
/// Bei 250 Metern zeigten sich am Stoos die Maschen des Netzes.
double nahDranAbstand(double tempo) => (tempo * 3.0).clamp(200.0, 700.0);

/// Die Neigung des Verfolgerblicks – rund 31 Grad.
///
/// Flacher sieht man vom Gelände nur noch die nächste Kuppe, steiler
/// wird daraus wieder der Blick von oben. Bei 0,55 liegen am Stoos See
/// und Gegenhang im oberen Drittel, wo das Auge den Horizont erwartet;
/// bei 0,62 standen sie in der Bildmitte.
const double nahDranNeigung = 0.55;

/// Wo im Bild der Punkt steht, auf den die Kamera blickt – als Anteil
/// der Höhe von oben.
///
/// Tief, damit davor viel Weg zu sehen ist: Der Leuchtpunkt geht voraus,
/// und was kommt, ist interessanter als das, was war. Im Hochformat
/// noch etwas tiefer, weil dort mehr Höhe zu füllen ist.
double nahDranMitte({required double breite, required double hoehe}) =>
    hoehe > breite ? 0.72 : 0.68;

/// Die Kamera des Verfolgerflugs zu einem [stand].
///
/// [zoom] und [versatz] kommen von der Hand am Bildschirm – zoomen und
/// sich umsehen soll man auch hier können. Im Video sind beide neutral.
Gelaendekamera verfolgerkamera({
  required Flugstand stand,
  required double breite,
  required double hoehe,
  required double tempo,
  double neigung = nahDranNeigung,
  double zoom = 1,
  double versatz = 0,
}) => Gelaendekamera(
  drehung: stand.drehung + versatz,
  neigung: neigung,
  entfernung: nahDranAbstand(tempo) / zoom,
  brennweite: math.min(breite, hoehe) * 1.1,
  mitte: Offset(breite / 2, hoehe * nahDranMitte(breite: breite, hoehe: hoehe)),
  blickpunkt: stand.blickpunkt,
);

/// Der Rundblick am Ende – wohin die Kamera über das Ziel abhebt.
///
/// **Aufsteigen, etwas flacher werden und dabei ein Stück herumdrehen.**
/// Der Überblick zieht am Ende auf die ganze Landschaft auf; aus der
/// Nähe wäre das ein Sprung von zweihundert Metern auf zehn Kilometer.
/// Hier bleibt das Ziel in der Mitte, die Kamera geht auf das
/// Zweieinhalbfache zurück, und die halbe Drehung (rund 30 Grad) gibt
/// den Blick auf das frei, was neben dem Weg lag – am Stoos der
/// Vierwaldstättersee.
Gelaendekamera panoramakamera(Gelaendekamera verfolger) => verfolger.kopieMit(
  drehung: verfolger.drehung + 0.55,
  neigung: math.max(0.3, verfolger.neigung - 0.12),
  entfernung: verfolger.entfernung * 2.5,
  mitte: Offset(verfolger.mitte.dx, verfolger.mitte.dy * 0.85),
);

/// Wie viel der Vorführung Einflug und Abspann einnehmen.
///
/// Der Abspann ist länger als beim Überblick (0,10): Der Rundblick ist
/// eine eigene Einstellung mit einer Tafel darüber, kein Aufziehen auf
/// eine Karte, und braucht Zeit, um anzukommen.
({double einflug, double abspann}) flugAnteile(Flugstil stil) => switch (stil) {
  Flugstil.ueberblick => (einflug: 0.07, abspann: 0.10),
  Flugstil.nahDran => (einflug: 0.08, abspann: 0.15),
};

/// Wie deutlich die Titeltafel zu sehen ist.
///
/// Sie steht vom ersten Bild an und bleibt, bis die Kamera hinter dem
/// Startpunkt angekommen ist und noch dreieinhalb Sekunden länger –
/// lange genug, um drei Zeilen zu lesen. **In Sekunden und nicht als
/// Anteil**, weil die Lesezeit nicht davon abhängt, wie lang die Tour
/// ist: Bei einem Video von zwei Minuten wäre ein fester Anteil eine
/// halbe Minute Tafel.
double titeltafelDeckkraft({
  required double sekunde,
  required double einflugEnde,
}) {
  if (sekunde < 0) return 0;
  const auf = 0.6;
  const halten = 3.5;
  const ab = 0.8;
  final ein = Curves.easeOut.transform((sekunde / auf).clamp(0.0, 1.0));
  final aus = ((sekunde - einflugEnde - halten) / ab).clamp(0.0, 1.0);
  return ein * (1 - Curves.easeIn.transform(aus));
}

/// Wie deutlich die Zieltafel zu sehen ist – sie kommt mit dem Abspann
/// und bleibt bis zum letzten Bild.
///
/// Erst ab einem Fünftel des Abspanns: Die Kamera soll erst abheben, bevor
/// sich etwas vor das Bild legt.
double zieltafelDeckkraft(double abspann) =>
    Curves.easeOut.transform(((abspann - 0.2) / 0.3).clamp(0.0, 1.0));

/// Wie deutlich ein Foto als Tafel zu sehen ist.
///
/// **Anders als im Überblick bleibt es nicht stehen, bis das nächste
/// kommt.** Dort ist es ein Vorschaubild in der Ecke; hier ist es eine
/// Tafel über einem Drittel des Bildes, und die soll die Landschaft
/// nicht für den Rest des Fluges verdecken. Es blendet über [einblendweg]
/// auf, steht [haltMeter] lang und blendet ebenso wieder ab.
double fototafelDeckkraft({
  required double meter,
  required double fotoMeter,
  required double einblendweg,
  required double haltMeter,
}) {
  final her = meter - fotoMeter;
  if (her < 0 || einblendweg <= 0) return 0;
  final auf = (her / einblendweg).clamp(0.0, 1.0);
  final ab = ((her - einblendweg - haltMeter) / einblendweg).clamp(0.0, 1.0);
  return Curves.easeOut.transform(auf) * (1 - Curves.easeIn.transform(ab));
}

/// Ein Name an einer Stelle der Landschaft – ein Gipfel, eine Hütte.
typedef Ortsname = ({Raumpunkt ort, String name});

/// Der Name, der [punkt] am nächsten liegt, aber höchstens [grenze]
/// Meter weg – waagerecht gemessen.
///
/// So heisst der Anfang der Tour „Klingenstock" und das Ende
/// „Fronalpstock": die Bergstation und der Gipfel, an denen die Spur
/// beginnt und endet. Liegt nichts in der Nähe, gibt es keinen Namen
/// statt eines falschen – ein Gipfel zwei Kilometer neben dem Weg ist
/// nicht das Ziel.
String? naechsterName(List<Ortsname> namen, Raumpunkt punkt, double grenze) {
  String? bester;
  var abstand = grenze * grenze;
  for (final n in namen) {
    final dx = n.ort.x - punkt.x;
    final dy = n.ort.y - punkt.y;
    final d = dx * dx + dy * dy;
    if (d <= abstand) {
      abstand = d;
      bester = n.name;
    }
  }
  return bester;
}

/// Ob eine Spur dort endet, wo sie begann.
///
/// Dann gibt es kein Ziel, das sich von „Start bis Ziel" nennen liesse –
/// die Tafel sagt „Rundweg ab …". Als nah gilt ein Dreissigstel der
/// Länge, mindestens 250 Meter: Wer am Parkplatz losgeht und an der
/// Bushaltestelle daneben ankommt, ist eine Runde gegangen.
bool istRundweg(Gelaendeflug flug) {
  if (!flug.moeglich) return false;
  final a = flug.punktBei(0);
  final b = flug.punktBei(flug.laengeMeter);
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy) <= math.max(250.0, flug.laengeMeter / 30);
}
