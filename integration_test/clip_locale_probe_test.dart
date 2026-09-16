// ignore_for_file: avoid_print
// Einmalige Sonde: Gibt ein CLIP-Text-Embedding als Zahlen aus, damit sich
// zwei Laeufe vergleichen lassen.
//
// Anlass: Die Ursache des HardSwish-Fehlers war eine locale-abhaengige
// Textumwandlung in ONNX, und sie trifft laut Plugin nicht nur HardSwish,
// sondern jeden funktionsdefinierten Operator mit gebrochener Konstante im
// Rumpf - genannt werden LayerNormalization und Gelu. CLIP benutzt beide.
// Also nachsehen, ob dieselbe Eingabe mit 1.8.3 und 1.8.4 dasselbe ergibt.
//
//   flutter test integration_test/clip_locale_probe_test.dart -d linux
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/clip_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('CLIP-Text-Embedding ausgeben', () async {
    final ordner = Platform.environment['PV_MODELLE'] ??
        '${Platform.environment['HOME']}/.var/app/com.example.PhotoVault/data'
            '/com.example.photo_vault/PhotoVault/models';

    if (!ClipService.isAvailable(ordner)) {
      markTestSkipped('CLIP nicht installiert in $ordner');
      return;
    }

    print('LC_NUMERIC=${Platform.environment['LC_NUMERIC'] ?? '(nicht gesetzt)'}');

    final dienst = await ClipService.load(ordner, bild: false, text: true);
    final v = await dienst.embedText('ein rotes Fahrrad vor einer Hauswand');
    await dienst.dispose();

    // Die ersten zwoelf Werte genuegen zum Vergleich; ein falsch gelesener
    // Epsilon-Wert in LayerNormalization schluege auf jede Stelle durch.
    print('EMBEDDING ${v.take(12).map((e) => e.toStringAsFixed(6)).join(' ')}');
    var summe = 0.0;
    for (final e in v) {
      summe += e * e;
    }
    print('LAENGE ${v.length}  QUADRATSUMME ${summe.toStringAsFixed(6)}');

    expect(v.length, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
