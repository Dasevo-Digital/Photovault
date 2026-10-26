import 'dart:convert';
import 'dart:io';

import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Welche Alben dieses Telefon vollständig ohne Verbindung bereithalten soll.
///
/// Die Auswahl ist absichtlich gerätebezogen und wird nicht abgeglichen: Ein
/// Telefon mit wenig Speicher darf andere Alben anheften als ein Tablet. Die
/// Datei enthält nur Albumkennungen; die eigentlichen Medien bleiben im schon
/// vorhandenen Zwischenspeicher der verbundenen Bibliothek.
class OfflineAlben {
  OfflineAlben._(this._datei, this._albumIds);

  final File _datei;
  final Set<String> _albumIds;

  static Future<OfflineAlben> oeffne(File datei) async {
    if (!await datei.exists()) return OfflineAlben._(datei, <String>{});
    try {
      final roh = jsonDecode(await datei.readAsString());
      if (roh is! Map || roh['alben'] is! List) {
        return OfflineAlben._(datei, <String>{});
      }
      return OfflineAlben._(datei, {
        for (final id in roh['alben'] as List)
          if (id is String && id.isNotEmpty) id,
      });
    } on FormatException {
      // Eine beschädigte Geräte-Einstellung darf die Bibliothek nicht am
      // Start hindern. Erst die nächste bewusste Auswahl schreibt sie neu.
      return OfflineAlben._(datei, <String>{});
    } on FileSystemException {
      return OfflineAlben._(datei, <String>{});
    }
  }

  bool enthaelt(String albumId) => _albumIds.contains(albumId);

  Set<String> get albumIds => Set.unmodifiable(_albumIds);

  Future<void> setze(String albumId, bool offline) async {
    final vorher = Set<String>.of(_albumIds);
    offline ? _albumIds.add(albumId) : _albumIds.remove(albumId);
    try {
      await _datei.parent.create(recursive: true);
      final teil = File('${_datei.path}.neu');
      final ids = _albumIds.toList()..sort();
      await teil.writeAsString(jsonEncode({'fassung': 1, 'alben': ids}));
      await teil.rename(_datei.path);
    } catch (_) {
      _albumIds
        ..clear()
        ..addAll(vorher);
      rethrow;
    }
  }

  /// Alle Dateien, die zu den angehefteten Alben gehören. Dieser Satz wird
  /// der Cache-Bereinigung übergeben, damit sie auch unter einer knappen
  /// Grenze nicht gelöscht werden.
  Future<Set<String>> geschuetztePfade(AppDatabase db) async {
    final aus = <String>{};
    for (final id in _albumIds) {
      aus.addAll(await _pfadeDesAlbums(db, id));
    }
    return aus;
  }

  /// Holt ein Album vollständig. Gibt die Zahl seiner Aufnahmen zurück.
  /// Bereits vorhandene Dateien werden von [StoragePaths.bereit] nur als
  /// zuletzt benutzt markiert und nicht noch einmal übertragen.
  Future<int> holeAlbum(
    AppDatabase db,
    StoragePaths paths,
    String albumId, {
    int gleichzeitig = 3,
  }) async {
    final aufnahmen = await _aufnahmenDesAlbums(db, albumId);
    // Eine Liste, kein Set: `elementAt` ginge bei jedem Schritt von vorn
    // durch die Menge – bei grossen Alben quadratisch (#220).
    final pfade = <String>{
      for (final a in aufnahmen) ..._medienpfade(a),
    }.toList();
    var index = 0;

    Future<void> arbeiter() async {
      while (index < pfade.length) {
        final relativ = pfade[index++];
        await paths.bereit(relativ);
      }
    }

    await Future.wait([
      for (var i = 0; i < gleichzeitig.clamp(1, 8); i++) arbeiter(),
    ]);
    return aufnahmen.length;
  }

  /// Wie viel Platz [albumId] auf diesem Telefon belegt – was schon da
  /// ist, nicht was noch fehlt (#220).
  Future<int> belegt(AppDatabase db, StoragePaths paths, String albumId) async {
    var summe = 0;
    for (final relativ in await _pfadeDesAlbums(db, albumId)) {
      final f = paths.absolute(relativ);
      if (await f.exists()) summe += await f.length();
    }
    return summe;
  }

  /// Holt alle angehefteten Alben nach. Neue Aufnahmen in einem Album werden
  /// dadurch beim nächsten Pflegegang ebenfalls offline verfügbar.
  Future<void> aktualisiere(AppDatabase db, StoragePaths paths) async {
    for (final id in _albumIds) {
      await holeAlbum(db, paths, id);
    }
  }

  Future<List<AssetData>> _aufnahmenDesAlbums(
    AppDatabase db,
    String albumId,
  ) async {
    final sichtbar = await db.assetsInAlbumOnce(albumId);
    final aus = <String, AssetData>{for (final a in sichtbar) a.id: a};
    for (final a in sichtbar) {
      final partner = a.linkedAssetId;
      if (partner != null) {
        final p = await db.assetById(partner);
        if (p != null && !p.isLocked && !p.isTrashed) aus[p.id] = p;
      }
      final stapel = a.stackId;
      if (stapel != null) {
        for (final s in await db.assetsInStack(stapel)) {
          if (!s.isLocked && !s.isTrashed) aus[s.id] = s;
        }
      }
    }
    return aus.values.toList();
  }

  Future<Set<String>> _pfadeDesAlbums(AppDatabase db, String albumId) async => {
    for (final a in await _aufnahmenDesAlbums(db, albumId)) ..._medienpfade(a),
  };

  static Iterable<String> _medienpfade(AssetData a) sync* {
    yield p.normalize(a.relativePath);
    for (final relativ in [
      a.thumbnailRelativePath,
      a.previewRelativePath,
      a.developedRelativePath,
      a.restoredRelativePath,
      a.trimmedRelativePath,
    ]) {
      if (relativ != null && relativ.isNotEmpty) yield p.normalize(relativ);
    }
  }
}
