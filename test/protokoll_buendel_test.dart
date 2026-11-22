import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/befehlsbasis.dart';
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/db/database.dart';

/// Zählt die Abfragen auf `assets`.
class _Zaehler extends QueryInterceptor {
  var abfragen = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('FROM "assets"')) abfragen++;
    return executor.runSelect(statement, args);
  }
}

/// Das Protokoll des Servers (#435): jede Änderung einmal, gebündelt
/// gelesen.
void main() {
  late _Zaehler zaehler;
  late AppDatabase db;
  late Protokoll p;

  setUp(() async {
    zaehler = _Zaehler();
    db = AppDatabase(NativeDatabase.memory().interceptWith(zaehler));
    await db.batch((b) {
      b.insertAll(db.assets, [
        for (var i = 0; i < 300; i++)
          AssetsCompanion.insert(
            id: 'a$i',
            originalFileName: 'a$i.jpg',
            relativePath: 'originals/a$i.jpg',
            checksum: 'pruef$i',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026),
            importedAt: DateTime(2026),
          ),
      ]);
    });
    p = Protokoll(db);
    await p.richteEin(mitschreiben: -1);
  });
  tearDown(() => db.close());

  Future<List<String>> eintraege() async => [
    for (final z
        in await db
            .customSelect('SELECT schluessel FROM pv_aenderungen ORDER BY seq')
            .get())
      z.read<String>('schluessel'),
  ];

  test('eine Änderung steht einmal im Protokoll, ein neuer Schlüssel mit '
      'dem alten', () async {
    await db.customStatement("UPDATE assets SET rating = 3 WHERE id = 'a1'");
    expect(await eintraege(), ['["a1"]']);

    await db.customStatement("UPDATE assets SET id = 'b1' WHERE id = 'a1'");
    expect(await eintraege(), ['["a1"]', '["a1"]', '["b1"]']);
  });

  test('eine Seite liest ihre Zeilen gebündelt', () async {
    await db.customStatement('UPDATE assets SET rating = 4');
    await db.customStatement("DELETE FROM assets WHERE id = 'a7'");
    zaehler.abfragen = 0;
    final s = await p.seit(0);
    expect(s.zeilen, hasLength(300));
    expect(s.mehr, isFalse);
    expect(s.zeilen.where((z) => z.werte == null).map((z) => z.schluessel), [
      ['a7'],
    ]);
    expect(s.zeilen.firstWhere((z) => z.werte != null).werte!['rating'], 4);
    expect(zaehler.abfragen, lessThanOrEqualTo(3));
  });

  test('die Konfliktprüfung liest ihre Zeilen gebündelt', () async {
    final spalten = ['rating'];
    final basis = [
      for (final z in await p.liesViele([
        for (var i = 0; i < 300; i++) ('assets', ['a$i']),
      ]))
        Befehlsbasis(
          tabelle: 'assets',
          schluessel: z.schluessel,
          spalten: spalten,
          vorher: Befehlsbasis.hash(z.werte, spalten),
          nachher: Befehlsbasis.hash({...z.werte!, 'rating': 5}, spalten),
        ),
    ];
    zaehler.abfragen = 0;
    expect(await Befehlsbasis.passt(p, basis), isTrue);
    expect(zaehler.abfragen, lessThanOrEqualTo(3));

    await db.customStatement("UPDATE assets SET rating = 2 WHERE id = 'a9'");
    expect(await Befehlsbasis.passt(p, basis), isFalse);
  });
}
