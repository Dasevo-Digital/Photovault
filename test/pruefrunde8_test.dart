import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/services/vault_crypto.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:uuid/uuid.dart';

/// Die Befunde der achten Prüfrunde – jeder als Test, der ohne die
/// zugehörige Behebung wieder durchfällt.
void main() {
  group('Verschlüsselung lässt keinen Klartext-Rumpf zurück', () {
    late Directory tempRoot;
    late SecretKey key;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('pruefrunde8_');
      key = await AesGcm.with256bits().newSecretKey();
    });
    tearDown(() => tempRoot.deleteSync(recursive: true));

    /// Ein Klartext über mehrere Blöcke – nur dann ist ein Rumpf überhaupt
    /// unterscheidbar vom Ganzen.
    Uint8List klartext() {
      final b = Uint8List(3 * (1 << 20));
      for (var i = 0; i < b.length; i++) {
        b[i] = i % 251;
      }
      return b;
    }

    test('eine abgeschnittene Datei hinterlässt keine entschlüsselte Teilkopie', () async {
      final quelle = File(p.join(tempRoot.path, 'klar.bin'))
        ..writeAsBytesSync(klartext());
      final chiffre = File(p.join(tempRoot.path, 'chiffre.bin'));
      await VaultCrypto.encryptFile(quelle, chiffre, key);

      final bytes = chiffre.readAsBytesSync();
      final kaputt = File(p.join(tempRoot.path, 'kaputt.bin'))
        ..writeAsBytesSync(bytes.sublist(0, bytes.length - 40));

      final ziel = File(p.join(tempRoot.path, 'ziel.bin'));
      await expectLater(
        VaultCrypto.decryptFile(kaputt, ziel, key),
        throwsA(anything),
      );

      // Der Kern: vor der Behebung lagen hier 2 MiB lesbarer Klartext.
      expect(ziel.existsSync(), isFalse,
          reason: 'Die abgebrochene Entschlüsselung darf nichts liegen lassen.');
    });

    test('ein falscher Schlüssel hinterlässt keine entschlüsselte Teilkopie', () async {
      final quelle = File(p.join(tempRoot.path, 'klar.bin'))
        ..writeAsBytesSync(klartext());
      final chiffre = File(p.join(tempRoot.path, 'chiffre.bin'));
      await VaultCrypto.encryptFile(quelle, chiffre, key);

      final fremd = await AesGcm.with256bits().newSecretKey();
      final ziel = File(p.join(tempRoot.path, 'ziel.bin'));
      await expectLater(
        VaultCrypto.decryptFile(chiffre, ziel, fremd),
        throwsA(anything),
      );
      expect(ziel.existsSync(), isFalse);
    });

    test('eine gelungene Entschlüsselung liefert weiterhin exakt das Original', () async {
      final urbild = klartext();
      final quelle = File(p.join(tempRoot.path, 'klar.bin'))..writeAsBytesSync(urbild);
      final chiffre = File(p.join(tempRoot.path, 'chiffre.bin'));
      final zurueck = File(p.join(tempRoot.path, 'zurueck.bin'));
      await VaultCrypto.encryptFile(quelle, chiffre, key);
      await VaultCrypto.decryptFile(chiffre, zurueck, key);
      expect(zurueck.readAsBytesSync(), equals(urbild));
    });
  });

  group('Gesichts-Neuscan räumt seine Ausschnitte weg', () {
    late Directory tempRoot;
    late AppDatabase db;
    late StoragePaths paths;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('pruefrunde8_faces_');
      db = AppDatabase(NativeDatabase.memory());
      paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    });
    tearDown(() async {
      await db.close();
      tempRoot.deleteSync(recursive: true);
    });

    Future<String> legeGesichtAn(String assetId, {String? personId, bool ignoriert = false}) async {
      final id = const Uuid().v4();
      final rel = paths.faceRelativePath(id);
      final datei = paths.absolute(rel);
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(List<int>.filled(1024, 7));
      await db.insertFace(FacesCompanion.insert(
        id: id,
        assetId: assetId,
        boxX: 0.1,
        boxY: 0.1,
        boxW: 0.2,
        boxH: 0.2,
        cropRelativePath: Value(rel),
        personId: Value(personId),
        isIgnored: Value(ignoriert),
      ));
      return rel;
    }

    test('das Löschen unbenannter Erkennungen meldet ihre Ausschnitte zurück', () async {
      const assetId = 'foto-1';
      final unbenannt = await legeGesichtAn(assetId);
      final zweitesUnbenannt = await legeGesichtAn(assetId);

      final pfade = await db.deleteUnassignedFacesForAsset(assetId);

      expect(pfade.toSet(), equals({unbenannt, zweitesUnbenannt}),
          reason: 'Ohne diese Rückgabe kann der Aufrufer die Dateien nicht wegräumen '
              '– genau so entstanden 17 643 verwaiste Ausschnitte.');
    });

    test('benannte und beiseitegelegte Erkennungen bleiben unangetastet', () async {
      const assetId = 'foto-2';
      final benannt = await legeGesichtAn(assetId, personId: 'person-1');
      final beiseite = await legeGesichtAn(assetId, ignoriert: true);
      final unbenannt = await legeGesichtAn(assetId);

      final pfade = await db.deleteUnassignedFacesForAsset(assetId);

      expect(pfade, equals([unbenannt]));
      expect(pfade, isNot(contains(benannt)));
      expect(pfade, isNot(contains(beiseite)));
      expect((await db.facesForAsset(assetId)).length, 2);
    });

    test('gemeldete Ausschnitte lassen sich über den Bibliothekspfad löschen', () async {
      const assetId = 'foto-3';
      await legeGesichtAn(assetId);
      final pfade = await db.deleteUnassignedFacesForAsset(assetId);
      expect(pfade, hasLength(1));
      expect(paths.absolute(pfade.first).existsSync(), isTrue);

      for (final pfad in pfade) {
        await paths.deletePermanently(pfad);
      }
      expect(paths.absolute(pfade.first).existsSync(), isFalse);
    });

    test('ohne unbenannte Erkennungen wird nichts gemeldet', () async {
      expect(await db.deleteUnassignedFacesForAsset('foto-ohne-gesichter'), isEmpty);
    });
  });

  group('Zwischenspeicher des gesperrten Ordners', () {
    late Directory tempRoot;
    late AppDatabase db;
    late StoragePaths paths;
    late LibraryState library;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('pruefrunde8_cache_');
      db = AppDatabase(NativeDatabase.memory());
      paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
      library = LibraryState()
        ..db = db
        ..paths = paths;
      await library.clearDecryptCache();
    });
    tearDown(() async {
      await library.clearDecryptCache();
      await db.close();
      tempRoot.deleteSync(recursive: true);
    });

    test('eine beschädigte Datei wird nicht als fertige Fassung zwischengespeichert', () async {
      await library.setupVaultPin('4711');

      const rel = 'thumbnails/kaputt.jpg';
      final klar = List<int>.generate(300000, (i) => i % 256);
      final datei = paths.absolute(rel);
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(klar);

      // Verschlüsseln und danach am Ende beschneiden.
      final tmp = File('${datei.path}.enc');
      await VaultCrypto.encryptFile(datei, tmp, (await _schluessel(library))!);
      final bytes = await tmp.readAsBytes();
      await datei.writeAsBytes(bytes.sublist(0, bytes.length - 30));

      await expectLater(library.decryptForViewing(rel), throwsA(anything));
      // Zweiter Versuch: Vor der Behebung kam hier lautlos der Rumpf zurück.
      await expectLater(library.decryptForViewing(rel), throwsA(anything));
    });

    test('eine heile Datei kommt beim zweiten Zugriff aus dem Zwischenspeicher zurück', () async {
      await library.setupVaultPin('4711');

      const rel = 'thumbnails/heil.jpg';
      final klar = List<int>.generate(300000, (i) => i % 256);
      final datei = paths.absolute(rel);
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(klar);

      final tmp = File('${datei.path}.enc');
      await VaultCrypto.encryptFile(datei, tmp, (await _schluessel(library))!);
      await datei.writeAsBytes(await tmp.readAsBytes());

      final erst = await library.decryptForViewing(rel);
      expect(await erst.readAsBytes(), equals(klar));
      final zweit = await library.decryptForViewing(rel);
      expect(zweit.path, equals(erst.path));
      expect(await zweit.readAsBytes(), equals(klar));
    });
  });
}

/// Der Sitzungsschlüssel des gesperrten Ordners ist bewusst privat; für den
/// Test wird er über den Weg beschafft, den auch die App nimmt.
Future<SecretKey?> _schluessel(LibraryState library) async {
  final row = await library.db.privacySettingsRow();
  return VaultCrypto.unwrapMasterKey(
    '4711',
    kdfSalt: row!.kdfSalt!,
    nonce: row.wrappedMasterKeyNonce!,
    wrapped: row.wrappedMasterKey!,
  );
}
