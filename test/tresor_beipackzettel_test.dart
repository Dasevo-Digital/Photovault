import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Der XMP-Beipackzettel neben dem Foto.
///
/// **Der Befund der 18. Prüfrunde.** *Werkzeuge → XMP-Beilagen schreiben*
/// legt neben jedes Foto eine `.xmp`-Datei mit Beschreibung,
/// Schlagwörtern, Bewertung, Farbmarke und Ort – im Klartext, damit
/// Lightroom und darktable sie lesen können. Beim Sperren wurde sie nicht
/// mitverschlüsselt: Das Original wurde zu Chiffrat, der Zettel daneben
/// blieb lesbar. Damit stand genau das offen da, wovor der gesperrte
/// Ordner schützen soll.
///
/// Beim endgültigen Löschen blieb sie ebenfalls liegen – für immer, denn
/// die Datenbankzeile war weg und niemand wusste mehr von der Datei.
///
/// Beides hatte dieselbe Ursache: **dieselbe Liste von Dateiarten, an
/// drei Stellen von Hand gepflegt.** Sie steht jetzt einmal in
/// [LibraryState.dateienVon].
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bib;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_beipack_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
    bib = LibraryState()
      ..db = db
      ..paths = pfade;
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// Ein Foto mit allem, was auf den Beipackzettel gehört.
  Future<AssetData> foto() async {
    final eingang = Directory(p.join(wurzel.path, 'ein'))..createSync();
    final datei = File(p.join(eingang.path, 'geheim.jpg'))
      ..writeAsBytesSync(List<int>.generate(2000, (i) => i % 256));
    final erg = await ImportService(db, pfade).importFile(datei.path);
    final id = erg.assetId!;
    await db.setDescription(id, 'Termin beim Anwalt am 3.9.');
    await db.tagAsset(id, 'Scheidung');
    await db.setLocation(id, 52.5163, 13.3777);
    return (await db.assetById(id))!;
  }

  File beipackzettel(AssetData asset) =>
      pfade.absolute(pfade.xmpSidecarPath(asset.relativePath));

  test('Sperren verschlüsselt den Beipackzettel mit', () async {
    final asset = await foto();
    await bib.writeXmpSidecars().drain<void>();
    final zettel = beipackzettel(asset);
    expect(zettel.existsSync(), isTrue, reason: 'die Beilage muss erst da sein');
    expect(zettel.readAsStringSync(), contains('Termin beim Anwalt'));

    await bib.setupVaultPin('1234');
    await bib.lockAsset(asset);

    // Das Original ist Chiffrat – und der Zettel daneben jetzt auch.
    // Als Bytes gelesen, nicht als Text: Chiffrat ist kein UTF-8, und ein
    // Lesefehler wäre eine unklarere Auskunft als ein Vergleich.
    final roh = zettel.readAsBytesSync();
    expect(String.fromCharCodes(roh.take(4)), 'PVE2',
        reason: 'die Kennung des Tresorformats');
    expect(String.fromCharCodes(roh), isNot(contains('Termin beim Anwalt')),
        reason: 'die Beschreibung stand im Klartext neben dem Chiffrat');
    expect(String.fromCharCodes(roh), isNot(contains('Scheidung')));
  });

  test('Entsperren stellt ihn wieder lesbar her', () async {
    final asset = await foto();
    await bib.writeXmpSidecars().drain<void>();
    final vorher = beipackzettel(asset).readAsBytesSync();

    await bib.setupVaultPin('1234');
    await bib.lockAsset(asset);
    await bib.unlockAsset((await db.assetById(asset.id))!);

    expect(beipackzettel(asset).readAsBytesSync(), vorher,
        reason: 'Byte für Byte dasselbe');
  });

  test('endgültiges Löschen nimmt ihn mit', () async {
    // Sonst bleibt der Zettel für immer liegen: Die Datenbankzeile ist
    // weg, und niemand weiss mehr von der Datei.
    final asset = await foto();
    await bib.writeXmpSidecars().drain<void>();
    expect(beipackzettel(asset).existsSync(), isTrue);

    await bib.deleteAssetFilesFromDisk(asset);

    expect(pfade.absolute(asset.relativePath).existsSync(), isFalse);
    expect(beipackzettel(asset).existsSync(), isFalse);
  });

  test('ohne Beipackzettel geht alles seinen Gang', () async {
    // Die meisten Bibliotheken haben keine Beilagen. Eine Datei, die es
    // nicht gibt, darf weder das Sperren noch das Löschen stören.
    final asset = await foto();
    await bib.setupVaultPin('1234');
    await bib.lockAsset(asset);
    await bib.unlockAsset((await db.assetById(asset.id))!);
    await bib.deleteAssetFilesFromDisk((await db.assetById(asset.id))!);
    expect(beipackzettel(asset).existsSync(), isFalse);
  });

  test('die Liste kennt jede Dateiart', () async {
    // Die Gegenprobe zur Ursache: Dass die drei Stellen dieselbe Liste
    // benutzen, hilft nur, solange die Liste vollständig ist.
    final asset = await foto();
    final dateien = await bib.dateienVon(asset);
    expect(dateien, contains(asset.relativePath));
    expect(dateien, contains(pfade.xmpSidecarPath(asset.relativePath)));
    // Nichts steht doppelt drin – sonst würde eine Datei zweimal
    // verschlüsselt, und das zweite Mal machte aus Chiffrat Unsinn.
    expect(dateien.length, dateien.toSet().length);
  });
}
