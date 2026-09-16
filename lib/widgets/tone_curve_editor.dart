import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../services/develop_color.dart';
import '../services/histogram.dart';
import '../theme/app_spacing.dart';
import 'histogram_view.dart';
import '../theme/app_theme.dart';

/// Fangradius in Pixeln, innerhalb dessen ein Tipp einen vorhandenen Punkt
/// greift statt einen neuen anzulegen. Grosszügig gewählt: Ein versehentlich
/// gesetzter Punkt ist lästiger als ein danebengegriffener.
const _fangradius = 18.0;

/// Mindestabstand zweier Punkte auf der Eingangsachse. Zwei Punkte exakt
/// übereinander ergäben eine senkrechte Sekante – die Interpolation müsste
/// dann durch null teilen.
const _mindestabstand = 0.02;

/// Das Zeichenfeld selbst – benannt, damit Tests seine Bildschirmkoordinaten
/// eindeutig bestimmen können. Ohne Schlüssel müssten sie über die Anzahl
/// gezeichneter Flächen raten, und das bräche bei jeder Layoutänderung.
const toneCurveRasterKey = Key('tonwertkurve-raster');

/// Editor für die Tonwertkurve.
///
/// Hinter dem Raster liegt die Tonwertverteilung des aktuellen Bildes. Das
/// ist nicht Zierde, sondern der Bezugspunkt: Man zieht die Kurve dorthin,
/// wo die Tonwerte tatsächlich liegen. Ohne sie zieht man ins Blaue.
class ToneCurveEditor extends StatefulWidget {
  final ToneCurve curve;
  final HistogramData? histogram;

  /// Während des Ziehens, für die Live-Vorschau.
  final ValueChanged<ToneCurve> onChanged;

  /// Nach dem Loslassen – Anlass für den massgeblichen nativen Render.
  final VoidCallback onChangeEnd;

  const ToneCurveEditor({
    super.key,
    required this.curve,
    required this.histogram,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<ToneCurveEditor> createState() => _ToneCurveEditorState();
}

class _ToneCurveEditorState extends State<ToneCurveEditor> {
  CurveChannel _kanal = CurveChannel.zusammen;
  int? _gezogen;

  /// Arbeitskopie für die Dauer einer Geste.
  ///
  /// Ohne sie läse jeder Zwischenschritt `widget.curve` – also den Stand
  /// VOR dem eigenen vorigen Aufruf, denn der Elternteil baut erst im
  /// nächsten Bild neu auf. Treffen zwei Zeigerbewegungen im selben Bild
  /// ein (bei 120 Hz Eingabe der Normalfall), rechnete der zweite Schritt
  /// dann mit veralteten Punkten: Ein gerade angelegter Punkt wäre wieder
  /// verschwunden und der Zeigefinger schöbe stattdessen den Endpunkt.
  List<CurvePoint>? _arbeit;

  /// Wo der Zeiger tatsächlich aufgesetzt wurde.
  ///
  /// `onPanStart` meldet erst die Stelle, an der die Geste als Ziehen
  /// erkannt wurde – bei einem Finger nach 18 Pixeln Weg. Bis dahin ist der
  /// Zeiger von dem Punkt, den der Nutzer greifen wollte, weit genug weg,
  /// dass der Fangradius nicht mehr trifft: Statt den Punkt zu verschieben,
  /// entstünde daneben ein neuer. `onPanDown` meldet die wahre Stelle
  /// sofort.
  Offset? _abgesetzt;

  List<CurvePoint> get _punkte => _arbeit ?? widget.curve.kanal(_kanal);

  /// Bildschirmkoordinate eines Kurvenpunkts. Die Ausgangsachse zeigt nach
  /// oben, die Bildschirmachse nach unten – daher das gespiegelte y.
  Offset _zuBild(CurvePoint p, Size size) =>
      Offset(p.input * size.width, (1 - p.output) * size.height);

  CurvePoint _zuKurve(Offset o, Size size) => CurvePoint(
        (o.dx / size.width).clamp(0.0, 1.0),
        (1 - o.dy / size.height).clamp(0.0, 1.0),
      );

  void _setze(List<CurvePoint> neu) {
    setState(() => _arbeit = neu);
    widget.onChanged(widget.curve.mitKanal(_kanal, neu));
  }

  int? _treffer(Offset stelle, Size size) {
    for (var i = 0; i < _punkte.length; i++) {
      if ((_zuBild(_punkte[i], size) - stelle).distance <= _fangradius) return i;
    }
    return null;
  }

  void _beginn(Offset stelle, Size size) {
    final treffer = _treffer(stelle, size);
    if (treffer != null) {
      setState(() {
        _gezogen = treffer;
        _arbeit = [..._punkte];
      });
      return;
    }

    // Kein Punkt in der Nähe: einen neuen anlegen, an der richtigen Stelle
    // einsortiert. Das ist der übliche Weg, eine Kurve zu formen – ein
    // eigener "Punkt hinzufügen"-Knopf wäre ein Umweg.
    final neuerPunkt = _zuKurve(stelle, size);
    if (neuerPunkt.input <= _mindestabstand ||
        neuerPunkt.input >= 1 - _mindestabstand) {
      return;
    }
    final neu = [..._punkte];
    var index = neu.indexWhere((p) => p.input > neuerPunkt.input);
    if (index < 0) index = neu.length;
    // Zu dicht an einem Nachbarn: lieber gar nichts, als einen Punkt
    // anzulegen, der sich anschliessend nicht mehr greifen lässt.
    if (index > 0 && neuerPunkt.input - neu[index - 1].input < _mindestabstand) return;
    if (index < neu.length && neu[index].input - neuerPunkt.input < _mindestabstand) return;

    neu.insert(index, neuerPunkt);
    _gezogen = index;
    _setze(neu);
  }

  void _zieh(Offset stelle, Size size) {
    final index = _gezogen;
    if (index == null || index >= _punkte.length) return;
    final neu = [..._punkte];
    final roh = _zuKurve(stelle, size);

    // Die beiden Endpunkte bleiben am Rand und lassen sich nur in der Höhe
    // verschieben – so wie in Lightroom und darktable. Verschöbe man sie
    // waagerecht, hätte die Kurve plötzlich einen undefinierten Bereich.
    final istEnde = index == 0 || index == neu.length - 1;
    if (istEnde) {
      neu[index] = CurvePoint(neu[index].input, roh.output);
    } else {
      // Ein Punkt darf seine Nachbarn nicht überholen, sonst wäre die
      // Punktfolge nicht mehr geordnet.
      final links = neu[index - 1].input + _mindestabstand;
      final rechts = neu[index + 1].input - _mindestabstand;
      neu[index] = CurvePoint(roh.input.clamp(links, rechts), roh.output);
    }

    _setze(neu);
  }

  void _entferne(Offset stelle, Size size) {
    final treffer = _treffer(stelle, size);
    // Die Endpunkte bleiben: Ohne sie hätte die Kurve keinen Anfang und
    // kein Ende.
    if (treffer == null || treffer == 0 || treffer == _punkte.length - 1) return;
    final neu = [..._punkte]..removeAt(treffer);
    _gezogen = null;
    _setze(neu);
    setState(() => _arbeit = null);
    widget.onChangeEnd();
  }

  void _kanalZuruecksetzen() {
    _setze(const [CurvePoint(0, 0), CurvePoint(1, 1)]);
    setState(() => _arbeit = null);
    widget.onChangeEnd();
  }

  @override
  Widget build(BuildContext context) {
    final kanalIstNeutral = _punkte.length == 2 &&
        _punkte.first == const CurvePoint(0, 0) &&
        _punkte.last == const CurvePoint(1, 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Flexible, weil das Bedienfeld nur 300 px breit ist – siehe
            // ColorMixerPanel.
            Flexible(
              child: Text(
                AppTexte.of(context).kurveTitel,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: kanalIstNeutral ? null : _kanalZuruecksetzen,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(AppTexte.of(context).einstZuruecksetzen,
                  style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: Colors.white24),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  key: toneCurveRasterKey,
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (d) => _abgesetzt = d.localPosition,
                  onPanStart: (d) => _beginn(_abgesetzt ?? d.localPosition, size),
                  onPanUpdate: (d) => _zieh(d.localPosition, size),
                  onPanEnd: (_) {
                    // Arbeitskopie verwerfen: Ab hier ist widget.curve
                    // wieder die Quelle der Wahrheit.
                    setState(() {
                      _gezogen = null;
                      _arbeit = null;
                    });
                    widget.onChangeEnd();
                  },
                  onLongPressStart: (d) => _entferne(d.localPosition, size),
                  child: CustomPaint(
                    painter: _ToneCurvePainter(
                      punkte: _punkte,
                      kanal: _kanal,
                      histogram: widget.histogram,
                      gezogen: _gezogen,
                    ),
                    size: Size.infinite,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<CurveChannel>(
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: const [
            ButtonSegment(value: CurveChannel.zusammen, label: Text('RGB', style: TextStyle(fontSize: 11))),
            ButtonSegment(value: CurveChannel.rot, label: Text('R', style: TextStyle(fontSize: 11))),
            ButtonSegment(value: CurveChannel.gruen, label: Text('G', style: TextStyle(fontSize: 11))),
            ButtonSegment(value: CurveChannel.blau, label: Text('B', style: TextStyle(fontSize: 11))),
          ],
          selected: {_kanal},
          onSelectionChanged: (auswahl) => setState(() {
            _kanal = auswahl.first;
            _gezogen = null;
            // Sonst zeigte der neue Kanal die Punkte des alten.
            _arbeit = null;
          }),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 4),
        Text(
          AppTexte.of(context).kurveHinweis,
          style: const TextStyle(color: DunkleFlaeche.hinweis, fontSize: 11),
        ),
      ],
    );
  }
}

/// Farbe der Kurve je Kanal – dieselben Töne wie im RGB-Histogramm, damit
/// beide Anzeigen zusammenpassen.
const _kanalFarben = {
  CurveChannel.zusammen: Colors.white,
  CurveChannel.rot: Color(0xFFFF6666),
  CurveChannel.gruen: Color(0xFF66DD66),
  CurveChannel.blau: Color(0xFF6699FF),
};

class _ToneCurvePainter extends CustomPainter {
  final List<CurvePoint> punkte;
  final CurveChannel kanal;
  final HistogramData? histogram;
  final int? gezogen;

  _ToneCurvePainter({
    required this.punkte,
    required this.kanal,
    required this.histogram,
    required this.gezogen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _zeichneHistogramm(canvas, size);
    _zeichneRaster(canvas, size);
    _zeichneKurve(canvas, size);
    _zeichnePunkte(canvas, size);
  }

  void _zeichneHistogramm(Canvas canvas, Size size) {
    final daten = histogram;
    if (daten == null || daten.isEmpty) return;
    // Zurückhaltend: Die Verteilung soll den Blick führen, nicht mit der
    // Kurve um Aufmerksamkeit streiten.
    final (bins, farbe) = switch (kanal) {
      CurveChannel.zusammen => (daten.luminance, Colors.white24),
      CurveChannel.rot => (daten.red, const Color(0x33FF4444)),
      CurveChannel.gruen => (daten.green, const Color(0x3344FF44)),
      CurveChannel.blau => (daten.blue, const Color(0x334488FF)),
    };
    paintHistogramSilhouette(canvas, size, bins, daten.peakOf([bins]), farbe);
  }

  void _zeichneRaster(Canvas canvas, Size size) {
    final linie = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linie);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linie);
    }
    // Die Diagonale ist die unveränderte Kurve – der Bezug, gegen den man
    // die eigene Kurve liest.
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 1,
    );
  }

  void _zeichneKurve(Canvas canvas, Size size) {
    // Punktweise über dieselbe Funktion ausgewertet, die auch die Tabelle
    // für Shader und Core Image füllt. Eine eigene Zeichenmathematik hier
    // wäre eine dritte Fassung – und die einzige, die der Nutzer sieht.
    final pfad = Path();
    final schritte = size.width.round().clamp(2, 512);
    for (var i = 0; i <= schritte; i++) {
      final x = i / schritte;
      final y = evaluateCurve(punkte, x);
      final stelle = Offset(x * size.width, (1 - y) * size.height);
      if (i == 0) {
        pfad.moveTo(stelle.dx, stelle.dy);
      } else {
        pfad.lineTo(stelle.dx, stelle.dy);
      }
    }
    canvas.drawPath(
      pfad,
      Paint()
        ..color = _kanalFarben[kanal]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  void _zeichnePunkte(Canvas canvas, Size size) {
    for (var i = 0; i < punkte.length; i++) {
      final stelle = Offset(
        punkte[i].input * size.width,
        (1 - punkte[i].output) * size.height,
      );
      final aktiv = i == gezogen;
      canvas.drawCircle(stelle, aktiv ? 6 : 4.5, Paint()..color = _kanalFarben[kanal]!);
      canvas.drawCircle(
        stelle,
        aktiv ? 6 : 4.5,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ToneCurvePainter alt) =>
      alt.kanal != kanal ||
      alt.gezogen != gezogen ||
      !identical(alt.histogram, histogram) ||
      !_gleich(alt.punkte, punkte);

  static bool _gleich(List<CurvePoint> a, List<CurvePoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
