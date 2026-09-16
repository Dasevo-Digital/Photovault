import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, debugPrint, visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../widgets/develop_preview.dart';
import 'develop_color.dart';
import 'native_image_converter.dart';

/// Rendert die Entwickeln-Anpassungen über den Shader in fertige
/// JPEG-Bytes – der maßgebliche Renderpfad überall dort, wo es kein Core
/// Image gibt (siehe docs/plan_linux.md, Phase 3).
///
/// Bis hierher war der Shader nur für die Live-Vorschau da: Man zog am
/// Regler, sah die Wirkung, und beim Speichern übernahm der native Pfad.
/// Unter Linux gibt es den nicht – die Regler wirkten dort auf gar nichts.
/// Dieselbe Rechnung, die schon die Vorschau zeichnet, schreibt hier das
/// Ergebnis.
///
/// **Was dabei gleich bleibt:** Kurve und Farbmischer kommen aus denselben
/// Nachschlagetabellen wie auf macOS (`develop_color.dart`) – nur eben mit
/// der vollen Kantenlänge [colorCubeSize] statt der gröberen der Vorschau.
///
/// **Was fehlt:** Schärfe und Rauschunterdrückung. Beide brauchen
/// Nachbarpixel, die ein Fragment-Shader so nicht sieht; sie bleiben
/// vorerst wirkungslos, statt genähert zu werden. [fehlendeWerkzeuge] sagt
/// für gegebene Anpassungen, was davon betroffen ist – die Oberfläche kann
/// das anzeigen, statt den Nutzer im Glauben zu lassen, er habe geschärft.
class DevelopRender {
  DevelopRender._();

  /// Ob dieser Weg auf der laufenden Plattform überhaupt gebraucht wird.
  ///
  /// Auf macOS bleibt Core Image maßgeblich: Bei RAW wirken die Regler dort
  /// auf den Rohdaten (beim Demosaicing), was deutlich mehr Spielraum hat
  /// als eine Korrektur am fertigen Bild.
  static bool get istMassgeblich => !Platform.isMacOS;

  /// Regler, die dieser Weg nicht umsetzt – unabhängig davon, ob sie
  /// gerade gesetzt sind.
  ///
  /// Schärfe und Rauschunterdrückung brauchen Nachbarpixel, die ein
  /// Fragment-Shader so nicht sieht; Klarheit und Vignettierung sind reine
  /// Core-Image-Filter. Sie zu nähern wäre schlechter, als sie zu benennen:
  /// Ein Regler, der sich bewegen lässt und nichts tut, ist die
  /// unangenehmste Art von Fehler.
  static const ohneWirkung = <Entwicklungsregler>[
    Entwicklungsregler.schaerfe,
    Entwicklungsregler.rauschunterdrueckung,
    Entwicklungsregler.klarheit,
    Entwicklungsregler.vignettierung,
  ];

  /// Welche davon in [a] tatsächlich gesetzt sind – für einen Hinweis, der
  /// nur dann erscheint, wenn er jemanden betrifft.
  static List<Entwicklungsregler> gesetztOhneWirkung(DevelopAdjustments a) => [
        if (a.sharpness != 0) Entwicklungsregler.schaerfe,
        if (a.noiseReduction != 0) Entwicklungsregler.rauschunterdrueckung,
        if (a.clarity != 0) Entwicklungsregler.klarheit,
        if (a.vignette != 0) Entwicklungsregler.vignettierung,
      ];

  /// Rendert [datei] und gibt JPEG-Bytes zurück, oder `null`, wenn schon
  /// das Bild nicht zu lesen war.
  static Future<Uint8List?> rendere(
    File datei, {
    required DevelopAdjustments adjustments,
    List<MaskAdjustmentLayer> masks = const [],
    int maxDimension = 2048,
    int quality = 90,
  }) async {
    final shader = await ladeDevelopShader();
    if (shader == null) {
      debugPrint('Entwickeln: Shader nicht ladbar – Bild bleibt unverändert.');
      return null;
    }

    ui.Image? basis;
    final aufraeumen = <ui.Image>[];
    try {
      basis = await _ladeBild(datei, maxDimension);
      if (basis == null) return null;

      final ergebnis = await _zeichne(
        shader: shader,
        basis: basis,
        adjustments: adjustments,
        masks: masks,
        aufraeumen: aufraeumen,
      );
      aufraeumen.add(ergebnis);

      final roh = await ergebnis.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (roh == null) return null;

      // Das Kodieren in einem Isolate: Bei 2048 px sind das gut 16 MB, die
      // sonst den Haupt-Isolate für einen Moment blockieren – dasselbe
      // Muster wie beim Thumbnail-Pfad in import_service.dart.
      return await compute(
        _kodiereJpeg,
        _KodierAuftrag(roh.buffer.asUint8List(), ergebnis.width, ergebnis.height, quality),
      );
    } catch (e) {
      debugPrint('Entwickeln über den Shader fehlgeschlagen: $e');
      return null;
    } finally {
      basis?.dispose();
      for (final b in aufraeumen) {
        b.dispose();
      }
      shader.dispose();
    }
  }

  /// Lädt das Ausgangsbild, bei Bedarf über die Formatumwandlung.
  ///
  /// HEIC und RAW kann Flutter selbst nicht dekodieren; dafür ist derselbe
  /// Weg zuständig, der auch die Vorschaubilder erzeugt.
  static Future<ui.Image?> _ladeBild(File datei, int maxDimension) async {
    Uint8List? bytes;
    if (heicAndRawExtensions.contains(p.extension(datei.path).toLowerCase())) {
      bytes = await NativeImageConverter.convertToJpegBytes(datei,
          maxDimension: maxDimension);
    } else {
      bytes = await datei.readAsBytes();
    }
    if (bytes == null) return null;

    // Die Zielgrösse dem Dekoder überlassen: Er skaliert beim Dekodieren,
    // statt erst ein 48-Megapixel-Bild aufzubauen und danach zu
    // verkleinern.
    //
    // Der Weg über [ui.instantiateImageCodecWithSize] ist dafür
    // wesentlich, nicht bloss hübscher. Wer die Ausgangsgrösse braucht,
    // um die Zielgrösse auszurechnen, kommt leicht darauf, das Bild
    // einmal ganz zu dekodieren und nachzumessen - und hat damit genau
    // das getan, was er vermeiden wollte. Die Grösse steht im Dateikopf.
    // An einem 24-Megapixel-JPEG gemessen:
    //
    //   ganz dekodieren, um nachzumessen   348 ms, 96 MB RGBA
    //   Kopfdaten lesen                      3 ms,  0 MB
    //
    // `getTargetSize` bekommt genau diese Kopfdaten und entscheidet
    // daraus; dekodiert wird danach ein einziges Mal, gleich in der
    // richtigen Grösse.
    final puffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    // Den Puffer gibt `instantiateImageCodecWithSize` selbst wieder frei.
    final codec = await ui.instantiateImageCodecWithSize(
      puffer,
      getTargetSize: (breite, hoehe) => zielGroesse(
        breite: breite,
        hoehe: hoehe,
        maxKante: maxDimension,
      ),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  /// Auf welche Grösse ein [breite] x [hoehe] grosses Bild dekodiert wird.
  ///
  /// Eigene Funktion, weil sie sonst nicht prüfbar wäre: Sie steckte in
  /// einem Rückruf innerhalb einer Methode, die eine Datei liest und
  /// einen Dekoder anwirft.
  ///
  /// Angegeben wird immer nur **eine** Kante; die andere rechnet der
  /// Dekoder seitenverhältnistreu nach. Beide anzugeben hiesse, das Bild
  /// bei krummem Verhältnis zu verzerren.
  @visibleForTesting
  static ui.TargetImageSize zielGroesse({
    required int breite,
    required int hoehe,
    required int maxKante,
  }) {
    final laengste = breite > hoehe ? breite : hoehe;
    // Kleiner als das Ziel: unverändert lassen. Hochrechnen brächte keine
    // Bildinformation, kostete aber Speicher.
    if (laengste <= maxKante) return const ui.TargetImageSize();
    return breite >= hoehe
        ? ui.TargetImageSize(width: maxKante)
        : ui.TargetImageSize(height: maxKante);
  }

  /// Zeichnet Basis und Masken in einer Aufnahme.
  static Future<ui.Image> _zeichne({
    required ui.FragmentShader shader,
    required ui.Image basis,
    required DevelopAdjustments adjustments,
    required List<MaskAdjustmentLayer> masks,
    required List<ui.Image> aufraeumen,
  }) async {
    final aufnahme = ui.PictureRecorder();
    final leinwand = ui.Canvas(aufnahme);
    final flaeche = ui.Rect.fromLTWH(0, 0, basis.width.toDouble(), basis.height.toDouble());

    await _zeichneSchicht(shader, leinwand, basis, adjustments, flaeche, aufraeumen);

    for (final schicht in masks) {
      final maske = await _ladeMaske(schicht.maskFilePath);
      if (maske == null) continue;
      aufraeumen.add(maske);

      // Erst die angepasste Fassung des GANZEN Bildes zeichnen, dann mit
      // der Maske als Alphakanal wieder wegnehmen, was ausserhalb liegt.
      // `dstIn` behält vom eben Gezeichneten nur, wo die Maske deckt –
      // dasselbe Ergebnis wie das Übereinanderlegen auf macOS, nur mit den
      // Mitteln der Leinwand statt mit Core Image.
      leinwand.saveLayer(flaeche, ui.Paint());
      await _zeichneSchicht(
          shader, leinwand, basis, schicht.adjustments, flaeche, aufraeumen);
      leinwand.drawImageRect(
        maske,
        ui.Rect.fromLTWH(0, 0, maske.width.toDouble(), maske.height.toDouble()),
        flaeche,
        ui.Paint()..blendMode = ui.BlendMode.dstIn,
      );
      leinwand.restore();
    }

    return aufnahme.endRecording().toImage(basis.width, basis.height);
  }

  static Future<void> _zeichneSchicht(
    ui.FragmentShader shader,
    ui.Canvas leinwand,
    ui.Image basis,
    DevelopAdjustments a,
    ui.Rect flaeche,
    List<ui.Image> aufraeumen,
  ) async {
    // Volle Kantenlänge statt der gröberen Vorschau-Auflösung: Hier
    // entsteht das Ergebnis, das bleibt.
    final platzhalter = await texturVonBytes(Uint8List.fromList([0, 0, 0, 255]), 1, 1);
    aufraeumen.add(platzhalter);

    ui.Image kurve = platzhalter;
    if (!a.toneCurve.istNeutral) {
      kurve = await texturVonBytes(
          packCurveLutForTexture(buildCurveLut(a.toneCurve)), curveLutSize, 1);
      aufraeumen.add(kurve);
    }
    ui.Image wuerfel = platzhalter;
    if (!a.colorMixer.istNeutral) {
      wuerfel = await texturVonBytes(
        packColorCubeForTexture(
            buildColorCube(a.colorMixer, size: colorCubeSize),
            size: colorCubeSize),
        colorCubeStripWidth(colorCubeSize),
        colorCubeSize,
      );
      aufraeumen.add(wuerfel);
    }

    setzeDevelopUniforms(
      shader,
      adjustments: a,
      breite: flaeche.width,
      hoehe: flaeche.height,
      bild: basis,
      curveLut: kurve,
      colorCube: wuerfel,
      wuerfelKante: colorCubeSize,
    );
    leinwand.drawRect(flaeche, ui.Paint()..shader = shader);
  }

  static Future<ui.Image?> _ladeMaske(String pfad) async {
    try {
      final datei = File(pfad);
      if (!await datei.exists()) return null;
      final codec = await ui.instantiateImageCodec(await datei.readAsBytes());
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}

class _KodierAuftrag {
  final Uint8List rgba;
  final int breite;
  final int hoehe;
  final int quality;
  const _KodierAuftrag(this.rgba, this.breite, this.hoehe, this.quality);
}

Uint8List _kodiereJpeg(_KodierAuftrag a) {
  final bild = img.Image.fromBytes(
    width: a.breite,
    height: a.hoehe,
    bytes: a.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodeJpg(bild, quality: a.quality));
}

/// Die Regler des Entwickeln-Bedienfelds, soweit sie hier eine Rolle
/// spielen.
///
/// Eine Aufzählung statt fertiger Namen: Dieser Dienst kennt keine
/// Oberflächensprache – dasselbe Muster wie `Analysestufe` und
/// `Startabweisung`.
enum Entwicklungsregler { schaerfe, rauschunterdrueckung, klarheit, vignettierung }
