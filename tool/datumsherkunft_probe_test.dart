import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Laesst den Nachtrag „Herkunft der Aufnahmedaten" ueber eine **Kopie**
/// einer echten Bibliothek laufen und berichtet, was er findet.
///
/// **Nie auf das Original ansetzen.** Der Lauf oeffnet die Datenbank mit
/// dem Quelltext von jetzt und wandert sie damit auf das aktuelle Schema
/// – eine aeltere installierte App kann sie danach nicht mehr oeffnen.
///
///     PV_DB=/pfad/zur/kopie.sqlite \
///     PV_LIB=/pfad/zur/library \
///     flutter test tool/datumsherkunft_probe_test.dart --tags tool
///
/// `PV_TROCKEN=1` zaehlt nur, ohne zu schreiben.
void main() {
  test('Datumsherkunft an einer echten Bibliothek', () async {
    final dbPfad = Platform.environment['PV_DB'];
    final libPfad = Platform.environment['PV_LIB'];
    if (dbPfad == null || libPfad == null) {
      markTestSkipped('PV_DB und PV_LIB noetig');
      return;
    }
    final trocken = Platform.environment['PV_TROCKEN'] == '1';

    final db = AppDatabase(NativeDatabase(File(dbPfad)));
    // ignore: invalid_use_of_visible_for_testing_member
    final paths = await StoragePaths.forTesting(Directory(libPfad));
    final library = LibraryState()
      ..db = db
      ..paths = paths
      ..importService = ImportService(db, paths);

    final gesamt = await db.customSelect('SELECT count(*) c FROM assets')
        .getSingle()
        .then((z) => z.read<int>('c'));
    final offen = await db.countDatumsherkunft();
    // Die Vermutung aus der 7. Vergleichsauflage: ein Zeitstempel auf die
    // volle Stunde ist verdaechtig. Sie steht hier nur zum Vergleich – der
    // Lauf unten sieht in den Dateien nach, statt zu raten.
    final volleStunde = await db
        .customSelect('SELECT count(*) c FROM assets '
            'WHERE (file_created_at % 3600) = 0')
        .getSingle()
        .then((z) => z.read<int>('c'));

    // ignore: avoid_print
    print('Bestand $gesamt · offen $offen · auf voller Stunde $volleStunde');

    if (trocken) {
      await db.close();
      return;
    }

    final uhr = Stopwatch()..start();
    var zuletzt = 0;
    await for (final f in library.backfillDatumsherkunft()) {
      if (f.done - zuletzt >= 1000) {
        zuletzt = f.done;
        // ignore: avoid_print
        print('  ${f.done}/${f.total} nach ${uhr.elapsed.inSeconds} s');
      }
    }
    uhr.stop();

    final geschaetzt = await db
        .customSelect(
            'SELECT count(*) c FROM assets WHERE datum_geschaetzt = 1')
        .getSingle()
        .then((z) => z.read<int>('c'));
    final beides = await db
        .customSelect('SELECT count(*) c FROM assets '
            'WHERE datum_geschaetzt = 1 AND (file_created_at % 3600) = 0')
        .getSingle()
        .then((z) => z.read<int>('c'));

    // ignore: avoid_print
    print('geschaetzt $geschaetzt von $gesamt in ${uhr.elapsed.inSeconds} s '
        '· davon auf voller Stunde $beides');

    for (final zeile in await db
        .customSelect('SELECT coalesce(camera_model, \'(keine)\') m, '
            'count(*) c FROM assets WHERE datum_geschaetzt = 1 '
            'GROUP BY m ORDER BY c DESC LIMIT 10')
        .get()) {
      // ignore: avoid_print
      print('  ${zeile.read<int>('c')}\t${zeile.read<String>('m')}');
    }

    await db.close();
  }, timeout: const Timeout(Duration(minutes: 40)));
}
