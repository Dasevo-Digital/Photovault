/// **Schilder im Gelände – Gipfel, Hütten, Quellen.**
///
/// Die Beschriftung einer Kachel liegt flach auf dem Boden und kippt mit
/// ihm weg; in einer Schräglage von zwanzig Grad ist sie nicht mehr zu
/// lesen. Was einen Namen verdient, steht deshalb aufrecht darüber.
///
/// **Drei Dinge, ohne die Schilder mehr schaden als nützen:**
///
/// 1. **Sie dürfen nicht durch Berge scheinen.** `drawVertices` kennt
///    keinen Tiefenpuffer, also weiss niemand, ob zwischen Kamera und
///    Gipfel noch ein Grat steht. Ohne Sichtprüfung schwebt der Name des
///    hintersten Berges vor dem vordersten – am Bild sofort zu sehen und
///    sofort falsch.
/// 2. **Sie dürfen sich nicht überdecken.** Das Ilsetal hat 41 Punkte
///    auf 2,8 × 3,3 km; in der Ferne fallen sie in einem Bildpunkt
///    zusammen. Wer näher steht, gewinnt.
/// 3. **Sie dürfen nicht alle gleich wichtig aussehen.** 27 der 41
///    Punkte sind Wegweiser, die meisten ohne Namen. Ein Gipfel bekommt
///    seinen Namen und seine Höhe, ein namenloser Wegweiser nur ein
///    Zeichen.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/gelaendesicht.dart';
import '../services/lichtstimmung.dart';
import '../services/wanderobjekte.dart';

/// Ein Schild, fertig zum Zeichnen.
///
/// Der Absatz entsteht **einmal** und nicht in jedem Bild: Text zu
/// setzen ist der teuerste Einzelposten einer Beschriftung, und der Text
/// ändert sich nie.
class Gelaendeschild {
  Gelaendeschild({
    required this.ort,
    required this.art,
    this.beschriftung,
  });

  /// Wo es steht – in denselben Metern wie das Netz.
  final Raumpunkt ort;
  final Wanderart art;

  /// Was daraufsteht. `null` heisst: nur das Zeichen, kein Text – so wie
  /// bei den namenlosen Wegweisern.
  final String? beschriftung;

  ui.Paragraph? _absatz;

  ui.Paragraph? absatz(double schriftgroesse, [String? schriftart]) {
    final text = beschriftung;
    if (text == null) return null;
    if (_absatz != null) return _absatz;
    final bauer = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: schriftart,
      fontSize: schriftgroesse,
      fontWeight: FontWeight.w600,
      maxLines: 1,
      textAlign: TextAlign.left,
    ))
      ..pushStyle(ui.TextStyle(color: const Color(0xFF1B1B1B)))
      ..addText(text);
    return _absatz = bauer.build()
      ..layout(const ui.ParagraphConstraints(width: 400));
  }
}

/// Wie hoch über dem Boden das Zeichen sitzt, in Metern der Landschaft.
///
/// **Zwölf Meter, und sie sind überhöht wie alles andere.** Genau auf
/// dem Boden verschwände das Zeichen halb darin, weil das Gitter
/// zwischen den Stützpunkten gerade verläuft und ein Gipfel gewölbt ist –
/// dasselbe Problem, das die Spur mit ihren zwei Metern Zugabe löst. Und
/// die Sichtprüfung gäbe reihenweise falsche Antworten: Ein Punkt genau
/// auf der Oberfläche ist von einer flachen Kamera aus immer verdeckt.
const double schildHoeheMeter = 12;

/// Wie viele Schilder höchstens beschriftet werden.
///
/// Zwölf. Darüber ist das Bild eine Wand aus Kästchen; die Landschaft
/// ist dann nicht mehr zu sehen, und genau die war der Zweck.
const int hoechstensBeschriftet = 12;

/// Ob die Sichtlinie von [von] nach [nach] frei ist.
///
/// **Ohne Tiefenpuffer bleibt nur Nachmessen.** Die Höhen entlang der
/// Sichtlinie werden abgetastet; liegt eine davon über der Linie, steht
/// dort ein Berg im Weg.
///
/// [proben] Stützstellen. Zwanzig sind bei einer Landschaft von vier
/// Kilometern alle zweihundert Meter – feiner, als das Höhengitter
/// aufgelöst ist (dort sind es rund dreissig Meter, aber ein Grat, der
/// schmaler ist als zweihundert Meter, verdeckt auch nicht viel).
///
/// [toleranz] verzeiht der Sichtlinie ein paar Meter. Ohne sie meldete
/// jede Kuppe zwischen zwei Stützstellen eine Verdeckung, die im Bild
/// keine ist.
bool sichtfrei(
  Raumpunkt von,
  Raumpunkt nach,
  double? Function(double x, double y) hoeheBei, {
  int proben = 20,
  double toleranz = 8,
}) {
  for (var i = 1; i < proben; i++) {
    final t = i / proben;
    final x = von.x + (nach.x - von.x) * t;
    final y = von.y + (nach.y - von.y) * t;
    final z = von.z + (nach.z - von.z) * t;
    final boden = hoeheBei(x, y);
    if (boden == null) continue;
    if (boden > z + toleranz) return false;
  }
  return true;
}

/// Zeichnet die Schilder über die fertige Landschaft und liefert, wie
/// viele davon **beschriftet** wurden.
///
/// Gezeichnet wird **nach** dem Gelände und nach dem Dunst: Ein Schild
/// gehört nicht in die Landschaft, sondern davor.
///
/// **Warum die Zahl zurückkommt.** Ob die Deckelung und der
/// Überdeckungsschutz greifen, lässt sich an der gemalten Farbe nicht
/// ablesen – vierzig Kästchen übereinander verbrauchen kaum mehr Farbe
/// als eines, weil sie einander verdecken. Die erste Fassung dieses
/// Tests ging mit ausgebauter Deckelung durch. Gezählt wird deshalb, was
/// wirklich entstanden ist.
int zeichneSchilder(
  ui.Canvas leinwand,
  ui.Size flaeche,
  Gelaendekamera kamera,
  List<Gelaendeschild> schilder, {
  double? Function(double x, double y)? hoeheBei,
  Lichtstimmung stimmung = stimmungMittag,
  double schriftgroesse = 12,
  String? schriftart,
}) {
  if (schilder.isEmpty || flaeche.isEmpty) return 0;
  final wo = kamera.standort;

  // Erst sammeln, dann zeichnen: Die Reihenfolge entscheidet, wer bei
  // Überdeckung gewinnt, und das lässt sich erst sagen, wenn alle
  // Tiefen bekannt sind.
  final sichtbar = <({Gelaendeschild schild, Offset stelle, double tiefe})>[];
  for (final s in schilder) {
    final b = kamera.projiziere(s.ort);
    if (b.tiefe <= 1) continue;
    if (b.stelle.dx < -200 ||
        b.stelle.dx > flaeche.width + 200 ||
        b.stelle.dy < -100 ||
        b.stelle.dy > flaeche.height + 100) {
      continue;
    }
    if (hoeheBei != null && !sichtfrei(wo, s.ort, hoeheBei)) continue;
    sichtbar.add((schild: s, stelle: b.stelle, tiefe: b.tiefe));
  }
  if (sichtbar.isEmpty) return 0;
  sichtbar.sort((a, b) => a.tiefe.compareTo(b.tiefe));

  // Die Skala für das Verblassen in der Ferne – dieselbe Idee wie beim
  // Dunst: Was weit weg ist, tritt zurück.
  final nahste = sichtbar.first.tiefe;
  final fernste = sichtbar.last.tiefe;
  final spanne = math.max(1.0, fernste - nahste);

  final belegt = <Rect>[];
  var beschriftet = 0;

  for (final e in sichtbar) {
    final t = ((e.tiefe - nahste) / spanne).clamp(0.0, 1.0);
    final deckkraft = (1 - 0.55 * t).clamp(0.3, 1.0);
    final zeichen = _zeichenfarbe(e.schild.art);

    final absatz = beschriftet < hoechstensBeschriftet
        ? e.schild.absatz(schriftgroesse, schriftart)
        : null;
    Rect? kasten;
    if (absatz != null) {
      const rand = 5.0;
      final breite = absatz.maxIntrinsicWidth + 2 * rand;
      final hoehe = absatz.height + 2 * rand;
      kasten = Rect.fromLTWH(
          e.stelle.dx + 10, e.stelle.dy - hoehe - 8, breite, hoehe);
      // Wer näher steht, gewinnt: Ein Kästchen, das ein schon
      // gezeichnetes überdeckt, fällt weg. Ohne das ist die Ferne eine
      // Wand aus Kästchen.
      if (belegt.any((r) => r.overlaps(kasten!.inflate(2)))) kasten = null;
    }

    _zeichenMalen(leinwand, e.stelle, e.schild.art, zeichen, deckkraft);

    if (kasten == null || absatz == null) continue;
    belegt.add(kasten);
    beschriftet++;

    // Ein heller Grund unter der Schrift. Über einem Luftbild ist jede
    // Schriftfarbe irgendwo unlesbar – Weiss auf Fels, Schwarz im Wald.
    leinwand.drawRRect(
      RRect.fromRectAndRadius(kasten, const Radius.circular(4)),
      ui.Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.86 * deckkraft),
    );
    leinwand.drawRRect(
      RRect.fromRectAndRadius(kasten, const Radius.circular(4)),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = zeichen.withValues(alpha: 0.85 * deckkraft),
    );
    // Ein Strich vom Kästchen zum Zeichen, damit klar ist, wozu der Name
    // gehört – bei mehreren Gipfeln nebeneinander sonst nicht.
    leinwand.drawLine(
      e.stelle,
      Offset(kasten.left, kasten.bottom),
      ui.Paint()
        ..strokeWidth = 1
        ..color = zeichen.withValues(alpha: 0.7 * deckkraft),
    );
    leinwand.drawParagraph(
        absatz, Offset(kasten.left + 5, kasten.top + 5));
  }
  return beschriftet;
}

/// Die Farbe je Art – nicht Zierrat, sondern die einzige Auskunft, die
/// ein namenloser Punkt gibt.
Color _zeichenfarbe(Wanderart art) => switch (art) {
      Wanderart.gipfel => const Color(0xFF8D5524),
      Wanderart.sattel => const Color(0xFF8D5524),
      Wanderart.aussicht => const Color(0xFF1565C0),
      Wanderart.huette => const Color(0xFFB3261E),
      Wanderart.schutzhuette => const Color(0xFFB3261E),
      Wanderart.quelle => const Color(0xFF00838F),
      Wanderart.wasserfall => const Color(0xFF00838F),
      Wanderart.wegweiser => const Color(0xFF5D6B3A),
      Wanderart.ruine => const Color(0xFF5B5B5B),
    };

/// Das Zeichen selbst – gezeichnet und nicht aus einer Schrift geholt.
///
/// **Keine Material-Glyphen.** Sie füllen ihren Kasten nicht aus, und wo
/// genau sie darin sitzen, hängt an der Glyphe; ein Dreieck und ein Haus
/// stünden dann auf verschiedenen Höhen über demselben Punkt. Vier
/// gezeichnete Formen sind hier billiger als eine Ausrichtung, die man
/// je Zeichen nachmessen müsste.
void _zeichenMalen(ui.Canvas leinwand, Offset wo, Wanderart art, Color farbe,
    double deckkraft) {
  final fuellung = ui.Paint()..color = farbe.withValues(alpha: deckkraft);
  final saum = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * deckkraft);
  const r = 5.0;

  switch (art) {
    case Wanderart.gipfel:
    case Wanderart.sattel:
      // Ein Dreieck, wie auf jeder Wanderkarte.
      final p = Path()
        ..moveTo(wo.dx, wo.dy - r - 1)
        ..lineTo(wo.dx + r, wo.dy + r - 1)
        ..lineTo(wo.dx - r, wo.dy + r - 1)
        ..close();
      leinwand.drawPath(p, fuellung);
      leinwand.drawPath(p, saum);
    case Wanderart.huette:
    case Wanderart.schutzhuette:
    case Wanderart.ruine:
      // Ein Haus: Rechteck mit Dach.
      final p = Path()
        ..moveTo(wo.dx - r, wo.dy + r)
        ..lineTo(wo.dx - r, wo.dy - 1)
        ..lineTo(wo.dx, wo.dy - r - 2)
        ..lineTo(wo.dx + r, wo.dy - 1)
        ..lineTo(wo.dx + r, wo.dy + r)
        ..close();
      leinwand.drawPath(p, fuellung);
      leinwand.drawPath(p, saum);
    case Wanderart.quelle:
    case Wanderart.wasserfall:
      // Ein Tropfen.
      final p = Path()
        ..moveTo(wo.dx, wo.dy - r - 2)
        ..quadraticBezierTo(wo.dx + r + 1, wo.dy + 1, wo.dx, wo.dy + r)
        ..quadraticBezierTo(wo.dx - r - 1, wo.dy + 1, wo.dx, wo.dy - r - 2)
        ..close();
      leinwand.drawPath(p, fuellung);
      leinwand.drawPath(p, saum);
    case Wanderart.aussicht:
    case Wanderart.wegweiser:
      leinwand.drawCircle(wo, r - 1, fuellung);
      leinwand.drawCircle(wo, r - 1, saum);
  }
}
