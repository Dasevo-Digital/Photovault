import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/native_image_converter.dart';
import 'package:photo_vault/widgets/develop_preview.dart';

import 'hilfen/echte_arbeit.dart';

/// Bis 3.29 zeigte die Live-Vorschau Schärfe, Rauschminderung, Klarheit
/// und Vignette gar nicht: Der Entwickeln-Shader sieht je Aufruf nur
/// einen Pixel. Jetzt rechnet das Widget bei gesetztem Regler das Bild
/// durch die Nachbarpixel-Stufen und zeigt das Ergebnis.
void main() {
  testWidgets('die Vorschau zeigt die Vignette', (tester) async {
    final (shader, grau) = (await tester.runAsync(() async {
      final shader = await ladeDevelopShader();
      final pixel = Uint8List(64 * 64 * 4);
      for (var i = 0; i < pixel.length; i += 4) {
        pixel
          ..[i] = 128
          ..[i + 1] = 128
          ..[i + 2] = 128
          ..[i + 3] = 255;
      }
      return (shader, await texturVonBytes(pixel, 64, 64));
    }))!;
    expect(shader, isNotNull);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 64,
          height: 64,
          child: DevelopShaderPreview(
            shader: shader,
            image: grau,
            adjustments: const DevelopAdjustments(vignette: 0.8),
          ),
        ),
      ),
    );

    // Das Widget rechnet echt auf der GPU – erst dann zeigt es ein
    // anderes Bild als die Basis.
    ui.Image? gezeigt() {
      final roh = tester.widgetList<RawImage>(find.byType(RawImage));
      return roh.isEmpty ? null : roh.first.image;
    }

    expect(
      await warteAufEchteArbeit(tester, () {
        final bild = gezeigt();
        return bild != null && !identical(bild, grau);
      }),
      isTrue,
      reason: 'die Vorschau zeigt kein bearbeitetes Bild',
    );

    final pixel = (await tester.runAsync(
      () => gezeigt()!.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    int helligkeit(int x, int y) => pixel.getUint8((y * 64 + x) * 4);
    expect(helligkeit(1, 1), lessThan(100), reason: 'Ecke nicht abgedunkelt');
    expect(helligkeit(32, 32), closeTo(128, 2), reason: 'Mitte verändert');

    // Regler zurück auf null: wieder der direkte Weg ohne Zwischenbild.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 64,
          height: 64,
          child: DevelopShaderPreview(
            shader: shader,
            image: grau,
            adjustments: const DevelopAdjustments(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    shader!.dispose();
    grau.dispose();
  });
}
