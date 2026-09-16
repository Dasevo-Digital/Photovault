import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/services/vault_crypto.dart';

/// Befunde der 9. Prüfrunde.
void main() {
  group('Klartext gehört nicht ins Sicherungsziel', () {
    late Directory tempRoot;
    late AppDatabase db;
    late BackupService backup;
    late StoragePaths paths;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('pv_p9_backup_');
      db = AppDatabase(NativeDatabase.memory());
      paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
      backup = BackupService(db, paths);
    });

    tearDown(() async {
      await db.close();
      tempRoot.deleteSync(recursive: true);
    });

    test('die verschlüsselte Sicherung legt keine lesbare Zwischendatei ab', () async {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'a',
            // Ein Dateiname, der in der Sicherung nichts zu suchen hat.
            originalFileName: 'Gehaltsabrechnung_Mai.jpg',
            relativePath: 'originals/a.jpg',
            checksum: 'a',
            fileCreatedAt: DateTime(2024, 5, 1),
            importedAt: DateTime(2024, 5, 2),
            type: 'IMAGE',
          ));

      final ziel = Directory(p.join(tempRoot.path, 'sicherung'))..createSync();
      final schluessel = (await VaultCrypto.createMasterKey('ein-langes-passwort')).masterKey;
      await backup.performBackup(ziel.path, encryptionKey: schluessel).drain<void>();

      // Nichts Lesbares im Zielordner – weder als vergessene Zwischendatei
      // noch als Inhalt einer der abgelegten Dateien.
      final abgelegt = ziel
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      expect(abgelegt, isNotEmpty);
      for (final datei in abgelegt) {
        expect(p.extension(datei.path), isNot('.plaintmp'),
            reason: 'die Klartext-Zwischendatei gehört in den privaten '
                'Temp-Ordner, nicht neben die verschlüsselte Fassung');
        expect(utf8.decode(datei.readAsBytesSync(), allowMalformed: true),
            isNot(contains('Gehaltsabrechnung')),
            reason: p.basename(datei.path));
      }
    });
  });

  group('Bibliotheks-Konfiguration', () {
    test('wird über eine Zwischendatei geschrieben, nicht an Ort und Stelle', () {
      // Das Verhalten selbst ist ohne echten Anker-Ordner nicht anzufassen;
      // geprüft wird deshalb der Quelltext an genau der Stelle. Ein
      // `writeAsString` direkt auf die Konfigurationsdatei würde sie beim
      // Schreiben zuerst leeren – ein Abbruch in dem Moment hinterlässt
      // einen Rumpf, den das Lesen (bewusst) als „keine Bibliothek"
      // auffasst. Die Übersicht wäre danach leer und das
      // Security-Scoped-Bookmark verloren.
      final quelle = File('lib/services/library_location.dart').readAsStringSync();
      final schreiben = quelle.substring(quelle.indexOf('static Future<void> _schreibeKonfig'));
      final rumpf = schreiben.substring(0, schreiben.indexOf('\n  }'));

      expect(rumpf, contains('.rename(configFile.path)'));
      expect(rumpf, isNot(contains('configFile.writeAsString')));
    });
  });

  group('gesperrte Fotos', () {
    late Directory tempRoot;
    late AppDatabase db;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('pv_p9_gesperrt_');
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
      tempRoot.deleteSync(recursive: true);
    });

    test('kommen bei der Vorschau-Erzeugung gar nicht erst vor', () async {
      for (final (id, gesperrt) in [('offen', false), ('gesperrt', true)]) {
        await db.into(db.assets).insert(AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.heic',
              relativePath: 'originals/$id.heic',
              checksum: id,
              fileCreatedAt: DateTime(2024, 5, 1),
              importedAt: DateTime(2024, 5, 2),
              type: 'IMAGE',
              isLocked: Value(gesperrt),
            ));
      }

      // Bei einem gesperrten Foto ist die Originaldatei verschlüsselt; das
      // Dekodieren scheitert zwangsläufig und es kommt nie ein Vorschaubild
      // dabei heraus. Es blieb nur das vollständige Lesen der Datei und ein
      // Isolate-Durchlauf ins Leere – je gesperrtem Foto, bei jedem
      // „Alle neu".
      for (final nurFehlende in [true, false]) {
        final liste = await db.assetsForThumbnailRegen(onlyMissing: nurFehlende);
        expect(liste.map((a) => a.id), ['offen'], reason: 'onlyMissing=$nurFehlende');
        expect(await db.countThumbnailRegen(onlyMissing: nurFehlende), liste.length);
      }
    });
  });
}
