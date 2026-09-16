import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/search_filters.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/services/stammbaum.dart';

/// **Was von der Handarbeit einen Rundlauf übersteht.**
///
/// Der vorhandene Rundlauftest setzt Favorit, Beschreibung, Schlagwörter
/// und ein Album – und alle vier kommen zurück. Genau das war schon in der
/// 16. Prüfrunde die Falle: Ein Test, der nur prüft, was die Umsetzung
/// ohnehin tut, prüft nichts. Dieser hier setzt zuerst das, was in einer
/// gewachsenen Bibliothek die teuerste Handarbeit ist – Namen an
/// Gesichtern, den Stammbaum, Reisen, Aktivitäten, gespeicherte Suchen –
/// und zählt danach nach.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pv_handarbeit_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('Sicherung und Wiederherstellung: was zurückkommt', () async {
    final quelle = AppDatabase(NativeDatabase.memory());
    addTearDown(quelle.close);
    final quellPfade =
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'quelle')));
    final quellImport = ImportService(quelle, quellPfade);
    final quellSicherung = BackupService(quelle, quellPfade);

    final rein = Directory(p.join(temp.path, 'rein'))..createSync();
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      final f = File(p.join(rein.path, 'foto_$i.jpg'))
        ..writeAsBytesSync(List.filled(64, i));
      final r = await quellImport.importFile(f.path);
      expect(r.outcome, ImportOutcome.imported);
      ids.add(r.assetId!);
    }

    // --- Handarbeit, die es sonst nirgends gibt ---
    await quelle.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
    await quelle.createPerson(PeopleCompanion.insert(id: 'p2', name: 'Bernd'));
    await quelle.insertFace(FacesCompanion.insert(
      id: 'f1',
      assetId: ids[0],
      boxX: 0.1,
      boxY: 0.1,
      boxW: 0.2,
      boxH: 0.2,
      personId: const Value('p1'),
    ));
    await quelle.fuegeBeziehungHinzu('p1', 'p2', Verwandtschaft.partner);
    await quelle.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: 'Toskana',
        von: DateTime(2024, 5, 1),
        bis: DateTime(2024, 5, 9),
        angelegtAm: DateTime(2024, 6, 1),
      ),
      [ids[0], ids[1]],
    );
    await quelle.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: 'ak1',
        name: 'Wanderung',
        art: 'wanderung',
        von: DateTime(2024, 5, 3),
        bis: DateTime(2024, 5, 3),
        angelegtAm: DateTime(2024, 6, 1),
      ),
      [ids[1]],
    );
    await quelle.createSavedSearch(
        's1', 'Fünf Sterne', const SearchFilters(minRating: 5));

    // --- Verschlüsselt sichern und in eine leere Bibliothek zurückspielen ---
    final quellZustand = LibraryState()
      ..db = quelle
      ..paths = quellPfade
      ..importService = quellImport
      ..backupService = quellSicherung;
    await quellZustand.setupBackupPassphrase('sicherungs-passwort');

    final ziel = Directory(p.join(temp.path, 'ziel'));
    await quellZustand
        .runManualBackup(ziel.path, encrypt: true)
        .drain<void>();

    final neu = AppDatabase(NativeDatabase.memory());
    addTearDown(neu.close);
    final neuPfade =
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'neu')));
    await BackupService(neu, neuPfade)
        .restoreFromBackup(
            p.join(ziel.path, 'PhotoVault-Backup'), ImportService(neu, neuPfade),
            passphrase: 'sicherungs-passwort')
        .drain<void>();

    Future<int> zahl(String tabelle) async {
      final z = await neu
          .customSelect('SELECT count(*) AS n FROM $tabelle')
          .getSingle();
      return z.read<int>('n');
    }

    expect(await zahl('assets'), 3, reason: 'die Aufnahmen selbst');

    // Und die Handarbeit, die vor der 19. Prüfrunde durchweg bei 0 stand.
    expect(await zahl('people'), 2);
    expect(await zahl('faces'), 1);
    expect(await zahl('person_beziehungen'), 1);
    expect(await zahl('reisen'), 1);
    expect(await zahl('reise_aufnahmen'), 2);
    expect(await zahl('aktivitaeten'), 1);
    expect(await zahl('aktivitaet_aufnahmen'), 1);
    expect(await zahl('saved_searches'), 1);

    // Die Zuordnung läuft über die Prüfsumme, nicht über die Kennung: Der
    // Restore importiert jede Datei neu und vergibt dabei neue Kennungen.
    // Ein Gesicht, das nach dem Zurückspielen an einer anderen Aufnahme
    // hinge, wäre schlimmer als eines, das fehlt.
    // Zweimal zurückspielen darf nichts verdoppeln – wer eine
    // Wiederherstellung abbricht und neu startet, tut genau das.
    await BackupService(neu, neuPfade)
        .restoreFromBackup(
            p.join(ziel.path, 'PhotoVault-Backup'), ImportService(neu, neuPfade),
            passphrase: 'sicherungs-passwort')
        .drain<void>();
    expect(await zahl('people'), 2);
    expect(await zahl('faces'), 1);
    expect(await zahl('reise_aufnahmen'), 2);

    final gesicht = await (neu.select(neu.faces)).getSingle();
    final traeger = await neu.assetById(gesicht.assetId);
    expect(traeger, isNotNull);
    expect(traeger!.originalFileName, 'foto_0.jpg');
    expect(gesicht.personId, 'p1');
  });

  test('die Gesichtsausschnitte werden neu gezeichnet', () async {
    // Abgeleitete Dateien liegen nicht in der Sicherung – gesichert werden
    // Originale. Ohne das Nachzeichnen kämen alle Namen zurück und die
    // Personenübersicht wäre eine Wand aus leeren Kacheln.
    final quelle = AppDatabase(NativeDatabase.memory());
    addTearDown(quelle.close);
    final quellPfade =
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'q2')));
    final quellImport = ImportService(quelle, quellPfade);
    final zustand = LibraryState()
      ..db = quelle
      ..paths = quellPfade
      ..importService = quellImport
      ..backupService = BackupService(quelle, quellPfade);

    final rein = Directory(p.join(temp.path, 'rein2'))..createSync();
    final bild = img.Image(width: 400, height: 300);
    for (var y = 0; y < 300; y++) {
      for (var x = 0; x < 400; x++) {
        bild.setPixelRgb(x, y, x % 256, y % 256, 128);
      }
    }
    final datei = File(p.join(rein.path, 'gruppe.jpg'))
      ..writeAsBytesSync(img.encodeJpg(bild));
    final r = await quellImport.importFile(datei.path);
    expect(r.outcome, ImportOutcome.imported);
    await quelle.markFacesScanned([r.assetId!]);

    await quelle.createPerson(PeopleCompanion.insert(id: 'p9', name: 'Clara'));
    await quelle.insertFace(FacesCompanion.insert(
      id: 'f9',
      assetId: r.assetId!,
      boxX: 0.3,
      boxY: 0.3,
      boxW: 0.2,
      boxH: 0.2,
      personId: const Value('p9'),
      cropRelativePath: Value(quellPfade.faceRelativePath('f9')),
    ));

    await zustand.setupBackupPassphrase('pw');
    final ziel = Directory(p.join(temp.path, 'ziel2'));
    await zustand.runManualBackup(ziel.path, encrypt: true).drain<void>();

    final neu = AppDatabase(NativeDatabase.memory());
    addTearDown(neu.close);
    final neuPfade =
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'neu2')));
    await BackupService(neu, neuPfade)
        .restoreFromBackup(p.join(ziel.path, 'PhotoVault-Backup'),
            ImportService(neu, neuPfade),
            passphrase: 'pw')
        .drain<void>();

    final gesicht = await neu.select(neu.faces).getSingle();
    expect(gesicht.personId, 'p9');
    // Und die Aufnahme gilt wieder als durchsucht: Sonst fände die
    // Hintergrundanalyse dieselben Köpfe ein zweites Mal und legte sie
    // namenlos daneben.
    expect((await neu.assetById(gesicht.assetId))!.facesScanned, isTrue);
    final ausschnitt = neuPfade.absolute(gesicht.cropRelativePath!);
    expect(ausschnitt.existsSync(), isTrue,
        reason: 'ohne die Datei bliebe der Name ohne Bild');
    final gezeichnet = img.decodeImage(ausschnitt.readAsBytesSync())!;
    expect(gezeichnet.width, 160);
    expect(gezeichnet.height, 160);
    // Und die Schärfe steht gleich mit da, statt einer Hintergrundaufgabe
    // zu überlassen, was hier ohnehin schon im Speicher liegt.
    expect(gesicht.schaerfe, isNotNull);
  });
}