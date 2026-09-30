import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'export_service.dart';
import 'import_service.dart';
import 'vault_crypto.dart';

/// Ein Paket wurde mit einer abgelaufenen Freigabefrist geöffnet.
///
/// Die Frist ist Teil des verschlüsselten Manifests. Sie verrät außerhalb des
/// Pakets weder Auswahl noch Namen und wird geprüft, bevor Klartextdateien
/// für den Import entstehen.
class SharePackageExpired implements Exception {
  const SharePackageExpired(this.expiresAt);

  final DateTime expiresAt;
}

/// Schreibt einen ZIP-Eintrag auf Platte, ohne sich auf dessen Größenangabe
/// blind zu verlassen. ZIP-Metadaten sind nicht authentifiziert: Ein
/// manipuliertes Archiv könnte eine kleine Größe behaupten und beim
/// Dekomprimieren weit mehr liefern. Der Zähler bricht dann *während* des
/// Entpackens ab, bevor Platte oder Arbeitsspeicher unkontrolliert wachsen.
class _BegrenzterDateiAusgabestrom extends OutputStream {
  _BegrenzterDateiAusgabestrom(String path, this.maxBytes)
      : _delegate = OutputFileStream(path),
        super(byteOrder: ByteOrder.littleEndian);

  final OutputFileStream _delegate;
  final int maxBytes;

  void _pruefe(int bytes) {
    if (bytes < 0 || length + bytes > maxBytes) {
      throw const FormatException('Unplausible Paketgröße.');
    }
  }

  @override
  int get length => _delegate.length;

  @override
  bool get isOpen => _delegate.isOpen;

  @override
  Future<void> close() => _delegate.close();

  @override
  void closeSync() => _delegate.closeSync();

  @override
  void clear() => _delegate.clear();

  @override
  void flush() => _delegate.flush();

  @override
  Uint8List subset(int start, [int? end]) => _delegate.subset(start, end);

  @override
  void writeByte(int value) {
    _pruefe(1);
    _delegate.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _pruefe(count);
    _delegate.writeBytes(bytes, length: count);
  }

  @override
  void writeStream(InputStream stream) {
    _pruefe(stream.length);
    _delegate.writeStream(stream);
  }
}

/// Erstellt ein einzelnes, portables und passwortgeschütztes Austauschpaket.
/// Dateinamen und Manifest sind ebenso verschlüsselt wie die Medien selbst.
class SecureShareService {
  /// Ein Paket ohne Frist. Jede Fassung dieser App kann es öffnen.
  static const formatOhneFrist = 1;

  /// Ein Paket **mit** Frist – und deshalb eine eigene Fassungsnummer.
  ///
  /// **Sonst ist die Frist keine.** Sie kam als zusätzliches Feld in ein
  /// Manifest, das weiterhin `format: 1` trug. Ältere Fassungen kennen das
  /// Feld nicht, überlesen es und importieren. Vorgeführt an einem Paket,
  /// dessen Frist ein Jahr zurücklag:
  ///
  /// ```
  /// heutige Fassung   SharePackageExpired, nichts importiert
  /// 3.15.0            importiert 1 Aufnahme
  /// ```
  ///
  /// 3.15.0 steht auf beiden Freigabeseiten zum Herunterladen; es war also
  /// kein Umbau nötig, nur ein älterer Download. Mit einer eigenen
  /// Fassungsnummer weist jede Fassung, die die Frist nicht kennt, das
  /// Paket ab, statt sie zu übergehen.
  ///
  /// **Was die Frist trotzdem nicht ist:** ein Schutz gegen den
  /// Empfänger. Wer das Paket und die Passphrase hat, kann seine Uhr
  /// stellen. Sie hält einen ehrlichen Empfänger davon ab, ein altes Paket
  /// weiterzuverwenden – mehr kann eine Frist, die im Paket selbst steht,
  /// nicht leisten. Der Oberflächentext sagt das inzwischen auch.
  static const formatMitFrist = 2;

  SecureShareService(this._exporter, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final ExportService _exporter;
  final DateTime Function() _now;
  Future<void> createPackage(
    List<AssetData> assets,
    File destination,
    String passphrase, {
    DateTime? expiresAt,
  }) async {
    if (assets.isEmpty) throw ArgumentError('Keine Aufnahmen ausgewählt');
    if (passphrase.trim().length < 10) {
      throw ArgumentError('Die Passphrase muss mindestens 10 Zeichen haben.');
    }
    final expiresAtUtc = expiresAt?.toUtc();
    if (expiresAtUtc != null && !expiresAtUtc.isAfter(_now().toUtc())) {
      throw ArgumentError('Der Ablaufzeitpunkt muss in der Zukunft liegen.');
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
      final manifestPayload = <String, Object?>{
        'format': expiresAtUtc == null ? formatOhneFrist : formatMitFrist,
        'createdAt': _now().toUtc().toIso8601String(),
        'assets': manifest,
        if (expiresAtUtc != null) 'expiresAt': expiresAtUtc.toIso8601String(),
      };
      final manifestBytes = utf8.encode(jsonEncode(manifestPayload));
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
      final allowed = RegExp(r'^(key\.json|manifest\.pve|data/[0-9]{6}\.pve)$');
      final packageBytes = await package.length();
      final maxExpandedBytes = packageBytes * 3 + 10 * 1024 * 1024;
      var declaredTotal = 0;
      final names = <String>{};

      // Die Callback-Prüfung läuft nach dem Lesen des Zentralverzeichnisses
      // und VOR dem ersten Entpacken. Damit wird eine ZIP-Bombe schon anhand
      // ihrer deklarierten Größen abgewiesen. Der begrenzte Ausgabestrom
      // unten kontrolliert zusätzlich jede tatsächlich ausgegebene Bytezahl,
      // falls jemand die Größenangabe im Archiv manipuliert hat.
      final archive =
          ZipDecoder().decodeStream(input, verify: true, callback: (entry) {
        final name = entry.name.replaceAll('\\', '/');
        if (entry.isDirectory && name == 'data/') return;
        if (entry.isDirectory ||
            entry.isSymbolicLink ||
            !allowed.hasMatch(name)) {
          throw const FormatException('Unerlaubter Eintrag im Austauschpaket.');
        }
        if (!names.add(name) || entry.size < 0) {
          throw const FormatException('Ungültige Paketstruktur.');
        }
        declaredTotal += entry.size;
        if (entry.size > maxExpandedBytes || declaredTotal > maxExpandedBytes) {
          throw const FormatException('Unplausible Paketgröße.');
        }
      });
      for (final entry in archive) {
        final name = entry.name.replaceAll('\\', '/');
        if (entry.isDirectory && name == 'data/') continue;
        final target = File(p.joinAll([temp.path, ...name.split('/')]));
        await target.parent.create(recursive: true);
        final output = _BegrenzterDateiAusgabestrom(target.path, entry.size);
        try {
          entry.writeContent(output);
          if (output.length != entry.size) {
            throw const FormatException('Unplausible Paketgröße.');
          }
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
      final format = manifest['format'];
      if ((format != formatOhneFrist && format != formatMitFrist) ||
          manifest['assets'] is! List) {
        throw const FormatException('Ungültiges Austauschmanifest.');
      }
      final rawExpiresAt = manifest['expiresAt'];
      // Eine Frist in einem Paket der Fassung 1 wäre genau die Lücke, die
      // die eigene Fassung schliesst: Sie käme von einem Absender, der die
      // Frist meinte, und von einem Leser, der sie nicht garantiert sieht.
      if ((format == formatMitFrist) != (rawExpiresAt != null)) {
        throw const FormatException('Ungültiges Austauschmanifest.');
      }
      if (rawExpiresAt != null) {
        if (rawExpiresAt is! String) {
          throw const FormatException('Ungültiger Ablaufzeitpunkt im Paket.');
        }
        final expiresAt = DateTime.tryParse(rawExpiresAt);
        if (expiresAt == null) {
          throw const FormatException('Ungültiger Ablaufzeitpunkt im Paket.');
        }
        if (!_now().toUtc().isBefore(expiresAt.toUtc())) {
          throw SharePackageExpired(expiresAt.toUtc());
        }
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
