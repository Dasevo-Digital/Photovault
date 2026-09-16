import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// **Der Index wurde neu geschrieben, auch wenn sich nichts geändert hatte.**
///
/// `AFTER UPDATE OF spalte` feuert, sobald die Spalte in der SET-Klausel
/// steht – nicht erst, wenn ihr Wert ein anderer wird. drift schreibt aber
/// regelmässig ganze Zeilen zurück, und die Durchgänge (Texterkennung,
/// Bildbeschreibung) tun das für die ganze Bibliothek.
///
/// Gemessen an der gewachsenen Bibliothek: 1,56 ms je Zeile mit Auslöser
/// gegen 0,03 ms ohne – über 8098 Aufnahmen rund neun Sekunden je
/// Durchgang, für lauter unveränderten Text.
///
/// Geprüft wird über `dbstat`-freie Beobachtung: Der Index trägt nach jedem
/// Schreiben denselben Inhalt, aber die **Zahl der Zeilen in der
/// FTS-Tabelle** verrät ein Neuschreiben nicht. Deshalb wird der Index
/// absichtlich verstimmt – eine Zeile von Hand daraus entfernt – und danach
/// geschaut, ob ein wirkungsloses UPDATE sie zurückbringt. Tut es das, hat
/// der Auslöser gefeuert.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(String id, {String? text}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'c_$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 2),
            ocrText: Value(text),
          ));

  Future<int> zeilenImIndex(String id) async {
    final z = await db
        .customSelect('SELECT count(*) AS n FROM asset_search_fts '
            'WHERE asset_id = ?', variables: [Variable<String>(id)])
        .getSingle();
    return z.read<int>('n');
  }

  /// Nimmt die Zeile aus dem Index heraus, ohne die Aufnahme anzufassen.
  /// Was danach den Index wieder füllt, kann nur der Auslöser gewesen sein.
  Future<void> indexVerstimmen(String id) => db.customStatement(
      'DELETE FROM asset_search_fts WHERE asset_id = ?', [id]);

  test('ein UPDATE ohne Textänderung lässt den Index in Ruhe', () async {
    await aufnahme('a1', text: 'Bahnhof Hannover');
    expect(await zeilenImIndex('a1'), 1);

    await indexVerstimmen('a1');
    expect(await zeilenImIndex('a1'), 0);

    // Dieselbe Zeichenkette noch einmal schreiben – wie es ein Durchgang
    // tut, der nichts Neues gefunden hat.
    await (db.update(db.assets)..where((t) => t.id.equals('a1')))
        .write(const AssetsCompanion(ocrText: Value('Bahnhof Hannover')));

    expect(await zeilenImIndex('a1'), 0,
        reason: 'Der Text ist derselbe – der Index hatte keinen Anlass.');
  });

  test('eine echte Textänderung schreibt den Index sehr wohl neu', () async {
    await aufnahme('a2', text: 'Bahnhof Hannover');
    await indexVerstimmen('a2');

    await (db.update(db.assets)..where((t) => t.id.equals('a2')))
        .write(const AssetsCompanion(ocrText: Value('Bahnhof Bremen')));

    expect(await zeilenImIndex('a2'), 1,
        reason: 'Sonst fände die Suche den neuen Text nie.');
  });

  test('der Übergang von und nach NULL zählt als Änderung', () async {
    // `<>` hätte hier geschwiegen, `IS NOT` nicht. Genau so sieht das
    // erste Beschreiben eines leeren Feldes aus.
    await aufnahme('a3');
    await indexVerstimmen('a3');
    await (db.update(db.assets)..where((t) => t.id.equals('a3')))
        .write(const AssetsCompanion(ocrText: Value('jetzt steht was da')));
    expect(await zeilenImIndex('a3'), 1, reason: 'NULL -> Text');

    await indexVerstimmen('a3');
    await (db.update(db.assets)..where((t) => t.id.equals('a3')))
        .write(const AssetsCompanion(ocrText: Value(null)));
    expect(await zeilenImIndex('a3'), 1, reason: 'Text -> NULL');
  });

  test('die Suche findet nach einer Änderung weiterhin das Richtige',
      () async {
    await aufnahme('a4', text: 'Leuchtturm');
    await (db.update(db.assets)..where((t) => t.id.equals('a4')))
        .write(const AssetsCompanion(ocrText: Value('Windrad')));

    final alt = await db.customSelect(
        'SELECT asset_id FROM asset_search_fts WHERE asset_search_fts '
        "MATCH 'ocr_text : (\"Leuchtturm\"*)'").get();
    final neu = await db.customSelect(
        'SELECT asset_id FROM asset_search_fts WHERE asset_search_fts '
        "MATCH 'ocr_text : (\"Windrad\"*)'").get();
    expect(alt, isEmpty, reason: 'Der alte Text darf nicht stehen bleiben.');
    expect(neu.length, 1);
  });
}
