import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/vault_crypto.dart';

/// Prüft die Kernversprechen der Vault-Verschlüsselung: Roundtrip liefert
/// exakt die Originaldaten zurück, ein falscher PIN wird zuverlässig
/// erkannt, und eine manipulierte Datei fällt beim Entschlüsseln auf statt
/// unbemerkt falsche Daten zu liefern.
void main() {
  late Directory tempRoot;

  setUp(() => tempRoot = Directory.systemTemp.createTempSync('photo_vault_vault_crypto_test_'));
  tearDown(() => tempRoot.deleteSync(recursive: true));

  test('PIN-Envelope: richtiger PIN entpackt den Master-Key, falscher PIN scheitert', () async {
    final wrapped = await VaultCrypto.createMasterKey('1234');
    final masterKeyBytes = await wrapped.masterKey.extractBytes();

    final unwrapped = await VaultCrypto.unwrapMasterKey(
      '1234',
      kdfSalt: wrapped.kdfSalt,
      nonce: wrapped.nonce,
      wrapped: wrapped.wrapped,
    );
    expect(await unwrapped.extractBytes(), equals(masterKeyBytes));

    await expectLater(
      VaultCrypto.unwrapMasterKey(
        '0000',
        kdfSalt: wrapped.kdfSalt,
        nonce: wrapped.nonce,
        wrapped: wrapped.wrapped,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('PIN-Wechsel: derselbe Master-Key lässt sich mit einem neuen PIN neu verpacken', () async {
    final original = await VaultCrypto.createMasterKey('1234');
    final rewrapped = await VaultCrypto.wrapMasterKey(original.masterKey, '5678');

    final viaOldPin = await VaultCrypto.unwrapMasterKey(
      '5678',
      kdfSalt: rewrapped.kdfSalt,
      nonce: rewrapped.nonce,
      wrapped: rewrapped.wrapped,
    );
    expect(await viaOldPin.extractBytes(), equals(await original.masterKey.extractBytes()));

    await expectLater(
      VaultCrypto.unwrapMasterKey(
        '1234',
        kdfSalt: rewrapped.kdfSalt,
        nonce: rewrapped.nonce,
        wrapped: rewrapped.wrapped,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('Datei-Roundtrip: Verschlüsseln + Entschlüsseln liefert exakt die Originaldaten zurück', () async {
    final wrapped = await VaultCrypto.createMasterKey('1234');
    final original = File(p.join(tempRoot.path, 'original.bin'))
      ..writeAsBytesSync(List.generate(3 * 1024 * 1024 + 137, (i) => i % 256)); // >2 Chunks, ungerade Restlänge

    final encrypted = File(p.join(tempRoot.path, 'encrypted.bin'));
    await VaultCrypto.encryptFile(original, encrypted, wrapped.masterKey);
    expect(await encrypted.length(), isNot(equals(await original.length())));

    final decrypted = File(p.join(tempRoot.path, 'decrypted.bin'));
    await VaultCrypto.decryptFile(encrypted, decrypted, wrapped.masterKey);

    expect(await decrypted.readAsBytes(), equals(await original.readAsBytes()));
  });

  test('Entschlüsseln mit falschem Master-Key schlägt fehl statt falsche Daten zu liefern', () async {
    final wrapped = await VaultCrypto.createMasterKey('1234');
    final other = await VaultCrypto.createMasterKey('9999');
    final original = File(p.join(tempRoot.path, 'original.bin'))..writeAsBytesSync([1, 2, 3, 4, 5]);
    final encrypted = File(p.join(tempRoot.path, 'encrypted.bin'));
    await VaultCrypto.encryptFile(original, encrypted, wrapped.masterKey);

    final decrypted = File(p.join(tempRoot.path, 'decrypted.bin'));
    await expectLater(
      VaultCrypto.decryptFile(encrypted, decrypted, other.masterKey),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('manipulierte verschlüsselte Datei wird beim Entschlüsseln erkannt', () async {
    final wrapped = await VaultCrypto.createMasterKey('1234');
    final original = File(p.join(tempRoot.path, 'original.bin'))..writeAsBytesSync([1, 2, 3, 4, 5]);
    final encrypted = File(p.join(tempRoot.path, 'encrypted.bin'));
    await VaultCrypto.encryptFile(original, encrypted, wrapped.masterKey);

    final bytes = await encrypted.readAsBytes();
    bytes[bytes.length - 1] ^= 0xFF; // letztes Tag-Byte kippen
    await encrypted.writeAsBytes(bytes);

    final decrypted = File(p.join(tempRoot.path, 'decrypted.bin'));
    await expectLater(
      VaultCrypto.decryptFile(encrypted, decrypted, wrapped.masterKey),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('Timing: PIN-Ableitung (Argon2id) liegt in einem für die UI akzeptablen Bereich', () async {
    final sw = Stopwatch()..start();
    await VaultCrypto.createMasterKey('1234');
    sw.stop();
    // ignore: avoid_print
    print('Argon2id-Ableitung: ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsedMilliseconds, lessThan(5000));
  });
}
