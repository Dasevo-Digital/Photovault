import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/raw_formats.dart';
import 'package:photo_vault/services/search_filters.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Suche nach Dateiformaten – „zeig mir nur die DNGs".
void main() {
  group('Das Format aus dem Dateinamen', () {
    test('einfacher Fall, kleingeschrieben und ohne Punkt', () {
      expect(dateiformatAus('IMG_1234.CR3'), 'cr3');
      expect(dateiformatAus('foto.jpg'), 'jpg');
    });

    test('mehrere Punkte: es zaehlt der letzte', () {
      // `Urlaub.2019.jpg` ist ein jpg, kein „2019.jpg".
      expect(dateiformatAus('Urlaub.2019.jpg'), 'jpg');
      expect(dateiformatAus('a.b.c.DNG'), 'dng');
    });

    test('ohne Endung gibt es null, nicht den leeren Text', () {
      // „hat kein Format" und „Format unbekannt" sind zwei verschiedene
      // Aussagen. Der leere Text wuerde als eigenes Format in der
      // Auswahlliste auftauchen.
      expect(dateiformatAus('ohnepunkt'), isNull);
      expect(dateiformatAus('endetmitpunkt.'), isNull);
    });

    test('die RAW-Liste ist abgeleitet, nicht abgeschrieben', () {
      // Zwei Listen von Hand waeren die naheliegendste Art, dass sie
      // auseinanderlaufen.
      expect(rawDateiformate.length, rawImageExtensions.length);
      for (final e in rawImageExtensions) {
        expect(rawDateiformate, contains(e.substring(1)));
      }
      expect(rawDateiformate, isNot(contains('jpg')));
    });
  });

  group('Die Abfrage', () {
    late Directory tempRoot;
    late AppDatabase db;
    late ImportService import;
    var naechstesByte = 0;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('pv_format_');
      db = AppDatabase(NativeDatabase.memory());
      final paths =
          await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
      import = ImportService(db, paths);
    });

    tearDown(() async {
      await db.close();
      tempRoot.deleteSync(recursive: true);
    });

    Future<void> importiere(String name) async {
      final inc = Directory(p.join(tempRoot.path, 'in'))..createSync(recursive: true);
      final f = File(p.join(inc.path, name))
        ..writeAsBytesSync([1, 2, 3, naechstesByte++]);
      final r = await import.importFile(f.path);
      expect(r.outcome, ImportOutcome.imported, reason: name);
    }

    Future<List<String>> suche(Set<String> formate) async {
      final treffer = await db.searchAssets(SearchFilters(formate: formate));
      return treffer.map((a) => a.originalFileName).toList()..sort();
    }

    test('der Import traegt das Format ein', () async {
      await importiere('a.DNG');
      final alle = await db.searchAssets(const SearchFilters());
      expect(alle.single.dateiformat, 'dng',
          reason: 'kleingeschrieben, ohne Punkt');
    });

    test('ein Format filtert genau dieses heraus', () async {
      await importiere('a.dng');
      await importiere('b.jpg');
      await importiere('c.cr3');

      expect(await suche({'dng'}), ['a.dng']);
      expect(await suche({'jpg'}), ['b.jpg']);
    });

    test('mehrere Formate sind ein ODER', () async {
      await importiere('a.dng');
      await importiere('b.jpg');
      await importiere('c.cr3');

      expect(await suche({'dng', 'cr3'}), ['a.dng', 'c.cr3']);
    });

    test('ein leerer Satz filtert NICHT', () async {
      // Der Fall, der am leichtesten falsch herauskommt: `isIn([])` waere
      // eine Bedingung, die nie zutrifft - die Suche bliebe ohne
      // erkennbaren Grund leer.
      await importiere('a.dng');
      await importiere('b.jpg');

      expect(await suche({}), ['a.dng', 'b.jpg']);
    });

    test('die Auswahlliste kennt nur, was da ist', () async {
      await importiere('a.dng');
      await importiere('b.jpg');
      await importiere('c.dng');

      expect(await db.distinctDateiformate(), ['dng', 'jpg'],
          reason: 'ohne Wiederholung, alphabetisch');
    });

    test('gespeicherte Suchen verlieren den Formatfilter nicht', () async {
      // Sie werden serialisiert. Ein vergessenes Feld faellt erst beim
      // naechsten Laden auf - und dann als „die Suche findet ploetzlich
      // mehr".
      const vorher = SearchFilters(formate: {'dng', 'cr3'});
      final nachher = SearchFilters.fromJson(vorher.toJson());
      expect(nachher.formate, {'dng', 'cr3'});
    });

    test('ein Formatfilter allein macht die Suche nicht leer', () {
      expect(const SearchFilters(formate: {'dng'}).isEmpty, isFalse);
      expect(const SearchFilters().isEmpty, isTrue);
    });
  });
}
