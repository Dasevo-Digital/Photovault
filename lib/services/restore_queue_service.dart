import 'dart:async';

import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'bilddekodierung.dart';
import 'modell_halter.dart';
import 'native_image_converter.dart';
import 'restore_service.dart';
import 'storage_paths.dart';

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
Duration? restzeitSchaetzung(
  RestoreJobData auftrag, {
  DateTime? jetzt,
}) {
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
  RestoreQueueService(this._db, this._paths);

  final AppDatabase _db;
  final StoragePaths _paths;

  /// Von außen gesetzt, sobald bekannt ist, ob das Modell installiert ist
  /// (Muster: LibraryState._loadModelsIfPresent, analog zu
  /// `segmentationHalter`) – lädt die ONNX-Sitzung erst beim ersten
  /// tatsächlichen Auftrag ([_process] leiht sie sich dort). Ohne Halter
  /// (App noch nicht initialisiert) bleibt die Warteschlange nutzbar für
  /// bereits vorhandene Aufträge, [enqueue] schlägt aber fehl.
  ModellHalter<RestoreService>? restoreHalter;

  bool _processing = false;
  String? _activeJobId;
  final Set<String> _cancelRequested = {};

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
  Future<String> enqueue(String assetId) async {
    if (restoreHalter?.installiert != true) {
      throw const RestaurierungNichtVerfuegbar();
    }
    final existing = await _db.activeRestoreJobForAsset(assetId);
    if (existing != null) return existing.id;

    final id = const Uuid().v4();
    await _db.createRestoreJob(RestoreJobsCompanion.insert(
      id: id,
      assetId: assetId,
      status: 'queued',
      createdAt: DateTime.now(),
    ));
    unawaited(_maybeStartNext());
    return id;
  }

  /// Ein noch wartender Auftrag wird sofort entfernt; ein gerade laufender
  /// wird zwischen Kacheln abgebrochen (siehe [RestoreService.restore]s
  /// `isCancelled`) und dann als `cancelled` markiert, OHNE ein
  /// unvollständiges Ergebnis zu speichern.
  Future<void> cancel(String jobId) async {
    if (jobId == _activeJobId) {
      _cancelRequested.add(jobId);
    } else {
      await _db.deleteRestoreJob(jobId);
    }
  }

  /// Stößt die Verarbeitung an, falls Aufträge warten und gerade nichts
  /// läuft – aufgerufen beim App-Start (nach [AppDatabase.resetStuckRunningRestoreJobs],
  /// siehe LibraryState.initialize) für Aufträge, die aus der letzten
  /// Sitzung noch offen sind.
  Future<void> resume() => _maybeStartNext();

  Future<void> _maybeStartNext() async {
    // _processing wird bewusst VOR dem ersten await gesetzt (statt erst
    // nachdem [nextQueuedRestoreJob] zurückkommt) – Audit-Fund: zwei
    // schnell aufeinanderfolgende Aufrufe (z.B. zwei enqueue()s in
    // Folge) würden sonst beide die DB-Abfrage starten, bevor einer von
    // beiden _processing setzt, und so zwei Aufträge parallel verarbeiten
    // (verdoppelte CPU/GPU-Last, doppelter Speicherbedarf für die
    // Kachel-Puffer) statt der vorgesehenen Ein-Auftrag-gleichzeitig-Regel.
    if (_processing) return;
    _processing = true;
    try {
      final next = await _db.nextQueuedRestoreJob();
      if (next == null) return;
      _activeJobId = next.id;
      try {
        await _process(next);
      } finally {
        _cancelRequested.remove(next.id);
        _activeJobId = null;
      }
    } finally {
      _processing = false;
    }
    unawaited(_maybeStartNext());
  }

  Future<void> _process(RestoreJobData job) async {
    // Lokal einfangen statt später erneut über das Feld zu gehen: Ersetzt
    // LibraryState.reloadModels() [restoreHalter] mitten in der Verarbeitung
    // (neuer Modell-Download), soll [zurueckgeben] weiterhin auf DIESEM
    // (dann "retirierten", aber noch gültigen) Halter aufgerufen werden –
    // sonst bliebe sein Nutzerzähler für immer > 0 und er würde nie entsorgt.
    final halter = restoreHalter;
    RestoreService? service;
    try {
      service = await halter?.leihen();
    } catch (e) {
      // Ohne dieses try/catch verließ eine Ladefehler-Exception (z.B. eine
      // beschädigte Modelldatei) _process() unbehandelt – der Auftrag blieb
      // für immer auf "queued" stehen UND das nachfolgende
      // unawaited(_maybeStartNext()) in _maybeStartNext() wurde nie erreicht,
      // wodurch die gesamte Warteschlange dauerhaft blockierte (Audit-Fund).
      await _db.markRestoreJobStatus(job.id, 'failed',
          // Kennung UND Ursache: Die Kennung wird übersetzt, die Ursache
          // dahinter ist das, was bei einem Fehlerbericht wirklich hilft.
          errorMessage: '${RestaurierungsGrund.modellLaedtNicht.name}: $e');
      return;
    }
    if (service == null) {
      await _db.markRestoreJobStatus(job.id, 'failed', errorMessage: RestaurierungsGrund.modellWeg.name);
      return;
    }
    await _db.markRestoreJobStatus(job.id, 'running');

    try {
      final asset = await _db.assetById(job.assetId);
      if (asset == null) {
        await _db.markRestoreJobStatus(job.id, 'failed', errorMessage: RestaurierungsGrund.fotoWeg.name);
        return;
      }
      if (asset.isLocked) {
        await _db.markRestoreJobStatus(job.id, 'failed',
            errorMessage: RestaurierungsGrund.gesperrt.name);
        return;
      }
      final targetWidth = asset.widthPx;
      final targetHeight = asset.heightPx;
      if (targetWidth == null || targetHeight == null) {
        await _db.markRestoreJobStatus(job.id, 'failed', errorMessage: RestaurierungsGrund.aufloesungUnbekannt.name);
        return;
      }

      // Eingabe: das bereits entwickelte Bild (aktuelle Regler/Masken) in
      // voller Auflösung über den nativen Kanal – das `image`-Dart-Paket
      // kann RAW-Originale nicht selbst dekodieren (siehe DevelopScreen).
      final settings = await _db.developSettingsForAsset(job.assetId);
      final adjustments = settings == null
          ? DevelopAdjustments.neutral
          : DevelopAdjustments(
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
      final masks = await _db.masksForAsset(job.assetId);
      final maskLayers = [
        for (final m in masks)
          MaskAdjustmentLayer(
            maskFilePath: _paths.absolute(m.maskRelativePath).path,
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

      final sourceFile = _paths.absolute(asset.relativePath);
      final jpegBytes = await NativeImageConverter.developImage(
        sourceFile,
        adjustments: adjustments,
        masks: maskLayers,
        maxDimension: targetWidth > targetHeight ? targetWidth : targetHeight,
        quality: 0.95,
      );
      if (jpegBytes == null) {
        await _db.markRestoreJobStatus(job.id, 'failed', errorMessage: RestaurierungsGrund.nichtGerendert.name);
        return;
      }
      final decoded = img.decodeJpg(jpegBytes);
      if (decoded == null) {
        await _db.markRestoreJobStatus(job.id, 'failed', errorMessage: RestaurierungsGrund.nichtDekodiert.name);
        return;
      }

      final result = await service.restore(
        decoded,
        // Absichtlich nicht awaited (der Fortschritt darf die Inferenz
        // nicht ausbremsen) – catchError statt eines unbehandelten
        // Future-Fehlers, falls der DB-Schreibzugriff einmal transient
        // fehlschlägt.
        onProgress: (done, total) =>
            unawaited(_db.updateRestoreJobProgress(job.id, done, total).catchError((_) {})),
        isCancelled: () => _cancelRequested.contains(job.id),
      );

      if (_cancelRequested.contains(job.id)) {
        await _db.markRestoreJobStatus(job.id, 'cancelled');
        return;
      }

      final relativePath = _paths.restoredRelativePath(job.assetId);
      final outFile = _paths.absolute(relativePath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(img.encodeJpg(result, quality: 92));

      // Der Pfad ist je Aufnahme derselbe (`restored/{id}.jpg`). Wer ein
      // Ergebnis verwirft und neu rechnen laesst, bekaeme sonst das alte
      // Bild aus dem Bildspeicher zu sehen - siehe [vergissAlleBilder].
      vergissAlleBilder();
      await _db.completeRestoreJob(job.id, job.assetId, relativePath);
    } catch (e) {
      await _db.markRestoreJobStatus(job.id, 'failed', errorMessage: e.toString());
    } finally {
      halter!.zurueckgeben();
    }
  }
}
