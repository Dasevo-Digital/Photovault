import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:kern/services/develop_color.dart';
import 'package:kern/services/entwicklungswerte.dart';

/// Pfad des Shaders (siehe pubspec.yaml, Abschnitt `shaders:`).
const developShaderAsset = 'shaders/develop_adjustments.frag';

/// Reihenfolge der Uniforms nach `uSize` – muss zur Deklarations-
/// reihenfolge in develop_adjustments.frag passen. Als benannte Konstanten,
/// damit eine Änderung im Shader hier auffällt statt still falsche Werte zu
/// setzen.
const _iExposure = 2;
const _iTemperature = 3;
const _iTint = 4;
const _iContrast = 5;
const _iShadows = 6;
const _iHighlights = 7;
const _iApplyWhiteBalance = 8;
const _iCurveActive = 9;
const _iMixerActive = 10;
const _iCubeSize = 11;
const _iClipWarn = 12;

/// Reihenfolge der Bildabtaster – eigener Indexraum, ebenfalls nach
/// Deklarationsreihenfolge.
const _sTexture = 0;
const _sCurveLut = 1;
const _sColorCube = 2;

/// Übersetzt [a] in die Uniform-Werte des Shaders – **ohne** Größe, die
/// setzt der Painter.
///
/// Reine Funktion, damit sich die Zuordnung ohne GPU testen lässt. Der
/// Rückgabewert ist nach Uniform-Index geordnet, beginnend hinter `uSize`
/// (Index 0 und 1).
///
/// `temperature == null` heißt automatischer Weißabgleich – dann bleibt der
/// Weißabgleich im Shader aus, statt einen Standardwert zu erzwingen.
///
/// [wuerfelKante] ist die tatsächlich hochgeladene Kantenlänge des
/// Farbwürfels; die Vorschau benutzt eine gröbere als der gespeicherte
/// Render (siehe [colorCubePreviewSize]).
List<double> developUniforms(
  DevelopAdjustments a, {
  int wuerfelKante = colorCubePreviewSize,
  bool beschneidungZeigen = false,
}) {
  final automatisch = a.temperature == null;
  return [
    a.exposure,
    a.temperature ?? 6500.0,
    a.tint ?? 0.0,
    a.contrast,
    a.shadows,
    a.highlights,
    automatisch ? 0.0 : 1.0,
    a.toneCurve.istNeutral ? 0.0 : 1.0,
    a.colorMixer.istNeutral ? 0.0 : 1.0,
    wuerfelKante.toDouble(),
    beschneidungZeigen ? 1.0 : 0.0,
  ];
}

/// Belegt alle Uniforms und Abtaster des Entwickeln-Shaders.
///
/// Eine Stelle für beide Wege – die Live-Vorschau (siehe
/// [DevelopPreviewPainter]) und das gespeicherte Ergebnis (siehe
/// DevelopRender). Zwei Fassungen davon wären die naheliegendste Art, dass
/// Vorschau und Ergebnis auseinanderlaufen, ohne dass es jemandem auffällt:
/// Ein hier vergessener Regler wirkt dann in der Vorschau und im Bild
/// unterschiedlich.
///
/// [beschneidungZeigen] ist bewusst mit `false` vorbelegt und nicht
/// erforderlich: Der Renderpfad (DevelopRender) gibt es gar nicht erst an
/// und kann die Markierungen damit auch nicht versehentlich in eine
/// gespeicherte Datei schreiben. Sicher durch Weglassen, nicht durch
/// Sorgfalt.
void setzeDevelopUniforms(
  ui.FragmentShader shader, {
  required DevelopAdjustments adjustments,
  required double breite,
  required double hoehe,
  required ui.Image bild,
  required ui.Image curveLut,
  required ui.Image colorCube,
  required int wuerfelKante,
  bool beschneidungZeigen = false,
}) {
  final werte = developUniforms(
    adjustments,
    wuerfelKante: wuerfelKante,
    beschneidungZeigen: beschneidungZeigen,
  );
  shader
    ..setFloat(0, breite)
    ..setFloat(1, hoehe)
    ..setFloat(_iExposure, werte[0])
    ..setFloat(_iTemperature, werte[1])
    ..setFloat(_iTint, werte[2])
    ..setFloat(_iContrast, werte[3])
    ..setFloat(_iShadows, werte[4])
    ..setFloat(_iHighlights, werte[5])
    ..setFloat(_iApplyWhiteBalance, werte[6])
    ..setFloat(_iCurveActive, werte[7])
    ..setFloat(_iMixerActive, werte[8])
    ..setFloat(_iCubeSize, werte[9])
    ..setFloat(_iClipWarn, werte[10]);
  // Bilinear, ausdrücklich: Ohne Angabe tastet Flutter den nächsten
  // Pixel ab (FilterQuality.none). Kurve und Farbwürfel sind aber
  // Stützstellen, zwischen denen der Shader die Textur interpolieren
  // lässt (siehe farbwuerfel() in develop_adjustments.frag). Bis 3.29
  // fehlte die Angabe, und ein Farbmischer zerlegte einen Verlauf in
  // Stufen von bis zu 14 Werten – unter Linux und Windows auch im
  // gespeicherten Bild. Das Bild selbst zeichnet die Vorschau verkleinert,
  // auch dort gehört gemittelt statt ein Pixel herausgegriffen.
  shader
    ..setImageSampler(_sTexture, bild, filterQuality: FilterQuality.low)
    ..setImageSampler(_sCurveLut, curveLut, filterQuality: FilterQuality.low)
    ..setImageSampler(_sColorCube, colorCube, filterQuality: FilterQuality.low);
}

/// Zeichnet [image] durch den Entwickeln-Shader.
class DevelopPreviewPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image image;
  final DevelopAdjustments adjustments;

  /// Tonwertkurve und Farbmischer als Textur. Beide sind Pflicht, auch wenn
  /// das jeweilige Werkzeug neutral ist: Ein Shader mit einem nicht
  /// gesetzten Bildabtaster zeichnet gar nicht. Für den neutralen Fall
  /// genügt ein 1×1-Platzhalter, den `uCurveActive`/`uMixerActive` dann
  /// ohnehin nie liest.
  final ui.Image curveLut;
  final ui.Image colorCube;
  final int wuerfelKante;

  /// Ob beschnittene Stellen im Bild markiert werden. Nur Anzeige – siehe
  /// [setzeDevelopUniforms].
  final bool beschneidungZeigen;

  DevelopPreviewPainter({
    required this.shader,
    required this.image,
    required this.adjustments,
    required this.curveLut,
    required this.colorCube,
    required this.wuerfelKante,
    this.beschneidungZeigen = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Seitenverhältnis wahren (wie BoxFit.contain beim bisherigen
    // Image.memory), sonst verzerrt die Live-Vorschau gegenüber dem
    // nativen Render.
    final skalierung = (size.width / image.width) < (size.height / image.height)
        ? size.width / image.width
        : size.height / image.height;
    final breite = image.width * skalierung;
    final hoehe = image.height * skalierung;
    final links = (size.width - breite) / 2;
    final oben = (size.height - hoehe) / 2;

    setzeDevelopUniforms(
      shader,
      adjustments: adjustments,
      breite: breite,
      hoehe: hoehe,
      bild: image,
      curveLut: curveLut,
      colorCube: colorCube,
      wuerfelKante: wuerfelKante,
      beschneidungZeigen: beschneidungZeigen,
    );

    canvas.save();
    canvas.translate(links, oben);
    canvas.drawRect(
      Offset.zero & Size(breite, hoehe),
      Paint()..shader = shader,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DevelopPreviewPainter alt) =>
      alt.adjustments != adjustments ||
      alt.beschneidungZeigen != beschneidungZeigen ||
      !identical(alt.image, image) ||
      !identical(alt.curveLut, curveLut) ||
      !identical(alt.colorCube, colorCube);
}

/// Zeichnet [bild] einmal durch den Entwickeln-Shader in ein neues Bild
/// derselben Grösse – die Vorstufe, wenn danach noch die
/// Nachbarpixel-Stufen laufen (siehe develop_nachbarn.dart).
Future<ui.Image> entwickleInBild(
  ui.FragmentShader shader,
  ui.Image bild,
  DevelopAdjustments a, {
  required ui.Image curveLut,
  required ui.Image colorCube,
  required int wuerfelKante,
}) async {
  final breite = bild.width.toDouble();
  final hoehe = bild.height.toDouble();
  setzeDevelopUniforms(
    shader,
    adjustments: a,
    breite: breite,
    hoehe: hoehe,
    bild: bild,
    curveLut: curveLut,
    colorCube: colorCube,
    wuerfelKante: wuerfelKante,
  );
  final aufnahme = ui.PictureRecorder();
  ui.Canvas(
    aufnahme,
  ).drawRect(Offset.zero & Size(breite, hoehe), Paint()..shader = shader);
  final bildaufnahme = aufnahme.endRecording();
  try {
    return await bildaufnahme.toImage(bild.width, bild.height);
  } finally {
    bildaufnahme.dispose();
  }
}

/// Erzeugt eine Textur aus rohen RGBA-Bytes.
///
/// 8 Bit je Kanal, nicht Fliesskomma. Die Sorge war, dass eine steile
/// Tonwertkurve dadurch in der Live-Vorschau sichtbar abstuft – die
/// Tabelle hat dann nur 256 Stützstellen, aus denen der Verlauf entsteht.
/// Am Bild geprüft (steile Kurve auf einem weichen Himmelsverlauf): keine
/// Streifen erkennbar, weder beim Ziehen noch im Vergleich zum nativen
/// Render danach. Es bleibt deshalb bei 8 Bit; `rgbaFloat32` wäre die
/// Nachbesserung, falls sich das an anderem Material doch zeigt.
Future<ui.Image> texturVonBytes(Uint8List bytes, int breite, int hoehe) {
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    breite,
    hoehe,
    ui.PixelFormat.rgba8888,
    fertig.complete,
  );
  return fertig.future;
}

/// Lädt das Shader-Programm einmalig. Gibt `null` zurück, wenn das
/// fehlschlägt (z.B. Plattform ohne Shader-Unterstützung) – die Aufrufer
/// fallen dann auf die bisherige Anzeige zurück.
Future<ui.FragmentShader?> ladeDevelopShader() async {
  try {
    final program = await ui.FragmentProgram.fromAsset(developShaderAsset);
    return program.fragmentShader();
  } catch (_) {
    return null;
  }
}
