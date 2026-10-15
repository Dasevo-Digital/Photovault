import '../l10n/app_localizations.dart';

export 'package:kern/services/groessentext.dart';

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
