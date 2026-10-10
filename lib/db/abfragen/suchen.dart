part of '../database.dart';

/// Gespeicherte Suchen.
extension SuchenAbfragen on AppDatabase {
  // -----------------------------------------------------------------------
  // Gespeicherte Suchen ("Intelligente Alben")
  // -----------------------------------------------------------------------

  Future<void> createSavedSearch(
    String id,
    String name,
    SearchFilters filters,
  ) => into(savedSearches).insert(
    SavedSearchesCompanion.insert(
      id: id,
      name: name,
      filtersJson: jsonEncode(filters.toJson()),
      createdAt: DateTime.now(),
    ),
  );

  Stream<List<SavedSearchData>> watchSavedSearches() => (select(
    savedSearches,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  Future<void> deleteSavedSearch(String id) =>
      (delete(savedSearches)..where((t) => t.id.equals(id))).go();

  /// Deserialisiert die bei [createSavedSearch] gespeicherten Filter. Ein
  /// beschädigtes JSON (sollte nicht vorkommen, aber die Datei liegt
  /// außerhalb der Kontrolle der App) liefert leere Filter statt die ganze
  /// App abstürzen zu lassen.
  SearchFilters decodeSavedSearchFilters(String filtersJson) {
    try {
      return SearchFilters.fromJson(
        jsonDecode(filtersJson) as Map<String, dynamic>,
      );
    } catch (_) {
      return const SearchFilters();
    }
  }
}
