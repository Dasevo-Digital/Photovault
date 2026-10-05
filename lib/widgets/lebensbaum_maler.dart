import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/lebensbaum.dart';
import '../theme/zierbaum_farben.dart'
    show zierschrift, zierschriftGross, zierGewicht;

/// Die drei Erscheinungsbilder des Lebensbaums.
///
/// Nach den Vorbildern gemalter Stammbaumtafeln: Pergament mit
/// Namensrollen, eine Landschaft unter offenem Himmel, und die heraldische
/// Form mit Wappenschilden.
enum Lebensbaumstil { pergament, landschaft, wappen }

enum Lebensbaumschildform { rolle, wappen }

enum Lebensbaumhintergrund { papier, landschaft, wolken }

/// Die Farben eines Stils.
///
/// Ein Wertobjekt aus demselben Grund wie beim Zierbaum: Bildschirm und
/// Tafel malen mit demselben Satz, statt jeder für sich nachzuschlagen.
/// Bewusst **unabhängig vom hellen oder dunklen Erscheinungsbild** der
/// App – der Lebensbaum ist ein Bild, kein Teil der Oberfläche, und ein
/// Pergament wird nachts nicht schwarz.
@immutable
class Lebensbaumfarben {
  final Color grundOben;
  final Color grundUnten;
  final Color wieseHell;
  final Color wieseDunkel;
  final Color holzDunkel;
  final Color holzHell;
  final Color rinde;
  final List<Color> laub;

  /// Wie viel Laub, 1 ist voll belaubt.
  final double laubdichte;
  final Color schildHell;
  final Color schildDunkel;
  final Color schildRand;
  final Color schrift;
  final Color nebenschrift;
  final Color mitte;
  final Color bandHell;
  final Color bandDunkel;
  final Color bandSchrift;

  /// Die Kordeln, an denen die Rollen in der Landschaft hängen.
  final Color? kordel;

  /// Nur für Wappenschilde: je Generation ein Ton.
  final List<Color> generationstoene;
  final Lebensbaumschildform schildform;
  final Lebensbaumhintergrund hintergrund;

  const Lebensbaumfarben._({
    required this.grundOben,
    required this.grundUnten,
    required this.wieseHell,
    required this.wieseDunkel,
    required this.holzDunkel,
    required this.holzHell,
    required this.rinde,
    required this.laub,
    required this.laubdichte,
    required this.schildHell,
    required this.schildDunkel,
    required this.schildRand,
    required this.schrift,
    required this.nebenschrift,
    required this.mitte,
    required this.bandHell,
    required this.bandDunkel,
    required this.bandSchrift,
    required this.schildform,
    required this.hintergrund,
    this.kordel,
    this.generationstoene = const [],
  });

  static const pergament = Lebensbaumfarben._(
    grundOben: Color(0xFFF6ECD2),
    grundUnten: Color(0xFFE6D3A6),
    wieseHell: Color(0xFFD5E2A8),
    wieseDunkel: Color(0xFF9DBB6A),
    holzDunkel: Color(0xFF5E3D22),
    holzHell: Color(0xFF9C6B3F),
    rinde: Color(0xFF3E2716),
    laub: [
      Color(0xFF2E6B2A),
      Color(0xFF3F8A33),
      Color(0xFF5FA843),
      Color(0xFF86C25A),
    ],
    laubdichte: 1,
    schildHell: Color(0xFFFCF3DA),
    schildDunkel: Color(0xFFE8CF97),
    schildRand: Color(0xFF8B6A3A),
    schrift: Color(0xFF3A2A14),
    nebenschrift: Color(0xFF6B5330),
    mitte: Color(0xFFB4862C),
    bandHell: Color(0xFFF4F4F2),
    bandDunkel: Color(0xFFB9BCC0),
    bandSchrift: Color(0xFF2B2B2B),
    schildform: Lebensbaumschildform.rolle,
    hintergrund: Lebensbaumhintergrund.papier,
  );

  static const landschaft = Lebensbaumfarben._(
    grundOben: Color(0xFF7EC2EC),
    grundUnten: Color(0xFFD6EEFA),
    wieseHell: Color(0xFFEFDF95),
    wieseDunkel: Color(0xFFA9CF6E),
    holzDunkel: Color(0xFF7A4B2A),
    holzHell: Color(0xFFB8804F),
    rinde: Color(0xFF55331C),
    laub: [
      Color(0xFF4E8F3A),
      Color(0xFF6FAE4A),
      Color(0xFF93C66A),
      Color(0xFFB8DB8F),
    ],
    laubdichte: 1,
    schildHell: Color(0xFFFFF9E6),
    schildDunkel: Color(0xFFF0DFB2),
    schildRand: Color(0xFFB39459),
    schrift: Color(0xFF3B2E1A),
    nebenschrift: Color(0xFF6E5A36),
    mitte: Color(0xFF2F5D9E),
    bandHell: Color(0xFFFFF8E2),
    bandDunkel: Color(0xFFE2CC92),
    bandSchrift: Color(0xFF3B2E1A),
    kordel: Color(0xFF2F5D9E),
    schildform: Lebensbaumschildform.rolle,
    hintergrund: Lebensbaumhintergrund.landschaft,
  );

  static const wappen = Lebensbaumfarben._(
    grundOben: Color(0xFFE3EDF6),
    grundUnten: Color(0xFF9DB8D3),
    wieseHell: Color(0xFFC9D8B4),
    wieseDunkel: Color(0xFF8DA874),
    holzDunkel: Color(0xFF6B472E),
    holzHell: Color(0xFFB58A63),
    rinde: Color(0xFF4A3020),
    laub: [Color(0xFF4F6F31), Color(0xFF6E8E43), Color(0xFF8FA95E)],
    laubdichte: 0.5,
    schildHell: Color(0xFFFFFFFF),
    schildDunkel: Color(0xFFE6E9EF),
    schildRand: Color(0xFF5E6170),
    schrift: Color(0xFF26282F),
    nebenschrift: Color(0xFF555866),
    mitte: Color(0xFF2B3F66),
    bandHell: Color(0xFF3A5385),
    bandDunkel: Color(0xFF22345A),
    bandSchrift: Color(0xFFF5F2E8),
    generationstoene: [
      Color(0xFFFFFFFF),
      Color(0xFFF3D3C0),
      Color(0xFFDCD3EC),
      Color(0xFFD5E8CC),
      Color(0xFFF5E7B2),
      Color(0xFFCFE2F1),
      Color(0xFFF0D0DC),
    ],
    schildform: Lebensbaumschildform.wappen,
    hintergrund: Lebensbaumhintergrund.wolken,
  );

  static Lebensbaumfarben fuer(Lebensbaumstil stil) => switch (stil) {
    Lebensbaumstil.pergament => pergament,
    Lebensbaumstil.landschaft => landschaft,
    Lebensbaumstil.wappen => wappen,
  };
}

/// Was auf einem Schild steht.
typedef Lebensbaumschild = ({String name, String? lebensspanne});

/// Malt den ganzen Lebensbaum: Grund, Wurzeln, Stamm, Äste, Laub,
/// Schilder und Spruchband.
///
/// **Alles wird gemalt, nichts als Widget gebaut** – auch die Schrift. So
/// entsteht die Tafel zum Aufhängen aus genau demselben Code wie das Bild
/// auf dem Schirm; die Ansicht legt nur unsichtbare Flächen für Tippen und
/// Bildschirmleser darüber.
class LebensbaumMaler extends CustomPainter {
  final Lebensbaumplan plan;
  final Lebensbaummasse masse;
  final Lebensbaumfarben farben;
  final Lebensbaumschild Function(String personId) beschriftung;

  /// Die Zeile auf dem Spruchband.
  final String titel;
  final TextDirection textRichtung;

  LebensbaumMaler({
    required this.plan,
    required this.masse,
    required this.farben,
    required this.beschriftung,
    required this.titel,
    this.textRichtung = TextDirection.ltr,
  });

  double get _s => masse.schildHoehe / 58;

  @override
  void paint(Canvas canvas, Size size) {
    _grund(canvas, size);
    _boden(canvas, size);
    _wurzeln(canvas);
    _stamm(canvas);
    _aeste(canvas);
    _laub(canvas);
    _kordeln(canvas);
    _schilder(canvas);
    _spruchband(canvas, size);
  }

  // --- Grund ---------------------------------------------------------

  void _grund(Canvas canvas, Size size) {
    final flaeche = Offset.zero & size;
    canvas.drawRect(
      flaeche,
      Paint()
        ..shader = ui.Gradient.linear(flaeche.topCenter, flaeche.bottomCenter, [
          farben.grundOben,
          farben.grundUnten,
        ]),
    );
    switch (farben.hintergrund) {
      case Lebensbaumhintergrund.papier:
        // Ein Rand, der nachdunkelt – altes Papier.
        canvas.drawRect(
          flaeche,
          Paint()
            ..shader = ui.Gradient.radial(
              flaeche.center,
              size.longestSide * 0.62,
              [const Color(0x00000000), const Color(0x2A5A3A10)],
              const [0.62, 1],
            ),
        );
      case Lebensbaumhintergrund.landschaft:
        _berge(canvas, size);
      case Lebensbaumhintergrund.wolken:
        _wolken(canvas, size);
    }
  }

  void _berge(Canvas canvas, Size size) {
    final zufall = math.Random(7);
    final fuss = plan.boden - masse.stamm * 0.15;
    final pfad = Path()..moveTo(0, fuss);
    var x = 0.0;
    while (x < size.width) {
      final breite = size.width * (0.08 + zufall.nextDouble() * 0.1);
      final spitze = fuss - masse.stamm * (0.35 + zufall.nextDouble() * 0.45);
      pfad.lineTo(x + breite / 2, spitze);
      x += breite;
      pfad.lineTo(x, fuss - masse.stamm * zufall.nextDouble() * 0.15);
    }
    pfad
      ..lineTo(size.width, fuss)
      ..close();
    canvas.drawPath(pfad, Paint()..color = const Color(0xFFC6D5E4));
    // Schnee auf den Gipfeln wäre Zierrat; ein hellerer Dunst davor
    // nimmt den Bergen die Härte.
    canvas.drawRect(
      Rect.fromLTRB(0, fuss - masse.stamm * 0.9, size.width, fuss),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, fuss - masse.stamm * 0.9),
          Offset(0, fuss),
          [const Color(0x00FFFFFF), const Color(0x66FFFFFF)],
        ),
    );
  }

  void _wolken(Canvas canvas, Size size) {
    final zufall = math.Random(11);
    final weich = Paint()
      ..color = const Color(0x8CFFFFFF)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 * _s);
    for (var i = 0; i < 9; i++) {
      final mitte = Offset(
        zufall.nextDouble() * size.width,
        zufall.nextDouble() * plan.boden * 0.8,
      );
      for (var j = 0; j < 4; j++) {
        canvas.drawCircle(
          mitte +
              Offset(
                (j - 1.5) * 34 * _s,
                (zufall.nextDouble() - 0.5) * 16 * _s,
              ),
          (26 + zufall.nextDouble() * 22) * _s,
          weich,
        );
      }
    }
  }

  void _boden(Canvas canvas, Size size) {
    final y = plan.boden;
    if (farben.hintergrund == Lebensbaumhintergrund.landschaft) {
      // Zwei Hügelbänder bis zum unteren Rand.
      for (final (anteil, farbe) in [
        (0.0, farben.wieseHell),
        (0.35, farben.wieseDunkel.withValues(alpha: 0.85)),
      ]) {
        final oben = y - masse.stamm * 0.1 + anteil * masse.fuss;
        final pfad = Path()
          ..moveTo(0, oben + 20 * _s)
          ..cubicTo(
            size.width * 0.3,
            oben - 30 * _s,
            size.width * 0.6,
            oben + 40 * _s,
            size.width,
            oben,
          )
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(pfad, Paint()..color = farbe);
      }
      return;
    }
    // Eine Wiese als flache Ellipse, auf der der Stamm steht.
    final wiese = Rect.fromCenter(
      center: Offset(plan.stammFuss.dx, y + 12 * _s),
      width: math.min(size.width * 0.86, plan.breite),
      height: 70 * _s,
    );
    canvas.drawOval(
      wiese,
      Paint()
        ..shader = ui.Gradient.radial(
          wiese.center,
          wiese.width / 2,
          [farben.wieseDunkel, farben.wieseHell.withValues(alpha: 0)],
          const [0.25, 1],
        ),
    );
  }

  // --- Holz ----------------------------------------------------------

  double _dicke(int spitzen) => math.min(
    masse.schildHoehe * 0.95,
    masse.schildHoehe * 0.16 * math.sqrt(spitzen) + 7 * _s,
  );

  Paint get _holz => Paint()
    ..shader = ui.Gradient.linear(Offset(0, plan.boden), const Offset(0, 0), [
      farben.holzDunkel,
      farben.holzHell,
    ]);

  /// Ein Glanzlicht auf der linken Flanke, damit Holz rund aussieht und
  /// nicht wie ausgeschnitten.
  Paint get _glanz => Paint()
    ..color = Color.lerp(
      farben.holzHell,
      Colors.white,
      0.35,
    )!.withValues(alpha: 0.45);

  /// Ein Ast als gefüllte Fläche, die von [dickeVon] auf [dickeBis]
  /// zuläuft. Ein Strich gleicher Breite sähe aus wie ein Rohr.
  Path _ast(Offset von, Offset bis, double dickeVon, double dickeBis) {
    final hoehe = (von.dy - bis.dy).abs();
    final p1 = von + Offset(0, -hoehe * 0.55);
    final p2 = bis + Offset(0, hoehe * 0.45);
    const schritte = 24;
    final links = <Offset>[];
    final rechts = <Offset>[];
    for (var i = 0; i <= schritte; i++) {
      final t = i / schritte;
      final punkt = _bezier(von, p1, p2, bis, t);
      final richtung = _bezierAbleitung(von, p1, p2, bis, t);
      final laenge = richtung.distance == 0 ? 1.0 : richtung.distance;
      final normale = Offset(-richtung.dy / laenge, richtung.dx / laenge);
      final dicke = dickeVon + (dickeBis - dickeVon) * t;
      links.add(punkt + normale * (dicke / 2));
      rechts.add(punkt - normale * (dicke / 2));
    }
    final pfad = Path()..moveTo(links.first.dx, links.first.dy);
    for (final p in links.skip(1)) {
      pfad.lineTo(p.dx, p.dy);
    }
    for (final p in rechts.reversed) {
      pfad.lineTo(p.dx, p.dy);
    }
    return pfad..close();
  }

  static Offset _bezier(Offset a, Offset b, Offset c, Offset d, double t) {
    final u = 1 - t;
    return a * (u * u * u) +
        b * (3 * u * u * t) +
        c * (3 * u * t * t) +
        d * (t * t * t);
  }

  static Offset _bezierAbleitung(
    Offset a,
    Offset b,
    Offset c,
    Offset d,
    double t,
  ) {
    final u = 1 - t;
    return (b - a) * (3 * u * u) +
        (c - b) * (6 * u * t) +
        (d - c) * (3 * t * t);
  }

  void _wurzeln(Canvas canvas) {
    final fuss = plan.stammFuss;
    final dicke = _dicke(plan.wurzel.spitzen);
    final zufall = math.Random(3);
    for (final seite in [-1.0, 1.0]) {
      for (var i = 0; i < 4; i++) {
        final weite =
            (dicke * 1.4 + (30 + i * 42 + zufall.nextDouble() * 24) * _s);
        final ziel =
            fuss +
            Offset(seite * weite, (6 + i * 7 + zufall.nextDouble() * 6) * _s);
        canvas.drawPath(
          _ast(
            fuss +
                Offset(
                  seite * dicke * (0.5 + i * 0.12),
                  -dicke * (0.9 - i * 0.15),
                ),
            ziel,
            dicke * (0.7 - i * 0.13),
            2.5 * _s,
          ),
          _holz,
        );
      }
    }
  }

  void _stamm(Canvas canvas) {
    final oben = plan.wurzel.rahmen.center;
    final fuss = plan.stammFuss;
    final dicke = _dicke(plan.wurzel.spitzen);
    final unten = dicke * 1.25;
    final hoehe = fuss.dy - oben.dy;
    final pfad = Path()
      ..moveTo(fuss.dx - unten, fuss.dy)
      ..cubicTo(
        fuss.dx - dicke * 0.55,
        fuss.dy - hoehe * 0.12,
        fuss.dx - dicke * 0.5,
        fuss.dy - hoehe * 0.55,
        oben.dx - dicke * 0.62,
        oben.dy,
      )
      ..lineTo(oben.dx + dicke * 0.62, oben.dy)
      ..cubicTo(
        fuss.dx + dicke * 0.5,
        fuss.dy - hoehe * 0.55,
        fuss.dx + dicke * 0.55,
        fuss.dy - hoehe * 0.12,
        fuss.dx + unten,
        fuss.dy,
      )
      ..close();
    final quer = Rect.fromLTRB(
      fuss.dx - unten,
      oben.dy,
      fuss.dx + unten,
      fuss.dy,
    );
    canvas.drawPath(
      pfad,
      Paint()
        ..shader = ui.Gradient.linear(
          quer.centerLeft,
          quer.centerRight,
          [
            farben.holzDunkel,
            farben.holzHell,
            farben.holzHell,
            farben.holzDunkel,
          ],
          const [0.08, 0.38, 0.55, 0.95],
        ),
    );
    // Rinde: dunkle Längsrisse.
    final riss = Paint()
      ..color = farben.rinde.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * _s
      ..strokeCap = StrokeCap.round;
    final zufall = math.Random(5);
    for (var i = 0; i < 11; i++) {
      final x = fuss.dx + (zufall.nextDouble() - 0.5) * dicke * 0.9;
      final y0 = fuss.dy - hoehe * (0.05 + zufall.nextDouble() * 0.55);
      final y1 = y0 - hoehe * (0.12 + zufall.nextDouble() * 0.25);
      canvas.drawPath(
        Path()
          ..moveTo(x, y0)
          ..quadraticBezierTo(
            x + (zufall.nextDouble() - 0.5) * 12 * _s,
            (y0 + y1) / 2,
            x + (zufall.nextDouble() - 0.5) * 6 * _s,
            y1,
          ),
        riss,
      );
    }
  }

  void _aeste(Canvas canvas) {
    final holz = _holz;
    final glanz = _glanz;
    for (final k in plan.knoten) {
      final vorgaenger = k.vorgaenger == null
          ? null
          : plan.knotenMit(k.vorgaenger!);
      if (vorgaenger == null) continue;
      final dicke = _dicke(k.spitzen);
      final von = vorgaenger.rahmen.center;
      final bis = k.rahmen.center;
      canvas.drawPath(_ast(von, bis, dicke, dicke * 0.5), holz);
      // Der Glanz läuft links neben der Mittellinie.
      final versatz = Offset(-dicke * 0.18, 0);
      canvas.drawPath(
        _ast(von + versatz, bis + versatz * 0.5, dicke * 0.22, dicke * 0.1),
        glanz,
      );
    }
  }

  // --- Laub ----------------------------------------------------------

  /// Das Laub wächst in Büscheln, nicht einzeln: dunkle Blätter unten
  /// und innen, helle oben, wo das Licht hinfällt. Gestreute
  /// Einzelblätter sähen aus wie Herbst.
  void _laub(Canvas canvas) {
    if (farben.laubdichte <= 0) return;
    final hauch = Paint()
      ..color = farben.laub.first.withValues(alpha: 0.3 * farben.laubdichte)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 30 * _s);

    // Erst alle Büschel bestimmen, dann in zwei Lagen malen – sonst
    // läge das helle Laub eines Astes unter dem dunklen des nächsten.
    final bueschel =
        <({Offset mitte, double rx, double ry, int anzahl, int saat})>[];
    for (final k in plan.knoten) {
      final zufall = math.Random(k.schluessel.hashCode);
      final spitze = plan.knoten.every((a) => a.vorgaenger != k.schluessel);
      final rx = k.rahmen.width / 2 + masse.schildBreite * 0.35;
      final ry = masse.schildHoehe * 0.95;
      final zahl = k.stufe == 0 ? 3 : (spitze ? 7 : 5);
      for (var i = 0; i < zahl; i++) {
        final winkel =
            math.pi * (1.05 + 0.9 * i / math.max(1, zahl - 1)) +
            (zufall.nextDouble() - 0.5) * 0.4;
        var mitte =
            k.rahmen.center +
            Offset(
              math.cos(winkel) * rx,
              math.sin(winkel) * ry * (spitze ? 1.25 : 0.9),
            );
        if (k.stufe == 0) mitte = mitte.translate(0, -masse.schildHoehe * 0.2);
        bueschel.add((
          mitte: mitte,
          rx: masse.schildBreite * (0.28 + zufall.nextDouble() * 0.12),
          ry: masse.schildHoehe * (0.55 + zufall.nextDouble() * 0.2),
          anzahl: (26 * farben.laubdichte).round(),
          saat: zufall.nextInt(1 << 30),
        ));
      }
      final vorgaenger = k.vorgaenger == null
          ? null
          : plan.knotenMit(k.vorgaenger!);
      if (vorgaenger == null) continue;
      // Am Ast entlang, je nach Länge: Ein langer Ast ohne Laub sieht
      // aus wie ein Gestell, nicht wie ein Baum.
      final von = vorgaenger.rahmen.center;
      final bis = k.rahmen.center;
      final anzahl = math.max(
        2,
        ((bis - von).distance / (masse.schildHoehe * 1.5)).round(),
      );
      for (var i = 1; i <= anzahl; i++) {
        final t = i / (anzahl + 1);
        final mitte = Offset.lerp(von, bis, t)!;
        bueschel.add((
          mitte: mitte + Offset((zufall.nextDouble() - 0.5) * 30 * _s, 0),
          rx: masse.schildBreite * (0.2 + zufall.nextDouble() * 0.08),
          ry: masse.schildHoehe * 0.45,
          anzahl: (16 * farben.laubdichte).round(),
          saat: zufall.nextInt(1 << 30),
        ));
      }
    }

    for (final b in bueschel) {
      canvas.drawOval(
        Rect.fromCenter(center: b.mitte, width: b.rx * 2.6, height: b.ry * 2.6),
        hauch,
      );
    }
    final dunkel = farben.laub.take((farben.laub.length / 2).ceil()).toList();
    final hell = farben.laub.skip(dunkel.length).toList();
    for (final (lage, toene) in [
      (0, dunkel),
      (1, hell.isEmpty ? dunkel : hell),
    ]) {
      final pinsel = [for (final c in toene) Paint()..color = c];
      for (final b in bueschel) {
        final zufall = math.Random(b.saat + lage);
        final zahl = lage == 0 ? b.anzahl : (b.anzahl * 0.7).round();
        for (var i = 0; i < zahl; i++) {
          final winkel = zufall.nextDouble() * math.pi * 2;
          final abstand = math.sqrt(zufall.nextDouble());
          // Die helle Lage sitzt oben im Büschel.
          final hoch = lage == 1 ? -b.ry * 0.3 : b.ry * 0.1;
          _blatt(
            canvas,
            b.mitte +
                Offset(
                  math.cos(winkel) * b.rx * abstand,
                  math.sin(winkel) * b.ry * abstand * 0.8 + hoch,
                ),
            (14 + zufall.nextDouble() * 11) * _s,
            zufall.nextDouble() * math.pi * 2,
            pinsel[zufall.nextInt(pinsel.length)],
          );
        }
      }
    }
  }

  void _blatt(
    Canvas canvas,
    Offset stelle,
    double laenge,
    double winkel,
    Paint farbe,
  ) {
    canvas
      ..save()
      ..translate(stelle.dx, stelle.dy)
      ..rotate(winkel);
    final breite = laenge * 0.45;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(laenge * 0.5, -breite, laenge, 0)
        ..quadraticBezierTo(laenge * 0.5, breite, 0, 0)
        ..close(),
      farbe,
    );
    canvas.restore();
  }

  // --- Schilder ------------------------------------------------------

  void _kordeln(Canvas canvas) {
    final kordel = farben.kordel;
    if (kordel == null) return;
    final pinsel = Paint()
      ..color = kordel
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * _s
      ..strokeCap = StrokeCap.round;
    for (final k in plan.knoten) {
      for (final r in k.schilder) {
        final aufhaenger = r.topCenter.translate(0, -masse.schildHoehe * 0.32);
        canvas
          ..drawLine(
            r.topLeft.translate(r.width * 0.2, 2 * _s),
            aufhaenger,
            pinsel,
          )
          ..drawLine(
            r.topRight.translate(-r.width * 0.2, 2 * _s),
            aufhaenger,
            pinsel,
          )
          ..drawCircle(aufhaenger, 3 * _s, Paint()..color = kordel);
      }
    }
  }

  void _schilder(Canvas canvas) {
    for (final k in plan.knoten) {
      for (var i = 0; i < k.schilder.length; i++) {
        final r = k.schilder[i];
        final mitte = k.stufe == 0;
        if (farben.schildform == Lebensbaumschildform.wappen) {
          _wappenschild(canvas, r, k.stufe, mitte);
        } else {
          _rolle(canvas, r, mitte);
        }
        _beschrifte(canvas, r, beschriftung(k.personen[i]));
      }
      if (k.schilder.length == 2) _ringe(canvas, k.schilder[0], k.schilder[1]);
    }
  }

  void _rolle(Canvas canvas, Rect r, bool mitte) {
    final schatten = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * _s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r.shift(Offset(0, 3 * _s)),
        Radius.circular(4 * _s),
      ),
      schatten,
    );
    final koerper = RRect.fromRectAndRadius(r, Radius.circular(4 * _s));
    canvas.drawRRect(
      koerper,
      Paint()
        ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [
          farben.schildHell,
          farben.schildDunkel,
        ]),
    );
    // Die eingerollten Enden: links und rechts ein schmaler Zylinder,
    // etwas höher als das Blatt.
    final rolle = r.height * 0.16;
    for (final x in [r.left, r.right]) {
      final zylinder = Rect.fromCenter(
        center: Offset(x, r.center.dy),
        width: rolle,
        height: r.height + 6 * _s,
      );
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(zylinder, Radius.circular(rolle / 2)),
          Paint()
            ..shader = ui.Gradient.linear(
              zylinder.centerLeft,
              zylinder.centerRight,
              [farben.schildDunkel, farben.schildHell, farben.schildDunkel],
              const [0, 0.45, 1],
            ),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(zylinder, Radius.circular(rolle / 2)),
          Paint()
            ..color = farben.schildRand
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 * _s,
        );
    }
    canvas.drawRRect(
      koerper,
      Paint()
        ..color = mitte ? farben.mitte : farben.schildRand
        ..style = PaintingStyle.stroke
        ..strokeWidth = (mitte ? 2.4 : 1.1) * _s,
    );
  }

  void _wappenschild(Canvas canvas, Rect r, int stufe, bool mitte) {
    // Ein Wappenschild ist höher als breit; im Rechteck des Schildes
    // steht es mittig, damit Tippen und Text dieselben Masse behalten.
    final breite = math.min(r.width, r.height * 1.6);
    final s = Rect.fromCenter(
      center: r.center,
      width: breite,
      height: r.height * 1.25,
    );
    final form = Path()
      ..moveTo(s.left, s.top)
      ..lineTo(s.right, s.top)
      ..lineTo(s.right, s.top + s.height * 0.5)
      ..quadraticBezierTo(
        s.right,
        s.bottom - s.height * 0.12,
        s.center.dx,
        s.bottom,
      )
      ..quadraticBezierTo(
        s.left,
        s.bottom - s.height * 0.12,
        s.left,
        s.top + s.height * 0.5,
      )
      ..close();
    canvas.drawPath(
      form.shift(Offset(0, 3 * _s)),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * _s),
    );
    final toene = farben.generationstoene;
    final ton = toene.isEmpty ? farben.schildHell : toene[stufe % toene.length];
    canvas
      ..drawPath(
        form,
        Paint()
          ..shader = ui.Gradient.linear(s.topLeft, s.bottomRight, [
            Color.lerp(ton, Colors.white, 0.5)!,
            ton,
          ]),
      )
      ..drawPath(
        form,
        Paint()
          ..color = mitte ? farben.mitte : farben.schildRand
          ..style = PaintingStyle.stroke
          ..strokeWidth = (mitte ? 2.6 : 1.2) * _s,
      );
  }

  /// Zwei verschlungene Ringe zwischen den Schildern eines Paares – das
  /// alte Zeichen für „verheiratet".
  void _ringe(Canvas canvas, Rect a, Rect b) {
    final mitte = Offset((a.right + b.left) / 2, a.center.dy);
    final pinsel = Paint()
      ..color = farben.schildRand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * _s;
    final r = 4.2 * _s;
    canvas
      ..drawCircle(mitte.translate(-r * 0.55, 0), r, pinsel)
      ..drawCircle(mitte.translate(r * 0.55, 0), r, pinsel);
  }

  void _beschrifte(Canvas canvas, Rect r, Lebensbaumschild inhalt) {
    final wappen = farben.schildform == Lebensbaumschildform.wappen;
    final breite = (wappen
        ? math.min(r.width, r.height * 1.6) * 0.82
        : r.width * 0.8);
    final name = TextPainter(
      text: TextSpan(
        text: inhalt.name,
        style: TextStyle(
          fontFamily: zierschrift,
          fontVariations: zierGewicht(620),
          fontSize: masse.schildHoehe * 0.26,
          height: 1.05,
          color: farben.schrift,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: textRichtung,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: breite);
    final spanne = inhalt.lebensspanne == null
        ? null
        : (TextPainter(
            text: TextSpan(
              text: inhalt.lebensspanne,
              style: TextStyle(
                fontFamily: zierschrift,
                fontSize: masse.schildHoehe * 0.2,
                color: farben.nebenschrift,
              ),
            ),
            textAlign: TextAlign.center,
            textDirection: textRichtung,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: breite));
    final gesamt = name.height + (spanne?.height ?? 0);
    // Im Wappen sitzt die Schrift im breiten oberen Teil.
    final mitteY = wappen ? r.center.dy - r.height * 0.08 : r.center.dy;
    var y = mitteY - gesamt / 2;
    name.paint(canvas, Offset(r.center.dx - name.width / 2, y));
    y += name.height;
    spanne?.paint(canvas, Offset(r.center.dx - spanne.width / 2, y));
  }

  // --- Spruchband ----------------------------------------------------

  void _spruchband(Canvas canvas, Size size) {
    final mitte = Offset(size.width / 2, plan.boden + masse.fuss * 0.55);
    final hoehe = masse.fuss * 0.3;
    final text = TextPainter(
      text: TextSpan(
        text: titel,
        style: TextStyle(
          fontFamily: zierschriftGross,
          fontSize: hoehe * 0.58,
          wordSpacing: hoehe * 0.18,
          color: farben.bandSchrift,
        ),
      ),
      textDirection: textRichtung,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width * 0.72);
    final breite = math.max(text.width + hoehe * 2.2, size.width * 0.42);
    final band = Rect.fromCenter(center: mitte, width: breite, height: hoehe);
    final bogen = hoehe * 0.35;

    // Die Enden hinter dem Band, mit Kerbe.
    final ende = hoehe * 0.95;
    for (final seite in [-1.0, 1.0]) {
      final innen = seite < 0
          ? band.left + hoehe * 0.3
          : band.right - hoehe * 0.3;
      final aussen = innen + seite * (ende + hoehe * 0.3);
      final y = band.center.dy + hoehe * 0.28;
      canvas.drawPath(
        Path()
          ..moveTo(innen, y - hoehe / 2)
          ..lineTo(aussen, y - hoehe / 2)
          ..lineTo(aussen - seite * hoehe * 0.32, y)
          ..lineTo(aussen, y + hoehe / 2)
          ..lineTo(innen, y + hoehe / 2)
          ..close(),
        Paint()..color = farben.bandDunkel,
      );
    }
    final form = Path()
      ..moveTo(band.left, band.top)
      ..quadraticBezierTo(
        band.center.dx,
        band.top + bogen,
        band.right,
        band.top,
      )
      ..lineTo(band.right, band.bottom)
      ..quadraticBezierTo(
        band.center.dx,
        band.bottom + bogen,
        band.left,
        band.bottom,
      )
      ..close();
    canvas
      ..drawPath(
        form.shift(Offset(0, 3 * _s)),
        Paint()
          ..color = const Color(0x33000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * _s),
      )
      ..drawPath(
        form,
        Paint()
          ..shader = ui.Gradient.linear(band.topCenter, band.bottomCenter, [
            farben.bandHell,
            farben.bandDunkel,
          ]),
      )
      ..drawPath(
        form,
        Paint()
          ..color = farben.bandSchrift.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * _s,
      );
    text.paint(
      canvas,
      Offset(mitte.dx - text.width / 2, mitte.dy + bogen / 2 - text.height / 2),
    );
  }

  @override
  bool shouldRepaint(LebensbaumMaler alt) =>
      alt.plan != plan ||
      alt.farben != farben ||
      alt.titel != titel ||
      alt.masse != masse ||
      alt.textRichtung != textRichtung;
}
