/// Das Höhenprofil einer aufgezeichneten Spur.
///
/// **Die Waagerechte ist die Strecke, nicht die Zeit.** Ein Profil über
/// der Zeit macht aus jeder Rast eine Ebene und aus jedem Abstieg eine
/// Wand – man sieht, wie lange man wo war, aber nicht, wie der Weg
/// aussah. Über der Strecke aufgetragen steht die Steigung da, wo sie
/// hingehört.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/gpx.dart' show Profilpunkt;
import '../theme/app_spacing.dart';

/// Zeichnet das Profil und meldet, wohin gezeigt wird.
class Hoehenprofil extends StatefulWidget {
  final List<Profilpunkt> punkte;

  /// Wird gerufen, während jemand über das Profil fährt – mit dem Index
  /// des nächstgelegenen Punktes, oder `null` beim Loslassen. So kann
  /// die Karte daneben die Stelle zeigen.
  final void Function(int?)? beiStelle;

  /// Die Beschreibung für die Sprachausgabe. Ein `CustomPaint` ist für
  /// sie sonst eine leere Fläche.
  final String beschreibung;

  final double hoehe;

  const Hoehenprofil({
    super.key,
    required this.punkte,
    required this.beschreibung,
    this.beiStelle,
    this.hoehe = 140,
  });

  @override
  State<Hoehenprofil> createState() => _HoehenprofilState();
}

class _HoehenprofilState extends State<Hoehenprofil> {
  int? _stelle;

  /// Welcher Punkt unter [x] liegt – gesucht über die Strecke und nicht
  /// über den Index: Die Punkte einer Aufzeichnung liegen nicht
  /// gleichmässig, wer stehen bleibt, erzeugt viele auf derselben
  /// Stelle.
  int? _punktBei(double x, double breite) {
    if (widget.punkte.isEmpty || breite <= 0) return null;
    final gesamt = widget.punkte.last.km;
    if (gesamt <= 0) return 0;
    final gesucht = (x / breite).clamp(0.0, 1.0) * gesamt;
    var besterIndex = 0;
    var besterAbstand = double.infinity;
    for (var i = 0; i < widget.punkte.length; i++) {
      final d = (widget.punkte[i].km - gesucht).abs();
      if (d < besterAbstand) {
        besterAbstand = d;
        besterIndex = i;
      }
    }
    return besterIndex;
  }

  void _zeigen(double x, double breite) {
    final i = _punktBei(x, breite);
    if (i == _stelle) return;
    setState(() => _stelle = i);
    widget.beiStelle?.call(i);
  }

  void _loslassen() {
    if (_stelle == null) return;
    setState(() => _stelle = null);
    widget.beiStelle?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final locale = Localizations.localeOf(context);
    final farben = Theme.of(context).colorScheme;
    if (widget.punkte.isEmpty) return const SizedBox.shrink();

    final zahl = NumberFormat.decimalPatternDigits(
        locale: locale.toString(), decimalDigits: 1);

    return Semantics(
      // `container: true`, damit die Beschreibung einen eigenen Knoten
      // bekommt: Ohne das ginge sie im nächsten Vorfahren auf, und ein
      // CustomPaint hat keinen, in dem sie sichtbar würde.
      container: true,
      label: widget.beschreibung,
      child: LayoutBuilder(
        builder: (context, platz) => MouseRegion(
          onHover: (e) => _zeigen(e.localPosition.dx, platz.maxWidth),
          onExit: (_) => _loslassen(),
          child: GestureDetector(
            onHorizontalDragUpdate: (d) =>
                _zeigen(d.localPosition.dx, platz.maxWidth),
            onHorizontalDragEnd: (_) => _loslassen(),
            onTapDown: (d) => _zeigen(d.localPosition.dx, platz.maxWidth),
            onTapUp: (_) => _loslassen(),
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(platz.maxWidth, widget.hoehe),
                  painter: _Profilmaler(
                    punkte: widget.punkte,
                    stelle: _stelle,
                    linie: farben.primary,
                    flaeche: farben.primary.withValues(alpha: 0.18),
                    raster: farben.outlineVariant,
                    marke: farben.error,
                  ),
                ),
                if (_stelle case final i?)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: farben.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        t.spurStelle(zahl.format(widget.punkte[i].km),
                            widget.punkte[i].hoehe.round()),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Profilmaler extends CustomPainter {
  final List<Profilpunkt> punkte;
  final int? stelle;
  final Color linie;
  final Color flaeche;
  final Color raster;
  final Color marke;

  _Profilmaler({
    required this.punkte,
    required this.stelle,
    required this.linie,
    required this.flaeche,
    required this.raster,
    required this.marke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (punkte.isEmpty) return;
    final gesamt = punkte.last.km;
    var tief = punkte.first.hoehe;
    var hoch = punkte.first.hoehe;
    for (final p in punkte) {
      tief = math.min(tief, p.hoehe);
      hoch = math.max(hoch, p.hoehe);
    }
    // **Nicht bei null anfangen.** Eine Wanderung zwischen 300 und 380 m
    // wäre über einer Nulllinie ein waagerechter Strich. Der Ausschnitt
    // ist der begangene Bereich; damit er nicht am Rand klebt, kommt
    // oben und unten ein Zehntel dazu – mindestens aber zehn Meter,
    // sonst blähte eine wirklich flache Runde ihre Wellen zu Bergen auf.
    final spanne = math.max(hoch - tief, 1.0);
    final luft = math.max(spanne * 0.1, 10.0);
    final unten = tief - luft;
    final oben = hoch + luft;

    double x(double km) => gesamt <= 0 ? 0 : km / gesamt * size.width;
    double y(double h) =>
        size.height - (h - unten) / (oben - unten) * size.height;

    final rasterStift = Paint()
      ..color = raster
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final yy = size.height * i / 4;
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), rasterStift);
    }

    final pfad = Path()..moveTo(x(punkte.first.km), y(punkte.first.hoehe));
    for (final p in punkte.skip(1)) {
      pfad.lineTo(x(p.km), y(p.hoehe));
    }
    final gefuellt = Path.from(pfad)
      ..lineTo(x(punkte.last.km), size.height)
      ..lineTo(x(punkte.first.km), size.height)
      ..close();
    canvas.drawPath(gefuellt, Paint()..color = flaeche);
    canvas.drawPath(
      pfad,
      Paint()
        ..color = linie
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    if (stelle case final i? when i >= 0 && i < punkte.length) {
      final xx = x(punkte[i].km);
      canvas.drawLine(
          Offset(xx, 0),
          Offset(xx, size.height),
          Paint()
            ..color = marke
            ..strokeWidth = 1);
      canvas.drawCircle(
          Offset(xx, y(punkte[i].hoehe)), 4, Paint()..color = marke);
    }

    _beschriftung(canvas, '${hoch.round()} m', const Offset(4, 2));
    _beschriftung(canvas, '${tief.round()} m', Offset(4, size.height - 16));
  }

  void _beschriftung(Canvas canvas, String text, Offset stelle) {
    final maler = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 10, color: linie)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    maler.paint(canvas, stelle);
  }

  @override
  bool shouldRepaint(_Profilmaler alt) =>
      alt.punkte != punkte || alt.stelle != stelle || alt.linie != linie;
}
