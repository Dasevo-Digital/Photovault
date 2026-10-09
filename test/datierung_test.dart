import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/datierung.dart';
import 'package:photo_vault/services/embedding_codec.dart';

/// Das Jahrzehnt aus dem Bildvektor – mit künstlichen Vektoren, bei denen
/// feststeht, was herauskommen muss.
void main() {
  // Je Jahrzehnt eine eigene Achse; „nahe" heisst: viel von dieser Achse.
  final n = datierungJahrzehnte.length;
  final saetze = {
    for (final (i, j) in datierungJahrzehnte.indexed)
      j: Float32List(n)..[i] = 1,
  };
  Float32List bild(Map<int, double> anteile) {
    final v = Float32List(n);
    for (final MapEntry(key: j, value: a) in anteile.entries) {
      v[datierungJahrzehnte.indexOf(j)] = a;
    }
    var l = 0.0;
    for (final x in v) {
      l += x * x;
    }
    return Float32List.fromList([for (final x in v) x / math.sqrt(l)]);
  }

  test('klar ein Jahrzehnt: enge Spanne, belastbar', () {
    final d = schaetzeDatierung(bild({1950: 1, 1940: 0.9, 1960: 0.9}), saetze);
    expect(d.von, 1950);
    expect(d.bis, 1959);
    expect(d.jahr, inInclusiveRange(1950, 1959));
    expect(d.belastbar, isTrue);
    expect(d.siehtAltAus, isTrue);
    expect(d.verteilung.values.fold(0.0, (a, b) => a + b), closeTo(1, 1e-9));
  });

  test('zwischen zwei Jahrzehnten: die Spanne nimmt beide', () {
    final d = schaetzeDatierung(bild({1960: 1, 1970: 1}), saetze);
    expect(d.von, 1960);
    expect(d.bis, 1979);
    expect(d.jahr, closeTo(1970, 1));
  });

  test('alles gleich nah: zu breit, nicht belastbar', () {
    final d = schaetzeDatierung(
      bild({for (final j in datierungJahrzehnte) j: 1}),
      saetze,
    );
    expect(d.belastbar, isFalse);
    expect(d.bis - d.von, greaterThan(datierungHoechsteSpanne));
  });

  test('ein modernes Foto sieht nicht alt aus', () {
    expect(schaetzeDatierung(bild({2010: 1}), saetze).siehtAltAus, isFalse);
  });

  test('der Mittelwert mehrerer Sätze ist wieder normiert', () {
    final m = mittlererVektor([
      Float32List.fromList([1, 0]),
      Float32List.fromList([0, 1]),
    ]);
    expect(m[0], closeTo(math.sqrt(0.5), 1e-6));
    expect(m[1], closeTo(math.sqrt(0.5), 1e-6));
  });

  test('jedes Jahrzehnt hat mehrere Sätze, keiner sagt „old"', () {
    for (final j in datierungJahrzehnte) {
      final s = datierungsSaetze(j);
      expect(s.length, greaterThan(1));
      expect(s.any((x) => x.contains('old')), isFalse);
    }
  });

  group('Datenbank', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> anlegen(
      String id, {
      bool geraten = false,
      String? modell,
      String? hersteller,
      bool vektor = true,
    }) async {
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2024, 3, 3),
              importedAt: DateTime(2026),
              datumGeschaetzt: Value(geraten),
              cameraModel: Value(modell),
              cameraMake: Value(hersteller),
            ),
          );
      if (vektor) {
        await db
            .into(db.imageEmbeddings)
            .insert(
              ImageEmbeddingsCompanion.insert(
                assetId: id,
                vector: blobFromEmbeddingFloats(Float32List(4)..[0] = 1),
              ),
            );
      }
    }

    test('geratene Daten und Scans, sonst nichts', () async {
      await anlegen('geraten', geraten: true);
      await anlegen('canoscan', modell: 'CanoScan 9000F Mark II');
      await anlegen('epson', hersteller: 'EPSON', modell: 'Perfection V600');
      await anlegen('kamera', hersteller: 'Canon', modell: 'EOS 5D');
      await anlegen('ohneVektor', geraten: true, vektor: false);
      final ids = {for (final k in await db.datierungskandidaten()) k.asset.id};
      expect(ids, {'geraten', 'canoscan', 'epson'});
    });

    test('übernommen wird die Jahresmitte, weiter als geschätzt', () async {
      await anlegen('scan', modell: 'CanoScan');
      await db.setzeGeschaetztesJahr('scan', 1965);
      final a = (await db.assetById('scan'))!;
      expect(a.fileCreatedAt, DateTime(1965, 7, 1, 12));
      expect(a.datumGeschaetzt, isTrue);
    });
  });
}
