import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';

class _Mitschrift extends QueryInterceptor {
  final abfragen = <String>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    abfragen.add(statement);
    return executor.runSelect(statement, args);
  }
}

/// Die Fotos von Personen (Personenseite, Browser, Handy, Familienkarte
/// und -statistik) lasen über einen Verbund mit den Gesichtern: drift holt
/// dabei jede Spalte beider Tabellen, auch die Einbettung jedes Gesichts,
/// und ein Foto mit zwei Gesichtern derselben Person kam doppelt und wurde
/// erst in Dart aussortiert. Jetzt fragen sie wie die Suche nur, welche
/// Aufnahmen die Person tragen.
void main() {
  late AppDatabase db;
  late _Mitschrift mitschrift;

  setUp(() async {
    mitschrift = _Mitschrift();
    db = AppDatabase(NativeDatabase.memory().interceptWith(mitschrift));
    Future<void> foto(
      String id,
      int jahr, {
      bool papierkorb = false,
      bool gesperrt = false,
      bool verortet = false,
    }) => db.insertAsset(
      AssetsCompanion.insert(
        id: id,
        originalFileName: '$id.jpg',
        relativePath: 'originals/$id.jpg',
        checksum: id,
        type: 'IMAGE',
        fileCreatedAt: DateTime(jahr),
        importedAt: DateTime(2026),
        isTrashed: Value(papierkorb),
        isLocked: Value(gesperrt),
        latitude: verortet ? const Value(52.0) : const Value.absent(),
        longitude: verortet ? const Value(10.0) : const Value.absent(),
      ),
    );
    var n = 0;
    Future<void> gesicht(String asset, String person) => db.insertFace(
      FacesCompanion.insert(
        id: 'g${n++}',
        assetId: asset,
        personId: Value(person),
        boxX: 0.1 * n,
        boxY: 0,
        boxW: 0.05,
        boxH: 0.05,
        embedding: Value(Uint8List(512)),
      ),
    );
    await foto('a1', 2021);
    await foto('a2', 2022, verortet: true);
    await foto('a3', 2023, papierkorb: true);
    await foto('a4', 2024, gesperrt: true);
    await foto('a5', 2025, verortet: true);
    await gesicht('a1', 'p1');
    await gesicht('a1', 'p1'); // dieselbe Person zweimal auf einem Foto
    await gesicht('a2', 'p1');
    await gesicht('a2', 'p2');
    await gesicht('a3', 'p1');
    await gesicht('a4', 'p1');
    await gesicht('a5', 'p2');
    mitschrift.abfragen.clear();
  });
  tearDown(() => db.close());

  void keineEinbettungGelesen() {
    expect(mitschrift.abfragen, isNotEmpty);
    for (final a in mitschrift.abfragen) {
      expect(a, isNot(contains('embedding')), reason: a);
    }
  }

  test('Fotos einer Person: jedes einmal, neueste zuerst', () async {
    final fotos = await db.assetsFuerPersonen(['p1']);
    expect([for (final a in fotos) a.id], ['a2', 'a1']);
    expect(
      [
        for (final a in await db.assetsFuerPersonen(['p1', 'p2'])) a.id,
      ],
      ['a5', 'a2', 'a1'],
    );
    keineEinbettungGelesen();
  });

  test('die Personenseite beobachtet dieselbe Menge', () async {
    final fotos = await db.watchAssetsForPerson('p1').first;
    expect([for (final a in fotos) a.id], ['a2', 'a1']);
    keineEinbettungGelesen();
  });

  test('Familienkarte: verortete Fotos mit ihren Personen', () async {
    final fotos = await db.verorteteAssetsFuerPersonen(['p1', 'p2']);
    expect([for (final f in fotos) f.asset.id], ['a5', 'a2']);
    expect(fotos.first.personen, {'p2'});
    expect(fotos.last.personen, {'p1', 'p2'});
    keineEinbettungGelesen();
  });

  test('Familienstatistik: jeder Auftritt mit seiner Zeit', () async {
    final auftritte = await db.auftritteFuerPersonen({'p1'});
    expect(
      [for (final a in auftritte) (a.assetId, a.zeit.year)]
        ..sort((x, y) => x.$1.compareTo(y.$1)),
      [('a1', 2021), ('a1', 2021), ('a2', 2022)],
    );
    keineEinbettungGelesen();
  });
}
