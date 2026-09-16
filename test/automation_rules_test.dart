import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Prüft zwei Ebenen des Automatisierungs-Regelwerks (siehe
/// AutomationRulesScreen) – Verallgemeinerung der Kamera-Presets (siehe
/// camera_presets_test.dart, gleiches Muster) auf Ort/KI-Tag/Datumsbereich:
///
/// 1. Die reine DB-Seite (CRUD, Tag-Zuordnung).
/// 2. LibraryState.applyAutomationRules – die Auswertung je Regeltyp,
///    insbesondere dass ein Aufruf ohne die für einen Regeltyp nötigen
///    Parameter genau diesen Typ überspringt statt fälschlich zu matchen.
void main() {
  group('AppDatabase Automatisierungsregeln (CRUD)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('upsertAutomationRule überschreibt eine bestehende Regel bei gleicher ID', () async {
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Alt',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Strand'),
      ));
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Neu',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Berge'),
      ));

      final rules = await db.watchAutomationRules().first;
      expect(rules, hasLength(1));
      expect(rules.single.name, 'Neu');
      expect(rules.single.aiTagTerm, 'Berge');
    });

    test('deleteAutomationRule entfernt die Regel und alle zugeordneten Tags', () async {
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Test',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Strand'),
      ));
      await db.setAutomationRuleTags('r1', ['tagA', 'tagB']);

      await db.deleteAutomationRule('r1');

      expect(await db.watchAutomationRules().first, isEmpty);
      expect(await db.tagIdsForAutomationRule('r1'), isEmpty);
    });

    test('setAutomationRuleTags ersetzt die komplette Tag-Menge (nicht nur hinzufügen)', () async {
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Test',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Strand'),
      ));

      await db.setAutomationRuleTags('r1', ['a', 'b']);
      expect(await db.tagIdsForAutomationRule('r1'), unorderedEquals(['a', 'b']));

      await db.setAutomationRuleTags('r1', ['c']);
      expect(await db.tagIdsForAutomationRule('r1'), ['c']);
    });

    test('allAutomationRules liefert alle Regeln unabhängig vom triggerType', () async {
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'loc',
        name: 'Ort',
        triggerType: 'location',
        regionCenterLat: const Value(52.5),
        regionCenterLon: const Value(13.4),
        regionRadiusKm: const Value(10),
      ));
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'date',
        name: 'Datum',
        triggerType: 'dateRange',
        dateFrom: Value(DateTime(2024, 12, 20)),
        dateTo: Value(DateTime(2025, 1, 5)),
      ));

      final rules = await db.allAutomationRules();
      expect(rules.map((r) => r.id), unorderedEquals(['loc', 'date']));
    });
  });

  group('LibraryState.applyAutomationRules', () {
    late Directory tempRoot;
    late AppDatabase db;
    late ImportService import;
    late LibraryState library;
    var nextByte = 0;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('photo_vault_automation_rules_test_');
      db = AppDatabase(NativeDatabase.memory());
      final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
      import = ImportService(db, paths);
      library = LibraryState()
        ..db = db
        ..paths = paths;
    });

    tearDown(() async {
      await db.close();
      tempRoot.deleteSync(recursive: true);
    });

    Future<String> importPhoto(String name) async {
      final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
      final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3, nextByte++]);
      final result = await import.importFile(file.path);
      expect(result.outcome, ImportOutcome.imported);
      return result.assetId!;
    }

    test('location: wendet die Regel an, wenn das Foto innerhalb des Umkreises liegt', () async {
      const albumId = 'album1';
      await db.createAlbum(AlbumsCompanion.insert(id: albumId, name: 'Berlin', createdAt: DateTime.now()));
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Berlin-Umkreis',
        triggerType: 'location',
        regionCenterLat: const Value(52.5200),
        regionCenterLon: const Value(13.4050),
        regionRadiusKm: const Value(10),
        targetAlbumId: const Value(albumId),
        autoFavorite: const Value(true),
      ));

      final assetId = await importPhoto('berlin.jpg');
      // Wenige km vom Mittelpunkt entfernt (Potsdamer Platz).
      await library.applyAutomationRules(assetId, latitude: 52.5096, longitude: 13.3759);

      expect((await db.assetsInAlbumOnce(albumId)).map((a) => a.id), contains(assetId));
      expect((await db.assetById(assetId))!.isFavorite, isTrue);
    });

    test('location: wendet die Regel NICHT an, wenn das Foto außerhalb des Umkreises liegt', () async {
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Berlin-Umkreis',
        triggerType: 'location',
        regionCenterLat: const Value(52.5200),
        regionCenterLon: const Value(13.4050),
        regionRadiusKm: const Value(10),
        autoFavorite: const Value(true),
      ));

      final assetId = await importPhoto('muenchen.jpg');
      // München liegt weit außerhalb von 10 km um Berlin.
      await library.applyAutomationRules(assetId, latitude: 48.1351, longitude: 11.5820);

      expect((await db.assetById(assetId))!.isFavorite, isFalse);
    });

    test('aiTag: wendet die Regel an, wenn der Begriff unter den übergebenen KI-Tags ist', () async {
      final tagId = await db.ensureTag('Urlaub');
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Strand-Tag',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Strand'),
      ));
      await db.setAutomationRuleTags('r1', [tagId]);

      final assetId = await importPhoto('strand.jpg');
      await library.applyAutomationRules(assetId, aiTags: ['Strand', 'Sonnenuntergang']);

      final tags = await db.tagsForAsset(assetId);
      expect(tags.map((t) => t.name), contains('Urlaub'));
    });

    test('aiTag: wendet die Regel nicht an, wenn der Begriff fehlt', () async {
      final tagId = await db.ensureTag('Urlaub');
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Strand-Tag',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Strand'),
      ));
      await db.setAutomationRuleTags('r1', [tagId]);

      final assetId = await importPhoto('wald.jpg');
      await library.applyAutomationRules(assetId, aiTags: ['Wald', 'Herbst']);

      expect(await db.tagsForAsset(assetId), isEmpty);
    });

    test('dateRange: wendet die Regel innerhalb (inkl. Grenzen) des Bereichs an, sonst nicht', () async {
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Weihnachten',
        triggerType: 'dateRange',
        dateFrom: Value(DateTime(2024, 12, 20)),
        dateTo: Value(DateTime(2025, 1, 5)),
        autoFavorite: const Value(true),
      ));

      final innerhalb = await importPhoto('heiligabend.jpg');
      await library.applyAutomationRules(innerhalb, fileCreatedAt: DateTime(2024, 12, 24));
      expect((await db.assetById(innerhalb))!.isFavorite, isTrue);

      final grenzeVon = await importPhoto('grenze_von.jpg');
      await library.applyAutomationRules(grenzeVon, fileCreatedAt: DateTime(2024, 12, 20));
      expect((await db.assetById(grenzeVon))!.isFavorite, isTrue, reason: 'untere Grenze eingeschlossen');

      final grenzeBis = await importPhoto('grenze_bis.jpg');
      await library.applyAutomationRules(grenzeBis, fileCreatedAt: DateTime(2025, 1, 5));
      expect((await db.assetById(grenzeBis))!.isFavorite, isTrue, reason: 'obere Grenze eingeschlossen');

      final ausserhalb = await importPhoto('sommer.jpg');
      await library.applyAutomationRules(ausserhalb, fileCreatedAt: DateTime(2024, 7, 1));
      expect((await db.assetById(ausserhalb))!.isFavorite, isFalse);
    });

    test('ein Aufruf ohne die für einen Regeltyp nötigen Parameter überspringt genau diesen Typ', () async {
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'KI-Tag-Regel',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Strand'),
        autoFavorite: const Value(true),
      ));

      final assetId = await importPhoto('import.jpg');
      // Import-Zeit-Aufruf ohne aiTags – die aiTag-Regel darf NICHT
      // fälschlich als "kein Tag verlangt, also immer Treffer" ausgewertet
      // werden.
      await library.applyAutomationRules(assetId, latitude: 52.5, longitude: 13.4, fileCreatedAt: DateTime.now());

      expect((await db.assetById(assetId))!.isFavorite, isFalse);
    });

    test('vorab geladene Regeln (rules-Parameter) werden statt einer erneuten Abfrage benutzt', () async {
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Strand',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Strand'),
        autoFavorite: const Value(true),
      ));
      final vorabGeladen = await db.allAutomationRules();

      // Regel nach dem Laden löschen: Wird der übergebene Stand benutzt,
      // greift sie trotzdem – genau das erlaubt Stapelläufen, die Regeln
      // einmal pro Lauf statt pro Foto zu lesen.
      await db.deleteAutomationRule('r1');

      final assetId = await importPhoto('strand.jpg');
      await library.applyAutomationRules(assetId, aiTags: ['Strand'], rules: vorabGeladen);
      expect((await db.assetById(assetId))!.isFavorite, isTrue);

      // Ohne den Parameter zählt der aktuelle DB-Stand (Regel ist weg).
      final zweites = await importPhoto('strand2.jpg');
      await library.applyAutomationRules(zweites, aiTags: ['Strand']);
      expect((await db.assetById(zweites))!.isFavorite, isFalse);
    });

    test('mehrere passende Regeln werden alle angewendet', () async {
      const albumId = 'album1';
      await db.createAlbum(AlbumsCompanion.insert(id: albumId, name: 'Ziel', createdAt: DateTime.now()));
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Regel A',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Strand'),
        targetAlbumId: const Value(albumId),
      ));
      await db.upsertAutomationRule(AutomationRulesCompanion.insert(
        id: 'r2',
        name: 'Regel B',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Sonnenuntergang'),
        autoFavorite: const Value(true),
      ));

      final assetId = await importPhoto('strand.jpg');
      await library.applyAutomationRules(assetId, aiTags: ['Strand', 'Sonnenuntergang']);

      expect((await db.assetsInAlbumOnce(albumId)).map((a) => a.id), contains(assetId));
      expect((await db.assetById(assetId))!.isFavorite, isTrue);
    });
  });
}
