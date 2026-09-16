// **Sammelmessstand der fuenften Optimierungsrunde.**
//
// Was seit der letzten Runde dazugekommen ist, und was seither offen
// stand. Gemessen an einer Kopie der echten Bibliothek.
//
//   PV_DB=/pfad/lese.sqlite flutter test tool/messe_runde5_test.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/clip_service.dart';
import 'package:photo_vault/services/search_filters.dart';
import 'package:photo_vault/services/serienvergleich.dart';
import 'package:photo_vault/services/sortierung.dart';

Future<double> misst(String name, Future<int> Function() was,
    {int laeufe = 8}) async {
  var n = 0;
  for (var i = 0; i < 3; i++) {
    n = await was();
  }
  final uhr = Stopwatch()..start();
  for (var i = 0; i < laeufe; i++) {
    await was();
  }
  uhr.stop();
  final je = uhr.elapsedMicroseconds / laeufe / 1000;
  print('${name.padRight(46)} ${je.toStringAsFixed(2).padLeft(7)} ms   ($n)');
  return je;
}

void main() {
  test('Runde 5', () async {
    final pfad = Platform.environment['PV_DB'];
    if (pfad == null) {
      markTestSkipped('PV_DB nicht gesetzt');
      return;
    }
    // Ueber die Isolat-Grenze, so wie die App sie oeffnet.
    final db = AppDatabase(NativeDatabase.createInBackground(File(pfad)));
    addTearDown(db.close);

    print('\n--- Zeitleiste: die sechs Reihenfolgen, Fenster 600 ---');
    for (final s in Rastersortierung.values) {
      await misst('schmal  ${s.name}',
          () async => (await db.watchRasterzeilen(limit: 600, sortierung: s).first).length);
    }
    print('--- dieselben ohne Fenster (nach dem Scrollen) ---');
    for (final s in Rastersortierung.values) {
      await misst('schmal  ${s.name}, ganze Bibliothek',
          () async => (await db.watchRasterzeilen(sortierung: s).first).length,
          laeufe: 4);
    }

    print('\n--- schmal gegen voll ---');
    await misst('watchRasterzeilen(600)',
        () async => (await db.watchRasterzeilen(limit: 600).first).length);
    await misst('watchTimeline(600)  volle Zeilen',
        () async => (await db.watchTimeline(limit: 600).first).length);
    await misst('watchRasterzeilen() ganze Bibliothek',
        () async => (await db.watchRasterzeilen().first).length, laeufe: 4);
    await misst('watchTimeline()     ganze Bibliothek',
        () async => (await db.watchTimeline().first).length, laeufe: 4);
    await misst('alleAufnahmen()     (Fotowaehler, alt)',
        () async => (await db.alleAufnahmen()).length, laeufe: 4);
    await misst('alleRasterzeilen()  (Fotowaehler, neu)',
        () async => (await db.alleRasterzeilen()).length, laeufe: 4);
    await misst('aufnahmenImZeitraum(5 Jahre).length (alt)',
        () async => (await db.aufnahmenImZeitraum(
            DateTime(2020), DateTime(2025, 12, 31))).length, laeufe: 4);
    await misst('zahlImZeitraum(5 Jahre) (neu)',
        () async => await db.zahlImZeitraum(
            DateTime(2020), DateTime(2025, 12, 31)), laeufe: 4);
    await misst('assetsWithLocation() (Karte)',
        () async => (await db.assetsWithLocation()).length, laeufe: 4);

    print('\n--- Suche ---');
    await misst('Volltext ueber 4 Felder (LIKE %..%)',
        () async => (await db.searchAssets(
            const SearchFilters(query: 'berg', textMode: SearchTextMode.context))).length);
    await misst('nur geschaetztes Datum',
        () async => (await db.searchAssets(
            const SearchFilters(nurGeschaetztesDatum: true))).length);

    print('\n--- Stroeme, die im build() stehen ---');
    await misst('watchSavedSearches',
        () async => (await db.watchSavedSearches().first).length);
    await misst('watchPapierkorbUmfang',
        () async => (await db.watchPapierkorbUmfang().first).anzahl);
    await misst('watchAlbums',
        () async => (await db.watchAlbums().first).length);
    await misst('watchAppSettings',
        () async => (await db.watchAppSettings().first)?.id ?? 0);

    print('\n--- Eine KI-Suche, ohne das Modell ---');
    final einbettungen = await db.allEmbeddings();
    final videoEinb = await db.alleVideoeinbettungen();
    print('  ${einbettungen.length} Einbettungen, ${videoEinb.length} Videos');
    final zufall = math.Random(7);
    final anfrage = Float32List.fromList(
        [for (var i = 0; i < einbettungen.values.first.length; i++) zufall.nextDouble() - 0.5]);

    await misst('suchkandidaten (Karte zusammensetzen)', () async {
      final k = <String, Float32List>{
        ...einbettungen,
        for (final e in videoEinb.entries)
          for (var i = 0; i < e.value.length; i++) '${e.key}#$i': e.value[i],
      };
      return k.length;
    });
    final kandidaten = <String, Float32List>{
      ...einbettungen,
      for (final e in videoEinb.entries)
        for (var i = 0; i < e.value.length; i++) '${e.key}#$i': e.value[i],
    };
    await misst('searchAssets: volle Zeilen, nur fuer byId',
        () async => (await db.searchAssets(
            const SearchFilters(query: 'berg', textMode: SearchTextMode.context))).length,
        laeufe: 4);
    await misst('searchAssetIds: nur die Kennungen (neu)',
        () async => (await db.searchAssetIds(
            const SearchFilters(query: 'berg', textMode: SearchTextMode.context))).length,
        laeufe: 4);
    await misst('assetsByIds fuer 200 Treffer', () async {
      final ids = (await db.customSelect(
              'SELECT id FROM assets LIMIT 200').get())
          .map((z) => z.read<String>('id')).toList();
      return (await db.assetsByIds(ids)).length;
    });
    await misst('rankBySimilarity ueber alle Kandidaten',
        () async => ClipService.rankBySimilarity(anfrage, kandidaten, topK: 1200).length,
        laeufe: 4);

    print('\n--- Serienvergleich (N+1) ---');
    final serie = (await db.customSelect(
            'SELECT id FROM assets WHERE stack_id = '
            '(SELECT stack_id FROM assets WHERE stack_size = '
            '(SELECT max(stack_size) FROM assets) LIMIT 1)')
        .get()).map((z) => z.read<String>('id')).toList();
    print('  groesste Serie: ${serie.length} Aufnahmen');
    final assets = [for (final id in serie) (await db.assetById(id))!];
    await misst('serienspalten (je Aufnahme eine Abfrage)',
        () async => (await serienspalten(db, assets)).length, laeufe: 4);
    await misst('dieselben Gesichter in EINER Abfrage', () async {
      final ids = assets.map((a) => "'${a.id}'").join(',');
      return (await db
              .customSelect('SELECT * FROM faces WHERE asset_id IN ($ids)')
              .get())
          .length;
    }, laeufe: 4);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
