// ignore_for_file: avoid_print
// Wie teuer ist es, die Bildgroesse durch vollstaendiges Dekodieren zu
// erfahren?
//
// `DevelopRender._ladeBild` dekodiert das Bild zuerst in voller Groesse,
// liest daraus Breite und Hoehe und dekodiert dann ein zweites Mal
// verkleinert. Genau das, was der Kommentar dort zu vermeiden
// beansprucht. Diese Messung stellt beide Wege nebeneinander.
import 'dart:ui' as ui;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/develop_render.dart';
import 'package:integration_test/integration_test.dart';

/// Ein Bild in der Groessenordnung einer heutigen Kamera. Rauschen statt
/// Flaeche, sonst schrumpft das JPEG auf ein Nichts und die Messung
/// bekaeme nichts zu tun.
Future<Uint8List> _grossesJpeg(int breite, int hoehe) async {
  final bild = img.Image(width: breite, height: hoehe);
  var z = 12345;
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      z = (z * 1103515245 + 12345) & 0x7fffffff;
      bild.setPixelRgb(x, y, z & 0xff, (z >> 8) & 0xff, (z >> 16) & 0xff);
    }
  }
  return img.encodeJpg(bild, quality: 88);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('voller Dekodierlauf gegen blosses Ablesen der Kopfdaten',
      (tester) async {
    // Das Testbild wird hier erzeugt statt mitgeliefert: Die App laeuft
    // unter macOS im Sandkasten und kaeme an eine Datei ausserhalb ihres
    // eigenen Bereichs nicht heran.
    final bytes = await _grossesJpeg(6000, 4000);
    const zielKante = 1600;

    // Weg 1: so, wie es heute laeuft.
    final u1 = Stopwatch()..start();
    final codec = await ui.instantiateImageCodec(bytes);
    final voll = (await codec.getNextFrame()).image;
    final b1 = voll.width, h1 = voll.height;
    u1.stop();
    final vollBytes = b1 * h1 * 4;
    voll.dispose();

    // Weg 2: Kopfdaten lesen, ohne Pixel zu erzeugen.
    final u2 = Stopwatch()..start();
    final puffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final beschreibung = await ui.ImageDescriptor.encoded(puffer);
    final b2 = beschreibung.width, h2 = beschreibung.height;
    beschreibung.dispose();
    u2.stop();

    print('Bild:              $b1 x $h1');
    print('Voll dekodieren:   ${u1.elapsedMilliseconds} ms, '
        '${(vollBytes / 1e6).toStringAsFixed(0)} MB RGBA im Speicher');
    print('Kopfdaten lesen:   ${u2.elapsedMilliseconds} ms, 0 MB');
    print('Zielkante:         $zielKante');

    expect(b2, b1, reason: 'beide Wege muessen dasselbe messen');
    expect(h2, h1);

    // Der Kern der Sache: Die Kopfdaten zu lesen muss um
    // Groessenordnungen billiger sein als das vollstaendige Dekodieren.
    // Waeren beide gleich teuer, brachte der Umbau nichts und der
    // Kommentar in develop_render.dart behauptete etwas Falsches.
    expect(u2.elapsedMilliseconds * 10, lessThan(u1.elapsedMilliseconds),
        reason: 'Kopfdaten $u2 gegen vollen Lauf $u1');

    // Und die Gegenprobe am echten Weg: Was DevelopRender laedt, muss die
    // verkleinerte Fassung sein, nicht das Original.
    final puffer2 = await ui.ImmutableBuffer.fromUint8List(bytes);
    final echterCodec = await ui.instantiateImageCodecWithSize(
      puffer2,
      getTargetSize: (b, h) => DevelopRender.zielGroesse(
          breite: b, hoehe: h, maxKante: zielKante),
    );
    final geladen = (await echterCodec.getNextFrame()).image;
    echterCodec.dispose();
    print('Tatsaechlich dekodiert: ${geladen.width} x ${geladen.height}, '
        '${(geladen.width * geladen.height * 4 / 1e6).toStringAsFixed(1)} MB');
    expect(geladen.width, zielKante);
    // Auf einen Punkt genau: Der Dekoder schneidet ab, wo die Rechnung
    // rundet. 1600 x 4000 / 6000 = 1066,67 -> er liefert 1066.
    expect(geladen.height, closeTo(zielKante * h1 / b1, 1));
    geladen.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
