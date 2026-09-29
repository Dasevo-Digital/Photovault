// **Eine Frist, die ältere Fassungen überlesen, ist keine Frist.**
//
// Das Ablaufdatum kam als zusätzliches Feld in ein Manifest, das
// weiterhin `format: 1` trug. Ältere Fassungen kennen das Feld nicht,
// überlesen es und importieren. Vorgeführt an einem Paket, dessen Frist
// ein Jahr zurücklag:
//
// ```
// heutige Fassung   SharePackageExpired, nichts importiert
// 3.15.0            importiert 1 Aufnahme
// ```
//
// 3.15.0 steht auf beiden Freigabeseiten zum Herunterladen – es brauchte
// also keinen Umbau, nur einen älteren Download.
//
// Geprüft wird deshalb an der Fassungsnummer im entschlüsselten
// Manifest: genau das, woran ein älterer Leser abprallt.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/secure_share_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/services/vault_crypto.dart';

/// Packt ein Paket aus und entschlüsselt sein Manifest – derselbe Weg,
/// den auch ein Leser der Fassung 3.15.0 gegangen ist.
Future<Map<Object?, Object?>> _manifest(File paket, String passphrase) async {
  final temp = Directory.systemTemp.createTempSync('pv_manifest_');
  try {
    final eingang = InputFileStream(paket.path);
    final archiv = ZipDecoder().decodeStream(eingang, verify: true);
    for (final eintrag in archiv) {
      if (eintrag.isDirectory) continue;
      final ziel = File(p.joinAll([temp.path, ...eintrag.name.split('/')]));
      await ziel.parent.create(recursive: true);
      final ausgang = OutputFileStream(ziel.path);
      try {
        eintrag.writeContent(ausgang);
      } finally {
        await ausgang.close();
      }
    }
    await eingang.close();
    final schluesseldaten =
        jsonDecode(await File(p.join(temp.path, 'key.json')).readAsString())
            as Map;
    final schluessel = await VaultCrypto.unwrapMasterKey(
      passphrase,
      kdfSalt: base64Decode(schluesseldaten['kdfSalt'] as String),
      nonce: base64Decode(schluesseldaten['nonce'] as String),
      wrapped: base64Decode(schluesseldaten['wrapped'] as String),
    );
    final klar = await VaultCrypto.decryptBytes(
        await File(p.join(temp.path, 'manifest.pve')).readAsBytes(), schluessel,
        aad: utf8.encode('photo-vault-share-manifest'));
    return jsonDecode(utf8.decode(klar)) as Map<Object?, Object?>;
  } finally {
    temp.deleteSync(recursive: true);
  }
}

/// Die Regel, nach der die Fassung 3.15.0 ein Manifest annahm.
bool _alterLeserNimmtAn(Map<Object?, Object?> manifest) =>
    manifest['format'] == 1 && manifest['assets'] is List;

AssetData _aufnahme(String rel, List<int> inhalt) => AssetData(
      id: 'frist',
      originalFileName: p.basename(rel),
      relativePath: rel,
      checksum: sha256.convert(inhalt).toString(),
      type: 'IMAGE',
      fileCreatedAt: DateTime(2026),
      importedAt: DateTime(2026),
      isFavorite: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      fileSizeBytes: inhalt.length,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      rating: 0,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
    );

void main() {
  late Directory temp;
  late StoragePaths paths;
  const passphrase = 'eine-lange-passphrase';
  const inhalt = [3, 1, 4, 1, 5];
  const rel = 'originals/frist.jpg';

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_frist_');
    paths =
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'library')));
    await paths.absolute(rel).parent.create(recursive: true);
    await paths.absolute(rel).writeAsBytes(inhalt);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<File> paket({DateTime? frist}) async {
    final ziel = File(p.join(temp.path, 'p${frist?.year ?? 0}.pvshare'));
    await SecureShareService(ExportService(paths))
        .createPackage([_aufnahme(rel, inhalt)], ziel, passphrase,
            expiresAt: frist);
    return ziel;
  }

  test('ein Paket MIT Frist sperrt den alten Leser aus', () async {
    final frist = DateTime.now().toUtc().add(const Duration(days: 3));
    final manifest = await _manifest(await paket(frist: frist), passphrase);

    expect(manifest['format'], SecureShareService.formatMitFrist);
    expect(manifest['expiresAt'], isNotNull);
    expect(_alterLeserNimmtAn(manifest), isFalse,
        reason: 'sonst überliest eine ältere Fassung die Frist und '
            'importiert – genau der vorgeführte Weg über 3.15.0');
  });

  test('ein Paket OHNE Frist bleibt für den alten Leser offen', () async {
    // Die Verschärfung darf nicht alles einsperren: Pakete ohne Frist
    // versprechen nichts und sollen weiter überall aufgehen.
    final manifest = await _manifest(await paket(), passphrase);

    expect(manifest['format'], SecureShareService.formatOhneFrist);
    expect(manifest.containsKey('expiresAt'), isFalse);
    expect(_alterLeserNimmtAn(manifest), isTrue);
  });

  test('und die heutige Fassung öffnet beide', () async {
    for (final frist in [
      null,
      DateTime.now().toUtc().add(const Duration(days: 3)),
    ]) {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final zielPaths = await StoragePaths.forTesting(
          Directory(p.join(temp.path, 'ziel${frist?.year ?? 0}')));
      final ergebnis = await SecureShareService(ExportService(paths))
          .importPackage(await paket(frist: frist), passphrase,
              ImportService(db, zielPaths));
      expect(ergebnis.imported, 1, reason: 'Frist: $frist');
    }
  });
}
