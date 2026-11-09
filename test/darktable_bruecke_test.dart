import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/darktable_bruecke.dart';

void main() {
  late Directory ordner;
  late DarktableBruecke bruecke;
  late List<String> gestartet;
  late bool klappt;
  late File original;

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('pv_dt_');
    gestartet = [];
    klappt = true;
    bruecke = DarktableBruecke(
      Directory('${ordner.path}/ablage'),
      starte: (d) async {
        gestartet.add(d);
        return klappt;
      },
    );
    original = File('${ordner.path}/quelle.bin')..writeAsStringSync('roh');
  });
  tearDown(() => ordner.deleteSync(recursive: true));

  Future<bool> oeffne({String name = 'IMG_1.CR3', String xmp = '<a/>'}) =>
      bruecke.oeffne(id: 'a1', name: name, original: original, xmp: xmp);

  File jpeg(String pfad, DateTime zeit) {
    final f = File('${bruecke.ordner('a1').path}/$pfad')
      ..createSync(recursive: true)
      ..writeAsStringSync('jpg');
    f.setLastModifiedSync(zeit);
    return f;
  }

  test('legt Kopie und Beilage unter dem Namen von darktable an', () async {
    expect(bruecke.offen('a1'), isFalse);
    expect(await oeffne(), isTrue);
    final platz = bruecke.ordner('a1').path;
    expect(File('$platz/IMG_1.CR3').readAsStringSync(), 'roh');
    expect(File('$platz/IMG_1.CR3.xmp').readAsStringSync(), '<a/>');
    expect(gestartet, ['$platz/IMG_1.CR3']);
    expect(bruecke.offen('a1'), isTrue);
  });

  test('ein zweites Öffnen behält die Bearbeitung', () async {
    await oeffne();
    bruecke.beilage('a1', 'IMG_1.CR3').writeAsStringSync('<bearbeitet/>');
    await oeffne(xmp: '<neu/>');
    expect(
      bruecke.beilage('a1', 'IMG_1.CR3').readAsStringSync(),
      '<bearbeitet/>',
    );
    expect(gestartet, hasLength(2));
  });

  test('ohne darktable liegt die Kopie trotzdem bereit', () async {
    klappt = false;
    expect(await oeffne(), isFalse);
    expect(bruecke.offen('a1'), isTrue);
  });

  test('das Ergebnis ist das neueste JPEG, nie die Arbeitskopie', () async {
    await oeffne(name: 'IMG_1.JPG');
    expect(await bruecke.ergebnis('a1', 'IMG_1.JPG'), isNull);
    jpeg('darktable_exported/IMG_1.jpg', DateTime(2026, 3));
    final neu = jpeg('darktable_exported/IMG_1_01.jpg', DateTime(2026, 5));
    expect((await bruecke.ergebnis('a1', 'IMG_1.JPG'))?.path, neu.path);
  });

  test('TIFF zählt nicht als Ergebnis', () async {
    await oeffne();
    File('${bruecke.ordner('a1').path}/darktable_exported/IMG_1.tif')
      ..createSync(recursive: true)
      ..writeAsStringSync('tif');
    expect(await bruecke.ergebnis('a1', 'IMG_1.CR3'), isNull);
  });

  test('schliessen räumt die Arbeitskopie weg', () async {
    await oeffne();
    await bruecke.schliesse('a1');
    expect(bruecke.offen('a1'), isFalse);
    expect(original.existsSync(), isTrue);
  });
}
