// **Was eine Suche kostet - und was die blosse ZAHL daneben kostet.**
//
// Die Filterleiste zeigt live, wie viele Treffer die eingestellte
// Kombination haette. Sie holt dafuer bisher alle Treffer vollstaendig.
//
//   PV_DB=/pfad/kopie.sqlite flutter test tool/messe_suche_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/search_filters.dart';

Future<double> misst(String name, Future<Object?> Function() was,
    {int laeufe = 5}) async {
  for (var i = 0; i < 2; i++) {
    await was();
  }
  final uhr = Stopwatch()..start();
  for (var i = 0; i < laeufe; i++) {
    await was();
  }
  uhr.stop();
  final je = uhr.elapsedMicroseconds / laeufe / 1000;
  print('${name.padRight(46)} ${je.toStringAsFixed(1).padLeft(8)} ms');
  return je;
}

void main() {
  final pfad = Platform.environment['PV_DB'];

  test('Suche und Trefferzahl', () async {
    if (pfad == null) {
      print('PV_DB nicht gesetzt.');
      return;
    }
    final db = AppDatabase(NativeDatabase(File(pfad)));

    for (final fall in <(String, SearchFilters)>[
      ('nur Favoriten', const SearchFilters(favoritesOnly: true)),
      ('nur Videos', const SearchFilters(mediaType: MediaTypeFilter.video)),
      ('Text "kind"', const SearchFilters(query: 'kind')),
      ('Text "a"', const SearchFilters(query: 'a')),
    ]) {
      final (name, filter) = fall;
      final treffer = await db.searchAssets(filter);
      print('\n$name: ${treffer.length} Treffer');
      await misst('  searchAssets (volle Zeilen)', () => db.searchAssets(filter));
      await misst('  searchAssetIds (nur Kennungen)',
          () => db.searchAssetIds(filter));
      await misst('  countSearchResults (neu)',
          () => db.countSearchResults(filter));
    }
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
