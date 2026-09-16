import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:drift/native.dart';
// Nur fuer den Typ der Verbindung in [AppDatabase.bereiteVerbindungVor].
import 'package:sqlite3/sqlite3.dart' show Database;
import 'package:path/path.dart' as p;

import '../services/ai_tagging_service.dart' show defaultAiTagVocabulary;
import '../services/aktivitaeten.dart' show istBekannteArt;
import '../services/embedding_codec.dart';
import '../services/embedding_similarity.dart' show duplikatPaarSchluessel;
import '../services/exif_camera.dart';
import '../services/face_threshold.dart';
import '../services/gelaendeebenen.dart';
import '../services/library_location.dart';
import '../services/library_stats.dart';
import '../services/lichtstimmung.dart';
import '../services/reisen.dart' show Reiseart, reiseartVorgabe;
import '../services/listenspalten.dart';
import '../services/ortsvorschlag.dart' show Ortsloser, Ortsnachbar;
import 'rasterzeile.dart';
import '../services/rasterstufen.dart'
    show
        zeitleisteKachelstufeVorgabe,
        zeitleisteFormVorgabe,
        zeitleisteForm,
        Zeitleistenform;
import '../services/raw_formats.dart' show rawImageExtensions;
import '../services/search_filters.dart';
import '../services/sortierung.dart'
    show
        Rastersortierung,
        rastersortierung,
        rastersortierungVorgabe,
        sortierungSql;
import '../services/stammbaum.dart';
import '../services/verwandtschaftsgrad.dart';
import '../services/videostandbilder.dart'
    show videoZweitblickAb, videostandbildstellen;
import '../services/xmp_regionen.dart';
import '../services/eigenkarte.dart';

part 'database.g.dart';

/// Ein einzelnes Foto oder Video. `relativePath`/`thumbnailRelativePath` sind
/// relativ zum Bibliotheksordner (siehe StoragePaths), damit die gesamte
/// Bibliothek portabel bleibt (z.B. beim Umzug auf einen anderen Rechner).
@DataClassName('AssetData')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get originalFileName => text()();
  TextColumn get relativePath => text()();
  TextColumn get thumbnailRelativePath => text().nullable()();
  TextColumn get previewRelativePath => text().nullable()(); // HEIC/DNG & Co.

  /// Ergebnis der nicht-destruktiven Entwicklung (siehe DevelopSettings) –
  /// nur gesetzt, solange der Nutzer tatsächlich Anpassungen vorgenommen
  /// hat. Null bedeutet "unverändert", nicht "fehlt" – dann wird
  /// [previewRelativePath] bzw. [relativePath] angezeigt. Bewusst NICHT für
  /// Gesichtserkennung/CLIP verwendet (siehe LibraryState._decodableFile) –
  /// KI-Verarbeitung soll immer das unveränderte Bild sehen.
  TextColumn get developedRelativePath => text().nullable()();

  /// Ergebnis des nicht-destruktiven Video-Zuschnitts (siehe VideoTrims) –
  /// analog zu [developedRelativePath]: null bedeutet "unverändert", die
  /// Original-Videodatei wird nie angetastet. Für IMAGE-Assets stets null,
  /// da sich die beiden Felder gegenseitig ausschließen (ein Asset ist
  /// entweder Foto oder Video).
  TextColumn get trimmedRelativePath => text().nullable()();

  /// Ergebnis einer KI-Restaurierung (Hochskalieren/Entrauschen, siehe
  /// RestoreJobs/RestoreQueueService) – analog zu [developedRelativePath]:
  /// null bedeutet "keine Restaurierung vorhanden". Höchste Priorität in
  /// displayRelativePath (siehe asset_display_path.dart), da sie – anders
  /// als [developedRelativePath] – ein bewusst einmalig angestoßenes,
  /// abgeschlossenes Ergebnis ist, kein live nachregelbarer Zustand.
  TextColumn get restoredRelativePath => text().nullable()();
  TextColumn get checksum => text().unique()();
  TextColumn get type => text()(); // 'IMAGE' oder 'VIDEO'

  /// Dateiformat, kleingeschrieben und ohne Punkt (`dng`, `cr3`, `jpg`).
  ///
  /// Eine eigene Spalte und kein `LIKE '%.dng'` auf dem Dateinamen: Jenes
  /// kann keinen Index benutzen und liest bei jedem Suchlauf die ganze
  /// Tabelle. Bei 100.000 Fotos wäre das ein Filter, den niemand benutzt.
  ///
  /// **Nullable, und leerer Text ist etwas anderes:** Eine Datei ohne
  /// Endung hat kein Format. „Unbekannt" und „keins" sind zwei
  /// verschiedene Aussagen – dieselbe Regel wie bei
  /// `Objektivkorrekturstand` und `Tiefenmaskenstand`.
  TextColumn get dateiformat => text().nullable()();
  DateTimeColumn get fileCreatedAt => dateTime()();
  DateTimeColumn get importedAt => dateTime()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isTrashed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get trashedAt => dateTime().nullable()();

  /// In den gesperrten (PIN-geschützten) Ordner verschoben – solche Assets
  /// werden aus Timeline, Kalender, Karte, Suche, Alben, Personen und
  /// Backup-Export herausgefiltert und sind nur über den gesperrten Ordner
  /// (nach PIN-Eingabe) erreichbar. Siehe [PrivacySettings].
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();

  /// Von der Gesichtssuche ausgenommen.
  ///
  /// **Nicht dasselbe wie [facesScanned].** Das hält fest, dass die Suche
  /// gelaufen ist; „alle Fotos erneut durchsuchen" setzt sich darüber
  /// hinweg, und genau das ist der Fall, um den es geht: Ein Gruppenbild
  /// vor einer Gemäldewand, ein Zeitungsfoto, ein Plakat – dort findet
  /// jeder Durchlauf dieselben Gesichter wieder, die man schon einmal
  /// beiseitegelegt hat.
  ///
  /// Ein einzelnes Gesicht lässt sich seit jeher ignorieren
  /// ([Faces.isIgnored]); das half nur nicht bei einem Foto, auf dem
  /// jeder Durchlauf NEUE Stellen findet. Diese Marke gilt dem Bild.
  BoolColumn get faceScanExcluded =>
      boolean().withDefault(const Constant(false))();
  TextColumn get description => text().nullable()();
  IntColumn get widthPx => integer().nullable()();
  IntColumn get heightPx => integer().nullable()();
  RealColumn get durationSeconds => real().nullable()();
  IntColumn get fileSizeBytes => integer().withDefault(const Constant(0))();
  BoolColumn get backedUp => boolean().withDefault(const Constant(false))();

  /// Separat von [backedUp] getrackt, damit sich manuelles Backup (eigener
  /// Zielordner) und automatisches Backup (eigener Zielordner, siehe
  /// [BackupSettings]) nicht gegenseitig den "schon gesichert"-Status
  /// stehlen, wenn beide gleichzeitig genutzt werden.
  BoolColumn get autoBackedUp => boolean().withDefault(const Constant(false))();
  BoolColumn get facesScanned => boolean().withDefault(const Constant(false))();
  TextColumn get linkedAssetId =>
      text().nullable()(); // Live-Photo-Partner (Foto<->Video)

  /// Aus EXIF-GPS-Daten übernommen (nur Fotos) oder manuell in der
  /// Info-Ansicht der Vollbildvorschau gesetzt/korrigiert. Beide null,
  /// solange kein Ort bekannt ist.
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();

  /// Kamera-/Objektiv-/Aufnahme-Angaben aus den EXIF-Daten (nur Fotos) –
  /// rein informativ für die Info-Ansicht, siehe ExifCamera.parseExifCameraInfo.
  TextColumn get cameraMake => text().nullable()();
  TextColumn get cameraModel => text().nullable()();
  TextColumn get lensModel => text().nullable()();
  RealColumn get focalLengthMm => real().nullable()();
  RealColumn get fNumber => real().nullable()();
  IntColumn get iso => integer().nullable()();
  RealColumn get exposureTimeSeconds => real().nullable()();

  /// Belichtungskorrektur in Blendenstufen (EXIF `ExposureBiasValue`) – der
  /// „0 ev"-Wert, den auch die macOS-Fotos-Informationen zeigen.
  ///
  /// Eigene Spalte statt „0 annehmen, wenn nichts dasteht": Ein Foto ohne
  /// diese Angabe (Screenshot, Scan) hat keine Belichtungskorrektur von
  /// null, es hat gar keine. Der Unterschied ist derselbe wie zwischen
  /// „ISO 0" und „ISO unbekannt".
  RealColumn get exposureBiasEv => real().nullable()();

  /// Kleinbild-äquivalente Brennweite (EXIF `FocalLengthIn35mmFilm`).
  ///
  /// Bei Telefonen ist das der Wert, den alle nennen: Die iPhone-Hauptkamera
  /// schreibt 5,7 mm echte Brennweite, gemeint und überall angezeigt sind
  /// 26 mm. Ohne diese Spalte stünde in der Info-Ansicht eine Zahl, die zu
  /// nichts passt, was der Nutzer über sein Gerät weiss.
  RealColumn get focalLength35mm => real().nullable()();

  /// Aus [latitude]/[longitude] abgeleitet über die lokale/offline
  /// Umkehr-Geokodierung (siehe ReverseGeocoder – nächstgelegene bekannte
  /// Stadt, keine Anfrage an einen Online-Dienst). Bleibt `null`, solange
  /// entweder kein Ort bekannt ist oder der GeoNames-Datensatz noch nicht
  /// heruntergeladen wurde.
  TextColumn get locationCountry => text().nullable()();
  TextColumn get locationState => text().nullable()();
  TextColumn get locationCity => text().nullable()();

  /// Sternebewertung 0-5 (0 = unbewertet), analog zu Photo Mechanic/
  /// Lightroom – für schnelle Sichtung großer Importstapel.
  IntColumn get rating => integer().withDefault(const Constant(0))();

  /// 'red'|'yellow'|'green'|'blue'|'purple', null = keine Markierung.
  TextColumn get colorLabel => text().nullable()();

  /// Per Vision-Framework erkannter Text im Bild (siehe ImageConverter.swift
  /// `recognizeText`), durchsuchbar über SearchTextMode.ocr.
  TextColumn get ocrText => text().nullable()();

  /// Eigenes Flag statt "ocrText == null" als "noch nicht gescannt"-Signal,
  /// da ein leerer erkannter Text (kein Text im Bild gefunden) ein gültiges
  /// Ergebnis ist – analog zu [facesScanned].
  BoolColumn get ocrScanned => boolean().withDefault(const Constant(false))();

  /// Wo im Bild der erkannte Text steht – die Stellen aus [ocrText], je mit
  /// ihrem Rechteck in Anteilen der Bildkante (siehe
  /// `services/textstellen.dart`).
  ///
  /// Eine eigene Spalte und nicht in [ocrText] hineingerechnet: Die
  /// Volltextsuche läuft mit `LIKE` über [ocrText], und JSON-Klammern darin
  /// wären Treffer, die niemand gesucht hat.
  ///
  /// `null` heisst „gescannt, aber ohne Stellen" – so sehen alle Fotos aus,
  /// die vor Schema 60 durch die Texterkennung gingen. Sie kommen beim
  /// nächsten Lauf erneut dran, siehe [assetsForOcrBackfill].
  TextColumn get ocrBoxen => text().nullable()();

  /// Ob in dieser Datei schon einmal nach einem GPS-Ort gesucht wurde.
  ///
  /// **Warum es diese Spalte gibt.** Der Nachtrag „Orte einlesen" nahm bis
  /// Fassung 2.6 jede Aufnahme ohne Koordinate – das sind an einer echten
  /// Bibliothek 5756 von 7988 – und las sie **vollständig** ein, um in den
  /// EXIF-Daten nachzusehen. Gemessen an 400 dieser Fotos: 3,3 Sekunden
  /// und 1215 MB für **null** Treffer; hochgerechnet rund 47 Sekunden und
  /// 17,5 GB je Lauf. Und beim nächsten Lauf wieder, denn ein erfolgloser
  /// Blick hinterliess keine Spur.
  ///
  /// Ein Screenshot, ein weitergeleitetes Bild, eine Kamera ohne Empfänger
  /// – die tragen keinen Ort und werden auch beim zwanzigsten Lauf keinen
  /// tragen. Das hier ist die Notiz „nachgesehen, nichts da".
  ///
  /// `false` für alles Bestehende: Nach dem Umstieg läuft der Nachtrag
  /// genau **einmal** über die ganze Bibliothek – und findet dabei die
  /// Videos, an die er vorher nie herankam. Danach ist er still.
  BoolColumn get gpsGeprueft => boolean().withDefault(const Constant(false))();

  /// Ob [fileCreatedAt] **geraten** ist statt gemessen.
  ///
  /// **Der Anlass.** An der echten Bibliothek tragen 1097 von 7443
  /// Aufnahmen einen Zeitstempel auf die volle Stunde – ohne Minute, ohne
  /// Sekunde. Bei Gleichverteilung wären zwei zu erwarten. 948 davon
  /// tragen sogar denselben Zeitpunkt auf die Sekunde: den 27.08.2006,
  /// 00:00 Uhr. In den Dateien nachgesehen steht dort wörtlich
  /// `DateTimeOriginal: 0000:00:00 00:00:00` – die Kamerauhr war nie
  /// gestellt, und der Import fiel auf den Zeitstempel der Datei zurück.
  ///
  /// Dass er das tut, ist richtig; es ist der letzte Ausweg und als
  /// solcher im Import auch benannt. Falsch war das **Schweigen danach**:
  /// Der geratene Wert landete in derselben Spalte wie ein gemessener,
  /// und ab da konnte kein Bildschirm die beiden mehr unterscheiden. Die
  /// Zeitleiste stellte eine halbe Kindheit auf einen einzigen Abend, die
  /// Erinnerungen meldeten am 27. August „vor 20 Jahren" mit 948
  /// Aufnahmen, die an diesem Tag nicht entstanden sind, und die
  /// Serienerkennung fand eine „Serie" mit 943 Mitgliedern.
  ///
  /// Diese Spalte erfindet keinen besseren Wert. Sie hört auf, einen
  /// schlechten als guten auszugeben.
  ///
  /// Wird beim Setzen von Hand wieder gelöscht (siehe
  /// [setAufnahmezeitpunkt]): Wer das Datum selbst einträgt, weiss mehr
  /// als die Datei.
  BoolColumn get datumGeschaetzt =>
      boolean().withDefault(const Constant(false))();

  /// Ob in dieser Datei schon einmal nach einem Aufnahmedatum gesucht
  /// wurde – dieselbe Notiz „nachgesehen" wie bei [gpsGeprueft] und aus
  /// demselben Grund.
  ///
  /// Ohne sie liefe der Nachtrag bei jedem Aufruf über die ganze
  /// Bibliothek, und der teure Teil ist das Lesen der Datei, nicht das
  /// Vergleichen. `false` für alles Bestehende: Der erste Lauf nach dem
  /// Umstieg sieht sich jede Aufnahme einmal an, danach ist er still.
  BoolColumn get datumGeprueft =>
      boolean().withDefault(const Constant(false))();

  /// Ob [latitude]/[longitude] von einer **zeitlichen Nachbaraufnahme
  /// geerbt** sind statt gemessen oder von Hand gesetzt.
  ///
  /// Ein geerbter Ort ist eine begruendete Vermutung: Die Aufnahmen davor
  /// und danach waren alle am selben Ort, also war es diese
  /// hoechstwahrscheinlich auch. Das ist gut genug, um ein Foto auf der
  /// Karte zu finden – und nicht gut genug, um als Messung durchzugehen.
  ///
  /// `false` fuer alles Bestehende ist keine Behauptung, sondern die
  /// Wahrheit: Vor Schema 76 gab es das Erben nicht.
  ///
  /// Faellt mit, sobald der Ort neu gesetzt wird (siehe [setLocation]) –
  /// wer eine Koordinate eintraegt oder aus der Datei liest, ersetzt die
  /// Vermutung durch etwas Belegtes.
  BoolColumn get ortGeerbt => boolean().withDefault(const Constant(false))();

  /// Ob bei diesem Video schon nach weiteren Standbildern gesehen wurde
  /// (siehe `services/videostandbilder.dart`).
  ///
  /// Eigene Spalte und nicht „hat Zeilen in [Videoeinbettungen]": Ein
  /// Video unter zehn Sekunden bekommt **keine** weiteren Standbilder,
  /// und das ist ein Ergebnis, kein offener Posten. Ohne die Spalte
  /// nähme sich der Nachtrag bei jedem Lauf dieselben 208 kurzen Videos
  /// erneut vor.
  BoolColumn get videobilderGeprueft =>
      boolean().withDefault(const Constant(false))();

  /// Der Zeitzonenversatz in Minuten, wie ihn `OffsetTimeOriginal` der
  /// Datei nennt – `null`, wenn die Datei keinen traegt.
  ///
  /// **Jede vierte Datei traegt ihn.** 126 Dateien quer durch die echte
  /// Bibliothek gezogen: 34 tragen `OffsetTimeOriginal`, also 27 %. Im
  /// ganzen Quelltext gab es dafuer bis Schema 78 null Fundstellen.
  ///
  /// [fileCreatedAt] bleibt davon unberuehrt: Das ist und war die
  /// **Ortszeit der Kamera**, und die ist die Zeit, an die man sich
  /// erinnert. Der Versatz sagt nur dazu, in welcher Zone sie galt – ob
  /// die 228 Aufnahmen aus Mazar-e Sharif um 16 Uhr in Berlin oder um
  /// 18:30 vor Ort entstanden.
  IntColumn get zeitversatzMinuten => integer().nullable()();

  /// Automatisch erzeugte (englische) Bildunterschrift (siehe
  /// FlorenceCaptioningService), durchsuchbar über SearchTextMode.caption. Bewusst
  /// NICHT [description] wiederverwendet – das ist Nutzer-Freitext.
  TextColumn get aiCaption => text().nullable()();

  /// Deutsche Fassung von [aiCaption] (siehe TranslationService).
  ///
  /// Als eigene Spalte, nicht als Ersatz: Das englische Original bleibt
  /// erhalten, damit ein Abschalten der Übersetzung nicht bedeutet, das
  /// Beschreibungsmodell über die ganze Bibliothek erneut laufen zu
  /// lassen. Die Suche durchsucht beide.
  TextColumn get aiCaptionDe => text().nullable()();

  /// Eigenes Flag statt "aiCaption == null" als "noch nicht erzeugt"-Signal,
  /// analog zu [ocrScanned].
  BoolColumn get aiCaptionScanned =>
      boolean().withDefault(const Constant(false))();

  /// Ob jemand die Bildunterschrift von Hand geändert hat.
  ///
  /// Ohne dieses Merkmal wäre das Bearbeiten eine Falle: Ein „Alle Fotos"
  /// bei den Bildbeschreibungen – gedacht für einen Modellwechsel – würde
  /// den mühsam getippten Satz kommentarlos überschreiben. Ist es gesetzt,
  /// fassen weder die Nachholvorgänge noch die Hintergrundanalyse den
  /// Eintrag noch an; er verhält sich damit wie der Freitext des Nutzers.
  ///
  /// Zurücknehmen lässt es sich, indem das Feld geleert wird – dann ist das
  /// Foto wieder Kandidat für das Modell.
  BoolColumn get aiCaptionEdited =>
      boolean().withDefault(const Constant(false))();

  /// Eigenes Flag statt "hat keine Tags" als "noch nicht verschlagwortet"-
  /// Signal, aus demselben Grund wie [ocrScanned]: Dass CLIP zu keinem
  /// Vokabelbegriff eine ausreichende Ähnlichkeit findet, ist ein GÜLTIGES
  /// Ergebnis, kein offener Posten. Ohne dieses Flag blieben solche Fotos
  /// dauerhaft Kandidaten und die Tagging-Stufe lud bei JEDEM Programmstart
  /// beide CLIP-Encoder (577 MB), rechnete sie durch und erzeugte wieder
  /// nichts (Audit-Fund: gemessen 1066 MB Grundlast statt 214 MB).
  BoolColumn get aiTagsScanned =>
      boolean().withDefault(const Constant(false))();

  /// Laplace-Varianz des Bilds (siehe blur_detection.dart) – höher = schärfer.
  /// Null, solange noch nicht berechnet.
  RealColumn get sharpnessScore => real().nullable()();

  /// Serien-/Burst-Gruppierung (siehe StackReviewScreen, findBurstGroups):
  /// alle Mitglieder einer Serie teilen dieselbe [stackId], analog zu
  /// [linkedAssetId] bei Live Photos. `null` = kein Stapel.
  TextColumn get stackId => text().nullable()();

  /// Genau ein Mitglied pro Stapel ist Titelbild – nur dieses erscheint in
  /// Timeline/Kalender/Karte & Co. (siehe die `stackId`/`isStackCover`-Filter
  /// dort, exakt wie bei [linkedAssetId] für Live Photos).
  BoolColumn get isStackCover => boolean().withDefault(const Constant(false))();

  /// Gesamtzahl der Fotos im Stapel – NUR auf der Titelbild-Zeile gesetzt
  /// (sonst `null`), damit die Rasteransicht die Zahl fürs Abzeichen ohne
  /// zusätzliche COUNT-Abfrage pro Kachel anzeigen kann.
  IntColumn get stackSize => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

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

@DataClassName('PersonData')
class People extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get coverFaceCropPath => text().nullable()();

  /// Persönliche Wiedererkennungs-Schwelle, abgeleitet aus den bisherigen
  /// Entscheidungen des Nutzers (siehe [FaceMatchFeedback] und
  /// face_threshold.dart). `null` = die allgemeine Schwelle gilt.
  ///
  /// Als gespeicherter Wert statt bei jedem Vorschlag neu gerechnet, damit
  /// die Zahl im Personen-Bildschirm dieselbe ist, nach der tatsächlich
  /// entschieden wurde – eine Schwelle, die sich zwischen Anzeige und
  /// Anwendung unterscheidet, wäre nicht erklärbar.
  RealColumn get similarityThreshold => real().nullable()();

  /// Lebensdaten – nur für den Stammbaum, und beide freiwillig.
  ///
  /// Als volles Datum und nicht als Jahreszahl: Bei Verwandten aus der
  /// eigenen Zeit kennt man den Tag, bei den Urgroßeltern oft nur das
  /// Jahr. Ein Feld, das nur Jahre aufnimmt, verlöre die genaue Angabe;
  /// eines für den Tag lässt sich mit dem 1. Januar füllen, wenn mehr
  /// nicht bekannt ist. Was davon angezeigt wird, entscheidet die
  /// Darstellung, nicht die Speicherung.
  DateTimeColumn get geburtsdatum => dateTime().nullable()();
  DateTimeColumn get sterbedatum => dateTime().nullable()();

  /// Geschlecht – ausschließlich für die Verwandtschaftsbezeichnungen.
  ///
  /// Ohne diese Angabe gibt es kein „Schwester", nur „Geschwister": Fast
  /// jede Bezeichnung im Deutschen wie im Englischen ist geschlechtsgebunden.
  /// `null` ist deshalb kein Mangel, sondern ein gültiger Zustand – dann
  /// erscheint die geschlechtsneutrale Form, und niemand muss eine Angabe
  /// machen, die er nicht kennt oder nicht machen will. Werte siehe
  /// `Geschlecht` in services/verwandtschaftsgrad.dart.
  TextColumn get geschlecht => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ein Ereignis im Leben einer Person – Hochzeit, Umzug, Berufsantritt.
///
/// Eigene Tabelle und nicht Spalten an [People]: Geburt und Tod gibt es
/// genau einmal, alles andere beliebig oft. Wer dreimal umgezogen ist,
/// hat drei Umzüge, und eine feste Spaltenzahl wäre entweder zu klein
/// oder meistens leer.
///
/// Geburt und Tod bleiben bewusst dort, wo sie sind: Sie stehen in fast
/// jeder Ansicht unter dem Namen, und sie hier ein zweites Mal zu führen
/// hiesse, zwei Wahrheiten zu haben.
class Lebensereignisse extends Table {
  TextColumn get id => text()();
  TextColumn get personId => text()();

  /// Siehe `Ereignisart` in services/lebenslauf.dart.
  TextColumn get art => text()();

  /// Freiwillig – manchmal weiß man nur, *dass* etwas war.
  DateTimeColumn get datum => dateTime().nullable()();
  TextColumn get ort => text().nullable()();
  TextColumn get notiz => text().nullable()();

  /// Der Ort als Koordinate, sobald er auflösbar war.
  ///
  /// **Zusätzlich zu [ort], nicht statt dessen.** Ein Ortsname, den der
  /// GeoNames-Auszug nicht kennt – ein untergegangenes Dorf, ein
  /// Gutshof, eine alte Schreibweise – bleibt als Text stehen und ist
  /// damit nicht verloren; er landet nur auf keiner Karte. Beide Felder
  /// zu koppeln hiesse, solche Einträge stillschweigend wegzuwerfen.
  ///
  /// Und getrennt von [ort] auch deshalb, weil die Zuordnung eine
  /// **Vermutung** ist: „Springfield" trifft in den USA über zwanzig Mal
  /// zu. Wer die Koordinate von Hand berichtigt, ändert diese Felder,
  /// ohne dass der aufgeschriebene Name sich ändert.
  RealColumn get ortBreite => real().nullable()();
  RealColumn get ortLaenge => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Eine bestätigte Reise.
///
/// **Bestätigt** ist das entscheidende Wort. Erkannt werden Reisen aus
/// den Aufnahmen selbst (siehe services/reisen.dart); was hier steht, hat
/// ein Mensch angesehen und benannt. Ein Programm, das Reisen im
/// Hintergrund anlegt, füllt die Bibliothek mit Behauptungen – und eine
/// falsch benannte Reise fällt später niemandem mehr auf.
class Reisen extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Erste und letzte Aufnahme – abgeleitet, aber gespeichert: Die Liste
  /// soll nach Zeitraum sortieren können, ohne für jede Zeile ihre
  /// Aufnahmen nachzuschlagen.
  DateTimeColumn get von => dateTime()();
  DateTimeColumn get bis => dateTime()();

  TextColumn get notiz => text().nullable()();

  /// Was für eine Art Reise – als Name der Aufzählung [Reiseart].
  ///
  /// Einsatz, Dienstreise, Besuch: „Reise" trifft nicht jede, und in der
  /// Liste sähen sonst alle gleich aus.
  TextColumn get art => text().withDefault(Constant(reiseartVorgabe.kennung))();

  /// Das Titelbild. `null` heißt „nimm die erste Aufnahme" – und ist
  /// etwas anderes als ein gewähltes Bild, das später gelöscht wurde.
  TextColumn get titelbildAssetId => text().nullable()();

  DateTimeColumn get angelegtAm => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Welche Aufnahme zu welcher Reise gehört.
///
/// Eine ausdrückliche Zuordnung und **nicht** „alles im Zeitraum": Wer
/// eine Aufnahme aus der Reise nimmt oder eine nachträglich importierte
/// hinzufügt, soll das behalten dürfen. Ein Zeitraum schluckte jedes
/// später eingelesene Bild stillschweigend mit.
class ReiseAufnahmen extends Table {
  TextColumn get reiseId => text()();
  TextColumn get assetId => text()();

  @override
  Set<Column> get primaryKey => {reiseId, assetId};
}

/// Was an einem Reisetag geschah – von Hand geschrieben.
///
/// **Warum es das braucht.** Die Reise war nach Tagen gegliedert, aber
/// ein Tagebuch besteht nicht aus Bildern allein. Es fehlte genau das,
/// was ein Tagebuch ausmacht: der Satz, den nur der Reisende schreiben
/// kann. Die Notiz an der Reise ([Reisen.notiz]) gab es schon, sie gilt
/// aber für die ganze Reise – und „am dritten Tag hat es geschüttet"
/// gehört an den dritten Tag.
///
/// **Der Tag als Datum ohne Uhrzeit** ist der Schlüssel, weil die
/// Kapitel genau so entstehen (siehe `reisetage`). Ein Eintrag ohne
/// Aufnahmen an diesem Tag bliebe unsichtbar – das ist gewollt: Das
/// Tagebuch folgt den Bildern, es führt keine eigene Zeitrechnung.
class Reisetagnotizen extends Table {
  TextColumn get reiseId => text()();

  /// Mitternacht des Tages, dem die Notiz gilt.
  DateTimeColumn get tag => dateTime()();

  /// Nicht `text`: Der Spaltenname wäre derselbe wie der Baustein
  /// `text()`, mit dem drift ihn beschreibt – der Getter riefe sich
  /// selbst auf, und die Erzeugung brach mit 3485 Fehlern ab, von denen
  /// keiner hier stand.
  TextColumn get notiz => text()();

  DateTimeColumn get geaendertAm => dateTime()();

  @override
  Set<Column> get primaryKey => {reiseId, tag};
}

/// Wo eine Reise oder Aktivität stattfand, in einer Zeile.
///
/// Alle drei Ortsangaben können fehlen: Eine Reise, deren Aufnahmen
/// keine Koordinate tragen, hat keinen Ort – und das ist etwas anderes
/// als „unbekannt". Die Übersicht lässt die Zeile dann weg, statt einen
/// Platzhalter hinzuschreiben.
///
/// [weitereOrte] zählt die Orte **neben** dem genannten. Ohne diese Zahl
/// sähe eine dreiwöchige Rundreise aus wie ein Wochenende an einem Ort:
/// Genannt wird der häufigste, und der ist bei einer Rundreise nur einer
/// von vielen.
typedef Ortsbezug = ({
  String? ort,
  String? region,
  String? land,
  int weitereOrte,
  int aufnahmen,
});

/// Der Stand eines Gesichts, bevor es zugeordnet wurde.
///
/// Wird von [AppDatabase.gesichtsstand] gelesen und von
/// [AppDatabase.nimmZuordnungZurueck] zurückgeschrieben.
typedef Gesichtsstand = ({
  String id,
  String? personId,
  bool ignoriert,
});

/// Ein abgelehnter Reisevorschlag.
///
/// Ohne dieses Gedächtnis käme derselbe Vorschlag bei jedem Start wieder
/// – und ein Vorschlag, den man dreimal wegwischen muss, ist eine
/// Belästigung. [schluessel] ist die Kennung der ersten Aufnahme des
/// Vorschlags (siehe `Reisevorschlag.schluessel`).
class VerworfeneReisen extends Table {
  TextColumn get schluessel => text()();
  DateTimeColumn get verworfenAm => dateTime()();

  @override
  Set<Column> get primaryKey => {schluessel};
}

/// Eine bestätigte Aktivität – eine Wanderung, eine Radtour, ein
/// Ausflug.
///
/// **Sie steht für sich und *kann* zu einer Reise gehören.** Deshalb ist
/// [reiseId] nullable: Die Sonntagswanderung vor der Haustür braucht
/// keine Reise, und eine Tabelle, die eine verlangt, zwänge dazu, eine
/// zu erfinden.
///
/// Wie bei den Reisen gilt: **bestätigt.** Erkannt wird aus den
/// Aufnahmen (siehe services/aktivitaeten.dart); was hier steht, hat
/// jemand angesehen und benannt.
class Aktivitaeten extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Die Art, als Name der Aufzählung `Aktivitaetsart` – nicht als
  /// Index: Wer später eine Art dazwischenschiebt, verschöbe sonst alle
  /// gespeicherten Zeilen.
  TextColumn get art => text()();

  DateTimeColumn get von => dateTime()();
  DateTimeColumn get bis => dateTime()();

  TextColumn get notiz => text().nullable()();

  /// Die Reise, zu der sie gehört – oder `null`.
  TextColumn get reiseId => text().nullable()();

  DateTimeColumn get angelegtAm => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Welche Aufnahme zu welcher Aktivität gehört – ausdrücklich, aus
/// demselben Grund wie bei [ReiseAufnahmen].
class AktivitaetAufnahmen extends Table {
  TextColumn get aktivitaetId => text()();
  TextColumn get assetId => text()();

  @override
  Set<Column> get primaryKey => {aktivitaetId, assetId};
}

/// Ein abgelehnter Aktivitätsvorschlag. [schluessel] ist die Kennung der
/// ersten Aufnahme des Vorschlags – wie bei [VerworfeneReisen].
class VerworfeneAktivitaeten extends Table {
  TextColumn get schluessel => text()();
  DateTimeColumn get verworfenAm => dateTime()();

  @override
  Set<Column> get primaryKey => {schluessel};
}

/// Eine abgelehnte Serie. [schluessel] ist die Kennung der ersten Aufnahme
/// der Gruppe – wie bei [VerworfeneReisen] und [VerworfeneAktivitaeten].
///
/// **Warum es die Tabelle braucht.** Die Serienerkennung findet in der
/// Prüfbibliothek 286 brauchbare Gruppen; bis Fassung 62 verschwand eine
/// abgelehnte Gruppe nur aus der Liste und stand beim nächsten Öffnen
/// wieder da. Wer einmal „nein" gesagt hat, will nicht jedes Mal erneut
/// gefragt werden – dieselbe Überlegung wie bei Reisen und Aktivitäten,
/// nur hatte sie hier gefehlt.
class VerworfeneSerien extends Table {
  TextColumn get schluessel => text()();
  DateTimeColumn get verworfenAm => dateTime()();

  @override
  Set<Column> get primaryKey => {schluessel};
}

/// Ein abgelehntes Buendel von Ortsvorschlaegen. [schluessel] ist die
/// kleinste Kennung der Gruppe – wie bei [VerworfeneReisen],
/// [VerworfeneAktivitaeten] und [VerworfeneSerien].
///
/// **Warum es die Tabelle braucht.** Der Vorschlag entsteht bei jedem
/// Aufruf neu aus den Daten; ohne Gedaechtnis stuende ein „nein" beim
/// naechsten Oeffnen wieder da. Und anders als bei Serien gibt es hier
/// keinen anderen Weg, ein Nein festzuhalten: Eine abgelehnte Aufnahme
/// bleibt genau das, was sie vorher war – unverortet.
class VerworfeneOrtsvorschlaege extends Table {
  TextColumn get schluessel => text()();
  DateTimeColumn get verworfenAm => dateTime()();

  @override
  Set<Column> get primaryKey => {schluessel};
}

/// Weitere Einbettungen eines Videos – eine je zusaetzlich ausgewertetem
/// Standbild.
///
/// **Warum eine eigene Tabelle und nicht mehrere Zeilen in
/// [ImageEmbeddings].** Dort ist die Aufnahmekennung der Schluessel, und
/// darauf verlassen sich die Duplikatsuche, die Serienerkennung und der
/// Bibliotheksvergleich: Sie fragen „welche Aufnahme sieht wem aehnlich"
/// und wuerden bei fuenf Zeilen je Video fuenfmal dasselbe Video finden.
///
/// Die Suche dagegen fragt „welche Aufnahme passt zu diesem Satz", und
/// dort ist mehr Material genau richtig: Es zaehlt das beste der
/// Standbilder, nicht ihr Mittel. Ein Mittelwert ueber verschiedene
/// Szenen waere ein Vektor, der zu nichts mehr recht passt.
class Videoeinbettungen extends Table {
  TextColumn get assetId => text()();

  /// Die Stelle in der Laufzeit, 0 bis 1 – als Tausendstel, damit der
  /// Primaerschluessel ganzzahlig bleibt.
  IntColumn get stelle => integer()();
  BlobColumn get vector => blob()();

  @override
  Set<Column> get primaryKey => {assetId, stelle};
}

/// Eine aufgezeichnete Spur – die GPX-Datei einer Wanderung oder
/// Radtour.
///
/// **Bis Fassung 55 wurde sie gelesen und weggeworfen.** Eine GPX-Datei
/// diente einmalig dazu, Fotos zu verorten, und war danach weg. Ohne sie
/// gibt es weder Linie noch Höhenprofil.
///
/// Die Kennzahlen stehen hier und werden **nicht** bei jeder Anzeige neu
/// gerechnet: Eine Spur mit zehntausend Punkten für eine Zeile in einer
/// Liste durchzurechnen, wäre derselbe Fehler wie bei den
/// Reise-Vorschaubildern.
class Spuren extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Der Dateiname, aus dem sie kam – die einzige Herkunftsangabe, die
  /// eine GPX-Datei verlässlich hergibt.
  TextColumn get quelle => text()();

  /// Die Aktivität, zu der sie gehört – oder `null`.
  ///
  /// **Die Verbindung liegt hier und nicht an der Aktivität.** Eine
  /// Aktivität kann ohne Spur bestehen, eine Spur ohne Aktivität auch;
  /// wer die Spalte auf die ältere Tabelle legte, müsste sie dort
  /// nachträglich anbauen, damit sie meistens leer bleibt.
  TextColumn get aktivitaetId => text().nullable()();

  /// Die Reise, zu der sie gehört – oder `null`.
  ///
  /// **Eine zweite Spalte und keine gemeinsame.** Eine Spur gehört zu
  /// einer Aktivität *oder* zu einer Reise, und beides in einem Feld mit
  /// einer Artangabe daneben zu führen hiesse, bei jeder Abfrage zwei
  /// Bedingungen zu schreiben, wo eine reicht – und beim Vergessen der
  /// zweiten die Spuren der jeweils anderen Sorte mitzuzählen.
  TextColumn get reiseId => text().nullable()();

  /// Erster und letzter Zeitstempel – `null`, wenn die Datei keine
  /// führt (eine geplante Route etwa).
  DateTimeColumn get von => dateTime().nullable()();
  DateTimeColumn get bis => dateTime().nullable()();

  IntColumn get punktzahl => integer()();
  RealColumn get laengeKm => real()();

  /// Auf- und Abstieg in Metern – `null`, wenn kein Punkt eine Höhe
  /// trug. Null Meter Aufstieg und „keine Höhenangabe" sind zweierlei.
  RealColumn get aufstieg => real().nullable()();
  RealColumn get abstieg => real().nullable()();

  DateTimeColumn get angelegtAm => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Die Punkte einer Spur, in der Reihenfolge der Datei.
class Spurpunkte extends Table {
  TextColumn get spurId => text()();

  /// Die laufende Nummer. Sie und nicht die Zeit ordnet die Punkte: Eine
  /// geplante Route hat gar keine Zeit, und eine Aufzeichnung mit zwei
  /// gleichen Zeitstempeln wäre sonst nicht mehr eindeutig.
  IntColumn get nummer => integer()();

  RealColumn get breite => real()();
  RealColumn get laenge => real()();
  RealColumn get hoehe => real().nullable()();
  DateTimeColumn get zeit => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {spurId, nummer};
}

/// Was beim Wandern zählt, aus OpenStreetMap – Gipfel, Hütten, Quellen.
///
/// **Warum das in der Bibliothek liegt und nicht nur im Arbeitsspeicher.**
/// Overpass wird ehrenamtlich betrieben und drosselt bei zu vielen
/// Anfragen. Eine Tour, die schon einmal angesehen wurde, soll niemanden
/// mehr fragen – auch nicht nach einem Neustart, und auch nicht ohne
/// Netz.
class Wanderpunkte extends Table {
  /// Die Kennung aus OpenStreetMap – damit derselbe Punkt aus zwei
  /// überlappenden Abfragen nicht zweimal im Bild steht.
  IntColumn get osmId => integer()();

  /// Die Art als Nummer aus `Wanderart`. Als Zahl und nicht als Name,
  /// wie überall hier: Ein Name aus einer älteren Fassung könnte einer
  /// sein, den es nicht mehr gibt.
  IntColumn get artNr => integer()();

  RealColumn get breite => real()();
  RealColumn get laenge => real()();
  TextColumn get name => text().nullable()();

  /// Die Höhe, wie sie in OpenStreetMap steht – **nicht** die aus dem
  /// Höhengitter. Eine eingetragene Gipfelhöhe ist vermessen; das Gitter
  /// kommt aus Kacheln und liegt bei einer Spitze regelmässig zu tief.
  RealColumn get hoehe => real().nullable()();

  @override
  Set<Column> get primaryKey => {osmId};
}

/// Welche Ausschnitte schon bei Overpass erfragt wurden.
///
/// **Getrennt von den Punkten, und das ist der Kern.** Ohne diese
/// Tabelle liesse sich „hier gibt es nichts" nicht von „hier wurde noch
/// nie gefragt" unterscheiden – ein Ausschnitt ohne einen einzigen
/// Gipfel würde bei jedem Öffnen neu erfragt.
class Wanderabfragen extends Table {
  /// Der Ausschnitt, gerundet auf drei Nachkommastellen – siehe
  /// `AppDatabase.wanderpunkteFuer`.
  TextColumn get kasten => text()();

  DateTimeColumn get gefragtAm => dateTime()();

  @override
  Set<Column> get primaryKey => {kasten};
}

/// Ein selbst gesetzter Haken auf der Weltkarte – ein Land, eine Region
/// oder ein Ort, den du besucht hast oder besuchen willst.
///
/// **Neben und nicht statt der Auswertung der Fotos.** Was die Kamera
/// belegt, wird weiterhin aus den Aufnahmen gezählt; diese Tabelle ist
/// für alles, wovon es kein Bild gibt: die Reise vor der ersten
/// Digitalkamera, der Zwischenstopp ohne Foto, das Ziel für nächstes
/// Jahr. Beides in einer Spalte zu führen hiesse, Beleg und Absicht zu
/// vermischen — und danach wäre nicht mehr entscheidbar, welche Zahl aus
/// welcher Quelle stammt.
///
/// [schluessel] ist je nach [art] verschieden: der ISO-Code („DE"), der
/// Regionscode („DE.02") oder Land, Region und Ort mit Strichen dazwischen
/// („DE|Bavaria|München") — dieselbe Bildung wie im Reisefortschritt, damit
/// gesetzte und gezählte Orte sich überhaupt treffen können.
class Ortsmarken extends Table {
  /// `land`, `region` oder `ort`.
  TextColumn get art => text()();

  TextColumn get schluessel => text()();

  /// Der Name zum Zeitpunkt des Setzens.
  ///
  /// Mitgeschrieben und nicht jedes Mal nachgeschlagen: Ohne den
  /// GeoNames-Datensatz gäbe es sonst eine Liste aus Codes.
  TextColumn get name => text()();

  RealColumn get breite => real().nullable()();
  RealColumn get laenge => real().nullable()();

  /// `besucht` oder `geplant`.
  TextColumn get status => text()();

  TextColumn get notiz => text().nullable()();

  DateTimeColumn get angelegtAm => dateTime()();

  /// Art und Schlüssel zusammen — ein Ort lässt sich nicht zweimal
  /// markieren, und das Aufheben einer Marke ist ein Löschen und kein
  /// Suchen nach der richtigen von mehreren Zeilen.
  @override
  Set<Column> get primaryKey => {art, schluessel};
}

/// Eine Verwandtschaft zwischen zwei Personen – die Grundlage des
/// Stammbaums.
///
/// Eine Kantenliste statt Spalten wie „Mutter"/„Vater" an [People]. Feste
/// Spalten legen die Familienform fest, bevor der Nutzer sie beschreibt:
/// Zwei Elternteile passen, drei (Stief-, Pflegeeltern) passen nicht mehr,
/// und für Partner bräuchte es ohnehin eine eigene Struktur. Eine
/// Kantenliste beschreibt jede dieser Formen, ohne dass das Schema davon
/// wüsste.
///
/// [art] entscheidet, wie die beiden Enden zu lesen sind:
/// * `elternteil`: [andereId] ist ein Elternteil von [personId]. Gerichtet
///   – die Umkehrung ist „Kind" und ergibt sich aus derselben Zeile.
/// * `partner`: symmetrisch. Genau **eine** Zeile je Paar, mit der
///   kleineren Kennung in [personId] (siehe `partnerKanteFuer`). Zwei
///   Zeilen je Paar könnten auseinanderlaufen, und dann wäre nicht
///   entscheidbar, welche gilt.
class PersonBeziehungen extends Table {
  TextColumn get personId => text()();
  TextColumn get andereId => text()();
  TextColumn get art => text()();

  @override
  Set<Column> get primaryKey => {personId, andereId, art};
}

/// Eine festgehaltene Entscheidung über einen Wiedererkennungs-Vorschlag.
///
/// Bisher wurden Zuordnungen zwar übernommen, aber nicht ausgewertet: Wer
/// einen Vorschlag korrigierte, bekam beim nächsten Lauf denselben erneut.
/// Diese Tabelle ist das Gedächtnis dafür.
///
/// [similarity] ist der Wert **zum Entscheidungszeitpunkt** und der
/// eigentliche Grund für die Tabelle. Dass ein Gesicht zu einer Person
/// gehört, steht schon in [Faces.personId]; woran die Erkennung das hätte
/// merken können, steht nur hier.
///
/// Bewusst NICHT festgehalten wird das Überspringen eines Vorschlags:
/// "nicht jetzt" ist keine Aussage darüber, ob der Vorschlag richtig war,
/// und als Ablehnung gewertet würde es die Schwelle verderben.
@DataClassName('FaceMatchFeedbackData')
class FaceMatchFeedback extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get personId => text()();
  TextColumn get faceId => text()();
  BoolColumn get accepted => boolean()();
  RealColumn get similarity => real()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Ein einzelnes erkanntes Gesicht innerhalb eines Assets (Bounding Box,
/// relativ 0..1). `personId` ist null, solange das Gesicht noch keiner
/// Person zugeordnet wurde. `embedding` ist nur gefüllt, wenn ein
/// Gesichts-Embedding-Modell installiert ist (siehe FaceEmbeddingService).
@DataClassName('FaceData')
class Faces extends Table {
  TextColumn get id => text()();
  TextColumn get assetId => text()();
  TextColumn get personId => text().nullable()();
  RealColumn get boxX => real()();
  RealColumn get boxY => real()();
  RealColumn get boxW => real()();
  RealColumn get boxH => real()();
  TextColumn get cropRelativePath => text().nullable()();
  BlobColumn get embedding => blob().nullable()();

  /// Wahrscheinlichkeit "Augen offen" (0..1, siehe EyeStateService) – `null`
  /// heißt "noch nicht berechnet" (kein Landmark verfügbar, oder das
  /// Augen-Modell war zum Scan-Zeitpunkt nicht installiert), NICHT "Augen
  /// geschlossen".
  ///
  /// **Alle vor Fassung 63 berechneten Werte sind gelöscht.** Sie entstanden
  /// mit einer falschen Normierung (0..1 statt -1..1) und stimmten nicht:
  /// An der echten Bibliothek meldete das Modell für 64,5 % der grossen
  /// Gesichter „geschlossen"; fünf zufällig herausgegriffene Gesichter mit
  /// dem Wert 0,00 hatten allesamt die Augen offen, ein schlafendes Kind
  /// stand bei 0,98. Nachgesehen wurde an den gespeicherten Ausschnitten,
  /// nicht im Quelltext – im Quelltext sah die Zeile richtig aus.
  ///
  /// Der Wert wird deshalb nur noch dort gezeigt, wo das Gesicht daneben
  /// steht (siehe SerienvergleichScreen) und nicht mehr als Warnung ohne
  /// Bild: Eine Behauptung, die man nicht nachprüfen kann, gehört nicht in
  /// einen Ablauf, an dessen Ende gelöscht wird.
  RealColumn get eyeOpenScore => real().nullable()();

  /// Schärfe des Gesichtsausschnitts (Laplace-Varianz, siehe
  /// [gesichtsschaerfe]) – `null` heisst „noch nicht berechnet".
  ///
  /// **Warum am Gesicht und nicht am Foto.** [Assets.sharpnessScore] misst
  /// das ganze Bild. Ein Porträt mit unscharfem Gesicht vor scharfem Laub
  /// besteht diese Prüfung mühelos, und beim Sichten ist genau das die
  /// Aufnahme, die man aussortieren will.
  ///
  /// Gerechnet wird auf dem 160x160-Ausschnitt, der ohnehin entsteht – die
  /// Zahl kostet damit rund zwei Millisekunden je Gesicht und keinen
  /// zusätzlichen Dekodiervorgang.
  RealColumn get schaerfe => real().nullable()();

  /// Vom Nutzer beiseitegelegt: kein Gesicht (Plakat, Spiegelung, Statue)
  /// oder eine Person, die er nicht benennen will.
  ///
  /// Bewusst ein Merkmal statt eines Löschens. Löschen wäre endgültig und
  /// obendrein wirkungslos: Der nächste Gesichts-Scan fände dieselbe Stelle
  /// erneut und legte den Eintrag neu an. Ein beiseitegelegtes Gesicht
  /// verschwindet aus dem Raster und aus der automatischen Gruppierung,
  /// bleibt aber unter „Ignoriert" auffindbar und rückholbar.
  BoolColumn get isIgnored => boolean().withDefault(const Constant(false))();

  /// Wer hier vermutlich zu sehen ist – gerechnet, nicht bestaetigt.
  ///
  /// **Warum das in der Tabelle steht und nicht bei Bedarf gerechnet
  /// wird.** Die Rechnung ist ein Vergleich jedes Gesichts mit jedem
  /// Personenkern; an der echten Bibliothek sind das 14.065 mal 45
  /// Vergleiche ueber je 512 Zahlen. Das ist als Hintergrundlauf richtig
  /// aufgehoben und als Antwort auf „wie viel liegt an?" unbrauchbar.
  /// Mit der Spalte kostet die Zahl auf dem Gesundheitsbildschirm eine
  /// gewoehnliche Zaehlung.
  ///
  /// Vorschlag heisst Vorschlag: Zugeordnet wird erst, wenn jemand
  /// zugestimmt hat. Ein uebersehener Fehlvorschlag kostet eine falsche
  /// Zuordnung, und die faellt spaeter niemandem mehr auf.
  TextColumn get vorschlagPersonId => text().nullable()();

  /// Die Aehnlichkeit zum Kern dieser Person, zum Zeitpunkt der Rechnung.
  ///
  /// Wird beim Bestaetigen oder Ablehnen als Rueckmeldung festgehalten
  /// (siehe [Gesichtsrueckmeldungen]) – ohne den Wert liesse sich aus der
  /// Entscheidung keine Schwelle ableiten.
  RealColumn get vorschlagWert => real().nullable()();

  /// Wann zuletzt nach einem Vorschlag gesucht wurde – auch dann gesetzt,
  /// wenn nichts nahe genug lag.
  ///
  /// Ohne diese Marke waere „noch nicht geprueft" von „geprueft, nichts
  /// gefunden" nicht zu unterscheiden, und jeder Lauf faenge wieder bei
  /// allen 14.065 an.
  DateTimeColumn get vorschlagGeprueftAm => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// CLIP-Bild-Embedding eines Assets (Float32-Vektor als Bytes), für die
/// KI-Bildsuche in natürlicher Sprache. Ähnlichkeit wird zur Laufzeit per
/// Brute-Force-Kosinus-Distanz berechnet – für private Bibliotheken
/// (bis zu einigen Zehntausend Fotos) schnell genug, ganz ohne
/// Vektordatenbank-Server.
class ImageEmbeddings extends Table {
  TextColumn get assetId => text()();
  BlobColumn get vector => blob()();

  @override
  Set<Column> get primaryKey => {assetId};
}

/// Einzeilige Tabelle (id immer 0) für den PIN-Schutz des gesperrten
/// Ordners – "Envelope Encryption": ein zufälliger Master-Key verschlüsselt
/// tatsächlich die Dateien (siehe VaultCrypto), der PIN verschlüsselt nur
/// diesen Master-Key (über Argon2id abgeleitet). Es wird nie der PIN selbst
/// gespeichert; die einzige PIN-Prüfung ist der Versuch, den Master-Key
/// damit zu entpacken (schlägt bei falschem PIN durch die
/// GCM-Authentifizierung fehl). `pinHash`/`pinSalt` sind Altlasten aus einer
/// früheren, rein anzeige-filternden (nicht verschlüsselnden) Version und
/// werden nicht mehr genutzt.
@DataClassName('PrivacySettingsData')
class PrivacySettings extends Table {
  IntColumn get id => integer()();
  TextColumn get pinHash => text().nullable()();
  TextColumn get pinSalt => text().nullable()();
  BlobColumn get kdfSalt => blob().nullable()();
  BlobColumn get wrappedMasterKeyNonce => blob().nullable()();
  BlobColumn get wrappedMasterKey => blob().nullable()();

  /// Entfernt bei neu gesperrten Aufnahmen zusätzlich lesbare Angaben aus
  /// der SQLite-Datei. Die Werte liegen dann authentifiziert verschlüsselt
  /// neben den ebenfalls verschlüsselten Mediendateien und kehren erst beim
  /// dauerhaften Entsperren zurück.
  BoolColumn get protectMetadata =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BackupRecordData')
class BackupRecords extends Table {
  TextColumn get id => text()();
  DateTimeColumn get performedAt => dateTime()();
  TextColumn get destinationPath => text()();
  IntColumn get fileCount => integer()();
  IntColumn get totalBytes => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Einzeilige Tabelle (id immer 0) für die Backup-Verschlüsselung: derselbe
/// Envelope-Ansatz wie [PrivacySettings], aber mit eigenem Master-Key und
/// eigener Passphrase (bewusst getrennt vom PIN des gesperrten Ordners –
/// ein Backup landet oft extern, z.B. in einem Cloud-Sync-Ordner, und muss
/// unabhängig von der lokalen Bibliothek entschlüsselbar sein). Der
/// verpackte Schlüssel wird deshalb zusätzlich als kleine Datei ins Backup
/// selbst geschrieben (siehe BackupService), nicht nur hier lokal.
///
/// [autoBackupEnabled]/[autoBackupDestination]/[autoBackupIntervalHours]/
/// [lastAutoBackupAt] konfigurieren das automatische Backup (läuft nur,
/// während die App offen ist – kein Hintergrunddienst).
@DataClassName('BackupSettingsData')
class BackupSettings extends Table {
  IntColumn get id => integer()();
  BlobColumn get kdfSalt => blob().nullable()();
  BlobColumn get wrappedMasterKeyNonce => blob().nullable()();
  BlobColumn get wrappedMasterKey => blob().nullable()();

  BoolColumn get autoBackupEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get autoBackupDestination => text().nullable()();
  IntColumn get autoBackupIntervalHours =>
      integer().withDefault(const Constant(24))();
  DateTimeColumn get lastAutoBackupAt => dateTime().nullable()();

  /// Obergrenze je Sicherungslauf in Megabyte, 0 = unbegrenzt.
  ///
  /// Gedacht für Cloud-Ordner: Ohne Grenze landen bei der ersten Sicherung
  /// zigtausend Dateien auf einmal im Sync-Ordner, und der Upload läuft
  /// danach stunden- bis tagelang. Mit Grenze wird portionsweise gesichert,
  /// der Rest folgt beim nächsten Intervall.
  IntColumn get autoBackupMaxMbPerRun =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Einzeilige Tabelle (id immer 0) für den automatischen Papierkorb-Ablauf:
/// löscht in den Papierkorb verschobene Assets nach [autoDeleteAfterDays]
/// Tagen endgültig (Dateien + DB-Zeile) – läuft, wie das automatische
/// Backup, nur während die App geöffnet ist (siehe
/// [LibraryState.purgeExpiredTrashIfDue]). Standardmäßig deaktiviert, damit
/// niemand unerwartet Fotos verliert, die "nur eben" im Papierkorb lagen.
@DataClassName('TrashSettingsData')
class TrashSettings extends Table {
  IntColumn get id => integer()();
  BoolColumn get autoDeleteEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get autoDeleteAfterDays =>
      integer().withDefault(const Constant(30))();
  DateTimeColumn get lastPurgeAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Einzeilige Tabelle (id immer 0, gleiches Muster wie [TrashSettings]) für
/// app-weite Oberflächen-Einstellungen – aktuell nur das Erscheinungsbild.
/// [themeMode] als Text ('system'|'light'|'dark') statt als Enum-Index
/// gespeichert, damit eine künftige Umsortierung von [ThemeMode] die
/// gespeicherte Bedeutung nicht verschiebt.
@DataClassName('AppSettingsData')
class AppSettings extends Table {
  IntColumn get id => integer()();
  TextColumn get themeMode => text().withDefault(const Constant('system'))();

  /// Oberflächensprache: `'system'`, `'de'` oder `'en'`.
  ///
  /// Dasselbe Muster wie [themeMode], und aus demselben Grund als Text
  /// statt als Aufzählung: Eine unbekannte Angabe (etwa aus einer
  /// neueren Fassung) fällt beim Lesen auf den Standard zurück, statt
  /// den Start zu verhindern.
  TextColumn get sprache => text().withDefault(const Constant('system'))();

  /// Ob die rechenintensiven KI-Auswertungen (Gesichter, Texterkennung,
  /// CLIP, Bildbeschreibung, Unschärfe) nach einem Import automatisch als
  /// Hintergrundaufgabe nachlaufen. Standard an – sonst blieben frisch
  /// importierte Fotos ohne Suche und ohne Personenzuordnung, bis jemand
  /// die Werkzeuge von Hand anstößt.
  BoolColumn get autoAnalyzeAfterImport =>
      boolean().withDefault(const Constant(true))();

  /// Ordner, der laufend auf neue Dateien geprüft wird (siehe
  /// LibraryState.pruefeUeberwachtenOrdner). Null = keiner eingerichtet.
  ///
  /// Der Zugriff braucht unter macOS zusätzlich das Sandbox-Merkmal aus der
  /// Ordnerauswahl, sonst erlischt er beim nächsten Programmstart – deshalb
  /// beide Angaben zusammen, wie bei den Bibliotheksorten auch.
  TextColumn get watchedFolderPath => text().nullable()();
  TextColumn get watchedFolderToken => text().nullable()();

  /// Allgemeine Schwelle für "dasselbe Gesicht" (Kosinus-Ähnlichkeit).
  ///
  /// 0,363 ist der von OpenCV Zoo für SFace dokumentierte Wert. Die
  /// Einstellung lag bisher nur im Speicher – der Regler unter "Werkzeuge"
  /// war bei jedem Programmstart wieder auf dem Ausgangswert, ohne dass
  /// das irgendwo stand.
  RealColumn get faceSimilarityThreshold =>
      real().withDefault(const Constant(0.363))();

  /// Zuletzt gewählte Kartenansicht: `'hell'`, `'dunkel'`, `'topo'` oder
  /// `'globus'` (siehe `Kartenansicht` in map_screen.dart).
  ///
  /// Als Text und nicht als Zahl, aus demselben Grund wie bei [themeMode]:
  /// Eine unbekannte Angabe fällt beim Lesen auf die dunkle Karte zurück,
  /// statt den Start zu verhindern.
  ///
  /// Die Wahl lag bisher nur im Bildschirmzustand. Wer die
  /// Topografiekarte einstellte und die Ansicht verliess, fand beim
  /// nächsten Öffnen wieder die dunkle vor - ohne dass das irgendwo
  /// stand. Derselbe Fall wie seinerzeit bei
  /// [faceSimilarityThreshold].
  TextColumn get kartenansicht =>
      text().withDefault(const Constant('dunkel'))();

  /// Schlüssel für die CARTO-Kacheln der dunklen Karte. Null = keiner.
  ///
  /// **Warum das überhaupt eine Einstellung ist.** CARTO hat die
  /// kostenlose Nutzung ohne Schlüssel beendet und schreibt seither
  /// quer über jede einzelne Kachel „API KEY REQUIRED" – auf jeder
  /// Zoomstufe, auch über den alten Fastly-Namen. Nachgemessen an einer
  /// Kachel Berlin-Mitte, Stufen 10 bis 20: der Stempel steht auf allen.
  ///
  /// Ohne Schlüssel zeichnet die dunkle Karte deshalb invertierte
  /// OpenStreetMap-Kacheln (siehe `Kartenstil.dunkel`). Wer den
  /// gewohnten Dark-Matter-Schnitt zurückwill, trägt hier seinen
  /// Schlüssel ein – CARTO gibt ihn kostenlos und **ohne Konto** aus,
  /// bis zu 5 Millionen Kacheln im Monat.
  ///
  /// In der Datenbank und nicht im Quelltext, und das ist der Punkt:
  /// Ein mitgelieferter Schlüssel wäre über den öffentlichen Spiegel
  /// für jeden lesbar und liefe auf eine Zugangskennung im Repository
  /// hinaus. Er gehört dem, der ihn beantragt.
  TextColumn get cartoSchluessel => text().nullable()();

  /// Anzeigename der eigenen Kartenquelle, z. B. „Mapbox Streets".
  ///
  /// **Warum es diese Quelle überhaupt gibt.** Die drei mitgelieferten
  /// Stile hängen an frei betriebenen Servern: OpenStreetMap trägt bis
  /// Zoomstufe 19, OpenTopoMap nur bis 17. Wer Hausnummern und
  /// Gebäudeumrisse braucht oder ein Luftbild, kommt an einem
  /// Anbieter mit Schlüssel nicht vorbei – und der gehört dem, der ihn
  /// beantragt, genau wie beim CARTO-Schlüssel.
  ///
  /// Als vier lose Spalten und nicht als Tabelle: Es ist **eine**
  /// Quelle, nicht eine Liste. Wer zwischen mehreren wechseln will,
  /// tauscht die Angaben – eine Verwaltung mit Anlegen, Umbenennen und
  /// Löschen wäre für einen einzigen Eintrag zu viel Maschine.
  TextColumn get eigeneKarteName => text().nullable()();

  /// Adressvorlage der eigenen Kartenquelle, mit `{z}`, `{x}`, `{y}`.
  ///
  /// Der Schlüssel steht **mit in dieser Adresse** und nicht in einer
  /// eigenen Spalte. Das ist Absicht: Jeder Anbieter hängt ihn woanders
  /// hin – Mapbox als `?access_token=`, MapTiler als `?key=`,
  /// Thunderforest als `?apikey=`, Google als `?session=…&key=`. Eine
  /// eigene Spalte müsste all diese Formen kennen und wäre bei jedem
  /// weiteren Anbieter wieder falsch.
  TextColumn get eigeneKarteUrl => text().nullable()();

  /// Die Namensnennung, die unter der eigenen Karte stehen muss.
  ///
  /// Keine Zierde, sondern die Lizenzauflage praktisch jedes Anbieters.
  /// Deshalb ist sie ein Pflichtfeld in der Einstellung: Ohne sie lässt
  /// sich die Quelle nicht einschalten.
  TextColumn get eigeneKarteNennung => text().nullable()();

  /// Höchste Stufe, für die der eigene Anbieter echte Kacheln liefert.
  ///
  /// Ohne Angabe gilt 19. Zu hoch angesetzt heisst: leere oder
  /// einfarbige Kacheln, ohne Fehlermeldung – genau die Falle, die bei
  /// OpenTopoMap gemessen wurde (siehe `Kartenstil.topo`).
  IntColumn get eigeneKarteStufe => integer().nullable()();

  /// Ob der Hinweis zu Datenübermittlung und Offline-Nutzung bestätigt
  /// wurde.
  ///
  /// **Ein eigener Wert und keine blosse Dialogfrage**, weil er etwas
  /// anderes bedeutet als „Adresse eingetragen": Diese App holt ihre
  /// Kacheln sonst von Servern, die niemandem Rechenschaft schulden.
  /// Eine Fremdquelle mit Schlüssel sieht dagegen jede angesehene
  /// Stelle **und** weiss, wer hinsieht. Wer das einschaltet, soll es
  /// einmal ausdrücklich gelesen haben – und nicht bei jedem Start neu
  /// gefragt werden.
  BoolColumn get eigeneKarteZugestimmt =>
      boolean().withDefault(const Constant(false))();

  /// Ob die Karte auf einem Bildschirm mit doppelter Punktdichte auch in
  /// doppelter Auflösung zeichnet.
  ///
  /// **Ein Handel, und beide Seiten sind gemessen.** Eine Kachel ist 256
  /// Pixel breit und wird auf 256 Punkte gezeichnet – auf einem
  /// Retina-Schirm also auf 512 Gerätepunkte, jeder Kachelpixel deckt
  /// vier. Dagegen holt die Karte vier Kacheln der nächsttieferen Stufe
  /// und setzt sie an die Stelle einer: viermal so viele Bildpunkte auf
  /// derselben Fläche (Schärfe bei Topo z16 von 11,70 auf 44,27), aber
  /// eben auch **2,6-mal so viele Kacheln je Bildschirm** – auf einem
  /// 1440×900-Fenster 165 statt 63. Jede davon ist ein Griff auf die
  /// Platte und ein Dekodiervorgang, und beim Zoomen fallen sie alle auf
  /// einmal an.
  ///
  /// Vorgabe an: Schärfe ist der Regelfall. Wer eine langsamere Maschine
  /// hat oder viel zoomt, schaltet sie ab und bekommt die Karte von
  /// vorher.
  BoolColumn get karteHochaufloesend =>
      boolean().withDefault(const Constant(true))();

  /// Welche Tageszeit über der Geländeansicht steht – als Nummer aus
  /// [Tageszeit].
  ///
  /// Als Zahl und nicht als Name, aus demselben Grund wie beim
  /// Kartenstil: Ein Name aus einer aelteren Fassung koennte einer sein,
  /// den es nicht mehr gibt. Eine Nummer ausserhalb der Reihe faellt
  /// ueber [tageszeit] auf die Vorgabe zurueck.
  IntColumn get gelaendeStimmungNr =>
      integer().withDefault(Constant(lichtstimmungVorgabe.index))();

  /// Was unter der Landschaft liegt – als Nummer aus [Gelaendegrund].
  ///
  /// **Vorgabe Luftbild und nicht die Wanderkarte, die es bisher als
  /// einzige gab.** Das ist eine sichtbare Aenderung fuer alle, und sie
  /// ist Absicht: Eine Wanderkarte in Schraeglage beantwortet „wie hiess
  /// der Weg"; ein Luftbild beantwortet „wie sah es dort aus", und das
  /// ist die Frage, wegen der jemand einen Ueberflug ansieht. Zurueck
  /// geht es mit einem Griff ins Kartenmenue.
  IntColumn get gelaendeGrundNr =>
      integer().withDefault(Constant(Gelaendegrund.luftbild.index))();

  /// Ob die Wanderwege ueber der Landschaft liegen.
  ///
  /// **Vorgabe an, und der Grund steht in einer Kachel.** An der echten
  /// Kachel des Ilsetals nachgesehen (51,8433 N / 10,6553 O, Stufe 17):
  /// Das Luftbild zeigt dichten Wald – der Weg, auf dem die Wanderung
  /// verlief, ist darauf NICHT zu sehen. Ohne diese Ebene waere das
  /// Luftbild als Wanderkarte unbrauchbar.
  BoolColumn get gelaendeWege => boolean().withDefault(const Constant(true))();

  /// Ob Strassen, Grenzen und Ortsnamen darueber liegen.
  BoolColumn get gelaendeBeschriftung =>
      boolean().withDefault(const Constant(true))();

  /// Ob Hoehenlinien eingezeichnet werden.
  ///
  /// Sie werden nicht geladen, sondern aus demselben Hoehengitter
  /// gerechnet, aus dem die Landschaft gebaut ist (siehe
  /// `hoehenlinien.dart`) – sie kosten also keinen einzigen Abruf und
  /// koennen gar nicht neben dem Hang liegen, den sie beschreiben.
  BoolColumn get gelaendeHoehenlinien =>
      boolean().withDefault(const Constant(true))();

  /// Ob Gipfel, Huetten und Quellen als Schilder ueber der Landschaft
  /// stehen.
  ///
  /// **Eigener Schalter und nicht an [gelaendeBeschriftung] gehaengt.**
  /// Die anderen Ebenen sind Kacheln von einem Auslieferungsnetz; diese
  /// hier kostet eine Abfrage bei Overpass, einem oeffentlichen Dienst
  /// mit Grenzen. Wer sie nicht braucht, soll ihn nicht fragen muessen.
  BoolColumn get gelaendeWanderobjekte =>
      boolean().withDefault(const Constant(true))();

  /// Ob ein Video oder ein Live Photo von selbst anlaeuft, wenn die Maus
  /// einen Augenblick darauf stehen bleibt.
  ///
  /// Vorgabe an: Es ist der Grund, warum es die Einstellung gibt. Wer die
  /// Bewegung im Raster nicht mag oder auf einer langsamen Maschine
  /// sitzt, schaltet sie ab und bekommt die stillen Kacheln von vorher.
  ///
  /// Der Ton bleibt in jedem Fall aus – siehe
  /// [Schwebevorschau.starte]. Eine Wand aus Kacheln, die beim
  /// Ueberstreichen zu toenen anfaengt, waere niemandem eine Hilfe.
  BoolColumn get schwebeVorschau =>
      boolean().withDefault(const Constant(true))();

  /// Welche Ansicht des Stammbaums zuletzt offen war und wer darin in der
  /// Mitte stand.
  ///
  /// Sechs Ansichten (Baum, Fächer, Sanduhr, Nachfahren, Verwandte,
  /// Zeitleiste) und je nach Familie hunderte Personen: Wer den
  /// Stammbaum schliesst und wieder aufschlägt, fing bis hierher jedes
  /// Mal beim Baum und bei der Person mit den meisten Verwandten an.
  ///
  /// Als Text und nullbar, aus demselben Grund wie bei [kartenansicht]:
  /// Eine Ansicht, die es nicht mehr gibt, oder eine Person, die
  /// gelöscht wurde, fällt beim Lesen auf die bisherige Wahl zurück,
  /// statt den Bildschirm zu verhindern.
  TextColumn get stammbaumAnsicht => text().nullable()();
  TextColumn get stammbaumPerson => text().nullable()();

  /// Wie gross die Kacheln der Zeitleiste sind – als Stufe, siehe
  /// [zeitleisteKachelstufen].
  ///
  /// Als Zahl und nicht als Breite in Punkten: Eine Breite aus einer
  /// alten Fassung koennte eine sein, die es nicht mehr gibt, und jede
  /// Zwischengroesse waere ein eigener Schluessel im Bildspeicher.
  IntColumn get zeitleisteKachelstufe =>
      integer().withDefault(const Constant(zeitleisteKachelstufeVorgabe))();

  /// Ob die Zeitleiste Quadrate zeigt oder buendige Reihen – als Nummer
  /// aus [Zeitleistenform].
  ///
  /// Als Zahl und nicht als Name: Ein Name aus einer aelteren Fassung
  /// koennte einer sein, den es nicht mehr gibt. Eine Nummer ausserhalb
  /// der Reihe faellt ueber [zeitleisteForm] auf die Vorgabe zurueck,
  /// statt den Bildschirm zu verhindern – dieselbe Regel wie beim
  /// Kartenstil.
  IntColumn get zeitleisteFormNr =>
      integer().withDefault(Constant(zeitleisteFormVorgabe.index))();

  /// Wonach die Zeitleiste ordnet – als Nummer aus [Rastersortierung].
  ///
  /// Als Zahl und aus demselben Grund wie bei [zeitleisteFormNr]: Ein
  /// Name aus einer aelteren Fassung koennte einer sein, den es nicht
  /// mehr gibt.
  IntColumn get zeitleisteSortierungNr =>
      integer().withDefault(Constant(rastersortierungVorgabe.index))();

  /// Welche Spalten die Listenansicht zeigt und wie breit sie sind –
  /// als Text, siehe [Listenspaltenwahl.alsText].
  ///
  /// `null` heisst Vorgabe: genau die fuenf Angaben, die es vorher gab.
  TextColumn get listenspalten => text().nullable()();

  /// Wie viele rechenintensive Aufgaben gleichzeitig laufen dürfen.
  ///
  /// **Warum das eine Einstellung ist und keine Konstante.** Bis hierher
  /// wurde eine zweite schwere Aufgabe schlicht **abgewiesen**: Wer
  /// Gesichter scannen liess und danach die Bildbeschreibungen anstiess,
  /// bekam eine Meldung und musste sich das Ende der ersten merken. Jetzt
  /// wird sie eingereiht — und wie viele nebeneinander laufen dürfen,
  /// hängt an der Maschine. Ein Rechner mit 64 GB verkraftet zwei Modelle
  /// nebeneinander, einer mit 8 GB nicht (allein CLIP-Bild 335 MB und die
  /// Bildbeschreibung 235 MB, gemessen).
  ///
  /// Vorgabe **eins**, also genau das bisherige Verhalten – nur ohne die
  /// Abweisung. Aufgaben ohne Modell (Orte einlesen, XMP schreiben,
  /// Live-Photo-Paare) zählen hier nicht mit; sie kosten nichts, was sich
  /// gegenseitig im Weg stünde.
  IntColumn get maxGleichzeitig => integer().withDefault(const Constant(1))();

  /// Bildbeschreibungen ins Deutsche übersetzen (Modell `translation_en_de`).
  BoolColumn get translateCaptions =>
      boolean().withDefault(const Constant(false))();

  /// Deutsche Suchanfragen und Schlagwörter vor der KI-Bildsuche ins
  /// Englische übersetzen (Modell `translation_de_en`).
  ///
  /// Standard aus, und zwar bewusst: An 103 Fotos der Testbibliothek
  /// gemessen trennt die englische Fassung eines Vokabelbegriffs bei 33
  /// von 56 Begriffen schärfer, bei 19 schlechter. Der Gewinn ist real,
  /// aber weder gross noch durchgängig – und die Zahl vergebener Tags
  /// sinkt bei gleicher Schwelle von 402 auf 248. Eine solche Änderung
  /// gehört nicht stillschweigend eingeschaltet.
  BoolColumn get translateSearchAndTags =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
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

/// Ein Foto-Paar, das der Nutzer bei der Duplikatsuche nicht mehr sehen
/// will („die beiden sind schon in Ordnung so").
///
/// Paarweise und nicht je Foto – das ist der Unterschied, auf den es
/// ankommt: Wer ein Foto als Ganzes von der Suche ausnähme, fände auch das
/// echte Duplikat nicht mehr, das nächste Woche dazukommt. Die Ausnahme
/// gilt deshalb nur für genau diese Kombination.
///
/// [assetA] ist immer die kleinere der beiden Kennungen (siehe
/// [AppDatabase.ignoriereDuplikatpaare]), sonst müsste jede Abfrage beide
/// Reihenfolgen prüfen.
@DataClassName('DuplikatAusnahmeData')
class DuplikatAusnahmen extends Table {
  TextColumn get assetA => text()();
  TextColumn get assetB => text()();
  DateTimeColumn get angelegtAm => dateTime()();

  @override
  Set<Column> get primaryKey => {assetA, assetB};
}

class _SperrWiederholung extends QueryInterceptor {
  Future<T> _wiederhole<T>(Future<T> Function() arbeit) async {
    final uhr = Stopwatch()..start();
    while (true) {
      try {
        return await arbeit();
      } catch (e, stack) {
        if (!_istSperre(e) ||
            uhr.elapsedMilliseconds >= AppDatabase.sperrwartezeitMs) {
          Error.throwWithStackTrace(e, stack);
        }
        final rest = AppDatabase.sperrwartezeitMs - uhr.elapsedMilliseconds;
        await Future<void>.delayed(Duration(milliseconds: rest.clamp(1, 40)));
      }
    }
  }

  // Fehler eines Hintergrund-Isolats können von Drift als entferntes
  // Fehlerobjekt zurückkommen. Dann bleibt der SQLite-Code in der stabilen
  // Textdarstellung erhalten, auch wenn der konkrete Dart-Typ verloren ist.
  bool _istSperre(Object fehler) {
    if (fehler is SqliteException) {
      return fehler.resultCode == 5 || fehler.resultCode == 6;
    }
    final fund = RegExp(r'^SqliteException\((\d+)\):').firstMatch('$fehler');
    final code = fund == null ? null : int.tryParse(fund.group(1)!);
    return code != null && (code & 0xff == 5 || code & 0xff == 6);
  }

  @override
  Future<void> runBatched(
          QueryExecutor executor, BatchedStatements statements) =>
      _wiederhole(() => executor.runBatched(statements));

  @override
  Future<void> runCustom(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _wiederhole(() => executor.runCustom(statement, args));

  @override
  Future<int> runInsert(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _wiederhole(() => executor.runInsert(statement, args));

  @override
  Future<int> runDelete(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _wiederhole(() => executor.runDelete(statement, args));

  @override
  Future<int> runUpdate(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _wiederhole(() => executor.runUpdate(statement, args));

  @override
  Future<List<Map<String, Object?>>> runSelect(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _wiederhole(() => executor.runSelect(statement, args));
}

@DriftDatabase(tables: [
  Assets,
  Albums,
  AlbumAssets,
  Tags,
  AssetTags,
  People,
  Faces,
  FaceMatchFeedback,
  ImageEmbeddings,
  BackupRecords,
  PrivacySettings,
  BackupSettings,
  SavedSearches,
  TrashSettings,
  DuplikatAusnahmen,
  CameraPresets,
  CameraPresetTags,
  DevelopSettings,
  DevelopHistory,
  VideoTrims,
  DevelopMasks,
  RestoreJobs,
  AppSettings,
  AiTagVocabulary,
  AutomationRules,
  AutomationRuleTags,
  DevelopPresets,
  ExportPresets,
  PersonBeziehungen,
  Lebensereignisse,
  Reisen,
  ReiseAufnahmen,
  Reisetagnotizen,
  VerworfeneReisen,
  Ortsmarken,
  Aktivitaeten,
  AktivitaetAufnahmen,
  VerworfeneAktivitaeten,
  Spuren,
  Spurpunkte,
  VerworfeneSerien,
  VerworfeneOrtsvorschlaege,
  Videoeinbettungen,
  Wanderpunkte,
  Wanderabfragen,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Wird bei jeder Mutation erhöht, die das Ergebnis von [allEmbeddings]
  /// verändern könnte (neues/aktualisiertes Embedding, Papierkorb/
  /// Wiederherstellen, endgültiges Löschen, Sperren/Entsperren) – LibraryState
  /// nutzt das als billigen "ist mein gecachtes allEmbeddings()-Ergebnis noch
  /// aktuell?"-Check, ohne bei jeder Suche erneut alle Embeddings (oft
  /// hunderte MB bei großen Bibliotheken) aus der DB laden zu müssen.
  int _embeddingsGeneration = 0;
  int get embeddingsGeneration => _embeddingsGeneration;

  @override
  int get schemaVersion => 85;

  Future<void> _createAssetSearchFts() async {
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS asset_search_fts USING fts5(
        asset_id UNINDEXED,
        original_file_name,
        description,
        ocr_text,
        ai_caption,
        ai_caption_de,
        tokenize = 'unicode61 remove_diacritics 2'
      )
    ''');
    await customStatement('DELETE FROM asset_search_fts');
    await customStatement('''
      INSERT INTO asset_search_fts
        (asset_id, original_file_name, description, ocr_text, ai_caption, ai_caption_de)
      SELECT id, original_file_name, coalesce(description, ''),
             coalesce(ocr_text, ''), coalesce(ai_caption, ''),
             coalesce(ai_caption_de, '')
      FROM assets
    ''');
    await _createAssetSearchTriggers();
  }

  /// Die drei Auslöser, die den Volltextindex mitführen.
  ///
  /// Eigene Methode, weil die Wanderung auf 84 **nur sie** neu setzt: Der
  /// Index selbst bleibt gültig, ihn dabei neu aufzubauen wäre für 8098
  /// Aufnahmen umsonst getane Arbeit.
  Future<void> _createAssetSearchTriggers() async {
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS assets_fts_insert AFTER INSERT ON assets BEGIN
        INSERT INTO asset_search_fts
          (asset_id, original_file_name, description, ocr_text, ai_caption, ai_caption_de)
        VALUES (new.id, new.original_file_name, coalesce(new.description, ''),
                coalesce(new.ocr_text, ''), coalesce(new.ai_caption, ''),
                coalesce(new.ai_caption_de, ''));
      END
    ''');
    // **`UPDATE OF` genügt nicht.** Es feuert, sobald eine der Spalten in
    // der SET-Klausel STEHT – nicht erst, wenn sich ihr Wert ändert. drift
    // schreibt bei `update(...).write(...)` regelmässig ganze Zeilen zurück,
    // und die Durchgänge (Texterkennung, Bildbeschreibung) tun das für die
    // ganze Bibliothek. Gemessen kostet ein Zeilen-UPDATE mit Auslöser
    // 1,56 ms gegen 0,03 ms ohne – das Zweiundfünfzigfache, und eine
    // Transaktion hilft kaum, weil der Preis das Neuschreiben des Index ist
    // und nicht das Sichern auf die Platte. Über 8098 Aufnahmen sind das
    // rund neun Sekunden je Durchgang, für lauter unveränderten Text.
    //
    // `IS NOT` und nicht `<>`: Nur `IS NOT` vergleicht NULL richtig. Mit
    // `<>` wäre jeder Übergang von oder nach NULL unbemerkt geblieben – und
    // genau so sieht das erste Beschreiben eines leeren Feldes aus.
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS assets_fts_update
      AFTER UPDATE OF original_file_name, description, ocr_text, ai_caption, ai_caption_de
      ON assets
      WHEN new.original_file_name IS NOT old.original_file_name
        OR new.description IS NOT old.description
        OR new.ocr_text IS NOT old.ocr_text
        OR new.ai_caption IS NOT old.ai_caption
        OR new.ai_caption_de IS NOT old.ai_caption_de
      BEGIN
        DELETE FROM asset_search_fts WHERE asset_id = old.id;
        INSERT INTO asset_search_fts
          (asset_id, original_file_name, description, ocr_text, ai_caption, ai_caption_de)
        VALUES (new.id, new.original_file_name, coalesce(new.description, ''),
                coalesce(new.ocr_text, ''), coalesce(new.ai_caption, ''),
                coalesce(new.ai_caption_de, ''));
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS assets_fts_delete AFTER DELETE ON assets BEGIN
        DELETE FROM asset_search_fts WHERE asset_id = old.id;
      END
    ''');
  }

  /// Bestückt AiTagVocabulary mit dem ursprünglichen, festen Begriffs-Array
  /// – für Neuinstallationen ([onCreate], das NICHT durch [onUpgrade] läuft)
  /// ebenso wie für das Upgrade bestehender Installationen auf v24.
  Future<void> _seedAiTagVocabulary() => batch((b) => b.insertAll(
        aiTagVocabulary,
        [
          for (final term in defaultAiTagVocabulary)
            AiTagVocabularyCompanion.insert(term: term)
        ],
      ));

  /// Indizes für die im Betrieb häufigsten Filter/Sortierungen – ohne sie
  /// degenerieren mehrere Abfragen (Timeline/Alben/Personen-Ansicht, die
  /// Personen-/Album-Filter in [searchAssets]) bei wachsender Bibliothek zu
  /// vollständigen Tabellen-Scans, siehe die einzelnen Abfragen weiter unten.
  /// In einer eigenen Methode, damit sowohl frisch angelegte Datenbanken
  /// ([onCreate]) als auch bestehende (Migration `from < 11`) dieselben
  /// Indizes bekommen.
  /// Der Index für „gehört diese Aufnahme schon zu einer Reise?".
  ///
  /// In einer eigenen Routine und aus **beiden** Wegen aufgerufen – aus
  /// [onCreate] wie aus der Migration. Ein Index, den nur bestehende
  /// Bibliotheken bekommen, fehlt genau dort, wo niemand ihn vermisst:
  /// bei der Neuinstallation.
  Future<void> _createIndicesV51(Migrator m) =>
      customStatement('CREATE INDEX IF NOT EXISTS idx_reise_aufnahme_asset '
          'ON reise_aufnahmen (asset_id)');

  Future<void> _createIndicesV55(Migrator m) async {
    // Die Punkte einer Spur werden immer am Stück und in ihrer
    // Reihenfolge geholt; ohne Index wäre das bei zehntausend Punkten je
    // Spur ein Durchlauf über alle Spuren.
    await customStatement('CREATE INDEX IF NOT EXISTS idx_spurpunkte_spur '
        'ON spurpunkte (spur_id, nummer)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_spuren_aktivitaet '
        'ON spuren (aktivitaet_id)');
  }

  Future<void> _createIndicesV54(Migrator m) async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_aktivitaet_aufnahme_asset '
        'ON aktivitaet_aufnahmen (asset_id)');
    // Die Aktivitäten einer Reise werden bei jedem Öffnen einer Reise
    // geholt; ohne Index ist das ein Durchlauf über alle.
    await customStatement('CREATE INDEX IF NOT EXISTS idx_aktivitaeten_reise '
        'ON aktivitaeten (reise_id)');
  }

  Future<void> _createPerformanceIndices(Migrator m) async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assets_trashed_locked_created '
        'ON assets (is_trashed, is_locked, file_created_at DESC)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_assets_location '
        'ON assets (location_country, location_state, location_city)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_faces_asset_id ON faces (asset_id)');
    // Teilindex, nicht vollständig: Nur ein kleiner Teil aller Gesichter ist
    // beiseitegelegt, und genau danach wird gefragt. Gemessen an 17.836
    // Gesichtern / 7.988 Fotos: ohne Index 8,3 ms, mit Teilindex 0,49 ms.
    // Ein vollständiger Index über is_ignored brachte nichts – der Planer
    // benutzt ihn nicht, weil die Spalte für den Regelfall (0) nichts
    // eingrenzt.
    await customStatement('CREATE INDEX IF NOT EXISTS idx_faces_ignored '
        'ON faces (is_ignored) WHERE is_ignored = 1');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_faces_person_id ON faces (person_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_album_assets_asset_id ON album_assets (asset_id)');
  }

  /// Zusätzliche Indizes ab Version 14: Papierkorb-Sortierung nach Alter
  /// (für den automatischen Ablauf sowie die Papierkorb-Ansichten),
  /// Kartenansicht (nur Fotos mit GPS-Koordinaten) und Backup-Status – alle
  /// drei filtern bei einer sehr großen Bibliothek sonst auf einem
  /// Großteil der Tabelle, ohne dass die bestehenden Indizes (siehe
  /// [_createPerformanceIndices]) dafür etwas hergeben. Die Teilindizes
  /// ("WHERE ...") halten die jeweils indexierte Zeilenmenge klein (nur
  /// GPS-Fotos bzw. noch nicht gesicherte Fotos) statt die komplette
  /// Tabelle zu indexieren.
  Future<void> _createIndicesV14(Migrator m) async {
    await customStatement('CREATE INDEX IF NOT EXISTS idx_assets_trashed_at '
        'ON assets (is_trashed, trashed_at DESC)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_assets_gps '
        'ON assets (latitude, longitude) WHERE latitude IS NOT NULL');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_assets_not_backed_up '
        'ON assets (is_trashed, is_locked) WHERE backed_up = 0');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assets_not_auto_backed_up '
        'ON assets (is_trashed, is_locked) WHERE auto_backed_up = 0');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_assets_camera '
        'ON assets (camera_make, camera_model)');
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createPerformanceIndices(m);
          await _createIndicesV14(m);
          await _createIndicesV48(m);
          await _createIndicesV51(m);
          await _createIndicesV54(m);
          await _createIndicesV55(m);
          await _createAssetSearchFts();
          await _seedAiTagVocabulary();
        },
        // **Die Schritte stehen aufsteigend, und das ist eine Zusage.**
        //
        // Ein Schritt darf voraussetzen, was die niedrigeren angelegt
        // haben – Schritt 65 biegt Zuordnungen in `aktivitaet_aufnahmen`
        // um, und diese Tabelle entsteht in Schritt 54.
        //
        // Ab Schritt 48 standen sie einmal absteigend: 71, 70, 69 … 48.
        // Fuer eine Bibliothek ab Fassung 54 fiel das nie auf, weil die
        // betroffenen Schritte dort gar nicht mehr laufen. Eine aeltere
        // liess sich dagegen **gar nicht mehr oeffnen** – Schritt 65
        // schrieb in eine Tabelle, die Schritt 54 erst spaeter anlegte,
        // und die Migration brach mit „no such table" ab. Gefunden an
        // einer Bibliothek der Fassung 27 (30.08. angelegt, nie wieder
        // geoeffnet), nicht durch Codelesen.
        //
        // `pruefstand_migration_reihenfolge_test.dart` haelt die
        // Reihenfolge fest, damit ein neuer Schritt nicht wieder oben
        // einsortiert wird.
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(assets, assets.facesScanned);
          }
          if (from < 3) {
            await m.addColumn(assets, assets.previewRelativePath);
          }
          if (from < 4) {
            await m.addColumn(assets, assets.linkedAssetId);
          }
          if (from < 5) {
            await m.addColumn(assets, assets.latitude);
            await m.addColumn(assets, assets.longitude);
          }
          if (from < 6) {
            await m.addColumn(assets, assets.isLocked);
            await m.createTable(privacySettings);
          }
          if (from < 7) {
            await m.addColumn(privacySettings, privacySettings.kdfSalt);
            await m.addColumn(
                privacySettings, privacySettings.wrappedMasterKeyNonce);
            await m.addColumn(
                privacySettings, privacySettings.wrappedMasterKey);
            // Das alte Schema (Version 6) hat "gesperrte" Fotos nie
            // tatsächlich verschlüsselt, nur aus den normalen Ansichten
            // gefiltert. Ein bestehender PIN-Hash lässt sich nicht sicher
            // ins neue Master-Key-Schema übernehmen (der Klartext-PIN ist
            // aus einem Hash nicht rekonstruierbar) – deshalb hier
            // zurückgesetzt. Da unter Version 6 ohnehin nie verschlüsselt
            // wurde, ist "entsperren" das einzig korrekte Verhalten (es
            // geht nichts verloren, nur der PIN-Schutz muss neu
            // eingerichtet werden, jetzt mit echter Verschlüsselung).
            await (update(assets)..where((t) => t.isLocked.equals(true)))
                .write(const AssetsCompanion(isLocked: Value(false)));
            await delete(privacySettings).go();
          }
          if (from < 8) {
            await m.addColumn(assets, assets.autoBackedUp);
            await m.createTable(backupSettings);
          }
          if (from < 9) {
            await m.addColumn(assets, assets.cameraMake);
            await m.addColumn(assets, assets.cameraModel);
            await m.addColumn(assets, assets.lensModel);
            await m.addColumn(assets, assets.focalLengthMm);
            await m.addColumn(assets, assets.fNumber);
            await m.addColumn(assets, assets.iso);
            await m.addColumn(assets, assets.exposureTimeSeconds);
          }
          if (from < 10) {
            await m.addColumn(assets, assets.locationCountry);
            await m.addColumn(assets, assets.locationState);
            await m.addColumn(assets, assets.locationCity);
          }
          if (from < 11) {
            await _createPerformanceIndices(m);
          }
          if (from < 12) {
            await m.createTable(savedSearches);
          }
          if (from < 13) {
            await m.createTable(trashSettings);
          }
          if (from < 14) {
            await _createIndicesV14(m);
          }
          if (from < 15) {
            await m.createTable(cameraPresets);
            await m.createTable(cameraPresetTags);
          }
          if (from < 16) {
            await m.addColumn(assets, assets.developedRelativePath);
            await m.createTable(developSettings);
          }
          if (from < 17) {
            await m.addColumn(assets, assets.rating);
            await m.addColumn(assets, assets.colorLabel);
            await m.addColumn(assets, assets.ocrText);
            await m.addColumn(assets, assets.ocrScanned);
            await m.addColumn(assets, assets.sharpnessScore);
          }
          if (from < 18) {
            await m.createTable(developHistory);
          }
          if (from < 19) {
            await m.addColumn(assets, assets.trimmedRelativePath);
            await m.createTable(videoTrims);
          }
          if (from < 20) {
            await m.addColumn(assets, assets.stackId);
            await m.addColumn(assets, assets.isStackCover);
            await m.addColumn(assets, assets.stackSize);
          }
          if (from < 21) {
            await m.createTable(developMasks);
          }
          if (from < 22) {
            await m.addColumn(assets, assets.aiCaption);
            await m.addColumn(assets, assets.aiCaptionScanned);
          }
          if (from < 23) {
            await m.createTable(appSettings);
          }
          if (from < 24) {
            await m.createTable(aiTagVocabulary);
            await _seedAiTagVocabulary();
          }
          if (from < 25) {
            await m.addColumn(faces, faces.eyeOpenScore);
          }
          if (from < 26) {
            await m.addColumn(developMasks, developMasks.shapeDefinitionJson);
          }
          if (from < 27) {
            await m.addColumn(assets, assets.restoredRelativePath);
            await m.createTable(restoreJobs);
          }
          if (from < 28) {
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.autoAnalyzeAfterImport,
                'app_settings',
                'auto_analyze_after_import');
          }
          if (from < 29) {
            // Beide bewusst nachgeholt: Eine fehlerhafte Zwischenfassung hat
            // Datenbanken als Version 28 gestempelt, ohne die zugehörige
            // Spalte anzulegen. Ohne dieses Nachholen bliebe eine so
            // markierte Datenbank dauerhaft unbrauchbar, weil Drift die
            // Migration für erledigt hält und nie erneut ausführt.
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.autoAnalyzeAfterImport,
                'app_settings',
                'auto_analyze_after_import');
            await _addColumnIfMissing(
                m,
                backupSettings,
                backupSettings.autoBackupMaxMbPerRun,
                'backup_settings',
                'auto_backup_max_mb_per_run');
          }
          if (from < 30) {
            await m.createTable(automationRules);
            await m.createTable(automationRuleTags);
          }
          if (from < 31) {
            await _addColumnIfMissing(
                m, assets, assets.aiTagsScanned, 'assets', 'ai_tags_scanned');
          }
          if (from < 32) {
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.watchedFolderPath,
                'app_settings',
                'watched_folder_path');
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.watchedFolderToken,
                'app_settings',
                'watched_folder_token');
          }
          if (from < 33) {
            // Tonwertkurve und Farbmischer. Beide nullable, `null` = neutral
            // – vorhandene Entwicklungen bleiben dadurch unverändert
            // gültig, es ist nichts nachzutragen.
            await _addColumnIfMissing(
                m,
                developSettings,
                developSettings.toneCurveJson,
                'develop_settings',
                'tone_curve_json');
            await _addColumnIfMissing(
                m,
                developSettings,
                developSettings.colorMixerJson,
                'develop_settings',
                'color_mixer_json');
            await _addColumnIfMissing(
                m,
                developHistory,
                developHistory.toneCurveJson,
                'develop_history',
                'tone_curve_json');
            await _addColumnIfMissing(
                m,
                developHistory,
                developHistory.colorMixerJson,
                'develop_history',
                'color_mixer_json');
          }
          if (from < 34) {
            // Lernende Gesichtserkennung. Ohne Rückmeldungen verhält sich
            // alles wie bisher: Die persönliche Schwelle bleibt null, es
            // gilt die allgemeine.
            await m.createTable(faceMatchFeedback);
            await _addColumnIfMissing(m, people, people.similarityThreshold,
                'people', 'similarity_threshold');
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.faceSimilarityThreshold,
                'app_settings',
                'face_similarity_threshold');
          }
          if (from < 35) {
            // Übersetzung. Beide Schalter stehen auf aus, vorhandene
            // englische Beschreibungen bleiben unangetastet – erst wer die
            // Modelle installiert und den Schalter umlegt, bekommt Deutsch.
            await _addColumnIfMissing(
                m, assets, assets.aiCaptionDe, 'assets', 'ai_caption_de');
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.translateCaptions,
                'app_settings',
                'translate_captions');
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.translateSearchAndTags,
                'app_settings',
                'translate_search_and_tags');
          }
          if (from < 36) {
            // Oberflächensprache. Standard 'system' – für bestehende
            // Installationen ändert sich damit nichts, solange das System
            // auf Deutsch steht.
            await _addColumnIfMissing(
                m, appSettings, appSettings.sprache, 'app_settings', 'sprache');
          }
          if (from < 37) {
            // Export-Voreinstellungen. Eine neue, anfangs leere Tabelle –
            // ohne eine einzige gespeicherte Vorgabe verhält sich der Export
            // wie bisher, die vier festen Grössen bleiben erhalten.
            await m.createTable(exportPresets);
          }
          if (from < 38) {
            // Ignorierte Gesichter. Ein Merkmal an der bestehenden Tabelle,
            // keine eigene: Die Alternative wäre eine Ausschlussliste
            // gewesen, die bei jeder Abfrage mitgejoint werden müsste – für
            // eine Eigenschaft, die genau ein Gesicht betrifft.
            await _addColumnIfMissing(
                m, faces, faces.isIgnored, 'faces', 'is_ignored');
            // Erst nach der Spalte – ein Index auf eine noch nicht
            // existierende Spalte scheitert.
            await _createPerformanceIndices(m);
          }
          if (from < 39) {
            // Klarheit, Vignettierung und importierte Farbtabellen – in
            // beiden Tabellen, damit der Verlauf nichts fallen lässt.
            // Ausgeschrieben statt in einer Schleife: Über beide Tabellen zu
            // laufen verliert deren konkreten Typ und damit die Spalten.
            await _addColumnIfMissing(m, developSettings,
                developSettings.clarity, 'develop_settings', 'clarity');
            await _addColumnIfMissing(m, developSettings,
                developSettings.vignette, 'develop_settings', 'vignette');
            await _addColumnIfMissing(m, developSettings,
                developSettings.lutPath, 'develop_settings', 'lut_path');
            await _addColumnIfMissing(
                m,
                developSettings,
                developSettings.lutStrength,
                'develop_settings',
                'lut_strength');
            await _addColumnIfMissing(m, developHistory, developHistory.clarity,
                'develop_history', 'clarity');
            await _addColumnIfMissing(m, developHistory,
                developHistory.vignette, 'develop_history', 'vignette');
            await _addColumnIfMissing(m, developHistory, developHistory.lutPath,
                'develop_history', 'lut_path');
            await _addColumnIfMissing(m, developHistory,
                developHistory.lutStrength, 'develop_history', 'lut_strength');
          }
          if (from < 40) {
            // Stammbaum: Verwandtschaften und Lebensdaten. Beides ist rein
            // additiv – eine leere Beziehungstabelle und zwei leere Spalten
            // verhalten sich wie zuvor, der Stammbaum einer Person ohne
            // Einträge ist schlicht leer.
            await m.createTable(personBeziehungen);
            await _addColumnIfMissing(
                m, people, people.geburtsdatum, 'people', 'geburtsdatum');
            await _addColumnIfMissing(
                m, people, people.sterbedatum, 'people', 'sterbedatum');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_beziehung_andere ON person_beziehungen (andere_id)');
          }
          if (from < 41) {
            // Geschlecht, nur für die Verwandtschaftsbezeichnungen. Leer
            // bedeutet „nicht angegeben" – der Stammbaum zeigt dann die
            // geschlechtsneutrale Form.
            await _addColumnIfMissing(
                m, people, people.geschlecht, 'people', 'geschlecht');
          }
          if (from < 42) {
            // Lebensereignisse. Eine neue, anfangs leere Tabelle – ohne
            // einen einzigen Eintrag verhält sich alles wie zuvor.
            await m.createTable(lebensereignisse);
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_ereignis_person '
                'ON lebensereignisse (person_id)');
          }
          if (from < 43) {
            // Belichtungskorrektur und Kleinbild-Brennweite. Beide bleiben
            // für bestehende Fotos leer, bis „Kameradaten einlesen" läuft –
            // die Info-Ansicht lässt eine fehlende Angabe einfach weg.
            await _addColumnIfMissing(
                m, assets, assets.exposureBiasEv, 'assets', 'exposure_bias_ev');
            await _addColumnIfMissing(m, assets, assets.focalLength35mm,
                'assets', 'focal_length35mm');
          }
          if (from < 44) {
            // Merkmal für eine von Hand geänderte Bildunterschrift. Für
            // bestehende Fotos falsch – vorher liess sie sich gar nicht
            // ändern.
            await _addColumnIfMissing(m, assets, assets.aiCaptionEdited,
                'assets', 'ai_caption_edited');
          }
          if (from < 45) {
            // Ausnahmen der Duplikatsuche. Neue, anfangs leere Tabelle –
            // ohne einen einzigen Eintrag verhält sich die Suche wie zuvor.
            await m.createTable(duplikatAusnahmen);
          }
          if (from < 46) {
            // Der Lichter-Regler. Vorgabe 0 heisst neutral: Jede bereits
            // gespeicherte Entwicklung sieht nach der Migration genauso
            // aus wie davor – niemand findet sein Bild verändert vor.
            await _addColumnIfMissing(m, developSettings,
                developSettings.highlights, 'develop_settings', 'highlights');
            await _addColumnIfMissing(m, developMasks, developMasks.highlights,
                'develop_masks', 'highlights');
            await _addColumnIfMissing(m, developHistory,
                developHistory.highlights, 'develop_history', 'highlights');
          }
          if (from < 47) {
            // Benannte Entwicklungs-Vorgaben. Neue, anfangs leere Tabelle –
            // ohne einen einzigen Eintrag verhält sich alles wie zuvor.
            await m.createTable(developPresets);
          }
          if (from < 48) {
            // Dateiformat als eigene, indexierte Spalte – Suche nach
            // „nur DNG" ohne Tabellen-Scan.
            await _addColumnIfMissing(
                m, assets, assets.dateiformat, 'assets', 'dateiformat');
            await _trageDateiformateNach();
            await _createIndicesV48(m);
          }
          if (from < 49) {
            // Die zuletzt gewählte Kartenansicht überdauert jetzt das
            // Schliessen des Bildschirms.
            await _addColumnIfMissing(m, appSettings, appSettings.kartenansicht,
                'app_settings', 'kartenansicht');
          }
          if (from < 50) {
            // Lebensereignisse bekommen eine Koordinate zum Ortsnamen.
            // Beide Spalten leer: Das Nachtragen läuft nicht hier,
            // sondern beim ersten Start mit geladenem GeoNames-Auszug
            // (siehe LibraryState.trageEreignisorteNach) – ohne den
            // Datensatz gäbe es nichts einzutragen, und eine Migration,
            // die auf einen optionalen Download wartet, wäre eine
            // Migration, die manchmal nicht fertig wird.
            await _addColumnIfMissing(m, lebensereignisse,
                lebensereignisse.ortBreite, 'lebensereignisse', 'ort_breite');
            await _addColumnIfMissing(m, lebensereignisse,
                lebensereignisse.ortLaenge, 'lebensereignisse', 'ort_laenge');
          }
          if (from < 51) {
            // Reisen. Drei neue, anfangs leere Tabellen – ohne einen
            // einzigen Eintrag verhält sich alles wie zuvor.
            await m.createTable(reisen);
            await m.createTable(reiseAufnahmen);
            await m.createTable(verworfeneReisen);
            await _createIndicesV51(m);
          }
          if (from < 52) {
            // Selbst gesetzte Ortsmarken. Neue, anfangs leere Tabelle –
            // solange niemand einen Haken setzt, zählt die Weltkarte
            // genau wie vorher nur die Fotos.
            await m.createTable(ortsmarken);
          }
          if (from < 53) {
            // Die Startzeit der KI-Restaurierung. Ohne sie liess sich
            // keine ehrliche Restzeit rechnen; laufende Auftraege gibt
            // es beim Start ohnehin keine (siehe
            // resetStuckRunningRestoreJobs), die Spalte darf also leer
            // beginnen.
            await _addColumnIfMissing(m, restoreJobs, restoreJobs.startedAt,
                'restore_jobs', 'started_at');
          }
          if (from < 54) {
            // Aktivitäten. Drei neue, anfangs leere Tabellen – ohne
            // einen einzigen Eintrag verhält sich alles wie zuvor.
            await m.createTable(aktivitaeten);
            await m.createTable(aktivitaetAufnahmen);
            await m.createTable(verworfeneAktivitaeten);
            await _createIndicesV54(m);
          }
          if (from < 55) {
            // Aufgezeichnete Spuren. Zwei neue, anfangs leere Tabellen –
            // ohne einen einzigen Eintrag verhält sich alles wie zuvor.
            await m.createTable(spuren);
            await m.createTable(spurpunkte);
            await _createIndicesV55(m);
          }
          if (from < 56) {
            // Woher ein Schlagwort stammt (siehe [Tagquelle]).
            await _addColumnIfMissing(
                m, assetTags, assetTags.quelle, 'asset_tags', 'quelle');
            await _bestimmeTagquelleNachtraeglich();
          }
          if (from < 57) {
            // Von der Gesichtssuche ausgenommen (siehe die Spalte).
            await _addColumnIfMissing(m, assets, assets.faceScanExcluded,
                'assets', 'face_scan_excluded');
          }
          if (from < 58) {
            // Der eigene CARTO-Schlüssel (siehe die Spalte). Null heisst
            // „keiner" und damit invertierte OSM-Kacheln – die dunkle
            // Karte funktioniert also ohne jedes Zutun weiter, nur ohne
            // das Wasserzeichen.
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.cartoSchluessel,
                'app_settings',
                'carto_schluessel');
          }
          if (from < 59) {
            // Wie viele schwere Aufgaben nebeneinander laufen dürfen
            // (siehe die Spalte). Vorgabe eins = das bisherige Verhalten.
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.maxGleichzeitig,
                'app_settings',
                'max_gleichzeitig');
          }
          if (from < 60) {
            // Wo der erkannte Text im Bild steht (siehe die Spalte). Leer
            // fuer alles Bisherige; die Texterkennung holt es nach.
            await _addColumnIfMissing(
                m, assets, assets.ocrBoxen, 'assets', 'ocr_boxen');
          }
          if (from < 61) {
            // Schaerfe des Gesichtsausschnitts (siehe die Spalte). Leer
            // fuer alles Bisherige; der Nachlauf holt es aus den bereits
            // gespeicherten Ausschnitten, ohne ein Foto neu zu dekodieren.
            await _addColumnIfMissing(
                m, faces, faces.schaerfe, 'faces', 'schaerfe');
          }
          if (from < 62) {
            // Abgelehnte Serienvorschlaege – bis hierher verschwand ein
            // „nein" mit dem Schliessen des Bildschirms.
            await m.createTable(verworfeneSerien);
          }
          if (from < 63) {
            // Die alten Augenwerte entstanden mit falscher Normierung und
            // sagten „geschlossen" zu offenen Augen. `null` heisst laut
            // Spaltendoku „noch nicht berechnet" – das ist die ehrliche
            // Auskunft, bis ein Gesichtsdurchlauf sie neu ermittelt.
            await m.database
                .customStatement('UPDATE faces SET eye_open_score = NULL');
          }
          if (from < 64) {
            // „Schon nachgesehen" beim Ortsnachtrag (siehe die Spalte).
            // `false` fuer alles Bestehende ist Absicht: Der erste Lauf
            // nach dem Umstieg geht noch einmal ueber alles – und findet
            // dabei die Videos, an die er vorher nie herankam.
            await _addColumnIfMissing(
                m, assets, assets.gpsGeprueft, 'assets', 'gps_geprueft');
          }
          if (from < 65) {
            // Zuordnungen, die auf die VIDEOHÄLFTE eines Live Photos
            // zeigen, auf das Foto umbiegen.
            //
            // Wie es dazu kam: Die Reise-/Aktivitätserkennung sah bis
            // hierher auch die Videohälften, weil ihr die Einschränkung
            // fehlte, die überall sonst gilt (siehe
            // [aufnahmenFuerReiseerkennung]). Was daraus entstand, hing
            // davon ab, welche Hälfte gerade Datum und Ort trug – und die
            // wurden beim Videodatum (Fassung 64) und beim CR3-Nachtrag
            // nachträglich berichtigt.
            //
            // An der gewachsenen Bibliothek: 19 Zuordnungen zeigten auf
            // eine Videohälfte, nur 5 der zugehörigen Fotos waren
            // ebenfalls zugeordnet. Zwei Aktivitäten – „Gifhorn -
            // Mühlenmuseum" und „Eiluhmer Horn" – bestanden damit aus
            // sieben Videoschnipseln und keinem einzigen Foto.
            //
            // `insertOrIgnore`, dann löschen: Ist das Foto schon drin,
            // bleibt es bei ihm, und die Videozeile fällt trotzdem weg.
            // Andersherum stünde beides da und jedes Live Photo zählte
            // doppelt.
            for (final tabelle in ['aktivitaet_aufnahmen', 'reise_aufnahmen']) {
              final spalte = tabelle == 'aktivitaet_aufnahmen'
                  ? 'aktivitaet_id'
                  : 'reise_id';
              await m.database.customStatement('''
                INSERT OR IGNORE INTO $tabelle ($spalte, asset_id)
                SELECT z.$spalte, a.linked_asset_id
                FROM $tabelle z JOIN assets a ON a.id = z.asset_id
                WHERE a.type != 'IMAGE' AND a.linked_asset_id IS NOT NULL
              ''');
              await m.database.customStatement('''
                DELETE FROM $tabelle WHERE asset_id IN (
                  SELECT id FROM assets
                  WHERE type != 'IMAGE' AND linked_asset_id IS NOT NULL
                )
              ''');
            }
          }
          if (from < 66) {
            // Die eigene Kartenquelle (siehe die Spalten). Alles leer und
            // nicht zugestimmt = genau das bisherige Verhalten: Der
            // Eintrag taucht im Kartenmenue erst auf, wenn er ausgefuellt
            // ist.
            for (final spalte in [
              appSettings.eigeneKarteName,
              appSettings.eigeneKarteUrl,
              appSettings.eigeneKarteNennung,
              appSettings.eigeneKarteStufe,
              appSettings.eigeneKarteZugestimmt,
            ]) {
              await _addColumnIfMissing(
                  m, appSettings, spalte, 'app_settings', spalte.name);
            }
          }
          if (from < 67) {
            // Vorgabe true = genau das bisherige Verhalten.
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.karteHochaufloesend,
                'app_settings',
                'karte_hochaufloesend');
          }
          if (from < 68) {
            // Beides leer = genau das bisherige Verhalten: Der Baum
            // beginnt bei der Person mit den meisten Verwandten.
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.stammbaumAnsicht,
                'app_settings',
                'stammbaum_ansicht');
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.stammbaumPerson,
                'app_settings',
                'stammbaum_person');
            // Die mittlere Stufe ist genau die Groesse, die es vorher
            // als einzige gab.
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.zeitleisteKachelstufe,
                'app_settings',
                'zeitleiste_kachelstufe');
            await _addColumnIfMissing(m, appSettings, appSettings.listenspalten,
                'app_settings', 'listenspalten');
          }
          if (from < 69) {
            // Vorgabe = Quadrate, also genau das bisherige Bild. Wer
            // nichts umstellt, merkt von der zweiten Form nichts.
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.zeitleisteFormNr,
                'app_settings',
                'zeitleiste_form_nr');
          }
          if (from < 70) {
            // Vorgabe an. Die Spalte ist neu, also hat noch niemand eine
            // Wahl getroffen - und wer die Bewegung nicht will, findet
            // den Schalter in den Einstellungen.
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.schwebeVorschau,
                'app_settings',
                'schwebe_vorschau');
          }
          if (from < 71) {
            // Vorgabe Mittag - genau die Beleuchtung, die es vorher als
            // einzige gab.
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.gelaendeStimmungNr,
                'app_settings',
                'gelaende_stimmung_nr');
          }
          if (from < 72) {
            // Die Wanderobjekte aus OpenStreetMap und die Liste der
            // schon erfragten Ausschnitte.
            await m.createTable(wanderpunkte);
            await m.createTable(wanderabfragen);
            // Die vier Spalten der Geländeauflage. Die Vorgaben stehen
            // bei den Spalten selbst; sie aendern das Bild sichtbar, und
            // das ist Absicht (siehe [AppSettings.gelaendeGrundNr]).
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.gelaendeGrundNr,
                'app_settings',
                'gelaende_grund_nr');
            await _addColumnIfMissing(m, appSettings, appSettings.gelaendeWege,
                'app_settings', 'gelaende_wege');
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.gelaendeBeschriftung,
                'app_settings',
                'gelaende_beschriftung');
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.gelaendeHoehenlinien,
                'app_settings',
                'gelaende_hoehenlinien');
          }
          if (from < 73) {
            // Der Schalter fuer die Schilder. Vorgabe an - sie sind der
            // Grund, warum die Landschaft mehr sagt als eine Karte.
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.gelaendeWanderobjekte,
                'app_settings',
                'gelaende_wanderobjekte');
          }
          if (from < 74) {
            // Eine Spur darf jetzt auch an einer Reise haengen. Die
            // Spalte bleibt bei allen vorhandenen Spuren leer - die
            // gehoeren zu Aktivitaeten.
            await _addColumnIfMissing(
                m, spuren, spuren.reiseId, 'spuren', 'reise_id');
          }
          if (from < 75) {
            // Woher der Aufnahmezeitpunkt stammt (siehe die beiden
            // Spalten). BEIDE `false` fuer alles Bestehende, und das ist
            // die vorsichtige Wahl:
            //
            // Es waere verlockend, hier gleich `datum_geschaetzt` fuer
            // alles zu setzen, was auf einer vollen Stunde liegt - an der
            // echten Bibliothek traefe das 1097 Aufnahmen und damit fast
            // genau die richtigen. Aber eben nur fast: Ein Foto, das
            // wirklich um Punkt 18 Uhr entstand, bekaeme eine Marke, die
            // eine Falschaussage waere. Statt einer Vermutung ueber alle
            // laeuft der Nachtrag einmal ueber die Bibliothek und sieht
            // in JEDER Datei nach, ob ein Aufnahmedatum darin steht.
            await _addColumnIfMissing(m, assets, assets.datumGeschaetzt,
                'assets', 'datum_geschaetzt');
            await _addColumnIfMissing(
                m, assets, assets.datumGeprueft, 'assets', 'datum_geprueft');
          }
          if (from < 76) {
            // Ein geerbter Ort ist kein gemessener (siehe die Spalte),
            // und abgelehnte Vorschlaege sollen abgelehnt bleiben -
            // dieselbe Machart wie bei Reisen, Aktivitaeten und Serien.
            await _addColumnIfMissing(
                m, assets, assets.ortGeerbt, 'assets', 'ort_geerbt');
            await m.createTable(verworfeneOrtsvorschlaege);
          }
          if (from < 77) {
            // Ein Video war bis hierher ein einziges Standbild (siehe
            // die Spalte und die Tabelle). `false` fuer alles
            // Bestehende: Der Nachtrag sieht sich jedes Video einmal an.
            await _addColumnIfMissing(m, assets, assets.videobilderGeprueft,
                'assets', 'videobilder_geprueft');
            await m.createTable(videoeinbettungen);
          }
          if (from < 78) {
            // Der Zeitzonenversatz aus der Datei (siehe die Spalte). Er
            // wird vom selben Nachtrag mitgelesen, der nach der Herkunft
            // des Datums sieht - die Datei ist dann ohnehin offen.
            await _addColumnIfMissing(m, assets, assets.zeitversatzMinuten,
                'assets', 'zeitversatz_minuten');
          }
          if (from < 79) {
            // Vorgabe = neueste Aufnahme oben, also genau die
            // Reihenfolge, die es vorher als einzige gab. Wer nichts
            // umstellt, merkt von der Wahl nichts.
            await _addColumnIfMissing(
                m,
                appSettings,
                appSettings.zeitleisteSortierungNr,
                'app_settings',
                'zeitleiste_sortierung_nr');
          }
          if (from < 80) {
            // Neue Tabelle, also nichts umzuschreiben: Wer nichts
            // schreibt, hat keine Tagesnotizen, und die Ansicht sieht
            // aus wie bisher.
            await m.createTable(reisetagnotizen);
          }
          if (from < 81) {
            // Jede bestehende Reise wird über den Vorgabewert eine
            // „Reise" – was sie bisher der Sache nach war. Wer eine als
            // Einsatz oder Dienstreise führen will, sagt es danach.
            await _addColumnIfMissing(m, reisen, reisen.art, 'reisen', 'art');
          }
          if (from < 82) {
            await _createAssetSearchFts();
          }
          if (from < 83) {
            await _addColumnIfMissing(
                m,
                privacySettings,
                privacySettings.protectMetadata,
                'privacy_settings',
                'protect_metadata');
          }
          if (from < 84) {
            // Der Auslöser bekommt eine Bedingung (siehe
            // [_createAssetSearchFts]). `CREATE TRIGGER IF NOT EXISTS`
            // liesse den alten stehen – er muss weg, bevor der neue kommt.
            await customStatement('DROP TRIGGER IF EXISTS assets_fts_update');
            await _createAssetSearchTriggers();
          }
          if (from < 85) {
            // Drei neue Spalten, alle leer: Vor dem ersten Lauf gibt es
            // keine Vorschlaege, und genau so sieht die App danach aus.
            for (final (spalte, name) in [
              (faces.vorschlagPersonId, 'vorschlag_person_id'),
              (faces.vorschlagWert, 'vorschlag_wert'),
              (faces.vorschlagGeprueftAm, 'vorschlag_geprueft_am'),
            ]) {
              await _addColumnIfMissing(m, faces, spalte, 'faces', name);
            }
          }
        },
      );

  /// Füllt [Assets.dateiformat] für den Bestand aus dem Dateinamen.
  ///
  /// **Eine einzige Anweisung, nicht ein Aufruf je Foto.** Bei 8.000
  /// Fotos wäre der Unterschied noch zu verschmerzen; bei 100.000 wäre es
  /// eine Migration, bei der man denkt, die App sei hängen geblieben.
  ///
  /// Die Endung ist alles hinter dem LETZTEN Punkt – `rindex` statt
  /// `instr`. Ein Dateiname wie `Urlaub.2019.jpg` hat zwei Punkte, und
  /// `2019.jpg` wäre kein Format.
  ///
  /// Namen ohne Punkt bleiben `NULL`: Sie haben kein Format, und das ist
  /// etwas anderes als ein unbekanntes.
  Future<void> _trageDateiformateNach() => customStatement(
        'UPDATE assets SET dateiformat = nullif(lower(substr('
        '  original_file_name,'
        '  length(rtrim(original_file_name,'
        "    replace(original_file_name, '.', ''))) + 1)), '') "
        'WHERE dateiformat IS NULL '
        "  AND instr(original_file_name, '.') > 0",
      );

  /// Index für den Formatfilter. Teilindex: Fotos ohne Format sind der
  /// seltene Fall und werden nie gesucht.
  Future<void> _createIndicesV48(Migrator m) => customStatement(
        'CREATE INDEX IF NOT EXISTS idx_assets_dateiformat '
        'ON assets (dateiformat) WHERE dateiformat IS NOT NULL',
      );

  /// Legt [spalte] nur an, wenn sie in [tabellenName] noch fehlt.
  ///
  /// Bestimmt für vorhandene Zuordnungen nachträglich die Herkunft.
  ///
  /// **Das ist eine Vermutung, und sie muss eine bleiben.** Bis Fassung 56
  /// stand nirgends, wer ein Schlagwort vergeben hat; rückwirkend lässt es
  /// sich nur erschliessen. Die Regel ist bewusst eng:
  ///
  /// Als `ki` gilt eine Zuordnung nur, wenn **beides** zutrifft – der
  /// Begriff steht im Vokabular der Bilderkennung, **und** das Foto ist
  /// nachweislich durch die Verschlagwortung gelaufen (`ai_tags_scanned`).
  /// Nur solche Zeilen kann die Bilderkennung überhaupt erzeugt haben.
  ///
  /// **Was schiefgehen kann, und was es kostet:** Wer selbst „Strand" an
  /// ein Foto geschrieben hat, das später durch die Verschlagwortung lief,
  /// bekommt seine Zuordnung als `ki` gestempelt. Beim Sperren dieses Fotos
  /// verschwindet sie dann – und kommt beim Entsperren zurück, sofern die
  /// Bilderkennung sie erneut vorschlägt. Der Schaden trifft also nur, wer
  /// ein Foto sperrt, und auch dort nur einen Begriff, den das Programm
  /// ohnehin für passend hält.
  ///
  /// Andersherum wäre der Schaden dauerhaft: Alles auf `hand` zu stempeln
  /// hiesse, dass in jeder gewachsenen Bibliothek genau die Schlagwörter
  /// weiter im Klartext stehen, deretwegen diese Spalte angelegt wurde.
  Future<void> _bestimmeTagquelleNachtraeglich() => customUpdate(
        'UPDATE asset_tags SET quelle = ? '
        'WHERE tag_id IN (SELECT t.id FROM tags t '
        '                 JOIN ai_tag_vocabulary v ON v.term = t.name) '
        '  AND asset_id IN (SELECT a.id FROM assets a '
        '                   WHERE a.ai_tags_scanned = 1)',
        variables: const [Variable<String>(Tagquelle.ki)],
        updates: {assetTags},
      );

  /// Schützt gegen den Fall, dass eine Datenbank bereits auf eine
  /// Schemaversion gestempelt wurde, deren Migration die Spalte gar nicht
  /// angelegt hat – dann würde ein blindes addColumn beim Nachholen mit
  /// "duplicate column" scheitern und der Start bräche ab.
  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo table,
    GeneratedColumn spalte,
    String tabellenName,
    String spaltenName,
  ) async {
    final vorhanden =
        await customSelect('PRAGMA table_info($tabellenName)').get();
    final namen = vorhanden.map((r) => r.data['name'] as String).toSet();
    if (namen.contains(spaltenName)) return;
    await m.addColumn(table, spalte);
  }

  /// Öffnet (bzw. legt beim ersten Start an) die lokale SQLite-Datei im
  /// App-Support-Verzeichnis des Betriebssystems.
  static Future<AppDatabase> open() async {
    final libraryRoot = await LibraryLocation.currentRoot();
    await libraryRoot.create(recursive: true);
    final dbFile = File(p.join(libraryRoot.path, 'library.sqlite'));
    return AppDatabase(mitSperrwartezeit(NativeDatabase.createInBackground(
        dbFile,
        setup: bereiteVerbindungVor)));
  }

  /// Ergänzt SQLites native Wartezeit um Wiederholungen für Plattformen, auf
  /// denen der gebündelte Treiber `busy_timeout` bei einzelnen Sperrarten
  /// vorzeitig mit `SQLITE_BUSY` oder `SQLITE_LOCKED` beendet.
  static QueryExecutor mitSperrwartezeit(QueryExecutor executor) =>
      executor.interceptWith(_SperrWiederholung());

  /// Wie lange auf eine belegte Datenbank gewartet wird, bevor
  /// aufgegeben wird.
  ///
  /// **SQLites Vorgabe ist null** – wer auf eine gesperrte Datei trifft,
  /// bekommt sofort „database is locked" und keinen zweiten Versuch. Das
  /// ist so lange folgenlos, wie genau ein Prozess die Datei anfasst, und
  /// genau das ist nicht zugesichert: Nichts in diesem Programm hindert
  /// jemanden daran, es zweimal zu starten (auf dem Windows-Prüfrechner
  /// liefen zwei Fassungen stundenlang nebeneinander), und ein
  /// Sicherungsdienst, ein Synchronisationsordner oder ein Blick mit dem
  /// `sqlite3`-Werkzeug halten die Sperre ebenfalls kurz.
  ///
  /// Gemessen an zwei Prozessen, die gleichzeitig 400 Zeilen schreiben:
  ///
  /// ```
  /// ohne Wartezeit    734 von 800 Schreibvorgängen scheitern
  /// 5 Sekunden          0 von 800, zusammen 170 ms
  /// ```
  ///
  /// Fünf Sekunden sind lang genug für jede Schreibfolge, die dieses
  /// Programm kennt, und kurz genug, dass eine wirklich klemmende
  /// Datenbank nicht als Aufhänger erscheint.
  static const int sperrwartezeitMs = 5000;

  /// Was an jeder frisch geöffneten Verbindung eingestellt gehört.
  ///
  /// Öffentlich, damit die Prüfstände dieselbe Einstellung bekommen wie
  /// der Betrieb – eine Einstellung, die nur im Betrieb gilt, ist eine,
  /// die nie geprüft wird.
  static void bereiteVerbindungVor(Database db) {
    db.execute('PRAGMA busy_timeout = $sperrwartezeitMs');
  }

  // -----------------------------------------------------------------------
  // Assets / Timeline
  // -----------------------------------------------------------------------

  Future<void> insertAsset(AssetsCompanion asset) => into(assets).insert(asset);

  Future<AssetData?> assetById(String id) =>
      (select(assets)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<AssetData>> assetsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await (select(assets)..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final r in rows) r.id: r};
    // Reihenfolge der übergebenen IDs beibehalten (z.B. Ranking nach Ähnlichkeit).
    return ids.map((id) => byId[id]).whereType<AssetData>().toList();
  }

  /// Prüft anhand der Prüfsumme, ob eine Datei bereits importiert wurde
  /// (Duplikaterkennung beim Import).
  Future<bool> checksumExists(String checksum) async {
    final row = await (select(assets)
          ..where((t) => t.checksum.equals(checksum)))
        .getSingleOrNull();
    return row != null;
  }

  /// "Eigenständig sichtbar" in Timeline/Kalender/Karte/Alben/Suche & Co.:
  /// weder das Video-Gegenstück eines Live-Photo-Paares (bleibt nur über das
  /// verknüpfte Foto sichtbar, siehe LivePhotoView) noch ein
  /// nicht-Titelbild-Mitglied eines Serien-Stapels (siehe createStack) –
  /// exakt dasselbe OR-Muster wie beim Live-Photo-Verstecken, nur einmal
  /// formuliert statt an jeder der rund ein Dutzend Fundstellen wiederholt.
  Expression<bool> _isPrimaryGridEntry($AssetsTable t) =>
      (t.type.equals('IMAGE') | t.linkedAssetId.isNull()) &
      (t.stackId.isNull() | t.isStackCover.equals(true));

  // ---------------------------------------------------------------------
  // Datenströme, die einen Schwall aushalten
  // ---------------------------------------------------------------------

  /// Wie viel Zeit zwischen zwei Durchläufen derselben Abfrage mindestens
  /// liegt, wenn die Änderungen nicht aufhören.
  ///
  /// Nicht kürzer, weil sonst wenig gespart wäre; nicht länger, weil ein
  /// Hintergrundlauf sonst zu lange ein veraltetes Raster stehen liesse.
  @visibleForTesting
  static const drosselfenster = Duration(milliseconds: 400);

  /// Ein Datenstrom auf [bauen], der bei einem **Schwall** von Änderungen
  /// nicht jede einzelne nachrechnet.
  ///
  /// **Warum es das braucht.** Drift lässt eine `watch`-Abfrage bei jeder
  /// Änderung an einer beteiligten Tabelle neu laufen. Das ist richtig,
  /// solange Änderungen einzeln kommen — die Hintergrundaufgaben schreiben
  /// aber Zeile für Zeile, tausendfach hintereinander. An der gewachsenen
  /// Bibliothek gemessen, 200 einzelne Schreibvorgänge:
  ///
  /// ```
  /// ohne offene Zeitleiste                    0,5 s
  /// Zeitleiste offen, Ladefenster 600         3,7 s
  /// Zeitleiste offen, ganze Bibliothek       41,9 s
  /// ```
  ///
  /// Über 8000 Aufnahmen wären das aus einer halben Minute Schreibarbeit
  /// fast eine halbe Stunde — und die fällt im selben Faden an, in dem
  /// gezeichnet wird. Was da so teuer ist, sind nicht die Schreibvorgänge,
  /// sondern die 101 Neudurchläufe, die sie auslösen.
  ///
  /// **Die erste Antwort kommt trotzdem sofort.** Gedrosselt wird nur, was
  /// innerhalb von [drosselfenster] auf einen frischen Durchlauf folgt. Ein
  /// einzelner Handgriff — ein Herz gesetzt, ein Foto in den Papierkorb —
  /// wirkt also unverändert augenblicklich; erst der zweite Schreibvorgang
  /// in derselben Zehntelsekunde wartet. Eine Drosselung, die auch den
  /// ersten verzögerte, wäre an jeder einzelnen Stelle der Oberfläche zu
  /// spüren und hier nirgends nötig.
  Stream<List<D>> _gedrosselt<D>(
    Selectable<D> Function() bauen,
    TableUpdateQuery worauf, {
    Duration fenster = drosselfenster,
  }) {
    late StreamController<List<D>> regler;
    StreamSubscription<void>? horcher;
    Timer? nachzuegler;
    var laeuft = false;
    var nochmal = false;
    DateTime? zuletzt;

    Future<void> frage() async {
      // Läuft schon eine Abfrage, wird die nächste einmal nachgeholt – aber
      // nur einmal. Ohne diese Klammer stapelten sich bei langsamen
      // Abfragen die Durchläufe genau dann, wenn es ohnehin eng ist.
      if (laeuft) {
        nochmal = true;
        return;
      }
      laeuft = true;
      zuletzt = DateTime.now();
      try {
        final zeilen = await bauen().get();
        if (!regler.isClosed) regler.add(zeilen);
      } catch (e, spur) {
        if (!regler.isClosed) regler.addError(e, spur);
      } finally {
        laeuft = false;
        if (nochmal) {
          nochmal = false;
          unawaited(frage());
        }
      }
    }

    void gemeldet() {
      // Ein Nachzügler ist schon bestellt – der holt alles mit ab.
      if (nachzuegler != null) return;
      final seit =
          zuletzt == null ? fenster : DateTime.now().difference(zuletzt!);
      if (seit >= fenster) {
        unawaited(frage());
      } else {
        nachzuegler = Timer(fenster - seit, () {
          nachzuegler = null;
          unawaited(frage());
        });
      }
    }

    regler = StreamController<List<D>>.broadcast(
      onListen: () {
        unawaited(frage());
        horcher = tableUpdates(worauf).listen((_) => gemeldet());
      },
      onCancel: () {
        nachzuegler?.cancel();
        nachzuegler = null;
        unawaited(horcher?.cancel());
        horcher = null;
      },
    );
    return regler.stream;
  }

  /// [limit] begrenzt auf die neuesten [limit] Fotos/Videos (per
  /// `idx_assets_trashed_locked_created` indexgestützt, also auch bei sehr
  /// großen Bibliotheken ein günstiger Index-Walk statt eines vollständigen
  /// Tabellen-Scans). Ohne [limit] wird – wie bisher – die komplette
  /// Zeitleiste geliefert; TimelineScreen nutzt [limit] für ein wachsendes
  /// Ladefenster (siehe dort), damit weder bei jeder Mutation noch beim
  /// ersten Öffnen zwingend die GESAMTE Bibliothek aus der DB geladen und in
  /// Dart neu gruppiert werden muss.
  Stream<List<AssetData>> watchTimeline(
      {bool favoritesOnly = false,
      int? limit,
      Rastersortierung sortierung = rastersortierungVorgabe}) {
    final query = select(assets)
      ..where((t) =>
          t.isTrashed.equals(false) &
          t.isLocked.equals(false) &
          _isPrimaryGridEntry(t));
    if (favoritesOnly) {
      query.where((t) => t.isFavorite.equals(true));
    }
    query.orderBy(_sortierterme(sortierung));
    if (limit != null) {
      query.limit(limit);
    }
    return _gedrosselt(() => query, TableUpdateQuery.onTable(assets));
  }

  /// [sortierungSql] als Abfragebauer-Fassung – fuer die Abfragen, die
  /// nicht als rohes SQL dastehen.
  ///
  /// Zwei Fassungen derselben Reihenfolge sind zwei Regeln, die
  /// auseinanderlaufen koennen; `sortierung_test.dart` haelt sie
  /// zusammen, indem es die erzeugte Abfrage gegen [sortierungSql]
  /// stellt.
  List<OrderingTerm Function($AssetsTable)> _sortierterme(Rastersortierung s) =>
      switch (s) {
        Rastersortierung.aufnahmeNeu => [
            (t) => OrderingTerm.desc(t.fileCreatedAt)
          ],
        Rastersortierung.aufnahmeAlt => [
            (t) => OrderingTerm.asc(t.fileCreatedAt)
          ],
        Rastersortierung.importNeu => [
            (t) => OrderingTerm.desc(t.importedAt),
            (t) => OrderingTerm.desc(t.fileCreatedAt),
          ],
        Rastersortierung.name => [
            (t) => OrderingTerm.asc(t.originalFileName.collate(Collate.noCase)),
            (t) => OrderingTerm.desc(t.fileCreatedAt),
          ],
        Rastersortierung.bewertung => [
            (t) => OrderingTerm.desc(t.rating),
            (t) => OrderingTerm.desc(t.fileCreatedAt),
          ],
        Rastersortierung.groesse => [
            (t) => OrderingTerm.desc(t.fileSizeBytes),
            (t) => OrderingTerm.desc(t.fileCreatedAt),
          ],
      };

  /// Dieselbe Auswahl wie [watchTimeline], aber **nur die Spalten, die
  /// ein Raster anfasst** – siehe [Rasterzeile] für die Messung.
  ///
  /// Als rohes SQL und nicht über den Abfragebauer: Der liefert immer
  /// die ganze Zeile samt Abbildung auf `AssetData`, und genau die
  /// beiden Posten sollen hier wegfallen. `readsFrom` sorgt dafür, dass
  /// der Strom trotzdem meldet, wenn sich an `assets` etwas ändert.
  Stream<List<Rasterzeile>> watchRasterzeilen(
      {bool favoritesOnly = false,
      int? limit,
      Rastersortierung sortierung = rastersortierungVorgabe}) {
    final wo = StringBuffer(rasterSichtbar);
    if (favoritesOnly) wo.write(' AND is_favorite = 1');
    final grenze = limit == null ? '' : ' LIMIT $limit';
    return _gedrosselt(
      () => customSelect(
        'SELECT $rasterSpalten FROM assets WHERE $wo '
        'ORDER BY ${sortierungSql(sortierung)}$grenze',
        readsFrom: {assets},
      ).map(Rasterzeile.ausZeile),
      TableUpdateQuery.onTable(assets),
    );
  }

  /// Dieselbe Liste wie [watchTimeline], aber einmalig statt als Strom.
  ///
  /// Für Ansichten, die eine Auswahl treffen und danach fertig sind
  /// (siehe `AufnahmenWaehlenScreen`). Ein Strom wäre dort nicht nur
  /// unnötig, sondern lästig: Er hinterlässt beim Abbauen einen
  /// Zeitgeber, und die Liste unter der Hand zu ändern, während jemand
  /// Häkchen setzt, wäre ohnehin das Gegenteil von hilfreich.
  /// Dieselbe Menge wie [alleAufnahmen], aber als schmale Rasterzeilen.
  ///
  /// Der Fotowähler zeigt ein Raster und wandelt jede Zeile ohnehin in
  /// eine [Rasterzeile] um – die 56 Spalten davor waren an dieser
  /// Bibliothek 80 ms, die 20 gebrauchten sind 30.
  Future<List<Rasterzeile>> alleRasterzeilen() async => (await customSelect(
          'SELECT $rasterSpalten FROM assets WHERE $rasterSichtbar '
          'ORDER BY file_created_at DESC',
          readsFrom: {assets}).get())
      .map(Rasterzeile.ausZeile)
      .toList();

  Future<List<AssetData>> alleAufnahmen() => (select(assets)
        ..where((t) =>
            t.isTrashed.equals(false) &
            t.isLocked.equals(false) &
            _isPrimaryGridEntry(t))
        ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]))
      .get();

  /// Fotos/Videos genau eines Kalenderjahres – im Gegensatz zu
  /// `watchTimeline()` + Dart-seitigem Filtern (früheres Verhalten von
  /// YearDetailScreen) direkt als indexgestützte SQL-Bereichsabfrage, die bei
  /// großen Bibliotheken nicht erst alle anderen Jahre mitladen muss.
  Stream<List<AssetData>> watchTimelineForYear(int year) {
    final start = DateTime(year);
    final end = DateTime(year + 1);
    final abfrage = select(assets)
      ..where((t) =>
          t.isTrashed.equals(false) &
          t.isLocked.equals(false) &
          _isPrimaryGridEntry(t) &
          t.fileCreatedAt.isBiggerOrEqualValue(start) &
          t.fileCreatedAt.isSmallerThanValue(end))
      ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]);
    return _gedrosselt(() => abfrage, TableUpdateQuery.onTable(assets));
  }

  /// Anzahl Fotos/Videos pro Kalenderjahr für die Jahresübersicht
  /// (CalendarScreen) – eine einzelne aggregierte SQL-Abfrage statt (wie
  /// zuvor) die komplette Zeitleiste zu laden und in Dart pro Jahr zu
  /// zählen. `strftime('%Y', ...)` arbeitet auf demselben, bereits über
  /// `idx_assets_trashed_locked_created` indexierten Filter.
  Stream<Map<int, int>> watchAssetCountsByYear() {
    // 'unixepoch' ist zwingend nötig: drift speichert DateTimeColumn
    // standardmäßig als Unix-Timestamp (Sekunden) statt als ISO8601-Text –
    // ohne den Modifier interpretiert SQLites strftime() die rohe Zahl als
    // Julianisches Datum statt als Unix-Zeit und liefert NULL zurück.
    const yearExpr = CustomExpression<String>(
        "strftime('%Y', file_created_at, 'unixepoch')");
    final query = selectOnly(assets)
      ..addColumns([yearExpr, assets.id.count()])
      ..where(assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          _isPrimaryGridEntry(assets))
      ..groupBy([yearExpr]);
    return query.watch().map((rows) => {
          for (final row in rows)
            int.parse(row.read(yearExpr)!): row.read(assets.id.count())!,
        });
  }

  Future<int> _countWhere(Expression<bool> predicate) async {
    final countExpr = assets.id.count();
    final query = selectOnly(assets)
      ..addColumns([countExpr])
      ..where(predicate);
    final row = await query.getSingle();
    return row.read<int>(countExpr) ?? 0;
  }

  /// Gebündelte Kennzahlen für die Analyseseite (StatisticsScreen) – bewusst
  /// eine einzelne Momentaufnahme (`Future`, kein `Stream`) statt mehrerer
  /// reaktiver Einzel-Queries: die Seite selbst nutzt Pull-to-Refresh statt
  /// Live-Aktualisierung, da bei einer großen Bibliothek sonst nach jeder
  /// Mutation (z.B. Favorit toggeln) sämtliche Aggregate neu berechnet
  /// würden, obwohl sich für die Analyseseite selbst nichts geändert hat.
  Future<LibraryStats> loadLibraryStats() async {
    // Dieselbe Definition von "sichtbares Medium" wie in watchTimeline() &
    // Co.: nicht im Papierkorb, nicht gesperrt, und beim Live-Photo-Paar nur
    // das Foto zählen (das zugehörige Video wird sonst doppelt gezählt).
    final visible = assets.isTrashed.equals(false) &
        assets.isLocked.equals(false) &
        _isPrimaryGridEntry(assets);

    final results = await Future.wait([
      _countWhere(visible & assets.type.equals('IMAGE')),
      _countWhere(visible & assets.type.equals('VIDEO')),
      _countWhere(visible & assets.isFavorite.equals(true)),
      _countWhere(
          assets.isTrashed.equals(true) & assets.isLocked.equals(false)),
      _countWhere(
          assets.isLocked.equals(true) & assets.isTrashed.equals(false)),
      _loadTotalSizeBytes(),
      watchAssetCountsByYear().first,
      _loadCountsByMonth(visible),
      _loadTopCameras(visible),
    ]);

    return LibraryStats(
      imageCount: results[0] as int,
      videoCount: results[1] as int,
      favoriteCount: results[2] as int,
      trashedCount: results[3] as int,
      lockedCount: results[4] as int,
      totalSizeBytes: results[5] as int,
      countsByYear: results[6] as Map<int, int>,
      countsByMonth: results[7] as Map<int, int>,
      topCameras: results[8] as List<CameraStat>,
    );
  }

  /// Tatsächlich belegter Speicherplatz aller nicht gelöschten Dateien –
  /// bewusst OHNE den `visible`-Filter von [loadLibraryStats]: das
  /// zugehörige Video eines Live-Photo-Paares belegt real Speicherplatz auf
  /// der Festplatte, auch wenn es in der UI nicht als eigenes Element
  /// gezählt wird. Gesperrte Assets werden trotzdem ausgeschlossen, damit
  /// die Analyseseite (ohne PIN-Eingabe erreichbar) keine Information über
  /// den Inhalt des gesperrten Ordners preisgibt.
  Future<int> _loadTotalSizeBytes() async {
    final sumExpr = assets.fileSizeBytes.sum();
    final query = selectOnly(assets)
      ..addColumns([sumExpr])
      ..where(assets.isTrashed.equals(false) & assets.isLocked.equals(false));
    final row = await query.getSingle();
    return row.read<int>(sumExpr) ?? 0;
  }

  /// Anzahl Fotos/Videos je Kalendermonat (1-12), über alle Jahre summiert –
  /// zeigt saisonale Muster (z.B. mehr Fotos im Sommer/an Feiertagen).
  Future<Map<int, int>> _loadCountsByMonth(Expression<bool> visible) async {
    const monthExpr = CustomExpression<String>(
        "strftime('%m', file_created_at, 'unixepoch')");
    final countExpr = assets.id.count();
    final query = selectOnly(assets)
      ..addColumns([monthExpr, countExpr])
      ..where(visible)
      ..groupBy([monthExpr]);
    final rows = await query.get();
    return {
      for (final row in rows)
        int.parse(row.read<String>(monthExpr)!): row.read<int>(countExpr) ?? 0,
    };
  }

  /// Die [limit] häufigsten Kamera-Kombinationen (Hersteller + Modell) für
  /// die Analyseseite – schließt Fotos ganz ohne Kamerainformation
  /// (Screenshots, Scans, ...) bewusst NICHT aus, damit deren Anteil an der
  /// Bibliothek sichtbar wird.
  Future<List<CameraStat>> _loadTopCameras(Expression<bool> visible,
      {int limit = 12}) async {
    final countExpr = assets.id.count();
    final query = selectOnly(assets)
      ..addColumns([assets.cameraMake, assets.cameraModel, countExpr])
      ..where(visible)
      ..groupBy([assets.cameraMake, assets.cameraModel])
      ..orderBy([OrderingTerm.desc(countExpr)])
      ..limit(limit);
    final rows = await query.get();
    return [
      for (final row in rows)
        CameraStat(
          make: row.read<String>(assets.cameraMake),
          model: row.read<String>(assets.cameraModel),
          count: row.read<int>(countExpr) ?? 0,
        ),
    ];
  }

  /// Position (0-basiert) eines Assets in der absteigend nach Datum
  /// sortierten Zeitleiste – wie viele andere (nicht Papierkorb/gesperrte)
  /// Assets neuer sind. Für TimelineScreen: bei "Foto in der Timeline
  /// anzeigen" (Kontextmenü der Vollbildansicht) muss das Ladefenster (siehe
  /// `watchTimeline(limit: ...)`) mindestens so weit geöffnet werden, dass
  /// das Zielfoto enthalten ist – auch wenn es weit "unten" in einer sehr
  /// großen Bibliothek liegt. Gibt `null` zurück, wenn das Asset nicht
  /// existiert.
  Future<int?> timelineRankOfAsset(String assetId) async {
    final asset = await assetById(assetId);
    if (asset == null) return null;
    final Expression<int> countExpr = assets.id.count();
    final JoinedSelectStatement<Assets, AssetData> query = selectOnly(assets)
      ..addColumns([countExpr])
      ..where(assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          _isPrimaryGridEntry(assets) &
          assets.fileCreatedAt.isBiggerThanValue(asset.fileCreatedAt));
    final row = await query.getSingle();
    return row.read<int>(countExpr) ?? 0;
  }

  /// Anzahl Fotos/Videos je Monat **eines Jahres** – für die
  /// Monatsübersicht.
  ///
  /// Dieselbe Bauart wie [watchAssetCountsByYear], nur mit `%m` statt
  /// `%Y` und einer Bereichsgrenze davor. Die Grenze steht als
  /// gewöhnlicher Vergleich auf `file_created_at` und nicht als
  /// `strftime`-Bedingung: So bleibt der Index nutzbar, während ein
  /// `strftime('%Y', …) = '2026'` ihn verwürfe.
  ///
  /// Der Schlüssel ist die Monatszahl 1..12.
  Stream<Map<int, int>> watchAssetCountsByMonth(int jahr) {
    const monatExpr = CustomExpression<String>(
        "strftime('%m', file_created_at, 'unixepoch')");
    final start = DateTime(jahr);
    final ende = DateTime(jahr + 1);
    final query = selectOnly(assets)
      ..addColumns([monatExpr, assets.id.count()])
      ..where(assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          _isPrimaryGridEntry(assets) &
          assets.fileCreatedAt.isBiggerOrEqualValue(start) &
          assets.fileCreatedAt.isSmallerThanValue(ende))
      ..groupBy([monatExpr]);
    return query.watch().map((rows) => {
          for (final row in rows)
            int.parse(row.read(monatExpr)!): row.read(assets.id.count())!,
        });
  }

  /// Alle Aufnahmen eines Monats, neueste zuerst – wie
  /// [watchTimelineForYear], nur enger.
  Stream<List<AssetData>> watchTimelineForMonth(int jahr, int monat) {
    final start = DateTime(jahr, monat);
    final ende = DateTime(jahr, monat + 1);
    final abfrage = select(assets)
      ..where((t) =>
          t.isTrashed.equals(false) &
          t.isLocked.equals(false) &
          _isPrimaryGridEntry(t) &
          t.fileCreatedAt.isBiggerOrEqualValue(start) &
          t.fileCreatedAt.isSmallerThanValue(ende))
      ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]);
    return _gedrosselt(() => abfrage, TableUpdateQuery.onTable(assets));
  }

  /// Titelbild eines Monats – neuestes Foto/Video darin.
  Future<AssetData?> newestAssetForMonth(int jahr, int monat) {
    final start = DateTime(jahr, monat);
    final ende = DateTime(jahr, monat + 1);
    return (select(assets)
          ..where((t) =>
              t.isTrashed.equals(false) &
              t.isLocked.equals(false) &
              _isPrimaryGridEntry(t) &
              t.fileCreatedAt.isBiggerOrEqualValue(start) &
              t.fileCreatedAt.isSmallerThanValue(ende))
          ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Neuestes Foto/Video eines Jahres als Titelbild für die Jahresübersicht
  /// (CalendarScreen) – dieselbe indexgestützte Bereichsabfrage wie
  /// [watchTimelineForYear], aber auf ein einzelnes Ergebnis begrenzt (pro
  /// Jahr wird dort nur ein Titelbild gebraucht, nicht die volle Liste).
  Future<AssetData?> newestAssetForYear(int year) {
    final start = DateTime(year);
    final end = DateTime(year + 1);
    return (select(assets)
          ..where((t) =>
              t.isTrashed.equals(false) &
              t.isLocked.equals(false) &
              _isPrimaryGridEntry(t) &
              t.fileCreatedAt.isBiggerOrEqualValue(start) &
              t.fileCreatedAt.isSmallerThanValue(end))
          ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Der normale, ungeschützte Papierkorb – gesperrte (verschlüsselte)
  /// Assets werden hier bewusst ausgeblendet (siehe [watchLockedTrash]):
  /// sonst könnte jeder ohne PIN ein gesperrtes Foto wiederherstellen oder
  /// sogar endgültig löschen, nur weil es zwischenzeitlich im Papierkorb
  /// liegt.
  Stream<List<AssetData>> watchTrash() {
    final abfrage = select(assets)
      ..where((t) => t.isTrashed.equals(true) & t.isLocked.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.trashedAt)]);
    return _gedrosselt(() => abfrage, TableUpdateQuery.onTable(assets));
  }

  /// Wie viel im Papierkorb liegt – **ohne die Aufnahmen selbst zu holen**.
  ///
  /// Zwei Stellen zeigen nur diese Kennzahl an (die Papierkorbzeile im
  /// Erkunden-Bildschirm und die Papierkorb-Einstellung), und beide
  /// zogen dafür bisher jede Zeile des Papierkorbs mitsamt allen 56
  /// Spalten über die Isolate-Grenze. An der gewachsenen Bibliothek
  /// gemessen, 618 Aufnahmen im Papierkorb:
  ///
  /// ```
  /// watchTrash() - volle Zeilen   13,0 ms
  /// diese Zusammenfassung          0,3 ms
  /// ```
  ///
  /// Das zählt, weil der ganze Widgetbaum bei JEDER Meldung des
  /// Bibliothekszustands neu gebaut wird – in der Hintergrundanalyse
  /// zehnmal je Sekunde.
  Stream<Papierkorbumfang> watchPapierkorbUmfang() {
    final anzahl = assets.id.count();
    final bytes = assets.fileSizeBytes.sum();
    Selectable<Papierkorbumfang> bauen() {
      final abfrage = selectOnly(assets)
        ..addColumns([anzahl, bytes])
        ..where(assets.isTrashed.equals(true) & assets.isLocked.equals(false));
      return abfrage.map((zeile) => Papierkorbumfang(
            anzahl: zeile.read(anzahl) ?? 0,
            bytes: zeile.read(bytes) ?? 0,
          ));
    }

    // `_gedrosselt` liefert Listen; eine Zusammenfassung ist immer genau
    // eine Zeile.
    return _gedrosselt(bauen, TableUpdateQuery.onTable(assets)).map((zeilen) =>
        zeilen.isEmpty
            ? const Papierkorbumfang(anzahl: 0, bytes: 0)
            : zeilen.first);
  }

  /// Eigener, PIN-geschützter Papierkorb für aus dem gesperrten Ordner
  /// gelöschte Fotos – nur über den gesperrten Ordner erreichbar (siehe
  /// LockedFolderScreen), damit "gelöscht" bei gesperrten Fotos denselben
  /// Schutz genießt wie "sichtbar".
  Stream<List<AssetData>> watchLockedTrash() {
    final abfrage = select(assets)
      ..where((t) => t.isTrashed.equals(true) & t.isLocked.equals(true))
      ..orderBy([(t) => OrderingTerm.desc(t.trashedAt)]);
    return _gedrosselt(() => abfrage, TableUpdateQuery.onTable(assets));
  }

  Future<void> setFavorite(String assetId, bool value) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(isFavorite: Value(value)));

  Future<void> setRating(String assetId, int rating) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(rating: Value(rating)));

  Future<void> setRatingBulk(List<String> assetIds, int rating) =>
      (update(assets)..where((t) => t.id.isIn(assetIds)))
          .write(AssetsCompanion(rating: Value(rating)));

  Future<void> setColorLabel(String assetId, String? colorLabel) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(colorLabel: Value(colorLabel)));

  /// Setzt den Favoriten-Status für mehrere Assets in EINER Anweisung.
  ///
  /// Die Auswahlleiste lief vorher in einer Schleife über die Auswahl – bei
  /// 500 markierten Fotos also 500 einzelne Schreibvorgänge statt einem.
  Future<void> setFavoriteBulk(List<String> assetIds, bool value) =>
      (update(assets)..where((t) => t.id.isIn(assetIds)))
          .write(AssetsCompanion(isFavorite: Value(value)));

  Future<void> setColorLabelBulk(List<String> assetIds, String? colorLabel) =>
      (update(assets)..where((t) => t.id.isIn(assetIds)))
          .write(AssetsCompanion(colorLabel: Value(colorLabel)));

  /// Setzt dieselbe Beschreibung für mehrere Assets auf einmal (Auswahlleiste
  /// "Metadaten bearbeiten") – überschreibt, statt anzuhängen.
  Future<void> setDescriptionBulk(List<String> assetIds, String description) =>
      (update(assets)..where((t) => t.id.isIn(assetIds)))
          .write(AssetsCompanion(description: Value(description)));

  /// Setzt denselben Zeitpunkt für mehrere Assets auf einmal – bewusst kein
  /// relatives Verschieben (jedes Foto würde sonst seinen ursprünglichen
  /// Abstand zu den anderen behalten müssen), sondern ein einfaches
  /// "alle auf diesen einen Zeitpunkt setzen" für die Auswahlleiste.
  /// **Schreibt nur die Spalte.** Wer ein Datum auf Wunsch des Menschen
  /// ändert, muss über [LibraryState.setzeAufnahmedatumVonHand] gehen: Das
  /// Datum bestimmt den Ablageort, und die Datei muss mitgehen. Hier
  /// stehenzubleiben hinterliess an der echten Bibliothek 1102 Aufnahmen,
  /// deren Ordner etwas anderes behauptet als ihre Zeile. Ein Prüfstand
  /// hält die Bildschirme davon fern (siehe
  /// `datum_setzen_verschiebt_test.dart`); für Prüfstände selbst ist der
  /// kurze Weg hier richtig.
  Future<void> setFileCreatedAtBulk(
          List<String> assetIds, DateTime fileCreatedAt) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(AssetsCompanion(
        fileCreatedAt: Value(fileCreatedAt),
        // Wie bei [setAufnahmezeitpunkt]: Ein gesetztes Datum ist kein
        // geratenes mehr.
        datumGeschaetzt: const Value(false),
      ));

  /// Siehe [setLocation] – auch hier fallen die alten Ortsnamen mit.
  /// Setzt Land, Region und Ort für viele Aufnahmen auf **denselben**
  /// Wert – in einer einzigen Anweisung.
  ///
  /// **Warum nicht in einer Schleife.** Genau das stand vorher in
  /// [LibraryState.setzeOrtVonHand]: je Aufnahme ein eigenes UPDATE, und
  /// jedes ist für SQLite eine eigene Übertragung samt Sichern auf die
  /// Platte. An einer Datei gemessen
  /// (`tool/messe_sammelaenderung_test.dart`), 500 Aufnahmen:
  ///
  /// ```
  /// je Aufnahme ein UPDATE   163 ms
  /// eine Klammer darum         24 ms
  /// eine einzige Anweisung      2 ms
  /// ```
  ///
  /// Und der wichtigere Grund ist gar nicht die Zeit: Eine Schleife
  /// hinterlässt, wenn sie in der Mitte scheitert, die eine Hälfte der
  /// Fotos am neuen Ort und die andere am alten. Eine Anweisung tut das
  /// nicht.
  Future<void> setLocationNamesBulk(
    List<String> assetIds, {
    String? country,
    String? state,
    required String city,
  }) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(AssetsCompanion(
        locationCountry: Value(country),
        locationState: Value(state),
        locationCity: Value(city),
      ));

  Future<void> setLocationBulk(
          List<String> assetIds, double? latitude, double? longitude) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(AssetsCompanion(
        latitude: Value(latitude),
        longitude: Value(longitude),
        locationCountry: const Value(null),
        locationState: const Value(null),
        locationCity: const Value(null),
      ));

  Future<void> moveToTrash(List<String> assetIds) async {
    await (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        AssetsCompanion(
            isTrashed: const Value(true), trashedAt: Value(DateTime.now())));
    _embeddingsGeneration++;
  }

  /// Führt die Metadaten ähnlicher Aufnahmen auf [behaltenId] zusammen und
  /// verschiebt die übrigen Dateien anschließend in den Papierkorb.
  ///
  /// Der Pixelinhalt wird nie verändert. Tags und Albumzuordnungen werden
  /// vereinigt; Favorit und höchste Sterne bleiben erhalten. Bei gleicher
  /// Beschreibung würde ein Anhängen nur Dubletten erzeugen, bei
  /// unterschiedlichen entscheidet [beschreibungenVerbinden], ob beide
  /// lesbar bleiben sollen. Die ganze Operation ist eine Transaktion, damit
  /// nie eine halbe Metadatenübernahme neben noch sichtbaren Kopien steht.
  Future<void> fuehreDuplikateZusammen({
    required String behaltenId,
    required List<String> duplikatIds,
    bool beschreibungenVerbinden = true,
  }) =>
      transaction(() async {
        final ids =
            duplikatIds.where((id) => id != behaltenId).toSet().toList();
        if (ids.isEmpty) {
          return;
        }
        final behalten = await assetById(behaltenId);
        if (behalten == null) {
          throw ArgumentError.value(behaltenId, 'behaltenId');
        }
        final kopien =
            await (select(assets)..where((t) => t.id.isIn(ids))).get();
        if (kopien.isEmpty) {
          return;
        }

        var favorit = behalten.isFavorite;
        var bewertung = behalten.rating;
        var farbe = behalten.colorLabel;
        final beschreibungen = <String>{
          if (behalten.description?.trim().isNotEmpty == true)
            behalten.description!.trim(),
        };
        for (final kopie in kopien) {
          favorit = favorit || kopie.isFavorite;
          if (kopie.rating > bewertung) bewertung = kopie.rating;
          farbe ??= kopie.colorLabel;
          if (kopie.description?.trim().isNotEmpty == true) {
            beschreibungen.add(kopie.description!.trim());
          }
        }

        for (final id in ids) {
          final tagsDerKopie = await (select(assetTags)
                ..where((t) => t.assetId.equals(id)))
              .get();
          final albenDerKopie = await (select(albumAssets)
                ..where((t) => t.assetId.equals(id)))
              .get();
          for (final tag in tagsDerKopie) {
            if (tag.quelle == Tagquelle.hand) {
              // Hand schlägt KI – dieselbe Regel wie in [tagAsset].
              await into(assetTags).insertOnConflictUpdate(
                  AssetTagsCompanion.insert(
                      assetId: behaltenId,
                      tagId: tag.tagId,
                      quelle: const Value(Tagquelle.hand)));
            } else {
              await into(assetTags).insert(
                AssetTagsCompanion.insert(
                    assetId: behaltenId,
                    tagId: tag.tagId,
                    quelle: Value(tag.quelle)),
                mode: InsertMode.insertOrIgnore,
              );
            }
          }
          for (final album in albenDerKopie) {
            await into(albumAssets).insert(
              AlbumAssetsCompanion.insert(
                  albumId: album.albumId, assetId: behaltenId),
              mode: InsertMode.insertOrIgnore,
            );
          }
        }

        final beschreibung = beschreibungen.isEmpty
            ? null
            : beschreibungenVerbinden
                ? beschreibungen.join('\n\n')
                : beschreibungen.first;
        await (update(assets)..where((t) => t.id.equals(behaltenId))).write(
          AssetsCompanion(
            isFavorite: Value(favorit),
            rating: Value(bewertung),
            colorLabel: Value(farbe),
            description: Value(beschreibung),
          ),
        );
        await moveToTrash(ids);
      });

  Future<void> restoreFromTrash(List<String> assetIds) async {
    await (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        const AssetsCompanion(isTrashed: Value(false), trashedAt: Value(null)));
    _embeddingsGeneration++;
  }

  /// Löscht die Datenbankzeile endgültig. Das eigentliche Löschen der Datei
  /// auf der Festplatte übernimmt StoragePaths.
  Future<void> deleteAssetRows(List<String> assetIds) async {
    await (delete(assets)..where((t) => t.id.isIn(assetIds))).go();
    // Ausnahmen der Duplikatsuche mit wegräumen. Sie würden sonst als
    // Zeilen ohne Foto liegen bleiben und niemandem mehr auffallen – ein
    // Paar, dessen eine Hälfte es nicht mehr gibt, kann nie wieder wirken.
    await (delete(duplikatAusnahmen)
          ..where((t) => t.assetA.isIn(assetIds) | t.assetB.isIn(assetIds)))
        .go();
    _embeddingsGeneration++;
  }

  // --- Ausnahmen der Duplikatsuche --------------------------------------

  /// Alle Ausnahmen als Schlüsselmenge für [findDuplicateGroups].
  ///
  /// Nicht `duplikatAusnahmen()` – so heisst bereits die von drift erzeugte
  /// Tabelle, und eine Methode gleichen Namens verdeckt sie im ganzen
  /// Klassenrumpf.
  Future<Set<String>> duplikatAusnahmeSchluessel() async {
    final zeilen = await select(duplikatAusnahmen).get();
    return {for (final z in zeilen) duplikatPaarSchluessel(z.assetA, z.assetB)};
  }

  Future<int> zaehleDuplikatAusnahmen() async {
    final zaehler = duplikatAusnahmen.assetA.count();
    final zeile = await (selectOnly(duplikatAusnahmen)..addColumns([zaehler]))
        .getSingle();
    return zeile.read(zaehler) ?? 0;
  }

  /// Nimmt alle Paare innerhalb von [assetIds] von der Duplikatsuche aus –
  /// also eine ganze Gruppe auf einmal.
  ///
  /// Alle Paare und nicht nur ein Merkmal an der Gruppe: Gruppen entstehen
  /// bei jedem Lauf neu und hängen an der eingestellten Schwelle; eine
  /// gespeicherte Gruppen-Kennung wäre beim nächsten Regler-Ruck wertlos.
  Future<void> ignoriereDuplikatgruppe(List<String> assetIds) async {
    if (assetIds.length < 2) return;
    final jetzt = DateTime.now();
    await batch((b) {
      for (var i = 0; i < assetIds.length; i++) {
        for (var j = i + 1; j < assetIds.length; j++) {
          final a = assetIds[i], c = assetIds[j];
          final klein = a.compareTo(c) <= 0 ? a : c;
          final gross = a.compareTo(c) <= 0 ? c : a;
          b.insert(
            duplikatAusnahmen,
            DuplikatAusnahmenCompanion.insert(
                assetA: klein, assetB: gross, angelegtAm: jetzt),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
    });
  }

  /// Nimmt die Ausnahmen einer einzelnen Gruppe zurück – für das
  /// „Rückgängig" direkt nach dem Ausblenden.
  Future<void> hebeDuplikatgruppeAuf(List<String> assetIds) async {
    if (assetIds.length < 2) return;
    await batch((b) {
      for (var i = 0; i < assetIds.length; i++) {
        for (var j = i + 1; j < assetIds.length; j++) {
          final a = assetIds[i], c = assetIds[j];
          final klein = a.compareTo(c) <= 0 ? a : c;
          final gross = a.compareTo(c) <= 0 ? c : a;
          b.deleteWhere(
            duplikatAusnahmen,
            ($DuplikatAusnahmenTable t) =>
                t.assetA.equals(klein) & t.assetB.equals(gross),
          );
        }
      }
    });
  }

  /// Hebt alle Ausnahmen wieder auf – der Weg zurück, wenn zu viel
  /// ausgeblendet wurde.
  Future<int> loescheDuplikatAusnahmen() => delete(duplikatAusnahmen).go();

  /// Alle Assets (gesperrt oder nicht – der PIN-Schutz gilt dem Ansehen des
  /// Inhalts, nicht dem endgültigen Löschen einer bereits im Papierkorb
  /// liegenden Datei), die vor [cutoff] in den Papierkorb verschoben wurden.
  /// Für den automatischen Papierkorb-Ablauf, siehe
  /// [LibraryState.purgeExpiredTrashIfDue].
  Future<List<AssetData>> expiredTrashAssets(DateTime cutoff) => (select(assets)
        ..where((t) =>
            t.isTrashed.equals(true) & t.trashedAt.isSmallerThanValue(cutoff)))
      .get();

  Future<TrashSettingsData?> trashSettingsRow() =>
      (select(trashSettings)..where((t) => t.id.equals(0))).getSingleOrNull();

  Future<void> setTrashAutoDeleteConfig(
          {required bool enabled, int? afterDays}) =>
      into(trashSettings).insertOnConflictUpdate(TrashSettingsCompanion.insert(
        id: const Value(0),
        autoDeleteEnabled: Value(enabled),
        autoDeleteAfterDays:
            afterDays != null ? Value(afterDays) : const Value.absent(),
      ));

  Future<void> setLastTrashPurgeAt(DateTime when) =>
      (update(trashSettings)..where((t) => t.id.equals(0)))
          .write(TrashSettingsCompanion(lastPurgeAt: Value(when)));

  /// Reaktiv statt einmalig gelesen, damit ein Theme-Wechsel in den
  /// Einstellungen sofort in main.dart ankommt, ohne App-Neustart.
  Stream<AppSettingsData?> watchAppSettings() =>
      (select(appSettings)..where((t) => t.id.equals(0))).watchSingleOrNull();

  Future<void> setAutoAnalyzeAfterImport(bool an) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        autoAnalyzeAfterImport: Value(an),
      ));

  /// Einmalig gelesen (nicht als Stream): wird direkt nach einem Import
  /// abgefragt, um zu entscheiden, ob die Analyse anlaufen soll.
  /// Der überwachte Ordner samt Sandbox-Merkmal, oder null.
  Future<({String pfad, String? token})?> ueberwachterOrdner() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    final pfad = row?.watchedFolderPath;
    if (pfad == null || pfad.isEmpty) return null;
    return (pfad: pfad, token: row?.watchedFolderToken);
  }

  /// Setzt den überwachten Ordner; [pfad] = null schaltet die Überwachung ab.
  Future<void> setzeUeberwachtenOrdner({String? pfad, String? token}) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        watchedFolderPath: Value(pfad),
        watchedFolderToken: Value(token),
      ));

  /// Allgemeine Gesichts-Ähnlichkeitsschwelle. Beim Schreiben werden die
  /// persönlichen Schwellen mitgezogen – sie hängen an dieser (siehe
  /// [rechneAlleSchwellenNeu]), sonst hätte der Regler für bereits
  /// gelernte Personen keine Wirkung mehr.
  Future<void> setFaceSimilarityThreshold(double wert) => transaction(() async {
        await into(appSettings)
            .insertOnConflictUpdate(AppSettingsCompanion.insert(
          id: const Value(0),
          faceSimilarityThreshold: Value(wert),
        ));
        await rechneAlleSchwellenNeu(wert);
      });

  Future<double> faceSimilarityThresholdWert() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return row?.faceSimilarityThreshold ?? 0.363;
  }

  Future<bool> autoAnalyzeAfterImportEnabled() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return row?.autoAnalyzeAfterImport ?? true;
  }

  /// Benennt Vokabelbegriffe und die zugehörigen Schlagwörter um – für das
  /// Angebot beim Sprachwechsel.
  ///
  /// [zuordnung] bildet alt auf neu ab und enthält **nur** Begriffe, die
  /// tatsächlich im Vokabular stehen; selbst hinzugefügte bleiben
  /// unangetastet.
  ///
  /// Drei Tabellen sind betroffen, und die dritte ist die, die man
  /// übersieht:
  ///
  ///  1. [AiTagVocabulary.term] – der Vokabeleintrag
  ///  2. [Tags.name] – der Schlagwort-Name. Alle Zuordnungen hängen an
  ///     [Tags.id] und wandern deshalb von selbst mit; es ist ein reines
  ///     Umbenennen, kein Umhängen.
  ///  3. [AutomationRules.aiTagTerm] – eine Textspalte, die exakt einem
  ///     Vokabelbegriff entsprechen muss. Bliebe sie stehen, hörte eine
  ///     Regel „wenn Hund erkannt" lautlos auf zu feuern.
  ///
  /// **Namenskollisionen** sind der Fall, an dem eine naive Fassung
  /// scheitert: Beide Namensspalten sind `unique`. Gibt es das Ziel schon
  /// (etwa ein von Hand angelegtes „Dog"), wird nicht umbenannt, sondern
  /// **verschmolzen** – die Zuordnungen des alten Schlagworts wandern auf
  /// das bestehende, das alte wird gelöscht. Ohne diesen Zweig bräche die
  /// ganze Umstellung mit einem Constraint-Fehler ab.
  ///
  /// Gibt die Anzahl tatsächlich umbenannter Begriffe zurück.
  Future<int> uebersetzeVokabular(Map<String, String> zuordnung) async {
    var geaendert = 0;
    await transaction(() async {
      for (final eintrag in zuordnung.entries) {
        final alt = eintrag.key;
        final neu = eintrag.value;
        if (alt == neu) continue;

        // --- Vokabular ---
        final vorhandenesVokabel = await (select(aiTagVocabulary)
              ..where((t) => t.term.equals(alt)))
            .getSingleOrNull();
        if (vorhandenesVokabel == null) continue;

        final zielVokabel = await (select(aiTagVocabulary)
              ..where((t) => t.term.equals(neu)))
            .getSingleOrNull();
        if (zielVokabel != null) {
          // Ziel gibt es schon – der alte Eintrag ist damit überflüssig.
          await (delete(aiTagVocabulary)
                ..where((t) => t.id.equals(vorhandenesVokabel.id)))
              .go();
        } else {
          await (update(aiTagVocabulary)
                ..where((t) => t.id.equals(vorhandenesVokabel.id)))
              .write(AiTagVocabularyCompanion(term: Value(neu)));
        }

        // --- Schlagwort samt Zuordnungen ---
        final altesTag = await (select(tags)..where((t) => t.name.equals(alt)))
            .getSingleOrNull();
        if (altesTag != null) {
          final zielTag = await (select(tags)..where((t) => t.name.equals(neu)))
              .getSingleOrNull();
          if (zielTag == null) {
            await (update(tags)..where((t) => t.id.equals(altesTag.id)))
                .write(TagsCompanion(name: Value(neu)));
          } else {
            // Verschmelzen: Zuordnungen umhängen, dabei bereits
            // bestehende Paare nicht doppelt anlegen.
            final betroffene = await (select(assetTags)
                  ..where((t) => t.tagId.equals(altesTag.id)))
                .get();
            for (final zuweisung in betroffene) {
              await into(assetTags)
                  .insertOnConflictUpdate(AssetTagsCompanion.insert(
                assetId: zuweisung.assetId,
                tagId: zielTag.id,
              ));
            }
            await (delete(assetTags)..where((t) => t.tagId.equals(altesTag.id)))
                .go();
            await (delete(automationRuleTags)
                  ..where((t) => t.tagId.equals(altesTag.id)))
                .go();
            await (delete(tags)..where((t) => t.id.equals(altesTag.id))).go();
          }
        }

        // --- Automatisierungsregeln ---
        await (update(automationRules)..where((t) => t.aiTagTerm.equals(alt)))
            .write(AutomationRulesCompanion(aiTagTerm: Value(neu)));

        geaendert++;
      }
    });
    return geaendert;
  }

  /// Begriffe im Vokabular, die NICHT aus der mitgelieferten
  /// Startbestückung stammen – sie bleiben beim Sprachwechsel unverändert
  /// und werden im Dialog gezählt.
  Future<int> zaehleEigeneVokabelbegriffe(Set<String> bekannte) async {
    final alle = await select(aiTagVocabulary).get();
    return alle.where((v) => !bekannte.contains(v.term)).length;
  }

  Future<void> setSprache(String sprache) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        sprache: Value(sprache),
      ));

  Future<String> spracheWert() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return row?.sprache ?? 'system';
  }

  Future<void> setThemeMode(String mode) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        themeMode: Value(mode),
      ));

  Future<void> setDescription(String assetId, String description) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(description: Value(description)));

  /// **Schreibt nur die Spalte.** Wer ein Datum auf Wunsch des Menschen
  /// ändert, muss über [LibraryState.setzeAufnahmedatumVonHand] gehen: Das
  /// Datum bestimmt den Ablageort, und die Datei muss mitgehen. Hier
  /// stehenzubleiben hinterliess an der echten Bibliothek 1102 Aufnahmen,
  /// deren Ordner etwas anderes behauptet als ihre Zeile. Ein Prüfstand
  /// hält die Bildschirme davon fern (siehe
  /// `datum_setzen_verschiebt_test.dart`); für Prüfstände selbst ist der
  /// kurze Weg hier richtig.
  Future<void> setFileCreatedAt(String assetId, DateTime fileCreatedAt) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(
        fileCreatedAt: Value(fileCreatedAt),
        // Wie bei [setAufnahmezeitpunkt]: Ein gesetztes Datum ist kein
        // geratenes mehr.
        datumGeschaetzt: const Value(false),
      ));

  /// Setzt (oder löscht, bei `null`) den Ort eines Assets – entweder aus
  /// EXIF-GPS-Daten beim Import übernommen oder manuell in der Info-Ansicht
  /// der Vollbildvorschau gesetzt/korrigiert.
  ///
  /// **Die ausgeschriebenen Ortsnamen fallen mit.** Sie gehören zur alten
  /// Koordinate; nach einer Korrektur wären sie schlicht falsch. Und weil
  /// [assetsForLocationNameBackfill] nur dort nachträgt, wo noch gar kein
  /// Land steht, blieben sie es für immer: Ein Foto, dessen Ort man von
  /// Afghanistan nach Niedersachsen zieht, hiesse weiterhin „Baghlān,
  /// Afghanistan" – im Infoblatt, in den Ortsgruppen der Übersicht und im
  /// Suchfilter. Genau so hielt sich das Phantomland einer Kamera mit
  /// verrutschtem Empfänger (31 Aufnahmen einer TG-810 von 2013, die
  /// wirklich so in der Datei stehen – mit exiftool gegengelesen).
  ///
  /// Nach dem Leeren trägt der Nachtrag die richtigen Namen ein; ohne
  /// Koordinate bleibt es leer, und das ist die Wahrheit.
  Future<void> setLocation(
          String assetId, double? latitude, double? longitude) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(
        latitude: Value(latitude),
        longitude: Value(longitude),
        locationCountry: const Value(null),
        locationState: const Value(null),
        locationCity: const Value(null),
        // Wer eine Koordinate setzt oder aus der Datei liest, ersetzt
        // eine Vermutung durch etwas Belegtes (siehe [Assets.ortGeerbt]).
        ortGeerbt: const Value(false),
      ));

  /// Die Daten, aus denen die Ortsvorschlaege entstehen: die
  /// unverorteten Aufnahmen und die verorteten, je nur mit dem, was die
  /// Rechnung braucht.
  ///
  /// **Zwei schlanke Abfragen statt zweier voller.** Es geht um 5351 und
  /// 2092 Zeilen; `select(assets)` zoege fuer jede alle 57 Spalten
  /// herueber, um daraus drei Zahlen zu lesen.
  ///
  /// Papierkorb und Tresor bleiben draussen: Ein geloeschtes Foto braucht
  /// keinen Ort, und ein gesperrtes soll nicht ueber seine Nachbarn
  /// verraten, wo es entstand.
  Future<({List<Ortsloser> ohneOrt, List<Ortsnachbar> verortet})>
      ortsvorschlagsdaten() async {
    Expression<bool> grund() =>
        assets.isTrashed.equals(false) & assets.isLocked.equals(false);

    final ohne = selectOnly(assets)
      ..addColumns([assets.id, assets.fileCreatedAt])
      ..where(grund() & assets.latitude.isNull());
    final mit = selectOnly(assets)
      ..addColumns([assets.fileCreatedAt, assets.latitude, assets.longitude])
      ..where(grund() & assets.latitude.isNotNull());

    return (
      ohneOrt: [
        for (final z in await ohne.get())
          (
            id: z.read<String>(assets.id)!,
            wann: z.read<DateTime>(assets.fileCreatedAt)!,
          ),
      ],
      verortet: [
        for (final z in await mit.get())
          (
            wann: z.read<DateTime>(assets.fileCreatedAt)!,
            breite: z.read<double>(assets.latitude)!,
            laenge: z.read<double>(assets.longitude)!,
          ),
      ],
    );
  }

  /// Uebernimmt einen Ortsvorschlag fuer eine ganze Gruppe – **in einer
  /// Anweisung je Koordinate**.
  ///
  /// Die ausgeschriebenen Ortsnamen bleiben leer; die traegt der
  /// vorhandene Nachtrag [assetsForLocationNameBackfill] nach, der genau
  /// nach Zeilen mit Koordinate und ohne Land sucht.
  Future<void> uebernimmOrtsvorschlag(
          List<String> assetIds, double breite, double laenge) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(AssetsCompanion(
        latitude: Value(breite),
        longitude: Value(laenge),
        locationCountry: const Value(null),
        locationState: const Value(null),
        locationCity: const Value(null),
        ortGeerbt: const Value(true),
      ));

  Future<Set<String>> verworfeneOrtsvorschlagsschluessel() async => {
        for (final z in await select(verworfeneOrtsvorschlaege).get())
          z.schluessel
      };

  Future<void> verwirfOrtsvorschlag(String schluessel) =>
      into(verworfeneOrtsvorschlaege).insertOnConflictUpdate(
          VerworfeneOrtsvorschlaegeCompanion.insert(
              schluessel: schluessel, verworfenAm: DateTime.now()));

  /// Fotos ohne bekannten Ort – für das nachträgliche Einlesen von
  /// EXIF-GPS-Daten (Werkzeuge), z.B. für Fotos, die vor Einführung dieser
  /// Funktion importiert wurden. Nur Fotos, da Videos i.d.R. keine
  /// EXIF-GPS-Daten haben (Ort muss dort manuell in der Info-Ansicht
  /// gesetzt werden).
  /// Alles ohne Ort – **Videos eingeschlossen**.
  ///
  /// Der Filter auf `IMAGE` stand hier von Anfang an und schloss damit
  /// genau die Gruppe aus, bei der noch etwas zu holen war: In der
  /// Prüfbibliothek trugen 43 von 60 zufällig geprüften Videos einen Ort
  /// in der Datei und keines von 440 einen in der Datenbank. Bei den
  /// Fotos ist der Topf dagegen leer – von 59 geprüften unverorteten
  /// iPhone- und Canon-Aufnahmen trug keine einzige noch GPS.
  ///
  /// **[alle] = false überspringt, was schon einmal angesehen wurde**
  /// (siehe [Assets.gpsGeprueft]). Ohne das las jeder Lauf dieselben
  /// tausende Dateien vollständig ein, um wieder nichts zu finden:
  /// gemessen 3,3 s und 1215 MB je 400 Fotos, hochgerechnet 47 s und
  /// 17,5 GB. `alle = true` ist der Weg für den Fall, dass jemand die
  /// Dateien ausserhalb der App mit Koordinaten versehen hat.
  Expression<bool> _ohneOrt(bool alle) {
    final grund = assets.isTrashed.equals(false) & assets.latitude.isNull();
    return alle ? grund : grund & assets.gpsGeprueft.equals(false);
  }

  Future<List<AssetData>> assetsForLocationBackfill({bool alle = false}) =>
      (select(assets)..where((_) => _ohneOrt(alle))).get();

  /// Zählvariante von [assetsForLocationBackfill] – für Anzeigezwecke (siehe
  /// BackgroundTasksScreen), ohne die vollen Zeilen aus der DB zu holen.
  Future<int> countLocationBackfill({bool alle = false}) =>
      _countWhere(_ohneOrt(alle));

  /// Wie viele ortlose Aufnahmen einen **verorteten zeitlichen Nachbarn**
  /// haben und deshalb im Ortsvorschlag landen können.
  ///
  /// Nicht dasselbe wie [countLocationBackfill]: Das zählt alles ohne Ort
  /// (an dieser Bibliothek 5143), hiervon sind aber nur 408 überhaupt
  /// erbbar. Eine Zahl, die zehnmal grösser ist als das, was der Bildschirm
  /// dahinter anbietet, wäre keine Auskunft, sondern ein Ärgernis.
  ///
  /// **In einem Durchlauf, nicht als Nachbarschaftssuche je Zeile.** Das
  /// nächstliegende `EXISTS (… abs(differenz) <= fenster)` braucht an
  /// dieser Bibliothek **2,4 s** – für einen Bildschirm, der ohnehin schon
  /// eine halbe Sekunde lädt, das Ende. Über zwei Fensterfunktionen auf
  /// derselben Sortierung – der letzte verortete davor, der nächste
  /// danach – sind es **27 ms** bei identischem Ergebnis.
  ///
  /// [fenster] in Sekunden, und die Vorgabe ist dieselbe wie in
  /// [Ortsvorschlagsregeln]: Was hier gezählt wird, muss das sein, was
  /// dort auch herauskommt.
  Future<int> countOrtsvorschlagskandidaten(
      {int fensterSekunden = 2 * 60 * 60}) async {
    final zeile = await customSelect(
      'WITH t AS (SELECT file_created_at AS ts, (latitude IS NOT NULL) AS hat '
      '           FROM assets WHERE is_trashed = 0), '
      '     f AS (SELECT ts, hat, '
      '             max(CASE WHEN hat THEN ts END) OVER (ORDER BY ts '
      '                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) '
      '               AS vorher, '
      '             min(CASE WHEN hat THEN ts END) OVER (ORDER BY ts '
      '                 ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) '
      '               AS nachher '
      '           FROM t) '
      'SELECT count(*) AS n FROM f WHERE hat = 0 '
      '  AND (ts - vorher <= ?1 OR nachher - ts <= ?1)',
      variables: [Variable<int>(fensterSekunden)],
      readsFrom: {assets},
    ).getSingle();
    return zeile.read<int>('n');
  }

  /// Wie viele erkannte Gesichter noch keiner Person gehören.
  ///
  /// Dieselbe Einschränkung wie [unassignedFaces] – beiseitegelegte
  /// Gesichter und solche an gelöschten oder gesperrten Aufnahmen zählen
  /// nicht mit. Eine Zahl, die mehr verspricht als die Liste dahinter
  /// zeigt, ist schlimmer als keine.
  Future<int> countOffeneGesichter() async {
    final n = faces.id.count();
    final zeile = await (selectOnly(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
          ..addColumns([n])
          ..where(faces.personId.isNull() &
              faces.isIgnored.equals(false) &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false)))
        .getSingle();
    return zeile.read(n) ?? 0;
  }

  /// Vermerkt für mehrere Aufnahmen auf einmal, dass in ihrer Datei nach
  /// einem Ort gesucht wurde – gleich ob mit Erfolg.
  ///
  /// Blockweise und nicht je Datei: Das Suchen selbst ist der teure Teil,
  /// aber tausende Einzelschreibvorgänge daneben wären es auch (gemessen
  /// bei den Ortsnamen: 2131 ms einzeln gegen 139 ms in Blöcken).
  Future<void> markGpsGeprueft(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds)))
          .write(const AssetsCompanion(gpsGeprueft: Value(true)));

  /// Aufnahmen, in deren Datei noch nicht nach einem Aufnahmedatum
  /// gesehen wurde (siehe [Assets.datumGeprueft]).
  ///
  /// Der Papierkorb ist dabei: Ein zurückgeholtes Foto soll nicht als
  /// einziges ohne Herkunftsvermerk dastehen.
  Expression<bool> _datumOffen(bool alle) => alle
      ? const CustomExpression<bool>('1')
      : assets.datumGeprueft.equals(false);

  Future<List<AssetData>> assetsFuerDatumsherkunft({bool alle = false}) =>
      (select(assets)..where((_) => _datumOffen(alle))).get();

  /// Zählvariante von [assetsFuerDatumsherkunft], siehe [countLocationBackfill].
  Future<int> countDatumsherkunft({bool alle = false}) =>
      _countWhere(_datumOffen(alle));

  /// Nur die Aufnahmen, bei denen der Lauf voraussichtlich etwas ändert:
  /// solche, deren Zeitstempel auf einer **vollen Stunde** sitzt.
  ///
  /// **Warum genau dieses Merkmal.** Ein echter Auslösezeitpunkt trifft die
  /// volle Stunde mit einer Wahrscheinlichkeit von 1:3600. An der
  /// Produktivbibliothek wären das bei 7443 Aufnahmen rund **2** – gezählt
  /// wurden **1097**, davon **948** auf ein und derselben Sekunde. Das ist
  /// kein Zufall, sondern ein Datum ohne Uhrzeit, das jemand beim Einlesen
  /// auf 00:00 aufgefüllt hat.
  ///
  /// [countDatumsherkunft] zählt dagegen alles, was noch niemand
  /// nachgesehen hat – an derselben Bibliothek 8098. Als Zahl auf dem
  /// Gesundheitsbildschirm verspräche sie Arbeit, die der Lauf gar nicht
  /// leistet, und das ist schlimmer als keine Zahl (siehe
  /// [countOffeneGesichter]).
  ///
  /// **Gerechnet wird in Ortszeit, nicht in UTC.** Die volle Stunde ist
  /// eine Eigenschaft der Uhrzeit, die jemand gesehen hat, als der Wert
  /// entstand. In Zonen mit halbstuendigem Versatz – Indien, Teile
  /// Australiens – laege eine erfundene Mitternacht in UTC bei 1800
  /// Sekunden und bliebe ungezaehlt. Der Sommerzeitsprung stoert dabei
  /// nicht: Er betraegt ueberall volle Stunden und aendert am Rest der
  /// Division nichts.
  /// Der Verdacht als Ausdruck, fuer alle, die ihn ausschliessen wollen –
  /// siehe [countAuffaelligeAufnahmedaten] fuer die Begruendung der
  /// vollen Stunde.
  ///
  /// **Er gilt nur, solange niemand nachgesehen hat.** Der Lauf
  /// „Herkunft der Aufnahmedaten" oeffnet die Datei und setzt
  /// [Assets.datumGeprueft]; was er dabei nicht als geschaetzt markiert,
  /// hat dort ein echtes Datum stehen. An der echten Bibliothek sind das
  /// **149 Aufnahmen auf voller Stunde, die der Lauf bestaetigt hat** –
  /// 148 davon am 27. August. Sie danach weiter auszuschliessen hiesse,
  /// eine Vermutung ueber einen Beleg zu stellen.
  Expression<bool> _nichtAufVollerStunde() => CustomExpression<bool>(
      '(datum_geprueft = 1 OR (file_created_at + '
      '${DateTime.now().timeZoneOffset.inSeconds}) % 3600 <> 0)');

  Future<int> countAuffaelligeAufnahmedaten() => _countWhere(
        _datumOffen(false) &
            assets.fileCreatedAt.isNotNull() &
            // file_created_at liegt als Sekunden seit 1970 vor, nicht als
            // Text und nicht in Millisekunden – der Rest der Division ist
            // deshalb direkt zu haben.
            CustomExpression<bool>('(file_created_at + '
                '${DateTime.now().timeZoneOffset.inSeconds}) % 3600 = 0'),
      );

  /// Vermerkt „nachgesehen" für eine ganze Gruppe – und setzt bei denen
  /// aus [geschaetzt] zugleich die Marke.
  ///
  /// **Zwei Anweisungen und nicht zweitausend.** Der Nachtrag geht über
  /// die ganze Bibliothek; je Aufnahme ein eigenes UPDATE wäre derselbe
  /// Fehler, der bei den Ortsnamen 163 ms gegen 2 ms kostete. Und ein
  /// Abbruch mittendrin lässt hier keinen halben Zustand zurück: Beide
  /// Anweisungen betreffen denselben Block.
  ///
  /// Die Marke wird auch **zurückgenommen**: Wer den Lauf mit „alle"
  /// wiederholt, nachdem er die Kameradaten ausserhalb der App
  /// nachgetragen hat, soll die Marke wieder los sein.
  Future<void> markDatumGeprueft(List<String> assetIds,
      {required List<String> geschaetzt,
      Map<String, int> versatz = const {}}) async {
    if (assetIds.isEmpty) return;
    final geraten = geschaetzt.toSet();
    await transaction(() async {
      await (update(assets)..where((t) => t.id.isIn(assetIds)))
          .write(const AssetsCompanion(
              datumGeprueft: Value(true),
              datumGeschaetzt: Value(false),
              // Auch der Versatz wird zurueckgenommen: Wer den Lauf mit
              // „alle" wiederholt, soll eine Angabe loswerden, die in der
              // Datei nicht mehr steht.
              zeitversatzMinuten: Value(null)));
      if (geraten.isNotEmpty) {
        await (update(assets)..where((t) => t.id.isIn(geraten.toList())))
            .write(const AssetsCompanion(datumGeschaetzt: Value(true)));
      }
      // Nach Wert gebuendelt: Eine Anweisung je vorkommender Zone statt
      // einer je Aufnahme. In der echten Bibliothek kommen zwei vor.
      final nachWert = <int, List<String>>{};
      for (final e in versatz.entries) {
        nachWert.putIfAbsent(e.value, () => []).add(e.key);
      }
      for (final e in nachWert.entries) {
        await (update(assets)..where((t) => t.id.isIn(e.value)))
            .write(AssetsCompanion(zeitversatzMinuten: Value(e.key)));
      }
    });
  }

  /// Setzt die Kamera-/Objektiv-/Aufnahme-Angaben eines Assets (siehe
  /// CameraInfo) – beim Import automatisch oder nachträglich über das
  /// Werkzeug "Kameradaten einlesen".
  Future<void> setCameraMetadata(String assetId, CameraInfo info) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(
        cameraMake: Value(info.make),
        cameraModel: Value(info.model),
        lensModel: Value(info.lensModel),
        focalLengthMm: Value(info.focalLengthMm),
        fNumber: Value(info.fNumber),
        iso: Value(info.iso),
        exposureTimeSeconds: Value(info.exposureTimeSeconds),
        exposureBiasEv: Value(info.exposureBiasEv),
        focalLength35mm: Value(info.focalLength35mm),
      ));

  /// Fotos ohne bekannte Kamera-Angaben – für das nachträgliche Einlesen in
  /// den Werkzeugen (Fotos, die vor Einführung dieser Funktion importiert
  /// wurden). Prüft nur Hersteller+Modell als "schon verarbeitet"-Signal;
  /// Fotos, deren EXIF-Daten tatsächlich keine Kamera-Angaben enthalten
  /// (z.B. Screenshots), werden dadurch bei jedem Lauf erneut geprüft – wie
  /// bei [assetsForLocationBackfill] bewusst in Kauf genommen, da das
  /// erneute Prüfen sehr günstig ist.
  /// **Videos gehören dazu.** Bis Fassung 2.5 stand hier `type = 'IMAGE'`,
  /// und damit blieben 275 Videos aussen vor, die Hersteller und Gerät in
  /// der Datei tragen – 228 davon in Apples Schlüsselliste, weitere acht
  /// in den klassischen Atomen `©mak`/`©mod` (siehe [kameraAusMoov]).
  /// Der Lauf las stattdessen 842 Fotos, von denen nachweislich **keines**
  /// eine Kameraangabe in der Datei hat, und änderte nichts.
  Expression<bool> get _ohneKameraangabe =>
      assets.isTrashed.equals(false) &
      assets.cameraMake.isNull() &
      assets.cameraModel.isNull();

  Future<List<AssetData>> assetsForCameraMetadataBackfill() =>
      (select(assets)..where((_) => _ohneKameraangabe)).get();

  /// Zählvariante von [assetsForCameraMetadataBackfill], siehe [countLocationBackfill].
  Future<int> countCameraMetadataBackfill() => _countWhere(_ohneKameraangabe);

  /// Setzt Aufnahmezeitpunkt und – falls der Monat wechselt – den neuen
  /// Ablageort einer Datei.
  ///
  /// Beides zusammen, weil beides zusammengehört: Der Ordner unter
  /// `originals/` wird aus dem Aufnahmedatum gebildet. Ein neues Datum
  /// ohne neuen Pfad hiesse, dass die Ablage auf der Platte nicht mehr zu
  /// dem passt, was die App anzeigt.
  /// Setzt den Aufnahmezeitpunkt – und nimmt dabei die Marke
  /// „geschätzt" zurück (siehe [Assets.datumGeschaetzt]).
  ///
  /// Wer ein Datum von Hand einträgt, weiss mehr als die Datei. Bliebe
  /// die Marke stehen, hinge sie ausgerechnet an dem Wert, der von allen
  /// der belegteste ist – und das Foto fiele weiter aus Erinnerungen und
  /// Serien heraus, obwohl der Grund dafür gerade behoben wurde.
  Future<void> setAufnahmezeitpunkt(String assetId, DateTime zeitpunkt,
          {String? neuerPfad}) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(
        fileCreatedAt: Value(zeitpunkt),
        datumGeschaetzt: const Value(false),
        relativePath:
            neuerPfad == null ? const Value.absent() : Value(neuerPfad),
      ));

  /// RAW-Fotos, deren Aufnahmedatum aus dem Dateizeitstempel stammen
  /// könnte – Kandidaten für die Datumskorrektur.
  ///
  /// Warum RAW **und Video**: `package:exif` liest nur TIFF/JPEG. Formate
  /// wie CR3 und die Videocontainer MOV/MP4 liefern dort NULL Tags, und
  /// dann fällt der Import auf `lastModified()` der Quelldatei zurück –
  /// also auf den Zeitpunkt des letzten Kopierens.
  ///
  /// **Die Videos fehlten hier bis Fassung 2.5.** Der Kommentar an dieser
  /// Stelle begründete das damit, dass es den Rückfall nur bei RAW gebe.
  /// An der echten Bibliothek nachgezählt war das falsch: 309 von 440
  /// Videos tragen einen Aufnahmezeitpunkt in der Datei, **kein einziges**
  /// trug den richtigen in der Datenbank, und 196 lagen um mehr als einen
  /// Tag daneben. Der Leser dafür steht in [zeitAusMoov]; diese Abfrage
  /// war das, was ihn nie zu Gesicht bekam.
  ///
  /// Gewöhnliche JPEG bleiben aussen vor: Dort kam das Datum immer aus den
  /// EXIF-Daten oder es gab überhaupt keines in der Datei (nachgezählt:
  /// 1774 Aufnahmen ohne jede Zeitangabe, die auch ein erneutes Lesen
  /// nicht datieren könnte).
  ///
  /// Bewusst ohne weitere Einschränkung: Ob ein Datum wirklich falsch ist,
  /// weiss erst der Vergleich mit der Datei. Diese Abfrage grenzt nur die
  /// Menge ein, die überhaupt betroffen sein kann.
  /// RAW-Aufnahmen, deren Aufnahmedatum nachgelesen werden soll.
  ///
  /// **Die RAW-Bedingung steht hier und nicht mehr im Aufrufer.** Vorher
  /// lud diese Abfrage ALLE Bilder – bei 7.988 Aufnahmen also achttausend
  /// Zeilen –, und `korrigiereAufnahmedaten` warf davon in Dart alles weg,
  /// was keine RAW-Endung hatte. Nebenbei liess sich die Zahl damit nicht
  /// anzeigen, ohne dieselbe Arbeit ein zweites Mal zu tun. Jetzt
  /// entscheidet SQL, [countDatumskorrektur] fragt dasselbe, und beide
  /// können nicht auseinanderlaufen.
  ///
  /// Über die Endung des Ablagepfades und **nicht** über die Spalte
  /// `dateiformat`: Die ist erst seit Fassung 47 da und darf leer sein –
  /// eine Datei, die ohne Endung hereinkam, hat dort nichts stehen. Mit
  /// `dateiformat` fielen solche Zeilen stillschweigend heraus, und der
  /// Prüfstand hat genau das gefangen. Der Ablagepfad dagegen trägt die
  /// kleingeschriebene Endung der Quelldatei, immer.
  ///
  /// Fünfundzwanzig `LIKE` über die ganze Tabelle sind kein Vergnügen,
  /// aber es ist eine Abfrage statt achttausend Zeilen durch den
  /// Dart-Speicher.
  Expression<bool> get _rohaufnahme {
    Expression<bool>? endungen;
    for (final e in rawImageExtensions) {
      final eine = assets.relativePath.lower().like('%$e');
      endungen = endungen == null ? eine : endungen | eine;
    }
    return assets.isTrashed.equals(false) &
        (assets.type.equals('VIDEO') |
            (assets.type.equals('IMAGE') & endungen!));
  }

  /// Aufnahmen, deren **Ablageordner nicht zu ihrem Datum passt**.
  ///
  /// Der Ablagepfad ist `originals/JJJJ/MM/<Kennung><Endung>` (siehe
  /// [StoragePaths.originalRelativePath]). Wer das Datum von Hand setzte,
  /// bekam bis Fassung 2.6 nur die Spalte geändert – die Datei blieb im
  /// Ordner des alten Monats. An einer echten Bibliothek betraf das
  /// **1102 von 7988 Aufnahmen**, davon 948 aus einer einzigen
  /// Sammelbearbeitung.
  ///
  /// Die Ursache ist behoben (siehe
  /// [LibraryState.setzeAufnahmedatumVonHand]); das hier räumt auf, was
  /// vorher entstanden ist.
  ///
  /// **In SQL und nicht in Dart**, obwohl der Pfad in Dart gebaut wird:
  /// Sonst kämen achttausend Zeilen herüber, damit von jeder zwei Zahlen
  /// verglichen werden. `substr(…, 11, 7)` schneidet die sieben Zeichen
  /// `JJJJ/MM` hinter `originals/` heraus.
  ///
  /// `'localtime'` ist zwingend: `originalRelativePath` nimmt Jahr und
  /// Monat der **Ortszeit**. Ohne den Modifier läge jede Aufnahme aus der
  /// ersten Stunde eines Monats scheinbar falsch. Sollten sich die beiden
  /// Zeitrechnungen doch einmal um eine Stunde uneinig sein, ist das
  /// harmlos: Der Lauf berechnet denselben Pfad und verschiebt nichts.
  ///
  /// **Der Papierkorb ist dabei**, anders als bei der Datumskorrektur: Ein
  /// gelöschtes Foto liegt weiterhin unter `originals/`, und die Frage
  /// lautet hier nicht „stimmt das Datum", sondern „stimmt der Ordner".
  Expression<bool> get _ablageFalsch => const CustomExpression<bool>(
        "replace(relative_path, char(92), '/') LIKE 'originals/%' AND "
        "substr(replace(relative_path, char(92), '/'), 11, 7) "
        "<> strftime('%Y/%m', file_created_at, 'unixepoch', 'localtime')",
      );

  Future<List<AssetData>> assetsFuerAblageordnung() =>
      (select(assets)..where((_) => _ablageFalsch)).get();

  /// Zählvariante von [assetsFuerAblageordnung], siehe [countLocationBackfill].
  Future<int> countAblageordnung() => _countWhere(_ablageFalsch);

  Future<List<AssetData>> assetsFuerDatumskorrektur() =>
      (select(assets)..where((_) => _rohaufnahme)).get();

  /// Zählvariante von [assetsFuerDatumskorrektur], siehe [countLocationBackfill].
  Future<int> countDatumskorrektur() => _countWhere(_rohaufnahme);

  /// Setzt das Ergebnis der Texterkennung (siehe ImageConverter.swift
  /// `recognizeText`) – [text] darf leer sein (kein Text im Bild gefunden),
  /// `ocrScanned` unterscheidet das von "noch nicht gescannt".
  Future<void> setOcrResult(String assetId, String text, {String? boxen}) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(
        ocrText: Value(text),
        ocrBoxen: Value(boxen),
        ocrScanned: const Value(true),
      ));

  /// Bild-Assets ohne Texterkennung – für den nachträglichen Lauf in den
  /// Werkzeugen (Fotos, die vor Einführung dieser Funktion importiert wurden).
  ///
  /// Ohne gesperrte Fotos, aus demselben Grund wie bei [assetsForAiTagging]:
  /// Erkannter Text ist Bildinhalt und hätte in der unverschlüsselten
  /// Datenbank nichts zu suchen. Bisher fehlte dieser Filter (Audit-Fund) –
  /// folgenlos nur deshalb, weil die mitverschlüsselte Vorschau ohnehin
  /// nicht dekodierbar ist; verlassen sollte sich darauf niemand.
  Future<List<AssetData>> assetsForOcrBackfill() =>
      (select(assets)..where(_ocrOffen)).get();

  /// Zählvariante von [assetsForOcrBackfill], siehe [countLocationBackfill].
  Future<int> countOcrBackfill() => _countWhere(_ocrOffen(assets));

  /// Auf wie vielen Aufnahmen überhaupt Text erkannt worden ist.
  ///
  /// Für die Suche im erkannten Text: Steht hier eine Null, dann liegt es
  /// nicht an der Suchanfrage, dass nichts kommt – dann ist die
  /// Texterkennung schlicht noch nie gelaufen. "Keine Treffer" wäre
  /// dafür die falsche Auskunft.
  Future<int> zaehleMitErkanntemText() =>
      _countWhere(assets.ocrText.isNotNull() & assets.ocrText.equals('').not());

  /// Was die Texterkennung noch vor sich hat.
  ///
  /// Zwei Fälle, nicht einer. Der erste ist der alte: nie gescannt. Der
  /// zweite kam mit Schema 60 dazu – gescannt, Text gefunden, aber ohne die
  /// Stellen im Bild. Ohne diesen zweiten Fall blieben die 2406 bereits
  /// erkannten Texte für immer ohne Kästchen, denn `ocrScanned` steht bei
  /// ihnen längst auf wahr und nichts holte sie je wieder hervor.
  ///
  /// Fotos, in denen nachweislich kein Text steht (`ocrText` leer), bleiben
  /// aussen vor: Bei ihnen gäbe es auch beim zweiten Lauf keine Stellen, und
  /// es wären über fünftausend vergebliche Durchläufe.
  /// Was sich aus dem Bildinhalt auswerten lässt.
  ///
  /// Jedes Bild – **und jedes Video, von dem ein Standbild vorliegt**. Der
  /// Filter `type = 'IMAGE'` stand in dreiundzwanzig Abfragen und liess
  /// damit die 440 Videos der Prüfbibliothek aus jeder Stufe heraus: null
  /// Beschreibungen, null Schlagwörter, null Gesichter, null Einbettungen,
  /// null erkannte Texte. Immich wertet bei Videos genau dieses eine
  /// Standbild aus und schreibt die Einschränkung in seine Doku; hier lag
  /// das Bild seit dem Import auf der Platte und niemand sah es an.
  ///
  /// Die Vorschau ist zugleich die Bedingung und der Weg dorthin: Sie ist
  /// das, was `LibraryState._decodableFile` liefert. Ein Video ohne
  /// Standbild (die Extraktion scheitert an beschädigten Dateien) bleibt
  /// deshalb aussen vor, statt jede Stufe einzeln scheitern zu lassen.
  Expression<bool> _auswertbar($AssetsTable t) =>
      t.type.equals('IMAGE') |
      (t.type.equals('VIDEO') & t.previewRelativePath.isNotNull());

  Expression<bool> _ocrOffen($AssetsTable t) =>
      _auswertbar(t) &
      t.isTrashed.equals(false) &
      t.isLocked.equals(false) &
      (t.ocrScanned.equals(false) |
          (t.ocrText.isNotNull() &
              t.ocrText.equals('').not() &
              t.ocrBoxen.isNull()));

  /// Setzt das Ergebnis der KI-Bildbeschreibung (siehe FlorenceCaptioningService) –
  /// analog zu [setOcrResult].
  ///
  /// [deutsch] ist die übersetzte Fassung, sofern das Übersetzungsmodell
  /// installiert und eingeschaltet ist. Das englische Original bleibt in
  /// jedem Fall stehen.
  Future<void> setAiCaption(String assetId, String caption,
          {String? deutsch}) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(
        aiCaption: Value(caption),
        aiCaptionDe: Value(deutsch),
        aiCaptionScanned: const Value(true),
      ));

  Future<bool> uebersetzeBeschreibungen() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return row?.translateCaptions ?? false;
  }

  Future<bool> uebersetzeSucheUndTags() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return row?.translateSearchAndTags ?? false;
  }

  Future<void> setzeUebersetzeBeschreibungen(bool an) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        translateCaptions: Value(an),
      ));

  /// Ob die Karte in doppelter Auflösung zeichnet (siehe die Spalte).
  Future<bool> karteHochaufloesendWert() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    // Ohne Zeile gilt die Vorgabe – und die ist an.
    return row?.karteHochaufloesend ?? true;
  }

  Future<void> setzeKarteHochaufloesend(bool an) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        karteHochaufloesend: Value(an),
      ));

  /// Die gemerkte Tageszeit der Geländeansicht.
  Future<Tageszeit> gelaendeStimmungWert() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return tageszeit(row?.gelaendeStimmungNr ?? lichtstimmungVorgabe.index);
  }

  Future<void> setzeGelaendeStimmung(Tageszeit zeit) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        gelaendeStimmungNr: Value(zeit.index),
      ));

  /// Die Wanderobjekte eines Ausschnitts – aus der Bibliothek, sonst aus
  /// dem Netz.
  ///
  /// **Der Ausschnitt wird auf drei Nachkommastellen gerundet**, bevor er
  /// zum Schlüssel wird. Ohne diese Rundung wäre jede Abfrage neu: Der
  /// Ausschnitt einer Wanderung hängt an ihren Spurpunkten, und die
  /// gerundeten Grade unterscheiden sich in der zwölften Stelle, sobald
  /// jemand einen Punkt löscht. Drei Stellen sind rund hundert Meter –
  /// darunter lohnt kein zweiter Abruf.
  ///
  /// [holen] wird nur gerufen, wenn zu diesem Ausschnitt noch nie
  /// gefragt wurde. Liefert es `null` (kein Netz, Overpass gedrosselt),
  /// wird **nichts gemerkt**: Der Ausschnitt bleibt offen, und beim
  /// nächsten Öffnen wird es noch einmal versucht.
  Future<List<WanderpunkteData>> wanderpunkteFuer({
    required double sued,
    required double west,
    required double nord,
    required double ost,
    required Future<
                List<
                    ({
                      int osmId,
                      int artNr,
                      double breite,
                      double laenge,
                      String? name,
                      double? hoehe
                    })>?>
            Function()
        holen,
  }) async {
    String r(double w) => w.toStringAsFixed(3);
    final schluessel = '${r(sued)},${r(west)},${r(nord)},${r(ost)}';

    Future<List<WanderpunkteData>> ausDerBibliothek() => (select(wanderpunkte)
          ..where((t) =>
              t.breite.isBiggerOrEqualValue(sued) &
              t.breite.isSmallerOrEqualValue(nord) &
              t.laenge.isBiggerOrEqualValue(west) &
              t.laenge.isSmallerOrEqualValue(ost)))
        .get();

    final schonGefragt = await (select(wanderabfragen)
          ..where((t) => t.kasten.equals(schluessel)))
        .getSingleOrNull();
    if (schonGefragt != null) return ausDerBibliothek();

    final frisch = await holen();
    if (frisch == null) return ausDerBibliothek();

    await batch((b) {
      b.insertAllOnConflictUpdate(wanderpunkte, [
        for (final p in frisch)
          WanderpunkteCompanion.insert(
            osmId: Value(p.osmId),
            artNr: p.artNr,
            breite: p.breite,
            laenge: p.laenge,
            name: Value(p.name),
            hoehe: Value(p.hoehe),
          ),
      ]);
      b.insertAllOnConflictUpdate(wanderabfragen, [
        WanderabfragenCompanion.insert(
            kasten: schluessel, gefragtAm: DateTime.now()),
      ]);
    });
    return ausDerBibliothek();
  }

  /// Die gemerkte Auflage der Geländeansicht – Grund und Ebenen.
  Future<Gelaendekarte> gelaendeKarteWert() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    // Ohne Zeile gelten die Vorgaben, und die stehen genau einmal – an
    // den Spalten selbst.
    if (row == null) return const Gelaendekarte();
    return Gelaendekarte(
      grund: gelaendegrundAus(row.gelaendeGrundNr),
      wege: row.gelaendeWege,
      beschriftung: row.gelaendeBeschriftung,
      hoehenlinien: row.gelaendeHoehenlinien,
      wanderobjekte: row.gelaendeWanderobjekte,
    );
  }

  Future<void> setzeGelaendeKarte(Gelaendekarte karte) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        gelaendeGrundNr: Value(karte.grund.index),
        gelaendeWege: Value(karte.wege),
        gelaendeBeschriftung: Value(karte.beschriftung),
        gelaendeHoehenlinien: Value(karte.hoehenlinien),
        gelaendeWanderobjekte: Value(karte.wanderobjekte),
      ));

  /// Ob Videos und Live Photos beim Schweben von selbst anlaufen.
  Future<bool> schwebeVorschauWert() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return row?.schwebeVorschau ?? true;
  }

  Future<void> setzeSchwebeVorschau(bool an) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        schwebeVorschau: Value(an),
      ));

  /// Die gemerkte Spaltenwahl der Listenansicht (siehe die Spalte).
  Future<Listenspaltenwahl> listenspaltenWahl() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return Listenspaltenwahl.ausText(row?.listenspalten);
  }

  Future<void> setzeListenspalten(Listenspaltenwahl wahl) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        listenspalten: Value(wahl.alsText()),
      ));

  /// Die gemerkte Kachelstufe der Zeitleiste (siehe die Spalte).
  Future<int> zeitleisteKachelstufeWert() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return row?.zeitleisteKachelstufe ?? zeitleisteKachelstufeVorgabe;
  }

  Future<void> setzeZeitleisteKachelstufe(int stufe) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        zeitleisteKachelstufe: Value(stufe),
      ));

  /// Quadrate oder buendige Reihen – siehe [Zeitleistenform].
  Future<Zeitleistenform> zeitleisteFormWert() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return zeitleisteForm(row?.zeitleisteFormNr ?? zeitleisteFormVorgabe.index);
  }

  Future<void> setzeZeitleisteForm(Zeitleistenform form) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        zeitleisteFormNr: Value(form.index),
      ));

  /// Wonach die Zeitleiste ordnet – siehe [Rastersortierung].
  Future<Rastersortierung> zeitleisteSortierungWert() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return rastersortierung(
        row?.zeitleisteSortierungNr ?? rastersortierungVorgabe.index);
  }

  Future<void> setzeZeitleisteSortierung(Rastersortierung s) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        zeitleisteSortierungNr: Value(s.index),
      ));

  /// Die gemerkte Stammbaum-Ansicht und die Person darin (siehe die
  /// Spalten). Beide `null`, solange niemand den Baum geöffnet hat.
  Future<({String? ansicht, String? person})> stammbaumZuletzt() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return (ansicht: row?.stammbaumAnsicht, person: row?.stammbaumPerson);
  }

  Future<void> setzeStammbaumZuletzt(
          {required String ansicht, String? person}) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        stammbaumAnsicht: Value(ansicht),
        stammbaumPerson: Value(person),
      ));

  /// Die gemerkte Kartenansicht, als Text wie in der Spalte.
  Future<String?> kartenansicht() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return row?.kartenansicht;
  }

  Future<void> setzeKartenansicht(String ansicht) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        kartenansicht: Value(ansicht),
      ));

  /// Wie viele schwere Aufgaben gleichzeitig laufen dürfen (siehe die
  /// Spalte). Ohne gespeicherte Zeile gilt die Vorgabe eins.
  Future<int> maxGleichzeitigeAufgaben() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    // Eine Null oder ein negativer Wert käme nur aus einer von Hand
    // veränderten Datenbank – dann liefe gar nichts mehr, und niemand
    // fände den Grund. Eins ist die Untergrenze.
    final wert = row?.maxGleichzeitig ?? 1;
    return wert < 1 ? 1 : wert;
  }

  Future<void> setzeMaxGleichzeitigeAufgaben(int anzahl) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        maxGleichzeitig: Value(anzahl < 1 ? 1 : anzahl),
      ));

  /// Der gespeicherte CARTO-Schlüssel, oder null.
  Future<String?> cartoSchluesselWert() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    final wert = row?.cartoSchluessel?.trim();
    return wert == null || wert.isEmpty ? null : wert;
  }

  /// Legt den CARTO-Schlüssel ab. Leer oder null löscht ihn wieder.
  ///
  /// Das Leeren muss ausdrücklich als `null` in der Spalte landen und
  /// nicht als leere Zeichenkette: Sonst hinge an der Kachel-Adresse ein
  /// `?key=` ohne Wert, und der Server antwortete mit dem Wasserzeichen
  /// statt mit einer Karte – also genau dem Zustand, den die
  /// Einstellung beheben soll.
  /// Die eigene Kartenquelle, oder null, wenn keine eingerichtet ist.
  ///
  /// Alles-oder-nichts: Fehlt Adresse, Namensnennung oder die
  /// Zustimmung, gibt es keine Quelle. Eine halb ausgefuellte Quelle
  /// waere schlimmer als keine – die Karte bliebe leer, und die
  /// Namensnennung ist eine Lizenzauflage, keine Kür.
  Future<Eigenkarte?> eigeneKarteWert() async {
    final row = await (select(appSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    if (row == null) return null;
    return Eigenkarte.aus(
      name: row.eigeneKarteName,
      url: row.eigeneKarteUrl,
      nennung: row.eigeneKarteNennung,
      stufe: row.eigeneKarteStufe,
      zugestimmt: row.eigeneKarteZugestimmt,
    );
  }

  /// Legt die eigene Kartenquelle ab. `null` loescht sie wieder.
  Future<void> setzeEigeneKarteWert(Eigenkarte? karte) {
    String? sauber(String? w) {
      final t = w?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    return into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
      id: const Value(0),
      eigeneKarteName: Value(sauber(karte?.name)),
      eigeneKarteUrl: Value(sauber(karte?.url)),
      eigeneKarteNennung: Value(sauber(karte?.nennung)),
      eigeneKarteStufe: Value(karte?.stufe),
      eigeneKarteZugestimmt: Value(karte?.zugestimmt ?? false),
    ));
  }

  Future<void> setzeCartoSchluesselWert(String? schluessel) {
    final wert = schluessel?.trim();
    return into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
      id: const Value(0),
      cartoSchluessel: Value(wert == null || wert.isEmpty ? null : wert),
    ));
  }

  Future<void> setzeUebersetzeSucheUndTags(bool an) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        id: const Value(0),
        translateSearchAndTags: Value(an),
      ));

  /// Bild-Assets ohne KI-Bildbeschreibung – für den nachträglichen Lauf in
  /// den Werkzeugen, analog zu [assetsForOcrBackfill] (gesperrte Fotos
  /// ebenfalls ausgenommen, siehe dort).
  /// [alle] nimmt auch Fotos mit, die schon eine Beschreibung haben – für
  /// den Modellwechsel: Die vorhandenen Sätze stammen vom abgelösten
  /// ViT-GPT2 und sind messbar schlechter (siehe
  /// [ModelCatalog.captioningFlorence]).
  /// Bedingung für „braucht (noch) eine Bildunterschrift vom Modell".
  ///
  /// [aiCaptionEdited] schliesst aus, was von Hand geschrieben wurde – auch
  /// bei [alle]. „Alle Fotos" ist für einen Modellwechsel gedacht, nicht
  /// zum Wegwerfen getippter Sätze; wer die Maschine wieder ranlassen will,
  /// leert das Feld.
  Expression<bool> _brauchtBeschreibung(bool alle) =>
      _auswertbar(assets) &
      assets.isTrashed.equals(false) &
      assets.isLocked.equals(false) &
      assets.aiCaptionEdited.equals(false) &
      (alle ? const Constant(true) : assets.aiCaptionScanned.equals(false));

  Future<List<AssetData>> assetsForCaptionBackfill({bool alle = false}) =>
      (select(assets)..where((t) => _brauchtBeschreibung(alle))).get();

  /// Zählvariante von [assetsForCaptionBackfill], siehe [countLocationBackfill].
  Future<int> countCaptionBackfill() =>
      _countWhere(_brauchtBeschreibung(false));

  /// Bedingung für „hat eine englische Bildunterschrift, aber (noch) keine
  /// deutsche".
  ///
  /// Einmal geschrieben und von Liste wie Zählung genutzt: Die übrigen Paare
  /// hier tippen ihr WHERE zweimal, was ein eigener Test absichern muss
  /// (siehe background_task_counts_test.dart). Bei einer Bedingung mit
  /// Schalter ist das Auseinanderdriften zu wahrscheinlich, um es nur zu
  /// prüfen.
  Expression<bool> _uebersetzbareBeschreibung(bool alle) =>
      _auswertbar(assets) &
      assets.isTrashed.equals(false) &
      assets.isLocked.equals(false) &
      assets.aiCaption.isNotNull() &
      assets.aiCaption.equals('').not() &
      // Ein von Hand geschriebener Satz wird nicht maschinell überschrieben.
      assets.aiCaptionEdited.equals(false) &
      (alle ? const Constant(true) : assets.aiCaptionDe.isNull());

  /// Fotos, deren englische Bildunterschrift noch übersetzt werden kann.
  ///
  /// Eigene Aufgabe statt eines Nebenwegs der Bildbeschreibung: Wer die
  /// Übersetzung erst nachträglich einschaltet, müsste sonst das
  /// 275-MB-Modell über die ganze Bibliothek erneut laufen lassen, um an
  /// deutsche Sätze zu kommen. Das Übersetzen allein kostet gemessen
  /// 0,03–0,05 s je Satz – die Sätze sind längst da.
  Future<List<AssetData>> assetsForCaptionTranslation({bool alle = false}) =>
      (select(assets)..where((t) => _uebersetzbareBeschreibung(alle))).get();

  /// Zählvariante von [assetsForCaptionTranslation].
  Future<int> countCaptionTranslation() =>
      _countWhere(_uebersetzbareBeschreibung(false));

  /// Trägt die deutsche Fassung nach, ohne das englische Original oder das
  /// `aiCaptionScanned`-Merkmal anzufassen.
  Future<void> setAiCaptionDe(String assetId, String deutsch) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(aiCaptionDe: Value(deutsch)));

  /// Übernimmt eine von Hand geänderte Bildunterschrift.
  ///
  /// [deutsch] wählt die Spalte; leerer Text wird zu `null`. Das Merkmal
  /// [Assets.aiCaptionEdited] wird gesetzt, solange in einer der beiden
  /// Sprachen etwas steht – ist danach beides leer, fällt es wieder weg und
  /// das Foto ist erneut Kandidat für das Modell. Genau so lässt sich eine
  /// Bearbeitung zurücknehmen, ohne dafür einen eigenen Knopf zu brauchen.
  Future<void> setAiCaptionVonHand(
    String assetId,
    String? text, {
    required bool deutsch,
  }) async {
    final gesetzt = (text ?? '').trim();
    final wert = Value<String?>(gesetzt.isEmpty ? null : gesetzt);
    final vorher = await assetById(assetId);
    if (vorher == null) return;

    final englischDanach = deutsch ? (vorher.aiCaption ?? '') : gesetzt;
    final deutschDanach = deutsch ? gesetzt : (vorher.aiCaptionDe ?? '');
    final nochWas =
        englischDanach.trim().isNotEmpty || deutschDanach.trim().isNotEmpty;

    await (update(assets)..where((t) => t.id.equals(assetId)))
        .write(AssetsCompanion(
      aiCaption: deutsch ? const Value.absent() : wert,
      aiCaptionDe: deutsch ? wert : const Value.absent(),
      aiCaptionEdited: Value(nochWas),
      // Ein von Hand geschriebener Satz zählt als vorhanden – sonst stünde
      // das Foto weiter unter „Wartend", obwohl da etwas steht. Und
      // umgekehrt: Sind beide Felder leer, ist es wieder Kandidat für das
      // Modell. Das ist der einzige Weg zurück, und er braucht keinen
      // eigenen Knopf.
      //
      // Das Zurücksetzen ist hier ungefährlich, obwohl `aiCaptionScanned`
      // sonst gerade verhindern soll, dass ein Foto ohne brauchbares
      // Ergebnis endlos erneut durchs Modell läuft: Hierher kommt nur, wer
      // wirklich etwas geändert hat – ein Feld zu leeren, in dem schon
      // nichts stand, schreibt gar nicht erst.
      aiCaptionScanned: Value(nochWas),
    ));
  }

  Future<void> setSharpnessScore(String assetId, double score) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(sharpnessScore: Value(score)));

  /// Bild-Assets, denen mindestens eine der drei Auswertungen fehlt, die
  /// DASSELBE dekodierte Bild brauchen: Unschärfe, Gesichter, CLIP-Embedding.
  ///
  /// Grundlage für den gemeinsamen Durchlauf in
  /// [LibraryState.starteHintergrundanalyse]: Statt dass jede Stufe die
  /// Bibliothek für sich durchgeht und jedes Foto erneut dekodiert (gemessen
  /// rund 85 ms je Foto), wird einmal dekodiert und das Ergebnis an alle drei
  /// weitergereicht.
  ///
  /// `hatEmbedding` kommt aus dem Left Join und sagt, ob die CLIP-Stufe für
  /// dieses Foto noch etwas zu tun hat – die beiden anderen Stufen lassen
  /// sich direkt am Asset ablesen ([Assets.sharpnessScore], [Assets.facesScanned]).
  Future<List<({AssetData asset, bool hatEmbedding})>>
      assetsForCombinedImageAnalysis() async {
    final query = select(assets).join([
      leftOuterJoin(
          imageEmbeddings, imageEmbeddings.assetId.equalsExp(assets.id)),
    ])
      ..where(_auswertbar(assets) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          (assets.sharpnessScore.isNull() |
              assets.facesScanned.equals(false) |
              imageEmbeddings.assetId.isNull()));
    final rows = await query.get();
    return [
      for (final r in rows)
        (
          asset: r.readTable(assets),
          hatEmbedding: r.readTableOrNull(imageEmbeddings) != null
        ),
    ];
  }

  /// Bild-Assets ohne Schärfe-Score – für den nachträglichen Lauf in den
  /// Werkzeugen. Gesperrte Fotos ausgenommen, siehe [assetsForOcrBackfill].
  Future<List<AssetData>> assetsForBlurBackfill() => (select(assets)
        ..where((t) =>
            _auswertbar(t) &
            t.isTrashed.equals(false) &
            t.isLocked.equals(false) &
            t.sharpnessScore.isNull()))
      .get();

  /// Zählvariante von [assetsForBlurBackfill], siehe [countLocationBackfill].
  Future<int> countBlurBackfill() => _countWhere(_auswertbar(assets) &
      assets.isTrashed.equals(false) &
      assets.isLocked.equals(false) &
      assets.sharpnessScore.isNull());

  /// Assets für den XMP-Sidecar-Export (Bibliothek + Backup) – bewusst OHNE
  /// gesperrte Assets: ein Sidecar würde Beschreibung/GPS/Tags im Klartext
  /// neben die (im Falle der Bibliothek noch verschlüsselte, im Falle des
  /// Backups gar nicht erst kopierte) Originaldatei legen und damit genau
  /// die Vertraulichkeit unterlaufen, wegen der das Foto gesperrt wurde –
  /// exakt dieselbe `isLocked`-Ausnahme wie bei [assetsNotBackedUp]. Beim
  /// manuellen Export (siehe ExportService.exportAsset) gilt das NICHT: dort
  /// hat der Nutzer das Entschlüsseln/Exportieren bereits aktiv angestoßen.
  Future<List<AssetData>> assetsForXmpExport() => (select(assets)
        ..where((t) => t.isTrashed.equals(false) & t.isLocked.equals(false)))
      .get();

  /// Zählvariante von [assetsForXmpExport], siehe [countLocationBackfill].
  Future<int> countXmpExport() => _countWhere(
      assets.isTrashed.equals(false) & assets.isLocked.equals(false));

  /// Noch unbewertete Fotos/Videos für den Sichtungs-Modus (Culling) –
  /// bewusst `rating == 0` statt eines eigenen "gesichtet"-Flags: sobald ein
  /// Foto eine Bewertung (auch 0 Sterne explizit gesetzt gäbe es nicht, da
  /// die Sternereihe bei erneutem Tippen auf 0 zurücksetzt) oder eine
  /// Ablehnung (Papierkorb) erhalten hat, verschwindet es automatisch aus
  /// dieser Liste. Neueste zuerst, da frisch importierte Fotos der
  /// Hauptanwendungsfall sind.
  Future<List<AssetData>> assetsForCulling({int limit = 500}) => (select(assets)
        ..where((t) =>
            t.rating.equals(0) &
            t.isTrashed.equals(false) &
            t.isLocked.equals(false))
        ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)])
        ..limit(limit))
      .get();

  /// Setzt die per Umkehr-Geokodierung ermittelten Orts-Namen eines Assets
  /// (siehe ReverseGeocoder) – beim Import automatisch (falls der
  /// GeoNames-Datensatz bereits heruntergeladen ist) oder nachträglich über
  /// das Werkzeug "Orte auflösen".
  Future<void> setLocationNames(
    String assetId, {
    String? country,
    String? state,
    required String city,
  }) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(
        locationCountry: Value(country),
        locationState: Value(state),
        locationCity: Value(city),
      ));

  /// Fotos mit bekanntem GPS-Ort, aber noch ohne aufgelösten Orts-Namen – für
  /// das nachträgliche Auflösen (Werkzeuge) sowie den erstmaligen Lauf,
  /// nachdem der GeoNames-Datensatz heruntergeladen wurde.
  Future<List<AssetData>> assetsForLocationNameBackfill() => (select(assets)
        ..where((t) =>
            t.isTrashed.equals(false) &
            t.latitude.isNotNull() &
            t.longitude.isNotNull() &
            t.locationCountry.isNull()))
      .get();

  /// Zählvariante von [assetsForLocationNameBackfill], siehe [countLocationBackfill].
  Future<int> countLocationNameBackfill() =>
      _countWhere(assets.isTrashed.equals(false) &
          assets.latitude.isNotNull() &
          assets.longitude.isNotNull() &
          assets.locationCountry.isNull());

  /// Alle nicht gelöschten Assets mit aufgelöstem Orts-Namen (Land/
  /// Bundesland/Stadt), neueste zuerst – für die "Erkannte Orte"-Sektion im
  /// Erkunden-Tab. Die Gruppierung zu einem repräsentativen Foto je Ort
  /// (erstes Vorkommen = zeitlich aktuellstes Foto dieses Orts) übernimmt der
  /// Aufrufer, da sie reine Präsentationslogik ist.
  Future<List<AssetData>> assetsWithResolvedLocation() => (select(assets)
        ..where((t) =>
            t.isTrashed.equals(false) &
            t.isLocked.equals(false) &
            t.locationCity.isNotNull() &
            // Sonst würde das .mov eines Live-Photos als eigenes Foto am
            // selben Ort mitgezählt (siehe searchAssets).
            _isPrimaryGridEntry(t))
        ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]))
      .get();

  /// Alle nicht gelöschten Assets mit bekanntem Ort – für die Kartenansicht.
  Future<List<AssetData>> assetsWithLocation() =>
      (select(assets)..where(_mitOrt)).get();

  /// Zählvariante, siehe [countLocationBackfill].
  ///
  /// Gebraucht dort, wo nur die Frage „gibt es überhaupt einen Ort?"
  /// ansteht – die Übersicht blendet den Abschnitt sonst ein und zeigt
  /// eine leere Karte. Die Liste dafür zu laden hiesse, mehrere tausend
  /// Zeilen zu holen, um `isNotEmpty` zu fragen, und zwar ein zweites
  /// Mal neben der Karte, die sie ohnehin lädt.
  Future<int> countAssetsWithLocation() => _countWhere(_mitOrt(assets));

  Expression<bool> _mitOrt($AssetsTable t) =>
      t.isTrashed.equals(false) &
      t.isLocked.equals(false) &
      t.latitude.isNotNull() &
      t.longitude.isNotNull() &
      _isPrimaryGridEntry(t);

  /// Der Schwerpunkt aller verorteten Aufnahmen – als eine Zeile.
  ///
  /// Dieselbe Menge wie [assetsWithLocation], nur eben nicht als Menge:
  /// Wer den Mittelpunkt sucht, braucht keine 1091 vollständigen Zeilen.
  /// An einer echten Bibliothek gemessen (7988 Aufnahmen, 1091 davon
  /// verortet): **76 ms für die vollen Zeilen, 2 ms für diese Abfrage** –
  /// und der Weg, auf dem sie gebraucht wird, läuft bei jedem Start
  /// (siehe `LibraryState.trageEreignisorteNach`).
  ///
  /// `null`, wenn keine einzige Aufnahme verortet ist – dann gibt es
  /// keinen Schwerpunkt, und ein geratener wäre schlimmer als keiner.
  Future<({double breite, double laenge})?> schwerpunktVerorteterFotos() async {
    final breite = assets.latitude.avg();
    final laenge = assets.longitude.avg();
    final zeile = await (selectOnly(assets)
          ..addColumns([breite, laenge])
          ..where(assets.isTrashed.equals(false) &
              assets.isLocked.equals(false) &
              assets.latitude.isNotNull() &
              assets.longitude.isNotNull() &
              _isPrimaryGridEntry(assets)))
        .getSingle();
    final b = zeile.read(breite);
    final l = zeile.read(laenge);
    return b == null || l == null ? null : (breite: b, laenge: l);
  }

  /// Trägt für mehrere Ereignisse auf einmal die Koordinate nach.
  ///
  /// **In einem Rutsch und nicht Zeile für Zeile.** Jedes einzelne
  /// `UPDATE` ist sonst eine eigene Transaktion mit eigenem Schreiben auf
  /// die Platte. An einer Dateidatenbank gemessen, 600 Ereignisse – so
  /// viele bringt ein GEDCOM mit 300 Personen mit:
  /// **einzeln 209 ms, gesammelt 4 ms.**
  Future<void> setzeEreignisorte(
          Map<String, ({double breite, double laenge})> orte) =>
      batch((b) {
        for (final e in orte.entries) {
          b.update(
            lebensereignisse,
            LebensereignisseCompanion(
              ortBreite: Value(e.value.breite),
              ortLaenge: Value(e.value.laenge),
            ),
            where: (t) => t.id.equals(e.key),
          );
        }
      });

  /// Alle Fotos/Videos, die exakt heute vor 1, 2, 3 … Jahren aufgenommen
  /// wurden (Monat+Tag, unabhängig vom Aufnahmejahr) – für die
  /// "Erinnerungen"-Sektion im Erkunden-Tab, analog zu "Vor X Jahren" in
  /// Google Fotos/Apple Fotos.
  ///
  /// **In zwei Schritten: erst fragen, wer gemeint ist, dann die Gemeinten
  /// laden.** Der Tagesvergleich bleibt in Dart – `strftime(…, 'localtime')`
  /// wäre eine Wette auf die Zeitzonenrechnung von SQLite gegen die von
  /// Dart, und an einem ganzen Jahr durchgespielt lieferte sie zwar überall
  /// dieselbe Anzahl, aber bei gleichen Zeitstempeln eine andere
  /// Reihenfolge. Gefragt wird deshalb nur nach Kennung und Datum, und erst
  /// die Handvoll Treffer wird vollständig geladen.
  ///
  /// Vorher wurde die **ganze Bibliothek** in Objekte umgesetzt, um daraus
  /// zwei Fotos zu behalten – 56 Spalten mal 7341 Zeilen für einen Vergleich
  /// von Monat und Tag. An der gewachsenen Bibliothek gemessen, und über
  /// alle 366 Tage gegen die alte Fassung geprüft (6141 Treffer an 260
  /// Tagen, keine Abweichung):
  ///
  /// ```
  /// alles laden, in Dart filtern   250,1 ms
  /// erst Kennung und Datum          30,9 ms
  /// ```
  /// Die Erinnerungen: was heute vor Jahren entstanden ist.
  ///
  /// **Ohne geschätzte Daten.** Ein geratener Zeitstempel ist hier
  /// besonders schädlich, weil dieser Abschnitt aus dem Datum eine
  /// Behauptung macht: „vor 20 Jahren, an genau diesem Tag". An der
  /// echten Bibliothek liegen 948 Aufnahmen auf einem einzigen erfundenen
  /// Zeitpunkt – am 27. August wären sie alle auf einmal erschienen, und
  /// keine einzige davon entstand an diesem Tag.
  ///
  /// **Die Marke allein genuegt nicht.** `datum_geschaetzt` wird erst
  /// gesetzt, wenn der Lauf „Herkunft der Aufnahmedaten" ueber die
  /// Bibliothek gegangen ist – an der echten stand sie am 10.09.2026 bei
  /// **0**, und die Abwehr oben war damit wirkungslos: Am 27. August
  /// haette dieser Abschnitt 1103 Aufnahmen gezeigt, 1096 davon mit einer
  /// erfundenen Uhrzeit.
  ///
  /// Deshalb zusaetzlich der Verdacht selbst, der keinen Lauf braucht:
  /// ein Zeitstempel auf voller Ortszeit-Stunde (siehe
  /// [countAuffaelligeAufnahmedaten]). Der Preis dafuer sind die rund
  /// **zwei** Aufnahmen, die eine volle Stunde zufaellig treffen; der
  /// Ertrag sind die 1095, die es nicht zufaellig tun.
  Future<List<AssetData>> assetsOnThisDay(DateTime today) async {
    final schlank = selectOnly(assets)
      ..addColumns([assets.id, assets.fileCreatedAt])
      ..where(assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          assets.datumGeschaetzt.equals(false) &
          _nichtAufVollerStunde() &
          _isPrimaryGridEntry(assets));
    final treffer = <String>[];
    for (final zeile in await schlank.get()) {
      // Über `rawData` und nicht über `zeile.read(assets.fileCreatedAt)`:
      // Der bequeme Weg schlägt jede Spalte über ihren Typ-Umsetzer nach,
      // und bei 7341 Zeilen kostete allein das die Hälfte der Zeit (58 ms
      // gegen 31 ms). Die Namen sind die, die drift der Abfrage gibt –
      // stimmten sie nicht, führe das Lesen sofort in einen Fehler, und
      // [assetsOnThisDayGleichAlterWeg] fängt das im Prüfstand ab.
      final wann = DateTime.fromMillisecondsSinceEpoch(
          zeile.rawData.read<int>('assets.file_created_at') * 1000);
      if (wann.month == today.month &&
          wann.day == today.day &&
          wann.year != today.year) {
        treffer.add(zeile.rawData.read<String>('assets.id'));
      }
    }
    if (treffer.isEmpty) return const [];
    final geladen =
        await (select(assets)..where((t) => t.id.isIn(treffer))).get();
    return geladen..sort((a, b) => b.fileCreatedAt.compareTo(a.fileCreatedAt));
  }

  /// Was in diesem **Monat** frueherer Jahre entstanden ist – ohne den
  /// heutigen Tag, denn den zeigt [assetsOnThisDay].
  ///
  /// **Warum es die zweite, weitere Frage braucht.** Der Tagesabschnitt
  /// trifft an der echten Bibliothek nur an **261 von 365** Tagen etwas,
  /// und an 107 davon sind es hoechstens drei Aufnahmen. An den uebrigen
  /// 104 Tagen verschwand der Abschnitt wortlos – heute, am 12.
  /// September, war das so. Der Monat ist die naechstgroessere Frage, die
  /// fast immer eine Antwort hat, und sie ist genauso wahr: „im
  /// September vor 13 Jahren" behauptet nichts ueber den Tag.
  ///
  /// [hoechstensJeJahr] deckelt, was ein einzelner Jahrgang beisteuert –
  /// ohne das waere ein Monat mit 900 Aufnahmen kein Rueckblick, sondern
  /// die Zeitleiste.
  Future<List<AssetData>> assetsInDiesemMonat(DateTime heute,
      {int hoechstensJeJahr = 12}) async {
    final schlank = selectOnly(assets)
      ..addColumns([assets.id, assets.fileCreatedAt])
      ..where(assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          assets.datumGeschaetzt.equals(false) &
          _nichtAufVollerStunde() &
          _isPrimaryGridEntry(assets));
    final jeJahr = <int, List<String>>{};
    for (final zeile in await schlank.get()) {
      final wann = DateTime.fromMillisecondsSinceEpoch(
          zeile.rawData.read<int>('assets.file_created_at') * 1000);
      if (wann.month != heute.month || wann.year == heute.year) continue;
      if (wann.day == heute.day) continue;
      final liste = jeJahr.putIfAbsent(wann.year, () => []);
      if (liste.length < hoechstensJeJahr) {
        liste.add(zeile.rawData.read<String>('assets.id'));
      }
    }
    final treffer = [for (final l in jeJahr.values) ...l];
    if (treffer.isEmpty) return const [];
    final geladen =
        await (select(assets)..where((t) => t.id.isIn(treffer))).get();
    return geladen..sort((a, b) => b.fileCreatedAt.compareTo(a.fileCreatedAt));
  }

  /// Ersetzt Original-Datei (Pfad + Prüfsumme) eines Assets nach einer
  /// Bildbearbeitung (Zuschneiden/Drehen/Spiegeln, siehe ImageEditorScreen).
  /// Löscht eine ggf. vorhandene konvertierte Vorschau (HEIC/RAW & Co.):
  /// nach der Bearbeitung ist die neue Originaldatei selbst bereits ein
  /// direkt darstellbares JPEG.
  Future<void> setEditedAssetFile(String assetId,
          {required String relativePath, required String checksum}) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(
        relativePath: Value(relativePath),
        checksum: Value(checksum),
        previewRelativePath: const Value(null),
        // Ein evtl. vorhandenes entwickeltes Bild wurde für die ALTE
        // Pixel-Grundlage berechnet (vor Zuschnitt/Drehung) und würde nach
        // dem destruktiven Bearbeiten falschen Inhalt zeigen – die
        // DevelopSettings-Zeile selbst bleibt bewusst bestehen (der Nutzer
        // müsste sie sonst nach jedem Zuschnitt neu einstellen), nur der
        // veraltete gerenderte Cache wird hier zurückgesetzt.
        developedRelativePath: const Value(null),
      ));

  /// Setzt den ursprünglichen, für Menschen lesbaren Dateinamen – u.a. nach
  /// einem Restore aus einem Backup nötig: der Reimport dort liest den
  /// Namen zunächst aus dem Backup-Pfad (`originals/{yyyy}/{mm}/{id}.ext`,
  /// also der Asset-UUID statt des Originalnamens), erst
  /// [BackupService._applyMetadataExport] korrigiert ihn anschließend
  /// anhand von metadata.json.
  Future<void> setOriginalFileName(String assetId, String name) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(originalFileName: Value(name)));

  // ---------------------------------------------------------------------
  // Live Photos (Standbild <-> Video-Verknüpfung)
  // ---------------------------------------------------------------------

  /// Alle noch nicht verknüpften, nicht gelöschten Assets eines Typs – für
  /// den Abgleich beim Import, ob ein passender Live-Photo-Partner (gleicher
  /// Dateiname, anderer Typ) schon in der Bibliothek liegt.
  Future<List<AssetData>> unlinkedAssetsOfType(String type) => (select(assets)
        ..where((t) =>
            t.type.equals(type) &
            t.isTrashed.equals(false) &
            t.linkedAssetId.isNull()))
      .get();

  /// Zählvariante von [unlinkedAssetsOfType], siehe [countLocationBackfill].
  /// Wie viele Aufnahmen dieser Art es gibt – für die Anzeige „betrifft N"
  /// bei der Prüfung der Dateiarten.
  Future<int> countAssetsOfType(String type) =>
      _countWhere(assets.type.equals(type));

  Future<int> countUnlinkedAssetsOfType(String type) =>
      _countWhere(assets.type.equals(type) &
          assets.isTrashed.equals(false) &
          assets.linkedAssetId.isNull());

  Future<void> linkAssets(String idA, String idB) async {
    await (update(assets)..where((t) => t.id.equals(idA)))
        .write(AssetsCompanion(linkedAssetId: Value(idB)));
    await (update(assets)..where((t) => t.id.equals(idB)))
        .write(AssetsCompanion(linkedAssetId: Value(idA)));
  }

  // ---------------------------------------------------------------------
  // Serien-/Burst-Stapel (siehe StackReviewScreen, findBurstGroups)

  Future<Set<String>> verworfeneSerienvorschlaege() async =>
      {for (final z in await select(verworfeneSerien).get()) z.schluessel};

  Future<void> verwirfSerienvorschlag(String schluessel) =>
      into(verworfeneSerien).insertOnConflictUpdate(
          VerworfeneSerienCompanion.insert(
              schluessel: schluessel, verworfenAm: DateTime.now()));

  /// Die Einbettungen, die für einen Serienvorschlag überhaupt in Frage
  /// kommen: alles, was nicht schon in einem Stapel liegt.
  ///
  /// Ohne diese Einschränkung fände der nächste Lauf dieselben Gruppen
  /// erneut – die Mitglieder eines Stapels sind aus dem Raster
  /// verschwunden, aus der Einbettungstabelle aber nicht.
  Future<Set<String>> bereitsGestapelt() async {
    final zeilen = await (selectOnly(assets)
          ..addColumns([assets.id])
          ..where(assets.stackId.isNotNull()))
        .get();
    return {for (final z in zeilen) z.read(assets.id)!};
  }
  // ---------------------------------------------------------------------

  /// Fasst [assetIds] zu einem neuen Stapel zusammen: [coverAssetId] (muss in
  /// [assetIds] enthalten sein) wird Titelbild (`isStackCover = true`,
  /// `stackSize` = Gesamtzahl) und bleibt allein in Timeline & Co. sichtbar
  /// (siehe die `stackId`/`isStackCover`-Filter dort), die übrigen
  /// Mitglieder werden aus der Rasteransicht ausgeblendet. [stackId] wird
  /// vom Aufrufer erzeugt (Muster wie `createSavedSearch`/`createAlbum`).
  Future<void> createStack(
      String stackId, List<String> assetIds, String coverAssetId) async {
    assert(assetIds.contains(coverAssetId));
    await batch((b) {
      for (final id in assetIds) {
        b.update(
          assets,
          AssetsCompanion(
            stackId: Value(stackId),
            isStackCover: Value(id == coverAssetId),
            stackSize:
                id == coverAssetId ? Value(assetIds.length) : const Value(null),
          ),
          where: (t) => t.id.equals(id),
        );
      }
    });
  }

  /// Löst einen Stapel wieder auf ("Serie auflösen") – alle Mitglieder
  /// werden wieder einzeln sichtbar.
  Future<void> unstackAssets(String stackId) =>
      (update(assets)..where((t) => t.stackId.equals(stackId))).write(
          const AssetsCompanion(
              stackId: Value(null),
              isStackCover: Value(false),
              stackSize: Value(null)));

  Future<List<AssetData>> assetsInStack(String stackId) =>
      (select(assets)..where((t) => t.stackId.equals(stackId))).get();

  /// Alle Assets (Fotos und Videos), die für eine (erneute) Thumbnail-/
  /// Vorschau-Erzeugung infrage kommen. Bei [onlyMissing] nur Assets ohne
  /// Thumbnail (z.B. HEIC-Fotos, die vor Einbindung der nativen
  /// Bildkonvertierung importiert wurden, oder Videos, die vor Einführung
  /// der Video-Thumbnail-Erzeugung importiert wurden).
  /// Assets, für die sich ein Vorschaubild erzeugen lässt.
  ///
  /// Gesperrte bleiben aussen vor. Der Kommentar stand hier früher
  /// andersherum („läuft absichtlich auch über gesperrte, die Ansicht
  /// braucht Thumbnails") – das ging nicht auf: Bei einem gesperrten Foto
  /// ist die Originaldatei verschlüsselt, das Dekodieren scheitert
  /// zwangsläufig, und [ImportService.generateThumbnailAndPreview] kehrt
  /// ohne Ergebnis zurück, bevor überhaupt etwas geschrieben wird. Es kam
  /// also nie ein Vorschaubild dabei heraus – nur für jedes gesperrte Foto
  /// ein vollständiges Lesen der Datei und ein Isolate-Durchlauf ins Leere.
  /// Das Vorschaubild eines gesperrten Fotos ist ohnehin mitverschlüsselt
  /// und wird beim Entsperren wieder lesbar.
  Future<List<AssetData>> assetsForThumbnailRegen({required bool onlyMissing}) {
    final query = select(assets)
      ..where((t) => t.isTrashed.equals(false) & t.isLocked.equals(false));
    if (onlyMissing) {
      query.where(_fehlendeVorschau);
    }
    return query.get();
  }

  /// Zählvariante von [assetsForThumbnailRegen], siehe [countLocationBackfill].
  Future<int> countThumbnailRegen({required bool onlyMissing}) =>
      _countWhere(onlyMissing
          ? assets.isTrashed.equals(false) &
              assets.isLocked.equals(false) &
              _fehlendeVorschau(assets)
          : assets.isTrashed.equals(false) & assets.isLocked.equals(false));

  /// „Fehlt hier ein Vorschaubild?"
  ///
  /// Bei einem Video zählt zusätzlich die **Vorschau**, nicht nur die
  /// Miniatur: Erst das grosse Standbild macht es auswertbar (siehe
  /// [_auswertbar]). Die 440 Videos der Prüfbibliothek hatten fast alle
  /// eine Miniatur und keines eine Vorschau – ohne diese Unterscheidung
  /// hätte „Fehlende erzeugen" sie für erledigt gehalten.
  ///
  /// Bei einem Bild dagegen ist eine fehlende Vorschau der Normalfall: Sie
  /// entsteht nur für HEIC und RAW.
  Expression<bool> _fehlendeVorschau($AssetsTable t) =>
      t.thumbnailRelativePath.isNull() |
      (t.type.equals('VIDEO') & t.previewRelativePath.isNull());

  /// Für die Bibliotheks-Integritätsprüfung (IntegrityCheckScreen): bewusst
  /// vollständig ungefiltert (auch gelöscht/gesperrt), da all diese Assets
  /// weiterhin echte Dateien auf der Platte referenzieren, die geprüft
  /// werden müssen.
  Future<List<AssetData>> allAssetsForIntegrityCheck() => select(assets).get();

  /// Löscht NUR den (dann fehlenden) Datei-Pfad einer abgeleiteten Datei,
  /// OHNE die zugehörigen Einstellungen zu verwerfen – anders als
  /// [resetDevelopSettings]/[resetVideoTrim], die bewusst auch die
  /// Regler-Werte zurücksetzen. Für die Bibliotheks-Integritätsprüfung: das
  /// Original ist ja noch da, die Datei lässt sich (mit denselben
  /// Einstellungen) einfach erneut rendern.
  Future<void> clearMissingThumbnailPath(String assetId) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(const AssetsCompanion(thumbnailRelativePath: Value(null)));

  Future<void> clearMissingPreviewPath(String assetId) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(const AssetsCompanion(previewRelativePath: Value(null)));

  Future<void> clearMissingDevelopedPath(String assetId) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(const AssetsCompanion(developedRelativePath: Value(null)));

  Future<void> clearMissingTrimmedPath(String assetId) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(const AssetsCompanion(trimmedRelativePath: Value(null)));

  Future<void> clearMissingRestoredPath(String assetId) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(const AssetsCompanion(restoredRelativePath: Value(null)));

  /// Löscht nur den fehlenden Crop-Pfad eines Gesichts, die Zuordnung zur
  /// Person und das Embedding bleiben erhalten (der Crop ist nur eine
  /// zwischengespeicherte Vorschau).
  Future<void> clearMissingFaceCropPath(String faceId) =>
      (update(faces)..where((t) => t.id.equals(faceId)))
          .write(const FacesCompanion(cropRelativePath: Value(null)));

  /// Aufnahmen, die als Video geführt werden – Anwärter dafür, dass der
  /// Name etwas anderes behauptet als die Bytes (siehe
  /// `LibraryState.repariereDateiarten`).
  Future<List<AssetData>> alsVideoGefuehrte() =>
      (select(assets)..where((t) => t.type.equals('VIDEO'))).get();

  /// Trägt für eine Aufnahme die Art ein, die ihre Bytes hergeben, und
  /// nimmt dabei alles zurück, was aus der falschen Annahme entstanden ist.
  ///
  /// Miniatur und Dauer werden ausdrücklich geleert: Die Miniatur kam vom
  /// Videowandler und ist bei diesen Dateien nie entstanden, und eine
  /// Laufzeit hat ein Standbild nicht.
  Future<void> setzeDateiart(String assetId, String art,
          {required String dateiformat}) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(
        type: Value(art),
        dateiformat: Value(dateiformat),
        thumbnailRelativePath: const Value(null),
        previewRelativePath: const Value(null),
        durationSeconds: const Value(null),
      ));

  Future<void> updateThumbnailInfo(
    String assetId, {
    String? thumbnailRelativePath,
    String? previewRelativePath,
    int? widthPx,
    int? heightPx,
    double? durationSeconds,
  }) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(
        thumbnailRelativePath: thumbnailRelativePath != null
            ? Value(thumbnailRelativePath)
            : const Value.absent(),
        previewRelativePath: previewRelativePath != null
            ? Value(previewRelativePath)
            : const Value.absent(),
        widthPx: widthPx != null ? Value(widthPx) : const Value.absent(),
        heightPx: heightPx != null ? Value(heightPx) : const Value.absent(),
        durationSeconds: durationSeconds != null
            ? Value(durationSeconds)
            : const Value.absent(),
      ));

  // -----------------------------------------------------------------------
  // Nicht-destruktive Entwicklung (DevelopScreen)
  // -----------------------------------------------------------------------

  Future<DevelopSettingsData?> developSettingsForAsset(String assetId) =>
      (select(developSettings)..where((t) => t.assetId.equals(assetId)))
          .getSingleOrNull();

  /// Speichert die Entwicklungs-Einstellungen und das dazu gerenderte Bild
  /// in einer Transaktion, damit `Assets.developedRelativePath` nie auf
  /// eine DevelopSettings-Zeile zeigt, die (durch einen Fehler mittendrin)
  /// gar nicht existiert. Schiebt zuvor den bisherigen Stand (falls
  /// vorhanden) in [DevelopHistory] – ein einfacher, linearer Verlauf ohne
  /// Sonderfall-Restore-Pfad: lädt der Nutzer später einen Verlaufs-Eintrag
  /// in die Regler zurück und speichert erneut, landet der gerade ersetzte
  /// Stand wieder ganz normal hier in der Historie.
  Future<void> saveDevelopResult(
    String assetId, {
    required DevelopSettingsCompanion settings,
    required String developedRelativePath,
  }) =>
      transaction(() async {
        final previous = await (select(developSettings)
              ..where((t) => t.assetId.equals(assetId)))
            .getSingleOrNull();
        if (previous != null) {
          await into(developHistory).insert(DevelopHistoryCompanion.insert(
            assetId: assetId,
            exposure: previous.exposure,
            temperature: Value(previous.temperature),
            tint: Value(previous.tint),
            contrast: previous.contrast,
            shadows: previous.shadows,
            highlights: Value(previous.highlights),
            sharpness: previous.sharpness,
            noiseReduction: previous.noiseReduction,
            lensCorrectionEnabled: previous.lensCorrectionEnabled,
            toneCurveJson: Value(previous.toneCurveJson),
            colorMixerJson: Value(previous.colorMixerJson),
            createdAt: DateTime.now(),
          ));
          await _pruneDevelopHistory(assetId);
        }
        await into(developSettings).insertOnConflictUpdate(settings);
        await (update(assets)..where((t) => t.id.equals(assetId))).write(
            AssetsCompanion(
                developedRelativePath: Value(developedRelativePath)));
      });

  /// Begrenzt [DevelopHistory] auf die neuesten [keep] Einträge pro Asset,
  /// damit die Tabelle bei Nutzern, die häufig speichern, nicht unbegrenzt
  /// wächst. Sortiert nach der Auto-Increment-`id` statt `createdAt` – die
  /// steigt garantiert streng mit jedem Insert, während zwei sehr schnell
  /// aufeinanderfolgende Speicher-Vorgänge (z.B. in Tests) denselben
  /// `DateTime.now()`-Millisekundenwert treffen könnten.
  Future<void> _pruneDevelopHistory(String assetId, {int keep = 10}) async {
    final rows = await (select(developHistory)
          ..where((t) => t.assetId.equals(assetId))
          ..orderBy([(t) => OrderingTerm.desc(t.id)]))
        .get();
    if (rows.length <= keep) return;
    final idsToDelete = rows.skip(keep).map((r) => r.id).toList();
    await (delete(developHistory)..where((t) => t.id.isIn(idsToDelete))).go();
  }

  /// Vergangene Entwickeln-Stände eines Assets, neueste zuerst (siehe
  /// [_pruneDevelopHistory] zur Sortierung nach `id` statt `createdAt`) –
  /// für den "Verlauf"-Einstieg im DevelopScreen.
  Future<List<DevelopHistoryData>> developHistoryForAsset(String assetId) =>
      (select(developHistory)
            ..where((t) => t.assetId.equals(assetId))
            ..orderBy([(t) => OrderingTerm.desc(t.id)]))
          .get();

  /// Setzt ein Asset auf unentwickelt zurück (Regler-"Zurücksetzen") – der
  /// Aufrufer löscht die zugehörige gerenderte Datei selbst von der Platte.
  Future<void> resetDevelopSettings(String assetId) => transaction(() async {
        await (delete(developSettings)..where((t) => t.assetId.equals(assetId)))
            .go();
        await (update(assets)..where((t) => t.id.equals(assetId)))
            .write(const AssetsCompanion(developedRelativePath: Value(null)));
      });

  /// Alle entwickelten Assets samt ihrer Einstellungen – für das
  /// "Entwickelte Fotos neu rendern"-Werkzeug (z.B. nach einer Änderung an
  /// der Render-Logik selbst).
  Future<List<(AssetData, DevelopSettingsData)>>
      assetsWithDevelopSettings() async {
    final query = select(assets).join([
      innerJoin(developSettings, developSettings.assetId.equalsExp(assets.id)),
    ])
      // isLocked ausgeschlossen, damit das Bulk-Werkzeug ("Entwickelte
      // Fotos neu rendern") nie versucht, aus der verschlüsselten
      // Originaldatei eines gesperrten Assets zu rendern und das Ergebnis
      // unverschlüsselt in developed/ zu schreiben.
      ..where(assets.isTrashed.equals(false) & assets.isLocked.equals(false));
    final rows = await query.get();
    return rows
        .map((r) => (r.readTable(assets), r.readTable(developSettings)))
        .toList();
  }

  /// Zählvariante von [assetsWithDevelopSettings], siehe [countLocationBackfill].
  Future<int> countAssetsWithDevelopSettings() async {
    final countExpr = assets.id.count();
    final query = selectOnly(assets).join([
      innerJoin(developSettings, developSettings.assetId.equalsExp(assets.id)),
    ])
      ..addColumns([countExpr])
      ..where(assets.isTrashed.equals(false) & assets.isLocked.equals(false));
    final row = await query.getSingle();
    return row.read<int>(countExpr) ?? 0;
  }

  // -----------------------------------------------------------------------
  // KI-Objektmasken (MaskEditor, SegmentationService)
  // -----------------------------------------------------------------------

  /// Masken eines Assets in Erstellreihenfolge – der native Renderer
  /// (developImage) legt sie in genau dieser Reihenfolge übereinander.
  Future<List<DevelopMaskData>> masksForAsset(String assetId) =>
      (select(developMasks)
            ..where((t) => t.assetId.equals(assetId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  /// Für die Bibliotheks-Integritätsprüfung – ein einzelner Full-Table-Select
  /// statt N+1-Abfragen pro Asset.
  Future<List<DevelopMaskData>> allDevelopMasks() => select(developMasks).get();

  Future<int> createDevelopMask(DevelopMasksCompanion mask) =>
      into(developMasks).insert(mask);

  /// Aktualisiert nur die Regler-Werte einer bereits vorhandenen Maske
  /// (Label/Maskendatei bleiben unverändert) – beim Speichern im
  /// Entwickeln-Screen, analog zu [saveDevelopResult] für die globalen
  /// Regler.
  Future<void> updateDevelopMaskAdjustments(
          int id, DevelopMasksCompanion adjustments) =>
      (update(developMasks)..where((t) => t.id.equals(id))).write(adjustments);

  /// Aktualisiert die Geometrie einer Vektor-Maske nach erneutem Bearbeiten
  /// ihrer Form (siehe MaskShapeDefinition/vector_mask_service.dart) – die
  /// gerenderte PNG-Datei selbst überschreibt der Aufrufer direkt (Muster
  /// wie [createDevelopMask]), hier wird nur die Quelle der Wahrheit
  /// (`shapeDefinitionJson`) aktualisiert.
  Future<void> updateDevelopMaskShape(int id, String shapeDefinitionJson) =>
      (update(developMasks)..where((t) => t.id.equals(id))).write(
          DevelopMasksCompanion(
              shapeDefinitionJson: Value(shapeDefinitionJson)));

  /// "Maske entfernen" – der Aufrufer löscht die zugehörige PNG-Datei selbst
  /// von der Platte (Muster wie [resetDevelopSettings]/[resetVideoTrim]).
  Future<void> deleteDevelopMask(int id) =>
      (delete(developMasks)..where((t) => t.id.equals(id))).go();

  // -----------------------------------------------------------------------
  // KI-Restaurierung (RestoreQueueService, RestoreService)
  // -----------------------------------------------------------------------

  Future<void> createRestoreJob(RestoreJobsCompanion job) =>
      into(restoreJobs).insert(job);

  /// Alle Aufträge, neueste zuerst – Grundlage für den Warteschlangen-
  /// Indikator (nur `queued`/`running` gefiltert vom Aufrufer) und den
  /// Warteschlangen-Screen (alle Status).
  Stream<List<RestoreJobData>> watchRestoreJobs() =>
      (select(restoreJobs)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  /// Der älteste noch wartende Auftrag – FIFO, ein Auftrag gleichzeitig
  /// (siehe RestoreQueueService: parallele ONNX-Inferenzen würden sich nur
  /// um CPU/GPU streiten).
  Future<RestoreJobData?> nextQueuedRestoreJob() => (select(restoreJobs)
        ..where((t) => t.status.equals('queued'))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
        ..limit(1))
      .getSingleOrNull();

  /// Bereits wartender/laufender Auftrag für dieses Asset, falls vorhanden
  /// – verhindert in [RestoreQueueService.enqueue] doppelte Aufträge für
  /// dasselbe Foto (z.B. durch einen Doppelklick).
  Future<RestoreJobData?> activeRestoreJobForAsset(String assetId) =>
      (select(restoreJobs)
            ..where((t) =>
                t.assetId.equals(assetId) &
                t.status.isIn(['queued', 'running']))
            ..limit(1))
          .getSingleOrNull();

  Future<void> updateRestoreJobProgress(
          String id, int tilesDone, int tilesTotal) =>
      (update(restoreJobs)..where((t) => t.id.equals(id))).write(
        RestoreJobsCompanion(
            tilesDone: Value(tilesDone), tilesTotal: Value(tilesTotal)),
      );

  Future<void> markRestoreJobStatus(String id, String status,
          {String? errorMessage}) =>
      (update(restoreJobs)..where((t) => t.id.equals(id))).write(
        RestoreJobsCompanion(
          status: Value(status),
          errorMessage: Value(errorMessage),
          // Beim Anlaufen die Startzeit setzen, beim Zurücksetzen auf
          // „wartet" wieder löschen: Ein hängengebliebener Auftrag wird
          // neu eingereiht (siehe resetStuckRunningRestoreJobs), und
          // seine alte Startzeit ergäbe beim zweiten Anlauf eine
          // Restzeit von mehreren Stunden.
          startedAt: switch (status) {
            'running' => Value(DateTime.now()),
            'queued' => const Value(null),
            _ => const Value.absent(),
          },
          completedAt: Value(status == 'queued' || status == 'running'
              ? null
              : DateTime.now()),
        ),
      );

  Future<void> deleteRestoreJob(String id) =>
      (delete(restoreJobs)..where((t) => t.id.equals(id))).go();

  /// Schließt einen erfolgreichen Auftrag transaktional ab: setzt
  /// `Assets.restoredRelativePath` UND markiert den Auftrag `done` in einem
  /// Zug (Muster: [saveDevelopResult]) – verhindert einen inkonsistenten
  /// Zwischenstand (Job "done", aber Asset zeigt noch nicht auf das
  /// Ergebnis, oder umgekehrt).
  Future<void> completeRestoreJob(
          String jobId, String assetId, String restoredRelativePath) =>
      transaction(() async {
        await (update(assets)..where((t) => t.id.equals(assetId))).write(
            AssetsCompanion(restoredRelativePath: Value(restoredRelativePath)));
        await (update(restoreJobs)..where((t) => t.id.equals(jobId))).write(
            RestoreJobsCompanion(
                status: const Value('done'),
                completedAt: Value(DateTime.now())));
      });

  /// Crash-Safety: setzt beim App-Start jeden Auftrag, der beim letzten
  /// Beenden noch `running` war (die App wurde mitten in der Verarbeitung
  /// beendet/ist abgestürzt), zurück auf `queued` – ohne Teil-Kacheln zu
  /// persistieren, läuft er beim nächsten Warteschlangen-Durchlauf komplett
  /// neu. Siehe LibraryState.initialize().
  Future<void> resetStuckRunningRestoreJobs() =>
      (update(restoreJobs)..where((t) => t.status.equals('running'))).write(
        const RestoreJobsCompanion(
            status: Value('queued'), tilesDone: Value(0), tilesTotal: Value(0)),
      );

  // -----------------------------------------------------------------------
  // Nicht-destruktiver Video-Zuschnitt (VideoTrimScreen)
  // -----------------------------------------------------------------------

  Future<VideoTrimData?> videoTrimForAsset(String assetId) =>
      (select(videoTrims)..where((t) => t.assetId.equals(assetId)))
          .getSingleOrNull();

  /// Speichert Start/Ende und das dazu geschnittene Video in einer
  /// Transaktion, analog zu [saveDevelopResult] – `Assets.trimmedRelativePath`
  /// zeigt nie auf eine VideoTrims-Zeile, die (durch einen Fehler
  /// mittendrin) gar nicht existiert.
  Future<void> saveVideoTrim(
    String assetId, {
    required double startSeconds,
    required double endSeconds,
    required String trimmedRelativePath,
  }) =>
      transaction(() async {
        await into(videoTrims)
            .insertOnConflictUpdate(VideoTrimsCompanion.insert(
          assetId: assetId,
          startSeconds: startSeconds,
          endSeconds: endSeconds,
          updatedAt: DateTime.now(),
        ));
        await (update(assets)..where((t) => t.id.equals(assetId))).write(
            AssetsCompanion(trimmedRelativePath: Value(trimmedRelativePath)));
      });

  /// Setzt ein Video auf den Originalausschnitt zurück (Zuschneiden-
  /// "Zurücksetzen") – der Aufrufer löscht die zugehörige geschnittene
  /// Datei selbst von der Platte.
  Future<void> resetVideoTrim(String assetId) => transaction(() async {
        await (delete(videoTrims)..where((t) => t.assetId.equals(assetId)))
            .go();
        await (update(assets)..where((t) => t.id.equals(assetId)))
            .write(const AssetsCompanion(trimmedRelativePath: Value(null)));
      });

  // -----------------------------------------------------------------------
  // Alben
  // -----------------------------------------------------------------------

  Stream<List<AlbumData>> watchAlbums() =>
      (select(albums)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<void> createAlbum(AlbumsCompanion album) => into(albums).insert(album);

  Future<void> addAssetsToAlbum(String albumId, List<String> assetIds) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        albumAssets,
        assetIds.map(
            (id) => AlbumAssetsCompanion.insert(albumId: albumId, assetId: id)),
      );
    });
  }

  /// Setzt das Titelbild eines Albums – `null` nimmt die Wahl zurück.
  ///
  /// Die Spalte gab es seit jeher, gelesen und geschrieben hat sie
  /// niemand: Ein Album war in der Übersicht ein Symbol und ein Name.
  Future<void> setzeAlbumTitelbild(String albumId, String? assetId) =>
      (update(albums)..where((t) => t.id.equals(albumId)))
          .write(AlbumsCompanion(coverAssetId: Value(assetId)));

  /// Das Bild, mit dem ein Album in der Übersicht steht.
  ///
  /// Erst das gewählte Titelbild; ist keines gewählt – oder liegt das
  /// gewählte inzwischen im Papierkorb, ist gesperrt oder gar nicht mehr
  /// im Album –, die neueste Aufnahme darin. `null` nur bei einem leeren
  /// Album. Ein Titelbild, das aus dem Album entfernt wurde, würde sonst
  /// weiter dafür werben.
  Future<AssetData?> albumTitelbild(AlbumData album) async {
    final gewaehlt = album.coverAssetId;
    if (gewaehlt != null) {
      final treffer = await (select(assets).join([
        innerJoin(albumAssets, albumAssets.assetId.equalsExp(assets.id)),
      ])
            ..where(albumAssets.albumId.equals(album.id) &
                assets.id.equals(gewaehlt) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false)))
          .getSingleOrNull();
      final zeile = treffer?.readTableOrNull(assets);
      if (zeile != null) return zeile;
    }
    final erste = await (select(assets).join([
      innerJoin(albumAssets, albumAssets.assetId.equalsExp(assets.id)),
    ])
          ..where(albumAssets.albumId.equals(album.id) &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false))
          ..orderBy([OrderingTerm.desc(assets.fileCreatedAt)])
          ..limit(1))
        .getSingleOrNull();
    return erste?.readTableOrNull(assets);
  }

  Future<void> removeAssetFromAlbum(String albumId, String assetId) => (delete(
          albumAssets)
        ..where((t) => t.albumId.equals(albumId) & t.assetId.equals(assetId)))
      .go();

  Stream<List<AssetData>> watchAlbumAssets(String albumId) {
    final query = select(assets).join([
      innerJoin(albumAssets, albumAssets.assetId.equalsExp(assets.id)),
    ])
      ..where(albumAssets.albumId.equals(albumId))
      ..where(assets.isTrashed.equals(false))
      ..where(assets.isLocked.equals(false))
      ..where(_isPrimaryGridEntry(assets))
      ..orderBy([OrderingTerm.desc(assets.fileCreatedAt)]);
    return _gedrosselt(
      () => query.map((r) => r.readTable(assets)),
      TableUpdateQuery.allOf([
        TableUpdateQuery.onTable(assets),
        TableUpdateQuery.onTable(albumAssets),
      ]),
    );
  }

  /// Einmalige (nicht-reaktive) Variante von [watchAlbumAssets], u.a. für den
  /// Metadaten-Export beim Backup und die Album-Vorschau im Erkunden-Tab –
  /// deshalb ebenfalls ohne gelöschte/gesperrte Assets, analog zu
  /// [watchAlbumAssets].
  Future<List<AssetData>> assetsInAlbumOnce(String albumId) async {
    final query = select(assets).join([
      innerJoin(albumAssets, albumAssets.assetId.equalsExp(assets.id)),
    ])
      ..where(albumAssets.albumId.equals(albumId) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          _isPrimaryGridEntry(assets));
    final rows = await query.get();
    return rows.map((r) => r.readTable(assets)).toList();
  }

  // -----------------------------------------------------------------------
  // Tags & Textsuche
  // -----------------------------------------------------------------------

  Future<String> ensureTag(String name) async {
    final existing = await (select(tags)..where((t) => t.name.equals(name)))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    final id = name.hashCode.toRadixString(36) +
        DateTime.now().microsecondsSinceEpoch.toString();
    await into(tags).insert(TagsCompanion.insert(id: id, name: name));
    return id;
  }

  /// Hängt ein Schlagwort an ein Foto.
  ///
  /// **Hand schlägt KI, nie andersherum** (siehe [Tagquelle]). Wer einen
  /// Begriff selbst vergibt, übernimmt ihn damit – auch wenn ihn zuvor die
  /// Bilderkennung vorgeschlagen hatte; die Zeile wird zu `hand` und bleibt
  /// beim Sperren stehen. Läuft umgekehrt die Bilderkennung über einen
  /// Begriff, den der Nutzer schon selbst vergeben hat, lässt sie ihn in
  /// Ruhe: Sie darf eine Handvergabe nicht zu ihrer eigenen erklären und
  /// sie damit löschbar machen.
  Future<void> tagAsset(String assetId, String tagName,
      {String quelle = Tagquelle.hand}) async {
    final tagId = await ensureTag(tagName);
    if (quelle == Tagquelle.ki) {
      // `insertOnConflictUpdate` würde eine vorhandene Handvergabe
      // überschreiben – hier ist genau das der Fehler.
      await into(assetTags).insert(
        AssetTagsCompanion.insert(
            assetId: assetId, tagId: tagId, quelle: const Value(Tagquelle.ki)),
        mode: InsertMode.insertOrIgnore,
      );
      return;
    }
    await into(assetTags).insertOnConflictUpdate(
      AssetTagsCompanion.insert(
          assetId: assetId, tagId: tagId, quelle: Value(quelle)),
    );
  }

  /// Hängt denselben Tag an mehrere Assets. Der Tag wird einmal angelegt
  /// (statt je Foto nachgeschlagen), die Zuordnungen gehen als ein Stapel
  /// in einer Transaktion hinaus.
  Future<void> tagAssetsBulk(List<String> assetIds, String tagName) async {
    final tagId = await ensureTag(tagName);
    await batch((b) => b.insertAllOnConflictUpdate(
          assetTags,
          [
            for (final id in assetIds)
              AssetTagsCompanion.insert(assetId: id, tagId: tagId),
          ],
        ));
  }

  /// Wie viele Schlagwörter die Bilderkennung vergeben hat.
  ///
  /// Für die Rückfrage vor dem Zurücknehmen: Eine Zahl zu nennen ist der
  /// Unterschied zwischen einer Warnung und einer Behauptung.
  Future<int> kiTagAnzahl() async {
    final zeile = await customSelect(
      'SELECT COUNT(*) AS anzahl FROM asset_tags WHERE quelle = ?',
      variables: const [Variable<String>(Tagquelle.ki)],
      readsFrom: {assetTags},
    ).getSingle();
    return zeile.read<int>('anzahl');
  }

  /// Nimmt **alle** von der Bilderkennung vergebenen Schlagwörter zurück.
  ///
  /// **Von Hand vergebene bleiben unangetastet** – das ist der ganze Grund,
  /// warum in `asset_tags` seit Schema 56 die Herkunft steht (siehe
  /// [Tagquelle]). Wer einen Begriff selbst vergeben hat, hat ihn damit
  /// übernommen; die Zeile steht auf `hand` und fällt hier nicht mit.
  ///
  /// Zusätzlich wird der Vermerk „schon durchgesehen" an den Aufnahmen
  /// gelöscht. Ohne ihn bliebe die Bibliothek nach dem Zurücknehmen leer:
  /// Die Bilderkennung überspringt jede Aufnahme, die den Vermerk trägt,
  /// und würde die Schlagwörter deshalb nie neu vergeben.
  ///
  /// Verwaiste Schlagwörter, die danach an keiner Aufnahme mehr hängen,
  /// werden mit entfernt – sonst bliebe die Auswahlliste in der Suche voll
  /// von Begriffen ohne ein einziges Foto.
  Future<int> nimmKiTagsZurueck() async {
    return transaction(() async {
      final anzahl = await kiTagAnzahl();
      await (delete(assetTags)..where((t) => t.quelle.equals(Tagquelle.ki)))
          .go();
      await customUpdate(
        'UPDATE assets SET ai_tags_scanned = 0',
        updates: {assets},
        updateKind: UpdateKind.update,
      );
      await customUpdate(
        'DELETE FROM tags WHERE id NOT IN (SELECT tag_id FROM asset_tags)',
        updates: {tags},
        updateKind: UpdateKind.delete,
      );
      return anzahl;
    });
  }

  Future<void> untagAsset(String assetId, String tagId) => (delete(assetTags)
        ..where((t) => t.assetId.equals(assetId) & t.tagId.equals(tagId)))
      .go();

  /// Alle Tags der Bibliothek – für die Mehrfachauswahl im
  /// Suchoptionen-Panel.
  Stream<List<TagData>> watchAllTags() =>
      (select(tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  /// Dasselbe als einmalige Abfrage.
  ///
  /// Ein `watch(...).first` sieht danach aus, als täte es dasselbe, tut es
  /// aber nicht: Es hängt einen Beobachter an die Tabelle, lässt bei
  /// Abbruch einen Zeitgeber zurück und wirft in einer frisch angelegten
  /// Datenbank „Bad state: No element". Dieselbe Lehre wie bei
  /// [alleAufnahmen].
  Future<List<TagData>> alleTags() =>
      (select(tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  /// Direkte Tag-Zuordnung per ID statt per Name (anders als [tagAsset], das
  /// den Tag bei Bedarf erst per Name anlegt) – für das Anwenden eines
  /// Kamera-Presets, dessen Tags bereits als IDs gespeichert sind, ohne
  /// zusätzlichen Namens-Lookup.
  Future<void> tagAssetById(String assetId, String tagId) =>
      into(assetTags).insertOnConflictUpdate(
          AssetTagsCompanion.insert(assetId: assetId, tagId: tagId));

  // -----------------------------------------------------------------------
  // Entwicklungs-Vorgaben (benannte Reglerstände)
  // -----------------------------------------------------------------------

  Stream<List<DevelopPresetData>> watchDevelopPresets() =>
      (select(developPresets)..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<List<DevelopPresetData>> alleDevelopPresets() =>
      (select(developPresets)..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  /// Legt eine Vorgabe an oder aktualisiert sie – wie
  /// [upsertExportPreset], samt derselben Begründung: Der Konflikt wird
  /// über die Nummer aufgelöst, nicht über den Namen. Ein zweiter Eintrag
  /// mit belegtem Namen soll nicht stillschweigend den ersten
  /// überschreiben.
  Future<void> upsertDevelopPreset(DevelopPresetsCompanion vorgabe) =>
      into(developPresets).insertOnConflictUpdate(vorgabe);

  /// Ob [name] schon vergeben ist – [ausserId] nimmt die gerade
  /// bearbeitete Vorgabe aus.
  Future<bool> developPresetNameVergeben(String name, {int? ausserId}) async {
    final abfrage = select(developPresets)..where((t) => t.name.equals(name));
    if (ausserId != null) {
      abfrage.where((t) => t.id.equals(ausserId).not());
    }
    return (await abfrage.get()).isNotEmpty;
  }

  Future<void> deleteDevelopPreset(int id) =>
      (delete(developPresets)..where((t) => t.id.equals(id))).go();

  // -----------------------------------------------------------------------
  // Export-Voreinstellungen (benannte Ausgabe-Vorgaben)
  // -----------------------------------------------------------------------

  Stream<List<ExportPresetData>> watchExportPresets() =>
      (select(exportPresets)..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<List<ExportPresetData>> alleExportPresets() =>
      (select(exportPresets)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  /// Legt eine Vorgabe an oder aktualisiert sie. Der Aufrufer setzt [id] nur
  /// beim Bearbeiten; ohne [id] vergibt SQLite eine neue.
  ///
  /// Der Konflikt wird über die Nummer aufgelöst, nicht über den Namen: Ein
  /// zweiter Eintrag mit belegtem Namen soll NICHT stillschweigend den
  /// ersten überschreiben, sondern an der `unique`-Spalte scheitern. Wer
  /// speichert, fragt vorher [exportPresetNameVergeben] und sagt es dem
  /// Nutzer – siehe ExportPresetsScreen.
  Future<void> upsertExportPreset(ExportPresetsCompanion vorgabe) =>
      into(exportPresets).insertOnConflictUpdate(vorgabe);

  /// Ob [name] schon vergeben ist – [ausserId] nimmt die gerade bearbeitete
  /// Vorgabe aus, sonst kollidierte jede Vorgabe mit sich selbst.
  Future<bool> exportPresetNameVergeben(String name, {int? ausserId}) async {
    final abfrage = select(exportPresets)..where((t) => t.name.equals(name));
    if (ausserId != null) {
      abfrage.where((t) => t.id.equals(ausserId).not());
    }
    return (await abfrage.get()).isNotEmpty;
  }

  Future<void> deleteExportPreset(int id) =>
      (delete(exportPresets)..where((t) => t.id.equals(id))).go();

  // -----------------------------------------------------------------------
  // Kamera-Presets (automatische Aktionen beim Import je erkannter Kamera)
  // -----------------------------------------------------------------------

  Stream<List<CameraPresetData>> watchCameraPresets() => (select(cameraPresets)
        ..orderBy([
          (t) => OrderingTerm.asc(t.cameraMake),
          (t) => OrderingTerm.asc(t.cameraModel)
        ]))
      .watch();

  /// Tag-Zuordnungen ALLER Presets auf einmal (presetId -> Tag-IDs), reaktiv
  /// – für die Presets-Liste, die sonst pro sichtbarer Kachel eine eigene
  /// Abfrage bräuchte (N+1, und bei einem einfachen `FutureBuilder` pro
  /// Kachel entweder bei jedem Rebuild neu abgefragt oder – bei
  /// zwischengespeichertem Future – nach einer Tag-Änderung veraltet
  /// stehenbleibt). Die Tabelle selbst ist immer klein (Presets × Tags pro
  /// Preset), ein voller Select ist hier günstiger als N Einzelabfragen.
  Stream<Map<String, List<String>>> watchAllCameraPresetTagIds() {
    return select(cameraPresetTags).watch().map((rows) {
      final map = <String, List<String>>{};
      for (final row in rows) {
        map.putIfAbsent(row.presetId, () => []).add(row.tagId);
      }
      return map;
    });
  }

  Future<void> upsertCameraPreset(CameraPresetsCompanion preset) =>
      into(cameraPresets).insertOnConflictUpdate(preset);

  Future<void> deleteCameraPreset(String id) async {
    await (delete(cameraPresetTags)..where((t) => t.presetId.equals(id))).go();
    await (delete(cameraPresets)..where((t) => t.id.equals(id))).go();
  }

  Future<List<String>> tagIdsForCameraPreset(String presetId) async {
    final rows = await (select(cameraPresetTags)
          ..where((t) => t.presetId.equals(presetId)))
        .get();
    return rows.map((r) => r.tagId).toList();
  }

  /// Ersetzt die komplette Tag-Zuordnung eines Presets auf einmal (statt
  /// einzelner Hinzufügen-/Entfernen-Aufrufe) – der Editor übergibt bei
  /// jedem Speichern die vollständige, gewünschte Tag-Menge.
  Future<void> setCameraPresetTags(String presetId, List<String> tagIds) async {
    await (delete(cameraPresetTags)..where((t) => t.presetId.equals(presetId)))
        .go();
    if (tagIds.isEmpty) return;
    await batch((b) {
      b.insertAll(
        cameraPresetTags,
        tagIds.map((tagId) =>
            CameraPresetTagsCompanion.insert(presetId: presetId, tagId: tagId)),
      );
    });
  }

  /// Das Preset für eine erkannte Kamera, falls eines existiert – `null`,
  /// solange Hersteller/Modell unbekannt sind (z.B. Videos ohne EXIF-Kamera)
  /// oder kein Preset für genau diese Kombination angelegt wurde. Bewusst
  /// über `.get()` + erste Zeile statt `getSingleOrNull()`, damit ein aus
  /// Versehen doppelt angelegtes Preset für dieselbe Kamera nicht den
  /// gesamten Importvorgang mit einer Exception abbricht.
  Future<CameraPresetData?> cameraPresetFor(
      String? cameraMake, String? cameraModel) async {
    if (cameraMake == null || cameraModel == null) return null;
    final rows = await (select(cameraPresets)
          ..where((t) =>
              t.cameraMake.equals(cameraMake) &
              t.cameraModel.equals(cameraModel))
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  // -----------------------------------------------------------------------
  // Automatisierungs-Regelwerk (Verallgemeinerung der Kamera-Presets auf
  // Ort/Datum/KI-Tag, siehe AutomationRules-Tabelle)
  // -----------------------------------------------------------------------

  Stream<List<AutomationRuleData>> watchAutomationRules() =>
      (select(automationRules)..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  /// Alle Regeln auf einmal statt eines gezielten Lookups (anders als
  /// [cameraPresetFor]): die Bedingungen sind zu unterschiedlich geformt
  /// (Umkreis/Datumsbereich/KI-Tag), um sie in einem einzelnen SQL-WHERE
  /// zusammenzufassen – die Tabelle ist wie CameraPresets klein, ein voller
  /// Scan mit Auswertung in Dart (siehe LibraryState.applyAutomationRules)
  /// ist hier güngstiger als der Aufwand einer typspezifischen Abfrage.
  Future<List<AutomationRuleData>> allAutomationRules() =>
      select(automationRules).get();

  /// Tag-Zuordnungen ALLER Regeln auf einmal, reaktiv – siehe
  /// [watchAllCameraPresetTagIds] für die Begründung (N+1/Veralten
  /// vermeiden).
  Stream<Map<String, List<String>>> watchAllAutomationRuleTagIds() {
    return select(automationRuleTags).watch().map((rows) {
      final map = <String, List<String>>{};
      for (final row in rows) {
        map.putIfAbsent(row.ruleId, () => []).add(row.tagId);
      }
      return map;
    });
  }

  Future<void> upsertAutomationRule(AutomationRulesCompanion rule) =>
      into(automationRules).insertOnConflictUpdate(rule);

  Future<void> deleteAutomationRule(String id) async {
    await (delete(automationRuleTags)..where((t) => t.ruleId.equals(id))).go();
    await (delete(automationRules)..where((t) => t.id.equals(id))).go();
  }

  Future<List<String>> tagIdsForAutomationRule(String ruleId) async {
    final rows = await (select(automationRuleTags)
          ..where((t) => t.ruleId.equals(ruleId)))
        .get();
    return rows.map((r) => r.tagId).toList();
  }

  /// Ersetzt die komplette Tag-Zuordnung einer Regel auf einmal, siehe
  /// [setCameraPresetTags].
  Future<void> setAutomationRuleTags(String ruleId, List<String> tagIds) async {
    await (delete(automationRuleTags)..where((t) => t.ruleId.equals(ruleId)))
        .go();
    if (tagIds.isEmpty) return;
    await batch((b) {
      b.insertAll(
        automationRuleTags,
        tagIds.map((tagId) =>
            AutomationRuleTagsCompanion.insert(ruleId: ruleId, tagId: tagId)),
      );
    });
  }

  Future<List<TagData>> tagsForAsset(String assetId) async {
    final query = select(tags).join([
      innerJoin(assetTags, assetTags.tagId.equalsExp(tags.id)),
    ])
      ..where(assetTags.assetId.equals(assetId));
    final rows = await query.get();
    return rows.map((r) => r.readTable(tags)).toList();
  }

  /// Tag-Namen ALLER Assets in einer einzigen Abfrage (assetId -> Tag-Namen)
  /// – für den Metadaten-Export beim Backup, damit nicht pro Foto eine
  /// eigene Datenbankabfrage nötig ist ([tagsForAsset] wäre dort ein
  /// N+1-Problem, das bei großen Bibliotheken spürbar Zeit kostet).
  Future<Map<String, List<String>>> allTagNamesByAssetId() async {
    // Nur die zwei Spalten – siehe [allEmbeddings]. Hier sind es 25.761
    // Zeilen, aus denen sonst ebenso viele Paare von Zeilenobjekten
    // entstehen: 55 ms gegen 23 ms.
    final query = selectOnly(assetTags).join([
      innerJoin(tags, tags.id.equalsExp(assetTags.tagId)),
    ])
      ..addColumns([assetTags.assetId, tags.name]);
    final result = <String, List<String>>{};
    for (final z in await query.get()) {
      result
          .putIfAbsent(z.rawData.read<String>('asset_tags.asset_id'), () => [])
          .add(z.rawData.read<String>('tags.name'));
    }
    return result;
  }

  /// Die BENANNTEN Gesichter aller Assets in einer einzigen Abfrage
  /// (assetId -> Regionen) – für den XMP-Export, aus demselben Grund wie
  /// [allTagNamesByAssetId]: pro Foto zwei Abfragen wären bei 8000
  /// Aufnahmen der teuerste Teil des Laufs.
  ///
  /// Nur benannte und nicht beiseitegelegte. Eine Region ohne Namen sagt
  /// dem Zielprogramm nur „hier ist irgendein Kopf", und das findet dessen
  /// eigene Erkennung selbst.
  Future<Map<String, List<Gesichtsregion>>> alleGesichtsregionen() async {
    // Nur die sechs Spalten, die gebraucht werden – siehe [allEmbeddings].
    // An jedem Gesicht hängt sonst seine 512er-Einbettung, zwei Kilobyte je
    // Zeile, die der XMP-Export nie ansieht: 11,2 ms gegen 3,9 ms.
    final abfrage = selectOnly(faces).join([
      innerJoin(people, people.id.equalsExp(faces.personId)),
    ])
      ..addColumns([
        faces.assetId,
        people.name,
        faces.boxX,
        faces.boxY,
        faces.boxW,
        faces.boxH,
      ])
      ..where(faces.personId.isNotNull() & faces.isIgnored.equals(false));
    final ergebnis = <String, List<Gesichtsregion>>{};
    for (final z in await abfrage.get()) {
      ergebnis
          .putIfAbsent(z.rawData.read<String>('faces.asset_id'), () => [])
          .add(Gesichtsregion(
            name: z.rawData.read<String>('people.name'),
            links: z.rawData.read<double>('faces.box_x'),
            oben: z.rawData.read<double>('faces.box_y'),
            breite: z.rawData.read<double>('faces.box_w'),
            hoehe: z.rawData.read<double>('faces.box_h'),
          ));
    }
    return ergebnis;
  }

  /// Die benannten Gesichter EINES Fotos – für den Einzelexport, wo eine
  /// Abfrage über die ganze Bibliothek Verschwendung wäre.
  Future<List<Gesichtsregion>> gesichtsregionenVon(String assetId) async {
    final alle = await (select(faces)
          ..where((f) =>
              f.assetId.equals(assetId) &
              f.personId.isNotNull() &
              f.isIgnored.equals(false)))
        .get();
    if (alle.isEmpty) return const [];
    final namen = {
      for (final p in await (select(people)
            ..where((p) => p.id.isIn([for (final f in alle) f.personId!])))
          .get())
        p.id: p.name,
    };
    return [
      for (final f in alle)
        if (namen[f.personId] case final name?)
          Gesichtsregion(
            name: name,
            links: f.boxX,
            oben: f.boxY,
            breite: f.boxW,
            hoehe: f.boxH,
          ),
    ];
  }

  /// Wie [allTagNamesByAssetId], aber nur die Vorschläge der
  /// Bilderkennung – für die Sicherung.
  ///
  /// **Ohne diese Auskunft verlöre eine Rücksicherung die Herkunft.** Die
  /// Sicherung führt Schlagwörter als blosse Namen; alles käme als
  /// Handvergabe zurück, und der gesperrte Ordner stünde wieder da, wo er
  /// vor Fassung 56 stand – nur eben nach einem Umweg über eine Sicherung.
  Future<Map<String, Set<String>>> kiTagNamesByAssetId() async {
    // Nur die zwei Spalten – siehe [allEmbeddings].
    final query = selectOnly(assetTags).join([
      innerJoin(tags, tags.id.equalsExp(assetTags.tagId)),
    ])
      ..addColumns([assetTags.assetId, tags.name])
      ..where(assetTags.quelle.equals(Tagquelle.ki));
    final result = <String, Set<String>>{};
    for (final z in await query.get()) {
      result
          .putIfAbsent(
              z.rawData.read<String>('asset_tags.asset_id'), () => <String>{})
          .add(z.rawData.read<String>('tags.name'));
    }
    return result;
  }

  // -----------------------------------------------------------------------
  // KI-Tagging-Vokabular (AiTaggingService)
  // -----------------------------------------------------------------------

  /// Für die Einstellungen (reaktiv, damit Änderungen sofort sichtbar sind).
  Stream<List<AiTagVocabularyData>> watchAiTagVocabulary() =>
      (select(aiTagVocabulary)..orderBy([(t) => OrderingTerm.asc(t.term)]))
          .watch();

  /// Idempotent (Muster: [ensureTag]) – ein Doppel-Tap auf "Hinzufügen"
  /// erzeugt keinen doppelten Eintrag und keinen UNIQUE-Constraint-Fehler.
  Future<void> addAiTagTerm(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    final existing = await (select(aiTagVocabulary)
          ..where((t) => t.term.equals(trimmed)))
        .getSingleOrNull();
    if (existing != null) return;
    await into(aiTagVocabulary)
        .insert(AiTagVocabularyCompanion.insert(term: trimmed));
  }

  Future<void> removeAiTagTerm(int id) =>
      (delete(aiTagVocabulary)..where((t) => t.id.equals(id))).go();

  /// Einmaliger, nicht-reaktiver Read für Aufrufer, die keinen Stream
  /// brauchen (Import-Pipeline, Backfill) – analog zu [tagsForAsset].
  Future<List<String>> aiTagVocabularyTerms() async {
    final rows = await (select(aiTagVocabulary)
          ..orderBy([(t) => OrderingTerm.asc(t.term)]))
        .get();
    return rows.map((r) => r.term).toList();
  }

  /// Kombinierte Suche über alle Filter des Suchoptionen-Panels (siehe
  /// [SearchFilters]) – alle aktiven Filter werden UND-verknüpft (z.B.
  /// Person UND Kamera UND Zeitraum), mehrere ausgewählte Personen bzw. Tags
  /// werden untereinander ebenfalls UND-verknüpft ("muss alle enthalten",
  /// nicht "mindestens einen").
  ///
  /// [restrictToIds] schränkt zusätzlich auf eine vorgegebene ID-Menge ein.
  ///
  /// Der "Kontext"-Modus (KI-Bildsuche) nutzt das bewusst NICHT mehr: Er
  /// filtert erst hier und rankt die Treffer danach über [ClipService].
  /// Andersherum – erst ranken, dann filtern – entschied das
  /// bibliotheksweite Top-N darüber, was die Filter überhaupt noch zu sehen
  /// bekamen, und ließ Treffer in kleinen Alben verschwinden (Audit-Fund).
  /// Der Suchtext selbst wird unten im Kontext-Modus absichtlich nicht als
  /// LIKE-Bedingung angewendet – dafür ist gerade das Embedding zuständig.
  /// Die Bedingungen der Suche - einmal gebaut, von beiden Wegen
  /// benutzt.
  ///
  /// **Warum getrennt.** [searchAssets] liefert volle Zeilen, und die KI-
  /// Suche brauchte davon nur die Kennungen, um ihre Kandidaten
  /// einzugrenzen: 7163 Zeilen mit 56 Spalten fuer eine Frage nach
  /// Zugehoerigkeit. Zwei Wege auf denselben Bedingungen sind billiger
  /// als eine zweite Aufzaehlung derselben 24 Filter, die eines Tages
  /// auseinanderliefe.
  List<Expression<bool>> _suchbedingungen(
      SearchFilters filters, List<String>? restrictToIds,
      {bool textAlreadyFiltered = false}) {
    final wo = <Expression<bool>>[
      assets.isTrashed.equals(false),
      assets.isLocked.equals(false),
      // Live-Photo-Partner (das .mov zu einem Standbild) und
      // nicht-Titelbild-Stapelmitglieder werden hier wie überall sonst
      // (Timeline, Alben, Kartenansicht) ausgeblendet – sichtbar/
      // abspielbar bleiben sie weiterhin über das verknüpfte Foto bzw.
      // das Titelbild, nur nicht als zusätzlicher, eigenständiger Treffer.
      _isPrimaryGridEntry(assets),
    ];

    if (restrictToIds != null) {
      wo.add(assets.id.isIn(restrictToIds));
    }

    final text = filters.query.trim();
    if (!textAlreadyFiltered &&
        text.isNotEmpty &&
        filters.textMode == SearchTextMode.filename) {
      wo.add(assets.originalFileName.like('%$text%'));
    } else if (!textAlreadyFiltered &&
        text.isNotEmpty &&
        filters.textMode == SearchTextMode.description) {
      wo.add(assets.description.like('%$text%'));
    } else if (!textAlreadyFiltered &&
        text.isNotEmpty &&
        filters.textMode == SearchTextMode.ocr) {
      wo.add(assets.ocrText.like('%$text%'));
    } else if (!textAlreadyFiltered &&
        text.isNotEmpty &&
        filters.textMode == SearchTextMode.caption) {
      // Beide Fassungen: Wer die Übersetzung erst später einschaltet, hat
      // Fotos mit nur englischer und Fotos mit beiden Beschreibungen. Nur
      // in einer zu suchen liesse einen Teil der Bibliothek unauffindbar.
      wo.add(assets.aiCaption.like('%$text%') |
          assets.aiCaptionDe.like('%$text%'));
    }

    if (filters.cameraMake != null) {
      wo.add(assets.cameraMake.equals(filters.cameraMake!));
    }
    if (filters.cameraModel != null) {
      wo.add(assets.cameraModel.equals(filters.cameraModel!));
    }
    if (filters.lensModel != null) {
      wo.add(assets.lensModel.equals(filters.lensModel!));
    }

    if (filters.locationCountry != null) {
      wo.add(assets.locationCountry.equals(filters.locationCountry!));
    }
    if (filters.locationState != null) {
      wo.add(assets.locationState.equals(filters.locationState!));
    }
    if (filters.locationCity != null) {
      wo.add(assets.locationCity.equals(filters.locationCity!));
    }

    if (filters.startDate != null) {
      final start = filters.startDate!;
      wo.add(assets.fileCreatedAt
          .isBiggerOrEqualValue(DateTime(start.year, start.month, start.day)));
    }
    if (filters.endDate != null) {
      final end = filters.endDate!;
      // Enddatum inklusive -> bis zum letzten Millisekunde des gewählten Tages.
      wo.add(assets.fileCreatedAt.isSmallerOrEqualValue(
          DateTime(end.year, end.month, end.day, 23, 59, 59, 999)));
    }

    if (filters.mediaType == MediaTypeFilter.image) {
      wo.add(assets.type.equals('IMAGE'));
    } else if (filters.mediaType == MediaTypeFilter.video) {
      wo.add(assets.type.equals('VIDEO'));
    }

    // Leerer Satz heisst „alle" – nicht „keins". Ein `isIn([])` waere
    // sonst eine Bedingung, die nie zutrifft, und die Suche bliebe ohne
    // erkennbaren Grund leer.
    if (filters.formate.isNotEmpty) {
      wo.add(assets.dateiformat.isIn(filters.formate.toList()));
    }

    if (filters.favoritesOnly) {
      wo.add(assets.isFavorite.equals(true));
    }

    if (filters.notInAnyAlbum) {
      wo.add(notExistsQuery(
          select(albumAssets)..where((aa) => aa.assetId.equalsExp(assets.id))));
    }

    if (filters.minRating != null) {
      wo.add(assets.rating.isBiggerOrEqualValue(filters.minRating!));
    }
    if (filters.colorLabels.isNotEmpty) {
      wo.add(assets.colorLabel.isIn(filters.colorLabels));
    }
    if (filters.minIso != null) {
      wo.add(assets.iso.isBiggerOrEqualValue(filters.minIso!));
    }
    if (filters.maxIso != null) {
      wo.add(assets.iso.isSmallerOrEqualValue(filters.maxIso!));
    }
    if (filters.minFNumber != null) {
      wo.add(assets.fNumber.isBiggerOrEqualValue(filters.minFNumber!));
    }
    if (filters.maxFNumber != null) {
      wo.add(assets.fNumber.isSmallerOrEqualValue(filters.maxFNumber!));
    }
    if (filters.minFocalLengthMm != null) {
      wo.add(
          assets.focalLengthMm.isBiggerOrEqualValue(filters.minFocalLengthMm!));
    }
    if (filters.maxFocalLengthMm != null) {
      wo.add(assets.focalLengthMm
          .isSmallerOrEqualValue(filters.maxFocalLengthMm!));
    }
    if (filters.maxSharpnessScore != null) {
      wo.add(assets.sharpnessScore
          .isSmallerOrEqualValue(filters.maxSharpnessScore!));
    }
    if (filters.nurGeschaetztesDatum) {
      wo.add(assets.datumGeschaetzt.equals(true));
    }

    for (final personId in filters.personIds) {
      wo.add(existsQuery(select(faces)
        ..where((f) =>
            f.assetId.equalsExp(assets.id) & f.personId.equals(personId))));
    }

    if (filters.noTag) {
      wo.add(notExistsQuery(
          select(assetTags)..where((at) => at.assetId.equalsExp(assets.id))));
    } else {
      for (final tagId in filters.tagIds) {
        wo.add(existsQuery(select(assetTags)
          ..where((at) =>
              at.assetId.equalsExp(assets.id) & at.tagId.equals(tagId))));
      }
    }

    return wo;
  }

  Future<List<String>?> _ftsAssetIds(SearchFilters filters) async {
    final text = filters.query.trim();
    if (text.isEmpty) return null;
    final columns = switch (filters.textMode) {
      SearchTextMode.filename => ['original_file_name'],
      SearchTextMode.description => ['description'],
      SearchTextMode.ocr => ['ocr_text'],
      SearchTextMode.caption => ['ai_caption', 'ai_caption_de'],
      _ => const <String>[],
    };
    if (columns.isEmpty) return null;
    // **Jeder Begriff in Anführungszeichen.** Der Ausdruck unten lässt nur
    // Buchstaben, Ziffern und Unterstrich durch, aber das genügt nicht: FTS5
    // liest `AND`, `OR` und `NOT` als Verknüpfung, sobald sie nackt
    // dastehen. Die Suche nach „a AND b" wurde damit zu
    // `(a* AND AND* AND b*)` – ein Syntaxfehler, der im Suchbildschirm als
    // „Suche fehlgeschlagen" landete, statt Treffer zu liefern. In
    // Anführungszeichen ist derselbe Begriff ein Wort wie jedes andere, und
    // das nachgestellte `*` bleibt gültige Präfixsuche.
    final terms = RegExp(r'[\p{L}\p{N}_]+', unicode: true)
        .allMatches(text)
        .map((match) => '"${match.group(0)!.replaceAll('"', '""')}"*')
        .toList();
    if (terms.isEmpty) return const [];
    final query = columns
        .map((column) => '$column : (${terms.join(' AND ')})')
        .join(' OR ');
    final rows = await customSelect(
      'SELECT asset_id FROM asset_search_fts WHERE asset_search_fts MATCH ?',
      variables: [Variable<String>(query)],
    ).get();
    return [for (final row in rows) row.read<String>('asset_id')];
  }

  List<String>? _intersectIds(List<String>? requested, List<String>? fts) {
    if (fts == null) return requested;
    if (requested == null) return fts;
    final allowed = fts.toSet();
    return [
      for (final id in requested)
        if (allowed.contains(id)) id
    ];
  }

  /// Wie viele Treffer die Filterkombination haette – **ohne** die
  /// Treffer selbst zu laden.
  ///
  /// **Der Anlass ist die Zahl in der Filterleiste.** Sie steht dort
  /// live, und sie wurde bisher aus `searchAssets(...).length` gewonnen:
  /// erst alle Treffer vollstaendig laden, dann zaehlen. Bei einem weiten
  /// Textfilter sind das an der echten Bibliothek **7163 Zeilen mit je
  /// 56 Spalten**, und die Leiste rechnet bei **jedem Tastendruck** neu.
  ///
  /// ```
  /// searchAssets(...).length     88,3 ms
  /// countSearchResults(...)      10,5 ms
  /// ```
  ///
  /// Die Bedingungen kommen aus derselben Quelle wie bei der Suche
  /// ([_suchbedingungen]) – waeren es zwei Kopien, koennte die Zahl
  /// etwas anderes versprechen als die Liste dahinter zeigt.
  Future<int> countSearchResults(SearchFilters filters,
      {List<String>? restrictToIds}) async {
    final fts = await _ftsAssetIds(filters);
    final effectiveIds = _intersectIds(restrictToIds, fts);
    // Eine leere Auswahl hat keine Treffer – und `id IN ()` waere eine
    // Abfrage, die ohnehin nichts findet.
    if (effectiveIds != null && effectiveIds.isEmpty) return 0;
    final anzahl = assets.id.count();
    final abfrage = selectOnly(assets)..addColumns([anzahl]);
    for (final b in _suchbedingungen(filters, effectiveIds,
        textAlreadyFiltered: fts != null)) {
      abfrage.where(b);
    }
    return (await abfrage.getSingle()).read(anzahl) ?? 0;
  }

  Future<List<AssetData>> searchAssets(SearchFilters filters,
      {List<String>? restrictToIds}) async {
    final fts = await _ftsAssetIds(filters);
    final effectiveIds = _intersectIds(restrictToIds, fts);
    final query = select(assets);
    for (final b in _suchbedingungen(filters, effectiveIds,
        textAlreadyFiltered: fts != null)) {
      query.where((_) => b);
    }
    query.orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]);
    return query.get();
  }

  /// Dieselbe Suche, aber nur die Kennungen.
  ///
  /// Fuer die KI-Bildsuche: Die filtert erst hier und rankt danach ueber
  /// die Einbettungen: Aus der Trefferliste werden am Ende 200 gezeigt.
  /// Die vollen Zeilen der 7163 Kandidaten dafuer zu lesen kostete an
  /// dieser Bibliothek 81 ms, die Kennungen kosten 4,3 ms - die 200
  /// Zeilen holt danach [assetsByIds] fuer 2,6 ms.
  ///
  /// **Ohne Reihenfolge**, und das ist Absicht: Wer die Kennungen holt,
  /// ordnet danach selbst (nach Aehnlichkeit). Ein ORDER BY waere hier
  /// eine Sortierung, die niemand liest.
  Future<List<String>> searchAssetIds(SearchFilters filters,
      {List<String>? restrictToIds}) async {
    final fts = await _ftsAssetIds(filters);
    final effectiveIds = _intersectIds(restrictToIds, fts);
    final query = selectOnly(assets)..addColumns([assets.id]);
    for (final b in _suchbedingungen(filters, effectiveIds,
        textAlreadyFiltered: fts != null)) {
      query.where(b);
    }
    return [for (final z in await query.get()) z.read(assets.id)!];
  }

  /// Alle in der Bibliothek tatsächlich vorkommenden, nicht-leeren Werte
  /// einer Text-Spalte – für die Dropdowns im Suchoptionen-Panel (Kamera-
  /// Marke/-Modell/Objektiv), damit dort nur Werte auswählbar sind, die auch
  /// wirklich zu einem Treffer führen können.
  Future<List<String>> _distinctNonNullValues(
      GeneratedColumn<String> column) async {
    final query = selectOnly(assets, distinct: true)
      ..addColumns([column])
      ..where(column.isNotNull())
      ..orderBy([OrderingTerm.asc(column)]);
    final rows = await query.get();
    return rows.map((r) => r.read(column)!).toList();
  }

  Future<List<String>> distinctCameraMakes() =>
      _distinctNonNullValues(assets.cameraMake);
  Future<List<String>> distinctCameraModels() =>
      _distinctNonNullValues(assets.cameraModel);
  Future<List<String>> distinctLensModels() =>
      _distinctNonNullValues(assets.lensModel);

  /// Alle in der Bibliothek vorkommenden Dateiformate – für die
  /// Auswahlliste im Suchfeld. Bewusst aus dem Bestand statt aus einer
  /// festen Liste: Angeboten wird, was da ist, nicht was die App könnte.
  Future<List<String>> distinctDateiformate() =>
      _distinctNonNullValues(assets.dateiformat);

  /// Alle in der Bibliothek bereits vorkommenden Kamera-Kombinationen
  /// (Hersteller + Modell zusammen, nicht unabhängig wie
  /// [distinctCameraMakes]/[distinctCameraModels]) – als Vorauswahl beim
  /// Anlegen eines Kamera-Presets (siehe CameraPresetsScreen), damit
  /// Tippfehler kein Preset erzeugen, das nie zu einem echten Foto passt.
  Future<List<(String, String)>> distinctCameras() async {
    final query = selectOnly(assets, distinct: true)
      ..addColumns([assets.cameraMake, assets.cameraModel])
      ..where(assets.cameraMake.isNotNull() & assets.cameraModel.isNotNull())
      ..orderBy([
        OrderingTerm.asc(assets.cameraMake),
        OrderingTerm.asc(assets.cameraModel)
      ]);
    final rows = await query.get();
    return [
      for (final row in rows)
        (
          row.read<String>(assets.cameraMake)!,
          row.read<String>(assets.cameraModel)!
        ),
    ];
  }

  Future<List<String>> distinctCountries() =>
      _distinctNonNullValues(assets.locationCountry);

  /// ALLE vorkommenden Bundesländer/Provinzen, ohne Einschränkung auf ein
  /// Land – für den Satzleser (siehe `suchsatz.dart`), der beim Lesen von
  /// „Toskana" noch nicht weiss, in welchem Land das liegt.
  /// Bis zu [grenze] auswertbare Aufnahmen einer Kamera – für die
  /// Staubsuche (siehe `staubflecken.dart`).
  ///
  /// Nur Bilder, kein Papierkorb, nichts Gesperrtes. Und bewusst über den
  /// ganzen Zeitraum verteilt statt der neuesten: Staub kommt und geht mit
  /// dem Objektivwechsel; vierzig Aufnahmen desselben Nachmittags würden
  /// eine Sensorreinigung von vor drei Jahren als heutigen Befund melden.
  Future<List<AssetData>> aufnahmenDerKamera(String modell, int grenze) async {
    final alle = await (select(assets)
          ..where((t) =>
              t.cameraModel.equals(modell) &
              t.type.equals('IMAGE') &
              t.isTrashed.equals(false) &
              t.isLocked.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.fileCreatedAt)]))
        .get();
    if (alle.length <= grenze) return alle;
    final schritt = alle.length / grenze;
    return [for (var i = 0; i < grenze; i++) alle[(i * schritt).floor()]];
  }

  Future<List<String>> distinctAlleStates() =>
      _distinctNonNullValues(assets.locationState);

  /// Wie [distinctAlleStates], für Städte.
  Future<List<String>> distinctAlleCities() =>
      _distinctNonNullValues(assets.locationCity);

  /// Wie [distinctCountries], aber nur Bundesländer/Provinzen innerhalb eines
  /// bestimmten Landes – für das kaskadierende Land->Bundesland->Stadt-Dropdown
  /// im Suchoptionen-Panel (jede Ebene schränkt die darunterliegende ein).
  Future<List<String>> distinctStates(String country) async {
    final query = selectOnly(assets, distinct: true)
      ..addColumns([assets.locationState])
      ..where(assets.locationState.isNotNull() &
          assets.locationCountry.equals(country))
      ..orderBy([OrderingTerm.asc(assets.locationState)]);
    final rows = await query.get();
    return rows.map((r) => r.read(assets.locationState)!).toList();
  }

  /// Wie [distinctStates], aber Städte innerhalb eines bestimmten
  /// Bundeslands/einer Provinz.
  Future<List<String>> distinctCities(String state) async {
    final query = selectOnly(assets, distinct: true)
      ..addColumns([assets.locationCity])
      ..where(
          assets.locationCity.isNotNull() & assets.locationState.equals(state))
      ..orderBy([OrderingTerm.asc(assets.locationCity)]);
    final rows = await query.get();
    return rows.map((r) => r.read(assets.locationCity)!).toList();
  }

  // -----------------------------------------------------------------------
  // Gespeicherte Suchen ("Intelligente Alben")
  // -----------------------------------------------------------------------

  Future<void> createSavedSearch(
          String id, String name, SearchFilters filters) =>
      into(savedSearches).insert(SavedSearchesCompanion.insert(
        id: id,
        name: name,
        filtersJson: jsonEncode(filters.toJson()),
        createdAt: DateTime.now(),
      ));

  Stream<List<SavedSearchData>> watchSavedSearches() =>
      (select(savedSearches)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<void> deleteSavedSearch(String id) =>
      (delete(savedSearches)..where((t) => t.id.equals(id))).go();

  /// Deserialisiert die bei [createSavedSearch] gespeicherten Filter. Ein
  /// beschädigtes JSON (sollte nicht vorkommen, aber die Datei liegt
  /// außerhalb der Kontrolle der App) liefert leere Filter statt die ganze
  /// App abstürzen zu lassen.
  SearchFilters decodeSavedSearchFilters(String filtersJson) {
    try {
      return SearchFilters.fromJson(
          jsonDecode(filtersJson) as Map<String, dynamic>);
    } catch (_) {
      return const SearchFilters();
    }
  }

  // -----------------------------------------------------------------------
  // Personen / Gesichter
  // -----------------------------------------------------------------------

  Stream<List<PersonData>> watchPeople() => select(people).watch();

  /// Dasselbe als einmalige Abfrage – siehe [alleTags].
  Future<List<PersonData>> allePersonen() => select(people).get();

  /// Wie viele Personen angelegt sind – für die Zahl am Reiter.
  ///
  /// Als Zählung und nicht über [watchPeople]: Ein zweiter Beobachter auf
  /// derselben Tabelle würde bei jeder Zuordnung den ganzen Bildschirm neu
  /// aufbauen, samt der 200 Gesichtskacheln darunter – genau das, was das
  /// stückweise Entfernen im Raster gerade vermeidet.
  Future<int> countPeople() async {
    final anzahl = people.id.count();
    final row = await (selectOnly(people)..addColumns([anzahl])).getSingle();
    return row.read(anzahl) ?? 0;
  }

  Stream<PersonData?> watchPerson(String id) =>
      (select(people)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<void> createPerson(PeopleCompanion person) =>
      into(people).insert(person);

  Future<void> insertFace(FacesCompanion face) => into(faces).insert(face);

  /// Unbenannte Gesichter für den "Unbenannte Gesichter"-Tab – über einen
  /// Join gegen Assets gefiltert, damit Gesichter aus gelöschten oder
  /// gesperrten Fotos dort nicht auftauchen (sonst würde ein Foto-Crop aus
  /// dem gesperrten Ordner beiläufig sichtbar, obwohl das zugehörige Foto
  /// selbst versteckt ist).
  Future<List<FaceData>> unassignedFaces({int limit = 200}) async {
    final query = select(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
      ..where(faces.personId.isNull() &
          faces.isIgnored.equals(false) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false))
      ..limit(limit);
    final rows = await query.get();
    return rows.map((r) => r.readTable(faces)).toList();
  }

  /// Unlimitierte Variante von [unassignedFaces] – ein vollständiger
  /// Clustering-Lauf (siehe face_clustering_service.dart) braucht alle
  /// unzugeordneten Gesichter, nicht nur die ersten 200 (Standard-Limit für
  /// die Rasteransicht im "Unbenannte Gesichter"-Tab).
  Future<List<FaceData>> allUnassignedFaces() async {
    final query = select(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
      ..where(faces.personId.isNull() &
          faces.isIgnored.equals(false) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false));
    final rows = await query.get();
    return rows.map((r) => r.readTable(faces)).toList();
  }

  /// Beiseitegelegte Gesichter für den Tab „Ignoriert" – dieselbe
  /// Absicherung über Assets wie [unassignedFaces], damit auch hier kein
  /// Ausschnitt aus einem gesperrten Foto sichtbar wird.
  Future<List<FaceData>> ignoredFaces({int limit = 200}) async {
    final query = select(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
      ..where(faces.isIgnored.equals(true) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false))
      ..limit(limit);
    final rows = await query.get();
    return rows.map((r) => r.readTable(faces)).toList();
  }

  /// Wie viele Gesichter insgesamt beiseitegelegt sind – für die Zahl am
  /// Tab, damit auch jenseits des Anzeigelimits von 200 ersichtlich ist,
  /// wie viel dort liegt.
  Future<int> ignoredFacesCount() async {
    final anzahl = faces.id.count();
    final query = selectOnly(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
      ..addColumns([anzahl])
      ..where(faces.isIgnored.equals(true) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false));
    final row = await query.getSingle();
    return row.read(anzahl) ?? 0;
  }

  /// Löscht eine einzelne Erkennung und liefert den Pfad ihres
  /// Ausschnitts, damit der Aufrufer die Datei mit wegräumen kann.
  ///
  /// Für den offensichtlichen Fehlgriff der Erkennung, den man direkt im
  /// Foto sieht. Wie jedes Löschen ist auch das nicht dauerhaft – der
  /// nächste Scan findet die Stelle wieder. Wer sie loswerden will, legt
  /// sie beiseite (siehe [Faces.isIgnored]).
  Future<String?> loescheGesicht(String faceId) async {
    final vorher = await (select(faces)..where((t) => t.id.equals(faceId)))
        .getSingleOrNull();
    if (vorher == null) return null;
    await (delete(faces)..where((t) => t.id.equals(faceId))).go();
    return vorher.cropRelativePath;
  }

  /// Nimmt einem Gesicht seine Person, ohne es zu löschen – es landet
  /// wieder unter „Unbenannte Gesichter".
  ///
  /// Für die falsch zugeordnete Erkennung: Sie zu löschen wäre zu viel
  /// (die Stelle IST ein Gesicht), sie beiseitezulegen auch (man will sie
  /// ja richtig benennen).
  Future<void> loeseZuordnung(String faceId) =>
      (update(faces)..where((t) => t.id.equals(faceId)))
          .write(const FacesCompanion(personId: Value(null)));

  /// Legt alle noch unbenannten Gesichter auf einen Schlag beiseite und
  /// liefert, wie viele es waren.
  ///
  /// Für den Fall, dass die Erkennung überwiegend Unbrauchbares gefunden
  /// hat – Plakate, Statuen, Passanten. Von Hand wären das hunderte Klicks;
  /// danach holt man sich unter „Ignoriert" die wenigen zurück, die man
  /// wirklich benennen will.
  ///
  /// Bereits benannte Gesichter bleiben unberührt: Sie sind ja gerade das
  /// Ergebnis der Arbeit, die hier nicht verloren gehen darf.
  Future<int> ignoriereAlleUnbenannten() async {
    final betroffen = await allUnassignedFaces();
    if (betroffen.isEmpty) return 0;
    await setFacesIgnored([for (final f in betroffen) f.id], true);
    return betroffen.length;
  }

  /// Löscht alle unbenannten Erkennungen und liefert ihre Zahl sowie die
  /// Pfade ihrer Ausschnitte, damit der Aufrufer auch die Dateien wegräumen
  /// kann.
  ///
  /// Beides getrennt, weil es nicht dasselbe ist: Ein Gesicht ohne
  /// Embedding-Modell bekommt zwar eine Zeile, aber nicht zwangsläufig
  /// einen Ausschnitt. Die Pfade zu zählen und das Ergebnis als Zahl der
  /// gelöschten Erkennungen zu melden, ergäbe eine zu kleine Zahl.
  ///
  /// Anders als das Beiseitelegen ist das **nicht dauerhaft**: Der nächste
  /// Gesichts-Scan findet dieselben Stellen wieder und legt sie neu an.
  /// Dafür wird der Platz auf der Platte frei. Wer die Erkennungen
  /// endgültig loswerden will, legt sie beiseite – siehe
  /// [ignoriereAlleUnbenannten].
  ///
  /// Beiseitegelegte werden mitgelöscht: Wer „alle Erkennungen löschen"
  /// wählt, meint auch die, die schon aussortiert waren.
  Future<({int anzahl, List<String> pfade})>
      loescheAlleUnbenanntenErkennungen() async {
    final query = select(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
      ..where(faces.personId.isNull() &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false));
    final betroffen =
        (await query.get()).map((r) => r.readTable(faces)).toList();
    if (betroffen.isEmpty) return (anzahl: 0, pfade: const <String>[]);
    await (delete(faces)
          ..where((t) => t.id.isIn([for (final f in betroffen) f.id])))
        .go();
    return (
      anzahl: betroffen.length,
      pfade: [
        for (final f in betroffen)
          if (f.cropRelativePath != null) f.cropRelativePath!,
      ],
    );
  }

  /// Wie viele unbenannte Erkennungen es insgesamt gibt – für die Zahlen in
  /// der Rückfrage, die über das Anzeigelimit von 200 hinausgeht.
  Future<int> unassignedFacesCount() async {
    final anzahl = faces.id.count();
    final query = selectOnly(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
      ..addColumns([anzahl])
      ..where(faces.personId.isNull() &
          faces.isIgnored.equals(false) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false));
    return (await query.getSingle()).read(anzahl) ?? 0;
  }

  /// Legt Gesichter beiseite bzw. holt sie zurück.
  ///
  /// Beim Beiseitelegen wird eine bestehende Personen-Zuordnung entfernt:
  /// Ein Gesicht, das noch als „Anna" zählte und zugleich ignoriert wäre,
  /// hinge zwischen beiden Zuständen – es erschiene weiter in Annas Fotos,
  /// wäre aber unter „Ignoriert" gelistet.
  Future<void> setFacesIgnored(List<String> faceIds, bool ignoriert) async {
    if (faceIds.isEmpty) return;
    await (update(faces)..where((t) => t.id.isIn(faceIds)))
        .write(FacesCompanion(
      isIgnored: Value(ignoriert),
      personId: ignoriert ? const Value(null) : const Value.absent(),
    ));
  }

  /// Alle erkannten (und ggf. manuell hinzugefügten) Gesichter eines
  /// einzelnen Fotos – für die Foto-Detailansicht mit Gesichts-Overlay.
  Future<List<FaceData>> facesForAsset(String assetId) =>
      (select(faces)..where((t) => t.assetId.equals(assetId))).get();

  /// Für die Bibliotheks-Integritätsprüfung – ein einzelner Full-Table-Select
  /// statt N+1-Abfragen pro Asset.
  Future<List<FaceData>> allFaces() => select(faces).get();

  /// Alle Gesichter, die bereits einer bestimmten Person zugeordnet sind –
  /// z.B. um in der Personen-Detailansicht ein anderes Profilbild auswählen
  /// zu lassen. Ebenfalls ohne gelöschte/gesperrte Fotos (siehe
  /// [unassignedFaces]), sonst ließe sich darüber ein Profilbild aus einem
  /// gesperrten Foto auswählen.
  /// Alle Einbettungen zugeordneter Gesichter, in EINER Abfrage.
  ///
  /// Für den Personenvorschlag. [facesForPerson] daneben zu benutzen hiesse
  /// eine Abfrage je Person – bei 39 Personen also 39 Abfragen, jedes Mal,
  /// wenn jemand ein Gesicht antippt. An der gewachsenen Bibliothek sind es
  /// so 2060 Zeilen zu je 512 Byte, zusammen ein Megabyte.
  ///
  /// Gesperrte und gelöschte Aufnahmen bleiben draussen – aus demselben
  /// Grund wie bei [facesForPerson]: Sonst schlüge die App einen Namen vor,
  /// der aus einem Foto stammt, das der Benutzer gerade weggeschlossen hat.
  Future<List<({String personId, Uint8List vektor})>>
      einbettungenZugeordneterGesichter() async {
    final abfrage = select(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
      ..where(faces.personId.isNotNull() &
          faces.embedding.isNotNull() &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false));
    final zeilen = await abfrage.get();
    return [
      for (final z in zeilen)
        if (z.readTable(faces) case final f
            when f.personId != null && f.embedding != null)
          (personId: f.personId!, vektor: f.embedding!),
    ];
  }

  Future<List<FaceData>> facesForPerson(String personId) async {
    final query = select(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
      ..where(faces.personId.equals(personId) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false));
    final rows = await query.get();
    return rows.map((r) => r.readTable(faces)).toList();
  }

  /// Benannte Personen, die auf diesem Foto erkannt wurden (über die
  /// zugeordneten Gesichter) – für die "Personen"-Sektion der Info-Ansicht.
  Future<List<PersonData>> peopleForAsset(String assetId) async {
    final query = select(people).join([
      innerJoin(faces, faces.personId.equalsExp(people.id)),
    ])
      ..where(faces.assetId.equals(assetId));
    final rows = await query.get();
    final seen = <String>{};
    final result = <PersonData>[];
    for (final row in rows) {
      final person = row.readTable(people);
      if (seen.add(person.id)) result.add(person);
    }
    return result;
  }

  /// Gesichter ohne berechnete Schärfe – für den Nachlauf nach Schema 61.
  ///
  /// Nur solche mit gespeichertem Ausschnitt: Ohne ihn gäbe es nichts zu
  /// messen, und sie stünden bei jedem Lauf erneut in der Liste.
  Future<List<FaceData>> gesichterOhneSchaerfe() async {
    final zeilen = await (select(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
          ..where(_schaerfeOffen))
        .get();
    return [for (final z in zeilen) z.readTable(faces)];
  }

  /// Zählvariante von [gesichterOhneSchaerfe].
  Future<int> countGesichterOhneSchaerfe() async {
    final abfrage = selectOnly(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
      ..addColumns([faces.id.count()])
      ..where(_schaerfeOffen);
    final zeile = await abfrage.getSingle();
    return zeile.read(faces.id.count()) ?? 0;
  }

  /// Wessen Schärfe noch aussteht.
  ///
  /// **Gesperrte Aufnahmen bleiben draussen.** Ihr Ausschnitt liegt als
  /// Chiffrat auf der Platte; `decodeImage` gibt dafür `null` zurück, der
  /// Wert bliebe leer, und die Aufgabe fände dieselben Gesichter beim
  /// nächsten Lauf wieder. Eine Hintergrundaufgabe, die dauerhaft „noch N
  /// offen" meldet und nie fertig wird, ist schlimmer als eine, die es gar
  /// nicht gibt – und die Zahl gehört ausserdem zu den Auskünften, die der
  /// gesperrte Ordner nicht geben soll.
  Expression<bool> get _schaerfeOffen =>
      faces.schaerfe.isNull() &
      faces.cropRelativePath.isNotNull() &
      assets.isLocked.equals(false);

  /// Trägt einen neu gezeichneten Ausschnitt samt seiner Schärfe ein.
  Future<void> setzeGesichtsausschnitt(String faceId, String pfad,
          {double? schaerfe}) =>
      (update(faces)..where((f) => f.id.equals(faceId))).write(FacesCompanion(
        cropRelativePath: Value(pfad),
        schaerfe: schaerfe == null ? const Value.absent() : Value(schaerfe),
      ));

  Future<void> setzeGesichtsschaerfe(String faceId, double wert) =>
      (update(faces)..where((f) => f.id.equals(faceId)))
          .write(FacesCompanion(schaerfe: Value(wert)));

  /// Gesichter, fuer die noch kein Vorschlag gerechnet wurde.
  ///
  /// [alle] nimmt auch die schon geprueften wieder mit – der Weg, nachdem
  /// neue Personen benannt wurden: Ein Gesicht, zu dem es vor einem Monat
  /// keinen Kern gab, kann heute einen haben.
  ///
  /// [beiseite] entscheidet ueber die 14.065 beiseitegelegten. Sie sind
  /// standardmaessig **draussen**: Wer sie weggelegt hat, hat entschieden,
  /// und dieselbe Frage von selbst noch einmal zu stellen waere keine
  /// Hilfe, sondern Widerspruch. Als ausdruecklicher Durchgang lohnt es
  /// sich trotzdem – an der echten Bibliothek liegen dort 960 Gesichter,
  /// die heute ueber der Schwelle einer inzwischen benannten Person
  /// liegen.
  Expression<bool> _wiedererkennungOffen(
          {required bool alle, required bool beiseite}) =>
      faces.personId.isNull() &
      faces.embedding.isNotNull() &
      (beiseite
          ? const CustomExpression<bool>('1')
          : faces.isIgnored.equals(false)) &
      (alle
          ? const CustomExpression<bool>('1')
          : faces.vorschlagGeprueftAm.isNull());

  Future<List<FaceData>> gesichterFuerWiedererkennung(
      {bool alle = false, bool beiseite = false}) async {
    final zeilen = await (select(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
          ..where(_wiedererkennungOffen(alle: alle, beiseite: beiseite) &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false)))
        .get();
    return [for (final z in zeilen) z.readTable(faces)];
  }

  /// Zaehlvariante von [gesichterFuerWiedererkennung].
  Future<int> countWiedererkennungOffen(
          {bool alle = false, bool beiseite = false}) async =>
      _zaehleGesichter(_wiedererkennungOffen(alle: alle, beiseite: beiseite));

  /// Beiseitegelegte Gesichter, die noch nie mit den benannten Personen
  /// verglichen wurden.
  ///
  /// **Warum das eine eigene Zahl braucht.** Der Lauf nach dem Import
  /// sieht sie nicht an – sie sind entschieden. Wer aber, wie an der
  /// echten Bibliothek, **14.065** Gesichter weggelegt hat, bevor es die
  /// heutigen 45 Personen gab, hat dort 960 liegen, die heute einen Namen
  /// bekommen koennten. [countVorschlaege] meldet davon nichts: Ohne
  /// Durchgang gibt es keinen Vorschlag, und ohne Vorschlag keine Karte –
  /// die Funktion waere genau dort unsichtbar, wo sie gebraucht wird.
  Future<int> countBeiseiteNieVerglichen() => _zaehleGesichter(
      faces.personId.isNull() &
          faces.isIgnored.equals(true) &
          faces.embedding.isNotNull() &
          faces.vorschlagGeprueftAm.isNull());

  /// Wie viele Vorschlaege auf eine Entscheidung warten – die Zahl fuer
  /// den Gesundheitsbildschirm.
  ///
  /// Beiseitegelegte zaehlen hier **nicht** mit: Sie sind entschieden, und
  /// eine Zahl, die mehr verspricht als die Liste dahinter zeigt, ist
  /// schlimmer als keine (siehe [countOffeneGesichter]).
  Future<int> countVorschlaege({bool beiseite = false}) =>
      _zaehleGesichter(faces.personId.isNull() &
          faces.vorschlagPersonId.isNotNull() &
          faces.isIgnored.equals(beiseite));

  Future<int> _zaehleGesichter(Expression<bool> bedingung) async {
    final anzahl = faces.id.count();
    final zeile = await (selectOnly(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
          ..addColumns([anzahl])
          ..where(bedingung &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false)))
        .getSingle();
    return zeile.read(anzahl) ?? 0;
  }

  /// Schreibt das Ergebnis eines Wiedererkennungslaufs.
  ///
  /// **In einem Zug und nicht je Gesicht.** Bei den Ortsnamen kostete das
  /// einzeln 2131 ms gegen 139 ms in Bloecken; hier geht es um
  /// zehntausende Zeilen. Die Marke [Faces.vorschlagGeprueftAm] wird auch
  /// dort gesetzt, wo nichts gefunden wurde – sonst begaenne der naechste
  /// Lauf wieder von vorn.
  Future<void> merkeVorschlaege(
      List<({String faceId, String? personId, double? wert})> ergebnisse,
      {DateTime? jetzt}) async {
    if (ergebnisse.isEmpty) return;
    final zeitpunkt = jetzt ?? DateTime.now();
    await batch((b) {
      for (final e in ergebnisse) {
        b.update(
          faces,
          FacesCompanion(
            vorschlagPersonId: Value(e.personId),
            vorschlagWert: Value(e.wert),
            vorschlagGeprueftAm: Value(zeitpunkt),
          ),
          where: (t) => t.id.equals(e.faceId),
        );
      }
    });
  }

  /// Die wartenden Vorschlaege, nach Person gebuendelt und nach Menge
  /// sortiert.
  Future<List<({PersonData person, int anzahl})>> vorschlaegeJePerson(
      {bool beiseite = false}) async {
    // Erst zaehlen, dann die Personen dazuholen. Ein `readTable` auf die
    // gruppierte Abfrage geht nicht: Eine Gruppe ist keine Zeile der
    // Personentabelle, und drift sagt das auch so.
    final anzahl = faces.id.count();
    final zeilen = await (selectOnly(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
          ..addColumns([faces.vorschlagPersonId, anzahl])
          ..where(faces.personId.isNull() &
              faces.vorschlagPersonId.isNotNull() &
              faces.isIgnored.equals(beiseite) &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false))
          ..groupBy([faces.vorschlagPersonId]))
        .get();
    final mengen = {
      for (final z in zeilen)
        z.read(faces.vorschlagPersonId)!: z.read(anzahl) ?? 0,
    };
    if (mengen.isEmpty) return const [];
    final leute = await (select(people)
          ..where((t) => t.id.isIn(mengen.keys.toList())))
        .get();
    final liste = [
      for (final p in leute) (person: p, anzahl: mengen[p.id] ?? 0),
    ]..sort((a, b) => b.anzahl.compareTo(a.anzahl));
    return liste;
  }

  /// Die Vorschlaege zu einer Person, wie [PersonSuggestionsScreen] sie
  /// erwartet – absteigend nach Aehnlichkeit, das Sicherste zuerst.
  Future<List<({FaceData gesicht, double aehnlichkeit})>> vorschlaegeFuerPerson(
      String personId,
      {bool beiseite = false}) async {
    final zeilen = await (select(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
          ..where(faces.personId.isNull() &
              faces.vorschlagPersonId.equals(personId) &
              faces.isIgnored.equals(beiseite) &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false)))
        .get();
    final liste = [
      for (final z in zeilen)
        (gesicht: z.readTable(faces), aehnlichkeit: z.readTable(faces).vorschlagWert ?? 0),
    ]..sort((a, b) => b.aehnlichkeit.compareTo(a.aehnlichkeit));
    return liste;
  }

  /// Nimmt den Vorschlag von diesen Gesichtern weg – nach einer
  /// Ablehnung.
  ///
  /// Die Marke [Faces.vorschlagGeprueftAm] bleibt stehen: Der naechste
  /// Lauf soll dieselbe Frage nicht sofort wieder stellen. Erst ein Lauf
  /// mit „alle" fragt erneut, und bis dahin ist die Schwelle dieser
  /// Person durch die Ablehnung gestiegen.
  Future<void> verwirfVorschlaege(List<String> faceIds) =>
      (update(faces)..where((t) => t.id.isIn(faceIds))).write(
          const FacesCompanion(
              vorschlagPersonId: Value(null), vorschlagWert: Value(null)));

  Future<void> assignFacesToPerson(
      List<String> faceIds, String personId) async {
    // Wer einem beiseitegelegten Gesicht einen Namen gibt, hat es damit
    // zurückgeholt – sonst verschwände es unmittelbar nach dem Benennen
    // wieder aus der Personenansicht.
    await (update(faces)..where((t) => t.id.isIn(faceIds))).write(
        FacesCompanion(
            personId: Value(personId),
            isIgnored: const Value(false),
            // Der Vorschlag ist erledigt, sobald er angenommen wurde – er
            // stuende sonst weiter in der Warteschlange.
            vorschlagPersonId: const Value(null),
            vorschlagWert: const Value(null)));
    final assignedFaces =
        await (select(faces)..where((t) => t.id.isIn(faceIds))).get();
    final withCrop = assignedFaces.where((f) => f.cropRelativePath != null);
    if (withCrop.isNotEmpty) {
      await setPersonCoverIfUnset(personId, withCrop.first.cropRelativePath!);
    }
  }

  /// Der Stand der Gesichter vor einer Zuordnung – genau das, was
  /// [nimmZuordnungZurueck] zurückschreiben muss.
  ///
  /// Vorher lesen statt hinterher raten: Ein Gesicht kann schon jemandem
  /// gehört haben oder beiseitegelegt gewesen sein, und [assignFacesToPerson]
  /// holt Beiseitegelegtes ausdrücklich zurück.
  Future<List<Gesichtsstand>> gesichtsstand(List<String> faceIds) async {
    final rows = await (select(faces)..where((t) => t.id.isIn(faceIds))).get();
    return [
      for (final f in rows)
        (id: f.id, personId: f.personId, ignoriert: f.isIgnored),
    ];
  }

  /// Nimmt eine Zuordnung samt allem zurück, was sie ausgelöst hat.
  ///
  /// Eine Zuordnung ändert mehr als die eine Spalte: Sie holt
  /// beiseitegelegte Gesichter zurück, setzt gegebenenfalls das Titelbild
  /// der Person, legt Rückmeldungen für die lernende Wiedererkennung an und
  /// verschiebt damit deren Schwelle. Ein Rückgängig, das nur `person_id`
  /// leert, liesse die Person mit einem fremden Titelbild und einer
  /// Schwelle zurück, die aus einer zurückgenommenen Entscheidung stammt.
  ///
  /// [rueckmeldungenSeit] ist der Zeitpunkt, den
  /// [merkeGesichtsEntscheidungen] verwendet hat; `null`, wenn keine
  /// Rückmeldungen entstanden sind.
  Future<void> nimmZuordnungZurueck({
    required List<Gesichtsstand> gesichter,
    required String personId,
    required bool personWarNeu,
    required String? titelbildVorher,
    required DateTime? rueckmeldungenSeit,
    required double allgemeineSchwelle,
  }) async {
    if (gesichter.isEmpty) return;
    await transaction(() async {
      for (final g in gesichter) {
        await (update(faces)..where((t) => t.id.equals(g.id))).write(
          FacesCompanion(
              personId: Value(g.personId), isIgnored: Value(g.ignoriert)),
        );
      }
      if (rueckmeldungenSeit != null) {
        await (delete(faceMatchFeedback)
              ..where((t) =>
                  t.personId.equals(personId) &
                  t.faceId.isIn([for (final g in gesichter) g.id]) &
                  t.createdAt.isBiggerOrEqualValue(rueckmeldungenSeit)))
            .go();
      }
      if (personWarNeu) {
        // Die Person entstand allein für diese Zuordnung; ohne sie bliebe
        // ein leerer Name in der Liste stehen.
        await (delete(people)..where((t) => t.id.equals(personId))).go();
      } else {
        await (update(people)..where((t) => t.id.equals(personId))).write(
            PeopleCompanion(coverFaceCropPath: Value(titelbildVorher)));
        await _aktualisiereSchwelle(personId, allgemeineSchwelle);
      }
    });
  }

  // -----------------------------------------------------------------------
  // Lernende Wiedererkennung (siehe face_threshold.dart)
  // -----------------------------------------------------------------------

  /// Hält Entscheidungen über Wiedererkennungs-Vorschläge fest und führt
  /// die persönliche Schwelle der Person in einem Zug nach.
  ///
  /// Beides zusammen in einer Transaktion, damit die gespeicherte Schwelle
  /// nie zu einem anderen Satz Rückmeldungen gehört als dem, der in der
  /// Oberfläche als Begründung angezeigt wird.
  ///
  /// Gibt den Zeitpunkt zurück, unter dem die Rückmeldungen abgelegt wurden
  /// – [nimmZuordnungZurueck] braucht ihn, um genau diese Zeilen wieder zu
  /// entfernen und nicht ältere zu derselben Person. `null`, wenn nichts
  /// abzulegen war.
  Future<DateTime?> merkeGesichtsEntscheidungen(
    String personId,
    List<({String faceId, bool accepted, double similarity})> entscheidungen, {
    required double allgemeineSchwelle,
  }) async {
    if (entscheidungen.isEmpty) return null;
    final jetzt = DateTime.now();
    await transaction(() async {
      await batch((b) => b.insertAll(faceMatchFeedback, [
            for (final e in entscheidungen)
              FaceMatchFeedbackCompanion.insert(
                personId: personId,
                faceId: e.faceId,
                accepted: e.accepted,
                similarity: e.similarity,
                createdAt: jetzt,
              ),
          ]));
      await _aktualisiereSchwelle(personId, allgemeineSchwelle);
    });
    return jetzt;
  }

  Future<void> _aktualisiereSchwelle(String personId, double allgemein) async {
    final rueckmeldungen = await gesichtsRueckmeldungen(personId);
    final abgeleitet = leiteSchwelleAb(rueckmeldungen, allgemein);
    await (update(people)..where((t) => t.id.equals(personId))).write(
      // Genau die allgemeine Schwelle wird als "nichts Eigenes" gespeichert
      // – sonst wanderte sie nicht mit, wenn der Nutzer die allgemeine
      // später in den Werkzeugen ändert.
      PeopleCompanion(
          similarityThreshold:
              Value(abgeleitet == allgemein ? null : abgeleitet)),
    );
  }

  Future<List<GesichtsRueckmeldung>> gesichtsRueckmeldungen(
      String personId) async {
    final rows = await (select(faceMatchFeedback)
          ..where((t) => t.personId.equals(personId)))
        .get();
    return [
      for (final r in rows)
        GesichtsRueckmeldung(
            bestaetigt: r.accepted, aehnlichkeit: r.similarity),
    ];
  }

  /// Verwirft alles Gelernte zu einer Person – der Ausweg, wenn die
  /// Anpassung einmal danebenliegt und der Nutzer nicht nachvollziehen
  /// kann, warum.
  Future<void> vergissGesichtsEntscheidungen(String personId) =>
      transaction(() async {
        await (delete(faceMatchFeedback)
              ..where((t) => t.personId.equals(personId)))
            .go();
        await (update(people)..where((t) => t.id.equals(personId)))
            .write(const PeopleCompanion(similarityThreshold: Value(null)));
      });

  /// Rechnet die persönlichen Schwellen aller Personen neu.
  ///
  /// Nötig, wenn der Nutzer die allgemeine Schwelle ändert: Die
  /// persönlichen sind daran gebunden (Ausgangspunkt und Deckel), sonst
  /// hätte der Regler in den Werkzeugen für gelernte Personen keine
  /// Wirkung mehr.
  Future<void> rechneAlleSchwellenNeu(double allgemein) async {
    for (final person in await select(people).get()) {
      await _aktualisiereSchwelle(person.id, allgemein);
    }
  }

  /// Setzt das Profilbild einer Person auf den Foto-Ausschnitt (Crop) eines
  /// bestimmten Gesichts – sowohl für die automatische Erstzuordnung als
  /// auch für die manuelle Auswahl in der Personen-Detailansicht.
  Future<void> setPersonCover(String personId, String cropRelativePath) =>
      (update(people)..where((t) => t.id.equals(personId)))
          .write(PeopleCompanion(coverFaceCropPath: Value(cropRelativePath)));

  /// Wie [setPersonCover], setzt das Profilbild aber nur, wenn die Person
  /// noch keins hat – wird beim automatischen Zuordnen eines Gesichts
  /// aufgerufen, damit ein bereits manuell gewähltes Profilbild nicht
  /// überschrieben wird.
  Future<void> setPersonCoverIfUnset(
      String personId, String cropRelativePath) async {
    final person = await (select(people)..where((t) => t.id.equals(personId)))
        .getSingleOrNull();
    if (person != null && person.coverFaceCropPath == null) {
      await setPersonCover(personId, cropRelativePath);
    }
  }

  /// Führt zwei Personen zusammen: alle Gesichter von [removePersonId] werden
  /// [keepPersonId] zugeordnet, anschließend wird die überflüssige
  /// Personen-Zeile gelöscht. Nützlich, wenn die Gesichtserkennung
  /// dieselbe reale Person versehentlich als zwei Personen angelegt hat.
  Future<void> mergePeople(
      {required String keepPersonId, required String removePersonId}) async {
    await transaction(() async {
      await (update(faces)..where((t) => t.personId.equals(removePersonId)))
          .write(FacesCompanion(personId: Value(keepPersonId)));
      // Die Verwandtschaften der aufgelösten Person würden sonst ins Leere
      // zeigen: Kanten auf eine nicht mehr vorhandene Kennung erscheinen im
      // Stammbaum als namenlose Karte. Übertragen statt löschen – wer zwei
      // Einträge derselben Person zusammenführt, will deren Familie
      // behalten.
      await _uebertrageBeziehungen(removePersonId, keepPersonId);
      await (delete(people)..where((t) => t.id.equals(removePersonId))).go();
    });
  }

  // -----------------------------------------------------------------------
  // Stammbaum (siehe services/stammbaum.dart)
  // -----------------------------------------------------------------------

  /// Alle Verwandtschaften. Als vollständige Liste und nicht je Person
  /// abgefragt: Der Stammbaum braucht für seine Hinweise („hat noch Eltern")
  /// ohnehin die Nachbarschaft der Nachbarn, und die Tabelle bleibt selbst
  /// bei einer sehr großen Familie klein gegenüber allem anderen hier.
  Stream<List<PersonBeziehungenData>> watchBeziehungen() =>
      select(personBeziehungen).watch();

  Future<List<PersonBeziehungenData>> alleBeziehungen() =>
      select(personBeziehungen).get();

  /// Trägt eine Verwandtschaft ein.
  ///
  /// Die Prüfung läuft hier und nicht nur in der Oberfläche: Ein Kreis
  /// („jemand ist sein eigener Urgroßvater") ließe jede Auswertung nach
  /// oben endlos laufen, und das wäre nach dem Speichern nicht mehr
  /// bequem zu heilen. Gibt den Grund zurück, wenn nichts eingetragen
  /// wurde.
  Future<Beziehungsfehler?> fuegeBeziehungHinzu(
    String personId,
    String andereId,
    Verwandtschaft art,
  ) async {
    final netz = Verwandtschaftsnetz(await _kanten());
    final fehler = pruefeBeziehung(netz, personId, andereId, art);
    if (fehler != null) return fehler;
    final k = art == Verwandtschaft.partner
        ? partnerKanteFuer(personId, andereId)
        : kante(personId, andereId, art);
    await into(personBeziehungen).insert(PersonBeziehungenCompanion.insert(
      personId: k.personId,
      andereId: k.andereId,
      art: artZuText(k.art),
    ));
    return null;
  }

  /// Trägt mehrere Verwandtschaften auf einmal ein – für die Grade, die
  /// über eine Zwischenperson entstehen (siehe verwandte_anlegen.dart).
  ///
  /// In einer Transaktion, weil ein Geschwisterkind an beiden Eltern
  /// gleichzeitig hängt: Bräche der zweite Eintrag ab, stünde ein
  /// Halbgeschwisterkind im Baum, das nie jemand so gemeint hat.
  ///
  /// Die Prüfung läuft je Kante gegen den **fortgeschriebenen** Stand, nicht
  /// gegen den Anfangszustand – sonst könnten zwei Kanten eines Aufrufs
  /// gemeinsam einen Kreis schliessen, den keine für sich geschlossen hätte.
  ///
  /// Gibt den ersten Grund zurück, an dem es scheiterte; dann wurde nichts
  /// geschrieben.
  Future<Beziehungsfehler?> fuegeBeziehungenHinzu(List<Kante> kanten) async {
    if (kanten.isEmpty) return null;
    try {
      await transaction(() async {
        final gesammelt = <Kante>[...await _kanten()];
        for (final k in kanten) {
          final netz = Verwandtschaftsnetz(gesammelt);
          final fehler = pruefeBeziehung(netz, k.personId, k.andereId, k.art);
          // Der Wurf rollt die Transaktion zurück und macht damit auch die
          // bereits eingefügten Kanten dieses Aufrufs rückgängig.
          if (fehler != null) throw _BeziehungAbbruch(fehler);
          final fest = k.art == Verwandtschaft.partner
              ? partnerKanteFuer(k.personId, k.andereId)
              : k;
          await into(personBeziehungen)
              .insert(PersonBeziehungenCompanion.insert(
            personId: fest.personId,
            andereId: fest.andereId,
            art: artZuText(fest.art),
          ));
          gesammelt.add(fest);
        }
      });
      return null;
    } on _BeziehungAbbruch catch (e) {
      return e.grund;
    }
  }

  /// Entfernt eine Verwandtschaft. Bei Partnerschaften ist die
  /// Eingaberichtung gleichgültig – gespeichert ist nur eine Zeile.
  ///
  /// Bei einer Elternverbindung wird die Art **nicht** mitverglichen: Zwei
  /// Menschen können nur auf genau eine Weise Eltern und Kind sein (das
  /// stellt [pruefeBeziehung] sicher), also ist „löse diese
  /// Elternverbindung" auch ohne die Art eindeutig.
  ///
  /// Vorher stand hier ein Vergleich auf die genaue Art – und die
  /// Oberfläche übergab für jede Elternreihe fest „leiblich". Bei einem
  /// Adoptiv- oder Pflegeelternteil traf die Bedingung deshalb keine
  /// Zeile: Es passierte nichts, ohne Fehler, ohne Hinweis.
  ///
  /// Gibt zurück, ob tatsächlich etwas entfernt wurde. Ein Aufrufer, der
  /// ins Leere greift, soll das erfahren können statt es zu vermuten.
  Future<bool> entferneBeziehung(
    String personId,
    String andereId,
    Verwandtschaft art,
  ) async {
    final k = art == Verwandtschaft.partner
        ? partnerKanteFuer(personId, andereId)
        : kante(personId, andereId, art);
    final betroffen = await (delete(personBeziehungen)
          ..where((t) {
            final gleicheStelle =
                t.personId.equals(k.personId) & t.andereId.equals(k.andereId);
            return istElternArt(k.art)
                ? gleicheStelle &
                    t.art.isIn([for (final e in elternArten) artZuText(e)])
                : gleicheStelle & t.art.equals(artZuText(k.art));
          }))
        .go();
    return betroffen > 0;
  }

  /// Ändert die Art einer bestehenden Elternverbindung – aus „leiblich"
  /// wird „Adoptiv", ohne die Verbindung erst zu lösen und neu zu legen.
  ///
  /// Die Art steht im Primärschlüssel, deshalb ist es kein einfaches
  /// Ändern der Spalte, sondern Entfernen und Neuanlegen – beides in einer
  /// Transaktion, damit die Verbindung nie zwischendurch fehlt.
  ///
  /// Gibt zurück, ob es die Verbindung überhaupt gab.
  Future<bool> aendereElternart(
    String kindId,
    String elternteilId,
    Verwandtschaft neueArt,
  ) async {
    if (!istElternArt(neueArt)) return false;
    return transaction(() async {
      final entfernt = await entferneBeziehung(kindId, elternteilId, neueArt);
      if (!entfernt) return false;
      await into(personBeziehungen).insert(PersonBeziehungenCompanion.insert(
        personId: kindId,
        andereId: elternteilId,
        art: artZuText(neueArt),
      ));
      return true;
    });
  }

  Future<List<Kante>> _kanten() async {
    final zeilen = await alleBeziehungen();
    return [
      for (final z in zeilen)
        if (artAusText(z.art) case final art?)
          kante(z.personId, z.andereId, art),
    ];
  }

  /// Hängt alle Kanten von [vonId] auf [aufId] um – für [mergePeople].
  ///
  /// Kanten, die dabei zur Selbstbeziehung würden (die beiden waren
  /// miteinander verwandt eingetragen), fallen weg statt einen Kreis zu
  /// bilden. Doppelte ebenfalls: `insertOnConflictUpdate` würde die
  /// bestehende Zeile nur mit sich selbst überschreiben.
  Future<void> _uebertrageBeziehungen(String vonId, String aufId) async {
    final betroffen = await (select(personBeziehungen)
          ..where((t) => t.personId.equals(vonId) | t.andereId.equals(vonId)))
        .get();
    await (delete(personBeziehungen)
          ..where((t) => t.personId.equals(vonId) | t.andereId.equals(vonId)))
        .go();
    for (final z in betroffen) {
      final art = artAusText(z.art);
      if (art == null) continue;
      final person = z.personId == vonId ? aufId : z.personId;
      final andere = z.andereId == vonId ? aufId : z.andereId;
      if (person == andere) continue;
      final k = art == Verwandtschaft.partner
          ? partnerKanteFuer(person, andere)
          : kante(person, andere, art);
      await into(personBeziehungen).insert(
        PersonBeziehungenCompanion.insert(
          personId: k.personId,
          andereId: k.andereId,
          art: artZuText(k.art),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  // -----------------------------------------------------------------------
  // Lebensereignisse (siehe services/lebenslauf.dart)
  // -----------------------------------------------------------------------

  Stream<List<LebensereignisseData>> watchEreignisse(String personId) =>
      (select(lebensereignisse)..where((t) => t.personId.equals(personId)))
          .watch();

  Future<void> fuegeEreignisHinzu(LebensereignisseCompanion ereignis) =>
      into(lebensereignisse).insert(ereignis);

  Future<void> loescheEreignis(String id) =>
      (delete(lebensereignisse)..where((t) => t.id.equals(id))).go();

  /// Übernimmt eine eingelesene GEDCOM-Datei – Personen, Ereignisse und
  /// Verwandtschaften in einem Zug.
  ///
  /// In **einer** Transaktion, weil eine halb eingelesene Datei der
  /// schlechteste aller Zustände wäre: Personen ohne ihre
  /// Verwandtschaften sehen aus wie richtige Einträge, und niemand
  /// könnte hinterher sagen, wo der Abbruch war.
  ///
  /// Die Kanten laufen hier **nicht** noch einmal durch
  /// [pruefeBeziehung], anders als bei [fuegeBeziehungenHinzu]. Zwei
  /// Gründe: Der Einleser hat die Datei bereits gegen Kreise geprüft
  /// (siehe `gedcom_import.dart`), und jede Person dieser Datei wird
  /// **neu** angelegt – eine Kante zwischen zwei frischen Kennungen kann
  /// mit dem Bestand keinen Kreis bilden, weil sie ihn nirgends berührt.
  /// Die Prüfung je Kante gegen den fortgeschriebenen Stand wäre bei
  /// dreitausend Personen ausserdem quadratisch.
  Future<void> uebernehmeGedcom({
    required List<PeopleCompanion> personen,
    required List<Kante> kanten,
    required List<LebensereignisseCompanion> ereignisse,
  }) =>
      transaction(() async {
        await batch((b) {
          b.insertAll(people, personen);
          b.insertAll(lebensereignisse, ereignisse);
          b.insertAll(personBeziehungen, [
            for (final k in kanten)
              PersonBeziehungenCompanion.insert(
                personId: k.personId,
                andereId: k.andereId,
                art: artZuText(k.art),
              ),
          ]);
        });
      });

  /// Ereignisse mit Ortsnamen, aber noch ohne Koordinate.
  ///
  /// Die Grundlage für das einmalige Nachtragen (siehe
  /// `LibraryState.trageEreignisorteNach`). Bewusst nur die ohne
  /// Koordinate: Ein von Hand berichtigter Punkt darf nicht bei jedem
  /// Start wieder überschrieben werden.
  Future<List<LebensereignisseData>> ereignisseOhneKoordinate() =>
      (select(lebensereignisse)
            ..where((t) =>
                t.ort.isNotNull() &
                t.ort.equals('').not() &
                t.ortBreite.isNull()))
          .get();

  /// Alle Ereignisse, die auf einer Karte darstellbar sind.
  Future<List<LebensereignisseData>> ereignisseMitKoordinate() =>
      (select(lebensereignisse)..where((t) => t.ortBreite.isNotNull())).get();

  /// Alle verorteten Ereignisse der Bibliothek, samt Personennamen –
  /// für die allgemeine Karte, die keine Familie eingrenzt.
  Future<List<({LebensereignisseData ereignis, String personName})>>
      ereignisseMitKoordinateUndName() async {
    final abfrage = select(lebensereignisse).join([
      innerJoin(people, people.id.equalsExp(lebensereignisse.personId)),
    ])
      ..where(lebensereignisse.ortBreite.isNotNull());
    final zeilen = await abfrage.get();
    return [
      for (final z in zeilen)
        (
          ereignis: z.readTable(lebensereignisse),
          personName: z.readTable(people).name,
        ),
    ];
  }

  /// Verortete Ereignisse bestimmter Personen, samt deren Namen.
  ///
  /// Der Name kommt gleich mit: Ein Punkt auf der Familienkarte ohne die
  /// Person, zu der er gehört, beantwortet keine Frage.
  Future<List<({LebensereignisseData ereignis, String personName})>>
      verorteteEreignisseFuerPersonen(List<String> personIds) async {
    if (personIds.isEmpty) return const [];
    final abfrage = select(lebensereignisse).join([
      innerJoin(people, people.id.equalsExp(lebensereignisse.personId)),
    ])
      ..where(lebensereignisse.ortBreite.isNotNull() &
          lebensereignisse.personId.isIn(personIds));
    final zeilen = await abfrage.get();
    return [
      for (final z in zeilen)
        (
          ereignis: z.readTable(lebensereignisse),
          personName: z.readTable(people).name,
        ),
    ];
  }

  // ------------------------------------------------------------------
  // Reisen
  // ------------------------------------------------------------------

  // **Der gesperrte Ordner bleibt aus ALLEN Abfragen dieses Abschnitts
  // heraus** – auch aus denen, die nichts anzeigen.
  //
  // Nicht nur aus dem Raster: Eine gesperrte Aufnahme, die an der
  // Reiseerkennung teilnimmt, landet in einer bestätigten Reise und wird
  // dann angezeigt. Und selbst der Länderzähler verriete etwas – ein
  // Land, das nur auf gesperrten Fotos vorkommt, stünde dort und sagte
  // „da war jemand".
  //
  // Eine Regel für alle statt vier Einzelfallentscheidungen. Wer die Orte
  // gesperrter Aufnahmen sehen will, öffnet den gesperrten Ordner – dort
  // gehören sie hin.
  //
  // Der Unterschied zu Abfragen wie `assetsForLocationBackfill`, die
  // gesperrte Aufnahmen bewusst mitnehmen: Jene **verarbeiten** nur. Die
  // hier münden alle in eine Anzeige.

  Stream<List<ReisenData>> watchReisen() =>
      (select(reisen)..orderBy([(t) => OrderingTerm.desc(t.von)])).watch();

  Future<List<ReisenData>> alleReisen() =>
      (select(reisen)..orderBy([(t) => OrderingTerm.desc(t.von)])).get();

  Future<ReisenData?> reise(String id) =>
      (select(reisen)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Legt eine bestätigte Reise samt ihren Aufnahmen an.
  ///
  /// In einer Transaktion: Eine Reise ohne ihre Aufnahmen sähe aus wie
  /// eine leere Reise, und niemand könnte hinterher sagen, ob sie so
  /// gemeint war.
  Future<void> reiseAnlegen(
    ReisenCompanion reise,
    List<String> assetIds,
  ) =>
      transaction(() async {
        await into(reisen).insert(reise);
        await batch((b) => b.insertAll(reiseAufnahmen, [
              for (final id in assetIds)
                ReiseAufnahmenCompanion.insert(
                    reiseId: reise.id.value, assetId: id),
            ]));
      });

  Future<void> reiseLoeschen(String id) => transaction(() async {
        await (delete(reiseAufnahmen)..where((t) => t.reiseId.equals(id))).go();
        // Sonst blieben die Tagesnotizen einer geloeschten Reise stehen
        // und taeten so, als gehoerten sie zur naechsten mit derselben
        // Kennung - dieselbe Sorte Rest wie die verwaisten
        // Gesichtsausschnitte der 8. Pruefrunde.
        await (delete(reisetagnotizen)..where((t) => t.reiseId.equals(id)))
            .go();
        // **Aktivitäten und Spuren überleben, ihre Reise nicht.** Sie
        // hingen bisher an der Kennung der gelöschten Reise weiter: eine
        // Wanderung, die zu einer Reise gehört, die es nicht mehr gibt.
        // Gezeigt hätte sie „Gehört zu: " und nichts dahinter.
        await (update(aktivitaeten)..where((t) => t.reiseId.equals(id)))
            .write(const AktivitaetenCompanion(reiseId: Value(null)));
        await (update(spuren)..where((t) => t.reiseId.equals(id)))
            .write(const SpurenCompanion(reiseId: Value(null)));
        await (delete(reisen)..where((t) => t.id.equals(id))).go();
      });

  /// Führt Reisen zusammen: Die [quellen] gehen in [ziel] auf.
  ///
  /// **Warum es das braucht.** Die Erkennung trennt zwei Reisen, sobald
  /// mehr als zwei Tage ohne Aufnahme dazwischenliegen (siehe
  /// `reiseLueckeTage`). Bei einem Urlaub ist das richtig; bei einem
  /// langen Aufenthalt ist es genau falsch – die 199 verorteten
  /// Aufnahmen eines zweimonatigen Auslandseinsatzes zerfielen dadurch
  /// in vier Vorschläge von 25, 63, 89 und 20 Bildern, und zwei weitere
  /// fielen ganz heraus, weil sie unter der Mindestzahl blieben. Ein
  /// Einsatz ist keine Reise mit Lücken; er *ist* die Lücken.
  ///
  /// Die Schwelle deshalb zu lockern wäre der falsche Griff: Sie ist für
  /// den Regelfall richtig, und wer sie hochsetzt, bekommt aus zwei
  /// Wochenenden im selben Monat eine Reise. Zusammenführen ist die
  /// Entscheidung eines Menschen, und die trifft er einmal.
  ///
  /// **[ziel] behält Namen, Art, Titelbild und Notiz** – es ist die
  /// Reise, die stehenbleibt. Zeitraum und Aufnahmen wachsen um die der
  /// Quellen; Tagesnotizen kommen mit, wo das Ziel für den Tag noch
  /// keine hat. Aktivitäten und Spuren der Quellen hängen danach am Ziel.
  Future<void> reisenZusammenfuehren(String ziel, List<String> quellen) async {
    final andere = quellen.where((q) => q != ziel).toList();
    if (andere.isEmpty) return;
    final platzhalter = List.filled(andere.length, '?').join(', ');

    await transaction(() async {
      // `OR IGNORE`: Eine Aufnahme, die in beiden Reisen steht, ist kein
      // Fehler – sie steht danach einmal in der einen.
      await customStatement(
        'INSERT OR IGNORE INTO reise_aufnahmen (reise_id, asset_id) '
        'SELECT ?, asset_id FROM reise_aufnahmen WHERE reise_id IN ($platzhalter)',
        [ziel, ...andere],
      );
      // Beim Tag gewinnt die Notiz des Ziels: Sie ist die, die
      // stehenbleibt, und zwei Sätze zu einem Tag zusammenzukleben
      // ergäbe einen dritten, den niemand geschrieben hat.
      await customStatement(
        'INSERT OR IGNORE INTO reisetagnotizen '
        '(reise_id, tag, notiz, geaendert_am) '
        'SELECT ?, tag, notiz, geaendert_am FROM reisetagnotizen '
        'WHERE reise_id IN ($platzhalter)',
        [ziel, ...andere],
      );
      await (update(aktivitaeten)..where((t) => t.reiseId.isIn(andere)))
          .write(AktivitaetenCompanion(reiseId: Value(ziel)));
      await (update(spuren)..where((t) => t.reiseId.isIn(andere)))
          .write(SpurenCompanion(reiseId: Value(ziel)));
      await (delete(reiseAufnahmen)..where((t) => t.reiseId.isIn(andere))).go();
      await (delete(reisetagnotizen)..where((t) => t.reiseId.isIn(andere)))
          .go();
      await (delete(reisen)..where((t) => t.id.isIn(andere))).go();

      // **Zeitraum aus den Aufnahmen und nicht aus den Reisen.** Wer
      // eine Aufnahme aus einer der Quellen genommen hatte, soll ihren
      // Tag nicht über den Umweg des gespeicherten Zeitraums
      // zurückbekommen.
      final frueheste = assets.fileCreatedAt.min();
      final spaeteste = assets.fileCreatedAt.max();
      final spanne = await (selectOnly(reiseAufnahmen).join([
        innerJoin(assets, assets.id.equalsExp(reiseAufnahmen.assetId)),
      ])
            ..addColumns([frueheste, spaeteste])
            ..where(reiseAufnahmen.reiseId.equals(ziel)))
          .getSingleOrNull();
      final anfang = spanne?.read(frueheste);
      final ende = spanne?.read(spaeteste);
      if (anfang != null && ende != null) {
        await (update(reisen)..where((t) => t.id.equals(ziel)))
            .write(ReisenCompanion(
          von: Value(anfang),
          bis: Value(ende),
        ));
      }
    });
  }

  /// Die Tagesnotizen einer Reise, nach Tag.
  ///
  /// Als Karte und nicht als Liste: Die Ansicht fragt je Kapitel genau
  /// einen Tag ab, und eine Liste hiesse, sie bei jedem Kapitel erneut
  /// zu durchsuchen.
  Future<Map<DateTime, String>> reisetagnotizenFuer(String reiseId) async {
    final zeilen = await (select(reisetagnotizen)
          ..where((t) => t.reiseId.equals(reiseId)))
        .get();
    return {for (final z in zeilen) z.tag: z.notiz};
  }

  /// Schreibt die Notiz eines Reisetages – leerer Text loescht sie.
  ///
  /// Leer heisst „keine Notiz" und nicht „eine leere Notiz": Sonst
  /// stuende unter der Ueberschrift ein leerer Absatz, und das Kapitel
  /// saehe aus, als fehle etwas.
  Future<void> setzeReisetagnotiz(
      String reiseId, DateTime tag, String text) async {
    final tagesbeginn = DateTime(tag.year, tag.month, tag.day);
    final sauber = text.trim();
    if (sauber.isEmpty) {
      await (delete(reisetagnotizen)
            ..where(
                (t) => t.reiseId.equals(reiseId) & t.tag.equals(tagesbeginn)))
          .go();
      return;
    }
    await into(reisetagnotizen).insertOnConflictUpdate(
        ReisetagnotizenCompanion.insert(
            reiseId: reiseId,
            tag: tagesbeginn,
            notiz: sauber,
            geaendertAm: DateTime.now()));
  }

  Future<void> reiseAendern(String id, ReisenCompanion aenderung) =>
      (update(reisen)..where((t) => t.id.equals(id))).write(aenderung);

  /// Die Aufnahmen einer Reise, chronologisch.
  ///
  /// Gelöschte und in den Papierkorb gelegte fallen heraus – eine Reise
  /// soll nicht auf Bilder verweisen, die es nicht mehr gibt.
  Future<List<AssetData>> aufnahmenDerReise(String reiseId) async {
    final abfrage = select(assets).join([
      innerJoin(reiseAufnahmen, reiseAufnahmen.assetId.equalsExp(assets.id)),
    ])
      ..where(reiseAufnahmen.reiseId.equals(reiseId) &
          assets.isTrashed.equals(false) &
          // Siehe die Regel am Anfang dieses Abschnitts.
          assets.isLocked.equals(false))
      ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)]);
    return [for (final z in await abfrage.get()) z.readTable(assets)];
  }

  /// Nur die erste Aufnahme einer Reise – für das Vorschaubild in der
  /// Liste.
  ///
  /// Eine eigene Abfrage mit `LIMIT 1` statt [aufnahmenDerReise] und
  /// `.first`. Gemessen an zwanzig Reisen mit je dreihundert Aufnahmen:
  /// 5865 geladene Zeilen und 92 ms, um zwanzig Vorschaubilder zu zeigen.
  /// Der Aufwand wächst mit der Größe der Reisen, der Nutzen nicht.
  Future<AssetData?> ersteAufnahmeDerReise(String reiseId) async {
    final abfrage = select(assets).join([
      innerJoin(reiseAufnahmen, reiseAufnahmen.assetId.equalsExp(assets.id)),
    ])
      ..where(reiseAufnahmen.reiseId.equals(reiseId) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false))
      ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)])
      ..limit(1);
    final zeile = await abfrage.getSingleOrNull();
    return zeile?.readTable(assets);
  }

  /// Der Ortsbezug jeder Reise, in einer Abfrage für alle.
  ///
  /// **Warum nicht je Zeile nachschlagen.** Die Übersicht zeigt zu jeder
  /// Reise, wo sie stattfand. Der Ort steht aber nicht an der Reise – er
  /// steht an ihren Aufnahmen, und zwar an jeder einzelnen. Für eine
  /// Liste von dreissig Reisen hiesse „je Zeile nachschlagen" dreissig
  /// Abfragen über zusammen mehrere tausend Aufnahmen, nur um drei
  /// Wörter anzuzeigen.
  ///
  /// Gruppiert liefert dieselbe Auskunft eine einzige Abfrage: je Reise
  /// und Ort eine Zeile mit Anzahl. Das sind auch bei grossen
  /// Bibliotheken wenige hundert Zeilen, weil zusammengefasst wird, was
  /// gleich ist.
  Future<Map<String, Ortsbezug>> ortsbezugJeReise() =>
      _ortsbezug('reise_aufnahmen', 'reise_id', reiseAufnahmen);

  /// Der Ortsbezug jeder Aktivität – wie [ortsbezugJeReise].
  Future<Map<String, Ortsbezug>> ortsbezugJeAktivitaet() =>
      _ortsbezug('aktivitaet_aufnahmen', 'aktivitaet_id', aktivitaetAufnahmen);

  Future<Map<String, Ortsbezug>> _ortsbezug(
      String tabelle, String spalte, TableInfo zuordnung) async {
    // **CROSS JOIN und nicht JOIN, und das ist keine Kosmetik.** In
    // SQLite ist beides bedeutungsgleich; `CROSS` schaltet nur die
    // Umsortierung der Schleifen ab und legt fest, dass die
    // **Zuordnungstabelle** aussen läuft.
    //
    // Ohne das entscheidet der Planer falsch herum: Er sieht den Index
    // über `is_trashed`/`is_locked`, hält ihn für den engeren Filter und
    // beginnt bei den Aufnahmen. Für jede einzelne davon schlägt er dann
    // in der Zuordnung nach — auch für die neunundneunzig Prozent, die
    // zu gar keiner Reise gehören. An einer auf 103.844 Aufnahmen
    // aufgeblasenen Kopie der echten Bibliothek nachgemessen, bei 423
    // Zuordnungen:
    //
    // ```
    // JOIN        SEARCH a USING idx_assets_trashed_locked_created   36,5 ms
    // CROSS JOIN  SCAN z USING COVERING INDEX, SEARCH a (id=?)        0,3 ms
    // ```
    //
    // Heute, bei 7.988 Aufnahmen, sind es 20 ms — nicht zu spüren.
    // Genau deshalb steht die Messung hier: Der Unterschied wächst mit
    // der Bibliothek, die Zuordnungstabelle wächst nicht mit.
    final zeilen = await customSelect(
      'SELECT z.$spalte AS kennung, a.location_city AS ort, '
      '       a.location_state AS region, a.location_country AS land, '
      '       COUNT(*) AS anzahl '
      'FROM $tabelle z CROSS JOIN assets a ON a.id = z.asset_id '
      'WHERE a.is_trashed = 0 AND a.is_locked = 0 '
      'GROUP BY z.$spalte, a.location_city, a.location_state, '
      '         a.location_country',
      readsFrom: {assets, zuordnung},
    ).get();

    // Je Kennung: die Aufnahmen zusammenzählen und den häufigsten Ort
    // behalten. Bei Gleichstand gewinnt der alphabetisch erste - nicht
    // weil er der bessere wäre, sondern damit dieselbe Bibliothek
    // zweimal dasselbe anzeigt.
    final gesamt = <String, int>{};
    final beste =
        <String, ({String ort, String? region, String? land, int n})>{};
    final orte = <String, Set<String>>{};
    for (final z in zeilen) {
      final kennung = z.read<String>('kennung');
      final anzahl = z.read<int>('anzahl');
      gesamt[kennung] = (gesamt[kennung] ?? 0) + anzahl;

      final ort = z.read<String?>('ort');
      if (ort == null || ort.isEmpty) continue;
      orte.putIfAbsent(kennung, () => <String>{}).add(ort);
      final bisher = beste[kennung];
      if (bisher == null ||
          anzahl > bisher.n ||
          (anzahl == bisher.n && ort.compareTo(bisher.ort) < 0)) {
        beste[kennung] = (
          ort: ort,
          region: z.read<String?>('region'),
          land: z.read<String?>('land'),
          n: anzahl,
        );
      }
    }

    return {
      for (final kennung in gesamt.keys)
        kennung: (
          ort: beste[kennung]?.ort,
          region: beste[kennung]?.region,
          land: beste[kennung]?.land,
          // Der häufigste zählt nicht als „weiterer".
          weitereOrte:
              (orte[kennung]?.length ?? 0) == 0 ? 0 : orte[kennung]!.length - 1,
          aufnahmen: gesamt[kennung]!,
        ),
    };
  }

  /// Welche Aufnahmen bereits einer Reise zugeordnet sind.
  Future<Set<String>> zugeordneteReiseAufnahmen() async =>
      {for (final z in await select(reiseAufnahmen).get()) z.assetId};

  Future<void> aufnahmenZurReise(String reiseId, List<String> assetIds) =>
      batch((b) => b.insertAll(
            reiseAufnahmen,
            [
              for (final id in assetIds)
                ReiseAufnahmenCompanion.insert(reiseId: reiseId, assetId: id),
            ],
            mode: InsertMode.insertOrIgnore,
          ));

  Future<void> aufnahmeAusReise(String reiseId, String assetId) => (delete(
          reiseAufnahmen)
        ..where((t) => t.reiseId.equals(reiseId) & t.assetId.equals(assetId)))
      .go();

  // ---------------------------------------------------------------
  // Aktivitäten. Dieselbe Bauart wie die Reisen darüber – bis auf die
  // eine Stelle, an der sie sich unterscheiden: `reiseId` darf leer
  // bleiben.

  /// Alle Aktivitäten, jüngste zuerst.
  Future<List<AktivitaetenData>> alleAktivitaeten() =>
      (select(aktivitaeten)..orderBy([(t) => OrderingTerm.desc(t.von)])).get();

  /// Dasselbe als Strom – für Übersichten, die sich selbst nachführen
  /// sollen (Erkunden). Gegenstück zu [watchReisen].
  Stream<List<AktivitaetenData>> watchAktivitaeten() =>
      (select(aktivitaeten)..orderBy([(t) => OrderingTerm.desc(t.von)]))
          .watch();

  Future<AktivitaetenData?> aktivitaet(String id) =>
      (select(aktivitaeten)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Die Aktivitäten einer Reise, chronologisch **aufsteigend**.
  ///
  /// Anders als die Liste der Reisen: Innerhalb einer Reise liest man
  /// vorwärts – erster Tag zuerst –, wie die Tageskapitel daneben.
  Future<List<AktivitaetenData>> aktivitaetenDerReise(String reiseId) =>
      (select(aktivitaeten)
            ..where((t) => t.reiseId.equals(reiseId))
            ..orderBy([(t) => OrderingTerm.asc(t.von)]))
          .get();

  /// Aktivitäten, die zu keiner Reise gehören – jüngste zuerst.
  Future<List<AktivitaetenData>> aktivitaetenOhneReise() =>
      (select(aktivitaeten)
            ..where((t) => t.reiseId.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.von)]))
          .get();

  /// Legt eine bestätigte Aktivität samt ihren Aufnahmen an – in einer
  /// Transaktion, aus demselben Grund wie bei [reiseAnlegen].
  Future<void> aktivitaetAnlegen(
    AktivitaetenCompanion neue,
    List<String> assetIds,
  ) =>
      transaction(() async {
        await into(aktivitaeten).insert(neue);
        await batch((b) => b.insertAll(aktivitaetAufnahmen, [
              for (final id in assetIds)
                AktivitaetAufnahmenCompanion.insert(
                    aktivitaetId: neue.id.value, assetId: id),
            ]));
      });

  Future<void> aktivitaetLoeschen(String id) => transaction(() async {
        await (delete(aktivitaetAufnahmen)
              ..where((t) => t.aktivitaetId.equals(id)))
            .go();
        await (delete(aktivitaeten)..where((t) => t.id.equals(id))).go();
      });

  Future<void> aktivitaetAendern(String id, AktivitaetenCompanion aenderung) =>
      (update(aktivitaeten)..where((t) => t.id.equals(id))).write(aenderung);

  /// Die Aufnahmen einer Aktivität, chronologisch. Gelöschte und
  /// gesperrte fallen heraus – siehe die Regel über [aufnahmenDerReise].
  Future<List<AssetData>> aufnahmenDerAktivitaet(String aktivitaetId) async {
    final abfrage = select(assets).join([
      innerJoin(aktivitaetAufnahmen,
          aktivitaetAufnahmen.assetId.equalsExp(assets.id)),
    ])
      ..where(aktivitaetAufnahmen.aktivitaetId.equals(aktivitaetId) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false))
      ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)]);
    return [for (final z in await abfrage.get()) z.readTable(assets)];
  }

  /// Nur die erste Aufnahme – für das Vorschaubild in der Liste. Eigene
  /// Abfrage mit `LIMIT 1`, aus demselben Grund wie
  /// [ersteAufnahmeDerReise].
  Future<AssetData?> ersteAufnahmeDerAktivitaet(String aktivitaetId) async {
    final abfrage = select(assets).join([
      innerJoin(aktivitaetAufnahmen,
          aktivitaetAufnahmen.assetId.equalsExp(assets.id)),
    ])
      ..where(aktivitaetAufnahmen.aktivitaetId.equals(aktivitaetId) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false))
      ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)])
      ..limit(1);
    final zeile = await abfrage.getSingleOrNull();
    return zeile?.readTable(assets);
  }

  /// Die Aufnahmen eines Zeitraums – für eine von Hand angelegte Reise
  /// oder Aktivität.
  ///
  /// **Der Zeitraum ist die ganze Eingabe.** Zugeordnet wird in dieser App
  /// über die Fotos und nicht über den Kalender; wer eine Reise von Hand
  /// anlegt, nennt deshalb ihren Zeitraum, und die Bilder darin kommen
  /// mit. Ein Auswahlraster für einzelne Fotos wäre der zweite Schritt,
  /// nicht der erste.
  ///
  /// [bis] ist einschliessend gemeint: Wer den 14. Juni als letzten Tag
  /// nennt, meint auch das Foto von 23:50 Uhr.
  /// Wie viele Aufnahmen im Zeitraum liegen – als Zahl, nicht als Liste.
  ///
  /// Der Zeitraum-Dialog zeigt beim Verschieben der Daten eine Zahl an.
  /// Er holte dafür bisher die vollen Zeilen und nahm deren `length` –
  /// bei einem weiten Zeitraum die halbe Bibliothek für eine einzige
  /// Ziffer, und das bei jeder Änderung.
  Future<int> zahlImZeitraum(DateTime von, DateTime bis) async {
    final ende = DateTime(bis.year, bis.month, bis.day, 23, 59, 59, 999);
    final anfang = DateTime(von.year, von.month, von.day);
    final zaehler = assets.id.count();
    final abfrage = selectOnly(assets)
      ..addColumns([zaehler])
      ..where(assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          assets.fileCreatedAt.isBiggerOrEqualValue(anfang) &
          assets.fileCreatedAt.isSmallerOrEqualValue(ende) &
          _isPrimaryGridEntry(assets));
    return (await abfrage.getSingle()).read(zaehler)!;
  }

  /// Dieselbe Menge wie [aufnahmenImZeitraum] als schmale Rasterzeilen.
  Future<List<Rasterzeile>> rasterzeilenImZeitraum(
      DateTime von, DateTime bis) async {
    final ende = DateTime(bis.year, bis.month, bis.day, 23, 59, 59, 999);
    final anfang = DateTime(von.year, von.month, von.day);
    return (await customSelect(
            'SELECT $rasterSpalten FROM assets WHERE $rasterSichtbar '
            'AND file_created_at >= ? AND file_created_at <= ? '
            'ORDER BY file_created_at ASC',
            variables: [
          Variable.withDateTime(anfang),
          Variable.withDateTime(ende)
        ],
            readsFrom: {
          assets
        }).get())
        .map(Rasterzeile.ausZeile)
        .toList();
  }

  Future<List<AssetData>> aufnahmenImZeitraum(DateTime von, DateTime bis) {
    final ende = DateTime(bis.year, bis.month, bis.day, 23, 59, 59, 999);
    final anfang = DateTime(von.year, von.month, von.day);
    return (select(assets)
          ..where((t) =>
              t.isTrashed.equals(false) &
              t.isLocked.equals(false) &
              t.fileCreatedAt.isBiggerOrEqualValue(anfang) &
              t.fileCreatedAt.isSmallerOrEqualValue(ende) &
              _isPrimaryGridEntry(t))
          ..orderBy([(t) => OrderingTerm.asc(t.fileCreatedAt)]))
        .get();
  }

  Future<Set<String>> zugeordneteAktivitaetsAufnahmen() async =>
      {for (final z in await select(aktivitaetAufnahmen).get()) z.assetId};

  /// Die Kennungen, die WIRKLICH zu dieser Aktivität gespeichert sind.
  ///
  /// **Warum das nicht dasselbe ist wie [aufnahmenDerAktivitaet].** Jene
  /// Abfrage liefert, was sich *zeigen* lässt: Aufnahmen im Papierkorb
  /// und gesperrte bleiben draussen. Wer aus ihrem Ergebnis die
  /// Ausgangsmenge für den Auswahlbildschirm baut, hat die
  /// verschwiegenen Zuordnungen schon verloren – und weil dort beim
  /// Sichern die Tabelle geleert und neu geschrieben wird
  /// ([setzeAufnahmenDerAktivitaet]), verschwinden sie endgültig, ohne
  /// dass jemand etwas angetippt hätte.
  ///
  /// Für „was gehört dazu" ist deshalb diese Abfrage die richtige und
  /// jene die falsche. Sie liest die Zuordnungstabelle selbst und
  /// verbindet sich mit nichts.
  Future<Set<String>> zuordnungenDerAktivitaet(String aktivitaetId) async => {
        for (final z in await (select(aktivitaetAufnahmen)
              ..where((t) => t.aktivitaetId.equals(aktivitaetId)))
            .get())
          z.assetId
      };

  /// Wie [zuordnungenDerAktivitaet], nur eine Tabelle weiter.
  Future<Set<String>> zuordnungenDerReise(String reiseId) async => {
        for (final z in await (select(reiseAufnahmen)
              ..where((t) => t.reiseId.equals(reiseId)))
            .get())
          z.assetId
      };

  /// Die selbst eingetragenen Arten: was in der Spalte steht und keine
  /// mitgelieferte Art ist.
  ///
  /// **Abgeleitet und nicht in einer eigenen Tabelle.** Eine Art
  /// existiert, solange eine Aktivität sie trägt – so kann keine Liste
  /// mit Namen volllaufen, die niemand mehr benutzt, und es braucht
  /// weder einen Schemaschritt noch ein Aufräumen. Der Preis: Wer die
  /// letzte Aktivität einer eigenen Art umträgt, verliert den Namen aus
  /// der Auswahl. Er steht danach genau so wieder da, wie er
  /// hineingekommen ist – als Eingabe.
  Future<List<String>> eigeneAktivitaetsarten() async {
    final zeilen = await customSelect(
      'SELECT DISTINCT art FROM aktivitaeten ORDER BY art',
      readsFrom: {aktivitaeten},
    ).get();
    return [
      for (final z in zeilen)
        if (!istBekannteArt(z.read<String>('art'))) z.read<String>('art'),
    ];
  }

  /// Setzt die Aufnahmen einer Aktivität auf genau [assetIds].
  ///
  /// **Setzen und nicht einzeln hinzufügen/entfernen.** Der Bildschirm
  /// zeigt eine Auswahl und gibt eine Auswahl zurück; die Unterschiede
  /// dazwischen sind Sache dieser Zeile und nicht die des Aufrufers.
  /// Zwei getrennte Aufrufe wären ausserdem zwei Gelegenheiten, dass
  /// dazwischen etwas schiefgeht.
  ///
  /// Führt danach den Zeitraum nach: `von`/`bis` sind aus den Aufnahmen
  /// abgeleitet und trotzdem gespeichert (damit die Liste sortieren kann,
  /// ohne für jede Zeile ihre Aufnahmen nachzuschlagen) – ohne diese
  /// Zeile stünde nach dem Bearbeiten ein Zeitraum da, den keine
  /// Aufnahme mehr belegt.
  Future<void> setzeAufnahmenDerAktivitaet(
          String aktivitaetId, Set<String> assetIds) =>
      transaction(() async {
        await (delete(aktivitaetAufnahmen)
              ..where((t) => t.aktivitaetId.equals(aktivitaetId)))
            .go();
        await batch((b) => b.insertAll(aktivitaetAufnahmen, [
              for (final id in assetIds)
                AktivitaetAufnahmenCompanion.insert(
                    aktivitaetId: aktivitaetId, assetId: id),
            ]));
        final zeitraum = await _zeitraumVon(assetIds);
        if (zeitraum != null) {
          await (update(aktivitaeten)..where((t) => t.id.equals(aktivitaetId)))
              .write(AktivitaetenCompanion(
                  von: Value(zeitraum.von), bis: Value(zeitraum.bis)));
        }
      });

  /// Setzt die Aufnahmen einer Reise auf genau [assetIds] – wie
  /// [setzeAufnahmenDerAktivitaet], nur eine Tabelle weiter.
  Future<void> setzeAufnahmenDerReise(String reiseId, Set<String> assetIds) =>
      transaction(() async {
        await (delete(reiseAufnahmen)..where((t) => t.reiseId.equals(reiseId)))
            .go();
        await batch((b) => b.insertAll(reiseAufnahmen, [
              for (final id in assetIds)
                ReiseAufnahmenCompanion.insert(reiseId: reiseId, assetId: id),
            ]));
        final zeitraum = await _zeitraumVon(assetIds);
        if (zeitraum != null) {
          await (update(reisen)..where((t) => t.id.equals(reiseId))).write(
              ReisenCompanion(
                  von: Value(zeitraum.von), bis: Value(zeitraum.bis)));
        }
      });

  /// Erste und letzte Aufnahmezeit einer Menge – `null` bei einer leeren
  /// Menge.
  ///
  /// Dann bleibt der bisherige Zeitraum stehen: Eine Reise ohne Bilder
  /// hat keinen belegten Zeitraum, und „1970" wäre eine Behauptung. Sie
  /// steht dann eben mit ihrem alten Datum in der Liste, bis wieder etwas
  /// darin liegt.
  Future<({DateTime von, DateTime bis})?> _zeitraumVon(
      Set<String> assetIds) async {
    if (assetIds.isEmpty) return null;
    final zeiten = await (select(assets)
          ..where((t) => t.id.isIn(assetIds))
          ..orderBy([(t) => OrderingTerm.asc(t.fileCreatedAt)]))
        .get();
    if (zeiten.isEmpty) return null;
    return (von: zeiten.first.fileCreatedAt, bis: zeiten.last.fileCreatedAt);
  }

  /// Welche Aufnahme zu welcher Reise gehört – für die Zuordnung einer
  /// Aktivität (siehe `reiseFuerAktivitaet`).
  /// Wie viele Aufnahmen je Reise – eine Abfrage für alle.
  ///
  /// Als Zahl und nicht als Liste: Gebraucht wird sie dort, wo man
  /// entscheidet, welche Reisen zusammengehören, und dafür genügt die
  /// Ziffer. (Siehe die Papierkorb-Kennzahl der Runde vom 31.08.: Zwei
  /// Stellen zogen 618 volle Zeilen, um deren Länge zu zeigen.)
  Future<Map<String, int>> aufnahmenzahlJeReise() async {
    final zeilen = await customSelect(
      'SELECT reise_id, count(*) AS n FROM reise_aufnahmen GROUP BY reise_id',
      readsFrom: {reiseAufnahmen},
    ).get();
    return {
      for (final z in zeilen) z.read<String>('reise_id'): z.read<int>('n'),
    };
  }

  /// Setzt die Art einer Reise (siehe [Reiseart]).
  Future<void> setzeReiseart(String id, String art) =>
      (update(reisen)..where((t) => t.id.equals(id)))
          .write(ReisenCompanion(art: Value(art)));

  Future<Map<String, String>> reiseJeAufnahme() async => {
        for (final z in await select(reiseAufnahmen).get()) z.assetId: z.reiseId
      };

  // ---------------------------------------------------------------
  // Aufgezeichnete Spuren.

  Future<List<SpurenData>> alleSpuren() =>
      (select(spuren)..orderBy([(t) => OrderingTerm.desc(t.angelegtAm)])).get();

  /// Die Spuren einer Reise – dieselbe Tabelle, die andere Spalte.
  Future<List<SpurenData>> spurenDerReise(String reiseId) => (select(spuren)
        ..where((t) => t.reiseId.equals(reiseId))
        ..orderBy([(t) => OrderingTerm(expression: t.angelegtAm)]))
      .get();

  Future<List<SpurenData>> spurenDerAktivitaet(String aktivitaetId) =>
      (select(spuren)
            ..where((t) => t.aktivitaetId.equals(aktivitaetId))
            ..orderBy([(t) => OrderingTerm.asc(t.angelegtAm)]))
          .get();

  /// Die Punkte einer Spur, in der Reihenfolge der Datei.
  Future<List<SpurpunkteData>> punkteDerSpur(String spurId) =>
      (select(spurpunkte)
            ..where((t) => t.spurId.equals(spurId))
            ..orderBy([(t) => OrderingTerm.asc(t.nummer)]))
          .get();

  /// Legt eine Spur samt ihren Punkten an.
  ///
  /// In einer Transaktion und als Stapel: Eine Aufzeichnung hat schnell
  /// zehntausend Punkte, und zehntausend einzelne Einfügungen wären
  /// zehntausend Schreibvorgänge.
  Future<void> spurAnlegen(
    SpurenCompanion spur,
    List<SpurpunkteCompanion> punkte,
  ) =>
      transaction(() async {
        await into(spuren).insert(spur);
        await batch((b) => b.insertAll(spurpunkte, punkte));
      });

  Future<void> spurLoeschen(String id) => transaction(() async {
        await (delete(spurpunkte)..where((t) => t.spurId.equals(id))).go();
        await (delete(spuren)..where((t) => t.id.equals(id))).go();
      });

  Future<void> spurAendern(String id, SpurenCompanion aenderung) =>
      (update(spuren)..where((t) => t.id.equals(id))).write(aenderung);

  Future<Set<String>> verworfeneAktivitaetsvorschlaege() async => {
        for (final z in await select(verworfeneAktivitaeten).get()) z.schluessel
      };

  Future<void> verwirfAktivitaetsvorschlag(String schluessel) =>
      into(verworfeneAktivitaeten).insertOnConflictUpdate(
          VerworfeneAktivitaetenCompanion.insert(
              schluessel: schluessel, verworfenAm: DateTime.now()));

  Future<Set<String>> verworfeneReisevorschlaege() async =>
      {for (final z in await select(verworfeneReisen).get()) z.schluessel};

  Future<void> verwirfReisevorschlag(String schluessel) =>
      into(verworfeneReisen).insertOnConflictUpdate(
          VerworfeneReisenCompanion.insert(
              schluessel: schluessel, verworfenAm: DateTime.now()));

  /// Alles, was die Reiseerkennung braucht – verortete, nicht gelöschte
  /// Aufnahmen.
  ///
  /// Eine Abfrage über die ganze Bibliothek, aber nur mit den fünf
  /// Spalten, die zählen: Bei hunderttausend Aufnahmen wäre das Laden
  /// vollständiger Zeilen der teuerste Teil des ganzen Vorgangs.
  Future<
      List<
          ({
            String id,
            DateTime zeit,
            double breite,
            double laenge,
            String? land,
            String? region,
            String? stadt
          })>> aufnahmenFuerReiseerkennung() async {
    // `_isPrimaryGridEntry` wie überall sonst: Die Videohälfte eines Live
    // Photos ist keine eigene Aufnahme, und ein Stapel zählt einmal.
    //
    // OHNE DIESE ZEILE kam ein bestätigter Ausflug als Vorschlag zurück.
    // Bestätigt wurde, was die Zeitleiste zeigt – die JPGs. Die MOV-Hälften
    // blieben unzugeordnet, trugen aber dieselbe Zeit und denselben Ort und
    // fanden sich beim nächsten Blick zu einem neuen Vorschlag desselben
    // Ausflugs zusammen. An der gewachsenen Bibliothek: ALLE drei noch
    // offenen Aktivitätsvorschläge waren solche Schatten – „Rautheim" mit
    // vier Videohälften zu einer bestätigten Aktivität aus vier Fotos, auf
    // die Sekunde dieselben Aufnahmen.
    final abfrage = selectOnly(assets)
      ..addColumns([
        assets.id,
        assets.fileCreatedAt,
        assets.latitude,
        assets.longitude,
        assets.locationCountry,
        assets.locationState,
        assets.locationCity,
      ])
      ..where(assets.latitude.isNotNull() &
          assets.longitude.isNotNull() &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          _isPrimaryGridEntry(assets))
      ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)]);
    return [
      for (final z in await abfrage.get())
        (
          id: z.read(assets.id)!,
          zeit: z.read(assets.fileCreatedAt)!,
          breite: z.read(assets.latitude)!,
          laenge: z.read(assets.longitude)!,
          land: z.read(assets.locationCountry),
          region: z.read(assets.locationState),
          stadt: z.read(assets.locationCity),
        ),
    ];
  }

  /// Setzt Koordinate **und** Ortsnamen in einem Zug.
  ///
  /// Beides zusammen und nicht nacheinander: Wer Fotos aus einer
  /// GPX-Spur verortet, hat sonst hinterher Punkte auf der Karte, aber
  /// keine Länder im Reisezähler – und müsste ein zweites Werkzeug
  /// starten, von dem er nichts weiss.
  Future<void> setzeOrte(
    List<
            ({
              String assetId,
              double breite,
              double laenge,
              String? land,
              String? region,
              String? ort
            })>
        eintraege,
  ) =>
      batch((b) {
        for (final e in eintraege) {
          b.update(
            assets,
            AssetsCompanion(
              latitude: Value(e.breite),
              longitude: Value(e.laenge),
              // Nur schreiben, wenn ein Name da ist: Ohne geladenen
              // GeoNames-Auszug bleibt die Spalte leer, statt einen
              // vorhandenen Namen zu löschen.
              locationCountry:
                  e.ort == null ? const Value.absent() : Value(e.land),
              locationState:
                  e.ort == null ? const Value.absent() : Value(e.region),
              locationCity: e.ort == null ? const Value.absent() : Value(e.ort),
            ),
            where: (t) => t.id.equals(e.assetId),
          );
        }
      });

  /// Land, Region und Ort aller verorteten Aufnahmen, mit Anzahl.
  ///
  /// Gruppiert in der Datenbank und nicht in Dart: Für den Länderzähler
  /// zählen nur die verschiedenen Kombinationen, und die sind auch bei
  /// hunderttausend Aufnahmen wenige hundert Zeilen.
  Future<List<({String? land, String? region, String? ort, int anzahl})>>
      besuchteOrte() async {
    final anzahl = assets.id.count();
    final abfrage = selectOnly(assets)
      ..addColumns([
        assets.locationCountry,
        assets.locationState,
        assets.locationCity,
        anzahl,
      ])
      ..where(assets.latitude.isNotNull() &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false))
      ..groupBy([
        assets.locationCountry,
        assets.locationState,
        assets.locationCity,
      ]);
    return [
      for (final z in await abfrage.get())
        (
          land: z.read(assets.locationCountry),
          region: z.read(assets.locationState),
          ort: z.read(assets.locationCity),
          anzahl: z.read(anzahl) ?? 0,
        ),
    ];
  }

  /// Wer wann auf welchem Bild zu sehen ist – für die Familienstatistik.
  ///
  /// Nur die angefragten Personen, damit bei einer grossen Bibliothek
  /// nicht jedes erkannte Gesicht durch den Speicher wandert.
  ///
  /// **Der gesperrte Ordner bleibt draussen**, ebenso der Papierkorb. Was
  /// hinter der PIN liegt, darf ausserhalb nicht auftauchen – auch nicht
  /// als Strich in einem Balkendiagramm, der verrät, dass es dort etwas
  /// gibt.
  Future<List<({String personId, String assetId, DateTime zeit})>>
      auftritteFuerPersonen(Set<String> personIds) async {
    if (personIds.isEmpty) return const [];
    final abfrage = select(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])
      ..where(faces.personId.isIn(personIds) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false));
    return [
      for (final z in await abfrage.get())
        (
          personId: z.readTable(faces).personId!,
          assetId: z.readTable(assets).id,
          zeit: z.readTable(assets).fileCreatedAt,
        ),
    ];
  }

  /// Alle selbst gesetzten Ortsmarken.
  Future<List<OrtsmarkenData>> alleOrtsmarken() => select(ortsmarken).get();

  /// Dieselben, als Strom – die Weltkarte soll sich sofort umfärben,
  /// wenn woanders ein Haken gesetzt wird.
  Stream<List<OrtsmarkenData>> beobachteOrtsmarken() =>
      select(ortsmarken).watch();

  /// Setzt eine Marke oder ersetzt die vorhandene.
  ///
  /// `insertOnConflictUpdate` und nicht erst suchen: Art und Schlüssel
  /// sind zusammen der Primärschlüssel, ein zweiter Haken auf dasselbe
  /// Land ist also gar nicht möglich – und ein Umschalten von „geplant"
  /// auf „besucht" ist genau dieselbe Zeile mit anderem Wert.
  Future<void> setzeOrtsmarke(OrtsmarkenCompanion marke) =>
      into(ortsmarken).insertOnConflictUpdate(marke);

  /// Nimmt eine Marke zurück.
  Future<void> loescheOrtsmarke(String art, String schluessel) =>
      (delete(ortsmarken)
            ..where((o) => o.art.equals(art) & o.schluessel.equals(schluessel)))
          .go();

  /// Aufnahmen **ohne** Koordinate – für das Auffüllen erkannter Reisen.
  ///
  /// Sie taugen nicht zum Erkennen, gehören aber dazu: An der echten
  /// Bibliothek trugen von einer Reise nur zwei Tage GPS-Daten, und im
  /// Fenster dieser zwei Tage lagen 28 weitere Aufnahmen ohne Koordinate.
  /// Dieselbe Einschränkung wie in [aufnahmenFuerReiseerkennung], und aus
  /// demselben Grund: Diese Aufnahmen werden einer erkannten Reise
  /// zugeschlagen, und eine Videohälfte doppelt sonst jedes Live Photo.
  Future<List<({String id, DateTime zeit})>> aufnahmenOhneKoordinate() async {
    final abfrage = selectOnly(assets)
      ..addColumns([assets.id, assets.fileCreatedAt])
      ..where(assets.latitude.isNull() &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          _isPrimaryGridEntry(assets))
      ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)]);
    return [
      for (final z in await abfrage.get())
        (id: z.read(assets.id)!, zeit: z.read(assets.fileCreatedAt)!),
    ];
  }

  /// Alle Lebensereignisse, in einem Zug.
  ///
  /// Für die Familien-Zeitleiste, die Dutzende Personen zugleich zeigt.
  /// Je Person einzeln zu fragen ergäbe dieselbe Zahl kleiner Abfragen
  /// wie Zeilen – und die Tabelle ist selbst bei ausgiebiger Forschung
  /// klein gegenüber allem anderen hier.
  Future<List<LebensereignisseData>> alleEreignisse() =>
      select(lebensereignisse).get();

  /// Setzt oder löscht die Koordinate eines Ereignisses.
  ///
  /// `null` für beide Werte heisst „nicht verortet" – so lässt sich eine
  /// falsch geratene Zuordnung auch wieder wegnehmen, ohne den
  /// aufgeschriebenen Ortsnamen zu verlieren.
  Future<void> setzeEreignisort(String id, {double? breite, double? laenge}) =>
      (update(lebensereignisse)..where((t) => t.id.equals(id))).write(
        LebensereignisseCompanion(
          ortBreite: Value(breite),
          ortLaenge: Value(laenge),
        ),
      );

  /// Setzt das Geschlecht einer Person. `null` bedeutet „nicht angegeben".
  Future<void> setzeGeschlecht(String personId, Geschlecht? geschlecht) =>
      (update(people)..where((t) => t.id.equals(personId))).write(
        PeopleCompanion(
          geschlecht:
              Value(geschlecht == null ? null : geschlechtZuText(geschlecht)),
        ),
      );

  /// Setzt die Lebensdaten einer Person. `null` löscht die Angabe.
  Future<void> setzeLebensdaten(
    String personId, {
    required DateTime? geburt,
    required DateTime? tod,
  }) =>
      (update(people)..where((t) => t.id.equals(personId))).write(
        PeopleCompanion(geburtsdatum: Value(geburt), sterbedatum: Value(tod)),
      );

  /// Alle Personen in der Reihenfolge, in der sie im Stammbaum stehen
  /// sollen: die Älteren zuerst, Unbekanntes zuletzt, bei Gleichstand nach
  /// Namen.
  ///
  /// Die Sortierung steckt hier und nicht in der Darstellung, weil sie
  /// auch die Reihenfolge innerhalb einer Geschwisterreihe bestimmt – und
  /// die soll überall dieselbe sein.
  List<PersonData> nachAlterSortiert(List<PersonData> personen) {
    final sortiert = [...personen];
    sortiert.sort((a, b) {
      final ga = a.geburtsdatum, gb = b.geburtsdatum;
      if (ga != null && gb != null && ga != gb) return ga.compareTo(gb);
      if (ga != null && gb == null) return -1;
      if (ga == null && gb != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sortiert;
  }

  /// Alle Fotos, auf denen mindestens eine der genannten Personen erkannt
  /// wurde – für „Fotos der Familie".
  ///
  /// Die eigentliche Verbindung zwischen den beiden Hälften dieser App:
  /// Gesichter sind Personen zugeordnet, Personen sind miteinander
  /// verwandt. Erst diese Abfrage macht daraus „zeig mir alles von diesem
  /// Familienzweig". Ein Foto mit mehreren Verwandten darauf erscheint
  /// einmal, nicht mehrfach.
  Future<List<AssetData>> assetsFuerPersonen(List<String> personIds) async {
    if (personIds.isEmpty) return [];
    final query = select(assets).join([
      innerJoin(faces, faces.assetId.equalsExp(assets.id)),
    ])
      ..where(faces.personId.isIn(personIds) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          _isPrimaryGridEntry(assets))
      ..orderBy([OrderingTerm.desc(assets.fileCreatedAt)]);
    final rows = await query.get();
    final gesehen = <String>{};
    final ergebnis = <AssetData>[];
    for (final row in rows) {
      final a = row.readTable(assets);
      if (gesehen.add(a.id)) ergebnis.add(a);
    }
    return ergebnis;
  }

  /// Verortete Fotos einer Personengruppe, samt der Personen darauf.
  ///
  /// Für die Familienkarte: Ein Foto kann mehrere Verwandte zeigen, und
  /// erst die Liste der Personen erlaubt der Karte zu entscheiden, welcher
  /// Verwandtschaftsgrad die Farbe bestimmt. Ein einzelnes „gehört zur
  /// Familie“ genügte dafür nicht.
  Future<List<({AssetData asset, Set<String> personen})>>
      verorteteAssetsFuerPersonen(List<String> personIds) async {
    if (personIds.isEmpty) return [];
    final query = select(assets).join([
      innerJoin(faces, faces.assetId.equalsExp(assets.id)),
    ])
      ..where(faces.personId.isIn(personIds) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          assets.latitude.isNotNull() &
          assets.longitude.isNotNull() &
          _isPrimaryGridEntry(assets))
      ..orderBy([OrderingTerm.desc(assets.fileCreatedAt)]);
    final rows = await query.get();
    final nachId = <String, AssetData>{};
    final leute = <String, Set<String>>{};
    for (final row in rows) {
      final a = row.readTable(assets);
      nachId[a.id] = a;
      final pid = row.readTable(faces).personId;
      if (pid != null) leute.putIfAbsent(a.id, () => {}).add(pid);
    }
    return [
      for (final e in nachId.entries)
        (asset: e.value, personen: leute[e.key] ?? const <String>{}),
    ];
  }

  Stream<List<AssetData>> watchAssetsForPerson(String personId) {
    final query = select(assets).join([
      innerJoin(faces, faces.assetId.equalsExp(assets.id)),
    ])
      ..where(faces.personId.equals(personId) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false))
      ..orderBy([OrderingTerm.desc(assets.fileCreatedAt)]);
    // Ein Foto mit zwei Gesichtern derselben Person steht zweimal im
    // Verbund – hier bleibt es bei einem Eintrag.
    return _gedrosselt(
      () => query.map((r) => r.readTable(assets)),
      TableUpdateQuery.allOf([
        TableUpdateQuery.onTable(assets),
        TableUpdateQuery.onTable(faces),
      ]),
    ).map((zeilen) {
      final gesehen = <String>{};
      return [
        for (final a in zeilen)
          if (gesehen.add(a.id)) a,
      ];
    });
  }

  /// Liefert alle Bild-Assets, die für einen (erneuten) Gesichts-Scan
  /// infrage kommen. Bei [onlyNew] werden nur Fotos zurückgegeben, die noch
  /// nie durch die Gesichtserkennung gelaufen sind.
  Future<List<AssetData>> assetsForFaceScan({required bool onlyNew}) {
    // Gesperrte Fotos bewusst ausgeschlossen: sonst würden ihre Gesichter im
    // "Unbenannte Gesichter"-Tab auftauchen, obwohl das Foto selbst versteckt
    // ist (siehe [unassignedFaces]).
    final query = select(assets)
      ..where((t) =>
          _auswertbar(t) &
          t.isTrashed.equals(false) &
          t.isLocked.equals(false) &
          // Gilt auch fuer "alle erneut durchsuchen" - sonst waere die
          // Ausnahme wertlos, denn nur dort greift sie ueberhaupt.
          t.faceScanExcluded.equals(false));
    if (onlyNew) {
      query.where((t) => t.facesScanned.equals(false));
    }
    return query.get();
  }

  /// Nimmt ein Foto von der Gesichtssuche aus oder holt es zurueck.
  Future<void> setzeGesichtssucheAusgenommen(String assetId, bool wert) =>
      (update(assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(faceScanExcluded: Value(wert)));

  /// Zählvariante von [assetsForFaceScan], siehe [countLocationBackfill].
  Future<int> countFaceScan({required bool onlyNew}) {
    var predicate = _auswertbar(assets) &
        assets.isTrashed.equals(false) &
        assets.isLocked.equals(false) &
        assets.faceScanExcluded.equals(false);
    if (onlyNew) predicate = predicate & assets.facesScanned.equals(false);
    return _countWhere(predicate);
  }

  Future<void> markFacesScanned(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds)))
          .write(const AssetsCompanion(facesScanned: Value(true)));

  /// Löscht bereits erkannte, aber noch keiner Person zugeordnete Gesichter
  /// eines Assets, bevor ein erneuter Scan neue Erkennungen einfügt – manuell
  /// zugeordnete Gesichter (mit personId) bleiben dabei bewusst unangetastet.
  ///
  /// Beiseitegelegte Gesichter bleiben ebenfalls stehen. Sonst wäre das
  /// Ignorieren beim ersten „alle Fotos erneut scannen" stillschweigend
  /// wieder weg – und genau davor soll es schützen (siehe [Faces.isIgnored]).
  /// Gibt die Ausschnitts-Pfade der gelöschten Zeilen zurück, damit der
  /// Aufrufer die Dateien mit wegräumt – wie [loescheGesicht] und
  /// [loescheAlleUnbenanntenErkennungen].
  ///
  /// Diese Rückgabe fehlte hier als einziger der drei Löschwege, und
  /// ausgerechnet dieser läuft nicht auf Knopfdruck, sondern bei jedem
  /// „alle Fotos erneut scannen" über den ganzen Bestand. In der
  /// Prüfbibliothek lagen dadurch 17 643 Ausschnitte ohne Datenbankzeile
  /// – 160 MB, genau die Hälfte des Ordners, alle aus einem einzigen
  /// Durchlauf. Jeder weitere Scan hätte den Bestand erneut verdoppelt
  /// (Prüfrunde 8).
  Future<List<String>> deleteUnassignedFacesForAsset(String assetId) async {
    final auswahl = select(faces)
      ..where((t) =>
          t.assetId.equals(assetId) &
          t.personId.isNull() &
          t.isIgnored.equals(false));
    final betroffen = await auswahl.get();
    if (betroffen.isEmpty) return const [];
    await (delete(faces)
          ..where((t) => t.id.isIn([for (final f in betroffen) f.id])))
        .go();
    return [
      for (final f in betroffen)
        if (f.cropRelativePath != null) f.cropRelativePath!,
    ];
  }

  // -----------------------------------------------------------------------
  // CLIP-Bild-Embeddings (KI-Suche)
  // -----------------------------------------------------------------------

  Future<void> saveEmbedding(String assetId, Float32List vector) async {
    await into(imageEmbeddings).insertOnConflictUpdate(
      ImageEmbeddingsCompanion.insert(
        assetId: assetId,
        vector: blobFromEmbeddingFloats(vector),
      ),
    );
    _embeddingsGeneration++;
  }

  /// Einzelnes gespeichertes CLIP-Embedding (falls vorhanden) – für das
  /// automatische KI-Tagging, das das beim Import ohnehin berechnete
  /// Bild-Embedding wiederverwendet, statt das Bild erneut zu dekodieren.
  Future<Float32List?> embeddingForAsset(String assetId) async {
    final row = await (select(imageEmbeddings)
          ..where((t) => t.assetId.equals(assetId)))
        .getSingleOrNull();
    if (row == null) return null;
    return floatsFromEmbeddingBlob(row.vector);
  }

  /// Fotos ohne CLIP-Embedding – z.B. weil sie importiert wurden, bevor das
  /// CLIP-Modell installiert war (Embeddings werden sonst automatisch beim
  /// Import berechnet). Für das nachträgliche Berechnen in den Werkzeugen.
  /// [alle] nimmt auch Fotos mit, die schon ein Embedding haben – nötig,
  /// wenn sich die Bildvorverarbeitung geändert hat: Ein Vektor aus einem
  /// gestauchten Bild und einer aus einem mittig zugeschnittenen lassen
  /// sich nicht sinnvoll gegeneinander rechnen (siehe `_aufClipGroesse` in
  /// clip_service.dart).
  Future<List<AssetData>> assetsForEmbeddingBackfill(
      {bool alle = false}) async {
    final query = select(assets).join([
      leftOuterJoin(
          imageEmbeddings, imageEmbeddings.assetId.equalsExp(assets.id)),
    ])
      ..where(_auswertbar(assets) &
          assets.isTrashed.equals(false) &
          // Gesperrte Fotos ausgenommen, siehe [assetsForOcrBackfill]: Ein
          // CLIP-Embedding beschreibt den Bildinhalt und ist damit ebenso
          // wenig für die unverschlüsselte Datenbank gedacht.
          assets.isLocked.equals(false) &
          (alle ? const Constant(true) : imageEmbeddings.assetId.isNull()));
    final rows = await query.get();
    return rows.map((r) => r.readTable(assets)).toList();
  }

  /// Zählvariante von [assetsForEmbeddingBackfill], siehe [countLocationBackfill].
  Future<int> countEmbeddingBackfill() async {
    final countExpr = assets.id.count();
    final query = selectOnly(assets).join([
      leftOuterJoin(
          imageEmbeddings, imageEmbeddings.assetId.equalsExp(assets.id)),
    ])
      ..addColumns([countExpr])
      ..where(_auswertbar(assets) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          imageEmbeddings.assetId.isNull());
    final row = await query.getSingle();
    return row.read<int>(countExpr) ?? 0;
  }

  /// Bild-Assets, die für automatisches KI-Tagging infrage kommen (nicht
  /// gelöscht/gesperrt – gesperrte Fotos werden bewusst nicht verarbeitet,
  /// solange sie versteckt sind).
  ///
  /// Bei [onlyUntagged] nur Fotos, die noch nie durch die Verschlagwortung
  /// gelaufen sind ([Assets.aiTagsScanned]) UND noch keinen Tag tragen.
  /// Das Flag ist dabei das entscheidende Kriterium: Ein Foto, zu dem CLIP
  /// keinen passenden Begriff gefunden hat, bleibt für immer ohne Tags und
  /// wäre ohne das Flag bei jedem Lauf erneut Kandidat – siehe dort.
  /// Die zusätzliche Tag-Prüfung hält Fotos draussen, die vor Einführung
  /// des Flags bereits verschlagwortet wurden.
  ///
  /// Wer stattdessen "Alle" wählt, ergänzt passende KI-Tags auch bei
  /// bereits getaggten Fotos, ohne vorhandene (auch manuelle) Tags zu
  /// entfernen.
  Future<List<AssetData>> assetsForAiTagging(
      {required bool onlyUntagged}) async {
    if (!onlyUntagged) {
      return (select(assets)
            ..where((t) =>
                _auswertbar(t) &
                t.isTrashed.equals(false) &
                t.isLocked.equals(false)))
          .get();
    }
    final query = select(assets).join([
      leftOuterJoin(assetTags, assetTags.assetId.equalsExp(assets.id)),
    ])
      ..where(_auswertbar(assets) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          assets.aiTagsScanned.equals(false) &
          assetTags.assetId.isNull());
    final rows = await query.get();
    return rows.map((r) => r.readTable(assets)).toList();
  }

  /// Vermerkt, dass ein Foto die Verschlagwortung durchlaufen hat –
  /// unabhängig davon, ob dabei Tags heraussprangen.
  Future<void> markAiTagsScanned(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds)))
          .write(const AssetsCompanion(aiTagsScanned: Value(true)));

  /// Zählvariante von [assetsForAiTagging], siehe [countLocationBackfill].
  Future<int> countAiTagging({required bool onlyUntagged}) async {
    if (!onlyUntagged) {
      return _countWhere(_auswertbar(assets) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false));
    }
    final countExpr = assets.id.count();
    final query = selectOnly(assets).join([
      leftOuterJoin(assetTags, assetTags.assetId.equalsExp(assets.id)),
    ])
      ..addColumns([countExpr])
      ..where(_auswertbar(assets) &
          assets.isTrashed.equals(false) &
          assets.isLocked.equals(false) &
          // Muss deckungsgleich mit assetsForAiTagging bleiben, sonst zeigt
          // die Hintergrundaufgaben-Übersicht Wartende an, die keine sind.
          assets.aiTagsScanned.equals(false) &
          assetTags.assetId.isNull());
    final row = await query.getSingle();
    return row.read<int>(countExpr) ?? 0;
  }

  /// Lädt alle gespeicherten Embeddings (assetId -> Vektor) für die
  /// Brute-Force-Ähnlichkeitssuche im ClipService (KI-Suche & Duplikate).
  /// Über einen Join gegen Assets gefiltert, damit gelöschte oder gesperrte
  /// Fotos dort nicht auftauchen können.
  /// **Nur die zwei Spalten, die gebraucht werden.**
  ///
  /// Ein `join` in drift holt **jede Spalte jeder beteiligten Tabelle** und
  /// baut daraus Zeilenobjekte. Hier hing an jeder der 7475 Einbettungen
  /// eine vollständige Aufnahme mit 56 Spalten, die niemand ansieht. An der
  /// gewachsenen Bibliothek gemessen: **105 ms gegen 19,3 ms**, dasselbe
  /// Ergebnis.
  ///
  /// Der Verbund selbst bleibt – er ist die Bedingung („nicht im
  /// Papierkorb, nicht gesperrt"), nicht die Auskunft. Und `rawData` statt
  /// `read(spalte)`, aus demselben Grund wie in [assetsOnThisDay]: Der
  /// bequeme Weg schlägt jede Spalte über ihren Typ-Umsetzer nach.
  /// Videos, bei denen noch nicht nach weiteren Standbildern gesehen
  /// wurde (siehe [Assets.videobilderGeprueft]).
  ///
  /// Ohne Papierkorb und ohne Tresor, wie ueberall bei der Auswertung:
  /// Was im Bildinhalt steckt, hat in der unverschluesselten Datenbank
  /// nichts zu suchen.
  Expression<bool> _videobilderOffen(bool alle) =>
      assets.type.equals('VIDEO') &
      assets.isTrashed.equals(false) &
      assets.isLocked.equals(false) &
      (alle
          ? const CustomExpression<bool>('1')
          : assets.videobilderGeprueft.equals(false));

  Future<List<AssetData>> assetsFuerVideobilder({bool alle = false}) =>
      (select(assets)..where((_) => _videobilderOffen(alle))).get();

  /// Zaehlvariante von [assetsFuerVideobilder], siehe [countLocationBackfill].
  Future<int> countVideobilder({bool alle = false}) =>
      _countWhere(_videobilderOffen(alle));

  /// Nur die Videos, bei denen der zweite Blick etwas bringt: die ab
  /// [videoZweitblickAb].
  ///
  /// [countVideobilder] zaehlt alle 429 Videos der Produktivbibliothek,
  /// obwohl [videostandbildstellen] fuer 210 davon eine leere Liste
  /// liefert – bei einem Live-Photo-Fetzen von zwei Sekunden ist das eine
  /// vorhandene Standbild das ganze Video. Auf dem Gesundheitsbildschirm
  /// steht deshalb die kleinere, ehrliche Zahl (**219**).
  Future<int> countVideoZweitblick() => _countWhere(
        _videobilderOffen(false) &
            assets.durationSeconds
                .isBiggerOrEqualValue(videoZweitblickAb.inSeconds.toDouble()),
      );

  /// Schreibt die Einbettungen der zusaetzlichen Standbilder eines Videos
  /// – **die alten fallen dabei weg**.
  ///
  /// Ein zweiter Lauf ueber dasselbe Video soll es ersetzen und nicht
  /// verdoppeln; die Stellen koennen sich mit der Laufzeit aendern.
  Future<void> setzeVideoeinbettungen(
      String assetId, List<({double stelle, Uint8List vector})> bilder) async {
    await transaction(() async {
      await (delete(videoeinbettungen)..where((t) => t.assetId.equals(assetId)))
          .go();
      for (final b in bilder) {
        await into(videoeinbettungen).insert(VideoeinbettungenCompanion.insert(
          assetId: assetId,
          stelle: (b.stelle * 1000).round(),
          vector: b.vector,
        ));
      }
      await (update(assets)..where((t) => t.id.equals(assetId)))
          .write(const AssetsCompanion(videobilderGeprueft: Value(true)));
    });
    _embeddingsGeneration++;
  }

  /// Merkt „nachgesehen" fuer Videos, bei denen nichts zu holen war –
  /// zu kurz, oder das Standbild liess sich nicht greifen.
  Future<void> markVideobilderGeprueft(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds)))
          .write(const AssetsCompanion(videobilderGeprueft: Value(true)));

  /// Die zusaetzlichen Einbettungen, nach Aufnahme gebuendelt – fuer die
  /// Suche, und nur fuer sie (siehe [Videoeinbettungen]).
  Future<Map<String, List<Float32List>>> alleVideoeinbettungen() async {
    final query = selectOnly(videoeinbettungen).join([
      innerJoin(assets, assets.id.equalsExp(videoeinbettungen.assetId)),
    ])
      ..addColumns([videoeinbettungen.assetId, videoeinbettungen.vector])
      ..where(assets.isTrashed.equals(false) & assets.isLocked.equals(false));
    final out = <String, List<Float32List>>{};
    for (final z in await query.get()) {
      out
          .putIfAbsent(
              z.rawData.read<String>('videoeinbettungen.asset_id'), () => [])
          .add(floatsFromEmbeddingBlob(
              z.rawData.read<Uint8List>('videoeinbettungen.vector')));
    }
    return out;
  }

  Future<Map<String, Float32List>> allEmbeddings() async {
    final query = selectOnly(imageEmbeddings).join([
      innerJoin(assets, assets.id.equalsExp(imageEmbeddings.assetId)),
    ])
      ..addColumns([imageEmbeddings.assetId, imageEmbeddings.vector])
      ..where(assets.isTrashed.equals(false) & assets.isLocked.equals(false));
    final out = <String, Float32List>{};
    for (final z in await query.get()) {
      out[z.rawData.read<String>('image_embeddings.asset_id')] =
          floatsFromEmbeddingBlob(
              z.rawData.read<Uint8List>('image_embeddings.vector'));
    }
    return out;
  }

  // -----------------------------------------------------------------------
  // Backup
  // -----------------------------------------------------------------------

  /// Gesperrte Fotos werden bewusst NIE ins (unverschlüsselte, oft in einen
  /// Cloud-Sync-Ordner zeigende) Backup aufgenommen – das würde den Zweck
  /// des gesperrten Ordners aushebeln.
  /// Die Aufnahmen, die in `metadata.json` beschrieben werden dürfen.
  ///
  /// **Dieselbe `isLocked`-Ausnahme wie bei [assetsNotBackedUp]**, und
  /// aus demselben Grund: Was nicht mitgesichert wird, soll auch nicht
  /// benannt werden. Ein Dateiname wie `Scheidungsurkunde_Anna.jpg` in
  /// einer unverschlüsselten Datei im Cloud-Ordner gibt genau das preis,
  /// wovor der gesperrte Ordner schützen soll.
  ///
  /// Papierkorb-Einträge bleiben **drin**: Ihre Dateien liegen aus
  /// früheren Läufen im Sicherungsziel, und wer sie später
  /// wiederherstellt, will seine Schlagwörter zurück.
  Future<List<AssetData>> assetsFuerMetadatenexport() =>
      (select(assets)..where((t) => t.isLocked.equals(false))).get();

  Future<List<AssetData>> assetsNotBackedUp() => (select(assets)
        ..where((t) =>
            t.backedUp.equals(false) &
            t.isTrashed.equals(false) &
            t.isLocked.equals(false)))
      .get();

  Future<void> markBackedUp(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds)))
          .write(const AssetsCompanion(backedUp: Value(true)));

  Future<void> insertBackupRecord(BackupRecordsCompanion record) =>
      into(backupRecords).insert(record);

  Future<BackupRecordData?> lastBackupRecord() => (select(backupRecords)
        ..orderBy([(t) => OrderingTerm.desc(t.performedAt)]))
      .getSingleOrNull();

  /// Schnelle SQLite-Eigenprüfung für die Zustandsübersicht. Anders als die
  /// vollständige Integritätsprüfung liest sie keine Mediendateien.
  Future<bool> databaseQuickCheck() async {
    final rows = await customSelect('PRAGMA quick_check').get();
    return rows.isNotEmpty &&
        rows.every((row) => row.data.values.singleOrNull == 'ok');
  }

  Future<int> countNotAutoBackedUp() => _countWhere(
        assets.isTrashed.equals(false) &
            assets.isLocked.equals(false) &
            assets.autoBackedUp.equals(false),
      );

  // -----------------------------------------------------------------------
  // Backup-Verschlüsselung + automatisches Backup
  // -----------------------------------------------------------------------
  //
  // Analog zum gesperrten Ordner: die eigentliche Kryptografie läuft über
  // VaultCrypto/LibraryState, hier wird nur der verpackte Backup-Master-Key
  // und die Konfiguration des automatischen Backups gespeichert.

  Future<bool> hasBackupKey() async {
    final row = await (select(backupSettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return row?.wrappedMasterKey != null;
  }

  Future<BackupSettingsData?> backupSettingsRow() =>
      (select(backupSettings)..where((t) => t.id.equals(0))).getSingleOrNull();

  Future<void> saveBackupKey({
    required Uint8List kdfSalt,
    required Uint8List nonce,
    required Uint8List wrapped,
  }) =>
      into(backupSettings)
          .insertOnConflictUpdate(BackupSettingsCompanion.insert(
        id: const Value(0),
        kdfSalt: Value(kdfSalt),
        wrappedMasterKeyNonce: Value(nonce),
        wrappedMasterKey: Value(wrapped),
      ));

  /// Entfernt nur die lokale Einrichtung der Backup-Verschlüsselung –
  /// bereits vorhandene verschlüsselte Backups am Zielort bleiben davon
  /// unberührt (sie lassen sich weiterhin mit der Passphrase entschlüsseln,
  /// die App merkt sich nur den Schlüssel nicht mehr).
  Future<void> clearBackupKey() =>
      (update(backupSettings)..where((t) => t.id.equals(0)))
          .write(const BackupSettingsCompanion(
        kdfSalt: Value(null),
        wrappedMasterKeyNonce: Value(null),
        wrappedMasterKey: Value(null),
      ));

  /// [destination] und [intervalHours] werden nur geschrieben, wenn sie
  /// angegeben sind – `null` heißt "unverändert lassen", nicht "löschen".
  ///
  /// Vorher wurde das Ziel immer geschrieben: Ein Umstellen des Intervalls
  /// oder auch nur des Aktiv-Schalters übergab kein Ziel und löschte damit
  /// den zuvor gewählten Ordner, der dann erneut ausgewählt werden musste.
  /// Zum bewussten Entfernen gibt es [clearAutoBackupDestination].
  Future<void> setAutoBackupConfig(
          {required bool enabled, String? destination, int? intervalHours}) =>
      into(backupSettings)
          .insertOnConflictUpdate(BackupSettingsCompanion.insert(
        id: const Value(0),
        autoBackupEnabled: Value(enabled),
        autoBackupDestination:
            destination != null ? Value(destination) : const Value.absent(),
        autoBackupIntervalHours:
            intervalHours != null ? Value(intervalHours) : const Value.absent(),
      ));

  Future<void> setAutoBackupMaxMbPerRun(int mb) => into(backupSettings)
          .insertOnConflictUpdate(BackupSettingsCompanion.insert(
        id: const Value(0),
        autoBackupMaxMbPerRun: Value(mb),
      ));

  /// Entfernt das Sicherungsziel ausdrücklich (siehe [setAutoBackupConfig]).
  Future<void> clearAutoBackupDestination() => (update(backupSettings)
        ..where((t) => t.id.equals(0)))
      .write(const BackupSettingsCompanion(autoBackupDestination: Value(null)));

  Future<void> setLastAutoBackupAt(DateTime when) =>
      (update(backupSettings)..where((t) => t.id.equals(0)))
          .write(BackupSettingsCompanion(lastAutoBackupAt: Value(when)));

  /// Wie [assetsNotBackedUp], aber mit eigenem Tracking-Flag für das
  /// automatische Backup (siehe [Assets.autoBackedUp]).
  Future<List<AssetData>> assetsNotAutoBackedUp() => (select(assets)
        ..where((t) =>
            t.autoBackedUp.equals(false) &
            t.isTrashed.equals(false) &
            t.isLocked.equals(false)))
      .get();

  Future<void> markAutoBackedUp(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds)))
          .write(const AssetsCompanion(autoBackedUp: Value(true)));

  // -----------------------------------------------------------------------
  // Gesperrter Ordner (PIN-Schutz + echte Verschlüsselung für private Fotos)
  // -----------------------------------------------------------------------
  //
  // Die eigentliche Kryptografie (Master-Key erzeugen/verpacken/entpacken,
  // Dateien ver-/entschlüsseln) läuft über VaultCrypto/LibraryState – hier
  // wird nur das Ergebnis (verpackter Master-Key + Salt/Nonce) gespeichert
  // bzw. ausgelesen.

  Future<bool> hasPinSet() async {
    final row = await (select(privacySettings)..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return row?.wrappedMasterKey != null;
  }

  Future<PrivacySettingsData?> privacySettingsRow() =>
      (select(privacySettings)..where((t) => t.id.equals(0))).getSingleOrNull();

  Future<void> saveVaultKey({
    required Uint8List kdfSalt,
    required Uint8List nonce,
    required Uint8List wrapped,
  }) =>
      into(privacySettings)
          .insertOnConflictUpdate(PrivacySettingsCompanion.insert(
        id: const Value(0),
        kdfSalt: Value(kdfSalt),
        wrappedMasterKeyNonce: Value(nonce),
        wrappedMasterKey: Value(wrapped),
      ));

  Future<void> clearVaultKey() =>
      (delete(privacySettings)..where((t) => t.id.equals(0))).go();

  Future<void> setProtectPrivateMetadata(bool value) => into(privacySettings)
      .insertOnConflictUpdate(PrivacySettingsCompanion.insert(
          id: const Value(0), protectMetadata: Value(value)));

  Future<Map<String, List<String>>> privateRelationsForAsset(
      String assetId) async {
    final tagRows = await (select(assetTags)
          ..where((t) => t.assetId.equals(assetId)))
        .get();
    final albumRows = await (select(albumAssets)
          ..where((a) => a.assetId.equals(assetId)))
        .get();
    return {
      'tags': [for (final row in tagRows) '${row.tagId}\u0000${row.quelle}'],
      'albums': [for (final row in albumRows) row.albumId],
    };
  }

  /// Ersetzt die unmittelbar lesbaren privaten Angaben durch neutrale
  /// Werte. Der Aufrufer muss die Originalwerte zuvor verschlüsselt haben.
  Future<void> hidePrivateMetadata(String assetId) => transaction(() async {
        await (update(assets)..where((a) => a.id.equals(assetId))).write(
          AssetsCompanion(
            originalFileName: const Value('Private Aufnahme'),
            fileCreatedAt: Value(DateTime.utc(1970)),
            importedAt: Value(DateTime.utc(1970)),
            isFavorite: const Value(false),
            description: const Value(null),
            latitude: const Value(null),
            longitude: const Value(null),
            cameraMake: const Value(null),
            cameraModel: const Value(null),
            lensModel: const Value(null),
            focalLengthMm: const Value(null),
            fNumber: const Value(null),
            iso: const Value(null),
            exposureTimeSeconds: const Value(null),
            exposureBiasEv: const Value(null),
            focalLength35mm: const Value(null),
            locationCountry: const Value(null),
            locationState: const Value(null),
            locationCity: const Value(null),
            rating: const Value(0),
            colorLabel: const Value(null),
            ocrText: const Value(null),
            ocrBoxen: const Value(null),
            zeitversatzMinuten: const Value(null),
            aiCaption: const Value(null),
            aiCaptionDe: const Value(null),
          ),
        );
        await (delete(assetTags)..where((t) => t.assetId.equals(assetId))).go();
        await (delete(albumAssets)..where((a) => a.assetId.equals(assetId)))
            .go();
      });

  Future<void> restorePrivateMetadata(
    String assetId,
    AssetsCompanion metadata, {
    required List<(String, String)> tags,
    required List<String> albumIds,
  }) =>
      transaction(() async {
        await (update(assets)..where((a) => a.id.equals(assetId)))
            .write(metadata);
        await batch((b) {
          for (final (tagId, source) in tags) {
            b.insert(
                assetTags,
                AssetTagsCompanion.insert(
                    assetId: assetId, tagId: tagId, quelle: Value(source)),
                mode: InsertMode.insertOrIgnore);
          }
          for (final albumId in albumIds) {
            b.insert(albumAssets,
                AlbumAssetsCompanion.insert(albumId: albumId, assetId: assetId),
                mode: InsertMode.insertOrIgnore);
          }
        });
      });

  Future<void> setAssetsLocked(List<String> assetIds, bool locked) async {
    await (update(assets)..where((t) => t.id.isIn(assetIds)))
        .write(AssetsCompanion(isLocked: Value(locked)));
    _embeddingsGeneration++;
  }

  /// Entfernt die maschinell aus dem BILDINHALT abgeleiteten Daten eines
  /// Assets: erkannten Text, KI-Bildunterschrift (in **beiden** Sprachen)
  /// und CLIP-Embedding.
  ///
  /// Wird beim Sperren aufgerufen. Ohne das blieb der Inhalt eines
  /// gesperrten Fotos in der unverschlüsselten `library.sqlite` lesbar –
  /// bei einem abfotografierten Dokument also genau der Text, wegen dem es
  /// gesperrt wurde (Audit-Fund). Über die Oberfläche war er zwar nicht
  /// erreichbar (searchAssets filtert `isLocked`), wohl aber für jeden mit
  /// Dateizugriff.
  ///
  /// Verlustfrei, nur nicht kostenlos: Die `*Scanned`-Flags werden
  /// zurückgesetzt, sodass die Hintergrundanalyse alles neu berechnet,
  /// sobald das Foto wieder entsperrt ist.
  ///
  /// Seit Fassung 56 gehören auch die **Schlagwörter der Bilderkennung**
  /// dazu. Sie standen vorher als einzige aus dem Bildinhalt abgeleitete
  /// Angabe weiter im Klartext – nicht aus Nachlässigkeit, sondern weil
  /// sie von Handvergaben nicht zu unterscheiden waren. Siehe [Tagquelle].
  ///
  /// Bewusst NICHT angetastet:
  /// - [description] – Nutzer-Freitext, kein abgeleiteter Wert.
  /// - Schlagwörter mit [Tagquelle.hand] – die zu löschen wäre echter
  ///   Datenverlust, nicht nur eine Neuberechnung.
  /// - Eine Bildunterschrift mit [Assets.aiCaptionEdited] – dann sind es
  ///   die Worte des Nutzers, und dieselbe Regel wie bei [description]
  ///   gilt. Bis zur 17. Prüfrunde wurde sie trotzdem gelöscht, und zwar
  ///   **unwiederbringlich**: Das Merkmal blieb dabei stehen, und
  ///   [_brauchtBeschreibung] schliesst genau damit aus, was von Hand
  ///   geschrieben wurde – nach dem Entsperren hätte sie also auch
  ///   niemand neu berechnet.
  /// - [Assets.latitude]/[Assets.longitude] – Aufnahmedaten der Datei,
  ///   nicht aus dem Bild gerechnet, und teils von Hand gesetzt. Sichtbar
  ///   sind sie nicht: [assetsWithLocation] filtert `isLocked`.
  /// - [sharpnessScore] – eine Zahl über die Bildschärfe verrät nichts
  ///   über den Bildinhalt und wird für die Ausschuss-Sichtung gebraucht.
  /// - Die **Einbettung eines Gesichts** (`faces.embedding`). Sie ist aus
  ///   dem Bildinhalt abgeleitet und gehörte nach derselben Regel hierher –
  ///   aber sie liesse sich nicht wiederherstellen. Berechnet wurde sie aus
  ///   einem an den Landmarken **ausgerichteten** Ausschnitt; die Landmarken
  ///   stehen nirgends in der Zeile, und ohne sie fällt
  ///   `FaceEngineService.embedFace` auf einen einfachen Kastenausschnitt
  ///   zurück. Das ergäbe eine andere und schlechtere Einbettung, und die
  ///   Wiedererkennung würde für genau die Fotos schlechter, die jemand
  ///   gesperrt hat. Ein Klartextrest von 512 Byte ist der kleinere Preis;
  ///   festgehalten in der 15. Prüfrunde.
  Future<void> clearDerivedContentData(List<String> assetIds) async {
    await (update(assets)..where((t) => t.id.isIn(assetIds)))
        .write(const AssetsCompanion(
      ocrText: Value(null),
      // Die Stellen stehen im Klartext neben dem Text und verraten mit ihm
      // dasselbe – ohne diese Zeile bliebe der Wortlaut eines gesperrten
      // Fotos in der unverschlüsselten Datenbank stehen.
      ocrBoxen: Value(null),
      ocrScanned: Value(false),
      // Damit die Verschlagwortung nach dem Entsperren neu läuft und die
      // gelöschten Begriffe zurückbringt.
      aiTagsScanned: Value(false),
    ));

    // Die Bildunterschrift getrennt, weil sie nur wegdarf, solange sie
    // wirklich von der Maschine stammt – siehe [aiCaptionEdited] oben.
    await (update(assets)
          ..where((t) => t.id.isIn(assetIds) & t.aiCaptionEdited.equals(false)))
        .write(const AssetsCompanion(
      aiCaption: Value(null),
      // **Beide** Sprachen. Bis zur 17. Prüfrunde stand hier nur die
      // englische, und die Übersetzung blieb im Klartext stehen: Wer sie
      // eingeschaltet hatte, dem nahm das Sperren den einen Satz weg und
      // liess denselben Satz auf Deutsch liegen. Der Test dazu hatte das
      // Feld nie gesetzt und ging deshalb durch.
      aiCaptionDe: Value(null),
      aiCaptionScanned: Value(false),
    ));
    await (delete(imageEmbeddings)..where((t) => t.assetId.isIn(assetIds)))
        .go();
    await (delete(assetTags)
          ..where(
              (t) => t.assetId.isIn(assetIds) & t.quelle.equals(Tagquelle.ki)))
        .go();
    _embeddingsGeneration++;
  }

  /// Hängt Profilbilder um, die auf einen Gesichts-Ausschnitt aus einem
  /// gerade gesperrten Foto zeigen.
  ///
  /// Die Ausschnittdatei selbst wird beim Sperren mitverschlüsselt (siehe
  /// `LibraryState._encryptAssetFiles`) – sie ist also kein Leck. Aber der
  /// Pfad im Profilbild zeigt danach auf Chiffrat: Die Person verliert
  /// ihren Avatar in Erkunden, Personen und Stammbaum, bis das Foto wieder
  /// entsperrt wird.
  ///
  /// Ersetzt wird durch einen Ausschnitt aus einem nicht gesperrten Foto;
  /// gibt es keinen, bleibt die Person ohne Profilbild. Beim Entsperren
  /// wird nichts zurückgehängt – jeder gültige Ausschnitt tut es, und ein
  /// automatisches Zurücksetzen würde eine inzwischen von Hand getroffene
  /// Wahl überschreiben.
  Future<int> verlegeProfilbilderVon(List<String> assetIds) async {
    final betroffen = await (select(faces)
          ..where(
              (t) => t.assetId.isIn(assetIds) & t.cropRelativePath.isNotNull()))
        .get();
    final pfade = [for (final f in betroffen) f.cropRelativePath!];
    if (pfade.isEmpty) return 0;

    final personen = await (select(people)
          ..where((t) => t.coverFaceCropPath.isIn(pfade)))
        .get();
    for (final person in personen) {
      final ersatz = await (select(faces).join([
        innerJoin(assets, assets.id.equalsExp(faces.assetId)),
      ])
            ..where(faces.personId.equals(person.id) &
                faces.cropRelativePath.isNotNull() &
                assets.isLocked.equals(false) &
                assets.isTrashed.equals(false))
            ..limit(1))
          .get();
      await (update(people)..where((t) => t.id.equals(person.id))).write(
        PeopleCompanion(
          coverFaceCropPath: Value(ersatz.isEmpty
              ? null
              : ersatz.first.readTable(faces).cropRelativePath),
        ),
      );
    }
    return personen.length;
  }

  Stream<List<AssetData>> watchLockedAssets() {
    final abfrage = select(assets)
      ..where((t) => t.isLocked.equals(true) & t.isTrashed.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]);
    return _gedrosselt(() => abfrage, TableUpdateQuery.onTable(assets));
  }
}

/// Bricht [AppDatabase.fuegeBeziehungenHinzu] ab und rollt die Transaktion
/// zurück. Rein intern – nach aussen wird daraus wieder ein
/// [Beziehungsfehler].
class _BeziehungAbbruch implements Exception {
  final Beziehungsfehler grund;
  const _BeziehungAbbruch(this.grund);
}

/// Was im Papierkorb liegt, in zwei Zahlen – siehe
/// [AppDatabase.watchPapierkorbUmfang].
class Papierkorbumfang {
  const Papierkorbumfang({required this.anzahl, required this.bytes});

  final int anzahl;
  final int bytes;

  bool get istLeer => anzahl == 0;

  @override
  bool operator ==(Object other) =>
      other is Papierkorbumfang &&
      other.anzahl == anzahl &&
      other.bytes == bytes;

  @override
  int get hashCode => Object.hash(anzahl, bytes);
}
