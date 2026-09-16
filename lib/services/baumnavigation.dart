import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Matrix4, Offset, Rect, Size;

/// Wie weit sich der Zierbaum wegschieben lässt.
///
/// Ein Viertel ist die Stufe, auf der ein Baum mit angeheirateter
/// Verwandtschaft (gemessen: 3400 Punkte breit) auf einen gewöhnlichen
/// Fensterausschnitt passt. Weiter hinaus wären die Schilder nur noch
/// Streifen.
const double kleinsterBaumzoom = 0.25;

/// Und wie nah heran. Die Schilder sind für ihre Größe gezeichnet;
/// darüber sieht man vor allem die Kanten der Porträts.
const double groessterBaumzoom = 3.0;

/// Ein Druck auf einen der Zoomknöpfe.
///
/// Ein Viertel mehr je Druck: Zwei Drücke sind ungefähr das Anderthalb-
/// fache, sechs ungefähr das Vierfache – nah genug beieinander, dass man
/// nicht zählt, und weit genug, dass man etwas sieht.
const double baumZoomschritt = 1.25;

/// Der Zoomanteil einer Ansichtsmatrix.
///
/// Gemessen über alle drei Achsen, und deshalb wird auch die dritte
/// mitskaliert, obwohl der Baum flach ist: Bliebe z auf 1, meldete diese
/// Zeile beim Herauszoomen weiterhin 1 – die grössere der Achsen
/// gewinnt. Dieselbe Rechnung benutzt [InteractiveViewer] selbst, also
/// muss sie zu dessen Matrizen passen.
double baumzoomAus(Matrix4 blick) => blick.getMaxScaleOnAxis();

/// Die Ansicht nach einem Zoomschritt um [faktor], festgehalten am
/// Punkt [drehpunkt] im Fenster.
///
/// **Der Drehpunkt ist der Punkt.** Ohne ihn wächst der Baum aus seiner
/// linken oberen Ecke heraus, und wer in der Mitte etwas ansieht,
/// verliert es beim Hineinzoomen aus dem Bild. Die Rechnung ist die
/// übliche: an den Drehpunkt schieben, dort skalieren, zurückschieben –
/// und das Ganze vor die bisherige Ansicht.
///
/// Gibt dieselbe Ansicht zurück, wenn die Grenze schon erreicht ist;
/// dann bewegt sich nichts, statt dass sich der Baum unter der Hand
/// verschiebt.
Matrix4 baumGezoomt(Matrix4 blick, double faktor, Offset drehpunkt) {
  final alt = baumzoomAus(blick);
  final neu = (alt * faktor).clamp(kleinsterBaumzoom, groessterBaumzoom);
  if (neu == alt) return blick;
  final wirklich = neu / alt;
  final schritt = Matrix4.identity()
    ..translateByDouble(drehpunkt.dx, drehpunkt.dy, 0, 1)
    ..scaleByDouble(wirklich, wirklich, wirklich, 1)
    ..translateByDouble(-drehpunkt.dx, -drehpunkt.dy, 0, 1);
  return schritt.multiplied(blick);
}

/// Die Ansicht, in der [inhalt] ganz in [fenster] steht.
///
/// **Nie über 1 hinaus.** Ein kleiner Baum in einem grossen Fenster
/// würde sonst aufgeblasen, bis die Schrift franst – „einpassen" heisst
/// „ganz zeigen", nicht „ausfüllen".
Matrix4 baumEingepasst(Size inhalt, Size fenster) {
  if (inhalt.width <= 0 || inhalt.height <= 0) return Matrix4.identity();
  final faktor = math
      .min(fenster.width / inhalt.width, fenster.height / inhalt.height)
      .clamp(kleinsterBaumzoom, 1.0);
  final dx = (fenster.width - inhalt.width * faktor) / 2;
  final dy = (fenster.height - inhalt.height * faktor) / 2;
  return Matrix4.identity()
    ..translateByDouble(dx, dy, 0, 1)
    ..scaleByDouble(faktor, faktor, faktor, 1);
}

/// Die Ansicht, die [stelle] (im Baum gemessen) in die Mitte von
/// [fenster] rückt, bei unverändertem Zoom.
///
/// Gebraucht beim Umsetzen der Mitte: Wer ein Schild antippt, rückt eine
/// andere Person in den Mittelpunkt – und deren Schild soll dann auch im
/// Bild stehen und nicht dort, wo zufällig gerade der Ausschnitt lag.
Matrix4 baumZentriert(Offset stelle, Size fenster, double zoom) {
  return Matrix4.identity()
    ..translateByDouble(fenster.width / 2 - stelle.dx * zoom,
        fenster.height / 2 - stelle.dy * zoom, 0, 1)
    ..scaleByDouble(zoom, zoom, zoom, 1);
}

/// Wo im Fenster ein Punkt des Baumes landet.
///
/// Der Umkehrweg zu den drei Rechnungen oben – gebraucht, um zu prüfen,
/// ob ein Schild überhaupt zu sehen ist.
Offset baumImFenster(Matrix4 blick, Offset stelle) {
  final v = blick.applyToVector3Array([stelle.dx, stelle.dy, 0]);
  return Offset(v[0], v[1]);
}

/// Der Ausschnitt, mit dem der Baum aufgeschlagen wird.
///
/// **Zwei Wünsche, die sich widersprechen.** Der ganze Baum soll zu sehen
/// sein – dazu gehört der Familienname unten am Stamm, der zum Bild
/// gehört. Und die Person, um die es geht, muss zu sehen sein: Vorher
/// begann der Ausschnitt am linken oberen Eck, also bei irgendeinem
/// Urgrossvater, und man musste die Mitte erst suchen.
///
/// Deshalb in dieser Reihenfolge: erst den ganzen Baum einmitten, und
/// nur wenn das Schild der Mitte dabei aus dem Bild fällt, auf dieses
/// Schild rücken. Nicht eingepasst – ein breiter Baum passt erst bei
/// einem Drittel seiner Grösse ins Fenster, und dort ist keine
/// Beschriftung mehr zu lesen. „Ganz zeigen" ist ein Knopf.
Matrix4 baumErsterBlick({
  required Size baum,
  required Size fenster,
  required Rect fokusSchild,
}) {
  final ganz =
      baumZentriert(Offset(baum.width / 2, baum.height / 2), fenster, 1.0);
  final ecke = baumImFenster(ganz, fokusSchild.topLeft);
  final gegenueber = baumImFenster(ganz, fokusSchild.bottomRight);
  final drin = ecke.dx >= 0 &&
      ecke.dy >= 0 &&
      gegenueber.dx <= fenster.width &&
      gegenueber.dy <= fenster.height;
  if (drin) return ganz;
  return baumZentriert(fokusSchild.center, fenster, 1.0);
}
