import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../db/database.dart';
import '../services/faechertafel.dart';
import '../services/stammbaum.dart';
import '../theme/app_spacing.dart';

/// Das Fächerdiagramm: die Vorfahren einer Person als Ringe.
///
/// Die gewählte Baumoptik – und zwar aus einem Grund, der sich nachrechnen
/// lässt: Ein Platz im Ring hat immer **genau einen** Nachfolger im Ring
/// darunter. Deshalb kann hier keine Linie mehrdeutig werden, und deshalb
/// darf diese Ansicht vier Generationen zeigen, wo die Reihen-Ansicht bei
/// einer bleiben muss.
///
/// Was der Fächer nicht kann: Nachkommen. Er ist auf Verdopplung nach
/// außen gebaut, und Kinder verzweigen unregelmäßig. Dafür gibt es die
/// Nachfahrengliederung – die beiden zusammen decken beide Richtungen ab.
class FaecherAnsicht extends StatelessWidget {
  final List<Fachplatz> plaetze;
  final Map<String, PersonData> personen;
  final void Function(String personId) onTippen;

  const FaecherAnsicht({
    super.key,
    required this.plaetze,
    required this.personen,
    required this.onTippen,
  });

  /// Wie viele Ringe tatsächlich belegt sind – der Fächer wird nur so
  /// groß gezeichnet, wie er Inhalt hat. Ein leerer äußerer Ring als
  /// breiter grauer Rand sähe aus wie ein Fehler.
  int get _ringe => plaetze.fold(0, (m, p) => p.ring > m ? p.ring : m);

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, platz) {
        // Der Halbkreis öffnet sich nach oben, die Mitte sitzt also unten.
        // Der Radius ist durch beides begrenzt: halbe Breite und volle
        // Höhe.
        final radius = math.min(platz.maxWidth / 2, platz.maxHeight) -
            AppSpacing.xl;
        final ringBreite = radius / (_ringe + 1);
        // Ein Halbkreis ist doppelt so breit wie hoch. Ist die Fläche
        // höher als das, bliebe oben ein leeres Band, wenn der Fußpunkt
        // unten säße – deshalb wird der Halbkreis in der Höhe zentriert.
        final mitte = Offset(
          platz.maxWidth / 2,
          (platz.maxHeight + radius) / 2,
        );

        // Ein CustomPaint ist für die Sprachausgabe eine leere Fläche.
        // Ohne die Beschriftungen unten wäre der Fächer für jemanden, der
        // ihn sich vorlesen lässt, überhaupt nicht vorhanden.
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: Stack(
            children: [
              GestureDetector(
                onTapUp: (d) {
                  final rel = d.localPosition - mitte;
                  final winkel = math.atan2(rel.dy, rel.dx);
                  final getroffen =
                      platzBei(plaetze, winkel, rel.distance / ringBreite);
                  final id = getroffen?.personId;
                  if (id != null) onTippen(id);
                },
                child: CustomPaint(
                  size: Size(platz.maxWidth, platz.maxHeight),
                  painter: _FaecherMaler(
                    plaetze: plaetze,
                    personen: personen,
                    mitte: mitte,
                    ringBreite: ringBreite,
                    farben: farben,
                    textRichtung: Directionality.of(context),
                  ),
                ),
              ),
              ..._vorleseFlaechen(mitte, ringBreite),
            ],
          ),
        );
      },
    );
  }

  /// Für jeden belegten Platz ein unsichtbares, aber vorlesbares Feld an
  /// seiner Stelle.
  ///
  /// Rechteckig statt in Ringform: Die Sprachausgabe liest Beschriftungen,
  /// keine Umrisse – für sie zählt, dass jede Person genau einmal vorkommt
  /// und sich antippen lässt.
  List<Widget> _vorleseFlaechen(Offset mitte, double ringBreite) {
    final felder = <Widget>[];
    for (final p in plaetze) {
      final person = p.personId == null ? null : personen[p.personId];
      if (person == null) continue;
      final abstand = (p.ring + 0.5) * ringBreite;
      final punkt = Offset(
        mitte.dx + abstand * math.cos(p.mittelWinkel),
        mitte.dy + abstand * math.sin(p.mittelWinkel),
      );
      felder.add(Positioned(
        left: punkt.dx - 24,
        top: punkt.dy - 12,
        width: 48,
        height: 24,
        child: Semantics(
          label: person.name,
          button: true,
          onTap: () => onTippen(person.id),
          child: const SizedBox.expand(),
        ),
      ));
    }
    return felder;
  }
}

/// Zeichnet den Fächer auf eine beliebige Leinwand.
///
/// Als freie Funktion und nicht nur im [CustomPainter], damit die
/// PDF-Tafel (siehe services/tafel_pdf.dart) exakt dieselbe Zeichnung
/// bekommt. Zwei Malroutinen für dasselbe Bild liefen früher oder später
/// auseinander – und die Abweichung fiele erst auf dem gedruckten Blatt
/// auf.
///
/// [schriftFaktor] skaliert die Schrift mit der Leinwand: Auf dem Schirm
/// 1, auf einer 2400 Pixel breiten Tafel entsprechend mehr.
void maleFaecher({
  required Canvas canvas,
  required List<Fachplatz> plaetze,
  required Map<String, PersonData> personen,
  required Offset mitte,
  required double ringBreite,
  required ColorScheme farben,
  required TextDirection textRichtung,
  double schriftFaktor = 1,
}) {
  final maler = _FaecherMaler(
    plaetze: plaetze,
    personen: personen,
    mitte: mitte,
    ringBreite: ringBreite,
    farben: farben,
    textRichtung: textRichtung,
    schriftFaktor: schriftFaktor,
  );
  for (final p in plaetze) {
    maler._malePlatz(canvas, p);
  }
}

class _FaecherMaler extends CustomPainter {
  final List<Fachplatz> plaetze;
  final Map<String, PersonData> personen;
  final Offset mitte;
  final double ringBreite;
  final ColorScheme farben;
  final TextDirection textRichtung;
  final double schriftFaktor;

  _FaecherMaler({
    required this.plaetze,
    required this.personen,
    required this.mitte,
    required this.ringBreite,
    required this.farben,
    required this.textRichtung,
    this.schriftFaktor = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in plaetze) {
      _malePlatz(canvas, p);
    }
  }

  void _malePlatz(Canvas canvas, Fachplatz p) {
    final innen = p.ring * ringBreite;
    final aussen = (p.ring + 1) * ringBreite;

    final pfad = Path();
    if (p.ring == 0) {
      // Die Mitte ist kein Ring, sondern ein halber Kreis.
      pfad.addArc(Rect.fromCircle(center: mitte, radius: aussen),
          p.vonWinkel, p.oeffnung);
      pfad.close();
    } else {
      pfad.addArc(Rect.fromCircle(center: mitte, radius: aussen),
          p.vonWinkel, p.oeffnung);
      pfad.arcTo(Rect.fromCircle(center: mitte, radius: innen),
          p.vonWinkel + p.oeffnung, -p.oeffnung, false);
      pfad.close();
    }

    // Ein leerer Platz bleibt sichtbar, aber zurückhaltend: Die Lücke ist
    // eine Aussage („hier fehlt ein Elternteil"), soll aber nicht so
    // aussehen wie ein Eintrag.
    //
    // Nur über die Füllfarbe ging das nicht: Gegen die belegte Ringfläche
    // gemessen kam die leere auf 1,17:1 im hellen Modus – nebeneinander
    // schlicht nicht unterscheidbar. Deshalb bekommt ein leerer Platz
    // zusätzlich eine gestrichelte statt einer durchgezogenen Kante.
    canvas.drawPath(
      pfad,
      Paint()
        ..style = PaintingStyle.fill
        ..color = p.istLeer
            ? farben.surfaceContainerLowest
            : p.ring == 0
                ? farben.primaryContainer
                : farben.surfaceContainerHighest,
    );
    canvas.drawPath(
      p.istLeer ? _gestrichelt(pfad) : pfad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (p.ring == 0 ? 2 : 1) * schriftFaktor
        ..color = p.ring == 0
            ? farben.primary
            : p.istLeer
                ? farben.outline
                : farben.outlineVariant,
    );

    final person = p.personId == null ? null : personen[p.personId];
    if (person == null) return;
    _maleText(canvas, p, person, innen, aussen);
  }

  void _maleText(
      Canvas canvas, Fachplatz p, PersonData person, double innen, double aussen) {
    final spanne = lebensspanne(person.geburtsdatum, person.sterbedatum);
    // Nach außen wird der Platz enger; ab dem dritten Ring bleibt nur der
    // erste Namensteil, und das Lebensdatum entfällt ganz. Lieber ein
    // lesbarer Vorname als ein abgeschnittener voller Name.
    final knapp = p.ring >= 3;
    final name = knapp ? person.name.split(' ').first : person.name;

    final maler = TextPainter(
      text: TextSpan(children: [
        TextSpan(
          text: name,
          style: TextStyle(
            color: p.ring == 0 ? farben.onPrimaryContainer : farben.onSurface,
            fontSize: (p.ring == 0 ? 14 : (knapp ? 9.5 : 11)) * schriftFaktor,
            fontWeight: p.ring == 0 ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        if (spanne != null && !knapp)
          TextSpan(
            text: '\n$spanne',
            // onSurfaceVariant statt outline: Gegen die Ringfläche
            // gemessen kam outline auf 3,48:1 im hellen und 3,89:1 im
            // dunklen Modus – für 9 Punkt hohe Schrift zu wenig,
            // gefordert sind 4,5:1. „outline" ist als Linienfarbe
            // gedacht, nicht als Textfarbe.
            style: TextStyle(
                color: farben.onSurfaceVariant, fontSize: 9 * schriftFaktor),
          ),
      ]),
      textAlign: TextAlign.center,
      textDirection: textRichtung,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: p.ring == 0 ? ringBreite * 1.6 : (aussen - innen) - 8);

    canvas.save();
    if (p.ring == 0) {
      // In der Mitte waagerecht, knapp über dem Fußpunkt.
      canvas.translate(mitte.dx - maler.width / 2,
          mitte.dy - aussen / 2 - maler.height / 2);
    } else {
      // In den Ringen entlang des Radius. Auf der linken Hälfte wäre die
      // Schrift sonst auf dem Kopf – dort wird sie um 180 Grad gedreht
      // und vom äußeren Rand her gesetzt.
      final winkel = p.mittelWinkel;
      final linkeHaelfte = math.cos(winkel) < 0;
      canvas.translate(mitte.dx, mitte.dy);
      canvas.rotate(linkeHaelfte ? winkel + math.pi : winkel);
      final abstand = linkeHaelfte ? -aussen + 4 : innen + 4;
      canvas.translate(abstand, -maler.height / 2);
    }
    maler.paint(canvas, Offset.zero);
    canvas.restore();
    // Ein TextPainter hält seinen gesetzten Absatz im Speicher der
    // Grafikschicht, den der Dart-Sammler nicht mitzählt. Der Fächer legt
    // bis zu 31 Stück je Neuzeichnen an; ohne diese Zeile blieben sie
    // liegen, bis der Sammler zufällig vorbeikommt (gemessen: 26 MB je
    // 2000 Neuzeichnen, Prüfrunde 8).
    maler.dispose();
  }

  /// Macht aus einem Umriss eine gestrichelte Linie.
  ///
  /// Flutter kennt keine Strichmuster für Pfade; der Umriss wird deshalb
  /// über [PathMetric] abgelaufen und stückweise wieder zusammengesetzt.
  Path _gestrichelt(Path pfad, {double strich = 5, double luecke = 4}) {
    strich *= schriftFaktor;
    luecke *= schriftFaktor;
    final ergebnis = Path();
    for (final teil in pfad.computeMetrics()) {
      var pos = 0.0;
      while (pos < teil.length) {
        final bis = math.min(pos + strich, teil.length);
        ergebnis.addPath(teil.extractPath(pos, bis), Offset.zero);
        pos = bis + luecke;
      }
    }
    return ergebnis;
  }

  @override
  bool shouldRepaint(_FaecherMaler alt) =>
      alt.plaetze != plaetze ||
      alt.personen != personen ||
      alt.ringBreite != ringBreite ||
      alt.farben != farben ||
      alt.schriftFaktor != schriftFaktor;
}
