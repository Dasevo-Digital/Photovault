part of '../database.dart';

// Tabellen: Alben, Schlagwörter, gespeicherte Suchen.

@DataClassName('AlbumData')
class Albums extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get coverAssetId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class AlbumAssets extends Table {
  TextColumn get albumId => text()();
  TextColumn get assetId => text()();

  @override
  Set<Column> get primaryKey => {albumId, assetId};
}

@DataClassName('TagData')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Woher ein Schlagwort an einem Foto stammt.
///
/// **Der Grund für diese Spalte ist der gesperrte Ordner.** Beim Sperren
/// löscht die App alles, was sie aus dem Bildinhalt errechnet hat – sonst
/// bliebe der Inhalt in der unverschlüsselten Datenbank lesbar (siehe
/// [AppDatabase.clearDerivedContentData]). Schlagwörter waren davon
/// ausgenommen, und zwar aus einem guten Grund: Sie können von Hand
/// vergeben sein, und die zu löschen wäre echter Datenverlust.
///
/// Nur waren sie damit **nicht unterscheidbar**. Ein `Schlafzimmer`, das
/// die Bilderkennung an ein gesperrtes Foto gehängt hat, stand weiter im
/// Klartext – ein Befund der 15. Prüfrunde. Diese Spalte macht den
/// Unterschied sichtbar, und erst dadurch lässt sich die Regel überhaupt
/// anwenden.
class Tagquelle {
  /// Von Hand vergeben – oder durch eine Regel, die der Nutzer aufgestellt
  /// hat. Bleibt beim Sperren stehen.
  static const hand = 'hand';

  /// Von der Bilderkennung vorgeschlagen. Wird beim Sperren entfernt und
  /// nach dem Entsperren neu berechnet.
  static const ki = 'ki';
}

class AssetTags extends Table {
  TextColumn get assetId => text()();
  TextColumn get tagId => text()();

  /// [Tagquelle.hand] oder [Tagquelle.ki].
  ///
  /// Die Vorgabe ist bewusst `hand`: Wer eine Zeile anlegt, ohne sich zu
  /// äussern, meint den Fall, der niemals gelöscht wird.
  TextColumn get quelle => text().withDefault(const Constant(Tagquelle.hand))();

  @override
  Set<Column> get primaryKey => {assetId, tagId};
}

/// Editierbares Vokabular für automatisches KI-Tagging (siehe
/// AiTaggingService.suggestTags) – ursprünglich ein fester Konstanten-Array
/// (siehe [defaultAiTagVocabulary]), seit Schema v24 eine echte Tabelle
/// (analog zu [Tags], aber ohne Join-Tabelle, da hier keine Zuordnung zu
/// einzelnen Assets nötig ist, nur eine flache Begriffsliste). Bestehende
/// Installationen werden beim Upgrade auf v24 mit den bisherigen Begriffen
/// bestückt (siehe `_seedAiTagVocabulary`), damit sich das Tagging-Verhalten
/// nicht stillschweigend ändert.
@DataClassName('AiTagVocabularyData')
class AiTagVocabulary extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get term => text().unique()();
}

/// Eine gespeicherte Kombination aus Suchoptionen-Filtern ("Intelligentes
/// Album") – anders als ein normales Album keine feste Foto-Liste, sondern
/// läuft bei jedem Öffnen live gegen die aktuelle Bibliothek (siehe
/// [SearchFilters.toJson]/[AppDatabase.createSavedSearch]).
@DataClassName('SavedSearchData')
class SavedSearches extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get filtersJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
