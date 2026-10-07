import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../services/lebensbaum_bild.dart';
import '../services/lebensbaum_vorlage.dart';
import '../theme/zierbaum_farben.dart'
    show zierschrift, zierschriftGross, zierGewicht;

/// Was auf einem Schild steht. [bezeichnung] ist die Verwandtschaft zur
/// Person am Stamm („Großmutter“) – ohne gezeichnete Äste sagt sie, wie
/// die Schilder zusammengehören.
typedef Lebensbaumschild = ({
  String name,
  String? lebensspanne,
  String? bezeichnung,
});

/// Schreibt die Namen in die Schilder eines [Lebensbaumbild]s.
///
/// Bild und gesetzte Schilder malt er nur, wenn sie ihm übergeben werden
/// ([bild], [schild]) – auf dem Bildschirm liegen sie als eigene Widgets
/// darunter und werden von Flutter geladen und zwischengespeichert, für
/// die Tafel gibt es keine Widgets.
class LebensbaumMaler extends CustomPainter {
  final Lebensbaumbild inhalt;
  final Lebensbaumschild Function(String personId) beschriftung;
  final String titel;
  final String? untertitel;
  final ui.Image? bild;
  final ui.Image? schild;
  final TextDirection textRichtung;

  /// Für wen es ein Porträt gibt. Die Schrift rückt dann darunter.
  ///
  /// Eine Menge statt einer Prüffunktion: Die Ansicht legt sie bei jedem
  /// Aufbau neu an, und zwei gleiche Mengen sollen keinen Neuanstrich
  /// auslösen.
  final Set<String>? mitPortrait;

  /// Die Porträts selbst – nur für die Tafel. Auf dem Bildschirm liegen
  /// sie als Widgets darüber.
  final Map<String, ui.Image>? portraits;

  LebensbaumMaler({
    required this.inhalt,
    required this.beschriftung,
    required this.titel,
    this.untertitel,
    this.bild,
    this.schild,
    this.textRichtung = TextDirection.ltr,
    this.mitPortrait,
    this.portraits,
  });

  Lebensbaumvorlage get vorlage => inhalt.vorlage;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / vorlage.groesse.width,
      size.height / vorlage.groesse.height,
    );
    final bild = this.bild;
    if (bild != null) {
      canvas.drawImageRect(
        bild,
        Rect.fromLTWH(0, 0, bild.width.toDouble(), bild.height.toDouble()),
        Offset.zero & vorlage.groesse,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    final schild = this.schild;
    for (final p in inhalt.plaetze) {
      if (schild != null && p.zuSetzen) {
        canvas.drawImageRect(
          schild,
          Rect.fromLTWH(
            0,
            0,
            schild.width.toDouble(),
            schild.height.toDouble(),
          ),
          p.rahmen,
          Paint()..filterQuality = FilterQuality.high,
        );
      }
      final mitPortrait = this.mitPortrait;
      final schrift = mitPortrait == null
          ? p.schrift
          : schriftUnterPortraits(p, mitPortrait.contains);
      _beschrifte(canvas, schrift, [
        for (final id in p.personen) beschriftung(id),
      ], amStamm: p.amStamm);
    }
    final portraits = this.portraits;
    if (portraits != null) {
      for (final p in inhalt.plaetze) {
        for (final (kreis, id) in portraitKreise(p, portraits.containsKey)) {
          _portrait(canvas, kreis, portraits[id]!);
        }
      }
    }
    _titel(canvas);
    canvas.restore();
  }

  /// Ein Porträt im Kreis, mit schmalem Rand in der Farbe der Schrift.
  void _portrait(Canvas canvas, Rect kreis, ui.Image bild) {
    final seite = math.min(bild.width, bild.height).toDouble();
    final quelle = Rect.fromCenter(
      center: Offset(bild.width / 2, bild.height / 2),
      width: seite,
      height: seite,
    );
    canvas
      ..save()
      ..clipPath(Path()..addOval(kreis))
      ..drawImageRect(
        bild,
        quelle,
        kreis,
        Paint()..filterQuality = FilterQuality.high,
      )
      ..restore()
      ..drawOval(
        kreis,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = kreis.width * 0.04
          ..color = vorlage.nebenschrift,
      );
  }

  /// Setzt die Schrift so gross, wie das Schild sie fasst.
  ///
  /// Die Schilder sind verschieden gross, und ein Name ist länger als der
  /// andere. Begonnen wird mit einer Grösse nach der Höhe des Schildes; so
  /// lange es nicht passt, wird sie kleiner. Würde sie dabei unleserlich,
  /// fällt erst die Verwandtschaft weg, dann die Lebensdaten – der Name
  /// bleibt.
  void _beschrifte(
    Canvas canvas,
    Rect r,
    List<Lebensbaumschild> leute, {
    bool amStamm = false,
  }) {
    if (leute.isEmpty) return;
    const lesbar = 6.5;
    for (var stufe = 0; stufe < 3; stufe++) {
      // Am Stamm braucht niemand eine Bezeichnung: Um diese Person geht es.
      if (stufe == 0 && amStamm) continue;
      final mitBezeichnung = stufe == 0;
      final mitSpanne = stufe < 2;
      final start = r.height / (leute.length * 2 + 0.6) * 1.1;
      for (var groesse = start; groesse >= 3; groesse *= 0.93) {
        if (stufe < 2 && groesse < lesbar) break;
        final text = _block(leute, groesse, mitBezeichnung, mitSpanne)
          ..layout(maxWidth: r.width);
        final passt =
            text.height <= r.height &&
            !text.didExceedMaxLines &&
            _woerterPassen(leute, groesse, r.width);
        if (passt) {
          text.paint(
            canvas,
            Offset(r.center.dx - text.width / 2, r.center.dy - text.height / 2),
          );
        }
        text.dispose();
        if (passt) return;
      }
    }
  }

  TextPainter _block(
    List<Lebensbaumschild> leute,
    double groesse,
    bool mitBezeichnung,
    bool mitSpanne,
  ) {
    final teile = <InlineSpan>[];
    var zeilen = 0;
    void zeile(String text, TextStyle stil, {int umbruch = 1}) {
      if (teile.isNotEmpty) teile.add(const TextSpan(text: '\n'));
      teile.add(TextSpan(text: text, style: stil));
      zeilen += umbruch;
    }

    final klein = TextStyle(
      fontFamily: zierschrift,
      fontSize: groesse * 0.74,
      height: 1.1,
      color: vorlage.nebenschrift,
    );
    for (final (n, l) in leute.indexed) {
      if (n > 0) zeile('&', klein);
      if (mitBezeichnung && l.bezeichnung != null) {
        zeile(l.bezeichnung!, klein.copyWith(fontStyle: FontStyle.italic));
      }
      // Ein Name darf über zwei Zeilen gehen.
      zeile(
        l.name,
        TextStyle(
          fontFamily: zierschrift,
          fontVariations: zierGewicht(620),
          fontSize: groesse,
          height: 1.05,
          color: vorlage.schrift,
        ),
        umbruch: 2,
      );
      if (mitSpanne && l.lebensspanne != null) zeile(l.lebensspanne!, klein);
    }
    return TextPainter(
      text: TextSpan(children: teile),
      textAlign: TextAlign.center,
      textDirection: textRichtung,
      maxLines: zeilen,
    );
  }

  /// Ob jedes Wort der Namen auf eine Zeile passt. Sonst bräche Flutter
  /// mitten im Wort um.
  bool _woerterPassen(
    List<Lebensbaumschild> leute,
    double groesse,
    double breite,
  ) {
    for (final l in leute) {
      for (final wort in l.name.split(' ')) {
        final t = TextPainter(
          text: TextSpan(
            text: wort,
            style: TextStyle(
              fontFamily: zierschrift,
              fontVariations: zierGewicht(620),
              fontSize: groesse,
            ),
          ),
          textDirection: textRichtung,
        )..layout();
        final passt = t.width <= breite;
        t.dispose();
        if (!passt) return false;
      }
    }
    return true;
  }

  void _titel(Canvas canvas) {
    final r = vorlage.titel;
    var groesse = r.height * 0.8;
    late TextPainter text;
    while (true) {
      text = TextPainter(
        text: TextSpan(
          text: titel,
          style: TextStyle(
            fontFamily: zierschriftGross,
            fontSize: groesse,
            wordSpacing: groesse * 0.15,
            color: vorlage.schrift,
          ),
        ),
        textDirection: textRichtung,
        maxLines: 1,
      )..layout();
      if (text.width <= r.width || groesse < 6) break;
      text.dispose();
      groesse *= 0.92;
    }
    text.paint(
      canvas,
      Offset(r.center.dx - text.width / 2, r.center.dy - text.height / 2),
    );
    text.dispose();

    final untertitel = this.untertitel;
    final unten = vorlage.untertitel;
    if (untertitel == null || unten == null) return;
    final zeile = TextPainter(
      text: TextSpan(
        text: untertitel,
        style: TextStyle(
          fontFamily: zierschrift,
          fontStyle: FontStyle.italic,
          fontSize: math.min(unten.height * 0.6, groesse * 0.42),
          color: vorlage.nebenschrift,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: textRichtung,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: unten.width);
    zeile.paint(canvas, Offset(unten.center.dx - zeile.width / 2, unten.top));
    zeile.dispose();
  }

  @override
  bool shouldRepaint(LebensbaumMaler alt) =>
      alt.inhalt != inhalt ||
      alt.schild != schild ||
      alt.beschriftung != beschriftung ||
      alt.titel != titel ||
      alt.untertitel != untertitel ||
      alt.bild != bild ||
      alt.textRichtung != textRichtung ||
      !setEquals(alt.mitPortrait, mitPortrait) ||
      alt.portraits != portraits;
}
