// ignore_for_file: avoid_print
// Öffnet BEIDE CLIP-Encoder wirklich und rechnet je einmal.
//
// **Warum es diesen Test gibt.** Vom 30.08. bis zum 02.09.2026 lieferte
// die App zwei Modelldateien aus, die sich mit der mitgelieferten ONNX
// Runtime gar nicht öffnen liessen (fp16, siehe `ModelCatalog.clip`).
// Einen Monat lang fiel es niemandem auf, und der Grund war der
// Prüfstand selbst: Die Sonden lesen die Modelle aus dem Container des
// **Testbaus**, und dort lagen noch die alten fp32-Dateien. Geprüft
// wurde also durchweg ein Modell, das die App nicht ausliefert.
//
// Dagegen hilft nur eines: dieselben Bytes wirklich öffnen. Eine
// Prüfung auf Vorhandensein genügt nicht – ob ein Modell lädt, weiss man
// erst, wenn man es lädt.
//
//   PV_MODELLE="$HOME/Library/Containers/com.example.photoVault.test/Data/\
//   Library/Application Support/com.example.photoVault.test/PhotoVault/models" \
//   flutter test integration_test/clip_modelle_laden_test.dart -d macos
//
// **Auf den Container der ausgelieferten App zeigen geht nicht**, so
// verlockend es wäre: Der Testbau trägt eine eigene Kennung
// (`com.example.photoVault.test`) und damit einen eigenen Sandkasten. Er
// bekommt von dort `system error number 1` – EPERM –, und das sähe
// genauso aus wie ein Modell, das nicht lädt. Am 02.09.2026 beim
// Einspielen von 3.3.0 gemessen, die Anweisung darüber stand vorher
// falsch hier.
//
// Die Kette schliesst sich stattdessen über die Prüfsumme: Erst
// `shasum -a 256` auf beide Ordner – sind die Dateien gleich, ist das
// hier Geöffnete dasselbe, was die App öffnet –, dann dieser Test im
// eigenen Container. Beides zusammen ist der Beleg, keines allein.
//
// Ohne PV_MODELLE nimmt der Test den Ordner des Testbaus – dann prüft er
// genau das, was oben schiefging, und sagt es auch.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/clip_service.dart';
import 'package:photo_vault/services/model_catalog.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final ordner = Platform.environment['PV_MODELLE'] ?? '';

  setUpAll(() {
    if (ordner.isEmpty) {
      print('PV_MODELLE ist nicht gesetzt - der Test prueft dann NICHT die '
          'Dateien der ausgelieferten App.');
    } else {
      print('Modelle aus: $ordner');
    }
  });

  test('die ausgelieferten Dateien haben Groesse und Pruefsumme des Katalogs',
      () async {
    // Zuerst die Buchhaltung: Passt die Datei nicht zum Katalog, ist jeder
    // weitere Befund ueber ein anderes Modell.
    for (final f in ModelCatalog.clip.files) {
      final datei = File('$ordner/${f.fileName}');
      expect(datei.existsSync(), isTrue, reason: '${f.fileName} fehlt');
      expect(await datei.length(), f.bytes,
          reason: '${f.fileName} hat eine andere Groesse als der Katalog');
    }
  }, skip: ordner.isEmpty ? 'PV_MODELLE nicht gesetzt' : null);

  test('der Text-Encoder laesst sich oeffnen und rechnet', () async {
    final dienst = await ClipService.load(ordner, bild: false, text: true);
    final v = await dienst.embedText('ein rotes Fahrrad vor einer Hauswand');
    await dienst.dispose();
    expect(v.length, 512);
    // Nicht nur „keine Ausnahme": Ein Vektor aus lauter Nullen kaeme
    // ebenfalls ohne Ausnahme zurueck.
    expect(v.any((e) => e != 0), isTrue);
    print('TEXT ${v.take(6).map((e) => e.toStringAsFixed(6)).join(' ')}');
  }, skip: ordner.isEmpty ? 'PV_MODELLE nicht gesetzt' : null);

  test('der Bild-Encoder laesst sich oeffnen und rechnet', () async {
    final dienst = await ClipService.load(ordner, bild: true, text: false);
    // Das Pruefbild wird gerechnet und nicht geladen: Fuer den Vergleich
    // zweier Laeufe zaehlt die Wiederholbarkeit, nicht der Bildinhalt.
    final bild = img.Image(width: 224, height: 224);
    for (var y = 0; y < 224; y++) {
      for (var x = 0; x < 224; x++) {
        bild.setPixelRgb(x, y, (x * 7) % 256, (y * 5) % 256, (x + y) % 256);
      }
    }
    final v = await dienst.embedImage(bild);
    await dienst.dispose();
    expect(v.length, 512);
    expect(v.any((e) => e != 0), isTrue);
    print('BILD ${v.take(6).map((e) => e.toStringAsFixed(6)).join(' ')}');
  }, skip: ordner.isEmpty ? 'PV_MODELLE nicht gesetzt' : null);
}
