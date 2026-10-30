import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';

/// Das Ziel entscheidet, was eine Sicherung noch schreiben muss (#242).
///
/// Bis dahin entschied die Markierung „gesichert“ an der Aufnahme. Sie sagt
/// nur, dass ein Foto irgendwann irgendwohin gesichert wurde – ein zweiter
/// Ordner bekam deshalb kein einziges älteres Original, nur die
/// `metadata.json`, die sie alle aufzählte.
void main() {
  late Directory temp;
  late AppDatabase db;
  late BackupService dienst;
  late SecretKey schluessel;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_neues_ziel_');
    db = AppDatabase(NativeDatabase.memory());
    final pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    dienst = BackupService(db, pfade);
    final w = await VaultCrypto.createMasterKey('synthetische-passphrase');
    schluessel = w.masterKey;
    await db.saveBackupKey(
      kdfSalt: w.kdfSalt,
      nonce: w.nonce,
      wrapped: w.wrapped,
    );
    final importe = ImportService(db, pfade);
    for (var i = 0; i < 4; i++) {
      final f = File(p.join(temp.path, 'bild-$i.jpg'))
        ..writeAsBytesSync(List.filled(64 * 1024, i));
      await importe.importFile(f.path);
    }
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Directory ordner(String name) =>
      Directory(p.join(temp.path, name))..createSync();

  int originaleIn(Directory ziel) {
    final d = Directory(p.join(ziel.path, 'PhotoVault-Backup', 'originals'));
    return d
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => p.extension(f.path) == '.jpg')
        .length;
  }

  int verschluesseltIn(Directory ziel, String sicherung) {
    final d = Directory(p.join(ziel.path, sicherung, 'data'));
    return d.existsSync() ? d.listSync().length : 0;
  }

  test('von Hand: ein zweiter Ordner bekommt alle Originale', () async {
    final a = ordner('stick-a'), b = ordner('stick-b');
    await dienst.performBackup(a.path).drain<void>();
    final verlauf = await dienst.performBackup(b.path).toList();

    expect(originaleIn(a), 4);
    expect(originaleIn(b), 4);
    expect(verlauf.last.wiederherstellungsprobe?.erfolgreich, isTrue);
    expect((await db.lastBackupRecord())!.fileCount, 4);
    expect(await db.assetsNotBackedUp(), isEmpty);
  });

  test('von Hand verschlüsselt: ebenso', () async {
    final a = ordner('stick-a'), b = ordner('stick-b');
    await dienst.performBackup(a.path, encryptionKey: schluessel).drain<void>();
    final verlauf = await dienst
        .performBackup(b.path, encryptionKey: schluessel)
        .toList();

    expect(verschluesseltIn(b, 'PhotoVault-Backup'), 4);
    expect(verlauf.last.wiederherstellungsprobe?.erfolgreich, isTrue);
  });

  test('ein zweiter Lauf ins selbe Ziel schreibt nichts neu', () async {
    final a = ordner('stick-a');
    await dienst.performBackup(a.path).drain<void>();
    final datei = Directory(p.join(a.path, 'PhotoVault-Backup', 'originals'))
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => p.extension(f.path) == '.jpg');
    final vorher = datei.lastModifiedSync();

    await dienst.performBackup(a.path).drain<void>();

    // Beide Berichte, nicht der letzte: Sie tragen dieselbe Sekunde.
    final berichte = await db.select(db.backupRecords).get();
    expect(berichte.map((b) => b.fileCount), unorderedEquals([4, 0]));
    expect(datei.lastModifiedSync(), vorher);
  });

  test('automatisch: ein neues Ziel füllt sich, die Probe gelingt', () async {
    final a = ordner('cloud-a'), b = ordner('cloud-b');
    await dienst.performAutoBackup(a.path, schluessel).drain<void>();
    BackupProbeErgebnis? probe;
    await for (final f in dienst.performAutoBackup(b.path, schluessel)) {
      probe = f.wiederherstellungsprobe ?? probe;
    }

    expect(verschluesseltIn(b, 'PhotoVault-AutoBackup'), 4);
    expect(dienst.letzterLaufNeu, 4);
    expect(probe?.erfolgreich, isTrue, reason: '${probe?.fehler}');
  });

  test('automatisch: eine im Ziel verlorene Datei kommt wieder', () async {
    final a = ordner('cloud-a');
    await dienst.performAutoBackup(a.path, schluessel).drain<void>();
    Directory(
      p.join(a.path, 'PhotoVault-AutoBackup', 'data'),
    ).listSync().whereType<File>().first.deleteSync();

    BackupProbeErgebnis? probe;
    await for (final f in dienst.performAutoBackup(a.path, schluessel)) {
      probe = f.wiederherstellungsprobe ?? probe;
    }

    expect(dienst.letzterLaufNeu, 1);
    expect(verschluesseltIn(a, 'PhotoVault-AutoBackup'), 4);
    expect(probe?.erfolgreich, isTrue, reason: '${probe?.fehler}');
  });

  test('Grenze: offen zählt nur, was im Ziel fehlt', () async {
    final a = ordner('stick-a');
    // 4 × 64 KB, Grenze 100 KB: Nach zwei Dateien ist sie erreicht.
    final erster = await dienst
        .performBackup(a.path, maxBytesPerRun: 100 * 1024)
        .toList();
    expect(originaleIn(a), 2);
    expect(erster.last.grenzeOffen, 2);

    // Der Rest kommt nach. Fehlt dann nur die erste Datei, greift die
    // Grenze gleich nach ihr – dahinter liegt aber alles schon im Ziel.
    // Der Lauf ist vollständig: Die Probe läuft, statt als „begrenzt“
    // auszufallen.
    await dienst.performBackup(a.path).drain<void>();
    final erste = (await db.assetsFuerSicherung()).first;
    File(p.join(a.path, 'PhotoVault-Backup', erste.relativePath)).deleteSync();
    final dritter = await dienst
        .performBackup(a.path, maxBytesPerRun: 1)
        .toList();
    expect(originaleIn(a), 4);
    expect(dritter.map((f) => f.grenzeOffen).whereType<int>(), isEmpty);
    expect(dritter.last.wiederherstellungsprobe?.erfolgreich, isTrue);
  });

  test('Papierkorb: nur mit gesicherter Datei in der Beilage', () async {
    final alle = await db.select(db.assets).get();
    final a = ordner('stick-a');
    // Vor dem ersten Lauf verworfen: Die Datei kommt nie ins Ziel, die
    // Beilage darf sie nicht aufzählen – sonst scheitert jede Probe.
    await db.moveToTrash([alle[0].id]);
    final proben = <String?>[];
    for (var lauf = 0; lauf < 3; lauf++) {
      await for (final f in dienst.performBackup(a.path)) {
        if (f.wiederherstellungsprobe case final w?) {
          proben.add(w.erfolgreich ? null : w.fehler);
        }
      }
    }
    expect(proben, [null, null, null]);

    // Nach einem Lauf verworfen: Die Datei liegt im Ziel, der Eintrag
    // bleibt mit seinen Angaben.
    await db.moveToTrash([alle[1].id]);
    await dienst.performBackup(a.path).drain<void>();
    final beilage = File(
      p.join(a.path, 'PhotoVault-Backup', 'metadata.json'),
    ).readAsStringSync();
    expect(beilage, isNot(contains(alle[0].checksum)));
    expect(beilage, contains(alle[1].checksum));
  });
}
