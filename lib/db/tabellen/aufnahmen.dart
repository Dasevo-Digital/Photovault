part of '../database.dart';

// Tabellen: Aufnahmen und was an ihnen hängt.

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

/// Erinnerungen, die jemand behalten wollte – siehe
/// `screens/erinnerungen_screen.dart`.
///
/// **Die Aufnahmen werden festgehalten, nicht die Frage.** Ein Rückblick
/// entsteht jeden Tag neu aus „was war an diesem Tag"; wer ihn merkt,
/// meint aber genau diese Auswahl – auch wenn später ein Foto ein anderes
/// Datum bekommt oder eins dazukommt. Die Kennungen stehen als JSON-Liste
/// in einer Spalte: Sie werden immer als Ganzes gelesen und geschrieben,
/// und eine Zwischentabelle brächte nur eine zweite Stelle zum Aufräumen.
class GemerkteErinnerungen extends Table {
  TextColumn get id => text()();
  TextColumn get titel => text()();

  /// Der Tag, an dem die Erinnerung spielt (für den Untertitel und die
  /// Reihenfolge), nicht der Tag des Merkens.
  DateTimeColumn get tag => dateTime()();
  TextColumn get assetIds => text()();
  DateTimeColumn get gemerktAm => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Vorschläge für den gesperrten Ordner, die abgelehnt wurden – siehe
/// `services/dokumenterkennung.dart`.
///
/// **Je Aufnahme, nicht je Fund.** Wer seinen Ausweis bewusst offen
/// liegen lässt, will ihn nicht nach jeder neuen Texterkennung wieder
/// vorgelegt bekommen.
class VerworfeneDokumente extends Table {
  TextColumn get assetId => text()();
  DateTimeColumn get verworfenAm => dateTime()();

  @override
  Set<Column> get primaryKey => {assetId};
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
