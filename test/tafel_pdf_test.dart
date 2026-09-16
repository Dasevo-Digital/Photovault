import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/faechertafel.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/tafel_pdf.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Die Tafel zum Aufhängen.
///
/// Der einzige Punkt im Stammbaum, an dem das Ergebnis das Programm
/// verlässt – ein Fehler fällt sonst erst auf dem Papier auf. Geprüft
/// wird deshalb, dass wirklich ein PDF entsteht, dass es die Zeichnung
/// enthält und dass die Dateiendung stimmt.
void main() {
  PersonData person(String id, String name, {int? jahr}) => PersonData(
        id: id,
        name: name,
        coverFaceCropPath: null,
        similarityThreshold: null,
        geburtsdatum: jahr == null ? null : DateTime(jahr),
        sterbedatum: null,
        geschlecht: null,
      );

  // Ein Name mit Umlaut ist kein Zufall: Die eingebauten PDF-Schriften
  // können kein Unicode, deshalb wird alle Schrift ins Bild gezeichnet.
  final personen = {
    'ich': person('ich', 'Lena Müller', jahr: 1990),
    'vater': person('vater', 'Karl Meier', jahr: 1960),
    'mutter': person('mutter', 'Eva Meier', jahr: 1962),
    'opa': person('opa', 'Hans Meier', jahr: 1931),
  };
  final netz = Verwandtschaftsnetz([
    kante('ich', 'vater', Verwandtschaft.elternteil),
    kante('ich', 'mutter', Verwandtschaft.elternteil),
    kante('vater', 'opa', Verwandtschaft.elternteil),
  ]);

  Future<Uint8List> tafel() => baueTafelPdf(
        plaetze: faechertafel(netz, 'ich', (id) => personen.keys.toList().indexOf(id)),
        personen: personen,
        titel: 'Lena Müller',
        farben: buildDarkTheme().colorScheme,
        textRichtung: TextDirection.ltr,
      );

  group('Dateiendung', () {
    test('wird angehängt, wenn sie fehlt', () {
      expect(mitTafelEndung('/tmp/tafel'), '/tmp/tafel.pdf');
    });

    test('wird nicht verdoppelt', () {
      expect(mitTafelEndung('/tmp/tafel.pdf'), '/tmp/tafel.pdf');
      expect(mitTafelEndung('/tmp/tafel.PDF'), '/tmp/tafel.PDF');
    });
  });

  testWidgets('erzeugt ein gültiges PDF mit einer Seite', (tester) async {
    // runAsync, weil `Picture.toImage` echte Asynchronität braucht: Der
    // Test läuft sonst gegen die künstliche Uhr und wartet ewig.
    final bytes = (await tester.runAsync(tafel))!;

    // Die Kennung am Dateianfang – daran erkennt jedes Programm ein PDF.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final inhalt = String.fromCharCodes(bytes);
    expect(inhalt, contains('/Type/Page'));
    expect(inhalt.trimRight(), endsWith('%%EOF'));

    // Die Zeichnung ist als Bild eingebettet; ohne sie wäre die Datei
    // ein leeres Blatt mit Überschrift.
    expect(inhalt, contains('/Image'));
    expect(bytes.length, greaterThan(20000),
        reason: 'ein paar Kilobyte wären eine leere Seite');
  });

  testWidgets('die Datei lässt sich schreiben und wieder lesen',
      (tester) async {
    final ordner = Directory.systemTemp.createTempSync('pv_tafel_');
    final datei = File(mitTafelEndung('${ordner.path}/stammbaum'));
    await tester.runAsync(() async {
      await datei.writeAsBytes(await tafel());
      expect(datei.existsSync(), isTrue);
      expect((await datei.readAsBytes()).take(5), '%PDF-'.codeUnits);
    });
    ordner.deleteSync(recursive: true);
  });
}
