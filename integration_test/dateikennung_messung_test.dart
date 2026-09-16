import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/native_image_converter.dart';

/// Der Beleg an der echten Datei: eine HEIC-Datei, die `.jpg` heisst,
/// bekommt jetzt Vorschaubild und Bildmasse.
///
/// **Warum als Integrationstest und nicht unter `test/`.** Die native
/// Bildumwandlung läuft über einen Plattformkanal; in `flutter test` gibt
/// es den nicht („Binding has not yet been initialized"). Nur im
/// gebauten Programm ist zu sehen, ob die Weiche wirklich greift.
///
/// **Und warum mit `--dart-define`.** Der Testbau ist
/// `com.example.photoVault.test` und sandkastet: Er liest weder
/// `~/Pictures` noch den Container der echten App. Die Datei wird deshalb
/// vorher in seinen eigenen Container gelegt und der Pfad hineingereicht.
/// `Platform.environment` greift dort nicht – der Test läuft im gebauten
/// Programm, nicht in der Werkzeugkette.
///
/// ```
/// T=~/Library/Containers/com.example.photoVault.test/Data/Documents/messung
/// cp <die Datei> "$T/heisst-jpg-ist-heic.jpg"
/// flutter test integration_test/dateikennung_messung_test.dart -d macos \
///   --dart-define=PV_HEIC="$T/heisst-jpg-ist-heic.jpg"
/// ```
const _pfad = String.fromEnvironment('PV_HEIC');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('eine HEIC-Datei namens .jpg wird umgewandelt und vermessen',
      (tester) async {
    final datei = File(_pfad);
    expect(await datei.exists(), isTrue,
        reason: 'PV_HEIC zeigt auf keine Datei: $_pfad');
    expect(datei.path.toLowerCase().endsWith('.jpg'), isTrue);

    // 1. Der Name lügt, die Bytes nicht.
    final kennung = await ImportService.inhaltskennung(datei, null);
    expect(kennung, '.heic');
    expect(heicAndRawExtensions.contains('.jpg'), isFalse);
    expect(heicAndRawExtensions.contains(kennung), isTrue);

    // 2. Der direkte Weg scheitert – das ist der Zustand von vorher.
    expect(
      await tester.runAsync(
          () async => decodeAndResizeThumbnail(await datei.readAsBytes())),
      isNull,
      reason: '`package:image` kann HEIC nicht, darum blieb alles leer',
    );

    // 3. Der native Weg, auf den die Kennung schickt, liefert.
    final umgewandelt = await tester.runAsync(
        () => NativeImageConverter.convertToJpegBytes(datei, maxDimension: 2048));
    expect(umgewandelt, isNotNull);

    final bild = await tester
        .runAsync(() async => decodeAndResizeThumbnail(umgewandelt!));
    expect(bild, isNotNull);

    // **Nicht die 3022x3351, die `sips` am Original nennt.** Die App
    // vermisst bei nativ umgewandelten Formaten die umgewandelte Fassung,
    // und die ist auf 2048 begrenzt. Das ist keine Nachlässigkeit dieser
    // Änderung, sondern der Zustand jedes HEIC und jedes CR3 in der
    // Bibliothek – in der Datenbank nachgesehen: 45 HEIC und 909 CR3
    // stehen dort samt und sonders mit hoechstens 2048 Punkten. Die
    // Datei reiht sich damit bei ihresgleichen ein statt eine Ausnahme
    // zu bleiben.
    expect(bild!.height, 2048);
    expect(bild.width, 1847);
    // Und es ist dasselbe Bild: 3022/3351 ist 1847/2048, auf ein
    // Tausendstel genau.
    expect(bild.width / bild.height, closeTo(3022 / 3351, 0.001));
    expect(bild.jpegBytes, isNotEmpty);
  }, skip: _pfad.isEmpty);
}
