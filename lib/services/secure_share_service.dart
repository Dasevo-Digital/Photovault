import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'export_service.dart';
import 'import_service.dart';
import 'vault_crypto.dart';

/// Erstellt ein einzelnes, portables und passwortgeschütztes Austauschpaket.
/// Dateinamen und Manifest sind ebenso verschlüsselt wie die Medien selbst.
class SecureShareService {
  SecureShareService(this._exporter);

  final ExportService _exporter;
  Future<void> createPackage(
    List<AssetData> assets,
    File destination,
    String passphrase,
  ) async {
    if (assets.isEmpty) throw ArgumentError('Keine Aufnahmen ausgewählt');
    if (passphrase.trim().length < 10) {
      throw ArgumentError('Die Passphrase muss mindestens 10 Zeichen haben.');
    }

    final temp = await Directory.systemTemp.createTemp('pv_share_');
    try {
      final dataDir = Directory(p.join(temp.path, 'data'));
      await dataDir.create(recursive: true);
      final wrapped = await VaultCrypto.createMasterKey(passphrase);
      final manifest = <Map<String, Object?>>[];

      for (var i = 0; i < assets.length; i++) {
        final asset = assets[i];
        final source = await _exporter.resolveSourceFile(asset);
        final opaqueName = '${(i + 1).toString().padLeft(6, '0')}.pve';
        await VaultCrypto.encryptFile(
            source, File(p.join(dataDir.path, opaqueName)), wrapped.masterKey);
        manifest.add({
          'file': opaqueName,
          'name': p.basename(asset.originalFileName),
          'type': asset.type,
          'capturedAt': asset.fileCreatedAt.toIso8601String(),
          'checksum': asset.checksum,
        });
      }

      final manifestEncrypted = File(p.join(temp.path, 'manifest.pve'));
      final manifestBytes = utf8.encode(jsonEncode({
        'format': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'assets': manifest,
      }));
      await manifestEncrypted.writeAsBytes(await VaultCrypto.encryptBytes(
          manifestBytes, wrapped.masterKey,
          aad: utf8.encode('photo-vault-share-manifest')));

      await File(p.join(temp.path, 'key.json')).writeAsString(jsonEncode({
        'format': 1,
        'kdfSalt': base64Encode(wrapped.kdfSalt),
        'nonce': base64Encode(wrapped.nonce),
        'wrapped': base64Encode(wrapped.wrapped),
      }));

      await destination.parent.create(recursive: true);
      if (await destination.exists()) await destination.delete();
      await ZipFileEncoder()
          .zipDirectory(temp, filename: destination.path, followLinks: false);
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  /// Öffnet ein Austauschpaket, prüft Struktur, Passwort und Prüfsummen und
  /// führt die entschlüsselten Originale durch denselben Importweg wie eine
  /// normale Dateiauswahl. Klartext liegt nur in einem privaten Temp-Ordner
  /// und wird auch bei Fehlern entfernt.
  Future<({int imported, int duplicates})> importPackage(
    File package,
    String passphrase,
    ImportService importer,
  ) async {
    final temp = await Directory.systemTemp.createTemp('pv_share_open_');
    InputFileStream? input;
    try {
      if (!Platform.isWindows) {
        await Process.run('chmod', ['700', temp.path]);
      }
      input = InputFileStream(package.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      final allowed = RegExp(r'^(key\.json|manifest\.pve|data/[0-9]{6}\.pve)$');
      var total = 0;
      final packageBytes = await package.length();
      for (final entry in archive) {
        final name = entry.name.replaceAll('\\', '/');
        if (entry.isDirectory && name == 'data/') continue;
        if (entry.isDirectory ||
            entry.isSymbolicLink ||
            !allowed.hasMatch(name)) {
          throw const FormatException('Unerlaubter Eintrag im Austauschpaket.');
        }
        total += entry.size;
        if (total > packageBytes * 3 + 10 * 1024 * 1024) {
          throw const FormatException('Unplausible Paketgröße.');
        }
        final target = File(p.joinAll([temp.path, ...name.split('/')]));
        await target.parent.create(recursive: true);
        final output = OutputFileStream(target.path);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }
      }
      await input.close();
      input = null;

      final keyData =
          jsonDecode(await File(p.join(temp.path, 'key.json')).readAsString())
              as Map;
      if (keyData['format'] != 1) {
        throw const FormatException('Unbekanntes Austauschformat.');
      }
      final key = await VaultCrypto.unwrapMasterKey(
        passphrase,
        kdfSalt: base64Decode(keyData['kdfSalt'] as String),
        nonce: base64Decode(keyData['nonce'] as String),
        wrapped: base64Decode(keyData['wrapped'] as String),
      );
      final encryptedManifest =
          await File(p.join(temp.path, 'manifest.pve')).readAsBytes();
      final manifestClear = await VaultCrypto.decryptBytes(
          encryptedManifest, key,
          aad: utf8.encode('photo-vault-share-manifest'));
      final manifest = jsonDecode(utf8.decode(manifestClear)) as Map;
      if (manifest['format'] != 1 || manifest['assets'] is! List) {
        throw const FormatException('Ungültiges Austauschmanifest.');
      }

      var imported = 0;
      var duplicates = 0;
      for (final raw in manifest['assets'] as List) {
        final item = raw as Map;
        final encryptedName = item['file'] as String;
        if (!RegExp(r'^[0-9]{6}\.pve$').hasMatch(encryptedName)) {
          throw const FormatException('Ungültiger Dateiverweis im Manifest.');
        }
        final originalName = p.basename(item['name'] as String);
        if (originalName.isEmpty || originalName != item['name']) {
          throw const FormatException('Ungültiger Originaldateiname.');
        }
        final clear = File(p.join(temp.path, 'clear', originalName));
        await clear.parent.create(recursive: true);
        await VaultCrypto.decryptFile(
            File(p.join(temp.path, 'data', encryptedName)), clear, key);
        final actualChecksum =
            await sha256.bind(clear.openRead()).first.then((d) => d.toString());
        if (actualChecksum != item['checksum']) {
          throw const FormatException('Prüfsumme einer Aufnahme stimmt nicht.');
        }
        final capturedAt = DateTime.tryParse(item['capturedAt'] as String);
        if (capturedAt != null) await clear.setLastModified(capturedAt);
        final result = await importer.importFile(clear.path);
        if (result.outcome == ImportOutcome.imported) {
          imported++;
        } else if (result.outcome == ImportOutcome.duplicateSkipped) {
          duplicates++;
        }
        await clear.delete();
      }
      return (imported: imported, duplicates: duplicates);
    } finally {
      await input?.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }
}
