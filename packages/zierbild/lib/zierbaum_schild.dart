import 'package:flutter/material.dart';

import 'package:kern/services/zierbaum.dart';
import 'zierbaum_farben.dart';
import 'zierbaum_maler.dart' show Schildtext;

/// Ein Schild des Zierbaums: Porträt über einer goldenen Tafel mit Name,
/// Verwandtschaft und Lebensdaten.
///
/// Rechner und Telefon zeigen dasselbe Schild (#234); was sich
/// unterscheidet, reichen sie herein: das [portrait] (aus der Datei bzw.
/// vom Server) und, was in der [ecke] liegt – am Rechner der Menüknopf.
class Zierbaumschild extends StatelessWidget {
  final Schildtext text;
  final Widget portrait;
  final Zierbaumfarben farben;

  /// Dieselben Zahlen, aus denen die Tafel gemalt wird.
  ///
  /// Nicht noch einmal getippt: Zwei Sätze wären zwei Schilder, die
  /// auseinanderlaufen, sobald jemand nur eines davon anfasst.
  final Schildmasse masse;
  final bool istMitte;

  /// Ob über bzw. unter der Person noch etwas steht, das dieses Bild
  /// nicht zeigt.
  final bool weitereOben;
  final bool weitereUnten;

  /// Bei der Mitte ohne Wirkung – sie steht schon in der Mitte.
  final VoidCallback? onTap;
  final Widget? ecke;

  const Zierbaumschild({
    super.key,
    required this.text,
    required this.portrait,
    required this.farben,
    required this.istMitte,
    this.masse = const Schildmasse(),
    this.weitereOben = false,
    this.weitereUnten = false,
    this.onTap,
    this.ecke,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: istMitte ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Das Porträt sitzt ÜBER dem Schild und ragt darüber
              // hinaus, wie ein Bildnis über einer Tafel. Innerhalb des
              // Schildes bliebe für den Namen nichts übrig.
              portrait,
              SizedBox(height: masse.portraitAbstand),
              Expanded(child: _tafel()),
            ],
          ),
        ),
        // **Die Mehrzeichen liegen AUF der Tafel, nicht in ihr.** In der
        // Reihe standen sie als vierte und fünfte Zeile in einem Schild,
        // das für drei gebaut ist: 56,6 Punkte brauchen die Zeilen, 67
        // hat die Tafel – mit zwei Zeichen zu je dreizehn werden daraus
        // 82,6. Ein `Flexible` lässt Zeilen dann nicht überlappen, es
        // QUETSCHT sie, und der Text malt über seinen eigenen Rand
        // hinaus. Genau so lag im gemeldeten Bild „Sohn" halb über
        // „Martin".
        //
        // Als Marke am Rand sagen sie dasselbe und kosten keine Zeile.
        // Und sie liegen im SELBEN Stack wie die Ecke: Ein zweiter Stack
        // darunter machte den Sucher der Tests blind, der über dem Namen
        // den nächsten Stack sucht.
        if (weitereOben)
          Positioned(
            top: masse.portraitRadius * 2 + masse.portraitAbstand - 1,
            left: 0,
            right: 0,
            child: _mehr(),
          ),
        if (weitereUnten)
          Positioned(bottom: -1, left: 0, right: 0, child: _mehr()),
        if (ecke != null) Positioned(top: 0, right: 0, child: ecke!),
      ],
    );
  }

  Widget _tafel() => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
      horizontal: masse.polsterX,
      vertical: masse.polsterY,
    ),
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
            text.name,
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
        if (text.verwandtschaft != null)
          Flexible(
            child: Text(
              text.verwandtschaft!,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              // Kein Kursiv: Die kursive Fassung waere eine zweite Datei
              // von 754 kB, und ein kuenstlich geneigtes Garamond sieht
              // schlechter aus als ein aufrechtes. Unterschieden wird
              // ueber Groesse und Farbe.
              style: TextStyle(
                color: farben.nebenschrift,
                fontSize: masse.schriftNeben,
                fontFamily: zierschrift,
              ),
            ),
          ),
        if (text.lebensspanne != null)
          Flexible(
            child: Text(
              text.lebensspanne!,
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
  /// weitergeht, und zwei verschiedene Symbole wären zwei Dinge zu lernen
  /// für eine Aussage.
  Widget _mehr() => Icon(
    Icons.more_horiz,
    size: masse.zeichenGroesse,
    color: farben.schildRand,
  );
}
