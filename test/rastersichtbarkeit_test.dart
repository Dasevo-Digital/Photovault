import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';

/// **Dieselbe Regel auf beiden Wegen.**
///
/// Wer im Raster eigenständig erscheint, steht zweimal geschrieben: als
/// drift-Ausdruck (`_isPrimaryGridEntry`, benutzt von `watchTimeline`
/// und `searchAssets`) und als SQL-Text (`rasterSichtbar`, benutzt von
/// den schmalen Abfragen, aus denen das Raster selbst lebt).
///
/// Nachgeschrieben fehlte dem SQL-Text die zweite Hälfte: kein
/// Stapelmitglied ausser dem Titelbild. Das Raster zeigte damit 144
/// Aufnahmen der gewachsenen Bibliothek, die die Listenansicht daneben
/// korrekt ausblendete – die Serienzusammenfassung wirkte in genau der
/// Ansicht nicht, für die es sie gibt. Gefunden hat das keine
/// Fehlermeldung, sondern zwei Zahlen, die gleich sein mussten und es
/// nicht waren.
///
/// `stacking_test` prüfte `watchTimeline` – die Methode, die das Raster
/// seit dem Umbau auf schmale Zeilen nicht mehr benutzt.
void main() {
  late AppDatabase db;

  Future<void> foto(String id,
          {String? stapel, bool titelbild = false, String art = 'IMAGE',
          String? verknuepft}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            relativePath: 'originals/$id.jpg',
            originalFileName: '$id.jpg',
            type: art,
            checksum: 'c$id',
            fileCreatedAt: DateTime(2024, 5, 5),
            importedAt: DateTime(2024, 6, 1),
            stackId: Value(stapel),
            isStackCover: Value(titelbild),
            linkedAssetId: Value(verknuepft),
          ));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await foto('einzeln');
    await foto('titel', stapel: 's1', titelbild: true);
    await foto('mitglied1', stapel: 's1');
    await foto('mitglied2', stapel: 's1');
    // Die andere Hälfte der Regel: der .mov-Partner eines Live Photos.
    await foto('livefoto');
    await foto('livevideo', art: 'VIDEO', verknuepft: 'livefoto');
  });
  tearDown(() => db.close());

  Set<String> ausZeilen(List<Rasterzeile> z) => {for (final r in z) r.id};

  test('das Raster zeigt Titelbild und Einzelne, keine Mitglieder', () async {
    expect(ausZeilen(await db.watchRasterzeilen().first),
        {'einzeln', 'titel', 'livefoto'});
  });

  test('und die Liste daneben zeigt genau dieselben', () async {
    final liste = {for (final a in await db.watchTimeline().first) a.id};
    expect(ausZeilen(await db.watchRasterzeilen().first), liste,
        reason: 'Raster und Listenansicht dürfen sich nicht trennen');
  });

  test('der Fotowähler ebenso', () async {
    expect(ausZeilen(await db.alleRasterzeilen()),
        {for (final a in await db.alleAufnahmen()) a.id});
  });

  test('und der Zeitraum-Ausschnitt ebenso', () async {
    final von = DateTime(2024), bis = DateTime(2024, 12, 31);
    expect(ausZeilen(await db.rasterzeilenImZeitraum(von, bis)),
        {for (final a in await db.aufnahmenImZeitraum(von, bis)) a.id});
    expect(await db.zahlImZeitraum(von, bis),
        (await db.aufnahmenImZeitraum(von, bis)).length,
        reason: 'der Zähler zählt dieselbe Menge, die die Liste zeigt');
  });

  test('nach dem Auflösen sind alle wieder einzeln zu sehen', () async {
    await db.unstackAssets('s1');
    expect(ausZeilen(await db.watchRasterzeilen().first),
        {'einzeln', 'titel', 'mitglied1', 'mitglied2', 'livefoto'});
  });
}
