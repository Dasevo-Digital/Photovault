import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/zierbaum.dart';
import '../theme/zierbaum_farben.dart';
import 'zierbaum_ansicht.dart' show Schildinhalt;

/// Woher der Maler erfährt, was auf einem Schild steht.
typedef Schildbeschriftung = Schildinhalt Function(String personId);

/// Malt Grund, Stamm, Äste und Ranken – alles ausser den Schildern.
///
/// **Die Schilder sind bewusst nicht hier.** Sie liegen als echte Widgets
/// darüber, damit Antippen, Rechtsklick-Menü, Kurzhinweis und
/// Sprachausgabe weiterhin von selbst funktionieren. Ein Bild, das alles
/// selbst malt, müsste all das nachbauen – und die Sprachausgabe fände
/// eine leere Fläche vor (siehe die Anmerkung in `faecher_ansicht.dart`).
///
/// Alles hier hängt allein am [Zierbaumplan]: gleiche Familie, gleiches
/// Bild. Nichts wird gewürfelt, was sich beim nächsten Aufbau anders
/// entscheiden könnte.
class ZierbaumMaler extends CustomPainter {
  final Zierbaumplan plan;
  final Zierbaumfarben farben;

  /// Um wie viel der Baum nach rechts gerückt ist, weil das Fenster
  /// breiter ist als er. Die Schilder oben bekommen denselben Versatz.
  final double versatzX;

  /// Was auf einem Schild steht – nur für die Tafel gesetzt.
  ///
  /// Auf dem Bildschirm sind die Schilder Widgets: nur so bleiben
  /// Antippen, Menü und Sprachausgabe erhalten. Auf dem Blatt gibt es
  /// nichts anzutippen, und dort malt dieser Maler sie mit. Beide lesen
  /// dieselben [Schildmasse] – zwei Sätze Zahlen wären zwei Schilder,
  /// die auseinanderlaufen.
  final Schildbeschriftung? beschriftung;

  /// Der Familienname unter dem Stamm – ebenfalls nur für die Tafel.
  final String? familienname;

  final Schildmasse schildmasse;
  final String? fokusId;
  final TextDirection textRichtung;

  /// Ob Grund und Goldstaub mitgemalt werden.
  ///
  /// Auf dem Bildschirm nicht: Dort liegt der Baum in einem
  /// verschiebbaren Bereich, und ein Grund, der mitwandert, hört
  /// irgendwo auf – man sieht dann seine Kante mitten im Fenster. Er
  /// wird deshalb von [Zierbaumgrund] hinter den Bereich gemalt und
  /// bleibt stehen, während der Baum sich bewegt. Für die Tafel gilt
  /// das nicht: Ein Blatt Papier verschiebt sich nicht.
  final bool malGrund;

  const ZierbaumMaler({
    required this.plan,
    required this.farben,
    this.versatzX = 0,
    this.malGrund = true,
    this.beschriftung,
    this.familienname,
    this.fokusId,
    this.schildmasse = const Schildmasse(),
    this.textRichtung = TextDirection.ltr,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (malGrund) _grund(canvas, size);
    canvas.save();
    canvas.translate(versatzX, 0);
    _stamm(canvas, size);
    for (final ast in plan.aeste) {
      _ast(canvas, ast);
    }
    for (final band in plan.baender) {
      _partnerband(canvas, band);
    }
    for (final ast in plan.aeste) {
      _ranke(canvas, ast);
    }
    if (beschriftung != null) {
      for (final schild in plan.schilder) {
        _schild(canvas, schild);
      }
    }
    canvas.restore();
    if (malGrund) _staub(canvas, size);
    if (familienname != null) _familienname(canvas, size);
  }

  /// Ein Schild auf der Tafel: Rahmen, Name, Verhältnis, Lebensdaten.
  ///
  /// **Ohne Porträt.** Auf dem Blatt gibt es keine Gesichter – wie auf
  /// jeder gedruckten Ahnentafel und wie auf der Vorlage, aus der dieser
  /// Baum stammt. Nebenbei ist das der Grund, warum die Tafel überhaupt
  /// in einem Zug gemalt werden kann: Ein Bild müsste erst geladen
  /// werden, und eine Zeichnung wartet auf nichts.
  void _schild(Canvas canvas, Schild schild) {
    final inhalt = beschriftung!(schild.personId);
    final istMitte = schild.personId == fokusId;
    // **Die ganze Fläche, nicht nur der Teil unter dem Porträt.** Auf dem
    // Bildschirm sitzt über der Tafel ein Gesichtsausschnitt; auf dem
    // Blatt gibt es keinen. Liesse man den Platz trotzdem frei, endeten
    // die Äste in der Luft und die Schilder hingen darunter – genau so
    // sah der erste Ausdruck aus.
    final rechteck = Rect.fromLTRB(
        schild.links, schild.oben, schild.rechts, schild.unten);
    final rund = RRect.fromRectAndRadius(
        rechteck, Radius.circular(schildmasse.rundung));

    canvas.drawRRect(
      rund,
      Paint()
        ..shader = ui.Gradient.linear(
          rechteck.topCenter,
          rechteck.bottomCenter,
          [farben.schildOben, farben.schildUnten],
        ),
    );
    canvas.drawRRect(
      rund,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            istMitte ? schildmasse.randStark : schildmasse.randSchwach
        ..color = istMitte ? farben.mitteRand : farben.schildRand,
    );

    final zeilen = <(String, double, Color)>[
      (inhalt.name, schildmasse.schriftName, farben.schrift),
      if (inhalt.verwandtschaft != null)
        (inhalt.verwandtschaft!, schildmasse.schriftNeben, farben.nebenschrift),
      if (inhalt.lebensspanne != null)
        (inhalt.lebensspanne!, schildmasse.schriftNeben, farben.nebenschrift),
    ];
    final maler = <TextPainter>[];
    var gesamt = 0.0;
    for (final zeile in zeilen) {
      final tp = TextPainter(
        text: TextSpan(
          text: zeile.$1,
          style: TextStyle(
            color: zeile.$3,
            fontSize: zeile.$2,
            fontFamily: zierschrift,
            fontVariations:
                zeile == zeilen.first ? zierGewicht(istMitte ? 700 : 600) : null,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: textRichtung,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: rechteck.width - 2 * schildmasse.polsterX);
      maler.add(tp);
      gesamt += tp.height;
    }
    var y = rechteck.center.dy - gesamt / 2;
    for (final tp in maler) {
      tp.paint(canvas, Offset(rechteck.center.dx - tp.width / 2, y));
      y += tp.height;
      tp.dispose();
    }
  }

  void _familienname(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: familienname,
        style: TextStyle(
          color: farben.familienname,
          fontSize: schildmasse.schriftName * 3.6,
          fontFamily: zierschriftGross,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: textRichtung,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width * 0.8);
    // Ein dunkler Schleier darunter, damit die Schrift auch über dem
    // Stamm lesbar bleibt.
    final y = size.height - tp.height - schildmasse.schriftName;
    canvas.drawRect(
      Rect.fromLTWH(0, y - schildmasse.schriftName * 0.4, size.width,
          tp.height + schildmasse.schriftName * 0.8),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, y),
          Offset(0, y + tp.height),
          [farben.grundAussen.withValues(alpha: 0.0),
           farben.grundAussen.withValues(alpha: 0.85)],
        ),
    );
    tp.paint(canvas, Offset((size.width - tp.width) / 2, y));
    tp.dispose();
  }

  /// Ein warmer Schein hinter der Mitte, nach aussen ins Dunkle.
  void _grund(Canvas canvas, Size size) {
    final flaeche = Offset.zero & size;
    canvas.drawRect(flaeche, Paint()..color = farben.grundAussen);
    canvas.drawRect(
      flaeche,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(plan.stammX + versatzX, size.height * 0.62),
          size.longestSide * 0.7,
          [farben.grundInnen, farben.grundAussen],
          const [0.0, 1.0],
        ),
    );
  }

  /// Der Stamm: vom unteren Rand herauf bis an die Person in der Mitte.
  ///
  /// **An ihr Schild, nicht an das tiefste.** Der erste Ausdruck nahm
  /// die Unterkante des untersten Schildes – die liegt aber irgendwo,
  /// während der Stamm unter der Mitte steht. Er endete deshalb in der
  /// Luft und sah aus wie ein abgebrochener Strich.
  void _stamm(Canvas canvas, Size size) {
    if (plan.schilder.isEmpty) return;
    final ankerSchild = fokusId == null
        ? null
        : plan.schilder.where((s) => s.personId == fokusId).firstOrNull;
    final mitte = ankerSchild?.unten ??
        plan.schilder.map((s) => s.unten).reduce((a, b) => a > b ? a : b);
    // Bis zum unteren Rand. Der Familienname steht darüber, nicht
    // daneben – auf der Vorlage sitzt er genau so am Stammfuss. Ein
    // Stamm, der vor der Schrift haltmacht, war der erste Versuch und
    // sah aus wie ein Stummel.
    final fuss = size.height;
    final ast = Ast(
      personId: '',
      vonX: plan.stammX,
      vonY: fuss,
      nachX: plan.stammX,
      nachY: mitte,
    );
    _gefuellterAst(canvas, ast, unten: 26, oben: 9);
  }

  void _ast(Canvas canvas, Ast ast) => _gefuellterAst(canvas, ast, unten: 3.5, oben: 8);

  /// Ein Ast als **gefüllte** Form, nicht als Strich.
  ///
  /// Ein Strich hat überall dieselbe Breite; ein Ast, der sich nicht
  /// verjüngt, sieht aus wie ein Draht. Deshalb werden zwei Ränder
  /// abgetastet – links und rechts der Kurve, mit schrumpfendem Abstand –
  /// und zu einer geschlossenen Fläche verbunden.
  void _gefuellterAst(Canvas canvas, Ast ast,
      {required double unten, required double oben}) {
    const schritte = 24;
    final links = <Offset>[];
    final rechts = <Offset>[];
    for (var i = 0; i <= schritte; i++) {
      final t = i / schritte;
      final punkt = _aufDerKurve(ast, t);
      final richtung = _tangente(ast, t);
      // Senkrecht zur Laufrichtung.
      final quer = Offset(-richtung.dy, richtung.dx);
      final halb = (unten + (oben - unten) * t) / 2;
      links.add(punkt + quer * halb);
      rechts.add(punkt - quer * halb);
    }

    final pfad = Path()..moveTo(links.first.dx, links.first.dy);
    for (final p in links.skip(1)) {
      pfad.lineTo(p.dx, p.dy);
    }
    for (final p in rechts.reversed) {
      pfad.lineTo(p.dx, p.dy);
    }
    pfad.close();

    canvas.drawPath(
      pfad,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(ast.vonX, ast.vonY),
          Offset(ast.nachX, ast.nachY),
          [farben.holzDunkel, farben.holzHell],
        ),
    );
  }

  /// Das Band zwischen zwei Partnern – ein schlichter Bogen.
  void _partnerband(Canvas canvas, Partnerband band) {
    final mitte = (band.vonX + band.nachX) / 2;
    final pfad = Path()
      ..moveTo(band.vonX, band.y)
      ..quadraticBezierTo(mitte, band.y + 5, band.nachX, band.y);
    canvas.drawPath(
      pfad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = farben.holzHell,
    );
  }

  /// Eine Ranke am Ast – die Zierde, die nichts bedeutet.
  ///
  /// Sie sitzt bei zwei Dritteln der Kurve und dreht sich zu der Seite,
  /// die der Ast ohnehin nimmt. Ihre Grösse hängt an der Kennung der
  /// Person **und am Ziel des Astes**: gleich bleibende Vielfalt, ohne
  /// einen Würfel, der beim nächsten Aufbau anders fiele – und ohne dass
  /// die zwei Äste eines Kindes getrennt lebender Eltern zwei gleiche
  /// Ranken bekommen.
  void _ranke(Canvas canvas, Ast ast) {
    final laenge = (ast.vonY - ast.nachY).abs();
    if (laenge < 40) return;

    final ansatz = _aufDerKurve(ast, 0.66);
    final richtung = _tangente(ast, 0.66);
    final quer = Offset(-richtung.dy, richtung.dx);
    // Zur Aussenseite: dorthin, wohin der Ast sich neigt.
    final seite = ast.nachX >= ast.vonX ? -1.0 : 1.0;
    // `Object.hash` waere hier falsch: Es ist ausdruecklich nicht ueber
    // Programmlaeufe hinweg stabil, und genau das fing der
    // Goldbildvergleich - dasselbe Bild sah beim zweiten Lauf anders aus.
    final streu = ast.personId.hashCode + ast.nachX.round();
    final groesse = 14 + (streu.abs() % 10).toDouble();

    final pfad = Path()..moveTo(ansatz.dx, ansatz.dy);
    var punkt = ansatz;
    var weite = groesse;
    var winkel = math.atan2(quer.dy * seite, quer.dx * seite);
    for (var i = 0; i < 3; i++) {
      final naechster =
          punkt + Offset(math.cos(winkel), math.sin(winkel)) * weite;
      final steuer = punkt +
          Offset(math.cos(winkel - 0.9), math.sin(winkel - 0.9)) * weite;
      pfad.quadraticBezierTo(steuer.dx, steuer.dy, naechster.dx, naechster.dy);
      punkt = naechster;
      winkel += 1.9;
      weite *= 0.62;
    }

    canvas.drawPath(
      pfad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = farben.ranken,
    );
  }

  /// Goldstaub – Punkte auf einem festen Raster, nicht gewürfelt.
  ///
  /// Ein Zufallsgenerator hätte bei jedem Aufbau ein anderes Bild
  /// ergeben; auf einem Goldbild wäre das ein Fehlschlag je Lauf.
  void _staub(Canvas canvas, Size size) => _staubAuf(canvas, size, farben);

  /// Dasselbe Muster für beide Maler – zwei Fassungen wären zwei
  /// Sternenhimmel.
  static void _staubAuf(Canvas canvas, Size size, Zierbaumfarben farben) {
    final stift = Paint()..color = farben.staub.withValues(alpha: 0.22);
    const abstand = 47.0;
    for (var x = abstand / 2; x < size.width; x += abstand) {
      for (var y = abstand / 2; y < size.height; y += abstand) {
        // Ein festes, aber unregelmässig aussehendes Muster.
        final koerner = ((x * 7 + y * 13) ~/ abstand) % 5;
        if (koerner != 0) continue;
        final radius = 0.8 + ((x + y) % 3) * 0.5;
        canvas.drawCircle(Offset(x, y), radius, stift);
      }
    }
  }

  Offset _aufDerKurve(Ast ast, double t) {
    final p0 = Offset(ast.vonX, ast.vonY);
    final p1 = Offset(ast.vonX, ast.steuer1Y);
    final p2 = Offset(ast.nachX, ast.steuer2Y);
    final p3 = Offset(ast.nachX, ast.nachY);
    final u = 1 - t;
    return p0 * (u * u * u) +
        p1 * (3 * u * u * t) +
        p2 * (3 * u * t * t) +
        p3 * (t * t * t);
  }

  /// Die Laufrichtung an der Stelle [t], auf Länge eins gebracht.
  Offset _tangente(Ast ast, double t) {
    final p0 = Offset(ast.vonX, ast.vonY);
    final p1 = Offset(ast.vonX, ast.steuer1Y);
    final p2 = Offset(ast.nachX, ast.steuer2Y);
    final p3 = Offset(ast.nachX, ast.nachY);
    final u = 1 - t;
    final ableitung = (p1 - p0) * (3 * u * u) +
        (p2 - p1) * (6 * u * t) +
        (p3 - p2) * (3 * t * t);
    final laenge = ableitung.distance;
    // Bei einem Ast der Länge null gibt es keine Richtung; senkrecht nach
    // oben ist dann die harmloseste Antwort.
    return laenge < 0.0001 ? const Offset(0, -1) : ableitung / laenge;
  }

  @override
  bool shouldRepaint(ZierbaumMaler alt) =>
      alt.plan != plan ||
      alt.farben != farben ||
      alt.versatzX != versatzX ||
      alt.familienname != familienname ||
      alt.malGrund != malGrund ||
      alt.fokusId != fokusId;
}

/// Nur der Grund: der warme Schein und der Goldstaub darauf.
///
/// **Warum das ein eigener Maler ist.** Auf dem Bildschirm liegt der Baum
/// in einem Bereich, den man verschieben und zoomen kann. Ein Grund, der
/// darin mitwandert, ist genau so gross wie der Baum – schiebt man ihn
/// zur Seite, sieht man seine Kante und dahinter die gewöhnliche
/// Hintergrundfarbe. Dieser hier bleibt stehen und füllt immer das ganze
/// Fenster, egal wo der Baum gerade steht.
///
/// Der Schein sitzt deshalb auch in der Fenstermitte und nicht am Stamm:
/// Der Stamm bewegt sich, das Fenster nicht.
class Zierbaumgrund extends CustomPainter {
  final Zierbaumfarben farben;

  const Zierbaumgrund({required this.farben});

  @override
  void paint(Canvas canvas, Size size) {
    final flaeche = Offset.zero & size;
    canvas.drawRect(flaeche, Paint()..color = farben.grundAussen);
    canvas.drawRect(
      flaeche,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, size.height * 0.62),
          size.longestSide * 0.7,
          [farben.grundInnen, farben.grundAussen],
          const [0.0, 1.0],
        ),
    );
    ZierbaumMaler._staubAuf(canvas, size, farben);
  }

  @override
  bool shouldRepaint(Zierbaumgrund alt) => alt.farben != farben;
}
