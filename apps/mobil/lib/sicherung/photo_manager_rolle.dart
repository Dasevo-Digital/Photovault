import 'dart:io';

import 'package:flutter/services.dart';
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
///
/// **Bearbeitete Fotos (#271).** Unter iOS bleibt das Original einer
/// Bearbeitung in der Fotos-App unverändert; bis 3.50.3 kam die
/// Bearbeitung deshalb nie auf den Server. Hat ein Foto Anpassungen, geht
/// die bearbeitete Fassung als dritter Teil mit (`bearbeitet`, ein JPEG –
/// so rendert photo_manager sie); der Server legt sie über das Original.
///
/// **Serien (#314).** Von einer Serie liefert das Plugin nur das Titelbild.
/// Die übrigen Bilder kommen über einen eigenen Kanal dazu
/// (`ios/Gemeinsam/Zusatzfotos.swift`), auch ihre Dateien.
class PhotoManagerRolle implements Kamerarolle {
  PhotoManagerRolle({this.alben = const []});

  /// Die Kennungen der gewählten Alben; leer heisst alle Fotos.
  final List<String> alben;

  static const _seite = 500;

  static const _zusatzkanal = MethodChannel('de.dasevo.photovault/zusatzfotos');

  /// Die Alben zur Auswahl, „Alle Fotos“ zuerst.
  static Future<List<AssetPathEntity>> albenZurAuswahl() =>
      PhotoManager.getAssetPathList(type: RequestType.common);

  @override
  Future<List<Rolleneintrag>> eintraege({required bool videos}) async {
    final zusatz = await _zusatzfotos();
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
          if (gesehen.add(a.id)) aus.add(_eintrag(a, zusatz[a.id]));
        }
      }
    }
    for (final z in zusatz.values) {
      if ((videos || !z.video) && gesehen.add(z.id)) aus.add(_zusatzeintrag(z));
    }
    aus.sort((a, b) => b.aufgenommen.compareTo(a.aufgenommen));
    return aus;
  }

  @override
  Future<int> loesche(List<String> ids) async =>
      (await PhotoManager.editor.deleteWithIds(ids)).length;

  @override
  Future<List<String>> vorhanden(List<String> ids) async {
    final da = [
      for (final id in ids)
        if (await AssetEntity.fromId(id) != null) id,
    ];
    if (!Platform.isIOS || da.isEmpty) return da;
    final serie = await _zusatzkanal.invokeListMethod<String>('serienglieder', {
      'kennungen': da,
    });
    final glieder = serie!.toSet();
    return da.where((id) => !glieder.contains(id)).toList();
  }

  Future<Map<String, _Zusatzfoto>> _zusatzfotos() async {
    if (!Platform.isIOS) return const {};
    final liste = await _zusatzkanal.invokeListMethod<Map<Object?, Object?>>(
      'liste',
      {'alben': alben},
    );
    return {for (final w in liste!) w['id']! as String: _Zusatzfoto(w)};
  }

  static Rolleneintrag _zusatzeintrag(_Zusatzfoto z) => Rolleneintrag(
    id: z.id,
    geaendert: z.geaendert,
    aufgenommen: z.aufgenommen,
    video: z.video,
    dateien: () => _zusatzdateien(z.id),
    serie: z.serie,
    serientitel: z.titel,
    serienauswahl: z.auswahl,
  );

  static Future<List<Rollendatei>?> _zusatzdateien(String id) async {
    // Ein Download aus iCloud lässt sich drüben nicht abbrechen; der Lauf
    // soll trotzdem nicht ewig daran hängen. Beim nächsten Mal wieder.
    final liste = await _zusatzkanal
        .invokeListMethod<Map<Object?, Object?>>('dateien', {'kennung': id})
        .timeout(const Duration(minutes: 10), onTimeout: () => null);
    return liste
        ?.map(
          (w) => Rollendatei(
            teil: w['teil']! as String,
            name: w['name']! as String,
            datei: File(w['pfad']! as String),
          ),
        )
        .toList();
  }

  static Rolleneintrag _eintrag(AssetEntity a, _Zusatzfoto? z) => Rolleneintrag(
    id: a.id,
    geaendert: a.modifiedDateTime,
    aufgenommen: a.createDateTime,
    video: a.type == AssetType.video,
    dateien: () => _dateien(a),
    quelle: a,
    bearbeitetesVideo: a.type == AssetType.video && Platform.isIOS
        ? () => a.darwin.hasAdjustments
        : null,
    serie: z?.serie,
    serientitel: z?.titel ?? false,
    serienauswahl: z?.auswahl ?? false,
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
    if (a.type == AssetType.image &&
        Platform.isIOS &&
        await a.darwin.hasAdjustments) {
      final bearbeitet = await a.file;
      if (bearbeitet != null && bearbeitet.path != original.path) {
        dateien.add(
          Rollendatei(
            teil: 'bearbeitet',
            // Ein eigener Stamm: Ohne Original auf dem Server wird die
            // Datei gewöhnlich aufgenommen und soll dann nicht als Hälfte
            // eines Live Photos gelten.
            name: '${stamm}_bearbeitet.jpg',
            datei: bearbeitet,
          ),
        );
      }
    }
    return dateien;
  }

  @override
  Future<void> aufraeumen() async {
    await PhotoManager.clearFileCache();
    if (Platform.isIOS) await _zusatzkanal.invokeMethod<void>('aufraeumen');
  }
}

/// Ein Eintrag von `Zusatzfotos.liste`.
class _Zusatzfoto {
  _Zusatzfoto(Map<Object?, Object?> w)
    : id = w['id']! as String,
      geaendert = _zeit(w['geaendert']),
      aufgenommen = _zeit(w['aufgenommen']),
      video = w['video'] == true,
      serie = w['serie'] as String?,
      titel = w['titel'] == true,
      auswahl = w['auswahl'] == true;

  static DateTime _zeit(Object? ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms! as int);

  final String id;
  final DateTime geaendert;
  final DateTime aufgenommen;
  final bool video;
  final String? serie;
  final bool titel;
  final bool auswahl;
}
