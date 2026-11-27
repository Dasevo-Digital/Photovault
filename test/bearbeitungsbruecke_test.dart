import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/bearbeitungsbruecke.dart';
import 'package:photo_vault/services/darktable_bruecke.dart';

/// Die Suche nach dem Ergebnis im Arbeitsordner (#499): welche Datei als
/// Ergebnis zählt, wann die Arbeitskopie selbst, und wann es nur einen
/// Hinweis gibt.
void main() {
  late Directory wurzel;
  late Bearbeitungsbruecke bruecke;
  late List<String> gestartet;
  late File original;

  setUp(() {
    wurzel = Directory.systemTemp.createTempSync('pv_bruecke_');
    gestartet = [];
    bruecke = Bearbeitungsbruecke(
      Directory(p.join(wurzel.path, 'PhotoVault-GIMP')),
      starte: (d) async {
        gestartet.add(d);
        return true;
      },
    );
    original = File(p.join(wurzel.path, 'quelle.bin'))
      ..writeAsStringSync('original');
  });
  tearDown(() => wurzel.deleteSync(recursive: true));

  Future<void> oeffne(String name) =>
      bruecke.oeffne(id: 'a1', name: name, original: original);

  File lege(String pfad, DateTime zeit, [String inhalt = 'neu']) {
    final f = File(p.join(bruecke.ordner('a1').path, pfad))
      ..createSync(recursive: true)
      ..writeAsStringSync(inhalt);
    f.setLastModifiedSync(zeit);
    return f;
  }

  test('legt die Kopie an, ohne Beilage, und startet mit ihrem Pfad', () async {
    await oeffne('IMG_1.JPG');
    final platz = bruecke.ordner('a1').path;
    expect(File(p.join(platz, 'IMG_1.JPG')).readAsStringSync(), 'original');
    expect(File(p.join(platz, 'IMG_1.JPG.xmp')).existsSync(), isFalse);
    expect(gestartet, [p.join(platz, 'IMG_1.JPG')]);
  });

  test('das neueste JPEG, TIFF oder PNG zählt', () async {
    await oeffne('IMG_1.CR3');
    expect(await bruecke.ergebnis('a1', 'IMG_1.CR3'), isNull);
    lege('IMG_1.jpg', DateTime(2026, 3));
    final tiff = lege('IMG_1-bearbeitet.tif', DateTime(2026, 5));
    lege('ausgabe/IMG_1.png', DateTime(2026, 4));
    expect((await bruecke.ergebnis('a1', 'IMG_1.CR3'))?.path, tiff.path);
  });

  test('eine überschriebene Kopie ist das Ergebnis', () async {
    await oeffne('IMG_1.JPG');
    expect(
      await bruecke.ergebnis('a1', 'IMG_1.JPG'),
      isNull,
      reason: 'unverändert ist sie noch das Original',
    );
    final kopie = bruecke.kopie('a1', 'IMG_1.JPG')
      ..writeAsStringSync('von Photoshop gespeichert');
    kopie.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    expect((await bruecke.ergebnis('a1', 'IMG_1.JPG'))?.path, kopie.path);
  });

  test('Gegenprobe: eine RAW-Kopie zählt nie, auch geändert nicht', () async {
    await oeffne('IMG_1.CR3');
    bruecke.kopie('a1', 'IMG_1.CR3')
      ..writeAsStringSync('angefasst')
      ..setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    expect(await bruecke.ergebnis('a1', 'IMG_1.CR3'), isNull);
  });

  test('Gegenprobe: ohne Marke gilt die Kopie als unverändert', () async {
    // Ein Ordner, den eine Fassung vor #499 angelegt hat.
    lege('IMG_1.JPG', DateTime(2026, 1));
    expect(await bruecke.ergebnis('a1', 'IMG_1.JPG'), isNull);
  });

  test('nur ein PSD: kein Ergebnis, aber der Hinweis darauf', () async {
    await oeffne('IMG_1.CR3');
    final psd = lege('IMG_1.psd', DateTime(2026, 5));
    lege('IMG_1.CR3.on1', DateTime(2026, 6));
    final fund = await bruecke.suche('a1', 'IMG_1.CR3');
    expect(fund.datei, isNull);
    expect(fund.unlesbar?.path, psd.path);
  });

  test('PSD und JPEG: das JPEG wird übernommen', () async {
    await oeffne('IMG_1.CR3');
    lege('IMG_1.psd', DateTime(2026, 6));
    final jpeg = lege('IMG_1.jpg', DateTime(2026, 5));
    expect((await bruecke.suche('a1', 'IMG_1.CR3')).datei?.path, jpeg.path);
  });

  test('Gegenprobe: die Kopie eines PSD-Originals ist kein Hinweis', () async {
    await oeffne('Plakat.psd');
    final fund = await bruecke.suche('a1', 'Plakat.psd');
    expect(fund.datei, isNull);
    expect(fund.unlesbar, isNull);
  });

  test('nur die ON1-Beilage: weder Ergebnis noch PSD-Hinweis', () async {
    await oeffne('IMG_1.CR3');
    lege('IMG_1.on1', DateTime(2026, 6));
    final fund = await bruecke.suche('a1', 'IMG_1.CR3');
    expect((fund.datei, fund.unlesbar), (null, null));
  });

  test('schliessen räumt auch den leeren Ordner des Programms weg', () async {
    await oeffne('IMG_1.JPG');
    await bruecke.oeffne(id: 'a2', name: 'IMG_2.JPG', original: original);
    await bruecke.schliesse('a1');
    expect(bruecke.offen('a1'), isFalse);
    expect(bruecke.ablage.existsSync(), isTrue, reason: 'a2 ist noch offen');
    await bruecke.schliesse('a2');
    expect(bruecke.ablage.existsSync(), isFalse);
    expect(original.existsSync(), isTrue);
  });

  group('darktable', () {
    late DarktableBruecke dt;
    setUp(() {
      dt = DarktableBruecke(
        Directory(p.join(wurzel.path, 'PhotoVault-darktable')),
        starte: (_) async => true,
      );
    });

    test('Gegenprobe: eine überschriebene Kopie zählt bei darktable nicht, '
        'und auch kein TIFF', () async {
      await dt.oeffne(
        id: 'a1',
        name: 'IMG_1.JPG',
        original: original,
        xmp: '<a/>',
      );
      dt.kopie('a1', 'IMG_1.JPG')
        ..writeAsStringSync('anders')
        ..setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
      File(p.join(dt.ordner('a1').path, 'darktable_exported', 'IMG_1.tif'))
        ..createSync(recursive: true)
        ..writeAsStringSync('tif');
      expect(await dt.ergebnis('a1', 'IMG_1.JPG'), isNull);
      expect(dt.beilage('a1', 'IMG_1.JPG').readAsStringSync(), '<a/>');
    });

    test('ein Arbeitsordner von vor #499 wird gefunden', () async {
      // So legte DarktableBruecke ihn an: ohne Marke, mit Beilage.
      final alt = Directory(p.join(dt.ablage.path, 'a7'))
        ..createSync(recursive: true);
      File(p.join(alt.path, 'IMG_7.CR3')).writeAsStringSync('roh');
      File(p.join(alt.path, 'IMG_7.CR3.xmp')).writeAsStringSync('<x/>');
      final export = File(p.join(alt.path, 'darktable_exported', 'IMG_7.jpg'))
        ..createSync(recursive: true);
      expect(dt.offen('a7'), isTrue);
      expect((await dt.ergebnis('a7', 'IMG_7.CR3'))?.path, export.path);
      expect(
        DarktableBruecke.standard().ablage.path,
        endsWith('PhotoVault-darktable'),
      );
    });
  });
}
