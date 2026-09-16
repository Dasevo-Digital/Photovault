import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/search_filters.dart';

/// **„a AND b" war ein Syntaxfehler, kein Suchbegriff.**
///
/// Die Volltextsuche setzt die eingetippten Wörter zu einem FTS5-Ausdruck
/// zusammen. Der Filter davor lässt nur Buchstaben, Ziffern und
/// Unterstrich durch – das hält Anführungszeichen, Klammern und Sternchen
/// heraus, aber nicht die drei Wörter, die FTS5 selbst als Verknüpfung
/// liest. Aus `AND` wurde der Operator AND, und die Abfrage brach mit
/// „fts5: syntax error near AND" ab; im Suchbildschirm kam das als
/// „Suche fehlgeschlagen" an, obwohl nichts fehlgeschlagen war ausser der
/// Zusammensetzung.
///
/// Wer nach „schwarz AND weiss" sucht, erwartet Treffer oder keine – aber
/// keinen Fehler.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(String id, String beschreibung) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'c_$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 2),
            description: Value(beschreibung),
          ));

  Future<List<String>> suche(String text) => db.searchAssetIds(
      SearchFilters(query: text, textMode: SearchTextMode.description));

  test('die Verknüpfer von FTS5 sind gewöhnliche Suchwörter', () async {
    await aufnahme('a1', 'Ein Schild mit AND und OR und NOT darauf');
    // Bewusst ohne ein Wort, das mit „and", „or" oder „not" BEGINNT: Die
    // Suche ist eine Präfixsuche, und „anderes" wäre ein berechtigter
    // Treffer auf „and" gewesen – das hätte diesen Test scheitern lassen,
    // ohne dass am Programm etwas falsch ist.
    await aufnahme('a2', 'Ein Bild vom Meer');

    for (final wort in ['AND', 'OR', 'NOT', 'and', 'or', 'not']) {
      expect(await suche(wort), ['a1'],
          reason: '„$wort" muss ein Wort sein, keine Verknüpfung.');
    }
  });

  test('mehrere Wörter, darunter ein Verknüpfer, bleiben eine Und-Suche',
      () async {
    await aufnahme('a1', 'Schild mit AND darauf');
    await aufnahme('a2', 'Schild ohne alles');

    expect(await suche('Schild AND darauf'), ['a1']);
    // Und die Und-Verknüpfung wirkt weiterhin: Ein Wort, das nur bei a1
    // steht, schliesst a2 aus.
    expect(await suche('Schild darauf'), ['a1']);
    expect((await suche('Schild')).toSet(), {'a1', 'a2'});
  });

  test('Sonderzeichen und Leereingaben werfen weiterhin nicht', () async {
    await aufnahme('a1', 'Urlaub am Meer');

    for (final eingabe in ['"', '*', '(', ')', '^', ':', '-', '{}', '🙂']) {
      expect(await suche(eingabe), isEmpty,
          reason: '„$eingabe" enthält kein Suchwort.');
    }
    expect(await suche('Urlaub'), ['a1']);
  });

  test('die Präfixsuche bleibt erhalten', () async {
    await aufnahme('a1', 'Sonnenuntergang am Strand');

    expect(await suche('Sonnen'), ['a1'],
        reason: 'Das nachgestellte * darf durch das Zitieren nicht verloren '
            'gehen.');
  });
}
