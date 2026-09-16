import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/develop_color.dart';
import '../services/native_image_converter.dart';

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
  final werte = developUniforms(adjustments,
      wuerfelKante: wuerfelKante, beschneidungZeigen: beschneidungZeigen);
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
  shader
    ..setImageSampler(_sTexture, bild)
    ..setImageSampler(_sCurveLut, curveLut)
    ..setImageSampler(_sColorCube, colorCube);
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
    canvas.drawRect(Offset.zero & Size(breite, hoehe), Paint()..shader = shader);
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

/// Live-Vorschau der Entwickeln-Regler auf der GPU.
///
/// Bewusst nur für die Zeit des Regler-Ziehens gedacht: maßgeblich für das
/// gespeicherte Ergebnis bleibt der native Renderpfad (siehe
/// develop_adjustments.frag). Kann der Shader nicht geladen werden, zeigt
/// das Widget das unveränderte Basisbild – dann fehlt nur die
/// Live-Rückmeldung, nichts stürzt ab.
class DevelopShaderPreview extends StatefulWidget {
  final ui.FragmentShader? shader;
  final ui.Image image;
  final DevelopAdjustments adjustments;

  /// Ob beschnittene Stellen markiert werden – reine Anzeige, wandert nie
  /// in eine gespeicherte Datei (siehe [setzeDevelopUniforms]).
  final bool beschneidungZeigen;

  const DevelopShaderPreview({
    super.key,
    required this.shader,
    required this.image,
    required this.adjustments,
    this.beschneidungZeigen = false,
  });

  @override
  State<DevelopShaderPreview> createState() => _DevelopShaderPreviewState();
}

class _DevelopShaderPreviewState extends State<DevelopShaderPreview> {
  ui.Image? _platzhalter;
  ui.Image? _curveLut;
  ui.Image? _colorCube;

  /// Verwirft spät fertig gewordene Texturen, wenn die Regler inzwischen
  /// weitergezogen wurden – dasselbe Muster wie `_requestToken` im
  /// Entwickeln-Bildschirm.
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _baueTexturen();
  }

  @override
  void didUpdateWidget(DevelopShaderPreview alt) {
    super.didUpdateWidget(alt);
    // Nur neu bauen, wenn sich Kurve oder Mischer tatsächlich geändert
    // haben – der Würfelbau kostet Millisekunden, die Belichtung zu ziehen
    // darf ihn nicht auslösen.
    if (alt.adjustments.toneCurve != widget.adjustments.toneCurve ||
        alt.adjustments.colorMixer != widget.adjustments.colorMixer) {
      _baueTexturen();
    }
  }

  Future<void> _baueTexturen() async {
    final token = ++_token;

    _platzhalter ??= await texturVonBytes(Uint8List.fromList([0, 0, 0, 255]), 1, 1);

    final kurve = widget.adjustments.toneCurve;
    final mischer = widget.adjustments.colorMixer;

    final neueKurve = kurve.istNeutral
        ? null
        : await texturVonBytes(
            packCurveLutForTexture(buildCurveLut(kurve)), curveLutSize, 1);

    final neuerWuerfel = mischer.istNeutral
        ? null
        : await texturVonBytes(
            packColorCubeForTexture(
              buildColorCube(mischer, size: colorCubePreviewSize),
              size: colorCubePreviewSize,
            ),
            colorCubeStripWidth(colorCubePreviewSize),
            colorCubePreviewSize,
          );

    if (!mounted || token != _token) {
      neueKurve?.dispose();
      neuerWuerfel?.dispose();
      return;
    }

    final alteKurve = _curveLut;
    final alterWuerfel = _colorCube;
    setState(() {
      _curveLut = neueKurve;
      _colorCube = neuerWuerfel;
    });
    alteKurve?.dispose();
    alterWuerfel?.dispose();
  }

  @override
  void dispose() {
    _platzhalter?.dispose();
    _curveLut?.dispose();
    _colorCube?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = widget.shader;
    final platzhalter = _platzhalter;
    // Solange der Platzhalter fehlt (ein Bildaufbau lang), gibt es noch
    // keinen vollständigen Satz Abtaster – dann lieber das Basisbild als
    // eine leere Fläche.
    if (shader == null || platzhalter == null) {
      return RawImage(image: widget.image, fit: BoxFit.contain);
    }
    return CustomPaint(
      painter: DevelopPreviewPainter(
        shader: shader,
        image: widget.image,
        adjustments: widget.adjustments,
        curveLut: _curveLut ?? platzhalter,
        colorCube: _colorCube ?? platzhalter,
        wuerfelKante: colorCubePreviewSize,
        beschneidungZeigen: widget.beschneidungZeigen,
      ),
      size: Size.infinite,
    );
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

/// Ob der Knopf für die Beschneidungswarnung bedienbar ist.
///
/// Bewusst hier und nicht im Bildschirm: Die Regel ist so nachprüfbar,
/// und der Fehler, den sie verhindert, war genau eine unprüfbare Regel.
/// Der Knopf hing ursprünglich daran, dass die Shader-Vorschau gerade
/// LÄUFT – und die lief nur beim Ziehen an einem Regler. Damit war er
/// nur in dem Sekundenbruchteil zwischen Loslassen und fertigem Render
/// anklickbar, also praktisch nie. Er war nicht kaputt, sondern
/// unerreichbar, und das sieht man einem Bildschirm nicht an.
///
/// Masken schliessen ihn weiterhin aus: Die Markierung entsteht im
/// Shader, und der zeichnet über einer neutralen Basis ohne
/// Maskenwirkung.
bool beschneidungBedienbar({
  required bool maskenVorhanden,
  required bool shaderGeladen,
  required bool basisGeladen,
}) =>
    !maskenVorhanden && shaderGeladen && basisGeladen;

/// Ob die Shader-Vorschau anstelle des nativen Renders gezeigt wird.
///
/// Zwei Anlässe: beim Ziehen (damit die Regler live wirken) und solange
/// die Beschneidungswarnung an ist (die Markierung gibt es nur im
/// Shader). [bedienbar] ist das Ergebnis von [beschneidungBedienbar] –
/// ohne Shader oder mit Masken gibt es nichts zu zeigen.
bool shaderVorschauZeigen({
  required bool bedienbar,
  required bool zieht,
  required bool warnungAn,
}) =>
    bedienbar && (zieht || warnungAn);

/// Ob der Vorher/Nachher-Trennstrich gerade gezeigt werden kann.
///
/// Drei Bedingungen, jede aus einem eigenen Grund:
///
/// - [eingeschaltet] – der Nutzer will ihn.
/// - [originalDa] – ohne das unbearbeitete Bild gäbe es nur eine Hälfte.
///   Es wird erst auf Anforderung gerendert (`_ensureOriginalPreviewLoaded`),
///   ist also nicht von Anfang an da.
/// - **nicht** [shaderLaeuft] – die Shader-Vorschau zeichnet nur das
///   bearbeitete Bild. Ein Trennstrich darüber zeigte links wie rechts
///   dasselbe und behauptete damit, es gäbe keinen Unterschied. Er tritt
///   während des Reglerziehens zurück und kommt danach wieder.
bool trennstrichZeigen({
  required bool eingeschaltet,
  required bool originalDa,
  required bool shaderLaeuft,
}) =>
    eingeschaltet && originalDa && !shaderLaeuft;

/// Das dargestellte Rechteck eines Bildes in einer Fläche – die Rechnung
/// hinter `BoxFit.contain`.
///
/// Gebraucht für den Trennstrich: Bei einem Hochformat in breiter Fläche
/// liegen links und rechts leere Ränder. Ein Strich bei „halber
/// Widget-Breite" träfe zwar zufällig die Bildmitte, aber das Ziehen liefe
/// zu einem Drittel durch Leere, in der sich sichtbar nichts tut. Deshalb
/// rechnet der Strich in Bildkoordinaten, nicht in Widget-Koordinaten.
Rect dargestelltesBild(Size flaeche, double seitenverhaeltnis) {
  if (flaeche.isEmpty || seitenverhaeltnis <= 0) return Rect.zero;
  final flaechenVerhaeltnis = flaeche.width / flaeche.height;
  final double breite, hoehe;
  if (seitenverhaeltnis > flaechenVerhaeltnis) {
    // Breiter als die Fläche: Breite füllt aus, oben und unten bleibt Rand.
    breite = flaeche.width;
    hoehe = breite / seitenverhaeltnis;
  } else {
    hoehe = flaeche.height;
    breite = hoehe * seitenverhaeltnis;
  }
  return Rect.fromLTWH(
    (flaeche.width - breite) / 2,
    (flaeche.height - hoehe) / 2,
    breite,
    hoehe,
  );
}

/// Rechnet eine waagerechte Zeigerposition in den Anteil 0…1 auf dem
/// dargestellten Bild um. Ausserhalb des Bildes wird begrenzt, statt
/// Werte unter 0 oder über 1 zu liefern.
double trennstrichAnteil(double x, Rect bild) {
  if (bild.width <= 0) return 0.5;
  return ((x - bild.left) / bild.width).clamp(0.0, 1.0);
}

/// Durchmesser des runden Griffs am Vorher/Nachher-Trennstrich – zugleich
/// die Breite der Fläche, die das Ziehen entgegennimmt. Ein Strich von
/// zwei Punkten wäre mit der Maus kaum zu treffen.
const double griffBreite = 28;

/// Vorher und Nachher in einem Bild, getrennt durch einen ziehbaren
/// Strich.
///
/// Beide Fassungen liegen im Entwickeln-Bildschirm ohnehin vor – das
/// unbearbeitete für das Gedrückt-Halten, das entwickelte als Vorschau.
/// Hier entsteht deshalb **kein zusätzlicher Render**, nur eine zweite
/// Art, dieselben zwei Bilder nebeneinanderzulegen.
///
/// Eigenständig und nicht im Bildschirm, damit es sich ohne dessen
/// Datenbank, Pfade und nativen Renderpfad prüfen lässt.
class VorherNachherVergleich extends StatelessWidget {
  /// Das unbearbeitete Bild – liegt links vom Strich.
  final Uint8List original;

  /// Das entwickelte Bild – liegt rechts vom Strich.
  final Uint8List bearbeitet;

  /// Breite geteilt durch Höhe der Vorschau. Nötig, weil beide Bilder mit
  /// `BoxFit.contain` sitzen und der Strich auf dem **dargestellten**
  /// Rechteck liegen muss, nicht auf dem Widget.
  final double seitenverhaeltnis;

  /// Position des Strichs, 0…1 auf dem dargestellten Bild.
  final double anteil;

  final ValueChanged<double> beiVerschieben;

  final String vorherText;
  final String nachherText;

  const VorherNachherVergleich({
    super.key,
    required this.original,
    required this.bearbeitet,
    required this.seitenverhaeltnis,
    required this.anteil,
    required this.beiVerschieben,
    required this.vorherText,
    required this.nachherText,
  });

  Widget _beschriftung(Rect bild, Size flaeche, {required bool links}) {
    return Positioned(
      // Am Rand des BILDES, nicht der Fläche: Bei einem Hochformat in
      // breiter Fläche schwebten sie sonst neben dem Bild.
      left: links ? bild.left + 8 : null,
      right: links ? null : flaeche.width - bild.right + 8,
      top: bild.top + 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(links ? vorherText : nachherText,
            style: const TextStyle(color: Colors.white, fontSize: 11)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final flaeche = Size(constraints.maxWidth, constraints.maxHeight);
        final bild = dargestelltesBild(flaeche, seitenverhaeltnis);
        final schnitt = bild.left + anteil * bild.width;

        return Stack(
          children: [
            Positioned.fill(
              child: Image.memory(original,
                  gaplessPlayback: true, fit: BoxFit.contain),
            ),
            Positioned.fill(
              child: ClipRect(
                clipper: _TrennstrichClipper(
                    schnitt: schnitt, hoehe: flaeche.height),
                child: Image.memory(bearbeitet,
                    gaplessPlayback: true, fit: BoxFit.contain),
              ),
            ),
            _beschriftung(bild, flaeche, links: true),
            _beschriftung(bild, flaeche, links: false),
            // Der Griff bekommt seinen EIGENEN Erkenner. Läge das Ziehen
            // auf der ganzen Fläche, stritte es sich mit dem langen Druck
            // darunter (Gedrückt-Halten zum Vergleichen) – und das sähe
            // am Bildschirm aus wie „hakt manchmal".
            Positioned(
              left: schnitt - griffBreite / 2,
              top: bild.top,
              width: griffBreite,
              height: bild.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) =>
                    beiVerschieben(trennstrichAnteil(schnitt + d.delta.dx, bild)),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Center(
                    child: Container(
                      width: 2,
                      color: Colors.white,
                      child: Center(
                        child: Container(
                          width: griffBreite,
                          height: griffBreite,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.compare_arrows,
                              size: 16, color: Colors.black87),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Beschneidet das entwickelte Bild links vom Trennstrich.
///
/// Bewusst ein eigener Clipper und kein `Align(widthFactor:)`: Jenes
/// rechnet in Anteilen der Kindbreite, hier ist aber ein Schnitt an einer
/// bestimmten Stelle der Fläche gefragt – die Stelle stammt aus dem
/// dargestellten Bildrechteck (siehe [dargestelltesBild]), nicht aus der
/// Widget-Breite.
class _TrennstrichClipper extends CustomClipper<Rect> {
  final double schnitt;
  final double hoehe;

  const _TrennstrichClipper({required this.schnitt, required this.hoehe});

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, schnitt, hoehe);

  @override
  bool shouldReclip(covariant _TrennstrichClipper alt) =>
      alt.schnitt != schnitt || alt.hoehe != hoehe;
}
