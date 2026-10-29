import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';

void main() {
  late Directory temp, ziel, probeTemp;
  late AppDatabase db;
  late BackupService dienst;
  late SecretKey key;
  late String wurzel;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_probe_regression_');
    ziel = Directory(p.join(temp.path, 'ziel'));
    probeTemp = await Directory(p.join(temp.path, 'proben')).create();
    db = AppDatabase(NativeDatabase.memory());
    final pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    dienst = BackupService(db, pfade);
    final w = await VaultCrypto.createMasterKey('synthetische-passphrase');
    key = w.masterKey;
    await db.saveBackupKey(
      kdfSalt: w.kdfSalt,
      nonce: w.nonce,
      wrapped: w.wrapped,
    );
    final importe = ImportService(db, pfade);
    for (var i = 0; i < 4; i++) {
      final f = File(p.join(temp.path, 'bild-$i.jpg'))
        ..writeAsBytesSync([1, 2, 3, i]);
      final r = await importe.importFile(f.path);
      await db.setDescription(r.assetId!, 'Beschreibung $i');
      await db.tagAsset(r.assetId!, 'probe-$i');
    }
    final fotos = await db.select(db.assets).get();
    await db.fuehreAus(AlbumAnlegen('album', 'Testalbum', DateTime(2026)));
    await db.fuehreAus(AlbumFuellen('album', fotos.map((a) => a.id).toList()));
    wurzel = p.join(ziel.path, 'PhotoVault-AutoBackup');
    await dienst.performAutoBackup(ziel.path, key).drain<void>();
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test(
    'automatische Probe stellt Metadaten und Alben wieder her und speichert den Nachweis',
    () async {
      final bericht = await dienst.letzteProbe(wurzel);
      expect(bericht?.erfolgreich, isTrue);
      expect(bericht?.datenbank, isTrue);
      expect(bericht?.originale, 3);
      expect(bericht?.gesamt, 4);
      final inhalt = File(
        p.join(wurzel, BackupWiederherstellungsprobe.probeDateiname),
      ).readAsStringSync();
      expect(inhalt, isNot(contains('Beschreibung')));
      expect(inhalt, isNot(contains('bild-')));
      expect(inhalt, isNot(contains('synthetische-passphrase')));
    },
  );

  test(
    'rotierende Stichprobe, isolierte Dateien und unveränderte aktive Bibliothek',
    () async {
      final vorher = (await db.select(db.assets).get())
          .map((a) => a.toJson())
          .toList();
      final start = (await dienst.letzteProbe(wurzel))!.position;
      final result = await dienst.pruefeWiederherstellung(
        wurzel,
        schluessel: key,
        anzahl: 1,
        zwischenlager: probeTemp,
      );
      expect(result.erfolgreich, isTrue);
      expect(result.position, (start + 1) % 4);
      expect(await probeTemp.list().toList(), isEmpty);
      expect(
        (await db.select(db.assets).get()).map((a) => a.toJson()).toList(),
        vorher,
      );
    },
  );

  test(
    'beschädigter Schnappschuss wird nicht durch Originale mit gültiger Prüfsumme verdeckt',
    () async {
      final erfolg = (await dienst.letzteProbe(wurzel))!.letzterErfolg;
      File(p.join(wurzel, 'library.sqlite.enc')).writeAsBytesSync([1, 2, 3]);
      final result = await dienst.pruefeWiederherstellung(
        wurzel,
        schluessel: key,
        zwischenlager: probeTemp,
      );
      expect(result.erfolgreich, isFalse);
      expect(result.letzterErfolg, erfolg);
      expect(await probeTemp.list().toList(), isEmpty);
    },
  );

  test(
    'fehlendes Original, falscher Schlüssel und Platzbudget ergeben keinen Erfolg',
    () async {
      final zuGross = await dienst.pruefeWiederherstellung(
        wurzel,
        schluessel: key,
        maxBytes: 1,
        zwischenlager: probeTemp,
      );
      expect(zuGross.erfolgreich, isFalse);
      expect(zuGross.fehler, 'pv_probe_stichprobe_zu_gross');
      final falsch = await dienst.pruefeWiederherstellung(
        wurzel,
        schluessel: SecretKey(List.filled(32, 0)),
        zwischenlager: probeTemp,
      );
      expect(falsch.erfolgreich, isFalse);
      for (final f in Directory(
        p.join(wurzel, VerschluesselteNamen.ordner),
      ).listSync()) {
        f.deleteSync();
      }
      final fehlt = await dienst.pruefeWiederherstellung(
        wurzel,
        schluessel: key,
        zwischenlager: probeTemp,
      );
      expect(fehlt.erfolgreich, isFalse);
      expect(await probeTemp.list().toList(), isEmpty);
    },
  );

  test('Metadatenverlust wird auch bei lesbarem Original erkannt', () async {
    final f = File(p.join(wurzel, 'metadata.json'));
    final klar = File(p.join(temp.path, 'manipuliert.json'));
    await VaultCrypto.decryptFile(f, klar, key);
    final j = jsonDecode(klar.readAsStringSync()) as Map;
    (j['assets'] as List).first['tags'] = [42];
    klar.writeAsStringSync(jsonEncode(j));
    await VaultCrypto.encryptFile(klar, f, key);
    final result = await dienst.pruefeWiederherstellung(
      wurzel,
      schluessel: key,
      zwischenlager: probeTemp,
    );
    expect(result.erfolgreich, isFalse);
    expect(await probeTemp.list().toList(), isEmpty);
  });

  test(
    'Verzeichnisverweise verlassen das gewählte Sicherungsziel nicht',
    () async {
      if (Platform.isWindows) return;
      final meta = File(p.join(wurzel, 'metadata.json'));
      final extern = File(p.join(temp.path, 'aussen.json'));
      await meta.rename(extern.path);
      await Link(meta.path).create(extern.path);
      final result = await dienst.pruefeWiederherstellung(
        wurzel,
        schluessel: key,
        zwischenlager: probeTemp,
      );
      expect(result.erfolgreich, isFalse);
      expect(result.fehler, 'pv_probe_pfad');
      expect(await probeTemp.list().toList(), isEmpty);
    },
  );
  test(
    'verfügbare Schlüssel ersetzen keinen mitgesicherten Umschlag und keine Passphraseprüfung',
    () async {
      expect((await dienst.letzteProbe(wurzel))!.passphraseGeprueft, isFalse);
      final manuell = await dienst.pruefeWiederherstellung(
        wurzel,
        passphrase: 'synthetische-passphrase',
        zwischenlager: probeTemp,
      );
      expect(manuell.erfolgreich, isTrue);
      expect(manuell.passphraseGeprueft, isTrue);
      final falsch = await dienst.pruefeWiederherstellung(
        wurzel,
        passphrase: 'falsche-passphrase',
        zwischenlager: probeTemp,
      );
      expect(falsch.erfolgreich, isFalse);
      expect(
        falsch.letzterErfolg!.isAtSameMomentAs(manuell.letzterErfolg!),
        isTrue,
      );
      final keyDatei = File(p.join(wurzel, 'vault.key'));
      await keyDatei.writeAsString('{}');
      expect(
        (await dienst.pruefeWiederherstellung(
          wurzel,
          schluessel: key,
          zwischenlager: probeTemp,
        )).erfolgreich,
        isFalse,
      );
      await keyDatei.delete();
      expect(
        (await dienst.pruefeWiederherstellung(
          wurzel,
          schluessel: key,
          zwischenlager: probeTemp,
        )).erfolgreich,
        isFalse,
      );
      expect(await probeTemp.list().toList(), isEmpty);
    },
  );
}
