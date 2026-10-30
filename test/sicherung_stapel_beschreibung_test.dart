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

/// Was an der Aufnahme selbst von Hand gesetzt wurde, kommt mit einer
/// Sicherung zurück (#244): Serien und Variantenstapel samt Titelbild, eine
/// von Hand geschriebene Bildbeschreibung und der Ausschluss von der
/// Gesichtssuche. Vorher waren nach einer Wiederherstellung alle Stapel
/// aufgelöst, und die Bilderkennung schrieb die Beschreibung neu.
void main() {
  late Directory temp;
  late AppDatabase db;
  late BackupService dienst;
  late List<String> ids;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_stapel_beschreibung_');
    db = AppDatabase(NativeDatabase.memory());
    final pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    dienst = BackupService(db, pfade);
    final importe = ImportService(db, pfade);
    ids = [];
    for (var i = 0; i < 6; i++) {
      final f = File(p.join(temp.path, 'bild-$i.jpg'))
        ..writeAsBytesSync(List.filled(1024, i));
      ids.add((await importe.importFile(f.path)).assetId!);
    }
    await db.fuehreAus(SerieBilden('serie-1', ids.sublist(0, 3), ids[1]));
    await db.fuehreAus(VariantenBilden('v1', ids.sublist(3, 5), ids[4]));
    await db.fuehreAus(
      BildbeschreibungSetzen(ids[5], 'Am Hafen, von Hand', deutsch: true),
    );
    await db.fuehreAus(GesichtssucheAusnehmen(ids[5], true));
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  /// Stellt [wurzel] in einer leeren Bibliothek wieder her und liefert deren
  /// Aufnahmen nach der Kennung der Quelle.
  Future<Map<String, AssetData>> zurueck(
    String wurzel, {
    SecretKey? schluessel,
  }) async {
    final ziel = AppDatabase(NativeDatabase.memory());
    addTearDown(ziel.close);
    final pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'ziel_lib')),
    );
    final verlauf = await BackupService(ziel, pfade)
        .restoreFromBackup(
          wurzel,
          ImportService(ziel, pfade),
          entschluesselungsschluessel: schluessel,
        )
        .toList();
    expect(verlauf.last.wiederherstellung?.probleme, isEmpty);
    final quelle = {
      for (final a in await db.select(db.assets).get()) a.checksum: a.id,
    };
    return {
      for (final a in await ziel.select(ziel.assets).get())
        quelle[a.checksum]!: a,
    };
  }

  void pruefe(Map<String, AssetData> z) {
    for (final id in ids.sublist(0, 3)) {
      expect(z[id]!.stackId, 'serie-1');
    }
    expect(z[ids[1]]!.isStackCover, isTrue);
    expect(z[ids[1]]!.stackSize, 3);
    expect(z[ids[0]]!.isStackCover, isFalse);
    for (final id in ids.sublist(3, 5)) {
      expect(z[id]!.stackId, variantenstapelId('v1'));
    }
    expect(z[ids[4]]!.isStackCover, isTrue);
    expect(z[ids[5]]!.stackId, isNull);
    expect(z[ids[5]]!.aiCaptionDe, 'Am Hafen, von Hand');
    expect(z[ids[5]]!.aiCaptionEdited, isTrue);
    expect(z[ids[5]]!.faceScanExcluded, isTrue);
    expect(z[ids[0]]!.faceScanExcluded, isFalse);
    expect(z[ids[0]]!.aiCaptionEdited, isFalse);
  }

  test('von Hand, unverschlüsselt: alles kommt zurück', () async {
    final ziel = Directory(p.join(temp.path, 'stick'))..createSync();
    final verlauf = await dienst.performBackup(ziel.path).toList();
    expect(verlauf.last.wiederherstellungsprobe?.erfolgreich, isTrue);

    pruefe(await zurueck(p.join(ziel.path, 'PhotoVault-Backup')));
  });

  test('automatisch: die Beilage aus dem Schnappschuss trägt es', () async {
    final w = await VaultCrypto.createMasterKey('synthetische-passphrase');
    await db.saveBackupKey(
      kdfSalt: w.kdfSalt,
      nonce: w.nonce,
      wrapped: w.wrapped,
    );
    final ziel = Directory(p.join(temp.path, 'cloud'))..createSync();
    BackupProbeErgebnis? probe;
    await for (final f in dienst.performAutoBackup(ziel.path, w.masterKey)) {
      probe = f.wiederherstellungsprobe ?? probe;
    }
    expect(probe?.erfolgreich, isTrue, reason: '${probe?.fehler}');

    pruefe(
      await zurueck(
        p.join(ziel.path, 'PhotoVault-AutoBackup'),
        schluessel: w.masterKey,
      ),
    );
  });

  test(
    'dieselbe Bibliothek zurückgespielt: Stapel bleiben, wie sie sind',
    () async {
      final ziel = Directory(p.join(temp.path, 'stick'))..createSync();
      await dienst.performBackup(ziel.path).drain<void>();
      // Inzwischen eine andere Titelseite gewählt.
      await db.fuehreAus(
        VariantenHauptbildSetzen(variantenstapelId('v1'), ids[3]),
      );

      await dienst
          .restoreFromBackup(
            p.join(ziel.path, 'PhotoVault-Backup'),
            ImportService(
              db,
              await StoragePaths.forTesting(
                Directory(p.join(temp.path, 'library')),
              ),
            ),
          )
          .drain<void>();

      final d = (await db.assetById(ids[3]))!,
          e = (await db.assetById(ids[4]))!;
      expect(d.isStackCover, isTrue);
      expect(e.isStackCover, isFalse);
    },
  );
}
