import 'dart:io';

import 'package:flutter/material.dart';

import '../services/bilddekodierung.dart';

/// Das runde Bild einer Person – ihr Gesichts-Ausschnitt, oder ein Symbol,
/// solange keiner gewählt ist.
///
/// **Warum als eigenes Widget.** Derselbe `CircleAvatar` mit demselben
/// `FileImage` und demselben Ersatzsymbol stand in **neun** Dateien:
/// Stammbaum (dreimal), Personen, Person, Erkunden, Personenauswahl,
/// Info-Blatt und Suchoptionen. Neun Abschriften heisst neun Stellen, an
/// denen eine Änderung vergessen werden kann – und genau das war der
/// Fall: Keine einzige begrenzte, wie gross sie das Bild dekodiert.
///
/// Ein Ausschnitt misst heute 160 × 160 Punkte, ein Bild davon belegt
/// also 102 kB. Das ist wenig – aber die Personenliste zeigt hunderte
/// nebeneinander, und vor allem hält nichts diese 160 fest. Wüchse die
/// Ausschnittgrösse je, dekodierten neun Bildschirme still das Volle.
class Profilbild extends StatelessWidget {
  const Profilbild({
    super.key,
    required this.datei,
    required this.radius,
    this.hintergrund,
    this.symbolgroesse,
    this.symbolfarbe,
  });

  /// Der Gesichts-Ausschnitt, oder `null` – dann steht das Symbol da.
  final File? datei;

  final double radius;
  final Color? hintergrund;

  /// Vorgabe ist ein Symbol, das etwa vier Fünftel des Kreises füllt.
  /// Material-Glyphen füllen ihren Kasten nicht ganz aus, deshalb nicht
  /// der volle Durchmesser.
  final double? symbolgroesse;

  final Color? symbolfarbe;

  @override
  Widget build(BuildContext context) {
    final bild = datei;
    return CircleAvatar(
      radius: radius,
      backgroundColor: hintergrund,
      backgroundImage: bild == null
          ? null
          : begrenztesBild(
              bild,
              // Der Kreis ist so breit wie zwei Radien; mehr Bildpunkte
              // als der Bildschirm hat, zeigt niemand.
              kante: (radius * 2 * MediaQuery.devicePixelRatioOf(context))
                  .round(),
            ),
      child: bild == null
          ? Icon(
              Icons.person_outline,
              size: symbolgroesse ?? radius * 0.8,
              color: symbolfarbe,
            )
          : null,
    );
  }
}
