import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// **Ein Verbund in drift holt jede Spalte jeder beteiligten Tabelle.**
///
/// Und baut daraus für jede Zeile die Objekte beider Tabellen. Wo nur zwei
/// Spalten gebraucht werden, ist das der grösste Teil der Arbeit. An der
/// gewachsenen Bibliothek gemessen (7475 Einbettungen, 25.761 Schlagwörter,
/// 18.139 Gesichter):
///
/// ```
/// allEmbeddings            105,0 ms  ->  19,3 ms
/// allTagNamesByAssetId      55,0 ms  ->  23,1 ms
/// alleGesichtsregionen      11,2 ms  ->   3,9 ms
/// ```
///
/// Bei `allEmbeddings` hing an jeder Einbettung eine vollständige Aufnahme
/// mit 56 Spalten, bei `alleGesichtsregionen` an jedem Gesicht seine
/// 512er-Einbettung – zwei Kilobyte, die der XMP-Export nie ansieht.
///
/// **Was dieser Prüfstand sichert, ist nicht die Geschwindigkeit, sondern
/// die Spaltennamen.** Gelesen wird jetzt über `rawData` (auch das kostet
/// die Hälfte, siehe [AppDatabase.assetsOnThisDay]), und die Namen dafür
/// vergibt drift. Änderte sich daran etwas, liefe das Lesen in einen
/// Fehler – ohne diese Prüfungen erst beim Anwender.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(String id,
          {bool papierkorb = false, bool gesperrt = false}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026),
            importedAt: DateTime(2026),
            isTrashed: Value(papierkorb),
            isLocked: Value(gesperrt),
          ));

  Float32List vektor(double erster) =>
      Float32List.fromList([erster, 0.5, -0.25, 1.0]);

  group('Die Einbettungen', () {
    test('kommen samt Kennung zurueck', () async {
      await aufnahme('a');
      await aufnahme('b');
      await db.saveEmbedding('a', vektor(1.0));
      await db.saveEmbedding('b', vektor(2.0));

      final alle = await db.allEmbeddings();
      expect(alle.keys.toSet(), {'a', 'b'});
      expect(alle['a']!.toList(), [1.0, 0.5, -0.25, 1.0]);
      expect(alle['b']![0], 2.0);
    });

    test('Papierkorb und Tresor bleiben draussen', () async {
      // Der Verbund ist die Bedingung, nicht die Auskunft – er muss also
      // bleiben, auch wenn keine Spalte der Aufnahme mehr gelesen wird.
      await aufnahme('sichtbar');
      await aufnahme('weg', papierkorb: true);
      await aufnahme('tresor', gesperrt: true);
      for (final id in ['sichtbar', 'weg', 'tresor']) {
        await db.saveEmbedding(id, vektor(1.0));
      }
      expect((await db.allEmbeddings()).keys, ['sichtbar']);
    });

    test('ohne Einbettungen kommt nichts', () async {
      await aufnahme('a');
      expect(await db.allEmbeddings(), isEmpty);
    });
  });

  group('Die Schlagwoerter', () {
    test('jede Aufnahme mit allen ihren Namen', () async {
      await aufnahme('a');
      await aufnahme('b');
      await db.tagAsset('a', 'Urlaub');
      await db.tagAsset('a', 'Meer');
      await db.tagAsset('b', 'Meer');

      final alle = await db.allTagNamesByAssetId();
      expect(alle['a']!.toSet(), {'Urlaub', 'Meer'});
      expect(alle['b'], ['Meer']);
    });

    test('die KI-Auskunft nennt nur die Vorschlaege', () async {
      // Der Unterschied, an dem eine Rücksicherung die Herkunft verliert.
      await aufnahme('a');
      await db.tagAsset('a', 'VonHand');
      await db.tagAsset('a', 'VonDerKI', quelle: Tagquelle.ki);

      expect((await db.allTagNamesByAssetId())['a']!.toSet(),
          {'VonHand', 'VonDerKI'});
      expect(await db.kiTagNamesByAssetId(), {
        'a': {'VonDerKI'}
      });
    });
  });

  group('Die Gesichtsregionen', () {
    Future<void> gesicht(String id, String? person,
            {bool beiseite = false, double x = 0.1}) =>
        db.insertFace(FacesCompanion.insert(
          id: id,
          assetId: 'a',
          personId: Value(person),
          boxX: x,
          boxY: 0.2,
          boxW: 0.3,
          boxH: 0.4,
          isIgnored: Value(beiseite),
          embedding: Value(Uint8List(2048)),
        ));

    test('Name und Kasten kommen richtig heraus', () async {
      await aufnahme('a');
      await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
      await gesicht('g1', 'p1');

      final regionen = await db.alleGesichtsregionen();
      final r = regionen['a']!.single;
      expect(r.name, 'Anna');
      expect(r.links, closeTo(0.1, 1e-9));
      expect(r.oben, closeTo(0.2, 1e-9));
      expect(r.breite, closeTo(0.3, 1e-9));
      expect(r.hoehe, closeTo(0.4, 1e-9));
    });

    test('namenlose und beiseitegelegte bleiben draussen', () async {
      await aufnahme('a');
      await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
      await gesicht('g1', 'p1');
      await gesicht('g2', null, x: 0.5);
      await gesicht('g3', 'p1', beiseite: true, x: 0.7);

      expect((await db.alleGesichtsregionen())['a'], hasLength(1));
    });

    test('mehrere Gesichter auf einem Foto stehen alle da', () async {
      await aufnahme('a');
      await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
      await db.createPerson(PeopleCompanion.insert(id: 'p2', name: 'Bernd'));
      await gesicht('g1', 'p1');
      await gesicht('g2', 'p2', x: 0.6);

      final r = (await db.alleGesichtsregionen())['a']!;
      expect(r.map((e) => e.name).toSet(), {'Anna', 'Bernd'});
    });
  });
}
