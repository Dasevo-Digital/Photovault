import '../db/database.dart';
import 'bilddekodierung.dart' show vergissAlleBilder;
import 'storage_paths.dart';

/// Welche nicht-destruktive Bearbeitung an einer Aufnahme hängt.
///
/// Alle drei arbeiten nach demselben Muster: Das Original bleibt
/// unangetastet, das Ergebnis liegt als eigene Datei daneben, und eine
/// Spalte in `assets` zeigt darauf (siehe [Assets.developedRelativePath]).
enum Bearbeitungsart {
  /// Entwickeln – Regler und Masken, siehe `DevelopScreen`.
  entwickelt,

  /// KI-Restaurierung (Hochskalieren/Entrauschen).
  restauriert,

  /// Video-Zuschnitt.
  zugeschnitten,
}

/// Was an dieser Aufnahme bearbeitet ist – leer heisst „unverändert".
Set<Bearbeitungsart> bearbeitungsarten(AssetData a) => {
      if (a.developedRelativePath != null) Bearbeitungsart.entwickelt,
      if (a.restoredRelativePath != null) Bearbeitungsart.restauriert,
      if (a.trimmedRelativePath != null) Bearbeitungsart.zugeschnitten,
    };

/// Nimmt **jede** Bearbeitung einer Aufnahme zurück.
///
/// **Wozu es das braucht.** Zurücknehmen liess sich bisher nur dort, wo
/// es entstanden war: die Entwicklung im Entwickeln-Bildschirm, die
/// Restaurierung daneben, der Zuschnitt im Video-Werkzeug. Wer ein Foto
/// vor sich hatte und das Original zurückwollte, musste erst wissen,
/// welches der drei Werkzeuge es verändert hatte – und dieses Werkzeug
/// öffnen, um einen Knopf zu drücken, der „Zurücksetzen" heisst und nach
/// „Regler auf null" klingt. Von der Aufnahme aus gab es keinen Weg
/// zurück.
///
/// **Das Original wird nicht angefasst.** Gelöscht werden nur die
/// abgeleiteten Dateien, die die App selbst angelegt hat; die Spalten,
/// die auf sie zeigen, fallen auf `null` zurück. Genau das ist der Sinn
/// des nicht-destruktiven Arbeitens – hier wird er einmal eingelöst.
///
/// Gibt zurück, was zurückgenommen wurde; leer heisst, es gab nichts.
Future<Set<Bearbeitungsart>> originalWiederherstellen({
  required AppDatabase db,
  required StoragePaths paths,
  required AssetData asset,
}) async {
  final arten = bearbeitungsarten(asset);
  if (arten.isEmpty) return const {};

  Future<void> loesche(String? relativerPfad) async {
    if (relativerPfad == null) return;
    final datei = paths.absolute(relativerPfad);
    if (await datei.exists()) await datei.delete();
  }

  if (arten.contains(Bearbeitungsart.entwickelt)) {
    // Die Masken zuerst: Sie hängen an der Entwicklung, und ihre
    // Bilddateien blieben sonst als Waisen liegen – derselbe Rest, den
    // die 8. Prüfrunde bei den Gesichtsausschnitten gefunden hat.
    for (final maske in await db.masksForAsset(asset.id)) {
      await loesche(maske.maskRelativePath);
      await db.deleteDevelopMask(maske.id);
    }
    await loesche(asset.developedRelativePath);
    await db.resetDevelopSettings(asset.id);
  }
  if (arten.contains(Bearbeitungsart.restauriert)) {
    await loesche(asset.restoredRelativePath);
    await db.clearMissingRestoredPath(asset.id);
  }
  if (arten.contains(Bearbeitungsart.zugeschnitten)) {
    await loesche(asset.trimmedRelativePath);
    await db.resetVideoTrim(asset.id);
  }

  // Der Pfad zur angezeigten Fassung ändert sich nicht, ihr Inhalt
  // schon – ohne dieses Vergessen zeigte die Vollbildansicht weiter das
  // bearbeitete Bild (dieselbe Falle wie beim Speichern im
  // Entwickeln-Bildschirm).
  vergissAlleBilder();
  return arten;
}
