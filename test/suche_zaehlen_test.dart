import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/search_filters.dart';

/// **Die Zahl in der Filterleiste und die Liste dahinter müssen dasselbe
/// meinen.**
///
/// Bis Fassung 3.14.0 wurde die Zahl aus `searchAssets(...).length`
/// gewonnen – erst alle Treffer vollständig laden, dann zählen. An der
/// echten Bibliothek sind das bei einem weiten Textfilter 7163 Zeilen mit
/// je 56 Spalten, und die Leiste rechnet bei **jedem Tastendruck** neu
/// (90,2 gegen 1,9 ms).
///
/// Eine eigene Zählabfrage ist schnell – und sofort eine zweite Kopie der
/// Suchregeln. Dieser Test hält beide aneinander: Was gezählt wird, muss
/// das sein, was auch gefunden wird.
void main() {
  late AppDatabase db;
  var laufend = 0;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> foto({
    String? beschreibung,
    String? ocr,
    bool favorit = false,
    String typ = 'IMAGE',
    bool papierkorb = false,
    bool gesperrt = false,
    DateTime? wann,
  }) async {
    final id = 'a${laufend++}';
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: typ,
          fileCreatedAt: wann ?? DateTime(2026, 5, 1),
          importedAt: DateTime(2026, 5, 1),
          description: Value(beschreibung),
          ocrText: Value(ocr),
          isFavorite: Value(favorit),
          isTrashed: Value(papierkorb),
          isLocked: Value(gesperrt),
        ));
    return id;
  }

  Future<void> bestand() async {
    await foto(beschreibung: 'Hund am Strand', favorit: true);
    await foto(beschreibung: 'Hund im Garten');
    await foto(beschreibung: 'Katze im Garten', ocr: 'Ausfahrt freihalten');
    await foto(typ: 'VIDEO', beschreibung: 'Hund rennt');
    await foto(beschreibung: 'Hund im Papierkorb', papierkorb: true);
    await foto(beschreibung: 'Hund im Tresor', gesperrt: true);
    await foto(wann: DateTime(2019, 3, 3), beschreibung: 'altes Bild');
  }

  final faelle = <String, SearchFilters>{
    'ohne alles': const SearchFilters(),
    'nur Favoriten': const SearchFilters(favoritesOnly: true),
    'nur Videos': const SearchFilters(mediaType: MediaTypeFilter.video),
    'nur Bilder': const SearchFilters(mediaType: MediaTypeFilter.image),
    'Text „Hund"': const SearchFilters(
        query: 'Hund', textMode: SearchTextMode.description),
    'Text „Garten"': const SearchFilters(
        query: 'Garten', textMode: SearchTextMode.description),
    'Text ohne Treffer': const SearchFilters(
        query: 'Nashorn', textMode: SearchTextMode.description),
    'Texterkennung': const SearchFilters(
        query: 'Ausfahrt', textMode: SearchTextMode.ocr),
    'Text und Favorit': const SearchFilters(
        query: 'Hund',
        textMode: SearchTextMode.description,
        favoritesOnly: true),
  };

  group('gezaehlt ist gefunden', () {
    for (final fall in faelle.entries) {
      test(fall.key, () async {
        await bestand();
        final gefunden = await db.searchAssets(fall.value);
        final gezaehlt = await db.countSearchResults(fall.value);
        expect(gezaehlt, gefunden.length,
            reason: 'die Zahl verspricht etwas anderes als die Liste');
      });
    }
  });

  test('Papierkorb und Tresor zaehlen bei keinem Filter mit', () async {
    await bestand();
    // Sechs sichtbare Aufnahmen, zwei davon ausgeblendet.
    expect(await db.countSearchResults(const SearchFilters()), 5);
  });

  test('eine leere Vorauswahl ergibt null, ohne die Datenbank zu fragen',
      () async {
    await bestand();
    expect(
        await db.countSearchResults(const SearchFilters(),
            restrictToIds: const []),
        0);
  });

  test('eine Vorauswahl schneidet mit dem Textfilter', () async {
    final einer = await foto(beschreibung: 'Hund am Strand');
    await foto(beschreibung: 'Hund im Garten');
    expect(
        await db.countSearchResults(
            const SearchFilters(
                query: 'Hund', textMode: SearchTextMode.description),
            restrictToIds: [einer]),
        1);
  });
}
