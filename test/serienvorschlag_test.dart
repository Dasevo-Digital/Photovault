import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/embedding_codec.dart';
import 'package:photo_vault/services/serienvorschlag.dart';

/// **Serien werden erkannt – nur übernommen wurden sie nie.**
///
/// An der echten Bibliothek gemessen: 286 brauchbare Gruppen mit 778
/// Aufnahmen in 240 ms, und **null Stapel** in der Datenbank. Die
/// Erkennung war also nie das Problem. Was fehlte, waren drei Dinge:
///
/// - eine Stelle, an der die Zahl steht (sonst weiss niemand, dass da
///   etwas wartet – derselbe Befund wie bei den Bewertungen),
/// - ein Weg, alle auf einmal zu übernehmen (286 Gruppen wären 286
///   Klicks),
/// - ein Gedächtnis für abgelehnte Vorschläge und bereits gestapelte
///   Aufnahmen. Ohne das kam beim nächsten Öffnen alles wieder.
void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pv_serien_');
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  /// Ein Vektor, der [nachbar] beliebig nahe kommt: gleiche Richtung plus
  /// eine winzige Abweichung.
  Float32List vektor(int saat, {double streuung = 0.0}) {
    final zufall = math.Random(saat);
    final v = Float32List(64);
    var summe = 0.0;
    for (var i = 0; i < v.length; i++) {
      v[i] = zufall.nextDouble() - 0.5;
      summe += v[i] * v[i];
    }
    final norm = math.sqrt(summe);
    for (var i = 0; i < v.length; i++) {
      v[i] = v[i] / norm;
    }
    if (streuung > 0) {
      final stoerung = math.Random(saat * 31 + 7);
      summe = 0;
      for (var i = 0; i < v.length; i++) {
        v[i] += (stoerung.nextDouble() - 0.5) * streuung;
        summe += v[i] * v[i];
      }
      final n2 = math.sqrt(summe);
      for (var i = 0; i < v.length; i++) {
        v[i] = v[i] / n2;
      }
    }
    return v;
  }

  Future<void> lege(String id, DateTime wann, Float32List v) async {
    await db.insertAsset(AssetsCompanion.insert(
      id: id,
      relativePath: 'originals/$id.jpg',
      originalFileName: '$id.jpg',
      type: 'IMAGE',
      checksum: id,
      fileCreatedAt: wann,
      importedAt: wann,
    ));
    await db.saveEmbedding(id, v);
  }

  /// Drei fast gleiche Aufnahmen im Abstand von einer Sekunde.
  Future<void> legeSerie(String praefix, int saat, DateTime start) async {
    for (var i = 0; i < 3; i++) {
      await lege('$praefix$i', start.add(Duration(seconds: i)),
          vektor(saat, streuung: 0.02 * i));
    }
  }

  Future<Map<String, Float32List>> alleEinbettungen() async {
    final zeilen =
        await db.customSelect('SELECT asset_id, vector FROM image_embeddings').get();
    return {
      for (final z in zeilen)
        z.read<String>('asset_id'):
            floatsFromEmbeddingBlob(z.read<Uint8List>('vector')),
    };
  }

  test('findet eine Serie und lässt fremde Aufnahmen liegen', () async {
    await legeSerie('a', 1, DateTime(2024, 5, 1, 12));
    // Ein ganz anderes Motiv, Stunden später.
    await lege('einzeln', DateTime(2024, 5, 1, 18), vektor(99));

    final gruppen = await serienvorschlaege(db, await alleEinbettungen());
    expect(gruppen.length, 1);
    expect([for (final a in gruppen.single) a.id]..sort(), ['a0', 'a1', 'a2']);
  });

  test('was schon gestapelt ist, wird nicht erneut vorgeschlagen', () async {
    // Der Fall, der den Bildschirm bis Fassung 62 unbrauchbar machte: Die
    // Mitglieder eines Stapels verschwinden aus dem Raster, aus der
    // Einbettungstabelle aber nicht.
    await legeSerie('a', 1, DateTime(2024, 5, 1, 12));
    expect((await serienvorschlaege(db, await alleEinbettungen())).length, 1);

    await db.createStack('s1', ['a0', 'a1', 'a2'], 'a1');
    expect(await serienvorschlaege(db, await alleEinbettungen()), isEmpty);
  });

  test('ein abgelehnter Vorschlag kommt nicht wieder', () async {
    await legeSerie('a', 1, DateTime(2024, 5, 1, 12));
    final gruppen = await serienvorschlaege(db, await alleEinbettungen());
    expect(gruppen.length, 1);

    await db.verwirfSerienvorschlag(serienschluessel(gruppen.single));
    expect(await serienvorschlaege(db, await alleEinbettungen()), isEmpty);
  });

  test('der Schlüssel hängt nicht an der Reihenfolge', () async {
    // Die Gruppenbildung sichert keine Reihenfolge zu. Hinge der Schlüssel
    // daran, käme ein abgelehnter Vorschlag beim nächsten Lauf unter neuem
    // Namen zurück.
    await legeSerie('a', 1, DateTime(2024, 5, 1, 12));
    final gruppe = (await serienvorschlaege(db, await alleEinbettungen())).single;
    final rueckwaerts = gruppe.reversed.toList();
    expect(serienschluessel(rueckwaerts), serienschluessel(gruppe));
  });

  test('zwei Serien bleiben zwei Serien', () async {
    await legeSerie('a', 1, DateTime(2024, 5, 1, 12));
    await legeSerie('b', 2, DateTime(2024, 6, 9, 15));
    final gruppen = await serienvorschlaege(db, await alleEinbettungen());
    expect(gruppen.length, 2);
    // Und eine abzulehnen lässt die andere in Ruhe.
    await db.verwirfSerienvorschlag(serienschluessel(gruppen.first));
    expect((await serienvorschlaege(db, await alleEinbettungen())).length, 1);
  });

  test('ohne Einbettungen kommt nichts heraus statt einer Ausnahme', () async {
    expect(await serienvorschlaege(db, const {}), isEmpty);
  });
}
