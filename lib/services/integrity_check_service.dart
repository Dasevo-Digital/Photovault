import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'vault_crypto.dart';

/// Art der fehlenden Datei – bestimmt, welche Behebungs-Aktion im
/// IntegrityCheckScreen sinnvoll ist (z.B. bei einer fehlenden Vorschau
/// reicht es, den DB-Pfad zu löschen und neu zu rendern; bei einem fehlenden
/// Original bleibt nur, die ganze Asset-Zeile zu entfernen).
enum MissingFileKind { original, thumbnail, preview, developed, restored, trimmed, faceCrop, mask }

/// Leichtgewichtiges, isolate-taugliches Abbild der für die
/// Integritätsprüfung relevanten Spalten eines Assets – bewusst kein
/// direkter Durchgriff auf die drift-generierte `AssetData`-Klasse, damit
/// dieser Service unabhängig von der DB-Schicht bleibt und sich leicht ohne
/// echte Datenbank testen lässt.
class AssetPathSnapshot {
  final String assetId;
  final String relativePath;
  final String? thumbnailRelativePath;
  final String? previewRelativePath;
  final String? developedRelativePath;
  final String? restoredRelativePath;
  final String? trimmedRelativePath;
  final String checksum;
  final bool isLocked;

  const AssetPathSnapshot({
    required this.assetId,
    required this.relativePath,
    this.thumbnailRelativePath,
    this.previewRelativePath,
    this.developedRelativePath,
    this.restoredRelativePath,
    this.trimmedRelativePath,
    required this.checksum,
    required this.isLocked,
  });
}

class FaceCropSnapshot {
  final String faceId;
  final String relativePath;
  const FaceCropSnapshot({required this.faceId, required this.relativePath});
}

class MaskSnapshot {
  final int maskId;
  final String relativePath;
  const MaskSnapshot({required this.maskId, required this.relativePath});
}

/// Eingabe für [runIntegrityCheck] – gebündelt in einer Klasse, da [compute]
/// genau ein Argument an die Isolate-Funktion übergibt (Muster: siehe
/// DuplicateSearchParams in embedding_similarity.dart).
class IntegrityCheckParams {
  final String libraryRootPath;
  final List<AssetPathSnapshot> assets;
  final List<FaceCropSnapshot> faceCrops;
  final List<MaskSnapshot> masks;
  final bool verifyChecksums;

  const IntegrityCheckParams({
    required this.libraryRootPath,
    required this.assets,
    required this.faceCrops,
    required this.masks,
    required this.verifyChecksums,
  });
}

class MissingFileIssue {
  final String ownerId;
  final MissingFileKind kind;
  final String relativePath;
  const MissingFileIssue({required this.ownerId, required this.kind, required this.relativePath});
}

class OrphanedFileIssue {
  final String relativePath;
  final int sizeBytes;
  const OrphanedFileIssue({required this.relativePath, required this.sizeBytes});
}

class ChecksumMismatchIssue {
  final String assetId;
  final String relativePath;
  const ChecksumMismatchIssue({required this.assetId, required this.relativePath});
}

/// Nur für gesperrte (verschlüsselte) Assets: die Datei beginnt nicht mit
/// dem erwarteten "PVE1"-Magic-Header – deutet auf eine beschädigte/
/// abgebrochen geschriebene Datei hin. Bewusst getrennt von
/// [ChecksumMismatchIssue], da ein normaler Prüfsummen-Vergleich für
/// verschlüsselte Dateien nie funktionieren würde (siehe VaultCrypto).
class EncryptedFileHeaderIssue {
  final String assetId;
  final String relativePath;
  const EncryptedFileHeaderIssue({required this.assetId, required this.relativePath});
}

class IntegrityCheckReport {
  final List<MissingFileIssue> missingFiles;
  final List<OrphanedFileIssue> orphanedFiles;
  final List<ChecksumMismatchIssue> checksumMismatches;
  final List<EncryptedFileHeaderIssue> encryptedHeaderIssues;
  final int filesScanned;

  const IntegrityCheckReport({
    required this.missingFiles,
    required this.orphanedFiles,
    required this.checksumMismatches,
    required this.encryptedHeaderIssues,
    required this.filesScanned,
  });

  bool get isClean =>
      missingFiles.isEmpty &&
      orphanedFiles.isEmpty &&
      checksumMismatches.isEmpty &&
      encryptedHeaderIssues.isEmpty;
}

/// Unterverzeichnisse, die auf verwaiste Dateien durchsucht werden – exakt
/// die Liste aus StoragePaths._createAt, MINUS "trash": Assets werden beim
/// Verschieben in den Papierkorb nur per DB-Flag markiert, nie physisch
/// verschoben (StoragePaths.moveToPhysicalTrash hat keine Aufrufer mehr),
/// der Ordner ist daher faktisch immer leer.
const _scannedSubdirs = ['originals', 'thumbnails', 'previews', 'developed', 'trimmed', 'masks', 'faces'];

/// Dateien, die absichtlich nie in der DB verzeichnet sind und daher nicht
/// als "verwaist" gelten sollen: macOS-Finder-Metadaten (.DS_Store, AppleDouble
/// ._*-Schattendateien) und XMP-Sidecars (siehe xmp_writer.dart – tragen
/// denselben Basisnamen wie ihr Foto, aber keine eigene DB-Spalte).
bool _isExpectedNonDbFile(String basename) =>
    basename.startsWith('.') || p.extension(basename).toLowerCase() == '.xmp';

/// Reine, isolate-taugliche Scan-Funktion (Muster: findDuplicateGroups in
/// embedding_similarity.dart) – gleicht DB-Zeilen gegen tatsächliche
/// Dateien auf der Platte ab. Läuft über [compute], damit das Auflisten
/// großer Verzeichnisse und ggf. Prüfsummen-Berechnung die UI nicht blockiert.
Future<IntegrityCheckReport> runIntegrityCheck(IntegrityCheckParams params) async {
  final root = Directory(params.libraryRootPath);
  final knownRelativePaths = <String>{};
  final missingFiles = <MissingFileIssue>[];
  final checksumMismatches = <ChecksumMismatchIssue>[];
  final encryptedHeaderIssues = <EncryptedFileHeaderIssue>[];

  Future<void> checkPath(String? relativePath, String ownerId, MissingFileKind kind) async {
    if (relativePath == null) return;
    knownRelativePaths.add(p.normalize(relativePath));
    final file = File(p.join(root.path, relativePath));
    if (!await file.exists()) {
      missingFiles.add(MissingFileIssue(ownerId: ownerId, kind: kind, relativePath: relativePath));
    }
  }

  for (final asset in params.assets) {
    await checkPath(asset.relativePath, asset.assetId, MissingFileKind.original);
    await checkPath(asset.thumbnailRelativePath, asset.assetId, MissingFileKind.thumbnail);
    await checkPath(asset.previewRelativePath, asset.assetId, MissingFileKind.preview);
    await checkPath(asset.developedRelativePath, asset.assetId, MissingFileKind.developed);
    await checkPath(asset.restoredRelativePath, asset.assetId, MissingFileKind.restored);
    await checkPath(asset.trimmedRelativePath, asset.assetId, MissingFileKind.trimmed);

    final originalFile = File(p.join(root.path, asset.relativePath));
    if (await originalFile.exists()) {
      if (asset.isLocked) {
        final hasValidHeader = await VaultCrypto.hasValidEncryptedHeader(originalFile);
        if (!hasValidHeader) {
          encryptedHeaderIssues.add(
            EncryptedFileHeaderIssue(assetId: asset.assetId, relativePath: asset.relativePath),
          );
        }
      } else if (params.verifyChecksums) {
        final actual = (await sha256.bind(originalFile.openRead()).first).toString();
        if (actual != asset.checksum) {
          checksumMismatches.add(
            ChecksumMismatchIssue(assetId: asset.assetId, relativePath: asset.relativePath),
          );
        }
      }
    }
  }

  for (final face in params.faceCrops) {
    await checkPath(face.relativePath, face.faceId, MissingFileKind.faceCrop);
  }
  for (final mask in params.masks) {
    await checkPath(mask.relativePath, mask.maskId.toString(), MissingFileKind.mask);
  }

  final orphanedFiles = <OrphanedFileIssue>[];
  var filesScanned = 0;
  final now = DateTime.now();
  for (final sub in _scannedSubdirs) {
    final dir = Directory(p.join(root.path, sub));
    if (!await dir.exists()) continue;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      filesScanned++;
      final basename = p.basename(entity.path);
      if (_isExpectedNonDbFile(basename)) continue;
      final relativePath = p.normalize(p.relative(entity.path, from: root.path));
      if (knownRelativePaths.contains(relativePath)) continue;
      // Wettlauf mit einem gerade laufenden Import vermeiden: frisch
      // geschriebene Dateien (< 60s) noch nicht als verwaist melden, die
      // zugehörige DB-Zeile ist evtl. noch nicht committet.
      final stat = await entity.stat();
      if (now.difference(stat.modified) < const Duration(seconds: 60)) continue;
      orphanedFiles.add(OrphanedFileIssue(relativePath: relativePath, sizeBytes: stat.size));
    }
  }

  return IntegrityCheckReport(
    missingFiles: missingFiles,
    orphanedFiles: orphanedFiles,
    checksumMismatches: checksumMismatches,
    encryptedHeaderIssues: encryptedHeaderIssues,
    filesScanned: filesScanned,
  );
}
