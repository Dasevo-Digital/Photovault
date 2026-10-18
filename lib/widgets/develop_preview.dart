import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:kern/services/develop_color.dart';
import '../services/develop_nachbarn.dart';
import '../services/native_image_converter.dart';
import 'package:zierbild/entwickeln_shader.dart';

// Shader, Uniforms und Vorschau-Maler liegen im Paket zierbild, damit die
// Handy-App dasselbe rechnet.
export 'package:zierbild/entwickeln_shader.dart';

/// Live-Vorschau der Entwickeln-Regler auf der GPU.
///
/// Bewusst nur für die Zeit des Regler-Ziehens gedacht: maßgeblich für das
/// gespeicherte Ergebnis bleibt der native Renderpfad (siehe
/// develop_adjustments.frag). Kann der Shader nicht geladen werden, zeigt
/// das Widget das unveränderte Basisbild – dann fehlt nur die
/// Live-Rückmeldung, nichts stürzt ab.
///
/// **Schärfe, Rauschminderung, Klarheit, Vignette.** Ist einer davon
/// gesetzt, reicht ein Shader-Aufruf je Pixel nicht mehr. Dann rechnet
/// das Widget das Bild in seiner eigenen Grösse durch den Shader und
/// danach durch die Nachbarpixel-Stufen – dieselben wie beim Speichern
/// unter Linux und Windows – und zeigt das Ergebnis. Bis 3.29 zeigte die
/// Vorschau diese vier Regler gar nicht: Beim Ziehen bewegte sich der
/// Regler, das Bild erst nach dem Loslassen, und beim Ziehen eines
/// anderen Reglers verschwand ihre Wirkung für die Dauer des Zugs.
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

  /// Ein eigenes Exemplar des Entwickeln-Shaders für die Vorstufe der
  /// Nachbarpixel-Regler – das von [DevelopShaderPreview.shader] zeichnet
  /// gleichzeitig direkt.
  ui.FragmentShader? _vorstufe;
  NachbarShader? _nachbarn;

  /// Das zuletzt fertig gerechnete Bild samt Nachbarpixel-Stufen.
  ui.Image? _nachbarBild;

  /// Es läuft immer nur EINE Rechnung. Was währenddessen an Bewegung
  /// anfällt, wird zu einem einzigen Nachzügler – dasselbe Muster wie
  /// beim nativen Render während des Ziehens (`_liveNativ`).
  bool _rechnet = false;
  bool _nochmal = false;

  /// Verwirft spät fertig gewordene Texturen, wenn die Regler inzwischen
  /// weitergezogen wurden – dasselbe Muster wie `_requestToken` im
  /// Entwickeln-Bildschirm.
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _baueTexturen();
    _ladeNachbarn();
  }

  Future<void> _ladeNachbarn() async {
    final vorstufe = await ladeDevelopShader();
    final nachbarn = await ladeNachbarShader();
    if (!mounted) {
      vorstufe?.dispose();
      nachbarn?.dispose();
      return;
    }
    _vorstufe = vorstufe;
    _nachbarn = nachbarn;
    _planeNachbarn();
  }

  void _planeNachbarn() {
    if (!brauchtNachbarn(widget.adjustments)) {
      final alt = _nachbarBild;
      if (alt != null) {
        setState(() => _nachbarBild = null);
        alt.dispose();
      }
      return;
    }
    if (_rechnet) {
      _nochmal = true;
      return;
    }
    unawaited(_rechneNachbarn());
  }

  Future<void> _rechneNachbarn() async {
    final vorstufe = _vorstufe;
    final nachbarn = _nachbarn;
    if (vorstufe == null || nachbarn == null) return;
    _rechnet = true;
    try {
      do {
        _nochmal = false;
        final platzhalter = _platzhalter ??= await texturVonBytes(
          Uint8List.fromList([0, 0, 0, 255]),
          1,
          1,
        );
        final stand = widget.adjustments;
        if (!mounted || !brauchtNachbarn(stand)) return;
        final aufraeumen = <ui.Image>[];
        ui.Image? ergebnis;
        try {
          final entwickelt = await entwickleInBild(
            vorstufe,
            widget.image,
            stand,
            curveLut: _curveLut ?? platzhalter,
            colorCube: _colorCube ?? platzhalter,
            wuerfelKante: colorCubePreviewSize,
          );
          aufraeumen.add(entwickelt);
          ergebnis = await wendeNachbarnAn(
            entwickelt,
            stand,
            nachbarn,
            aufraeumen,
            beschneidungZeigen: widget.beschneidungZeigen,
          );
        } finally {
          for (final b in aufraeumen) {
            if (!identical(b, ergebnis)) b.dispose();
          }
        }
        if (!mounted) {
          ergebnis.dispose();
          return;
        }
        final alt = _nachbarBild;
        setState(() => _nachbarBild = ergebnis);
        alt?.dispose();
      } while (_nochmal && mounted);
    } finally {
      _rechnet = false;
    }
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
    if (alt.adjustments != widget.adjustments ||
        !identical(alt.image, widget.image) ||
        alt.beschneidungZeigen != widget.beschneidungZeigen) {
      _planeNachbarn();
    }
  }

  Future<void> _baueTexturen() async {
    final token = ++_token;

    _platzhalter ??= await texturVonBytes(
      Uint8List.fromList([0, 0, 0, 255]),
      1,
      1,
    );

    final kurve = widget.adjustments.toneCurve;
    final mischer = widget.adjustments.colorMixer;

    final neueKurve = kurve.istNeutral
        ? null
        : await texturVonBytes(
            packCurveLutForTexture(buildCurveLut(kurve)),
            curveLutSize,
            1,
          );

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
    // Kurve und Mischer stecken in der Vorstufe – mit den neuen Tabellen
    // noch einmal rechnen.
    _planeNachbarn();
  }

  @override
  void dispose() {
    _platzhalter?.dispose();
    _curveLut?.dispose();
    _colorCube?.dispose();
    _nachbarBild?.dispose();
    _vorstufe?.dispose();
    _nachbarn?.dispose();
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
    final nachbarBild = _nachbarBild;
    if (nachbarBild != null && brauchtNachbarn(widget.adjustments)) {
      return RawImage(image: nachbarBild, fit: BoxFit.contain);
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
}) => !maskenVorhanden && shaderGeladen && basisGeladen;

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
}) => bedienbar && (zieht || warnungAn);

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
}) => eingeschaltet && originalDa && !shaderLaeuft;

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
        child: Text(
          links ? vorherText : nachherText,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
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
              child: Image.memory(
                original,
                gaplessPlayback: true,
                fit: BoxFit.contain,
              ),
            ),
            Positioned.fill(
              child: ClipRect(
                clipper: _TrennstrichClipper(
                  schnitt: schnitt,
                  hoehe: flaeche.height,
                ),
                child: Image.memory(
                  bearbeitet,
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                ),
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
                onHorizontalDragUpdate: (d) => beiVerschieben(
                  trennstrichAnteil(schnitt + d.delta.dx, bild),
                ),
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
                          child: const Icon(
                            Icons.compare_arrows,
                            size: 16,
                            color: Colors.black87,
                          ),
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
