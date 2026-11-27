import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:kern/services/bildzuschnitt.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'entwicklung_ablegen.dart';
import 'hochskalieren.dart';
import 'hochskalieren_ablegen.dart';
import 'package:kern/services/modell_halter.dart';
import 'native_image_converter.dart';
import 'restore_service.dart';
import 'package:kern/services/storage_paths.dart';

/// Wie lange die Restaurierung noch braucht – `null`, solange sich das
/// nicht sagen lässt.
///
/// **Warum die Rechnung so einfach sein darf.** Real-ESRGAN zerlegt das
/// Bild in gleich große Kacheln und rechnet jede einzeln; die Dauer je
/// Kachel schwankt kaum. An dem einen echten Auftrag der Testbibliothek
/// gemessen: 20 Kacheln in 99 Sekunden, also rund fünf Sekunden je
/// Kachel. Aus den bereits erledigten Kacheln auf die verbleibenden zu
/// schließen ist deshalb keine Schätzung ins Blaue.
///
/// `null` kommt in drei Fällen: solange keine einzige Kachel fertig ist
/// (dann gibt es nichts, woraus sich rechnen liesse), solange die
/// Gesamtzahl noch nicht feststeht, und wenn der Auftrag keine Startzeit
/// trägt – das sind die Aufträge aus der Zeit vor Fassung 53.
///
/// **Nicht aus [RestoreJobData.createdAt] rechnen.** Das ist der Moment
/// des Einreihens; bei drei wartenden Aufträgen läge dazwischen eine
/// Stunde, und die Restzeit wäre um diese Stunde zu lang.
Duration? restzeitSchaetzung(RestoreJobData auftrag, {DateTime? jetzt}) {
  final start = auftrag.startedAt;
  if (start == null) return null;
  if (auftrag.tilesDone <= 0 || auftrag.tilesTotal <= 0) return null;
  if (auftrag.tilesDone >= auftrag.tilesTotal) return Duration.zero;
  final vergangen = (jetzt ?? DateTime.now()).difference(start);
  if (vergangen <= Duration.zero) return null;
  final jeKachel = vergangen.inMilliseconds / auftrag.tilesDone;
  final offen = auftrag.tilesTotal - auftrag.tilesDone;
  return Duration(milliseconds: (jeKachel * offen).round());
}

/// Der Fortschritt in Prozent, gerundet – `null`, solange die Gesamtzahl
/// der Kacheln nicht feststeht.
int? fortschrittProzent(RestoreJobData auftrag) {
  if (auftrag.tilesTotal <= 0) return null;
  return ((auftrag.tilesDone / auftrag.tilesTotal) * 100).round().clamp(0, 100);
}

/// Grund, an dem ein Restaurierungs-Auftrag gescheitert ist.
///
/// In der Datenbank steht der Name dieses Werts, nicht der fertige Satz:
/// Die Zeile überlebt einen Sprachwechsel, und ein Dienst ohne
/// BuildContext kann ohnehin nicht übersetzen. Die Zuordnung zum Text
/// steht im Warteschlangen-Bildschirm; Einträge aus älteren Fassungen
/// tragen dort noch den deutschen Satz und werden unverändert angezeigt.
enum RestaurierungsGrund {
  modellLaedtNicht,
  modellWeg,
  fotoWeg,
  gesperrt,
  aufloesungUnbekannt,
  nichtGerendert,
  nichtDekodiert,
  speicherbudget,

  /// Hochskalieren (#500): Das Ergebnis wäre grösser als
  /// [hochskalierMaxKante] oder [hochskalierMaxPixel]. Der Dialog sperrt
  /// solche Faktoren; hier kommt es an, wenn die Entwicklung das Foto
  /// seither grösser gemacht hat als beim Einreihen.
  zuGross,

  /// Hochskalieren (#500) gibt es nur für Fotos, nicht für Videos.
  keinFoto,

  /// Ein Auftrag, den diese Fassung nicht kennt – etwa ein Hochskalieren
  /// um einen Faktor, den erst eine spätere Fassung anbietet. Er läuft
  /// nicht, statt als Restaurierung die vorhandene zu ersetzen.
  unbekannteArt,
}

/// Woraus ein Hochskalieren rechnet (#500) – siehe
/// [RestoreQueueService.hochskalierVorlage].
enum Hochskalierquelle {
  /// Die gespeicherte Entwicklung des Originals.
  entwicklung,

  /// Das KI-Entrauschen oder die KI-Restaurierung, die das Foto zeigt.
  restaurierung,
}

/// Was der Dialog des Hochskalierens über die Vorlage wissen muss: ihre
/// Grösse (`null`, wenn unbekannt), woher sie kommt, und ob eine
/// Restaurierung übergangen wird, weil sie schon vergrössert ist.
typedef Hochskalierplan = ({
  int? breite,
  int? hoehe,
  Hochskalierquelle quelle,
  bool restaurierungUebergangen,
});

/// Fertig gerechnete Ergebnisse, die noch abgelegt werden müssen – je
/// Auftrag eine Datei im Ordner `auftragsergebnisse` der Bibliothek (#500).
///
/// **Warum.** Bis hierher lag ein fertiges Ergebnis nur im Speicher. Jeder
/// Fehler beim Ablegen verwarf es – ein Server, der kurz nicht erreichbar
/// war, ein Import, der scheiterte –, und wurde die App währenddessen
/// beendet, rechnete der Auftrag beim nächsten Start von vorn: Minuten
/// Rechenzeit für ein Ergebnis, das schon fertig war. Jetzt wird es
/// aufgehoben, bevor das Ablegen beginnt; ein weiterer Versuch (nach einem
/// Neustart oder über „Erneut versuchen“) legt es ab, ohne zu rechnen.
///
/// **Nicht im Temp-Ordner des Systems**: macOS leert ihn, auch binnen
/// Stunden. In der Bibliothek überlebt das Ergebnis jeden Neustart.
///
/// **Und nicht länger als nötig.** Es ist eine Klartextkopie des Fotos:
/// Sie geht weg, sobald der Auftrag fertig ist oder aus der Liste genommen
/// wird, wenn das Foto gesperrt wird ([RestoreQueueService.verwirfErgebnisseFuer])
/// oder das Ablegen daran scheitert, und beim Start alles, wozu es keinen
/// offenen Auftrag mehr gibt.
class Auftragsergebnisse {
  Auftragsergebnisse(this._paths);

  final StoragePaths _paths;

  Directory get ordner =>
      Directory(p.join(_paths.root.path, 'auftragsergebnisse'));

  /// Nur Kennungen, die sich gefahrlos als Dateiname nehmen lassen – die
  /// Warteschlange vergibt nur solche.
  static final _kennung = RegExp(r'^[A-Za-z0-9-]{1,128}$');

  File? _datei(String auftrag, String endung) => _kennung.hasMatch(auftrag)
      ? File(p.join(ordner.path, '$auftrag$endung'))
      : null;

  /// Das aufgehobene Ergebnis von [auftrag] – `null`, wenn es keines gibt
  /// oder es kein JPEG ist.
  Future<Uint8List?> lies(String auftrag) async {
    final f = _datei(auftrag, '.jpg');
    if (f == null || !await f.exists()) return null;
    final bytes = await f.readAsBytes();
    if (jpegMasse(bytes) != null) return bytes;
    await verwirf(auftrag);
    return null;
  }

  /// Hebt [jpeg] für [auftrag] auf – erst unter einem Zwischennamen, dann
  /// umbenannt: Ein halb geschriebenes Ergebnis gilt nie als fertig.
  Future<void> lege(String auftrag, Uint8List jpeg) async {
    final f = _datei(auftrag, '.jpg');
    if (f == null) return;
    await ordner.create(recursive: true);
    final teil = File('${f.path}.teil');
    await teil.writeAsBytes(jpeg, flush: true);
    await teil.rename(f.path);
  }

  /// Wo ein angefangenes Hochladen des Ergebnisses steht (siehe
  /// [Hochskalierablage.hochladeort]).
  Future<String?> hochladeort(String auftrag) async {
    final f = _datei(auftrag, '.ort');
    if (f == null || !await f.exists()) return null;
    final ort = (await f.readAsString()).trim();
    return ort.isEmpty ? null : ort;
  }

  /// Synchron: Das Hochladen meldet den Ort, bevor es das erste Stück
  /// schickt, und soll danach nicht auf die Platte warten.
  void merkeHochladeort(String auftrag, String ort) {
    final f = _datei(auftrag, '.ort');
    if (f == null) return;
    try {
      ordner.createSync(recursive: true);
      f.writeAsStringSync(ort, flush: true);
    } on FileSystemException catch (e) {
      // Ohne Ort beginnt ein weiterer Versuch eben von vorn.
      debugPrint('Hochladeort nicht gemerkt: $e');
    }
  }

  Future<void> verwirf(String auftrag) async {
    for (final endung in ['.jpg', '.jpg.teil', '.ort']) {
      final f = _datei(auftrag, endung);
      if (f != null && await f.exists()) await f.delete();
    }
  }

  /// Löscht alles, was zu keinem der [behalten]en Aufträge gehört.
  Future<void> raeumeAuf(Set<String> behalten) async {
    if (!await ordner.exists()) return;
    await for (final e in ordner.list()) {
      final name = p.basename(e.path);
      final auftrag = name.substring(
        0,
        name.indexOf('.').clamp(0, name.length),
      );
      if (!behalten.contains(auftrag)) await e.delete(recursive: true);
    }
  }
}

/// Geworfen, wenn das Modell fehlt – der Aufrufer zeigt seinen eigenen,
/// übersetzten Hinweis.
class RestaurierungNichtVerfuegbar implements Exception {
  const RestaurierungNichtVerfuegbar();
}

/// Persistierte Hintergrund-Warteschlange für KI-Restaurierung (siehe
/// RestoreService, RestoreJobs) – ein Auftrag läuft oft mehrere Minuten
/// (echt gemessen: ~5 Min. bei 12 MP mit CoreML), daher bewusst NICHT als
/// blockierender Dialog, sondern als Warteschlange, die der Nutzer anstößt
/// und dann in der App weiterarbeitet. Verarbeitet **einen Auftrag
/// gleichzeitig** – mehrere parallele ONNX-Inferenzen würden sich nur um
/// CPU/GPU streiten. Lebt auf [LibraryState] wie `importService`/
/// `backupService`.
class RestoreQueueService {
  RestoreQueueService(this._db, this._paths, {this.waitForIdle = false});

  final AppDatabase _db;
  final StoragePaths _paths;

  /// Die Produktionsinstanz wartet auf Leerlauf. Der Standard bleibt für
  /// gezielte Dienst-Aufrufe sofortig, damit ein explizites `enqueue()` in
  /// einem Kommando oder Test genau die bisherige Semantik behält.
  final bool waitForIdle;

  /// Von außen gesetzt, sobald bekannt ist, ob das Modell installiert ist
  /// (Muster: LibraryState._loadModelsIfPresent, analog zu
  /// `segmentationHalter`) – lädt die ONNX-Sitzung erst beim ersten
  /// tatsächlichen Auftrag ([_process] leiht sie sich dort). Ohne Halter
  /// (App noch nicht initialisiert) bleibt die Warteschlange nutzbar für
  /// bereits vorhandene Aufträge, [enqueue] schlägt aber fehl.
  ModellHalter<RestoreService>? restoreHalter;

  /// Das Modell für das KI-Entrauschen (#275) – hier, weil es dieselbe
  /// Vorlage braucht ([entwickeltesJpeg]) und sein Ergebnis gleich abgelegt
  /// wird ([legeRestauriertAb]). Es läuft nicht über die Warteschlange.
  ModellHalter<Entrauschdienst>? entrauschHalter;

  /// Legt das Ergebnis eines Hochskalier-Auftrags (#500) als Variante neben
  /// sein Original und gibt die Kennung der neuen Aufnahme zurück – `null`,
  /// wenn genau diese Datei schon da war und nicht mehr eingeordnet werden
  /// konnte.
  ///
  /// Von aussen gesetzt wie [restoreHalter]: [LibraryState] weiss, ob die
  /// Bibliothek mit einem Server verbunden ist (dann geht die Datei dorthin)
  /// und was nach einem Import noch zu tun ist. Ohne ihn importiert die
  /// Warteschlange selbst in diese Bibliothek – so laufen die Prüfstände.
  ///
  /// Bekommt die Datei samt Abbruch und Hochladeort ([Hochskalierablage]).
  Future<String?> Function(Hochskalierablage ablage)? hochskaliertAblegen;

  /// Siehe [Auftragsergebnisse].
  late final ergebnisse = Auftragsergebnisse(_paths);

  bool _processing = false;
  String? _activeJobId;
  final Set<String> _cancelRequested = {};
  Timer? _idleTimer;
  Future<void>? _ablage;

  /// Der gerade rechnende Lauf – zum Anhalten, Fortsetzen und Abbrechen.
  Restaurierungslauf? _lauf;

  /// Eine Restaurierung belegt CPU, GPU und mehrere grosse Bildpuffer. Sie
  /// beginnt deshalb erst nach einer kurzen ruhigen Phase, hält bei neuer
  /// Eingabe nach der laufenden Kachel an und macht nach der nächsten
  /// ruhigen Phase an derselben Stelle weiter (siehe [Restaurierungslauf]).
  static const idleDelay = Duration(seconds: 20);
  bool _idle = false;

  /// Ob gerade ein Auftrag verarbeitet wird – für die Duplikat-Prüfung in
  /// [enqueue]/[cancel]. Ein Ersetzen von [restoreHalter] durch
  /// LibraryState.reloadModels() während eines laufenden Auftrags ist
  /// unproblematisch: [_process] hält seine eigene lokale Referenz auf den
  /// Halter, von dem es geliehen hat (siehe dort), die Nutzerzähler-Logik in
  /// ModellHalter verhindert ein Entsorgen mitten in der Inferenz strukturell.
  bool get isProcessing => _processing;

  /// Legt einen neuen Auftrag an und stößt die Verarbeitung an (falls
  /// gerade nichts läuft). Wirft, wenn kein Modell geladen ist – der
  /// Aufrufer (UI) sollte den Knopf dafür ohnehin deaktivieren. Ist für
  /// dasselbe Asset bereits ein wartender/laufender Auftrag vorhanden, wird
  /// dessen ID zurückgegeben statt eines Duplikats – ohne diese Prüfung
  /// würde ein Doppelklick (oder mehrfaches Anstoßen aus verschiedenen
  /// Screens) denselben mehrminütigen Auftrag mehrfach redundant laufen
  /// lassen.
  Future<String> enqueue(String assetId) =>
      _legeAn(assetId, faktor: null, id: const Uuid().v4());

  /// Reiht das Hochskalieren von [assetId] um [faktor] ein (#500) – in
  /// dieselbe Warteschlange wie die Restaurierung, als Auftrag, dessen
  /// Kennung den Faktor trägt (siehe [hochskalierAuftragsId]).
  ///
  /// **Warum hier und nicht als eigener Lauf.** Beides rechnet dasselbe
  /// Modell mit denselben grossen Kachelpuffern. Nebeneinander stritten sie
  /// sich um CPU, GPU und Speicher, und zwei Sitzungen desselben Netzes
  /// lägen gleichzeitig im Speicher; so läuft auch hier ein Auftrag nach
  /// dem anderen. Das Hochskalieren übernimmt damit auch das Übrige: Es
  /// beginnt nach einer ruhigen Phase, hält bei Bedienung nach der
  /// laufenden Kachel an, überlebt das Schliessen des Vollbilds und einen
  /// Neustart, und Band und Warteschlangen-Bildschirm zeigen es an.
  ///
  /// Derselbe Faktor für dasselbe Foto wird nicht doppelt eingereiht; ein
  /// anderer Faktor oder eine Restaurierung desselben Fotos schon.
  Future<String> hochskalieren(String assetId, int faktor) {
    if (!hochskalierFaktoren.contains(faktor)) {
      throw ArgumentError.value(faktor, 'faktor');
    }
    return _legeAn(assetId, faktor: faktor, id: hochskalierAuftragsId(faktor));
  }

  Future<String> _legeAn(
    String assetId, {
    required int? faktor,
    required String id,
  }) async {
    if (_beendet || restoreHalter?.installiert != true) {
      throw const RestaurierungNichtVerfuegbar();
    }
    final existing = await _aktiverAuftrag(assetId, faktor);
    if (existing != null) return existing.id;
    if (_beendet) throw const RestaurierungNichtVerfuegbar();

    await _db.createRestoreJob(
      RestoreJobsCompanion.insert(
        id: id,
        assetId: assetId,
        status: 'queued',
        createdAt: DateTime.now(),
      ),
    );
    if (waitForIdle) {
      _warteAufLeerlauf();
    } else {
      _idle = true;
      unawaited(_maybeStartNext());
    }
    return id;
  }

  /// Der wartende oder laufende Auftrag derselben Art für [assetId] – eine
  /// Restaurierung bei [faktor] `null`, sonst ein Hochskalieren um genau
  /// diesen Faktor. Nicht mehr [AppDatabase.activeRestoreJobForAsset]: Die
  /// fragt nach irgendeinem Auftrag des Fotos, und ein wartendes
  /// Hochskalieren hätte eine Restaurierung desselben Fotos verschluckt.
  Future<RestoreJobData?> _aktiverAuftrag(String assetId, int? faktor) async {
    final aktiv =
        await (_db.select(_db.restoreJobs)..where(
              (t) =>
                  t.assetId.equals(assetId) &
                  t.status.isIn(const ['queued', 'running']),
            ))
            .get();
    // Nach der Art, nicht nur nach dem Faktor: Ein Hochskalieren mit einem
    // unbekannten Faktor hat den Faktor `null` wie eine Restaurierung.
    return aktiv
        .where(
          (j) =>
              istHochskalierauftrag(j.id) == (faktor != null) &&
              hochskalierfaktor(j.id) == faktor,
        )
        .firstOrNull;
  }

  /// Ein noch wartender Auftrag wird sofort entfernt; ein gerade laufender
  /// wird zwischen Kacheln abgebrochen (siehe [RestoreService.restore]s
  /// `isCancelled`) und dann als `cancelled` markiert, OHNE ein
  /// unvollständiges Ergebnis zu speichern.
  Future<void> cancel(String jobId) async {
    if (_beendet) return;
    if (jobId == _activeJobId) {
      _cancelRequested.add(jobId);
      _lauf?.abbrechen();
    } else {
      await entferne(jobId);
    }
  }

  /// Nimmt einen Auftrag, der nicht gerade läuft, aus der Liste – samt
  /// seinem aufgehobenen Ergebnis (siehe [Auftragsergebnisse]).
  Future<void> entferne(String jobId) async {
    if (_beendet || jobId == _activeJobId) return;
    await _db.deleteRestoreJob(jobId);
    await _verwirfErgebnis(jobId);
  }

  /// Reiht einen gescheiterten oder abgebrochenen Auftrag noch einmal ein.
  /// Liegt sein Ergebnis schon vor (siehe [Auftragsergebnisse]), wird nur
  /// noch abgelegt. Wartet schon ein Auftrag derselben Art für dasselbe
  /// Foto, bleibt es bei dem.
  Future<void> wiederholen(String jobId) async {
    if (_beendet) return;
    final job = await (_db.select(
      _db.restoreJobs,
    )..where((t) => t.id.equals(jobId))).getSingleOrNull();
    if (job == null || (job.status != 'failed' && job.status != 'cancelled')) {
      return;
    }
    final art = istHochskalierauftrag(job.id);
    final faktor = hochskalierfaktor(job.id);
    if (!art || faktor != null) {
      if (await _aktiverAuftrag(job.assetId, faktor) != null) return;
    }
    await _db.requeueRestoreJob(jobId);
    if (waitForIdle) {
      _warteAufLeerlauf();
    } else {
      _idle = true;
      unawaited(_maybeStartNext());
    }
  }

  /// Verwirft die aufgehobenen Ergebnisse aller Aufträge zu [assetIds] –
  /// beim Sperren: Eine Klartextkopie eines gesperrten Fotos darf nicht
  /// liegen bleiben, bis jemand den Auftrag aus der Liste nimmt.
  Future<void> verwirfErgebnisseFuer(List<String> assetIds) async {
    if (assetIds.isEmpty) return;
    final auftraege = await (_db.select(
      _db.restoreJobs,
    )..where((t) => t.assetId.isIn(assetIds))).get();
    for (final a in auftraege) {
      await _verwirfErgebnis(a.id);
    }
  }

  /// Räumt beim Start auf, was kein offener Auftrag mehr braucht: Ergebnisse
  /// ohne Auftrag, fertiger Aufträge und solcher, deren Foto inzwischen
  /// gesperrt, gelöscht oder im Papierkorb ist.
  Future<void> _raeumeErgebnisseAuf() async {
    if (_beendet) return;
    try {
      final behalten = <String>{};
      for (final a in await _db.select(_db.restoreJobs).get()) {
        if (_beendet) return;
        if (a.status == 'done') continue;
        final foto = await _db.assetById(a.assetId);
        if (foto != null && !foto.isLocked && !foto.isTrashed) {
          behalten.add(a.id);
        }
      }
      if (_beendet) return;
      await ergebnisse.raeumeAuf(behalten);
    } catch (e) {
      debugPrint('Aufgehobene Ergebnisse nicht aufgeräumt: $e');
    }
  }

  /// Wird von der App-Hülle für Zeigen, Scrollen und Tippen aufgerufen.
  /// Ein laufender Auftrag beendet seine aktuelle Kachel und wartet dann,
  /// bis die App [idleDelay] lang unbenutzt ist – mit allem schon
  /// Gerechneten. Vorher wurde er hier verworfen und neu eingereiht; ein
  /// Foto mit sechzig Kacheln wurde so nie fertig, solange jemand mit der
  /// App arbeitete.
  void noteUserInteraction() {
    if (_beendet) return;
    _idle = false;
    _idleTimer?.cancel();
    _lauf?.pausieren();
    _idleTimer = Timer(idleDelay, () {
      _idle = true;
      _lauf?.fortsetzen();
      unawaited(_maybeStartNext());
    });
  }

  /// Stößt die Verarbeitung an, falls Aufträge warten und gerade nichts
  /// läuft – aufgerufen beim App-Start (nach [AppDatabase.resetStuckRunningRestoreJobs],
  /// siehe LibraryState.initialize) für Aufträge, die aus der letzten
  /// Sitzung noch offen sind.
  /// Startet ausdrücklich sofort, etwa nach einem manuellen Fortsetzen.
  /// Der App-Start verwendet dagegen [resumeWhenIdle], damit eine beim
  /// Beenden unterbrochene Restaurierung nicht gleich beim nächsten Öffnen
  /// wieder die Bedienung belegt.
  Future<void> resume() {
    if (_beendet) return Future<void>.value();
    _idle = true;
    return _maybeStartNext();
  }

  Future<void> resumeWhenIdle() {
    if (_beendet) return Future<void>.value();
    unawaited(_raeumeErgebnisseAuf());
    _warteAufLeerlauf();
    return Future<void>.value();
  }

  void _warteAufLeerlauf() {
    if (_beendet) return;
    // Ein neu angelegter Auftrag muss nicht zwingend eine weitere Eingabe
    // abwarten, wenn die App schon lange still ist. Beim Start gilt die
    // gleiche Regel trotzdem: Erst nach [idleDelay] darf Rechenarbeit los.
    if (_idle) {
      unawaited(_maybeStartNext());
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(idleDelay, () {
      _idle = true;
      unawaited(_maybeStartNext());
    });
  }

  /// Hält die Warteschlange an und bricht die laufende Inferenz ab.
  /// Die Aufträge bleiben beim Beenden offen und werden beim Neustart
  /// wieder eingereiht. Eine begonnene Restaurierung darf fertig abgelegt
  /// werden; ein Hochskalieren bricht am nächsten sicheren Schritt ab (auch
  /// mitten im Hochladen) und legt beim nächsten Start die aufgehobene Datei
  /// ab (siehe [Auftragsergebnisse]) – vorher schloss die Datenbank nach
  /// drei Sekunden mitten im Import.
  Future<void> beende() async {
    _beendet = true;
    _idle = false;
    _idleTimer?.cancel();
    _idleTimer = null;
    _lauf?.abbrechen();
    try {
      await _ablage?.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      rethrow;
    } catch (_) {
      // Wie das Ablegen endet, vermerkt der Auftrag selbst (siehe
      // [_process]); hier zählt nur, dass es zu Ende ist.
    } finally {
      _ablagefristAbgelaufen = true;
    }
  }

  bool _beendet = false;

  Future<void> _maybeStartNext() async {
    // _processing wird bewusst VOR dem ersten await gesetzt (statt erst
    // nachdem [nextQueuedRestoreJob] zurückkommt) – Audit-Fund: zwei
    // schnell aufeinanderfolgende Aufrufe (z.B. zwei enqueue()s in
    // Folge) würden sonst beide die DB-Abfrage starten, bevor einer von
    // beiden _processing setzt, und so zwei Aufträge parallel verarbeiten
    // (verdoppelte CPU/GPU-Last, doppelter Speicherbedarf für die
    // Kachel-Puffer) statt der vorgesehenen Ein-Auftrag-gleichzeitig-Regel.
    if (_beendet || _processing || !_idle) return;
    _processing = true;
    try {
      final next = await _db.nextQueuedRestoreJob();
      if (_beendet || next == null) return;
      _activeJobId = next.id;
      try {
        await _process(next);
      } finally {
        _cancelRequested.remove(next.id);
        _activeJobId = null;
        _lauf = null;
      }
    } finally {
      _processing = false;
    }
    if (_idle) unawaited(_maybeStartNext());
  }

  Future<void> _process(RestoreJobData job) async {
    // Ein Hochskalier-Auftrag (#500) trägt seinen Faktor in der Kennung.
    final faktor = hochskalierfaktor(job.id);
    if (istHochskalierauftrag(job.id) && faktor == null) {
      await _status(
        job.id,
        'failed',
        errorMessage: RestaurierungsGrund.unbekannteArt.name,
      );
      return;
    }
    // Schon gerechnet und nur nicht abgelegt: dann ohne Modell weiter.
    Uint8List? fertig;
    try {
      fertig = await ergebnisse.lies(job.id);
    } on FileSystemException catch (e) {
      debugPrint('Aufgehobenes Ergebnis nicht lesbar: $e');
    }
    // Lokal einfangen statt später erneut über das Feld zu gehen: Ersetzt
    // LibraryState.reloadModels() [restoreHalter] mitten in der Verarbeitung
    // (neuer Modell-Download), soll [zurueckgeben] weiterhin auf DIESEM
    // (dann "retirierten", aber noch gültigen) Halter aufgerufen werden –
    // sonst bliebe sein Nutzerzähler für immer > 0 und er würde nie entsorgt.
    final halter = restoreHalter;
    RestoreService? service;
    if (fertig == null) {
      try {
        service = await halter?.leihen();
      } catch (e) {
        // Ohne dieses try/catch verließ eine Ladefehler-Exception (z.B. eine
        // beschädigte Modelldatei) _process() unbehandelt – der Auftrag blieb
        // für immer auf "queued" stehen UND das nachfolgende
        // unawaited(_maybeStartNext()) in _maybeStartNext() wurde nie
        // erreicht, wodurch die gesamte Warteschlange dauerhaft blockierte
        // (Audit-Fund).
        await _status(
          job.id,
          'failed',
          // Kennung UND Ursache: Die Kennung wird übersetzt, die Ursache
          // dahinter ist das, was bei einem Fehlerbericht wirklich hilft.
          errorMessage: '${RestaurierungsGrund.modellLaedtNicht.name}: $e',
        );
        return;
      }
      if (service == null) {
        await _status(
          job.id,
          'failed',
          errorMessage: RestaurierungsGrund.modellWeg.name,
        );
        return;
      }
    }
    try {
      if (_beendet) return;
      await _status(job.id, 'running');
      if (_beendet) return;
      final asset = await _db.assetById(job.assetId);
      if (_beendet) return;
      if (asset == null) {
        await _verwirfErgebnis(job.id);
        await _status(
          job.id,
          'failed',
          errorMessage: RestaurierungsGrund.fotoWeg.name,
        );
        return;
      }
      if (asset.isLocked) {
        await _verwirfErgebnis(job.id);
        await _status(
          job.id,
          'failed',
          errorMessage: RestaurierungsGrund.gesperrt.name,
        );
        return;
      }
      if (faktor != null && (asset.type != 'IMAGE' || asset.isTrashed)) {
        await _verwirfErgebnis(job.id);
        await _status(
          job.id,
          'failed',
          errorMessage: asset.isTrashed
              ? RestaurierungsGrund.fotoWeg.name
              : RestaurierungsGrund.keinFoto.name,
        );
        return;
      }
      final ergebnis = fertig ?? await _rechne(job, asset, faktor, service!);
      if (_beendet || ergebnis == null) return;

      final ablage = faktor == null
          ? _speichereErgebnis(job, ergebnis)
          : _speichereHochskaliert(job, faktor, ergebnis);
      _ablage = ablage;
      try {
        await ablage;
      } finally {
        _ablage = null;
      }
    } on AblageAbgebrochen {
      // Beim Beenden: Der Auftrag bleibt offen, das Ergebnis aufgehoben.
    } on AufnahmeNichtAblegbar catch (e) {
      // Während des Rechnens gesperrt oder gelöscht (#430): Das Ergebnis
      // ist verworfen, nichts liegt im Klartext im gesperrten Foto – auch
      // nicht unter den aufgehobenen Ergebnissen.
      await _verwirfErgebnis(job.id);
      await _status(
        job.id,
        'failed',
        errorMessage: e.gesperrt
            ? RestaurierungsGrund.gesperrt.name
            : RestaurierungsGrund.fotoWeg.name,
      );
    } catch (e) {
      // Das Ergebnis bleibt aufgehoben: „Erneut versuchen“ legt es ab, ohne
      // noch einmal zu rechnen.
      await _status(
        job.id,
        'failed',
        errorMessage: e.toString().contains('pv_kachel_speicher:')
            ? RestaurierungsGrund.speicherbudget.name
            : e.toString(),
      );
    } finally {
      if (service != null) {
        halter!.zurueckgeben();
        if (_beendet) await halter.freigebenWennUnbenutzt();
      }
    }
  }

  /// Rechnet [job] und hebt das Ergebnis auf (siehe [Auftragsergebnisse]).
  /// `null`, wenn nichts abzulegen ist – der Grund steht dann schon am
  /// Auftrag, oder die App wird beendet.
  Future<Uint8List?> _rechne(
    RestoreJobData job,
    AssetData asset,
    int? faktor,
    RestoreService service,
  ) async {
    final targetWidth = asset.widthPx;
    final targetHeight = asset.heightPx;
    if (targetWidth == null || targetHeight == null) {
      await _status(
        job.id,
        'failed',
        errorMessage: RestaurierungsGrund.aufloesungUnbekannt.name,
      );
      return null;
    }

    final jpegBytes = faktor == null
        ? await entwickeltesJpeg(asset)
        : await hochskalierVorlage(asset);
    if (_beendet) return null;
    if (jpegBytes == null) {
      await _status(
        job.id,
        'failed',
        errorMessage: RestaurierungsGrund.nichtGerendert.name,
      );
      return null;
    }
    if (faktor != null) {
      // Gemessen wird, was wirklich gerechnet wird: Die Entwicklung kann
      // das Foto seit dem Einreihen beschnitten oder gedreht haben.
      final masse = jpegMasse(jpegBytes);
      if (masse == null) {
        await _status(
          job.id,
          'failed',
          errorMessage: RestaurierungsGrund.nichtDekodiert.name,
        );
        return null;
      }
      if (hochskalierziel(masse.breite, masse.hoehe, faktor).sperre != null) {
        await _status(
          job.id,
          'failed',
          errorMessage: RestaurierungsGrund.zuGross.name,
        );
        return null;
      }
    }
    // Absichtlich nicht awaited (der Fortschritt darf die Inferenz
    // nicht ausbremsen) – catchError statt eines unbehandelten
    // Future-Fehlers, falls der DB-Schreibzugriff einmal transient
    // fehlschlägt.
    void fortschritt(int done, int total) {
      if (!_beendet) {
        unawaited(
          _db.updateRestoreJobProgress(job.id, done, total).catchError((_) {}),
        );
      }
    }

    // Dekodieren, Kacheln, Zusammensetzen und das JPEG schreiben laufen
    // im Isolat des Laufs, nicht auf dem Faden der Oberfläche (#14).
    final lauf = faktor == null
        ? service.starteJpeg(jpegBytes, quality: 92, onProgress: fortschritt)
        : service.starteHochskalieren(
            jpegBytes,
            faktor: faktor,
            quality: 92,
            onProgress: fortschritt,
          );
    _lauf = lauf;
    // Kam in der Zwischenzeit eine Eingabe, wartet er von Anfang an.
    if (!_idle) lauf.pausieren();
    if (_cancelRequested.contains(job.id)) lauf.abbrechen();
    var ergebnis = await lauf.ergebnis;
    // Ein spätes Ergebnis nach dem Beenden zählt nicht: Der Lauf war
    // abgebrochen.
    if (_beendet) return null;

    if (_cancelRequested.contains(job.id)) {
      await _status(job.id, 'cancelled');
      return null;
    }
    if (ergebnis == null) {
      await _status(
        job.id,
        'failed',
        errorMessage: RestaurierungsGrund.nichtDekodiert.name,
      );
      return null;
    }
    if (faktor != null) ergebnis = mitHochskalierangaben(ergebnis, asset);
    try {
      await ergebnisse.lege(job.id, ergebnis);
    } on FileSystemException catch (e) {
      // Ohne Platz zum Aufheben wird trotzdem abgelegt – nur ein weiterer
      // Versuch müsste dann wieder rechnen.
      debugPrint('Ergebnis nicht aufgehoben: $e');
    }
    return ergebnis;
  }

  /// [Auftragsergebnisse.verwirf], ohne dass ein Fehler der Platte den
  /// Auftrag aufhält.
  Future<void> _verwirfErgebnis(String id) async {
    try {
      await ergebnisse.verwirf(id);
    } on FileSystemException catch (e) {
      debugPrint('Aufgehobenes Ergebnis nicht gelöscht: $e');
    }
  }

  Future<void> _status(String id, String status, {String? errorMessage}) async {
    if (_beendet) return;
    await _db.markRestoreJobStatus(id, status, errorMessage: errorMessage);
  }

  Future<void> _speichereErgebnis(RestoreJobData job, Uint8List jpeg) async {
    await legeRestaurierungAb(
      db: _db,
      paths: _paths,
      assetId: job.assetId,
      jpeg: jpeg,
      abgebrochen: () => _ablagefristAbgelaufen,
    );
    if (!_ablagefristAbgelaufen) {
      await _db.markRestoreJobStatus(job.id, 'done');
      await _verwirfErgebnis(job.id);
    }
  }

  /// Legt das Ergebnis eines Hochskalier-Auftrags ab (siehe
  /// [hochskaliertAblegen]) und schliesst den Auftrag. Ist das Original
  /// inzwischen gesperrt oder gelöscht, wirft das Ablegen
  /// [AufnahmeNichtAblegbar], und [_process] vermerkt den Grund – wie bei
  /// einer Restaurierung (#430).
  ///
  /// Beim Beenden bricht das Ablegen am nächsten sicheren Schritt ab
  /// ([Hochskalierablage.abgebrochen]); ein angefangenes Hochladen geht beim
  /// nächsten Versuch dort weiter, wo es stand.
  Future<void> _speichereHochskaliert(
    RestoreJobData job,
    int faktor,
    Uint8List jpeg,
  ) async {
    final ablegen =
        hochskaliertAblegen ??
        (Hochskalierablage ablage) => legeHochskaliertAb(
          db: _db,
          paths: _paths,
          importe: ImportService(_db, _paths),
          ablage: ablage,
        );
    if (_beendet) return;
    await ablegen(
      Hochskalierablage(
        originalId: job.assetId,
        jpeg: jpeg,
        faktor: faktor,
        abgebrochen: () => _beendet,
        hochladeort: await ergebnisse.hochladeort(job.id),
        hochladeortMerken: (ort) => ergebnisse.merkeHochladeort(job.id, ort),
      ),
    );
    if (!_ablagefristAbgelaufen) {
      await _db.markRestoreJobStatus(job.id, 'done');
      await _verwirfErgebnis(job.id);
    }
  }

  // LibraryState schließt die DB auch dann, wenn die Ablage festhängt.
  // In diesem Fall darf ein später fortgesetzter Schreibweg die DB nicht
  // mehr verwenden. Der Auftrag bleibt beim nächsten Start wiederholbar.
  bool _ablagefristAbgelaufen = false;

  /// Das Foto so, wie es entwickelt ist (Regler und Masken), in voller
  /// Auflösung als JPEG – die Vorlage für die Restaurierung und für das
  /// KI-Entrauschen (#275). `null`, wenn es sich nicht rendern liess.
  Future<Uint8List?> entwickeltesJpeg(AssetData asset) async {
    // Ohne bekannte Grösse: so gross, wie der Wandler es hergibt.
    final kante = math.max(asset.widthPx ?? 0, asset.heightPx ?? 0);
    // Eingabe: das bereits entwickelte Bild (aktuelle Regler/Masken) in
    // voller Auflösung über den nativen Kanal – das `image`-Dart-Paket
    // kann RAW-Originale nicht selbst dekodieren (siehe DevelopScreen).
    if (_beendet) return null;
    final settings = await _db.developSettingsForAsset(asset.id);
    if (_beendet) return null;
    // Alle Regler, auch Kurve, Mischer und Farbtabelle – bis 3.51 nur die
    // acht Grundregler, und die Vorlage wich vom entwickelten Bild ab (#283).
    final adjustments = settings == null
        ? DevelopAdjustments.neutral
        : reglerAusEinstellungen(
            settings,
            lut: await ladeFarbtabelle(_paths, settings.lutPath),
          );
    if (_beendet) return null;
    final masks = await _db.masksForAsset(asset.id);
    if (_beendet) return null;
    final maskLayers = [
      for (final m in masks)
        MaskAdjustmentLayer(
          maskFilePath: (await _paths.bereit(m.maskRelativePath)).path,
          adjustments: DevelopAdjustments(
            exposure: m.exposure,
            temperature: m.temperature,
            tint: m.tint,
            contrast: m.contrast,
            shadows: m.shadows,
            highlights: m.highlights,
            sharpness: m.sharpness,
            noiseReduction: m.noiseReduction,
          ),
        ),
    ];

    final sourceFile = (await _paths.bereit(asset.relativePath));
    final jpegBytes = await NativeImageConverter.developImage(
      sourceFile,
      adjustments: adjustments,
      masks: maskLayers,
      maxDimension: kante > 0 ? kante : 16384,
      quality: 0.95,
    );
    return jpegBytes;
  }

  /// Die Vorlage des Hochskalierens (#500): das Foto, wie es angezeigt
  /// wird.
  ///
  /// **Erst entrauschen, dann vergrössern.** Bis hierher rechnete das
  /// Hochskalieren immer aus der gespeicherten Entwicklung des Originals,
  /// auch wenn das Foto ein KI-Entrauschen trug: Wer erst entrauschte und
  /// dann vergrösserte, bekam die verrauschte Fassung vergrössert. Liegt
  /// eine Restaurierung in Originalgrösse vor – so gross wie das Original
  /// oder kleiner, also ein Entrauschen der (womöglich beschnittenen)
  /// Entwicklung –, ist sie die Vorlage; sie zeigt auch die Anzeige, und sie
  /// trägt die Entwicklung, aus der sie gerechnet wurde.
  ///
  /// Eine KI-Restaurierung mit Real-ESRGAN ist schon vierfach vergrössert;
  /// sie noch einmal zu vergrössern sprengte jede Grenze. Dann bleibt es bei
  /// der Entwicklung, und der Dialog sagt das ([hochskalierplan]).
  Future<Uint8List?> hochskalierVorlage(AssetData asset) async {
    final restauriert = await _restaurierungAlsVorlage(asset);
    if (restauriert != null) return restauriert.datei.readAsBytes();
    return entwickeltesJpeg(asset);
  }

  /// Was [hochskalierVorlage] nehmen wird, und wie gross das ist – für den
  /// Dialog, ohne etwas zu rendern: Bei der Entwicklung sind es die Masse
  /// des Originals nach dem gespeicherten Zuschnitt und seiner Drehung
  /// ([masseNachZuschnitt]); bisher rechnete der Dialog mit dem
  /// unbeschnittenen Original, und ein Faktor, den er anbot, scheiterte
  /// erst in der Warteschlange.
  Future<Hochskalierplan> hochskalierplan(AssetData asset) async {
    final restauriert = await _restaurierungAlsVorlage(asset);
    if (restauriert != null) {
      return (
        breite: restauriert.masse.breite,
        hoehe: restauriert.masse.hoehe,
        quelle: Hochskalierquelle.restaurierung,
        restaurierungUebergangen: false,
      );
    }
    final uebergangen = asset.restoredRelativePath != null;
    final b = asset.widthPx, h = asset.heightPx;
    if (b == null || h == null || b <= 0 || h <= 0) {
      return (
        breite: null,
        hoehe: null,
        quelle: Hochskalierquelle.entwicklung,
        restaurierungUebergangen: uebergangen,
      );
    }
    var zuschnitt = Bildzuschnitt.ganz;
    try {
      zuschnitt = Bildzuschnitt.aus(
        (await _db.developSettingsForAsset(asset.id))?.cropJson,
      );
    } on FormatException {
      // Ein unlesbarer Zuschnitt: so, wie das Entwickeln ihn auch nähme.
    }
    final m = masseNachZuschnitt(zuschnitt, b, h);
    return (
      breite: m.breite,
      hoehe: m.hoehe,
      quelle: Hochskalierquelle.entwicklung,
      restaurierungUebergangen: uebergangen,
    );
  }

  /// Die Restaurierung von [asset], wenn sie als Vorlage taugt (siehe
  /// [hochskalierVorlage]), samt ihren Massen aus dem Kopf der Datei.
  Future<({File datei, ({int breite, int hoehe}) masse})?>
  _restaurierungAlsVorlage(AssetData asset) async {
    final relativ = asset.restoredRelativePath;
    final kante = math.max(asset.widthPx ?? 0, asset.heightPx ?? 0);
    if (relativ == null || kante <= 0) return null;
    try {
      final datei = await _paths.bereit(relativ);
      final masse = await jpegMasseAusDatei(datei);
      if (masse == null || math.max(masse.breite, masse.hoehe) > kante) {
        return null;
      }
      return (datei: datei, masse: masse);
    } on Exception catch (e) {
      // Nicht zu holen oder nicht zu lesen: dann aus der Entwicklung.
      debugPrint('Restaurierung als Vorlage nicht lesbar: $e');
      return null;
    }
  }

  /// Legt [jpeg] als Restaurierung von [assetId] ab – so, wie die
  /// Warteschlange ein Ergebnis ablegt, nur ohne Auftrag (das
  /// KI-Entrauschen läuft im Entwickeln selbst, #275).
  Future<void> legeRestauriertAb(String assetId, Uint8List jpeg) =>
      legeRestaurierungAb(db: _db, paths: _paths, assetId: assetId, jpeg: jpeg);
}
