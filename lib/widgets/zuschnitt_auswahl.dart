import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:kern/services/bildzuschnitt.dart';
import 'package:kern/services/jpeg_icc.dart';

/// Die Geste bleibt im Originalkoordinatensystem. Eine anschließende
/// Vierteldrehung ändert weder Masken noch die Auswahlkoordinaten.
class ZuschnittAuswahl extends StatefulWidget {
  const ZuschnittAuswahl({
    super.key,
    required this.jpeg,
    required this.wert,
    required this.beiAuswahl,
    required this.beschreibung,
  });
  final Uint8List jpeg;
  final Bildzuschnitt wert;
  final ValueChanged<Bildzuschnitt> beiAuswahl;
  final String beschreibung;
  @override
  State<ZuschnittAuswahl> createState() => _ZuschnittAuswahlState();
}

class _ZuschnittAuswahlState extends State<ZuschnittAuswahl> {
  Offset? _anfang;
  Rect? _entwurf;
  @override
  Widget build(BuildContext context) {
    final m = JpegIcc.masse(widget.jpeg);
    final w = widget.wert;
    return Semantics(
      label: widget.beschreibung,
      child: Center(
        child: AspectRatio(
          aspectRatio: m.breite / m.hoehe,
          child: LayoutBuilder(
            builder: (context, c) {
              Offset norm(Offset p) => Offset(
                (p.dx / c.maxWidth).clamp(0, 1),
                (p.dy / c.maxHeight).clamp(0, 1),
              );
              return GestureDetector(
                dragStartBehavior: DragStartBehavior.down,
                onTap: () =>
                    widget.beiAuswahl(Bildzuschnitt(drehungen: w.drehungen)),
                onPanStart: (d) {
                  _anfang = norm(d.localPosition);
                },
                onPanUpdate: (d) {
                  setState(
                    () => _entwurf = Rect.fromPoints(
                      _anfang!,
                      norm(d.localPosition),
                    ),
                  );
                },
                onPanCancel: () => setState(() => _entwurf = null),
                onPanEnd: (_) {
                  final r = _entwurf;
                  setState(() => _entwurf = null);
                  if (r != null && r.width >= .01 && r.height >= .01) {
                    widget.beiAuswahl(
                      Bildzuschnitt(
                        links: r.left,
                        oben: r.top,
                        breite: r.width,
                        hoehe: r.height,
                        drehungen: w.drehungen,
                      ),
                    );
                  }
                },
                child: CustomPaint(
                  foregroundPainter: _Auswahlrahmen(
                    _entwurf ??
                        Rect.fromLTWH(w.links, w.oben, w.breite, w.hoehe),
                  ),
                  child: Image.memory(
                    widget.jpeg,
                    fit: BoxFit.fill,
                    width: c.maxWidth,
                    height: c.maxHeight,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Auswahlrahmen extends CustomPainter {
  const _Auswahlrahmen(this.rect);
  final Rect rect;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      rect.left * size.width,
      rect.top * size.height,
      rect.width * size.width,
      rect.height * size.height,
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(r),
      Paint()..color = Colors.black54,
    );
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(r, p);
    p
      ..color = Colors.white54
      ..strokeWidth = 1;
    for (final t in [1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(r.left + r.width * t, r.top),
        Offset(r.left + r.width * t, r.bottom),
        p,
      );
      canvas.drawLine(
        Offset(r.left, r.top + r.height * t),
        Offset(r.right, r.top + r.height * t),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_Auswahlrahmen old) => old.rect != rect;
}
