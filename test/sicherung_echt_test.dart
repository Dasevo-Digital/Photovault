import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:sqlite3/sqlite3.dart';

/// Die Übernahme aus dem Datenbank-Schnappschuss an einer **Kopie einer
/// echten Bibliothek**.
///
/// Läuft nur, wenn `PV_MIGRATION_DIR` auf den Ordner mit den Kopien zeigt –
/// sonst hinge die Suite an Dateien, die es auf keiner anderen Maschine
/// gibt. Der Grund: An einer frisch angelegten Datenbank mit drei Zeilen
/// sagt eine Übernahme nichts darüber, ob sie 17.868 Gesichter und 39
/// Personen verträgt – und schon gar nichts darüber, wie lange sie dafür
/// braucht.
///
/// Die Kopie ist ausserdem **älter als der laufende Quelltext** (Fassung 59
/// gegen 61). Genau der Fall, für den die Spalten aus dem Schema kommen und
/// nicht aus einer Liste: Was es dort nicht gibt, wird ausgelassen, statt
/// den Lauf zu beenden.
void main() {
  final ordner = Platform.environment['PV_MIGRATION_DIR'];

  test('eine gewachsene Bibliothek kommt vollständig zurück', () async {
    if (ordner == null) {
      markTestSkipped('PV_MIGRATION_DIR nicht gesetzt');
      return;
    }
    final schnappschuss = File(p.join(ordner, 'gross.sqlite'));
    expect(schnappschuss.existsSync(), isTrue, reason: 'gross.sqlite fehlt');

    // Was drinsteht – gelesen wie ein Schnappschuss, also ohne Migration.
    final roh = sqlite3.open(schnappschuss.path, mode: OpenMode.readOnly);
    int zahlIn(String tabelle) =>
        roh.select('SELECT count(*) AS n FROM "$tabelle"').first['n'] as int;
    final erwartet = {
      for (final t in ['people', 'faces', 'person_beziehungen', 'reisen',
                       'reise_aufnahmen', 'aktivitaeten', 'aktivitaet_aufnahmen',
                       'ortsmarken', 'duplikat_ausnahmen'])
        t: zahlIn(t),
    };
    final aufnahmen = roh
        .select('SELECT id, checksum FROM assets')
        .map((z) => (z['id'] as String, z['checksum'] as String))
        .toList();
    roh.close();

    // Die Zielbibliothek so, wie sie nach dem Zurückspielen der Dateien
    // aussieht: dieselben Prüfsummen, neue Kennungen.
    final temp = Directory.systemTemp.createTempSync('pv_sich_echt_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final ziel = AppDatabase(NativeDatabase.memory());
    addTearDown(ziel.close);
    final pfade = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));

    await ziel.batch((b) => b.insertAll(ziel.assets, [
          for (var i = 0; i < aufnahmen.length; i++)
            AssetsCompanion.insert(
              id: 'neu-$i',
              relativePath: 'originals/neu-$i.jpg',
              originalFileName: 'neu-$i.jpg',
              type: 'IMAGE',
              checksum: aufnahmen[i].$2,
              fileCreatedAt: DateTime(2024),
              importedAt: DateTime(2024),
            ),
        ]));

    final uhr = Stopwatch()..start();
    final zeilen = await BackupService(ziel, pfade)
        .uebernimmAusSchnappschuss(schnappschuss);
    uhr.stop();

    Future<int> zahlAus(String tabelle) async => (await ziel
            .customSelect('SELECT count(*) AS n FROM "$tabelle"')
            .getSingle())
        .read<int>('n');

    for (final eintrag in erwartet.entries) {
      expect(await zahlAus(eintrag.key), eintrag.value,
          reason: '${eintrag.key} kam nicht vollständig zurück');
    }
    expect(zeilen, greaterThan(0));

    // Die Zuordnung muss über die Prüfsumme gelaufen sein: kein Gesicht
    // darf an einer Kennung hängen, die es hier nicht gibt.
    final verwaist = await ziel
        .customSelect('SELECT count(*) AS n FROM faces f '
            'LEFT JOIN assets a ON a.id = f.asset_id WHERE a.id IS NULL')
        .getSingle();
    expect(verwaist.read<int>('n'), 0);

    // ignore: avoid_print
    print('Übernahme: $zeilen Zeilen in ${uhr.elapsedMilliseconds} ms '
        '(${erwartet['faces']} Gesichter, ${erwartet['people']} Personen)');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
