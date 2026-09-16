// ignore_for_file: avoid_print
// Der ganze Weg der Tiefenmaske an einem echten Foto: ImageIO liest das
// Hilfsbild, Swift normiert es, Dart bekommt ein PNG.
//
// Braucht ein Portraetfoto eines neueren iPhones - nur solche tragen eine
// Tiefenkarte. Der Ordner wird uebergeben, damit kein Pfad im Verzeichnis
// steht:
//
//   flutter test integration_test/tiefenmaske_probe_test.dart -d macos \
//       --dart-define=FOTOS=/pfad/zu/fotos
//
// Ohne Angabe ueberspringt der Test sich selbst.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/native_image_converter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('eine echte Tiefenkarte wird zur Maske', () async {
    const ordner = String.fromEnvironment('FOTOS');
    if (ordner.isEmpty || !Directory(ordner).existsSync()) {
      print('kein Ordner uebergeben (--dart-define=FOTOS=...) - uebersprungen');
      return;
    }

    final heics = Directory(ordner)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.heic'))
        .toList();
    print('${heics.length} HEIC-Dateien gefunden');

    Uint8List? maske;
    var mitTiefe = 0;
    for (final f in heics) {
      final e = await NativeImageConverter.tiefenmaske(f);
      if (e.stand == Tiefenmaskenstand.verfuegbar) {
        mitTiefe++;
        maske ??= e.png;
      }
    }
    print('davon mit auswertbarer Tiefenkarte: $mitTiefe');
    expect(mitTiefe, greaterThan(0),
        reason: 'ohne ein Foto mit Tiefenkarte laesst sich das nicht abnehmen');

    // Das PNG muss eine echte Graustufenmaske sein - nicht einfarbig,
    // sonst haette die Normierung nichts gebracht.
    final bild = img.decodePng(maske!)!;
    print('Maske: ${bild.width}x${bild.height}, ${maske.length} Bytes');
    var min = 255, max = 0;
    for (var x = 0; x < bild.width; x += 4) {
      for (var y = 0; y < bild.height; y += 4) {
        final w = bild.getPixel(x, y).r.toInt();
        if (w < min) min = w;
        if (w > max) max = w;
      }
    }
    print('Wertebereich der Maske: $min bis $max');

    // Zum Ansehen ablegen, wenn gewuenscht. Eine Spannweite von 0 bis 255
    // haette auch Rauschen - ob es eine Tiefenkarte IST, sieht man nur.
    const raus = String.fromEnvironment('MASKE_NACH');
    if (raus.isNotEmpty) {
      File(raus).writeAsBytesSync(maske);
      print('Maske abgelegt: $raus');
    }
    expect(bild.width, greaterThan(0));
    expect(max - min, greaterThan(100),
        reason: 'eine Tiefenmaske ohne Spannweite waere keine Maske');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
