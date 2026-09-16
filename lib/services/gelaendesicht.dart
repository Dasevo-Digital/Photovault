/// Die Kamera für die Geländeansicht – von Hand gerechnet.
///
/// **Warum ohne 3D-Bibliothek.** Bei MapLibre trug ein Paket auf pub.dev
/// einen grünen Haken für Linux und scheiterte dort trotzdem. Hier kommt
/// nichts dazu, was scheitern könnte: Gezeichnet wird mit
/// `Canvas.drawVertices`, und das ist Flutter selbst. Was fehlt, ist
/// allein die Kamera – und die sind zwei Drehungen und eine Division.
///
/// Reine Rechnung ohne Flutter-Abhängigkeit ausser `Offset`, damit sich
/// jede Drehung prüfen lässt, ohne ein Fenster zu öffnen.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'lichtstimmung.dart';

/// Wie stark die Höhe gegenüber der Fläche übertrieben wird.
///
/// **Dreifach, und das ist eine Entscheidung, keine Messung.** Massstäblich
/// wäre eine Zwölf-Kilometer-Wanderung mit dreihundert Höhenmetern eine
/// ebene Platte: Der Höhenunterschied ist zweieinhalb Prozent der Breite.
/// Jede Geländedarstellung überhöht deshalb; wer es nicht tut, zeigt
/// nichts. Zwei ist zurückhaltend – Kartenprogramme nehmen oft drei bis
/// fünf.
const double gelaendeUeberhoehung = 3;

/// Ein Punkt im Raum, in Metern: x nach Osten, y nach Norden, z nach oben.
typedef Raumpunkt = ({double x, double y, double z});

/// Wohin ein Raumpunkt auf dem Bildschirm fällt.
typedef Bildpunkt = ({Offset stelle, double tiefe});

/// Kippen, Drehen, Zoomen – und die Umrechnung auf den Bildschirm.
class Gelaendekamera {
  /// Drehung um die Hochachse, im Bogenmass. 0 heisst: von Süden aus.
  final double drehung;

  /// Neigung, im Bogenmass – **0 ist Augenhöhe, π/2 ist senkrecht von
  /// oben.**
  ///
  /// Hier stand es lange andersherum. Nachgerechnet an [projiziere]:
  /// Bei 0 ist `y2 = y1` und `z2 = z`, die Tiefe ist also der waagerechte
  /// Abstand und oben im Bild ist oben in der Welt – ein Blick von der
  /// Seite. Bei π/2 ist `y2 = -z` und `z2 = y1`, die Tiefe kommt aus der
  /// Höhe und oben im Bild ist Norden – eine Karte.
  ///
  /// Aufgefallen ist es erst beim Flug: Die erste Fassung stellte die
  /// Kamera auf 1,26 in der Annahme, das sei flach. Es war das Gegenteil,
  /// und der Flug sah aus wie eine gekippte Karte.
  final double neigung;

  /// Wie weit die Kamera vom Mittelpunkt weg steht, in Metern.
  final double entfernung;

  /// Brennweite in Bildpunkten – bestimmt, wie stark die Perspektive
  /// wirkt.
  final double brennweite;

  /// Die Mitte des Bildes.
  final Offset mitte;

  /// Der Punkt, um den die Kamera kreist – in denselben Metern wie das
  /// Netz.
  ///
  /// Bis zum Flug gab es ihn nicht: Die Kamera drehte sich immer um den
  /// Nullpunkt, also um die Mitte der geladenen Landschaft. Für eine
  /// Ansicht, die das Ganze zeigt, ist das genau richtig; für einen Flug
  /// entlang der Spur muss sich der Bezugspunkt mitbewegen. Der
  /// Nullpunkt bleibt die Vorgabe, damit sich für die Handbedienung
  /// nichts ändert.
  final Raumpunkt blickpunkt;

  static const Raumpunkt nullpunkt = (x: 0.0, y: 0.0, z: 0.0);

  const Gelaendekamera({
    required this.drehung,
    required this.neigung,
    required this.entfernung,
    required this.brennweite,
    required this.mitte,
    this.blickpunkt = nullpunkt,
  });

  Gelaendekamera kopieMit({
    double? drehung,
    double? neigung,
    double? entfernung,
    double? brennweite,
    Offset? mitte,
    Raumpunkt? blickpunkt,
  }) =>
      Gelaendekamera(
        drehung: drehung ?? this.drehung,
        neigung: neigung ?? this.neigung,
        entfernung: entfernung ?? this.entfernung,
        brennweite: brennweite ?? this.brennweite,
        mitte: mitte ?? this.mitte,
        blickpunkt: blickpunkt ?? this.blickpunkt,
      );

  /// Wo die Kamera selbst steht – in denselben Metern wie das Netz.
  ///
  /// [projiziere] setzt die Kamera in den Ursprung und schiebt die Welt
  /// um [entfernung] von ihr weg; hier ist derselbe Weg rückwärts
  /// gegangen. Gebraucht wird das an zwei Stellen, an denen die
  /// Bildstelle nicht reicht: für die **Reihenfolge der Blöcke** (was
  /// weiter weg ist, wird zuerst gemalt) und für die **Wahl der
  /// Kachelstufe** (was näher ist, wird schärfer geladen). Beide
  /// brauchen einen Abstand in Metern, nicht eine Tiefe im Bild.
  Raumpunkt get standort {
    final cn = math.cos(neigung);
    final sn = math.sin(neigung);
    final y1 = -entfernung * cn;
    final z = entfernung * sn;
    final cd = math.cos(drehung);
    final sd = math.sin(drehung);
    // Die Umkehrung der Drehung in [projiziere]: dort x1 = x·cos − y·sin.
    return (
      x: blickpunkt.x + y1 * sd,
      y: blickpunkt.y + y1 * cd,
      z: blickpunkt.z + z,
    );
  }

  /// Rechnet einen Raumpunkt auf den Bildschirm.
  ///
  /// Erst um die Hochachse drehen, dann kippen, dann die Kamera nach
  /// hinten schieben, dann teilen. Punkte hinter der Kamera bekommen
  /// eine [Bildpunkt.tiefe] ≤ 0 – wer sie zeichnet, bekommt Unsinn, und
  /// deshalb steht die Zahl dabei.
  Bildpunkt projiziere(Raumpunkt p) {
    // Erst den Blickpunkt abziehen: Gedreht und gekippt wird um ihn,
    // nicht um den Nullpunkt der Landschaft.
    final px = p.x - blickpunkt.x;
    final py = p.y - blickpunkt.y;
    final pz = p.z - blickpunkt.z;

    final cd = math.cos(drehung);
    final sd = math.sin(drehung);
    final x1 = px * cd - py * sd;
    final y1 = px * sd + py * cd;

    final cn = math.cos(neigung);
    final sn = math.sin(neigung);
    // Nach dem Kippen zeigt y2 in die Tiefe und z2 nach oben im Bild.
    final y2 = y1 * cn - pz * sn;
    final z2 = y1 * sn + pz * cn;

    final tiefe = y2 + entfernung;
    if (tiefe <= 1) {
      return (stelle: Offset(mitte.dx, mitte.dy), tiefe: tiefe);
    }
    final f = brennweite / tiefe;
    // Das Minus vor z2: Auf dem Bildschirm wächst y nach unten, in der
    // Landschaft wächst die Höhe nach oben.
    return (
      stelle: Offset(mitte.dx + x1 * f, mitte.dy - z2 * f),
      tiefe: tiefe,
    );
  }
}

/// Wie viele Meter die Kamera mindestens über dem Boden bleibt.
///
/// In den Einheiten des Netzes, also bereits überhöht
/// ([gelaendeUeberhoehung]). Fünfzig sind knapp: Sie reichen, damit kein
/// Hang durchs Bild schneidet, und liegen tief genug, dass ein Flug
/// durch ein Tal auch wirklich im Tal bleibt.
const double gelaendeBodenabstand = 50;

/// Hebt [k] an, wenn die Kamera sonst im Berg stünde.
///
/// **Der Fund.** Aus dem Erstlauf-Bericht: „im Flug teilweise breiig
/// oder es fliegt unter dem Berg". Die Kamera kreist um ihren
/// Blickpunkt; bei flacher [Gelaendekamera.neigung] steht sie fast auf
/// dessen Höhe und damit **innerhalb** des Hangs, der hinter dem Weg
/// ansteigt. Gezeichnet wird dann die Landschaft von innen, und das
/// sieht aus wie ein Fehler im Maler.
///
/// Angehoben wird über die Neigung und nicht über den Blickpunkt: Das
/// ist dieselbe Bewegung, die ein Pilot machen würde, und der Weg bleibt
/// dabei im Bild. Gesucht wird die **kleinste** Neigung, die reicht –
/// eine feste Anhebung machte jeden flachen Flug unnötig steil.
///
/// [hoeheBei] liefert die Geländehöhe an einer Stelle des Netzes oder
/// `null`, wo das Höhengitter nichts weiss; dort gibt es auch nichts zu
/// unterschreiten.
Gelaendekamera ueberDemBoden(
  Gelaendekamera k, {
  required double? Function(double x, double y) hoeheBei,
  double abstand = gelaendeBodenabstand,
  double hoechsteNeigung = 1.45,
}) {
  bool frei(Gelaendekamera kandidat) {
    final wo = kandidat.standort;
    final boden = hoeheBei(wo.x, wo.y);
    return boden == null || wo.z >= boden + abstand;
  }

  if (frei(k)) return k;
  // Senkrecht von oben steht die Kamera immer frei; dazwischen wird
  // gesucht. Acht Halbierungen treffen die Neigung auf ein
  // Zweihundertstel genau – genauer, als ein Auge es sieht.
  final steil = k.kopieMit(neigung: hoechsteNeigung);
  if (!frei(steil)) return steil;
  var unten = k.neigung;
  var oben = hoechsteNeigung;
  for (var i = 0; i < 8; i++) {
    final mitte = (unten + oben) / 2;
    if (frei(k.kopieMit(neigung: mitte))) {
      oben = mitte;
    } else {
      unten = mitte;
    }
  }
  return k.kopieMit(neigung: oben);
}

/// Wie viele Meter ein Grad Länge auf einer Breite misst.
double meterJeGradLaenge(double breite) =>
    111320 * math.cos(breite * math.pi / 180);

/// Und wie viele ein Grad Breite – nahezu überall gleich.
const double meterJeGradBreite = 110540;

/// Die Schattierung einer Dreiecksfläche: 0 (im Schatten) bis 1 (voll
/// beleuchtet).
///
/// Ein einfaches Lambert-Modell mit der Sonne aus [stimmung]. **Aus
/// Nordwesten und nicht aus Südosten**, obwohl die Sonne dort nie steht:
/// Das Auge liest eine von links oben beleuchtete Fläche als erhaben und
/// eine von rechts unten beleuchtete als vertieft. Wer physikalisch
/// richtig beleuchtet, dreht jedes Tal zum Berg. Deshalb bleibt die
/// Himmelsrichtung über alle Tageszeiten gleich, und nur die Höhe der
/// Sonne wandert (siehe [Lichtstimmung]).
///
/// Ohne Angabe gilt [stimmungMittag] – genau die Zahlen, die hier
/// vorher fest standen.
double schattierung(Raumpunkt normale,
    [Lichtstimmung stimmung = stimmungMittag]) {
  final l = stimmung.sonne;
  final laenge = math.sqrt(normale.x * normale.x +
      normale.y * normale.y +
      normale.z * normale.z);
  if (laenge == 0) return 1;
  final punktprodukt =
      (normale.x * l.x + normale.y * l.y + normale.z * l.z) / laenge;
  // **Viel Grundhelligkeit, wenig Richtungslicht.** Liegt eine Karte
  // darauf, multipliziert die Schattierung sie: Bei 0,45 Grundhelligkeit
  // war die halbe Karte am Bildschirm nicht mehr zu lesen. Und nicht bis
  // auf null abdunkeln – eine schwarze Nordflanke sieht aus wie ein Loch
  // im Gitter. Wie weit beides geht, entscheidet die Stimmung.
  return (stimmung.grundlicht + stimmung.richtungslicht * punktprodukt)
      .clamp(stimmung.untergrenze, 1.0);
}

/// Die Flächennormale eines Dreiecks.
Raumpunkt normale(Raumpunkt a, Raumpunkt b, Raumpunkt c) {
  final ux = b.x - a.x;
  final uy = b.y - a.y;
  final uz = b.z - a.z;
  final vx = c.x - a.x;
  final vy = c.y - a.y;
  final vz = c.z - a.z;
  return (
    x: uy * vz - uz * vy,
    y: uz * vx - ux * vz,
    z: ux * vy - uy * vx,
  );
}
