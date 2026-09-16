import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/zierbaum.dart';
import '../theme/zierbaum_farben.dart';
import 'profilbild.dart';
import 'zierbaum_maler.dart';

/// Was auf einem Schild steht.
@immutable
class Schildinhalt {
  final String name;

  /// Wie diese Person zur Mitte steht – bei der Mitte selbst `null`.
  final String? verwandtschaft;

  /// Der Gesichtsausschnitt, falls es einen gibt.
  final File? bild;

  /// „1874–1955", „*1972" – oder `null`, wenn nichts bekannt ist.
  ///
  /// Steht auf dem Schild, weil sie auf der alten Karte stand: Ein
  /// Stammbaum ohne Jahreszahlen beantwortet die halben Fragen nicht,
  /// die man an ihn stellt. Sie beim Umbau stillschweigend wegzulassen
  /// wäre ein Verlust gewesen, den niemand bestellt hat.
  final String? lebensspanne;

  /// Ob über bzw. unter der Person noch etwas steht, das dieses Bild
  /// nicht zeigt.
  final bool weitereOben;
  final bool weitereUnten;

  const Schildinhalt({
    required this.name,
    this.verwandtschaft,
    this.bild,
    this.lebensspanne,
    this.weitereOben = false,
    this.weitereUnten = false,
  });
}

/// Der Zierbaum: gemalter Grund, echte Schilder darüber.
///
/// **Die Aufteilung ist der Kern.** Grund, Stamm, Äste und Ranken malt
/// [ZierbaumMaler]; die Schilder liegen als gewöhnliche Widgets in einem
/// [Stack] darüber. Damit bleiben Antippen, Rechtsklick-Menü,
/// Kurzhinweis, Tastaturfokus und Sprachausgabe erhalten, ohne dass
/// irgendetwas davon nachgebaut werden müsste – und das Profilbild ist
/// dasselbe Widget wie überall sonst.
class ZierbaumAnsicht extends StatelessWidget {
  final Zierbaumplan plan;
  final Zierbaumfarben farben;

  /// Was auf dem Schild dieser Person steht.
  final Schildinhalt Function(String personId) inhalt;

  /// Die Person in der Mitte – ihr Schild hebt sich ab.
  final String fokusId;

  final void Function(String personId) beiTipp;
  final void Function(String personId, Offset stelle) beiMenue;

  /// Steht unten am Stamm. `null`, wenn sich kein gemeinsamer Name
  /// findet – dann bleibt die Zeile weg, statt etwas zu behaupten.
  final String? familienname;

  /// Der Kurzhinweis am Menüknopf jedes Schildes.
  final String menueHinweis;

  /// Wie gross das Bild mindestens wird.
  ///
  /// Ein unbeschränkter Bereich gibt seinem Kind unbegrenzten Platz; ohne
  /// diese Untergrenze wäre der gemalte Grund nur so gross wie der Baum,
  /// und daneben stünde die gewöhnliche Hintergrundfarbe – ein Bild mit
  /// einer Kante mitten im Fenster. Wer den Grund mit [Zierbaumgrund]
  /// selbst dahinterlegt, braucht das nicht und lässt es bei null.
  final Size mindestens;

  /// Ob der Grund mitgemalt wird.
  ///
  /// Aus, sobald der Baum sich verschieben lässt: Dann steht der Grund
  /// dahinter still, statt mit ihm aus dem Bild zu wandern.
  final bool malGrund;

  /// Die Masszahlen des Schildes.
  ///
  /// Übergeben und nicht fest: Wer die Systemschrift grösser stellt,
  /// bekommt grössere Schilder – und keine, in denen der Text über den
  /// Rand malt. Der [Zierbaumplan] muss mit **demselben** Faktor
  /// gerechnet sein, sonst stehen die Schilder neben ihren Ästen.
  final Schildmasse schildmasse;

  const ZierbaumAnsicht({
    super.key,
    required this.plan,
    required this.farben,
    required this.inhalt,
    required this.fokusId,
    required this.beiTipp,
    required this.beiMenue,
    required this.menueHinweis,
    this.familienname,
    this.mindestens = Size.zero,
    this.malGrund = true,
    this.schildmasse = const Schildmasse(),
  });

  @override
  Widget build(BuildContext context) {
    final breite = math.max(plan.breite, mindestens.width);
    final hoehe = math.max(plan.hoehe, mindestens.height);
    // Der Baum steht mittig, wenn Platz übrig ist.
    final versatzX = (breite - plan.breite) / 2;
    return SizedBox(
      width: breite,
      height: hoehe,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: ZierbaumMaler(
                plan: plan,
                farben: farben,
                versatzX: versatzX,
                malGrund: malGrund,
                schildmasse: schildmasse,
                // Damit der Stamm an der Person in der Mitte ansetzt und
                // nicht am tiefsten Schild.
                fokusId: fokusId,
              ),
            ),
          ),
          if (familienname != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Text(
                familienname!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: farben.familienname,
                  fontSize: 46 * schildmasse.schriftName / 14,
                  letterSpacing: 2,
                  fontFamily: zierschriftGross,
                ),
              ),
            ),
          for (final schild in plan.schilder)
            Positioned(
              left: schild.links + versatzX,
              top: schild.oben,
              width: schild.breite,
              height: schild.hoehe,
              child: _Schild(
                inhalt: inhalt(schild.personId),
                farben: farben,
                masse: schildmasse,
                istMitte: schild.personId == fokusId,
                onTap: () => beiTipp(schild.personId),
                onMenue: (stelle) => beiMenue(schild.personId, stelle),
                menueHinweis: menueHinweis,
              ),
            ),
        ],
      ),
    );
  }
}

/// Ein einzelnes Schild: Porträt, Name, Verwandtschaft.
class _Schild extends StatelessWidget {
  final Schildinhalt inhalt;
  final Zierbaumfarben farben;
  final bool istMitte;
  final VoidCallback onTap;
  final void Function(Offset stelle) onMenue;

  /// Der Kurzhinweis am Menüknopf.
  final String menueHinweis;

  /// Dieselben Zahlen, aus denen die Tafel gemalt wird.
  ///
  /// Nicht noch einmal getippt: Zwei Sätze wären zwei Schilder, die
  /// auseinanderlaufen, sobald jemand nur eines davon anfasst.
  final Schildmasse masse;

  const _Schild({
    required this.inhalt,
    required this.farben,
    required this.masse,
    required this.istMitte,
    required this.onTap,
    required this.onMenue,
    required this.menueHinweis,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: [
        inhalt.name,
        if (inhalt.verwandtschaft != null) inhalt.verwandtschaft!,
        if (inhalt.lebensspanne != null) inhalt.lebensspanne!,
      ].join(', '),
      child: GestureDetector(
        onSecondaryTapDown: (d) => onMenue(d.globalPosition),
        onLongPressStart: (d) => onMenue(d.globalPosition),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              onTap: istMitte ? null : onTap,
              borderRadius: BorderRadius.circular(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Das Porträt sitzt ÜBER dem Schild und ragt darüber
                  // hinaus, wie ein Bildnis über einer Tafel. Innerhalb
                  // des Schildes bliebe für den Namen nichts übrig.
                  Profilbild(
                    datei: inhalt.bild,
                    radius: masse.portraitRadius,
                    hintergrund: farben.schildUnten,
                    symbolgroesse: masse.portraitRadius + 1,
                    symbolfarbe: farben.schildRand,
                  ),
                  SizedBox(height: masse.portraitAbstand),
                  Expanded(child: _tafel(context)),
                ],
              ),
            ),
            // **Die Mehrzeichen liegen AUF der Tafel, nicht in ihr.**
            // In der Reihe standen sie als vierte und fünfte Zeile in
            // einem Schild, das für drei gebaut ist: 56,6 Punkte
            // brauchen die Zeilen, 67 hat die Tafel – mit zwei Zeichen
            // zu je dreizehn werden daraus 82,6. Ein `Flexible` lässt
            // Zeilen dann nicht überlappen, es QUETSCHT sie, und der
            // Text malt über seinen eigenen Rand hinaus. Genau so lag im
            // gemeldeten Bild „Sohn" halb über „Martin".
            //
            // Als Marke am Rand sagen sie dasselbe und kosten keine
            // Zeile. Und sie liegen im SELBEN Stack wie der Menüknopf:
            // Ein zweiter Stack darunter machte den Sucher der Tests
            // blind, der über dem Namen den nächsten Stack sucht.
            if (inhalt.weitereOben)
              Positioned(
                  top: masse.portraitRadius * 2 + masse.portraitAbstand - 1,
                  left: 0,
                  right: 0,
                  child: _mehr()),
            if (inhalt.weitereUnten)
              Positioned(bottom: -1, left: 0, right: 0, child: _mehr()),
            // **Ein sichtbarer Weg ins Menü.** Rechtsklick und langes
            // Drücken tun dasselbe, aber beide muss man kennen. Auf der
            // alten Karte stand dieser Knopf, und ihn beim Umbau
            // wegzulassen hiesse, eine Tür zuzumauern – derselbe Fehler
            // wie beim Papierkorb, der eine Prüfrunde lang keinen
            // Eingang hatte.
            Positioned(
              top: 0,
              right: 0,
              child: Builder(
                builder: (knopfKontext) => IconButton(
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(2),
                  constraints: const BoxConstraints(),
                  tooltip: menueHinweis,
                  color: farben.schildRand,
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {
                    final kasten =
                        knopfKontext.findRenderObject() as RenderBox;
                    onMenue(kasten
                        .localToGlobal(kasten.size.bottomLeft(Offset.zero)));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tafel(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
            horizontal: masse.polsterX, vertical: masse.polsterY),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [farben.schildOben, farben.schildUnten],
          ),
          borderRadius: BorderRadius.circular(masse.rundung),
          border: Border.all(
            color: istMitte ? farben.mitteRand : farben.schildRand,
            width: istMitte ? masse.randStark : masse.randSchwach,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                inhalt.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: farben.schrift,
                  fontSize: masse.schriftName,
                  height: 1.1,
                  fontFamily: zierschrift,
                  fontVariations: zierGewicht(istMitte ? 700 : 600),
                ),
              ),
            ),
            if (inhalt.verwandtschaft != null)
              Flexible(
                child: Text(
                  inhalt.verwandtschaft!,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  // Kein Kursiv: Die kursive Fassung waere eine zweite
                  // Datei von 754 kB, und ein kuenstlich geneigtes
                  // Garamond sieht schlechter aus als ein aufrechtes.
                  // Unterschieden wird ueber Groesse und Farbe.
                  style: TextStyle(
                    color: farben.nebenschrift,
                    fontSize: masse.schriftNeben,
                    fontFamily: zierschrift,
                  ),
                ),
              ),
            if (inhalt.lebensspanne != null)
              Flexible(
                child: Text(
                  inhalt.lebensspanne!,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: farben.nebenschrift,
                    fontSize: masse.schriftNeben,
                    fontFamily: zierschrift,
                  ),
                ),
              ),
          ],
        ),
      );

  /// Das Zeichen „hier geht es weiter, aber nicht in diesem Bild".
  ///
  /// Oben und unten dasselbe Zeichen: Die Richtung sagt schon, wohin es
  /// weitergeht, und zwei verschiedene Symbole wären zwei Dinge zu
  /// lernen für eine Aussage.
  Widget _mehr() => Icon(
        Icons.more_horiz,
        size: masse.zeichenGroesse,
        color: farben.schildRand,
      );
}
