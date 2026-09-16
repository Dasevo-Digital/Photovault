import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/search_filters.dart';

/// **Zwei Wege auf denselben Bedingungen.**
///
/// `searchAssets` liefert volle Zeilen, `searchAssetIds` nur die
/// Kennungen – beide bauen ihre Bedingungen aus derselben Liste. Dieser
/// Test hält fest, dass sie auch dieselbe Menge treffen: Der Umbau war
/// mechanisch (24 Filter), und ein einzelner verrutschter Vergleich
/// fiele sonst erst dem Nutzer auf, dessen Suche etwas anderes findet
/// als die Suche daneben.
void main() {
  late AppDatabase db;

  Future<void> foto(
    String id, {
    DateTime? datum,
    bool favorit = false,
    int bewertung = 0,
    String? kamera,
    String? land,
    String? beschreibung,
    String? ocr,
    String art = 'IMAGE',
    bool geschaetzt = false,
    int? iso,
  }) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            relativePath: 'originals/$id.jpg',
            originalFileName: '$id.jpg',
            type: art,
            checksum: 'c$id',
            fileCreatedAt: datum ?? DateTime(2024, 5, 5),
            importedAt: DateTime(2024, 6, 1),
            isFavorite: Value(favorit),
            rating: Value(bewertung),
            cameraMake: Value(kamera),
            locationCountry: Value(land),
            description: Value(beschreibung ?? ''),
            ocrText: Value(ocr),
            datumGeschaetzt: Value(geschaetzt),
            iso: Value(iso),
          ));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await foto('a', datum: DateTime(2020, 1, 1), favorit: true, bewertung: 5,
        kamera: 'Canon', land: 'Deutschland', beschreibung: 'Berg im Nebel',
        iso: 100);
    await foto('b', datum: DateTime(2022, 7, 7), bewertung: 3, kamera: 'Nikon',
        land: 'Italien', ocr: 'Bahnhof Berlin', iso: 800);
    await foto('c', datum: DateTime(2024, 3, 3), geschaetzt: true, iso: 3200);
    await foto('d', datum: DateTime(2025, 9, 9), art: 'VIDEO', favorit: true);
    await foto('e', datum: DateTime(2019, 2, 2), bewertung: 1, kamera: 'Canon',
        land: 'Deutschland');
  });
  tearDown(() => db.close());

  /// Jeder Filter einzeln – und zwei, die sich überschneiden.
  final faelle = <String, SearchFilters>{
    'ohne alles': const SearchFilters(),
    'nur Favoriten': const SearchFilters(favoritesOnly: true),
    'Bewertung ab 3': const SearchFilters(minRating: 3),
    'Kamera Canon': const SearchFilters(cameraMake: 'Canon'),
    'Land Deutschland': const SearchFilters(locationCountry: 'Deutschland'),
    'nur Videos': const SearchFilters(mediaType: MediaTypeFilter.video),
    'nur Bilder': const SearchFilters(mediaType: MediaTypeFilter.image),
    'geschätztes Datum': const SearchFilters(nurGeschaetztesDatum: true),
    'Dateiname': const SearchFilters(
        query: 'a.jpg', textMode: SearchTextMode.filename),
    'Beschreibung': const SearchFilters(
        query: 'Nebel', textMode: SearchTextMode.description),
    'Schrift im Bild':
        const SearchFilters(query: 'Bahnhof', textMode: SearchTextMode.ocr),
    'Kontext (Text greift NICHT)':
        const SearchFilters(query: 'Nebel', textMode: SearchTextMode.context),
    'ISO 200 bis 1000':
        const SearchFilters(minIso: 200, maxIso: 1000),
    'ohne Schlagwort': const SearchFilters(noTag: true),
    'in keinem Album': const SearchFilters(notInAnyAlbum: true),
    'Canon UND Favorit':
        const SearchFilters(cameraMake: 'Canon', favoritesOnly: true),
  };

  faelle.forEach((name, filter) {
    test('dieselbe Menge: $name', () async {
      final voll = (await db.searchAssets(filter)).map((a) => a.id).toSet();
      final kennungen = (await db.searchAssetIds(filter)).toSet();
      expect(kennungen, voll, reason: 'die beiden Wege trennen sich bei „$name"');
    });
  });

  test('Zeitraum und restrictToIds ebenso', () async {
    final filter = SearchFilters(
        startDate: DateTime(2020), endDate: DateTime(2024, 12, 31));
    expect((await db.searchAssetIds(filter)).toSet(),
        (await db.searchAssets(filter)).map((a) => a.id).toSet());

    const auswahl = ['a', 'b', 'zz'];
    expect(
        (await db.searchAssetIds(const SearchFilters(),
                restrictToIds: auswahl))
            .toSet(),
        (await db.searchAssets(const SearchFilters(), restrictToIds: auswahl))
            .map((a) => a.id)
            .toSet());
  });

  test('und sie ist nicht leer – sonst prüfte der Test nichts', () async {
    expect(await db.searchAssetIds(const SearchFilters()), hasLength(5));
    expect(await db.searchAssetIds(const SearchFilters(cameraMake: 'Canon')),
        hasLength(2));
  });
}
