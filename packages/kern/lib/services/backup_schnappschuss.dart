import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart' show Tagquelle;
import 'backup_manifest.dart';
import 'backup_modelle.dart';
import 'vault_crypto.dart';

/// Zugriff auf archivierte Stände und deren Beilagen, unabhängig von der
/// geöffneten Bibliothek und vom Ablauf einer Wiederherstellung.
class BackupSchnappschussSpeicher {
  static const _uuid = Uuid();
  static Future<String> _hash(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();

  Future<File> waehle(String wurzel, String? ausgewaehlt) async {
    if (ausgewaehlt == null) return File(p.join(wurzel, 'library.sqlite.enc'));
    final root = p.normalize(p.absolute(wurzel));
    final generations = p.join(root, 'generations');
    final file = File(p.normalize(p.absolute(ausgewaehlt)));
    final ordner = p.dirname(file.path);
    if (p.basename(file.path) != 'library.sqlite.enc' ||
        p.dirname(ordner) != generations ||
        !await file.exists()) {
      throw const FormatException('pv_restore_generation');
    }
    final manifest = File(p.join(ordner, 'generation.json'));
    final echt = await Directory(root).resolveSymbolicLinks();
    for (final f in [file, manifest]) {
      if (!p.isWithin(echt, await f.resolveSymbolicLinks())) {
        throw const FormatException('pv_restore_generation');
      }
    }
    final j = jsonDecode(await manifest.readAsString()) as Map;
    if (!{1, 2}.contains(j['format'])) {
      throw const FormatException('pv_restore_generation');
    }
    if (j['format'] == 2) {
      final meta = File(p.join(ordner, 'metadata.json'));
      if (!p.isWithin(echt, await meta.resolveSymbolicLinks()) ||
          await _hash(file) != j['snapshotSha256'] ||
          await _hash(meta) != j['metadataSha256']) {
        throw const FormatException('pv_restore_generation');
      }
    }
    return file;
  }

  Future<List<BackupGeneration>> generationen(String wurzel) async {
    final dir = Directory(p.join(wurzel, 'generations'));
    if (!await dir.exists()) return const [];
    final result = <BackupGeneration>[];
    await for (final d in dir.list(followLinks: false)) {
      if (d is! Directory || p.basename(d.path).startsWith('.')) continue;
      try {
        final j =
            jsonDecode(
                  await File(p.join(d.path, 'generation.json')).readAsString(),
                )
                as Map;
        final datum = DateTime.tryParse('${j['createdAt']}');
        final db = File(p.join(d.path, 'library.sqlite.enc'));
        if (!{1, 2}.contains(j['format']) ||
            datum == null ||
            !await db.exists()) {
          continue;
        }
        if (j['format'] == 2 &&
            !await File(p.join(d.path, 'metadata.json')).exists()) {
          continue;
        }
        result.add(
          BackupGeneration(
            id: p.basename(d.path),
            createdAt: datum.toLocal(),
            snapshotPath: db.path,
          ),
        );
      } on FileSystemException {
        // Unvollständige Punkte werden nicht angeboten.
      } on FormatException {
        // Fremde Manifeste sind keine Sicherungsgeneration.
      } on TypeError {
        // Ein falsch typisiertes Manifest ist ebenfalls unvollständig.
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<void> archiviere(String wurzel, {required int behalten}) async {
    final root = Directory(wurzel);
    final generations = Directory(p.join(root.path, 'generations'));
    await generations.create(recursive: true);
    final am = DateTime.now().toUtc();
    final id = '${am.toIso8601String().replaceAll(':', '')}_${_uuid.v4()}';
    final stage = Directory(p.join(generations.path, '.$id'));
    final ziel = Directory(p.join(generations.path, id));
    await stage.create();
    try {
      final db = File(p.join(stage.path, 'library.sqlite.enc'));
      final meta = File(p.join(stage.path, 'metadata.json'));
      await File(p.join(root.path, 'library.sqlite.enc')).copy(db.path);
      await File(p.join(root.path, 'metadata.json')).copy(meta.path);
      await File(p.join(stage.path, 'generation.json')).writeAsString(
        jsonEncode({
          'format': 2,
          'createdAt': am.toIso8601String(),
          'usesSharedEncryptedOriginals': true,
          'snapshotSha256': await _hash(db),
          'metadataSha256': await _hash(meta),
        }),
      );
      await stage.rename(ziel.path);
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
    final alle = await generationen(wurzel);
    for (final alt in alle.skip(behalten)) {
      await Directory(p.dirname(alt.snapshotPath)).delete(recursive: true);
    }
  }

  Future<void> schreibeManifest(
    BackupManifest manifest,
    File ziel, {
    SecretKey? schluessel,
  }) async {
    final text = const JsonEncoder.withIndent('  ').convert(manifest.alsJson());
    if (schluessel == null) {
      await ziel.writeAsString(text);
      return;
    }
    final dir = await Directory.systemTemp.createTemp('pv_backup_meta_');
    try {
      final klar = File(p.join(dir.path, 'metadata.json'));
      await klar.writeAsString(text);
      await VaultCrypto.encryptFile(klar, ziel, schluessel);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Auch alte Generationen besitzen ihren vollständigen Datenbankstand.
  /// Daraus entsteht dieselbe Metadatenstruktur wie bei neuen Manifesten.
  /// Die Paare der Live Photos im Schnappschuss als Prüfsummen (#255).
  ///
  /// Für Sicherungen vor 3.49.9: Deren Beilage trägt keinen Partner, ihr
  /// Schnappschuss aber jede Verknüpfung.
  List<(String, String)> livePaareAusDatei(File datei) {
    final db = sqlite3.open(datei.path, mode: OpenMode.readOnly);
    try {
      final spalten = {
        for (final r in db.select('PRAGMA table_info(assets)')) r['name'],
      };
      if (!spalten.contains('linked_asset_id')) return const [];
      return [
        for (final r in db.select(
          'SELECT a.checksum AS x, b.checksum AS y FROM assets a '
          'JOIN assets b ON b.id = a.linked_asset_id',
        ))
          (r['x'] as String, r['y'] as String),
      ];
    } finally {
      db.close();
    }
  }

  BackupManifest manifestAusDatei(File datei) {
    final db = sqlite3.open(datei.path, mode: OpenMode.readOnly);
    try {
      final tabellen = {
        for (final r in db.select(
          "SELECT name FROM sqlite_master WHERE type='table'",
        ))
          r['name'],
      };
      final spalten = {
        for (final r in db.select('PRAGMA table_info(assets)')) r['name'],
      };
      final zeilen = db.select('SELECT * FROM assets');
      // Der Partner eines Live Photos als Prüfsumme (#255).
      final pruefsummeVon = {
        for (final r in zeilen) r['id'] as String: r['checksum'] as String,
      };
      final fotos = <BackupAufnahme>[];
      final hashes = <String, String>{};
      final tags = <String, List<String>>{}, ki = <String, List<String>>{};
      if (tabellen.contains('tags') && tabellen.contains('asset_tags')) {
        final quelle = {
          for (final s in db.select('PRAGMA table_info(asset_tags)')) s['name'],
        }.contains('quelle');
        for (final t in db.select(
          'SELECT a.asset_id,t.name${quelle ? ', a.quelle' : ''} FROM tags t JOIN asset_tags a ON a.tag_id=t.id',
        )) {
          final id = t['asset_id'] as String, name = t['name'] as String;
          (tags[id] ??= []).add(name);
          if (quelle && t['quelle'] == Tagquelle.ki) (ki[id] ??= []).add(name);
        }
      }
      for (final r in zeilen) {
        if (r['is_trashed'] == 1 || r['is_locked'] == 1) continue;
        final id = r['id'] as String;
        hashes[id] = r['checksum'] as String;
        final werte = <String, dynamic>{
          'checksum': r['checksum'],
          'originalFileName': r['original_file_name'],
          'backupRelativePath': r['relative_path'],
          if (spalten.contains('linked_asset_id'))
            'livePartner': ?pruefsummeVon[r['linked_asset_id']],
        };
        const felder = {
          'is_favorite': 'isFavorite',
          'description': 'description',
          'rating': 'rating',
          'color_label': 'colorLabel',
          'latitude': 'latitude',
          'longitude': 'longitude',
          'location_city': 'locationCity',
          'location_state': 'locationState',
          'location_country': 'locationCountry',
          'datum_geschaetzt': 'datumGeschaetzt',
        };
        for (final f in felder.entries) {
          if (!spalten.contains(f.key)) continue;
          werte[f.value] =
              const {'is_favorite', 'datum_geschaetzt'}.contains(f.key)
              ? r[f.key] == 1
              : r[f.key];
        }
        if (r['file_created_at'] case final int zeit) {
          werte['fileCreatedAt'] = DateTime.fromMillisecondsSinceEpoch(
            zeit * 1000,
            isUtc: true,
          ).toIso8601String();
        }
        werte['tags'] = tags[id] ?? const <String>[];
        werte['kiTags'] = ki[id] ?? const <String>[];
        // Ältere Stände kennen die Spalten nicht – dann bleibt es leer.
        bool wahr(String spalte) => spalten.contains(spalte) && r[spalte] == 1;
        String? text(String spalte) =>
            spalten.contains(spalte) ? r[spalte] as String? : null;
        werte.addAll(
          handarbeitAnDerAufnahme(
            stackId: text('stack_id'),
            isStackCover: wahr('is_stack_cover'),
            aiCaptionEdited: wahr('ai_caption_edited'),
            aiCaption: text('ai_caption'),
            aiCaptionDe: text('ai_caption_de'),
            faceScanExcluded: wahr('face_scan_excluded'),
          ),
        );
        fotos.add(BackupAufnahme(werte));
      }
      final alben = <BackupAlbum>[];
      if (tabellen.contains('albums') && tabellen.contains('album_assets')) {
        final inhalte = <String, List<String>>{};
        for (final r in db.select(
          'SELECT album_id,asset_id FROM album_assets',
        )) {
          if (hashes[r['asset_id']] case final hash?) {
            (inhalte[r['album_id'] as String] ??= []).add(hash);
          }
        }
        for (final a in db.select('SELECT id,name FROM albums')) {
          final ids = inhalte[a['id']] ?? const <String>[];
          alben.add(BackupAlbum(name: a['name'] as String, aufnahmen: ids));
        }
      }
      return BackupManifest(
        aufnahmen: fotos,
        alben: alben,
        exportiertAm: DateTime.now().toUtc(),
      );
    } finally {
      db.close();
    }
  }
}
