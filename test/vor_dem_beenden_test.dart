import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/modell_halter.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/restore_queue_service.dart';
import 'package:photo_vault/services/restore_service.dart';
import 'package:photo_vault/state/library_state.dart';

/// Vor dem Beenden schliesst die Bibliothek ihre Datenbank (#215) – sonst
/// räumte die Dart-Laufzeit sie erst beim Herunterfahren über Finalizer ab,
/// und die App stürzte dabei in `sqlite3_finalize` ab.
void main() {
  test('schliesst die Datenbank, ein zweiter Aufruf tut nichts', () async {
    final temp = Directory.systemTemp.createTempSync('pv_beenden_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    final bib = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'lib')),
      );
    bib.datenbankAlsGeoeffnet();
    expect(await db.select(db.assets).get(), isEmpty);

    await bib.vorDemBeenden();
    await expectLater(db.select(db.assets).get(), throwsA(anything));
    await bib.vorDemBeenden();
  });

  test(
    'die Restaurierung fragt nach dem Anhalten die Datenbank nicht mehr',
    () async {
      // Ihr Leerlauf-Wecker feuerte bis zu 20 s nach dem Schliessen und
      // fragte dann eine geschlossene Datenbank ("connection was closed").
      final temp = Directory.systemTemp.createTempSync('pv_beenden_queue_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final db = AppDatabase(NativeDatabase.memory());
      final queue = RestoreQueueService(
        db,
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib'))),
      );
      await queue.beende();
      await db.close();
      // Ohne beende() liefe das in die geschlossene Datenbank.
      await queue.resume();
      queue.noteUserInteraction();
      await queue.resumeWhenIdle();
    },
  );

  group('begonnene Restaurierung', () {
    late Directory temp;
    late AppDatabase db;
    late LibraryState bib;
    late RestoreQueueService queue;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('pv_beenden_lauf_');
      addTearDown(() => temp.delete(recursive: true));
      db = AppDatabase(NativeDatabase.memory());
      final paths = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'lib')),
      );
      queue = _TestWarteschlange(db, paths);
      bib = LibraryState()
        ..db = db
        ..paths = paths
        ..restoreQueue = queue
        ..datenbankAlsGeoeffnet();
      addTearDown(bib.vorDemBeenden);
      final jetzt = DateTime.now();
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'foto',
              originalFileName: 'probe.jpg',
              relativePath: 'originals/probe.jpg',
              checksum: 'probe',
              type: 'IMAGE',
              fileCreatedAt: jetzt,
              importedAt: jetzt,
              widthPx: const Value(32),
              heightPx: const Value(24),
            ),
          );
    });

    test(
      'ein verspäteter Ladefehler bleibt beim Beenden ohne Datenbankzugriff',
      () async {
        final laden = Completer<RestoreService>();
        final begonnen = Completer<void>();
        queue.restoreHalter = ModellHalter<RestoreService>(
          name: 'Testmodell',
          installiert: true,
          laden: () {
            begonnen.complete();
            return laden.future;
          },
          entsorgen: (_) async {},
        );
        await queue.enqueue('foto');
        final fertig = expectLater(queue.resume(), completes);
        await begonnen.future;
        await bib.vorDemBeenden();
        await expectLater(db.select(db.assets).get(), throwsStateError);
        laden.completeError(StateError('Modell nicht lesbar'));
        await fertig;
        expect(queue.restoreHalter!.nutzer, 0);
      },
    );

    test(
      'Beenden bricht die Inferenz ab und ignoriert späte Ergebnisse',
      () async {
        final service = _TestModell();
        queue.restoreHalter = ModellHalter<RestoreService>(
          name: 'Testmodell',
          installiert: true,
          laden: () async => service,
          entsorgen: (_) async {},
        );
        await queue.enqueue('foto');
        final fertig = expectLater(queue.resume(), completes);
        await service.begonnen.future;
        expect((await db.watchRestoreJobs().first).single.status, 'running');
        await bib.vorDemBeenden();
        expect(service.lauf.abbrueche, 1);
        service.fortschritt?.call(1, 2);
        service.lauf.fertig.complete(Uint8List.fromList([1, 2, 3]));
        await fertig;
        expect(queue.restoreHalter!.nutzer, 0);
        final ablage = Directory(p.join(bib.paths.root.path, 'restored'));
        expect(!ablage.existsSync() || ablage.listSync().isEmpty, isTrue);
      },
    );
  });
}

class _TestWarteschlange extends RestoreQueueService {
  _TestWarteschlange(super.db, super.paths) : super(waitForIdle: true);

  @override
  Future<Uint8List?> entwickeltesJpeg(AssetData asset) async =>
      Uint8List.fromList([1, 2, 3]);
}

class _TestModell implements RestoreService {
  final begonnen = Completer<void>();
  final lauf = _TestLauf();
  void Function(int, int)? fortschritt;

  @override
  Restaurierungslauf starteJpeg(
    Uint8List jpeg, {
    int quality = 92,
    void Function(int, int)? onProgress,
  }) {
    fortschritt = onProgress;
    begonnen.complete();
    return lauf;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLauf implements Restaurierungslauf {
  final fertig = Completer<Uint8List?>();
  var abbrueche = 0;

  @override
  Future<Uint8List?> get ergebnis => fertig.future;

  @override
  void abbrechen() => abbrueche++;

  @override
  void fortsetzen() {}

  @override
  void pausieren() {}
}
