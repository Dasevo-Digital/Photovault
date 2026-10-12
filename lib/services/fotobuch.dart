/// Das Fotobuch: eine Auswahl als druckfertiges PDF.
///
/// Ein, zwei oder vier Bilder je Seite, jedes in der Auflösung, die es auf
/// dem Papier braucht (300 dpi), mit einer Bildunterschrift darunter. Ohne
/// Oberfläche und ohne Datenbank: Die Seiten werden aus den Seitenverhält-
/// nissen geplant, bevor ein einziges Bild geladen ist – erst danach weiss
/// man, wie gross jedes gerechnet werden muss.
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Das Dateiformat des Fotobuchs – als Kürzel. Hier und nicht im
/// Bedienbaustein, aus demselben Grund wie beim Kontaktblatt: Eine
/// Dateiendung ist kein Oberflächentext.
const fotobuchFormatKuerzel = 'pdf';

/// Die Druckauflösung.
const fotobuchDpi = 300;

/// Höchstens so viele Fotos je Fotobuch. Das PDF entsteht im Speicher,
/// und bei einem Bild je Seite trägt jedes rund zwei Megabyte.
const fotobuchHoechstensBilder = 250;

/// Wie viele Bilder auf einer Seite stehen können.
const fotobuchBilderJeSeite = [1, 2, 4];

/// Die Seitenformate.
enum Fotobuchformat {
  a4Hoch,
  a4Quer,

  /// 21 × 21 cm, das übliche Mass gebundener Fotobücher.
  quadrat;

  PdfPageFormat get seite => switch (this) {
    Fotobuchformat.a4Hoch => PdfPageFormat.a4,
    Fotobuchformat.a4Quer => PdfPageFormat.a4.landscape,
    Fotobuchformat.quadrat => const PdfPageFormat(
      21 * PdfPageFormat.cm,
      21 * PdfPageFormat.cm,
    ),
  };
}

/// Rand der Seite, Lücke zwischen zwei Bildern, Schrift der Unterschrift.
const _rand = 12 * PdfPageFormat.mm;
const _luecke = 6 * PdfPageFormat.mm;
const _schrift = 9.0;

/// Platz unter einem Bild für zwei Zeilen Unterschrift.
const fotobuchUnterschriftHoehe = _schrift * 1.3 * 2 + 2 * PdfPageFormat.mm;

/// Ein Rechteck in Punkten, von links oben in der beschreibbaren Fläche.
typedef Fotobuchzelle = ({
  double links,
  double oben,
  double breite,
  double hoehe,
});

/// Eine geplante Seite: welche Bilder (Nummern in der Eingabe) in welchen
/// Zellen stehen.
@immutable
class Fotobuchseite {
  final List<int> bilder;
  final List<Fotobuchzelle> zellen;
  const Fotobuchseite(this.bilder, this.zellen);
}

/// Wo ein Bild in seiner Zelle steht: so gross wie möglich, ohne
/// Beschnitt, über der Unterschrift und waagerecht mittig.
Fotobuchzelle fotobuchBildIn(
  Fotobuchzelle zelle,
  double verhaeltnis, {
  required bool mitUnterschrift,
}) {
  final verfuegbar =
      zelle.hoehe - (mitUnterschrift ? fotobuchUnterschriftHoehe : 0);
  final (b, h) = verhaeltnis > zelle.breite / verfuegbar
      ? (zelle.breite, zelle.breite / verhaeltnis)
      : (verfuegbar * verhaeltnis, verfuegbar);
  // Bild und Unterschrift zusammen mittig in der Zelle: Steht ein
  // Querformat neben einem Hochformat, schwebt es sonst oben.
  final block = h + (mitUnterschrift ? fotobuchUnterschriftHoehe : 0);
  return (
    links: zelle.links + (zelle.breite - b) / 2,
    oben: zelle.oben + (zelle.hoehe - block) / 2,
    breite: b,
    hoehe: h,
  );
}

/// Die Zellen einer Seite für Bilder mit den Seitenverhältnissen
/// [verhaeltnisse] (Breite durch Höhe) auf einer Fläche von [breite] mal
/// [hoehe] Punkten.
///
/// **Das Raster richtet sich nach den Bildern.** Zwei Querformate stehen
/// auf einer hohen Seite übereinander, zwei Hochformate nebeneinander.
/// Gewählt wird unter allen Rastern, in die die Bilder passen – höchstens
/// eine Reihe unvollständig –, das, in dem sie zusammen am meisten Fläche
/// bekommen. Bei gleicher Fläche das mit weniger leeren Zellen.
List<Fotobuchzelle> fotobuchZellen(
  List<double> verhaeltnisse, {
  required double breite,
  required double hoehe,
  required bool mitUnterschrift,
}) {
  final n = verhaeltnisse.length;
  List<Fotobuchzelle>? beste;
  var besteFlaeche = -1.0;
  var besteLeere = 0;
  for (var spalten = 1; spalten <= n; spalten++) {
    final zeilen = (n + spalten - 1) ~/ spalten;
    final leer = zeilen * spalten - n;
    if (leer >= spalten) continue;
    final zb = (breite - (spalten - 1) * _luecke) / spalten;
    final zh = (hoehe - (zeilen - 1) * _luecke) / zeilen;
    if (zb <= 0 || zh <= fotobuchUnterschriftHoehe) continue;
    final zellen = <Fotobuchzelle>[
      for (var i = 0; i < n; i++)
        (
          links: (i % spalten) * (zb + _luecke),
          oben: (i ~/ spalten) * (zh + _luecke),
          breite: zb,
          hoehe: zh,
        ),
    ];
    var flaeche = 0.0;
    for (var i = 0; i < n; i++) {
      final b = fotobuchBildIn(
        zellen[i],
        verhaeltnisse[i],
        mitUnterschrift: mitUnterschrift,
      );
      flaeche += b.breite * b.hoehe;
    }
    final besser =
        flaeche > besteFlaeche * (1 + 1e-9) ||
        (flaeche >= besteFlaeche * (1 - 1e-9) && leer < besteLeere);
    if (beste == null || besser) {
      beste = zellen;
      besteFlaeche = flaeche;
      besteLeere = leer;
    }
  }
  return beste!;
}

/// Plant das ganze Buch: [jeSeite] Bilder je Seite, in der gegebenen
/// Reihenfolge.
List<Fotobuchseite> fotobuchPlan(
  List<double> verhaeltnisse, {
  required Fotobuchformat format,
  required int jeSeite,
  required bool mitUnterschrift,
}) {
  final (breite, hoehe) = fotobuchFlaeche(format);
  return [
    for (var von = 0; von < verhaeltnisse.length; von += jeSeite)
      () {
        final bilder = [
          for (
            var i = von;
            i < math.min(von + jeSeite, verhaeltnisse.length);
            i++
          )
            i,
        ];
        return Fotobuchseite(
          bilder,
          fotobuchZellen(
            [for (final i in bilder) verhaeltnisse[i]],
            breite: breite,
            hoehe: hoehe,
            mitUnterschrift: mitUnterschrift,
          ),
        );
      }(),
  ];
}

/// Die beschreibbare Fläche einer Seite in Punkten.
(double, double) fotobuchFlaeche(Fotobuchformat format) =>
    (format.seite.width - 2 * _rand, format.seite.height - 2 * _rand);

/// Wie viele Pixel die längere Kante eines Bildes braucht, das im Druck
/// [zelle] füllt – bei [fotobuchDpi].
int fotobuchPixel(Fotobuchzelle bild) =>
    (math.max(bild.breite, bild.hoehe) / PdfPageFormat.inch * fotobuchDpi)
        .ceil();

/// Ein geladenes Bild für das Buch.
@immutable
class Fotobuchbild {
  final Uint8List jpeg;
  final int breite;
  final int hoehe;
  final String unterschrift;

  const Fotobuchbild({
    required this.jpeg,
    required this.breite,
    required this.hoehe,
    this.unterschrift = '',
  });

  double get verhaeltnis => breite / hoehe;
}

/// Baut das PDF – in einem eigenen Isolate, denn ein Buch aus zweihundert
/// Bildern ist ein paar hundert Megabyte, die zusammengesetzt werden.
///
/// [schrift] ist eine TrueType-Datei für die Unterschriften und den Titel:
/// Die Standardschriften im PDF kennen nur westeuropäische Zeichen, und
/// ein Name mit „ł" oder „ș" stünde dort als Kästchen.
Future<Uint8List> baueFotobuch({
  required List<Fotobuchbild> bilder,
  required List<Fotobuchseite> seiten,
  required Fotobuchformat format,
  required bool mitUnterschrift,
  required ByteData schrift,
  String? titel,
  String? untertitel,
}) => Isolate.run(
  () => _baue(
    bilder: bilder,
    seiten: seiten,
    format: format,
    mitUnterschrift: mitUnterschrift,
    schrift: schrift,
    titel: titel,
    untertitel: untertitel,
  ),
);

Future<Uint8List> _baue({
  required List<Fotobuchbild> bilder,
  required List<Fotobuchseite> seiten,
  required Fotobuchformat format,
  required bool mitUnterschrift,
  required ByteData schrift,
  String? titel,
  String? untertitel,
}) async {
  final font = pw.Font.ttf(schrift);
  final dokument = pw.Document(title: titel);
  final seite = format.seite.copyWith(
    marginLeft: _rand,
    marginRight: _rand,
    marginTop: _rand,
    marginBottom: _rand,
  );

  if (titel != null && titel.trim().isNotEmpty) {
    dokument.addPage(
      pw.Page(
        pageFormat: seite,
        build: (_) => pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                titel.trim(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: font, fontSize: 30),
              ),
              if (untertitel != null && untertitel.trim().isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Text(
                  untertitel.trim(),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 14,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  for (final s in seiten) {
    final kinder = <pw.Widget>[];
    for (final (k, i) in s.bilder.indexed) {
      final b = bilder[i];
      final zelle = s.zellen[k];
      final platz = fotobuchBildIn(
        zelle,
        b.verhaeltnis,
        mitUnterschrift: mitUnterschrift,
      );
      kinder.add(
        pw.Positioned(
          left: platz.links,
          top: platz.oben,
          child: pw.SizedBox(
            width: platz.breite,
            height: platz.hoehe,
            child: pw.Image(pw.MemoryImage(b.jpeg), fit: pw.BoxFit.fill),
          ),
        ),
      );
      if (mitUnterschrift && b.unterschrift.isNotEmpty) {
        kinder.add(
          pw.Positioned(
            left: zelle.links,
            top: platz.oben + platz.hoehe + PdfPageFormat.mm,
            child: pw.SizedBox(
              width: zelle.breite,
              child: pw.Text(
                b.unterschrift,
                textAlign: pw.TextAlign.center,
                maxLines: 2,
                style: pw.TextStyle(
                  font: font,
                  fontSize: _schrift,
                  color: PdfColors.grey800,
                ),
              ),
            ),
          ),
        );
      }
    }
    dokument.addPage(
      pw.Page(
        pageFormat: seite,
        build: (_) => pw.Stack(
          children: [
            pw.SizedBox(
              width: seite.availableWidth,
              height: seite.availableHeight,
            ),
            ...kinder,
          ],
        ),
      ),
    );
  }
  return dokument.save();
}

/// Breite und Höhe eines JPEG aus seinem Bildkopf, ohne es zu dekodieren.
/// `null`, wenn es keines ist.
(int, int)? jpegGroesse(Uint8List daten) {
  if (daten.length < 4 || daten[0] != 0xFF || daten[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < daten.length) {
    if (daten[i] != 0xFF) return null;
    final marke = daten[i + 1];
    if (marke == 0xFF) {
      i++;
      continue;
    }
    final laenge = (daten[i + 2] << 8) | daten[i + 3];
    // SOF0 bis SOF15, ohne DHT (C4), JPG (C8) und DAC (CC).
    if (marke >= 0xC0 &&
        marke <= 0xCF &&
        marke != 0xC4 &&
        marke != 0xC8 &&
        marke != 0xCC) {
      final hoehe = (daten[i + 5] << 8) | daten[i + 6];
      final breite = (daten[i + 7] << 8) | daten[i + 8];
      if (breite == 0 || hoehe == 0) return null;
      return (breite, hoehe);
    }
    i += 2 + laenge;
  }
  return null;
}

/// Das JPEG ohne Beipackzettel: EXIF und XMP (APP1) und IPTC (APP13)
/// fallen weg, das Farbprofil (APP2) und alles Übrige bleibt.
///
/// Ohne Neukodieren, also ohne Qualitätsverlust. Ein Fotobuch ist ein
/// Blatt, das man weitergibt; aus einem eingebetteten JPEG liessen sich
/// sonst Kamera, Zeit und Aufnahmeort herauslesen – derselbe Fund wie
/// beim Kontaktblatt.
Uint8List jpegOhneBeipackzettel(Uint8List daten) {
  if (daten.length < 4 || daten[0] != 0xFF || daten[1] != 0xD8) return daten;
  final aus = BytesBuilder(copy: false)..add(daten.sublist(0, 2));
  var i = 2;
  while (i + 4 <= daten.length) {
    if (daten[i] != 0xFF) break;
    final marke = daten[i + 1];
    // Ab Start of Scan folgen die Bilddaten – der Rest unverändert.
    if (marke == 0xDA) break;
    final laenge = (daten[i + 2] << 8) | daten[i + 3];
    final ende = i + 2 + laenge;
    if (ende > daten.length) break;
    if (marke != 0xE1 && marke != 0xED) {
      aus.add(Uint8List.sublistView(daten, i, ende));
    }
    i = ende;
  }
  aus.add(Uint8List.sublistView(daten, i));
  return aus.toBytes();
}

/// Die Schrift der Titelseite und der Unterschriften – dieselbe wie auf
/// dem Zierbaum. EB Garamond setzt Latein, Griechisch und Kyrillisch.
const fotobuchSchriftDatei = 'assets/fonts/EBGaramond-Variable.ttf';

/// Was unter einem Bild stehen kann.
enum Fotobuchangabe { datum, ort, personen, beschreibung }

/// Die Unterschrift eines Bildes aus den gewählten Angaben, in der
/// Reihenfolge Datum, Ort, Personen, Beschreibung. Leere Angaben fallen
/// weg, Personen stehen von links nach rechts, wie im Bild.
String fotobuchUnterschrift({
  String? datum,
  String? ort,
  List<String> personen = const [],
  String? beschreibung,
}) =>
    [
          datum,
          ort,
          if (personen.isNotEmpty) {...personen}.join(', '),
          beschreibung,
        ]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' · ');
