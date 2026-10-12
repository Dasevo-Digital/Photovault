import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/fotobuch.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/fotobuch_export.dart';

/// Ein JPEG mit einem Verlauf – gross genug, dass ein Neukodieren auffiele.
Uint8List jpeg(int breite, int hoehe) {
  final b = img.Image(width: breite, height: hoehe);
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      b.setPixelRgb(x, y, x * 255 ~/ breite, y * 255 ~/ hoehe, 90);
    }
  }
  return Uint8List.fromList(img.encodeJpg(b, quality: 85));
}

/// Ein Segment `FF <marke>` mit [inhalt], wie es im Kopf eines JPEG steht.
List<int> segment(int marke, List<int> inhalt) => [
  0xFF,
  marke,
  (inhalt.length + 2) >> 8,
  (inhalt.length + 2) & 0xFF,
  ...inhalt,
];

/// [daten] mit zusätzlichen Segmenten gleich hinter dem Bildanfang.
Uint8List mitSegmenten(Uint8List daten, List<List<int>> segmente) =>
    Uint8List.fromList([
      ...daten.sublist(0, 2),
      for (final s in segmente) ...s,
      ...daten.sublist(2),
    ]);

bool enthaelt(Uint8List daten, String text) =>
    String.fromCharCodes(daten).contains(text);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('das Raster einer Seite', () {
    final (breite, hoehe) = fotobuchFlaeche(Fotobuchformat.a4Hoch);

    List<Fotobuchzelle> zellen(List<double> v, {Fotobuchformat? format}) {
      final (b, h) = fotobuchFlaeche(format ?? Fotobuchformat.a4Hoch);
      return fotobuchZellen(v, breite: b, hoehe: h, mitUnterschrift: true);
    }

    test('zwei Querformate übereinander, zwei Hochformate nebeneinander', () {
      final quer = zellen([1.5, 1.5]);
      expect(quer[0].links, quer[1].links, reason: 'eine Spalte');
      expect(quer[1].oben, greaterThan(quer[0].oben));
      final hoch = zellen([2 / 3, 2 / 3]);
      expect(hoch[0].oben, hoch[1].oben, reason: 'eine Zeile');
      expect(hoch[1].links, greaterThan(hoch[0].links));
    });

    test('vier Bilder auf dem Quadrat: zwei mal zwei', () {
      final z = zellen([1.5, 1.5, 1.5, 1.5], format: Fotobuchformat.quadrat);
      expect({for (final c in z) c.links}, hasLength(2));
      expect({for (final c in z) c.oben}, hasLength(2));
    });

    test('kein Bild ragt hinaus, keines liegt auf einem anderen', () {
      const reihen = [
        [1.5],
        [0.75, 1.33],
        [1.5, 0.66, 1.0],
        [1.78, 0.56, 1.0, 1.5],
      ];
      for (final format in Fotobuchformat.values) {
        final (b, h) = fotobuchFlaeche(format);
        for (final v in reihen) {
          final z = zellen(v, format: format);
          expect(z, hasLength(v.length));
          final bilder = [
            for (final (i, c) in z.indexed)
              fotobuchBildIn(c, v[i], mitUnterschrift: true),
          ];
          for (final (i, r) in bilder.indexed) {
            expect(r.links, greaterThanOrEqualTo(-1e-9));
            expect(r.oben, greaterThanOrEqualTo(-1e-9));
            expect(r.links + r.breite, lessThanOrEqualTo(b + 1e-6));
            expect(
              r.oben + r.hoehe + fotobuchUnterschriftHoehe,
              lessThanOrEqualTo(h + 1e-6),
            );
            expect(r.breite / r.hoehe, closeTo(v[i], 1e-9));
            for (final o in bilder.skip(i + 1)) {
              final getrennt =
                  r.links + r.breite <= o.links + 1e-6 ||
                  o.links + o.breite <= r.links + 1e-6 ||
                  r.oben + r.hoehe <= o.oben + 1e-6 ||
                  o.oben + o.hoehe <= r.oben + 1e-6;
              expect(getrennt, isTrue, reason: '${format.name} $v');
            }
          }
        }
      }
    });

    test('das Buch hat so viele Seiten, wie die Bilder brauchen', () {
      final plan = fotobuchPlan(
        List.filled(9, 1.5),
        format: Fotobuchformat.a4Hoch,
        jeSeite: 4,
        mitUnterschrift: false,
      );
      expect([for (final s in plan) s.bilder.length], [4, 4, 1]);
      expect(plan.last.bilder, [8]);
      expect(breite, greaterThan(0));
      expect(hoehe, greaterThan(breite));
    });
  });

  test('300 dpi auf der langen Kante, je nach Platz', () {
    double pixel(int jeSeite) {
      final s = fotobuchPlan(
        List.filled(jeSeite, 1.5),
        format: Fotobuchformat.a4Quer,
        jeSeite: jeSeite,
        mitUnterschrift: true,
      ).single;
      return fotobuchPixel(
        fotobuchBildIn(s.zellen.first, 1.5, mitUnterschrift: true),
      ).toDouble();
    }

    // Ein Bild auf A4 quer: mit Unterschrift von der Höhe begrenzt, gut
    // 26 cm breit – also über 3000 Pixel, höchstens die ganze Breite.
    final (b, _) = fotobuchFlaeche(Fotobuchformat.a4Quer);
    expect(
      pixel(1),
      inInclusiveRange(3000, (b / PdfPageFormat.inch * 300).ceil()),
    );
    expect(pixel(4), lessThan(pixel(1) * 0.55));
  });

  group('JPEG', () {
    test('Breite und Höhe aus dem Bildkopf', () {
      expect(jpegGroesse(jpeg(120, 80)), (120, 80));
      final png = Uint8List.fromList(
        img.encodePng(img.Image(width: 4, height: 4)),
      );
      expect(jpegGroesse(png), isNull);
    });

    test('EXIF, XMP und IPTC fallen weg, Farbprofil und Bild bleiben', () {
      // Der Fund beim Kontaktblatt: Das eingebettete JPEG trug Kamera und
      // Aufnahmeort mit, obwohl auf dem Blatt nur ein Datum stand.
      final original = jpeg(64, 48);
      final mit = mitSegmenten(original, [
        segment(0xE1, [...'Exif'.codeUnits, 0, 0, ...'GPSLatitude'.codeUnits]),
        segment(0xE1, 'http://ns.adobe.com/xap/1.0/'.codeUnits),
        segment(0xED, 'Photoshop 3.0'.codeUnits),
        segment(0xE2, [...'ICC_PROFILE'.codeUnits, 0, 1, 1]),
      ]);
      final ohne = jpegOhneBeipackzettel(mit);
      expect(enthaelt(ohne, 'Exif'), isFalse);
      expect(enthaelt(ohne, 'GPSLatitude'), isFalse);
      expect(enthaelt(ohne, 'ns.adobe.com'), isFalse);
      expect(enthaelt(ohne, 'Photoshop'), isFalse);
      expect(enthaelt(ohne, 'ICC_PROFILE'), isTrue);
      expect(jpegGroesse(ohne), (64, 48));
      final dekodiert = img.decodeJpg(ohne)!;
      expect([dekodiert.width, dekodiert.height], [64, 48]);
      // Ohne Neukodieren: Die Bilddaten sind Byte für Byte die alten.
      expect(
        ohne.length,
        original.length +
            segment(0xE2, [...'ICC_PROFILE'.codeUnits, 0, 1, 1]).length,
      );
    });
  });

  test('die Unterschrift: Reihenfolge, Leeres fällt weg, Namen einmal', () {
    expect(
      fotobuchUnterschrift(
        datum: '12. März 2025',
        ort: ' ',
        personen: ['Anna', 'Bruno', 'Anna'],
        beschreibung: 'Am See',
      ),
      '12. März 2025 · Anna, Bruno · Am See',
    );
    expect(fotobuchUnterschrift(), '');
  });

  test(
    'das PDF: Titelseite, eine Seite je Gruppe, Schrift eingebettet',
    () async {
      final bilder = [
        for (final (b, h) in [(300, 200), (200, 300), (300, 200)])
          Fotobuchbild(
            jpeg: jpeg(b, h),
            breite: b,
            hoehe: h,
            unterschrift: 'Kraków · Łukasz, Ștefan, Αλέξης',
          ),
      ];
      final seiten = fotobuchPlan(
        [for (final b in bilder) b.verhaeltnis],
        format: Fotobuchformat.a4Hoch,
        jeSeite: 2,
        mitUnterschrift: true,
      );
      final pdf = await baueFotobuch(
        bilder: bilder,
        seiten: seiten,
        format: Fotobuchformat.a4Hoch,
        mitUnterschrift: true,
        schrift: await rootBundle.load(fotobuchSchriftDatei),
        titel: 'Sommer',
      );
      final text = String.fromCharCodes(pdf);
      expect(text, startsWith('%PDF'));
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text), hasLength(3));
      // Die Schrift steckt im Dokument; die Standardschriften könnten
      // „Ł", „Ș" und Griechisch nicht setzen.
      expect(text, contains('Garamond'));
    },
  );

  group('aus der Bibliothek', () {
    late Directory wurzel;
    late AppDatabase db;
    late LibraryState library;

    setUp(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_fotobuch_');
      db = AppDatabase(NativeDatabase.memory());
      final paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'lib')),
      );
      library = LibraryState()
        ..db = db
        ..paths = paths
        ..backupService = BackupService(db, paths);
    });

    tearDown(() async {
      await db.close();
      wurzel.deleteSync(recursive: true);
    });

    Future<void> foto(
      String id, {
      String? entwickelt,
      bool entwickeltDa = true,
      String? beschreibung,
      String? stadt,
    }) async {
      final datei = library.paths.absolute('originals/$id.jpg');
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(jpeg(90, 60));
      if (entwickelt != null && entwickeltDa) {
        final e = library.paths.absolute(entwickelt);
        await e.parent.create(recursive: true);
        await e.writeAsBytes(jpeg(60, 90));
      }
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2025, 3, 12),
              importedAt: DateTime(2026),
              developedRelativePath: Value(entwickelt),
              description: Value(beschreibung),
              locationCity: Value(stadt),
              locationCountry: const Value('Switzerland'),
              widthPx: const Value(90),
              heightPx: const Value(60),
            ),
          );
    }

    test('entwickelt vor Original, Namen von links nach rechts, '
        'Unlesbares bleibt draussen', () async {
      await foto('a', entwickelt: 'developed/a.jpg', stadt: 'Bern');
      // Die entwickelte Datei fehlt auf der Platte: dann das Original.
      await foto('b', entwickelt: 'developed/b.jpg', entwickeltDa: false);
      await foto('c', beschreibung: 'kaputt');
      for (final (id, name) in [('p1', 'Zora'), ('p2', 'Anna')]) {
        await db.createPerson(PeopleCompanion.insert(id: id, name: name));
      }
      // Zora steht links im Bild, Anna rechts.
      for (final (i, (person, x)) in [('p2', 0.7), ('p1', 0.1)].indexed) {
        await db
            .into(db.faces)
            .insert(
              FacesCompanion.insert(
                id: 'f$i',
                assetId: 'a',
                personId: Value(person),
                boxX: x,
                boxY: 0.2,
                boxW: 0.1,
                boxH: 0.1,
              ),
            );
      }
      final assets = await db.select(db.assets).get()
        ..sort((x, y) => x.id.compareTo(y.id));

      final gewandelt = <String>[];
      final ziel = File(p.join(wurzel.path, 'buch.pdf'));
      final ergebnis = await erstelleFotobuch(
        library,
        assets,
        (
          titel: '',
          format: Fotobuchformat.a4Hoch,
          jeSeite: 1,
          angaben: Fotobuchangabe.values.toSet(),
        ),
        ziel: ziel,
        untertitel: null,
        datum: (a) => '12. März 2025',
        sprache: 'de',
        fortschritt: (_) {},
        abbruch: () => false,
        wandle: (datei, {maxDimension}) async {
          gewandelt.add(p.relative(datei.path, from: library.paths.root.path));
          expect(maxDimension, greaterThan(2000), reason: '300 dpi');
          if (datei.path.endsWith('c.jpg')) return null;
          // Mit Beipackzettel, wie ihn ein Wandler mitliefern könnte.
          return mitSegmenten(await datei.readAsBytes(), [
            segment(0xE1, [...'Exif'.codeUnits, 0, 0]),
          ]);
        },
      );

      expect(gewandelt, [
        p.join('developed', 'a.jpg'),
        p.join('originals', 'b.jpg'),
        p.join('originals', 'c.jpg'),
      ]);
      expect(ergebnis, (seiten: 2, bilder: 2));
      final pdf = await ziel.readAsBytes();
      expect(enthaelt(pdf, 'Exif'), isFalse);
    });

    test('abgebrochen heisst: keine Datei', () async {
      await foto('a');
      final ziel = File(p.join(wurzel.path, 'buch.pdf'));
      final ergebnis = await erstelleFotobuch(
        library,
        await db.select(db.assets).get(),
        (
          titel: 'Titel',
          format: Fotobuchformat.quadrat,
          jeSeite: 4,
          angaben: const {},
        ),
        ziel: ziel,
        untertitel: null,
        datum: (a) => '',
        sprache: 'de',
        fortschritt: (_) {},
        abbruch: () => true,
        wandle: (datei, {maxDimension}) async => datei.readAsBytes(),
      );
      expect(ergebnis, isNull);
      expect(ziel.existsSync(), isFalse);
    });
  });

  test('Dateinamen aus Titeln', () {
    expect(mitPdfEndung('reise-2025.mp4'), 'reise-2025.pdf');
    expect(mitPdfEndung('Sommer'), 'Sommer.pdf');
    expect(dateinameAus('Ferien 2025/26: Süd?'), 'Ferien 2025-26- Süd-');
  });
}
