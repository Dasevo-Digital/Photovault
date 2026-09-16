import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/cr3_gps.dart';
import 'package:photo_vault/services/dateikennung.dart';

import 'cr3_bauen.dart';

void main() {
  group('gpsAusTiffIfd', () {
    test('Grad, Minuten und Sekunden werden zu einer Dezimalzahl', () {
      final ort = gpsAusTiffIfd(gpsVerzeichnis(
          breite: beispielBreite,
          breiteRef: 'N',
          laenge: beispielLaenge,
          laengeRef: 'E'));
      expect(ort, isNotNull);
      expect(ort!.breite, closeTo(52 + 14 / 60 + 35.2 / 3600, 1e-9));
      expect(ort.laenge, closeTo(10 + 35 / 60 + 7.0 / 3600, 1e-9));
    });

    test('Süd und West kehren das Vorzeichen um', () {
      // Ohne diese Umkehr läge jeder Ort auf der Nordhalbkugel und
      // östlich von Greenwich – und zwar plausibel aussehend.
      final ort = gpsAusTiffIfd(gpsVerzeichnis(
          breite: beispielBreite,
          breiteRef: 'S',
          laenge: beispielLaenge,
          laengeRef: 'W'));
      expect(ort!.breite, lessThan(0));
      expect(ort.laenge, lessThan(0));
      expect(ort.breite, closeTo(-(52 + 14 / 60 + 35.2 / 3600), 1e-9));
    });

    test('fehlt die Länge, kommt kein halber Ort heraus', () {
      expect(
          gpsAusTiffIfd(gpsVerzeichnis(
              breite: beispielBreite,
              breiteRef: 'N',
              laenge: beispielLaenge,
              laengeRef: 'E',
              ohneLaenge: true)),
          isNull);
    });

    test('ohne Bytereihenfolge-Zeichen kein Ergebnis', () {
      final kaputt = gpsVerzeichnis(
          breite: beispielBreite,
          breiteRef: 'N',
          laenge: beispielLaenge,
          laengeRef: 'E');
      kaputt[0] = 0x00;
      expect(gpsAusTiffIfd(kaputt), isNull);
    });

    test('ein Nenner von null gibt nicht NaN, sondern null Grad', () {
      // 0/0 kommt in leeren GPS-Blöcken tatsächlich vor. Ohne die
      // Behandlung käme NaN heraus und liefe als Koordinate weiter.
      final ort = gpsAusTiffIfd(gpsVerzeichnis(
          breite: [
            [0, 0],
            [0, 0],
            [0, 0]
          ],
          breiteRef: 'N',
          laenge: [
            [0, 0],
            [0, 0],
            [0, 0]
          ],
          laengeRef: 'E'));
      expect(ort!.breite, 0.0);
      expect(ort.laenge, 0.0);
    });

    test('zu kurz ist kein Verzeichnis', () {
      expect(gpsAusTiffIfd(Uint8List(4)), isNull);
    });
  });

  group('cmt4Aus', () {
    test('findet den Kasten zwei Ebenen tief', () {
      final inhalt = Uint8List.fromList([1, 2, 3, 4]);
      final gefunden = cmt4Aus(cr3Mit(inhalt));
      expect(gefunden, isNotNull);
      expect(gefunden!.toList(), [1, 2, 3, 4]);
    });

    test('eine Kastenlänge kleiner als ihr Kopf beendet die Suche', () {
      // Ohne diese Schranke liefe die Schleife ewig: Der Zeiger käme nie
      // voran.
      final b = BytesBuilder();
      b.add((ByteData(4)..setUint32(0, 3)).buffer.asUint8List());
      b.add('moov'.codeUnits);
      b.add(List.filled(64, 0));
      expect(cmt4Aus(b.toBytes()), isNull);
    });

    test('eine Länge über das Ende hinaus wird abgewiesen', () {
      final b = BytesBuilder();
      b.add((ByteData(4)..setUint32(0, 1 << 30)).buffer.asUint8List());
      b.add('moov'.codeUnits);
      b.add(List.filled(64, 0));
      expect(cmt4Aus(b.toBytes()), isNull);
    });

    test('ohne CMT4 kommt null zurück, nicht irgendein Kasten', () {
      final ohne = BytesBuilder()
        ..add(kasten('ftyp', 'crx '.codeUnits))
        ..add(kasten('moov', uuidKasten(kasten('CMT1', [9, 9, 9, 9]))));
      expect(cmt4Aus(ohne.toBytes()), isNull);
    });
  });

  group('leseCr3Gps an einer Datei', () {
    late Directory tempDir;
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pv_cr3_');
    });
    tearDown(() => tempDir.delete(recursive: true));

    File schreibe(String name, List<int> bytes) =>
        File('${tempDir.path}/$name')..writeAsBytesSync(bytes);

    test('liest den Ort, ohne die ganze Datei zu lesen', () async {
      // `mdat` ist hier absichtlich 8 MB gross. Läse der Leser die Datei
      // ganz, wäre das an einer echten 31-MB-Aufnahme mal 812 Dateien
      // ein Vielfaches der Arbeit – gemessen an der Bibliothek, für die
      // es diesen Weg gibt.
      final datei = schreibe(
          'mit_ort.cr3',
          cr3Mit(
              gpsVerzeichnis(
                  breite: beispielBreite,
                  breiteRef: 'N',
                  laenge: beispielLaenge,
                  laengeRef: 'E'),
              mdatBytes: 8 * 1024 * 1024));
      final ort = await leseCr3Gps(datei);
      expect(ort, isNotNull);
      expect(ort!.breite, closeTo(52.2431111, 1e-6));
      expect(ort.laenge, closeTo(10.5852778, 1e-6));
    });

    test('ein JPEG ist keine CR3 und liefert null statt eines Fehlers',
        () async {
      final datei =
          schreibe('foto.jpg', [0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 0)]);
      expect(await leseCr3Gps(datei), isNull);
    });

    test('eine fehlende Datei wirft nicht', () async {
      expect(await leseCr3Gps(File('${tempDir.path}/gibtsnicht.cr3')), isNull);
    });

    test('ein abgeschnittenes moov wirft nicht', () async {
      final ganz = cr3Mit(gpsVerzeichnis(
          breite: beispielBreite,
          breiteRef: 'N',
          laenge: beispielLaenge,
          laengeRef: 'E'));
      final datei = schreibe('halb.cr3', ganz.sublist(0, 40));
      expect(await leseCr3Gps(datei), isNull);
    });
  });

  group('an einer echten Canon-Datei', () {
    // Der Kopf (ftyp + moov, 30 kB) einer CC0-Musteraufnahme einer Canon
    // EOS R10 von raw.pixls.us – dieselbe Quelle wie
    // raw_identify_eos_r10.txt. Echte Kamerabytes statt nachgebauter:
    // Sie hat einen CMT4-Kasten, aber keine Koordinaten darin.
    final datei = File('test/fixtures/werkzeuge/eos_r10_kopf.cr3');

    test('der Kastenlauf findet CMT4 in echten Bytes', () {
      final cmt4 = cmt4Aus(datei.readAsBytesSync());
      expect(cmt4, isNotNull);
      // Ein vollständiger TIFF-Kopf, kleine Bytereihenfolge.
      expect(cmt4!.sublist(0, 4), [0x49, 0x49, 0x2A, 0x00]);
    });

    test('ohne Koordinaten im Kasten kommt kein Ort heraus', () async {
      expect(await leseCr3Gps(datei), isNull);
    });

    test('die Bytes verraten CR3, ohne dass jemand die Endung liest', () {
      final kopf = datei.readAsBytesSync().sublist(0, kennungBytes);
      expect(kennungAus(kopf), '.cr3');
    });
  });
}
