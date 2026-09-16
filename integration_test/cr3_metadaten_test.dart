// ignore_for_file: avoid_print
// Prüft den nativen Weg für Aufnahmewerte an einer ECHTEN CR3-Datei.
//
// Muss integration_test sein: NativeImageConverter geht über einen
// MethodChannel, den `flutter test` nicht hat. Die Datei liegt im
// tmp-Ordner des Test-Containers – der sandboxte Testbau kommt an
// beliebige Pfade nicht heran.
//
//   flutter test integration_test/cr3_metadaten_test.dart -d macos
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/native_image_converter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('CR3: Kamera, Objektiv und Aufnahmezeitpunkt', () async {
    final datei = File('${Directory.systemTemp.path}/EOS_R10.CR3');
    if (!datei.existsSync()) {
      // Sichtbar überspringen statt still grün zu sein: Die Datei muss
      // vorher in den tmp-Ordner des Test-Containers gelegt werden, weil
      // der sandboxte Testbau an beliebige Pfade nicht herankommt.
      markTestSkipped('${datei.path} fehlt – CC0-Muster dorthin kopieren');
      return;
    }
    final d = await NativeImageConverter.readCameraMetadata(datei);
    print('MAKE=${d.kamera.make}');
    print('MODEL=${d.kamera.model}');
    print('LENS=${d.kamera.lensModel}');
    print('ISO=${d.kamera.iso} F=${d.kamera.fNumber} '
        'MM=${d.kamera.focalLengthMm} T=${d.kamera.exposureTimeSeconds}');
    print('ZEIT=${d.zeitpunkt}');

    expect(d.kamera.model, 'Canon EOS R10');
    expect(d.kamera.lensModel, 'EF50mm f/1.8 STM');
    expect(d.zeitpunkt, DateTime(2022, 8, 19, 19, 19, 28));
    expect(d.kamera.iso, 1600);
  });
}
