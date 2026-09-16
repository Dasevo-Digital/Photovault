import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';

/// Die Migration 55 → 56: Wer hat die vorhandenen Schlagwörter vergeben?
///
/// Rückwirkend steht es nirgends, es lässt sich nur erschliessen. Diese
/// Prüfung hält fest, **wie eng die Regel gefasst ist** – und dass die
/// beiden Bedingungen wirklich beide zählen.
///
/// Geprüft wird an einer echten Fassung-55-Datenbank: Die Spalte wird
/// wieder entfernt und der Stempel zurückgesetzt, dann läuft die
/// Migration beim nächsten Öffnen von selbst.
/// Die Fassung, auf die diese App migriert – aus einer frisch angelegten
/// Datenbank abgelesen statt als Zahl hingeschrieben.
///
/// Eine feste Nummer im Test bricht bei jedem Schemaschritt, und zwar an
/// einer Stelle, die mit dem Schritt nichts zu tun hat (so geschehen bei
/// 56 -> 57).
Future<int> aktuelleFassung() async {
  final frisch = AppDatabase(NativeDatabase.memory());
  final v = await frisch
      .customSelect('PRAGMA user_version')
      .map((r) => r.read<int>('user_version'))
      .getSingle();
  await frisch.close();
  return v;
}

void main() {
  late Directory temp;
  late File datei;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pv_mig56_');
    datei = File(p.join(temp.path, 'library.sqlite'));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> aufFassung55Zuruecksetzen() async {
    final db = AppDatabase(NativeDatabase(datei));
    await db.customStatement('ALTER TABLE asset_tags DROP COLUMN quelle');
    await db.customStatement('PRAGMA user_version = 55');
    await db.close();
  }

  Future<Map<String, String>> quellen(AppDatabase db) async {
    final rows = await db.customSelect(
      'SELECT at.asset_id AS a, t.name AS n, at.quelle AS q '
      'FROM asset_tags at JOIN tags t ON t.id = at.tag_id',
    ).get();
    return {
      for (final r in rows)
        '${r.data['a']}/${r.data['n']}': r.data['q'] as String,
    };
  }

  Future<void> foto(AppDatabase db, String id, {required bool kiGelaufen}) =>
      db.insertAsset(AssetsCompanion.insert(
        id: id,
        relativePath: 'originals/$id.jpg',
        originalFileName: '$id.jpg',
        type: 'IMAGE',
        checksum: id,
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
        aiTagsScanned: Value(kiGelaufen),
      ));

  test('nur was die Bilderkennung erzeugt haben KANN, gilt als ihres',
      () async {
    var db = AppDatabase(NativeDatabase(datei));
    // „Strand" steht im mitgelieferten Vokabular, „Kreta 2018" nicht.
    final vokabular = await db.aiTagVocabularyTerms();
    expect(vokabular, contains('Strand'),
        reason: 'ohne diesen Begriff prueft der Test nichts');
    expect(vokabular, isNot(contains('Kreta 2018')));

    await foto(db, 'verschlagwortet', kiGelaufen: true);
    await foto(db, 'unberuehrt', kiGelaufen: false);

    // Vier Fälle, die sich in genau je einer Bedingung unterscheiden.
    await db.tagAsset('verschlagwortet', 'Strand');      // beides -> ki
    await db.tagAsset('verschlagwortet', 'Kreta 2018');  // kein Vokabular
    await db.tagAsset('unberuehrt', 'Strand');           // nie gelaufen
    await db.tagAsset('unberuehrt', 'Kreta 2018');       // keines von beidem
    await db.close();

    await aufFassung55Zuruecksetzen();

    db = AppDatabase(NativeDatabase(datei));
    // Die erste Abfrage löst die Migration aus.
    final fassung = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(fassung, await aktuelleFassung());

    expect(await quellen(db), {
      'verschlagwortet/Strand': Tagquelle.ki,
      'verschlagwortet/Kreta 2018': Tagquelle.hand,
      'unberuehrt/Strand': Tagquelle.hand,
      'unberuehrt/Kreta 2018': Tagquelle.hand,
    });
    await db.close();
  });

  test('ohne einen einzigen Treffer bleibt alles Handvergabe', () async {
    // Die Gegenprobe: Eine Bibliothek, die nie verschlagwortet wurde,
    // darf durch die Migration nichts loeschbar bekommen.
    var db = AppDatabase(NativeDatabase(datei));
    await foto(db, 'a', kiGelaufen: false);
    await db.tagAsset('a', 'Strand');
    await db.tagAsset('a', 'Hund');
    await db.close();

    await aufFassung55Zuruecksetzen();

    db = AppDatabase(NativeDatabase(datei));
    expect((await quellen(db)).values.toSet(), {Tagquelle.hand});
    await db.close();
  });
}
