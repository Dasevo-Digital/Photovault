part of '../database.dart';

// Tabellen: Entwickeln, Vorgaben, Masken, Restaurierung.

/// Vorkonfigurierte Aktionen für eine bestimmte, per EXIF erkannte Kamera
/// (Hersteller + Modell) – analog zu Digikams "Kamera für den Import
/// voreinstellen". Wird bei jedem neu importierten (oder nachträglich per
/// Kameradaten-Backfill erkannten) Foto automatisch angewendet, sobald
/// cameraMake/cameraModel übereinstimmen, siehe
/// LibraryState._applyCameraPreset.
@DataClassName('CameraPresetData')
class CameraPresets extends Table {
  TextColumn get id => text()();
  TextColumn get cameraMake => text()();
  TextColumn get cameraModel => text()();
  TextColumn get targetAlbumId => text().nullable()();
  BoolColumn get autoFavorite => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class CameraPresetTags extends Table {
  TextColumn get presetId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column> get primaryKey => {presetId, tagId};
}

/// Eine benannte Entwicklung, die sich auf beliebige Fotos anwenden lässt.
///
/// Der Schritt über das blosse Kopieren: Einstellungen von einem Foto aufs
/// nächste zu übertragen gab es schon (siehe
/// `LibraryState.uebertrageEntwicklung`), aber die Zwischenablage hält
/// genau einen Stand und vergisst ihn beim Beenden. Eine Vorgabe hat einen
/// Namen und bleibt – „Innenaufnahme Kunstlicht", „Winterlandschaft".
///
/// Dieselben Wertspalten wie [DevelopSettings], nur ohne `assetId`: Eine
/// Vorgabe gehört zu keinem Foto. **Masken fehlen mit Absicht** – aus
/// demselben Grund, aus dem sie schon beim Kopieren fehlen: Eine Maske um
/// einen Kopf auf Foto A liegt auf Foto B irgendwo im Nichts.
///
/// Muster: [ExportPresets] und [CameraPresets]. Die dritte Vorgabenart in
/// derselben App, und die einzige, die bisher fehlte – dabei ist sie die,
/// nach der am ehesten jemand sucht.
@DataClassName('DevelopPresetData')
class DevelopPresets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Angezeigter Name. Eindeutig, damit die Auswahlliste eindeutig bleibt.
  TextColumn get name => text().unique()();

  RealColumn get exposure => real().withDefault(const Constant(0))();
  RealColumn get temperature => real().nullable()();
  RealColumn get tint => real().nullable()();
  RealColumn get contrast => real().withDefault(const Constant(0))();
  RealColumn get shadows => real().withDefault(const Constant(0))();
  RealColumn get highlights => real().withDefault(const Constant(0))();
  RealColumn get sharpness => real().withDefault(const Constant(0))();
  RealColumn get noiseReduction => real().withDefault(const Constant(0))();
  BoolColumn get lensCorrectionEnabled =>
      boolean().withDefault(const Constant(true))();
  RealColumn get clarity => real().withDefault(const Constant(0))();
  RealColumn get vignette => real().withDefault(const Constant(0))();

  /// Der Pfad der Farbtabelle wandert mit. Zeigt er ins Leere, weil die
  /// `.cube`-Datei inzwischen fehlt, greift die Vorgabe ohne sie – der
  /// Rest der Werte ist deswegen nicht falsch.
  TextColumn get lutPath => text().nullable()();
  RealColumn get lutStrength => real().withDefault(const Constant(1))();
  TextColumn get toneCurveJson => text().nullable()();
  TextColumn get colorMixerJson => text().nullable()();

  DateTimeColumn get erstelltAm => dateTime()();
}

/// Eine benannte Ausgabe-Vorgabe für den Export – Grösse, Format, Qualität,
/// Dateibenennung und ob die XMP-Beistelldatei mitgeschrieben wird.
///
/// Bisher gab es dafür nur die feste Aufzählung `Exportgroesse` mit vier
/// Stufen. Die deckt die häufigen Fälle ab, aber nicht die
/// wiederkehrenden: „für den Fotoclub, lange Kante 2048, benannt nach
/// Aufnahmedatum" tippt man sonst jedes Mal neu zusammen.
///
/// [nachJpeg] und [maxKante] sind bewusst getrennt: Ohne [nachJpeg] wird
/// die Datei unverändert kopiert (der einzige Weg, der RAW und Videos
/// unangetastet lässt); mit [nachJpeg] wird gerendert, und [maxKante]
/// begrenzt dabei zusätzlich die längere Seite – `null` heisst dann
/// „volle Auflösung, nur neu kodiert".
@DataClassName('ExportPresetData')
class ExportPresets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Angezeigter Name. Eindeutig, damit die Auswahlliste eindeutig bleibt.
  TextColumn get name => text().unique()();

  BoolColumn get nachJpeg => boolean().withDefault(const Constant(false))();

  /// Längere Bildkante in Pixeln; `null` = nicht begrenzen.
  IntColumn get maxKante => integer().nullable()();

  /// JPEG-Qualität 0,1 … 1,0. Ohne [nachJpeg] ohne Bedeutung.
  RealColumn get qualitaet => real().withDefault(const Constant(0.9))();

  /// Muster für den Dateinamen, siehe `export_naming.dart`.
  TextColumn get namensmuster => text().withDefault(const Constant('{name}'))();

  BoolColumn get xmpDaneben => boolean().withDefault(const Constant(true))();

  DateTimeColumn get erstelltAm => dateTime()();
}

/// Verallgemeinerung von [CameraPresets] auf andere Bedingungen als die
/// Kamera – bewusst eine eigene, zusätzliche Tabelle statt [CameraPresets]
/// zu erweitern: Kamera-Presets bleiben unverändert nutzbar (kein
/// Migrationsrisiko für bestehende Daten), und die je nach [triggerType]
/// stark unterschiedlich geformten Bedingungen (Umkreis, Datumsbereich,
/// KI-Tag) hätten als zusätzliche, meist leere Spalten auf [CameraPresets]
/// keine saubere Passform gehabt.
///
/// [triggerType] ist bewusst ein einfacher String statt eines Drift-Enums
/// (`'location'`/`'aiTag'`/`'dateRange'`) – dieselbe Konvention wie
/// [Assets.type] (`'IMAGE'`/`'VIDEO'`). Je nach Typ sind nur die
/// zugehörigen Bedingungs-Spalten gesetzt, der Rest bleibt `null` – siehe
/// LibraryState.applyAutomationRules für die Auswertung.
///
/// Zwei Auslösepunkte, weil die jeweilige Bedingung zu unterschiedlichen
/// Zeitpunkten überhaupt geprüft werden kann: `location`/`dateRange` schon
/// beim Import (GPS/Datum liegen sofort vor), `aiTag` erst nach der
/// KI-Tagging-Stufe der Hintergrundanalyse.
@DataClassName('AutomationRuleData')
class AutomationRules extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get triggerType => text()();

  // triggerType == 'location': Umkreis um einen Mittelpunkt (einfacher fürs
  // UI als eine Bounding-Box – ein Punkt + Radius-Regler).
  RealColumn get regionCenterLat => real().nullable()();
  RealColumn get regionCenterLon => real().nullable()();
  RealColumn get regionRadiusKm => real().nullable()();

  // triggerType == 'aiTag': muss exakt einem Begriff aus dem KI-Tag-
  // Vokabular entsprechen (siehe AiTagVocabulary).
  TextColumn get aiTagTerm => text().nullable()();

  // triggerType == 'dateRange': volles Datum statt wiederkehrend
  // Monat/Tag – vermeidet Jahresübergangs-Sonderfälle (z.B. "20.12.–5.1."),
  // auf Kosten dessen, dass eine wiederkehrende Regel jedes Jahr neu
  // angelegt werden muss.
  DateTimeColumn get dateFrom => dateTime().nullable()();
  DateTimeColumn get dateTo => dateTime().nullable()();

  TextColumn get targetAlbumId => text().nullable()();
  BoolColumn get autoFavorite => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class AutomationRuleTags extends Table {
  TextColumn get ruleId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column> get primaryKey => {ruleId, tagId};
}

/// Nicht-destruktive Entwicklungs-Einstellungen für ein Asset (siehe
/// DevelopScreen) – existiert nur, solange der Nutzer tatsächlich
/// Anpassungen vorgenommen hat (kein Row = "unverändert"). Ein Asset pro
/// Zeile statt zusätzlicher Spalten direkt auf [Assets], analog zu
/// [Faces]/[ImageEmbeddings] als Pro-Asset-Zusatztabelle.
@DataClassName('DevelopSettingsData')
class DevelopSettings extends Table {
  TextColumn get assetId => text()();
  RealColumn get exposure =>
      real().withDefault(const Constant(0))(); // EV, -3..3
  RealColumn get temperature =>
      real().nullable()(); // Kelvin, null = Kamera-Weißabgleich
  RealColumn get tint =>
      real().nullable()(); // Grün/Magenta, null = Kamera-Weißabgleich
  RealColumn get contrast => real().withDefault(const Constant(0))(); // -1..1
  RealColumn get shadows => real().withDefault(const Constant(0))(); // -1..1

  /// Lichter, -1..1 – das Gegenstück zu [shadows].
  ///
  /// Kam erst mit Schema 46 dazu, und das war eine echte Lücke: Bei RAW
  /// ist der Spielraum in den Lichtern der Grund, überhaupt RAW zu
  /// fotografieren. Ein überstrahlter Himmel steckt in der Datei, es gab
  /// nur keinen Griff dafür.
  RealColumn get highlights => real().withDefault(const Constant(0))();
  RealColumn get sharpness => real().withDefault(const Constant(0))(); // 0..1
  RealColumn get noiseReduction =>
      real().withDefault(const Constant(0))(); // 0..1
  BoolColumn get lensCorrectionEnabled =>
      boolean().withDefault(const Constant(true))();

  /// Klarheit (lokaler Mikrokontrast) und Vignettierung, je -1..1.
  ///
  /// Beide sind reine Core-Image-Filter und wirken deshalb – wie Schärfe
  /// und Rauschunterdrückung – erst im gerenderten Bild, nicht in der
  /// Shader-Vorschau während des Ziehens.
  RealColumn get clarity => real().withDefault(const Constant(0))();
  RealColumn get vignette => real().withDefault(const Constant(0))();

  /// Eine importierte Farbtabelle (`.cube`), relativ zur Bibliothek, und
  /// wie stark sie wirkt.
  ///
  /// Der Pfad statt des Inhalts: Ein 33er-Würfel sind 36.000 Zahlen, die
  /// sonst in jeder Zeile und noch einmal in jedem Verlaufseintrag lägen.
  TextColumn get lutPath => text().nullable()();
  RealColumn get lutStrength => real().withDefault(const Constant(1))();

  /// JSON-kodierte [ToneCurve] bzw. [ColorMixer] (siehe develop_color.dart).
  ///
  /// Anders als die Regler darüber sind das keine einzelnen Zahlen, sondern
  /// eine Punktfolge je Kanal bzw. acht Bänder mit je drei Werten – als
  /// Spalten flachgeklopft wären das über dreissig zusätzliche Felder, die
  /// in [DevelopHistory] noch einmal aufträten. `null` bedeutet neutral;
  /// damit brauchen vorhandene Zeilen keine Migration und der Normalfall
  /// kostet zur Laufzeit nichts (siehe `ToneCurve.istNeutral`).
  TextColumn get toneCurveJson => text().nullable()();
  TextColumn get colorMixerJson => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {assetId};
}

/// Nicht-destruktiver Video-Zuschnitt (siehe VideoTrimScreen) – analog zu
/// [DevelopSettings]: ein Asset pro Zeile, existiert nur solange ein
/// Zuschnitt aktiv ist. Speichert Start/Ende getrennt vom eigentlichen
/// Ergebnis (`Assets.trimmedRelativePath`), damit der Zuschnitt-Editor beim
/// erneuten Öffnen wieder mit den zuletzt gewählten Grenzen startet, statt
/// bei 0/volle Länge.
@DataClassName('VideoTrimData')
class VideoTrims extends Table {
  TextColumn get assetId => text()();
  RealColumn get startSeconds => real()();
  RealColumn get endSeconds => real()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {assetId};
}

/// Vergangene, dauerhaft gespeicherte Entwickeln-Einstellungs-Stände eines
/// Assets – jeder Speichern-Vorgang im DevelopScreen schiebt den bisherigen
/// [DevelopSettings]-Stand hierher, bevor er überschrieben wird (siehe
/// AppDatabase.pushDevelopHistory), begrenzt auf die neuesten 10 Einträge
/// pro Asset. Eigene Tabelle statt Versionierung von [DevelopSettings]
/// selbst, damit "aktueller Stand" weiterhin ein einfaches 1:1-Lookup
/// bleibt (wie bei [Faces]/[ImageEmbeddings] als Pro-Asset-Zusatztabelle).
@DataClassName('DevelopHistoryData')
class DevelopHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get assetId => text()();
  RealColumn get exposure => real()();
  RealColumn get temperature => real().nullable()();
  RealColumn get tint => real().nullable()();
  RealColumn get contrast => real()();
  RealColumn get shadows => real()();

  /// Wie in [DevelopSettings]. Mit Vorgabewert statt `real()()`, weil die
  /// Spalte einer bestehenden Tabelle hinzugefügt wird: Für die Einträge,
  /// die es beim Umstieg auf Schema 46 schon gab, ist neutral die einzig
  /// richtige Antwort – damals gab es den Regler nicht.
  RealColumn get highlights => real().withDefault(const Constant(0))();
  RealColumn get sharpness => real()();
  RealColumn get noiseReduction => real()();
  BoolColumn get lensCorrectionEnabled => boolean()();

  /// Wie in [DevelopSettings]. Ohne sie liesse ein Verlaufs-Eintrag diese
  /// Werte stillschweigend fallen, und „Zurück zu diesem Stand" führte zu
  /// einem anderen Bild als damals.
  RealColumn get clarity => real().withDefault(const Constant(0))();
  RealColumn get vignette => real().withDefault(const Constant(0))();
  TextColumn get lutPath => text().nullable()();
  RealColumn get lutStrength => real().withDefault(const Constant(1))();

  /// Wie in [DevelopSettings] – ohne diese beiden Spalten liesse ein
  /// Verlaufs-Eintrag Kurve und Mischer stillschweigend fallen, und
  /// "Zurück zu diesem Stand" führte zu einem anderen Bild als damals.
  TextColumn get toneCurveJson => text().nullable()();
  TextColumn get colorMixerJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
}

/// KI-Objektmaske (siehe MaskEditor, SegmentationService): eine per SAM
/// vorhergesagte, vom Nutzer bestätigte Region eines Fotos, mit eigenen
/// Regler-Werten (nur innerhalb der Maske wirksam) – ein Asset kann mehrere
/// Masken haben (1:n), zusätzlich zu den globalen [DevelopSettings] fürs
/// ganze Bild. [maskRelativePath] zeigt auf eine kleine Graustufen-PNG-
/// Alphamaske (analog zu [Faces.cropRelativePath]), NICHT die rohen
/// SAM-Embeddings – die werden nur während der offenen Maskier-Sitzung im
/// Speicher gehalten, nie persistiert. Nimmt bewusst NICHT am
/// [DevelopHistory]-Verlauf teil (der ist auf den flachen 8-Felder-
/// Regler-Satz eines einzelnen Bildes zugeschnitten) – "Maske entfernen"
/// ist die einzige Rückgängig-Funktion für Masken.
@DataClassName('DevelopMaskData')
class DevelopMasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get assetId => text()();
  TextColumn get maskRelativePath => text()();
  TextColumn get label => text()();
  RealColumn get exposure => real().withDefault(const Constant(0))();
  RealColumn get temperature => real().nullable()();
  RealColumn get tint => real().nullable()();
  RealColumn get contrast => real().withDefault(const Constant(0))();
  RealColumn get shadows => real().withDefault(const Constant(0))();

  /// Wie in [DevelopSettings] – eine Maske kann Lichter genauso
  /// zurückholen wie das ganze Bild, und meistens will man genau das:
  /// den Himmel, nicht die Wiese darunter.
  RealColumn get highlights => real().withDefault(const Constant(0))();
  RealColumn get sharpness => real().withDefault(const Constant(0))();
  RealColumn get noiseReduction => real().withDefault(const Constant(0))();
  BoolColumn get lensCorrectionEnabled =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  /// JSON-kodierte [MaskShapeDefinition] (siehe vector_mask_service.dart) –
  /// `null` bedeutet eine per SAM-Punkt-Prompt erzeugte Maske (heutiges
  /// Verhalten, nicht nachträglich als Form editierbar). Ist ein Wert
  /// gesetzt, ist er die Quelle der Wahrheit für erneutes Bearbeiten;
  /// [maskRelativePath] bleibt in beiden Fällen der gerenderte Graustufen-
  /// PNG-Cache, den die native Kompositierung tatsächlich konsumiert – bei
  /// jeder Formänderung wird er neu gerendert und überschrieben.
  TextColumn get shapeDefinitionJson => text().nullable()();
}

/// Ein KI-Restaurierungs-Auftrag (siehe RestoreQueueService,
/// RestoreService) – läuft im Hintergrund, oft mehrere Minuten pro Foto
/// (echt gemessen: ~5 Min. bei 12 MP mit CoreML-Beschleunigung), daher als
/// eigene, persistierte Warteschlange statt eines blockierenden Dialogs.
/// [status] durchläuft `queued` → `running` → `done`/`failed`/`cancelled`.
/// Wird die App mitten in `running` beendet, setzt
/// [AppDatabase.resetStuckRunningRestoreJobs] beim nächsten Start auf
/// `queued` zurück (Crash-Safety, siehe LibraryState.initialize) – es
/// werden keine Teil-Kacheln persistiert, ein zurückgesetzter Job läuft
/// komplett neu.
@DataClassName('RestoreJobData')
class RestoreJobs extends Table {
  TextColumn get id => text()();
  TextColumn get assetId => text()();
  TextColumn get status =>
      text()(); // 'queued' | 'running' | 'done' | 'failed' | 'cancelled'
  IntColumn get tilesDone => integer().withDefault(const Constant(0))();
  IntColumn get tilesTotal => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  /// Wann der Auftrag tatsächlich **begonnen** hat.
  ///
  /// Nicht dasselbe wie [createdAt]: Zwischen Einreihen und Anfangen
  /// können Stunden liegen, wenn mehrere Aufträge warten. Ohne diese
  /// Spalte liesse sich keine Restzeit schätzen, die stimmt – jede
  /// Rechnung aus der Wartezeit wäre eine Lüge, und eine Lüge über eine
  /// Restzeit merkt man erst, wenn sie abgelaufen ist.
  DateTimeColumn get startedAt => dateTime().nullable()();

  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
