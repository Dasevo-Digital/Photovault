import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import 'kamerarolle.dart';

/// Die Kamerarolle über `photo_manager`: MediaStore unter Android, die
/// Fotomediathek unter iOS.
///
/// Gesichert wird das **Original** (`originFile`) mit allen Aufnahmedaten.
/// Unter Android braucht das `ACCESS_MEDIA_LOCATION`, sonst entfernt das
/// System den Ort aus der Datei; unter iOS lädt `originFile` ein Original,
/// das nur in iCloud liegt, erst herunter. Ein Live Photo besteht aus Bild
/// und Video; beide gehen unter demselben Namensstamm zum Server, der sie
/// daran wieder zusammenfügt.
class PhotoManagerRolle implements Kamerarolle {
  PhotoManagerRolle({this.alben = const []});

  /// Die Kennungen der gewählten Alben; leer heisst alle Fotos.
  final List<String> alben;

  static const _seite = 500;

  /// Die Alben zur Auswahl, „Alle Fotos“ zuerst.
  static Future<List<AssetPathEntity>> albenZurAuswahl() =>
      PhotoManager.getAssetPathList(type: RequestType.common);

  @override
  Future<List<Rolleneintrag>> eintraege({required bool videos}) async {
    final pfade = await PhotoManager.getAssetPathList(
      type: videos ? RequestType.common : RequestType.image,
      onlyAll: alben.isEmpty,
    );
    final gewaehlt = alben.isEmpty
        ? pfade.where((x) => x.isAll)
        : pfade.where((x) => alben.contains(x.id));
    final gesehen = <String>{};
    final aus = <Rolleneintrag>[];
    for (final pfad in gewaehlt) {
      final n = await pfad.assetCountAsync;
      for (var start = 0; start < n; start += _seite) {
        final ende = start + _seite < n ? start + _seite : n;
        for (final a in await pfad.getAssetListRange(start: start, end: ende)) {
          if (gesehen.add(a.id)) aus.add(_eintrag(a));
        }
      }
    }
    aus.sort((a, b) => b.aufgenommen.compareTo(a.aufgenommen));
    return aus;
  }

  @override
  Future<int> loesche(List<String> ids) async =>
      (await PhotoManager.editor.deleteWithIds(ids)).length;

  static Rolleneintrag _eintrag(AssetEntity a) => Rolleneintrag(
    id: a.id,
    geaendert: a.modifiedDateTime,
    aufgenommen: a.createDateTime,
    video: a.type == AssetType.video,
    dateien: () => _dateien(a),
    quelle: a,
  );

  static Future<List<Rollendatei>?> _dateien(AssetEntity a) async {
    final original = await a.originFile;
    if (original == null) return null;
    // Der Name auf dem Telefon (IMG_1234.HEIC), mit der Endung der Datei,
    // die tatsächlich kommt – der Server erkennt das Format daran.
    final titel = await a.titleAsync;
    final stamm = titel.isEmpty
        ? p.basenameWithoutExtension(original.path)
        : p.basenameWithoutExtension(titel);
    String name(String pfad, {required String sonst}) {
      final endung = p.extension(pfad);
      return '$stamm${endung.isEmpty ? sonst : endung}';
    }

    final dateien = [
      Rollendatei(
        teil: a.type == AssetType.video ? 'video' : 'bild',
        name: name(
          original.path,
          sonst: titel.isEmpty ? '' : p.extension(titel),
        ),
        datei: original,
      ),
    ];
    if (a.isLivePhoto) {
      final film = await a.originFileWithSubtype;
      if (film != null && film.path != original.path) {
        dateien.add(
          Rollendatei(
            teil: 'video',
            name: name(film.path, sonst: '.MOV'),
            datei: film,
          ),
        );
      }
    }
    return dateien;
  }

  @override
  Future<void> aufraeumen() => PhotoManager.clearFileCache();
}
