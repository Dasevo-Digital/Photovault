// ignore_for_file: avoid_print
// Der echte Fall hinter dem Umbau der Zwischendatei: eine Datei, die
// groesser ist als das Zwischenlager.
//
// Unter Flatpak ist /tmp ein tmpfs von 789 MiB (nachgemessen am
// 25.08.2026). In einer echten Bibliothek liegen Videos bis 9,1 GB. Die
// Sicherung legte dort jede Datei zwischen - die erste zu grosse warf eine
// Ausnahme, und weil die Schleife kein catch hatte, brach der ganze Lauf
// ab.
//
// /run/user/1000 ist auf derselben Maschine ebenfalls ein tmpfs von
// 789 MiB (beides zehn Prozent des Arbeitsspeichers). Es dient hier als
// Zwischenlager - kein nachgestellter Fehler, sondern derselbe ENOSPC auf
// demselben Dateisystemtyp in derselben Groesse, nur ohne root.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('Datei groesser als das Zwischenlager kommt trotzdem an', () async {
    final lager = Directory('/run/user/1000/pv_zwischenlager_test');
    if (!Platform.isLinux || !Directory('/run/user/1000').existsSync()) {
      print('kein tmpfs unter /run/user/1000 - uebersprungen');
      return;
    }
    lager.createSync(recursive: true);

    final wurzel = Directory.systemTemp.createTempSync('pv_grossdatei_');
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final pfade = await StoragePaths.forTesting(
          Directory(p.join(wurzel.path, 'library')));
      final einfuhr = ImportService(db, pfade);

      // 900 MB - sicher ueber den 789 MiB des Zwischenlagers.
      const mb = 900;
      final quelle = File(p.join(wurzel.path, 'gross.mp4'));
      final block = List.filled(1024 * 1024, 42);
      final schreiber = quelle.openSync(mode: FileMode.write);
      for (var i = 0; i < mb; i++) {
        schreiber.writeFromSync(block);
      }
      schreiber.closeSync();
      print('Quelldatei: ${quelle.lengthSync() ~/ (1024 * 1024)} MB');
      await einfuhr.importFile(quelle.path);

      final ziel = Directory(p.join(wurzel.path, 'ziel'))
        ..createSync(recursive: true);
      final dienst = BackupService(db, pfade, zwischenlager: lager);
      final meldungen = await dienst.performBackup(ziel.path).toList();

      print('Zwischenlagergrenze geeicht auf: ${dienst.zwischenlagerGrenze}');
      expect(dienst.zwischenlagerGrenze, isNotNull,
          reason: 'das Zwischenlager haette ueberlaufen muessen');
      expect(meldungen.where((m) => m.fehlgeschlagen != null), isEmpty,
          reason: 'der Ausweichweg ist kein Fehlschlag');

      // Nur die Originale: Daneben liegen metadata.json und die
      // XMP-Beilagen, die mit dieser Frage nichts zu tun haben.
      final gesichert =
          Directory(p.join(ziel.path, 'PhotoVault-Backup', 'originals'))
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => !f.path.endsWith('.xmp'))
              .toList();
      expect(gesichert, hasLength(1));
      expect(gesichert.single.lengthSync(), quelle.lengthSync(),
          reason: 'die Sicherung muss vollstaendig sein, nicht abgeschnitten');
      print('gesichert: ${gesichert.single.lengthSync() ~/ (1024 * 1024)} MB');

      // Und im Zwischenlager darf nichts liegenbleiben.
      expect(lager.listSync(), isEmpty);
    } finally {
      await db.close();
      wurzel.deleteSync(recursive: true);
      if (lager.existsSync()) lager.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
