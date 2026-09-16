/// Die Tafel zum Aufhängen: der Fächer als PDF.
///
/// Der einzige Punkt im Stammbaum, an dem das Ergebnis das Programm
/// verlässt und auf Papier weiterlebt.
///
/// Gezeichnet wird mit **derselben** Routine wie auf dem Bildschirm, nur
/// auf eine sehr viel größere Leinwand; das fertige Bild wandert in die
/// Seite. Den Fächer ein zweites Mal mit den Zeichenbefehlen der
/// PDF-Bibliothek zu bauen hätte zwei Darstellungen ergeben, die
/// auseinanderlaufen können – und die Abweichung fiele erst auf dem
/// gedruckten Blatt auf.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/database.dart';
import '../theme/zierbaum_farben.dart';
import '../widgets/faecher_ansicht.dart';
import '../widgets/zierbaum_maler.dart';
import 'faechertafel.dart';
import 'stammbaum.dart';
import 'zierbaum.dart';

const tafelEndung = '.pdf';
const tafelEndungOhnePunkt = 'pdf';
const tafelDateiname = 'stammbaum-tafel$tafelEndung';
const zierbaumDateiname = 'stammbaum-zierbaum$tafelEndung';

String mitTafelEndung(String pfad) =>
    pfad.toLowerCase().endsWith(tafelEndung) ? pfad : '$pfad$tafelEndung';

/// Kantenlänge der gerenderten Zeichnung in Pixeln.
///
/// 2400 Pixel auf einer A3-Breite ergeben rund 200 dpi – genug, dass die
/// Namen auf einem Meter Abstand sauber stehen, und klein genug, dass die
/// Datei ein paar Megabyte bleibt. Die Zeichnung entsteht in einem Zug im
/// Speicher; ein größerer Wert kostet quadratisch.
const _tafelPixel = 2400;

/// Baut das PDF und gibt seine Bytes zurück.
///
/// [farben] kommt aus dem laufenden Thema. Für den Druck wird daraus
/// bewusst die **helle** Fassung genommen: Eine Tafel auf schwarzem Grund
/// verbraucht eine Tonerkassette und liest sich an der Wand schlechter.
Future<Uint8List> baueTafelPdf({
  required List<Fachplatz> plaetze,
  required Map<String, PersonData> personen,
  required String titel,
  required ColorScheme farben,
  required TextDirection textRichtung,
}) async {
  final bild = await _zeichneFaecher(
    plaetze: plaetze,
    personen: personen,
    titel: titel,
    farben: _druckfarben(farben),
    textRichtung: textRichtung,
  );
  final png = await bild.toByteData(format: ui.ImageByteFormat.png);
  bild.dispose();

  final dokument = pw.Document();
  final grafik = pw.MemoryImage(png!.buffer.asUint8List());
  dokument.addPage(
    pw.Page(
      // Querformat: Ein Fächer ist doppelt so breit wie hoch.
      pageFormat: PdfPageFormat.a3.landscape,
      // Die Seite enthält nur das Bild – auch die Überschrift steckt
      // darin. Grund ist die Schrift: Die eingebauten PDF-Schriften
      // können kein Unicode („Helvetica has no Unicode support“), ein
      // Name wie „Müller“ käme zerstört heraus. Flutters Textsatz kann
      // es, also wird auch die Überschrift dort gezeichnet – und
      // nebenbei bleibt es bei einer einzigen Zeichenroutine.
      build: (kontext) => pw.Center(child: pw.Image(grafik)),
    ),
  );
  return dokument.save();
}

/// Ein helles Farbschema für den Druck, abgeleitet aus dem der App.
///
/// Nicht einfach `buildLightTheme()` benutzt: Diese Datei soll nichts vom
/// Aufbau der Oberfläche wissen müssen, und für eine Tafel genügen
/// Schwarz auf Weiß mit einem Akzent für die Person in der Mitte.
ColorScheme _druckfarben(ColorScheme vorlage) => ColorScheme.fromSeed(
      seedColor: vorlage.primary,
      brightness: Brightness.light,
    );

Future<ui.Image> _zeichneFaecher({
  required List<Fachplatz> plaetze,
  required Map<String, PersonData> personen,
  required String titel,
  required ColorScheme farben,
  required TextDirection textRichtung,
}) async {
  const breite = _tafelPixel * 1.0;
  const kopfhoehe = 140.0;
  // Ein Halbkreis ist halb so hoch wie breit; dazu der Kopfbereich und
  // etwas Luft für die Beschriftung am äußeren Rand.
  const hoehe = breite / 2 + kopfhoehe + 40;
  final ringe = plaetze.fold(0, (m, p) => p.ring > m ? p.ring : m);
  const radius = breite / 2 - 20;
  final ringBreite = radius / (ringe + 1);
  const mitte = Offset(breite / 2, hoehe - 20);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, breite, hoehe));
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, breite, hoehe),
    Paint()..color = farben.surface,
  );
  final ueberschrift = TextPainter(
    text: TextSpan(
      text: titel,
      style: TextStyle(color: farben.onSurface, fontSize: 64),
    ),
    textAlign: TextAlign.center,
    textDirection: textRichtung,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: breite - 80);
  ueberschrift.paint(
      canvas, Offset((breite - ueberschrift.width) / 2, kopfhoehe / 2 - 32));
  ueberschrift.dispose();

  maleFaecher(
    canvas: canvas,
    plaetze: plaetze,
    personen: personen,
    mitte: mitte,
    ringBreite: ringBreite,
    farben: farben,
    textRichtung: textRichtung,
    schriftFaktor: ringBreite / 90,
  );
  final aufzeichnung = recorder.endRecording();
  try {
    return await aufzeichnung.toImage(breite.round(), hoehe.round());
  } finally {
    // Die Aufzeichnung hält alle Zeichenbefehle der 2400-Pixel-Tafel im
    // Speicher der Grafikschicht. Nach dem Ausrastern wird sie nicht mehr
    // gebraucht.
    aufzeichnung.dispose();
  }
}

/// Wie viele Punkte der Zierbaum für die Tafel bekommt.
///
/// Der Baum auf dem Bildschirm ist rund tausend Punkte breit; drei
/// Bildpunkte je Punkt ergeben auf A3 rund 200 dpi – dieselbe Rechnung
/// wie beim Fächer.
const zierbaumTafelFaktor = 3.0;

/// Der Zierbaum als PDF – die zweite Tafel zum Aufhängen.
///
/// **Dieselbe Zeichenroutine wie auf dem Bildschirm**, nur auf einer
/// dreifach so grossen Leinwand: [ZierbaumMaler] malt Grund, Stamm, Äste
/// und Ranken hier wie dort. Was hinzukommt, sind die Schilder – auf dem
/// Bildschirm sind sie Widgets (damit Antippen, Menü und Sprachausgabe
/// funktionieren), auf dem Blatt gibt es nichts anzutippen. Beide lesen
/// dieselben [Schildmasse].
///
/// **Ohne Porträts**, wie auf jeder gedruckten Ahnentafel. Das ist nicht
/// nur Geschmack: Ein Bild müsste erst geladen werden, und eine
/// Zeichnung wartet auf nichts.
Future<Uint8List> baueZierbaumPdf({
  required Stammbaumgeflecht geflecht,
  required Schildbeschriftung beschriftung,
  required String? familienname,
  required Zierbaumfarben farben,
  required TextDirection textRichtung,
}) async {
  final masse = const Zierbaummasse().mal(zierbaumTafelFaktor);
  final plan = zierbaumplan(geflecht, masse: masse);

  final recorder = ui.PictureRecorder();
  final flaeche = Rect.fromLTWH(0, 0, plan.breite, plan.hoehe);
  final canvas = Canvas(recorder, flaeche);
  ZierbaumMaler(
    plan: plan,
    farben: farben,
    beschriftung: beschriftung,
    familienname: familienname,
    fokusId: geflecht.fokus,
    schildmasse: const Schildmasse().mal(zierbaumTafelFaktor),
    textRichtung: textRichtung,
  ).paint(canvas, Size(plan.breite, plan.hoehe));

  final bild = await recorder
      .endRecording()
      .toImage(plan.breite.round(), plan.hoehe.round());
  final png = await bild.toByteData(format: ui.ImageByteFormat.png);
  bild.dispose();

  final dokument = pw.Document();
  final grafik = pw.MemoryImage(png!.buffer.asUint8List());
  dokument.addPage(
    pw.Page(
      // Hoch oder quer, je nachdem, wie die Familie gewachsen ist. Eine
      // feste Ausrichtung liesse den Baum in einem der beiden Fälle als
      // Briefmarke auf dem Blatt stehen.
      pageFormat: plan.breite >= plan.hoehe
          ? PdfPageFormat.a3.landscape
          : PdfPageFormat.a3,
      // Mit Rand und mittig: Ohne ihn stünde neben dem Bild ein weisser
      // Streifen, weil das Seitenverhältnis eines Baums selten das eines
      // Blattes ist – und ein Streifen an einer Kante sieht aus wie ein
      // Fehler, während ein Rand ringsum wie ein Rand aussieht.
      build: (kontext) => pw.Center(child: pw.Image(grafik)),
    ),
  );
  return dokument.save();
}
