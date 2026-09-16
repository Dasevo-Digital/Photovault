// ignore_for_file: avoid_print
// Antwortet der Standortkanal? `null` ist ein gueltiges Ergebnis (keine
// Erlaubnis, keine Ortung) - was hier zaehlt, ist dass er ueberhaupt
// antwortet und nicht haengenbleibt oder wirft.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/native_image_converter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('Standortabfrage antwortet', () async {
    print('standortMoeglich = ${NativeImageConverter.standortMoeglich}');
    final uhr = Stopwatch()..start();
    final ort = await NativeImageConverter.aktuellerStandort();
    uhr.stop();
    // Bewusst OHNE die Koordinaten: Ein Testprotokoll ist kein Ort fuer
    // den Wohnort dessen, der es laufen laesst.
    print('Antwort nach ${uhr.elapsedMilliseconds} ms: '
        '${ort == null ? "kein Standort" : "Standort da, +/- ${ort.genauigkeit} m"}');
    // Die Zeitgrenze im Swift-Teil sind zwoelf Sekunden.
    expect(uhr.elapsed, lessThan(const Duration(seconds: 20)));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
