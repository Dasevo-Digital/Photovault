/// Was zwischen dem Server und einer verbundenen App abgeglichen wird.
///
/// Abgeglichen wird Zeile um Zeile, und zwar alles, was zur Bibliothek
/// gehört – Aufnahmen, Personen, Alben, Ergebnisse der Auswertungen. Nicht
/// dazu gehört, was nur auf einem Rechner gilt: seine Sicherungen, seine
/// Aufträge, sein Zwischenspeicher, seine Ansicht. Die Volltextsuche baut
/// jede Datenbank aus ihren eigenen Aufnahmen selbst (Trigger auf `assets`).
///
/// Eine neue Tabelle muss hier eingeordnet werden; das prüft
/// `test/abgleichsplan_test.dart`.
class Abgleichsplan {
  const Abgleichsplan._();

  /// Tabellen, die nur auf dem Rechner gelten, auf dem sie entstehen.
  static const nurLokal = {
    'aufgabenlaeufe',
    'backup_records',
    'backup_settings',
    'restore_jobs',
    // Zwischenspeicher der Wanderwege aus OpenStreetMap.
    'wanderabfragen',
    'wanderpunkte',
  };

  /// Tabellen, von denen nur einige Spalten allen gehören. Die anderen
  /// (Ansicht, Sprache, Karte …) stellt jeder Rechner für sich ein.
  static const geteilteSpalten = {
    'app_settings': {
      'id',
      'auto_analyze_after_import',
      'face_similarity_threshold',
      'vorschlaege_automatisch_ab',
      'translate_captions',
      'translate_search_and_tags',
    },
    // PIN und Tresorschlüssel bleiben auf dem Gerät: Der Tresor ist Ende zu
    // Ende verschlüsselt, der Schlüssel kommt nie zum Server.
    'privacy_settings': {'id', 'protect_metadata'},
  };

  /// Die übrigen Spalten dieser Tabellen – ausdrücklich, damit eine neue
  /// Spalte nicht stillschweigend einer der beiden Seiten zufällt.
  static const lokaleSpalten = {
    'app_settings': {
      'theme_mode',
      'sprache',
      'watched_folder_path',
      'watched_folder_token',
      'kartenansicht',
      'carto_schluessel',
      'eigene_karte_name',
      'eigene_karte_url',
      'eigene_karte_nennung',
      'eigene_karte_stufe',
      'eigene_karte_zugestimmt',
      'karte_hochaufloesend',
      'gelaende_stimmung_nr',
      'gelaende_grund_nr',
      'gelaende_wege',
      'gelaende_beschriftung',
      'gelaende_hoehenlinien',
      'gelaende_wanderobjekte',
      'schwebe_vorschau',
      'stammbaum_ansicht',
      'stammbaum_person',
      'lebensbaum_richtung',
      'lebensbaum_stil',
      'lebensbaum_generationen',
      'lebensbaum_familie_oben',
      'lebensbaum_familie_unten',
      'lebensbaum_familie_kreis',
      'stammbaum_oben',
      'stammbaum_unten',
      'stammbaum_kreis',
      'zeitleiste_kachelstufe',
      'zeitleiste_form_nr',
      'zeitleiste_sortierung_nr',
      'zeitleiste_mit_tagen',
      'listenspalten',
      'max_gleichzeitig',
    },
    'privacy_settings': {
      'pin_hash',
      'pin_salt',
      'kdf_salt',
      'wrapped_master_key_nonce',
      'wrapped_master_key',
    },
  };

  /// Ob [tabelle] abgeglichen wird (ganz oder mit [geteilteSpalten]).
  static bool abgeglichen(String tabelle) =>
      !tabelle.startsWith('sqlite_') &&
      !tabelle.startsWith('pv_') &&
      !tabelle.startsWith('asset_search_fts') &&
      !nurLokal.contains(tabelle);
}
