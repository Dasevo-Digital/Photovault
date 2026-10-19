import 'package:drift/drift.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';

/// Die Orte der Bibliothek (Issue #173): Länder mit ihren Städten, je mit
/// Anzahl und Titelbild – für Browser und Telefon dieselbe Rechnung, wie
/// „Orte“ in Immich.
///
/// Gezählt wird, was im Raster eigenständig steht ([rasterSichtbar]):
/// ohne die Videohälfte eines Live Photos, ohne die Fotos hinter dem
/// Titelbild einer Serie, ohne Gesperrtes und Papierkorb. Die Namen
/// kommen aus der Umkehr-Geokodierung beim Import (`locationCountry`,
/// `locationCity`); wer keinen Ort hat, fehlt.

/// Ein Ort: ein Land oder eine Stadt darin.
typedef Ort = ({
  String land,

  /// `null` für das Land als Ganzes.
  String? stadt,
  int anzahl,

  /// Das Titelbild: der jüngste Favorit, sonst die jüngste Aufnahme.
  String titelbild,
  String? miniatur,
});

/// Ein Land mit seinen Städten, die grössten zuerst.
typedef Land = ({Ort land, List<Ort> staedte});

/// Alle Länder, die mit den meisten Aufnahmen zuerst.
Future<List<Land>> ortsuebersicht(AppDatabase db) async {
  // SQLite nimmt bei MAX() die übrigen Spalten aus der Zeile mit dem
  // grössten Wert – so kommt das Titelbild in derselben Abfrage mit.
  // Favoriten zählen vor dem Datum (Sekunden seit 1970 bleiben unter 1e11).
  const wahl = 'MAX(is_favorite * 100000000000 + file_created_at)';
  Ort ort(QueryRow z, {required bool mitStadt}) => (
    land: z.read<String>('land'),
    stadt: mitStadt ? z.readNullable<String>('stadt') : null,
    anzahl: z.read<int>('anzahl'),
    titelbild: z.read<String>('id'),
    miniatur: z.readNullable<String>('thumbnail_relative_path'),
  );
  final laender = await db
      .customSelect(
        'SELECT location_country AS land, COUNT(*) AS anzahl, $wahl, '
        'id, thumbnail_relative_path FROM assets '
        'WHERE $rasterSichtbar AND location_country IS NOT NULL '
        "AND location_country != '' GROUP BY location_country",
        readsFrom: {db.assets},
      )
      .get();
  final staedte = await db
      .customSelect(
        'SELECT location_country AS land, location_city AS stadt, '
        'COUNT(*) AS anzahl, $wahl, id, thumbnail_relative_path FROM assets '
        'WHERE $rasterSichtbar AND location_country IS NOT NULL '
        "AND location_country != '' AND location_city IS NOT NULL "
        "AND location_city != '' GROUP BY location_country, location_city",
        readsFrom: {db.assets},
      )
      .get();
  final jeLand = <String, List<Ort>>{};
  for (final z in staedte) {
    final o = ort(z, mitStadt: true);
    jeLand.putIfAbsent(o.land, () => []).add(o);
  }
  int groesste(Ort a, Ort b) {
    final n = b.anzahl.compareTo(a.anzahl);
    return n != 0 ? n : (a.stadt ?? a.land).compareTo(b.stadt ?? b.land);
  }

  return [
    for (final z in laender)
      (
        land: ort(z, mitStadt: false),
        staedte: (jeLand[z.read<String>('land')] ?? [])..sort(groesste),
      ),
  ]..sort((a, b) => groesste(a.land, b.land));
}

/// Die Aufnahmen eines Landes oder einer Stadt darin, die jüngste zuerst.
Future<List<Rasterzeile>> aufnahmenAmOrt(
  AppDatabase db, {
  required String land,
  String? stadt,
}) async =>
    (await db
            .customSelect(
              'SELECT $rasterSpalten FROM assets WHERE $rasterSichtbar '
              'AND location_country = ?${stadt == null ? '' : ' AND location_city = ?'} '
              'ORDER BY file_created_at DESC',
              variables: [Variable(land), if (stadt != null) Variable(stadt)],
              readsFrom: {db.assets},
            )
            .get())
        .map(Rasterzeile.ausZeile)
        .toList();
