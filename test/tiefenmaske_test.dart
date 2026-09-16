import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/native_image_converter.dart';

/// Die Tiefenmaske gibt es nur unter macOS. Diese Tests halten fest, was
/// die App auf den anderen Plattformen SAGT – denn das ist der eigentliche
/// Entwurf: Ein Foto, das die Funktion auf einem anderen Rechner hätte,
/// soll das auch sagen, statt den Eintrag stillschweigend wegzulassen.
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

  test('bei HEIC ausserhalb von macOS wird die Plattform genannt', () async {
    if (Platform.isMacOS) return; // dort wird wirklich nachgesehen
    final e = await NativeImageConverter.tiefenmaske(lege('portraet.heic'));
    expect(e.stand, Tiefenmaskenstand.nichtAufDieserPlattform,
        reason: 'sonst hiesse es faelschlich "keine Tiefendaten"');
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
