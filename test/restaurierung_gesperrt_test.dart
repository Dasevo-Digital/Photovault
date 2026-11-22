import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/modell_halter.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/entwicklung_ablegen.dart';
import 'package:photo_vault/services/restore_queue_service.dart';
import 'package:photo_vault/services/restore_service.dart';
import 'package:photo_vault/services/tresorreihe.dart';
import 'package:photo_vault/state/library_state.dart';

/// Eine Restaurierung rechnet Minuten mit dem Stand vom Beginn. Wird das
/// Foto in dieser Zeit gesperrt, darf ihr Ergebnis nicht im Klartext in
/// den gesperrten Ordner – sonst scheitert jedes spätere Entsperren an der
/// Datei (#430).
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_rest_gesperrt_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..klartextOrdnerFuerTests = Directory(p.join(temp.path, 'klartext'));
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<AssetData> foto() async {
    final bild = img.Image(width: 32, height: 24);
    img.fill(bild, color: img.ColorRgb8(200, 90, 40));
    final f = File(p.join(temp.path, 'foto.jpg'))
      ..writeAsBytesSync(img.encodeJpg(bild));
    final r = await ImportService(
      db,
      paths,
      bildwerkzeuge: const KeineBildwerkzeuge(),
    ).importFile(f.path);
    return (await db.assetById(r.assetId!))!;
  }

  List<String> restauriert() => paths.restoredDir.existsSync()
      ? [for (final e in paths.restoredDir.listSync()) p.basename(e.path)]
      : const [];

  test('während der Restaurierung gesperrt: verworfen, entsperrbar', () async {
    final asset = await foto();
    await library.setupVaultPin('1234');
    final modell = _TestModell();
    final queue = _TestWarteschlange(db, paths)
      ..restoreHalter = ModellHalter<RestoreService>(
        name: 'Testmodell',
        installiert: true,
        laden: () async => modell,
        entsorgen: (_) async {},
      );
    library.restoreQueue = queue;

    // Ohne Warten auf Leerlauf beginnt der Auftrag gleich.
    await queue.enqueue(asset.id);
    await modell.begonnen.future;
    await library.lockAsset(asset);
    modell.lauf.fertig.complete(Uint8List.fromList([0xFF, 0xD8, 1, 2]));
    for (var i = 0; i < 500 && queue.isProcessing; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final auftrag = (await db.watchRestoreJobs().first).single;
    expect(auftrag.status, 'failed');
    expect(auftrag.errorMessage, RestaurierungsGrund.gesperrt.name);
    expect(
      restauriert(),
      isEmpty,
      reason: 'bisher lag das Ergebnis im Klartext im gesperrten Foto',
    );
    expect((await db.assetById(asset.id))!.restoredRelativePath, isNull);

    // Und das Foto lässt sich wieder entsperren.
    await library.unlockAsset((await db.assetById(asset.id))!);
    expect((await db.assetById(asset.id))!.isLocked, isFalse);
  });

  test('wartet ein Ablegen auf ein laufendes Sperren, verwirft es', () async {
    final asset = await foto();
    final sperren = Completer<void>();
    // Ein Sperren, das gerade läuft: Es hat die Dateien der Aufnahme schon
    // gesammelt und trägt sie gleich als gesperrt ein.
    final laeuft = inTresorreihe(paths, () async {
      await sperren.future;
      await db.setAssetsLocked([asset.id], true);
    });
    final ablage = legeRestaurierungAb(
      db: db,
      paths: paths,
      assetId: asset.id,
      jpeg: Uint8List.fromList([1, 2, 3]),
    );
    sperren.complete();
    await laeuft;

    await expectLater(ablage, throwsA(isA<AufnahmeNichtAblegbar>()));
    expect(restauriert(), isEmpty);
  });

  // Dasselbe Muster mit kleinerem Fenster: „Vorschaubilder erzeugen“ geht
  // eine Liste vom Beginn des Laufs durch.
  test(
    'eine neue Miniatur kommt nicht in ein inzwischen gesperrtes Foto',
    () async {
      final asset = await foto();
      library.importService = ImportService(
        db,
        paths,
        bildwerkzeuge: const KeineBildwerkzeuge(),
      );
      final miniatur = paths.absolute(asset.thumbnailRelativePath!)
        ..writeAsBytesSync([7, 7, 7]);
      final sperren = Completer<void>();
      final laeuft = inTresorreihe(paths, () async {
        await sperren.future;
        await db.setAssetsLocked([asset.id], true);
      });
      final lauf = library.regenerateThumbnails(onlyMissing: false).toList();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      sperren.complete();
      await laeuft;
      await lauf;

      expect(miniatur.readAsBytesSync(), [7, 7, 7]);
    },
  );

  test('eine gelöschte Aufnahme bekommt keine Datei', () async {
    await expectLater(
      legeEntwicklungAb(
        db: db,
        paths: paths,
        assetId: 'gibt-es-nicht',
        jpeg: Uint8List.fromList([1]),
        einstellungen: DevelopSettingsCompanion.insert(
          assetId: 'gibt-es-nicht',
          updatedAt: DateTime(2026),
        ),
      ),
      throwsA(
        isA<AufnahmeNichtAblegbar>().having(
          (e) => e.gesperrt,
          'gesperrt',
          false,
        ),
      ),
    );
    expect(
      !paths.developedDir.existsSync() || paths.developedDir.listSync().isEmpty,
      isTrue,
    );
  });
}

class _TestWarteschlange extends RestoreQueueService {
  _TestWarteschlange(super.db, super.paths);

  @override
  Future<Uint8List?> entwickeltesJpeg(AssetData asset) async =>
      Uint8List.fromList([1, 2, 3]);
}

class _TestModell implements RestoreService {
  final begonnen = Completer<void>();
  final lauf = _TestLauf();

  @override
  Restaurierungslauf starteJpeg(
    Uint8List jpeg, {
    int quality = 92,
    void Function(int, int)? onProgress,
  }) {
    begonnen.complete();
    return lauf;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLauf implements Restaurierungslauf {
  final fertig = Completer<Uint8List?>();

  @override
  Future<Uint8List?> get ergebnis => fertig.future;

  @override
  void abbrechen() {}

  @override
  void fortsetzen() {}

  @override
  void pausieren() {}
}
