import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../berechne.dart';
import '../db/database.dart';
import '../services/blur_detection.dart';
import '../services/bild_lesen.dart';
import '../services/embedding_codec.dart';
import '../services/eye_state_service.dart';
import '../services/face_engine_service.dart';
import '../services/face_postprocess.dart';
import '../services/textstellen.dart';
import 'auswertungen.dart';
import 'herkunft.dart';

/// Rechnen auf einem verbundenen Rechner für den Server (Issue #104): Der
/// Server vergibt Aufträge, der Rechner rechnet mit seinen Modellen und
/// schickt das Ergebnis; eingetragen wird auf dem Server, nach denselben
/// Regeln wie bei seinen eigenen Läufen.
///
/// Drei Arten, die teuren Bildmodelle – Spracherkennung bliebe ein
/// Hin und Her ganzer Videos und rechnet weiter der Server.
enum Rechenart { bildanalyse, texterkennung, bildbeschreibung }

/// Wer gerade an welcher Aufnahme rechnet (der Server führt sie): Seine
/// eigenen Läufe und die Rechner nehmen eine Aufnahme, bevor sie rechnen,
/// und geben sie danach ab.
abstract class Vergabe {
  /// Nimmt [aufnahme] für [art] – `false`, wenn ein anderer sie gerade hat
  /// oder ein Rechner sie in der Zwischenzeit geliefert hat.
  bool nimm(Rechenart art, String aufnahme);

  void gib(Rechenart art, String aufnahme);
}

/// Die Teile der Bildanalyse, die offen sein können.
abstract final class Bildanalyseteil {
  static const schaerfe = 'schaerfe';
  static const gesichter = 'gesichter';
  static const clip = 'clip';
  static const alle = {schaerfe, gesichter, clip};
}

/// Ein Auftrag vom Server.
class Rechenauftrag {
  const Rechenauftrag({
    required this.id,
    required this.art,
    required this.aufnahme,
    required this.datei,
    this.teile = const {},
    this.deutsch = false,
  });

  factory Rechenauftrag.ausJson(Map<String, Object?> j) => Rechenauftrag(
    id: j['id']! as String,
    art: Rechenart.values.byName(j['art']! as String),
    aufnahme: j['aufnahme']! as String,
    datei: j['datei']! as String,
    teile: {...?(j['teile'] as List?)?.cast<String>()},
    deutsch: j['deutsch'] == true,
  );

  /// Die Kennung der Vergabe – sie gilt nur bis zu ihrem Ablauf.
  final String id;
  final Rechenart art;
  final String aufnahme;

  /// Die Datei der Bibliothek, aus der gerechnet wird (relativer Pfad, wie
  /// `GET /api/v1/dateien/<pfad>` ihn will): die Vorschau, wo es eine gibt.
  final String datei;

  /// Bildanalyse: welche Teile offen sind (siehe [Bildanalyseteil]).
  final Set<String> teile;

  /// Bildbeschreibung: auch ins Deutsche übersetzen.
  final bool deutsch;

  Map<String, Object?> alsJson() => {
    'id': id,
    'art': art.name,
    'aufnahme': aufnahme,
    'datei': datei,
    if (teile.isNotEmpty) 'teile': teile.toList(),
    if (deutsch) 'deutsch': true,
  };
}

/// Ein Gesicht, wie der Rechner es fand.
class Gesichtsfund {
  const Gesichtsfund({
    required this.x,
    required this.y,
    required this.breite,
    required this.hoehe,
    required this.schaerfe,
    required this.ausschnitt,
    this.merkmal,
    this.augen,
  });

  factory Gesichtsfund.ausJson(Map<String, Object?> j) => Gesichtsfund(
    x: (j['x']! as num).toDouble(),
    y: (j['y']! as num).toDouble(),
    breite: (j['breite']! as num).toDouble(),
    hoehe: (j['hoehe']! as num).toDouble(),
    schaerfe: (j['schaerfe']! as num).toDouble(),
    ausschnitt: base64.decode(j['ausschnitt']! as String),
    merkmal: j['merkmal'] == null
        ? null
        : floatsFromEmbeddingBlob(base64.decode(j['merkmal']! as String)),
    augen: (j['augen'] as num?)?.toDouble(),
  );

  /// Lage als Anteil der Bildkante, 0..1.
  final double x, y, breite, hoehe;
  final double schaerfe;

  /// Der Ausschnitt als JPEG – derselbe, den die App ablegt.
  final Uint8List ausschnitt;

  /// Die Einbettung für die Wiedererkennung, wo ein Modell sie rechnet.
  final Float32List? merkmal;
  final double? augen;

  Map<String, Object?> alsJson() => {
    'x': x,
    'y': y,
    'breite': breite,
    'hoehe': hoehe,
    'schaerfe': schaerfe,
    'ausschnitt': base64.encode(ausschnitt),
    if (merkmal != null)
      'merkmal': base64.encode(blobFromEmbeddingFloats(merkmal!)),
    if (augen != null) 'augen': augen,
  };
}

/// Woher ein Teil des Ergebnisses stammt (siehe `ergebnisherkunft`).
typedef Herkunftsangabe = ({
  String modell,
  String geraet,
  String beschleuniger,
});

/// Was der Rechner liefert. Je Art nur ihre Felder; [herkunft] je
/// [Ergebnisart], die darin steckt.
class Rechenergebnis {
  const Rechenergebnis({
    this.schaerfe,
    this.clip,
    this.gesichter,
    this.textstellen,
    this.beschreibung,
    this.deutsch,
    this.herkunft = const {},
  });

  factory Rechenergebnis.ausJson(Map<String, Object?> j) => Rechenergebnis(
    schaerfe: (j['schaerfe'] as num?)?.toDouble(),
    clip: j['clip'] == null
        ? null
        : floatsFromEmbeddingBlob(base64.decode(j['clip']! as String)),
    gesichter: (j['gesichter'] as List?)
        ?.map((g) => Gesichtsfund.ausJson((g as Map).cast<String, Object?>()))
        .toList(),
    textstellen: j['textstellen'] == null
        ? null
        : textstellenAusJson(j['textstellen']! as String),
    beschreibung: j['beschreibung'] as String?,
    deutsch: j['deutsch'] as String?,
    herkunft: {
      for (final e in ((j['herkunft'] as Map?) ?? const {}).entries)
        e.key as String: (
          modell: (e.value as Map)['modell']! as String,
          geraet: (e.value as Map)['geraet']! as String,
          beschleuniger: (e.value as Map)['beschleuniger']! as String,
        ),
    },
  );

  final double? schaerfe;
  final Float32List? clip;
  final List<Gesichtsfund>? gesichter;
  final List<Textstelle>? textstellen;
  final String? beschreibung;
  final String? deutsch;
  final Map<String, Herkunftsangabe> herkunft;

  Map<String, Object?> alsJson() => {
    if (schaerfe != null) 'schaerfe': schaerfe,
    if (clip != null) 'clip': base64.encode(blobFromEmbeddingFloats(clip!)),
    if (gesichter != null)
      'gesichter': [for (final g in gesichter!) g.alsJson()],
    if (textstellen != null) 'textstellen': textstellenNachJson(textstellen!),
    if (beschreibung != null) 'beschreibung': beschreibung,
    if (deutsch != null) 'deutsch': deutsch,
    'herkunft': {
      for (final e in herkunft.entries)
        e.key: {
          'modell': e.value.modell,
          'geraet': e.value.geraet,
          'beschleuniger': e.value.beschleuniger,
        },
    },
  };
}

/// Welche Arten (und Teile der Bildanalyse) die Modelle hier rechnen
/// können – danach fragt ein Rechner den Server.
extension Rechenfaehigkeit on Auswertungen {
  Set<Rechenart> get rechenarten => {
    if (clipBildHalter.installiert || faceEngineHalter.installiert)
      Rechenart.bildanalyse,
    if (ocrHalter.installiert || bildwerkzeuge.liestTextSelbst)
      Rechenart.texterkennung,
    if (captioningHalter.installiert) Rechenart.bildbeschreibung,
  };

  Set<String> get bildanalyseteile => {
    Bildanalyseteil.schaerfe,
    if (faceEngineHalter.installiert) Bildanalyseteil.gesichter,
    if (clipBildHalter.installiert) Bildanalyseteil.clip,
  };
}

/// Rechnen, ohne die Bibliothek anzufassen (auf dem Rechner).
extension Rechnen on Auswertungen {
  Herkunftsangabe _herkunft(Ergebnisart art) => (
    modell: art.modell,
    geraet: rechner.geraet,
    beschleuniger: rechner.beschleuniger(art),
  );

  /// Rechnet [auftrag] aus [datei]; `null`, wenn die Datei sich nicht lesen
  /// lässt oder ein nötiges Modell fehlt.
  Future<Rechenergebnis?> rechne(Rechenauftrag auftrag, File datei) async {
    switch (auftrag.art) {
      case Rechenart.texterkennung:
        if (bildwerkzeuge.liestTextSelbst) {
          final stellen = await bildwerkzeuge.recognizeText(datei);
          if (stellen == null) return null;
          return Rechenergebnis(
            textstellen: stellen,
            herkunft: {
              Ergebnisart.texterkennung.name: (
                modell: 'Apple Vision',
                geraet: rechner.geraet,
                beschleuniger: 'System',
              ),
            },
          );
        }
        final bild = await _dekodiere(datei);
        if (bild == null) return null;
        final ocr = await ocrHalter.leihen();
        if (ocr == null) return null;
        try {
          return Rechenergebnis(
            textstellen: await ocr.erkenne(bild),
            herkunft: {
              Ergebnisart.texterkennung.name: _herkunft(
                Ergebnisart.texterkennung,
              ),
            },
          );
        } finally {
          ocrHalter.zurueckgeben();
        }
      case Rechenart.bildbeschreibung:
        final bild = await _dekodiere(datei);
        if (bild == null) return null;
        final dienst = await captioningHalter.leihen();
        if (dienst == null) return null;
        try {
          final beschreibung = await dienst.generateCaption(bild);
          String? deutsch;
          if (auftrag.deutsch && beschreibung.isNotEmpty) {
            final u = await uebersetzungEnDeHalter.leihen();
            if (u != null) {
              try {
                deutsch = await u.translate(beschreibung);
              } finally {
                uebersetzungEnDeHalter.zurueckgeben();
              }
            }
          }
          return Rechenergebnis(
            beschreibung: beschreibung,
            deutsch: deutsch,
            herkunft: {
              Ergebnisart.bildbeschreibung.name: _herkunft(
                Ergebnisart.bildbeschreibung,
              ),
            },
          );
        } finally {
          captioningHalter.zurueckgeben();
        }
      case Rechenart.bildanalyse:
        final bild = await _dekodiere(datei);
        if (bild == null) return null;
        final teile = auftrag.teile;
        double? schaerfe;
        Float32List? clip;
        List<Gesichtsfund>? gesichter;
        final herkunft = <String, Herkunftsangabe>{};
        if (teile.contains(Bildanalyseteil.schaerfe)) {
          schaerfe = await berechne(computeBlurScore, bild);
        }
        if (teile.contains(Bildanalyseteil.clip)) {
          final c = await clipBildHalter.leihen();
          if (c != null) {
            try {
              clip = await c.embedImage(bild);
              herkunft[Ergebnisart.clip.name] = _herkunft(Ergebnisart.clip);
            } finally {
              clipBildHalter.zurueckgeben();
            }
          }
        }
        if (teile.contains(Bildanalyseteil.gesichter)) {
          final engine = await faceEngineHalter.leihen();
          if (engine != null) {
            final augen = await eyeStateHalter.leihen();
            try {
              gesichter = await erkenneGesichter(bild, engine, augen);
              herkunft[Ergebnisart.gesichter.name] = _herkunft(
                Ergebnisart.gesichter,
              );
            } finally {
              if (augen != null) eyeStateHalter.zurueckgeben();
              faceEngineHalter.zurueckgeben();
            }
          }
        }
        return Rechenergebnis(
          schaerfe: schaerfe,
          clip: clip,
          gesichter: gesichter,
          herkunft: herkunft,
        );
    }
  }

  Future<img.Image?> _dekodiere(File datei) async {
    try {
      return await berechne(decodeImageBytes, await datei.readAsBytes());
    } catch (_) {
      return null;
    }
  }
}

/// Eintragen, was ein Rechner lieferte (auf dem Server).
extension Eintragen on Auswertungen {
  /// Trägt [e] für den Auftrag ein – nur, was noch offen ist: Hat der
  /// Server es inzwischen selbst gerechnet, gilt sein Ergebnis.
  Future<void> trageEin(Rechenauftrag a, Rechenergebnis e) async {
    final asset = await db.assetById(a.aufnahme);
    if (asset == null) return;
    Future<void> vermerke(Ergebnisart art) async {
      final h = e.herkunft[art.name];
      if (h == null) return;
      await db.vermerkeHerkunft(
        asset.id,
        art.name,
        modell: h.modell,
        geraet: h.geraet,
        beschleuniger: h.beschleuniger,
      );
    }

    switch (a.art) {
      case Rechenart.texterkennung:
        final stellen = e.textstellen;
        if (stellen == null) return;
        await db.setOcrResult(
          asset.id,
          textAusStellen(stellen),
          boxen: stellen.isEmpty ? null : textstellenNachJson(stellen),
        );
        await vermerke(Ergebnisart.texterkennung);
      case Rechenart.bildbeschreibung:
        final beschreibung = e.beschreibung;
        if (beschreibung == null) return;
        var deutsch = e.deutsch;
        // Konnte der Rechner nicht übersetzen, tut es der Server, wenn er
        // es kann und soll.
        if (deutsch == null &&
            beschreibung.isNotEmpty &&
            await db.uebersetzeBeschreibungen()) {
          final u = await uebersetzungEnDeHalter.leihen();
          if (u != null) {
            try {
              deutsch = await u.translate(beschreibung);
            } finally {
              uebersetzungEnDeHalter.zurueckgeben();
            }
          }
        }
        await db.setAiCaption(asset.id, beschreibung, deutsch: deutsch);
        await vermerke(Ergebnisart.bildbeschreibung);
      case Rechenart.bildanalyse:
        if (e.schaerfe != null && asset.sharpnessScore == null) {
          await db.setSharpnessScore(asset.id, e.schaerfe!);
        }
        if (e.clip != null) {
          await db.saveEmbedding(asset.id, e.clip!);
          await vermerke(Ergebnisart.clip);
        }
        if (e.gesichter != null && !asset.facesScanned) {
          await speichereGesichter(asset, e.gesichter!);
          await vermerke(Ergebnisart.gesichter);
        }
    }
  }
}

/// Die Gesichter in [bild] mit Ausschnitt, Einbettung und Augenzustand –
/// ohne die Bibliothek. [auslassen] überspringt Stellen, die schon da sind
/// (und spart deren Einbettung).
Future<List<Gesichtsfund>> erkenneGesichter(
  img.Image bild,
  FaceEngineService engine,
  EyeStateService? augenzustand, {
  List<DetectedFace> auslassen = const [],
}) async {
  final funde = <Gesichtsfund>[];
  for (final box in await engine.detectFaces(bild)) {
    if (auslassen.any((alt) => FacePostprocess.iou(alt, box) > 0.3)) {
      continue;
    }
    final ausschnitt = FaceEngineService.cropFaceImage(bild, box);
    Float32List? merkmal;
    if (engine.canEmbed) merkmal = await engine.embedFace(bild, box);
    double? augen;
    if (augenzustand != null) {
      try {
        augen = await augenzustand.eyeOpenScore(bild, box);
      } catch (_) {
        // Ohne Augenzustand ist das Gesicht trotzdem eines.
      }
    }
    funde.add(
      Gesichtsfund(
        x: box.x,
        y: box.y,
        breite: box.width,
        hoehe: box.height,
        schaerfe: gesichtsschaerfe(ausschnitt),
        ausschnitt: img.encodeJpg(ausschnitt, quality: 85),
        merkmal: merkmal,
        augen: augen,
      ),
    );
  }
  return funde;
}

/// Trägt [funde] als Gesichter von [asset] ein und vermerkt es als
/// gescannt. Was beiseitegelegt wurde, kommt nicht zurück (dieselbe Regel
/// wie `scanFacesForDecodedAsset`).
extension GesichterSpeichern on Auswertungen {
  Future<void> speichereGesichter(
    AssetData asset,
    List<Gesichtsfund> funde,
  ) async {
    final ignoriert = [
      for (final f in await db.facesForAsset(asset.id))
        if (f.isIgnored) DetectedFace(f.boxX, f.boxY, f.boxW, f.boxH, 1.0),
    ];
    for (final f in funde) {
      final box = DetectedFace(f.x, f.y, f.breite, f.hoehe, 1.0);
      if (ignoriert.any((alt) => FacePostprocess.iou(alt, box) > 0.3)) {
        continue;
      }
      final faceId = const Uuid().v4();
      final cropFile = paths.absolute(paths.faceRelativePath(faceId));
      await cropFile.create(recursive: true);
      await cropFile.writeAsBytes(f.ausschnitt);
      await db.insertFace(
        FacesCompanion.insert(
          id: faceId,
          assetId: asset.id,
          boxX: f.x,
          boxY: f.y,
          boxW: f.breite,
          boxH: f.hoehe,
          cropRelativePath: Value(paths.faceRelativePath(faceId)),
          embedding: f.merkmal != null
              ? Value(blobFromEmbeddingFloats(f.merkmal!))
              : const Value.absent(),
          eyeOpenScore: f.augen != null ? Value(f.augen) : const Value.absent(),
          schaerfe: Value(f.schaerfe),
        ),
      );
    }
    await db.markFacesScanned([asset.id]);
  }
}
