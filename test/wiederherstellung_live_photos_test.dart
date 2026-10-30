import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/state/library_state.dart';

/// Eine Wiederherstellung bringt Live Photos als Paare zurück (#255).
///
/// Bis 3.49.8 importierte sie jede Datei für sich und verknüpfte nichts:
/// Jede Videohälfte stand danach als eigenes Video in der Zeitleiste.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late SecretKey schluessel;
  late String foto, video;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_live_zurueck_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    final importe = ImportService(db, pfade);
    Future<String> lege(String name, int fuellung) async {
      final f = File(p.join(temp.path, 'eingang', name))
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(4000, fuellung));
      return (await importe.importFile(f.path)).assetId!;
    }

    foto = await lege('IMG_0001.JPG', 1);
    video = await lege('IMG_0001.MOV', 2);
    await lege('IMG_0002.JPG', 3);
    await db.linkAssets(foto, video);
    final w = await VaultCrypto.createMasterKey('synthetische-passphrase');
    schluessel = w.masterKey;
    await db.saveBackupKey(
      kdfSalt: w.kdfSalt,
      nonce: w.nonce,
      wrapped: w.wrapped,
    );
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<String> sichere({required bool verschluesselt}) async {
    final ziel = Directory(p.join(temp.path, verschluesselt ? 'mit' : 'ohne'))
      ..createSync();
    await BackupService(db, pfade)
        .performBackup(
          ziel.path,
          encryptionKey: verschluesselt ? schluessel : null,
        )
        .drain<void>();
    return p.join(ziel.path, 'PhotoVault-Backup');
  }

  /// Nimmt den Partner aus der Beilage – wie eine Sicherung vor 3.49.9.
  Future<void> ohnePartner(String wurzel, {SecretKey? key}) async {
    final beilage = File(p.join(wurzel, 'metadata.json'));
    final klar = File(p.join(temp.path, 'klar.json'));
    if (key != null) await VaultCrypto.decryptFile(beilage, klar, key);
    final text = await (key == null ? beilage : klar).readAsString();
    final j = jsonDecode(text) as Map<String, dynamic>;
    for (final a in (j['assets'] as List).cast<Map<String, dynamic>>()) {
      a.remove('livePartner');
    }
    if (key == null) {
      await beilage.writeAsString(jsonEncode(j));
    } else {
      await klar.writeAsString(jsonEncode(j));
      await VaultCrypto.encryptFile(klar, beilage, key);
    }
  }

  Future<List<AssetData>> zurueck(
    String wurzel, {
    String? passphrase,
    bool ueberDieApp = false,
  }) async {
    final db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    final pfade2 = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'zurueck-${wurzel.hashCode}')),
    );
    final importe2 = ImportService(db2, pfade2);
    final Stream<dynamic> lauf;
    if (ueberDieApp) {
      final app = LibraryState()
        ..db = db2
        ..paths = pfade2
        ..importService = importe2
        ..backupService = BackupService(db2, pfade2);
      lauf = app.restoreFromBackup(wurzel, passphrase: passphrase);
    } else {
      lauf = BackupService(
        db2,
        pfade2,
      ).restoreFromBackup(wurzel, importe2, passphrase: passphrase);
    }
    await lauf.drain<void>();
    return db2.select(db2.assets).get();
  }

  void erwartePaar(List<AssetData> alle) {
    final f = alle.singleWhere((a) => a.originalFileName == 'IMG_0001.JPG');
    final v = alle.singleWhere((a) => a.originalFileName == 'IMG_0001.MOV');
    expect(f.linkedAssetId, v.id);
    expect(v.linkedAssetId, f.id);
    final allein = alle.singleWhere(
      (a) => a.originalFileName == 'IMG_0002.JPG',
    );
    expect(allein.linkedAssetId, isNull);
  }

  test('ohne Passphrase', () async {
    erwartePaar(await zurueck(await sichere(verschluesselt: false)));
  });

  test('mit Passphrase', () async {
    erwartePaar(
      await zurueck(
        await sichere(verschluesselt: true),
        passphrase: 'synthetische-passphrase',
      ),
    );
  });

  test(
    'ältere Sicherung mit Passphrase: das Paar steht im Schnappschuss',
    () async {
      final wurzel = await sichere(verschluesselt: true);
      await ohnePartner(wurzel, key: schluessel);

      erwartePaar(await zurueck(wurzel, passphrase: 'synthetische-passphrase'));
    },
  );

  test('ältere Sicherung ohne Passphrase: Name und Zeit paaren', () async {
    final wurzel = await sichere(verschluesselt: false);
    await ohnePartner(wurzel);

    final ohneApp = await zurueck(wurzel);
    expect(ohneApp.every((a) => a.linkedAssetId == null), isTrue);

    erwartePaar(await zurueck(wurzel, ueberDieApp: true));
  });

  test('schon verknüpfte Aufnahmen bleiben, wie sie sind', () async {
    final wurzel = await sichere(verschluesselt: false);
    // Wiederhergestellt in eine Bibliothek, in der das Foto schon liegt
    // und anders verknüpft ist.
    final db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    final pfade2 = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'bestand')),
    );
    final importe2 = ImportService(db2, pfade2);
    final f = File(p.join(temp.path, 'b', 'IMG_0001.JPG'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(4000, 1));
    final fotoHier = (await importe2.importFile(f.path)).assetId!;
    await (db2.update(db2.assets)..where((t) => t.id.equals(fotoHier))).write(
      const AssetsCompanion(linkedAssetId: Value('anderes')),
    );

    await BackupService(
      db2,
      pfade2,
    ).restoreFromBackup(wurzel, importe2).drain<void>();

    expect((await db2.assetById(fotoHier))!.linkedAssetId, 'anderes');
  });
}
