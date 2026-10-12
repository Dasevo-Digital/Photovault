// ignore_for_file: avoid_print
// Die Spracherkennung im laufenden Programm, mit der ONNX Runtime der
// Plattform und dem echten Modell.
//
// Gebraucht wird ein Ordner mit den drei Modelldateien unter ihren
// App-Namen (whisper_encoder.onnx, whisper_decoder.onnx,
// whisper_vocab.json) und den Sprachproben: de1.wav, de2.wav, en1.wav
// (16 kHz, mono, 16 Bit), rauschen.wav und de1.m4a (dieselbe Probe als
// AAC in MP4, für das Herauslösen der Tonspur). Die Proben spricht die
// Sprachausgabe von macOS (`say`); sie liegen nicht im Repository.
//
//   macOS:   <Sandkasten der Test-App>/Data/tmp/whisper_probe
//   sonst:   PV_MODELLE=<ordner> flutter test integration_test/whisper_test.dart -d linux
//
// Fehlt der Ordner, meldet der Test das und prüft nichts.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/native_image_converter.dart';
import 'package:photo_vault/services/whisper_service.dart';

/// Die Abtastwerte einer WAV-Datei (16 Bit, mono) – den Chunk `data`
/// gesucht, nicht hinter 44 Bytes vermutet: afconvert legt davor weitere
/// Chunks ab.
Int16List wav(File datei) {
  final b = datei.readAsBytesSync();
  final d = ByteData.sublistView(b);
  var i = 12;
  while (i + 8 <= b.length) {
    final name = String.fromCharCodes(b.sublist(i, i + 4));
    final laenge = d.getUint32(i + 4, Endian.little);
    if (name == 'data') {
      final werte = Int16List(laenge ~/ 2);
      for (var k = 0; k < werte.length; k++) {
        werte[k] = d.getInt16(i + 8 + k * 2, Endian.little);
      }
      return werte;
    }
    i += 8 + laenge + (laenge.isOdd ? 1 : 0);
  }
  throw StateError('kein data-Chunk in ${datei.path}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Whisper hört, was gesagt wurde', (tester) async {
    await tester.runAsync(() async {
      final ordner =
          Platform.environment['PV_MODELLE'] ??
          p.join(Directory.systemTemp.path, 'whisper_probe');
      if (!WhisperService.isAvailable(ordner) ||
          !File(p.join(ordner, 'de1.wav')).existsSync()) {
        print('WHISPER kein Probeordner unter $ordner – nichts geprüft');
        return;
      }
      final uhr = Stopwatch()..start();
      final whisper = await WhisperService.load(ordner);
      print('WHISPER geladen in ${uhr.elapsedMilliseconds} ms');

      Future<Transkript?> hoere(Int16List pcm, String name) async {
        uhr.reset();
        final t = await whisper.transkribiere(pcm);
        print(
          'WHISPER $name (${(pcm.length / 16000).toStringAsFixed(1)} s) '
          'in ${uhr.elapsedMilliseconds} ms: [${t?.sprache}] ${t?.text}',
        );
        return t;
      }

      final de1 = await hoere(wav(File(p.join(ordner, 'de1.wav'))), 'de1');
      expect(de1?.sprache, 'de');
      expect(de1!.text, contains('Geburtstag'));
      expect(de1.text, contains('Garten'));

      final de2 = await hoere(wav(File(p.join(ordner, 'de2.wav'))), 'de2');
      expect(de2!.text, contains('Hamburg'));
      expect(de2.text, contains('Gleis'));

      final en1 = await hoere(wav(File(p.join(ordner, 'en1.wav'))), 'en1');
      expect(en1?.sprache, 'en');
      expect(en1!.text, contains('mountain'));

      final rauschen = await hoere(
        wav(File(p.join(ordner, 'rauschen.wav'))),
        'rauschen',
      );
      expect(rauschen, isNull, reason: 'Rauschen ist keine Sprache');

      // Die Tonspur aus einem MP4-Behälter (AAC), über den Weg der
      // Plattform – AVFoundation oder ffmpeg.
      uhr.reset();
      final ton = await NativeImageConverter.videoTon(
        File(p.join(ordner, 'de1.m4a')),
      );
      print(
        'WHISPER Tonspur: ${ton?.length} Werte '
        '(${((ton?.length ?? 0) / 16000).toStringAsFixed(1)} s) '
        'in ${uhr.elapsedMilliseconds} ms',
      );
      expect(ton, isNotNull, reason: 'Tonspur nicht lesbar');
      expect(ton!.length / 16000, closeTo(8.2, 1.5));
      final ausVideo = await hoere(ton, 'de1.m4a');
      expect(ausVideo!.text, contains('Geburtstag'));
      await whisper.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
