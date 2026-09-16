import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/dateikennung.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/native_image_converter.dart';

/// Baut den Kopf eines ISO-BMFF-Kastens: vier Byte Länge, `ftyp`, Marke.
Uint8List bmff(String marke) => Uint8List.fromList([
      0x00, 0x00, 0x00, 0x18, //
      ...'ftyp'.codeUnits,
      ...marke.codeUnits,
    ]);

void main() {
  group('kennungAus', () {
    test('erkennt die echte HEIC-Datei, die sich .jpg nennt', () {
      // Byte für Byte die ersten zwölf der Datei aus der Bibliothek
      // (`FullSizeRender - Kopie.jpg`, 3022x3351, laut `sips` HEIC) –
      // abgelesen, nicht ausgedacht.
      final echt = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18, //
        0x66, 0x74, 0x79, 0x70, // ftyp
        0x68, 0x65, 0x69, 0x63, // heic
      ]);
      expect(kennungAus(echt), '.heic');
    });

    test('kennt die Marken der HEIF-Familie', () {
      for (final marke in ['heic', 'heix', 'heim', 'heis', 'hevc', 'mif1', 'msf1']) {
        expect(kennungAus(bmff(marke)), '.heic', reason: marke);
      }
      expect(kennungAus(bmff('avif')), '.avif');
      expect(kennungAus(bmff('avis')), '.avif');
    });

    test('ein Film im selben Kasten ist keine Antwort auf diese Frage', () {
      // MOV und MP4 tragen dasselbe `ftyp`. Sie hier als Bild
      // durchzureichen wäre schlimmer als zu schweigen.
      expect(kennungAus(bmff('qt  ')), isNull);
      expect(kennungAus(bmff('mp42')), isNull);
      expect(kennungAus(bmff('isom')), isNull);
    });

    test('erkennt die übrigen gängigen Bildformate', () {
      expect(kennungAus([0xFF, 0xD8, 0xFF, 0xE0]), '.jpg');
      expect(kennungAus([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), '.png');
      expect(kennungAus('GIF89a'.codeUnits), '.gif');
      expect(kennungAus([0x42, 0x4D, 0x00, 0x00]), '.bmp');
      expect(
        kennungAus([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]),
        '.webp',
      );
    });

    test('RIFF allein ist noch kein WebP', () {
      // Eine WAV-Datei fängt genauso an.
      expect(kennungAus([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WAVE'.codeUnits]), isNull);
    });

    test('schweigt bei TIFF – dort steckt jedes RAW-Format mit drin', () {
      // `II*\0` haben CR2, NEF, ARW und DNG genauso. Aus diesen vier
      // Bytes „TIFF" zu schliessen hiesse, jede RAW-Datei umzubenennen.
      expect(kennungAus([0x49, 0x49, 0x2A, 0x00]), isNull);
      expect(kennungAus([0x4D, 0x4D, 0x00, 0x2A]), isNull);
    });

    test('schweigt bei zu kurzen und bei unbekannten Bytes', () {
      expect(kennungAus([]), isNull);
      expect(kennungAus([0xFF, 0xD8]), isNull);
      expect(kennungAus('Hallo Welt!'.codeUnits), isNull);
      // `ftyp` an der richtigen Stelle, aber die Marke fehlt.
      expect(kennungAus([0, 0, 0, 0x18, ...'ftyp'.codeUnits]), isNull);
    });
  });

  group('ImportService.inhaltskennung', () {
    late Directory ordner;

    setUp(() async {
      ordner = await Directory.systemTemp.createTemp('kennung');
    });
    tearDown(() async => ordner.delete(recursive: true));

    test('liest die Bytes von der Platte, wenn sie nicht schon da sind', () async {
      final datei = File('${ordner.path}/heisst-so.jpg');
      // Absichtlich mehr als [kennungBytes], damit belegt ist, dass ein
      // Teilstück genügt.
      await datei.writeAsBytes([...bmff('heic'), ...List.filled(4096, 0)]);
      expect(await ImportService.inhaltskennung(datei, null), '.heic');
    });

    test('nimmt die schon gelesenen Bytes und fasst die Platte nicht an', () async {
      // Die Datei gibt es gar nicht – käme die Antwort von der Platte,
      // stünde hier `null`.
      final gibtEsNicht = File('${ordner.path}/nirgends.jpg');
      expect(
        await ImportService.inhaltskennung(gibtEsNicht, bmff('avif')),
        '.avif',
      );
    });

    test('eine fehlende Datei ist keine Ausnahme, sondern keine Auskunft', () async {
      expect(await ImportService.inhaltskennung(File('${ordner.path}/weg.jpg'), null), isNull);
    });

    test('die Weiche: der Inhalt schickt die Datei auf den nativen Weg', () async {
      // Das ist die Aussage, um die es geht. Die Endung `.jpg` steht
      // NICHT in [heicAndRawExtensions] – die erkannte Kennung schon,
      // und nur deshalb wird umgewandelt statt direkt dekodiert.
      final datei = File('${ordner.path}/FullSizeRender - Kopie.jpg');
      await datei.writeAsBytes(bmff('heic'));
      expect(heicAndRawExtensions.contains('.jpg'), isFalse);
      expect(
        heicAndRawExtensions.contains(await ImportService.inhaltskennung(datei, null)),
        isTrue,
      );
    });

    test('ein echtes JPEG bleibt auf dem direkten Weg', () async {
      final datei = File('${ordner.path}/echt.jpg');
      await datei.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 0)]);
      expect(
        heicAndRawExtensions.contains(await ImportService.inhaltskennung(datei, null)),
        isFalse,
      );
    });
  });
}
