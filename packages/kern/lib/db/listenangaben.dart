import 'package:drift/drift.dart';

import 'database.dart';

/// Was die Liste der Aufnahmen über die [Rasterzeile] hinaus zeigt
/// (Issue #195): Kameramodell, Objektiv, Belichtung, Dateigrösse, Ort und
/// ob das Datum geschätzt ist.
///
/// **Neben der Rasterzeile, nicht in ihr.** Die Kachelwand braucht diese
/// Spalten nicht, und dort zählt jede: Die schmale Zeile war an der echten
/// Bibliothek 30 statt 80 ms. Die Liste holt sie für die Aufnahmen, die
/// sie zeigt, dazu.
class Listenangaben {
  const Listenangaben({
    this.kameramodell,
    this.objektiv,
    this.brennweite,
    this.blende,
    this.zeit,
    this.iso,
    this.bytes = 0,
    this.stadt,
    this.land,
    this.geschaetzt = false,
  });

  final String? kameramodell;
  final String? objektiv;
  final double? brennweite;
  final double? blende;
  final double? zeit;
  final int? iso;
  final int bytes;
  final String? stadt;
  final String? land;
  final bool geschaetzt;
}

extension ListenangabenAbfrage on AppDatabase {
  /// Die [Listenangaben] zu [ids] – in Stücken, weil SQLite nicht beliebig
  /// viele Platzhalter nimmt.
  Future<Map<String, Listenangaben>> listenangaben(List<String> ids) async {
    final aus = <String, Listenangaben>{};
    for (var i = 0; i < ids.length; i += 500) {
      final ende = i + 500 < ids.length ? i + 500 : ids.length;
      final stueck = ids.sublist(i, ende);
      final zeilen = await customSelect(
        'SELECT id, camera_model, lens_model, focal_length_mm, f_number, '
        'exposure_time_seconds, iso, file_size_bytes, location_city, '
        'location_country, datum_geschaetzt FROM assets '
        'WHERE id IN (${List.filled(stueck.length, '?').join(', ')})',
        variables: [for (final id in stueck) Variable<String>(id)],
        readsFrom: {assets},
      ).get();
      for (final z in zeilen) {
        aus[z.read<String>('id')] = Listenangaben(
          kameramodell: z.readNullable<String>('camera_model'),
          objektiv: z.readNullable<String>('lens_model'),
          brennweite: z.readNullable<double>('focal_length_mm'),
          blende: z.readNullable<double>('f_number'),
          zeit: z.readNullable<double>('exposure_time_seconds'),
          iso: z.readNullable<int>('iso'),
          bytes: z.readNullable<int>('file_size_bytes') ?? 0,
          stadt: z.readNullable<String>('location_city'),
          land: z.readNullable<String>('location_country'),
          geschaetzt: z.readNullable<bool>('datum_geschaetzt') ?? false,
        );
      }
    }
    return aus;
  }
}
