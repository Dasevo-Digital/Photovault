import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../services/blur_detection.dart';
import '../services/embedding_codec.dart';
import '../services/face_engine_service.dart';
import 'auswertungen.dart';

/// Ob ein aufgezogener Rahmen gross genug ist, um ein Gesicht zu sein – in
/// Anteilen des Bildes, damit es nicht an der Grösse des Bildschirms hängt.
bool gesichtsrahmenGrossGenug(double breite, double hoehe) =>
    breite >= 0.01 && hoehe >= 0.01;

/// Ein von Hand aufgezogenes Gesicht anlegen – dort, wo das Original und
/// das Gesichtsmodell liegen: am Server für Browser, Handy und verbundene
/// Rechner (Issue #190), am Rechner für eine eigene Bibliothek.
///
/// Die Kopie eines verbundenen Geräts darf nicht selbst schreiben (der
/// Schutz `pv_nur_ueber_server`); am verbundenen Rechner brach das
/// Aufziehen deshalb wortlos ab. Am Server angelegt, kommt das Gesicht über
/// den Abgleich zu allen Geräten.
extension GesichtVonHand on Auswertungen {
  /// Der Kasten in Anteilen des Bildes (0..1), wie die Datenbank ihn
  /// führt. [personId] ordnet das Gesicht gleich zu (dann wird sein
  /// Ausschnitt das Bild der Person, falls sie noch keines hat).
  ///
  /// `null`, wenn es die Aufnahme nicht gibt, sie gesperrt ist oder sich
  /// nicht dekodieren lässt. Lässt sich das Wiedererkennungsmodell nicht
  /// nutzen, entsteht das Gesicht trotzdem – nur ohne Einbettung.
  Future<FaceData?> gesichtVonHandAnlegen({
    required String assetId,
    required double x,
    required double y,
    required double breite,
    required double hoehe,
    String? personId,
    String? gesichtId,
  }) async {
    final a = await db.assetById(assetId);
    if (a == null || a.isLocked || a.isTrashed) return null;
    final bild = await decodeAsset(a);
    if (bild == null) return null;
    final box = DetectedFace(
      x.clamp(0.0, 1.0),
      y.clamp(0.0, 1.0),
      breite.clamp(0.0, 1.0 - x.clamp(0.0, 1.0)),
      hoehe.clamp(0.0, 1.0 - y.clamp(0.0, 1.0)),
      1.0,
    );
    final id = gesichtId ?? const Uuid().v4();
    final ausschnitt = FaceEngineService.cropFaceImage(bild, box);
    final pfad = paths.faceRelativePath(id);
    final datei = paths.absolute(pfad);
    await datei.create(recursive: true);
    await datei.writeAsBytes(img.encodeJpg(ausschnitt, quality: 85));
    Float32List? merkmal;
    try {
      merkmal = await faceEngineHalter.mit<Float32List?>(
        (engine) => engine.canEmbed
            ? engine.embedFace(bild, box)
            : Future<Float32List?>.value(null),
      );
    } catch (_) {
      // Ohne Einbettung bleibt es ein Gesicht – nur ohne Wiedererkennung.
    }
    await db.insertFace(
      FacesCompanion.insert(
        id: id,
        assetId: assetId,
        personId: Value(personId),
        boxX: box.x,
        boxY: box.y,
        boxW: box.width,
        boxH: box.height,
        cropRelativePath: Value(pfad),
        embedding: merkmal == null
            ? const Value.absent()
            : Value(blobFromEmbeddingFloats(merkmal)),
        schaerfe: Value(gesichtsschaerfe(ausschnitt)),
      ),
    );
    if (personId != null) await db.setPersonCoverIfUnset(personId, pfad);
    return (await db.facesForAsset(assetId)).where((f) => f.id == id).first;
  }
}
