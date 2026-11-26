import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/einstellungen/backup_probe_status.dart';
import 'package:photo_vault/services/backup_koordinator.dart';

/// Die beiden Befunde des Sicherheitsaudits vom 26.11.2026: Die erste
/// Sicherung prüfte die Quelle nicht (#493), und eine im Ziel beschädigte
/// Datei gleicher Grösse blieb für immer liegen (#494).
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importe;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_audit_493_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory('${temp.path}/library'));
    importe = ImportService(
      db,
      paths,
      bildwerkzeuge: const KeineBildwerkzeuge(),
    );
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<AssetData> foto(String name, int rot) async {
    final bild = img.Image(width: 16, height: 16);
    img.fill(bild, color: img.ColorRgb8(rot, 90, 180));
    final f = File('${temp.path}/$name')..writeAsBytesSync(img.encodeJpg(bild));
    final r = await importe.importFile(f.path);
    expect(r.outcome, ImportOutcome.imported);
    return (await db.assetById(r.assetId!))!;
  }

  /// Ein Bit im Original der Bibliothek, das die Datenbank nicht kennt.
  Future<void> beschaedige(File datei) async {
    final bytes = await datei.readAsBytes();
    bytes[bytes.length ~/ 2] ^= 1;
    await datei.writeAsBytes(bytes);
  }

  Future<WrappedMasterKey> schluessel() async {
    final key = await VaultCrypto.createMasterKey('synthetischer-schluessel');
    await db.saveBackupKey(
      kdfSalt: key.kdfSalt,
      nonce: key.nonce,
      wrapped: key.wrapped,
    );
    return key;
  }

  List<File> dateienIn(String ordner) => Directory(ordner).existsSync()
      ? Directory(ordner).listSync(recursive: true).whereType<File>().toList()
      : const [];

  group('#493: die erste Sicherung prüft die Quelle', () {
    test(
      'automatisch: ein beschädigtes Original kommt nicht ins Ziel',
      () async {
        final kaputt = await foto('kaputt.jpg', 70);
        final heil = await foto('heil.jpg', 140);
        await beschaedige(paths.absolute(kaputt.relativePath));
        final key = await schluessel();

        final verlauf = await BackupService(
          db,
          paths,
        ).performAutoBackup('${temp.path}/ziel', key.masterKey).toList();

        expect(verlauf.map((v) => v.fehlgeschlagen).whereType<int>().last, 1);
        final root = '${temp.path}/ziel/${BackupService.autoBackupFolderName}';
        final daten = dateienIn('$root/data');
        expect(daten, hasLength(1), reason: 'nur das heile Foto');
        await VaultCrypto.pruefeDatei(
          daten.single,
          key.masterKey,
          erwartetePruefsumme: heil.checksum,
        );
        expect((await db.assetById(kaputt.id))!.autoBackedUp, isFalse);
        expect((await db.assetById(heil.id))!.autoBackedUp, isTrue);
      },
    );

    for (final verschluesselt in [true, false]) {
      test('von Hand ${verschluesselt ? 'verschlüsselt' : 'unverschlüsselt'}: '
          'ebenso', () async {
        final kaputt = await foto('kaputt.jpg', 70);
        final heil = await foto('heil.jpg', 140);
        await beschaedige(paths.absolute(kaputt.relativePath));
        final key = verschluesselt ? (await schluessel()).masterKey : null;

        final verlauf = await BackupService(
          db,
          paths,
        ).performBackup('${temp.path}/ziel', encryptionKey: key).toList();

        expect(verlauf.map((v) => v.fehlgeschlagen).whereType<int>().last, 1);
        final root = '${temp.path}/ziel/${BackupService.backupFolderName}';
        final fotos = dateienIn(
          verschluesselt ? '$root/data' : '$root/originals',
        ).where((f) => !f.path.endsWith('.xmp')).toList();
        expect(fotos, hasLength(1), reason: 'nur das heile Foto');
        if (!verschluesselt) {
          expect(
            await fotos.single.readAsBytes(),
            await paths.absolute(heil.relativePath).readAsBytes(),
          );
        }
        expect((await db.assetById(kaputt.id))!.backedUp, isFalse);
        expect((await db.assetById(heil.id))!.backedUp, isTrue);
      });
    }
  });

  group('#494: eine im Ziel beschädigte Datei wird neu geschrieben', () {
    test(
      'verschlüsselt: die Probe benennt sie, der nächste Lauf ersetzt sie',
      () async {
        final a = await foto('urlaub.jpg', 70);
        final key = await schluessel();
        final service = BackupService(db, paths);
        final ziel = '${temp.path}/ziel';
        final root = '$ziel/${BackupService.autoBackupFolderName}';
        await service.performAutoBackup(ziel, key.masterKey).drain<void>();
        final datei = dateienIn('$root/data').single;
        final bytes = await datei.readAsBytes();
        bytes[bytes.length - 1] ^= 1;
        await datei.writeAsBytes(bytes);
        // Die Grösse stimmt: Bis hierher lag die Datei in jedem Lauf weiter.
        expect(
          await VaultCrypto.passtZurGroesse(datei, a.fileSizeBytes),
          isTrue,
        );

        final probe = await service.pruefeWiederherstellung(
          root,
          schluessel: key.masterKey,
        );
        expect(probe.erfolgreich, isFalse);
        expect(probe.fehler, 'pv_probe_original_beschaedigt');
        expect(probe.beschaedigt.single.pruefsumme, a.checksum);
        expect(probe.beschaedigt.single.name, 'urlaub.jpg');
        expect(
          (await service.letzteProbe(root))!.beschaedigt.single.name,
          'urlaub.jpg',
        );

        final verlauf = await service
            .performAutoBackup(ziel, key.masterKey)
            .toList();
        await VaultCrypto.pruefeDatei(
          dateienIn('$root/data').single,
          key.masterKey,
          erwartetePruefsumme: a.checksum,
        );
        // Die Probe danach ist wieder gelungen, und nichts gilt mehr als
        // beschädigt.
        expect(
          verlauf.map((v) => v.wiederherstellungsprobe).whereType<Object>(),
          isNotEmpty,
        );
        final danach = (await service.letzteProbe(root))!;
        expect(danach.erfolgreich, isTrue);
        expect(danach.beschaedigt, isEmpty);
      },
    );

    test(
      'unverschlüsselt: ebenso, und die Liste leert sich auch ohne Probe',
      () async {
        final a = await foto('urlaub.jpg', 70);
        final service = BackupService(db, paths);
        final ziel = '${temp.path}/ziel';
        final root = '$ziel/${BackupService.backupFolderName}';
        await service.performBackup(ziel).drain<void>();
        final kopie = dateienIn(
          '$root/originals',
        ).singleWhere((f) => !f.path.endsWith('.xmp'));
        await beschaedige(kopie);

        final probe = await service.pruefeWiederherstellung(root);
        expect(probe.beschaedigt.single.pruefsumme, a.checksum);

        // Ein zweites Foto, dessen Original fehlt: Der Lauf scheitert daran,
        // und danach läuft keine neue Probe, die die Liste ersetzen würde.
        // Er selbst nimmt das Neugeschriebene heraus.
        final weg = await foto('weg.jpg', 200);
        await paths.absolute(weg.relativePath).delete();
        await service.performBackup(ziel).drain<void>();
        expect(
          await kopie.readAsBytes(),
          await paths.absolute(a.relativePath).readAsBytes(),
        );
        final danach = (await service.letzteProbe(root))!;
        expect(danach.fehler, 'pv_probe_original_beschaedigt');
        expect(danach.beschaedigt, isEmpty);
      },
    );

    test('die Meldung nennt die Aufnahmen', () async {
      final probe = BackupProbeErgebnis(
        am: DateTime.utc(2026, 11, 26, 8),
        erfolgreich: false,
        originale: 0,
        gesamt: 9,
        datenbank: true,
        fehler: 'pv_probe_original_beschaedigt',
        beschaedigt: [
          for (var i = 1; i <= 7; i++)
            (pruefsumme: ('$i' * 64).substring(0, 64), name: 'bild$i.jpg'),
        ],
      );
      expect(
        BackupProbeFandSchaden.aus(probe)!.namen,
        'bild1.jpg, bild2.jpg, bild3.jpg, bild4.jpg, bild5.jpg …',
      );
      final t = lookupAppTexte(const Locale('de'));
      final text = backupProbeTextMit(t, probe, (d) => 'heute');
      expect(text, contains('bild1.jpg'));
      expect(text, contains('Die nächste Sicherung schreibt sie'));
      // Gespeichert und wieder gelesen.
      final wieder = BackupProbeErgebnis.ausJson(probe.alsJson());
      expect(wieder.beschaedigt.map((b) => b.name), [
        for (var i = 1; i <= 7; i++) 'bild$i.jpg',
      ]);
    });
  });
}
