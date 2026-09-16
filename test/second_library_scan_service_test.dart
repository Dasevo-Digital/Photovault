import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/second_library_scan_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft SecondLibraryScanService gegen eine ECHTE zweite, dateibasierte
/// "Bibliothek" (nicht In-Memory, siehe unten warum) – insbesondere die
/// beiden zentralen Zusicherungen aus dem Klassenkommentar: (1) gesperrte
/// Fotos der zweiten Bibliothek tauchen nie als Treffer auf, (2) die
/// Original-Datei der zweiten Bibliothek bleibt unangetastet (Kopie statt
/// Direktzugriff).
void main() {
  late Directory tempRoot;
  var nextByte = 0;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_second_library_test_');
  });

  tearDown(() {
    tempRoot.deleteSync(recursive: true);
  });

  // Sehr ähnliche ("praktisch identische") bzw. sehr unähnliche Vektoren –
  // die genaue Normierung ist für diesen Test irrelevant, nur der klare
  // Abstand zur Schwelle (Standard 0.92) zählt.
  Float32List aehnlich() => Float32List.fromList(List.filled(512, 0.1));
  Float32List unaehnlich() => Float32List.fromList(List.filled(512, -0.1));

  Future<AssetData> importPhoto(ImportService import, AppDatabase db, Directory incoming, String name) async {
    final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3, nextByte++]);
    final result = await import.importFile(file.path);
    expect(result.outcome, ImportOutcome.imported);
    return (await db.assetById(result.assetId!))!;
  }

  test(
      'findet Übereinstimmungen mit der zweiten Bibliothek, schließt aber deren gesperrte Fotos aus, '
      'und lässt die Original-Datei der zweiten Bibliothek unangetastet', () async {
    // Zweite Bibliothek: ECHTE Datei statt NativeDatabase.memory(), weil
    // loadExternalLibrary die Datei tatsächlich per File.copy() dupliziert –
    // ohne Datei auf der Platte gäbe es nichts zu kopieren, und der Test der
    // Original-Unversehrtheit unten wäre wirkungslos.
    final secondRoot = Directory(p.join(tempRoot.path, 'second'))..createSync();
    final secondDbFile = File(p.join(secondRoot.path, 'library.sqlite'));
    final secondDb = AppDatabase(NativeDatabase(secondDbFile));
    final secondPaths = await StoragePaths.forTesting(Directory(p.join(secondRoot.path, 'library')));
    final secondImport = ImportService(secondDb, secondPaths);
    final secondIncoming = Directory(p.join(tempRoot.path, 'second_incoming'))..createSync();

    final matchendes = await importPhoto(secondImport, secondDb, secondIncoming, 'match.jpg');
    await secondDb.saveEmbedding(matchendes.id, aehnlich());

    final gesperrtes = await importPhoto(secondImport, secondDb, secondIncoming, 'gesperrt.jpg');
    await secondDb.saveEmbedding(gesperrtes.id, aehnlich());
    await secondDb.setAssetsLocked([gesperrtes.id], true);

    final unaehnliches = await importPhoto(secondImport, secondDb, secondIncoming, 'anders.jpg');
    await secondDb.saveEmbedding(unaehnliches.id, unaehnlich());

    final originalBytesVorher = await secondDbFile.readAsBytes();
    await secondDb.close();

    // Eigene Bibliothek.
    final ownDb = AppDatabase(NativeDatabase.memory());
    final ownPaths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'own', 'library')));
    final ownImport = ImportService(ownDb, ownPaths);
    final ownIncoming = Directory(p.join(tempRoot.path, 'own_incoming'))..createSync();

    final eigenes = await importPhoto(ownImport, ownDb, ownIncoming, 'eigenes.jpg');
    await ownDb.saveEmbedding(eigenes.id, aehnlich());

    final ownEmbeddings = await ownDb.allEmbeddings();
    final external = await loadExternalLibrary(secondRoot);
    final matches = await matchAgainstExternalLibrary(
      ownDb: ownDb,
      ownEmbeddings: ownEmbeddings,
      external: external,
    );

    expect(matches, hasLength(1), reason: 'nur das ähnliche, nicht-gesperrte Foto darf als Treffer erscheinen');
    expect(matches.single.ownAsset.id, eigenes.id);
    expect(matches.single.externalAssetId, matchendes.id);
    expect(matches.single.externalFileName, 'match.jpg');
    expect(matches.single.similarity, greaterThan(0.9));
    expect(matches.map((m) => m.externalAssetId), isNot(contains(gesperrtes.id)),
        reason: 'gesperrte Fotos der zweiten Bibliothek dürfen nie als Treffer auftauchen');

    final originalBytesNachher = await secondDbFile.readAsBytes();
    expect(originalBytesNachher, orderedEquals(originalBytesVorher),
        reason: 'die Original-Datei der zweiten Bibliothek darf durch den Vergleich nicht verändert werden');

    await ownDb.close();
  });

  test('wirft einen verständlichen Fehler, wenn der gewählte Ordner keine library.sqlite enthält', () async {
    final leererOrdner = Directory(p.join(tempRoot.path, 'leer'))..createSync();

    await expectLater(
      loadExternalLibrary(leererOrdner),
      throwsA(isA<StateError>()),
    );
  });
}
