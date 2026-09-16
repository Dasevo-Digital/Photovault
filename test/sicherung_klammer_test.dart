import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// **Die Zusicherung, die eine Transaktion aufs Spiel setzt.**
///
/// Das Zurückspielen einer Sicherung schreibt Zehntausende Zeilen und
/// sichert dabei jede einzelne ab: „Eine Zeile, die hier nicht
/// hineinpasst, darf die Wiederherstellung nicht abbrechen." Seit die
/// Schleife in einer Klammer läuft (ohne sie kostete sie das
/// Sechzehnfache), hängt diese Zusicherung an einer Eigenschaft, die
/// nirgends geschrieben steht: Bleibt eine Transaktion nach einer
/// gescheiterten Anweisung benutzbar?
///
/// SQLite nimmt eine gescheiterte Anweisung für sich allein zurück, die
/// Transaktion steht danach unverändert offen. Dieser Test hält das
/// fest – wenn drift oder SQLite das eines Tages anders halten, fällt er
/// hier und nicht erst beim Zurückspielen einer echten Sicherung.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.assets).insert(AssetsCompanion.insert(
        id: 'a1',
        relativePath: 'x',
        originalFileName: 'x',
        type: 'IMAGE',
        checksum: 'c1',
        fileCreatedAt: DateTime(2024),
        importedAt: DateTime(2024)));
  });
  tearDown(() => db.close());

  Future<int> gesichter() async =>
      (await db.customSelect('SELECT count(*) AS n FROM faces').getSingle())
          .read<int>('n');

  Future<void> gutesGesicht(String id) => db.customInsert(
        'INSERT OR IGNORE INTO faces '
        '(id, asset_id, box_x, box_y, box_w, box_h, is_ignored) '
        'VALUES (?,?,?,?,?,?,0)',
        variables: [
          Variable(id),
          const Variable('a1'),
          const Variable(0.1),
          const Variable(0.1),
          const Variable(0.1),
          const Variable(0.1),
        ],
      );

  test('eine gescheiterte Anweisung vergiftet die Klammer nicht', () async {
    Object? gefangen;
    await db.transaction(() async {
      await gutesGesicht('davor');
      try {
        // NOT NULL verletzt und ohne `OR IGNORE` – muss werfen.
        await db.customInsert('INSERT INTO faces (id) VALUES (?)',
            variables: [const Variable('kaputt')]);
      } catch (e) {
        gefangen = e;
      }
      await gutesGesicht('danach');
    });

    expect(gefangen, isA<SqliteException>(),
        reason: 'die Anweisung muss wirklich gescheitert sein');
    expect(await gesichter(), 2,
        reason: 'was vor und was nach dem Fehlschlag kam, steht beides da');
  });

  test('`OR IGNORE` schluckt eine verletzte Bedingung wortlos', () async {
    // Deshalb greift die Absicherung je Zeile beim Schnappschuss selten:
    // Der Befehl dort trägt `OR IGNORE`, und der wirft gar nicht erst.
    // Wer das nicht weiss, sucht den Fehler später an der falschen Stelle.
    await db.transaction(() async {
      await db.customInsert('INSERT OR IGNORE INTO faces (id) VALUES (?)',
          variables: [const Variable('leer')]);
      await gutesGesicht('gut');
    });
    expect(await gesichter(), 1, reason: 'nur das gute Gesicht kam an');
  });
}
