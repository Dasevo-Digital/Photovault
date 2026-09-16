import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/search_filters.dart';
import 'package:uuid/uuid.dart';

/// Prüft "Gespeicherte Suchen" (Intelligente Alben): die Filter-Kombination
/// muss die JSON-Rundreise (toJson/fromJson, wie sie AppDatabase beim
/// Speichern/Laden durchläuft) unverändert überstehen, und die DB-Methoden
/// selbst müssen sie korrekt ablegen/wiederfinden/löschen.
void main() {
  test('SearchFilters übersteht die JSON-Rundreise unverändert', () {
    final original = SearchFilters(
      personIds: const ['p1', 'p2'],
      textMode: SearchTextMode.description,
      query: 'Geburtstag',
      tagIds: const ['t1'],
      noTag: false,
      cameraMake: 'Apple',
      locationCountry: 'Deutschland',
      locationCity: 'Braunschweig',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      mediaType: MediaTypeFilter.image,
      favoritesOnly: true,
      notInAnyAlbum: true,
      minRating: 3,
      colorLabels: const {'red', 'blue'},
      minIso: 100,
      maxIso: 1600,
      minFNumber: 1.4,
      maxFNumber: 8.0,
      minFocalLengthMm: 24,
      maxFocalLengthMm: 200,
      maxSharpnessScore: 100.0,
    );

    final restored = SearchFilters.fromJson(original.toJson());

    expect(restored.personIds, original.personIds);
    expect(restored.textMode, original.textMode);
    expect(restored.query, original.query);
    expect(restored.tagIds, original.tagIds);
    expect(restored.cameraMake, original.cameraMake);
    expect(restored.locationCountry, original.locationCountry);
    expect(restored.locationCity, original.locationCity);
    expect(restored.startDate, original.startDate);
    expect(restored.endDate, original.endDate);
    expect(restored.mediaType, original.mediaType);
    expect(restored.favoritesOnly, original.favoritesOnly);
    expect(restored.notInAnyAlbum, original.notInAnyAlbum);
    expect(restored.minRating, original.minRating);
    expect(restored.colorLabels, original.colorLabels);
    expect(restored.minIso, original.minIso);
    expect(restored.maxIso, original.maxIso);
    expect(restored.minFNumber, original.minFNumber);
    expect(restored.maxFNumber, original.maxFNumber);
    expect(restored.minFocalLengthMm, original.minFocalLengthMm);
    expect(restored.maxFocalLengthMm, original.maxFocalLengthMm);
    expect(restored.maxSharpnessScore, original.maxSharpnessScore);
  });

  test('copyWith mit clear-Flags löscht die neuen optionalen Filterfelder gezielt', () {
    const filled = SearchFilters(
      minRating: 4,
      minIso: 100,
      maxIso: 1600,
      minFNumber: 1.4,
      maxFNumber: 8.0,
      minFocalLengthMm: 24,
      maxFocalLengthMm: 200,
      maxSharpnessScore: 100.0,
    );

    final cleared = filled.copyWith(
      clearMinRating: true,
      clearMinIso: true,
      clearMaxIso: true,
      clearMinFNumber: true,
      clearMaxFNumber: true,
      clearMinFocalLengthMm: true,
      clearMaxFocalLengthMm: true,
      clearMaxSharpnessScore: true,
    );

    expect(cleared.minRating, isNull);
    expect(cleared.minIso, isNull);
    expect(cleared.maxIso, isNull);
    expect(cleared.minFNumber, isNull);
    expect(cleared.maxFNumber, isNull);
    expect(cleared.minFocalLengthMm, isNull);
    expect(cleared.maxFocalLengthMm, isNull);
    expect(cleared.maxSharpnessScore, isNull);
    expect(cleared.isEmpty, isTrue);
  });

  test('leere/unbekannte Felder im JSON fallen sicher auf die Standardwerte zurück', () {
    final restored = SearchFilters.fromJson(const {});
    expect(restored.isEmpty, isTrue);
  });

  test('beschädigtes JSON liefert leere Filter statt abzustürzen', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.decodeSavedSearchFilters('{ das ist kein json'), const SearchFilters());
  });

  test('createSavedSearch/watchSavedSearches/deleteSavedSearch funktionieren zusammen', () async {
    final tempRoot = Directory.systemTemp.createTempSync('photo_vault_saved_search_test_');
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    const filters = SearchFilters(favoritesOnly: true, query: 'Strand');
    final id = const Uuid().v4();
    await db.createSavedSearch(id, 'Strandfotos', filters);

    final saved = await db.watchSavedSearches().first;
    expect(saved, hasLength(1));
    expect(saved.single.name, 'Strandfotos');
    final decoded = db.decodeSavedSearchFilters(saved.single.filtersJson);
    expect(decoded.favoritesOnly, isTrue);
    expect(decoded.query, 'Strand');

    await db.deleteSavedSearch(id);
    expect(await db.watchSavedSearches().first, isEmpty);
  });
}
