import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kern/services/zierbaum.dart';
import '../theme/zierbaum_farben.dart';
import 'profilbild.dart';
import 'package:zierbild/zierbaum_schild.dart';
import 'zierbaum_maler.dart';

/// Was auf einem Schild steht – dazu, was nur der Rechner kennt: den
/// Gesichtsausschnitt als Datei und die Mehrzeichen.
@immutable
class Schildinhalt extends Schildtext {
  /// Der Gesichtsausschnitt, falls es einen gibt.
  final File? bild;

  /// Ob über bzw. unter der Person noch etwas steht, das dieses Bild
  /// nicht zeigt.
  final bool weitereOben;
  final bool weitereUnten;

  const Schildinhalt({
    required super.name,
    super.verwandtschaft,
    this.bild,
    super.lebensspanne,
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
        child: Zierbaumschild(
          text: inhalt,
          farben: farben,
          masse: masse,
          istMitte: istMitte,
          weitereOben: inhalt.weitereOben,
          weitereUnten: inhalt.weitereUnten,
          onTap: onTap,
          portrait: Profilbild(
            datei: inhalt.bild,
            radius: masse.portraitRadius,
            hintergrund: farben.schildUnten,
            symbolgroesse: masse.portraitRadius + 1,
            symbolfarbe: farben.schildRand,
          ),
          // **Ein sichtbarer Weg ins Menü.** Rechtsklick und langes
          // Drücken tun dasselbe, aber beide muss man kennen. Auf der
          // alten Karte stand dieser Knopf, und ihn beim Umbau
          // wegzulassen hiesse, eine Tür zuzumauern – derselbe Fehler
          // wie beim Papierkorb, der eine Prüfrunde lang keinen
          // Eingang hatte.
          ecke: Builder(
            builder: (knopfKontext) => IconButton(
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(2),
              constraints: const BoxConstraints(),
              tooltip: menueHinweis,
              color: farben.schildRand,
              icon: const Icon(Icons.more_vert),
              onPressed: () {
                final kasten = knopfKontext.findRenderObject() as RenderBox;
                onMenue(
                  kasten.localToGlobal(kasten.size.bottomLeft(Offset.zero)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
