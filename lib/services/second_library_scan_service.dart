import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'embedding_similarity.dart';

/// Präfix für externe Asset-IDs im gemeinsamen Embedding-Vergleich – rein
/// zur Unterscheidung "eigenes Foto" vs. "Foto aus der zweiten Bibliothek",
/// da [findDuplicateGroups] beide Seiten nur als Strings kennt.
const _externalPrefix = 'external:';

/// Die (teuer geladenen) Embeddings/Metadaten einer zweiten, externen
/// PhotoVault-Bibliothek – getrennt von [matchAgainstExternalLibrary], damit
/// ein geänderter Ähnlichkeits-Schwellenwert (siehe SecondLibraryCompareScreen,
/// analog zum Schieberegler in DuplicatesScreen) nicht jedes Mal die fremde
/// `library.sqlite` erneut kopieren/öffnen muss.
class ExternalLibrary {
  final Map<String, Float32List> embeddings;
  final Map<String, AssetData> assetsById;
  final Directory root;
  const ExternalLibrary({required this.embeddings, required this.assetsById, required this.root});
}

/// Ein Treffer zwischen einem eigenen Foto und einem inhaltlich sehr
/// ähnlichen Foto in einer zweiten, externen PhotoVault-Bibliothek.
class ExternalDuplicateMatch {
  final AssetData ownAsset;
  final String externalAssetId;
  final String externalFileName;

  /// Kosinus-Ähnlichkeit der beiden CLIP-Embeddings (0..1, höher = ähnlicher)
  /// – analog zur Ähnlichkeits-Anzeige in DuplicatesScreen, damit auch hier
  /// erkennbar ist, wie sicher ein Treffer ist, statt einer reinen
  /// Ja/Nein-Liste.
  final double similarity;

  /// Nicht garantiert vorhanden (z.B. bei Videos oder wenn das Thumbnail in
  /// der fremden Bibliothek fehlt) – Aufrufer prüfen [File.existsSync]
  /// selbst, statt sich auf die Existenz zu verlassen.
  final File externalThumbnail;

  const ExternalDuplicateMatch({
    required this.ownAsset,
    required this.externalAssetId,
    required this.externalFileName,
    required this.similarity,
    required this.externalThumbnail,
  });
}

/// Lädt Embeddings/Metadaten einer ZWEITEN, komplett unabhängigen
/// PhotoVault-Bibliothek (z.B. auf einer externen Platte oder einem alten
/// Rechner) – "ist das schon in meiner Bibliothek?", bevor man erneut
/// importiert. Siehe [matchAgainstExternalLibrary] für den eigentlichen
/// Vergleich.
///
/// Öffnet die fremde `library.sqlite` NIE direkt: sie könnte von einer
/// älteren PhotoVault-Version stammen, und Drifts Schema-Migration würde
/// beim Öffnen automatisch versuchen, sie hochzustufen – das würde die
/// fremde Datei verändern, obwohl hier nur gelesen werden soll. Stattdessen
/// wird die Datei zuerst in ein Temp-Verzeichnis kopiert, nur die Kopie
/// geöffnet, und die Kopie danach wieder gelöscht (auch im Fehlerfall).
///
/// Gesperrte Fotos der zweiten Bibliothek tauchen hier NIE auf, ohne dass
/// deren PIN gebraucht wird: [AppDatabase.allEmbeddings] schließt gesperrte
/// (und papierkorb-) Assets grundsätzlich aus – dieselbe Garantie wie für
/// die eigene Bibliothek, siehe database.dart.
///
/// [secondLibraryRoot] ist der vom Nutzer gewählte Ordner, der sowohl
/// `library.sqlite` als auch den `library/`-Unterordner enthält (dasselbe
/// Layout wie der eigene Speicherort, siehe StoragePaths).
Future<ExternalLibrary> loadExternalLibrary(Directory secondLibraryRoot) async {
  final dbFile = File(p.join(secondLibraryRoot.path, 'library.sqlite'));
  if (!await dbFile.exists()) {
    throw StateError('Kein PhotoVault-Ordner: library.sqlite fehlt unter "${secondLibraryRoot.path}".');
  }

  final tempDir = await Directory.systemTemp.createTemp('photo_vault_second_library_');
  AppDatabase? secondDb;
  try {
    final tempDbFile = File(p.join(tempDir.path, 'library.sqlite'));
    await dbFile.copy(tempDbFile.path);
    secondDb = AppDatabase(NativeDatabase.createInBackground(tempDbFile));

    final embeddings = await secondDb.allEmbeddings();
    final assets = await secondDb.assetsByIds(embeddings.keys.toList());
    return ExternalLibrary(
      embeddings: embeddings,
      assetsById: {for (final a in assets) a.id: a},
      root: secondLibraryRoot,
    );
  } finally {
    await secondDb?.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  }
}

/// Vergleicht die eigene Bibliothek gegen eine bereits geladene [external]
/// (siehe [loadExternalLibrary]) und findet inhaltlich sehr ähnliche Fotos
/// per CLIP-Embedding. Rein rechnerisch (keine Datei-/DB-Zugriffe mehr) –
/// beliebig oft mit unterschiedlichem [threshold] wiederholbar, ohne die
/// fremde Bibliothek erneut zu kopieren/öffnen.
Future<List<ExternalDuplicateMatch>> matchAgainstExternalLibrary({
  required AppDatabase ownDb,
  required Map<String, Float32List> ownEmbeddings,
  required ExternalLibrary external,
  double threshold = 0.92,
}) async {
  if (ownEmbeddings.isEmpty || external.embeddings.isEmpty) return [];

  final combined = <String, Float32List>{
    ...ownEmbeddings,
    for (final entry in external.embeddings.entries) '$_externalPrefix${entry.key}': entry.value,
  };

  // Derselbe LSH-vorgefilterte Union-Find-Vergleich wie bei der internen
  // Duplikatsuche (siehe DuplicatesScreen) – findDuplicateGroups kennt keine
  // Vault-Zugehörigkeit, nur Strings, daher die Präfix-Trennung oben.
  final groups = await compute(findDuplicateGroups, DuplicateSearchParams(combined, threshold));

  final ownIdsNeeded = <String>{};
  final pairs = <(String ownId, String externalId)>[];
  for (final group in groups) {
    final ownIds = [for (final id in group) if (!id.startsWith(_externalPrefix)) id];
    final externalIds = [
      for (final id in group)
        if (id.startsWith(_externalPrefix)) id.substring(_externalPrefix.length)
    ];
    // Nur Gruppen mit mindestens einem eigenen UND einem externen Foto sind
    // hier relevant – rein interne Ähnlichkeits-Cluster (nur eigene oder nur
    // externe IDs) beantwortet bereits die normale Duplikatsuche innerhalb
    // einer Bibliothek.
    if (ownIds.isEmpty || externalIds.isEmpty) continue;
    for (final ownId in ownIds) {
      for (final externalId in externalIds) {
        ownIdsNeeded.add(ownId);
        pairs.add((ownId, externalId));
      }
    }
  }
  if (pairs.isEmpty) return [];

  final ownAssets = await ownDb.assetsByIds(ownIdsNeeded.toList());
  final ownAssetsById = {for (final a in ownAssets) a.id: a};

  return [
    for (final (ownId, externalId) in pairs)
      if (ownAssetsById[ownId] != null && external.assetsById[externalId] != null)
        ExternalDuplicateMatch(
          ownAsset: ownAssetsById[ownId]!,
          externalAssetId: externalId,
          externalFileName: external.assetsById[externalId]!.originalFileName,
          // Ein Union-Find-Cluster kann transitiv verbundene Fotos enthalten,
          // deren PAARWEISE Ähnlichkeit unterschiedlich hoch ist (A~B, B~C
          // ⟹ Gruppe {A,B,C}, auch wenn A und C selbst unter der Schwelle
          // liegen) – deshalb hier die tatsächliche Ähnlichkeit DIESES
          // konkreten Paares neu berechnet statt sie aus der Gruppenbildung
          // zu übernehmen.
          similarity: cosineSimilarity(ownEmbeddings[ownId]!, external.embeddings[externalId]!),
          externalThumbnail: File(p.join(external.root.path, 'library', 'thumbnails', '$externalId.jpg')),
        ),
  ];
}
