import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/model_catalog.dart';
import 'package:photo_vault/services/model_download_service.dart';
import 'package:photo_vault/services/translation_service.dart';

/// Die Katalogeinträge der beiden Übersetzungsrichtungen und ihr
/// Zusammenspiel mit dem Verfügbarkeits-Check.
///
/// Die eigentliche Inferenz lässt sich hier nicht prüfen –
/// `flutter_onnxruntime` hängt an einem Method-Channel und ist in
/// `flutter test` nicht ladbar. Sie wurde stattdessen mit einem realen
/// Python-`onnxruntime`-Lauf gegen dieselben Dateien belegt (siehe die
/// Anmerkungen in model_catalog.dart). Was hier bleibt, ist die Verdrahtung
/// – und die trägt jeden Fehler, der beim Herunterladen erst nach 100 MB
/// auffiele.
void main() {
  late Directory dir;
  late ModelDownloadService dienst;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pv_uebersetzung_');
    dienst = ModelDownloadService(dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Legt eine Attrappe in der Länge, die der Katalog nennt.
  ///
  /// Ein blosses `'x'` genügt seit der 21. Prüfrunde nicht mehr:
  /// [ModelDownloadService.isEntryInstalled] vergleicht die Länge mit
  /// [ModelFile.bytes], damit eine abgebrochene Übertragung nicht als
  /// fertig gilt und eine geänderte Fassung im Katalog die alte Datei
  /// nicht stillschweigend überlebt.
  void lege(String name) {
    final laenge = ModelCatalog.all
        .expand((e) => e.files)
        .firstWhere((f) => f.fileName == name)
        .bytes;
    // Als Loch-Datei: Die Attrappen zusammen sind über 100 MB, und
    // geschrieben werden müssen sie nicht – geprüft wird die Länge.
    final datei = File('${dir.path}/$name').openSync(mode: FileMode.write);
    datei.truncateSync(laenge);
    datei.closeSync();
  }

  test('beide Richtungen stehen im Katalog', () {
    expect(ModelCatalog.all, contains(ModelCatalog.translationEnDe));
    expect(ModelCatalog.all, contains(ModelCatalog.translationDeEn));
  });

  test('jede Datei hat eine Prüfsumme und eine Quelle', () {
    for (final eintrag in [ModelCatalog.translationEnDe, ModelCatalog.translationDeEn]) {
      expect(eintrag.files, hasLength(3), reason: eintrag.id);
      for (final datei in eintrag.files) {
        expect(datei.sha256, hasLength(64), reason: '${eintrag.id}/${datei.fileName}');
        expect(datei.url, startsWith('https://huggingface.co/'));
      }
    }
  });

  test('beide Richtungen teilen sich dieselbe Wörterbuchdatei', () {
    // Die tokenizer.json beider Modelle ist Byte für Byte identisch
    // (geprüft) – OPUS-MT nutzt für ein Sprachpaar ein gemeinsames
    // SentencePiece-Wörterbuch. Derselbe Zielname sorgt dafür, dass es
    // nur einmal geladen wird, egal welche Richtung zuerst kommt.
    final enDe = ModelCatalog.translationEnDe.files.firstWhere((f) => f.fileName.endsWith('.json'));
    final deEn = ModelCatalog.translationDeEn.files.firstWhere((f) => f.fileName.endsWith('.json'));
    expect(enDe.fileName, deEn.fileName);
    expect(enDe.sha256, deEn.sha256);
  });

  test('die Modelldateien der Richtungen kollidieren nicht', () {
    // Gleiche Namen für verschiedene Gewichte wären fatal: Die zweite
    // Richtung überschriebe die erste, und beide übersetzten danach
    // dasselbe.
    final enDe = ModelCatalog.translationEnDe.files
        .where((f) => f.fileName.endsWith('.onnx'))
        .map((f) => f.fileName);
    final deEn = ModelCatalog.translationDeEn.files
        .where((f) => f.fileName.endsWith('.onnx'))
        .map((f) => f.fileName);
    expect(enDe.toSet().intersection(deEn.toSet()), isEmpty);
  });

  test('die Prüfsummen der beiden Encoder sind verschieden', () {
    // Sie sind exakt gleich gross – ein vertauschter oder kopierter
    // Eintrag fiele über die Grösse nicht auf.
    final a = ModelCatalog.translationEnDe.files.first.sha256;
    final b = ModelCatalog.translationDeEn.files.first.sha256;
    expect(a, isNot(b));
  });

  group('Verfügbarkeit', () {
    test('ohne Dateien ist keine Richtung verfügbar', () {
      for (final r in Uebersetzungsrichtung.values) {
        expect(TranslationService.isAvailable(dir.path, r), isFalse, reason: r.name);
      }
    });

    test('eine Richtung allein genügt für sich', () {
      lege('translate_vocab.json');
      lege('translate_en_de_encoder.onnx');
      lege('translate_en_de_decoder.onnx');

      expect(TranslationService.isAvailable(dir.path, Uebersetzungsrichtung.enDe), isTrue);
      expect(TranslationService.isAvailable(dir.path, Uebersetzungsrichtung.deEn), isFalse,
          reason: 'die Gegenrichtung braucht ihre eigenen Gewichte');
    });

    test('ohne Wörterbuch nützen die Gewichte nichts', () {
      lege('translate_en_de_encoder.onnx');
      lege('translate_en_de_decoder.onnx');
      expect(TranslationService.isAvailable(dir.path, Uebersetzungsrichtung.enDe), isFalse);
    });

    test('der Katalogeintrag und der Dienst meinen dieselben Dateien', () {
      // Liefen die beiden auseinander, meldete der Katalog "installiert",
      // während der Dienst die Dateien nicht fände – oder umgekehrt.
      for (final datei in ModelCatalog.translationDeEn.files) {
        lege(datei.fileName);
      }
      expect(dienst.isEntryInstalled(ModelCatalog.translationDeEn), isTrue);
      expect(TranslationService.isAvailable(dir.path, Uebersetzungsrichtung.deEn), isTrue);
    });
  });
}
