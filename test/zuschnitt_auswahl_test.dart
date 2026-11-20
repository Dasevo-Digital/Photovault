import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/bildzuschnitt.dart';
import 'package:photo_vault/widgets/zuschnitt_auswahl.dart';

void main() {
  testWidgets(
    'ziehen wählt Originalkoordinaten, Tippen setzt nur den Ausschnitt zurück',
    (tester) async {
      final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 40, height: 20)),
      );
      var z = Bildzuschnitt(drehungen: 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 200,
                child: StatefulBuilder(
                  builder: (context, neu) => ZuschnittAuswahl(
                    jpeg: jpeg,
                    wert: z,
                    beiAuswahl: (x) => neu(() => z = x),
                    beschreibung: 'Zuschnitt',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ort = tester.getTopLeft(find.byType(ZuschnittAuswahl));
      final g = await tester.startGesture(ort + const Offset(100, 50));
      await g.moveTo(ort + const Offset(300, 150));
      await g.up();
      await tester.pump();
      expect(z.links, closeTo(.25, .01));
      expect(z.oben, closeTo(.25, .01));
      expect(z.breite, closeTo(.5, .01));
      expect(z.hoehe, closeTo(.5, .01));
      expect(z.drehungen, 1);
      await tester.tap(find.byType(ZuschnittAuswahl));
      await tester.pump();
      expect((z.links, z.oben, z.breite, z.hoehe), (0, 0, 1, 1));
      expect(z.drehungen, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
