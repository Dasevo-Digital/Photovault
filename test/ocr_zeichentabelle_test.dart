import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/model_catalog.dart';
import 'package:photo_vault/services/ocr_service.dart';

/// **Die Zeichentabelle des Lesemodells.**
///
/// Sie steht seit dem Wechsel auf `latin_PP-OCRv5` in der Konfiguration des
/// Modells und nicht mehr in einer eigenen Textdatei. Das ist der Grund für
/// diesen Prüfstand: Die Tabelle ist keine Liste von Zeichen, sondern eine
/// **Zuordnung von Klassennummer zu Zeichen**. Ein Eintrag zu viel, zu
/// wenig oder an falscher Stelle verschiebt alles dahinter, und das Modell
/// liest dann nicht schlechter, sondern Unsinn – ohne dass irgendetwas
/// fehlschlägt.
///
/// Geprüft wird gegen die **echte** ausgelieferte Datei unter
/// `test/fixtures/ocr/ocr_rec.yml`; ihre Prüfsumme steht im Katalog.
void main() {
  final echte = File('test/fixtures/ocr/ocr_rec.yml');

  /// Die Zahl der Klassen, die das Modell wirklich ausgibt – nachgemessen
  /// an `inference.onnx`: Ausgabeform [N, T, 838]. Daraus folgt die
  /// Rechnung unten, und sie ist der eigentliche Beweis, dass die Tabelle
  /// vollständig gelesen wurde.
  const klassenDesModells = 838;

  test('die echte Datei liefert 836 Zeichen', () {
    expect(echte.existsSync(), isTrue, reason: 'Vorlage fehlt');
    final tabelle = OcrService.zeichenAusKonfig(echte.readAsStringSync());
    expect(tabelle, hasLength(836));
  });

  test('Tabelle plus Leerplatz plus Leerzeichen ergibt die Klassenzahl', () {
    // Die Probe, die alles zusammenhält: Das Modell gibt 838 Klassen aus,
    // die Tabelle hat 836, und OcrService.load setzt vorn den CTC-Leerplatz
    // und hinten das Leerzeichen. Geht diese Rechnung nicht auf, ist die
    // Zuordnung verschoben – und genau das würde man am Ergebnis nicht als
    // Fehler erkennen, sondern für ein schlechtes Modell halten.
    final tabelle = OcrService.zeichenAusKonfig(echte.readAsStringSync());
    expect(1 + tabelle.length + 1, klassenDesModells);
  });

  test('quotierte Zeichen kommen ausgepackt heraus', () {
    // 31 der 836 Einträge sind quotiert – Ziffern und Satzzeichen, die YAML
    // sonst missverstünde. Blieben die Anführungszeichen stehen, stünde
    // statt „0" die Zeichenfolge „'0'" in der Tabelle: drei Zeichen, und
    // alles dahinter verschoben.
    final tabelle = OcrService.zeichenAusKonfig(echte.readAsStringSync());
    for (final z in ['0', '9', '!', '"', '#', '%', '&', '*', ',', '-', ':']) {
      expect(tabelle, contains(z), reason: 'Zeichen $z fehlt');
    }
    // Nicht „kein Eintrag beginnt mit einem Apostroph": Der Apostroph
    // selbst IST ein Zeichen der Tabelle. Die tragfähige Zusage ist, dass
    // jeder Eintrag genau ein Zeichen lang ist – ein nicht ausgepacktes
    // `'0'` wären drei.
    //
    // Gezählt wird in RUNEN, nicht in Dart-Codeeinheiten: Zwei Einträge
    // der Tabelle (𝑢 und 𝜓, mathematische Kursive) liegen ausserhalb der
    // Grundebene und zählen als zwei Einheiten. Mit `length` wäre diese
    // Prüfung an echten, richtigen Daten rot geworden.
    expect(tabelle.where((z) => z.runes.length != 1), isEmpty,
        reason: 'jeder Eintrag ist genau ein Zeichen');
  });

  test('der doppelte Apostroph wird zu einem', () {
    // YAMLs Schreibweise für einen Apostroph ist `''''`. Ohne diese
    // Auflösung stünde dort ein Eintrag aus zwei Zeichen.
    final tabelle = OcrService.zeichenAusKonfig(echte.readAsStringSync());
    expect(tabelle, contains("'"));
  });

  test('die deutschen Zeichen sind alle dabei', () {
    // Der Grund, warum überhaupt das lateinische und nicht das chinesische
    // Lesemodell genommen wird. Vor dem Wechsel machte v3 aus jedem ß ein
    // B – nicht weil das Zeichen fehlte, sondern weil das Modell es nicht
    // erkannte. Dass es in der Tabelle steht, ist die Voraussetzung dafür,
    // dass es überhaupt herauskommen kann.
    final tabelle = OcrService.zeichenAusKonfig(echte.readAsStringSync());
    for (final z in ['ä', 'ö', 'ü', 'Ä', 'Ö', 'Ü', 'ß', '€', 'é', 'ç']) {
      expect(tabelle, contains(z), reason: 'Zeichen $z fehlt');
    }
  });

  test('die Reihenfolge bleibt, wie sie in der Datei steht', () {
    // Leere Einträge dürfen NICHT übersprungen werden, und sortiert werden
    // darf schon gar nicht. Beides sähe wie eine Verbesserung aus und wäre
    // der Totalschaden.
    const konfig = '''
PostProcess:
  name: CTCLabelDecode
  character_dict:
  - Z
  - '0'
  - A
  - '-'
  use_space_char: true
''';
    expect(OcrService.zeichenAusKonfig(konfig), ['Z', '0', 'A', '-']);
  });

  test('ohne den Block kommt eine leere Tabelle, kein Fehler', () {
    // Eine leere Tabelle führt beim Laden zu einem sichtbaren Ausfall.
    // Eine Ausnahme mitten im Modellladen wäre schwerer zu deuten.
    expect(OcrService.zeichenAusKonfig('Global:\n  model_name: x\n'), isEmpty);
    expect(OcrService.zeichenAusKonfig(''), isEmpty);
  });

  test('der Block endet an der nächsten Angabe', () {
    const konfig = '''
  character_dict:
  - A
  - B
  use_space_char: true
  - C
''';
    expect(OcrService.zeichenAusKonfig(konfig), ['A', 'B'],
        reason: 'was nach dem Block steht, gehört nicht dazu');
  });

  test('der Katalog nennt genau die Datei, die der Dienst liest', () {
    // Die beiden liefen schon einmal auseinander: Der Katalog lud eine
    // `ocr_dict.txt`, die es nach dem Modellwechsel nicht mehr gibt.
    final namen =
        ModelCatalog.ocrPaddle.files.map((f) => f.fileName).toList();
    expect(namen, contains(OcrService.zeichenDatei));
    expect(namen, contains(OcrService.erkennungsDatei));
    expect(namen, contains(OcrService.lesungsDatei));
  });

  test('die Vorlage ist die ausgelieferte Datei', () {
    // Sonst prüfte alles oben eine Datei, die niemand bekommt.
    final eintrag = ModelCatalog.ocrPaddle.files
        .firstWhere((f) => f.fileName == OcrService.zeichenDatei);
    expect(echte.lengthSync(), eintrag.bytes);
  });
}
