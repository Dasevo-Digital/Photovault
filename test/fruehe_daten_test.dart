import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/exif_camera.dart';

/// Alte Scans und Stammbäume tragen frühe Daten (#407).
///
/// Bis dahin verwarf der Import ein EXIF-Datum vor 1990, und die
/// Datumswahl begann je nach Stelle erst 1990 oder 2000. Ein Scan von 1985
/// bekam den Dateizeitstempel und liess sich auch von Hand nicht richten;
/// ein Lebensdatum vor 1800 sprengte die Wahl mit einer Zusicherung.
void main() {
  group('exifDatumAusText', () {
    test('ein Scan von 1985 behält sein Datum', () {
      expect(
        exifDatumAusText('1985:07:14 10:30:00'),
        DateTime(1985, 7, 14, 10, 30),
      );
      expect(exifDatumAusText('1890:01:01 12:00:00')?.year, 1890);
    });

    test('ungestellte Uhren ergeben weiter nichts', () {
      expect(exifDatumAusText('0000:00:00 00:00:00'), isNull);
      expect(exifDatumAusText('1970:01:01 00:00:00'), isNull);
      expect(exifDatumAusText('1825:12:31 23:59:59'), isNull);
    });
  });

  group('ersteWahl', () {
    test('die Grenze, solange der Wert nicht davor liegt', () {
      expect(ersteWahl(fruehesteAufnahme), fruehesteAufnahme);
      expect(ersteWahl(fruehesteAufnahme, DateTime(1985)), fruehesteAufnahme);
    });

    test('ein älterer Wert verschiebt sie auf sein Jahr', () {
      expect(ersteWahl(DateTime(1000), DateTime(812, 5, 3)), DateTime(812));
    });

    testWidgets('die Datumswahl öffnet auch mit einem frühen Wert', (
      tester,
    ) async {
      // Vorher: firstDate 1990 und ein Ausgangswert von 1985 – die Wahl
      // brach mit einer Zusicherung ab.
      final wert = DateTime(1985, 7, 14);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDatePicker(
                context: context,
                initialDate: wert,
                firstDate: ersteWahl(fruehesteAufnahme, wert),
                lastDate: DateTime(2030),
              ),
              child: const Text('wählen'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('wählen'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });
  });
}
