import 'dart:io';

/// Die Fotos und Videos auf dem Telefon, so weit die Sicherung sie braucht.
///
/// Eine Schnittstelle statt `photo_manager` direkt: Der Lauf der Sicherung
/// (siehe `Sicherungslauf`) lässt sich so mit Dateien aus einem Ordner
/// gegen einen echten Server prüfen, ohne Telefon.
abstract class Kamerarolle {
  /// Alle Einträge der gewählten Alben, der neueste zuerst – damit das
  /// Frischeste zuerst sicher ist.
  Future<List<Rolleneintrag>> eintraege({required bool videos});

  /// Gibt Platz frei, den das Bereitstellen der Dateien gekostet hat
  /// (iOS kopiert jedes Original erst in einen Zwischenspeicher).
  Future<void> aufraeumen();

  /// Löscht Einträge vom Telefon (siehe `Speicherfreigabe`); das System
  /// fragt den Nutzer dabei selbst. Gibt zurück, wie viele gingen.
  Future<int> loesche(List<String> ids);
}

/// Ein Eintrag der Kamerarolle: ein Foto, ein Video oder ein Live Photo.
class Rolleneintrag {
  const Rolleneintrag({
    required this.id,
    required this.geaendert,
    required this.aufgenommen,
    required this.video,
    required this.dateien,
    this.quelle,
  });

  /// Die Kennung auf dem Telefon (MediaStore bzw. Fotomediathek).
  final String id;

  /// Ändert sich, wenn der Eintrag bearbeitet wurde.
  final DateTime geaendert;

  final DateTime aufgenommen;
  final bool video;

  /// Die Dateien, die zum Server gehen – beim Live Photo das Bild und das
  /// Video, sonst eine. Lädt sie bei Bedarf (iCloud); `null`, wenn das
  /// nicht geht.
  final Future<List<Rollendatei>?> Function() dateien;

  /// Der Eintrag der Plattform dahinter (`AssetEntity`) – für Miniaturen
  /// in der Zeitleiste; `null` in einer Rolle aus Dateien.
  final Object? quelle;
}

/// Eine Datei eines Eintrags.
class Rollendatei {
  const Rollendatei({
    required this.teil,
    required this.name,
    required this.datei,
  });

  /// `bild` oder `video` – unterscheidet die Hälften eines Live Photos im
  /// Sicherungsstand.
  final String teil;

  /// Der Name auf dem Server. Bei einem Live Photo tragen beide Hälften
  /// denselben Stamm (`IMG_1234.HEIC`, `IMG_1234.MOV`); daran erkennt der
  /// Server das Paar.
  final String name;

  final File datei;
}
