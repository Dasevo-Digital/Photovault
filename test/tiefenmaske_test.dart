import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/native_image_converter.dart';

/// Tiefenmasken laufen auf macOS über ImageIO und auf den anderen
/// Desktop-Systemen über libheif. Fehlt eine Auxiliary-Ebene, bleibt der
/// Zustand erklärbar statt eine leere Maske anzulegen.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pv_tiefe_'));
  tearDown(() => temp.deleteSync(recursive: true));

  File lege(String name) =>
      File(p.join(temp.path, name))..writeAsBytesSync(List.filled(64, 7));

  test('ein JPEG kann gar keine Tiefenkarte tragen', () async {
    // Der Unterschied, um den es geht: Bei einem JPEG ist "hier ginge
    // etwas, nur nicht auf dieser Plattform" schlicht falsch. Tiefendaten
    // kommen aus dem HEIC-Container einer iPhone-Portraetaufnahme.
    final e = await NativeImageConverter.tiefenmaske(lege('foto.jpg'));
    expect(e.stand, Tiefenmaskenstand.keineTiefendaten);
    expect(e.png, isNull);
  });

  test('bei HEIC ohne lesbare Auxiliary-Ebene bleibt der Zustand erklärbar',
      () async {
    if (Platform.isMacOS) return; // dort wird wirklich nachgesehen
    final e = await NativeImageConverter.tiefenmaske(lege('portraet.heic'));
    expect(e.stand, Tiefenmaskenstand.nichtAufDieserPlattform,
        reason:
            'die Datei könnte Tiefendaten tragen; das Werkzeug las aber keine');
    expect(e.png, isNull);
  });

  test('die Endungsliste bleibt bei dem, was Tiefendaten tragen kann', () {
    // RAW-Dateien tragen keine - die Tiefenkarte entsteht aus zwei
    // Kameras beim Auslösen und landet im HEIC-Container.
    expect(NativeImageConverter.tiefenFaehigeEndungen, {'.heic', '.heif'});
  });

  test('jeder Zustand hat eine eigene Bedeutung', () {
    // Ein bool koennte nur zwei davon erzaehlen, und eine davon waere
    // dann falsch (siehe Tiefenmaskenstand).
    expect(Tiefenmaskenstand.values, hasLength(4));
  });
}
