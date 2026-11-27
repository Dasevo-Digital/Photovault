import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/bearbeitungsbruecke.dart';
import 'package:photo_vault/services/darktable_bruecke.dart';

/// Die Suche nach dem Ergebnis im Arbeitsordner (#499): welche Datei als
/// Ergebnis zählt, wann die Arbeitskopie selbst, und wann es nur einen
/// Hinweis gibt – und was beim Übernehmen, Sperren und Löschen bleibt.
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

  Future<void> oeffne(String name, {String? frueher}) => bruecke.oeffne(
    id: 'a1',
    name: name,
    frueher: frueher,
    original: original,
  );

  File lege(String pfad, DateTime zeit, [String inhalt = 'neu']) {
    final f = File(p.join(bruecke.ordner('a1').path, pfad))
      ..createSync(recursive: true)
      ..writeAsStringSync(inhalt);
    f.setLastModifiedSync(zeit);
    return f;
  }

  List<String> inhalt(Directory d) => [
    for (final e in d.listSync(recursive: true))
      if (e is File) p.relative(e.path, from: d.path),
  ]..sort();

  test('legt die Kopie an, ohne Beilage, und startet mit ihrem Pfad', () async {
    await oeffne('IMG_1.JPG');
    final platz = bruecke.ordner('a1').path;
    expect(File(p.join(platz, 'IMG_1.JPG')).readAsStringSync(), 'original');
    expect(File(p.join(platz, 'IMG_1.JPG.xmp')).existsSync(), isFalse);
    expect(gestartet, [p.join(platz, 'IMG_1.JPG')]);
    expect(await bruecke.stand('a1'), Arbeitsstand.offen);
  });

  test('das neueste JPEG, TIFF oder PNG zählt', () async {
    await oeffne('IMG_1.CR3');
    expect(await bruecke.ergebnis('a1', 'IMG_1.CR3'), isNull);
    lege('IMG_1.jpg', DateTime(2026, 3));
    final tiff = lege('IMG_1-bearbeitet.tif', DateTime(2026, 5));
    lege('ausgabe/IMG_1.png', DateTime(2026, 4));
    expect((await bruecke.ergebnis('a1', 'IMG_1.CR3'))?.path, tiff.path);
  });

  test(
    'bei gleicher Zeit entscheidet der Pfad, nicht die Auflistung',
    () async {
      await oeffne('IMG_1.CR3');
      final zeit = DateTime(2026, 5, 1, 12);
      lege('z.tif', zeit);
      final a = lege('a.jpg', zeit);
      lege('m.png', zeit);
      for (var i = 0; i < 3; i++) {
        expect((await bruecke.ergebnis('a1', 'IMG_1.CR3'))?.path, a.path);
      }
    },
  );

  test('eine überschriebene Kopie ist das Ergebnis', () async {
    await oeffne('IMG_1.JPG');
    expect(
      await bruecke.ergebnis('a1', 'IMG_1.JPG'),
      isNull,
      reason: 'unverändert ist sie noch das Original',
    );
    final kopie = (await bruecke.kopie('a1', 'IMG_1.JPG'))
      ..writeAsStringSync('von Photoshop gespeichert');
    kopie.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    expect((await bruecke.ergebnis('a1', 'IMG_1.JPG'))?.path, kopie.path);
  });

  test('Gegenprobe: eine RAW-Kopie zählt nie, auch geändert nicht', () async {
    await oeffne('IMG_1.CR3');
    (await bruecke.kopie('a1', 'IMG_1.CR3'))
      ..writeAsStringSync('angefasst')
      ..setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    expect(await bruecke.ergebnis('a1', 'IMG_1.CR3'), isNull);
  });

  test('Gegenprobe: ohne Marke gilt die Kopie als unverändert', () async {
    // Ein Ordner, den eine Fassung vor #499 angelegt hat.
    lege('IMG_1.JPG', DateTime(2026, 1));
    expect(await bruecke.stand('a1'), Arbeitsstand.offen);
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
    expect(await bruecke.offen('a1'), isFalse);
    expect(bruecke.ablage.existsSync(), isTrue, reason: 'a2 ist noch offen');
    await bruecke.schliesse('a2');
    expect(bruecke.ablage.existsSync(), isFalse);
    expect(original.existsSync(), isTrue);
  });

  group('nach dem Übernehmen', () {
    test('bleiben PSD, XCF, .on1 und XMP; nur Kopie, Marke und Ergebnis '
        'gehen', () async {
      await oeffne('IMG_1.CR3');
      lege('IMG_1.psd', DateTime(2026, 5, 1));
      lege('IMG_1.xcf', DateTime(2026, 5, 1));
      lege('IMG_1.on1', DateTime(2026, 5, 1));
      lege('IMG_1.xmp', DateTime(2026, 5, 1));
      final jpeg = lege('ausgabe/IMG_1.jpg', DateTime(2026, 5, 2));
      final blieb = await bruecke.nachUebernahme('a1', jpeg, name: 'IMG_1.CR3');
      expect(blieb, isTrue);
      expect(inhalt(bruecke.ordner('a1')), [
        Bearbeitungsbruecke.marke,
        'IMG_1.on1',
        'IMG_1.psd',
        'IMG_1.xcf',
        'IMG_1.xmp',
      ]);
      expect(
        Directory(p.join(bruecke.ordner('a1').path, 'ausgabe')).existsSync(),
        isFalse,
        reason: 'der leere Unterordner geht',
      );
      expect(await bruecke.stand('a1'), Arbeitsstand.arbeitsdateien);
      final fund = await bruecke.suche('a1', 'IMG_1.CR3');
      expect(
        (fund.datei, fund.unlesbar),
        (null, null),
        reason: 'das alte PSD ist kein neuer Hinweis',
      );
    });

    test('ein älteres JPEG daneben ist danach kein neues Ergebnis, ein '
        'späteres schon – auch nach erneutem Öffnen', () async {
      await oeffne('IMG_1.CR3');
      lege('IMG_1.psd', DateTime(2026, 5, 1));
      lege('IMG_1-erst.jpg', DateTime(2026, 5, 1));
      final jpeg = lege('IMG_1-dann.jpg', DateTime(2026, 5, 2));
      await bruecke.nachUebernahme('a1', jpeg, name: 'IMG_1.CR3');
      // Weiter bearbeitet, als dasselbe Foto (jetzt ein JPEG) noch einmal
      // geöffnet.
      await oeffne('IMG_1.jpg', frueher: 'IMG_1.CR3');
      expect(await bruecke.stand('a1'), Arbeitsstand.offen);
      expect(await bruecke.ergebnis('a1', 'IMG_1.jpg'), isNull);
      final spaeter = lege('IMG_1-wieder.jpg', DateTime(2026, 5, 3));
      expect((await bruecke.ergebnis('a1', 'IMG_1.jpg'))?.path, spaeter.path);
    });

    test('heisst eine Arbeitsdatei wie die neue Kopie, wird sie nicht '
        'überschrieben', () async {
      await oeffne('IMG_1.CR3');
      final alt = lege('IMG_1.jpg', DateTime(2026, 5, 1), 'eigene Arbeit');
      final jpeg = lege('IMG_1-fertig.tif', DateTime(2026, 5, 2));
      await bruecke.nachUebernahme('a1', jpeg, name: 'IMG_1.CR3');
      await oeffne('IMG_1.jpg', frueher: 'IMG_1.CR3');
      expect(alt.readAsStringSync(), 'eigene Arbeit');
      final kopie = await bruecke.kopie('a1', 'IMG_1.jpg');
      expect(p.basename(kopie.path), 'IMG_1 (2).jpg');
      expect(kopie.readAsStringSync(), 'original');
      expect(gestartet.last, kopie.path);
    });

    test('Gegenprobe: bleibt nichts als Beiwerk, geht der Ordner', () async {
      await oeffne('IMG_1.CR3');
      lege('.DS_Store', DateTime(2026, 5, 1));
      final jpeg = lege('IMG_1.jpg', DateTime(2026, 5, 2));
      expect(
        await bruecke.nachUebernahme('a1', jpeg, name: 'IMG_1.CR3'),
        false,
      );
      expect(bruecke.ordner('a1').existsSync(), isFalse);
      expect(bruecke.ablage.existsSync(), isFalse);
    });

    test('darktable räumt den ganzen Ordner weg', () async {
      final dt = DarktableBruecke(
        Directory(p.join(wurzel.path, 'PhotoVault-darktable')),
        starte: (_) async => true,
      );
      await dt.oeffne(id: 'a1', name: 'IMG_1.CR3', original: original);
      final export = File(
        p.join(dt.ordner('a1').path, 'darktable_exported', 'IMG_1.jpg'),
      )..createSync(recursive: true);
      File(
        p.join(dt.ordner('a1').path, 'darktable_exported', 'IMG_1.tif'),
      ).createSync();
      expect(await dt.nachUebernahme('a1', export, name: 'IMG_1.CR3'), false);
      expect(dt.ordner('a1').existsSync(), isFalse);
    });
  });

  group('Name der Kopie (arbeitsname)', () {
    test('nach einer Bearbeitung trägt die Kopie die Endung der Datei', () {
      expect(arbeitsname('IMG_1234.CR3', 'originals/2026/06/x.jpg'), (
        name: 'IMG_1234.jpg',
        frueher: 'IMG_1234.CR3',
      ));
      expect(arbeitsname('IMG_1.HEIC', 'originals/2026/06/x.jpg'), (
        name: 'IMG_1.jpg',
        frueher: 'IMG_1.HEIC',
      ));
    });

    test('Gegenprobe: gleiche Endung in anderer Schreibung bleibt', () {
      expect(arbeitsname('IMG_1.JPG', 'originals/2026/06/x.jpg'), (
        name: 'IMG_1.JPG',
        frueher: null,
      ));
      expect(arbeitsname('IMG_1.CR3', 'originals/2026/06/x.cr3'), (
        name: 'IMG_1.CR3',
        frueher: null,
      ));
    });

    test('ein Ordner von vorher wird unter dem alten Namen gefunden', () async {
      final dt = DarktableBruecke(
        Directory(p.join(wurzel.path, 'PhotoVault-darktable')),
        starte: (d) async {
          gestartet.add(d);
          return true;
        },
      );
      // So legte es eine Fassung davor an: Kopie unter dem Namen der
      // Aufnahme, keine Marke.
      final alt = Directory(p.join(dt.ablage.path, 'a1'))
        ..createSync(recursive: true);
      File(p.join(alt.path, 'IMG_1.CR3')).writeAsStringSync('jpeg-inhalt');
      File(p.join(alt.path, 'IMG_1.CR3.xmp')).writeAsStringSync('<alt/>');
      final n = arbeitsname('IMG_1.CR3', 'originals/x.jpg');
      final beilage = await dt.beilage('a1', n.name, frueher: n.frueher);
      expect(beilage.readAsStringSync(), '<alt/>');
      await dt.oeffne(
        id: 'a1',
        name: n.name,
        frueher: n.frueher,
        original: original,
        xmp: '<neu/>',
      );
      expect(gestartet, [p.join(alt.path, 'IMG_1.CR3')]);
      expect(File(p.join(alt.path, 'IMG_1.jpg')).existsSync(), isFalse);
    });

    test('ein neuer Ordner bekommt den neuen Namen', () async {
      final n = arbeitsname('IMG_1.CR3', 'originals/x.jpg');
      await oeffne(n.name, frueher: n.frueher);
      expect(gestartet, [p.join(bruecke.ordner('a1').path, 'IMG_1.jpg')]);
    });
  });

  group('fertig geschrieben', () {
    late List<Duration> gewartet;
    late Bearbeitungsbruecke b;
    setUp(() {
      gewartet = [];
      b = Bearbeitungsbruecke(
        Directory(p.join(wurzel.path, 'PhotoVault-X')),
        starte: (_) async => true,
        warte: (d) async => gewartet.add(d),
      );
    });

    test('eine länger liegende Datei: kurz zweimal hinsehen', () async {
      final f = File(p.join(wurzel.path, 'a.jpg'))..writeAsStringSync('x');
      f.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
      expect(await b.fertig(f), isTrue);
      expect(gewartet, [const Duration(milliseconds: 500)]);
    });

    test('eine eben geschriebene Datei: den Rest der Ruhe abwarten', () async {
      final f = File(p.join(wurzel.path, 'a.jpg'))..writeAsStringSync('x');
      expect(await b.fertig(f), isTrue);
      expect(gewartet.single, greaterThan(const Duration(seconds: 1)));
      expect(gewartet.single, lessThanOrEqualTo(const Duration(seconds: 2)));
    });

    test(
      'Gegenprobe: wächst sie währenddessen, ist sie nicht fertig',
      () async {
        final f = File(p.join(wurzel.path, 'a.jpg'))..writeAsStringSync('x');
        final wachsend = Bearbeitungsbruecke(
          b.ablage,
          starte: (_) async => true,
          warte: (_) async =>
              f.writeAsStringSync('mehr', mode: FileMode.append),
        );
        expect(await wachsend.fertig(f), isFalse);
      },
    );

    test('eine Datei aus der Zukunft wartet höchstens die Ruhe', () async {
      final f = File(p.join(wurzel.path, 'a.jpg'))..writeAsStringSync('x');
      f.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
      expect(await b.fertig(f), isTrue);
      expect(gewartet, [const Duration(seconds: 2)]);
    });
  });

  group('Sperren und Löschen (raeumeKlartextWeg)', () {
    test('unveränderte Kopie und Marke gehen, mit dem Ordner', () async {
      await oeffne('IMG_1.JPG');
      expect(await bruecke.raeumeKlartextWeg('a1'), isNull);
      expect(bruecke.ordner('a1').existsSync(), isFalse);
    });

    test('was ein Programm gespeichert hat, bleibt – auch die überschriebene '
        'Kopie', () async {
      await oeffne('IMG_1.JPG');
      final kopie = (await bruecke.kopie('a1', 'IMG_1.JPG'))
        ..writeAsStringSync('in Photoshop gespeichert')
        ..setLastModifiedSync(DateTime(2026, 5, 2));
      lege('IMG_1.psd', DateTime(2026, 5, 1));
      final geblieben = await bruecke.raeumeKlartextWeg('a1');
      expect(geblieben?.path, bruecke.ordner('a1').path);
      expect(kopie.existsSync(), isTrue);
      expect(inhalt(bruecke.ordner('a1')), [
        Bearbeitungsbruecke.marke,
        'IMG_1.JPG',
        'IMG_1.psd',
      ]);
      expect(await bruecke.stand('a1'), Arbeitsstand.arbeitsdateien);
    });

    test('darktable: Kopie und Beilage gehen, ein Export bleibt', () async {
      final dt = DarktableBruecke(
        Directory(p.join(wurzel.path, 'PhotoVault-darktable')),
        starte: (_) async => true,
      );
      await dt.oeffne(
        id: 'a1',
        name: 'IMG_1.CR3',
        original: original,
        xmp: '<schlagwort>geheim</schlagwort>',
      );
      File(
        p.join(dt.ordner('a1').path, 'darktable_exported', 'IMG_1.jpg'),
      ).createSync(recursive: true);
      expect(await dt.raeumeKlartextWeg('a1'), isNotNull);
      expect(inhalt(dt.ordner('a1')), [
        Bearbeitungsbruecke.marke,
        p.join('darktable_exported', 'IMG_1.jpg'),
      ]);
    });

    test(
      'darktable von vor #499: das Paar aus Kopie und Beilage geht',
      () async {
        final dt = DarktableBruecke(
          Directory(p.join(wurzel.path, 'PhotoVault-darktable')),
          starte: (_) async => true,
        );
        final alt = Directory(p.join(dt.ablage.path, 'a7'))
          ..createSync(recursive: true);
        File(p.join(alt.path, 'IMG_7.CR3')).writeAsStringSync('roh');
        File(p.join(alt.path, 'IMG_7.CR3.xmp')).writeAsStringSync('<x/>');
        expect(await dt.raeumeKlartextWeg('a7'), isNull);
        expect(alt.existsSync(), isFalse);
      },
    );
  });

  group('Verweise', () {
    test('ist der Ordner der Aufnahme ein Verweis, wird nichts dahinter '
        'gelöscht', () async {
      final fremd = Directory(p.join(wurzel.path, 'fremd'))..createSync();
      final wichtig = File(p.join(fremd.path, 'wichtig.txt'))
        ..writeAsStringSync('bleibt');
      bruecke.ablage.createSync(recursive: true);
      Link(bruecke.ordner('a1').path).createSync(fremd.path);
      expect(await bruecke.stand('a1'), Arbeitsstand.keiner);
      await bruecke.schliesse('a1');
      expect(await bruecke.raeumeKlartextWeg('a1'), isNull);
      expect(wichtig.readAsStringSync(), 'bleibt');
    });

    test('ist die Ablage ein Verweis, auch nicht', () async {
      final fremd = Directory(p.join(wurzel.path, 'fremd'))..createSync();
      final innen = Directory(p.join(fremd.path, 'a1'))..createSync();
      final wichtig = File(p.join(innen.path, 'wichtig.txt'))
        ..writeAsStringSync('bleibt');
      Link(bruecke.ablage.path).createSync(fremd.path);
      await bruecke.schliesse('a1');
      expect(wichtig.readAsStringSync(), 'bleibt');
    });

    test('ein Name aus der Marke führt nicht aus dem Ordner', () async {
      await oeffne('IMG_1.JPG');
      final draussen = File(p.join(wurzel.path, 'draussen.jpg'))
        ..writeAsStringSync('bleibt');
      File(
        p.join(bruecke.ordner('a1').path, Bearbeitungsbruecke.marke),
      ).writeAsStringSync('{"kopie": "../../draussen.jpg", "groesse": 1}');
      await bruecke.raeumeKlartextWeg('a1');
      expect(draussen.readAsStringSync(), 'bleibt');
    });
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
      (await dt.kopie('a1', 'IMG_1.JPG'))
        ..writeAsStringSync('anders')
        ..setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
      File(p.join(dt.ordner('a1').path, 'darktable_exported', 'IMG_1.tif'))
        ..createSync(recursive: true)
        ..writeAsStringSync('tif');
      expect(await dt.ergebnis('a1', 'IMG_1.JPG'), isNull);
      expect((await dt.beilage('a1', 'IMG_1.JPG')).readAsStringSync(), '<a/>');
    });

    test('ein Arbeitsordner von vor #499 wird gefunden', () async {
      // So legte DarktableBruecke ihn an: ohne Marke, mit Beilage.
      final alt = Directory(p.join(dt.ablage.path, 'a7'))
        ..createSync(recursive: true);
      File(p.join(alt.path, 'IMG_7.CR3')).writeAsStringSync('roh');
      File(p.join(alt.path, 'IMG_7.CR3.xmp')).writeAsStringSync('<x/>');
      final export = File(p.join(alt.path, 'darktable_exported', 'IMG_7.jpg'))
        ..createSync(recursive: true);
      expect(await dt.offen('a7'), isTrue);
      expect((await dt.ergebnis('a7', 'IMG_7.CR3'))?.path, export.path);
      expect(
        DarktableBruecke.standard().ablage.path,
        endsWith('PhotoVault-darktable'),
      );
    });
  });
}
