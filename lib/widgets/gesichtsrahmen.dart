import 'package:flutter/material.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'tippfaenger.dart';

/// Ein Kasten um ein erkanntes Gesicht, mit dem Namen darunter.
///
/// **Warum das ein eigenes Widget ist.** Es gab die Rahmen bisher genau
/// einmal – in der Gesichts-Bearbeitung, die man über das Rechtsklick-Menü
/// der Vollbildansicht erreicht. Wer ein Foto ansieht und wissen will, wer
/// darauf ist, findet dort nichts: Die Info-Ansicht zählt die benannten
/// Personen als Reihe von Köpfen auf, sagt aber nicht, welcher Kopf im
/// Bild welcher ist, und die unbenannten verschweigt sie ganz.
///
/// Beide Stellen zeichnen deshalb jetzt denselben Rahmen. Zwei Fassungen
/// wären zwei Farbschlüssel, und ein Grün, das an einer Stelle „benannt"
/// und an der anderen etwas anderes hiesse, ist schlimmer als gar keine
/// Farbe.
///
/// Der Rahmen ist ein [Positioned] und gehört damit unmittelbar in einen
/// [Stack], dessen Fläche genau das Foto ist.
class Gesichtsrahmen extends StatelessWidget {
  final FaceData gesicht;

  /// Der Name der zugeordneten Person – `null` heisst unbenannt.
  final String? personName;

  /// Die Fläche, auf der das Foto liegt. Die Kästen stehen in der
  /// Datenbank als Anteile davon (0..1), nicht in Punkten: Dasselbe
  /// Gesicht muss in der Vorschau und im Vollbild an derselben Stelle
  /// sitzen.
  final Size flaeche;

  final VoidCallback? beiTipp;
  final void Function(Offset stelle)? beiMenue;

  /// Wie viele Bildschirmpunkte ein Punkt von [flaeche] gerade misst.
  ///
  /// **Warum das gebraucht wird** (Issue #16). In der Vollansicht ist
  /// [flaeche] das Foto in seinen eigenen Bildpunkten, und PhotoView
  /// verkleinert es aufs Fenster – ein Foto von 6000 Punkten Breite auf
  /// rund ein Achtel. Schrift und Rand, in Bildpunkten bemessen, schrumpften
  /// mit: Ein Name war auf dem Schirm 3,5 Punkte hoch. Mit dem Massstab
  /// werden sie in Schirmpunkten bemessen und zurückgerechnet. Dort, wo die
  /// Fläche schon der Schirm ist, bleibt es bei 1.
  final double massstab;

  const Gesichtsrahmen({
    super.key,
    required this.gesicht,
    required this.personName,
    required this.flaeche,
    this.beiTipp,
    this.beiMenue,
    this.massstab = 1,
  });

  /// Wie weit der Finger zwischen Aufsetzen und Abheben wandern darf,
  /// damit es noch als Tipp gilt. Liegt seit dem Textrahmen bei
  /// [Tippfaenger], der sie auswertet.
  static const double tippWackeln = Tippfaenger.wackeln;

  /// Grün benannt, Orange unbenannt, Grau beiseitegelegt.
  static Color farbeFuer(FaceData gesicht) => gesicht.isIgnored
      ? DunkleFlaeche.inaktiv
      : gesicht.personId != null
      ? Colors.greenAccent
      : Colors.orangeAccent;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final beschriftung = gesicht.isIgnored
        ? t.gesichtIgnoriert
        : personName ?? t.gesichtUnbenannt;
    return Positioned(
      left: gesicht.boxX * flaeche.width,
      top: gesicht.boxY * flaeche.height,
      width: gesicht.boxW * flaeche.width,
      height: gesicht.boxH * flaeche.height,
      child: Tippfaenger(
        beiTipp: beiTipp,
        // Der Rahmen liegt über der Fläche und fängt den Klick zuerst
        // ab – ohne diese Zeile bekäme man auf einem Gesicht das Menü
        // der freien Fläche.
        beiMenue: beiMenue,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final m = massstab > 0 ? massstab : 1.0;
            // In Schirmpunkten: mit dem Gesicht wachsend, aber nie unter
            // 13 – sonst ist ein Gesicht in einer Gruppe nicht zu lesen.
            final schirm = constraints.biggest.shortestSide * m;
            final schrift = (schirm * 0.16).clamp(13.0, 18.0) / m;
            return Semantics(
              label: beschriftung,
              button: beiTipp != null,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: farbeFuer(gesicht), width: 2 / m),
                ),
                alignment: Alignment.bottomLeft,
                // Der Name darf breiter sein als das Gesicht: In einer
                // Gruppe ist ein Gesicht schmaler als „Anna“, und ein auf
                // „A…“ gekürzter Name sagt nichts.
                child: OverflowBox(
                  alignment: Alignment.bottomLeft,
                  minWidth: 0,
                  maxWidth: (constraints.maxWidth > 240 / m
                      ? constraints.maxWidth
                      : 240 / m),
                  child: Container(
                    color: Colors.black87,
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs / m,
                      vertical: 2 / m,
                    ),
                    child: Text(
                      beschriftung,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: gesicht.isIgnored
                            ? DunkleFlaeche.zweitText
                            : DunkleFlaeche.text,
                        fontSize: schrift,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
