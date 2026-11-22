import 'dart:async';
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

  /// Welche von [ids] noch auf dem Telefon liegen und die App löschen darf.
  /// Bilder einer Serie gehören nicht dazu: Was iOS mit den übrigen macht,
  /// wenn das Titelbild geht, sagt es nicht zu (#314).
  Future<List<String>> vorhanden(List<String> ids);
}

/// Ein Eintrag der Kamerarolle: ein Foto, ein Video oder ein Live Photo.
class Rolleneintrag {
  const Rolleneintrag({
    required this.id,
    required this.geaendert,
    required this.aufgenommen,
    required this.video,
    required this.dateien,
    this.lokal,
    this.quelle,
    this.bearbeitetesVideo,
    this.serie,
    this.serientitel = false,
    this.serienauswahl = false,
  });

  /// Die Kennung auf dem Telefon (MediaStore bzw. Fotomediathek).
  final String id;

  /// Ändert sich, wenn der Eintrag bearbeitet wurde.
  final DateTime geaendert;

  final DateTime aufgenommen;
  final bool video;

  /// Die Dateien, die zum Server gehen – beim Live Photo das Bild und das
  /// Video, sonst eine. Lädt sie bei Bedarf (iCloud); `null`, wenn das
  /// nicht geht. Über die [Bereitstellung] meldet die Rolle, dass es
  /// vorangeht, und der Lauf kann abbrechen (#437).
  final Future<List<Rollendatei>?> Function(Bereitstellung b) dateien;

  /// Ob das Original schon auf dem Telefon liegt (und nicht erst aus iCloud
  /// käme); `null`, wenn die Rolle es nicht weiss.
  final Future<bool> Function()? lokal;

  /// Ob dieses Video auf dem Telefon bearbeitet wurde. Gesichert wird nur
  /// sein Original; löschte man es vom Telefon, wäre die Bearbeitung fort.
  final Future<bool> Function()? bearbeitetesVideo;

  /// Der Eintrag der Plattform dahinter (`AssetEntity`) – für Miniaturen
  /// in der Zeitleiste; `null` in einer Rolle aus Dateien.
  final Object? quelle;

  /// Die Kennung der Serie, zu der dieser Eintrag gehört (#314).
  final String? serie;

  /// Ob er das Titelbild seiner Serie ist – das, was die Fotos-App zeigt.
  final bool serientitel;

  /// Ob jemand dieses Bild in der Fotos-App aus der Serie ausgewählt hat.
  /// Es steht dort dann als eigenes Foto und kommt nicht in den Stapel.
  final bool serienauswahl;

  /// Ob er auch in der Fotos-App als eigenes Bild zu sehen ist. Nur solche
  /// gehören zwischen die Fotos der Zeitleiste.
  bool get eigenesBild => serie == null || serientitel || serienauswahl;

  /// Die Serie, in deren Stapel er gehört; `null` für Ausgewählte.
  String? get stapelserie => serienauswahl ? null : serie;
}

/// Eine Datei eines Eintrags.
class Rollendatei {
  const Rollendatei({
    required this.teil,
    required this.name,
    required this.datei,
  });

  /// `bild` oder `video` – unterscheidet die Hälften eines Live Photos im
  /// Sicherungsstand. `bearbeitet` ist die in der Fotos-App bearbeitete
  /// Fassung des Bildes (#271); der Server legt sie über das Original.
  final String teil;

  /// Der Name auf dem Server. Bei einem Live Photo tragen beide Hälften
  /// denselben Stamm (`IMG_1234.HEIC`, `IMG_1234.MOV`); daran erkennt der
  /// Server das Paar.
  final String name;

  final File datei;
}

/// Das Bereitstellen der Dateien eines Eintrags (#437): Ein Original, das
/// nur in iCloud liegt, oder ein grosses Video kann lange brauchen, und ein
/// Download, der nie zurückkommt, hielt den Lauf samt Sperre für immer.
/// Die Rolle meldet hier, dass es vorangeht ([geht]), und trägt ein, wie
/// sich ein laufender Abruf abbrechen lässt ([beiAbbruch]); der Lauf bricht
/// ab, wenn er aufhören soll oder es zu lange nicht vorangeht.
class Bereitstellung {
  final _abbrecher = <Future<void> Function()>[];
  var _abgebrochen = false;
  var _zuletzt = DateTime.now();

  /// Wann es zuletzt voranging (oder wann es begann).
  DateTime get zuletzt => _zuletzt;

  bool get abgebrochen => _abgebrochen;

  /// Es geht voran – etwa ein Stück des Downloads aus iCloud.
  void geht() => _zuletzt = DateTime.now();

  /// So lässt sich ein laufender Abruf abbrechen. Ist schon abgebrochen,
  /// geschieht es gleich.
  void beiAbbruch(Future<void> Function() abbrechen) {
    if (_abgebrochen) {
      unawaited(abbrechen().catchError((_) {}));
    } else {
      _abbrecher.add(abbrechen);
    }
  }

  /// Bricht ab, was eingetragen ist.
  void brichAb() {
    if (_abgebrochen) return;
    _abgebrochen = true;
    for (final a in _abbrecher) {
      unawaited(a().catchError((_) {}));
    }
    _abbrecher.clear();
  }
}
