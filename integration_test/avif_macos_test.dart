@TestOn('mac-os')
library;

// ignore_for_file: avoid_print
// Kann der native macOS-Weg AVIF?
//
// Unter Linux und Windows ging jede AVIF-Datei an dcraw_emu und blieb
// deshalb ohne Vorschau; das ist behoben. Für macOS wurde bisher
// angenommen, ImageIO könne es – geprüft war das nie. Steht .avif zu
// Unrecht in heicAndRawExtensions, sähe der Nutzer dort dasselbe:
// ein Foto ohne Vorschau, das sich nicht öffnen lässt.
//
// Als Integrationstest, weil der native Kanal einen laufenden Prozess
// braucht.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_vault/services/native_image_converter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AVIF geht durch den nativen Kanal', (tester) async {
    expect(await NativeImageConverter.isSupported(), isTrue,
        reason: 'ohne den nativen Kanal prüft dieser Test nichts');

    // Die Vorlage liegt im Projektordner, die App im Sandkasten – also
    // erst in ihren eigenen Bereich kopieren. Die Bytes stehen hier
    // eingebettet, weil der Sandkasten den Projektordner nicht sieht.
    final ziel = Directory(p.join(
        (await getTemporaryDirectory()).path, 'avif_probe'));
    await ziel.create(recursive: true);
    final datei = File(p.join(ziel.path, 'probe.avif'));
    await datei.writeAsBytes(_probeAvif);
    print('Vorlage: ${datei.lengthSync()} Bytes');

    final jpeg = await NativeImageConverter.convertToJpegBytes(datei,
        maxDimension: 400);
    print('Ergebnis: ${jpeg?.length} Bytes');

    expect(jpeg, isNotNull,
        reason: 'AVIF blieb ohne Vorschau – dann gehört .avif nicht in '
            'heicAndRawExtensions, oder ImageIO braucht Hilfe');

    final bild = img.decodeImage(jpeg!)!;
    print('Bild: ${bild.width}x${bild.height}');
    // Links rot, rechts grün – sonst ist es irgendein Bild.
    final links = bild.getPixel(40, 200);
    final rechts = bild.getPixel(360, 200);
    print('links r=${links.r} g=${links.g}  rechts r=${rechts.r} g=${rechts.g}');
    expect(links.r, greaterThan(120));
    expect(rechts.g, greaterThan(80));
  });
}

/// Die 535-Byte-Vorlage aus `test/fixtures/werkzeuge/probe.avif`.
///
/// Eingebettet statt gelesen: Die macOS-Testfassung läuft im Sandkasten
/// und sieht den Projektordner nicht – `File(...).existsSync()` ist dort
/// schlicht `false`, wie beim Videotest gemessen.
final _probeAvif = base64Decode(
    'AAAAIGZ0eXBhdmlmAAAAAGF2aWZtaWYxbWlhZk1BMUIAAAD5bWV0YQAAAAAAAAAvaGRscgAAAAAA'
    'AAAAcGljdAAAAAAAAAAAAAAAAFBpY3R1cmVIYW5kbGVyAAAAAA5waXRtAAAAAAABAAAAHmlsb2MA'
    'AAAARAAAAQABAAAAAQAAASEAAAD2AAAAKGlpbmYAAAAAAAEAAAAaaW5mZQIAAAAAAQAAYXYwMUNv'
    'bG9yAAAAAGppcHJwAAAAS2lwY28AAAAUaXNwZQAAAAAAAAGQAAABkAAAABBwaXhpAAAAAAMICAgA'
    'AAAMYXYxQ4EBDAAAAAATY29scm5jbHgAAgACAAIAAAAAF2lwbWEAAAAAAAAAAQABBAECgwQAAAD+'
    'bWRhdAoLAgAADWIx+PGr5gEy5gEQAJEggwwYYIA8AgGLSP7NvHTDygX3OmVYCyM1ZijnhgcOTDML'
    'SZ/9TTP7pCd0k76sGsXI9mPUQtXMRNiwsY7RpVtHKKQ/4iWCbEdixsZCgV08mbeg2xGrn3ijMxaT'
    'QF6Lof/HN8ggS0XnydXfilXK6RJsgKDWroD8xmyogN2tvOx1pOVZkbplY8Eax44O0j9MQ1urB842'
    'mX0j19qQJaAE1kTSL1URBvfce1ycLLOr4udhrLT734Yu7LKBastAAj7UF0GYBsHR8ZZPC2ziSAlR'
    'HqgODlNcoeKE29SRdbQ8L/zt0prk3A==');
