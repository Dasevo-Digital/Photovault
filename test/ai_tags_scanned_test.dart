import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Ein Foto, zu dem CLIP keinen passenden Vokabelbegriff findet, bleibt
/// dauerhaft ohne Tags. Ohne eigenes "wurde verschlagwortet"-Flag wäre es
/// damit bei JEDEM Programmstart erneut Kandidat – die Tagging-Stufe lüde
/// beide CLIP-Encoder (577 MB), rechnete es durch und fände wieder nichts.
/// Gemessen belegte die App dadurch 1066 statt 214 MB Grundlast.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService importService;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_aitags_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    importService = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<String> importiere(String name, int fuellung) async {
    final inc = Directory(p.join(tempRoot.path, 'in'))..createSync(recursive: true);
    final f = File(p.join(inc.path, name))..writeAsBytesSync(List.filled(64, fuellung));
    final r = await importService.importFile(f.path);
    return r.assetId!;
  }

  test('ein verschlagwortetes Foto ohne Treffer wird nicht erneut zum Kandidaten', () async {
    final id = await importiere('ohne_treffer.jpg', 1);

    // Vor dem Lauf: offener Kandidat.
    expect((await db.assetsForAiTagging(onlyUntagged: true)).map((a) => a.id), contains(id));
    expect(await db.countAiTagging(onlyUntagged: true), 1);

    // Die Stufe lief durch, fand aber keinen passenden Begriff – deshalb
    // kein Tag, aber sehr wohl der Vermerk.
    await db.markAiTagsScanned([id]);

    expect((await db.assetsForAiTagging(onlyUntagged: true)), isEmpty,
        reason: 'sonst lädt die Tagging-Stufe bei jedem Start erneut beide '
            'CLIP-Encoder, um wieder nichts zu finden');
    expect(await db.countAiTagging(onlyUntagged: true), 0,
        reason: 'die Wartend-Anzeige muss zur Kandidatenliste passen');
  });

  test('"Alle" verschlagwortet auch bereits vermerkte Fotos erneut', () async {
    final id = await importiere('nochmal.jpg', 2);
    await db.markAiTagsScanned([id]);

    expect((await db.assetsForAiTagging(onlyUntagged: false)).map((a) => a.id), contains(id),
        reason: 'der manuelle "Alle"-Lauf darf sich vom Vermerk nicht aufhalten lassen');
  });

  test('ein bereits getaggtes Foto bleibt auch ohne Vermerk draussen', () async {
    // Fotos, die vor Einführung des Flags verschlagwortet wurden: Das Flag
    // steht auf false, sie haben aber Tags.
    final id = await importiere('alt_getaggt.jpg', 3);
    await db.tagAsset(id, 'Strand');

    final kandidaten = await db.assetsForAiTagging(onlyUntagged: true);
    expect(kandidaten.map((a) => a.id), isNot(contains(id)));
  });

  test('ein frisches, unbearbeitetes Foto ist weiterhin Kandidat', () async {
    final id = await importiere('frisch.jpg', 4);
    expect((await db.assetsForAiTagging(onlyUntagged: true)).map((a) => a.id), contains(id),
        reason: 'sonst würde nie etwas verschlagwortet');
  });
}
