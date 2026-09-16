import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Das Übertragen von Entwicklungseinstellungen auf andere Fotos – die
/// Zwischenablage nach Lightroom-Vorbild. Geprüft wird vor allem, was NICHT
/// mitwandert: gesperrte Fotos, Videos und Masken.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService imp;
  late LibraryState lib;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_uebertrag_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    imp = ImportService(db, paths);
    lib = LibraryState()
      ..db = db
      ..paths = paths;
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<String> importiere(String name, int fuellung) async {
    final inc = Directory(p.join(tempRoot.path, 'in'))..createSync(recursive: true);
    final f = File(p.join(inc.path, name))..writeAsBytesSync(List.filled(64, fuellung));
    return (await imp.importFile(f.path)).assetId!;
  }

  Future<void> entwickle(String id, {double belichtung = 1.5}) async {
    await db.saveDevelopResult(
      id,
      settings: DevelopSettingsCompanion.insert(
        assetId: id,
        exposure: Value(belichtung),
        contrast: const Value(0.3),
        updatedAt: DateTime.now(),
      ),
      developedRelativePath: 'developed/$id.jpg',
    );
  }

  test('ohne entwickeltes Quellfoto lässt sich nichts kopieren', () async {
    final id = await importiere('roh.jpg', 1);
    expect(await lib.kopiereEntwicklungVon(id), isFalse);
    expect(lib.hatKopierteEntwicklung, isFalse);
  });

  test('kopieren legt die Werte in die Zwischenablage', () async {
    final id = await importiere('quelle.jpg', 2);
    await entwickle(id, belichtung: 1.5);

    expect(await lib.kopiereEntwicklungVon(id), isTrue);
    expect(lib.kopierteEntwicklung!.exposure, 1.5);
    expect(lib.kopierteEntwicklung!.contrast, 0.3);

    lib.leereEntwicklungsZwischenablage();
    expect(lib.hatKopierteEntwicklung, isFalse);
  });

  test('der aktuelle Reglerstand lässt sich ohne Speichern kopieren', () async {
    // Das Speichern schliesst den Entwickeln-Bildschirm; müsste man erst
    // speichern, käme man nie zum Kopieren (Fehlerbericht). Deshalb nimmt
    // setzeKopierteEntwicklung beliebige Werte entgegen – auch für ein
    // Foto, das noch gar keine gespeicherte Entwicklung hat.
    final id = await importiere('ungespeichert.jpg', 9);
    expect(await db.developSettingsForAsset(id), isNull);

    lib.setzeKopierteEntwicklung(DevelopSettingsData(
      assetId: id,
      exposure: 0.75,
      contrast: -0.2,
      shadows: 0,
      highlights: 0,
      sharpness: 0,
      noiseReduction: 0,
      clarity: 0,
      vignette: 0,
      lutStrength: 1,
      lensCorrectionEnabled: true,
      updatedAt: DateTime.now(),
    ));

    expect(lib.hatKopierteEntwicklung, isTrue);
    expect(lib.kopierteEntwicklung!.exposure, 0.75);
    expect(lib.kopierteEntwicklung!.contrast, -0.2);
  });

  test('ohne Zwischenablage passiert nichts', () async {
    final ziel = await importiere('ziel.jpg', 3);
    final schritte = await lib.uebertrageEntwicklung([ziel]).toList();
    expect(schritte.single.total, 0);
    expect(await db.developSettingsForAsset(ziel), isNull);
  });

  test('gesperrte Fotos und Videos bleiben aussen vor', () async {
    final quelle = await importiere('quelle2.jpg', 4);
    await entwickle(quelle);
    await lib.kopiereEntwicklungVon(quelle);

    final gesperrt = await importiere('geheim.jpg', 5);
    await db.setAssetsLocked([gesperrt], true);

    // Der Zähler im Fortschritt gibt die tatsächlich bearbeiteten Fotos an.
    final schritte = await lib.uebertrageEntwicklung([gesperrt]).toList();
    expect(schritte.first.total, 0,
        reason: 'ein gesperrtes Foto liegt verschlüsselt vor und darf nicht '
            'entwickelt werden');
    expect(await db.developSettingsForAsset(gesperrt), isNull);
  });

  test('das Quellfoto selbst wird übersprungen', () async {
    final quelle = await importiere('quelle3.jpg', 6);
    await entwickle(quelle);
    await lib.kopiereEntwicklungVon(quelle);

    final schritte = await lib.uebertrageEntwicklung([quelle]).toList();
    expect(schritte.first.total, 0,
        reason: 'sich selbst zu überschreiben hätte nur einen Verlaufseintrag '
            'ohne Änderung zur Folge');
  });

  test('Masken des Quellfotos wandern nicht mit', () async {
    final quelle = await importiere('mitmaske.jpg', 7);
    await entwickle(quelle);
    await db.createDevelopMask(
      DevelopMasksCompanion.insert(
        assetId: quelle,
        maskRelativePath: 'masks/$quelle-1.png',
        label: 'Himmel',
        createdAt: DateTime.now(),
        exposure: const Value(2.0),
      ),
    );
    expect(await db.masksForAsset(quelle), hasLength(1));

    await lib.kopiereEntwicklungVon(quelle);
    final ziel = await importiere('ohnemaske.jpg', 8);
    await lib.uebertrageEntwicklung([ziel]).drain<void>();

    expect(await db.masksForAsset(ziel), isEmpty,
        reason: 'eine Maske umschliesst einen Ort im Quellbild und hätte im '
            'Zielbild keine Entsprechung');
  });
}
