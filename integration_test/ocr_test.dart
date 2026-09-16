import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/ocr_service.dart';

/// Texterkennung gegen die ECHTEN Modelle, nicht gegen Attrappen.
///
/// Als Integrationstest, weil die ONNX-Laufzeit eine echte Anbindung
/// braucht. Erwartet die Modelle unter `~/ocr_modelle` und ein Bild mit
/// bekanntem deutschen Text daneben; fehlt beides, überspringt sich der
/// Test, statt rot zu werden.
///
/// Aufruf auf der Linux-Maschine:
///   flutter test integration_test/ocr_test.dart -d linux

/// Der Heimatordner des angemeldeten Benutzers.
///
/// `HOME` setzt Windows nicht; dort heisst die Variable `USERPROFILE`.
/// Ohne diesen Zweig hiesse der gesuchte Ordner buchstäblich
/// `null/ocr_modelle`, und der Test meldete „Modelle fehlen" – was wie ein
/// fehlendes Modell aussieht und keins ist.
String heimat() =>
    Platform.environment['HOME'] ??
    Platform.environment['USERPROFILE'] ??
    Directory.current.path;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final ordner = p.join(heimat(), 'ocr_modelle');
  final bildDatei = File(p.join(ordner, 'probe_de.png'));

  testWidgets('liest deutschen Text samt Umlauten und ß', (tester) async {
    // Kein stilles Überspringen: Ein Test, der ohne Modelle grün meldet,
    // sagt nichts – und genau das ist hier schon einmal passiert, weil die
    // macOS-Sandbox ein anderes HOME hat als die Anmeldung.
    expect(OcrService.isAvailable(ordner), isTrue,
        reason: 'Modelle fehlen unter $ordner');
    expect(bildDatei.existsSync(), isTrue, reason: 'Probe fehlt unter $ordner');

    final dienst = await OcrService.load(ordner);
    addTearDown(dienst.dispose);

    final bild = img.decodeImage(await bildDatei.readAsBytes())!;
    final begonnen = DateTime.now();
    final text = await dienst.erkenneText(bild);
    final dauer = DateTime.now().difference(begonnen);

    // ignore: avoid_print
    print('--- erkannt in ${dauer.inMilliseconds} ms:\n$text\n---');

    expect(text, isNotEmpty, reason: 'gar kein Text gefunden');

    // Die beiden Zeilen, die in der Referenzkette fehlerfrei waren – sie
    // enthalten ß, Ziffern, Satzzeichen und Währung.
    expect(text, contains('Straße des 17. Juni 135'));
    expect(text, contains('12,50 EUR'));

    // Und der Umlaut-Nachweis: die chinesische Zeichentabelle hätte hier
    // „Strae" geliefert.
    expect(text, contains('ß'));
    expect(text.toLowerCase(), contains('öffnungszeiten'));
  });
}
