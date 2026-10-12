import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../services/import_service.dart';
import '../services/motion_photo.dart';
import '../services/reverse_geocoder.dart';
import '../services/storage_paths.dart';
import 'auswertungen.dart';

/// Was mit einer Aufnahme gleich nach dem Import geschieht: Live Photos
/// zusammenführen, Kameravorgaben und Regeln anwenden, Ortsnamen eintragen.
///
/// In der App wie auf dem Server dieselbe Arbeit – darum im Kern. Die
/// teuren Auswertungen gehören nicht hierher, sie laufen danach (siehe
/// [Auswertungen]).
class Nachbearbeitung {
  Nachbearbeitung({
    required this.db,
    required this.paths,
    required this.importe,
    required this.auswertungen,
    ReverseGeocoder? Function()? ortsverzeichnis,
    Future<void> Function()? ortsverzeichnisBereit,
  }) : ortsverzeichnis = ortsverzeichnis ?? (() => null),
       ortsverzeichnisBereit = ortsverzeichnisBereit ?? (() async {});

  final AppDatabase db;
  final StoragePaths paths;

  /// Der Import, über den das Video eines Motion Photos hereinkommt –
  /// erst bei Bedarf geholt, weil nicht jeder Aufrufer einen hat.
  final ImportService Function() importe;
  final Auswertungen auswertungen;

  /// Das Ortsverzeichnis (GeoNames), falls eines geladen ist.
  final ReverseGeocoder? Function() ortsverzeichnis;

  /// Wird fertig, sobald das Ortsverzeichnis gelesen ist.
  final Future<void> Function() ortsverzeichnisBereit;

  static const _livePhotoImageExts = {'.heic', '.heif', '.jpg', '.jpeg'};
  static const _livePhotoVideoExt = '.mov';

  /// Nachbereitung direkt beim Import – bewusst NUR ressourcenschonende
  /// Schritte: reine Datenbankarbeit und ein Nachschlagen im bereits
  /// geladenen Ortsverzeichnis. Kein Dekodieren, keine Modell-Inferenz.
  ///
  /// Alles Rechenintensive (Gesichter, Unschärfe, Texterkennung, CLIP,
  /// Bildbeschreibung) läuft NACH dem Import als Hintergrundaufgabe, siehe
  /// [Analysestufe]. Vorher lief es hier inline und machte den
  /// Import bei mehreren tausend Fotos unzumutbar langsam: fünf schwere
  /// Durchläufe je Foto, nacheinander.
  Future<void> neueAufnahme(String assetId) async {
    final asset = await db.assetById(assetId);
    if (asset == null) return;

    await verknuepfeLivePhoto(asset);
    await applyCameraPreset(
      asset.id,
      cameraMake: asset.cameraMake,
      cameraModel: asset.cameraModel,
    );
    await auswertungen.applyAutomationRules(
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
    // nebenher lädt, wäre ein Import in der ersten halben Sekunde nach dem
    // Start sonst still ohne Ortsnamen geblieben.
    await ortsverzeichnisBereit();
    final geocoder = ortsverzeichnis();
    if (geocoder != null && asset.latitude != null && asset.longitude != null) {
      final result = geocoder.lookup(asset.latitude!, asset.longitude!);
      if (result != null) {
        await db.setLocationNames(
          asset.id,
          country: result.country,
          state: result.state,
          city: result.city,
        );
      }
    }
  }

  /// Prüft, ob es zu diesem frisch importierten Asset schon einen
  /// unverknüpften Partner mit demselben Dateinamen (ohne Endung) gibt –
  /// z.B. das HEIC-Standbild zu einem bereits importierten MOV oder
  /// umgekehrt – und verknüpft die beiden als Live Photo.
  Future<void> verknuepfeLivePhoto(AssetData asset) async {
    final ext = p.extension(asset.originalFileName).toLowerCase();
    final isImage = asset.type == 'IMAGE';
    if (isImage && !_livePhotoImageExts.contains(ext)) return;
    if (!isImage && ext != _livePhotoVideoExt) return;

    final stem = p
        .basenameWithoutExtension(asset.originalFileName)
        .toLowerCase();
    final candidates = await db.unlinkedAssetsOfType(
      isImage ? 'VIDEO' : 'IMAGE',
    );
    for (final candidate in candidates) {
      if (candidate.id == asset.id) continue;
      final candidateExt = p
          .extension(candidate.originalFileName)
          .toLowerCase();
      if (isImage && candidateExt != _livePhotoVideoExt) continue;
      if (!isImage && !_livePhotoImageExts.contains(candidateExt)) continue;
      final candidateStem = p
          .basenameWithoutExtension(candidate.originalFileName)
          .toLowerCase();
      if (candidateStem == stem) {
        await db.linkAssets(asset.id, candidate.id);
        return;
      }
    }
    if (isImage && (ext == '.jpg' || ext == '.jpeg')) {
      await motionPhotoAbtrennen(asset);
    }
  }

  /// Holt das Video aus einem Motion Photo (siehe
  /// `motion_photo.dart`) und verknüpft es mit dem Foto – wie die
  /// Hälften eines Live Photos.
  ///
  /// **Das Original bleibt, wie es ist.** Das Video liegt danach zweimal
  /// in der Bibliothek, im JPEG und als eigene Datei. Das JPEG zu kürzen
  /// hiesse, eine Originaldatei umzuschreiben; das tut diese App nirgends.
  ///
  /// Gelesen wird erst Anfang und Ende; ganz nur, was danach aussieht.
  /// Sonst läse die Aufgabe „Live Photos“ jedes JPEG der Bibliothek ganz.
  Future<void> motionPhotoAbtrennen(AssetData foto) async {
    final datei = paths.absolute(foto.relativePath);
    Directory? ordner;
    try {
      final groesse = await datei.length();
      if (groesse < 64) return;
      final zugriff = await datei.open();
      final Uint8List kopf, ende;
      try {
        kopf = await zugriff.read(math.min(motionPhotoKopf, groesse));
        await zugriff.setPosition(math.max(0, groesse - motionPhotoEnde));
        ende = await zugriff.read(motionPhotoEnde);
      } finally {
        await zugriff.close();
      }
      if (!siehtNachMotionPhotoAus(kopf, ende)) return;
      final alles = await datei.readAsBytes();
      final anfang = motionPhotoAnfang(alles);
      if (anfang == null) return;

      ordner = await Directory.systemTemp.createTemp('pv_motion_');
      final film = File(
        p.join(
          ordner.path,
          '${p.basenameWithoutExtension(foto.originalFileName)}.mp4',
        ),
      );
      await film.writeAsBytes(Uint8List.sublistView(alles, anfang));
      final ergebnis = await importe().importFile(film.path);
      final id = ergebnis.assetId;
      if (ergebnis.outcome != ImportOutcome.imported || id == null) return;
      // Das angehängte Video trägt selten eigene Angaben; es gehört zum
      // Foto und bekommt dessen Zeit und Ort.
      await db.uebernimmFotoangabenFuerBewegtbild(id, foto);
      await db.linkAssets(foto.id, id);
    } on FileSystemException {
      // Datei weg oder nicht lesbar – dann eben kein Bewegtbild.
    } finally {
      await ordner?.delete(recursive: true);
    }
  }

  /// Wendet ein evtl. für die erkannte Kamera hinterlegtes Preset an
  /// (Zielalbum, Tags, automatisches Favorisieren) – siehe
  /// CameraPresetsScreen. Für Videos (keine EXIF-Kamera) und Fotos ohne
  /// passendes Preset ein günstiges No-Op (siehe AppDatabase.cameraPresetFor).
  Future<void> applyCameraPreset(
    String assetId, {
    required String? cameraMake,
    required String? cameraModel,
  }) async {
    final preset = await db.cameraPresetFor(cameraMake, cameraModel);
    if (preset == null) return;
    if (preset.targetAlbumId != null) {
      await db.fuehreAus(AlbumFuellen(preset.targetAlbumId!, [assetId]));
    }
    if (preset.autoFavorite) {
      await db.fuehreAus(FavoritSetzen([assetId], true));
    }
    final tagIds = await db.tagIdsForCameraPreset(preset.id);
    for (final tagId in tagIds) {
      await db.fuehreAus(SchlagwortAnheftenPerKennung(assetId, tagId));
    }
  }
}
