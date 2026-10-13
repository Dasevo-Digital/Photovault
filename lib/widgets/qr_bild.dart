import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Ein QR-Code – schwarz auf weiss mit Rand, wie Kameras ihn am besten
/// lesen, auch im dunklen Erscheinungsbild.
class QrBild extends StatelessWidget {
  const QrBild(this.daten, {super.key, this.kante = 220});

  final String daten;
  final double kante;

  @override
  Widget build(BuildContext context) {
    final bild = QrImage(
      QrCode.fromData(data: daten, errorCorrectLevel: QrErrorCorrectLevel.M),
    );
    return Semantics(
      image: true,
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.all(kante / 16),
        child: CustomPaint(size: Size.square(kante), painter: _QrMaler(bild)),
      ),
    );
  }
}

class _QrMaler extends CustomPainter {
  _QrMaler(this.bild);
  final QrImage bild;

  @override
  void paint(Canvas canvas, Size size) {
    final n = bild.moduleCount;
    final m = size.width / n;
    final farbe = Paint()..color = Colors.black;
    for (var z = 0; z < n; z++) {
      for (var s = 0; s < n; s++) {
        if (bild.isDark(z, s)) {
          // Etwas überlappend, damit zwischen Modulen keine Haarlinien
          // entstehen.
          canvas.drawRect(Rect.fromLTWH(s * m, z * m, m + 0.5, m + 0.5), farbe);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrMaler alt) => !identical(alt.bild, bild);
}
