import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/ai_tagging_service.dart';
import '../services/backup_service.dart';
import '../services/bibliothekssperre.dart';
import '../services/bilddekodierung.dart';
import '../services/blur_detection.dart';
import '../services/florence_captioning_service.dart';
import '../services/clip_service.dart';
import '../services/cube_lut.dart';
import '../services/develop_color.dart';
import '../services/speicher_rueckgabe.dart';
import '../services/translation_service.dart';
import '../services/embedding_codec.dart';
import '../services/embedding_ann_index.dart';
import '../services/eye_state_service.dart';
import '../services/face_engine_service.dart';
import '../services/face_postprocess.dart';
import '../services/geo_data_download_service.dart';
import '../services/import_service.dart';
import '../services/raw_formats.dart';
import '../services/library_location.dart';
import '../services/model_catalog.dart';
import '../services/model_download_service.dart';
import '../services/model_processing_state.dart';
import '../services/ocr_service.dart';
import '../services/personenvorschlag.dart';
import '../services/ortsvorschlag.dart';
import '../services/serienvorschlag.dart';
import '../services/videostandbilder.dart';
import '../services/textstellen.dart';
import '../services/modell_halter.dart';
import '../services/platform/folder_access.dart';
import '../services/native_image_converter.dart';
import '../services/restore_queue_service.dart';
import '../services/restore_service.dart';
import '../services/reverse_geocoder.dart';
import '../widgets/mini_location_map.dart'
    show setzeCartoSchluessel, setzeEigeneKarte, setzeKarteHochaufloesend;
import '../services/segmentation_service.dart';
import '../services/storage_paths.dart';
import '../services/vault_crypto.dart';
import '../services/xmp_writer.dart';
import 'hintergrundlauf.dart';
// [ImportProgress] steht seit der Warteschlange in hintergrundlauf.dart –
// der Lauf hält seinen eigenen Strom, und ein Feld vom Typ
// `Stream<ImportProgress>` in einer Datei, die library_state.dart nicht
// kennen darf, ginge sonst nicht. Von hier weitergereicht, damit die drei
// Dutzend Bildschirme, die den Typ benutzen, ihren Import behalten.
export 'hintergrundlauf.dart' show ImportProgress;

/// Die Schritte der Hintergrundanalyse, in der Reihenfolge ihres Ablaufs.
///
/// Eine Aufzählung statt eines fertigen Namens: Dieser Dienst kennt keine
/// Oberflächensprache, und der Name wird an zwei Stellen angezeigt (Leiste
/// oben, Hintergrundaufgaben). Die Zuordnung zum Text steht dort.
enum Analysestufe {
  bildanalyse,
  texterkennung,
  schlagwoerter,
  bildbeschreibung,
  wiedererkennung
}

/// Der Name einer Stufe in der Oberflächensprache.
String analysestufeName(AppTexte t, Analysestufe stufe) => switch (stufe) {
      Analysestufe.bildanalyse => t.stufeBildanalyse,
      Analysestufe.texterkennung => t.stufeTexterkennung,
      Analysestufe.schlagwoerter => t.stufeSchlagwoerter,
      Analysestufe.bildbeschreibung => t.stufeBildbeschreibung,
      Analysestufe.wiedererkennung => t.stufeWiedererkennung,
    };

/// Fortschritt der Hintergrundanalyse (siehe
/// [LibraryState.starteHintergrundanalyse]).
class AnalyseFortschritt {
  final Analysestufe stufe;
  final int stufeNummer;
  final int stufenGesamt;
  final int erledigt;
  final int gesamt;
  const AnalyseFortschritt({
    required this.stufe,
    required this.stufeNummer,
    required this.stufenGesamt,
    required this.erledigt,
    required this.gesamt,
  });
}

/// Reine Top-Level-Funktion für `compute()` (siehe [LibraryState._decodeAsset]
/// – dasselbe Muster wie `decodeAndResizeThumbnail` in `import_service.dart`).
/// Das Decodieren einer vollen JPEG/HEIC-Vorschau ist für große Fotos die mit
/// Abstand teuerste Einzeloperation vor Gesichtserkennung/CLIP-Einbettung
/// (oft 100+ ms) – lief bisher synchron auf dem Haupt-Isolate und blockierte
/// damit beim Import oder Backfill vieler Fotos hintereinander spürbar die
/// UI. Gibt `null` zurück, wenn die Bytes nicht dekodierbar sind (z.B.
/// beschädigte Datei).
///
/// **Hier wird ohne Deckel dekodiert, und das ist Absicht.** Gemessen an der
/// Prüfbibliothek (19. Prüfrunde):
///
/// ```
/// 20383 × 4077  dekodieren 1442 ms   Arbeitssatz 301 -> 1205 MB
/// 16350 × 3788  dekodieren 1376 ms   Arbeitssatz      ->  981 MB
///  3456 × 5184  dekodieren  755 ms
/// laenger als 4096 Punkte: 1062 von 5784 Aufnahmen ohne Vorschaudatei
/// ```
///
/// Ein Deckel wie bei der Anzeige (`begrenztesBild`) würde diese Spitze
/// nehmen, aber die Ergebnisse ändern: YuNet fände auf einem verkleinerten
/// Bild andere – kleinere – Gesichter, und die Bibliothek bestünde danach
/// aus zwei Beständen, einem vor und einem nach dem Deckel. Die Spitze ist
/// vorübergehend, tritt je Foto einzeln auf und wird mit dem Isolat wieder
/// freigegeben; die Uneinheitlichkeit wäre dauerhaft. Deshalb gemessen,
/// notiert und nicht geändert.
///
/// Die Übergabe an ein weiteres `compute()` (etwa
/// `compute(computeBlurScore, decoded)`) ist dagegen kein Posten: gemessen
/// 28 ms Aufschlag bei 249 MB Bilddaten, bei kleineren Aufnahmen unter der
/// Messgenauigkeit.
img.Image? decodeImageBytes(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}

/// Zentraler App-Zustand: hält Datenbank- und Service-Instanzen bereit und
/// bündelt zusammengesetzte Abläufe (Import inkl. Gesichtserkennung +
/// CLIP-Embedding). Alle KI-Modelle sind quelloffen und laufen komplett
/// lokal (siehe ModelCatalog) – ähnlich wie digiKam lädt die App sie bei
/// Bedarf von offiziellen Open-Source-Quellen herunter, statt sie
/// mitzuliefern oder auf proprietäre Betriebssystem-APIs zu setzen.
class LibraryState extends ChangeNotifier {
  // Ein fehlgeschlagener Start schließt bereits geöffnete Teile; ein neuer
  // Versuch legt sie anschließend frisch an.
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importService;
  late BackupService backupService;
  late ModelDownloadService modelDownloadService;
  ModelProcessingState? modelProcessingState;
  late GeoDataDownloadService geoDataDownloadService;
  late RestoreQueueService restoreQueue;

  Set<String> _outdatedModelPipelines = const {};

  /// KI-Ergebnisse, die zu einer anderen Modellfassung gehören. Die
  /// bestehenden Treffer bleiben sichtbar, bis die entsprechende Aufgabe
  /// bewusst vollständig neu ausgeführt wurde.
  Set<String> get outdatedModelPipelines => _outdatedModelPipelines;

  // Jedes KI-Modell wird erst beim ersten Gebrauch geladen und nach einer
  // Weile Leerlauf wieder freigegeben (siehe ModellHalter, _sweepIdleModels) –
  // vorher lagen hier eager beim App-Start alle sechs Modelle im Speicher
  // (gemessen 1538 MB gegen 213 MB ohne). Nicht `late`, sondern mit einem
  // "nichts installiert"-Platzhalter vorbelegt: Tests bauen LibraryState oft
  // ohne den vollen initialize()-Durchlauf zusammen (siehe
  // audit_optimierungen_test.dart) und dürfen dabei nicht auf ein
  // uninitialisiertes `late`-Feld treffen. _loadModelsIfPresent() ersetzt
  // die Platzhalter beim echten Start durch die tatsächlichen Halter.
  ModellHalter<FaceEngineService> faceEngineHalter =
      _leererHalter('Gesichtserkennung');
  ModellHalter<EyeStateService> eyeStateHalter = _leererHalter('Augen-Zustand');
  // CLIP getrennt nach Encoder: Der Bildteil (335 MB) arbeitet in der
  // Hintergrundanalyse, der Textteil (242 MB) nur, wenn jemand eine
  // Kontext-Suche eintippt. Zusammen wären es 577 MB, von denen die
  // jeweilige Aufgabe die Hälfte nie anfasst. Einzige Ausnahme ist das
  // KI-Tagging, das beide braucht (Bild-Embedding des Fotos gegen
  // Text-Embeddings der Vokabelbegriffe) und deshalb beide leiht.
  ModellHalter<ClipService> clipBildHalter = _leererHalter('CLIP-Bild');
  ModellHalter<ClipService> clipTextHalter = _leererHalter('CLIP-Text');
  ModellHalter<SegmentationService> segmentationHalter =
      _leererHalter('Segmentierung');
  ModellHalter<FlorenceCaptioningService> captioningHalter =
      _leererHalter('Bildbeschreibung');

  /// Die beiden Übersetzungsrichtungen – getrennte Halter, weil sie
  /// getrennt installierbar sind und selten gleichzeitig gebraucht werden.
  ModellHalter<TranslationService> uebersetzungEnDeHalter =
      _leererHalter('translate-en-de');
  ModellHalter<TranslationService> uebersetzungDeEnHalter =
      _leererHalter('translate-de-en');

  /// Texterkennung ohne Betriebssystem-Hilfe – nur ausserhalb von macOS
  /// gebraucht, wo Apples Vision-Framework die Arbeit besser und ohne
  /// Download erledigt.
  ModellHalter<OcrService> ocrHalter = _leererHalter('Texterkennung');

  static ModellHalter<T> _leererHalter<T>(String name) => ModellHalter<T>(
        name: name,
        installiert: false,
        laden: () => throw StateError(
            'LibraryState.initialize() wurde noch nicht aufgerufen.'),
        entsorgen: (_) async {},
      );

  /// Halter, die gerade durch einen frischen ersetzt wurden, während sie
  /// noch in Benutzung waren (siehe _loadModelsIfPresent) – ohne diese Liste
  /// gäbe es keine Referenz mehr, über die sie je freigegeben würden. Wird
  /// vom selben Timer wie die übrigen Halter regelmäßig abgeräumt.
  final List<ModellHalter> _retiredHalters = [];
  Timer? _modellFreigabeTimer;

  List<ModellHalter> get _alleHalter => [
        faceEngineHalter,
        eyeStateHalter,
        clipBildHalter,
        clipTextHalter,
        segmentationHalter,
        captioningHalter,
        uebersetzungEnDeHalter,
        uebersetzungDeEnHalter,
        if (restoreQueue.restoreHalter != null) restoreQueue.restoreHalter!,
      ];

  /// Kein eigenes ONNX-Modell (siehe ai_tagging_service.dart) – braucht nur
  /// eine bereits geladene [ClipService]-Sitzung als Parameter, deshalb ohne
  /// eigenen Halter und für die ganze App-Laufzeit unverändert nutzbar.
  final AiTaggingService aiTaggingService = AiTaggingService();

  /// Name der geöffneten Bibliothek – nur gesetzt, wenn überhaupt mehr als
  /// eine bekannt ist. Sonst wäre die Anzeige in der Navigationsleiste ein
  /// Hinweis ohne Aussage.
  String? aktiveBibliothek;

  ReverseGeocoder? geocoder;

  /// Läuft, solange der GeoNames-Datensatz noch gelesen wird.
  ///
  /// **Warum das nebenher läuft.** `cities1000.txt` ist 31 MB gross, und
  /// es zu lesen dauert an der echten Datei **376 ms** – gemessen. Das
  /// lag bis hierher vor `_ready`, also vor dem ersten Bild: Jeder Start
  /// begann mit einer reichlichen Drittelsekunde Ladeanzeige für etwas,
  /// das für das erste Bild niemand braucht.
  ///
  /// Wer die Ortsauflösung wirklich braucht (der Import und das
  /// Nachtragen), wartet hierauf. Die Ansichten fragen weiterhin nur
  /// [geocoder] ab und bekommen `null`, solange nichts da ist – nach dem
  /// Laden folgt ein [notifyListeners], damit sich das gerade richtet.
  Future<void> get geoBereit => _geoLaeuft;
  Future<void> _geoLaeuft = Future<void>.value();
  bool _ready = false;
  bool get isReady => _ready;

  String? _initialisierungsfehler;
  String? get initialisierungsfehler => _initialisierungsfehler;
  bool _initialisierungLaeuft = false;
  bool _datenbankGeoeffnet = false;

  /// Gesetzt, wenn eine andere Instanz dieselbe Bibliothek hält. [initialize]
  /// bricht dann ab, BEVOR die Datenbank geöffnet wird – die Oberfläche zeigt
  /// statt der Bibliothek den [BibliothekBelegtScreen]. Siehe
  /// [Bibliothekssperre]: Nur eine wirklich belegte Sperre führt hierher, ein
  /// unbeantwortbarer Fall wird durchgelassen.
  bool _bibliothekBelegt = false;
  bool get bibliothekBelegt => _bibliothekBelegt;

  /// Der Ort, an dem es klemmt – für die Meldung, damit erkennbar ist, um
  /// WELCHE Bibliothek es geht, wenn mehrere in der Liste stehen.
  String? _belegterOrt;
  String? get belegterOrt => _belegterOrt;

  // Cache für AppDatabase.allEmbeddings() (KI-Suche, Ähnliche Fotos,
  // Duplikatsuche) – bei einer großen Bibliothek ein potenziell sehr großes
  // Ergebnis (mehrere hundert MB an CLIP-Vektoren), das bisher bei JEDEM
  // Öffnen einer dieser drei Ansichten neu aus der DB geladen wurde. Statt
  // eines aktiv nachgeführten (Timer/Stream-basierten) Caches – der auch bei
  // völlig unrelated Mutationen wie einem einzelnen Favoriten-Toggle ständig
  // im Hintergrund neu laden würde – wird hier nur EINMALIG geladen und beim
  // nächsten Zugriff über AppDatabase.embeddingsGeneration (siehe dort)
  // günstig geprüft, ob sich seitdem überhaupt etwas Relevantes geändert hat.
  Map<String, Float32List>? _embeddingsCache;
  int? _embeddingsCacheGeneration;

  EmbeddingAnnIndex? _embeddingAnnIndex;
  int? _embeddingAnnIndexGeneration;

  Future<Map<String, Float32List>> cachedEmbeddings() async {
    if (_embeddingsCache != null &&
        _embeddingsCacheGeneration == db.embeddingsGeneration) {
      return _embeddingsCache!;
    }
    final result = await db.allEmbeddings();
    _embeddingsCache = result;
    _embeddingsCacheGeneration = db.embeddingsGeneration;
    return result;
  }

  /// Exakte Rangfolge auf einer persistent vorgefilterten Kandidatenmenge.
  /// Für kleine Bestände oder einen zu dünnen Bucket-Vorrat fällt die Methode
  /// bewusst auf die vollständige Suche zurück – Annäherung darf nie weniger
  /// Ergebnisse liefern als die Oberfläche verlangt.
  Future<Map<String, Float32List>> similarityCandidates(Float32List query,
      {required int minimum}) async {
    final ids = await db.embeddingAssetIds();
    EmbeddingAnnIndex? index = _embeddingAnnIndex;
    if (index == null ||
        _embeddingAnnIndexGeneration != db.embeddingsGeneration) {
      index = await EmbeddingAnnIndex.load(paths.embeddingAnnIndexFile, ids);
      if (index == null) {
        index = EmbeddingAnnIndex.build(await cachedEmbeddings());
        await index.save(paths.embeddingAnnIndexFile);
      }
      _embeddingAnnIndex = index;
      _embeddingAnnIndexGeneration = db.embeddingsGeneration;
    }
    final candidateIds = index.candidates(query, minimum: minimum);
    if (candidateIds.length < minimum || candidateIds.length >= ids.length) {
      return cachedEmbeddings();
    }
    return db.embeddingsForAssetIds(candidateIds);
  }

  /// Kandidaten für die semantische Textsuche. Der persistente Index deckt
  /// die Hauptbilder ab; zusätzliche Video-Standbilder kommen vollständig
  /// dazu, damit eine Szene in der Mitte eines Videos nicht verlorengeht.
  /// Nach einem engen UI-Filter fällt der Weg auf die exakte Menge zurück,
  /// sobald der ANN-Vorrat zu wenige zugelassene Aufnahmen enthält.
  Future<Map<String, Float32List>> textSimilarityCandidates(
    Float32List query,
    Set<String> allowedAssetIds, {
    required int minimum,
  }) async {
    final primary = await similarityCandidates(query, minimum: minimum);
    final out = <String, Float32List>{
      for (final entry in primary.entries)
        if (allowedAssetIds.contains(entry.key)) entry.key: entry.value,
    };
    final videos = await cachedVideoEinbettungen();
    for (final entry in videos.entries) {
      if (!allowedAssetIds.contains(entry.key)) continue;
      for (var i = 0; i < entry.value.length; i++) {
        out['${entry.key}#$i'] = entry.value[i];
      }
    }
    final distinctAssets = {
      for (final key in out.keys) aufnahmeAusSuchschluessel(key),
    };
    if (distinctAssets.length >= minimum || allowedAssetIds.length <= minimum) {
      return out;
    }
    final exact = await suchkandidaten();
    return {
      for (final entry in exact.entries)
        if (allowedAssetIds.contains(aufnahmeAusSuchschluessel(entry.key)))
          entry.key: entry.value,
    };
  }

  /// Die zusätzlichen Einbettungen der Video-Standbilder – **nur für die
  /// Suche** (siehe [Videoeinbettungen]).
  ///
  /// Derselbe Zwischenspeicher wie bei [cachedEmbeddings] und dieselbe
  /// Gültigkeitsprüfung: Beide ändern sich aus denselben Gründen.
  Map<String, List<Float32List>>? _videoEinbettungenCache;
  int? _videoEinbettungenGeneration;

  Future<Map<String, List<Float32List>>> cachedVideoEinbettungen() async {
    if (_videoEinbettungenCache != null &&
        _videoEinbettungenGeneration == db.embeddingsGeneration) {
      return _videoEinbettungenCache!;
    }
    final ergebnis = await db.alleVideoeinbettungen();
    _videoEinbettungenCache = ergebnis;
    _videoEinbettungenGeneration = db.embeddingsGeneration;
    return ergebnis;
  }

  /// Die Kandidaten der Textsuche: je Aufnahme ihre Einbettung, bei
  /// Videos zusätzlich die ihrer weiteren Standbilder.
  ///
  /// **Die Schlüssel tragen die Stelle mit** (`kennung#2`), damit die
  /// Rangfolge jedes Standbild einzeln bewerten kann. Es zählt das
  /// **beste**, nicht das Mittel: Ein Mittelwert über verschiedene Szenen
  /// wäre ein Vektor, der zu nichts mehr recht passt. Zurück auf die
  /// Aufnahme kommt man über [aufnahmeAusSuchschluessel].
  Future<Map<String, Float32List>> suchkandidaten() async {
    final einzeln = await cachedEmbeddings();
    final videos = await cachedVideoEinbettungen();
    if (videos.isEmpty) return einzeln;
    return {
      ...einzeln,
      for (final e in videos.entries)
        for (var i = 0; i < e.value.length; i++) '${e.key}#$i': e.value[i],
    };
  }

  /// Die Aufnahmekennung zu einem Schlüssel aus [suchkandidaten].
  static String aufnahmeAusSuchschluessel(String schluessel) {
    final trenner = schluessel.lastIndexOf('#');
    return trenner < 0 ? schluessel : schluessel.substring(0, trenner);
  }

  /// Die Serienvorschläge – einmal gerechnet, nicht bei jedem Blick.
  ///
  /// **Warum das einen Zwischenspeicher braucht.** Die Rechnung kostet an
  /// der gewachsenen Bibliothek 260 ms (7441 Einbettungen, 499 Gruppen),
  /// und der grössere Teil davon ist das Kopieren der Einbettungen über
  /// die Isolate-Grenze, das [compute] für jeden Aufruf erneut macht.
  /// Gelaufen ist sie bis hierher **zweimal je Rundgang**: einmal beim
  /// Öffnen des Serienbildschirms und noch einmal, wenn die Werkzeugliste
  /// nach der Rückkehr ihre Zahl auffrischte. Wer mehrere Serien
  /// nacheinander übernahm, zahlte das jedes Mal.
  ///
  /// Gültig bleibt der Vorrat, solange sich an den Einbettungen nichts
  /// ändert (Import, Papierkorb, Sperren – siehe
  /// [AppDatabase.embeddingsGeneration]). Was der Anwender selbst
  /// erledigt, nimmt [serieErledigt] heraus; ein Neuaufbau ist dafür
  /// nicht nötig, denn eine übernommene Gruppe ist genau das, was die
  /// nächste Rechnung ohnehin weglassen würde.
  List<List<AssetData>>? _serienCache;
  int? _serienCacheGeneration;

  Future<List<List<AssetData>>> serienvorschlaegeGecacht() async {
    if (_serienCache != null &&
        _serienCacheGeneration == db.embeddingsGeneration) {
      return _serienCache!;
    }
    final gruppen = await serienvorschlaege(db, await cachedEmbeddings());
    _serienCache = gruppen;
    _serienCacheGeneration = db.embeddingsGeneration;
    return gruppen;
  }

  /// Diese Gruppe ist übernommen oder verworfen – aus dem Vorrat damit.
  void serieErledigt(List<AssetData> gruppe) {
    _serienCache?.removeWhere((g) => identical(g, gruppe));
    notifyListeners();
  }

  /// Alle auf einmal erledigt.
  void serienGeleert() {
    _serienCache = const [];
    _serienCacheGeneration = db.embeddingsGeneration;
    notifyListeners();
  }

  /// Die Ortsvorschläge – was unverortete Aufnahmen von ihren zeitlichen
  /// Nachbarn erben könnten (siehe `services/ortsvorschlag.dart`).
  ///
  /// **Ohne Zwischenspeicher, anders als bei den Serien.** Die Rechnung
  /// braucht keine Einbettungen und keinen Isolatwechsel; an der echten
  /// Bibliothek (5351 ohne Ort, 2092 mit) kostet sie **2 ms**. Ein
  /// Vorrat wäre hier nur eine zweite Wahrheit, die veralten kann.
  ///
  /// Abgelehnte Bündel bleiben abgelehnt: Der Vorschlag entsteht bei
  /// jedem Aufruf neu aus den Daten, und ohne das Gedächtnis stünde ein
  /// „nein" beim nächsten Öffnen wieder da.
  Future<List<Ortsbuendel>> ortsvorschlagsbuendel() async {
    final daten = await db.ortsvorschlagsdaten();
    final vorschlaege = ortsvorschlaege(daten.ohneOrt, daten.verortet);
    if (vorschlaege.isEmpty) return const [];
    final zeiten = {for (final o in daten.ohneOrt) o.id: o.wann};
    final verworfen = await db.verworfeneOrtsvorschlagsschluessel();
    return [
      for (final b in buendleOrtsvorschlaege(vorschlaege, zeiten))
        if (!verworfen.contains(b.schluessel)) b,
    ];
  }

  /// Übernimmt ein Bündel: Die Aufnahmen bekommen den Ort ihrer Nachbarn,
  /// gekennzeichnet als geerbt ([Assets.ortGeerbt]).
  ///
  /// Die ausgeschriebenen Ortsnamen kommen gleich hinterher – dieselbe
  /// Umkehr-Geokodierung, die auch beim Import läuft. Ohne sie stünde die
  /// Aufnahme mit einer Koordinate und ohne Ortsnamen da, und die
  /// Ortsgruppen der Übersicht sähen sie nicht.
  Future<void> uebernimmOrtsbuendel(Ortsbuendel buendel) async {
    final ids = [for (final v in buendel.vorschlaege) v.assetId];
    await db.uebernimmOrtsvorschlag(ids, buendel.breite, buendel.laenge);
    final treffer = geocoder?.lookup(buendel.breite, buendel.laenge);
    if (treffer != null) {
      await db.setLocationNamesBulk(ids,
          country: treffer.country, state: treffer.state, city: treffer.city);
    }
    notifyListeners();
  }

  Timer? _autoBackupTimer;
  bool _autoBackupRunning = false;
  Timer? _trashPurgeTimer;
  bool _trashPurgeRunning = false;

  /// Schwelle für "Ähnliche mit auswählen" (Personen-Tab) – zentral hier
  /// statt lokal im Screen gehalten, damit sie auch im "Werkzeuge"-Bereich
  /// eingestellt werden kann. 0.363 ist der von OpenCV Zoo für SFace
  /// dokumentierte Kosinus-Ähnlichkeits-Schwellwert für "gleiche Person"
  /// (gilt seit der Landmark-Ausrichtung vor dem Embedding, siehe
  /// FaceEngineService.alignFace – mit dem vorherigen reinen
  /// Bounding-Box-Crop lagen die Werte auf einer anderen, unkalibrierten
  /// Skala).
  ///
  /// Wird beim Start aus [AppSettings] geladen und beim Ändern dorthin
  /// zurückgeschrieben – vorher lag der Wert nur im Speicher und der
  /// Regler stand nach jedem Programmstart wieder auf dem Ausgangswert,
  /// ohne dass das irgendwo stand.
  double faceSimilarityThreshold = 0.363;

  Future<void> ladeGesichtsSchwelle() async {
    faceSimilarityThreshold = await db.faceSimilarityThresholdWert();
    notifyListeners();
  }

  /// Setzt die allgemeine Schwelle. Die persönlichen Schwellen einzelner
  /// Personen werden dabei mitgezogen (siehe
  /// `AppDatabase.setFaceSimilarityThreshold`).
  Future<void> setFaceSimilarityThreshold(double value) async {
    faceSimilarityThreshold = value;
    notifyListeners();
    await db.setFaceSimilarityThreshold(value);
  }

  /// Die für [personId] geltende Schwelle: die persönliche, sonst die
  /// allgemeine.
  double schwelleFuerPerson(PersonData person) =>
      person.similarityThreshold ?? faceSimilarityThreshold;

  /// Wer könnte auf [einbettung] zu sehen sein?
  ///
  /// Gibt `null` zurück, wenn nichts nahe genug ist – der Regelfall bei
  /// einem fremden Gesicht, und richtig so: Ein falscher Vorschlag, den
  /// jemand übersieht und bestätigt, kostet eine falsche Zuordnung.
  ///
  /// [ausser] lässt eine Person aus. Gebraucht beim Umbenennen: Dort ist
  /// die aktuelle Zuordnung bekannt, und sie sich selbst vorzuschlagen
  /// hilft niemandem.
  /// Die Kerne der benannten Personen, solange sich an den Zuordnungen
  /// nichts geaendert hat.
  ///
  /// **Warum das gemerkt gehoert.** Sie zu bilden heisst: 2366
  /// Einbettungen zu je 512 Zahlen laden und mitteln. An der echten
  /// Bibliothek kostet das **62 ms warm und 507 ms beim ersten Mal** –
  /// und [personenvorschlag] laeuft bei jedem Tippen auf ein Gesicht,
  /// beim Oeffnen des Infoblatts und bei jedem Schritt durch die
  /// Gesichter-Durchsicht. Gerechnet wurde dabei jedes Mal dasselbe.
  List<Personenkern>? _kerne;
  Map<String, double>? _schwellen;
  String? _abdruck;

  /// Woran erkannt wird, dass der Vorrat nicht mehr gilt – **eine
  /// Abfrage, 3,5 ms.**
  ///
  /// **Nicht ueber `tableUpdates`.** Der Weg gaebe es, und er waere
  /// billiger; er meldet aber ueber einen Strom, also **spaeter** als der
  /// naechste Aufruf. Wer ein Gesicht benennt und sofort das naechste
  /// antippt, bekaeme den Vorschlag von vorhin. Dass in der Bedienung
  /// meist ein Wimpernschlag dazwischenliegt, ist keine Zusicherung.
  ///
  /// Gezaehlt wird nicht nur, WIE VIELE Gesichter zugeordnet sind,
  /// sondern auch WEM: Die Summe aus Gesichts- und Personenzeile faengt
  /// das Umhaengen einer Zuordnung, das Zahl und Zeilenzahl unveraendert
  /// liesse. Und die Schwellen kommen mit, weil eine Ablehnung sie
  /// verschiebt, ohne ein einziges Gesicht anzufassen.
  static const _abdruckSql =
      'SELECT count(*) AS n, coalesce(sum(f.rowid),0) AS a, '
      'coalesce(sum(p.rowid),0) AS b, coalesce(sum(f.rowid*p.rowid),0) AS c, '
      '(SELECT count(*) FROM people) AS pn, '
      '(SELECT coalesce(sum(coalesce(similarity_threshold,0)),0) FROM people) '
      '  AS ps '
      'FROM faces f JOIN people p ON p.id = f.person_id '
      'WHERE f.embedding IS NOT NULL';

  Future<String> _zuordnungsabdruck() async {
    final z = await db.customSelect(_abdruckSql).getSingle();
    return [
      z.read<int>('n'),
      z.read<int>('a'),
      z.read<int>('b'),
      z.read<int>('c'),
      z.read<int>('pn'),
      z.read<double>('ps'),
    ].join('/');
  }

  Future<List<Personenkern>> _personenkerne() async {
    final abdruck = await _zuordnungsabdruck();
    final vorrat = _kerne;
    if (vorrat != null && abdruck == _abdruck) return vorrat;

    final roh = await db.einbettungenZugeordneterGesichter();
    final leute = {for (final p in await db.select(db.people).get()) p.id: p};
    final gebildet = personenkerne([
      for (final e in roh)
        if (leute.containsKey(e.personId))
          (personId: e.personId, vektor: floatsFromEmbeddingBlob(e.vektor)),
    ]);
    _kerne = gebildet;
    // Die Schwellen wandern mit in den Vorrat, der Name NICHT: Wer
    // umbenannt wird, soll beim naechsten Vorschlag seinen neuen Namen
    // tragen, und dafuer wird die Person unten frisch geladen.
    _schwellen = {
      for (final e in leute.entries)
        if (e.value.similarityThreshold != null)
          e.key: e.value.similarityThreshold!,
    };
    _abdruck = abdruck;
    return gebildet;
  }

  Future<PersonData?> personenvorschlag(Uint8List? einbettung,
      {String? ausser}) async {
    if (einbettung == null) return null;
    final alleKerne = await _personenkerne();
    // [ausser] faellt erst hier heraus: Der Vorrat gilt fuer alle
    // Aufrufer, und eine Person auszulassen ist die Sache dieses einen.
    final kerne = ausser == null
        ? alleKerne
        : [
            for (final k in alleKerne)
              if (k.personId != ausser) k
          ];
    final treffer = besterTreffer(
      floatsFromEmbeddingBlob(einbettung),
      kerne,
      schwelleFuer: (id) => _schwellen?[id] ?? faceSimilarityThreshold,
    );
    if (treffer == null) return null;
    return (db.select(db.people)..where((t) => t.id.equals(treffer.personId)))
        .getSingleOrNull();
  }

  /// Übersetzt [text] ins Englische, sofern das Modell installiert und die
  /// Einstellung eingeschaltet ist – sonst kommt [text] unverändert zurück.
  ///
  /// Gebraucht, weil der CLIP-Text-Encoder nur Englisch versteht, das
  /// Tag-Vokabular aber deutsch ist und die Suche in einer deutschen
  /// Oberfläche stattfindet. An 103 Fotos gemessen trennt die übersetzte
  /// Fassung bei 33 von 56 Vokabelbegriffen schärfer, bei 19 schlechter –
  /// ein realer, aber weder grosser noch durchgängiger Gewinn. Deshalb
  /// eine Einstellung und keine stille Umstellung.
  ///
  /// Schlägt die Übersetzung fehl, gilt der Ausgangstext: Eine Suche, die
  /// mittelmässige Treffer liefert, ist besser als eine, die eine
  /// Fehlermeldung liefert.
  Future<String> insEnglische(String text) async {
    if (text.trim().isEmpty) return text;
    if (!uebersetzungDeEnHalter.installiert) return text;
    if (!await db.uebersetzeSucheUndTags()) return text;
    try {
      // `mit` gibt null zurück, wenn das Modell doch nicht ladbar war.
      final uebersetzt =
          await uebersetzungDeEnHalter.mit((s) => s.translate(text));
      if (uebersetzt == null || uebersetzt.trim().isEmpty) return text;
      return uebersetzt;
    } catch (e) {
      debugPrint('Übersetzung der Anfrage fehlgeschlagen: $e');
      return text;
    }
  }

  String? _modelsDir;
  String get modelsDir => _modelsDir!;

  /// Einmalige Anfrage von "Foto in der Timeline anzeigen" (Kontextmenü der
  /// Vollbildansicht): [HomeShell] wechselt beim nächsten Build auf den
  /// Timeline-Tab und reicht die ID an [MonthGroupedAssetGrid] weiter, das
  /// dorthin scrollt und das Foto kurz hervorhebt. Absichtlich ohne eigenen
  /// `notifyListeners()`-Aufruf beim Zurücksetzen (siehe
  /// [clearTimelineHighlightRequest]) – der einmalige Verbrauch reicht, ein
  /// zusätzlicher Rebuild dafür wäre unnötig.
  String? _timelineHighlightAssetId;
  String? get timelineHighlightAssetId => _timelineHighlightAssetId;

  void requestTimelineHighlight(String assetId) {
    _timelineHighlightAssetId = assetId;
    notifyListeners();
  }

  void clearTimelineHighlightRequest() {
    _timelineHighlightAssetId = null;
  }

  /// Einmalige Anfrage „zeig mir den Bereich mit dieser Nummer".
  ///
  /// Dieselbe Machart wie [requestTimelineHighlight] daneben, und aus
  /// demselben Grund: Ein Bildschirm tief im Arbeitsbereich kann die
  /// Menüleiste nicht selbst umschalten – sie liegt über ihm. Gebraucht
  /// wird das vom Gesundheitsbildschirm, der offene Arbeit meldet und den
  /// Weg dorthin anbieten will, ohne die Maschinerie dahinter ein zweites
  /// Mal zu bauen.
  ///
  /// Die Nummern stehen in [Hauptbereich]; hier steht bewusst nur ein
  /// `int`, damit die Zustandsklasse nichts von der Oberfläche wissen muss.
  int? _bereichswunsch;
  int? get bereichswunsch => _bereichswunsch;

  void zeigeBereich(int nummer) {
    _bereichswunsch = nummer;
    notifyListeners();
  }

  void bereichswunschErledigt() {
    _bereichswunsch = null;
  }

  Future<void> initialize() async {
    if (_initialisierungLaeuft) return;
    _initialisierungLaeuft = true;
    _initialisierungsfehler = null;
    _ready = false;
    try {
      await _initialize();
    } catch (e, spur) {
      debugPrint('Photo Vault konnte nicht initialisiert werden: $e');
      debugPrintStack(stackTrace: spur);
      await _raeumeFehlgeschlagenenStartAuf();
      _bibliothekBelegt = false;
      _belegterOrt = null;
      _initialisierungsfehler = e.toString();
      notifyListeners();
    } finally {
      _initialisierungLaeuft = false;
    }
  }

  Future<void> _raeumeFehlgeschlagenenStartAuf() async {
    _autoBackupTimer?.cancel();
    _trashPurgeTimer?.cancel();
    _ordnerTimer?.cancel();
    _modellFreigabeTimer?.cancel();
    _autoBackupTimer = null;
    _trashPurgeTimer = null;
    _ordnerTimer = null;
    _modellFreigabeTimer = null;
    if (_datenbankGeoeffnet) {
      try {
        await db.close();
      } catch (_) {
        // Der ursprüngliche Startfehler bleibt die aussagekräftige Meldung.
      }
      _datenbankGeoeffnet = false;
    }
    await Bibliothekssperre.gib();
  }

  Future<void> _initialize() async {
    // ERST die Bibliothek beanspruchen, DANN die Datenbank öffnen. Zwei
    // Instanzen auf derselben Datei zeigen verschiedene Stände, lassen
    // Hintergrundaufgaben doppelt laufen und schreiben abwechselnd
    // übereinander. Die Wartezeit aus AppDatabase.sperrwartezeitMs wendet
    // den Schaden ab, nicht die Verwirrung.
    final wurzel = await LibraryLocation.currentRoot();
    final befund = await Bibliothekssperre.nimm(wurzel);
    if (befund.zustand == Sperrzustand.belegt) {
      _bibliothekBelegt = true;
      _belegterOrt = wurzel.path;
      notifyListeners();
      return;
    }
    _bibliothekBelegt = false;
    _belegterOrt = null;

    db = await AppDatabase.open();
    _datenbankGeoeffnet = true;
    paths = await StoragePaths.instance();
    modelProcessingState = ModelProcessingState(paths.modelProcessingStateFile);
    _outdatedModelPipelines = await modelProcessingState!.initialize(
      ModelProcessingState.currentFingerprints(),
    );
    importService = ImportService(db, paths);
    backupService = BackupService(db, paths);
    restoreQueue = RestoreQueueService(db, paths);

    // Nicht mehr selbst aus dem App-Support-Ordner gebaut: Unter Windows
    // liegt der Datenordner im MSIX-Paket woanders als in der
    // ausgepackten Fassung, und diese Stelle hier hätte sonst weiter auf
    // den Paketbehälter gezeigt, während die Bibliothek am alten Ort
    // liegt - Modelle und Geodaten wären grundlos neu heruntergeladen
    // worden. LibraryLocation.datenordner() entscheidet das an einer
    // Stelle für alle.
    final datenordner = await LibraryLocation.datenordner();
    _modelsDir = p.join(datenordner.path, 'models');
    await Directory(_modelsDir!).create(recursive: true);
    modelDownloadService = ModelDownloadService(_modelsDir!);

    final geoDataDir = p.join(datenordner.path, 'geodata');
    await Directory(geoDataDir).create(recursive: true);
    geoDataDownloadService = GeoDataDownloadService(geoDataDir);

    // Reste abgebrochener Modell-Downloads wegräumen, bevor irgendetwas
    // den Modellordner ansieht – sie sind nutzlos und können mehrere
    // hundert MB belegen (Audit-Fund).
    unawaited(modelDownloadService.raeumeAbgebrocheneDownloads());
    unawaited(modelDownloadService.raeumeAbgeloesteModelle());
    // Welche Bibliothek ist offen? Nur anzeigen, wenn es eine Wahl gibt.
    try {
      final bekannt = await LibraryLocation.bekannte();
      if (bekannt.length > 1) {
        aktiveBibliothek = bekannt
            .where((b) => b.istAktiv)
            .map((b) => b.eintrag.name)
            .firstOrNull;
      }
    } catch (e) {
      debugPrint('Bibliotheksliste nicht lesbar: $e');
    }

    await ladeGesichtsSchwelle();
    // Vor dem ersten Bild und nicht erst über den Einstellungsstrom in
    // main.dart: Sonst zeichnete die erste Karte einen Atemzug lang die
    // schlüssellose Fassung und lüde ihre Kacheln zweimal.
    setzeCartoSchluessel(await db.cartoSchluesselWert());
    setzeEigeneKarte(await db.eigeneKarteWert());
    setzeKarteHochaufloesend(await db.karteHochaufloesendWert());
    _maxGleichzeitig = await db.maxGleichzeitigeAufgaben();
    await _loadModelsIfPresent();
    // Ohne `await`: siehe [geoBereit]. Das Lesen des GeoNames-Datensatzes
    // kostet 376 ms, und das erste Bild braucht ihn nicht.
    _geoLaeuft = _loadGeoDataIfPresent().then((_) {
      if (geocoder != null) notifyListeners();
    });
    // Absichtlich ohne `await`: Bei einem grossen Stammbaum sind das
    // viele einzelne Schreibvorgänge, und der Start soll nicht darauf
    // warten. Die Ereignisse tauchen dann eben eine Sekunde später auf
    // der Karte auf.
    unawaited(trageEreignisorteNach());
    await clearDecryptCache();

    // Crash-Safety: ein Restaurierungs-Auftrag, der beim letzten Beenden
    // noch "running" war (App wurde mitten in der Verarbeitung beendet/ist
    // abgestürzt), zurück auf "queued" setzen und die Warteschlange dann
    // fortsetzen – siehe AppDatabase.resetStuckRunningRestoreJobs.
    await db.resetStuckRunningRestoreJobs();
    unawaited(restoreQueue.resume());

    // Automatisches Backup läuft nur, während die App offen ist (kein
    // Hintergrunddienst) – einmal direkt beim Start prüfen (falls das
    // Intervall während der App war geschlossen abgelaufen ist) und danach
    // regelmäßig, damit es auch bei einer lange offenen Sitzung nicht erst
    // beim nächsten Neustart nachgeholt wird.
    unawaited(runAutoBackupIfDue());
    _autoBackupTimer = Timer.periodic(
        const Duration(minutes: 30), (_) => runAutoBackupIfDue());

    // Automatischer Papierkorb-Ablauf – aus demselben Grund (kein
    // Hintergrunddienst) ebenfalls einmal direkt beim Start geprüft und
    // danach regelmäßig. Ein gröberes Intervall als beim Backup reicht hier,
    // da "nach N Tagen" ohnehin keine Sekundengenauigkeit braucht.
    unawaited(purgeExpiredTrashIfDue());
    _trashPurgeTimer = Timer.periodic(
        const Duration(hours: 6), (_) => purgeExpiredTrashIfDue());

    // Überwachter Ordner – einmal beim Start und danach regelmässig, aus
    // demselben Grund wie beim automatischen Backup: Es gibt keinen
    // Hintergrunddienst, der das erledigen könnte.
    unawaited(pruefeUeberwachtenOrdner());
    _ordnerTimer =
        Timer.periodic(_ordnerIntervall, (_) => pruefeUeberwachtenOrdner());

    // Gibt KI-Modelle frei, die seit dem letzten Durchlauf nicht mehr in
    // Benutzung sind (siehe ModellHalter.freigebenWennUnbenutzt) – das ist
    // der Gegenpart zum bedarfsweisen Laden: ohne das hier bliebe ein einmal
    // benutztes Modell bis zum Beenden der App im Speicher.
    _modellFreigabeTimer =
        Timer.periodic(const Duration(minutes: 2), (_) => _sweepIdleModels());

    _ready = true;
    notifyListeners();

    // Eine beim letzten Beenden unfertige Hintergrundanalyse fortsetzen.
    // Sie ist nach einem Import mit mehreren tausend Fotos stundenlang
    // unterwegs – die App zwischendurch zu schließen ist der Normalfall,
    // und ohne diesen Aufruf bliebe die Bibliothek halb ausgewertet, bis
    // der nächste Import läuft oder jemand den Knopf in den Werkzeugen
    // findet (Audit-Fund). Ein eigener Fortschrittsstand ist dafür nicht
    // nötig: Jede Stufe ermittelt selbst, welche Fotos ihr noch fehlen,
    // und ist damit gefahrlos wiederholbar. Erst NACH `_ready`, damit der
    // Start der Oberfläche nicht darauf wartet.
    if (await db.autoAnalyzeAfterImportEnabled()) {
      unawaited(starteHintergrundanalyse());
    }
  }

  /// Prüft, welche Modelldateien bereits im models-Ordner liegen, und legt
  /// dafür je einen [ModellHalter] an (der die eigentliche Engine erst beim
  /// ersten Gebrauch lädt). Wird auch nach einem Download in den
  /// Einstellungen erneut aufgerufen ([reloadModels]) – dann ersetzt ein
  /// frischer Halter den alten, weil `installiert` sich nur beim Anlegen
  /// ermittelt (siehe ModellHalter-Klassenkommentar). Ein alter Halter, der
  /// gerade noch in Benutzung ist, wird nicht zwangsweise entsorgt (das
  /// würde eine laufende Inferenz zum Absturz bringen), sondern in
  /// [_retiredHalters] geparkt und dort vom selben Timer wie die übrigen
  /// Halter abgeräumt, sobald er wieder frei ist – die frühere
  /// Sonderbehandlung von `restoreService` ("während eines Auftrags nicht
  /// ersetzen") ist dadurch nicht mehr nötig, siehe RestoreQueueService.
  Future<void> _loadModelsIfPresent() async {
    // Die Platzhalter aus den Feld-Initialisierern (nichts installiert,
    // nie geladen) landen hier harmlos: _sweepIdleModels() entfernt sie
    // beim nächsten Durchlauf sofort wieder aus _retiredHalters, da
    // `istGeladen` nie true war. _alleHalter liest dieselben (gleich
    // überschriebenen) Felder, daher identisch zu einer eigenen Liste hier.
    _retiredHalters.addAll(_alleHalter);

    faceEngineHalter = ModellHalter<FaceEngineService>(
      name: 'Gesichtserkennung',
      installiert: FaceEngineService.isDetectionAvailable(_modelsDir!),
      // load() ist nullable, weil es intern denselben Dateicheck wie
      // isDetectionAvailable() wiederholt – der ist hier über `installiert`
      // oben bereits als true bekannt, daher unbedenklich entpackt.
      laden: () async => (await FaceEngineService.load(_modelsDir!))!,
      entsorgen: (s) => s.dispose(),
    );
    eyeStateHalter = ModellHalter<EyeStateService>(
      name: 'Augen-Zustand',
      installiert: EyeStateService.isAvailable(_modelsDir!),
      // Gleiches Argument wie bei faceEngineHalter oben.
      laden: () async => (await EyeStateService.load(_modelsDir!))!,
      entsorgen: (s) => s.dispose(),
    );
    // Beide Halter prüfen dieselben Dateien (isAvailable deckt Bild-,
    // Text-Encoder und Tokenizer gemeinsam ab), laden aber jeweils nur
    // ihren Teil – siehe ClipService.load.
    clipBildHalter = ModellHalter<ClipService>(
      name: 'CLIP-Bild',
      installiert: ClipService.isAvailable(_modelsDir!),
      laden: () => ClipService.load(_modelsDir!, bild: true, text: false),
      entsorgen: (s) => s.dispose(),
    );
    clipTextHalter = ModellHalter<ClipService>(
      name: 'CLIP-Text',
      installiert: ClipService.isAvailable(_modelsDir!),
      laden: () => ClipService.load(_modelsDir!, bild: false, text: true),
      entsorgen: (s) => s.dispose(),
    );
    segmentationHalter = ModellHalter<SegmentationService>(
      name: 'Segmentierung',
      installiert: SegmentationService.isAvailable(_modelsDir!),
      laden: () => SegmentationService.load(_modelsDir!),
      entsorgen: (s) => s.dispose(),
    );
    uebersetzungEnDeHalter = ModellHalter<TranslationService>(
      name: 'translate-en-de',
      installiert: TranslationService.isAvailable(
          _modelsDir!, Uebersetzungsrichtung.enDe),
      laden: () =>
          TranslationService.load(_modelsDir!, Uebersetzungsrichtung.enDe),
      entsorgen: (s) => s.dispose(),
    );
    uebersetzungDeEnHalter = ModellHalter<TranslationService>(
      name: 'translate-de-en',
      installiert: TranslationService.isAvailable(
          _modelsDir!, Uebersetzungsrichtung.deEn),
      laden: () =>
          TranslationService.load(_modelsDir!, Uebersetzungsrichtung.deEn),
      entsorgen: (s) => s.dispose(),
    );
    ocrHalter = ModellHalter<OcrService>(
      name: 'Texterkennung',
      installiert: OcrService.isAvailable(_modelsDir!),
      laden: () => OcrService.load(_modelsDir!),
      entsorgen: (s) => s.dispose(),
    );
    captioningHalter = ModellHalter<FlorenceCaptioningService>(
      name: 'Bildbeschreibung',
      installiert: FlorenceCaptioningService.isAvailable(_modelsDir!),
      laden: () => FlorenceCaptioningService.load(_modelsDir!),
      entsorgen: (s) => s.dispose(),
    );
    restoreQueue.restoreHalter = ModellHalter<RestoreService>(
      name: 'KI-Restaurierung',
      installiert: RestoreService.isAvailable(_modelsDir!),
      laden: () => RestoreService.load(_modelsDir!),
      entsorgen: (s) => s.dispose(),
    );
  }

  /// Gibt alle aktuellen UND retirierten Halter frei, die gerade nicht in
  /// Benutzung sind (siehe ModellHalter.freigebenWennUnbenutzt) – regelmäßig
  /// per Timer aufgerufen, siehe [initialize].
  Future<void> _sweepIdleModels() async {
    var etwasFreigegeben = false;
    for (final halter in _alleHalter) {
      if (await halter.freigebenWennUnbenutzt()) etwasFreigegeben = true;
    }
    for (final halter in _retiredHalters) {
      if (await halter.freigebenWennUnbenutzt()) etwasFreigegeben = true;
    }
    _retiredHalters.removeWhere((h) => !h.istGeladen && !h.laedtGerade);

    // Eine geschlossene ONNX-Sitzung gibt ihren Speicher an die
    // C-Bibliothek zurück – die behält ihn aber. Gemessen auf einer
    // Linux-Instanz nach längerer Modellarbeit: 2,4 GB belegt, davon
    // 1,5 GB liegengebliebener Heap; ein `malloc_trim(0)` gab davon
    // 692 MB ans System zurück (siehe [SpeicherRueckgabe]).
    //
    // Bewusst nur nach einer tatsächlichen Freigabe und nicht bei jedem
    // Durchlauf: Der Aufruf geht alle Arenen durch, und während eines
    // laufenden Imports gäbe er Seiten zurück, die sofort wieder
    // angefordert werden.
    if (etwasFreigegeben) SpeicherRueckgabe.jetzt();
  }

  /// Wird nach einem Modell-Download/-Löschen in den Einstellungen
  /// aufgerufen (siehe settings_screen.dart) – legt frische Halter an, damit
  /// neu heruntergeladene Dateien als `installiert` erkannt werden.
  Future<void> reloadModels() async {
    await _loadModelsIfPresent();
    notifyListeners();
    unawaited(restoreQueue.resume());
  }

  /// Lädt den GeoNames-Datensatz (falls bereits heruntergeladen) in den
  /// Speicher – das Parsen der ca. 150.000 Städte kostet ein-, zweistellig
  /// viele hundert Millisekunden, läuft deshalb einmalig hier statt bei jeder
  /// einzelnen Umkehr-Geokodierung erneut.
  Future<void> _loadGeoDataIfPresent() async {
    if (!geoDataDownloadService.isInstalled) {
      geocoder = null;
      return;
    }
    try {
      geocoder = await ReverseGeocoder.loadFromFiles(
        citiesFile: geoDataDownloadService.citiesFile,
        admin1File: geoDataDownloadService.admin1File,
        countryFile: geoDataDownloadService.countryFile,
      );
    } catch (e) {
      debugPrint('GeoNames-Datensatz konnte nicht geladen werden: $e');
      geocoder = null;
    }
  }

  /// Wird nach einem Download/Löschen des GeoNames-Datensatzes in den
  /// Einstellungen aufgerufen.
  Future<void> reloadGeoData() async {
    _geoLaeuft = _loadGeoDataIfPresent();
    await _geoLaeuft;
    // Ein frisch eingespielter Datensatz ist der Augenblick, in dem
    // Ereignisorte zum ersten Mal auflösbar werden.
    await trageEreignisorteNach();
    notifyListeners();
  }

  /// Trägt Koordinaten für Lebensereignisse nach, die bisher nur einen
  /// Ortsnamen haben.
  ///
  /// Läuft beim Start und nach einem GeoNames-Download, nicht in der
  /// Migration: Ohne den – optionalen – Datensatz gäbe es nichts
  /// einzutragen, und eine Migration, die auf einen Download wartet,
  /// wäre eine Migration, die manchmal nicht fertig wird.
  ///
  /// Angefasst werden nur Ereignisse **ohne** Koordinate. Wer einen
  /// falsch geratenen Punkt von Hand berichtigt hat, findet ihn beim
  /// nächsten Start unverändert vor.
  Future<void> trageEreignisorteNach() async {
    final geo = geocoder;
    if (geo == null) return;
    final offen = await db.ereignisseOhneKoordinate();
    if (offen.isEmpty) return;

    // Der Schwerpunkt der verorteten Fotos als Anhaltspunkt bei
    // mehrdeutigen Namen: Wer seine Bilder überwiegend in einer Gegend
    // aufgenommen hat, meint mit „Springfield" eher das dortige.
    //
    // Als eine Zeile aus der Datenbank und nicht als 1091 – dieser Weg
    // läuft bei jedem Start, sobald auch nur ein Ereignis einen Ort
    // trägt, den die Ortsliste nicht kennt (der bleibt ohne Koordinate
    // und steht beim nächsten Mal wieder hier). Siehe
    // [AppDatabase.schwerpunktVerorteterFotos] für die Messung.
    final mitte = await db.schwerpunktVerorteterFotos();

    final gefunden = <String, ({double breite, double laenge})>{};
    for (final ereignis in offen) {
      final treffer = geo.sucheOrt(
        ereignis.ort!,
        naheBreite: mitte?.breite,
        naheLaenge: mitte?.laenge,
      );
      if (treffer == null) continue;
      gefunden[ereignis.id] = (breite: treffer.breite, laenge: treffer.laenge);
    }
    // Ein Schreibvorgang für alle, nicht einer je Ereignis.
    if (gefunden.isNotEmpty) await db.setzeEreignisorte(gefunden);
    debugPrint(
        'Ereignisorte nachgetragen: ${gefunden.length} von ${offen.length}');
  }

  // Beide CLIP-Halter prüfen dieselben Dateien – einer genügt als Auskunft.
  bool get clipAvailable => clipBildHalter.installiert;
  bool get faceDetectionAvailable => faceEngineHalter.installiert;
  // Statische Dateiprüfung statt `faceEngine?.canEmbed`: Letzteres brauchte
  // eine dauerhaft geladene Instanz, die es jetzt nicht mehr gibt.
  bool get faceRecognitionAvailable =>
      FaceEngineService.isRecognitionAvailable(_modelsDir!);
  bool get segmentationAvailable => segmentationHalter.installiert;
  bool get captioningAvailable => captioningHalter.installiert;
  bool get uebersetzungEnDeAvailable => uebersetzungEnDeHalter.installiert;

  /// Ob Text erkannt werden kann – über das Betriebssystem (macOS) oder
  /// über das nachgeladene Modell (überall sonst).
  bool get ocrAvailable => Platform.isMacOS || ocrHalter.installiert;
  bool get geoDataAvailable => geocoder != null;

  bool isModelInstalled(ModelCatalogEntry entry) =>
      modelDownloadService.isEntryInstalled(entry);

  /// Importiert eine Liste von Dateipfaden und liefert währenddessen
  /// Fortschritts-Updates. Führt pro Bild zusätzlich Gesichtserkennung
  /// (falls Modell vorhanden), CLIP-Embedding (falls Modell vorhanden) und
  /// den Live-Photo-Abgleich (Foto <-> Video mit gleichem Dateinamen) aus.
  Stream<ImportProgress> importFiles(List<String> filePaths) async* {
    var done = 0;
    yield ImportProgress(0, filePaths.length);
    for (final filePath in filePaths) {
      final result = await importService.importFile(filePath);
      if (result.outcome == ImportOutcome.imported && result.assetId != null) {
        await _postProcessNewAsset(result.assetId!);
      }
      done++;
      yield ImportProgress(
        done,
        filePaths.length,
        currentFile: p.basename(filePath),
        assetId:
            result.outcome == ImportOutcome.imported ? result.assetId : null,
        duplikat: result.outcome == ImportOutcome.duplicateSkipped,
        gescheitert: result.outcome == ImportOutcome.failed,
      );
    }

    // Erst NACH dem Import: die rechenintensiven Auswertungen laufen im
    // Hintergrund nach, statt jeden einzelnen Import auszubremsen. Bewusst
    // nicht abgewartet – der Import gilt als fertig, sobald die Dateien in
    // der Bibliothek sind.
    if (await db.autoAnalyzeAfterImportEnabled()) {
      unawaited(starteHintergrundanalyse());
    }
  }

  /// Datei, die tatsächlich dekodiert werden kann: die konvertierte
  /// Vorschau, falls das Originalformat (HEIC/DNG & Co.) von Flutter bzw.
  /// dem `image`-Paket nicht direkt gelesen werden kann – sonst das
  /// Original selbst.
  File _decodableFile(AssetData asset) =>
      paths.absolute(asset.previewRelativePath ?? asset.relativePath);

  /// Lädt und dekodiert das Bild eines Assets einmalig – wird sowohl für
  /// die Gesichtserkennung als auch für die CLIP-Einbettung wiederverwendet
  /// (siehe [_postProcessNewAsset]), statt dieselbe JPEG/HEIC-Vorschau für
  /// jeden Verarbeitungsschritt erneut von der Platte zu lesen und zu
  /// dekodieren. Gibt `null` zurück, wenn die Datei fehlt oder nicht
  /// dekodierbar ist (z.B. beschädigt).
  Future<img.Image?> _decodeAsset(AssetData asset) async {
    try {
      return await compute(
          decodeImageBytes, await _decodableFile(asset).readAsBytes());
    } catch (_) {
      return null;
    }
  }

  static const _livePhotoImageExts = {'.heic', '.heif', '.jpg', '.jpeg'};
  static const _livePhotoVideoExt = '.mov';

  /// Prüft, ob es zu diesem frisch importierten Asset schon einen
  /// unverknüpften Partner mit demselben Dateinamen (ohne Endung) gibt –
  /// z.B. das HEIC-Standbild zu einem bereits importierten MOV oder
  /// umgekehrt – und verknüpft die beiden als Live Photo.
  Future<void> _tryLinkLivePhoto(AssetData asset) async {
    final ext = p.extension(asset.originalFileName).toLowerCase();
    final isImage = asset.type == 'IMAGE';
    if (isImage && !_livePhotoImageExts.contains(ext)) return;
    if (!isImage && ext != _livePhotoVideoExt) return;

    final stem =
        p.basenameWithoutExtension(asset.originalFileName).toLowerCase();
    final candidates =
        await db.unlinkedAssetsOfType(isImage ? 'VIDEO' : 'IMAGE');
    for (final candidate in candidates) {
      if (candidate.id == asset.id) continue;
      final candidateExt =
          p.extension(candidate.originalFileName).toLowerCase();
      if (isImage && candidateExt != _livePhotoVideoExt) continue;
      if (!isImage && !_livePhotoImageExts.contains(candidateExt)) continue;
      final candidateStem =
          p.basenameWithoutExtension(candidate.originalFileName).toLowerCase();
      if (candidateStem == stem) {
        await db.linkAssets(asset.id, candidate.id);
        return;
      }
    }
  }

  /// Wendet ein evtl. für die erkannte Kamera hinterlegtes Preset an
  /// (Zielalbum, Tags, automatisches Favorisieren) – siehe
  /// CameraPresetsScreen. Für Videos (keine EXIF-Kamera) und Fotos ohne
  /// passendes Preset ein günstiges No-Op (siehe AppDatabase.cameraPresetFor).
  /// Öffentlich (statt privat) nur wegen [visibleForTesting]: ein Test über
  /// den vollen Importpfad bräuchte eine echte EXIF-tragende JPEG-Datei
  /// (siehe camera_metadata_test.dart, das aus demselben Grund
  /// setCameraMetadata statt eines echten Imports nutzt) – hier lässt sich
  /// die Anwendungslogik stattdessen direkt mit einer bereits bekannten
  /// Kamera testen.
  @visibleForTesting
  Future<void> applyCameraPreset(
    String assetId, {
    required String? cameraMake,
    required String? cameraModel,
  }) async {
    final preset = await db.cameraPresetFor(cameraMake, cameraModel);
    if (preset == null) return;
    if (preset.targetAlbumId != null) {
      await db.addAssetsToAlbum(preset.targetAlbumId!, [assetId]);
    }
    if (preset.autoFavorite) {
      await db.setFavorite(assetId, true);
    }
    final tagIds = await db.tagIdsForCameraPreset(preset.id);
    for (final tagId in tagIds) {
      await db.tagAssetById(assetId, tagId);
    }
  }

  /// Wendet passende Automatisierungsregeln an (Zielalbum, Tags, automatisch
  /// favorisieren) – Verallgemeinerung von [applyCameraPreset] auf Orts-/
  /// Datums-/KI-Tag-Bedingungen statt nur Kamera, siehe AutomationRules in
  /// database.dart. Zwei Aufrufstellen, je nachdem, wann die jeweilige
  /// Bedingung überhaupt geprüft werden kann:
  ///
  /// - [latitude]/[longitude]/[fileCreatedAt] liegen schon beim Import vor
  ///   ([_postProcessNewAsset]) – werten `location`-/`dateRange`-Regeln aus.
  /// - [aiTags] liegen erst nach der KI-Tagging-Stufe der Hintergrundanalyse
  ///   vor ([backfillAiTags]) – wertet `aiTag`-Regeln aus.
  ///
  /// Ein Aufruf mit nur einem Teil der Parameter überspringt die jeweils
  /// nicht auswertbaren Regeltypen folgerichtig (kein Fehler) – so ruft
  /// jede Aufrufstelle dieselbe Methode auf, ohne die andere Bedingungsart
  /// zu kennen.
  ///
  /// [rules] erlaubt Stapelverarbeitungen, die Regeln EINMAL pro Lauf statt
  /// pro Foto zu laden (siehe [backfillAiTags]) – dieselbe Überlegung wie
  /// beim dortigen Vokabular-Laden. Ohne den Parameter werden sie pro
  /// Aufruf frisch geholt, was für den Einzelaufruf beim Import richtig ist
  /// (eine zwischenzeitlich geänderte Regel soll sofort greifen).
  @visibleForTesting
  Future<void> applyAutomationRules(
    String assetId, {
    double? latitude,
    double? longitude,
    DateTime? fileCreatedAt,
    List<String>? aiTags,
    List<AutomationRuleData>? rules,
  }) async {
    for (final rule in rules ?? await db.allAutomationRules()) {
      final bool matches;
      switch (rule.triggerType) {
        case 'location':
          matches = latitude != null &&
              longitude != null &&
              rule.regionCenterLat != null &&
              rule.regionCenterLon != null &&
              rule.regionRadiusKm != null &&
              ReverseGeocoder.haversineKm(latitude, longitude,
                      rule.regionCenterLat!, rule.regionCenterLon!) <=
                  rule.regionRadiusKm!;
        case 'dateRange':
          matches = fileCreatedAt != null &&
              rule.dateFrom != null &&
              rule.dateTo != null &&
              !fileCreatedAt.isBefore(rule.dateFrom!) &&
              !fileCreatedAt.isAfter(rule.dateTo!);
        case 'aiTag':
          matches = aiTags != null &&
              rule.aiTagTerm != null &&
              aiTags.contains(rule.aiTagTerm);
        default:
          matches = false;
      }
      if (!matches) continue;

      if (rule.targetAlbumId != null) {
        await db.addAssetsToAlbum(rule.targetAlbumId!, [assetId]);
      }
      if (rule.autoFavorite) {
        await db.setFavorite(assetId, true);
      }
      final tagIds = await db.tagIdsForAutomationRule(rule.id);
      for (final tagId in tagIds) {
        await db.tagAssetById(assetId, tagId);
      }
    }
  }

  // --- Hintergrundanalyse nach dem Import -------------------------------

  /// Beschreibt, was die Hintergrundanalyse gerade tut – für den Hinweis in
  /// [HomeShell].
  AnalyseFortschritt? _analyse;
  AnalyseFortschritt? get analyse => _analyse;
  bool get analyseLaeuft => _analyse != null;
  bool _analyseAbbruch = false;

  /// Arbeitet die rechenintensiven Auswertungen nacheinander ab – jede
  /// überspringt selbst die Fotos, die sie schon hat, und tut nichts, wenn
  /// ihr Modell fehlt. Deshalb ist ein erneuter Aufruf gefahrlos.
  ///
  /// Reihenfolge nach steigendem Aufwand: Zuerst das, was schnell fertig
  /// ist und sofort nutzbar, zuletzt die Bildbeschreibung – die erzeugt
  /// ihren Satz Wort für Wort und ist damit mit Abstand die teuerste Stufe.
  ///
  /// Unschärfe, Gesichter und CLIP brauchen DASSELBE dekodierte Bild und
  /// laufen deshalb als ein gemeinsamer Durchlauf ([_bildinhaltsAnalyse]),
  /// der je Foto nur einmal dekodiert. Vorher ging jede Stufe die
  /// Bibliothek für sich durch und dekodierte erneut – bei gemessenen
  /// ~85 ms je Dekodiervorgang war das der größte vermeidbare Posten
  /// (Audit-Fund).
  ///
  /// Die Bildbeschreibung bleibt bewusst eine eigene, letzte Stufe, obwohl
  /// sie dasselbe Bild bräuchte: Sie ist um ein Vielfaches teurer als die
  /// anderen drei zusammen. Zöge man sie in den gemeinsamen Durchlauf,
  /// zahlte jedes einzelne Foto sofort ihren vollen Preis, und ein Abbruch
  /// nach der halben Zeit ließe die halbe Bibliothek gänzlich unausgewertet
  /// zurück – statt, wie jetzt, vollständig bis auf die Bildbeschreibung.
  /// Die Texterkennung wiederum arbeitet nativ auf der Datei und hat vom
  /// dekodierten Bild ohnehin nichts.
  /// Wie oft der Fortschritt einer Hintergrundstufe gemeldet wird.
  ///
  /// Nicht öfter, weil jede Meldung den ganzen sichtbaren Baum neu aufbaut;
  /// nicht seltener, weil eine Anzeige, die nur alle paar Sekunden springt,
  /// wie ein Stillstand aussieht.
  @visibleForTesting
  static const meldeabstand = Duration(milliseconds: 100);

  Future<void> starteHintergrundanalyse() async {
    if (_analyse != null) return; // läuft bereits

    // Nicht neben eine rechenintensive Aufgabe legen: Die Analyse arbeitet
    // genau deren Stufen ab – zwei Durchgänge gingen dann dieselbe Liste
    // durch, mit zwei Modellsitzungen im Speicher. Die Anfrage geht nicht
    // verloren, sie wird nachgeholt, sobald die Aufgabe durch ist. Ohne
    // dieses Nachholen bliebe ein direkt nach dem Import gestarteter
    // Durchgang bis zum nächsten Programmstart aus, und frisch importierte
    // Fotos wären ohne Gesichter und ohne Suche.
    if (laufendeSchwerarbeit.isNotEmpty) {
      _analyseZurueckgestellt = true;
      return;
    }
    _analyseZurueckgestellt = false;
    _analyseAbbruch = false;

    final stufen =
        <({Analysestufe name, Stream<ImportProgress> Function() lauf})>[
      (name: Analysestufe.bildanalyse, lauf: () => _bildinhaltsAnalyse()),
      (name: Analysestufe.texterkennung, lauf: () => backfillOcrText()),
      // Kein eigener CLIP-Schritt mehr – die Embeddings entstehen bereits in
      // der Bildanalyse. [backfillClipEmbeddings] bleibt für den manuellen
      // Aufruf in den Werkzeugen erhalten.
      (
        name: Analysestufe.schlagwoerter,
        lauf: () => backfillAiTags(onlyUntagged: true)
      ),
      (name: Analysestufe.bildbeschreibung, lauf: () => backfillCaptions()),
      // Zuletzt, und das ist keine Nebensache: Die Gesichter entstehen
      // erst in der Bildanalyse ganz oben. Wer hier frueher fragt, fragt
      // nach Gesichtern, die es noch nicht gibt.
      (
        name: Analysestufe.wiedererkennung,
        lauf: () => backfillWiedererkennung()
      ),
    ];

    try {
      for (var i = 0; i < stufen.length; i++) {
        if (_analyseAbbruch) break;
        final stufe = stufen[i];
        // Jede Stufe für sich absichern: Wirft eine (z.B. weil ein einzelnes
        // Foto beschädigt ist oder ein Modell fehlschlägt), sollen die
        // FOLGENDEN Stufen trotzdem noch laufen. Vorher umschloss ein
        // einziges try/catch die ganze Schleife – ein Fehler in Stufe 1 ließ
        // die Stufen 2-6 stillschweigend ausfallen (Audit-Fund).
        try {
          // **Der Stand wird immer gesetzt, gemeldet wird er zehnmal die
          // Sekunde.** Jede Meldung baut den gesamten Baum unter dem
          // `Consumer<LibraryState>` in `main.dart` neu auf – und das ist
          // alles, was auf dem Bildschirm steht. Über 8000 Aufnahmen und
          // vier Stufen wären das 32.000 Anlässe dazu, für eine Anzeige,
          // die kein Bildschirm öfter als sechzigmal die Sekunde zeigt.
          // Wer den Stand liest, ohne auf eine Meldung zu warten (das
          // Aufgabenblatt beim Öffnen), sieht trotzdem den aktuellen.
          var zuletztGemeldet = DateTime.now();
          await for (final p in stufe.lauf()) {
            if (_analyseAbbruch) break;
            _analyse = AnalyseFortschritt(
              stufe: stufe.name,
              stufeNummer: i + 1,
              stufenGesamt: stufen.length,
              erledigt: p.done,
              gesamt: p.total,
            );
            final jetzt = DateTime.now();
            if (jetzt.difference(zuletztGemeldet) >= meldeabstand) {
              zuletztGemeldet = jetzt;
              notifyListeners();
            }
          }
          // Der letzte Stand einer Stufe muss ankommen – sonst bliebe die
          // Anzeige bei „7994 von 8096" stehen.
          notifyListeners();
        } catch (e) {
          debugPrint('Analysestufe "${stufe.name.name}" fehlgeschlagen, '
              'weiter mit der nächsten: $e');
        }
      }
    } finally {
      _analyse = null;
      _analyseAbbruch = false;
      notifyListeners();
      // Schwere Aufgaben warten, solange die Analyse arbeitet – jetzt
      // dürfen sie.
      _versucheStarten();
    }
  }

  /// Gesetzt, wenn eine Analyse angefragt wurde, während eine
  /// rechenintensive Aufgabe lief.
  bool _analyseZurueckgestellt = false;

  /// Ob ein zurückgestellter Analysedurchgang aussteht – für die Anzeige.
  bool get analyseZurueckgestellt => _analyseZurueckgestellt;

  /// Holt eine zurückgestellte Analyse nach, sobald die letzte
  /// rechenintensive Aufgabe durch ist.
  void _holeZurueckgestellteAnalyseNach() {
    if (!_analyseZurueckgestellt) return;
    if (laufendeSchwerarbeit.isNotEmpty) return;
    _analyseZurueckgestellt = false;
    unawaited(starteHintergrundanalyse());
  }

  /// Bricht nach der laufenden Datei ab – kein harter Abbruch mitten in
  /// einer Modell-Inferenz.
  void brichHintergrundanalyseAb() {
    if (_analyse == null) return;
    _analyseAbbruch = true;
  }

  // --- Aufgaben, die wirklich im Hintergrund laufen ----------------------

  /// Die laufenden und die eben beendeten Nachholvorgänge, nach ihrer
  /// Kennung.
  ///
  /// Warum hier und nicht im Bildschirm: Die Aufgabenübersicht öffnete
  /// bisher je Aufgabe ein Fortschrittsfenster. Das liess sich weder
  /// verkleinern noch beiseitelegen – wer die Bibliothek während der Arbeit
  /// ansehen wollte, musste den Vorgang abbrechen. Ein Lauf an dieser
  /// Stelle überlebt jeden Bildschirmwechsel.
  final Map<String, Hintergrundlauf> _laeufe = {};

  /// Der Lauf zu einer Kennung, oder `null`, wenn dort gerade nichts steht.
  Hintergrundlauf? lauf(String schluessel) => _laeufe[schluessel];

  /// Alle Läufe, die gerade tatsächlich arbeiten.
  Iterable<Hintergrundlauf> get laufendeAufgaben =>
      _laeufe.values.where((l) => l.laeuft);

  /// Alle Läufe, die eingereiht sind und auf einen Platz warten.
  Iterable<Hintergrundlauf> get wartendeAufgaben =>
      _laeufe.values.where((l) => l.wartet);

  /// Alles, was noch offen ist – laufend oder wartend.
  Iterable<Hintergrundlauf> get offeneAufgaben =>
      _laeufe.values.where((l) => l.offen);

  /// Wie viele rechenintensive Aufgaben nebeneinander laufen dürfen.
  ///
  /// Aus der Datenbank geladen (siehe `AppSettings.maxGleichzeitig`), bis
  /// dahin gilt die Vorgabe eins. Ein Feld und keine Abfrage bei jedem
  /// Start: Die Schlange wird bei jedem Fortschrittsbescheid angesehen.
  int _maxGleichzeitig = 1;

  int get maxGleichzeitig => _maxGleichzeitig;

  /// Setzt die Obergrenze und lässt sofort nachrücken, was dadurch darf.
  Future<void> setzeMaxGleichzeitig(int anzahl) async {
    final wert = anzahl < 1 ? 1 : anzahl;
    if (wert == _maxGleichzeitig) return;
    _maxGleichzeitig = wert;
    await db.setzeMaxGleichzeitigeAufgaben(wert);
    notifyListeners();
    _versucheStarten();
  }

  /// Ob überhaupt noch etwas arbeitet – einschliesslich der
  /// Hintergrundanalyse, die ihren eigenen Zustand führt. Grundlage für die
  /// Rückfrage beim Beenden (siehe BeendenWaechter).
  bool get etwasLaeuft => analyseLaeuft || offeneAufgaben.isNotEmpty;

  /// Die laufenden Aufgaben, die als teure Auswertung gelten – Modell im
  /// Speicher oder dieselbe Arbeit wie eine Stufe der Hintergrundanalyse.
  Iterable<Hintergrundlauf> get laufendeSchwerarbeit =>
      laufendeAufgaben.where((l) => l.rechenintensiv);

  /// Warum eine Aufgabe gerade nicht eingereiht werden kann – `null`
  /// heisst: sie kann.
  ///
  /// **Es ist nur noch ein Grund übrig.** Bis Fassung 2.2.3 wies diese
  /// Prüfung auch dann ab, wenn eine andere schwere Aufgabe lief oder die
  /// Hintergrundanalyse arbeitete. Der Anlass dafür war richtig und gilt
  /// weiter: Vier Klicks genügten, um Gesichter, Bildbeschreibung,
  /// Einbettung und Übersetzung gleichzeitig zu starten – deren Modelle
  /// liegen dann zusammen im Speicher (allein CLIP-Bild 335 MB und die
  /// Bildbeschreibung 235 MB, gemessen), und dieselben Fotos werden
  /// vierfach dekodiert.
  ///
  /// Die **Antwort** darauf war falsch. Abweisen heisst: Der Mensch muss
  /// sich merken, was er noch wollte, und das Ende der ersten Aufgabe
  /// abpassen. Seither wird eingereiht und der Reihe nach abgearbeitet
  /// (siehe [_versucheStarten]); wie viele nebeneinander dürfen, steht in
  /// [maxGleichzeitig].
  ///
  /// Dieselbe Arbeit zweimal in die Schlange zu stellen bleibt sinnlos.
  ///
  /// Ohne die frühere Angabe `rechenintensiv`: Sie entschied, ob abgewiesen
  /// wird, und tut das nicht mehr. Ein Parameter, den niemand liest, ist
  /// eine Behauptung über die Regel, die nicht mehr stimmt.
  Startabweisung? pruefeStart(String schluessel) =>
      (_laeufe[schluessel]?.offen ?? false)
          ? Startabweisung.laeuftBereits
          : null;

  /// Ob [lauf] jetzt losdarf.
  ///
  /// Aufgaben ohne Modell (Orte einlesen, XMP schreiben, Live-Photo-Paare)
  /// laufen immer sofort – sie kosten nichts, was sich gegenseitig im Weg
  /// stünde, und würden in einer Schlange nur warten, ohne dass jemand
  /// etwas davon hätte.
  bool _darfLosgehen(Hintergrundlauf lauf) {
    if (!lauf.rechenintensiv) return true;
    // Die Analyse arbeitet genau diese Stufen ab – zwei Durchgänge gingen
    // sonst dieselbe Liste durch, mit zwei Modellsitzungen im Speicher.
    if (analyseLaeuft) return false;
    return laufendeSchwerarbeit.length < _maxGleichzeitig;
  }

  /// Lässt aus der Schlange nachrücken, was darf.
  ///
  /// Wird an jeder Stelle gerufen, an der ein Platz frei werden kann: nach
  /// dem Einreihen, nach dem Ende eines Laufs, nach dem Ende der
  /// Hintergrundanalyse und nach einer Änderung von [maxGleichzeitig].
  ///
  /// In der Einfügereihenfolge, denn `Map` behält sie in Dart bei – wer
  /// zuerst angestossen hat, läuft zuerst. Eine eigene Liste daneben wäre
  /// eine zweite Quelle derselben Wahrheit.
  void _versucheStarten() {
    var etwasGestartet = false;
    for (final lauf in _laeufe.values.where((l) => l.wartet).toList()) {
      if (!_darfLosgehen(lauf)) continue;
      lauf.gestartet = true;
      etwasGestartet = true;
      unawaited(_fuehreAus(lauf));
    }
    if (etwasGestartet) notifyListeners();
  }

  /// Reiht die Aufgabe [schluessel] ein. Sie läuft los, sobald ein Platz
  /// frei ist – bei Aufgaben ohne Modell also sofort.
  ///
  /// Gibt den Grund zurück, wenn nicht eingereiht wurde (siehe
  /// [pruefeStart]). Kein `Future`: Das Einreihen selbst ist unmittelbar,
  /// und wer auf das Ende warten will, nimmt [Hintergrundlauf.abschluss].
  /// Vorher gab es hier ein `Future`, das erst mit dem **Ende des Laufs**
  /// erfüllt wurde – dieselbe Rückgabe für zwei ganz verschiedene Dinge,
  /// und jeder Aufrufer musste wissen, dass er es nicht abwarten darf.
  Startabweisung? reiheAufgabeEin({
    required String schluessel,
    required String titel,
    required String leermeldung,
    required Stream<ImportProgress> Function() strom,
    String Function(int getan, int gesamt)? bilanztext,
    bool rechenintensiv = false,
  }) {
    final abweisung = pruefeStart(schluessel);
    if (abweisung != null) return abweisung;

    _laeufe[schluessel] = Hintergrundlauf(
      schluessel: schluessel,
      titel: titel,
      leermeldung: leermeldung,
      bilanztext: bilanztext,
      rechenintensiv: rechenintensiv,
      strom: strom,
    );
    notifyListeners();
    _versucheStarten();
    return null;
  }

  /// Arbeitet einen Lauf ab, der eben seinen Platz bekommen hat.
  Future<void> _fuehreAus(Hintergrundlauf lauf) async {
    // Auf [Hintergrundlauf.abschluss] warten statt auf ein `await for`:
    // Der Lauf muss von aussen abbrechbar sein, und ein gekündigtes
    // Abonnement meldet kein `onDone` mehr – ein `await for` bliebe dann
    // für immer stehen.
    // Gedrosselt melden. Ein Lauf über 8000 Fotos meldet 8000 Fortschritte,
    // und an diesem ChangeNotifier hängt über den Consumer in main.dart der
    // gesamte Widget-Baum – jede Meldung baut also die ganze App neu auf.
    // Fünf Aktualisierungen je Sekunde sind für eine Zahl, die ein Mensch
    // liest, reichlich.
    var letzteMeldung = DateTime.fromMillisecondsSinceEpoch(0);
    const drosselMs = 200;

    try {
      lauf.abo = lauf.strom().listen(
        (p) {
          lauf.erledigt = p.done;
          lauf.gesamt = p.total;
          lauf.datei = p.currentFile;
          // Die zuletzt gemeldete Zahl gilt: Ein Lauf schickt sie am
          // Schluss, und ein spaeteres `null` soll sie nicht loeschen.
          if (p.getan != null) lauf.getan = p.getan;
          final jetzt = DateTime.now();
          // Der letzte Schritt kommt immer durch, sonst bliebe die Anzeige
          // kurz vor der Gesamtzahl stehen.
          if (p.done >= p.total ||
              jetzt.difference(letzteMeldung).inMilliseconds >= drosselMs) {
            letzteMeldung = jetzt;
            notifyListeners();
          }
        },
        onError: (Object e) {
          lauf.fehler = e;
          lauf.schliesseAb();
        },
        onDone: lauf.schliesseAb,
        cancelOnError: true,
      );
      await lauf.abschluss;
    } catch (e) {
      lauf.fehler = e;
    } finally {
      lauf.beendet = true;
      lauf.abo = null;
      notifyListeners();
      // Der frei gewordene Platz gehört dem nächsten in der Schlange.
      _versucheStarten();
      // Eine wegen dieser Aufgabe zurückgestellte Analyse jetzt nachholen.
      _holeZurueckgestellteAnalyseNach();
    }
  }

  /// Bricht den Lauf zu [schluessel] ab.
  ///
  /// Das Kündigen des Abonnements hält den Generator bei seinem nächsten
  /// `yield` an – also nach der gerade bearbeiteten Datei, nicht mitten in
  /// einer Modell-Inferenz. Die `finally`-Blöcke der Nachholvorgänge laufen
  /// dabei durch und geben ihre geliehenen Modelle zurück.
  void brichAufgabeAb(String schluessel) {
    final lauf = _laeufe[schluessel];
    if (lauf == null || lauf.beendet) return;
    lauf.abgebrochen = true;
    // Ein wartender Lauf hat noch kein Abonnement – ihn wegzunehmen ist
    // nichts weiter als ein Streichen aus der Schlange. Er verschwindet
    // ganz statt als beendeter Eintrag stehenzubleiben: Es gab nichts zu
    // sehen, also gibt es auch kein Ergebnis zu zeigen.
    if (lauf.wartet) {
      _laeufe.remove(schluessel);
      lauf.beendet = true;
      lauf.schliesseAb();
      notifyListeners();
      return;
    }
    final abo = lauf.abo;
    lauf.abo = null;
    // Erst melden, wenn das Kündigen wirklich durch ist – und nicht,
    // sobald es angestossen wurde.
    //
    // `cancel()` gibt ein Future zurück, das erst erfüllt ist, wenn der
    // Generator seinen `finally`-Block durchlaufen hat, und genau dort
    // gibt er sein geliehenes Modell zurück. Vorher stand hier
    // `unawaited(abo?.cancel())`, unmittelbar gefolgt von
    // `beendet = true` und `_versucheStarten()`: Der nächste in der
    // Schlange lief damit los, während der Abgebrochene noch mitten in
    // seiner letzten Inferenz steckte. Bei der Vorgabe von einer
    // gleichzeitigen Aufgabe lagen so zwei Modelle nebeneinander im
    // Speicher (Bildbeschreibung 235 MB und CLIP-Bild 335 MB, gemessen)
    // – genau der Zustand, den die Grenze verhindern soll.
    //
    // Das Ende selbst setzt weiterhin [_fuehreAus] in seinem `finally`,
    // das auf [Hintergrundlauf.abschluss] wartet. Bis dahin zählt der
    // Lauf als laufend, und das stimmt auch: Er arbeitet seine letzte
    // Datei noch ab.
    notifyListeners();
    unawaited(
        (abo?.cancel() ?? Future<void>.value()).whenComplete(lauf.schliesseAb));
  }

  /// Räumt einen beendeten Lauf weg, damit die Karte wieder ihre Zahlen
  /// zeigt. Ein noch laufender bleibt stehen.
  void verwerfeLauf(String schluessel) {
    if (_laeufe[schluessel]?.offen ?? false) return;
    if (_laeufe.remove(schluessel) != null) notifyListeners();
  }

  /// Nachbereitung direkt beim Import – bewusst NUR ressourcenschonende
  /// Schritte: reine Datenbankarbeit und ein Nachschlagen im bereits
  /// geladenen Ortsverzeichnis. Kein Dekodieren, keine Modell-Inferenz.
  ///
  /// Alles Rechenintensive (Gesichter, Unschärfe, Texterkennung, CLIP,
  /// Bildbeschreibung) läuft NACH dem Import als Hintergrundaufgabe, siehe
  /// [starteHintergrundanalyse]. Vorher lief es hier inline und machte den
  /// Import bei mehreren tausend Fotos unzumutbar langsam: fünf schwere
  /// Durchläufe je Foto, nacheinander.
  Future<void> _postProcessNewAsset(String assetId) async {
    final asset = await db.assetById(assetId);
    if (asset == null) return;

    await _tryLinkLivePhoto(asset);
    await applyCameraPreset(asset.id,
        cameraMake: asset.cameraMake, cameraModel: asset.cameraModel);
    await applyAutomationRules(
      asset.id,
      latitude: asset.latitude,
      longitude: asset.longitude,
      fileCreatedAt: asset.fileCreatedAt,
    );

    if (asset.type != 'IMAGE') return;

    // Ortsauflösung bleibt hier: reines Nachschlagen im bereits im
    // Speicher liegenden GeoNames-Verzeichnis, kein Bild wird angefasst.
    //
    // Erst abwarten, ob das Verzeichnis noch gelesen wird: Seit es
    // nebenher lädt (siehe [geoBereit]), wäre ein Import in der ersten
    // halben Sekunde nach dem Start sonst still ohne Ortsnamen geblieben.
    await geoBereit;
    if (geocoder != null && asset.latitude != null && asset.longitude != null) {
      final result = geocoder!.lookup(asset.latitude!, asset.longitude!);
      if (result != null) {
        await db.setLocationNames(asset.id,
            country: result.country, state: result.state, city: result.city);
      }
    }
  }

  /// Setzt den Ort von Hand – und trägt die Ortsnamen gleich mit nach.
  ///
  /// **Beides gehört zusammen.** [AppDatabase.setLocation] leert die alten
  /// Namen, weil sie zur alten Koordinate gehören; ohne diesen zweiten
  /// Schritt stünde das Foto bis zum nächsten Lauf der Hintergrundaufgabe
  /// ohne Ortsangabe da, obwohl gerade eine gesetzt wurde.
  ///
  /// Mit `null` für beide Koordinaten wird der Ort entfernt – dann bleiben
  /// auch die Namen leer, und das ist die Wahrheit: Es ist keiner bekannt.
  ///
  /// Ohne eingespielten GeoNames-Datensatz bleibt es bei der Koordinate.
  Future<void> setzeOrtVonHand(
      List<String> assetIds, double? breite, double? laenge) async {
    await db.setLocationBulk(assetIds, breite, laenge);
    if (breite == null || laenge == null) return;
    // **Kein `await geoBereit` hier**, anders als beim Import. Der wartet
    // darauf, weil er in der ersten halben Sekunde nach dem Start laufen
    // kann; ein Handgriff am Bildschirm kann das nicht. Und der Preis wäre
    // hoch: `geoBereit` ist ein Future aus dem Zeitgeber-Bereich des
    // Starts, und darauf zu warten hängt in einem Widget-Prüfstand
    // wortlos – dieselbe Falle wie beim echten Lesen von der Platte.
    // Ist das Verzeichnis wirklich noch nicht da, trägt der Nachtrag die
    // Namen später ein.
    final treffer = geocoder?.lookup(breite, laenge);
    if (treffer == null) return;
    // **Eine Anweisung, keine Schleife.** Alle bekommen denselben Ort –
    // es gibt also nichts, was je Aufnahme verschieden wäre. Vorher stand
    // hier ein UPDATE je Foto; bei 500 Fotos gemessen 163 ms gegen 2 ms.
    // Wichtiger als die Zeit: Eine Schleife, die in der Mitte scheitert,
    // lässt die eine Hälfte am neuen Ort und die andere am alten stehen.
    await db.setLocationNamesBulk(assetIds,
        country: treffer.country, state: treffer.state, city: treffer.city);
  }

  /// Führt die Gesichtserkennung für ein Asset aus, dessen Bild bereits
  /// dekodiert vorliegt (siehe [_postProcessNewAsset], wo dasselbe Bild auch
  /// für die CLIP-Einbettung dekodiert wird), und markiert es als gescannt.
  ///
  /// [decoded] darf `null` sein (z.B. wenn die Datei beschädigt ist) – dann
  /// werden schlicht keine Gesichter gefunden, das Asset aber trotzdem als
  /// gescannt markiert (kein endloses Wiederholen bei kaputten Dateien).
  ///
  /// [deleteExistingUnassigned] löscht vorher alle noch nicht einer Person
  /// zugeordneten Gesichter dieses Assets (relevant beim "alle Fotos erneut
  /// scannen", damit sich Erkennungen nicht endlos aufsummieren) – bereits
  /// manuell zugeordnete Gesichter bleiben davon unberührt.
  Future<void> _scanFacesForDecodedAsset(
    AssetData asset,
    img.Image? decoded, {
    required FaceEngineService engine,
    EyeStateService? eyeState,
    required bool deleteExistingUnassigned,
    bool nurNeueStellen = false,
  }) async {
    // **Ohne Bild wird gar nichts angefasst.** Nicht die vorhandenen
    // Gesichter gelöscht, und vor allem nicht der Vermerk „gescannt"
    // gesetzt. Bis Fassung 2.5 stand dieser Vermerk am Ende des Rumpfes,
    // ausserhalb der `decoded != null`-Prüfung: Liess sich ein Foto nicht
    // dekodieren, galt es danach trotzdem als gescannt – und der Modus
    // „nur Fehlende" ging für immer daran vorbei, auch bei der
    // Hintergrundanalyse. Ein Lauf, der an beschädigten Dateien
    // vorbeirauscht und „fertig" meldet, ist genau die Art Ergebnis, der
    // man nicht ansieht, dass sie keines ist.
    //
    // (An der Prüfbibliothek hatte der Fehler noch nichts angerichtet:
    // Kein Foto war als gescannt vermerkt, ohne dass Unschärfe und
    // Einbettung – die dasselbe dekodierte Bild brauchen – dastanden.)
    //
    // Ein früher Ausstieg und keine Bedingung um den Vermerk herum, damit
    // die Regel baulich gilt und nicht an einer Stelle hängt, die beim
    // nächsten Umbau mitwandern muss.
    if (decoded == null) return;

    if (deleteExistingUnassigned) {
      // Die Ausschnitte der gelöschten Zeilen müssen mit weg. Sonst
      // hinterlässt jedes „alle Fotos erneut scannen" den kompletten alten
      // Bestand als Dateien ohne Datenbankzeile – siehe
      // [AppDatabase.deleteUnassignedFacesForAsset].
      for (final pfad in await db.deleteUnassignedFacesForAsset(asset.id)) {
        await paths.deletePermanently(pfad);
      }
    }

    // Was beiseitegelegt wurde, darf ein erneuter Scan nicht als neue
    // Erkennung zurückbringen. Das Löschen oben verschont diese Gesichter
    // zwar, aber die Erkennung findet dieselbe Stelle wieder – ohne diesen
    // Abgleich stünde neben jedem ignorierten Plakatgesicht nach dem
    // nächsten Scan ein frisches, unbenanntes.
    //
    // [nurNeueStellen] weitet das auf ALLE vorhandenen Gesichter aus – der
    // Fall der weiteren Standbilder eines Videos: Wer zwei Sekunden lang
    // stillsteht, ist auf jedem Standbild an derselben Stelle und soll
    // trotzdem einmal in der Bibliothek stehen. Wer sich bewegt hat,
    // bekommt eine zweite Zeile, und das ist richtig so.
    final ignorierteBoxen = [
      for (final f in await db.facesForAsset(asset.id))
        if (nurNeueStellen || f.isIgnored)
          DetectedFace(f.boxX, f.boxY, f.boxW, f.boxH, 1.0),
    ];

    try {
      final boxes = await engine.detectFaces(decoded);
      for (final box in boxes) {
        // Dieselbe Schwelle wie die Unterdrückung mehrfacher Erkennungen
        // derselben Stelle (FaceEngineService.detectFaces) – es ist
        // dieselbe Frage: Ist das nochmal dieses Gesicht?
        if (ignorierteBoxen.any((alt) => FacePostprocess.iou(alt, box) > 0.3)) {
          continue;
        }
        final faceId = const Uuid().v4();
        final cropFile = paths.absolute(paths.faceRelativePath(faceId));
        final croppedThumb = FaceEngineService.cropFaceImage(decoded, box);
        await FaceEngineService.saveFaceCrop(croppedThumb, cropFile);

        Float32List? embedding;
        if (engine.canEmbed) {
          embedding = await engine.embedFace(decoded, box);
        }

        // Nutzt dieselben Landmarks weiter, die YuNet für diese Box schon
        // geliefert hat (siehe FaceEngineService.detectFaces) – keine
        // erneute Erkennung nötig, nur ein kleiner Zusatz-Klassifikator
        // auf zwei winzigen Augen-Ausschnitten.
        double? eyeOpenScore;
        if (eyeState != null) {
          try {
            eyeOpenScore = await eyeState.eyeOpenScore(decoded, box);
          } catch (e) {
            debugPrint(
                'Augen-Zustand-Erkennung fehlgeschlagen für ${asset.originalFileName}: $e');
          }
        }

        await db.insertFace(FacesCompanion.insert(
          id: faceId,
          assetId: asset.id,
          boxX: box.x,
          boxY: box.y,
          boxW: box.width,
          boxH: box.height,
          cropRelativePath: Value(paths.faceRelativePath(faceId)),
          embedding: embedding != null
              ? Value(blobFromEmbeddingFloats(embedding))
              : const Value.absent(),
          eyeOpenScore:
              eyeOpenScore != null ? Value(eyeOpenScore) : const Value.absent(),
          // Auf dem Ausschnitt, der ohnehin schon im Speicher liegt –
          // kein zweiter Dekodiervorgang, keine zweite Skalierung.
          schaerfe: Value(gesichtsschaerfe(croppedThumb)),
        ));
      }
      await db.markFacesScanned([asset.id]);
    } catch (e) {
      debugPrint(
          'Gesichtserkennung fehlgeschlagen für ${asset.originalFileName}: $e');
    }
  }

  /// Dekodiert das Bild eines Assets und führt die Gesichtserkennung aus –
  /// für Aufrufer, die (anders als [_postProcessNewAsset]) noch kein
  /// dekodiertes Bild vorliegen haben (manueller Rescan über die Werkzeuge).
  Future<void> _scanFacesForAsset(
    AssetData asset, {
    required FaceEngineService engine,
    EyeStateService? eyeState,
    required bool deleteExistingUnassigned,
  }) async {
    final decoded = await _decodeAsset(asset);
    await _scanFacesForDecodedAsset(
      asset,
      decoded,
      engine: engine,
      eyeState: eyeState,
      deleteExistingUnassigned: deleteExistingUnassigned,
    );
  }

  /// Manueller (Re-)Scan der Gesichtserkennung, z.B. nachdem das YuNet-Modell
  /// erst nachträglich installiert wurde oder ein Erkennungs-Bug (wie die
  /// BGR/RGB-Verwechslung) behoben wurde.
  ///
  /// [onlyNewPhotos] = true: nur Fotos, die noch nie gescannt wurden.
  /// [onlyNewPhotos] = false: ALLE Fotos erneut scannen (dauert entsprechend
  /// länger bei großen Bibliotheken).
  Stream<ImportProgress> rescanFaces({required bool onlyNewPhotos}) async* {
    // Erst die Arbeit ermitteln, dann die Modelle holen – siehe
    // [_bildinhaltsAnalyse].
    final assets = await db.assetsForFaceScan(onlyNew: onlyNewPhotos);
    if (assets.isEmpty) {
      yield ImportProgress(0, 0);
      return;
    }
    final engine = await faceEngineHalter.leihen();
    if (engine == null) {
      yield ImportProgress(0, 0);
      return;
    }
    var failed = false;
    try {
      final eyeState = await eyeStateHalter.leihen();
      try {
        var done = 0;
        yield ImportProgress(0, assets.length);
        for (final asset in assets) {
          try {
            await _scanFacesForAsset(
              asset,
              engine: engine,
              eyeState: eyeState,
              deleteExistingUnassigned: !onlyNewPhotos,
            );
          } catch (e) {
            failed = true;
            debugPrint('Gesichtserkennung fehlgeschlagen für '
                '${asset.originalFileName}: $e');
          }
          done++;
          yield ImportProgress(done, assets.length,
              currentFile: asset.originalFileName);
        }
      } finally {
        if (eyeState != null) eyeStateHalter.zurueckgeben();
      }
    } finally {
      faceEngineHalter.zurueckgeben();
    }
    if (!onlyNewPhotos && !failed) {
      await _markModelPipelineCurrent('faces');
    }
  }

  /// Manuelles (Re-)Erzeugen von Thumbnails/Vorschauen, z.B. nachdem die
  /// native Bildkonvertierung für HEIC/DNG oder die Video-Thumbnail-
  /// Erzeugung erst nachträglich eingerichtet wurde. [onlyMissing] = true
  /// verarbeitet nur Assets ohne Thumbnail.
  Stream<ImportProgress> regenerateThumbnails(
      {required bool onlyMissing}) async* {
    final assets = await db.assetsForThumbnailRegen(onlyMissing: onlyMissing);
    var done = 0;
    yield ImportProgress(0, assets.length);
    for (final asset in assets) {
      try {
        final result = asset.type == 'IMAGE'
            ? await importService.generateThumbnailAndPreview(
                paths.absolute(asset.relativePath),
                asset.id,
                p.extension(asset.originalFileName),
              )
            : await importService.generateVideoThumbnail(
                paths.absolute(asset.relativePath),
                asset.id,
              );
        if (result.hasThumbnail || result.durationSeconds != null) {
          await db.updateThumbnailInfo(
            asset.id,
            thumbnailRelativePath: result.thumbnailRelativePath,
            previewRelativePath: result.previewRelativePath,
            widthPx: result.width,
            heightPx: result.height,
            durationSeconds: result.durationSeconds,
          );
        }
      } catch (e) {
        debugPrint(
            'Vorschau-Erzeugung fehlgeschlagen für ${asset.originalFileName}: $e');
      }
      done++;
      yield ImportProgress(done, assets.length,
          currentFile: asset.originalFileName);
    }
  }

  /// Rendert alle bereits entwickelten Fotos (siehe DevelopScreen) mit
  /// ihren gespeicherten Einstellungen neu – z.B. sinnvoll nach einer
  /// Änderung an der nativen Render-Logik selbst. Die Einstellungen bleiben
  /// dabei unverändert, nur das gerenderte Bild wird neu erzeugt.
  Stream<ImportProgress> redevelopAll() async* {
    final entries = await db.assetsWithDevelopSettings();
    var done = 0;
    yield ImportProgress(0, entries.length);
    for (final (asset, settings) in entries) {
      try {
        final adjustments = DevelopAdjustments(
          exposure: settings.exposure,
          temperature: settings.temperature,
          tint: settings.tint,
          contrast: settings.contrast,
          shadows: settings.shadows,
          highlights: settings.highlights,
          sharpness: settings.sharpness,
          noiseReduction: settings.noiseReduction,
          lensCorrectionEnabled: settings.lensCorrectionEnabled,
        );
        final masks = await db.masksForAsset(asset.id);
        final bytes = await NativeImageConverter.developImage(
          paths.absolute(asset.relativePath),
          adjustments: adjustments,
          masks: [
            for (final mask in masks)
              MaskAdjustmentLayer(
                maskFilePath: paths.absolute(mask.maskRelativePath).path,
                adjustments: DevelopAdjustments(
                  exposure: mask.exposure,
                  temperature: mask.temperature,
                  tint: mask.tint,
                  contrast: mask.contrast,
                  shadows: mask.shadows,
                  highlights: mask.highlights,
                  sharpness: mask.sharpness,
                  noiseReduction: mask.noiseReduction,
                ),
              ),
          ],
          maxDimension: 4096,
          quality: 0.92,
        );
        if (bytes != null) {
          final developedRelativePath = paths.developedRelativePath(asset.id);
          final targetFile = paths.absolute(developedRelativePath);
          await targetFile.parent.create(recursive: true);
          await targetFile.writeAsBytes(bytes);
          await db.saveDevelopResult(
            asset.id,
            settings: DevelopSettingsCompanion.insert(
              assetId: asset.id,
              exposure: Value(settings.exposure),
              temperature: Value(settings.temperature),
              tint: Value(settings.tint),
              contrast: Value(settings.contrast),
              shadows: Value(settings.shadows),
              highlights: Value(settings.highlights),
              sharpness: Value(settings.sharpness),
              noiseReduction: Value(settings.noiseReduction),
              lensCorrectionEnabled: Value(settings.lensCorrectionEnabled),
              updatedAt: DateTime.now(),
            ),
            developedRelativePath: developedRelativePath,
          );
        }
      } catch (e) {
        debugPrint(
            'Neu-Rendern fehlgeschlagen für ${asset.originalFileName}: $e');
      }
      done++;
      yield ImportProgress(done, entries.length,
          currentFile: asset.originalFileName);
    }
  }

  /// Prüft die komplette Bibliothek erneut auf Live-Photo-Paare – für
  /// Fotos/Videos, die bereits vor Einführung dieser Funktion importiert
  /// wurden.
  Stream<ImportProgress> relinkLivePhotos() async* {
    final images = await db.unlinkedAssetsOfType('IMAGE');
    var done = 0;
    yield ImportProgress(0, images.length);
    for (final asset in images) {
      await _tryLinkLivePhoto(asset);
      done++;
      yield ImportProgress(done, images.length,
          currentFile: asset.originalFileName);
    }
  }

  /// Setzt die Dateiart auf das, was die Bytes hergeben.
  ///
  /// **Der Anlass.** In der Prüfbibliothek sind 31 von 440 als Video
  /// geführten Aufnahmen in Wahrheit JPEG oder HEIC – Standbilder, die
  /// unter einem `.mov`-Namen ankamen. Bis zur Umstellung entschied
  /// ausschliesslich die Endung, und als Video geführt fielen sie aus
  /// jeder Auswertung heraus: keine Beschreibung, keine Schlagwörter,
  /// keine Gesichter, kein Ort. Ihre Miniatur fehlte ebenfalls — der
  /// Videowandler bekam ein Standbild und lieferte nichts (gemessen: 33
  /// der 440 hatten keine).
  ///
  /// Die Datei bleibt liegen, wo sie liegt, und behält ihren Namen. Nur
  /// die Art wird berichtigt und alles Abgeleitete verworfen; Miniatur,
  /// Vorschau, Ort, Datum und Auswertung holen danach die gewohnten
  /// Aufgaben nach — sie sehen die Aufnahme jetzt zum ersten Mal.
  Stream<ImportProgress> repariereDateiarten() async* {
    final verdaechtig = await db.alsVideoGefuehrte();
    var done = 0;
    var berichtigt = 0;
    yield ImportProgress(0, verdaechtig.length);
    for (final asset in verdaechtig) {
      try {
        final datei = paths.absolute(asset.relativePath);
        if (await datei.exists()) {
          final kennung = await ImportService.inhaltskennung(datei, null);
          if (kennung != null) {
            await db.setzeDateiart(asset.id, 'IMAGE',
                dateiformat: kennung.substring(1));
            berichtigt++;
          }
        }
      } catch (e) {
        debugPrint('Dateiart für ${asset.originalFileName} nicht geprüft: $e');
      }
      done++;
      yield ImportProgress(done, verdaechtig.length,
          currentFile: asset.originalFileName);
    }
    debugPrint('Dateiarten berichtigt: $berichtigt');
  }

  /// Liest GPS-Orte nachträglich aus Fotos ein, die vor Einführung dieser
  /// Funktion importiert wurden (siehe Werkzeuge → Orte). Fotos ohne
  /// EXIF-GPS-Daten bleiben unverändert – nur ein Fund führt zu einem
  /// DB-Update.
  Stream<ImportProgress> backfillLocations({bool alle = false}) async* {
    final assets = await db.assetsForLocationBackfill(alle: alle);
    var done = 0;
    yield ImportProgress(0, assets.length);

    // Der Vermerk „nachgesehen" blockweise, aus demselben Grund wie bei
    // den Ortsnamen: Das Lesen der Datei ist der teure Teil, aber
    // tausende Einzelschreibvorgänge daneben wären es auch. Blöcke und
    // nicht ein einziger Schreibvorgang am Ende, damit ein Abbruch nach
    // der halben Zeit die halbe Arbeit behält.
    const blockGroesse = 200;
    var block = <String>[];
    Future<void> blockSchreiben() async {
      if (block.isEmpty) return;
      final zuSchreiben = block;
      block = [];
      await db.markGpsGeprueft(zuSchreiben);
    }

    try {
      for (final asset in assets) {
        final gps = await importService
            .readGpsLocation(paths.absolute(asset.relativePath));
        if (gps != null) {
          await db.setLocation(asset.id, gps.latitude, gps.longitude);
        }
        block.add(asset.id);
        if (block.length >= blockGroesse) await blockSchreiben();
        done++;
        yield ImportProgress(done, assets.length,
            currentFile: asset.originalFileName);
      }
    } finally {
      // Auch bei Abbruch: Was angesehen wurde, ist angesehen. Ein
      // gekündigtes Abonnement hält den Generator beim nächsten `yield`
      // an und durchläuft diesen Block.
      await blockSchreiben();
    }
  }

  /// Sieht in jeder Datei nach, ob sie ein Aufnahmedatum trägt – und
  /// vermerkt bei denen, die keines tragen, dass ihr Datum **geraten** ist
  /// (siehe [Assets.datumGeschaetzt]).
  ///
  /// **Warum ein Lauf über die Dateien und nicht eine Regel über die
  /// Datenbank.** Es wäre eine Zeile SQL, alles zu markieren, was auf
  /// einer vollen Stunde liegt – an der echten Bibliothek träfe das 1097
  /// Aufnahmen und damit fast genau die richtigen. Aber eben nur fast:
  /// Ein Foto, das wirklich um Punkt achtzehn Uhr entstand, bekäme eine
  /// Marke, die eine Falschaussage wäre. Und eine Marke, die selbst
  /// geraten ist, taugt nicht als Auskunft darüber, was geraten ist.
  ///
  /// Der Lauf ist einmalig: Was angesehen wurde, bleibt angesehen
  /// ([AppDatabase.markDatumGeprueft]). `alle: true` sieht auch dort noch
  /// einmal nach – der Weg für Dateien, die ausserhalb der App
  /// nachträglich ein Datum bekommen haben.
  Stream<ImportProgress> backfillDatumsherkunft({bool alle = false}) async* {
    final assets = await db.assetsFuerDatumsherkunft(alle: alle);
    var done = 0;
    var geraten = 0;
    var unlesbar = 0;
    var mitZone = 0;
    yield ImportProgress(0, assets.length);

    // Blockweise aus demselben Grund wie beim Ortsnachtrag: Das Lesen der
    // Datei ist der teure Teil, aber tausende Einzelschreibvorgänge
    // daneben wären es auch. Und ein Abbruch nach der halben Zeit behält
    // die halbe Arbeit.
    const blockGroesse = 200;
    var block = <String>[];
    var ohneDatum = <String>[];
    var versatz = <String, int>{};
    Future<void> blockSchreiben() async {
      if (block.isEmpty) return;
      final zuSchreiben = block;
      final markieren = ohneDatum;
      final zonen = versatz;
      block = [];
      ohneDatum = [];
      versatz = {};
      await db.markDatumGeprueft(zuSchreiben,
          geschaetzt: markieren, versatz: zonen);
    }

    try {
      for (final asset in assets) {
        final datei = paths.absolute(asset.relativePath);
        // Eine Datei, die nicht da ist, sagt nichts – und „nicht da"
        // heisst nicht „ohne Datum". Sie bleibt ungeprüft, damit ein
        // späterer Lauf sie wieder aufgreift.
        if (await datei.exists()) {
          try {
            final befund = await importService.pruefeAufnahmedatum(datei);
            // Ein Fehlschlag des Lesers ist kein Befund. Beim ersten Lauf
            // über die echte Bibliothek meldete der Nachtrag alle 909 CR3
            // als „ohne Datum" – sie tragen alle eines, nur konnte es
            // niemand lesen. Die bleiben ungeprüft und kommen im nächsten
            // Lauf wieder dran.
            if (befund.lesbar) {
              if (befund.zeitpunkt == null) {
                ohneDatum.add(asset.id);
                geraten++;
              }
              // Die Zeitzone kommt aus demselben Tagsatz – die Datei ist
              // ohnehin offen. Ein eigener Lauf dafuer hiesse,
              // achttausend Dateien ein zweites Mal zu lesen.
              if (befund.versatzMinuten case final v?) {
                versatz[asset.id] = v;
                mitZone++;
              }
              block.add(asset.id);
            } else {
              unlesbar++;
            }
          } catch (e) {
            debugPrint('Datum für ${asset.originalFileName} nicht lesbar: $e');
          }
        }
        if (block.length >= blockGroesse) await blockSchreiben();
        done++;
        yield ImportProgress(done, assets.length,
            currentFile: asset.originalFileName);
      }
    } finally {
      await blockSchreiben();
    }
    debugPrint('Datumsherkunft: $geraten von ${assets.length} geraten, '
        '$unlesbar nicht lesbar, $mitZone mit Zeitzone');
  }

  /// Wertet **weitere Standbilder** eines Videos aus – bisher war ein
  /// Video ein einziges Bild.
  ///
  /// **Was daran fehlte.** Seit der 6. Vergleichsauflage haben 428 von 429
  /// Videos eine Einbettung für die Suche und Schlagwörter. Alles davon
  /// stammt aus dem einen Standbild, das seit dem Import auf der Platte
  /// liegt. Bei einem Live-Photo-Fetzen von zwei Sekunden ist das das
  /// ganze Video; bei neun Minuten – so lang ist das längste in der
  /// echten Bibliothek – ist es eine Stichprobe von 0,2 Promille.
  ///
  /// ```
  /// 429 Videos, 186 Minuten
  ///   unter 10 s     208   ein Bild reicht
  ///   ab 10 s        219   ein Bild reicht nicht
  /// ```
  ///
  /// Die Bilder werden **nicht aufgehoben**. Sie entstehen, gehen durch
  /// die Modelle und werden verworfen; was bleibt, sind die Einbettungen,
  /// die Schlagwörter und die Gesichtsausschnitte, die die
  /// Gesichtserkennung ohnehin selbst schreibt. Fünf Bilder je Video auf
  /// der Platte wären an dieser Bibliothek rund 340 MB für nichts.
  ///
  /// Die zusätzlichen Einbettungen gehen in eine **eigene** Tabelle: Die
  /// Duplikatsuche und die Serienerkennung fragen „welche Aufnahme sieht
  /// wem ähnlich" und fänden bei fünf Zeilen je Video fünfmal dasselbe
  /// Video (siehe [Videoeinbettungen]).
  /// Sucht zu jedem noch namenlosen Gesicht die Person, die es sein
  /// koennte – und **schlaegt sie nur vor**.
  ///
  /// **Warum es diesen Lauf braucht.** Die Rechnung dafuer gibt es seit
  /// langem ([personenvorschlag]), aufgerufen wurde sie an genau drei
  /// Stellen: Vollbild, Info-Blatt, Gesichter-Durchsicht. Alle drei
  /// setzen voraus, dass jemand ein Gesicht **anschaut**. Nach einem
  /// Import lagen die neuen Gesichter deshalb einfach da. An der echten
  /// Bibliothek endete das damit, dass 14.065 Gesichter von Hand
  /// beiseitegelegt wurden – die Warteschlange war nicht abgearbeitet,
  /// sondern weggeraeumt.
  ///
  /// **Und warum nur vorschlagen.** Ein falscher Vorschlag, den jemand
  /// wegklickt, kostet Zeit; einer, den jemand uebersieht und bestaetigt,
  /// kostet eine falsche Zuordnung – und die faellt spaeter niemandem
  /// mehr auf. Zugeordnet wird deshalb erst nach Zustimmung.
  ///
  /// Gerechnet wird gegen die Kerne der benannten Personen, mit der
  /// **persoenlichen** Schwelle jeder Person: Darin steckt, was aus
  /// frueheren Zustimmungen und Ablehnungen gelernt wurde.
  Stream<ImportProgress> backfillWiedererkennung(
      {bool alle = false, bool beiseite = false}) async* {
    final gesichter =
        await db.gesichterFuerWiedererkennung(alle: alle, beiseite: beiseite);
    if (gesichter.isEmpty) {
      yield ImportProgress(0, 0);
      return;
    }

    // Die Kerne einmal fuer den ganzen Lauf. Sie je Gesicht neu zu
    // bilden hiesse, 2366 Einbettungen zehntausendfach zu mitteln.
    final roh = await db.einbettungenZugeordneterGesichter();
    final leute = {for (final p in await db.select(db.people).get()) p.id: p};
    final kerne = personenkerne([
      for (final e in roh)
        if (leute.containsKey(e.personId))
          (personId: e.personId, vektor: floatsFromEmbeddingBlob(e.vektor)),
    ]);
    if (kerne.isEmpty) {
      // Ohne eine einzige benannte Person gibt es nichts zu vergleichen.
      // Die Marke trotzdem zu setzen waere falsch: Sobald die erste
      // Person benannt ist, gehoeren diese Gesichter wieder in den Lauf.
      yield ImportProgress(0, 0);
      return;
    }

    var done = 0;
    var gefunden = 0;
    yield ImportProgress(0, gesichter.length);
    final ergebnisse = <({String faceId, String? personId, double? wert})>[];
    for (final gesicht in gesichter) {
      final einbettung = gesicht.embedding;
      if (einbettung != null) {
        final treffer = besterTreffer(
          floatsFromEmbeddingBlob(einbettung),
          kerne,
          schwelleFuer: (id) {
            final person = leute[id];
            return person == null
                ? faceSimilarityThreshold
                : schwelleFuerPerson(person);
          },
        );
        if (treffer != null) gefunden++;
        ergebnisse.add((
          faceId: gesicht.id,
          personId: treffer?.personId,
          wert: treffer?.aehnlichkeit,
        ));
      }
      done++;
      // Blockweise sichern statt erst am Ende: Wer den Lauf nach der
      // Haelfte abbricht, soll die Haelfte behalten – und ein Abbruch
      // geschieht hier ueber das Abbestellen des Stroms, mitten in der
      // Schleife.
      if (done % 200 == 0) {
        await db.merkeVorschlaege(ergebnisse);
        ergebnisse.clear();
        yield ImportProgress(done, gesichter.length, getan: gefunden);
      }
    }
    await db.merkeVorschlaege(ergebnisse);
    yield ImportProgress(done, gesichter.length, getan: gefunden);
  }

  Stream<ImportProgress> backfillVideobilder({bool alle = false}) async* {
    final videos = await db.assetsFuerVideobilder(alle: alle);
    if (videos.isEmpty) {
      yield ImportProgress(0, 0);
      return;
    }
    // Erst die Arbeit ermitteln, dann die Modelle holen – siehe
    // [_bildinhaltsAnalyse].
    final clipBild = await clipBildHalter.leihen();
    final clipText = await clipTextHalter.leihen();
    try {
      final gesichter = await faceEngineHalter.leihen();
      try {
        final augenzustand =
            gesichter != null ? await eyeStateHalter.leihen() : null;
        try {
          final vokabular = await db.aiTagVocabularyTerms();
          var done = 0;
          var bilder = 0;
          yield ImportProgress(0, videos.length);
          final ohneArbeit = <String>[];

          for (final video in videos) {
            final stellen = videostandbildstellen(video.durationSeconds);
            if (stellen.isEmpty) {
              // Zu kurz – und das ist ein Ergebnis, kein offener Posten.
              ohneArbeit.add(video.id);
            } else {
              try {
                final neue = <({double stelle, Uint8List vector})>[];
                for (final stelle in stellen) {
                  final bild =
                      await NativeImageConverter.generateVideoThumbnail(
                    paths.absolute(video.relativePath),
                    maxDimension: videoStandbildKante,
                    anteil: stelle,
                  );
                  if (bild == null) continue;
                  final dekodiert =
                      await compute(img.decodeJpg, bild.jpegBytes);
                  if (dekodiert == null) continue;
                  bilder++;

                  if (clipBild != null) {
                    final vektor = await clipBild.embedImage(dekodiert);
                    neue.add((
                      stelle: stelle,
                      vector: blobFromEmbeddingFloats(vektor)
                    ));
                    if (clipText != null) {
                      for (final tag in await aiTaggingService.suggestTags(
                          clipText, vektor, vokabular,
                          insEnglische: insEnglische)) {
                        await db.tagAsset(video.id, tag, quelle: Tagquelle.ki);
                      }
                    }
                  }
                  if (gesichter != null) {
                    // `nurNeueStellen`: Wer im Video stillsteht, ist auf
                    // jedem Standbild an derselben Stelle und soll
                    // trotzdem einmal in der Bibliothek stehen.
                    await _scanFacesForDecodedAsset(
                      video,
                      dekodiert,
                      engine: gesichter,
                      eyeState: augenzustand,
                      deleteExistingUnassigned: false,
                      nurNeueStellen: true,
                    );
                  }
                }
                // Auch mit leerer Liste vermerken: Ein Video, aus dem sich
                // kein Standbild greifen lässt, ist angesehen worden.
                await db.setzeVideoeinbettungen(video.id, neue);
              } catch (e) {
                debugPrint(
                    'Standbilder fehlgeschlagen für ${video.originalFileName}: $e');
              }
            }
            done++;
            yield ImportProgress(done, videos.length,
                currentFile: video.originalFileName);
          }
          if (ohneArbeit.isNotEmpty) {
            await db.markVideobilderGeprueft(ohneArbeit);
          }
          debugPrint('Videostandbilder: $bilder aus ${videos.length} Videos');
        } finally {
          if (augenzustand != null) eyeStateHalter.zurueckgeben();
        }
      } finally {
        if (gesichter != null) faceEngineHalter.zurueckgeben();
      }
    } finally {
      if (clipBild != null) clipBildHalter.zurueckgeben();
      if (clipText != null) clipTextHalter.zurueckgeben();
    }
  }

  /// Löst für Fotos mit bekanntem GPS-Ort, aber noch ohne Land/Bundesland/
  /// Stadt, die lokale/offline Umkehr-Geokodierung aus (siehe Werkzeuge →
  /// Ort) – z.B. für Fotos, die vor dem Herunterladen des GeoNames-
  /// Datensatzes importiert wurden. Braucht keinen Dateizugriff: Breiten-
  /// und Längengrad liegen bereits in der Datenbank.
  Stream<ImportProgress> backfillLocationNames() async* {
    await geoBereit;
    final engine = geocoder;
    if (engine == null) {
      yield ImportProgress(0, 0);
      return;
    }
    final assets = await db.assetsForLocationNameBackfill();
    var done = 0;
    yield ImportProgress(0, assets.length);

    // Blockweise schreiben statt je Foto einzeln.
    //
    // Diese Stufe ist die einzige der Nachträge, bei der die eigentliche
    // Arbeit im Hauptspeicher stattfindet – kein Dateizugriff, kein Modell,
    // nur ein Nachschlagen im Ortsraster. Damit wird das Schreiben zum
    // Kostentreiber: Für 5000 Fotos gemessen 2131 ms einzeln gegen 139 ms in
    // Blöcken, bei 359 ms für die Auflösungen selbst.
    //
    // Blöcke statt einer einzigen grossen Transaktion, damit der
    // Fortschrittsbalken weiterläuft und ein Abbruch nicht alles verwirft.
    const blockGroesse = 200;
    var block = <({String id, GeoLookupResult treffer})>[];

    Future<void> blockSchreiben() async {
      if (block.isEmpty) return;
      final zuSchreiben = block;
      block = [];
      await db.transaction(() async {
        for (final e in zuSchreiben) {
          await db.setLocationNames(e.id,
              country: e.treffer.country,
              state: e.treffer.state,
              city: e.treffer.city);
        }
      });
    }

    for (final asset in assets) {
      final result = engine.lookup(asset.latitude!, asset.longitude!);
      if (result != null) block.add((id: asset.id, treffer: result));
      if (block.length >= blockGroesse) await blockSchreiben();
      done++;
      yield ImportProgress(done, assets.length,
          currentFile: asset.originalFileName);
    }
    await blockSchreiben();
  }

  /// Liest Kamera-/Objektiv-Angaben nachträglich aus Fotos ein, die vor
  /// Einführung dieser Funktion importiert wurden (siehe Werkzeuge →
  /// Kamera). Fotos ohne entsprechende EXIF-Daten bleiben unverändert.
  Stream<ImportProgress> backfillCameraMetadata() async* {
    final assets = await db.assetsForCameraMetadataBackfill();
    var done = 0;
    yield ImportProgress(0, assets.length);
    for (final asset in assets) {
      final info = await importService
          .readCameraInfo(paths.absolute(asset.relativePath));
      if (!info.isEmpty) {
        await db.setCameraMetadata(asset.id, info);
        await applyCameraPreset(asset.id,
            cameraMake: info.make, cameraModel: info.model);
      }
      done++;
      yield ImportProgress(done, assets.length,
          currentFile: asset.originalFileName);
    }
  }

  /// Trägt Aufnahmedatum, Kamera und Objektiv für RAW-Fotos nach, deren
  /// Metadaten beim Import nicht gelesen werden konnten – und verschiebt
  /// die Datei, wenn sich dadurch der Monat ändert.
  ///
  /// Anlass: `package:exif` liest nur TIFF/JPEG. Bei CR3 (ISO-BMFF, wie
  /// MP4) kamen NULL Tags heraus, und der Import fiel für das Datum auf
  /// den Zeitstempel der Quelldatei zurück. Das ist der teurere Schaden:
  /// In einer Bibliothek mit 909 CR3-Dateien lagen 891 Daten falsch, 517
  /// davon im falschen Monat und 236 im falschen Jahr.
  ///
  /// Reihenfolge beim Verschieben: erst die Datei umhängen, dann die
  /// Datenbank. Scheitert die Datenbank, wird die Datei zurückgelegt.
  /// Andersherum zeigte die Datenbank auf einen Pfad, den es noch nicht
  /// gibt.
  Stream<ImportProgress> korrigiereAufnahmedaten() async* {
    // RAW und Videos: Bei beiden liest `package:exif` nichts, und der
    // Import fiel auf den Zeitstempel der Datei zurück. Bei JPEG gab es
    // diesen Weg nie. Die Bedingung steht seit Fassung 59 in der Abfrage
    // selbst – sonst kämen achttausend Zeilen herüber, von denen hier
    // siebentausend wieder wegfielen, und die Zahl auf der Karte liesse
    // sich nur ausrechnen, indem man dieselbe Arbeit ein zweites Mal tut.
    final kandidaten = await db.assetsFuerDatumskorrektur();
    var done = 0;
    yield ImportProgress(0, kandidaten.length);
    for (final asset in kandidaten) {
      final datei = paths.absolute(asset.relativePath);
      if (await datei.exists()) {
        final daten = await importService.readAufnahmedaten(datei);
        if (!daten.kamera.isEmpty) {
          await db.setCameraMetadata(asset.id, daten.kamera);
          await applyCameraPreset(asset.id,
              cameraMake: daten.kamera.make, cameraModel: daten.kamera.model);
        }
        final neu = daten.zeitpunkt;
        // Eine Minute Spielraum: Sekundenbruchteile und Rundungen der
        // verschiedenen Wege sollen keine Verschiebung auslösen.
        if (neu != null &&
            neu.difference(asset.fileCreatedAt).abs() >
                const Duration(minutes: 1)) {
          await _datumUmschreiben(asset, neu);
        }
      }
      done++;
      yield ImportProgress(done, kandidaten.length,
          currentFile: asset.originalFileName);
    }
  }

  /// Holt Fotos aus dem Papierkorb zurück – und stellt dabei ihr
  /// Aufnahmedatum richtig, falls es beim Import nicht gelesen werden
  /// konnte.
  ///
  /// Warum hier und nicht in [AppDatabase.restoreFromTrash]: Das Datum
  /// steht in der Datei, und die Datenbankschicht kennt keine Dateien.
  ///
  /// Warum überhaupt: [korrigiereAufnahmedaten] überspringt den
  /// Papierkorb – dort stört ein falsches Datum niemanden, weil die Fotos
  /// weder in der Zeitleiste noch im Kalender auftauchen. Beim
  /// Zurückholen ändert sich das schlagartig: Ohne diesen Schritt käme
  /// ein CR3-Foto mit dem Zeitstempel seiner Datei zurück und landete
  /// wieder im falschen Monat. Gemessen an einer echten Bibliothek waren
  /// das 36 von 36 der noch falsch datierten Fotos.
  ///
  /// Nur RAW und Videos: Bei JPEG kam das Datum immer aus den EXIF-Daten,
  /// dort gibt es nichts nachzuholen.
  Future<void> ausPapierkorbHolen(List<String> assetIds) async {
    // Erst zurückholen. Scheitert das Nachlesen danach, ist das Foto
    // trotzdem wieder da – nur mit dem Datum, das es vorher hatte.
    await db.restoreFromTrash(assetIds);

    for (final id in assetIds) {
      final asset = await db.assetById(id);
      if (asset == null) continue;
      final endung = p.extension(asset.relativePath).toLowerCase();
      if (asset.type != 'VIDEO' && !rawImageExtensions.contains(endung)) {
        continue;
      }

      final datei = paths.absolute(asset.relativePath);
      if (!await datei.exists()) continue;
      final daten = await importService.readAufnahmedaten(datei);

      if (!daten.kamera.isEmpty && (asset.cameraModel ?? '').isEmpty) {
        await db.setCameraMetadata(id, daten.kamera);
        await applyCameraPreset(id,
            cameraMake: daten.kamera.make, cameraModel: daten.kamera.model);
      }
      final neu = daten.zeitpunkt;
      if (neu != null &&
          neu.difference(asset.fileCreatedAt).abs() >
              const Duration(minutes: 1)) {
        await _datumUmschreiben(asset, neu);
      }
    }
  }

  /// Legt Aufnahmen in den Ordner, der zu ihrem Datum gehört.
  ///
  /// Räumt auf, was entstand, solange ein von Hand gesetztes Datum die
  /// Datei liegen liess: An einer echten Bibliothek 1102 von 7988
  /// Aufnahmen, deren Ordner etwas anderes behauptet als ihre Zeile.
  ///
  /// **Das Datum wird dabei nicht angefasst.** Es gilt als richtig – es
  /// ist ja das, was jemand von Hand gesetzt hat. Falsch ist nur der Ort
  /// auf der Platte. Wer das Datum aus der Datei neu lesen will, nimmt die
  /// Datumskorrektur; die beiden Aufgaben tun ausdrücklich Verschiedenes.
  ///
  /// Ein Fehlschlag beim Verschieben hält den Lauf nicht auf: Die übrigen
  /// tausend sind davon unabhängig, und [_datumUmschreiben] lässt eine
  /// unverschiebbare Datei dort, wo sie liegt.
  Stream<ImportProgress> ordneAblageNeu() async* {
    final betroffen = await db.assetsFuerAblageordnung();
    // Die liegengebliebenen Beipackzettel gehören zur selben Aufgabe: Sie
    // an ihren Platz zu legen ist das, was „Ablage ordnen" heisst. Sie
    // stehen VOR dem Lauf fest, damit die Gesamtzahl von Anfang an stimmt
    // – ein Fortschritt, der unterwegs wächst, ist keiner.
    final zettel = await verirrteBeipackzettel();
    final gesamt = betroffen.length + zettel.length;
    var done = 0;
    var verschoben = 0;
    yield ImportProgress(0, gesamt);
    for (final asset in betroffen) {
      try {
        await _datumUmschreiben(asset, asset.fileCreatedAt);
        verschoben++;
      } catch (e) {
        debugPrint('Ablage: ${asset.originalFileName} nicht umgelegt: $e');
      }
      done++;
      yield ImportProgress(done, gesamt, currentFile: asset.originalFileName);
    }
    var zettelVerschoben = 0;
    for (final z in zettel) {
      // Der Zettel eines soeben umgezogenen Fotos ist oben schon
      // mitgekommen; dann ist hier nichts mehr zu tun.
      final quelle = paths.absolute(z.von);
      if (await quelle.exists()) {
        try {
          await paths.absolute(z.nach).parent.create(recursive: true);
          await quelle.rename(paths.absolute(z.nach).path);
          zettelVerschoben++;
        } catch (e) {
          debugPrint('Beipackzettel ${z.von} nicht umgelegt: $e');
        }
      }
      done++;
      yield ImportProgress(done, gesamt, currentFile: p.basename(z.nach));
    }
    // Die Schlussmeldung: Was wirklich umgelegt wurde, Fotos und
    // Beipackzettel zusammen. Sie stand bisher nur im Entwicklerprotokoll
    // – aus dem Erstlauf-Bericht (A08): „Aufgabe lief ohne Fehlermeldung
    // durch, genannt wurde nichts."
    if (gesamt > 0) {
      yield ImportProgress(gesamt, gesamt,
          getan: verschoben + zettelVerschoben);
    }
    debugPrint('Ablage neu geordnet: $verschoben von ${betroffen.length}, '
        'Beipackzettel $zettelVerschoben von ${zettel.length}');
    notifyListeners();
  }

  /// Was die Aufgabe „Ablage nach Datum ordnen" zu tun hat: falsch
  /// einsortierte Aufnahmen **und** liegengebliebene Beipackzettel. Beides
  /// in einer Zahl, weil ein Lauf beides erledigt.
  Future<int> zaehleAblageordnung() async =>
      await db.countAblageordnung() + (await verirrteBeipackzettel()).length;

  /// Setzt das Aufnahmedatum von Hand – und legt die Datei dorthin, wo sie
  /// nach dem neuen Datum hingehört.
  ///
  /// **Warum das nicht mehr direkt in die Datenbank geht.** Die beiden
  /// Wege, auf denen man ein Datum von Hand setzt (Info-Ansicht und
  /// Sammelbearbeitung), schrieben bis Fassung 2.5 nur die Spalte. Die
  /// Datei blieb in `originals/2007/01/` liegen, während die Datenbank
  /// 2013 behauptete. An der echten Bibliothek gemessen: bei **1102 von
  /// 7988 Aufnahmen** widersprachen sich Ablagepfad und Datum, davon 948
  /// aus einer einzigen Sammelbearbeitung.
  ///
  /// Sichtbar wird das nirgends in der App – sie geht immer über den in
  /// der Datenbank vermerkten Pfad. Es fällt dem auf die Füsse, der die
  /// Bibliothek im Dateimanager ansieht, ein Backup einspielt oder die
  /// Ordner als das liest, was sie zu sein behaupten. Ein Ablageschema,
  /// dem man nicht trauen kann, ist keines.
  Future<void> setzeAufnahmedatumVonHand(
      List<String> assetIds, DateTime neu) async {
    for (final id in assetIds) {
      final asset = await db.assetById(id);
      if (asset == null) continue;
      await _datumUmschreiben(asset, neu);
    }
    notifyListeners();
  }

  Future<void> _datumUmschreiben(AssetData asset, DateTime neu) async {
    final alterPfad = asset.relativePath;
    final neuerPfad = paths.originalRelativePath(
        neu, asset.id, p.extension(alterPfad).toLowerCase());
    if (neuerPfad == alterPfad) {
      await db.setAufnahmezeitpunkt(asset.id, neu);
      return;
    }
    final quelle = paths.absolute(alterPfad);
    final ziel = paths.absolute(neuerPfad);
    try {
      await ziel.parent.create(recursive: true);
      await quelle.rename(ziel.path);
      // Der Beipackzettel liegt als einzige abgeleitete Datei NEBEN dem
      // Original – alle anderen (Miniatur, Vorschau, Entwickeltes,
      // Gesichtsausschnitte) stehen in eigenen Ordnern unter ihrer
      // Kennung und sind von einem Umzug gar nicht betroffen. Bleibt er
      // liegen, ist er ein Metadatensatz ohne Foto: Beschreibung,
      // Schlagwörter, Personennamen und Ort im Klartext an einer Stelle,
      // die niemand mehr aufräumt – und die beim Sperren nicht
      // mitverschlüsselt wird, weil [dateienVon] den NEUEN Pfad nennt.
      await _beipackzettelMitnehmen(alterPfad, neuerPfad);
    } on FileSystemException catch (e) {
      debugPrint('Ablage: ${asset.id} nicht verschiebbar: $e');
      // Das Datum trotzdem richtigstellen – ein falsch einsortierter
      // Ordner ist das kleinere Übel gegenüber einem falschen Datum in
      // Zeitleiste, Kalender und Suche.
      await db.setAufnahmezeitpunkt(asset.id, neu);
      return;
    }
    try {
      await db.setAufnahmezeitpunkt(asset.id, neu, neuerPfad: neuerPfad);
    } catch (e) {
      // Zurücklegen, sonst zeigt die Datenbank auf eine Datei, die dort
      // nicht mehr liegt.
      try {
        await ziel.rename(quelle.path);
      } catch (_) {}
      rethrow;
    }
  }

  /// Legt den `.xmp`-Beipackzettel neben die Datei, die gerade umgezogen
  /// ist. Fehlt er, ist nichts zu tun – nicht jede Aufnahme hat einen.
  ///
  /// Scheitert bewusst still: Ein liegengebliebener Beipackzettel ist
  /// ärgerlich, aber er darf keinen Umzug rückgängig machen, der sonst
  /// geklappt hat. Er wird beim nächsten Lauf von
  /// [verirrteBeipackzettel] ohnehin eingesammelt.
  Future<void> _beipackzettelMitnehmen(
      String alterPfad, String neuerPfad) async {
    final alt = paths.absolute(paths.xmpSidecarPath(alterPfad));
    if (!await alt.exists()) return;
    try {
      await alt.rename(paths.absolute(paths.xmpSidecarPath(neuerPfad)).path);
    } on FileSystemException catch (e) {
      debugPrint('Beipackzettel blieb liegen: ${alt.path}: $e');
    }
  }

  /// **Beipackzettel, die ihr Foto verloren haben.**
  ///
  /// Bis Fassung 2.6 nahm ein Umzug den `.xmp` nicht mit. An der echten
  /// Bibliothek blieben dadurch **1244 von 7370** an ihrem alten Platz
  /// zurück – 949 davon in `originals/00-1/11`, dem Ordner, den ein
  /// EXIF-Datum „0000:00:00" einmal erzeugte (`DateTime(0,0,0)` ist der
  /// 30. November des Jahres −1; der Jahresschutz in [exifDatumAusText]
  /// unterbindet das heute, die Dateien von damals blieben).
  ///
  /// Ein solcher Zettel ist kein toter Platzhalter: Er trägt Beschreibung,
  /// Schlagwörter, Bewertung, Personennamen und Ort im Klartext. Er wird
  /// beim Sperren nicht mitverschlüsselt, weil [dateienVon] den neuen Pfad
  /// nennt, und beim endgültigen Löschen nicht entfernt, aus demselben
  /// Grund.
  ///
  /// Erkannt wird er am Dateinamen: Der ist die Kennung der Aufnahme.
  /// Gibt es die Aufnahme, und liegt ihr Zettel nicht dort, wo sie liegt,
  /// gehört er dorthin verschoben. Gibt es die Aufnahme nicht mehr, bleibt
  /// er stehen – Löschen ist hier nicht die Aufgabe.
  ///
  /// Der Durchgang durch `originals/` kostet an 15 358 Dateien 9 ms warm
  /// und 70 ms kalt; billig genug, um daraus einen Zähler zu speisen.
  Future<List<({String von, String nach})>> verirrteBeipackzettel() async {
    final wurzel = Directory(p.join(paths.root.path, 'originals'));
    if (!wurzel.existsSync()) return const [];
    final pfadJeKennung = {
      for (final a in await db.allAssetsForIntegrityCheck())
        a.id: a.relativePath
    };
    final gefunden = <({String von, String nach})>[];
    await for (final eintrag
        in wurzel.list(recursive: true, followLinks: false)) {
      if (eintrag is! File) continue;
      final rel = p.relative(eintrag.path, from: paths.root.path);
      if (p.extension(rel).toLowerCase() != '.xmp') continue;
      final aufnahme = pfadJeKennung[p.basenameWithoutExtension(rel)];
      if (aufnahme == null) continue;
      final soll = paths.xmpSidecarPath(aufnahme);
      if (soll != rel) gefunden.add((von: rel, nach: soll));
    }
    return gefunden;
  }

  /// Erkennt Text nachträglich für Fotos, die vor Einführung der OCR-Suche
  /// importiert wurden (siehe [_postProcessNewAsset], wo dasselbe seit
  /// diesem Feature automatisch bei jedem Import läuft).
  // -----------------------------------------------------------------------
  // Überwachter Ordner
  // -----------------------------------------------------------------------

  Timer? _ordnerTimer;
  bool _ordnerLaeuft = false;

  /// Wie oft nachgesehen wird. Bewusst Abtastung statt echter
  /// Dateisystem-Ereignisse: Letzteres bräuchte eine weitere Abhängigkeit,
  /// und ein Ordner, in den eine Kamera entlädt, verträgt ein paar Minuten
  /// Verzögerung ohne Weiteres.
  static const _ordnerIntervall = Duration(minutes: 5);

  /// Sieht im überwachten Ordner nach neuen Dateien und importiert sie.
  ///
  /// Gefahrlos wiederholbar: Der Import erkennt bereits vorhandene Dateien
  /// an ihrer Prüfsumme und legt sie kein zweites Mal an. Deshalb genügt
  /// hier schlichtes Nachsehen – es braucht keine Liste dessen, was schon
  /// gesehen wurde, die bei jedem Fehlerfall aus dem Tritt geriete.
  ///
  /// Die Dateien bleiben, wo sie sind. Sie zu verschieben oder zu löschen
  /// wäre ein Eingriff in fremde Ordner, den ein Programm ungefragt nicht
  /// tun sollte – auch wenn andere Programme das so halten.
  Future<int> pruefeUeberwachtenOrdner() async {
    if (_ordnerLaeuft) return 0;
    final eintrag = await db.ueberwachterOrdner();
    if (eintrag == null) return 0;

    _ordnerLaeuft = true;
    try {
      // Unter macOS erlischt der Zugriff auf einen fremden Ordner bei jedem
      // Programmstart und muss aus dem gespeicherten Merkmal wiederhergestellt
      // werden (siehe FolderAccess).
      final zugriff = FolderAccess.forCurrentPlatform();
      var pfad =
          await zugriff.resolveRoot(path: eintrag.pfad, token: eintrag.token);
      // Ohne Merkmal liefert die macOS-Umsetzung grundsätzlich null – das
      // ist für Ordner ausserhalb des Programmbereichs richtig, schliesst
      // aber auch solche aus, die ohnehin gelesen werden dürfen (innerhalb
      // des eigenen Bereichs, und unter Linux/Windows generell). Deshalb
      // ein Rückfall auf den blossen Pfad: Fehlt der Zugriff tatsächlich,
      // scheitert das Auflisten gleich darauf und wird unten aufgefangen.
      pfad ??= Directory(eintrag.pfad).existsSync() ? eintrag.pfad : null;
      if (pfad == null) {
        debugPrint('Überwachter Ordner nicht erreichbar: ${eintrag.pfad}');
        return 0;
      }

      final dateien = await importService.collectSupportedFilesInFolder(pfad);
      if (dateien.isEmpty) return 0;

      var neue = 0;
      await for (final p in importFiles(dateien)) {
        if (p.assetId != null) neue++;
      }
      return neue;
    } catch (e) {
      debugPrint('Überwachter Ordner konnte nicht geprüft werden: $e');
      return 0;
    } finally {
      _ordnerLaeuft = false;
    }
  }

  // -----------------------------------------------------------------------
  // Entwicklungseinstellungen übertragen
  // -----------------------------------------------------------------------

  /// Zuletzt kopierte Entwicklungseinstellungen – Zwischenablage nach dem
  /// Vorbild von Lightrooms "Einstellungen kopieren/einfügen". Bewusst nur
  /// im Speicher: Sie soll wie eine Zwischenablage wirken und nicht über
  /// einen Programmstart hinaus überraschen.
  DevelopSettingsData? _kopierteEntwicklung;
  DevelopSettingsData? get kopierteEntwicklung => _kopierteEntwicklung;
  bool get hatKopierteEntwicklung => _kopierteEntwicklung != null;

  /// Legt die GESPEICHERTEN Einstellungen eines Fotos in die
  /// Zwischenablage. Gibt `false` zurück, wenn das Foto gar nicht
  /// entwickelt wurde. Für Aufrufer ausserhalb des Entwickeln-Bildschirms,
  /// die nur eine Foto-Kennung haben.
  Future<bool> kopiereEntwicklungVon(String assetId) async {
    final s = await db.developSettingsForAsset(assetId);
    if (s == null) return false;
    _kopierteEntwicklung = s;
    notifyListeners();
    return true;
  }

  /// Legt einen beliebigen Satz Werte in die Zwischenablage – gedacht für
  /// den Entwickeln-Bildschirm, der den AKTUELLEN Reglerstand kopiert.
  ///
  /// Die erste Fassung kopierte dort nur, was schon gespeichert war. Das
  /// klang vorsichtig ("übertragen wird, was das Foto auch zeigt"), führte
  /// aber in eine Sackgasse: Speichern schliesst den Bildschirm, man kam
  /// also nach dem Einstellen gar nicht mehr zum Kopieren
  /// (Fehlerbericht). Wer Werte kopiert, will sie weitergeben – ob er sie
  /// für dieses Foto auch behält, ist eine andere Entscheidung.
  void setzeKopierteEntwicklung(DevelopSettingsData werte) {
    _kopierteEntwicklung = werte;
    notifyListeners();
  }

  void leereEntwicklungsZwischenablage() {
    _kopierteEntwicklung = null;
    notifyListeners();
  }

  /// Lädt eine Farbtabelle, wenn eine hinterlegt ist.
  ///
  /// Fehlt die `.cube`-Datei inzwischen, wird ohne sie übertragen statt
  /// abzubrechen: Der Rest der Werte ist deswegen nicht falsch, und ein
  /// Abbruch mitten in einer Auswahl wäre die schlechtere Antwort.
  Future<CubeLut?> _ladeLut(String? relativerPfad) async {
    if (relativerPfad == null) return null;
    try {
      return parseCubeLut(await paths.absolute(relativerPfad).readAsString());
    } catch (e) {
      debugPrint('Farbtabelle $relativerPfad nicht lesbar: $e');
      return null;
    }
  }

  /// Baut aus einem gespeicherten Reglerstand einen übertragbaren Satz.
  ///
  /// Klarheit, Vignette und Farbtabelle wandern mit. Bis 1.9.5 taten sie
  /// das nicht – ein kopierter „Look" liess ausgerechnet das weg, was ihn
  /// ausmacht, und niemand sah, dass etwas fehlte.
  Future<Entwicklungswerte> _werteAus(
    DevelopSettingsData d, {
    String? quellAssetId,
  }) async =>
      Entwicklungswerte(
        regler: DevelopAdjustments(
          exposure: d.exposure,
          temperature: d.temperature,
          tint: d.tint,
          contrast: d.contrast,
          shadows: d.shadows,
          highlights: d.highlights,
          sharpness: d.sharpness,
          noiseReduction: d.noiseReduction,
          clarity: d.clarity,
          vignette: d.vignette,
          lensCorrectionEnabled: d.lensCorrectionEnabled,
          // Kurve und Mischer gehören genauso zur Entwicklung wie die
          // Regler. Ohne sie übernähme das Ziel die Belichtung, aber nicht
          // die Gradation.
          toneCurve: toneCurveAus(d.toneCurveJson),
          colorMixer: colorMixerAus(d.colorMixerJson),
          lut: await _ladeLut(d.lutPath),
          lutStrength: d.lutStrength,
        ),
        lutPath: d.lutPath,
        toneCurveJson: d.toneCurveJson,
        colorMixerJson: d.colorMixerJson,
        quellAssetId: quellAssetId,
      );

  Future<Entwicklungswerte?> _ausZwischenablage() async {
    final q = _kopierteEntwicklung;
    if (q == null) return null;
    return _werteAus(q, quellAssetId: q.assetId);
  }

  /// Dasselbe aus einer benannten Vorgabe. Ohne Quellfoto – eine Vorgabe
  /// gehört zu keinem.
  Future<Entwicklungswerte> werteAusVorgabe(DevelopPresetData v) => _werteAus(
        DevelopSettingsData(
          // Der Bezeichner wird nie benutzt: [quellAssetId] bleibt null,
          // also überspringt die Übertragung kein Foto.
          assetId: '',
          exposure: v.exposure,
          temperature: v.temperature,
          tint: v.tint,
          contrast: v.contrast,
          shadows: v.shadows,
          highlights: v.highlights,
          sharpness: v.sharpness,
          noiseReduction: v.noiseReduction,
          lensCorrectionEnabled: v.lensCorrectionEnabled,
          clarity: v.clarity,
          vignette: v.vignette,
          lutPath: v.lutPath,
          lutStrength: v.lutStrength,
          toneCurveJson: v.toneCurveJson,
          colorMixerJson: v.colorMixerJson,
          updatedAt: v.erstelltAm,
        ),
      );

  /// Überträgt die kopierten Einstellungen auf [zielIds] und rendert jedes
  /// Zielfoto dabei neu – ohne das Rendern bliebe die Änderung unsichtbar,
  /// weil die Anzeige aus der entwickelten Datei kommt und nicht aus den
  /// Reglerwerten.
  ///
  /// Masken werden bewusst NICHT mitübertragen: Sie umschliessen einen Ort
  /// im Quellbild (ein Gesicht, einen Himmel) und hätten im Zielbild keine
  /// Entsprechung – eine Maske um den Kopf auf Foto A liegt auf Foto B
  /// irgendwo im Nichts. Übertragen werden die Werte, die für das ganze
  /// Bild gelten.
  ///
  /// Der bisherige Stand jedes Zielfotos wandert über [saveDevelopResult]
  /// in dessen Verlauf; ein versehentlicher Übertrag lässt sich also je
  /// Foto im Entwickeln-Bildschirm wieder zurückholen.
  Stream<ImportProgress> uebertrageEntwicklung(
    List<String> zielIds, {
    Entwicklungswerte? vorgabe,
  }) async* {
    // Ohne [vorgabe] gilt die Zwischenablage. Beides läuft ab hier durch
    // denselben Code – eine zweite Fassung des Übertragungswegs vergässe
    // beim nächsten neuen Regler etwas, ohne dass es auffiele.
    final quelle = vorgabe ?? await _ausZwischenablage();
    if (quelle == null) {
      yield ImportProgress(0, 0);
      return;
    }

    // Gesperrte Fotos und Videos scheiden aus: Bei gesperrten läge das
    // Original verschlüsselt vor, Videos kennen keine Entwicklung.
    final ziele = <AssetData>[];
    for (final id in zielIds) {
      final a = await db.assetById(id);
      if (a == null || a.isLocked || a.type != 'IMAGE') continue;
      if (a.id == quelle.quellAssetId) continue;
      ziele.add(a);
    }

    final werte = quelle.regler;

    var done = 0;
    yield ImportProgress(0, ziele.length);
    for (final asset in ziele) {
      try {
        final bytes = await NativeImageConverter.developImage(
          paths.absolute(asset.relativePath),
          adjustments: werte,
          maxDimension: 4096,
          quality: 0.92,
        );
        if (bytes == null) {
          throw Exception('Bild konnte nicht gerendert werden.');
        }

        final zielPfad = paths.developedRelativePath(asset.id);
        final datei = paths.absolute(zielPfad);
        await datei.parent.create(recursive: true);
        await datei.writeAsBytes(bytes);

        await db.saveDevelopResult(
          asset.id,
          settings: DevelopSettingsCompanion.insert(
            assetId: asset.id,
            exposure: Value(werte.exposure),
            temperature: Value(werte.temperature),
            tint: Value(werte.tint),
            contrast: Value(werte.contrast),
            shadows: Value(werte.shadows),
            highlights: Value(werte.highlights),
            sharpness: Value(werte.sharpness),
            noiseReduction: Value(werte.noiseReduction),
            lensCorrectionEnabled: Value(werte.lensCorrectionEnabled),
            clarity: Value(werte.clarity),
            vignette: Value(werte.vignette),
            lutPath: Value(quelle.lutPath),
            lutStrength: Value(werte.lutStrength),
            toneCurveJson: Value(quelle.toneCurveJson),
            colorMixerJson: Value(quelle.colorMixerJson),
            updatedAt: DateTime.now(),
          ),
          developedRelativePath: zielPfad,
        );
      } catch (e) {
        debugPrint(
            'Entwicklung übertragen fehlgeschlagen für ${asset.originalFileName}: $e');
      }
      done++;
      yield ImportProgress(done, ziele.length,
          currentFile: asset.originalFileName);
    }
  }

  Stream<ImportProgress> backfillOcrText({bool alle = false}) async* {
    final assets = await db.assetsForOcrBackfill(alle: alle);
    if (assets.isEmpty) {
      yield ImportProgress(0, 0);
      return;
    }

    // Auf macOS erledigt das Vision-Framework die Arbeit ohne Modell und
    // ohne Download; überall sonst braucht es die beiden ONNX-Modelle.
    // Das Modell wird für den ganzen Lauf EINMAL geliehen, nicht je Foto –
    // dasselbe Muster wie bei den Bildbeschreibungen.
    final ueberSystem = Platform.isMacOS;
    OcrService? modell;
    if (!ueberSystem) {
      modell = await ocrHalter.leihen();
      if (modell == null) {
        yield ImportProgress(0, 0);
        return;
      }
    }

    var failed = false;
    try {
      var done = 0;
      yield ImportProgress(0, assets.length);
      for (final asset in assets) {
        // Pro Foto abgesichert: Ein einzelner Fehlschlag (beschädigte
        // Datei, Fehler im nativen Aufruf) darf nicht den ganzen Lauf
        // abbrechen.
        try {
          List<Textstelle>? stellen;
          if (ueberSystem) {
            stellen =
                await NativeImageConverter.recognizeText(_decodableFile(asset));
          } else {
            final bild = await _decodeAsset(asset);
            if (bild != null) stellen = await modell!.erkenne(bild);
          }
          if (stellen != null) {
            // Kein Text im Bild: Nur das Ergebnis merken, keine leere Liste
            // als „Stellen" ablegen – sonst käme das Foto beim nächsten Lauf
            // nicht mehr dran, obwohl nichts zu holen war. Genau das
            // unterscheidet die beiden Fälle in [_ocrOffen].
            await db.setOcrResult(
              asset.id,
              textAusStellen(stellen),
              boxen: stellen.isEmpty ? null : textstellenNachJson(stellen),
            );
          }
        } on LesungLiefertNichts catch (e) {
          // NICHT als leeres Ergebnis speichern: Das Foto würde als
          // durchsucht vermerkt und nach einer Reparatur nie wieder
          // drankommen. Es bleibt offen, der Lauf geht weiter.
          debugPrint('Texterkennung: ${e.stellen} Stellen mit Schrift in '
              '${asset.originalFileName}, keine lesbar – Foto bleibt offen.');
          failed = true;
        } catch (e) {
          failed = true;
          debugPrint(
              'Texterkennung fehlgeschlagen für ${asset.originalFileName}: $e');
        }
        done++;
        yield ImportProgress(done, assets.length,
            currentFile: asset.originalFileName);
      }
    } finally {
      if (!ueberSystem) ocrHalter.zurueckgeben();
    }
    if (alle && !failed) await _markModelPipelineCurrent('ocr');
  }

  /// Erzeugt KI-Bildbeschreibungen nachträglich für Fotos, die vor
  /// Installation des Modells importiert wurden (Captions entstehen sonst
  /// nur automatisch beim Import, siehe [_postProcessNewAsset]).
  /// [alle] beschreibt auch Fotos neu, die schon eine Beschreibung haben –
  /// nach dem Modellwechsel der sinnvolle Weg, siehe
  /// [AppDatabase.assetsForCaptionBackfill].
  Stream<ImportProgress> backfillCaptions({bool alle = false}) async* {
    // Erst die Arbeit ermitteln, dann das Modell holen – siehe
    // [_bildinhaltsAnalyse]. Das Bildbeschreibungs-Modell ist mit 275 MB
    // das zweitgrösste; es für eine leere Liste zu laden war der teuerste
    // Einzelposten des Fehlers.
    final assets = await db.assetsForCaptionBackfill(alle: alle);
    if (assets.isEmpty) {
      yield ImportProgress(0, 0);
      return;
    }
    final service = await captioningHalter.leihen();
    if (service == null) {
      yield ImportProgress(0, 0);
      return;
    }
    // Der Übersetzer wird für den ganzen Lauf einmal geliehen, nicht je
    // Foto – sonst würde ein 100-MB-Modell pro Bild geladen und wieder
    // freigegeben. Null heisst schlicht: nicht installiert oder
    // abgeschaltet, dann bleibt es bei der englischen Beschreibung.
    final uebersetzer = await db.uebersetzeBeschreibungen()
        ? await uebersetzungEnDeHalter.leihen()
        : null;

    var failed = false;
    try {
      var done = 0;
      yield ImportProgress(0, assets.length);
      for (final asset in assets) {
        try {
          final decoded = await _decodeAsset(asset);
          if (decoded == null) {
            throw Exception('Bild konnte nicht dekodiert werden.');
          }
          final caption = await service.generateCaption(decoded);
          String? deutsch;
          if (uebersetzer != null && caption.isNotEmpty) {
            try {
              deutsch = await uebersetzer.translate(caption);
            } catch (e) {
              // Eine fehlgeschlagene Übersetzung darf die Beschreibung
              // nicht mitreissen – das englische Original ist brauchbar.
              debugPrint(
                  'Übersetzung fehlgeschlagen für ${asset.originalFileName}: $e');
            }
          }
          await db.setAiCaption(asset.id, caption, deutsch: deutsch);
        } catch (e) {
          failed = true;
          debugPrint(
              'KI-Bildbeschreibung fehlgeschlagen für ${asset.originalFileName}: $e');
        }
        done++;
        yield ImportProgress(done, assets.length,
            currentFile: asset.originalFileName);
      }
    } finally {
      if (uebersetzer != null) uebersetzungEnDeHalter.zurueckgeben();
      captioningHalter.zurueckgeben();
    }
    if (alle && !failed) await _markModelPipelineCurrent('captions');
  }

  /// Übersetzt vorhandene englische Bildunterschriften ins Deutsche, ohne
  /// das Beschreibungsmodell zu bemühen.
  ///
  /// Das ist der Weg für alle, die die Übersetzung erst später einschalten:
  /// Die englischen Sätze stehen längst in der Datenbank, es fehlt nur ihre
  /// Übertragung. Der Umweg über [backfillCaptions] mit `alle: true` würde
  /// dafür das 275-MB-Modell über die gesamte Bibliothek laufen lassen und
  /// dabei ausgerechnet die vorhandenen Sätze wegwerfen.
  ///
  /// [alle] übersetzt auch das, was schon eine deutsche Fassung hat – nach
  /// einem Modellwechsel der sinnvolle Weg.
  Stream<ImportProgress> uebersetzeBildbeschreibungen(
      {bool alle = false}) async* {
    // Erst die Arbeit ermitteln, dann das Modell holen – siehe
    // [_bildinhaltsAnalyse].
    final assets = await db.assetsForCaptionTranslation(alle: alle);
    if (assets.isEmpty) {
      yield ImportProgress(0, 0);
      return;
    }
    final uebersetzer = await uebersetzungEnDeHalter.leihen();
    if (uebersetzer == null) {
      yield ImportProgress(0, 0);
      return;
    }

    try {
      var done = 0;
      yield ImportProgress(0, assets.length);
      for (final asset in assets) {
        final englisch = asset.aiCaption?.trim() ?? '';
        if (englisch.isNotEmpty) {
          try {
            final deutsch = await uebersetzer.translate(englisch);
            if (deutsch.trim().isNotEmpty) {
              await db.setAiCaptionDe(asset.id, deutsch.trim());
            }
          } catch (e) {
            // Ein Satz, an dem sich das Modell verschluckt, darf den Lauf
            // über die ganze Bibliothek nicht beenden.
            debugPrint(
                'Übersetzung fehlgeschlagen für ${asset.originalFileName}: $e');
          }
        }
        done++;
        yield ImportProgress(done, assets.length,
            currentFile: asset.originalFileName);
      }
    } finally {
      uebersetzungEnDeHalter.zurueckgeben();
    }
  }

  /// Gemeinsamer Durchlauf für die drei Auswertungen, die dasselbe
  /// dekodierte Bild brauchen: Unschärfe, Gesichter und CLIP-Embedding.
  /// Jedes Foto wird EINMAL dekodiert (gemessen ~85 ms) statt bis zu
  /// dreimal – siehe [starteHintergrundanalyse].
  ///
  /// Je Foto wird nur nachgeholt, was tatsächlich fehlt, und nur, wenn das
  /// zugehörige Modell da ist. Ein Foto, dem keine der drei Auswertungen
  /// mehr fehlt, wird gar nicht erst dekodiert.
  ///
  /// Fehler bleiben pro Foto UND pro Auswertung eingegrenzt: Ein
  /// fehlschlagendes CLIP-Modell darf weder die Unschärfe desselben Fotos
  /// noch die folgenden Fotos verhindern.
  Stream<ImportProgress> _bildinhaltsAnalyse() async* {
    final kandidaten = await db.assetsForCombinedImageAnalysis();
    // Nichts zu tun? Dann auch nichts laden. Ohne diese Abkürzung lieh sich
    // die Stufe ihre Modelle, sah danach eine leere Liste und gab sie
    // ungenutzt wieder frei – bei jedem Programmstart, weil die Analyse dort
    // automatisch anläuft. Gemessen belegte die App so 1076 MB statt 214 MB,
    // ohne ein einziges Foto anzufassen; der ganze Zweck des bedarfsweisen
    // Ladens war damit für den Normalfall aufgehoben (Audit-Fund).
    if (kandidaten.isEmpty) {
      yield ImportProgress(0, 0);
      return;
    }
    // Einmal für den ganzen Durchlauf geliehen (siehe ModellHalter.leihen)
    // statt bei tausenden Fotos das Modell implizit ständig neu zu laden.
    // Nur der Bild-Encoder: Hier entstehen ausschliesslich Bild-Embeddings.
    final clip = await clipBildHalter.leihen();
    try {
      final gesichter = await faceEngineHalter.leihen();
      try {
        final augenzustand =
            gesichter != null ? await eyeStateHalter.leihen() : null;
        try {
          var done = 0;
          yield ImportProgress(0, kandidaten.length);

          for (final k in kandidaten) {
            final asset = k.asset;
            final brauchtUnschaerfe = asset.sharpnessScore == null;
            final brauchtGesichter = !asset.facesScanned && gesichter != null;
            final brauchtEmbedding = !k.hatEmbedding && clip != null;

            if (brauchtUnschaerfe || brauchtGesichter || brauchtEmbedding) {
              final decoded = await _decodeAsset(asset);
              if (decoded != null) {
                if (brauchtUnschaerfe) {
                  try {
                    await db.setSharpnessScore(
                        asset.id, await compute(computeBlurScore, decoded));
                  } catch (e) {
                    debugPrint(
                        'Unschärfe fehlgeschlagen für ${asset.originalFileName}: $e');
                  }
                }
                if (brauchtGesichter) {
                  try {
                    await _scanFacesForDecodedAsset(
                      asset,
                      decoded,
                      engine: gesichter,
                      eyeState: augenzustand,
                      deleteExistingUnassigned: false,
                    );
                  } catch (e) {
                    debugPrint(
                        'Gesichtserkennung fehlgeschlagen für ${asset.originalFileName}: $e');
                  }
                }
                if (brauchtEmbedding) {
                  try {
                    await db.saveEmbedding(
                        asset.id, await clip.embedImage(decoded));
                  } catch (e) {
                    debugPrint(
                        'CLIP-Embedding fehlgeschlagen für ${asset.originalFileName}: $e');
                  }
                }
              }
            }

            done++;
            yield ImportProgress(done, kandidaten.length,
                currentFile: asset.originalFileName);
          }
        } finally {
          if (augenzustand != null) eyeStateHalter.zurueckgeben();
        }
      } finally {
        if (gesichter != null) faceEngineHalter.zurueckgeben();
      }
    } finally {
      if (clip != null) clipBildHalter.zurueckgeben();
    }
  }

  /// Berechnet Unschärfe-Scores nachträglich für Fotos, die vor Einführung
  /// dieses Features importiert wurden (siehe [_postProcessNewAsset]).
  /// Wird von der Hintergrundanalyse nicht mehr direkt aufgerufen (dort
  /// erledigt das [_bildinhaltsAnalyse] mit), bleibt aber für den manuellen
  /// Lauf in den Werkzeugen erhalten.
  Stream<ImportProgress> backfillBlurScores() async* {
    final assets = await db.assetsForBlurBackfill();
    var done = 0;
    yield ImportProgress(0, assets.length);
    for (final asset in assets) {
      // Pro Foto abgesichert, analog zu [backfillOcrText].
      try {
        final decoded = await _decodeAsset(asset);
        if (decoded != null) {
          await db.setSharpnessScore(
              asset.id, await compute(computeBlurScore, decoded));
        }
      } catch (e) {
        debugPrint(
            'Unschärfe-Berechnung fehlgeschlagen für ${asset.originalFileName}: $e');
      }
      done++;
      yield ImportProgress(done, assets.length,
          currentFile: asset.originalFileName);
    }
  }

  /// Holt die Gesichtsschärfe für Gesichter nach, die vor Schema 61
  /// erkannt wurden.
  ///
  /// **Aus den gespeicherten Ausschnitten, nicht aus den Fotos.** Der
  /// 160x160-Ausschnitt liegt für jedes erkannte Gesicht auf der Platte.
  /// Ihn zu lesen kostet rund zwei Millisekunden; das zugehörige Foto neu zu
  /// dekodieren kostet je nach Format das Hundertfache – bei 17.867
  /// Gesichtern der Unterschied zwischen einer halben Minute und einer
  /// halben Stunde.
  ///
  /// Ein Gesicht ohne Ausschnitt (von Hand eingezeichnet, oder die Datei
  /// fehlt) bleibt ohne Wert stehen, statt den Lauf abzubrechen.
  Stream<ImportProgress> backfillGesichtsschaerfe() async* {
    final offen = await db.gesichterOhneSchaerfe();
    var done = 0;
    yield ImportProgress(0, offen.length);
    for (final gesicht in offen) {
      try {
        final pfad = gesicht.cropRelativePath;
        if (pfad != null) {
          final datei = paths.absolute(pfad);
          if (await datei.exists()) {
            final bild = img.decodeImage(await datei.readAsBytes());
            if (bild != null) {
              await db.setzeGesichtsschaerfe(
                  gesicht.id, gesichtsschaerfe(bild));
            }
          }
        }
      } catch (e) {
        debugPrint('Gesichtsschärfe fehlgeschlagen für ${gesicht.id}: $e');
      }
      done++;
      yield ImportProgress(done, offen.length);
    }
  }

  /// Schreibt für jedes Asset in der Bibliothek eine `.xmp`-Sidecar-Datei
  /// neben das Original (Interoperabilität mit Lightroom/darktable/digiKam,
  /// siehe xmp_writer.dart) – läuft absichtlich immer über ALLE Assets neu
  /// (kein "bereits geschrieben"-Tracking wie bei OCR/Unschärfe): das
  /// Schreiben ist günstig und idempotent, und so bleiben Sidecars nach
  /// nachträglichen Metadaten-Änderungen (Tag/Bewertung/Beschreibung) bei
  /// erneutem Lauf konsistent. Gesperrte Assets werden ausgeschlossen (siehe
  /// AppDatabase.assetsForXmpExport).
  Stream<ImportProgress> writeXmpSidecars() async* {
    final assets = await db.assetsForXmpExport();
    final tagsByAssetId = await db.allTagNamesByAssetId();
    // Eine Abfrage für alle, nicht eine je Foto – siehe
    // [AppDatabase.alleGesichtsregionen].
    final gesichterByAssetId = await db.alleGesichtsregionen();
    var done = 0;
    yield ImportProgress(0, assets.length);
    for (final asset in assets) {
      final xmp = buildXmpPacket(
        asset,
        tagsByAssetId[asset.id] ?? const [],
        gesichter: gesichterByAssetId[asset.id] ?? const [],
      );
      final sidecarFile =
          paths.absolute(paths.xmpSidecarPath(asset.relativePath));
      await sidecarFile.writeAsString(xmp);
      done++;
      yield ImportProgress(done, assets.length,
          currentFile: asset.originalFileName);
    }
  }

  /// Setzt den Speicherort zurück auf den Standard-App-Support-Ordner.
  /// Schließt dafür die aktuelle Datenbankverbindung – die App muss danach
  /// neu gestartet werden, damit sie den Standardordner wieder lädt (siehe
  /// [LibraryLocation] für die Details zur Sandbox-Zugriffsproblematik).
  Future<void> resetLibraryLocation({
    ValueChanged<BibliotheksVerschiebefortschritt>? onProgress,
  }) async {
    await db.close();
    await LibraryLocation.resetToDefault(onProgress: onProgress);
  }

  /// Löscht die GESAMTE Bibliothek unwiderruflich: die Datenbank (Fotos-
  /// Metadaten, Alben, Personen, Tags, Orte, Favoriten, gesperrter Ordner,
  /// Papierkorb, gespeicherte Suchen, Backup-/Trash-Einstellungen, …) sowie
  /// alle Mediendateien (Originale, Thumbnails, Vorschauen, Gesichts-Crops,
  /// physischer Papierkorb). Heruntergeladene KI-Modelle und Geodaten (siehe
  /// [_modelsDir]/`geoDataDir` in [initialize]) bleiben bewusst erhalten –
  /// sie enthalten keine persönlichen Daten und müssten sonst erneut
  /// heruntergeladen werden. Ein abweichender Speicherort (siehe
  /// [LibraryLocation]) bleibt als Einstellung ebenfalls bestehen, nur dessen
  /// Inhalt wird geleert. Schließt dafür die aktuelle Datenbankverbindung –
  /// die App muss danach neu gestartet werden (siehe SettingsScreen).
  Future<void> eraseLibraryCompletely() async {
    await db.close();
    final root = await LibraryLocation.currentRoot();
    await eraseLibraryDataAt(root);
  }

  /// Löscht eine einzelne Erkennung samt ihrem Ausschnitt auf der Platte.
  Future<void> loescheGesicht(String faceId) async {
    final pfad = await db.loescheGesicht(faceId);
    if (pfad != null) await paths.deletePermanently(pfad);
  }

  /// Löscht alle unbenannten Gesichts-Erkennungen samt ihrer Ausschnitte
  /// auf der Platte und liefert, wie viele es waren.
  ///
  /// Die Dateien mitzunehmen ist der eigentliche Grund, warum das hier
  /// steht und nicht in der Datenbankschicht: Blieben die Ausschnitte
  /// liegen, wäre der Platz nicht frei – und genau der ist der einzige
  /// Vorteil des Löschens gegenüber dem Beiseitelegen.
  Future<int> loescheAlleUnbenanntenErkennungen() async {
    final ergebnis = await db.loescheAlleUnbenanntenErkennungen();
    for (final pfad in ergebnis.pfade) {
      await paths.deletePermanently(pfad);
    }
    return ergebnis.anzahl;
  }

  /// Löscht `library.sqlite` (+ WAL/SHM-Nebendateien) und den `library/`-
  /// Ordner unter [root] – die eigentliche Löschlogik hinter
  /// [eraseLibraryCompletely], hier als eigene, mit einem beliebigen
  /// Verzeichnis testbare Funktion, da [LibraryLocation.currentRoot] über
  /// `path_provider`-Plattform-Kanäle läuft und sich in einem reinen
  /// `flutter test` nicht ohne Weiteres auflösen lässt (siehe
  /// `StoragePaths.forTesting` für dasselbe Muster).
  @visibleForTesting
  static Future<void> eraseLibraryDataAt(Directory root) async {
    final dbPath = p.join(root.path, 'library.sqlite');
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$dbPath$suffix');
      if (await file.exists()) await file.delete();
    }
    final libraryDir = Directory(p.join(root.path, 'library'));
    if (await libraryDir.exists()) await libraryDir.delete(recursive: true);
  }

  /// Berechnet CLIP-Bild-Embeddings nachträglich für Fotos, die vor
  /// Installation des CLIP-Modells importiert wurden (Embeddings entstehen
  /// sonst nur automatisch beim Import, siehe [_postProcessNewAsset]) –
  /// ohne dieses Werkzeug bliebe die KI-Bildsuche/Duplikatsuche auf die
  /// wenigen danach importierten Fotos beschränkt.
  /// [alle] rechnet auch bereits vorhandene Einbettungen neu – für den
  /// Fall, dass sich die Bildvorverarbeitung geändert hat.
  Stream<ImportProgress> backfillClipEmbeddings({bool alle = false}) async* {
    // Erst die Arbeit ermitteln, dann das Modell holen – siehe
    // [_bildinhaltsAnalyse].
    final assets = await db.assetsForEmbeddingBackfill(alle: alle);
    if (assets.isEmpty) {
      yield ImportProgress(0, 0);
      return;
    }
    final service = await clipBildHalter.leihen();
    if (service == null) {
      yield ImportProgress(0, 0);
      return;
    }
    var failed = false;
    try {
      var done = 0;
      yield ImportProgress(0, assets.length);
      for (final asset in assets) {
        try {
          final decoded = await _decodeAsset(asset);
          if (decoded == null) {
            throw Exception('Bild konnte nicht dekodiert werden.');
          }
          final embedding = await service.embedImage(decoded);
          await db.saveEmbedding(asset.id, embedding);
        } catch (e) {
          failed = true;
          debugPrint(
              'CLIP-Embedding fehlgeschlagen für ${asset.originalFileName}: $e');
        }
        done++;
        yield ImportProgress(done, assets.length,
            currentFile: asset.originalFileName);
      }
    } finally {
      clipBildHalter.zurueckgeben();
    }
    if (alle && !failed) await _markModelPipelineCurrent('clip');
  }

  Future<void> _markModelPipelineCurrent(String pipeline) async {
    final state = modelProcessingState;
    if (state == null) return;
    final fingerprint = ModelProcessingState.currentFingerprints()[pipeline];
    if (fingerprint == null) return;
    await state.markCurrent(pipeline, fingerprint);
    _outdatedModelPipelines = {
      ..._outdatedModelPipelines,
    }..remove(pipeline);
    notifyListeners();
  }

  /// Berechnet automatische KI-Tags nachträglich (siehe [AiTaggingService])
  /// – für Fotos, die vor Einführung dieser Funktion importiert wurden oder
  /// wenn das CLIP-Modell erst nachträglich installiert wurde. Nutzt ein
  /// bereits gespeichertes CLIP-Embedding weiter, falls vorhanden, statt es
  /// neu zu berechnen.
  Stream<ImportProgress> backfillAiTags({required bool onlyUntagged}) async* {
    // Erst nachsehen, ob es Arbeit gibt – Modelle zu leihen kostet hier
    // besonders viel (beide CLIP-Encoder, 577 MB), und bei einer fertig
    // ausgewerteten Bibliothek wäre es reine Verschwendung. Siehe
    // [_bildinhaltsAnalyse] für den gemessenen Effekt.
    final assets = await db.assetsForAiTagging(onlyUntagged: onlyUntagged);
    if (assets.isEmpty) {
      yield ImportProgress(0, 0);
      return;
    }
    // Die einzige Stelle, die BEIDE CLIP-Encoder braucht: das Foto wird
    // als Bild eingebettet, die Vokabelbegriffe als Text (siehe
    // AiTaggingService.suggestTags). Hier fällt die Aufteilung also nicht
    // ins Gewicht – die übrigen Stellen sparen dafür je die Hälfte.
    final clipBild = await clipBildHalter.leihen();
    final clipText = clipBild == null ? null : await clipTextHalter.leihen();
    if (clipBild == null || clipText == null) {
      if (clipBild != null) clipBildHalter.zurueckgeben();
      yield ImportProgress(0, 0);
      return;
    }
    try {
      // Einmal pro Lauf statt pro Asset gelesen – das Vokabular ändert sich
      // während eines laufenden Backfills nicht, ein SELECT pro Foto wäre
      // gegenüber der ohnehin pro Foto anfallenden CLIP-Inferenz reine Verschwendung.
      final vocabulary = await db.aiTagVocabularyTerms();
      // Aus demselben Grund wie das Vokabular einmal pro Lauf statt pro
      // Foto geladen (siehe applyAutomationRules' `rules`-Parameter).
      final automationRules = await db.allAutomationRules();
      var done = 0;
      yield ImportProgress(0, assets.length);
      for (final asset in assets) {
        try {
          var embedding = await db.embeddingForAsset(asset.id);
          if (embedding == null) {
            final decoded = await _decodeAsset(asset);
            if (decoded == null) {
              throw Exception('Bild konnte nicht dekodiert werden.');
            }
            embedding = await clipBild.embedImage(decoded);
            await db.saveEmbedding(asset.id, embedding);
          }
          final tags = await aiTaggingService.suggestTags(
            clipText,
            embedding,
            vocabulary,
            insEnglische: insEnglische,
          );
          for (final tag in tags) {
            // Als Vorschlag der Bilderkennung gekennzeichnet – damit er
            // beim Sperren verschwindet und nach dem Entsperren neu
            // berechnet wird (siehe [Tagquelle]). Eine bereits von Hand
            // vergebene Zuordnung lässt `tagAsset` dabei unangetastet.
            await db.tagAsset(asset.id, tag, quelle: Tagquelle.ki);
          }
          if (tags.isNotEmpty) {
            await applyAutomationRules(asset.id,
                aiTags: tags, rules: automationRules);
          }
          // Auch bei LEERER Trefferliste vermerken: "kein Begriff passt" ist
          // ein Ergebnis, kein offener Posten. Ohne diesen Vermerk bliebe das
          // Foto für immer Kandidat und die Stufe lüde bei jedem Start erneut
          // beide CLIP-Encoder, um wieder nichts zu finden (Audit-Fund).
          // Bewusst NUR im Erfolgsfall – ein abgebrochener Durchlauf (siehe
          // catch) soll erneut versucht werden.
          await db.markAiTagsScanned([asset.id]);
        } catch (e) {
          debugPrint(
              'KI-Tagging fehlgeschlagen für ${asset.originalFileName}: $e');
        }
        done++;
        yield ImportProgress(done, assets.length,
            currentFile: asset.originalFileName);
      }
    } finally {
      clipTextHalter.zurueckgeben();
      clipBildHalter.zurueckgeben();
    }
  }

  // -----------------------------------------------------------------------
  // Gesperrter Ordner (PIN-Schutz + echte AES-256-Verschlüsselung)
  // -----------------------------------------------------------------------
  //
  // Der entpackte Master-Key lebt ausschließlich im Prozessspeicher dieser
  // Sitzung ([_vaultKey]) – nie auf der Platte. Er bleibt für den Rest der
  // App-Sitzung gültig, sobald der PIN einmal korrekt eingegeben wurde
  // (siehe [ensureVaultUnlocked] in pin_dialogs.dart), damit weder das
  // Sperren eines weiteren Fotos noch ein erneuter Besuch des gesperrten
  // Ordners jedes Mal wieder nach dem PIN fragen muss. [lockVaultSession]
  // erlaubt, das manuell vorzeitig zu beenden.

  SecretKey? _vaultKey;
  bool get vaultUnlockedThisSession => _vaultKey != null;

  /// Richtet den gesperrten Ordner erstmalig ein: neuer zufälliger
  /// Master-Key, mit [pin] verpackt – und direkt für diese Sitzung
  /// entsperrt.
  Future<void> setupVaultPin(String pin) async {
    final wrapped = await VaultCrypto.createMasterKey(pin);
    await db.saveVaultKey(
        kdfSalt: wrapped.kdfSalt,
        nonce: wrapped.nonce,
        wrapped: wrapped.wrapped);
    _vaultKey = wrapped.masterKey;
  }

  /// Entsperrt den gesperrten Ordner für die laufende Sitzung. Wirft bei
  /// falschem PIN (GCM-Authentifizierung des Master-Keys schlägt fehl).
  Future<void> unlockVaultWithPin(String pin) async {
    final row = await db.privacySettingsRow();
    final kdfSalt = row?.kdfSalt;
    final nonce = row?.wrappedMasterKeyNonce;
    final wrapped = row?.wrappedMasterKey;
    if (kdfSalt == null || nonce == null || wrapped == null) {
      throw StateError('Kein PIN eingerichtet.');
    }
    _vaultKey = await VaultCrypto.unwrapMasterKey(pin,
        kdfSalt: kdfSalt, nonce: nonce, wrapped: wrapped);
  }

  /// Ändert den PIN, ohne den Master-Key (und damit alle bereits
  /// verschlüsselten Dateien) neu erzeugen zu müssen – nur die "Verpackung"
  /// des Master-Keys ändert sich.
  Future<void> changeVaultPin(String newPin) async {
    final key = _vaultKey;
    if (key == null) {
      throw StateError('Der gesperrte Ordner muss vorher entsperrt sein.');
    }
    final wrapped = await VaultCrypto.wrapMasterKey(key, newPin);
    await db.saveVaultKey(
        kdfSalt: wrapped.kdfSalt,
        nonce: wrapped.nonce,
        wrapped: wrapped.wrapped);
  }

  /// Entfernt den PIN-Schutz und entschlüsselt alle gesperrten Dateien
  /// wieder zurück in Klartext – sonst wären sie über keine UI mehr
  /// erreichbar.
  Future<void> removeVaultPin() async {
    final key = _vaultKey;
    if (key == null) {
      throw StateError('Der gesperrte Ordner muss vorher entsperrt sein.');
    }
    final locked = await db.watchLockedAssets().first;
    for (final asset in locked) {
      await _decryptAssetFiles(asset, key);
      await _restorePrivateMetadata(asset.id, key);
      await db.setAssetsLocked([asset.id], false);
    }
    await db.clearVaultKey();
    _vaultKey = null;
  }

  /// Sperrt die laufende Sitzung wieder (z.B. bevor man den Rechner aus der
  /// Hand gibt), ohne die App beenden zu müssen – der Master-Key ist danach
  /// aus dem Speicher entfernt, der nächste Zugriff verlangt wieder den PIN.
  void lockVaultSession() {
    if (_vaultKey == null) return;
    _vaultKey = null;
    // Damit ein offener gesperrter Ordner davon erfährt und sich schliesst,
    // statt gleich darauf an jeder Kachel zu scheitern.
    notifyListeners();
  }

  /// Sperrt die Sitzung **und** räumt die entschlüsselten Zwischenkopien
  /// weg.
  ///
  /// Zwei Schritte, die immer zusammengehören: Ein Schlüssel aus dem
  /// Speicher nützt wenig, solange die Klartextkopien der eben
  /// angesehenen Fotos im Temp-Verzeichnis liegen. Bis zur 17. Prüfrunde
  /// stand die Reihenfolge an genau einer Aufrufstelle im Bildschirm –
  /// jede weitere hätte sie sich merken müssen.
  Future<void> sperreTresor() async {
    lockVaultSession();
    await clearDecryptCache();
  }

  Future<void> _cryptFileInPlace(
    String relativePath,
    SecretKey key, {
    required bool encrypt,
  }) async {
    final file = paths.absolute(relativePath);
    if (!await file.exists()) return;
    final tmp = File('${file.path}.vaulttmp');
    try {
      if (encrypt) {
        await VaultCrypto.encryptFile(file, tmp, key);
      } else {
        await VaultCrypto.decryptFile(file, tmp, key);
      }
      await tmp.rename(file.path);
    } finally {
      // Scheitert der Durchgang, bleibt sonst ein Rumpf neben dem Original
      // liegen: beim Entsperren Klartext einer gesperrten Datei, beim
      // Sperren Chiffretext, den niemand mehr zuordnen kann. Das Original
      // ist in beiden Fällen unangetastet – nur der Rumpf muss weg.
      if (await tmp.exists()) await tmp.delete();
    }
  }

  /// Verschlüsselt Original, Thumbnail, Vorschau, ein evtl. entwickeltes
  /// Bild (siehe DevelopScreen), einen evtl. nicht-destruktiven Video-
  /// Zuschnitt (siehe VideoTrimScreen), evtl. gespeicherte KI-Objektmasken
  /// (siehe MaskEditor) und ggf. bereits vorhandene Gesichts-Crops eines
  /// Assets an Ort und Stelle (derselbe relative Pfad, nur der
  /// Dateiinhalt ändert sich von Klartext zu Chiffretext) – wichtig, damit
  /// beim Sperren nie eine unverschlüsselte Kopie einer dieser
  /// Zusatzdateien zurückbleibt (Audit-Fund: `trimmedRelativePath` und
  /// `DevelopMasks.maskRelativePath` fehlten hier ursprünglich).
  /// **Alle Dateien, die zu einem Foto gehören – an einer Stelle.**
  ///
  /// Diese Liste stand dreimal fast gleich im Quelltext: beim
  /// Verschlüsseln, beim Entschlüsseln und beim endgültigen Löschen. Sie
  /// ist zweimal auseinandergelaufen, und beide Male fiel es erst einer
  /// Prüfrunde auf – zuerst fehlten Videozuschnitt und Objektmasken,
  /// danach der XMP-Beipackzettel. Wer eine Dateiart hinzufügt, trägt sie
  /// hier ein und ist damit überall richtig.
  ///
  /// Nicht vorhandene Dateien stehen mit in der Liste; die drei
  /// Verwender kommen damit zurecht.
  Future<List<String>> dateienVon(AssetData asset) async => [
        asset.relativePath,
        // Der Beipackzettel neben dem Original: Er trägt Beschreibung,
        // Schlagwörter, Bewertung und Ort im Klartext. Beim Sperren blieb
        // er liegen – genau das, wovor der gesperrte Ordner schützen soll
        // (dieselbe Überlegung wie bei metadata.json in backup_service).
        paths.xmpSidecarPath(asset.relativePath),
        if (asset.thumbnailRelativePath != null) asset.thumbnailRelativePath!,
        if (asset.previewRelativePath != null) asset.previewRelativePath!,
        if (asset.developedRelativePath != null) asset.developedRelativePath!,
        if (asset.restoredRelativePath != null) asset.restoredRelativePath!,
        if (asset.trimmedRelativePath != null) asset.trimmedRelativePath!,
        for (final face in await db.facesForAsset(asset.id))
          if (face.cropRelativePath != null) face.cropRelativePath!,
        for (final mask in await db.masksForAsset(asset.id))
          mask.maskRelativePath,
      ];

  Future<void> _encryptAssetFiles(AssetData asset, SecretKey key) async {
    for (final relPath in await dateienVon(asset)) {
      await _cryptFileInPlace(relPath, key, encrypt: true);
    }
  }

  Future<void> _decryptAssetFiles(AssetData asset, SecretKey key) async {
    for (final relPath in await dateienVon(asset)) {
      await _cryptFileInPlace(relPath, key, encrypt: false);
    }
  }

  static const _privateMetadataMagic = <int>[0x50, 0x56, 0x4d, 0x31];

  /// Schreibt die privaten, in SQLite sonst direkt lesbaren Angaben als
  /// authentifiziert verschlüsselten Datensatz. Die Asset-ID wird als AAD
  /// gebunden, damit zwei gültige Metadatendateien nicht vertauscht werden
  /// können. Klartext entsteht dabei nur im Arbeitsspeicher.
  Future<void> _protectPrivateMetadata(AssetData asset, SecretKey key) async {
    final setting = await db.privacySettingsRow();
    if (!(setting?.protectMetadata ?? true)) return;

    final relations = await db.privateRelationsForAsset(asset.id);
    final metadata = <String, Object?>{
      'originalFileName': asset.originalFileName,
      'fileCreatedAt': asset.fileCreatedAt.toIso8601String(),
      'importedAt': asset.importedAt.toIso8601String(),
      'isFavorite': asset.isFavorite,
      'faceScanExcluded': asset.faceScanExcluded,
      'description': asset.description,
      'latitude': asset.latitude,
      'longitude': asset.longitude,
      'cameraMake': asset.cameraMake,
      'cameraModel': asset.cameraModel,
      'lensModel': asset.lensModel,
      'focalLengthMm': asset.focalLengthMm,
      'fNumber': asset.fNumber,
      'iso': asset.iso,
      'exposureTimeSeconds': asset.exposureTimeSeconds,
      'exposureBiasEv': asset.exposureBiasEv,
      'focalLength35mm': asset.focalLength35mm,
      'locationCountry': asset.locationCountry,
      'locationState': asset.locationState,
      'locationCity': asset.locationCity,
      'rating': asset.rating,
      'colorLabel': asset.colorLabel,
      'ocrText': asset.ocrText,
      'ocrScanned': asset.ocrScanned,
      'ocrBoxen': asset.ocrBoxen,
      'gpsGeprueft': asset.gpsGeprueft,
      'datumGeschaetzt': asset.datumGeschaetzt,
      'datumGeprueft': asset.datumGeprueft,
      'ortGeerbt': asset.ortGeerbt,
      'videobilderGeprueft': asset.videobilderGeprueft,
      'zeitversatzMinuten': asset.zeitversatzMinuten,
      'aiCaption': asset.aiCaption,
      'aiCaptionDe': asset.aiCaptionDe,
      'aiCaptionScanned': asset.aiCaptionScanned,
      'aiCaptionEdited': asset.aiCaptionEdited,
      'aiTagsScanned': asset.aiTagsScanned,
      'tags': relations['tags'] ?? const <String>[],
      'albums': relations['albums'] ?? const <String>[],
    };
    final cipher = AesGcm.with256bits();
    final nonce = cipher.newNonce();
    final box = await cipher.encrypt(utf8.encode(jsonEncode(metadata)),
        secretKey: key, nonce: nonce, aad: utf8.encode(asset.id));
    final target = paths.absolute(paths.vaultMetadataRelativePath(asset.id));
    final part = File('${target.path}.part');
    try {
      await part.writeAsBytes([
        ..._privateMetadataMagic,
        ...nonce,
        ...box.cipherText,
        ...box.mac.bytes
      ], flush: true);
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } finally {
      if (await part.exists()) await part.delete();
    }
    await db.hidePrivateMetadata(asset.id);
  }

  Future<void> _restorePrivateMetadata(String assetId, SecretKey key) async {
    final target = paths.absolute(paths.vaultMetadataRelativePath(assetId));
    if (!await target.exists()) return; // Bestand aus älteren Fassungen.
    final bytes = await target.readAsBytes();
    if (bytes.length < 4 + 12 + 16 ||
        !listEquals(bytes.sublist(0, 4), _privateMetadataMagic)) {
      throw const FormatException('Ungültige private Metadatendatei.');
    }
    final nonce = bytes.sublist(4, 16);
    final payload = bytes.sublist(16, bytes.length - 16);
    final mac = Mac(bytes.sublist(bytes.length - 16));
    final cipher = AesGcm.with256bits();
    final clear = await cipher.decrypt(
      SecretBox(payload, nonce: nonce, mac: mac),
      secretKey: key,
      aad: utf8.encode(assetId),
    );
    final json = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    double? number(String key) => (json[key] as num?)?.toDouble();
    final tags = <(String, String)>[];
    for (final encoded in (json['tags'] as List? ?? const [])) {
      final parts = (encoded as String).split('\u0000');
      if (parts.length == 2) tags.add((parts[0], parts[1]));
    }
    await db.restorePrivateMetadata(
      assetId,
      AssetsCompanion(
        originalFileName: Value(json['originalFileName'] as String),
        fileCreatedAt: Value(DateTime.parse(json['fileCreatedAt'] as String)),
        importedAt: Value(DateTime.parse(json['importedAt'] as String)),
        isFavorite: Value(json['isFavorite'] as bool),
        faceScanExcluded: Value(json['faceScanExcluded'] as bool),
        description: Value(json['description'] as String?),
        latitude: Value(number('latitude')),
        longitude: Value(number('longitude')),
        cameraMake: Value(json['cameraMake'] as String?),
        cameraModel: Value(json['cameraModel'] as String?),
        lensModel: Value(json['lensModel'] as String?),
        focalLengthMm: Value(number('focalLengthMm')),
        fNumber: Value(number('fNumber')),
        iso: Value(json['iso'] as int?),
        exposureTimeSeconds: Value(number('exposureTimeSeconds')),
        exposureBiasEv: Value(number('exposureBiasEv')),
        focalLength35mm: Value(number('focalLength35mm')),
        locationCountry: Value(json['locationCountry'] as String?),
        locationState: Value(json['locationState'] as String?),
        locationCity: Value(json['locationCity'] as String?),
        rating: Value(json['rating'] as int),
        colorLabel: Value(json['colorLabel'] as String?),
        ocrText: Value(json['ocrText'] as String?),
        ocrScanned: Value(json['ocrScanned'] as bool),
        ocrBoxen: Value(json['ocrBoxen'] as String?),
        gpsGeprueft: Value(json['gpsGeprueft'] as bool),
        datumGeschaetzt: Value(json['datumGeschaetzt'] as bool),
        datumGeprueft: Value(json['datumGeprueft'] as bool),
        ortGeerbt: Value(json['ortGeerbt'] as bool),
        videobilderGeprueft: Value(json['videobilderGeprueft'] as bool),
        zeitversatzMinuten: Value(json['zeitversatzMinuten'] as int?),
        aiCaption: Value(json['aiCaption'] as String?),
        aiCaptionDe: Value(json['aiCaptionDe'] as String?),
        aiCaptionScanned: Value(json['aiCaptionScanned'] as bool),
        aiCaptionEdited: Value(json['aiCaptionEdited'] as bool),
        aiTagsScanned: Value(json['aiTagsScanned'] as bool),
      ),
      tags: tags,
      albumIds: [
        for (final id in json['albums'] as List? ?? const []) id as String
      ],
    );
    await target.delete();
  }

  /// Verschlüsselt ein Foto/Video und verschiebt es in den gesperrten
  /// Ordner. Setzt voraus, dass der gesperrte Ordner für diese Sitzung
  /// bereits entsperrt ist (siehe [ensureVaultUnlocked] in
  /// pin_dialogs.dart) – wirft sonst. Ein verknüpfter Live-Photo-Partner
  /// (Foto<->Video) wird automatisch mitgesperrt, damit nie nur eine Hälfte
  /// eines Live Photos verschlüsselt ist.
  Future<void> lockAsset(AssetData asset) async {
    final key = _vaultKey;
    if (key == null) {
      throw StateError('Der gesperrte Ordner muss vorher entsperrt sein.');
    }
    await _encryptAssetFiles(asset, key);
    await _protectPrivateMetadata(asset, key);
    await db.setAssetsLocked([asset.id], true);
    // Auch die aus dem Bildinhalt abgeleiteten Daten müssen weg, sonst
    // bliebe der Inhalt in der unverschlüsselten Datenbank lesbar – siehe
    // [AppDatabase.clearDerivedContentData].
    await db.clearDerivedContentData([asset.id]);
    // Der Ausschnitt ist jetzt Chiffrat – ein Profilbild, das darauf
    // zeigt, bliebe leer.
    await db.verlegeProfilbilderVon([asset.id]);
    if (asset.linkedAssetId != null) {
      final partner = await db.assetById(asset.linkedAssetId!);
      if (partner != null && !partner.isLocked) {
        await _encryptAssetFiles(partner, key);
        await _protectPrivateMetadata(partner, key);
        await db.setAssetsLocked([partner.id], true);
        await db.clearDerivedContentData([partner.id]);
        await db.verlegeProfilbilderVon([partner.id]);
      }
    }
    // **Auf der Platte steht jetzt Chiffrat – im Bildspeicher der
    // Klartext.** Flutter merkt sich dekodierte Bilder nach Pfad und
    // Zielgrösse, nicht nach Inhalt (siehe [vergissAlleBilder]). Die
    // Vorschau, die der Anwender eine Sekunde vor dem Sperren noch
    // angesehen hat, liegt also unverändert im Arbeitsspeicher und würde
    // von dort weiter ausgeliefert, ohne dass je wieder eine Datei
    // gelesen oder ein Schlüssel gebraucht würde. Das Versprechen des
    // gesperrten Ordners ist aber, dass der Inhalt ohne PIN weg ist.
    vergissAlleBilder();
  }

  /// Kehrt [lockAsset] um: entschlüsselt die Dateien wieder in Klartext und
  /// entfernt das Foto (samt Live-Photo-Partner) aus dem gesperrten Ordner.
  Future<void> unlockAsset(AssetData asset) async {
    final key = _vaultKey;
    if (key == null) {
      throw StateError('Der gesperrte Ordner muss vorher entsperrt sein.');
    }
    await _decryptAssetFiles(asset, key);
    await _restorePrivateMetadata(asset.id, key);
    await db.setAssetsLocked([asset.id], false);
    if (asset.linkedAssetId != null) {
      final partner = await db.assetById(asset.linkedAssetId!);
      if (partner != null && partner.isLocked) {
        await _decryptAssetFiles(partner, key);
        await _restorePrivateMetadata(partner.id, key);
        await db.setAssetsLocked([partner.id], false);
      }
    }
  }

  /// Temporäres Verzeichnis außerhalb der Bibliothek für rein zur Anzeige
  /// entschlüsselte Dateien (Vollbildansicht/Thumbnails im gesperrten
  /// Ordner) – die Originaldatei auf der Platte bleibt verschlüsselt.
  Directory get _decryptCacheDir =>
      Directory(p.join(Directory.systemTemp.path, 'photovault_decrypt'));

  /// Wie viel Klartext im Zwischenspeicher liegen darf, bevor die
  /// ältesten Stücke weichen.
  ///
  /// **Vorher gab es gar keine Grenze.** Wer durch einen gesperrten
  /// Ordner blättert, entschlüsselt jedes angesehene Original in voller
  /// Grösse hierher; geräumt wurde erst beim Verlassen. Bei
  /// Fünf-Megabyte-Aufnahmen sind hundertfünfzig Bilder schon
  /// dreiviertel Gigabyte – und unter Flatpak ist `/tmp` ein tmpfs, also
  /// Arbeitsspeicher. Eine halbe Milliarde Byte reicht für mehr Bilder,
  /// als jemand am Stück ansieht, und lässt sich nicht vollblättern.
  static const int hoechstensImZwischenspeicher = 512 * 1024 * 1024;

  /// Wirft die ältesten Stücke weg, bis der Zwischenspeicher wieder unter
  /// [hoechstensImZwischenspeicher] liegt.
  ///
  /// Nach der Zugriffszeit, nicht nach der Schreibzeit: Ein Bild, das
  /// beim Blättern mehrfach gebraucht wird, soll nicht deshalb weichen,
  /// weil es früh entschlüsselt wurde. Ein weggeworfenes Stück ist kein
  /// Verlust – der nächste Zugriff entschlüsselt es erneut.
  Future<void> _kuerzeZwischenspeicher(Directory cacheDir) async {
    final stuecke = <(File, DateTime, int)>[];
    var summe = 0;
    await for (final e in cacheDir.list(followLinks: false)) {
      if (e is! File) continue;
      try {
        final st = await e.stat();
        stuecke.add((e, st.accessed, st.size));
        summe += st.size;
      } on FileSystemException {
        // Ein anderer Durchgang war schneller – dann zählt es nicht mehr.
      }
    }
    if (summe <= hoechstensImZwischenspeicher) return;
    stuecke.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (datei, _, groesse) in stuecke) {
      if (summe <= hoechstensImZwischenspeicher) break;
      try {
        await datei.delete();
        summe -= groesse;
      } on FileSystemException {
        // Schon weg oder gerade in Benutzung – dann eben das nächste.
      }
    }
  }

  /// Entschlüsselt eine gesperrte Datei in den temporären Zwischenspeicher
  /// (nur beim ersten Zugriff, danach aus dem Cache) und gibt sie zurück.
  /// Setzt einen bereits entsperrten gesperrten Ordner voraus.
  Future<File> decryptForViewing(String relativePath) async {
    final key = _vaultKey;
    if (key == null) {
      throw StateError('Der gesperrte Ordner muss vorher entsperrt sein.');
    }
    final cacheDir = _decryptCacheDir;
    final frisch = !await cacheDir.exists();
    await cacheDir.create(recursive: true);
    if (frisch) await _nurFuerMich(cacheDir);
    // Über den Hash des Pfades, nicht über ersetzte Trennzeichen: „a/b.jpg"
    // und „a_b.jpg" wurden sonst auf denselben Namen abgebildet und konnten
    // sich gegenseitig anzeigen.
    final safeName = sha256.convert(utf8.encode(relativePath)).toString();
    final target = File(p.join(cacheDir.path, safeName));
    if (!await target.exists()) {
      // Erst unter eigenem Namen entschlüsseln, dann umbenennen. Zwei
      // Gründe, beide aus Prüfrunde 8:
      //
      // Die Ansicht kann dieselbe Datei zweimal gleichzeitig anfordern –
      // eine Kachel, die aus dem Bild scrollt und zurückkommt, startet
      // einen zweiten Durchgang, während der erste noch schreibt. Beide
      // sähen "gibt es noch nicht" und schrieben ineinander. Das Umbenennen
      // ist unteilbar; im schlimmsten Fall gewinnt der zweite Durchgang mit
      // demselben Inhalt.
      //
      // Und: Unter dem endgültigen Namen darf nie ein Rumpf stehen. Bräche
      // das Entschlüsseln ab, hielte der Zwischenspeicher die abgebrochene
      // Fassung für fertig und zeigte sie beim nächsten Zugriff wortlos
      // weiter, statt es erneut zu versuchen.
      final teil =
          File('${target.path}.${DateTime.now().microsecondsSinceEpoch}');
      try {
        await VaultCrypto.decryptFile(paths.absolute(relativePath), teil, key);
        await teil.rename(target.path);
      } finally {
        if (await teil.exists()) await teil.delete();
      }
      // Nur nach einem echten Zulauf, nicht bei jedem Treffer: Das
      // Durchzählen kostet einen Systemaufruf je Stück, und ein Treffer
      // soll billig bleiben.
      await _kuerzeZwischenspeicher(cacheDir);
    }
    return target;
  }

  /// Entzieht allen ausser dem eigenen Benutzer den Zugriff auf [ordner].
  ///
  /// Dart legt Verzeichnisse mit 0755 und Dateien mit 0644 an (gemessen).
  /// Auf allen drei ausgelieferten Verpackungen liegt `Directory.systemTemp`
  /// zwar ohnehin schon geschützt – macOS im Sandkasten-Container, Windows
  /// im Benutzerprofil, Linux im privaten tmpfs des Flatpaks –, aber das
  /// ist eine Eigenschaft der Verpackung, keine der App. Ein Klartextfoto
  /// aus dem gesperrten Ordner soll nicht davon abhängen.
  Future<void> _nurFuerMich(Directory ordner) async {
    if (Platform.isWindows) return; // Dort regeln es die Zugriffslisten.
    try {
      await Process.run('chmod', ['700', ordner.path]);
    } on ProcessException {
      // Kein chmod vorhanden – dann bleibt es beim Schutz der Verpackung.
    }
  }

  /// Leert den Entschlüsselungs-Zwischenspeicher – beim App-Start (Reste
  /// einer abgestürzten vorigen Sitzung) und beim Verlassen des gesperrten
  /// Ordners, damit keine entschlüsselten Kopien länger als nötig auf der
  /// Platte liegen bleiben.
  Future<void> clearDecryptCache() async {
    final dir = _decryptCacheDir;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    // Aus demselben Grund wie beim Sperren: Die Dateien sind weg, die
    // daraus dekodierten Bilder lägen sonst weiter im Arbeitsspeicher.
    // Der Bildspeicher fasst 100 MiB – so viel Klartext bliebe nach dem
    // Verlassen des gesperrten Ordners stehen.
    vergissAlleBilder();
  }

  /// Räumt Klartext-Vorschauen aus dem Tresor-Zwischenspeicher und alte,
  /// unvollständige Schreibdateien weg. Beide Gruppen sind vollständig
  /// regenerierbar; Originale, Vorschaubilder und Modelle werden nie
  /// gelöscht.
  Future<({int dateien, int bytes})> bereinigeTemporareDateien() async {
    var cacheDateien = 0;
    var cacheBytes = 0;
    final dir = _decryptCacheDir;
    if (await dir.exists()) {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            cacheDateien++;
            cacheBytes += await entity.length();
          } on FileSystemException {
            // Bereits verschwunden.
          }
        }
      }
    }
    await clearDecryptCache();
    final reste = await paths.bereinigeSchreibreste();
    return (
      dateien: cacheDateien + reste.dateien,
      bytes: cacheBytes + reste.bytes,
    );
  }

  // -----------------------------------------------------------------------
  // Backup-Verschlüsselung (eigener Master-Key, eigene Passphrase – bewusst
  // getrennt vom PIN des gesperrten Ordners, siehe BackupSettings)
  // -----------------------------------------------------------------------

  SecretKey? _backupKey;
  bool get backupKeyAvailableThisSession => _backupKey != null;

  Future<void> setupBackupPassphrase(String passphrase) async {
    final wrapped = await VaultCrypto.createMasterKey(passphrase);
    await db.saveBackupKey(
        kdfSalt: wrapped.kdfSalt,
        nonce: wrapped.nonce,
        wrapped: wrapped.wrapped);
    _backupKey = wrapped.masterKey;
  }

  Future<void> unlockBackupKeyWithPassphrase(String passphrase) async {
    final row = await db.backupSettingsRow();
    final kdfSalt = row?.kdfSalt;
    final nonce = row?.wrappedMasterKeyNonce;
    final wrapped = row?.wrappedMasterKey;
    if (kdfSalt == null || nonce == null || wrapped == null) {
      throw StateError('Keine Backup-Passphrase eingerichtet.');
    }
    _backupKey = await VaultCrypto.unwrapMasterKey(passphrase,
        kdfSalt: kdfSalt, nonce: nonce, wrapped: wrapped);
  }

  Future<void> changeBackupPassphrase(String newPassphrase) async {
    final key = _backupKey;
    if (key == null) {
      throw StateError('Die Backup-Passphrase muss vorher entsperrt sein.');
    }
    final wrapped = await VaultCrypto.wrapMasterKey(key, newPassphrase);
    await db.saveBackupKey(
        kdfSalt: wrapped.kdfSalt,
        nonce: wrapped.nonce,
        wrapped: wrapped.wrapped);
  }

  /// Entfernt nur die lokale Backup-Verschlüsselungs-Einrichtung – bereits
  /// bestehende verschlüsselte Backups am Zielort bleiben unangetastet
  /// (anders als beim gesperrten Ordner gibt es hier nichts "zu
  /// entschlüsseln", die Originaldateien in der Bibliothek selbst waren nie
  /// verschlüsselt).
  Future<void> removeBackupEncryption() async {
    await db.clearBackupKey();
    _backupKey = null;
  }

  /// Führt ein manuelles Backup aus – bei [encrypt] mit dem für diese
  /// Sitzung entsperrten Backup-Schlüssel (siehe [ensureBackupKeyAvailable]
  /// in pin_dialogs.dart, das der Aufrufer vorher ausgeführt haben muss).
  Stream<BackupProgress> runManualBackup(String destination,
      {required bool encrypt}) async* {
    final grenze = await _backupGrenzeBytes();
    yield* backupService.performBackup(destination,
        encryptionKey: encrypt ? _backupKey : null, maxBytesPerRun: grenze);
  }

  /// Portionsgrenze je Sicherungslauf in Bytes, 0 = unbegrenzt (siehe
  /// BackupSettings.autoBackupMaxMbPerRun).
  Future<int> _backupGrenzeBytes() async {
    final config = await db.backupSettingsRow();
    final mb = config?.autoBackupMaxMbPerRun ?? 0;
    return mb > 0 ? mb * 1024 * 1024 : 0;
  }

  /// Löst das automatische Backup unabhängig vom Intervall manuell aus
  /// (z.B. über den "Jetzt synchronisieren"-Button in den Einstellungen).
  /// Setzt voraus, dass die Backup-Passphrase für diese Sitzung bereits
  /// entsperrt ist.
  Stream<BackupProgress> runAutoBackupNow(String destination) async* {
    final key = _backupKey;
    if (key == null) {
      throw StateError('Die Backup-Passphrase muss vorher entsperrt sein.');
    }
    yield* backupService.performAutoBackup(destination, key,
        maxBytesPerRun: await _backupGrenzeBytes());
    await db.setLastAutoBackupAt(DateTime.now());
  }

  /// Prüft, ob das automatische Backup fällig ist (aktiviert, Ziel gesetzt,
  /// Intervall abgelaufen) und der Backup-Schlüssel für diese Sitzung
  /// bereits vorliegt – wenn nicht, wird NICHT nach der Passphrase gefragt
  /// (das würde unerwartet mitten in der Nutzung passieren), sondern der
  /// Lauf einfach übersprungen; die Einstellungen zeigen dann an, dass eine
  /// erneute Passphrase-Eingabe nötig ist. Läuft nur, solange die App offen
  /// ist – kein Hintergrunddienst, siehe Klassenkommentar in
  /// [BackupService.performAutoBackup].
  Future<void> runAutoBackupIfDue() async {
    if (_autoBackupRunning) return;
    final config = await db.backupSettingsRow();
    if (config == null || !config.autoBackupEnabled) return;
    final destination = config.autoBackupDestination;
    if (destination == null || destination.isEmpty) return;

    final lastRun = config.lastAutoBackupAt;
    if (lastRun != null) {
      final due = lastRun.add(Duration(hours: config.autoBackupIntervalHours));
      if (DateTime.now().isBefore(due)) return;
    }

    final key = _backupKey;
    if (key == null) {
      return; // Passphrase muss erst wieder manuell entsperrt werden.
    }

    _autoBackupRunning = true;
    try {
      await backupService
          .performAutoBackup(destination, key,
              maxBytesPerRun: (config.autoBackupMaxMbPerRun > 0)
                  ? config.autoBackupMaxMbPerRun * 1024 * 1024
                  : 0)
          .drain<void>();
      await db.setLastAutoBackupAt(DateTime.now());
    } catch (e) {
      debugPrint('Automatisches Backup fehlgeschlagen: $e');
    } finally {
      _autoBackupRunning = false;
    }
  }

  /// Löscht alle zu einem Asset gehörenden Dateien von der Platte (Original,
  /// Thumbnail, Vorschau, entwickeltes Bild, Video-Zuschnitt, KI-Objekt-
  /// masken, Gesichts-Crops) – zentrale Stelle für "endgültig löschen",
  /// genutzt von allen drei Aufrufstellen (normaler Papierkorb,
  /// automatisches Ablaufen, gesperrter Papierkorb). Vorher pflegte jede
  /// Stelle ihre eigene Kopie dieser Liste, wodurch z.B.
  /// [previewRelativePath] beim automatischen Ablaufen jahrelang vergessen
  /// wurde (orphaned Dateien) – ein Audit-Fund, den diese Konsolidierung
  /// strukturell ausschließen soll; ein späterer Audit-Fund war, dass
  /// [trimmedRelativePath]/[DevelopMasks.maskRelativePath] bei Einführung
  /// dieser Features hier nicht ergänzt wurden. Löscht bewusst NICHT die
  /// DB-Zeile selbst; das bleibt Sache des Aufrufers (unterschiedliche
  /// Batch-Strategien).
  Future<void> deleteAssetFilesFromDisk(AssetData asset) async {
    for (final relPath in await dateienVon(asset)) {
      await paths.deletePermanently(relPath);
    }
    await paths.deletePermanently(paths.vaultMetadataRelativePath(asset.id));
  }

  /// Prüft, ob im Papierkorb liegende Assets älter als das eingestellte
  /// Ablaufdatum sind, und löscht diese dann endgültig (Datei + DB-Zeile) –
  /// deaktiviert per Default (siehe [TrashSettings]). Läuft, wie das
  /// automatische Backup, nur während die App geöffnet ist.
  Future<void> purgeExpiredTrashIfDue() async {
    if (_trashPurgeRunning) return;
    final config = await db.trashSettingsRow();
    if (config == null || !config.autoDeleteEnabled) return;

    _trashPurgeRunning = true;
    try {
      final cutoff =
          DateTime.now().subtract(Duration(days: config.autoDeleteAfterDays));
      final expired = await db.expiredTrashAssets(cutoff);
      for (final asset in expired) {
        await deleteAssetFilesFromDisk(asset);
      }
      if (expired.isNotEmpty) {
        await db.deleteAssetRows(expired.map((a) => a.id).toList());
      }
      await db.setLastTrashPurgeAt(DateTime.now());
    } catch (e) {
      debugPrint('Automatisches Leeren des Papierkorbs fehlgeschlagen: $e');
    } finally {
      _trashPurgeRunning = false;
    }
  }

  @override
  void dispose() {
    _autoBackupTimer?.cancel();
    _trashPurgeTimer?.cancel();
    _ordnerTimer?.cancel();
    _modellFreigabeTimer?.cancel();
    super.dispose();
  }
}
