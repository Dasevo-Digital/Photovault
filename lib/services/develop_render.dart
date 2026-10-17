import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../widgets/develop_preview.dart';
import 'package:kern/services/develop_color.dart';
import 'develop_nachbarn.dart';
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
/// Die vier Regler, die Nachbarpixel brauchen – Schärfe, Rauschminderung,
/// Klarheit, Vignette –, folgen als eigene GPU-Stufen hinter dem Shader
/// (siehe develop_nachbarn.dart), mit an Core Image gemessenen Formeln.
/// Bis 3.29 liefen sie hier als Schleife über jedes Pixel auf der CPU, mit
/// eigenen, nicht abgeglichenen Formeln: Die Klarheit nahm denselben
/// Radius von ein, zwei Pixeln wie die Schärfe und war damit nur ein
/// zweites Nachschärfen.
///
/// **Masken** wirken wie unter macOS (compositeMaskLayers) auf das schon
/// entwickelte Bild, eine nach der anderen. Bis 3.29 rechnete jede Maske
/// auf dem Original, und innerhalb der Maske fehlten damit die globalen
/// Regler: Eine Maske, die nur den Kontrast anhebt, nahm dort die
/// Belichtung des ganzen Bildes wieder zurück.
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
  /// Alle sichtbaren Regler werden auch in das gespeicherte Ergebnis
  /// gerechnet. Die Konstante bleibt als Diagnosevertrag bestehen.
  static const ohneWirkung = <Entwicklungsregler>[];

  /// Welche davon in [a] tatsächlich gesetzt sind – für einen Hinweis, der
  /// nur dann erscheint, wenn er jemanden betrifft.
  static List<Entwicklungsregler> gesetztOhneWirkung(DevelopAdjustments a) =>
      const [];

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
    final nachbarn = await ladeNachbarShader();
    if (nachbarn == null && brauchtNachbarn(adjustments)) {
      debugPrint(
        'Entwickeln: Nachbarpixel-Shader nicht ladbar – Schärfe, '
        'Rauschminderung, Klarheit und Vignette entfallen.',
      );
    }

    ui.Image? basis;
    final aufraeumen = <ui.Image>[];
    try {
      basis = await _ladeBild(
        datei,
        maxDimension,
        objektivkorrektur: adjustments.lensCorrectionEnabled,
      );
      if (basis == null) return null;

      final ergebnis = await _zeichne(
        shader: shader,
        nachbarn: nachbarn,
        basis: basis,
        adjustments: adjustments,
        masks: masks,
        aufraeumen: aufraeumen,
      );

      final roh = await ergebnis.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (roh == null) return null;

      // Das Kodieren in einem Isolate: Bei 2048 px sind das gut 16 MB, die
      // sonst den Haupt-Isolate für einen Moment blockieren – dasselbe
      // Muster wie beim Thumbnail-Pfad in import_service.dart.
      return await compute(
        _kodiereJpeg,
        _KodierAuftrag(
          roh.buffer.asUint8List(),
          ergebnis.width,
          ergebnis.height,
          quality,
        ),
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
      nachbarn?.dispose();
    }
  }

  /// Lädt das Ausgangsbild, bei Bedarf über die Formatumwandlung.
  ///
  /// HEIC und RAW kann Flutter selbst nicht dekodieren; dafür ist derselbe
  /// Weg zuständig, der auch die Vorschaubilder erzeugt.
  static Future<ui.Image?> _ladeBild(
    File datei,
    int maxDimension, {
    required bool objektivkorrektur,
  }) async {
    Uint8List? bytes;
    if (heicAndRawExtensions.contains(p.extension(datei.path).toLowerCase())) {
      bytes = await NativeImageConverter.convertToJpegBytes(
        datei,
        maxDimension: maxDimension,
        objektivkorrektur: objektivkorrektur,
      );
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
      getTargetSize: (breite, hoehe) =>
          zielGroesse(breite: breite, hoehe: hoehe, maxKante: maxDimension),
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

  /// Entwickelt [basis] mit den globalen Reglern und legt danach jede
  /// Maske darüber.
  static Future<ui.Image> _zeichne({
    required ui.FragmentShader shader,
    required NachbarShader? nachbarn,
    required ui.Image basis,
    required DevelopAdjustments adjustments,
    required List<MaskAdjustmentLayer> masks,
    required List<ui.Image> aufraeumen,
  }) async {
    var aktuell = await _entwickle(
      shader,
      nachbarn,
      basis,
      adjustments,
      aufraeumen,
    );

    if (masks.isEmpty) return aktuell;
    final mischer = await _ladeMaskenShader();
    if (mischer == null) {
      debugPrint('Entwickeln: Masken-Shader nicht ladbar – Masken entfallen.');
      return aktuell;
    }
    try {
      for (final schicht in masks) {
        final maske = await _ladeMaske(schicht.maskFilePath);
        if (maske == null) continue;
        aufraeumen.add(maske);

        // Die Regler der Maske auf den AKTUELLEN Stand, nicht auf das
        // Original: So bleiben die globalen Regler auch innerhalb der Maske
        // erhalten, und mehrere Masken wirken nacheinander – wie
        // compositeMaskLayers unter macOS.
        final angepasst = await _entwickle(
          shader,
          nachbarn,
          aktuell,
          schicht.adjustments,
          aufraeumen,
        );
        aktuell = await _ueberMaske(mischer, aktuell, angepasst, maske);
        aufraeumen.add(aktuell);
      }
    } finally {
      mischer.dispose();
    }
    return aktuell;
  }

  /// Ein Durchgang des Entwickeln-Shaders über [bild], danach die
  /// Nachbarpixel-Stufen.
  static Future<ui.Image> _entwickle(
    ui.FragmentShader shader,
    NachbarShader? nachbarn,
    ui.Image bild,
    DevelopAdjustments a,
    List<ui.Image> aufraeumen,
  ) async {
    final flaeche = ui.Rect.fromLTWH(
      0,
      0,
      bild.width.toDouble(),
      bild.height.toDouble(),
    );
    final aufnahme = ui.PictureRecorder();
    await _zeichneSchicht(
      shader,
      ui.Canvas(aufnahme),
      bild,
      a,
      flaeche,
      aufraeumen,
    );
    final bildaufnahme = aufnahme.endRecording();
    final ui.Image entwickelt;
    try {
      entwickelt = await bildaufnahme.toImage(bild.width, bild.height);
    } finally {
      bildaufnahme.dispose();
    }
    aufraeumen.add(entwickelt);
    if (nachbarn == null || !brauchtNachbarn(a)) return entwickelt;
    return wendeNachbarnAn(entwickelt, a, nachbarn, aufraeumen);
  }

  /// Legt [oben] über [unten], aber nur, wo [maske] deckt – über
  /// shaders/develop_maske.frag, dasselbe wie CIBlendWithMask unter macOS.
  ///
  /// **Gedeckt wird nach Helligkeit, nicht nach Alphakanal.** Die App
  /// speichert Masken als deckende Graustufenbilder, weiß = ausgewählt
  /// (segmentation_service.dart, vector_mask_service.dart). Bis 3.29 lag
  /// die Maske hier mit `BlendMode.dstIn` darüber, und das liest den
  /// Alphakanal – bei einem deckenden Bild überall voll: Jede Maske wirkte
  /// unter Linux und Windows auf das ganze Bild. Der Test dazu nahm eine
  /// durchsichtige Maske, wie die App sie nie schreibt.
  ///
  /// Die Maske liegt in der Auflösung des Originals vor und wird bilinear
  /// auf die Arbeitsgrösse gebracht wie bei Core Image; ohne Glättung
  /// bekäme ihr Rand Treppen.
  static Future<ui.Image> _ueberMaske(
    ui.FragmentShader mischer,
    ui.Image unten,
    ui.Image oben,
    ui.Image maske,
  ) async {
    final breite = unten.width.toDouble();
    final hoehe = unten.height.toDouble();
    mischer
      ..setFloat(0, breite)
      ..setFloat(1, hoehe)
      ..setImageSampler(0, unten)
      ..setImageSampler(1, oben)
      ..setImageSampler(2, maske, filterQuality: ui.FilterQuality.low);
    final aufnahme = ui.PictureRecorder();
    ui.Canvas(aufnahme).drawRect(
      ui.Rect.fromLTWH(0, 0, breite, hoehe),
      ui.Paint()..shader = mischer,
    );
    final bild = aufnahme.endRecording();
    try {
      return await bild.toImage(unten.width, unten.height);
    } finally {
      bild.dispose();
    }
  }

  static Future<ui.FragmentShader?> _ladeMaskenShader() async {
    try {
      final programm = await ui.FragmentProgram.fromAsset(
        'shaders/develop_maske.frag',
      );
      return programm.fragmentShader();
    } catch (_) {
      return null;
    }
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
    final platzhalter = await texturVonBytes(
      Uint8List.fromList([0, 0, 0, 255]),
      1,
      1,
    );
    aufraeumen.add(platzhalter);

    ui.Image kurve = platzhalter;
    if (!a.toneCurve.istNeutral) {
      kurve = await texturVonBytes(
        packCurveLutForTexture(buildCurveLut(a.toneCurve)),
        curveLutSize,
        1,
      );
      aufraeumen.add(kurve);
    }
    ui.Image wuerfel = platzhalter;
    if (!a.colorMixer.istNeutral) {
      wuerfel = await texturVonBytes(
        packColorCubeForTexture(
          buildColorCube(a.colorMixer, size: colorCubeSize),
          size: colorCubeSize,
        ),
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
enum Entwicklungsregler {
  schaerfe,
  rauschunterdrueckung,
  klarheit,
  vignettierung,
}
