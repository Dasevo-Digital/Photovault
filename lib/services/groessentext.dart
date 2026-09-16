import '../l10n/app_localizations.dart';

/// Eine Byte-Zahl als Text, den man lesen kann.
///
/// Stand bisher als private Methode im Einstellungs-Bildschirm. Der
/// Papierkorb braucht sie jetzt auch, und zwei Fassungen derselben
/// Rundungsregel laufen früher oder später auseinander – dieselbe
/// Überlegung wie bei `LibraryState.dateienVon`.
///
/// Stufen bewusst bei 1024 und nicht bei 1000: Es geht um belegten Platz,
/// und den zeigt sowohl der Finder als auch der Dateimanager unter Linux
/// auf dieselbe Weise an.
String groessentext(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Wie ein Posten der Speicheraufstellung in der Oberflächensprache
/// heisst – siehe [Bibliotheksbelegung.posten].
///
/// Eine Zuordnung von Hand und keine Namensableitung: Die Schlüssel sind
/// Ordnernamen und damit Technik, die Beschriftungen sind Sprache. Ein
/// unbekannter Schlüssel bekommt seinen Ordnernamen – sichtbar falsch ist
/// besser als unsichtbar fehlend.
String belegungName(AppTexte t, String schluessel) => switch (schluessel) {
      'originals' => t.belegung_originals,
      'previews' => t.belegung_previews,
      'thumbnails' => t.belegung_thumbnails,
      'developed' => t.belegung_developed,
      'restored' => t.belegung_restored,
      'trimmed' => t.belegung_trimmed,
      'masks' => t.belegung_masks,
      'faces' => t.belegung_faces,
      'luts' => t.belegung_luts,
      'trash' => t.belegung_trash,
      'datenbank' => t.belegung_datenbank,
      'sonstiges' => t.belegung_sonstiges,
      _ => schluessel,
    };
