import 'package:flutter/material.dart';

import '../services/textstellen.dart';
import '../theme/app_spacing.dart';
import 'tippfaenger.dart';

/// Ein Kasten um eine gelesene Textstelle im Foto.
///
/// Das Gegenstück zu [Gesichtsrahmen], und aus demselben Grund entstanden:
/// Die Texterkennung fand seit jeher, wo die Schrift steht, und behielt davon
/// nur die Buchstaben. Wer ein Schild fotografiert hat und die Nummer darauf
/// braucht, sah bisher dieselbe Nummer wie vorher – als Bildpunkte.
///
/// Antippen legt genau diese Zeile in die Zwischenablage. Der ganze Text
/// steht daneben in der Info-Ansicht; hier geht es um die eine Zeile, auf die
/// man zeigt.
///
/// Der Rahmen ist ein [Positioned] und gehört damit unmittelbar in einen
/// [Stack], dessen Fläche genau das Foto ist – sonst läge ein Anteil von 0,3
/// auf drei Zehnteln des Fensters statt des Bildes.
class Textrahmen extends StatelessWidget {
  final Textstelle stelle;

  /// Die Fläche, auf der das Foto liegt.
  final Size flaeche;

  /// Wird mit dem Text dieser Stelle aufgerufen.
  final void Function(String text)? beiTipp;

  const Textrahmen({
    super.key,
    required this.stelle,
    required this.flaeche,
    this.beiTipp,
  });

  /// Blau – abgesetzt von Grün/Orange/Grau der Gesichtsrahmen, damit beide
  /// Überlagerungen gleichzeitig eingeschaltet unterscheidbar bleiben.
  static const Color farbe = Color(0xFF4FC3F7);

  @override
  Widget build(BuildContext context) {
    // Ein Kasten sitzt eng um die Schrift. Ein Rahmen genau auf der Kante
    // verdeckt die oberste und unterste Pixelreihe der Buchstaben, und das
    // ist ausgerechnet dort, wo Umlautpunkte und Unterlängen sitzen.
    const luft = 2.0;
    return Positioned(
      left: stelle.links * flaeche.width - luft,
      top: stelle.oben * flaeche.height - luft,
      width: stelle.breite * flaeche.width + luft * 2,
      height: stelle.hoehe * flaeche.height + luft * 2,
      child: Tippfaenger(
        beiTipp: beiTipp == null ? null : () => beiTipp!(stelle.text),
        beiMenue: null,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: farbe, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            color: farbe.withValues(alpha: 0.12),
          ),
        ),
      ),
    );
  }
}
