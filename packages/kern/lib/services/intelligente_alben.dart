/// Intelligente Alben – gespeicherte Suchen – für Server und Telefon
/// (Issue #187). Am Rechner öffnet ein solches Album den Suchbildschirm mit
/// seinen Filtern; Browser und Handy zeigen die Treffer als Album.
library;

import 'dart:typed_data';

import '../db/database.dart';
import 'bildsuche.dart';
import 'search_filters.dart';
import 'suchlauf.dart';

/// Ob [f] den Text als Bildinhalt sucht und dafür einen Suchvektor braucht
/// (den Textteil von CLIP, den nur der Server hat).
bool brauchtSuchvektor(SearchFilters f) =>
    f.query.trim().isNotEmpty && f.textMode == SearchTextMode.context;

/// Die Aufnahmen eines intelligenten Albums: die gespeicherte Suche,
/// frisch gegen die Bibliothek – wie am Rechner. Sucht sie nach
/// Bildinhalt, braucht es [vektor]; ohne ihn bleibt die Liste leer.
Future<List<AssetData>> intelligentesAlbum(
  AppDatabase db,
  SearchFilters f, {
  Float32List? vektor,
}) async {
  if (!brauchtSuchvektor(f)) return db.searchAssets(f);
  if (vektor == null) return const [];
  final erlaubt = (await db.searchAssetIds(f.copyWith(query: ''))).toSet();
  return db.assetsByIds(
    rangfolgeDerBildsuche(
      vektor,
      suchkandidatenAus(
        await db.einbettungenImSpeicher(),
        await db.videoeinbettungenImSpeicher(),
      ),
      erlaubt,
    ),
  );
}

/// Was Browser und Handy als intelligentes Album merken: ihre Filter, der
/// Suchtext und wie er gemeint ist – als Bildinhalt oder als Wort
/// irgendwo in den Angaben.
SearchFilters alsGespeicherteSuche(
  Suchfilter filter, {
  String text = '',
  Suchart art = Suchart.text,
}) => filter.alsFilter.copyWith(
  query: text.trim(),
  textMode: art == Suchart.inhalt
      ? SearchTextMode.context
      : SearchTextMode.ueberall,
);
