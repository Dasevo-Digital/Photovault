import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../state/library_state.dart';
import 'face_engine_service.dart';

/// **Ein von Hand aufgezogenes Gesicht anlegen.**
///
/// Stand bisher nur in `FaceReviewScreen`. Seit die Vollbildansicht dasselbe
/// kann, gibt es zwei Aufrufer – und ein Weg, der an zwei Stellen steht,
/// läuft auseinander. Hier ist besonders viel zu verlieren: Ausschnitt auf
/// der Platte, Zeile in der Datenbank und Profilbild der Person hängen
/// zusammen, und eine Fassung, die einen der drei Schritte vergisst, lässt
/// eine verwaiste Datei oder eine Person ohne Bild zurück.
///
/// Gibt die Kennung des angelegten Gesichts zurück, oder `null`, wenn sich
/// das Bild nicht dekodieren liess.
///
/// [kasten] ist der Rahmen als **Anteil** des Bildes (0..1), so wie die
/// Datenbank ihn führt.
///
/// [beiEinbettungsfehler] wird gerufen, wenn sich zwar der Ausschnitt
/// speichern liess, das Wiedererkennungsmodell aber nicht. Der Aufrufer
/// entscheidet, wie er das sagt; **abgebrochen wird nicht**. Das ist
/// Absicht: Der Ausschnitt liegt zu diesem Zeitpunkt schon auf der Platte,
/// und ein Abbruch hinterliesse ihn ohne die Zeile, die ihn erklärt – ein
/// verwaistes Bild ohne jede Meldung. Ohne Einbettung ist das Gesicht
/// zugeordnet, taugt nur nicht zur Wiedererkennung.
Future<String?> gesichtVonHandAnlegen({
  required LibraryState library,
  required String assetId,
  required File bilddatei,
  required Rect kasten,
  required String personId,
  void Function(Object fehler)? beiEinbettungsfehler,
}) async {
  // `decodeImage` liefert bei einer beschädigten Datei nicht immer `null`,
  // sondern wirft auch – gemessen an vier zufälligen Bytes. Beides heisst
  // hier dasselbe: kein Bild, kein Gesicht.
  final img.Image? gelesen;
  try {
    gelesen = img.decodeImage(await bilddatei.readAsBytes());
  } catch (_) {
    return null;
  }
  if (gelesen == null) return null;
  final bild = gelesen;

  final gesichtId = const Uuid().v4();
  final box = DetectedFace(
      kasten.left, kasten.top, kasten.width, kasten.height, 1.0);

  final ausschnittPfad = library.paths.faceRelativePath(gesichtId);
  await FaceEngineService.saveFaceCrop(
    FaceEngineService.cropFaceImage(bild, box),
    library.paths.absolute(ausschnittPfad),
  );

  Float32List? einbettung;
  try {
    einbettung = await library.faceEngineHalter.mit<Float32List?>((engine) {
      return engine.canEmbed
          ? engine.embedFace(bild, box)
          : Future<Float32List?>.value(null);
    });
  } catch (e) {
    beiEinbettungsfehler?.call(e);
  }

  await library.db.insertFace(FacesCompanion.insert(
    id: gesichtId,
    assetId: assetId,
    personId: Value(personId),
    boxX: box.x,
    boxY: box.y,
    boxW: box.width,
    boxH: box.height,
    cropRelativePath: Value(ausschnittPfad),
    embedding: einbettung != null
        ? Value(Uint8List.view(einbettung.buffer, einbettung.offsetInBytes,
            einbettung.lengthInBytes))
        : const Value.absent(),
  ));
  await library.db.setPersonCoverIfUnset(personId, ausschnittPfad);
  return gesichtId;
}

/// Ob ein aufgezogener Rahmen gross genug ist, um ein Gesicht zu sein.
///
/// **In Anteilen, nicht in Bildpunkten.** Eine Grenze in Punkten hinge an
/// der Fenstergrösse: Derselbe Wisch ergäbe auf einem grossen Bildschirm
/// einen gültigen Rahmen und auf einem kleinen nicht. Ein Promille
/// Kantenlänge ist auf jedem Bildschirm ein Versehen.
///
/// Genau auf der Grenze ist nichts zugesichert: `Rect.fromLTWH(0.1, …, 0.01)`
/// hat eine Breite von 0,009999999999999995, weil die Kanten und nicht die
/// Breite gespeichert werden. Für die Frage „Zug oder Tipp?" spielt das
/// keine Rolle, und ein Epsilon hier wäre eine Genauigkeit, die es nicht
/// gibt.
bool rahmenGrossGenug(Rect kasten) =>
    kasten.width >= 0.01 && kasten.height >= 0.01;

/// Rechnet einen Zug über dem Foto in einen Kasten in **Anteilen** um.
///
/// [von] und [bis] sind Punkte der Fotofläche, nicht des Fensters – in der
/// Vollbildansicht bekommt der Zeichner sie so, weil PhotoView dort ein
/// Kind bekommt, das genau das Foto ist (`childSize`).
///
/// **Die Umkehrung von [Gesichtsrahmen].** Dort wird `boxX * flaeche.width`
/// gerechnet, hier `punkt / flaeche.width`. Liefen die beiden auseinander,
/// läge ein frisch gezogener Rahmen neben dem Gesicht, um das er gezogen
/// wurde – und niemand käme auf die Idee, das an zwei verschiedenen Stellen
/// zu suchen.
///
/// Die Richtung des Zuges ist egal: Von rechts unten nach links oben ergibt
/// denselben Kasten. Und was über den Bildrand hinausgeht, wird
/// abgeschnitten – wer darüber hinauszieht, meint den Rand.
Rect kastenAusZug(Offset von, Offset bis, Size flaeche) {
  if (flaeche.width <= 0 || flaeche.height <= 0) return Rect.zero;
  final r = Rect.fromPoints(von, bis);
  return Rect.fromLTRB(
    (r.left / flaeche.width).clamp(0.0, 1.0),
    (r.top / flaeche.height).clamp(0.0, 1.0),
    (r.right / flaeche.width).clamp(0.0, 1.0),
    (r.bottom / flaeche.height).clamp(0.0, 1.0),
  );
}
