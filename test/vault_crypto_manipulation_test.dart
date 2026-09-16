import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/vault_crypto.dart';

/// Prüft, dass eine verschlüsselte Datei nicht nur blockweise, sondern auch
/// als Ganzes geschützt ist.
///
/// Der Anlass: AES-GCM authentifiziert jeden Block für sich – das allein
/// sagt aber nichts darüber, ob es noch dieselben Blöcke in derselben
/// Reihenfolge sind. Vorher liess sich eine 3 MiB grosse Datei am Ende
/// kürzen, und das Entschlüsseln lieferte klaglos 2 MiB.
void main() {
  late Directory tmp;
  late SecretKey key;

  /// Kopf und Aufbau eines Blocks, für die Manipulationen unten.
  const kopf = 4;
  const nonce = 12;
  const mac = 16;
  const blockGroesse = 1 << 20;
  const proBlock = kopf + nonce + blockGroesse + mac;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('pv_crypto_test_');
    key = await AesGcm.with256bits().newSecretKey();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  File datei(String name, [List<int>? inhalt]) {
    final f = File(p.join(tmp.path, name));
    if (inhalt != null) f.writeAsBytesSync(inhalt);
    return f;
  }

  Future<File> verschluesselt(List<int> inhalt, {String name = 'v.bin'}) async {
    final ziel = datei(name);
    await VaultCrypto.encryptFile(datei('klar_$name', inhalt), ziel, key);
    return ziel;
  }

  test('Hin und zurück über mehrere Blöcke hinweg', () async {
    final inhalt = List<int>.generate(3 << 20, (i) => i % 251);
    final zurueck = datei('zurueck.bin');
    await VaultCrypto.decryptFile(await verschluesselt(inhalt), zurueck, key);
    expect(zurueck.readAsBytesSync(), inhalt);
  });

  test('eine leere Datei bleibt leer – und hat trotzdem einen Abschluss', () async {
    final ver = await verschluesselt(const []);
    final zurueck = datei('leer_zurueck.bin');
    await VaultCrypto.decryptFile(ver, zurueck, key);
    expect(zurueck.lengthSync(), 0);
    // 4 Bytes Magic plus genau ein (leerer) Abschlussblock.
    expect(ver.lengthSync(), 4 + kopf + nonce + mac);
  });

  test('ein abgeschnittenes Ende fällt auf', () async {
    final ver = await verschluesselt(List.filled(3 << 20, 7));
    final roh = ver.readAsBytesSync();
    final gekuerzt = datei('kurz.bin', roh.sublist(0, roh.length - proBlock));

    await expectLater(
      VaultCrypto.decryptFile(gekuerzt, datei('z1.bin'), key),
      throwsA(isA<FormatException>()),
    );
  });

  test('auch das Abschneiden nur des Abschlussblocks fällt auf', () async {
    // Der heimtückischere Fall: Alle Datenblöcke sind noch da, es fehlt
    // bloss die Angabe, dass es alle waren.
    final ver = await verschluesselt(List.filled(2 << 20, 3));
    final roh = ver.readAsBytesSync();
    final ohneAbschluss =
        datei('ohne.bin', roh.sublist(0, roh.length - (kopf + nonce + mac)));

    await expectLater(
      VaultCrypto.decryptFile(ohneAbschluss, datei('z2.bin'), key),
      throwsA(isA<FormatException>()),
    );
  });

  test('vertauschte Blöcke fallen auf', () async {
    final ver = await verschluesselt(List.generate(2 << 20, (i) => i % 7));
    final roh = ver.readAsBytesSync();
    final a = roh.sublist(4, 4 + proBlock);
    final b = roh.sublist(4 + proBlock, 4 + 2 * proBlock);
    final getauscht = datei('tausch.bin',
        [...roh.sublist(0, 4), ...b, ...a, ...roh.sublist(4 + 2 * proBlock)]);

    await expectLater(
      VaultCrypto.decryptFile(getauscht, datei('z3.bin'), key),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('eine unplausible Blocklänge wird abgewiesen, statt sie anzufordern', () async {
    final ver = await verschluesselt(List.filled(1024, 1));
    final roh = ver.readAsBytesSync();
    // Die Länge steht unverschlüsselt in der Datei – ohne Schranke ginge sie
    // ungeprüft an read().
    roh.setRange(4, 8, [0xFF, 0xFF, 0xFF, 0xFF]);

    await expectLater(
      VaultCrypto.decryptFile(datei('gross.bin', roh), datei('z4.bin'), key),
      throwsA(isA<FormatException>()),
    );
  });

  test('ein veränderter Block fällt weiterhin auf', () async {
    final ver = await verschluesselt(List.filled(1024, 9));
    final roh = ver.readAsBytesSync();
    roh[4 + kopf + nonce] ^= 0xFF; // ein Bit im Chiffretext

    await expectLater(
      VaultCrypto.decryptFile(datei('kaputt.bin', roh), datei('z5.bin'), key),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('Dateien aus der Zeit vor der Umstellung bleiben lesbar', () async {
    // Das alte Format ("PVE1") von Hand nachgebaut: dieselben Blöcke, aber
    // ohne mitauthentifizierte Nummer und ohne Abschluss. Wer die App
    // aktualisiert, muss seine gesperrten Fotos nicht neu verschlüsseln.
    final cipher = AesGcm.with256bits();
    final inhalt = List<int>.generate(2 << 20, (i) => i % 13);
    final aus = <int>[0x50, 0x56, 0x45, 0x31];
    for (var start = 0; start < inhalt.length; start += blockGroesse) {
      final teil = inhalt.sublist(
          start, (start + blockGroesse).clamp(0, inhalt.length));
      final n = cipher.newNonce();
      final box = await cipher.encrypt(teil, secretKey: key, nonce: n);
      aus
        ..addAll((ByteData(4)..setUint32(0, teil.length, Endian.big))
            .buffer
            .asUint8List())
        ..addAll(n)
        ..addAll(box.cipherText)
        ..addAll(box.mac.bytes);
    }

    final zurueck = datei('alt_zurueck.bin');
    await VaultCrypto.decryptFile(datei('alt.bin', aus), zurueck, key);
    expect(zurueck.readAsBytesSync(), inhalt);
  });

  test('der Kopf-Schnelltest kennt beide Fassungen', () async {
    expect(await VaultCrypto.hasValidEncryptedHeader(await verschluesselt(const [1, 2, 3])),
        isTrue);
    expect(
        await VaultCrypto.hasValidEncryptedHeader(
            datei('alt2.bin', [0x50, 0x56, 0x45, 0x31, 0, 0])),
        isTrue);
    expect(await VaultCrypto.hasValidEncryptedHeader(datei('fremd.bin', [1, 2, 3, 4])),
        isFalse);
  });
}
