import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Was die Sicherung mitnimmt – und was sie nicht verraten darf.
///
/// **Zwei Befunde der 16. Prüfrunde stehen hier fest.**
///
/// Der erste: `metadata.json` beschrieb **alle** Aufnahmen, auch die im
/// gesperrten Ordner. Deren Dateien wurden seit jeher ausgelassen, ihre
/// Namen, Beschreibungen und Schlagwörter aber im Klartext in eine Datei
/// geschrieben, die typischerweise in einem Cloud-Ordner liegt.
///
/// Der zweite: Sterne und Farbmarke fehlten ganz. Die Anleitung nannte
/// „Bewertungen" trotzdem — der Rundlauftest merkte es nicht, weil er
/// selbst nie einen Stern setzte. Ein Test, der nur prüft, was die
/// Umsetzung ohnehin tut, prüft nichts.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService imp;
  late BackupService backup;
  late Directory rein;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_sicherung_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(temp.path, 'library')));
    imp = ImportService(db, paths);
    backup = BackupService(db, paths);
    rein = Directory(p.join(temp.path, 'rein'))..createSync();
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<String> aufnahme(String name, List<int> inhalt) async {
    final f = File(p.join(rein.path, name))..writeAsBytesSync(inhalt);
    final r = await imp.importFile(f.path);
    expect(r.outcome, ImportOutcome.imported, reason: name);
    return r.assetId!;
  }

  Future<Map<String, dynamic>> sichereUndLies() async {
    final ziel = Directory(p.join(temp.path, 'ziel'));
    await backup.performBackup(ziel.path).drain<void>();
    final meta = File(p.join(ziel.path, 'PhotoVault-Backup', 'metadata.json'));
    return jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
  }

  List<String> namen(Map<String, dynamic> json) => [
        for (final a in json['assets'] as List) a['originalFileName'] as String,
      ];

  group('der gesperrte Ordner bleibt gesperrt', () {
    test('kein Wort über ein gesperrtes Foto in metadata.json', () async {
      final geheim = await aufnahme('Scheidungsurkunde_Anna.jpg', [1, 2, 3]);
      await aufnahme('strand.jpg', [4, 5, 6]);
      await db.setDescription(geheim, 'Termin beim Anwalt am 3.9.');
      await db.tagAsset(geheim, 'Scheidung');
      await db.setAssetsLocked([geheim], true);

      final json = await sichereUndLies();
      final text = jsonEncode(json);

      expect(namen(json), ['strand.jpg']);
      // Nicht nur der Name: Auch Beschreibung und Schlagwort dürfen
      // nirgends im Dokument auftauchen.
      expect(text, isNot(contains('Scheidungsurkunde')));
      expect(text, isNot(contains('Anwalt')));
      expect(text, isNot(contains('Scheidung')));
    });

    test('die Datei des gesperrten Fotos liegt auch nicht im Ziel', () async {
      // Das galt schon vorher - hier steht es fest, damit die Ausnahme
      // nicht bei einer Umstellung still wegfällt.
      final geheim = await aufnahme('geheim.jpg', [1, 2, 3]);
      await aufnahme('offen.jpg', [4, 5, 6]);
      await db.setAssetsLocked([geheim], true);
      await sichereUndLies();

      final originals =
          Directory(p.join(temp.path, 'ziel', 'PhotoVault-Backup', 'originals'));
      final dateien = originals
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => p.extension(f.path) == '.jpg')
          .toList();
      expect(dateien.length, 1);
    });

    test('ein Foto im Papierkorb bleibt dagegen beschrieben', () async {
      // Seine Datei liegt aus früheren Läufen im Ziel, und wer es
      // wiederherstellt, will seine Schlagwörter zurück.
      final weg = await aufnahme('geloescht.jpg', [1, 2, 3]);
      await db.moveToTrash([weg]);
      expect(namen(await sichereUndLies()), contains('geloescht.jpg'));
    });
  });

  group('was von Hand gesetzt wurde, kommt mit', () {
    test('Sterne, Farbmarke und Ort stehen in der Sicherung', () async {
      final a = await aufnahme('urlaub.jpg', [1, 2, 3]);
      await db.setRating(a, 4);
      await db.setColorLabel(a, 'gruen');
      await db.setLocation(a, 41.9028, 12.4964);
      await db.setLocationNames(a, country: 'Italien', state: 'Latium', city: 'Rom');

      final eintrag = (await sichereUndLies())['assets'][0] as Map<String, dynamic>;
      expect(eintrag['rating'], 4);
      expect(eintrag['colorLabel'], 'gruen');
      expect(eintrag['latitude'], closeTo(41.9028, 0.0001));
      expect(eintrag['longitude'], closeTo(12.4964, 0.0001));
      expect(eintrag['locationCity'], 'Rom');
      expect(eintrag['locationCountry'], 'Italien');
    });

    test('der Rundlauf bringt sie in einer leeren Bibliothek zurück',
        () async {
      // Der eigentliche Nachweis. Ohne ihn belegt der Test oben nur,
      // dass etwas geschrieben wird - nicht, dass es ankommt.
      final a = await aufnahme('urlaub.jpg', [1, 2, 3]);
      await db.setRating(a, 5);
      await db.setColorLabel(a, 'rot');
      await db.setLocation(a, 41.9028, 12.4964);
      await db.setLocationNames(a, country: 'Italien', state: 'Latium', city: 'Rom');
      final ziel = Directory(p.join(temp.path, 'ziel'));
      await backup.performBackup(ziel.path).drain<void>();

      final zielDb = AppDatabase(NativeDatabase.memory());
      addTearDown(zielDb.close);
      final zielPaths =
          await StoragePaths.forTesting(Directory(p.join(temp.path, 'ziel_lib')));
      await BackupService(zielDb, zielPaths)
          .restoreFromBackup(p.join(ziel.path, 'PhotoVault-Backup'),
              ImportService(zielDb, zielPaths))
          .drain<void>();

      final zurueck = (await zielDb.select(zielDb.assets).get()).single;
      expect(zurueck.rating, 5);
      expect(zurueck.colorLabel, 'rot');
      expect(zurueck.latitude, closeTo(41.9028, 0.0001));
      expect(zurueck.locationCity, 'Rom');
      expect(zurueck.locationCountry, 'Italien');
    });

    test('eine ältere Sicherung ohne die Felder löscht nichts', () async {
      // Sicherungen vor dieser Fassung kennen die Schlüssel nicht. Sie
      // dürfen im Ziel nicht als „bitte auf null setzen" ankommen.
      final ziel = Directory(p.join(temp.path, 'ziel', 'PhotoVault-Backup'))
        ..createSync(recursive: true);
      await aufnahme('alt.jpg', [7, 8, 9]);
      final quelle = (await db.select(db.assets).get()).single;
      File(p.join(ziel.path, 'metadata.json')).writeAsStringSync(jsonEncode({
        'exportedAt': DateTime(2026).toIso8601String(),
        'assets': [
          {
            'checksum': quelle.checksum,
            'originalFileName': 'alt.jpg',
            'isFavorite': false,
            'description': null,
            'fileCreatedAt': quelle.fileCreatedAt.toIso8601String(),
            'tags': <String>[],
          }
        ],
        'albums': <dynamic>[],
      }));

      await db.setRating(quelle.id, 3);
      await backup.restoreFromBackup(ziel.path, imp).drain<void>();
      final danach = (await db.select(db.assets).get()).single;
      expect(danach.rating, 3, reason: 'die alte Sicherung darf nichts wegnehmen');
    });
  });
}
