import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('Migration 82 auf 83 ergänzt den Metadatenschutz verlustfrei', () async {
    final dir = await Directory.systemTemp.createTemp('photo_vault_v82_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.sqlite');

    final initial = AppDatabase(NativeDatabase(file));
    await initial.saveVaultKey(
      kdfSalt: Uint8List.fromList([1, 2, 3]),
      nonce: Uint8List.fromList([4, 5, 6]),
      wrapped: Uint8List.fromList([7, 8, 9]),
    );
    await initial.close();

    final old = sqlite.sqlite3.open(file.path);
    old.execute('ALTER TABLE privacy_settings DROP COLUMN protect_metadata');
    old.execute('PRAGMA user_version = 82');
    old.close();

    final migrated = AppDatabase(NativeDatabase(file));
    addTearDown(migrated.close);
    final row = await migrated.privacySettingsRow();

    expect(row, isNotNull);
    expect(row!.protectMetadata, isTrue);
    expect(row.kdfSalt, Uint8List.fromList([1, 2, 3]));
    expect(row.wrappedMasterKeyNonce, Uint8List.fromList([4, 5, 6]));
    expect(row.wrappedMasterKey, Uint8List.fromList([7, 8, 9]));
  });
}
