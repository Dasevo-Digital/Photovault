import 'dart:math' as math;
import 'dart:ui' as ui show PointMode;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../services/histogram.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Welche Kanäle das Histogramm gerade zeigt.
enum HistogramMode {
  /// Wahrgenommene Helligkeit (Luma) als einzelne Fläche – zeigt die
  /// Tonwertverteilung von Schwarz (links) bis Weiß (rechts).
  luminance,

  /// Rot, Grün und Blau getrennt, additiv übereinandergelegt.
  rgb,

  /// Waveform: die Tonwertverteilung je Bildspalte. Die waagerechte Achse
  /// ist die Bildbreite, die senkrechte der Tonwert – man sieht damit,
  /// WO im Bild etwas ausfrisst, was ein Histogramm nicht zeigen kann.
  waveform,

  /// Dieselbe Darstellung, aber die drei Farbkanäle nebeneinander. Zeigt
  /// Farbstiche, die in der Helligkeits-Waveform untergehen.
  parade,
}

/// Zeigt die Tonwertverteilung eines Bildes, umschaltbar zwischen
/// Helligkeit und RGB.
///
/// Bewusst ohne eigene Berechnung: die Daten kommen fertig von außen
/// (siehe computeHistogramFromBytes), damit das Widget beim Neuzeichnen
/// keine Bildverarbeitung anstößt und dieselbe Berechnung auch für andere
/// Anzeigen wiederverwendbar bleibt.
class HistogramView extends StatefulWidget {
  final HistogramData? data;

  /// Die Datengrundlage für Waveform und Parade. Getrennt vom Histogramm,
  /// weil es eine andere Auswertung ist und nicht bloss eine andere
  /// Zeichnung: Ein Histogramm wirft die Bildposition weg, eine Waveform
  /// braucht sie.
  final WaveformData? waveform;

  /// Zeigt einen dezenten Ladehinweis, während im Hintergrund eine neue
  /// Vorschau berechnet wird – das bisherige Histogramm bleibt dabei
  /// sichtbar, statt auf einen leeren Kasten zu springen.
  final bool isStale;

  const HistogramView({
    super.key,
    required this.data,
    this.waveform,
    this.isStale = false,
  });

  @override
  State<HistogramView> createState() => _HistogramViewState();
}

class _HistogramViewState extends State<HistogramView> {
  HistogramMode _mode = HistogramMode.luminance;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final welle = widget.waveform;
    final istWelle =
        _mode == HistogramMode.waveform || _mode == HistogramMode.parade;
    final leer = istWelle ? welle == null || welle.isEmpty : data == null || data.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(AppTexte.of(context).histogrammTitel,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (widget.isStale)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white38),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          height: 96,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: Colors.white24),
          ),
          clipBehavior: Clip.antiAlias,
          child: leer
              ? Center(
                  child: Text(
                    AppTexte.of(context).histogrammKeineVorschau,
                    style: const TextStyle(color: DunkleFlaeche.hinweis, fontSize: 11),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: istWelle
                          ? _WaveformPainter(
                              data: welle!, parade: _mode == HistogramMode.parade)
                          : _HistogramPainter(data: data!, mode: _mode),
                      size: Size.infinite,
                    ),
                    // Nur ueber Histogramm und RGB, NICHT ueber Waveform
                    // und Parade. Dort ist die waagerechte Achse die
                    // Bildbreite und die senkrechte der Tonwert - eine
                    // Marke am linken Rand hiesse dort "die linke
                    // Bildkante", nicht "die Tiefen". Beschnittenes sieht
                    // man in diesen beiden ohnehin: als Anhaeufung an der
                    // oberen oder unteren Kante. Genau dafuer sind sie da.
                    if (!istWelle && data != null && !data.isEmpty)
                      _Beschneidungsmarken(beschneidungAus(data)),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<HistogramMode>(
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: [
            ButtonSegment(
              value: HistogramMode.luminance,
              label: Text(AppTexte.of(context).histogrammHelligkeit,
                  style: const TextStyle(fontSize: 11)),
            ),
            const ButtonSegment(
              value: HistogramMode.rgb,
              label: Text('RGB', style: TextStyle(fontSize: 11)),
            ),
            ButtonSegment(
              value: HistogramMode.waveform,
              label: Text(AppTexte.of(context).histogrammWaveform,
                  style: const TextStyle(fontSize: 11)),
            ),
            ButtonSegment(
              value: HistogramMode.parade,
              label: Text(AppTexte.of(context).histogrammParade,
                  style: const TextStyle(fontSize: 11)),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) => setState(() => _mode = selection.first),
          showSelectedIcon: false,
        ),
      ],
    );
  }
}

/// Die Marken an den beiden Enden – links abgesoffen, rechts ausgefressen.
///
/// Eingefärbt nach betroffenem Kanal: Schlagen alle drei an, ist die
/// Stelle wirklich schwarz bzw. weiss; schlägt nur einer an, ist bloss
/// dieser Kanal übersteuert, und das ist ein anderer Befund. Ein einzelner
/// grauer Balken könnte das nicht sagen.
class _Beschneidungsmarken extends StatelessWidget {
  const _Beschneidungsmarken(this.beschneidung);

  final Beschneidung beschneidung;

  Color? _farbe(bool rot, bool gruen, bool blau) {
    if (!rot && !gruen && !blau) return null;
    if (rot && gruen && blau) return Colors.white;
    // Ein oder zwei Kanäle: die Mischfarbe genau dieser Kanäle.
    return Color.fromARGB(255, rot ? 255 : 0, gruen ? 255 : 0, blau ? 255 : 0);
  }

  Widget _balken(Color farbe, Alignment wo) => Align(
        alignment: wo,
        child: Container(width: 3, color: farbe),
      );

  @override
  Widget build(BuildContext context) {
    final links = _farbe(beschneidung.tiefenRot, beschneidung.tiefenGruen,
        beschneidung.tiefenBlau);
    final rechts = _farbe(beschneidung.lichterRot, beschneidung.lichterGruen,
        beschneidung.lichterBlau);
    if (links == null && rechts == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (links != null) _balken(links, Alignment.centerLeft),
          if (rechts != null) _balken(rechts, Alignment.centerRight),
        ],
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final HistogramData data;
  final HistogramMode mode;

  _HistogramPainter({required this.data, required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    if (mode == HistogramMode.luminance) {
      final peak = data.peakOf([data.luminance]);
      _paintChannel(canvas, size, data.luminance, peak, Colors.white.withValues(alpha: 0.75));
    } else {
      // Gemeinsame Bezugshöhe über alle drei Kanäle, sonst wären die
      // Kurven zueinander nicht mehr vergleichbar (jeder Kanal würde auf
      // seine eigene Spitze normiert).
      final peak = data.peakOf([data.red, data.green, data.blue]);
      // Additiv überlagert (Plus-Blendmode): wo sich alle drei Kanäle
      // decken, entsteht Weiß – das übliche Lightroom-/darktable-Bild.
      _paintChannel(canvas, size, data.red, peak, const Color(0xFFFF4444), blend: BlendMode.plus);
      _paintChannel(canvas, size, data.green, peak, const Color(0xFF44FF44), blend: BlendMode.plus);
      _paintChannel(canvas, size, data.blue, peak, const Color(0xFF4488FF), blend: BlendMode.plus);
    }
  }

  /// Senkrechte Viertel-Linien als Orientierung (Schatten/Mitten/Lichter).
  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _paintChannel(
    Canvas canvas,
    Size size,
    List<int> bins,
    int peak,
    Color color, {
    BlendMode blend = BlendMode.srcOver,
  }) =>
      paintHistogramSilhouette(canvas, size, bins, peak, color, blend: blend);

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) =>
      oldDelegate.mode != mode || !identical(oldDelegate.data, data);
}

/// Zeichnet die Fläche unter einer Tonwertverteilung.
///
/// Öffentlich, weil der Tonwertkurven-Editor dieselbe Silhouette hinter
/// seinem Raster zeigt – dort ist sie der eigentliche Bezugspunkt: Man
/// zieht die Kurve dorthin, wo die Tonwerte tatsächlich liegen. Eine
/// zweite, leicht abweichende Zeichenroutine dafür wäre genau die Art
/// Ungenauigkeit, die beim Vergleichen stört.
///
/// Die Quadratwurzel-Skalierung ist kein Schönheitsmittel: Reale Fotos
/// haben oft einzelne, extrem hohe Spitzen (etwa eine grosse einfarbige
/// Fläche), gegen die alle anderen Tonwerte bei linearer Skalierung zu
/// einer unlesbaren Nulllinie zusammenfielen.
void paintHistogramSilhouette(
  Canvas canvas,
  Size size,
  List<int> bins,
  int peak,
  Color color, {
  BlendMode blend = BlendMode.srcOver,
}) {
  if (peak <= 0 || bins.length < 2) return;

  final path = Path()..moveTo(0, size.height);
  for (var i = 0; i < bins.length; i++) {
    final x = size.width * i / (bins.length - 1);
    final normalized = (bins[i] / peak).clamp(0.0, 1.0);
    path.lineTo(x, size.height * (1 - math.sqrt(normalized)));
  }
  path
    ..lineTo(size.width, size.height)
    ..close();

  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..blendMode = blend,
  );
}

/// Zeichnet Waveform und RGB-Parade.
///
/// Beide sind dasselbe Bild, nur anders angeordnet: Die Waveform legt die
/// Helligkeit über die volle Breite, die Parade stellt die drei Farbkanäle
/// nebeneinander in je einem Drittel. Deshalb ein Maler für beides.
///
/// Gezeichnet wird als Bildpunkte, nicht als Linie: Jede Bildspalte hat
/// eine ganze Verteilung von Tonwerten, keinen einzelnen Wert. Wie hell ein
/// Punkt ist, sagt, wie viele Pixel dieser Spalte diesen Tonwert haben –
/// genau so sieht eine Waveform in einem Schnittprogramm aus.
class _WaveformPainter extends CustomPainter {
  final WaveformData data;
  final bool parade;

  _WaveformPainter({required this.data, required this.parade});

  /// In wie viele Helligkeitsstufen abgestuft wird.
  ///
  /// `drawPoints` kennt nur eine Farbe für den ganzen Aufruf. Statt jeden
  /// Punkt einzeln zu zeichnen – bei 256×256 Stützstellen wäre das zu
  /// langsam – werden die Punkte nach Stufe gebündelt und je Stufe ein Mal
  /// gezeichnet. Sechs Stufen sind fein genug, dass keine Kanten sichtbar
  /// werden.
  static const _stufen = 6;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.peak <= 0) return;

    void zeichne(List<List<int>> kanal, Color farbe, double x0, double breite) {
      final spalten = kanal.length;
      final punktBreite = breite / spalten;
      final buendel = List.generate(_stufen, (_) => <Offset>[]);

      for (var x = 0; x < spalten; x++) {
        final spalte = kanal[x];
        final px = x0 + x * punktBreite + punktBreite / 2;
        for (var t = 0; t < spalte.length; t++) {
          if (spalte[t] <= 0) continue;
          // Wurzelkennlinie statt linear: Eine Spalte hat wenige sehr hohe
          // und viele sehr kleine Werte. Linear abgebildet wäre ausser der
          // Spitze nichts zu sehen.
          final h = math.sqrt(spalte[t] / data.peak);
          final stufe = (h * _stufen).ceil().clamp(1, _stufen) - 1;
          // Tonwert 255 gehört nach oben, 0 nach unten.
          final py = size.height * (1 - t / (spalte.length - 1));
          buendel[stufe].add(Offset(px, py));
        }
      }

      for (var stufe = 0; stufe < _stufen; stufe++) {
        if (buendel[stufe].isEmpty) continue;
        canvas.drawPoints(
          ui.PointMode.points,
          buendel[stufe],
          Paint()
            ..strokeWidth = math.max(1.0, punktBreite)
            ..strokeCap = StrokeCap.square
            // Additiv: Wo sich in der Parade zwei Kanäle decken, entsteht
            // die Mischfarbe – dasselbe Verhalten wie beim RGB-Histogramm.
            ..blendMode = BlendMode.plus
            ..color = farbe.withValues(alpha: (stufe + 1) / _stufen),
        );
      }
    }

    if (parade) {
      final drittel = size.width / 3;
      zeichne(data.red, const Color(0xFFFF5252), 0, drittel);
      zeichne(data.green, const Color(0xFF69F0AE), drittel, drittel);
      zeichne(data.blue, const Color(0xFF448AFF), drittel * 2, drittel);
    } else {
      zeichne(data.luminance, Colors.white, 0, size.width);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      !identical(old.data, data) || old.parade != parade;
}
