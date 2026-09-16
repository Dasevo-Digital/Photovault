import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// **"Keine Treffer" war die falsche Auskunft.**
///
/// Zwei Suchweisen brauchen erst einen Durchgang ueber die Bibliothek,
/// bevor sie ueberhaupt etwas finden koennen: die KI-Bildsuche und die
/// Suche im erkannten Text. Wer die App neu aufsetzt, hat beides noch
/// nicht - und die Suche sagte trotzdem "Keine Treffer", als laege es an
/// der Suchanfrage. [AppDatabase.zaehleMitErkanntemText] ist die Frage,
/// mit der der Suchbildschirm die beiden Faelle auseinanderhaelt.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> aufnahme(String id) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'c_$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 1, 1),
          importedAt: DateTime(2026, 1, 2),
        ));
    return id;
  }

  test('eine frische Bibliothek hat keinen erkannten Text', () async {
    await aufnahme('a1');
    await aufnahme('a2');
    expect(await db.zaehleMitErkanntemText(), 0);
  });

  test('ein Lauf ohne Fund zaehlt nicht mit', () async {
    await aufnahme('a1');
    // Gescannt, aber im Bild stand nichts: Das ist etwas anderes als
    // "noch nie angesehen" - und trotzdem kein erkannter Text.
    await db.setOcrResult('a1', '');
    expect(await db.zaehleMitErkanntemText(), 0);
  });

  test('ein Fund zaehlt', () async {
    await aufnahme('a1');
    await aufnahme('a2');
    await db.setOcrResult('a1', 'Bahnhof Ilsenburg');
    await db.setOcrResult('a2', '');
    expect(await db.zaehleMitErkanntemText(), 1);
  });
}
