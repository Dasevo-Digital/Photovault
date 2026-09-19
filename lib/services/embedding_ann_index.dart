import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Persistenter, lokaler Vorfilter für CLIP-Ähnlichkeitssuchen.
///
/// Der Index ist absichtlich kein Ersatz für die exakte Kosinuswertung:
/// mehrere SimHash-Tabellen liefern nur eine kleine Kandidatenmenge; deren
/// Rangfolge wird anschließend wieder mit den vollständigen Vektoren
/// bestimmt. Dadurch bleibt das Ergebnis nachvollziehbar und die Suche muss
/// bei großen Bibliotheken nach einem Neustart nicht mehr alle Vektoren in
/// den Arbeitsspeicher laden.
class EmbeddingAnnIndex {
  EmbeddingAnnIndex._(this.assetIds, this._buckets);

  static const _version = 1;
  static const _tables = 8;
  static const _bitsPerTable = 8;
  static const _samplesPerBit = 32;

  /// Die vollständige, sortierte Menge ist der günstige Gültigkeitsbeleg.
  /// Die Datenbank liefert dafür nur Kennungen, keine mehrere hundert MB
  /// umfassenden Vektor-Blobs.
  final List<String> assetIds;
  final Map<int, List<String>> _buckets;

  static EmbeddingAnnIndex build(Map<String, Float32List> embeddings) {
    final buckets = <int, List<String>>{};
    final ids = embeddings.keys.toList()..sort();
    for (final id in ids) {
      final vector = embeddings[id]!;
      for (var table = 0; table < _tables; table++) {
        final key = _bucketKey(table, _signature(vector, table));
        buckets.putIfAbsent(key, () => []).add(id);
      }
    }
    return EmbeddingAnnIndex._(ids, buckets);
  }

  /// Lädt nur dann, wenn der Index exakt zu den aktuell suchbaren Assets
  /// gehört. Ein Import, Papierkorb oder Sperren führt damit zuverlässig
  /// zu einem Neuaufbau, statt neue Aufnahmen still zu übersehen.
  static Future<EmbeddingAnnIndex?> load(
      File file, List<String> currentAssetIds) async {
    for (final candidate in [file, File('${file.path}.previous')]) {
      try {
        if (!await candidate.exists()) continue;
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is! Map<String, dynamic> ||
            decoded['version'] != _version) {
          continue;
        }
        final ids = (decoded['assetIds'] as List?)?.cast<String>();
        final rawBuckets = decoded['buckets'] as Map?;
        if (ids == null ||
            rawBuckets == null ||
            !_sameIds(ids, currentAssetIds)) {
          continue;
        }
        final buckets = <int, List<String>>{};
        for (final entry in rawBuckets.entries) {
          final key = int.tryParse(entry.key.toString());
          final values = (entry.value as List?)?.cast<String>();
          if (key == null || values == null) continue;
          buckets[key] = values;
        }
        return EmbeddingAnnIndex._(List.unmodifiable(ids), buckets);
      } catch (_) {
        // Ein abgebrochener oder manuell kopierter Index ist nur ein Cache.
        // Die vorherige Fassung kann noch vollständig vorhanden sein.
      }
    }
    // Er darf den Start nie verhindern; die aufrufende Seite baut ihn neu.
    return null;
  }

  Future<void> save(File file) async {
    await file.parent.create(recursive: true);
    final payload = jsonEncode({
      'version': _version,
      'assetIds': assetIds,
      'buckets': {for (final e in _buckets.entries) e.key.toString(): e.value},
    });
    final part = File('${file.path}.part');
    final previous = File('${file.path}.previous');
    await part.writeAsString(payload, flush: true);
    if (await previous.exists()) await previous.delete();
    if (await file.exists()) await file.rename(previous.path);
    await part.rename(file.path);
    if (await previous.exists()) await previous.delete();
  }

  /// Liefert Kandidaten aus identischen und einem Bit benachbarten Buckets.
  /// Die Nachbar-Buckets vermeiden, dass ein Wert knapp an einer
  /// Hash-Grenze einen ansonsten sehr ähnlichen Treffer verliert.
  List<String> candidates(Float32List query, {required int minimum}) {
    final out = <String>{};
    for (var table = 0; table < _tables; table++) {
      final signature = _signature(query, table);
      void add(int value) =>
          out.addAll(_buckets[_bucketKey(table, value)] ?? const []);
      add(signature);
      for (var bit = 0; bit < _bitsPerTable && out.length < minimum; bit++) {
        add(signature ^ (1 << bit));
      }
    }
    return out.toList(growable: false);
  }

  static bool _sameIds(List<String> stored, List<String> current) {
    if (stored.length != current.length) return false;
    for (var i = 0; i < stored.length; i++) {
      if (stored[i] != current[i]) return false;
    }
    return true;
  }

  static int _bucketKey(int table, int signature) =>
      (table << _bitsPerTable) | signature;

  /// Deterministische, dünn besetzte SimHash-Ebenen. Keine Zufallsquelle
  /// bedeutet: derselbe Vektor landet auf Linux, Windows und macOS im selben
  /// Bucket und der Index bleibt über App-Starts hinweg lesbar.
  static int _signature(Float32List vector, int table) {
    if (vector.isEmpty) return 0;
    var signature = 0;
    for (var bit = 0; bit < _bitsPerTable; bit++) {
      var sum = 0.0;
      for (var sample = 0; sample < _samplesPerBit; sample++) {
        final seed = _mix(table * 0x9e3779b9 ^ bit * 0x85ebca6b ^ sample);
        final value = vector[seed % vector.length];
        sum += (seed & 1) == 0 ? value : -value;
      }
      if (sum >= 0) signature |= 1 << bit;
    }
    return signature;
  }

  static int _mix(int value) {
    var x = value & 0x7fffffff;
    x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0x7fffffff;
    x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0x7fffffff;
    return (x ^ (x >> 16)) & 0x7fffffff;
  }
}
