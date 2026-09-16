import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Prüft die DB-Seite der KI-Restaurierungs-Warteschlange (siehe
/// RestoreQueueService, RestoreJobs): Anlegen/Auflisten/Fortschritt/Status,
/// FIFO-Reihenfolge und insbesondere die Crash-Safety
/// ([resetStuckRunningRestoreJobs]) – ein Auftrag, der beim letzten Beenden
/// noch "running" war, muss beim nächsten Start wieder anlaufen können,
/// statt für immer als "running" hängen zu bleiben.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
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

  RestoreJobsCompanion job({required String id, required String assetId, required DateTime createdAt}) =>
      RestoreJobsCompanion.insert(id: id, assetId: assetId, status: 'queued', createdAt: createdAt);

  test('createRestoreJob legt einen Auftrag mit tilesDone/tilesTotal=0 an', () async {
    final assetId = await insertAsset('a');
    await db.createRestoreJob(job(id: 'job1', assetId: assetId, createdAt: DateTime(2024, 1, 1)));

    final jobs = await db.watchRestoreJobs().first;
    expect(jobs, hasLength(1));
    expect(jobs.single.status, 'queued');
    expect(jobs.single.tilesDone, 0);
    expect(jobs.single.tilesTotal, 0);
  });

  test('activeRestoreJobForAsset findet einen wartenden Auftrag desselben Assets', () async {
    final assetId = await insertAsset('a');
    await db.createRestoreJob(job(id: 'job1', assetId: assetId, createdAt: DateTime(2024, 1, 1)));

    final active = await db.activeRestoreJobForAsset(assetId);
    expect(active?.id, 'job1');
  });

  test('activeRestoreJobForAsset findet auch einen laufenden Auftrag', () async {
    final assetId = await insertAsset('a');
    await db.createRestoreJob(job(id: 'job1', assetId: assetId, createdAt: DateTime(2024, 1, 1)));
    await db.markRestoreJobStatus('job1', 'running');

    final active = await db.activeRestoreJobForAsset(assetId);
    expect(active?.id, 'job1');
  });

  test('activeRestoreJobForAsset ignoriert abgeschlossene Aufträge desselben Assets', () async {
    final assetId = await insertAsset('a');
    await db.createRestoreJob(job(id: 'job1', assetId: assetId, createdAt: DateTime(2024, 1, 1)));
    await db.markRestoreJobStatus('job1', 'done');

    final active = await db.activeRestoreJobForAsset(assetId);
    expect(active, isNull);
  });

  test('activeRestoreJobForAsset ignoriert Aufträge anderer Assets', () async {
    final assetA = await insertAsset('a');
    final assetB = await insertAsset('b');
    await db.createRestoreJob(job(id: 'job1', assetId: assetA, createdAt: DateTime(2024, 1, 1)));

    final active = await db.activeRestoreJobForAsset(assetB);
    expect(active, isNull);
  });

  test('nextQueuedRestoreJob liefert den ältesten wartenden Auftrag (FIFO)', () async {
    final assetId = await insertAsset('a');
    await db.createRestoreJob(job(id: 'later', assetId: assetId, createdAt: DateTime(2024, 1, 2)));
    await db.createRestoreJob(job(id: 'earlier', assetId: assetId, createdAt: DateTime(2024, 1, 1)));

    final next = await db.nextQueuedRestoreJob();
    expect(next?.id, 'earlier');
  });

  test('nextQueuedRestoreJob ignoriert bereits laufende/fertige Aufträge', () async {
    final assetId = await insertAsset('a');
    await db.createRestoreJob(job(id: 'running', assetId: assetId, createdAt: DateTime(2024, 1, 1)));
    await db.markRestoreJobStatus('running', 'running');

    final next = await db.nextQueuedRestoreJob();
    expect(next, isNull);
  });

  test('updateRestoreJobProgress aktualisiert tilesDone/tilesTotal', () async {
    final assetId = await insertAsset('a');
    await db.createRestoreJob(job(id: 'job1', assetId: assetId, createdAt: DateTime(2024, 1, 1)));

    await db.updateRestoreJobProgress('job1', 12, 63);

    final updated = (await db.watchRestoreJobs().first).single;
    expect(updated.tilesDone, 12);
    expect(updated.tilesTotal, 63);
  });

  test('markRestoreJobStatus setzt completedAt bei einem Endstatus, nicht bei queued/running', () async {
    final assetId = await insertAsset('a');
    await db.createRestoreJob(job(id: 'job1', assetId: assetId, createdAt: DateTime(2024, 1, 1)));

    await db.markRestoreJobStatus('job1', 'running');
    var updated = (await db.watchRestoreJobs().first).single;
    expect(updated.completedAt, isNull);

    await db.markRestoreJobStatus('job1', 'failed', errorMessage: 'Testfehler');
    updated = (await db.watchRestoreJobs().first).single;
    expect(updated.status, 'failed');
    expect(updated.errorMessage, 'Testfehler');
    expect(updated.completedAt, isNotNull);
  });

  test('completeRestoreJob setzt Assets.restoredRelativePath und den Job-Status transaktional', () async {
    final assetId = await insertAsset('a');
    await db.createRestoreJob(job(id: 'job1', assetId: assetId, createdAt: DateTime(2024, 1, 1)));

    await db.completeRestoreJob('job1', assetId, 'restored/a.jpg');

    final asset = await db.assetById(assetId);
    expect(asset?.restoredRelativePath, 'restored/a.jpg');
    final updatedJob = (await db.watchRestoreJobs().first).single;
    expect(updatedJob.status, 'done');
    expect(updatedJob.completedAt, isNotNull);
  });

  test('deleteRestoreJob entfernt nur den angegebenen Auftrag', () async {
    final assetId = await insertAsset('a');
    await db.createRestoreJob(job(id: 'keep', assetId: assetId, createdAt: DateTime(2024, 1, 1)));
    await db.createRestoreJob(job(id: 'remove', assetId: assetId, createdAt: DateTime(2024, 1, 2)));

    await db.deleteRestoreJob('remove');

    final jobs = await db.watchRestoreJobs().first;
    expect(jobs.map((j) => j.id), ['keep']);
  });

  test('resetStuckRunningRestoreJobs setzt nur "running" auf "queued" zurück, mit tilesDone=0', () async {
    final assetId = await insertAsset('a');
    await db.createRestoreJob(job(id: 'stuck', assetId: assetId, createdAt: DateTime(2024, 1, 1)));
    await db.markRestoreJobStatus('stuck', 'running');
    await db.updateRestoreJobProgress('stuck', 30, 63);

    await db.createRestoreJob(job(id: 'already-queued', assetId: assetId, createdAt: DateTime(2024, 1, 2)));
    await db.createRestoreJob(job(id: 'already-done', assetId: assetId, createdAt: DateTime(2024, 1, 3)));
    await db.markRestoreJobStatus('already-done', 'done');

    await db.resetStuckRunningRestoreJobs();

    final jobs = {for (final j in await db.watchRestoreJobs().first) j.id: j};
    expect(jobs['stuck']!.status, 'queued');
    expect(jobs['stuck']!.tilesDone, 0);
    expect(jobs['stuck']!.tilesTotal, 0);
    expect(jobs['already-queued']!.status, 'queued');
    expect(jobs['already-done']!.status, 'done'); // unangetastet
  });
}
