import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Woher ein Schlagwort stammt – und was das beim Sperren bedeutet.
///
/// **Der Befund der 15. Prüfrunde:** Beim Sperren löschte die App den
/// erkannten Text, die Bildunterschrift und das Embedding, „sonst bliebe
/// der Inhalt in der unverschlüsselten Datenbank lesbar". Die
/// Schlagwörter der Bilderkennung blieben – nicht aus Nachlässigkeit,
/// sondern weil sie von Handvergaben nicht zu unterscheiden waren.
/// Fassung 56 macht den Unterschied sichtbar.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService imp;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_tagquelle_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'l')));
    imp = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<String> foto(String name) async {
    final inc = Directory(p.join(tempRoot.path, 'in'))..createSync(recursive: true);
    final r = await imp.importFile((File(p.join(inc.path, '$name.jpg'))
          ..writeAsBytesSync(List.filled(64, name.codeUnitAt(0))))
        .path);
    return r.assetId!;
  }

  Future<Set<String>> namen(String id) async =>
      {for (final t in await db.tagsForAsset(id)) t.name};

  Future<Map<String, String>> quellen(String id) async {
    final rows = await db.customSelect(
      'SELECT t.name AS name, at.quelle AS quelle FROM asset_tags at '
      'JOIN tags t ON t.id = at.tag_id WHERE at.asset_id = ?',
      variables: [Variable<String>(id)],
    ).get();
    return {
      for (final r in rows) r.data['name'] as String: r.data['quelle'] as String,
    };
  }

  group('wer den Begriff vergeben hat', () {
    test('ohne Angabe gilt Handvergabe', () async {
      final id = await foto('a');
      await db.tagAsset(id, 'Urlaub');
      expect(await quellen(id), {'Urlaub': Tagquelle.hand});
    });

    test('die Bilderkennung kennzeichnet sich', () async {
      final id = await foto('b');
      await db.tagAsset(id, 'Strand', quelle: Tagquelle.ki);
      expect(await quellen(id), {'Strand': Tagquelle.ki});
    });

    test('Hand uebernimmt einen KI-Vorschlag', () async {
      // Wer einen Vorschlag selbst noch einmal vergibt, macht ihn zu
      // seinem – und ab da wird er nicht mehr gelöscht.
      final id = await foto('c');
      await db.tagAsset(id, 'Hund', quelle: Tagquelle.ki);
      await db.tagAsset(id, 'Hund');
      expect(await quellen(id), {'Hund': Tagquelle.hand});
    });

    test('die KI erklaert eine Handvergabe NICHT zu ihrer', () async {
      // **Die wichtigere Richtung.** Andersherum würde ein von Hand
      // vergebener Begriff löschbar, nur weil die Bilderkennung ihn
      // später auch vorschlägt.
      final id = await foto('d');
      await db.tagAsset(id, 'Oma');
      await db.tagAsset(id, 'Oma', quelle: Tagquelle.ki);
      expect(await quellen(id), {'Oma': Tagquelle.hand});
    });
  });

  group('was das Sperren entfernt', () {
    test('KI-Begriffe gehen, Handvergaben bleiben', () async {
      final id = await foto('e');
      await db.tagAsset(id, 'Schlafzimmer', quelle: Tagquelle.ki);
      await db.tagAsset(id, 'Kind', quelle: Tagquelle.ki);
      await db.tagAsset(id, 'Weihnachten 2019');
      await db.setOcrResult(id, 'Kontonummer');
      await db.saveEmbedding(id, Float32List.fromList(List.filled(512, .1)));
      await db.markAiTagsScanned([id]);

      await db.clearDerivedContentData([id]);

      expect(await namen(id), {'Weihnachten 2019'},
          reason: 'was die Bilderkennung aus dem Bild gelesen hat, ist weg');
      final danach = (await db.select(db.assets).get()).single;
      expect(danach.aiTagsScanned, isFalse,
          reason: 'damit nach dem Entsperren neu verschlagwortet wird');
    });

    test('ein anderes Foto bleibt unberuehrt', () async {
      // Die Gegenprobe: Das Löschen darf nicht die ganze Tabelle treffen.
      final gesperrt = await foto('f');
      final offen = await foto('g');
      await db.tagAsset(gesperrt, 'Strand', quelle: Tagquelle.ki);
      await db.tagAsset(offen, 'Strand', quelle: Tagquelle.ki);

      await db.clearDerivedContentData([gesperrt]);

      expect(await namen(gesperrt), isEmpty);
      expect(await namen(offen), {'Strand'});
    });
  });

  group('eine Sicherung darf die Herkunft nicht einebnen', () {
    test('KI-Begriffe stehen getrennt in der Auskunft', () async {
      final id = await foto('h');
      await db.tagAsset(id, 'Strand', quelle: Tagquelle.ki);
      await db.tagAsset(id, 'Kreta 2018');

      expect((await db.allTagNamesByAssetId())[id]!.toSet(),
          {'Strand', 'Kreta 2018'});
      expect((await db.kiTagNamesByAssetId())[id], {'Strand'},
          reason: 'sonst käme nach einer Rücksicherung alles als '
              'Handvergabe zurück und stünde wieder im Klartext');
    });
  });
}
