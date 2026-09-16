/// Wonach eine Kachelwand ihre Aufnahmen ordnet.
///
/// **Warum das hier steht und nicht bei der Zeitleiste.** Dieselbe
/// Begründung wie bei [zeitleisteKachelstufen] in `rasterstufen.dart`:
/// Die Wahl wird in den Einstellungen abgelegt, und die Datenbank darf
/// keinen Baustein der Oberfläche einlesen. Die Datenbank braucht die
/// Reihenfolge als SQL, die Suche als Vergleicher in Dart – beide
/// Fassungen liegen deshalb nebeneinander, damit sie nicht auseinander
/// laufen können.
library;

import '../db/database.dart' show AssetData;

/// Die wählbaren Reihenfolgen.
///
/// **Warum nur diese sechs.** Jede weitere Spalte kostet nichts an
/// Rechnung, aber jede kostet eine Zeile im Menü – und was hier fehlt,
/// findet man über die Suchoptionen ohnehin. Aufnahmedatum in beiden
/// Richtungen, weil das die eigentliche Bitte war; Importdatum, weil
/// „was ist zuletzt dazugekommen" nichts mit dem Aufnahmedatum zu tun
/// hat; Name, Bewertung und Dateigrösse, weil sie ohne Umweg
/// beantworten, was ein Filter nur einkreisen könnte.
enum Rastersortierung {
  /// Aufnahmedatum, neueste zuerst – die Vorgabe und das bisherige Bild.
  aufnahmeNeu,

  /// Aufnahmedatum, älteste zuerst.
  aufnahmeAlt,

  /// Wann die Datei in die Bibliothek kam, zuletzt Hinzugekommenes oben.
  importNeu,

  /// Dateiname, A–Z und ohne Rücksicht auf Gross-/Kleinschreibung.
  name,

  /// Bewertung, beste zuerst.
  bewertung,

  /// Dateigrösse, grösste zuerst.
  groesse,
}

/// Welche Reihenfolge gilt, wenn niemand etwas eingestellt hat.
///
/// Das Neueste oben – wer nichts umstellt, sieht genau das Bisherige.
const Rastersortierung rastersortierungVorgabe = Rastersortierung.aufnahmeNeu;

/// Die Reihenfolge zu einer gespeicherten Zahl.
///
/// Eine Zahl ausserhalb der Reihe fällt auf die Vorgabe zurück, statt den
/// Bildschirm zu verhindern – dieselbe Regel wie bei der Kachelstufe.
Rastersortierung rastersortierung(int wert) =>
    wert >= 0 && wert < Rastersortierung.values.length
        ? Rastersortierung.values[wert]
        : rastersortierungVorgabe;

/// Ob nach dem **Aufnahmedatum** geordnet wird.
///
/// Nur dann darf die Zeitleiste nach Monaten gliedern: Eine Überschrift
/// „März 2019" über einer Gruppe, die nach Dateigrösse sortiert ist,
/// wäre schlicht falsch – die Aufnahme darunter kann von 2024 sein.
bool nachAufnahmedatum(Rastersortierung s) =>
    s == Rastersortierung.aufnahmeNeu || s == Rastersortierung.aufnahmeAlt;

/// Ob die Reihenfolge **absteigend** läuft (das Neueste/Grösste zuerst).
bool sortierungAbsteigend(Rastersortierung s) =>
    s != Rastersortierung.aufnahmeAlt;

/// Die Reihenfolge als SQL – der Teil hinter `ORDER BY`.
///
/// **Was das kostet.** Nur `file_created_at` (in beiden Richtungen) wird
/// von `idx_assets_trashed_locked_created` getragen; die übrigen vier
/// brauchen eine Sortierung im Speicher. An einer Bibliothek mit 105.274
/// Aufnahmen gemessen, Ladefenster 600 Zeilen:
///
/// ```
/// file_created_at DESC                     0,8 ms
/// file_created_at ASC                      0,7 ms
/// imported_at DESC                        68,3 ms
/// original_file_name COLLATE NOCASE ASC   70,5 ms
/// rating DESC                             70,1 ms
/// file_size_bytes DESC                    69,7 ms
/// ```
///
/// **Und warum trotzdem kein Index dafür.** Vier weitere Indizes auf der
/// grössten Tabelle verteuern jeden Import und jede Änderung – dauerhaft,
/// für eine Reihenfolge, die die Ausnahme ist. Siebzig Millisekunden
/// zahlt, wer sie einstellt; nicht jeder andere.
String sortierungSql(Rastersortierung s) => switch (s) {
      Rastersortierung.aufnahmeNeu => 'file_created_at DESC',
      Rastersortierung.aufnahmeAlt => 'file_created_at ASC',
      // Zweiter Schlüssel überall dort, wo der erste sich wiederholen
      // kann: Zwei Dateien gleicher Grösse dürfen nicht bei jeder
      // Abfrage die Plätze tauschen.
      Rastersortierung.importNeu => 'imported_at DESC, file_created_at DESC',
      Rastersortierung.name =>
        'original_file_name COLLATE NOCASE ASC, file_created_at DESC',
      Rastersortierung.bewertung => 'rating DESC, file_created_at DESC',
      Rastersortierung.groesse => 'file_size_bytes DESC, file_created_at DESC',
    };

/// Dieselbe Reihenfolge als Vergleicher.
///
/// Die Suche holt ihre Treffer nicht seitenweise, sondern vollständig –
/// und beim Bildersuchen kommen sie nach Ähnlichkeit sortiert an, also
/// gar nicht aus einem `ORDER BY`. Dort wird in Dart geordnet, und zwar
/// nach denselben Regeln wie in [sortierungSql].
int Function(AssetData, AssetData) sortierungVergleicher(Rastersortierung s) {
  int datumAb(AssetData a, AssetData b) =>
      b.fileCreatedAt.compareTo(a.fileCreatedAt);
  return switch (s) {
    Rastersortierung.aufnahmeNeu => datumAb,
    Rastersortierung.aufnahmeAlt => (a, b) =>
        a.fileCreatedAt.compareTo(b.fileCreatedAt),
    Rastersortierung.importNeu => (a, b) {
        final i = b.importedAt.compareTo(a.importedAt);
        return i != 0 ? i : datumAb(a, b);
      },
    Rastersortierung.name => (a, b) {
        final i = a.originalFileName
            .toLowerCase()
            .compareTo(b.originalFileName.toLowerCase());
        return i != 0 ? i : datumAb(a, b);
      },
    // Ohne Bewertung steht 0 in der Spalte, nicht null - unbewertete
    // Aufnahmen landen also ans Ende, in SQL wie in Dart.
    Rastersortierung.bewertung => (a, b) {
        final i = b.rating.compareTo(a.rating);
        return i != 0 ? i : datumAb(a, b);
      },
    Rastersortierung.groesse => (a, b) {
        final i = b.fileSizeBytes.compareTo(a.fileSizeBytes);
        return i != 0 ? i : datumAb(a, b);
      },
  };
}
