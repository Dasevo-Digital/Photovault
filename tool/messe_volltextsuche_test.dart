// **Was der Volltextindex aus Schema 82 kostet und bringt.**
//
// Er kostet eine Migration, eine virtuelle Tabelle und drei Ausloeser.
// Diese Messung sagt, was dafuer herauskommt.
//
// **Zwei Messfehler auf dem Weg hierher, beide derselben Art:** Erst habe
// ich `searchAssets` (volle Zeilen, 56 Spalten) gegen ein handgeschriebenes
// `SELECT id` gestellt und den Unterschied dem Index zugeschrieben - er lag
// am Zusammenbauen der Zeilen. Dann dasselbe noch einmal mit `SELECT id`,
// aber ohne die uebrigen Bedingungen, die der echte Weg mitfuehrt. Wer
// einen Weg misst, muss ihn ganz messen; ein nachgebauter Vergleichsweg
// misst den Nachbau.
//
// **Die belastbare Zahl** kommt daher aus zwei Laeufen DESSELBEN Aufrufs
// (`searchAssetIds`), einmal mit und einmal ohne Index. Das "ohne" braucht
// eine Zeile im Quelltext - `_ftsAssetIds` zu Beginn `return null;` -, dann
// greift der LIKE-Zweig in `_suchbedingungen`. An der gewachsenen
// Bibliothek (8098 Aufnahmen, 8096 mit Bildbeschreibung):
//
//   Wort       Treffer   mit Index   ohne Index
//   bathtub          7      2,5 ms       3,0 ms   <- Index gewinnt
//   woman          900      6,3 ms       4,6 ms
//   people        1771      7,1 ms       4,6 ms
//   with          2270      8,3 ms       5,2 ms   <- Index verliert 1,6x
//
// Ein Index gewinnt bei wenigen Treffern und verliert bei vielen - das ist
// sein Wesen, kein Fehler. Bei 8098 Aufnahmen bleibt beides einstellig;
// die Frage entscheidet sich erst bei einer viel groesseren Bibliothek,
// wo der LIKE-Weg die ganze Tabelle liest. Der Preis dafuer steht unten
// bei den Ausloesern und ist die eigentliche Zahl dieser Messung.
//
//   PV_DB=/pfad/library.sqlite flutter test tool/messe_volltextsuche_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/search_filters.dart';

Future<double> misst(Future<int> Function() was, {int laeufe = 15}) async {
  for (var i = 0; i < 3; i++) {
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
  test('Volltextindex: Nutzen und Preis', () async {
    final quelle = Platform.environment['PV_DB'];
    if (quelle == null) {
      markTestSkipped('PV_DB nicht gesetzt');
      return;
    }
    final ordner = await Directory.systemTemp.createTemp('pv_fts');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final ziel = File('${ordner.path}/mess.sqlite');
    await File(quelle).copy(ziel.path);
    final db = AppDatabase(NativeDatabase(ziel));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get(); // oeffnen + wandern lassen

    print('\nDer Suchweg, wie ihn der Bildschirm geht');
    print('-' * 58);
    print('Wort            Treffer   nur Kennungen   volle Zeilen');
    for (final wort in ['bathtub', 'woman', 'people', 'with']) {
      final filter =
          SearchFilters(query: wort, textMode: SearchTextMode.caption);
      final treffer = (await db.searchAssetIds(filter)).length;
      final kennungen =
          await misst(() async => (await db.searchAssetIds(filter)).length);
      final zeilen =
          await misst(() async => (await db.searchAssets(filter)).length);
      print('${wort.padRight(14)}${treffer.toString().padLeft(8)}'
          '${kennungen.toStringAsFixed(1).padLeft(13)} ms'
          '${zeilen.toStringAsFixed(1).padLeft(12)} ms');
    }
    print('\n  Der Sprung von links nach rechts ist NICHT der Index, sondern');
    print('  das Zusammenbauen der Zeilen - 56 Spalten je Treffer.');

    // Der Index fuer sich allein, ohne alles Drumherum.
    final nurFts = await misst(() async => (await db.customSelect(
          'SELECT asset_id FROM asset_search_fts WHERE asset_search_fts '
          "MATCH 'ai_caption : (\"with\"*) OR ai_caption_de : (\"with\"*)'",
        ).get())
            .length);
    print('\n  Die reine FTS-Abfrage fuer "with": '
        '${nurFts.toStringAsFixed(1)} ms');

    // **Der Preis.** Die drei Ausloeser haengen an jedem UPDATE der fuenf
    // indizierten Spalten - und genau die schreiben Texterkennung und
    // Bildbeschreibung fuer die ganze Bibliothek.
    print('\nWas die Ausloeser beim Schreiben kosten');
    print('-' * 58);
    final inKlammer = await misst(() async {
      await db.transaction(() async {
        for (var i = 0; i < 100; i++) {
          await db.customStatement(
              "UPDATE assets SET ai_caption = ai_caption || '' WHERE id = "
              '(SELECT id FROM assets LIMIT 1 OFFSET $i)');
        }
      });
      return 0;
    }, laeufe: 5);
    // Zwei Faelle, und der Unterschied ist der Sinn der Bedingung am
    // Ausloeser (Schema 84): Text, der sich WIRKLICH aendert, muss den
    // Index kosten. Text, der nur noch einmal hingeschrieben wird - und so
    // schreiben die Durchgaenge -, darf ihn nichts kosten.
    var zaehler = 0;
    final echteAenderung = await misst(() async {
      await db.customStatement(
          "UPDATE assets SET description = 'x${zaehler++}' WHERE id = "
          '(SELECT id FROM assets LIMIT 1)');
      return 0;
    }, laeufe: 50);
    final einzelnMit = await misst(() async {
      await db.customStatement(
          "UPDATE assets SET description = 'gleichbleibend' WHERE id = "
          '(SELECT id FROM assets LIMIT 1)');
      return 0;
    }, laeufe: 50);
    print('  eine Zeile, Text WIRKLICH geaendert  '
        '${echteAenderung.toStringAsFixed(3)} ms');
    await db.customStatement('DROP TRIGGER IF EXISTS assets_fts_update');
    final einzelnOhne = await misst(() async {
      await db.customStatement(
          "UPDATE assets SET description = 'y' WHERE id = "
          '(SELECT id FROM assets LIMIT 1)');
      return 0;
    }, laeufe: 50);
    print('  100 Zeilen in einer Transaktion  '
        '${(inKlammer / 100).toStringAsFixed(3)} ms je Zeile');
    print('  eine Zeile, Text unveraendert        '
        '${einzelnMit.toStringAsFixed(3)} ms');
    print('  eine Zeile, ohne Ausloeser           '
        '${einzelnOhne.toStringAsFixed(3)} ms');
    print('\n  Vor Schema 84 kostete AUCH die unveraenderte Zeile 1,56 ms:');
    print('  `UPDATE OF` feuert, sobald die Spalte in der SET-Klausel steht,');
    print('  nicht erst wenn ihr Wert ein anderer wird. Ueber 8098 Aufnahmen');
    print('  waren das rund neun Sekunden je Durchgang fuer nichts. Die');
    print('  Bedingung am Ausloeser macht daraus 0,3 Sekunden.');

    final quick = await misst(() async {
      await db.databaseQuickCheck();
      return 0;
    }, laeufe: 5);
    print('\nPRAGMA quick_check (Gesundheitsbildschirm): '
        '${quick.toStringAsFixed(0)} ms');
  });
}
