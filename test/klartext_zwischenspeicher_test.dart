import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/vault_crypto.dart';
import 'package:photo_vault/state/library_state.dart';

/// Der Klartext-Zwischenspeicher des gesperrten Ordners (#434): Er wird
/// nicht nach jeder Entschlüsselung ganz durchgezählt, und was eben
/// angesehen wurde, fliegt nicht bei der nächsten Miniatur heraus.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;
  late _ZaehlenderOrdner klartext;
  late SecretKey schluessel;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_klartext_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    klartext = _ZaehlenderOrdner(Directory(p.join(temp.path, 'klartext')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..klartextOrdnerFuerTests = klartext;
    await library.setupVaultPin('4711');
    schluessel = (await _schluessel(library))!;
  });

  tearDown(() async {
    await library.clearDecryptCache();
    await db.close();
    await temp.delete(recursive: true);
  });

  /// Eine verschlüsselte Datei der Bibliothek mit [bytes] Bytes.
  Future<String> verschluesselt(String name, int bytes) async {
    final rel = 'thumbnails/$name';
    final klar = File(p.join(temp.path, name))
      ..writeAsBytesSync(List<int>.generate(bytes, (i) => i % 251));
    final ziel = paths.absolute(rel)..parent.createSync(recursive: true);
    await VaultCrypto.encryptFile(klar, ziel, schluessel);
    return rel;
  }

  test('der Ordner wird einmal gezählt, nicht nach jeder Miniatur', () async {
    final pfade = [
      for (var i = 0; i < 20; i++) await verschluesselt('m$i.jpg', 1000),
    ];
    for (final rel in pfade) {
      await library.decryptForViewing(rel);
    }
    expect(
      klartext.auflistungen,
      lessThanOrEqualTo(1),
      reason: 'bisher eine Auflistung samt Abfrage jeder Datei je Miniatur',
    );
  });

  test('ein grosses Video bleibt über die nächste Miniatur hinaus', () async {
    library.zwischenspeicherGrenze = 100 * 1024;
    final video = await library.decryptForViewing(
      await verschluesselt('video.mp4', 300 * 1024),
    );
    expect(video.existsSync(), isTrue);

    await library.decryptForViewing(await verschluesselt('m.jpg', 1000));
    expect(
      video.existsSync(),
      isTrue,
      reason: 'bisher fiel es beim nächsten Entschlüsseln heraus',
    );
  });

  test(
    'über der Grenze weicht, was am längsten nicht gebraucht wurde',
    () async {
      library.zwischenspeicherGrenze = 30 * 1000;
      final pfade = [
        for (var i = 0; i < 20; i++) await verschluesselt('m$i.jpg', 2000),
      ];
      final dateien = [
        for (final rel in pfade) await library.decryptForViewing(rel),
      ];
      // m0 wird noch einmal angesehen – es bleibt, m1 nicht.
      await library.decryptForViewing(pfade[0]);
      await library.decryptForViewing(await verschluesselt('neu.jpg', 2000));

      final summe = klartext.echt.listSync().whereType<File>().fold<int>(
        0,
        (s, f) => s + f.lengthSync(),
      );
      expect(summe, lessThanOrEqualTo(30 * 1000));
      expect(dateien[0].existsSync(), isTrue);
      expect(dateien[1].existsSync(), isFalse);
      expect(dateien.last.existsSync(), isTrue);
    },
  );
}

/// Der Sitzungsschlüssel des gesperrten Ordners, über den Weg der App.
Future<SecretKey?> _schluessel(LibraryState library) async {
  final row = await library.db.privacySettingsRow();
  return VaultCrypto.unwrapMasterKey(
    '4711',
    kdfSalt: row!.kdfSalt!,
    nonce: row.wrappedMasterKeyNonce!,
    wrapped: row.wrappedMasterKey!,
  );
}

/// Zählt, wie oft der Klartext-Ordner aufgelistet wird.
class _ZaehlenderOrdner implements Directory {
  _ZaehlenderOrdner(this.echt);

  final Directory echt;
  var auflistungen = 0;

  @override
  String get path => echt.path;

  @override
  Future<bool> exists() => echt.exists();

  @override
  Future<Directory> create({bool recursive = false}) =>
      echt.create(recursive: recursive);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      echt.delete(recursive: recursive);

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    auflistungen++;
    return echt.list(recursive: recursive, followLinks: followLinks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
