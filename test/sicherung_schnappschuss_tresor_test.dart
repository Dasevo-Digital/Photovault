import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/services/vault_crypto.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:sqlite3/sqlite3.dart';

/// **Der gesperrte Ordner endet nicht an `metadata.json`.**
///
/// Die 16. Prüfrunde nahm die gesperrten Aufnahmen aus dem Metadaten-Export
/// heraus, weil dort Dateiname, Beschreibung und Schlagwörter im Klartext in
/// einem Cloud-Ordner landeten. Zwanzig Zeilen weiter schreibt die
/// automatische Sicherung einen Schnappschuss der kompletten Datenbank – und
/// darin standen dieselben Zeilen weiter, samt der Namen der Personen auf
/// diesen Fotos. Verschlüsselt, aber mit der Sicherungs-Passphrase und nicht
/// mit dem PIN.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pv_schnapp_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('der Schnappschuss der automatischen Sicherung kennt gesperrte Fotos nicht',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pfade = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
    final imp = ImportService(db, pfade);
    final library = LibraryState()
      ..db = db
      ..paths = pfade
      ..importService = imp
      ..backupService = BackupService(db, pfade);

    final rein = Directory(p.join(temp.path, 'rein'))..createSync();
    final offen = await imp.importFile(
        (File(p.join(rein.path, 'urlaub.jpg'))..writeAsBytesSync([1, 2, 3])).path);
    final geheim = await imp.importFile(
        (File(p.join(rein.path, 'steuerbescheid.jpg'))..writeAsBytesSync([4, 5, 6])).path);

    await db.setDescription(geheim.assetId!, 'Kontostand');
    await db.tagAsset(geheim.assetId!, 'privat');
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
    await db.insertFace(FacesCompanion.insert(
      id: 'f1',
      assetId: geheim.assetId!,
      boxX: 0.1,
      boxY: 0.1,
      boxW: 0.2,
      boxH: 0.2,
      personId: const Value('p1'),
    ));

    // Sperren – der Weg, den auch die Oberfläche nimmt.
    await library.setupVaultPin('1234');
    await library.lockAsset((await db.assetById(geheim.assetId!))!);

    await library.setupBackupPassphrase('sicherungs-passwort');
    final ziel = Directory(p.join(temp.path, 'ziel'));
    await library.runAutoBackupNow(ziel.path).drain<void>();

    // Entschlüsseln und nachsehen.
    final zeile = (await db.backupSettingsRow())!;
    final schluessel = await VaultCrypto.unwrapMasterKey(
      'sicherungs-passwort',
      kdfSalt: zeile.kdfSalt!,
      nonce: zeile.wrappedMasterKeyNonce!,
      wrapped: zeile.wrappedMasterKey!,
    );
    final chiffrat = File(p.join(
        ziel.path, 'PhotoVault-AutoBackup', 'library.sqlite.enc'));
    expect(await chiffrat.exists(), isTrue);
    final klar = File(p.join(temp.path, 'schnappschuss.sqlite'));
    await VaultCrypto.decryptFile(chiffrat, klar, schluessel);

    final schnappschuss = sqlite3.open(klar.path);
    addTearDown(schnappschuss.close);

    final namen = schnappschuss
        .select('SELECT original_file_name FROM assets')
        .map((z) => z['original_file_name'] as String)
        .toList();
    expect(namen, ['urlaub.jpg'],
        reason: 'die gesperrte Aufnahme darf nicht im Schnappschuss stehen');

    // Und alles, was an ihr hing, ebenso wenig.
    expect(
        schnappschuss.select('SELECT * FROM faces').length, 0,
        reason: 'ein Gesicht verrät den Namen der Person auf dem Foto');
    expect(
        schnappschuss
            .select('SELECT * FROM asset_tags WHERE asset_id = ?',
                [geheim.assetId!]).length,
        0);

    // Der Rest bleibt: Ein Schnappschuss, der die offenen Fotos verlöre,
    // wäre die schlechtere Hälfte beider Welten.
    expect(schnappschuss.select('SELECT * FROM people').length, 1);
    expect(
        schnappschuss.select(
            'SELECT * FROM assets WHERE id = ?', [offen.assetId!]).length,
        1);

    // Und im Rohtext der entschlüsselten Datei ebenso wenig – ein DELETE
    // gibt die Seite frei, überschreibt sie aber nicht.
    final roh = String.fromCharCodes(await klar.readAsBytes());
    expect(roh.contains('steuerbescheid.jpg'), isFalse);
    expect(roh.contains('Kontostand'), isFalse);
  });

  test('der Klartext steht auch nicht mehr in den freien Seiten', () async {
    // Ein DELETE gibt die Seiten frei, überschreibt sie aber nicht. Ohne
    // das VACUUM danach liesse sich der Dateiname mit einem Hexeditor
    // weiterhin lesen, obwohl keine Abfrage ihn mehr findet.
    final quelle = File(p.join(temp.path, 'roh.sqlite'));
    final db = sqlite3.open(quelle.path);
    db.execute('CREATE TABLE assets (id TEXT, original_file_name TEXT, is_locked INT)');
    db.execute('CREATE TABLE faces (id TEXT, asset_id TEXT)');
    db.execute("INSERT INTO assets VALUES ('a', 'steuerbescheid-2019.jpg', 1)");
    db.execute("INSERT INTO faces VALUES ('f', 'a')");
    db.close();

    entferneGesperrteAus(quelle.path);

    final roh = String.fromCharCodes(await quelle.readAsBytes());
    expect(roh.contains('steuerbescheid-2019.jpg'), isFalse);
  });
}
