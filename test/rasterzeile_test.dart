// Die schmale Rasterzeile – und die eine Stelle, an der sie lügen könnte.
//
// Sie liest die Spalten von Hand aus einer rohen Abfragezeile, statt sich
// von drift ein `AssetData` bauen zu lassen. Damit steht sie neben der
// Wahrheit, statt sie zu sein: Ein Tippfehler in einem Spaltennamen, ein
// falsch gedeuteter Zeitstempel oder eine vergessene Spalte fiele sonst
// erst am Bildschirm auf. Geprüft wird deshalb gegen genau die Zeile, die
// der Abfragebauer liefert.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> lege(String id, DateTime wann,
      {String type = 'IMAGE',
      bool favorit = false,
      bool gesperrt = false,
      int bewertung = 0,
      String? farbe,
      String? verknuepft,
      int? breite,
      int? hoehe,
      double? dauer,
      double? lat,
      double? lon,
      String? kamera,
      String? stapel,
      bool titelbild = false,
      int? stapelgroesse,
      String? vorschau}) {
    return db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'o/$id.jpg',
          checksum: 'c$id',
          type: type,
          fileCreatedAt: wann,
          importedAt: DateTime(2026),
          isFavorite: Value(favorit),
          isLocked: Value(gesperrt),
          rating: Value(bewertung),
          colorLabel: Value(farbe),
          linkedAssetId: Value(verknuepft),
          widthPx: Value(breite),
          heightPx: Value(hoehe),
          durationSeconds: Value(dauer),
          latitude: Value(lat),
          longitude: Value(lon),
          cameraMake: Value(kamera),
          stackId: Value(stapel),
          isStackCover: Value(titelbild),
          stackSize: Value(stapelgroesse),
          thumbnailRelativePath: Value(vorschau),
        ));
  }

  test('jedes Feld kommt so an wie über den Abfragebauer', () async {
    // Ein Datensatz, in dem jedes Feld belegt ist – sonst prüfte der Test
    // hauptsächlich, dass null gleich null ist.
    final wann = DateTime(2026, 3, 12, 14, 37, 5);
    // Ein Live-Photo-Standbild: Es traegt eine Verknuepfung UND kommt
    // durch den Filter. Eine Videohaelfte taete das nicht - siehe den
    // Test weiter unten.
    await lege('a1', wann,
        favorit: true,
        bewertung: 4,
        farbe: 'rot',
        verknuepft: 'b9',
        breite: 4032,
        hoehe: 3024,
        dauer: 12.5,
        lat: 51.87,
        lon: 10.68,
        kamera: 'Apple',
        stapel: 's1',
        titelbild: true,
        stapelgroesse: 7,
        vorschau: 't/a1.jpg');

    final voll = (await db.watchTimeline().first).single;
    final schmal = (await db.watchRasterzeilen().first).single;
    final abgeleitet = Rasterzeile.aus(voll);

    void gleich(String name, Object? a, Object? b) =>
        expect(a, b, reason: name);

    gleich('id', schmal.id, abgeleitet.id);
    gleich('type', schmal.type, abgeleitet.type);
    gleich('originalFileName', schmal.originalFileName,
        abgeleitet.originalFileName);
    gleich('relativePath', schmal.relativePath, abgeleitet.relativePath);
    gleich('thumbnailRelativePath', schmal.thumbnailRelativePath,
        abgeleitet.thumbnailRelativePath);
    gleich('fileCreatedAt', schmal.fileCreatedAt, abgeleitet.fileCreatedAt);
    gleich('durationSeconds', schmal.durationSeconds,
        abgeleitet.durationSeconds);
    gleich('isFavorite', schmal.isFavorite, abgeleitet.isFavorite);
    gleich('isStackCover', schmal.isStackCover, abgeleitet.isStackCover);
    gleich('stackId', schmal.stackId, abgeleitet.stackId);
    gleich('stackSize', schmal.stackSize, abgeleitet.stackSize);
    gleich('linkedAssetId', schmal.linkedAssetId, abgeleitet.linkedAssetId);
    gleich('rating', schmal.rating, abgeleitet.rating);
    gleich('colorLabel', schmal.colorLabel, abgeleitet.colorLabel);
    gleich('widthPx', schmal.widthPx, abgeleitet.widthPx);
    gleich('heightPx', schmal.heightPx, abgeleitet.heightPx);
    gleich('latitude', schmal.latitude, abgeleitet.latitude);
    gleich('longitude', schmal.longitude, abgeleitet.longitude);
    gleich('cameraMake', schmal.cameraMake, abgeleitet.cameraMake);
    gleich('isLocked', schmal.isLocked, abgeleitet.isLocked);
  });

  test('das Aufnahmedatum kommt auf die Sekunde genau an', () async {
    // Die Falle: In der Datenbank stehen SEKUNDEN, nicht Millisekunden.
    // Wer das verwechselt, bekommt das Jahr 1970 – und damit alle
    // Aufnahmen in einer einzigen Monatsgruppe. Genau dieser Fehler ist
    // in dieser Bibliothek schon einmal in einem Messskript passiert.
    for (final wann in [
      DateTime(1998, 12, 31, 23, 59, 59),
      DateTime(2026, 3, 12, 14, 37, 5),
      DateTime(2038, 1, 20, 3, 14, 8),
    ]) {
      await db.delete(db.assets).go();
      await lege('a1', wann);
      final schmal = (await db.watchRasterzeilen().first).single;
      expect(schmal.fileCreatedAt, wann, reason: 'bei $wann');
      expect(schmal.fileCreatedAt.year, wann.year);
    }
  });

  test('leere Felder bleiben leer statt zu Platzhaltern zu werden',
      () async {
    await lege('a1', DateTime(2026, 3, 12));
    final schmal = (await db.watchRasterzeilen().first).single;
    expect(schmal.thumbnailRelativePath, isNull);
    expect(schmal.durationSeconds, isNull);
    expect(schmal.widthPx, isNull);
    expect(schmal.latitude, isNull);
    expect(schmal.cameraMake, isNull);
    expect(schmal.stackId, isNull);
    expect(schmal.colorLabel, isNull);
    expect(schmal.rating, 0);
    expect(schmal.isFavorite, isFalse);
  });

  group('dieselbe Auswahl wie die volle Abfrage', () {
    test('Papierkorb und Tresor bleiben draussen', () async {
      await lege('sichtbar', DateTime(2026, 3, 3));
      await lege('gesperrt', DateTime(2026, 3, 2), gesperrt: true);
      await lege('papierkorb', DateTime(2026, 3, 1));
      await db.moveToTrash(['papierkorb']);

      final schmal = await db.watchRasterzeilen().first;
      final voll = await db.watchTimeline().first;
      expect(schmal.map((z) => z.id), voll.map((a) => a.id));
      expect(schmal.map((z) => z.id), ['sichtbar']);
    });

    test('die Videohälfte eines Live Photos bleibt draussen', () async {
      await lege('foto', DateTime(2026, 3, 3), verknuepft: 'video');
      await lege('video', DateTime(2026, 3, 3),
          type: 'VIDEO', verknuepft: 'foto');
      final schmal = await db.watchRasterzeilen().first;
      final voll = await db.watchTimeline().first;
      expect(schmal.map((z) => z.id), voll.map((a) => a.id));
      expect(schmal.map((z) => z.id), ['foto']);
    });

    test('Reihenfolge, Grenze und Favoritenfilter stimmen überein',
        () async {
      for (var i = 0; i < 6; i++) {
        await lege('a$i', DateTime(2026, 3, 1 + i), favorit: i.isEven);
      }
      expect((await db.watchRasterzeilen().first).map((z) => z.id),
          (await db.watchTimeline().first).map((a) => a.id));
      expect((await db.watchRasterzeilen(limit: 3).first).map((z) => z.id),
          (await db.watchTimeline(limit: 3).first).map((a) => a.id));
      expect(
          (await db.watchRasterzeilen(favoritesOnly: true).first)
              .map((z) => z.id),
          (await db.watchTimeline(favoritesOnly: true).first).map((a) => a.id));
    });

    test('der Strom meldet sich, wenn sich etwas ändert', () async {
      await lege('a1', DateTime(2026, 3, 1));
      final strom = db.watchRasterzeilen();
      expect((await strom.first).length, 1);
      await lege('a2', DateTime(2026, 3, 2));
      await expectLater(
          strom.firstWhere((z) => z.length == 2).timeout(
              const Duration(seconds: 5)),
          completes);
    });
  });
}
