import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/beilagenangaben.dart';
import 'package:kern/services/import_plan.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/umzugsquelle.dart';

void main() {
  late Directory temp;
  late AppDatabase db;
  late ImportService importe;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_umzug_test_');
    db = AppDatabase(NativeDatabase.memory());
    importe = ImportService(
      db,
      await StoragePaths.forTesting(Directory(p.join(temp.path, 'ziel'))),
    );
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<String> datei(String name, List<int> bytes) async {
    final f = File(p.normalize(p.join(temp.path, 'quelle', name)));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    return f.path;
  }

  Future<void> json(String name, Object wert) async {
    await datei(name, utf8.encode(jsonEncode(wert)));
  }

  Future<String> zip(String name, List<ArchiveFile> eintraege) async {
    final a = Archive();
    for (final e in eintraege) {
      a.addFile(e);
    }
    final f = File(p.join(temp.path, name));
    await f.writeAsBytes(ZipEncoder().encode(a));
    return f.path;
  }

  final xmp = utf8.encode(
    '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
    'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description '
    'xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="4" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:description><rdf:Alt><rdf:li xml:lang="x-default">XMP-Text</rdf:li></rdf:Alt></dc:description>'
    '<dc:subject><rdf:Bag><rdf:li>Familie</rdf:li></rdf:Bag></dc:subject>'
    '</rdf:Description></rdf:RDF></x:xmpmeta>',
  );

  for (final anzahl in [100, 101]) {
    test('Albumvereinigung prüft $anzahl Zuordnungen vor dem Kürzen', () async {
      for (var i = 0; i < anzahl; i++) {
        await datei('a$i/foto.jpg', [1, 2, 3]);
        await json('a$i/metadata.json', {'title': 'Album $i'});
      }
      final q = await Umzugsquelle.ordner(p.join(temp.path, 'quelle'));
      addTearDown(q.schliesse);
      final plan = await ImportPlanDienst(db, importe).erstelle(q.dateien);
      q.verbindeDubletten(plan);
      if (anzahl == 100) {
        expect(q.fehler, isEmpty);
        final b = q.beilagen[q.dateien.first]!;
        expect(b.alben.length, 100);
        expect(Beilagenangaben.ausText(b.alsText())!.alben.length, 100);
        final e = plan.eintraege.firstWhere((e) => e.art == ImportPlanArt.neu);
        final dienst = ImportPlanDienst(db, importe);
        await importe.importFile(
          e.pfad,
          erwarteteAngaben: e.angaben,
          beiEintrag: (id) => dienst.uebernehme(plan, e.mitBeilage(b), id),
        );
        expect((await db.select(db.albums).get()).length, 100);
      } else {
        expect(q.fehler, q.dateien.toSet());
        expect(q.beilagen, isEmpty);
        expect(await db.select(db.assets).get(), isEmpty);
        expect(
          () => Beilagenangaben.aus({
            'alben': List.generate(101, (i) => 'Album $i'),
          }),
          throwsFormatException,
        );
        expect(
          () => Beilagenangaben(
            alben: List.generate(101, (i) => 'Album $i'),
          ).alsText(),
          throwsFormatException,
        );
      }
    });
  }

  test(
    'Verbotene Linkköpfe werden vor dem Lesen defekter Linkdaten abgelehnt',
    () async {
      final f = await zip('link-vorpruefung.zip', [
        ArchiveFile.symlink('link.jpg', 'x' * (1024 * 1024)),
      ]);
      final bytes = await File(f).readAsBytes();
      // Lokalen Nutzinhalt beschädigen, Zentralverzeichnis erhalten. Ein
      // Decoder müsste jetzt scheitern; die Vorprüfung braucht ihn nicht.
      final offset =
          30 + bytes[26] + (bytes[27] << 8) + bytes[28] + (bytes[29] << 8);
      bytes[offset] ^= 0xff;
      await File(f).writeAsBytes(bytes);
      await expectLater(
        Umzugsquelle.archive([f]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'Ablehnungsgrund',
            'pv_umzug_zip_pfad',
          ),
        ),
      );
    },
  );

  test(
    'Die Gesamtgrenze zählt JSON und XMP, schützt Originale und erlaubt einen erneuten gültigen Versuch',
    () async {
      final foto = await datei('bild.jpg', [1, 2, 3]);
      final j = utf8.encode('{"title":"bild.jpg"}');
      await datei('bild.jpg.json', j);
      await datei('bild.xmp', xmp);
      final bytes = j.length + xmp.length;
      final root = p.join(temp.path, 'quelle');
      await expectLater(
        Umzugsquelle.ordner(root, hoechstensBeilagenBytes: bytes - 1),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'Gesamtgrenze',
            'pv_umzug_metadaten_budget',
          ),
        ),
      );
      expect(await db.select(db.assets).get(), isEmpty);
      expect(await File(foto).readAsBytes(), [1, 2, 3]);
      final quelle = await Umzugsquelle.ordner(
        root,
        hoechstensBeilagenBytes: bytes,
      );
      expect(quelle.fehler, isEmpty);
      expect(quelle.beilagen[foto]!.sterne, 4);
      await quelle.schliesse();
      expect(await File(foto).exists(), isTrue);
    },
  );

  test(
    'Takeout und XMP werden vor dem Import geprüft, gewählte Angaben wirken lokal',
    () async {
      final foto = await datei('Album/bild.jpg', [1, 2, 3]);
      await json('Album/metadata.json', {'title': 'Testalbum'});
      await json('Album/bild.jpg.supplemental-metadata.json', {
        'title': 'bild.jpg',
        'description': 'Takeout-Text',
        'photoTakenTime': {'timestamp': '946684860'},
        'favorited': true,
        'geoData': {'latitude': 12.5, 'longitude': 23.5},
      });
      await datei('Album/bild.xmp', xmp);
      final quelle = await Umzugsquelle.ordner(p.join(temp.path, 'quelle'));
      expect(quelle.dateien, [foto]);
      expect(quelle.fehler, isEmpty);
      expect(quelle.konflikte[foto], [
        'Takeout: Takeout-Text',
        'XMP: XMP-Text',
      ]);
      expect(await db.select(db.assets).get(), isEmpty);
      final dienst = ImportPlanDienst(db, importe);
      final plan = await dienst.erstelle(quelle.dateien);
      final e = plan.eintraege.single.mitBeilage(quelle.beilagen[foto]);
      final r = await importe.importFile(
        foto,
        erwarteteAngaben: e.angaben,
        beiEintrag: (id) => dienst.uebernehme(plan, e, id),
      );
      expect(r.outcome, ImportOutcome.imported);
      final a = (await db.select(db.assets).get()).single;
      expect(
        (a.rating, a.description, a.isFavorite, a.latitude, a.longitude),
        (4, 'Takeout-Text', true, 12.5, 23.5),
      );
      expect(a.fileCreatedAt.toUtc(), DateTime.utc(2000, 1, 1, 0, 1));
      expect(a.datumGeschaetzt, isFalse);
      final album = (await db.select(db.albums).get()).single;
      expect(album.name, 'Testalbum');
      expect((await db.albumAufnahmen(album.id)).single.id, a.id);
      expect(
        (await db.tagsForAsset(a.id)).map((t) => t.name),
        contains('Familie'),
      );
      final roundtrip = Beilagenangaben.ausText(
        quelle.beilagen[foto]!.alsText(),
      )!;
      expect(roundtrip.alsMap(), quelle.beilagen[foto]!.alsMap());
      await quelle.schliesse();
      expect(await File(foto).exists(), isTrue);
    },
  );

  test(
    'Gleiche Dateien aus mehreren Alben behalten alle Zuordnungen',
    () async {
      for (final name in ['A', 'B']) {
        await datei('$name/foto.jpg', [7, 8]);
        await json('$name/metadata.json', {'title': name});
      }
      final quelle = await Umzugsquelle.ordner(p.join(temp.path, 'quelle'));
      final dienst = ImportPlanDienst(db, importe);
      final plan = await dienst.erstelle(quelle.dateien);
      quelle.verbindeDubletten(plan);
      expect(
        plan.eintraege.where((e) => e.art == ImportPlanArt.neu),
        hasLength(1),
      );
      final e = plan.eintraege.firstWhere((e) => e.art == ImportPlanArt.neu);
      expect(quelle.beilagen[e.pfad]!.alben.toSet(), {'A', 'B'});
      final r = await importe.importFile(
        e.pfad,
        beiEintrag: (id) =>
            dienst.uebernehme(plan, e.mitBeilage(quelle.beilagen[e.pfad]), id),
      );
      expect(r.outcome, ImportOutcome.imported);
      expect((await db.select(db.albumAssets).get()), hasLength(2));
      expect(await db.select(db.assets).get(), hasLength(1));
    },
  );

  test(
    'Widersprüchliche Dubletten und defekte JSON-Beilagen werden nicht still übernommen',
    () async {
      for (final name in ['A', 'B']) {
        await datei('$name/foto.jpg', [7, 8]);
        await json('$name/foto.jpg.json', {
          'title': 'foto.jpg',
          'description': name,
        });
      }
      final kaputt = await datei('kaputt.jpg', [9]);
      await datei('kaputt.jpg.json', utf8.encode('{'));
      final quelle = await Umzugsquelle.ordner(p.join(temp.path, 'quelle'));
      quelle.verbindeDubletten(
        await ImportPlanDienst(db, importe).erstelle(quelle.dateien),
      );
      expect(quelle.fehler, containsAll(quelle.dateien));
      expect(quelle.fehler, contains(kaputt));
      expect(quelle.beilagen, isEmpty);
    },
  );

  test(
    'JSON-Datum außerhalb des gültigen Bereichs wird sichtbar abgewiesen',
    () async {
      final foto = await datei('foto.jpg', [4]);
      await json('foto.jpg.json', {
        'title': 'foto.jpg',
        'photoTakenTime': {'timestamp': '999999999999999999'},
      });
      final quelle = await Umzugsquelle.ordner(p.join(temp.path, 'quelle'));
      expect(quelle.fehler, {foto});
      expect(quelle.beilagen, isEmpty);
    },
  );

  test(
    'ZIP-Teile mit gleichen Inhalten funktionieren, temporäre Originale werden entfernt',
    () async {
      final a = await zip('teil1.zip', [
        ArchiveFile('Takeout/Fotos/f.jpg', 2, [1, 2]),
      ]);
      final b = await zip('teil2.zip', [
        ArchiveFile('Takeout/Fotos/f.jpg', 2, [1, 2]),
        ArchiveFile(
          'Takeout/Fotos/f.jpg.json',
          17,
          utf8.encode('{"title":"f.jpg"}'),
        ),
      ]);
      final quelle = await Umzugsquelle.archive([a, b]);
      final file = File(quelle.dateien.single);
      expect(await file.readAsBytes(), [1, 2]);
      await quelle.schliesse();
      expect(await file.exists(), isFalse);
      expect(await File(a).exists(), isTrue);
    },
  );

  test('ZIP-Verknüpfungen werden nicht entpackt', () async {
    final f = await zip('link.zip', [
      ArchiveFile.symlink('link.jpg', '../privat.jpg'),
    ]);
    await expectLater(Umzugsquelle.archive([f]), throwsFormatException);
  });

  test(
    'Unplausible ZIP-Größen werden vor der Dekompression abgewiesen',
    () async {
      final f = await zip('bombe.zip', [
        ArchiveFile('foto.jpg', 1024 * 1024 * 1024, [1]),
      ]);
      await expectLater(
        Umzugsquelle.archive([f]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'Grenze',
            'pv_umzug_zip_groesse',
          ),
        ),
      );
    },
  );

  for (final name in [
    '../ausbruch.jpg',
    '/absolut.jpg',
    'C:/foto.jpg',
    'A/../foto.jpg',
    'A./foto.jpg',
    'A//foto.jpg',
    'CON.jpg',
    'album/LPT1.txt',
  ]) {
    test('ZIP-Pfad $name wird vor dem Schreiben abgewiesen', () async {
      final f = await zip('pfad.zip', [
        ArchiveFile(name, 1, [1]),
      ]);
      await expectLater(Umzugsquelle.archive([f]), throwsFormatException);
      expect(await File(p.join(temp.path, 'ausbruch.jpg')).exists(), isFalse);
    });
  }
  test(
    'ZIP-Teile mit widersprüchlichen Namen oder Inhalten werden abgewiesen',
    () async {
      final a = await zip('a.zip', [
        ArchiveFile('A.jpg', 1, [1]),
      ]);
      final b = await zip('b.zip', [
        ArchiveFile('a.jpg', 1, [1]),
      ]);
      final c = await zip('c.zip', [
        ArchiveFile('A.jpg', 1, [2]),
      ]);
      await expectLater(Umzugsquelle.archive([a, b]), throwsFormatException);
      await expectLater(Umzugsquelle.archive([a, c]), throwsFormatException);
    },
  );
  test('XMP-Verweis außerhalb der Quelle wird nicht gelesen', () async {
    if (Platform.isWindows) return;
    final foto = await datei('f.jpg', [4]);
    final fremd = File(p.join(temp.path, 'fremd.xmp'));
    await fremd.writeAsBytes(xmp);
    await Link(p.join(temp.path, 'quelle', 'f.xmp')).create(fremd.path);
    final quelle = await Umzugsquelle.ordner(p.join(temp.path, 'quelle'));
    expect(quelle.fehler, {foto});
    expect(quelle.beilagen, isEmpty);
  });
}
