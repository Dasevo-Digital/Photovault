import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/modell_halter.dart';
import 'package:photo_vault/services/restore_queue_service.dart';
import 'package:photo_vault/services/restore_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Audit-Fund: Ein Ladefehler des Restaurierungs-Modells (z.B. eine
/// beschädigte Datei) verließ RestoreQueueService._process() unbehandelt,
/// bevor der Job auf "failed" gesetzt werden konnte – die Exception stoppte
/// die Warteschlange dauerhaft (das nachfolgende Anstoßen des nächsten
/// Auftrags wurde nie erreicht). Dieser Test stellt sicher, dass ein
/// Ladefehler stattdessen wie jeder andere Fehler behandelt wird: Auftrag
/// "failed", Warteschlange bleibt für den nächsten Auftrag funktionsfähig.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_restore_queue_load_failure_test_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<String> insertAsset(String id) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'checksum_$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024, 1, 1),
          importedAt: DateTime(2024, 1, 1),
        ));
    return id;
  }

  test('ein Ladefehler des Modells markiert den Auftrag als fehlgeschlagen statt die Warteschlange zu blockieren',
      () async {
    final queue = RestoreQueueService(db, paths);
    queue.restoreHalter = ModellHalter<RestoreService>(
      name: 'kaputtes Testmodell',
      installiert: true,
      laden: () async => throw StateError('Modelldatei beschädigt'),
      entsorgen: (_) async {},
    );

    final assetA = await insertAsset('a');
    final jobIdA = await queue.enqueue(assetA);
    await pumpEventQueue();

    final jobA = (await db.watchRestoreJobs().first).firstWhere((j) => j.id == jobIdA);
    expect(jobA.status, 'failed');
    // Gespeichert wird die Kennung des Grundes (übersetzbar) und dahinter
    // die Ursache – die ist es, die bei einem Fehlerbericht weiterhilft.
    expect(jobA.errorMessage, startsWith('modellLaedtNicht: '));
    expect(jobA.errorMessage, contains('Modelldatei beschädigt'));

    // Die Warteschlange darf danach nicht blockiert bleiben – ein zweiter
    // Auftrag muss trotzdem angefasst (und ebenfalls sauber als
    // fehlgeschlagen markiert, nicht auf "queued" hängen bleiben) werden.
    final assetB = await insertAsset('b');
    final jobIdB = await queue.enqueue(assetB);
    await pumpEventQueue();

    final jobB = (await db.watchRestoreJobs().first).firstWhere((j) => j.id == jobIdB);
    expect(jobB.status, 'failed');
    expect(queue.isProcessing, isFalse);
  });
}
