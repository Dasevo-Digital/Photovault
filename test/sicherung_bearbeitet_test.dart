import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Eine bearbeitete Aufnahme behält in der unverschlüsselten Sicherung
/// ihren Pfad – und muss trotzdem neu ins Ziel (#251).
///
/// Bis 3.49.7 genügte „dort liegt eine Datei“: Im Ziel blieb die alte, die
/// Beilage nannte die neue Prüfsumme, die Probe scheiterte, und eine
/// Wiederherstellung brachte das Foto weder alt noch neu zurück.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late BackupService dienst;
  late Directory ziel;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_sicherung_bearbeitet_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    dienst = BackupService(db, pfade);
    final importe = ImportService(db, pfade);
    for (var i = 0; i < 4; i++) {
      final f = File(p.join(temp.path, 'bild-$i.jpg'))
        ..writeAsBytesSync(List.filled(64 * 1024, i));
      await importe.importFile(f.path);
    }
    ziel = Directory(p.join(temp.path, 'stick'))..createSync();
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Directory originale() =>
      Directory(p.join(ziel.path, 'PhotoVault-Backup', 'originals'));

  File imZiel(AssetData a) => File(
    p.join(originale().path, a.relativePath.replaceFirst('originals/', '')),
  );

  /// Wie der Editor ein JPEG am Ort ersetzt: neue Bytes unter demselben
  /// Pfad, dann Pfad und Prüfsumme in der Datenbank. [mitGroesse] wie seit
  /// 3.49.7; vorher blieb die alte Grösse stehen.
  Future<List<int>> bearbeite(
    AssetData a,
    int fuellung, {
    int laenge = 70 * 1024,
    bool mitGroesse = true,
  }) async {
    final neu = List<int>.filled(laenge, fuellung);
    await pfade.absolute(a.relativePath).writeAsBytes(neu);
    await db.setEditedAssetFile(
      a.id,
      relativePath: a.relativePath,
      checksum: sha256.convert(neu).toString(),
      fileSizeBytes: mitGroesse ? neu.length : null,
    );
    return neu;
  }

  Future<List<AssetData>> stelleWiederHer() async {
    final db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    final pfade2 = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'zurueck')),
    );
    final verlauf = await BackupService(db2, pfade2)
        .restoreFromBackup(
          p.join(ziel.path, 'PhotoVault-Backup'),
          ImportService(db2, pfade2),
        )
        .toList();
    expect(verlauf.last.wiederherstellung!.erfolgreich, isTrue);
    return db2.select(db2.assets).get();
  }

  test('nach dem Bearbeiten kommt die neue Fassung ins Ziel', () async {
    await dienst.performBackup(ziel.path).drain<void>();
    final a = (await db.select(db.assets).get()).first;
    final neu = await bearbeite(a, 200);

    final verlauf = await dienst.performBackup(ziel.path).toList();

    expect(await imZiel(a).readAsBytes(), neu);
    expect(verlauf.last.wiederherstellungsprobe?.erfolgreich, isTrue);
    // Das alte Original gibt es nirgends mehr – also bleibt es im Ziel.
    final beiseite = originale()
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('.vorher-'))
        .toList();
    expect(beiseite, hasLength(1));
    expect(beiseite.single.lengthSync(), 64 * 1024);

    final zurueck = await stelleWiederHer();
    expect(zurueck, hasLength(4));
    expect(
      zurueck.map((x) => x.checksum),
      contains(sha256.convert(neu).toString()),
    );
  });

  test(
    'eine Sicherung, die schon falsch steht, heilt der nächste Lauf',
    () async {
      await dienst.performBackup(ziel.path).drain<void>();
      final a = (await db.select(db.assets).get()).first;
      // Wie vor 3.49.7: Grösse in der Datenbank nicht nachgeführt …
      final neu = await bearbeite(a, 201, mitGroesse: false);
      // … und eine Beilage, die schon die neue Prüfsumme nennt, weil ein
      // Lauf danach nichts kopierte und nur sie neu schrieb.
      final beilage = File(
        p.join(ziel.path, 'PhotoVault-Backup', 'metadata.json'),
      );
      final j = jsonDecode(beilage.readAsStringSync()) as Map<String, dynamic>;
      for (final e in (j['assets'] as List).cast<Map<String, dynamic>>()) {
        if (e['checksum'] == a.checksum) {
          e['checksum'] = sha256.convert(neu).toString();
        }
      }
      beilage.writeAsStringSync(jsonEncode(j));

      final verlauf = await dienst.performBackup(ziel.path).toList();

      expect(await imZiel(a).readAsBytes(), neu);
      expect(verlauf.last.wiederherstellungsprobe?.erfolgreich, isTrue);
      expect(await stelleWiederHer(), hasLength(4));
    },
  );

  test('gleiche Grösse: die vorige Beilage verrät die Änderung', () async {
    await dienst.performBackup(ziel.path).drain<void>();
    final a = (await db.select(db.assets).get()).first;
    final neu = await bearbeite(a, 202, laenge: 64 * 1024);

    await dienst.performBackup(ziel.path).drain<void>();

    expect(await imZiel(a).readAsBytes(), neu);
  });

  test('liegt das alte Original als Variante vor, wird nur ersetzt', () async {
    await dienst.performBackup(ziel.path).drain<void>();
    final a = (await db.select(db.assets).get()).first;
    final alt = await pfade.absolute(a.relativePath).readAsBytes();
    await bearbeite(a, 203);
    // Wie seit 3.49.7: Das Original ist eine eigene Aufnahme.
    final kopie = File(p.join(temp.path, 'original.jpg'))
      ..writeAsBytesSync(alt);
    await ImportService(db, pfade).importFile(kopie.path);

    await dienst.performBackup(ziel.path).drain<void>();

    expect(
      originale()
          .listSync(recursive: true)
          .where((f) => f.path.contains('.vorher-')),
      isEmpty,
    );
  });

  test('ein unveränderter Bestand wird nicht neu geschrieben', () async {
    await dienst.performBackup(ziel.path).drain<void>();
    final dateien = {
      for (final f in originale().listSync(recursive: true).whereType<File>())
        f.path: f.lastModifiedSync(),
    };

    await dienst.performBackup(ziel.path).drain<void>();

    for (final MapEntry(key: pfad, value: zeit) in dateien.entries) {
      expect(File(pfad).lastModifiedSync(), zeit, reason: pfad);
    }
  });
}
