import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/backup_verification_service.dart';
import 'package:photo_vault/services/vault_crypto.dart';

void main() {
  late Directory temp;

  setUp(
      () => temp = Directory.systemTemp.createTempSync('pv_backup_pruefung_'));
  tearDown(() => temp.deleteSync(recursive: true));

  Future<File> schreibeManifest(Directory backup, List<int> bytes) async {
    final checksum = sha256.convert(bytes).toString();
    final datei = File(p.join(backup.path, 'originals', '2026', '01', 'a.jpg'));
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(bytes);
    await File(p.join(backup.path, 'metadata.json')).writeAsString(jsonEncode({
      'assets': [
        {
          'checksum': checksum,
          'originalFileName': 'a.jpg',
          'backupRelativePath': 'originals/2026/01/a.jpg',
        }
      ],
    }));
    return datei;
  }

  test('prueft ein vollständiges Klartext-Backup auch vom Zielordner aus',
      () async {
    final ziel = Directory(p.join(temp.path, 'ziel'))..createSync();
    final backup = Directory(p.join(ziel.path, 'PhotoVault-Backup'))
      ..createSync();
    await schreibeManifest(backup, [1, 2, 3, 4]);

    final fortschritt = await BackupPruefdienst().pruefe(ziel.path).toList();
    final ende = fortschritt.last;
    expect(ende.erfolgreich, isTrue);
    expect(ende.gueltig, 1);
  });

  test('meldet eine manipulierte Originaldatei als beschädigt', () async {
    final backup = Directory(p.join(temp.path, 'PhotoVault-Backup'))
      ..createSync();
    final datei = await schreibeManifest(backup, [1, 2, 3, 4]);
    await datei.writeAsBytes([9, 9, 9, 9]);

    final ende = (await BackupPruefdienst().pruefe(backup.path).toList()).last;
    expect(ende.erfolgreich, isFalse);
    expect(ende.beschaedigt, 1);
  });

  test('entschlüsselt verschlüsselte Backups nur für die Prüfung', () async {
    final backup = Directory(p.join(temp.path, 'PhotoVault-Backup'))
      ..createSync();
    const passphrase = 'korrektes-passwort';
    final schluessel = await VaultCrypto.createMasterKey(passphrase);
    final bytes = [7, 8, 9, 10];
    final checksum = sha256.convert(bytes).toString();
    final klartext = File(p.join(temp.path, 'klar.jpg'))
      ..writeAsBytesSync(bytes);
    final daten = Directory(p.join(backup.path, VerschluesselteNamen.ordner))
      ..createSync();
    final verschluesselt = File(p.join(
        daten.path,
        await VerschluesselteNamen.fuerPruefsumme(
            checksum, schluessel.masterKey)));
    await VaultCrypto.encryptFile(
        klartext, verschluesselt, schluessel.masterKey);

    final metaKlar = File(p.join(temp.path, 'metadata.json'))
      ..writeAsStringSync(jsonEncode({
        'assets': [
          {'checksum': checksum, 'originalFileName': 'a.jpg'}
        ],
      }));
    await VaultCrypto.encryptFile(metaKlar,
        File(p.join(backup.path, 'metadata.json')), schluessel.masterKey);
    await File(p.join(backup.path, 'vault.key')).writeAsString(jsonEncode({
      'kdfSalt': base64Encode(schluessel.kdfSalt),
      'nonce': base64Encode(schluessel.nonce),
      'wrapped': base64Encode(schluessel.wrapped),
    }));

    final ende = (await BackupPruefdienst()
            .pruefe(backup.path, passphrase: passphrase)
            .toList())
        .last;
    expect(ende.erfolgreich, isTrue);
    expect(ende.gueltig, 1);
  });
}
