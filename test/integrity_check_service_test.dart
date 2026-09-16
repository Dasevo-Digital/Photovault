import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/integrity_check_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft [runIntegrityCheck] direkt mit selbst geschriebenen Dummy-Dateien
/// (Muster: test/delete_asset_files_test.dart) – ohne echte Drift-DB, da der
/// Service bewusst nur leichtgewichtige Snapshot-Klassen entgegennimmt.
void main() {
  late Directory tempRoot;
  late StoragePaths paths;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_integrity_check_test_');
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
  });

  tearDown(() {
    tempRoot.deleteSync(recursive: true);
  });

  /// Setzt den Änderungszeitpunkt einer Datei auf "vor 5 Minuten" – ohne das
  /// würde die Wettlauf-Kulanzfrist (< 60s) jede frisch im Test geschriebene
  /// Datei als "gerade importiert" ignorieren.
  void backdate(File file) {
    file.setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 5)));
  }

  test('erkennt eine fehlende Originaldatei', () async {
    final params = IntegrityCheckParams(
      libraryRootPath: paths.root.path,
      assets: const [
        AssetPathSnapshot(
          assetId: 'a1',
          relativePath: 'originals/a1.jpg',
          checksum: 'irrelevant',
          isLocked: false,
        ),
      ],
      faceCrops: const [],
      masks: const [],
      verifyChecksums: false,
    );

    final report = await runIntegrityCheck(params);

    expect(report.missingFiles, hasLength(1));
    expect(report.missingFiles.single.ownerId, 'a1');
    expect(report.missingFiles.single.kind, MissingFileKind.original);
  });

  test('meldet keine fehlende Datei, wenn sie tatsächlich existiert', () async {
    paths.absolute('originals/a1.jpg').writeAsBytesSync([1, 2, 3]);

    final params = IntegrityCheckParams(
      libraryRootPath: paths.root.path,
      assets: const [
        AssetPathSnapshot(
          assetId: 'a1',
          relativePath: 'originals/a1.jpg',
          checksum: 'irrelevant',
          isLocked: false,
        ),
      ],
      faceCrops: const [],
      masks: const [],
      verifyChecksums: false,
    );

    final report = await runIntegrityCheck(params);

    expect(report.missingFiles, isEmpty);
  });

  test('erkennt eine verwaiste Datei ohne DB-Zeile', () async {
    final orphan = paths.absolute('originals/orphan.jpg')..writeAsBytesSync([1, 2, 3]);
    backdate(orphan);

    final params = IntegrityCheckParams(
      libraryRootPath: paths.root.path,
      assets: const [],
      faceCrops: const [],
      masks: const [],
      verifyChecksums: false,
    );

    final report = await runIntegrityCheck(params);

    expect(report.orphanedFiles, hasLength(1));
    expect(report.orphanedFiles.single.relativePath, p.join('originals', 'orphan.jpg'));
  });

  test('ignoriert .DS_Store und .xmp-Sidecars als "verwaist"', () async {
    final dsStore = paths.absolute('originals/.DS_Store')..writeAsBytesSync([1]);
    final sidecar = paths.absolute('originals/a1.xmp')..writeAsBytesSync([1]);
    backdate(dsStore);
    backdate(sidecar);

    final params = IntegrityCheckParams(
      libraryRootPath: paths.root.path,
      assets: const [],
      faceCrops: const [],
      masks: const [],
      verifyChecksums: false,
    );

    final report = await runIntegrityCheck(params);

    expect(report.orphanedFiles, isEmpty);
  });

  test('ignoriert frisch geschriebene Dateien (Wettlauf mit laufendem Import)', () async {
    // Kein backdate() – die Datei hat den echten "jetzt"-Zeitstempel.
    paths.absolute('originals/fresh.jpg').writeAsBytesSync([1, 2, 3]);

    final params = IntegrityCheckParams(
      libraryRootPath: paths.root.path,
      assets: const [],
      faceCrops: const [],
      masks: const [],
      verifyChecksums: false,
    );

    final report = await runIntegrityCheck(params);

    expect(report.orphanedFiles, isEmpty);
  });

  test('erkennt eine Prüfsummen-Abweichung, wenn verifyChecksums aktiv ist', () async {
    final file = paths.absolute('originals/a1.jpg')..writeAsBytesSync([1, 2, 3]);
    final realChecksum = sha256.convert(file.readAsBytesSync()).toString();

    final params = IntegrityCheckParams(
      libraryRootPath: paths.root.path,
      assets: [
        const AssetPathSnapshot(
          assetId: 'a1',
          relativePath: 'originals/a1.jpg',
          checksum: 'ein-falscher-checksum-wert',
          isLocked: false,
        ),
      ],
      faceCrops: const [],
      masks: const [],
      verifyChecksums: true,
    );

    final report = await runIntegrityCheck(params);

    expect(report.checksumMismatches, hasLength(1));
    expect(report.checksumMismatches.single.assetId, 'a1');
    // Gegenprobe: die echte Prüfsumme hätte keine Abweichung ergeben.
    expect(realChecksum, isNot('ein-falscher-checksum-wert'));
  });

  test('überspringt den Prüfsummen-Vergleich für gesperrte Assets', () async {
    final file = paths.absolute('originals/a1.jpg')..writeAsBytesSync([1, 2, 3]);
    file.writeAsBytesSync([9, 9, 9]); // definitiv nicht die gespeicherte Prüfsumme

    final params = IntegrityCheckParams(
      libraryRootPath: paths.root.path,
      assets: [
        const AssetPathSnapshot(
          assetId: 'a1',
          relativePath: 'originals/a1.jpg',
          checksum: 'waere-eine-abweichung',
          isLocked: true,
        ),
      ],
      faceCrops: const [],
      masks: const [],
      verifyChecksums: true,
    );

    final report = await runIntegrityCheck(params);

    expect(report.checksumMismatches, isEmpty);
    // Stattdessen: ungültiger Verschlüsselungs-Header (Datei ist kein PVE1).
    expect(report.encryptedHeaderIssues, hasLength(1));
  });

  test('meldet fehlende Gesichts-Crops und Masken mit dem richtigen Kind', () async {
    final params = IntegrityCheckParams(
      libraryRootPath: paths.root.path,
      assets: const [],
      faceCrops: const [FaceCropSnapshot(faceId: 'f1', relativePath: 'faces/f1.jpg')],
      masks: const [MaskSnapshot(maskId: 42, relativePath: 'masks/42.png')],
      verifyChecksums: false,
    );

    final report = await runIntegrityCheck(params);

    expect(report.missingFiles, hasLength(2));
    expect(report.missingFiles.map((i) => i.kind), containsAll([MissingFileKind.faceCrop, MissingFileKind.mask]));
  });

  test('ein sauberes Ergebnis ist isClean', () async {
    paths.absolute('originals/a1.jpg').writeAsBytesSync([1, 2, 3]);

    final params = IntegrityCheckParams(
      libraryRootPath: paths.root.path,
      assets: const [
        AssetPathSnapshot(
          assetId: 'a1',
          relativePath: 'originals/a1.jpg',
          checksum: 'irrelevant',
          isLocked: false,
        ),
      ],
      faceCrops: const [],
      masks: const [],
      verifyChecksums: false,
    );

    final report = await runIntegrityCheck(params);

    expect(report.isClean, isTrue);
  });
}
