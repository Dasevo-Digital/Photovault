import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/florence_captioning_service.dart';
import 'package:photo_vault/services/model_download_service.dart';

/// Die beiden Teile des neuen Beschreibungsmodells, die sich ohne
/// ONNX-Sitzung prüfen lassen: die Wiederholungsbremse und das Aufräumen
/// des abgelösten Vorgängers.
void main() {
  group('Wiederholungsbremse', () {
    test('sperrt nichts, solange die Folge zu kurz ist', () {
      expect(gesperrteToken([5], 3), isEmpty);
      expect(gesperrteToken([5, 7], 3), isEmpty);
    });

    test('sperrt die Fortsetzung einer schon dagewesenen Folge', () {
      // „a b c … a b" – ein weiteres c schlösse dieselbe Dreierfolge.
      expect(gesperrteToken([1, 2, 3, 9, 1, 2], 3), contains(3));
    });

    test('lässt eine andere Fortsetzung zu', () {
      expect(gesperrteToken([1, 2, 3, 9, 1, 2], 3), isNot(contains(9)));
    });

    test('bricht die Schleife, in der das alte Modell hängen blieb', () {
      // „Gruppe von Männern … Gruppe von" – ohne Bremse käme wieder
      // „Männern", und so fort. Genau dieser Satz stand in der
      // Prüfstichprobe.
      const gruppe = 11, von = 12, maenner = 13, raum = 14;
      final bisher = [gruppe, von, maenner, raum, gruppe, von];
      expect(gesperrteToken(bisher, 3), contains(maenner));
    });

    test('n kleiner als zwei schaltet die Bremse ab', () {
      expect(gesperrteToken([1, 2, 3, 1, 2], 1), isEmpty);
    });
  });

  group('Abgelöstes Modell aufräumen', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('florence_aufraeumen');
    });
    tearDown(() => temp.deleteSync(recursive: true));

    test('entfernt die drei Dateien des Vorgängers und meldet die Bytes',
        () async {
      // Sie stehen in keinem Katalogeintrag mehr und liessen sich deshalb
      // auch nicht mehr über die Modellverwaltung löschen.
      for (final (name, groesse) in [
        ('caption_encoder.onnx', 1000),
        ('caption_decoder.onnx', 2000),
        ('caption_vocab.json', 50),
      ]) {
        File('${temp.path}/$name').writeAsBytesSync(List.filled(groesse, 0));
      }
      File('${temp.path}/clip_image_encoder.onnx').writeAsBytesSync([1, 2, 3]);

      final dienst = ModelDownloadService(temp.path);
      expect(await dienst.raeumeAbgeloesteModelle(), 3050);

      expect(File('${temp.path}/caption_encoder.onnx').existsSync(), isFalse);
      expect(File('${temp.path}/caption_decoder.onnx').existsSync(), isFalse);
      expect(File('${temp.path}/caption_vocab.json').existsSync(), isFalse);
      expect(File('${temp.path}/clip_image_encoder.onnx').existsSync(), isTrue,
          reason: 'andere Modelle bleiben unangetastet');
    });

    test('ein zweiter Lauf findet nichts mehr und stört nicht', () async {
      final dienst = ModelDownloadService(temp.path);
      expect(await dienst.raeumeAbgeloesteModelle(), 0);
      expect(await dienst.raeumeAbgeloesteModelle(), 0);
    });
  });
}
