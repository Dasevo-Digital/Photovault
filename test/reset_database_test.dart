import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Prüft die eigentliche Löschlogik hinter "Datenbank zurücksetzen"
/// (LibraryState.eraseLibraryDataAt): `library.sqlite` (+ Nebendateien) und
/// der gesamte `library/`-Ordner (Originale, Thumbnails, Papierkorb, …)
/// müssen vollständig verschwinden, während Geschwisterordner außerhalb der
/// Bibliothek (z.B. heruntergeladene KI-Modelle) unangetastet bleiben.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService import;
  var nextByte = 0;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_reset_test_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library_root', 'library')));
    import = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('löscht library.sqlite samt WAL/SHM und den gesamten library-Ordner', () async {
    final libraryRoot = Directory(p.join(tempRoot.path, 'library_root'));

    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
    final photo = File(p.join(incoming.path, 'a.jpg'))..writeAsBytesSync([1, 2, 3, nextByte++]);
    final result = await import.importFile(photo.path);
    expect(result.outcome, ImportOutcome.imported);
    expect(paths.originalsDir.listSync(recursive: true).whereType<File>(), isNotEmpty);

    final dbFile = File(p.join(libraryRoot.path, 'library.sqlite'))..createSync(recursive: true);
    final walFile = File('${dbFile.path}-wal')..createSync();
    final shmFile = File('${dbFile.path}-shm')..createSync();

    // Nachbar-Ordner außerhalb der Bibliothek (steht z.B. für den separaten
    // KI-Modell-Ordner) – darf vom Reset nicht berührt werden.
    final modelsDir = Directory(p.join(tempRoot.path, 'models'))..createSync(recursive: true);
    final modelFile = File(p.join(modelsDir.path, 'yunet.onnx'))..writeAsBytesSync([9, 9, 9]);

    await LibraryState.eraseLibraryDataAt(libraryRoot);

    expect(dbFile.existsSync(), isFalse);
    expect(walFile.existsSync(), isFalse);
    expect(shmFile.existsSync(), isFalse);
    expect(Directory(p.join(libraryRoot.path, 'library')).existsSync(), isFalse);
    expect(modelFile.existsSync(), isTrue);
  });

  test('funktioniert auch, wenn noch keine Datenbank-/WAL-Dateien existieren', () async {
    final emptyRoot = Directory(p.join(tempRoot.path, 'nie_verwendet'))..createSync(recursive: true);
    await LibraryState.eraseLibraryDataAt(emptyRoot);
    expect(emptyRoot.existsSync(), isTrue); // das Wurzelverzeichnis selbst bleibt bestehen
  });
}
