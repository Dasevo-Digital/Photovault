import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../berechne.dart';
import '../db/database.dart';
import '../protokoll.dart';
import '../services/ai_tagging_service.dart';
import '../services/asset_display_path.dart';
import '../services/bild_lesen.dart';
import '../services/bildwerkzeuge.dart';
import '../services/blur_detection.dart';
import '../services/clip_service.dart';
import '../services/embedding_codec.dart';
import '../services/eye_state_service.dart';
import '../services/face_engine_service.dart';
import '../services/face_postprocess.dart';
import '../services/florence_captioning_service.dart';
import '../services/import_service.dart';
import '../services/modell_halter.dart';
import '../services/ocr_service.dart';
import '../services/personenvorschlag.dart';
import '../services/reverse_geocoder.dart';
import '../services/storage_paths.dart';
import '../services/textstellen.dart';
import '../services/translation_service.dart';
import '../services/videostandbilder.dart';
import '../services/whisper_service.dart';
import 'fortschritt.dart';
import 'modelle.dart';
import 'herkunft.dart';

/// Die Stufen der Hintergrundanalyse nach dem Import – **in der
/// Reihenfolge ihres Ablaufs** (siehe [Auswertungen.stufe]). Jede
/// überspringt selbst die Aufnahmen, die sie schon hat, und tut nichts,
/// wenn ihr Modell fehlt; ein erneuter Durchgang ist deshalb gefahrlos.
///
/// Reihenfolge nach steigendem Aufwand: Zuerst das, was schnell fertig ist
/// und sofort nutzbar, zuletzt die Bildbeschreibung – die erzeugt ihren
/// Satz Wort für Wort und ist damit mit Abstand die teuerste Stufe.
///
/// Unschärfe, Gesichter und CLIP brauchen DASSELBE dekodierte Bild und
/// laufen deshalb als ein gemeinsamer Durchlauf ([bildanalyse]), der je
/// Foto nur einmal dekodiert. Die Bildbeschreibung bleibt eine eigene,
/// späte Stufe, obwohl sie dasselbe Bild bräuchte: Sie ist um ein
/// Vielfaches teurer als die anderen drei zusammen, und ein Abbruch nach
/// der halben Zeit soll die Bibliothek vollständig bis auf die
/// Bildbeschreibung ausgewertet zurücklassen, nicht zur Hälfte gar nicht.
///
/// Eine Aufzählung statt eines fertigen Namens: Der Kern kennt keine
/// Oberflächensprache. Den Namen gibt die App dazu.
enum Analysestufe {
  bildanalyse,
  texterkennung,

  /// Kein eigener CLIP-Schritt davor – die Einbettungen entstehen bereits
  /// in der Bildanalyse.
  schlagwoerter,
  bildbeschreibung,

  /// Nach der Bildbeschreibung: Sie ist je Aufnahme billiger als ein Video
  /// mit Ton, und es gibt mehr Fotos als Videos.
  spracherkennung,

  /// Zuletzt, und das ist keine Nebensache: Die Gesichter entstehen erst in
  /// der Bildanalyse ganz oben. Wer früher fragt, fragt nach Gesichtern,
  /// die es noch nicht gibt.
  wiedererkennung,
}

/// Die Auswertungen einer Bibliothek: Gesichter, Bildinhalt (CLIP),
/// Schärfe, Text im Bild, Bildbeschreibung, Schlagwörter, Gesprochenes in
/// Videos und die Wiedererkennung benannter Personen – jede als Lauf über
/// die Aufnahmen, die noch offen sind, mit Fortschritt als Strom.
///
/// Dieselben Läufe in der App (über `LibraryState`) und auf dem Server
/// (Issue #86): Hier steht nichts, was eine Oberfläche braucht. Was von
/// der App abhängt, kommt herein – die Bildwerkzeuge der Plattform, die
/// allgemeine Schwelle der Gesichtserkennung, ein Abbruch und was nach
/// einem vollständigen Lauf mit neuen Modellen geschehen soll.
class Auswertungen {
  Auswertungen({
    required this.db,
    required this.paths,
    required this.modelle,
    Bildwerkzeuge? bildwerkzeuge,
    AiTaggingService? aiTaggingService,
    double Function()? gesichtsschwelle,
    bool Function()? abgebrochen,
    this.pipelineAktuell,
    Rechner? rechner,
  }) : rechner = rechner ?? Rechner.hier(),
       bildwerkzeuge = bildwerkzeuge ?? Bildwerkzeuge.standard,
       aiTaggingService = aiTaggingService ?? AiTaggingService(),
       gesichtsschwelle = gesichtsschwelle ?? (() => standardGesichtsschwelle),
       abgebrochen = abgebrochen ?? (() => false);

  /// Die allgemeine Schwelle, solange niemand eine andere einstellt.
  static const standardGesichtsschwelle = 0.363;

  final AppDatabase db;
  final StoragePaths paths;
  final Modelle modelle;
  final Bildwerkzeuge bildwerkzeuge;
  final AiTaggingService aiTaggingService;

  /// Die allgemeine Schwelle der Gesichtserkennung, wie sie gerade gilt.
  final double Function() gesichtsschwelle;

  /// Ob ein laufender Durchgang aufhören soll.
  final bool Function() abgebrochen;

  /// Was geschieht, wenn ein Lauf über alle Aufnahmen mit den aktuellen
  /// Modellen fertig ist (siehe ModelProcessingState).
  final Future<void> Function(String pipeline)? pipelineAktuell;

  /// Wer rechnet – für die Herkunft jedes Ergebnisses (siehe
  /// [Ergebnisart]).
  final Rechner rechner;

  Future<void> _vermerke(String assetId, Ergebnisart art) =>
      db.vermerkeHerkunft(
        assetId,
        art.name,
        modell: art.modell,
        geraet: rechner.geraet,
        beschleuniger: rechner.beschleuniger(art),
      );

  Future<void> _pipelineAktuell(String pipeline) async =>
      pipelineAktuell?.call(pipeline);

  ModellHalter<FaceEngineService> get faceEngineHalter =>
      modelle.faceEngineHalter;
  ModellHalter<EyeStateService> get eyeStateHalter => modelle.eyeStateHalter;
  ModellHalter<ClipService> get clipBildHalter => modelle.clipBildHalter;
  ModellHalter<ClipService> get clipTextHalter => modelle.clipTextHalter;
  ModellHalter<FlorenceCaptioningService> get captioningHalter =>
      modelle.captioningHalter;
  ModellHalter<WhisperService> get spracherkennungHalter =>
      modelle.spracherkennungHalter;
  ModellHalter<TranslationService> get uebersetzungEnDeHalter =>
      modelle.uebersetzungEnDeHalter;
  ModellHalter<TranslationService> get uebersetzungDeEnHalter =>
      modelle.uebersetzungDeEnHalter;
  ModellHalter<OcrService> get ocrHalter => modelle.ocrHalter;

  /// Der Lauf einer Stufe der Hintergrundanalyse (siehe [Analysestufe]).
  /// [backfillClipEmbeddings] gehört nicht dazu – es bleibt für den Aufruf
  /// von Hand.
  Stream<ImportProgress> stufe(Analysestufe stufe) => switch (stufe) {
    Analysestufe.bildanalyse => bildinhaltsAnalyse(),
    Analysestufe.texterkennung => backfillOcrText(),
    Analysestufe.schlagwoerter => backfillAiTags(onlyUntagged: true),
    Analysestufe.bildbeschreibung => backfillCaptions(),
    Analysestufe.spracherkennung => transkribiereVideos(),
    Analysestufe.wiedererkennung => backfillWiedererkennung(),
  };

  /// Datei, die tatsächlich dekodiert werden kann: die konvertierte
  /// Vorschau, falls das Originalformat (HEIC/DNG & Co.) von Flutter bzw.
  /// dem `image`-Paket nicht direkt gelesen werden kann – sonst das
  /// Original selbst.
  File decodableFile(AssetData asset) =>
      paths.absolute(asset.previewRelativePath ?? asset.relativePath);

  /// Lädt und dekodiert das Bild eines Assets einmalig – wird sowohl für
  /// die Gesichtserkennung als auch für die CLIP-Einbettung wiederverwendet
  /// (siehe `LibraryState._postProcessNewAsset`), statt dieselbe JPEG/HEIC-Vorschau für
  /// jeden Verarbeitungsschritt erneut von der Platte zu lesen und zu
  /// dekodieren. Gibt `null` zurück, wenn die Datei fehlt oder nicht
  /// dekodierbar ist (z.B. beschädigt).
  Future<img.Image?> decodeAsset(AssetData asset) async {
    try {
      return await berechne(
        decodeImageBytes,
        await decodableFile(asset).readAsBytes(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Führt die Gesichtserkennung für ein Asset aus, dessen Bild bereits
  /// dekodiert vorliegt (siehe `LibraryState._postProcessNewAsset`, wo dasselbe Bild auch
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
  Future<void> scanFacesForDecodedAsset(
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
            protokoll(
              'Augen-Zustand-Erkennung fehlgeschlagen für ${asset.originalFileName}: $e',
            );
          }
        }

        await db.insertFace(
          FacesCompanion.insert(
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
            eyeOpenScore: eyeOpenScore != null
                ? Value(eyeOpenScore)
                : const Value.absent(),
            // Auf dem Ausschnitt, der ohnehin schon im Speicher liegt –
            // kein zweiter Dekodiervorgang, keine zweite Skalierung.
            schaerfe: Value(gesichtsschaerfe(croppedThumb)),
          ),
        );
      }
      await db.markFacesScanned([asset.id]);
      await _vermerke(asset.id, Ergebnisart.gesichter);
    } catch (e) {
      protokoll(
        'Gesichtserkennung fehlgeschlagen für ${asset.originalFileName}: $e',
      );
    }
  }

  /// Dekodiert das Bild eines Assets und führt die Gesichtserkennung aus –
  /// für Aufrufer, die (anders als `LibraryState._postProcessNewAsset`) noch kein
  /// dekodiertes Bild vorliegen haben (manueller Rescan über die Werkzeuge).
  Future<void> _scanFacesForAsset(
    AssetData asset, {
    required FaceEngineService engine,
    EyeStateService? eyeState,
    required bool deleteExistingUnassigned,
  }) async {
    final decoded = await decodeAsset(asset);
    await scanFacesForDecodedAsset(
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
    // [bildinhaltsAnalyse].
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
            protokoll(
              'Gesichtserkennung fehlgeschlagen für '
              '${asset.originalFileName}: $e',
            );
          }
          done++;
          yield ImportProgress(
            done,
            assets.length,
            currentFile: asset.originalFileName,
          );
        }
      } finally {
        if (eyeState != null) eyeStateHalter.zurueckgeben();
      }
    } finally {
      faceEngineHalter.zurueckgeben();
    }
    if (!onlyNewPhotos && !failed) {
      await _pipelineAktuell('faces');
    }
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
  Stream<ImportProgress> backfillWiedererkennung({
    bool alle = false,
    bool beiseite = false,
  }) async* {
    final gesichter = await db.gesichterFuerWiedererkennung(
      alle: alle,
      beiseite: beiseite,
    );
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
                ? gesichtsschwelle()
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
    // [bildinhaltsAnalyse].
    final clipBild = await clipBildHalter.leihen();
    final clipText = await clipTextHalter.leihen();
    try {
      final gesichter = await faceEngineHalter.leihen();
      try {
        final augenzustand = gesichter != null
            ? await eyeStateHalter.leihen()
            : null;
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
                  final bild = await bildwerkzeuge.generateVideoThumbnail(
                    paths.absolute(video.relativePath),
                    maxDimension: videoStandbildKante,
                    anteil: stelle,
                  );
                  if (bild == null) continue;
                  final dekodiert = await berechne(
                    img.decodeJpg,
                    bild.jpegBytes,
                  );
                  if (dekodiert == null) continue;
                  bilder++;

                  if (clipBild != null) {
                    final vektor = await clipBild.embedImage(dekodiert);
                    neue.add((
                      stelle: stelle,
                      vector: blobFromEmbeddingFloats(vektor),
                    ));
                    if (clipText != null) {
                      for (final tag in await aiTaggingService.suggestTags(
                        clipText,
                        vektor,
                        vokabular,
                        insEnglische: insEnglische,
                      )) {
                        await db.fuehreAus(
                          SchlagwortAnheften(
                            [video.id],
                            tag,
                            quelle: Tagquelle.ki,
                          ),
                        );
                      }
                    }
                  }
                  if (gesichter != null) {
                    // `nurNeueStellen`: Wer im Video stillsteht, ist auf
                    // jedem Standbild an derselben Stelle und soll
                    // trotzdem einmal in der Bibliothek stehen.
                    await scanFacesForDecodedAsset(
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
                await _vermerke(video.id, Ergebnisart.clip);
              } catch (e) {
                protokoll(
                  'Standbilder fehlgeschlagen für ${video.originalFileName}: $e',
                );
              }
            }
            done++;
            yield ImportProgress(
              done,
              videos.length,
              currentFile: video.originalFileName,
            );
          }
          if (ohneArbeit.isNotEmpty) {
            await db.markVideobilderGeprueft(ohneArbeit);
          }
          protokoll('Videostandbilder: $bilder aus ${videos.length} Videos');
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
    final ueberSystem = bildwerkzeuge.liestTextSelbst;
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
            stellen = await bildwerkzeuge.recognizeText(decodableFile(asset));
          } else {
            final bild = await decodeAsset(asset);
            if (bild != null) stellen = await modell!.erkenne(bild);
          }
          if (stellen != null) {
            // Kein Text im Bild: Nur das Ergebnis merken, keine leere Liste
            // als „Stellen" ablegen – sonst käme das Foto beim nächsten Lauf
            // nicht mehr dran, obwohl nichts zu holen war. Genau das
            // unterscheidet die beiden Fälle in `_ocrOffen` in der Datenbank.
            await db.setOcrResult(
              asset.id,
              textAusStellen(stellen),
              boxen: stellen.isEmpty ? null : textstellenNachJson(stellen),
            );
            await _vermerke(asset.id, Ergebnisart.texterkennung);
          }
        } on LesungLiefertNichts catch (e) {
          // NICHT als leeres Ergebnis speichern: Das Foto würde als
          // durchsucht vermerkt und nach einer Reparatur nie wieder
          // drankommen. Es bleibt offen, der Lauf geht weiter.
          protokoll(
            'Texterkennung: ${e.stellen} Stellen mit Schrift in '
            '${asset.originalFileName}, keine lesbar – Foto bleibt offen.',
          );
          failed = true;
        } catch (e) {
          failed = true;
          protokoll(
            'Texterkennung fehlgeschlagen für ${asset.originalFileName}: $e',
          );
        }
        done++;
        yield ImportProgress(
          done,
          assets.length,
          currentFile: asset.originalFileName,
        );
      }
    } finally {
      if (!ueberSystem) ocrHalter.zurueckgeben();
    }
    if (alle && !failed) await _pipelineAktuell('ocr');
  }

  /// Erzeugt KI-Bildbeschreibungen nachträglich für Fotos, die vor
  /// Installation des Modells importiert wurden (Captions entstehen sonst
  /// nur automatisch beim Import, siehe `LibraryState._postProcessNewAsset`).
  /// [alle] beschreibt auch Fotos neu, die schon eine Beschreibung haben –
  /// nach dem Modellwechsel der sinnvolle Weg, siehe
  /// [AppDatabase.assetsForCaptionBackfill].
  Stream<ImportProgress> backfillCaptions({bool alle = false}) async* {
    // Erst die Arbeit ermitteln, dann das Modell holen – siehe
    // [bildinhaltsAnalyse]. Das Bildbeschreibungs-Modell ist mit 275 MB
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
          final decoded = await decodeAsset(asset);
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
              protokoll(
                'Übersetzung fehlgeschlagen für ${asset.originalFileName}: $e',
              );
            }
          }
          await db.setAiCaption(asset.id, caption, deutsch: deutsch);
          await _vermerke(asset.id, Ergebnisart.bildbeschreibung);
        } catch (e) {
          failed = true;
          protokoll(
            'KI-Bildbeschreibung fehlgeschlagen für ${asset.originalFileName}: $e',
          );
        }
        done++;
        yield ImportProgress(
          done,
          assets.length,
          currentFile: asset.originalFileName,
        );
      }
    } finally {
      if (uebersetzer != null) uebersetzungEnDeHalter.zurueckgeben();
      captioningHalter.zurueckgeben();
    }
    if (alle && !failed) await _pipelineAktuell('captions');
  }

  /// Wie lang ein Video höchstens gehört wird. Darüber nur der Anfang:
  /// Eine Stunde Ton wären 120 Durchgänge des Modells, und für die Suche
  /// genügt meist, was in der ersten halben Stunde gesagt wird.
  static const transkriptHoechstensSekunden = 30 * 60;

  /// Hört die Videos ab, die die Spracherkennung noch nicht kennt, und
  /// hält fest, was gesagt wird – auch, dass nichts gesagt wird.
  ///
  /// [alle] hört auch die schon gehörten noch einmal, nach einem
  /// Modellwechsel der sinnvolle Weg.
  Stream<ImportProgress> transkribiereVideos({bool alle = false}) async* {
    // Erst die Arbeit ermitteln, dann das Modell holen – siehe
    // [bildinhaltsAnalyse].
    final videos = await db.assetsForTranskription(alle: alle);
    if (videos.isEmpty) {
      yield ImportProgress(0, 0);
      return;
    }
    final service = await spracherkennungHalter.leihen();
    if (service == null) {
      yield ImportProgress(0, 0);
      return;
    }
    var failed = false;
    try {
      var done = 0;
      yield ImportProgress(0, videos.length);
      for (final video in videos) {
        try {
          // Der Ton aus dem Video, das man sieht: ein gekürztes, wenn es
          // eines gibt.
          final datei = paths.absolute(displayRelativePath(video));
          final ton = await bildwerkzeuge.videoTon(
            datei,
            hoechstensSekunden: transkriptHoechstensSekunden,
          );
          if (ton == null) {
            // Keine Tonspur ist ein Ergebnis; eine unlesbare Datei auch –
            // sonst käme sie bei jedem Durchgang wieder.
            await db.setTranskript(video.id);
          } else {
            final gehoert = await service.transkribiere(
              ton,
              abbruch: abgebrochen,
            );
            if (abgebrochen()) break;
            await db.setTranskript(
              video.id,
              text: gehoert?.text,
              sprache: gehoert?.sprache,
            );
            await _vermerke(video.id, Ergebnisart.spracherkennung);
          }
        } catch (e) {
          failed = true;
          protokoll(
            'Spracherkennung fehlgeschlagen für ${video.originalFileName}: $e',
          );
        }
        done++;
        yield ImportProgress(
          done,
          videos.length,
          currentFile: video.originalFileName,
        );
      }
    } finally {
      spracherkennungHalter.zurueckgeben();
    }
    if (failed) {
      protokoll('Spracherkennung: nicht jedes Video liess sich hören.');
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
  Stream<ImportProgress> bildinhaltsAnalyse() async* {
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
        final augenzustand = gesichter != null
            ? await eyeStateHalter.leihen()
            : null;
        try {
          var done = 0;
          yield ImportProgress(0, kandidaten.length);

          for (final k in kandidaten) {
            final asset = k.asset;
            final brauchtUnschaerfe = asset.sharpnessScore == null;
            final brauchtGesichter = !asset.facesScanned && gesichter != null;
            final brauchtEmbedding = !k.hatEmbedding && clip != null;

            if (brauchtUnschaerfe || brauchtGesichter || brauchtEmbedding) {
              final decoded = await decodeAsset(asset);
              if (decoded != null) {
                if (brauchtUnschaerfe) {
                  try {
                    await db.setSharpnessScore(
                      asset.id,
                      await berechne(computeBlurScore, decoded),
                    );
                  } catch (e) {
                    protokoll(
                      'Unschärfe fehlgeschlagen für ${asset.originalFileName}: $e',
                    );
                  }
                }
                if (brauchtGesichter) {
                  try {
                    await scanFacesForDecodedAsset(
                      asset,
                      decoded,
                      engine: gesichter,
                      eyeState: augenzustand,
                      deleteExistingUnassigned: false,
                    );
                  } catch (e) {
                    protokoll(
                      'Gesichtserkennung fehlgeschlagen für ${asset.originalFileName}: $e',
                    );
                  }
                }
                if (brauchtEmbedding) {
                  try {
                    await db.saveEmbedding(
                      asset.id,
                      await clip.embedImage(decoded),
                    );
                    await _vermerke(asset.id, Ergebnisart.clip);
                  } catch (e) {
                    protokoll(
                      'CLIP-Embedding fehlgeschlagen für ${asset.originalFileName}: $e',
                    );
                  }
                }
              }
            }

            done++;
            yield ImportProgress(
              done,
              kandidaten.length,
              currentFile: asset.originalFileName,
            );
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
  /// dieses Features importiert wurden (siehe `LibraryState._postProcessNewAsset`).
  /// Wird von der Hintergrundanalyse nicht mehr direkt aufgerufen (dort
  /// erledigt das [bildinhaltsAnalyse] mit), bleibt aber für den manuellen
  /// Lauf in den Werkzeugen erhalten.
  Stream<ImportProgress> backfillBlurScores() async* {
    final assets = await db.assetsForBlurBackfill();
    var done = 0;
    yield ImportProgress(0, assets.length);
    for (final asset in assets) {
      // Pro Foto abgesichert, analog zu [backfillOcrText].
      try {
        final decoded = await decodeAsset(asset);
        if (decoded != null) {
          await db.setSharpnessScore(
            asset.id,
            await berechne(computeBlurScore, decoded),
          );
        }
      } catch (e) {
        protokoll(
          'Unschärfe-Berechnung fehlgeschlagen für ${asset.originalFileName}: $e',
        );
      }
      done++;
      yield ImportProgress(
        done,
        assets.length,
        currentFile: asset.originalFileName,
      );
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
                gesicht.id,
                gesichtsschaerfe(bild),
              );
            }
          }
        }
      } catch (e) {
        protokoll('Gesichtsschärfe fehlgeschlagen für ${gesicht.id}: $e');
      }
      done++;
      yield ImportProgress(done, offen.length);
    }
  }

  /// Berechnet CLIP-Bild-Embeddings nachträglich für Fotos, die vor
  /// Installation des CLIP-Modells importiert wurden (Embeddings entstehen
  /// sonst nur automatisch beim Import, siehe `LibraryState._postProcessNewAsset`) –
  /// ohne dieses Werkzeug bliebe die KI-Bildsuche/Duplikatsuche auf die
  /// wenigen danach importierten Fotos beschränkt.
  /// [alle] rechnet auch bereits vorhandene Einbettungen neu – für den
  /// Fall, dass sich die Bildvorverarbeitung geändert hat.
  Stream<ImportProgress> backfillClipEmbeddings({bool alle = false}) async* {
    // Erst die Arbeit ermitteln, dann das Modell holen – siehe
    // [bildinhaltsAnalyse].
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
          final decoded = await decodeAsset(asset);
          if (decoded == null) {
            throw Exception('Bild konnte nicht dekodiert werden.');
          }
          final embedding = await service.embedImage(decoded);
          await db.saveEmbedding(asset.id, embedding);
          await _vermerke(asset.id, Ergebnisart.clip);
        } catch (e) {
          failed = true;
          protokoll(
            'CLIP-Embedding fehlgeschlagen für ${asset.originalFileName}: $e',
          );
        }
        done++;
        yield ImportProgress(
          done,
          assets.length,
          currentFile: asset.originalFileName,
        );
      }
    } finally {
      clipBildHalter.zurueckgeben();
    }
    if (alle && !failed) await _pipelineAktuell('clip');
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
    // [bildinhaltsAnalyse] für den gemessenen Effekt.
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
            final decoded = await decodeAsset(asset);
            if (decoded == null) {
              throw Exception('Bild konnte nicht dekodiert werden.');
            }
            embedding = await clipBild.embedImage(decoded);
            await db.saveEmbedding(asset.id, embedding);
            await _vermerke(asset.id, Ergebnisart.clip);
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
            await db.fuehreAus(
              SchlagwortAnheften([asset.id], tag, quelle: Tagquelle.ki),
            );
          }
          if (tags.isNotEmpty) {
            await applyAutomationRules(
              asset.id,
              aiTags: tags,
              rules: automationRules,
            );
          }
          // Auch bei LEERER Trefferliste vermerken: "kein Begriff passt" ist
          // ein Ergebnis, kein offener Posten. Ohne diesen Vermerk bliebe das
          // Foto für immer Kandidat und die Stufe lüde bei jedem Start erneut
          // beide CLIP-Encoder, um wieder nichts zu finden (Audit-Fund).
          // Bewusst NUR im Erfolgsfall – ein abgebrochener Durchlauf (siehe
          // catch) soll erneut versucht werden.
          await db.markAiTagsScanned([asset.id]);
        } catch (e) {
          protokoll(
            'KI-Tagging fehlgeschlagen für ${asset.originalFileName}: $e',
          );
        }
        done++;
        yield ImportProgress(
          done,
          assets.length,
          currentFile: asset.originalFileName,
        );
      }
    } finally {
      clipTextHalter.zurueckgeben();
      clipBildHalter.zurueckgeben();
    }
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
  Stream<ImportProgress> uebersetzeBildbeschreibungen({
    bool alle = false,
  }) async* {
    // Erst die Arbeit ermitteln, dann das Modell holen – siehe
    // [bildinhaltsAnalyse].
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
            protokoll(
              'Übersetzung fehlgeschlagen für ${asset.originalFileName}: $e',
            );
          }
        }
        done++;
        yield ImportProgress(
          done,
          assets.length,
          currentFile: asset.originalFileName,
        );
      }
    } finally {
      uebersetzungEnDeHalter.zurueckgeben();
    }
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
      final uebersetzt = await uebersetzungDeEnHalter.mit(
        (s) => s.translate(text),
      );
      if (uebersetzt == null || uebersetzt.trim().isEmpty) return text;
      return uebersetzt;
    } catch (e) {
      protokoll('Übersetzung der Anfrage fehlgeschlagen: $e');
      return text;
    }
  }

  /// Die für [personId] geltende Schwelle: die persönliche, sonst die
  /// allgemeine.
  double schwelleFuerPerson(PersonData person) =>
      person.similarityThreshold ?? gesichtsschwelle();

  /// Wendet passende Automatisierungsregeln an (Zielalbum, Tags, automatisch
  /// favorisieren) – Verallgemeinerung von `applyCameraPreset` der App auf Orts-/
  /// Datums-/KI-Tag-Bedingungen statt nur Kamera, siehe AutomationRules in
  /// database.dart. Zwei Aufrufstellen, je nachdem, wann die jeweilige
  /// Bedingung überhaupt geprüft werden kann:
  ///
  /// - [latitude]/[longitude]/[fileCreatedAt] liegen schon beim Import vor
  ///   (Nachbearbeitung des Imports) – werten `location`-/`dateRange`-Regeln aus.
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
          matches =
              latitude != null &&
              longitude != null &&
              rule.regionCenterLat != null &&
              rule.regionCenterLon != null &&
              rule.regionRadiusKm != null &&
              ReverseGeocoder.haversineKm(
                    latitude,
                    longitude,
                    rule.regionCenterLat!,
                    rule.regionCenterLon!,
                  ) <=
                  rule.regionRadiusKm!;
        case 'dateRange':
          matches =
              fileCreatedAt != null &&
              rule.dateFrom != null &&
              rule.dateTo != null &&
              !fileCreatedAt.isBefore(rule.dateFrom!) &&
              !fileCreatedAt.isAfter(rule.dateTo!);
        case 'aiTag':
          matches =
              aiTags != null &&
              rule.aiTagTerm != null &&
              aiTags.contains(rule.aiTagTerm);
        default:
          matches = false;
      }
      if (!matches) continue;

      if (rule.targetAlbumId != null) {
        await db.fuehreAus(AlbumFuellen(rule.targetAlbumId!, [assetId]));
      }
      if (rule.autoFavorite) {
        await db.fuehreAus(FavoritSetzen([assetId], true));
      }
      final tagIds = await db.tagIdsForAutomationRule(rule.id);
      for (final tagId in tagIds) {
        await db.fuehreAus(SchlagwortAnheftenPerKennung(assetId, tagId));
      }
    }
  }
}
