/// **Die Tafeln des Flugstils „Nah dran"** – Titel, Ziel und Foto.
///
/// Gemalt und nicht als Widgets, und zwar **am Bildschirm wie im Video
/// mit derselben Rechnung**. Beim Überblick gibt es beides doppelt:
/// Widgets am Bildschirm (`_Flugbild`, `_Abspann`), Malerei im Video.
/// Das hat seinen Grund – dort wurden die Tafeln nachträglich ins Video
/// geholt –, aber es heisst auch, dass jede Änderung zweimal gemacht und
/// zweimal geprüft werden muss. Hier sieht man am Bildschirm genau das,
/// was später im Video steht.
///
/// Alles ist an der kürzeren Bildkante bemessen und nichts in festen
/// Punkten: Dieselbe Tafel muss im Hochformat 1080 × 1920 so aussehen
/// wie in 1920 × 1080 und am Bildschirm im Fenster.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Eine Texttafel: eine grosse Zeile und darunter kleinere.
typedef Flugtafel = ({String titel, List<String> zeilen, double deckkraft});

/// Ein Foto als Tafel, mit der Zeile darunter.
typedef Fototafel = ({ui.Image bild, String? unterschrift, double deckkraft});

/// Wo die Texttafel beginnt: oben links, unter dem Bereich, den eine
/// Videoplattform im Hochformat mit ihrer eigenen Leiste belegt.
Offset texttafelEcke(Size size) {
  final e = math.min(size.width, size.height);
  final hochkant = size.height > size.width;
  return Offset(e * 0.05, size.height * (hochkant ? 0.11 : 0.06));
}

/// Der Rahmen der Fototafel – das Bild, ohne die Zeile darunter.
///
/// Im Hochformat oben in der Mitte und fast so breit wie das Bild, im
/// Querformat oben rechts und gut ein Drittel breit: Dort ist die Mitte
/// der Platz der Landschaft, und rechts oben steht das Foto auch im
/// Überblick.
Rect fototafelRahmen(Size size) {
  final e = math.min(size.width, size.height);
  final hochkant = size.height > size.width;
  final breite = hochkant ? size.width * 0.86 : size.width * 0.36;
  final hoehe = breite / 1.5;
  final oben = size.height * (hochkant ? 0.11 : 0.06);
  final links = hochkant
      ? (size.width - breite) / 2
      : size.width - breite - e * 0.05;
  return Rect.fromLTWH(links, oben, breite, hoehe);
}

/// Malt die Tafeln auf [canvas].
///
/// [schriftart] nur für Bildwerkzeuge (siehe `Gelaendemaler.schriftart`).
void maleFlugtafeln(
  Canvas canvas,
  Size size, {
  Flugtafel? text,
  Fototafel? foto,
  String? schriftart,
}) {
  if (size.isEmpty) return;
  if (foto != null && foto.deckkraft > 0.01) {
    _fotoMalen(canvas, size, foto, schriftart);
  }
  if (text != null && text.deckkraft > 0.01) {
    _textMalen(canvas, size, text, schriftart);
  }
}

ui.Paragraph _absatz(
  String text,
  double groesse,
  double breite, {
  required Color farbe,
  FontWeight gewicht = FontWeight.w500,
  String? schriftart,
  TextAlign ausrichtung = TextAlign.left,
}) {
  final bauer =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontFamily: schriftart,
            fontSize: groesse,
            fontWeight: gewicht,
            textAlign: ausrichtung,
            maxLines: 2,
            ellipsis: '…',
          ),
        )
        ..pushStyle(ui.TextStyle(color: farbe, height: 1.2))
        ..addText(text);
  return bauer.build()..layout(ui.ParagraphConstraints(width: breite));
}

/// Die Farbe des Tafelgrunds – fast schwarz und halb durchsichtig.
///
/// Die Tafel liegt über Himmel, Fels und Wiese; nur ein dunkler Grund
/// trägt weisse Schrift über all dem, und durchscheinend bleibt die
/// Landschaft darunter Teil des Bildes.
const Color _grund = Color(0xFF101418);

void _textMalen(Canvas canvas, Size size, Flugtafel t, String? schriftart) {
  final deck = t.deckkraft.clamp(0.0, 1.0);
  final e = math.min(size.width, size.height);
  final hochkant = size.height > size.width;
  final innen = e * 0.035;
  final hoechstens =
      (hochkant ? size.width * 0.84 : size.width * 0.42) - innen * 2;

  final titel = _absatz(
    t.titel,
    e * (hochkant ? 0.062 : 0.052),
    hoechstens,
    farbe: const Color(0xFFFFFFFF).withValues(alpha: deck),
    gewicht: FontWeight.w700,
    schriftart: schriftart,
  );
  final zeilen = [
    for (final z in t.zeilen)
      _absatz(
        z,
        e * (hochkant ? 0.036 : 0.03),
        hoechstens,
        farbe: const Color(0xFFFFFFFF).withValues(alpha: 0.88 * deck),
        schriftart: schriftart,
      ),
  ];

  // So breit wie die längste Zeile, nicht wie der erlaubte Platz: Eine
  // Tafel, die bei einem kurzen Namen bis zur Bildmitte reicht, ist ein
  // leerer Kasten.
  var breite = titel.longestLine;
  var hoehe = titel.height;
  for (final z in zeilen) {
    breite = math.max(breite, z.longestLine);
    hoehe += z.height;
  }
  final luft = zeilen.isEmpty ? 0.0 : e * 0.012;
  final ecke = texttafelEcke(size);
  final kasten = Rect.fromLTWH(
    ecke.dx,
    ecke.dy,
    breite + innen * 2,
    hoehe + luft + innen * 2,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(kasten, Radius.circular(e * 0.022)),
    Paint()..color = _grund.withValues(alpha: 0.62 * deck),
  );
  var y = kasten.top + innen;
  canvas.drawParagraph(titel, Offset(kasten.left + innen, y));
  y += titel.height + luft;
  for (final z in zeilen) {
    canvas.drawParagraph(z, Offset(kasten.left + innen, y));
    y += z.height;
  }
}

void _fotoMalen(Canvas canvas, Size size, Fototafel f, String? schriftart) {
  final deck = f.deckkraft.clamp(0.0, 1.0);
  final e = math.min(size.width, size.height);
  final rahmen = fototafelRahmen(size);
  final rand = e * 0.008;
  final unterschrift = f.unterschrift == null
      ? null
      : _absatz(
          f.unterschrift!,
          e * 0.026,
          rahmen.width - rand * 4,
          farbe: const Color(0xFFFFFFFF).withValues(alpha: 0.85 * deck),
          schriftart: schriftart,
        );
  final unten = unterschrift == null ? 0.0 : unterschrift.height + rand * 3;
  final kasten = Rect.fromLTRB(
    rahmen.left - rand,
    rahmen.top - rand,
    rahmen.right + rand,
    rahmen.bottom + rand + unten,
  );
  final radius = Radius.circular(e * 0.022);
  canvas.drawRRect(
    RRect.fromRectAndRadius(kasten, radius),
    Paint()..color = _grund.withValues(alpha: 0.75 * deck),
  );

  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(rahmen, Radius.circular(e * 0.016)));
  // `cover`: Ein Foto ist selten 3:2, und verzerrt sähe es aus wie ein
  // Fehler.
  final quelle = _fuellend(
    f.bild.width.toDouble(),
    f.bild.height.toDouble(),
    rahmen,
  );
  canvas.drawImageRect(
    f.bild,
    quelle,
    rahmen,
    Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: deck)
      ..filterQuality = FilterQuality.medium,
  );
  canvas.restore();

  if (unterschrift != null) {
    canvas.drawParagraph(
      unterschrift,
      Offset(rahmen.left + rand, rahmen.bottom + rand * 2),
    );
  }
}

/// Der Ausschnitt aus dem Bild, der [ziel] ohne Verzerrung ausfüllt.
Rect _fuellend(double b, double h, Rect ziel) {
  if (b <= 0 || h <= 0) return Rect.fromLTWH(0, 0, b, h);
  final quell = b / h;
  final soll = ziel.width / ziel.height;
  if (quell > soll) {
    final neu = h * soll;
    return Rect.fromLTWH((b - neu) / 2, 0, neu, h);
  }
  final neu = b / soll;
  return Rect.fromLTWH(0, (h - neu) / 2, b, neu);
}
