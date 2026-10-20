import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'bildsuche.dart';
import 'search_filters.dart';

/// Die Suche in Browser (über den Server) und Telefon: nach Bildinhalt
/// oder Text, eingeschränkt durch dieselben Filter wie am Rechner – und
/// auch ohne Suchtext, nur nach Filtern („alle Videos mit Anna 2024 in
/// Italien“).

enum Suchart { inhalt, text }

/// Die Filter, die Browser und Telefon anbieten – ein Ausschnitt aus
/// [SearchFilters], der sich als Adresse schreiben lässt.
class Suchfilter {
  const Suchfilter({
    this.personen = const [],
    this.land,
    this.stadt,
    this.von,
    this.bis,
    this.art = MediaTypeFilter.all,
    this.favoriten = false,
    this.kamera,
  });

  /// Alle müssen auf der Aufnahme sein.
  final List<String> personen;
  final String? land;
  final String? stadt;

  /// Einschliesslich beider Tage.
  final DateTime? von;
  final DateTime? bis;
  final MediaTypeFilter art;
  final bool favoriten;

  /// Das Kameramodell.
  final String? kamera;

  bool get leer =>
      personen.isEmpty &&
      land == null &&
      stadt == null &&
      von == null &&
      bis == null &&
      art == MediaTypeFilter.all &&
      !favoriten &&
      kamera == null;

  SearchFilters get alsFilter => SearchFilters(
    personIds: personen,
    locationCountry: land,
    locationCity: stadt,
    startDate: von,
    endDate: bis,
    mediaType: art,
    favoritesOnly: favoriten,
    cameraModel: kamera,
  );

  /// Für die Adresse: `person` (mehrfach), `land`, `stadt`, `von`, `bis`
  /// (`JJJJ-MM-TT`), `art` (`bild`/`video`), `favoriten=1`, `kamera`.
  static Suchfilter ausParametern(Map<String, List<String>> p) {
    String? eins(String name) {
      final w = p[name];
      final s = w == null || w.isEmpty ? '' : w.first.trim();
      return s.isEmpty ? null : s;
    }

    DateTime? tag(String name) {
      final s = eins(name);
      return s == null ? null : DateTime.tryParse(s);
    }

    return Suchfilter(
      personen: [
        for (final x in p['person'] ?? const <String>[])
          if (x.trim().isNotEmpty) x.trim(),
      ],
      land: eins('land'),
      stadt: eins('stadt'),
      von: tag('von'),
      bis: tag('bis'),
      art: switch (eins('art')) {
        'bild' => MediaTypeFilter.image,
        'video' => MediaTypeFilter.video,
        _ => MediaTypeFilter.all,
      },
      favoriten: eins('favoriten') == '1',
      kamera: eins('kamera'),
    );
  }
}

/// Sucht. Ohne [text] nur nach [filter], nach Datum geordnet; nach Text
/// in Namen, Beschreibungen, erkanntem Text, Schlagwörtern, Orten und
/// Personen; nach Inhalt mit dem eingebetteten Suchtext [vektor], nach
/// Ähnlichkeit geordnet – Videos mit allen ihren Standbildern.
Future<List<AssetData>> suchlauf(
  AppDatabase db, {
  String text = '',
  Suchart art = Suchart.text,
  Suchfilter filter = const Suchfilter(),
  Float32List? vektor,
}) async => db.assetsByIds(
  await suchlaufKennungen(
    db,
    text: text,
    art: art,
    filter: filter,
    vektor: vektor,
  ),
);

/// [suchlauf], aber nur die Kennungen in ihrer Reihenfolge – nach Datum
/// oder, bei der Inhaltssuche, nach Ähnlichkeit. Damit laden Browser und
/// Handy die Zeilen seitenweise statt alle auf einmal (Issue #186): An
/// 45.000 künstlichen Aufnahmen brauchte ein häufiges Wort mit allen
/// 36.000 vollen Zeilen 390 ms.
Future<List<String>> suchlaufKennungen(
  AppDatabase db, {
  String text = '',
  Suchart art = Suchart.text,
  Suchfilter filter = const Suchfilter(),
  Float32List? vektor,
}) async {
  final f = filter.alsFilter;
  if (text.trim().isEmpty) return db.searchAssetIdsNachDatum(f);
  if (art == Suchart.text) {
    final ids = await db.textfundstellen(text.trim());
    return ids.isEmpty
        ? const []
        : db.searchAssetIdsNachDatum(f, restrictToIds: ids);
  }
  if (vektor == null) return const [];
  final erlaubt = (await db.searchAssetIds(f)).toSet();
  return rangfolgeDerBildsuche(
    vektor,
    suchkandidatenAus(
      await db.einbettungenImSpeicher(),
      await db.videoeinbettungenImSpeicher(),
    ),
    erlaubt,
  );
}

/// Was sich in den Filtern wählen lässt: die benannten Personen, die
/// Länder mit ihren Städten und die Kameramodelle – nur, was in der
/// Bibliothek vorkommt.
typedef Suchauswahl = ({
  List<PersonData> personen,
  List<({String land, List<String> staedte})> orte,
  List<String> kameras,
});

Future<Suchauswahl> suchauswahl(AppDatabase db) async {
  final personen = [
    for (final p in await db.select(db.people).get())
      if (p.name.trim().isNotEmpty) p,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final zeilen =
      await (db.selectOnly(db.assets, distinct: true)
            ..addColumns([db.assets.locationCountry, db.assets.locationCity])
            ..where(
              db.assets.locationCountry.isNotNull() &
                  db.assets.isTrashed.equals(false) &
                  db.assets.isLocked.equals(false),
            ))
          .get();
  final staedte = <String, Set<String>>{};
  for (final z in zeilen) {
    final land = z.read(db.assets.locationCountry)!;
    final stadt = z.read(db.assets.locationCity);
    final s = staedte.putIfAbsent(land, () => {});
    if (stadt != null && stadt.isNotEmpty) s.add(stadt);
  }
  return (
    personen: personen,
    orte: [
      for (final land in staedte.keys.toList()..sort())
        (land: land, staedte: staedte[land]!.toList()..sort()),
    ],
    kameras: await db.distinctCameraModels(),
  );
}
