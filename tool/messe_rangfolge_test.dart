// **Lohnt der Weg ins eigene Isolat?**
//
// Die Bewertung der CLIP-Einbettungen ist seit 3.10.0 zweifach umgebaut:
// ein begrenzter Haufen statt vollstaendiger Sortierung, und der ganze
// Lauf in einem eigenen Isolat. Das Erste ist reine Rechnung und kann nur
// gewinnen. Das Zweite ist ein Tausch: Die Oberflaeche bleibt frei, aber
// die Vektoren muessen hinueber.
//
// Gemessen an den echten Einbettungen einer Kopie der Bibliothek.
//
//   PV_DB=/pfad/library.sqlite flutter test tool/messe_rangfolge_test.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:photo_vault/services/clip_service.dart';

/// Die Isolat-Fassung, wie sie eine Zeit lang in `lib/` stand.
///
/// Sie lebt jetzt HIER und nicht mehr im Programm: Das Programm rechnet an
/// Ort und Stelle (siehe [ClipService.rankBySimilarity]), und dieser
/// Messstand hält die verworfene Fassung fest, damit die Entscheidung
/// nachpruefbar bleibt - vor allem, wenn die Bibliothek einmal um ein
/// Vielfaches groesser ist.
typedef _RankingArgs = ({
  TransferableTypedData vectors,
  int queryLength,
  List<String> ids,
  List<int> lengths,
  int topK,
});

List<(String, double)> _berechneRanking(_RankingArgs args) {
  final floats = args.vectors.materialize().asFloat32List();
  final query = Float32List.sublistView(floats, 0, args.queryLength);
  var offset = args.queryLength;
  final candidates = <String, Float32List>{};
  for (var i = 0; i < args.ids.length; i++) {
    final end = offset + args.lengths[i];
    candidates[args.ids[i]] = Float32List.sublistView(floats, offset, end);
    offset = end;
  }
  return [
    for (final e in ClipService.rankBySimilarity(query, candidates,
        topK: args.topK))
      (e.key, e.value),
  ];
}

Future<List<(String, double)>> _imIsolat(
  Float32List query,
  Map<String, Float32List> candidates, {
  required int topK,
}) {
  final ids = candidates.keys.toList(growable: false);
  final lengths = [for (final id in ids) candidates[id]!.length];
  final packed = Float32List(
      query.length + lengths.fold<int>(0, (sum, length) => sum + length));
  packed.setRange(0, query.length, query);
  var offset = query.length;
  for (final id in ids) {
    final vector = candidates[id]!;
    packed.setRange(offset, offset + vector.length, vector);
    offset += vector.length;
  }
  return compute(
    _berechneRanking,
    (
      vectors: TransferableTypedData.fromList([packed.buffer.asUint8List()]),
      queryLength: query.length,
      ids: ids,
      lengths: lengths,
      topK: topK,
    ),
  );
}

Future<double> misst(Future<void> Function() was, {int laeufe = 10}) async {
  for (var i = 0; i < 2; i++) {
    await was();
  }
  final uhr = Stopwatch()..start();
  for (var i = 0; i < laeufe; i++) {
    await was();
  }
  uhr.stop();
  return uhr.elapsedMicroseconds / laeufe / 1000;
}

void main() {
  test('Rangfolge: im Isolat gegen an Ort und Stelle', () async {
    final quelle = Platform.environment['PV_DB'];
    if (quelle == null) {
      markTestSkipped('PV_DB nicht gesetzt');
      return;
    }
    final ordner = await Directory.systemTemp.createTemp('pv_rang');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final ziel = File('${ordner.path}/mess.sqlite');
    await File(quelle).copy(ziel.path);
    final db = AppDatabase(NativeDatabase(ziel));
    addTearDown(db.close);

    final zeilen = await db
        .customSelect('SELECT asset_id, vector FROM image_embeddings')
        .get();
    final alle = <String, Float32List>{
      for (final z in zeilen)
        z.read<String>('asset_id'):
            Float32List.sublistView(z.read<Uint8List>('vector'))
    };
    if (alle.isEmpty) {
      print('Keine Einbettungen in dieser Bibliothek.');
      return;
    }
    final abfrage = alle.values.first;
    print('\n${alle.length} Einbettungen, je ${abfrage.length} Zahlen '
        '(${(alle.length * abfrage.length * 4 / 1024 / 1024).toStringAsFixed(1)} MB)\n');

    print('Kandidaten   an Ort und Stelle      im Isolat   Unterschied');
    print('-' * 62);
    for (final n in [50, 500, 2000, alle.length]) {
      final teil = Map.fromEntries(alle.entries.take(n));
      final hier = await misst(() async {
        ClipService.rankBySimilarity(abfrage, teil, topK: 200);
      });
      final dort = await misst(() async {
        await _imIsolat(abfrage, teil, topK: 200);
      });
      print('${n.toString().padLeft(9)}'
          '${hier.toStringAsFixed(1).padLeft(17)} ms'
          '${dort.toStringAsFixed(1).padLeft(13)} ms'
          '${'${(dort - hier) >= 0 ? '+' : ''}${(dort - hier).toStringAsFixed(1)} ms'.padLeft(14)}');
    }
  });
}
