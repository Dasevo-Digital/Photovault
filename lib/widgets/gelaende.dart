/// Die Landschaft – Dreiecke aus einem Höhengitter, mit `drawVertices`.
///
/// **Ohne 3D-Bibliothek und ohne Shader.** `Canvas.drawVertices` ist
/// Flutter selbst; was fehlt, ist allein die Kamera, und die steht als
/// reine Rechnung in `gelaendesicht.dart`. Bei MapLibre trug ein Paket
/// auf pub.dev einen grünen Haken für Linux und scheiterte dort trotzdem
/// – hier kommt nichts dazu, was scheitern könnte.
///
/// Die Karte liegt als Textur darauf: Geländehöhen sind keine Karte, und
/// eine Wanderung vor einer namenlosen Landschaft beantwortet keine
/// Frage.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show DisabledMapCachingProvider;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'wisch_zoom.dart' show istWischen;
import '../utils/dauertext.dart';
import '../services/gelaendeflug.dart';
import '../theme/app_spacing.dart';

import '../services/gelaendekacheln.dart';
import '../services/blocktexturen.dart';
import '../services/gelaendetextur.dart';
import '../services/gelaendesicht.dart';
import '../services/lichtstimmung.dart';
import '../services/flugvideo.dart';
import '../services/gelaendeebenen.dart';
import '../services/meldungsdienst.dart';
import 'gelaendeschilder.dart';

/// Wie dicht der Dunst in der Ferne höchstens wird.
///
/// Nicht 1: Auch der fernste Grat soll noch als Grat erkennbar sein und
/// nicht als Nebelbank. Am gerenderten Bild entschieden – 0,72 wusch die
/// Gipfelkette am oberen Rand weiss.
const double _dunstStaerke = 0.55;

/// Wie schnell der Dunst mit der Tiefe zunimmt.
///
/// **Warum eine Exponentialkurve und keine Potenz.** Der erste Versuch
/// nahm `t³`. In der Übersicht sah das gut aus, im Flug war der Dunst
/// unsichtbar: Dort liegt der fernste Eckpunkt des ganzen Gitters
/// fünfzehn Kilometer weit weg, der obere Bildrand aber nur fünf – und
/// `0,33³` sind drei Prozent. Eine Atmosphäre schluckt exponentiell, und
/// genau die Kurve gibt auch nahen Unterschieden Gewicht.
const double _dunstDichte = 2.2;

/// Höchstens so viele Gitterpunkte je Seite.
///
/// **Gemessen, nicht geschätzt** (`gelaende_messung_test.dart`, auf
/// einem Mac):
///
/// ```
/// Kante | Dreiecke | Zeichnen
///    32 |    1.922 |  0,24 ms
///    64 |    7.938 |  0,46 ms
///    96 |   18.050 |  0,86 ms
///   128 |   32.258 |  1,83 ms
///   192 |   72.962 |  2,82 ms
///   256 |  130.050 |  4,71 ms
/// ```
///
/// Gemessen ist dabei **nur die Rechnung in Dart** – das Aufzeichnen der
/// Dreiecke. Was die Grafikkarte daraus macht, steht hier nicht; das
/// zeigt erst die laufende App. Deshalb nicht 256, obwohl 4,71 ms in ein
/// Bild von 16,7 ms passen: Auf einer langsameren Maschine ist das ein
/// Vielfaches, und die Grafikkarte kommt obendrauf. 96 lässt Luft und
/// war am Bildschirm nicht von 192 zu unterscheiden.
const int gelaendeGitterkante = 96;

/// Die Farbe des Geländes **ohne** Karte darauf – ein sandiges Braun,
/// wie es Reliefkarten benutzen.
///
/// Liegt eine Karte darüber, muss stattdessen Weiss genommen werden:
/// `modulate` multipliziert Karte und Eckpunktfarbe, und eine gefärbte
/// Grundlage dunkelte die Karte ein zweites Mal ab. Am Bildschirm sah
/// das aus wie eine Landschaft bei Nacht.
const Color gelaendeGrundfarbe = Color(0xFFB0A99A);

/// Ein Punkt der Spur, so wie ihn die Geländeansicht braucht.
///
/// Die Zeit ist seit dem Flug dabei: Ohne sie gibt es kein Tempo, und ein
/// Flug, der nicht sagt, wie schnell jemand unterwegs war, lässt die
/// wichtigste Zahl der Aufzeichnung liegen. Sie darf fehlen – eine
/// geplante Route hat keine.
typedef Gelaendespurpunkt = ({
  double breite,
  double laenge,
  double? hoehe,
  DateTime? zeit,
});

/// Ein Stück der Landschaft mit **eigener Textur**.
///
/// **Warum die Landschaft überhaupt zerfällt.** Bis hierher trug sie ein
/// einziges Bild, und dessen Stufe war an die des Höhengitters gekettet:
/// bei der Wanderung durch das Ilsetal Stufe 14, also 5,90 Meter je
/// Bildpunkt. Daher der Brei. Eine einzige Textur der Stufe 18 wären
/// 270 MB in einer Bildfläche – nicht zu halten und nicht anzulegen.
///
/// Also viele kleine. Jeder Block deckt genau **eine Kachel der
/// Grundstufe** ab (siehe [Texturblock]) und wählt seine eigene Stufe
/// nach der Entfernung zur Kamera: nah scharf, fern grob. Geladen wird
/// nur, was zu sehen ist.
///
/// **Jeder Block hat seine eigenen Puffer**, und das ist keine
/// Bequemlichkeit. `ui.Vertices.raw` kopiert die übergebenen Felder nach
/// nativ; ein gemeinsames Feld für alle Blöcke würde bei hundert
/// Zeichenzügen hundertmal vollständig kopiert. Ausserdem verweist
/// Flutter auf Eckpunkte nur mit sechzehn Bit – über 65.536 Eckpunkte
/// hinaus gäbe es keine Zeichenreihenfolge mehr, und je Block sind es
/// wenige hundert.
class Blocknetz {
  /// Welches Kachelrechteck – die Adresse, unter der die Textur liegt.
  final Texturblock block;

  /// Je Eckpunkt drei Zahlen: Ost, Nord, Höhe – alles in Metern,
  /// bezogen auf die Mitte des **ganzen** Ausschnitts.
  final Float32List ecken;

  /// Je Eckpunkt zwei Zahlen: die Stelle auf der Textur **dieses
  /// Blocks**, von 0 bis 1.
  ///
  /// Blocklokal und nicht über den ganzen Ausschnitt: Jeder Block trägt
  /// sein eigenes Bild, und dessen Kanten sind seine Kachelkanten.
  final Float32List texturstellen;

  /// Je Eckpunkt eine Farbe – die Schattierung.
  final Int32List farben;

  /// Je Eckpunkt: wie weit im Inneren des **Ausschnitts** er liegt. 0 am
  /// Rand, 1 innen.
  ///
  /// Gegen den Ausschnitt gerechnet und nicht gegen den Block, sonst
  /// bekäme jeder Block seinen eigenen weichen Saum und die Landschaft
  /// sähe aus wie ein Fliesenspiegel.
  final Float32List randnaehe;

  /// Die Mitte des Blocks in Netzmetern – für die Reihenfolge.
  final double mitteX;
  final double mitteY;

  /// Der Kasten, in dem dieser Block ganz enthalten ist – in Netzmetern.
  ///
  /// Acht Ecken statt hunderter Eckpunkte: Damit lässt sich in einem
  /// Bruchteil der Zeit entscheiden, ob ein Block überhaupt ins Bild
  /// ragt. Siehe [Gelaendemaler.imBild].
  final double westM;
  final double ostM;
  final double suedM;
  final double nordM;
  final double tiefM;
  final double hochM;

  Blocknetz({
    required this.block,
    required this.ecken,
    required this.texturstellen,
    required this.farben,
    required this.randnaehe,
    required this.mitteX,
    required this.mitteY,
    required this.westM,
    required this.ostM,
    required this.suedM,
    required this.nordM,
    required this.tiefM,
    required this.hochM,
  });

  int get eckenzahl => ecken.length ~/ 3;
  int get dreiecke => ecken.length ~/ 9;

  /// Kratzpapier für den Maler.
  ///
  /// Alles hier hängt von der Kamera ab und entsteht in **jedem** Bild
  /// neu – aber es entsteht in denselben Puffern. Am Netz und nicht am
  /// Maler, weil der Maler je Bild neu gebaut wird.
  ///
  /// **Gemessen, warum das nicht egal ist.** Vorher legte der Maler je
  /// Bild eine neue `Float32List` für die Bildstellen (440 KB), eine
  /// Liste von Wahrheitswerten (55 KB) und noch einmal 440 KB für die
  /// Texturstellen an. Bei sechzig Bildern in der Sekunde – und der Flug
  /// ist eine Bewegung – sind das rund sechzig Megabyte Abfall je
  /// Sekunde, den der Aufräumer wieder einsammeln muss.
  late final Int32List dunstfarben = Int32List(eckenzahl);
  late final Float32List tiefen = Float32List(eckenzahl);
  late final Float32List bildstellen = Float32List(eckenzahl * 2);
  late final Uint8List hinterDerKamera = Uint8List(eckenzahl);

  /// Die Zeichenreihenfolge der Eckpunkte – von hinten nach vorn.
  late final Uint16List reihenfolge = Uint16List(eckenzahl);

  /// Zähler für die Eimersortierung, einer je Tiefenstufe plus einer.
  late final Int32List eimer = Int32List(tiefenstufen + 1);

  /// In wie viele Tiefenstufen einsortiert wird.
  ///
  /// Zweitausend bei einer Landschaft von zehn Kilometern sind fünf Meter
  /// je Stufe – feiner, als zwei Dreiecke desselben Gitterfeldes
  /// auseinanderliegen. Innerhalb einer Stufe bleibt die Gitterreihenfolge
  /// erhalten, weil die Zählsortierung sie nicht antastet.
  static const int tiefenstufen = 2048;

  /// Die kleinste und grösste Tiefe der letzten Projektion – der Maler
  /// braucht beide über **alle** Blöcke, damit der Dunst über die ganze
  /// Landschaft dieselbe Skala hat.
  double nahste = double.infinity;
  double fernste = 0;
}

/// Ein Foto, das beim Vorbeifliegen auftaucht.
///
/// Die Stelle steht als **Weg in Metern** und nicht als Koordinate: Wo
/// auf der Spur ein Foto liegt, weiss der Aufrufer besser – er kennt
/// beide. Hier zählt nur, wann es dran ist.
typedef Flugfoto = ({
  /// Wie weit auf der Spur, in Metern von deren Anfang.
  double meter,

  /// Das Bild – als Anbieter und nicht als Datei, damit die Landschaft
  /// nicht wissen muss, wie eine Bibliothek ihre Vorschauen ablegt.
  ImageProvider bild,

  /// Was darunter steht – Uhrzeit oder nichts.
  String? unterschrift,
});

/// Was ausgegeben werden soll – Ziel, Kantenlängen und Dauer.
///
/// **Warum nicht nur eine Datei.** Bis 3.5.1 gab die Ansicht das Video
/// starr in 1920 × 1080 und in der Länge aus, die der Flug auf dem
/// Bildschirm gerade hatte. Beides sind aber Fragen an den, der das
/// Video haben will: Ein Video zum Verschicken darf kleiner sein, eines
/// für einen grossen Bildschirm grösser, und wie lange man zusehen mag,
/// entscheidet nicht die Länge der Wanderung.
typedef Videoauftrag = ({
  File ziel,
  int breite,
  int hoehe,
  Duration dauer,
});

/// Die fertig gerechneten Dreiecke – einmal je Gitter, nicht je Bild.
///
/// Getrennt vom Zeichnen, weil sich beim Drehen nur die Kamera ändert
/// und nicht das Gelände: Das Gitter in jedem Bild neu abzutasten wäre
/// der teuerste Teil, und er ist unnötig.
class Gelaendenetz {
  /// Die Blöcke, zeilenweise von Nordwesten nach Südosten.
  final List<Blocknetz> bloecke;

  /// Die Ausdehnung in Metern – für den Anfangsabstand der Kamera.
  final double breiteMeter;
  final double hoeheMeter;

  /// Der Ausschnitt in Grad – gebraucht, um eine Übersichtskarte auf die
  /// einzelnen Blöcke abzubilden und um Kacheln nachzuladen.
  final double sued;
  final double west;
  final double nord;
  final double ost;

  /// Auf welcher Kachelstufe die Blöcke abgesteckt sind.
  final int grundstufe;

  /// Die Höhe, die als Null gilt – die Mitte zwischen tiefstem und
  /// höchstem Punkt.
  ///
  /// **Steht hier und wird nicht zweimal gerechnet.** Die Spur wird
  /// getrennt vom Netz in Meter umgerechnet und muss denselben Nullpunkt
  /// benutzen; rechnete sie ihn selbst aus einem anders beschnittenen
  /// Gitter, läge der Weg um die Differenz über oder unter dem Boden.
  final double mittlereHoehe;

  Gelaendenetz({
    required this.bloecke,
    required this.mittlereHoehe,
    required this.breiteMeter,
    required this.hoeheMeter,
    required this.sued,
    required this.west,
    required this.nord,
    required this.ost,
    required this.grundstufe,
  });

  int get dreiecke {
    var n = 0;
    for (final b in bloecke) {
      n += b.dreiecke;
    }
    return n;
  }
}

/// Wie viele Blöcke die Landschaft höchstens bekommt.
///
/// Jeder Block ist ein eigener Zeichenzug mit eigenem Shader; die lassen
/// sich nicht zusammenfassen. Hundertvierundvierzig ist die Zahl, bis zu
/// der `tool/messe_gelaendemaler_test.dart` keinen Ausschlag zeigt.
/// Darüber wird die Grundstufe gröber – eine Zwölf-Kilometer-Tour hätte
/// auf Stufe 16 über tausend Blöcke, und die sieht ohnehin niemand aus
/// der Nähe.
const int gelaendeHoechstensBloecke = 144;

/// Die feinste Grundstufe, deren Blockzahl für diesen Ausschnitt noch
/// unter [gelaendeHoechstensBloecke] bleibt.
int passendeGrundstufe({
  required double sued,
  required double west,
  required double nord,
  required double ost,
  int feinste = texturGrundstufe,
}) {
  for (var z = feinste; z > 0; z--) {
    final n = texturbloecke(
            sued: sued, west: west, nord: nord, ost: ost, grundstufe: z)
        .length;
    if (n <= gelaendeHoechstensBloecke) return z;
  }
  return 1;
}

/// Baut die Dreiecke eines Gitters – einen Satz je Block.
///
/// [ueberhoehung] übertreibt die Höhe; siehe [gelaendeUeberhoehung] für
/// den Grund.
///
/// **Das Gitter wird an den Blockgrenzen ausgerichtet und nicht
/// gleichmässig über den Ausschnitt gelegt.** Läge es gleichmässig, ginge
/// eine Masche irgendwo quer über eine Blockgrenze; ihre Texturstellen
/// zeigten dann über den Rand des Blockbildes hinaus, und `TileMode.clamp`
/// zöge dort den letzten Bildpunkt in die Länge – ein Schmierstreifen
/// entlang jeder Blockkante. Deshalb bekommt jeder Block sein eigenes
/// Untergitter, das genau an seinen Kanten anfängt und aufhört.
///
/// **Und deshalb klaffen die Blöcke trotzdem nicht auseinander.** Zwei
/// Nachbarn teilen sich eine Kante; beide tasten das Höhengitter an
/// **denselben** Grad-Koordinaten ab und bekommen damit dieselben Höhen.
/// Innerhalb einer Blockzeile ist auch die Unterteilung dieselbe, weil
/// alle Blöcke der Zeile denselben Breitenbereich haben.
Gelaendenetz baueNetz(
  Hoehengitter gitter, {
  double ueberhoehung = gelaendeUeberhoehung,
  int kante = gelaendeGitterkante,
  Color grundfarbe = gelaendeGrundfarbe,
  Lichtstimmung stimmung = stimmungMittag,
  int? grundstufe,
  double reliefstaerke = 1.0,
}) {
  final mitteBreite = (gitter.nord + gitter.sued) / 2;
  final mLaenge = meterJeGradLaenge(mitteBreite);
  final breiteMeter = (gitter.ost - gitter.west) * mLaenge;
  final hoeheMeter = (gitter.nord - gitter.sued) * meterJeGradBreite;
  final spanne = gitter.spanne;
  final mittlereHoehe = (spanne.tief + spanne.hoch) / 2;

  final stufe = grundstufe ??
      passendeGrundstufe(
          sued: gitter.sued,
          west: gitter.west,
          nord: gitter.nord,
          ost: gitter.ost);
  final bloecke = texturbloecke(
      sued: gitter.sued,
      west: gitter.west,
      nord: gitter.nord,
      ost: gitter.ost,
      grundstufe: stufe);

  // So viele Maschen je Block, dass die Landschaft insgesamt etwa so fein
  // bleibt wie bisher: [kante] Punkte über die längere Seite des
  // Ausschnitts, verteilt auf die Blöcke dieser Seite.
  final spaltenBloecke =
      kachelX(gitter.ost, stufe) - kachelX(gitter.west, stufe) + 1;
  final zeilenBloecke =
      kachelY(gitter.sued, stufe) - kachelY(gitter.nord, stufe) + 1;
  final maschen = math
      .max(2, (kante / math.max(spaltenBloecke, zeilenBloecke)).round())
      .clamp(2, 64);

  /// Wie weit im Inneren des **Ausschnitts** ein Punkt liegt: 0 auf der
  /// Kante, 1 ab einem Zwanzigstel Abstand.
  ///
  /// Ein Zwanzigstel. Ein Zehntel war zu breit: In der Übersicht lag ein
  /// handbreiter weisser Streifen über der Gipfelkette, und der Saum fiel
  /// mehr auf als die harte Kante, die er ersetzen sollte.
  const saumanteil = 1 / 20;
  final saumL = (gitter.ost - gitter.west) * saumanteil;
  final saumB = (gitter.nord - gitter.sued) * saumanteil;
  double innen(double breite, double laenge) {
    final dl = math.min(laenge - gitter.west, gitter.ost - laenge) / saumL;
    final db = math.min(breite - gitter.sued, gitter.nord - breite) / saumB;
    return math.min(dl, db).clamp(0.0, 1.0);
  }

  final netze = <Blocknetz>[];
  for (final b in bloecke) {
    // Der Block, beschnitten auf den Ausschnitt. Ein Block ragt in der
    // Regel darüber hinaus – die Geometrie hört am Ausschnitt auf, die
    // Textur behält ihre vollen Kachelkanten.
    final west = math.max(b.west, gitter.west);
    final ost = math.min(b.ost, gitter.ost);
    final nord = math.min(b.nord, gitter.nord);
    final sued = math.max(b.sued, gitter.sued);
    if (!(ost > west) || !(nord > sued)) continue;

    Raumpunkt punkt(double breite, double laenge) {
      final h = gitter.anOrt(breite, laenge) ?? mittlereHoehe;
      return (
        x: ((laenge - gitter.west) / (gitter.ost - gitter.west) - 0.5) *
            breiteMeter,
        y: (0.5 - (gitter.nord - breite) / (gitter.nord - gitter.sued)) *
            hoeheMeter,
        z: (h - mittlereHoehe) * ueberhoehung,
      );
    }

    // Die Texturstelle: der Nachkommaanteil der Kachelkoordinate auf der
    // Grundstufe. In Mercator gerechnet, weil die Kachel es ist.
    double u(double laenge) => kachelXGenau(laenge, stufe) - b.spalte;
    double v(double breite) => kachelYGenau(breite, stufe) - b.zeile;

    // **Ein beschnittener Block bekommt weniger Maschen.** Der äusserste
    // Block einer Reihe ragt in der Regel über den Ausschnitt hinaus und
    // behält davon manchmal nur ein Zehntel. Bekäme er trotzdem die volle
    // Zahl, lägen seine Maschen zehnmal so dicht wie überall sonst –
    // Dreiecke, die niemand sieht, und ein Saum, der aus lauter winzigen
    // Maschen besteht.
    //
    // Dass die Nachbarn trotzdem zusammenpassen, liegt an der Herkunft
    // der Zahl: Sie hängt allein an der Breite der **Spalte** und der
    // Höhe der **Zeile**, und die sind für alle Blöcke einer Spalte
    // beziehungsweise Zeile dieselben.
    final maschenX =
        math.max(1, (maschen * (ost - west) / (b.ost - b.west)).round());
    final maschenY =
        math.max(1, (maschen * (nord - sued) / (b.nord - b.sued)).round());
    final felder = maschenX * maschenY;
    final ecken = Float32List(felder * 2 * 3 * 3);
    final texturstellen = Float32List(felder * 2 * 3 * 2);
    final farben = Int32List(felder * 2 * 3);
    final randnaehe = Float32List(felder * 2 * 3);

    var e = 0;
    var tz = 0;
    var f = 0;
    void lege(Raumpunkt p, double breite, double laenge, int farbe) {
      ecken[e++] = p.x;
      ecken[e++] = p.y;
      ecken[e++] = p.z;
      texturstellen[tz++] = u(laenge);
      texturstellen[tz++] = v(breite);
      final rand = innen(breite, laenge);
      randnaehe[f] = rand;
      // Die Deckkraft steckt in der Eckpunktfarbe: Am Rand des
      // Ausschnitts wird das Gelände durchsichtig, und der Himmel scheint
      // durch.
      //
      // **Nicht als Dunst darüber, sondern als Durchsichtigkeit.** Der
      // erste Versuch legte den Saum in die Dunstschicht. Das ergab ein
      // weisses Band quer über die Gipfelkette: Der nördliche Rand liegt
      // weit hinten und ragt zwischen den Bergen hervor, und dort war er
      // nicht durchsichtig, sondern weiss angestrichen. Sichtbar wurde es
      // nur am gerenderten Bild.
      farben[f++] =
          (farbe & 0x00FFFFFF) | ((rand * 255).round().clamp(0, 255) << 24);
    }

    double laengeBei(int i) => west + (ost - west) * i / maschenX;
    double breiteBei(int j) => nord - (nord - sued) * j / maschenY;

    for (var j = 0; j < maschenY; j++) {
      final b0 = breiteBei(j);
      final b1 = breiteBei(j + 1);
      for (var i = 0; i < maschenX; i++) {
        final l0 = laengeBei(i);
        final l1 = laengeBei(i + 1);
        final a = punkt(b0, l0);
        final bb = punkt(b0, l1);
        final c = punkt(b1, l0);
        final d = punkt(b1, l1);
        // Zwei Dreiecke je Feld, jedes mit seiner eigenen Schattierung.
        // Eine Schattierung je Eckpunkt sähe weicher aus und verwischte
        // genau die Kanten, die ein Gelände lesbar machen.
        final f1 = _farbe(grundfarbe,
            _gedaempft(schattierung(normale(a, bb, c), stimmung), reliefstaerke),
            stimmung);
        lege(a, b0, l0, f1);
        lege(bb, b0, l1, f1);
        lege(c, b1, l0, f1);
        final f2 = _farbe(grundfarbe,
            _gedaempft(schattierung(normale(bb, d, c), stimmung), reliefstaerke),
            stimmung);
        lege(bb, b0, l1, f2);
        lege(d, b1, l1, f2);
        lege(c, b1, l0, f2);
      }
    }

    final mitte = punkt((nord + sued) / 2, (west + ost) / 2);
    var tiefM = double.infinity;
    var hochM = double.negativeInfinity;
    for (var i = 2; i < ecken.length; i += 3) {
      if (ecken[i] < tiefM) tiefM = ecken[i];
      if (ecken[i] > hochM) hochM = ecken[i];
    }
    final nw = punkt(nord, west);
    final so = punkt(sued, ost);
    netze.add(Blocknetz(
      block: b,
      ecken: ecken,
      texturstellen: texturstellen,
      farben: farben,
      randnaehe: randnaehe,
      mitteX: mitte.x,
      mitteY: mitte.y,
      westM: nw.x,
      ostM: so.x,
      suedM: so.y,
      nordM: nw.y,
      tiefM: tiefM,
      hochM: hochM,
    ));
  }

  return Gelaendenetz(
    bloecke: netze,
    mittlereHoehe: mittlereHoehe,
    breiteMeter: breiteMeter,
    hoeheMeter: hoeheMeter,
    sued: gitter.sued,
    west: gitter.west,
    nord: gitter.nord,
    ost: gitter.ost,
    grundstufe: stufe,
  );
}

/// Zieht die Schattierung in Richtung „unbeleuchtet" – 1 lässt sie, 0
/// nimmt sie ganz weg.
///
/// **Warum es das gibt.** Die Schattierung ist eine gerechnete Sonne, und
/// `modulate` multipliziert sie auf die Textur. Bei einer Karte ist das
/// genau richtig: Eine Karte ist flach gezeichnet und bekommt hier ihr
/// Relief.
///
/// Ein **Luftbild bringt sein eigenes Licht schon mit** – als es
/// aufgenommen wurde, stand eine echte Sonne am Himmel, und ihre Schatten
/// stecken in den Bildpunkten. Unsere Sonne kommt dann obendrauf, und am
/// gerenderten Bild des Ilsetals war das Ergebnis eine fast schwarze
/// Waldflanke. Also weniger, aber nicht nichts: Ganz ohne Schattierung
/// verliert die Landschaft ihre Form, weil ein senkrecht aufgenommenes
/// Luftbild von der Steilheit eines Hangs kaum etwas verrät.
double _gedaempft(double licht, double staerke) =>
    staerke >= 1 ? licht : 1 - (1 - licht) * staerke.clamp(0.0, 1.0);

/// Grundfarbe mal Helligkeit mal Lichtfarbe.
///
/// Die Lichtfarbe kommt seit den Tageszeiten dazu: Morgenlicht ist warm,
/// die blaue Stunde kalt. Sie multipliziert wie die Helligkeit, faerbt
/// also auch die Karte mit – deshalb steht sie in [Lichtstimmung]
/// zurueckhaltend.
int _farbe(Color grund, double licht,
    [Lichtstimmung stimmung = stimmungMittag]) {
  final l = stimmung.lichtfarbe;
  int kanal(double v, double ton) =>
      (v * licht * ton * 255).round().clamp(0, 255);
  return (0xFF << 24) |
      (kanal(grund.r, l.r) << 16) |
      (kanal(grund.g, l.g) << 8) |
      kanal(grund.b, l.b);
}

/// Ob ein Block überhaupt ins Bild ragt.
///
/// **Gemessen, warum es das gibt.** Jeder Block ist ein eigener
/// Zeichenzug mit eigenem Shader, und die lassen sich nicht
/// zusammenfassen. Bei gleicher Dreieckszahl (rund 18.000) kostete das
/// Aufzeichnen eines Bildes auf einem Mac:
///
/// ```
///   6 Blöcke   1,27 ms
///  20 Blöcke   1,63 ms
///  64 Blöcke   2,39 ms
/// 240 Blöcke   3,29 ms
/// 900 Blöcke   7,02 ms
/// ```
///
/// Im Flug steht die Kamera aber mitten in der Landschaft und sieht
/// nach vorn: Der grösste Teil der Blöcke liegt hinter ihr oder neben
/// dem Bildausschnitt. Geprüft werden die **acht Ecken des Kastens**,
/// in dem der Block liegt – acht Projektionen statt mehrerer hundert.
///
/// Grosszügig geprüft: Ragt auch nur eine Ecke hinter die Kamera, gilt
/// der Block als sichtbar. Ein Block, der die Kamera umschliesst, hat
/// keine brauchbare Bildfläche – ihn wegzulassen risse ein Loch in den
/// Vordergrund.
bool blockImBild(Blocknetz b, Gelaendekamera kamera, Size size) {
  var links = double.infinity;
  var rechts = double.negativeInfinity;
  var oben = double.infinity;
  var unten = double.negativeInfinity;
  var davor = 0;
  for (var i = 0; i < 8; i++) {
    final p = kamera.projiziere((
      x: (i & 1) == 0 ? b.westM : b.ostM,
      y: (i & 2) == 0 ? b.suedM : b.nordM,
      z: (i & 4) == 0 ? b.tiefM : b.hochM,
    ));
    if (p.tiefe <= 1) return true;
    davor++;
    if (p.stelle.dx < links) links = p.stelle.dx;
    if (p.stelle.dx > rechts) rechts = p.stelle.dx;
    if (p.stelle.dy < oben) oben = p.stelle.dy;
    if (p.stelle.dy > unten) unten = p.stelle.dy;
  }
  if (davor == 0) return false;
  return rechts >= 0 && links <= size.width && unten >= 0 && oben <= size.height;
}

/// Welche Blöcke im Bild stehen, wie weit sie weg sind und wie fein
/// sie sein müssten.
///
/// **Die Regel ist gerechnet und nicht geraten** (siehe [blockstufe]):
/// Ein Bildpunkt deckt in der Entfernung *d* genau `d / brennweite`
/// Meter ab. Gesucht ist die gröbste Kachelstufe, die noch feiner ist.
///
/// [schaerfe] ist das Pixelverhältnis des Bildschirms – auf einem
/// Gerät mit doppelter Punktdichte ist die Karte sonst auf halbem Weg
/// zur Unschärfe.
///
/// [uebersichtAufloesung] ist, was die Übersichtskarte an dieser Stelle
/// hergibt, in Metern je Bildpunkt. Blöcke, die nicht schärfer würden
/// als sie, kommen gar nicht erst auf die Liste: Für sie wäre ein
/// eigener Abruf ein Bild, das genauso aussieht.
List<Blockwunsch> bloeckeImBild(
Gelaendenetz netz,
Gelaendekamera kamera,
Size size, {
  double schaerfe = 1.0,
  double? uebersichtAufloesung,
}) {
  final wo = kamera.standort;
  final aus = <Blockwunsch>[];
  for (final b in netz.bloecke) {
    if (!blockImBild(b, kamera, size)) continue;
    final dx = b.mitteX - wo.x;
    final dy = b.mitteY - wo.y;
    final dz = (b.tiefM + b.hochM) / 2 - wo.z;
    final d = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (uebersichtAufloesung != null &&
        d / (kamera.brennweite * schaerfe) >= uebersichtAufloesung) {
      continue;
    }
    aus.add((
      block: b.block,
      stufe: blockstufe(
        entfernungMeter: d,
        brennweite: kamera.brennweite,
        breite: b.block.mitteBreite,
        schaerfe: schaerfe,
      ),
      entfernung: d,
    ));
  }
  return aus;
}

/// Wie viele Blöcke bei dieser Kameraeinstellung ins Bild ragen.
///
/// Nur zum Messen und Prüfen – das Zeichnen fragt [blockImBild] selbst.
int bloeckeAnzahlImBild(
    Gelaendenetz netz, Gelaendekamera kamera, Size size) {
  var n = 0;
  for (final b in netz.bloecke) {
    if (blockImBild(b, kamera, size)) n++;
  }
  return n;
}

/// Zeichnet ein Netz mit einer Kamera.
/// Ein Messwert, wie er im Videobild steht.
///
/// [breitester] ist die **breiteste Fassung, die dieser Wert im ganzen
/// Flug annimmt** – „12,3 km/h", wenn irgendwo unterwegs zweistellig
/// gefahren wird. Der Maler richtet das Fach danach aus und malt darin
/// den jeweiligen [wert].
///
/// **Warum nicht einfach der Wert.** Ein Fach, das mit seinem Inhalt
/// wächst, verschiebt bei jedem Bild alles rechts davon – dreissigmal in
/// der Sekunde, sobald das Tempo von 9,9 auf 10,1 geht. Gleich breite
/// Ziffern allein reichen dafür nicht; es ist die **Zahl** der Ziffern,
/// die wechselt.
typedef Flugmesswert = ({String name, String wert, String breitester, Color? farbe});

class Gelaendemaler extends CustomPainter {
  final Gelaendenetz netz;
  final Gelaendekamera kamera;

  /// Die Übersichtskarte über dem ganzen Ausschnitt – `null` heisst:
  /// nur schattiertes Gelände.
  ///
  /// Sie ist der **Rückfall**: Solange ein Block seine eigene, feinere
  /// Textur noch nicht hat, schneidet er sich sein Stück hier heraus.
  /// Ohne diesen Rückfall wäre die Landschaft während des Ladens
  /// stellenweise leer, und Löcher fallen mehr auf als Unschärfe.
  final ui.Image? karte;

  /// Die eigene Textur je Block – schärfer als [karte], und nur da, wo
  /// sie schon geladen ist.
  final Map<Texturblock, ui.Image>? blocktexturen;

  /// Die Spur, in denselben Metern wie das Netz.
  final List<Raumpunkt> spur;
  final Color spurfarbe;

  /// Tageszeit: Himmelsfarben, Dunst und – über das Netz – das Relief.
  final Lichtstimmung stimmung;

  /// Bis wohin die Spur zurückgelegt ist, in Metern – `null` ausserhalb
  /// des Fluges.
  ///
  /// Zurückgelegt wird in voller Farbe gezeichnet, was noch kommt blass.
  /// Ohne diesen Schnitt sieht die Spur im Flug genauso aus wie im
  /// Stillstand, und man verliert, wo auf ihr man gerade ist.
  final double? gefahrenBis;

  /// Die aufsummierte Strecke bis zu jedem Punkt aus [spur] – muss zu
  /// [gefahrenBis] gehören und genauso lang sein wie [spur].
  final List<double>? streckeJePunkt;

  /// Gipfel, Hütten, Quellen – als aufrechte Schilder über der
  /// Landschaft (siehe `gelaendeschilder.dart`).
  final List<Gelaendeschild> schilder;

  /// Die Geländehöhe an einer Stelle, in Netzmetern – für die
  /// Sichtprüfung der Schilder. Ohne sie schweben Gipfelnamen durch
  /// Berge hindurch.
  final double? Function(double x, double y)? hoeheBei;

  /// Das Foto zur Stelle – **nur für den Videoexport**.
  ///
  /// Am Bildschirm ist das Flugbild ein Widget (siehe `_Flugbild`): Dort
  /// lädt Flutter die Datei selbst, blendet auf und ab und räumt hinter
  /// sich auf. Ein Video entsteht dagegen ohne Widgetbaum, Bild für Bild
  /// auf eine Leinwand – dort muss dasselbe gemalt werden.
  final ({ui.Image bild, double deckkraft, String? unterschrift})? flugbild;

  /// Die Namensnennung – ebenfalls nur für den Videoexport.
  ///
  /// **Keine Zierleiste, sondern eine Lizenzauflage.** Am Bildschirm
  /// steht sie als Fussnote unter der Ansicht; ein Video geht aus der
  /// App heraus und muss sie mitnehmen.
  final String? namensnennung;

  /// Der Abspann – die Zahlen der Tour, ebenfalls nur für das Video.
  final ({List<String> zeilen, double deckkraft})? abspann;

  /// Höhe, Steigung und Tempo im Bild – **nur für den Videoexport**.
  ///
  /// Am Bildschirm stehen sie als Widgetzeile **unter** der Ansicht
  /// (siehe `_Messwerte`); ein Video hat kein Darunter. Was aus der App
  /// herausgeht, trägt seine Zahlen im Bild oder gar nicht.
  final ({List<Flugmesswert> werte, double deckkraft})? messwerte;

  /// Die Schrift der Schilder – nur für Bildwerkzeuge nötig.
  ///
  /// `flutter test` setzt sonst „Ahem", und die malt jedes Zeichen als
  /// gefüllten Kasten; ein Standbild sähe dann aus wie eine Reihe
  /// schwarzer Balken, und über Grösse und Lage der Schilder liesse sich
  /// nichts sagen. In der laufenden App bleibt das `null` – dort steht
  /// die Schrift des Themas.
  final String? schriftart;

  Gelaendemaler({
    required this.netz,
    required this.kamera,
    required this.spur,
    required this.spurfarbe,
    this.stimmung = stimmungMittag,
    this.karte,
    this.blocktexturen,
    this.gefahrenBis,
    this.streckeJePunkt,
    this.schilder = const [],
    this.hoeheBei,
    this.schriftart,
    this.flugbild,
    this.namensnennung,
    this.abspann,
    this.messwerte,
  });

  /// Die Grösse des letzten Bildes – die Dunstschicht braucht sie für
  /// ihren Ausschnitt.
  Size _flaeche = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    _flaeche = size;
    // **Der Himmel zuerst, und als Verlauf.** Vorher stand hier eine
    // Flaeche in der Hintergrundfarbe des Themas – im dunklen Thema eine
    // schwarze Leere, in die die Landschaft hineinragte. Ein Verlauf
    // kostet nichts weiter: `drawRect` mit einem Shader ist Flutter
    // selbst, kein Paket.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height),
          [stimmung.himmelOben, stimmung.himmelUnten],
        ),
    );

    // **Erst alle sichtbaren Blöcke projizieren, dann zeichnen.** Der
    // Dunst braucht die nächste und die fernste Tiefe über die **ganze**
    // Landschaft; rechnete jeder Block seine eigene Skala, bekäme jeder
    // Block seinen eigenen Nebel und die Blockgrenzen wären als Stufen zu
    // sehen.
    var nahste = double.infinity;
    var fernste = 0.0;
    final sichtbar = <Blocknetz>[];
    for (final b in netz.bloecke) {
      if (!blockImBild(b, kamera, size)) continue;
      _projiziere(b);
      if (b.nahste < nahste) nahste = b.nahste;
      if (b.fernste > fernste) fernste = b.fernste;
      sichtbar.add(b);
    }

    // **Die Blöcke von hinten nach vorn.**
    //
    // `drawVertices` kennt keinen Tiefenpuffer: Was zuletzt gemalt wird,
    // gewinnt. Innerhalb eines Blocks ordnet [_reihenfolgeNachTiefe] die
    // Dreiecke; zwischen den Blöcken ordnet diese Liste.
    //
    // Sortiert wird nach dem **waagerechten Abstand zur Kamera** und
    // nicht nach der Bildtiefe des Mittelpunkts. Der Unterschied zählt
    // bei einem Block, der die Kamera umschliesst: Sein Mittelpunkt kann
    // hinter ihr liegen, seine sichtbare Hälfte aber unmittelbar vor ihr.
    // Nach Bildtiefe geriete er ganz nach hinten und verschwände unter
    // der halben Landschaft.
    final wo = kamera.standort;
    final ordnung = sichtbar
      ..sort((a, b) {
        final da = (a.mitteX - wo.x) * (a.mitteX - wo.x) +
            (a.mitteY - wo.y) * (a.mitteY - wo.y);
        final db = (b.mitteX - wo.x) * (b.mitteX - wo.x) +
            (b.mitteY - wo.y) * (b.mitteY - wo.y);
        return db.compareTo(da);
      });

    for (final b in ordnung) {
      _zeichneBlock(canvas, b);
    }

    _dunstDarueber(canvas, ordnung, nahste, fernste);

    if (spur.length > 1) {
      // Zwei Pfade statt eines: der zurückgelegte Teil und der, der noch
      // kommt. Getrennt gezeichnet und nicht als ein Pfad mit
      // wechselnder Farbe – ein Path kennt nur eine.
      final pfad = Path();
      final kommtNoch = Path();
      final teilen = gefahrenBis != null &&
          streckeJePunkt != null &&
          streckeJePunkt!.length == spur.length;
      var offen = false;
      var offenNoch = false;
      for (var i = 0; i < spur.length; i++) {
        final b = kamera.projiziere(spur[i]);
        if (b.tiefe <= 1) {
          offen = false;
          offenNoch = false;
          continue;
        }
        final schonDa = !teilen || streckeJePunkt![i] <= gefahrenBis!;
        final ziel = schonDa ? pfad : kommtNoch;
        final warOffen = schonDa ? offen : offenNoch;
        if (!warOffen) {
          ziel.moveTo(b.stelle.dx, b.stelle.dy);
        } else {
          ziel.lineTo(b.stelle.dx, b.stelle.dy);
        }
        if (schonDa) {
          offen = true;
          // Damit die beiden Hälften nicht auseinanderklaffen, beginnt
          // die kommende dort, wo die zurückgelegte endet.
          if (teilen) {
            kommtNoch.moveTo(b.stelle.dx, b.stelle.dy);
            offenNoch = true;
          }
        } else {
          offenNoch = true;
        }
      }
      // Erst der Teil, der noch kommt, dann der zurückgelegte: So liegt
      // der volle Strich obenauf, wo beide sich an der Nahtstelle
      // berühren.
      if (teilen) _spurZug(canvas, kommtNoch, spurfarbe, 0.4);
      _spurZug(canvas, pfad, spurfarbe, 1);
    }

    // Die Schilder ganz zuletzt: Sie gehören nicht in die Landschaft,
    // sondern davor – auch vor die Spur, denn ein Name, den ein Strich
    // durchkreuzt, ist keiner.
    zeichneSchilder(canvas, size, kamera, schilder,
        hoeheBei: hoeheBei, stimmung: stimmung, schriftart: schriftart);

    _flugbildMalen(canvas, size);
    // Die Messwerte **vor** dem Abspann: Der legt sich als helle Tafel
    // über die Mitte, und die Zahlen des Fluges gehören dann darunter –
    // sie verabschieden sich, während er kommt.
    _messwerteMalen(canvas, size);
    _abspannMalen(canvas, size);
    _nennungMalen(canvas, size);
  }

  /// Baut einen Textabsatz – einmal je Aufruf, und das ist hier in
  /// Ordnung: Diese drei Dinge werden nur beim Videoexport gemalt, und
  /// dort kostet ein Bild ohnehin eine Kodierung.
  ui.Paragraph _absatz(String text, double groesse,
      {Color farbe = const Color(0xFF1B1B1B),
      FontWeight gewicht = FontWeight.w500,
      TextAlign ausrichtung = TextAlign.left,
      bool festeZifferbreite = false,
      double breite = 1200}) {
    final bauer = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: schriftart,
      fontSize: groesse,
      fontWeight: gewicht,
      textAlign: ausrichtung,
    ))
      ..pushStyle(ui.TextStyle(
        color: farbe,
        fontFeatures: festeZifferbreite
            ? const [ui.FontFeature.tabularFigures()]
            : null,
      ))
      ..addText(text);
    return bauer.build()..layout(ui.ParagraphConstraints(width: breite));
  }

  /// Das Foto zur Stelle, oben rechts – dieselbe Ecke wie am Bildschirm.
  void _flugbildMalen(Canvas canvas, Size size) {
    final f = flugbild;
    if (f == null || f.deckkraft <= 0.01) return;
    final deck = f.deckkraft.clamp(0.0, 1.0);
    // Ein Fünftel der Bildbreite: Auf 1920 sind das 384 Punkte, auf einer
    // kleineren Ausgabe entsprechend weniger. Eine feste Zahl liesse das
    // Foto bei 3840 zur Briefmarke werden.
    final kante = size.width / 5;
    final bildhoehe = kante * 0.75;
    final rand = size.width * 0.02;
    final unten = f.unterschrift == null ? 0.0 : kante * 0.1;
    final kasten = Rect.fromLTWH(size.width - kante - rand - 8, rand,
        kante + 8, bildhoehe + 8 + unten);

    canvas.drawRRect(
      RRect.fromRectAndRadius(kasten, const Radius.circular(6)),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.92 * deck),
    );
    final ziel = Rect.fromLTWH(kasten.left + 4, kasten.top + 4, kante,
        bildhoehe);
    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(ziel, const Radius.circular(3)));
    // `cover`: Ein Vorschaubild ist selten 4:3, und verzerrt sähe es aus
    // wie ein Fehler.
    final q = _fuellend(
        f.bild.width.toDouble(), f.bild.height.toDouble(), ziel);
    canvas.drawImageRect(f.bild, q, ziel,
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: deck)
          ..filterQuality = FilterQuality.medium);
    canvas.restore();

    if (f.unterschrift case final u?) {
      final absatz = _absatz(u, kante * 0.075,
          farbe: const Color(0xFF1B1B1B).withValues(alpha: deck),
          ausrichtung: TextAlign.center,
          breite: kante);
      canvas.drawParagraph(absatz, Offset(kasten.left + 4, ziel.bottom + 2));
    }
  }

  /// Der Ausschnitt aus dem Bild, der [ziel] ohne Verzerrung ausfüllt.
  static Rect _fuellend(double b, double h, Rect ziel) {
    if (b <= 0 || h <= 0) return Rect.fromLTWH(0, 0, b, h);
    final quellVerhaeltnis = b / h;
    final zielVerhaeltnis = ziel.width / ziel.height;
    if (quellVerhaeltnis > zielVerhaeltnis) {
      final neu = h * zielVerhaeltnis;
      return Rect.fromLTWH((b - neu) / 2, 0, neu, h);
    }
    final neu = b / zielVerhaeltnis;
    return Rect.fromLTWH(0, (h - neu) / 2, b, neu);
  }

  void _abspannMalen(Canvas canvas, Size size) {
    final a = abspann;
    if (a == null || a.deckkraft <= 0.01 || a.zeilen.isEmpty) return;
    final deck = a.deckkraft.clamp(0.0, 1.0);
    final gross = size.height * 0.055;
    final klein = size.height * 0.026;
    final absaetze = [
      for (var i = 0; i < a.zeilen.length; i++)
        _absatz(a.zeilen[i], i == 0 ? gross : klein,
            farbe: const Color(0xFF1B1B1B),
            gewicht: i == 0 ? FontWeight.w300 : FontWeight.w500,
            ausrichtung: TextAlign.center,
            breite: size.width * 0.6),
    ];
    var hoehe = 0.0;
    for (final p in absaetze) {
      hoehe += p.height;
    }
    final kasten = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.6,
      height: hoehe + size.height * 0.08,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(kasten, Radius.circular(size.height * 0.02)),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.88 * deck),
    );
    var y = kasten.top + size.height * 0.04;
    for (final p in absaetze) {
      canvas.drawParagraph(p, Offset(kasten.left, y));
      y += p.height;
    }
  }

  /// Höhe, Steigung und Tempo – unten links, über der Namensnennung.
  ///
  /// **Warum unten links.** Oben rechts steht das Foto zur Stelle, unten
  /// links die Namensnennung; die Zahlen setzen sich darüber und lassen
  /// die Bildmitte frei, in der die Landschaft vorbeizieht. Es ist auch
  /// die Ecke, in der jeder sie erwartet, der einmal einen Flyover
  /// gesehen hat.
  void _messwerteMalen(Canvas canvas, Size size) {
    final m = messwerte;
    if (m == null || m.werte.isEmpty || m.deckkraft <= 0.01) return;
    final deck = m.deckkraft.clamp(0.0, 1.0);

    // Alles am Bild bemessen und nichts in festen Punkten: Dieselbe
    // Ausgabe entsteht in 1280 x 720 wie in 3840 x 2160, und eine feste
    // Schriftgrösse wäre dort einmal plakativ und einmal unleserlich.
    final namensgroesse = size.height * 0.019;
    final wertgroesse = size.height * 0.042;
    final rand = size.width * 0.012;
    final luft = size.height * 0.014;
    final spalt = size.width * 0.028;

    final fach = <({ui.Paragraph name, ui.Paragraph wert, double breite})>[];
    for (final w in m.werte) {
      final name = _absatz(w.name, namensgroesse,
          farbe: const Color(0xFFFFFFFF).withValues(alpha: 0.75 * deck),
          gewicht: FontWeight.w500);
      final wert = _absatz(w.wert, wertgroesse,
          farbe: (w.farbe ?? const Color(0xFFFFFFFF))
              .withValues(alpha: deck),
          gewicht: FontWeight.w600,
          festeZifferbreite: true);
      // Gemessen wird an der breitesten Fassung, gemalt die jetzige.
      final vorlage = _absatz(w.breitester, wertgroesse,
          gewicht: FontWeight.w600, festeZifferbreite: true);
      fach.add((
        name: name,
        wert: wert,
        breite: math.max(name.maxIntrinsicWidth, vorlage.maxIntrinsicWidth),
      ));
    }

    var breite = 0.0;
    for (final f in fach) {
      breite += f.breite;
    }
    breite += spalt * (fach.length - 1);
    final hoehe = namensgroesse * 1.35 + wertgroesse * 1.25;

    final nennung = _nennungsabsatz(size);
    final belegt = nennung == null ? 0.0 : nennung.height + 4 + luft;
    final tafel = Rect.fromLTWH(
      rand,
      size.height - rand - belegt - hoehe - luft * 2,
      breite + luft * 2,
      hoehe + luft * 2,
    );

    // Dieselbe Sorge wie bei der Namensnennung, nur ernster: Diese
    // Zahlen ziehen über Himmel, Fels und Wald hinweg, und über hellem
    // Kalk ist Weiss auf Weiss nicht zu lesen. Ein deutlicherer Grund
    // als dort (0x99 statt 0x66) – die Zahlen sind grösser und tragen
    // mehr Gewicht als eine Fussnote.
    canvas.drawRRect(
      RRect.fromRectAndRadius(tafel, Radius.circular(size.height * 0.012)),
      Paint()..color = const Color(0xFF000000).withValues(alpha: 0.6 * deck),
    );

    var x = tafel.left + luft;
    for (final f in fach) {
      canvas.drawParagraph(f.name, Offset(x, tafel.top + luft));
      canvas.drawParagraph(
          f.wert, Offset(x, tafel.top + luft + namensgroesse * 1.35));
      x += f.breite + spalt;
    }
  }

  /// Die Namensnennung als fertiger Absatz – oder `null`, wenn keine da
  /// ist. Auch die Messwerte fragen danach: Sie sitzen darüber und
  /// müssen wissen, wie viel unten schon belegt ist.
  ui.Paragraph? _nennungsabsatz(Size size) {
    final n = namensnennung;
    if (n == null || n.isEmpty) return null;
    return _absatz(n, size.height * 0.018,
        farbe: const Color(0xFFFFFFFF), breite: size.width * 0.9);
  }

  void _nennungMalen(Canvas canvas, Size size) {
    final absatz = _nennungsabsatz(size);
    if (absatz == null) return;
    final rand = size.width * 0.012;
    final wo = Offset(rand, size.height - absatz.height - rand);
    // Ein dunkler Grund darunter: Über hellem Himmel wäre weisse Schrift
    // unlesbar, und über dunklem Wald schwarze.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(wo.dx - 4, wo.dy - 2, absatz.maxIntrinsicWidth + 8,
              absatz.height + 4),
          const Radius.circular(3)),
      Paint()..color = const Color(0x66000000),
    );
    canvas.drawParagraph(absatz, wo);
  }

  /// Rechnet die Eckpunkte eines Blocks auf den Bildschirm.
  void _projiziere(Blocknetz b) {
    final anzahl = b.eckenzahl;
    final flach = b.bildstellen;
    final tiefen = b.tiefen;
    // Merkposten je Eckpunkt: Liegt er hinter der Kamera? Als Bytes und
    // nicht als `List<bool>`: Dart legt die als Zeiger auf zwei Objekte
    // ab, acht Byte je Eintrag statt einem.
    final hinten = b.hinterDerKamera;
    var nahste = double.infinity;
    var fernste = 0.0;
    for (var i = 0; i < anzahl; i++) {
      final p = kamera.projiziere((
        x: b.ecken[i * 3],
        y: b.ecken[i * 3 + 1],
        z: b.ecken[i * 3 + 2],
      ));
      flach[i * 2] = p.stelle.dx;
      flach[i * 2 + 1] = p.stelle.dy;
      tiefen[i] = p.tiefe;
      hinten[i] = p.tiefe <= 1 ? 1 : 0;
      if (hinten[i] == 0) {
        if (p.tiefe < nahste) nahste = p.tiefe;
        if (p.tiefe > fernste) fernste = p.tiefe;
      }
    }

    // **Dreiecke hinter der Kamera fallen weg.**
    //
    // `projiziere` legt einen Punkt hinter der Kamera auf die Bildmitte –
    // das steht dort ausdrücklich dabei, und für eine Linie ist es
    // richtig, weil die Linie an der Stelle ohnehin abgesetzt wird. Für
    // `drawVertices` ist es verheerend: Flutter schneidet nicht an einer
    // vorderen Ebene, also bleibt das Dreieck stehen und spannt sich vom
    // Bildrand bis in die Mitte. Am Bild sind das Schlieren, die aus
    // einem Punkt herausfächern.
    //
    // In der Übersicht kam das nie vor – dort steht die Kamera immer
    // ausserhalb der Landschaft. Beim Flug steht sie mittendrin, und
    // hinter ihr liegt die halbe Karte.
    //
    // Ein Dreieck zu einem Punkt zusammenzuziehen ist die billigste
    // Fassung von „nicht zeichnen": Es hat dann keine Fläche mehr. Das
    // richtige Beschneiden an der vorderen Ebene würde Dreiecke teilen
    // und neue Eckpunkte erzeugen – Aufwand für einen Rand, den man
    // ohnehin nicht ansieht, weil er hinter einem liegt.
    for (var d = 0; d < anzahl; d += 3) {
      if (hinten[d] != 0 || hinten[d + 1] != 0 || hinten[d + 2] != 0) {
        for (var k = 1; k < 3; k++) {
          flach[(d + k) * 2] = flach[d * 2];
          flach[(d + k) * 2 + 1] = flach[d * 2 + 1];
        }
      }
    }

    b.nahste = nahste;
    b.fernste = fernste;
  }

  /// Zeichnet einen Block mit der Textur, die für ihn da ist.
  void _zeichneBlock(Canvas canvas, Blocknetz b) {
    final bild = blocktextur(b.block);
    final ecken = ui.Vertices.raw(
      ui.VertexMode.triangles,
      b.bildstellen,
      colors: b.farben,
      indices: _reihenfolgeNachTiefe(b),
      textureCoordinates: bild == null ? null : b.texturstellen,
    );
    if (bild == null) {
      canvas.drawVertices(ecken, BlendMode.dst, Paint());
    } else {
      // `modulate` multipliziert die Karte mit der Schattierung: Man
      // sieht die Wege *und* das Relief. Nur die Karte wäre eine flache
      // Karte in Schräglage, nur die Schattierung wären Berge ohne Wege.
      canvas.drawVertices(
        ecken,
        BlendMode.modulate,
        Paint()
          ..shader = ui.ImageShader(bild.bild, TileMode.clamp, TileMode.clamp,
              bild.abbildung.storage)
          ..filterQuality = FilterQuality.low,
      );
    }
    ecken.dispose();
  }

  /// Welches Bild auf einen Block gehört – und wie es darauf liegt.
  ///
  /// Zwei Fälle, und der zweite ist der Grund für die Rechnung: Entweder
  /// der Block hat **seine eigene** Textur, dann füllt sie ihn genau aus;
  /// oder es gibt nur die **Übersichtskarte** über dem ganzen Ausschnitt,
  /// und dann muss der Block sich sein Stück daraus herausschneiden.
  ///
  /// Das Herausschneiden steckt in der Abbildung des Shaders und nicht in
  /// den Texturstellen der Eckpunkte: Die sind blocklokal und liegen
  /// fest, die Karte darunter kann wechseln. `ui.ImageShader` rechnet
  /// Bildpunkte in eben diese blocklokalen Stellen um – bei der eigenen
  /// Textur ist das nur ein Massstab, bei der Übersicht kommt eine
  /// Verschiebung dazu.
  ({ui.Image bild, Matrix4 abbildung})? blocktextur(Texturblock block) {
    final eigen = blocktexturen?[block];
    if (eigen != null) {
      return (
        bild: eigen,
        abbildung: Matrix4.diagonal3Values(
            1 / eigen.width, 1 / eigen.height, 1),
      );
    }
    final k = karte;
    if (k == null) return null;
    // Wo der Block im Ausschnitt liegt – in Länge geradlinig, in Breite
    // über Mercator, weil die Karte eine Kachelkarte ist.
    final u0 = (block.west - netz.west) / (netz.ost - netz.west);
    final u1 = (block.ost - netz.west) / (netz.ost - netz.west);
    final yN = kachelYGenau(netz.nord, 0);
    final yS = kachelYGenau(netz.sued, 0);
    final v0 = (kachelYGenau(block.nord, 0) - yN) / (yS - yN);
    final v1 = (kachelYGenau(block.sued, 0) - yN) / (yS - yN);
    if (!(u1 > u0) || !(v1 > v0)) return null;
    final sx = 1 / (k.width * (u1 - u0));
    final sy = 1 / (k.height * (v1 - v0));
    return (
      bild: k,
      abbildung: Matrix4.identity()
        ..translateByDouble(-u0 / (u1 - u0), -v0 / (v1 - v0), 0, 1)
        ..scaleByDouble(sx, sy, 1, 1),
    );
  }

  /// Die Eckpunkte eines Blocks in Zeichenreihenfolge – fernste Dreiecke
  /// zuerst.
  ///
  /// **Zählsortierung und kein Vergleich.** Neuntausend Dreiecke je Bild
  /// bei sechzig Bildern in der Sekunde: `sort` wäre n·log(n) mit einem
  /// Vergleichsaufruf je Schritt, das hier ist zweimal linear plus ein
  /// Durchlauf über die Eimer.
  ///
  /// Die Tiefe eines Dreiecks ist das Mittel seiner drei Eckpunkte. Ein
  /// Dreieck mit einem Punkt hinter der Kamera ist an dieser Stelle
  /// bereits auf einen Punkt zusammengezogen (siehe [_projiziere]) – es
  /// hat keine Fläche mehr und darf deshalb irgendwohin; es kommt nach
  /// ganz hinten.
  ///
  /// **Der Fund, den das behoben hat.** Vorher verliess sich der Maler
  /// darauf, die Gitterreihenfolge (Norden nach Süden) sei schon von
  /// hinten nach vorn. Das gilt nur, solange die Kamera nach Norden
  /// sieht – **die Flugkamera dreht sich in Laufrichtung** (siehe
  /// `Gelaendeflug.drehung`). Wer nach Süden wandert, sah fernes Gelände
  /// über nahem: am gerenderten Bild ein breites Band quer durch die
  /// Landschaft, in `gelaende_zeichenreihenfolge_test.dart` 960 von 3120
  /// Bildpunkten.
  Uint16List _reihenfolgeNachTiefe(Blocknetz netz) {
    final ordnung = netz.reihenfolge;
    final eimer = netz.eimer;
    final tiefen = netz.tiefen;
    final hinten = netz.hinterDerKamera;
    final dreiecke = ordnung.length ~/ 3;
    const stufen = Blocknetz.tiefenstufen;
    final nahste = netz.nahste;
    final fernste = netz.fernste;
    final spanne = fernste - nahste;

    // Ohne Tiefenunterschied gibt es nichts zu ordnen - die Gitterfolge
    // ist dann so gut wie jede andere.
    if (!(spanne > 0)) {
      for (var i = 0; i < ordnung.length; i++) {
        ordnung[i] = i;
      }
      return ordnung;
    }

    /// Stufe 0 ist die fernste. Damit kommt sie beim Auslesen zuerst.
    int stufeVon(int d) {
      if (hinten[d * 3] != 0 ||
          hinten[d * 3 + 1] != 0 ||
          hinten[d * 3 + 2] != 0) {
        return 0;
      }
      final t = (tiefen[d * 3] + tiefen[d * 3 + 1] + tiefen[d * 3 + 2]) / 3;
      final anteil = ((fernste - t) / spanne).clamp(0.0, 1.0);
      return (anteil * (stufen - 1)).toInt();
    }

    eimer.fillRange(0, eimer.length, 0);
    for (var d = 0; d < dreiecke; d++) {
      eimer[stufeVon(d) + 1]++;
    }
    for (var s = 1; s < eimer.length; s++) {
      eimer[s] += eimer[s - 1];
    }
    for (var d = 0; d < dreiecke; d++) {
      final stelle = eimer[stufeVon(d)]++ * 3;
      ordnung[stelle] = d * 3;
      ordnung[stelle + 1] = d * 3 + 1;
      ordnung[stelle + 2] = d * 3 + 2;
    }
    return ordnung;
  }

  /// **Der Dunst in der Ferne – und die weiche Kante.**
  ///
  /// Dieselben Dreiecke ein zweites Mal, diesmal in der Dunstfarbe mit
  /// einer Deckkraft je Eckpunkt. Ein zweiter Zug und keine Rechnung an
  /// den Eckpunktfarben, weil `modulate` multipliziert: Damit lässt sich
  /// nur abdunkeln, und Dunst hellt auf. Er muss also darübergelegt
  /// werden.
  ///
  /// Was weiter weg ist, verblasst – der älteste Tiefenhinweis der
  /// Malerei und der einzige, den eine Ansicht ohne Schattenwurf hat.
  /// Die Skala kommt aus der Szene selbst (nächster und fernster
  /// Eckpunkt **über alle Blöcke**), damit sie in der Übersicht wie im
  /// Flug passt und nicht an den Blockgrenzen springt.
  ///
  /// Die weiche Kante steckt dagegen in der Deckkraft des Geländes
  /// selbst (siehe [baueNetz]) – hier wird sie nur ausgespart.
  void _dunstDarueber(
      Canvas canvas, List<Blocknetz> ordnung, double nahste, double fernste) {
    if (_flaeche.isEmpty) return;
    if (fernste <= nahste) return;
    final spanne = fernste - nahste;
    final rot = (stimmung.dunst.r * 255).round().clamp(0, 255);
    final gruen = (stimmung.dunst.g * 255).round().clamp(0, 255);
    final blau = (stimmung.dunst.b * 255).round().clamp(0, 255);
    final grundton = (rot << 16) | (gruen << 8) | blau;

    // **Auf eine eigene Schicht, und dort ersetzend statt überlagernd.**
    //
    // `drawVertices` kennt keinen Tiefenpuffer; für das Gelände löst das
    // die Reihenfolge, für den Dunst reicht sie nicht: Hinter einem Grat
    // liegt ferne Landschaft, deren Dunst zuerst gemalt wird – und das
    // nahe Dreieck darüber trägt fast keinen Dunst, deckt also nichts zu.
    // Übrig blieb ein weisses Band quer über die Gipfelkette. Erst die
    // Gegenprobe mit ausgeschaltetem Saum zeigte, dass es nicht der Rand
    // war.
    //
    // Auf einer eigenen Schicht mit `src` **ersetzt** jedes Dreieck, was
    // dort steht. Weil sie von hinten nach vorn kommen, gewinnt das
    // nächste – genau das, was ein Tiefenpuffer täte. Die fertige
    // Schicht kommt dann in einem Zug über das Gelände.
    //
    // **Eine Schicht für alle Blöcke**, nicht eine je Block: Eine
    // Zwischenfläche in Bildschirmgrösse ist der teuerste Einzelposten
    // dieses Malers, und hundert davon je Bild wären hundertmal der
    // Preis. Die Blöcke kommen in derselben Reihenfolge hinein wie das
    // Gelände, damit `src` innerhalb der Schicht dasselbe leistet.
    canvas.saveLayer(Offset.zero & _flaeche, Paint());
    final farbe = Paint()..blendMode = BlendMode.src;
    for (final b in ordnung) {
      final anzahl = b.eckenzahl;
      final farben = b.dunstfarben;
      final tiefen = b.tiefen;
      final hinten = b.hinterDerKamera;
      for (var i = 0; i < anzahl; i++) {
        if (hinten[i] != 0) {
          farben[i] = 0;
          continue;
        }
        final t = ((tiefen[i] - nahste) / spanne).clamp(0.0, 1.0);
        final deckung = _dunstStaerke * (1 - math.exp(-_dunstDichte * t))
            // Wo das Gelände selbst schon durchsichtig ist, darf der
            // Dunst es nicht wieder zumalen.
            * b.randnaehe[i];
        farben[i] = ((deckung * 255).round().clamp(0, 255) << 24) | grundton;
      }
      // Dieselbe Ordnung wie das Gelände – hier ist sie sogar zwingend:
      // Auf der eigenen Schicht ERSETZT jedes Dreieck, was dort steht,
      // und gewinnen soll das nächste.
      final schleier = ui.Vertices.raw(
          ui.VertexMode.triangles, b.bildstellen,
          colors: farben, indices: b.reihenfolge);
      canvas.drawVertices(schleier, BlendMode.dst, farbe);
      schleier.dispose();
    }
    canvas.restore();
  }

  /// **Die Spur in drei Zügen.**
  ///
  /// Ein einzelner Strich verschwindet auf einer bunten Karte – im Bild
  /// vom 02.09. war er über der Wiese kaum zu finden. Deshalb:
  /// 1. ein versetzter dunkler Schatten, der ihn vom Hang abhebt,
  /// 2. ein breiter weicher Schein darunter,
  /// 3. der scharfe Kern darüber.
  ///
  /// In dieser Reihenfolge, sonst läge der Schatten über dem Kern.
  void _spurZug(Canvas canvas, Path pfad, Color farbe, double deckkraft) {
    if (deckkraft <= 0) return;
    canvas.drawPath(
      pfad.shift(const Offset(1.5, 2.5)),
      Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.35 * deckkraft)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      pfad,
      Paint()
        ..color = farbe.withValues(alpha: 0.45 * deckkraft)
        ..strokeWidth = 9
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 3.5),
    );
    canvas.drawPath(
      pfad,
      Paint()
        ..color = farbe.withValues(alpha: deckkraft)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(Gelaendemaler alt) =>
      alt.netz != netz ||
      alt.kamera != kamera ||
      alt.stimmung != stimmung ||
      alt.karte != karte ||
      alt.blocktexturen != blocktexturen ||
      alt.schilder != schilder ||
      alt.flugbild != flugbild ||
      alt.abspann != abspann ||
      alt.messwerte != messwerte ||
      alt.spur != spur ||
      // Ohne diese Zeile stünde der Schnitt zwischen zurückgelegt und
      // kommend still, sobald die Kamera einmal gleich bleibt – etwa
      // beim Spulen an derselben Stelle.
      alt.gefahrenBis != gefahrenBis;
}

/// Die Landschaft mit Ziehen zum Drehen und Kippen – und dem Flug an der
/// Spur entlang.
class Gelaendeansicht extends StatefulWidget {
  final Gelaendenetz netz;
  final List<Raumpunkt> spur;

  /// Echte Höhe und Zeit zu jedem Punkt aus [spur]. Leer heisst: Flug
  /// ohne Zahlen – möglich, aber wortkarg.
  final List<Flugwert> spurwerte;

  final ui.Image? karte;

  /// Die Tageszeit. Muss zu dem Netz passen, das hereingereicht wird:
  /// Das Relief steckt in den Eckpunktfarben und entsteht beim Bauen,
  /// Himmel und Dunst entstehen beim Zeichnen. Wer nur eines von beiden
  /// umstellt, bekommt einen Morgenhimmel über einer Mittagslandschaft.
  final Lichtstimmung stimmung;

  /// Was am unteren Rand über der Flugleiste stehen soll – Bedienung,
  /// Namensnennung.
  ///
  /// **Warum das hier hereingereicht wird und nicht darüber gelegt.**
  /// Die Flugleiste sitzt am unteren Rand dieser Ansicht, und wer
  /// draussen einen zweiten Stapel mit `bottom:` darüberlegt, landet
  /// genau darauf – die Erklärung stand über dem Flugzeugsymbol und
  /// verdeckte den einzigen Knopf, der den Flug startet. Beides in einer
  /// Spalte zu stapeln kann nur die Stelle, die beide kennt.
  final List<Widget> fussnoten;

  /// Was auf der Landschaft liegen soll – Grund, Ebenen, Höhenlinien.
  ///
  /// Dieselbe Wahl wie bei [karte]; die Übersicht ist nur der Rückfall,
  /// solange ein Block seine eigene Textur noch nicht hat.
  final Gelaendekarte auflage;

  /// Das Höhengitter – für die Höhenlinien, die daraus gerechnet werden
  /// statt geladen zu werden, und für die Sichtprüfung der Schilder.
  final Hoehengitter? hoehen;

  /// Gipfel, Hütten, Quellen – als aufrechte Schilder über der
  /// Landschaft.
  final List<Gelaendeschild> schilder;

  /// Die Namensnennung, die **ins Video** gebrannt wird.
  ///
  /// Am Bildschirm steht sie als Fussnote unter der Ansicht; ein Video
  /// geht aus der App heraus und muss sie mitnehmen. Keine Zierleiste,
  /// sondern eine Lizenzauflage.
  final String? namensnennung;

  /// Wohin das Video geschrieben wird – `null` heisst: kein Knopf dafür.
  ///
  /// Als Rückruf und nicht als Pfad: Wo eine Datei hinsoll, fragt man
  /// den, der sie haben will, und ein Dateiwähler gehört nicht in ein
  /// Widget, das eine Landschaft zeichnet.
  final Future<Videoauftrag?> Function(Duration vorgabe)? beimVideoZiel;

  /// Die Fotos der Aktivität, mit ihrer Stelle auf der Spur.
  ///
  /// **Das ist der Punkt, an dem sich eine Fotoverwaltung von einem
  /// Sportprogramm unterscheidet.** Strava und Relive fliegen dieselbe
  /// Spur ab; nur hier liegen die Bilder schon daneben und mussten nur
  /// noch hergereicht werden.
  final List<Flugfoto> fotos;

  /// Nur für Tests: Wer hier etwas hereinreicht, holt keine Kacheln aus
  /// dem Netz – und geht dann auch am gemeinsamen Kachelspeicher vorbei,
  /// damit ein Test nicht davon abhängt, was auf dieser Platte liegt.
  final http.Client? netzKlient;

  const Gelaendeansicht({
    super.key,
    required this.netz,
    this.spur = const [],
    this.spurwerte = const [],
    this.karte,
    this.stimmung = stimmungMittag,
    this.fussnoten = const [],
    this.auflage = const Gelaendekarte(),
    this.hoehen,
    this.schilder = const [],
    this.fotos = const [],
    this.namensnennung,
    this.beimVideoZiel,
    this.netzKlient,
  });

  @override
  State<Gelaendeansicht> createState() => _GelaendeansichtState();
}

class _GelaendeansichtState extends State<Gelaendeansicht>
    with SingleTickerProviderStateMixin {
  /// Von Südsüdwest, leicht schräg – die Ansicht, in der man ein Tal als
  /// Tal erkennt. Genau von Süden wirkte die Landschaft flach, weil alle
  /// Kanten parallel zum Bildrand lägen.
  double _drehung = 0.35;

  /// Rund 55°. Senkrecht von oben ist eine Karte, waagerecht ist ein
  /// Strich.
  double _neigung = 0.95;

  double _zoom = 1;

  /// Wie schnell der Flug über Grund geht. Am Bildschirm eingestellt: Bei
  /// 150 m/s wirkt eine Tageswanderung wie eine Diaschau, bei 600 sieht
  /// man das Gelände nicht mehr.
  static const double _flugtempo = 300;

  late final AnimationController _uhr;
  late Gelaendeflug _flug;

  /// Ob geflogen wird – auch angehalten bleibt die Flugkamera stehen, wo
  /// sie ist. Ohne diesen Merker spränge ein Pausieren zurück in die
  /// Übersicht.
  bool _imFlug = false;

  /// Was das Ziehen beim Flug verändert: nicht die Drehung selbst, die
  /// gehört dem Weg, sondern ein Versatz darauf. So kann man sich im
  /// Flug umsehen, ohne dass die Kamera danach den Weg verliert.
  ///
  /// **Die Neigung bleibt dagegen dieselbe wie in der Übersicht.** Die
  /// erste Fassung stellte sie beim Start um, in der Annahme, ein Flug
  /// wolle flacher sehen. An echtem Gelände durchprobiert (Grindelwald,
  /// 547 bis 4035 m) stimmt das nicht: Flacher als etwa 0,8 fliegt man
  /// in einem Alpental gegen eine Wand – bei dreifacher Überhöhung stehen
  /// die Hänge dreimal so steil wie in Wirklichkeit. Zwischen 0,85 und
  /// 1,05 liest sich das Bild gut, und 0,95 liegt mittendrin. Also keine
  /// eigene Zahl, keine Umschaltung und kein Merken – der Blickwinkel
  /// gehört durchweg dem Betrachter.
  double _flugversatz = 0;

  /// Der Lader für die scharfen Blocktexturen.
  ///
  /// **Gehört der Ansicht und nicht dem Bildschirm**, weil er die Kamera
  /// braucht: Welcher Block wie fein sein muss, hängt daran, wie weit er
  /// weg ist, und das weiss nur, wer die Kamera führt.
  Blocktexturlader? _lader;

  @override
  void initState() {
    super.initState();
    _flug = Gelaendeflug(widget.spur, werte: widget.spurwerte);
    _laderAufsetzen();
    _uhr = AnimationController(vsync: this, duration: _dauer())
      ..addListener(() => setState(() {}))
      ..addStatusListener((stand) {
        // Am Ende stehen bleiben und nicht in die Übersicht springen:
        // Der letzte Blick ist das Ziel, und danach will man es ansehen.
        if (stand == AnimationStatus.completed) setState(() {});
      });
  }

  @override
  void didUpdateWidget(Gelaendeansicht alt) {
    super.didUpdateWidget(alt);
    if (alt.spur != widget.spur || alt.spurwerte != widget.spurwerte) {
      _flug = Gelaendeflug(widget.spur, werte: widget.spurwerte);
      _uhr.duration = _dauer();
    }
    // Anderes Gelände oder andere Karte heisst andere Texturen. Der alte
    // Vorrat muss dabei **freigegeben** werden, sonst bliebe der Speicher
    // der Grafikkarte bei jedem Stilwechsel um achtzig Megabyte voller.
    if (alt.netz != widget.netz || alt.auflage != widget.auflage) {
      _lader?.schliessen();
      _laderAufsetzen();
    }
  }

  void _laderAufsetzen() {
    _lader = Blocktexturlader(
      karte: widget.auflage,
      hoehen: widget.hoehen,
      grundstufe: widget.netz.grundstufe,
      netz: widget.netzKlient,
      speicher: widget.netzKlient == null
          ? null
          : const DisabledMapCachingProvider(),
      beiAenderung: () {
        if (mounted) setState(() {});
      },
    );
  }

  /// Die Geländehöhe an einer Stelle des Netzes, in Netzmetern.
  ///
  /// **Aus dem Höhengitter und nicht aus dem Netz.** Das Netz besteht aus
  /// Dreiecken und liesse sich nur durch Suchen abfragen; das Gitter kann
  /// es direkt und bilinear. Gebraucht wird es für die Sichtprüfung der
  /// Schilder – zwanzig Abfragen je Schild und Bild.
  double? _hoeheBei(double x, double y) {
    final g = widget.hoehen;
    final netz = widget.netz;
    if (g == null || netz.breiteMeter <= 0 || netz.hoeheMeter <= 0) return null;
    final laenge = netz.west +
        (x / netz.breiteMeter + 0.5) * (netz.ost - netz.west);
    final breite = netz.nord -
        (0.5 - y / netz.hoeheMeter) * (netz.nord - netz.sued);
    final h = g.anOrt(breite, laenge);
    if (h == null) return null;
    return (h - netz.mittlereHoehe) * gelaendeUeberhoehung;
  }

  /// Was die Übersichtskarte an dieser Stelle hergibt, in Metern je
  /// Bildpunkt – die Schwelle, ab der ein eigener Abruf sich lohnt.
  double? get _uebersichtAufloesung {
    final k = widget.karte;
    if (k == null || k.width == 0) return null;
    final mitte = (widget.netz.nord + widget.netz.sued) / 2;
    return (widget.netz.ost - widget.netz.west) *
        meterJeGradLaenge(mitte) /
        k.width;
  }

  /// Wie lange der Einflug dauert, als Anteil an der ganzen Vorführung.
  ///
  /// **Warum es ihn gibt.** Bisher stand die Kamera im ersten Bild
  /// mitten in der Landschaft, und man wusste nicht, wo. Der Einflug
  /// beantwortet die Frage, die vor allen anderen kommt: *wo sind wir
  /// überhaupt.* Er beginnt in der Übersicht, die man gerade noch
  /// gesehen hat, und geht von dort auf den Startpunkt zu – dieselbe
  /// Bewegung, die Strava und Relive an den Anfang stellen.
  static const double _einflugAnteil = 0.07;

  /// Und der Abspann am Ende – aufziehen und die Zahlen zeigen.
  static const double _abspannAnteil = 0.10;

  Duration _dauer() {
    final flug = _flug.moeglich
        ? _flug.dauerBei(_flugtempo)
        : const Duration(seconds: 10);
    // Einflug und Abspann kommen oben drauf, statt vom Flug abzugehen:
    // Sonst wäre eine kurze Wanderung nach dem Einflug schon vorbei.
    return flug * (1 / (1 - _einflugAnteil - _abspannAnteil));
  }

  /// Wo in der Vorführung wir sind.
  ///
  /// Drei Abschnitte auf einer Uhr: Einflug, Flug, Abspann. Sie liegen
  /// auf **einer** Uhr und nicht auf dreien, damit der Regler unter dem
  /// Bild die ganze Vorführung zeigt und nicht nur ihren Mittelteil.
  ({double einflug, double flug, double abspann}) get _abschnitt {
    final t = _uhr.value;
    const a = _einflugAnteil;
    const b = 1 - _abspannAnteil;
    return (
      einflug: t < a ? (t / a).clamp(0.0, 1.0) : 1.0,
      flug: ((t - a) / (b - a)).clamp(0.0, 1.0),
      abspann: t <= b ? 0.0 : ((t - b) / (1 - b)).clamp(0.0, 1.0),
    );
  }

  @override
  void dispose() {
    _lader?.schliessen();
    _uhr.dispose();
    super.dispose();
  }

  void _flugSchalten() {
    setState(() {
      if (!_imFlug) {
        _imFlug = true;
        _flugversatz = 0;
        _uhr.forward(from: 0);
      } else if (_uhr.isAnimating) {
        _uhr.stop();
      } else {
        // Am Ende noch einmal von vorn, sonst weiterlaufen.
        _uhr.forward(from: _uhr.value >= 1 ? 0 : _uhr.value);
      }
    });
  }

  void _flugBeenden() {
    setState(() {
      _uhr.stop();
      _imFlug = false;
    });
  }

  void _spulen(double wert) {
    setState(() {
      _uhr.stop();
      _uhr.value = wert.clamp(0.0, 1.0);
    });
  }

  /// Ob gerade ein Video geschrieben wird.
  bool _videoLaeuft = false;

  /// Vom Knopf gesetzt, vom Lauf vor jedem Bild gelesen.
  bool _videoAbbruch = false;

  /// Wie weit die Ausgabe ist, 0 bis 1.
  double _videoFortschritt = 0;

  /// Der Auftrag, der gerade läuft – für die Kachelvorschau, die seine
  /// Bildgrösse braucht.
  Videoauftrag? _videoauftrag;

  /// Wann die Ausgabe begann – für die Restzeit.
  DateTime? _videoBegann;

  /// Die breitesten Fassungen der Messwerte dieses Fluges – einmal vor
  /// dem Lauf gerechnet, siehe [_breitesteMesswerte].
  ({String hoehe, String tempo, String steigung})? _videoBreiteste;

  /// Wie lange die Ausgabe noch braucht – aus dem bisherigen Tempo.
  ///
  /// `null`, solange sich nichts rechnen lässt. **Eine geratene Restzeit
  /// wäre schlimmer als keine** – dieselbe Regel wie bei der
  /// KI-Restaurierung.
  Duration? get _videoRest {
    final begann = _videoBegann;
    if (begann == null || _videoFortschritt <= 0.02) return null;
    final her = DateTime.now().difference(begann).inMilliseconds;
    if (her <= 0) return null;
    final ganz = her / _videoFortschritt;
    return Duration(milliseconds: (ganz - her).round());
  }

  /// Schreibt den Flug als Video – oder bricht einen laufenden ab.
  Future<void> _videoAusgeben() async {
    if (_videoLaeuft) {
      setState(() => _videoAbbruch = true);
      return;
    }
    final t = AppTexte.of(context);
    // **Nicht mehr „gibt es ffmpeg".** Unter macOS schreibt AVFoundation
    // das Video, unter Linux und Windows das mitgelieferte ffmpeg – die
    // Frage lautet also, ob hier irgendein Weg offen ist.
    if (!await videoausgabeMoeglich()) {
      if (!mounted) return;
      melde.warnung(t.flugVideoKeinWerkzeug);
      return;
    }
    if (!mounted) return;
    final auftrag =
        await widget.beimVideoZiel?.call(_uhr.duration ?? _dauer());
    if (auftrag == null || !mounted) return;
    final ziel = auftrag.ziel;

    // **Die Fotos vorher aufdecken.** Am Bildschirm lädt Flutter sie
    // selbst, während der Flug läuft; ein Video entsteht ohne
    // Widgetbaum, und ein Bild, das erst zur Hälfte des Fluges ankommt,
    // fehlte in den Bildern davor.
    final fotos = <double, ui.Image>{};
    for (final f in widget.fotos) {
      final bild = await _bildAufdecken(f.bild);
      if (bild != null) fotos[f.meter] = bild;
    }
    if (!mounted) {
      for (final b in fotos.values) {
        b.dispose();
      }
      return;
    }

    setState(() {
      _videoLaeuft = true;
      _videoAbbruch = false;
      _videoFortschritt = 0;
      _videoauftrag = auftrag;
      _videoBegann = DateTime.now();
      _videoBreiteste = _breitesteMesswerte();
    });
    try {
      final ergebnis = await schreibeFlugvideo(
        ziel: ziel,
        breite: auftrag.breite,
        hoehe: auftrag.hoehe,
        dauer: auftrag.dauer,
        abbruch: () => _videoAbbruch || !mounted,
        // Der Fortschritt steht als Balken über der Flugleiste und nicht
        // als Meldung: Eine Meldung, die neunhundertmal aktualisiert
        // wird, ist keine Meldung mehr.
        fortschritt: (a) {
          if (mounted) setState(() => _videoFortschritt = a);
        },
        // **Vor jedem Bild die Kacheln holen, die darin stehen.** Ohne
        // das nähme die Ausgabe die Texturen, die gerade zufällig im
        // Vorrat lagen – am Bildschirm holt der Lader nach, während man
        // fliegt, ein Video hat dafür keine Gelegenheit mehr.
        vorBild: (zeit) => _videoKachelnHolen(zeit),
        maleBild: (leinwand, flaeche, zeit) =>
            _videobild(leinwand, flaeche, zeit, fotos),
      );
      if (!mounted) return;
      switch (ergebnis.ausgang) {
        case Videoausgang.fertig:
          melde.hinweis(t.flugVideoFertig(ziel.uri.pathSegments.last));
        case Videoausgang.abgebrochen:
          melde.hinweis(t.flugVideoAbgebrochen);
        case Videoausgang.keinWerkzeug:
          melde.warnung(t.flugVideoKeinWerkzeug);
        case Videoausgang.fehler:
          melde.warnung(t.flugVideoFehler(ergebnis.meldung ?? '?'));
      }
    } finally {
      for (final b in fotos.values) {
        b.dispose();
      }
      if (mounted) {
        setState(() {
          _videoLaeuft = false;
          _videoAbbruch = false;
          _videoauftrag = null;
          _videoBegann = null;
          _videoBreiteste = null;
        });
      }
    }
  }

  /// Holt aus einem Bildanbieter ein fertiges `ui.Image`.
  Future<ui.Image?> _bildAufdecken(ImageProvider anbieter) {
    final fertig = Completer<ui.Image?>();
    final strom = anbieter.resolve(ImageConfiguration.empty);
    late ImageStreamListener horcher;
    horcher = ImageStreamListener(
      (info, _) {
        if (!fertig.isCompleted) fertig.complete(info.image.clone());
        info.dispose();
        strom.removeListener(horcher);
      },
      onError: (_, __) {
        // Ein Bild, das nicht kommt, nimmt das Video nicht mit.
        if (!fertig.isCompleted) fertig.complete(null);
        strom.removeListener(horcher);
      },
    );
    strom.addListener(horcher);
    return fertig.future;
  }

  /// Sagt dem Lader, was in diesem Videobild steht – und wartet kurz.
  Future<void> _videoKachelnHolen(double zeit) async {
    final lader = _lader;
    if (lader == null) return;
    final breite = (_videoauftrag?.breite ?? 1920).toDouble();
    final hoehe = (_videoauftrag?.hoehe ?? 1080).toDouble();
    lader.brauche(bloeckeImBild(
      widget.netz,
      _videokamera(zeit, breite, hoehe),
      Size(breite, hoehe),
      uebersichtAufloesung: _uebersichtAufloesung,
    ));
    // **Nur auf das warten, was man sieht.** Vorher stand hier
    // `ruhe(700 ms)` – warten, bis der Lader gar nichts mehr zu tun hat.
    // Das tritt im Flug nie ein: Ein Bild will über fünfhundert Blöcke,
    // in den Vorrat passen hundertfünfzig, und mit jedem Bild verschiebt
    // sich die Zuteilung. Gemessen kostete das 665 ms je Bild – bei einem
    // Server, der sofort antwortet. Ein Überflug von einer Minute wäre
    // zwanzig Minuten Warten gewesen, und genau so sah es aus: als
    // täte die Ausgabe nichts.
    await lader.ruheNah(hoechstens: const Duration(milliseconds: 300));
  }

  /// Die Kamera für ein Videobild – dieselbe Rechnung wie am Bildschirm.
  Gelaendekamera _videokamera(double zeit, double breite, double hoehe) {
    final ausdehnung =
        math.max(widget.netz.breiteMeter, widget.netz.hoeheMeter);
    final abschnitt = _abschnittBei(zeit);
    final stand = _flug.bei(abschnitt.flug);
    final brennweite = math.min(breite, hoehe) * 1.1;
    final uebersicht = Gelaendekamera(
      drehung: _drehung,
      neigung: _neigung,
      entfernung: ausdehnung * 0.95,
      brennweite: brennweite,
      mitte: Offset(breite / 2, hoehe * 0.5),
    );
    final flugkamera = Gelaendekamera(
      drehung: stand.drehung,
      neigung: _neigung,
      entfernung: Gelaendeflug.flugabstand(
          ausdehnung: ausdehnung,
          kante: gelaendeGitterkante,
          brennweite: brennweite),
      brennweite: brennweite,
      mitte: Offset(breite / 2, hoehe * 0.62),
      blickpunkt: stand.blickpunkt,
    );
    // Dieselbe Anhebung wie am Bildschirm: Ein Video, das durch den Berg
    // fliegt, waere derselbe Fehler in haltbar.
    if (abschnitt.einflug < 1) {
      return _ueberDemBoden(_zwischenKamera(uebersicht, flugkamera,
          Curves.easeInOutCubic.transform(abschnitt.einflug)));
    }
    if (abschnitt.abspann > 0) {
      return _ueberDemBoden(_zwischenKamera(flugkamera, uebersicht,
          Curves.easeInOutCubic.transform(abschnitt.abspann)));
    }
    return _ueberDemBoden(flugkamera);
  }

  /// Malt ein einzelnes Videobild – dieselbe Rechnung wie am Bildschirm,
  /// nur auf eine feste Leinwand statt in ein Fenster.
  void _videobild(ui.Canvas leinwand, ui.Size flaeche, double zeit,
      Map<double, ui.Image> fotos) {
    final abschnitt = _abschnittBei(zeit);
    final stand = _flug.bei(abschnitt.flug);
    final kamera = _videokamera(zeit, flaeche.width, flaeche.height);

    final foto = _fotoBei(stand.gefahrenMeter);
    final bild = foto == null ? null : fotos[foto.meter];

    Gelaendemaler(
      netz: widget.netz,
      kamera: kamera,
      spur: widget.spur,
      karte: widget.karte,
      blocktexturen: _lader?.bilder,
      spurfarbe: const Color(0xFFFF5722),
      stimmung: widget.stimmung,
      gefahrenBis: stand.gefahrenMeter,
      streckeJePunkt: _flug.streckeJePunkt,
      schilder: widget.schilder,
      hoeheBei: _hoeheBei,
      flugbild: bild == null
          ? null
          : (
              bild: bild,
              deckkraft: _fotoDeckkraft(stand.gefahrenMeter),
              unterschrift: foto!.unterschrift
            ),
      namensnennung: widget.namensnennung,
      // Sie kommen mit dem Einflug und gehen mit dem Abspann: Was der
      // Flug gerade misst, hat neben den Zahlen der ganzen Tour nichts
      // mehr zu suchen.
      messwerte: (
        werte: _videomesswerte(stand),
        deckkraft: Curves.easeOut.transform(abschnitt.einflug) *
            (1 - Curves.easeIn.transform(abschnitt.abspann)),
      ),
      abspann: abschnitt.abspann <= 0
          ? null
          : (
              zeilen: _abspannzeilen(),
              deckkraft: Curves.easeIn.transform(abschnitt.abspann)
            ),
    ).paint(leinwand, flaeche);
  }

  /// Dieselbe Abschnittsrechnung wie [_abschnitt], nur für eine Zeit, die
  /// nicht von der Uhr kommt – beim Video läuft keine.
  ({double einflug, double flug, double abspann}) _abschnittBei(double t) {
    const a = _einflugAnteil;
    const b = 1 - _abspannAnteil;
    return (
      einflug: t < a ? (t / a).clamp(0.0, 1.0) : 1.0,
      flug: ((t - a) / (b - a)).clamp(0.0, 1.0),
      abspann: t <= b ? 0.0 : ((t - b) / (1 - b)).clamp(0.0, 1.0),
    );
  }

  /// Bergauf und bergab im Video – feste Farben, anders als am
  /// Bildschirm.
  ///
  /// Dort nimmt die Zeile `error` und `primary` aus dem Thema, und die
  /// sind für dessen Grund gemacht. Im Video liegen die Zahlen auf einer
  /// dunklen Tafel über wechselnder Landschaft; das dunkle Blau des
  /// hellen Themas wäre darauf nicht zu lesen. Die Farbe bleibt Beiwerk
  /// – das Vorzeichen sagt dasselbe (18. Prüfrunde).
  static const _videoBergauf = Color(0xFFFFAB91);
  static const _videoBergab = Color(0xFF80DEEA);

  /// Höhe, Tempo und Steigung für ein Videobild – in derselben
  /// Reihenfolge wie in der Zeile unter der Ansicht.
  List<Flugmesswert> _videomesswerte(Flugstand stand) {
    final breiteste = _videoBreiteste;
    if (breiteste == null) return const [];
    final t = AppTexte.of(context);
    final eine = NumberFormat.decimalPatternDigits(
        locale: Localizations.localeOf(context).toString(), decimalDigits: 1);
    return [
      if (stand.hoeheMeter case final h?)
        (
          name: t.flugHoehe,
          wert: t.flugMeterProfil(h.round()),
          breitester: breiteste.hoehe,
          farbe: null
        ),
      if (stand.tempoMeterJeSekunde case final v?)
        (
          name: t.flugTempo,
          wert: t.flugKmH(eine.format(v * 3.6)),
          breitester: breiteste.tempo,
          farbe: null
        ),
      if (stand.steigungProzent case final st?)
        (
          name: t.flugSteigung,
          wert: t.flugProzent(eine.format(st)),
          breitester: breiteste.steigung,
          farbe: st.abs() < 1
              ? null
              : (st > 0 ? _videoBergauf : _videoBergab),
        ),
    ];
  }

  /// Die breiteste Fassung, die jeder Messwert im Lauf dieses Fluges
  /// annimmt.
  ///
  /// **Der Vergleich nach Zeichenzahl ist hier genau und nicht
  /// ungefähr**: Innerhalb einer Spalte steht immer dasselbe Muster –
  /// dieselbe Einheit, eine Nachkommastelle – und die Ziffern sind im
  /// Bild gleich breit. Länger heisst dann breiter. Über Spalten hinweg
  /// gälte das nicht, und über sie hinweg wird auch nicht verglichen.
  ///
  /// Zweihundert Stellen und nicht jedes Bild: Der Flug ist stetig,
  /// zweihundert Stichproben treffen den Höchstwert auf die
  /// Nachkommastelle, und gerechnet wird das **einmal** vor dem Lauf
  /// statt neunhundertmal darin.
  ({String hoehe, String tempo, String steigung}) _breitesteMesswerte() {
    final t = AppTexte.of(context);
    final eine = NumberFormat.decimalPatternDigits(
        locale: Localizations.localeOf(context).toString(), decimalDigits: 1);
    String laenger(String bisher, String neu) =>
        neu.length > bisher.length ? neu : bisher;
    var hoehe = '';
    var tempo = '';
    var steigung = '';
    for (var i = 0; i <= 200; i++) {
      final stand = _flug.bei(i / 200);
      if (stand.hoeheMeter case final h?) {
        hoehe = laenger(hoehe, t.flugMeterProfil(h.round()));
      }
      if (stand.tempoMeterJeSekunde case final v?) {
        tempo = laenger(tempo, t.flugKmH(eine.format(v * 3.6)));
      }
      if (stand.steigungProzent case final st?) {
        steigung = laenger(steigung, t.flugProzent(eine.format(st)));
      }
    }
    return (hoehe: hoehe, tempo: tempo, steigung: steigung);
  }

  List<String> _abspannzeilen() {
    final t = AppTexte.of(context);
    final zahl = NumberFormat(
        '#,##0.0', Localizations.localeOf(context).toLanguageTag());
    final hoch = _flug.aufstiegMeter;
    final dauer = _flug.gesamtdauer;
    return [
      '${zahl.format(_flug.laengeMeter / 1000)} km',
      [
        if (hoch != null) '${hoch.round()} m ${t.flugAufstieg}',
        if (dauer != null)
          '${dauer.inHours > 0 ? '${dauer.inHours}:${(dauer.inMinutes % 60).toString().padLeft(2, '0')} h' : '${dauer.inMinutes} min'} ${t.flugUnterwegs}',
      ].join('   ·   '),
    ];
  }

  /// Über welchen Weg ein eben erschienenes Foto aufblendet, in Metern.
  ///
  /// **Als Anteil der Strecke und nicht als feste Zahl.** Bei einem
  /// Spaziergang von zwei Kilometern wären zweihundert Meter ein Zehntel
  /// des Weges; bei einer Radtour über hundert wären sie zwei
  /// Zehntelsekunden.
  double get _einblendweg => math.max(40.0, _flug.laengeMeter * 0.01);

  /// Welches Foto an dieser Stelle dran ist – das zuletzt erreichte.
  ///
  /// **Es bleibt stehen, bis das nächste kommt.** Vorher galt ein Fenster
  /// von sechs Prozent der Strecke um die Stelle herum; wer nicht
  /// gleichmässig fotografiert, sah dadurch fast nichts. An der Wanderung
  /// Ilsenburg–Ilsefälle–Plesseburg gemessen: 14 Fotos an drei Stellen
  /// einer 16-km-Runde, **22 % des Fluges mit Bild** – die ersten 28 %,
  /// also gerade der Anfang, ganz ohne. Dass dazwischen nicht
  /// fotografiert wurde, ist kein Grund, die Landschaft unbebildert zu
  /// lassen: Das letzte Bild gilt weiter, bis eines an seine Stelle
  /// tritt.
  ///
  /// **Vor dem ersten Foto bleibt es leer**, und das ist Absicht: Dort
  /// gab es keines, und ein vorgezogenes Bild behauptete eine Stelle, an
  /// der es nicht entstanden ist.
  ///
  /// [widget.fotos] ist nach `meter` sortiert (siehe
  /// `_fotosAufDieSpur`); mehrere Fotos an derselben Stelle sind durch
  /// das letzte von ihnen vertreten.
  Flugfoto? _fotoBei(double meter) {
    Flugfoto? erreicht;
    for (final f in widget.fotos) {
      if (f.meter > meter) break;
      erreicht = f;
    }
    return erreicht;
  }

  /// Wie deutlich es gerade zu sehen ist – aufblendend.
  ///
  /// Ein Bild, das hart erscheint, wirkt wie ein Fehler. Abgeblendet wird
  /// nicht mehr: Das Bild geht, wenn das nächste kommt, und den Wechsel
  /// blendet [_Flugbild] selbst über.
  double _fotoDeckkraft(double meter) {
    final f = _fotoBei(meter);
    if (f == null) return 0;
    return ((meter - f.meter) / _einblendweg).clamp(0.0, 1.0);
  }

  /// Mischt zwei Kameraeinstellungen – für Einflug und Abspann.
  ///
  /// **Die Drehung braucht Sonderbehandlung.** Sie ist ein Winkel, und
  /// zwischen 3,1 und −3,1 liegt kein halber Umlauf, sondern ein
  /// Fingerbreit. Ohne die Rechnung mit dem kürzeren Weg drehte sich die
  /// Landschaft beim Einflug einmal ganz herum – am Bild sofort zu
  /// sehen, in Zahlen nie.
  Gelaendekamera _zwischenKamera(
      Gelaendekamera von, Gelaendekamera nach, double t) {
    double misch(double a, double b) => a + (b - a) * t;
    var dd = nach.drehung - von.drehung;
    while (dd > math.pi) {
      dd -= 2 * math.pi;
    }
    while (dd < -math.pi) {
      dd += 2 * math.pi;
    }
    return Gelaendekamera(
      drehung: von.drehung + dd * t,
      neigung: misch(von.neigung, nach.neigung),
      entfernung: misch(von.entfernung, nach.entfernung),
      brennweite: misch(von.brennweite, nach.brennweite),
      mitte: Offset(misch(von.mitte.dx, nach.mitte.dx),
          misch(von.mitte.dy, nach.mitte.dy)),
      blickpunkt: (
        x: misch(von.blickpunkt.x, nach.blickpunkt.x),
        y: misch(von.blickpunkt.y, nach.blickpunkt.y),
        z: misch(von.blickpunkt.z, nach.blickpunkt.z),
      ),
    );
  }

  /// Hebt die Kamera an, wenn sie sonst im Berg stünde – siehe
  /// [ueberDemBoden]. Die Rechnung liegt bei der Sicht, weil sie ohne
  /// ein Pixel auskommt; hier steht nur, woher die Höhen kommen.
  Gelaendekamera _ueberDemBoden(Gelaendekamera k) =>
      ueberDemBoden(k, hoeheBei: _hoeheBei);

  /// Der Zoom beim Beginn einer Wisch-/Kneifgeste.
  ///
  /// Fortgeschrieben wird daraus und nicht aus dem jeweils letzten Wert:
  /// `pan` und `scale` sind der Gesamtweg seit dem Beginn, nicht der Weg
  /// seit dem letzten Ereignis.
  double? _zoomBeginn;

  double _zoomGrenzen(double z) => z.clamp(0.4, 6.0);

  void _ziehen(DragUpdateDetails d) {
    setState(() {
      if (_imFlug) {
        _flugversatz += d.delta.dx * 0.01;
      } else {
        _drehung += d.delta.dx * 0.01;
      }
      _neigung = (_neigung - d.delta.dy * 0.01).clamp(0.15, 1.45);
    });
  }

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    // **Nicht `_uhr.value`, sondern der Anteil des Flugabschnitts.** Die
    // Uhr trägt Einflug, Flug und Abspann; die Spur kennt nur den Flug.
    // Ohne diese Umrechnung wäre die Wanderung schon zu sieben Prozent
    // gelaufen, bevor der Einflug überhaupt ankommt.
    final stand = _imFlug ? _flug.bei(_abschnitt.flug) : null;
    return LayoutBuilder(
      builder: (context, platz) {
        final breite = platz.maxWidth;
        final hoehe = platz.maxHeight;
        // Der Abstand richtet sich nach der Ausdehnung: Eine
        // Zwölf-Kilometer-Wanderung und ein Mittelgebirge sollen beide
        // ins Bild passen, ohne dass jemand zoomt.
        final ausdehnung =
            math.max(widget.netz.breiteMeter, widget.netz.hoeheMeter);
        // Am Bildschirm eingestellt: Mit dem Faktor 1,6 lag die
        // Landschaft als Briefmarke in der Mitte eines schwarzen
        // Fensters.
        final uebersichtkamera = Gelaendekamera(
          drehung: _drehung,
          neigung: _neigung,
          entfernung: ausdehnung * 0.95 / _zoom,
          brennweite: math.min(breite, hoehe) * 1.1,
          mitte: Offset(breite / 2, hoehe * 0.5),
        );
        final kamera = stand == null
            ? Gelaendekamera(
                drehung: _drehung,
                neigung: _neigung,
                entfernung: ausdehnung * 0.95 / _zoom,
                brennweite: math.min(breite, hoehe) * 1.1,
                // Etwas über der Mitte: Bei gekippter Sicht läuft die
                // Landschaft nach hinten oben aus, der Schwerpunkt liegt
                // also unterhalb des Fluchtpunkts.
                mitte: Offset(breite / 2, hoehe * 0.5),
              )
            : Gelaendekamera(
                drehung: stand.drehung + _flugversatz,
                neigung: _neigung,
                entfernung: Gelaendeflug.flugabstand(
                      ausdehnung: ausdehnung,
                      kante: gelaendeGitterkante,
                      brennweite: math.min(breite, hoehe) * 1.1,
                    ) /
                    _zoom,
                brennweite: math.min(breite, hoehe) * 1.1,
                // Beim Flug höher angesetzt: Der Weg soll im unteren
                // Drittel liegen, damit oben die Landschaft steht, in
                // die er hineinführt.
                mitte: Offset(breite / 2, hoehe * 0.62),
                blickpunkt: stand.blickpunkt,
              );

        // **Einflug und Abspann sind dieselbe Bewegung, rückwärts.** Am
        // Anfang von der Übersicht auf den Startpunkt zu, am Ende von der
        // letzten Stelle wieder auf. Eine Kurve dazwischen, damit es
        // nicht ruckt: `easeInOutCubic` beschleunigt und bremst, ein
        // linearer Übergang setzte an beiden Enden hart an.
        final kameraJetzt = _ueberDemBoden(stand == null
            ? kamera
            : (_abschnitt.einflug < 1
                ? _zwischenKamera(uebersichtkamera, kamera,
                    Curves.easeInOutCubic.transform(_abschnitt.einflug))
                : _abschnitt.abspann > 0
                    ? _zwischenKamera(kamera, uebersichtkamera,
                        Curves.easeInOutCubic.transform(_abschnitt.abspann))
                    : kamera));

        // **Sagen, was gebraucht wird – in jedem Bild.** Der Lader
        // arbeitet immer nur an einer Sache und fragt nach jedem
        // fertigen Block neu, was am nächsten liegt. Eine Liste von vor
        // zwei Sekunden führte die Arbeit hinter dem Betrachter her.
        //
        // Steht hier und nicht in einem Rückruf nach dem Bild: Der
        // Wunsch ändert nichts an der Oberfläche, er setzt nur einen
        // Merkposten und stösst eine Aufgabe an. Ein zweiter Durchlauf
        // dafür wäre ein Bild Verzögerung bei jeder Bewegung.
        _lader?.brauche(bloeckeImBild(
          widget.netz,
          kameraJetzt,
          Size(breite, hoehe),
          schaerfe: MediaQuery.devicePixelRatioOf(context),
          uebersichtAufloesung: _uebersichtAufloesung,
        ));

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onPanUpdate: _ziehen,
                child: Listener(
                  onPointerSignal: (e) {
                    if (e is PointerScrollEvent) {
                      setState(() => _zoom = _zoomGrenzen(
                          _zoom * (1 - e.scrollDelta.dy * 0.002)));
                    }
                  },
                  // **Eine Magic Mouse hat kein Rad.** macOS meldet das
                  // Wischen auf ihrer Tastfläche nicht als Radschritte,
                  // sondern als fortlaufende Geste – dieselbe Art
                  // Ereignis wie ein Trackpad. Hier kam bis dahin gar
                  // nichts an: kein Zoom mit der Maus, kein Zoom mit
                  // dem Trackpad (Erstlauf-Bericht, G12). Dieselbe
                  // Behandlung wie bei der Karte, siehe
                  // [WischZoom] – nur ohne den Kunstgriff mit der
                  // Mikroaufgabe, weil hier niemand dazwischenfunkt.
                  onPointerPanZoomStart: (_) => _zoomBeginn = _zoom,
                  onPointerPanZoomUpdate: (e) {
                    final beginn = _zoomBeginn;
                    if (beginn == null) return;
                    // Kneifen und Wischen sind hier beides Zoom: Der
                    // Flug wird mit dem Ziehen gedreht und geneigt, das
                    // Wischen ist also frei.
                    final neu = istWischen(e.scale)
                        ? beginn * math.exp(-e.pan.dy * 0.004)
                        : beginn * e.scale;
                    setState(() => _zoom = _zoomGrenzen(neu));
                  },
                  onPointerPanZoomEnd: (_) => _zoomBeginn = null,
                  child: CustomPaint(
                    size: Size(breite, hoehe),
                    painter: Gelaendemaler(
                      netz: widget.netz,
                      kamera: kameraJetzt,
                      spur: widget.spur,
                      karte: widget.karte,
                      blocktexturen: _lader?.bilder,
                      spurfarbe: farben.error,
                      stimmung: widget.stimmung,
                      // Beim Flug endet die volle Farbe dort, wo man
                      // gerade ist: Was hinter einem liegt, ist
                      // zurückgelegt, was davor liegt, kommt noch. Ohne
                      // diesen Schnitt sieht die Spur im Flug genauso aus
                      // wie im Stillstand, und man verliert, wo man ist.
                      gefahrenBis: stand?.gefahrenMeter,
                      streckeJePunkt: _imFlug ? _flug.streckeJePunkt : null,
                      schilder: widget.schilder,
                      hoeheBei: _hoeheBei,
                    ),
                  ),
                ),
              ),
            ),
            // Das Foto zur Stelle – oben rechts, damit es die Spur
            // unten und die Schilder in der Mitte nicht verdeckt.
            if (stand != null)
              Positioned(
                top: AppSpacing.md,
                right: AppSpacing.md,
                child: _Flugbild(
                  foto: _fotoBei(stand.gefahrenMeter),
                  deckkraft: _fotoDeckkraft(stand.gefahrenMeter),
                ),
              ),
            if (stand != null && _abschnitt.abspann > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Opacity(
                      opacity:
                          Curves.easeIn.transform(_abschnitt.abspann.clamp(0.0, 1.0)),
                      child: _Abspann(
                          key: _Abspann.schluessel,
                          flug: _flug,
                          tempo: _flugtempo),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.fussnoten.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0,
                          AppSpacing.md, AppSpacing.sm),
                      // Beide biegsam: Die linke Fussnote erklärt die
                      // Bedienung und ist lang, die rechte trägt die
                      // Namensnennung. Auf einem schmalen Fenster passen
                      // sie nicht nebeneinander, und ein starres `Row`
                      // lief dort um 413 Punkte über.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(child: widget.fussnoten.first),
                          const SizedBox(width: AppSpacing.sm),
                          if (widget.fussnoten.length > 1)
                            Flexible(child: widget.fussnoten[1]),
                        ],
                      ),
                    ),
                  if (_flug.moeglich)
                    Flugleiste(
                      flug: _flug,
                      stand: stand,
                      fortschritt: _uhr.value,
                      laeuft: _uhr.isAnimating,
                      imFlug: _imFlug,
                      beimSchalten: _flugSchalten,
                      beimBeenden: _flugBeenden,
                      beimSpulen: _spulen,
                      beimAusgeben:
                          widget.beimVideoZiel == null ? null : _videoAusgeben,
                      gibtAus: _videoLaeuft,
                      ausgabeFortschritt:
                          _videoLaeuft ? _videoFortschritt : null,
                      ausgabeRest: _videoRest,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Die Leiste unter dem Flug: Steuerung, Messwerte und das Höhenprofil,
/// das mitläuft.
///
/// **Warum die Zahlen hierher gehören und nicht in eine Ecke.** Ein Flug
/// über eine Landschaft ist schön und sagt nichts. Was er soll, ist die
/// Frage beantworten „wie war der Weg" – und die beantworten Höhe,
/// Steigung und Tempo, nicht die Aussicht. Sie stehen deshalb in der
/// Leseachse unter dem Bild und nicht als Kleingedrucktes am Rand.
///
/// **Warum eine eigene Klasse.** Die Ansicht darüber ist ein
/// `CustomPaint` mit einer selbstgerechneten Kamera; hier sind es
/// Material-Widgets. Beides in einem `build` wäre zweihundert Zeilen, in
/// denen niemand mehr die Kamera findet.
class Flugleiste extends StatelessWidget {
  final Gelaendeflug flug;

  /// Der aktuelle Stand – `null` heisst: Übersicht, es wird nicht
  /// geflogen.
  final Flugstand? stand;

  final double fortschritt;
  final bool laeuft;
  final bool imFlug;
  final VoidCallback beimSchalten;
  final VoidCallback beimBeenden;
  final ValueChanged<double> beimSpulen;

  /// Den Flug als Video schreiben – `null` heisst: geht hier nicht.
  final VoidCallback? beimAusgeben;

  /// Ob gerade ausgegeben wird. Dann ist der Knopf ein Abbruch.
  final bool gibtAus;

  /// Wie weit die Ausgabe ist – `null` heisst: läuft keine.
  final double? ausgabeFortschritt;

  /// Wie lange die Ausgabe noch braucht, oder `null`.
  final Duration? ausgabeRest;

  const Flugleiste({
    super.key,
    required this.flug,
    required this.stand,
    required this.fortschritt,
    required this.laeuft,
    required this.imFlug,
    required this.beimSchalten,
    required this.beimBeenden,
    required this.beimSpulen,
    this.beimAusgeben,
    this.gibtAus = false,
    this.ausgabeFortschritt,
    this.ausgabeRest,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final sprache = Localizations.localeOf(context).toString();
    final eine = NumberFormat.decimalPatternDigits(
        locale: sprache, decimalDigits: 1);

    final anteil = ausgabeFortschritt;

    return ColoredBox(
      color: farben.surface.withValues(alpha: 0.88),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // **Der Balken, den es bis 3.5.1 nicht gab.** Der Fortschritt
            // wurde gerechnet und bis hierher durchgereicht – und dann
            // nirgends gezeichnet. Zu sehen war allein, dass aus dem
            // Filmzeichen ein Stoppzeichen wurde. Wer auf eine Wanderung
            // von sechzehn Kilometern rund zweitausend Bilder ausgeben
            // liess, sass also eine Minute oder länger vor einer
            // Oberfläche, die nichts sagte, und hielt das für „es tut
            // nichts".
            if (anteil != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ausgabeRest == null
                          ? t.flugVideoLaeuft((anteil * 100).round())
                          : t.flugVideoLaeuftMitRest((anteil * 100).round(),
                              dauerText(t, ausgabeRest!)),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              LinearProgressIndicator(value: anteil.clamp(0.0, 1.0)),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (imFlug) ...[
              _Messwerte(stand: stand!, flug: flug),
              const SizedBox(height: AppSpacing.sm),
              // Das Profil trägt die Stelle mit, an der der Flug steht –
              // und nimmt einen Griff darauf an: Wer hineinfährt, spult.
              // Dieselbe Geste, die es für die Karte schon konnte.
              _Flugprofil(flug: flug, fortschritt: fortschritt,
                  beimSpulen: beimSpulen),
            ],
            Row(
              children: [
                IconButton(
                  tooltip: !imFlug
                      ? t.flugStarten
                      : laeuft
                          ? t.flugAnhalten
                          : (fortschritt >= 1 ? t.flugNochmal : t.flugWeiter),
                  icon: Icon(!imFlug
                      ? Icons.flight_takeoff
                      : laeuft
                          ? Icons.pause_circle_outline
                          : (fortschritt >= 1
                              ? Icons.replay
                              : Icons.play_circle_outline)),
                  onPressed: beimSchalten,
                ),
                if (imFlug)
                  IconButton(
                    tooltip: t.flugBeenden,
                    icon: const Icon(Icons.zoom_out_map),
                    onPressed: beimBeenden,
                  ),
                // Der Ausgabeknopf steht bei den Flugknöpfen und nicht in
                // der Werkzeugleiste oben: Was ausgegeben wird, ist der
                // Flug, nicht die Ansicht.
                if (beimAusgeben != null)
                  IconButton(
                    tooltip: gibtAus ? t.flugVideoAbbrechen : t.flugVideo,
                    icon: Icon(gibtAus
                        ? Icons.stop_circle_outlined
                        : Icons.movie_outlined),
                    onPressed: beimAusgeben,
                  ),
                Expanded(
                  child: Slider(
                    value: fortschritt.clamp(0.0, 1.0),
                    // Nur beim Flug greifbar: In der Übersicht bewegt der
                    // Regler nichts, was zu sehen wäre, und ein Regler
                    // ohne Wirkung ist schlimmer als keiner.
                    onChanged: imFlug ? beimSpulen : null,
                    label: t.flugFortschritt,
                  ),
                ),
                Text(
                  t.flugKm(eine.format(
                      (stand?.gefahrenMeter ?? flug.laengeMeter) / 1000)),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Höhe, Tempo, Steigung, Dauer – in einer Zeile, die umbrechen darf.
class _Messwerte extends StatelessWidget {
  final Flugstand stand;
  final Gelaendeflug flug;
  const _Messwerte({required this.stand, required this.flug});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final sprache = Localizations.localeOf(context).toString();
    final eine =
        NumberFormat.decimalPatternDigits(locale: sprache, decimalDigits: 1);

    final werte = <({String name, String wert, Color? farbe})>[
      if (stand.hoeheMeter case final h?)
        (name: t.flugHoehe, wert: t.flugMeterProfil(h.round()), farbe: null),
      if (stand.tempoMeterJeSekunde case final v?)
        // In km/h und nicht in m/s: Niemand denkt eine Wanderung in
        // Metern je Sekunde.
        (name: t.flugTempo, wert: t.flugKmH(eine.format(v * 3.6)), farbe: null),
      if (stand.steigungProzent case final st?)
        (
          name: t.flugSteigung,
          wert: t.flugProzent(eine.format(st)),
          // Bergauf und bergab unterscheiden sich schon durch das
          // Vorzeichen; die Farbe macht es auf einen Blick lesbar, ohne
          // die einzige Auskunft zu sein (siehe 18. Prüfrunde).
          farbe: st.abs() < 1
              ? null
              : (st > 0 ? farben.error : farben.primary),
        ),
      if (stand.seitStart case final d?)
        (name: t.flugUnterwegs, wert: _dauertext(d), farbe: null),
    ];

    if (werte.isEmpty) {
      return Text(t.flugOhneZeit,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: farben.onSurfaceVariant));
    }

    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: [
        for (final w in werte)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(w.name,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: farben.onSurfaceVariant)),
              const SizedBox(width: AppSpacing.xs),
              Text(
                w.wert,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: w.farbe,
                      fontFeatures: const [
                        // Ohne feste Zifferbreite zappelt jede Zahl bei
                        // jedem Bild – zwanzig Mal in der Sekunde.
                        ui.FontFeature.tabularFigures(),
                      ],
                    ),
              ),
            ],
          ),
      ],
    );
  }

  /// `1:04:37` bzw. `4:37` – ohne führende Null bei den Stunden und mit
  /// zweistelligen Minuten, wie man eine Dauer liest.
  static String _dauertext(Duration d) {
    final s = d.inSeconds;
    final st = s ~/ 3600;
    final min = (s % 3600) ~/ 60;
    final sek = s % 60;
    final zwei = sek.toString().padLeft(2, '0');
    return st > 0
        ? '$st:${min.toString().padLeft(2, '0')}:$zwei'
        : '$min:$zwei';
  }
}

/// Das Höhenprofil mit der Stelle, an der der Flug steht.
///
/// Eigener Maler und nicht [Hoehenprofil]: Jenes markiert einen
/// **Stützpunkt** und will angefahren werden, damit die Karte daneben
/// mitgeht. Hier ist die Stelle ein stufenloser Wert zwischen zwei
/// Punkten, sie kommt von der Uhr und nicht vom Zeiger, und der
/// zurückgelegte Teil soll sich vom kommenden abheben. Das ist genug
/// Unterschied für einen eigenen, sehr kurzen Maler – und es hält das
/// vorhandene Profil aus der Wanderansicht unangetastet.
class _Flugprofil extends StatelessWidget {
  final Gelaendeflug flug;
  final double fortschritt;
  final ValueChanged<double> beimSpulen;

  static const double hoehe = 64;

  const _Flugprofil({
    required this.flug,
    required this.fortschritt,
    required this.beimSpulen,
  });

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    // Aus dem Flug und nicht hier gebaut: Diese Liste ist je Flug
    // dieselbe, die Leiste baut sich aber in jedem Bild neu.
    final punkte = flug.hoehenprofil;
    if (punkte.length < 2) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: AppTexte.of(context).flugProfilBeschreibung,
      child: LayoutBuilder(
        builder: (context, platz) {
          void spulen(double x) =>
              beimSpulen((x / platz.maxWidth).clamp(0.0, 1.0));
          return GestureDetector(
            onHorizontalDragUpdate: (d) => spulen(d.localPosition.dx),
            onTapDown: (d) => spulen(d.localPosition.dx),
            child: CustomPaint(
              size: Size(platz.maxWidth, hoehe),
              painter: _Flugprofilmaler(
                punkte: punkte,
                gesamt: flug.laengeMeter,
                fortschritt: fortschritt,
                gefahren: farben.primary,
                kommend: farben.outlineVariant,
                marke: farben.error,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Flugprofilmaler extends CustomPainter {
  final List<({double meter, double hoehe})> punkte;
  final double gesamt;
  final double fortschritt;
  final Color gefahren;
  final Color kommend;
  final Color marke;

  _Flugprofilmaler({
    required this.punkte,
    required this.gesamt,
    required this.fortschritt,
    required this.gefahren,
    required this.kommend,
    required this.marke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (punkte.length < 2 || gesamt <= 0) return;
    var tief = punkte.first.hoehe;
    var hoch = punkte.first.hoehe;
    for (final p in punkte) {
      tief = math.min(tief, p.hoehe);
      hoch = math.max(hoch, p.hoehe);
    }
    // **Nicht bei null anfangen** – dieselbe Überlegung wie im
    // Wanderprofil: Eine Runde zwischen 300 und 380 m wäre über einer
    // Nulllinie ein waagerechter Strich. Und mindestens zehn Meter Luft,
    // sonst blähte eine flache Runde ihre Wellen zu Bergen auf.
    final luft = math.max((hoch - tief) * 0.1, 10.0);
    final unten = tief - luft;
    final oben = hoch + luft;

    double x(double meter) => meter / gesamt * size.width;
    double y(double h) =>
        size.height - (h - unten) / (oben - unten) * size.height;

    final linie = Path()..moveTo(x(punkte.first.meter), y(punkte.first.hoehe));
    for (final p in punkte.skip(1)) {
      linie.lineTo(x(p.meter), y(p.hoehe));
    }
    final gefuellt = Path.from(linie)
      ..lineTo(x(punkte.last.meter), size.height)
      ..lineTo(x(punkte.first.meter), size.height)
      ..close();

    // Der zurückgelegte Teil wird durch ein Fenster gefüllt, nicht durch
    // einen zweiten Pfad: So folgt die Kante genau der Höhenlinie,
    // stufenlos zwischen zwei Stützpunkten – ein aus Punkten gebauter
    // Teilpfad spränge von Punkt zu Punkt.
    final xJetzt = size.width * fortschritt.clamp(0.0, 1.0);
    canvas.drawPath(gefuellt, Paint()..color = kommend.withValues(alpha: 0.5));
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, xJetzt, size.height));
    canvas.drawPath(gefuellt, Paint()..color = gefahren.withValues(alpha: 0.35));
    canvas.restore();

    canvas.drawPath(
      linie,
      Paint()
        ..color = gefahren
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawLine(Offset(xJetzt, 0), Offset(xJetzt, size.height),
        Paint()..color = marke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_Flugprofilmaler alt) =>
      alt.fortschritt != fortschritt ||
      alt.punkte != punkte ||
      alt.gefahren != gefahren;
}

/// Das Foto zur Stelle, oben rechts im Bild.
///
/// **Der Punkt, an dem sich eine Fotoverwaltung von einem Sportprogramm
/// unterscheidet.** Strava und Relive fliegen dieselbe Spur ab; nur hier
/// liegen die Bilder schon daneben. Beim Vorbeifliegen taucht das
/// Vorschaubild auf und verblasst wieder – nicht als Liste am Rand,
/// sondern zu der Stelle, an der es entstanden ist.
class _Flugbild extends StatelessWidget {
  const _Flugbild({required this.foto, required this.deckkraft});

  final Flugfoto? foto;
  final double deckkraft;

  /// Wie gross das Bild höchstens wird.
  ///
  /// Zweihundertvierzig Punkte. Grösser verdeckt es die Landschaft, um
  /// die es geht; kleiner erkennt man nicht, was darauf ist.
  static const double kante = 240;

  @override
  Widget build(BuildContext context) {
    final f = foto;
    // **`AnimatedOpacity` und kein `if`.** Ohne die Animation springt das
    // Bild beim Wechsel von einem zum nächsten hart um; das Auf- und
    // Abblenden über die Strecke (siehe `_fotoDeckkraft`) allein reicht
    // nicht, weil zwei dicht beieinander liegende Fotos einander
    // ablösen, ohne dass die Deckkraft dazwischen auf null fällt.
    return AnimatedOpacity(
      opacity: f == null ? 0 : deckkraft.clamp(0.0, 1.0),
      duration: const Duration(milliseconds: 180),
      // **Eine feste Breite, und der Grund ist eine Fehlermeldung.** Das
      // Bild haengt in einem `Positioned` mit nur `top` und `right`; die
      // Breite ist dort unbegrenzt, und eine `Column` mit `stretch`
      // darin bricht beim Vermessen ab.
      child: f == null
          ? const SizedBox(width: kante + 8, height: 1)
          : SizedBox(
              width: kante + 8,
              child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x66000000), blurRadius: 10, spreadRadius: 1),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: kante, maxHeight: kante),
                        child: Image(
                          image: f.bild,
                          fit: BoxFit.cover,
                          width: kante,
                          height: kante * 0.75,
                          // Ein Bild, das nicht kommt, darf keinen roten
                          // Kasten in die Landschaft setzen.
                          errorBuilder: (_, __, ___) =>
                              const SizedBox(width: kante, height: 1),
                        ),
                      ),
                    ),
                    if (f.unterschrift case final u?)
                      Padding(
                        padding: const EdgeInsets.only(top: 3, bottom: 1),
                        child: Text(
                          u,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

/// Der Abspann – die Zahlen der Tour, wenn die Kamera wieder aufzieht.
///
/// **Was am Ende bleibt, ist nicht das letzte Bild, sondern die Bilanz.**
/// Bis hierher blieb der Flug einfach stehen, wo er zu Ende war; die
/// Zahlen standen zwar in der Leiste darunter, aber sie standen dort die
/// ganze Zeit und wurden zum Schluss nicht mehr angesehen.
class _Abspann extends StatelessWidget {
  const _Abspann({super.key, required this.flug, required this.tempo});

  /// Damit ein Test die Zahlen des Abspanns von denen der Flugleiste
  /// unterscheiden kann – beide zeigen „unterwegs".
  static const schluessel = ValueKey('gelaende-abspann');

  final Gelaendeflug flug;
  final double tempo;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    // **`format` will eine Zahl, keinen Text.** Der erste Anlauf reichte
    // `toStringAsFixed(1)` hinein; das wirft erst zur Laufzeit und nur
    // dann, wenn der Abspann wirklich erscheint – gefunden hat es der
    // Bedienungstest, nicht der Übersetzer.
    final zahl = NumberFormat(
        '#,##0.0', Localizations.localeOf(context).toLanguageTag());

    final hoch = flug.aufstiegMeter;
    final dauer = flug.gesamtdauer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: farben.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 18, spreadRadius: 2),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${zahl.format(flug.laengeMeter / 1000)} km',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w300,
                color: farben.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hoch != null) ...[
                  _Zahl(wert: '${hoch.round()} m', was: t.flugAufstieg),
                  const SizedBox(width: AppSpacing.xl),
                ],
                if (dauer != null)
                  _Zahl(
                      wert: _dauerText(dauer), was: t.flugUnterwegs),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _dauerText(Duration d) {
    final st = d.inHours;
    final mi = d.inMinutes % 60;
    return st > 0 ? '$st:${mi.toString().padLeft(2, '0')} h' : '$mi min';
  }
}

class _Zahl extends StatelessWidget {
  const _Zahl({required this.wert, required this.was});
  final String wert;
  final String was;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(wert,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: farben.onSurface)),
        Text(was,
            style: TextStyle(fontSize: 11, color: farben.onSurfaceVariant)),
      ],
    );
  }
}
