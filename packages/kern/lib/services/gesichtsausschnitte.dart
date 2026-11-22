/// Gesichtsausschnitte aus ihrem Foto neu zeichnen: nach einer
/// Wiederherstellung (die Ausschnitte liegen nicht in der Sicherung) und
/// einmal je Bibliothek für die grau abgelegten (#459).
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../berechne.dart';
import '../db/database.dart';
import 'asset_display_path.dart';
import 'bild_lesen.dart';
import 'bildnachlauf.dart' show naechsterZusatz;
import 'blur_detection.dart';
import 'face_engine_service.dart';
import 'storage_paths.dart';
import 'tresorreihe.dart';

/// Ein Gesicht, dessen Ausschnitt neu entstehen soll: seine Kennung, sein
/// Kasten (Anteile am Bild) und der Ausschnitt, den es gerade hat.
typedef Ausschnittsstelle = ({
  String id,
  DetectedFace kasten,
  String? ausschnitt,
});

/// Zeichnet die Ausschnitte von [gesichter] neu, alle aus [asset] – aus
/// dem Bild, aus dem die Erkennung sie schnitt ([lesbarerPfad]). Das Foto
/// wird dafür einmal dekodiert, auch wenn mehrere Gesichter darauf sind.
///
/// **Kein Modell nötig.** Der Kasten steht in der Zeile;
/// [FaceEngineService.cropFaceImage] ist eine reine Bildoperation. Es wird
/// also nicht neu erkannt (das ergäbe andere Gesichter und damit
/// Doppelungen), sondern nur nachgezeichnet.
///
/// Jeder Ausschnitt kommt nach `ziel(gesicht)`. Ist das ein anderer Pfad
/// als bisher, ziehen Profilbilder mit (siehe
/// [PersonenAbfragen.setzeGesichtsausschnitt]), und die alte Datei wird
/// gelöscht. [verwerfen] kann einen neuen Ausschnitt ablehnen.
///
/// Abgelegt wird in der [inTresorreihe] und nur, solange die Aufnahme
/// nicht gesperrt ist (#430): Ein Sperren zwischen Dekodieren und
/// Schreiben liesse sonst einen Ausschnitt im Klartext im Tresor zurück.
/// Ein Gesicht, das inzwischen gelöscht ist oder einen anderen Ausschnitt
/// bekommen hat, bleibt, wie es ist.
///
/// Gibt die Kennungen der Gesichter zurück, die einen neuen Ausschnitt
/// bekamen – `null`, wenn das Bild nicht zu lesen war oder die Aufnahme
/// inzwischen gesperrt ist. Nicht aus der [inTresorreihe] heraus aufrufen.
Future<Set<String>?> zeichneAusschnitteNeu(
  AppDatabase db,
  StoragePaths paths,
  AssetData asset,
  List<Ausschnittsstelle> gesichter, {
  required String Function(Ausschnittsstelle gesicht) ziel,
  bool Function(img.Image ausschnitt)? verwerfen,
}) async {
  if (gesichter.isEmpty) return {};
  final Uint8List bytes;
  try {
    bytes = await (await paths.bereit(lesbarerPfad(asset))).readAsBytes();
  } catch (_) {
    // Fehlt, liegt auf einem getrennten Laufwerk oder ist kein Pfad der
    // Bibliothek – dann gibt es nichts nachzuzeichnen.
    return null;
  }
  final ausschnitte = await berechne(_schneideAus, (
    bytes,
    [for (final g in gesichter) g.kasten],
  ));
  if (ausschnitte == null) return null;
  return inTresorreihe(paths, () async {
    final jetzt = await db.assetById(asset.id);
    if (jetzt == null || jetzt.isLocked) return null;
    final neu = <String>{};
    for (var i = 0; i < gesichter.length; i++) {
      final g = gesichter[i];
      final bild = ausschnitte[i];
      if (verwerfen?.call(bild) ?? false) continue;
      final zeile = await (db.select(
        db.faces,
      )..where((f) => f.id.equals(g.id))).getSingleOrNull();
      if (zeile == null || zeile.cropRelativePath != g.ausschnitt) continue;
      final pfad = ziel(g);
      await FaceEngineService.saveFaceCrop(bild, paths.absolute(pfad));
      await db.setzeGesichtsausschnitt(
        g.id,
        pfad,
        schaerfe: gesichtsschaerfe(bild),
      );
      final alt = g.ausschnitt;
      if (alt != null && alt != pfad) {
        try {
          await paths.deletePermanently(alt);
        } catch (_) {
          // Ein Rest bleibt liegen; die Integritätsprüfung findet ihn.
        }
      }
      neu.add(g.id);
    }
    return neu;
  });
}

/// Im Isolat: das Bild dekodieren und die Kästen ausschneiden. Zurück
/// kommen nur die kleinen Ausschnitte, nicht das ganze Bild.
List<img.Image>? _schneideAus((Uint8List, List<DetectedFace>) eingabe) {
  final bild = decodeImageBytes(eingabe.$1);
  if (bild == null) return null;
  return [for (final k in eingabe.$2) FaceEngineService.cropFaceImage(bild, k)];
}

/// Ob [bild] grau ist: in jedem Punkt alle drei Kanäle gleich, bis auf
/// [toleranz].
///
/// Ein grau abgelegter Ausschnitt kommt nach dem JPEG genau so zurück –
/// die Farbkanäle sind dort konstant und überstehen die Kompression ohne
/// Abweichung. Ein farbiges Gesicht hat Hauttöne, deren Rot und Blau weit
/// auseinanderliegen.
bool istGrau(img.Image bild, {int toleranz = 2}) {
  if (bild.numChannels < 3) return true;
  for (final punkt in bild) {
    final r = punkt.r, g = punkt.g, b = punkt.b;
    if ((r - g).abs() > toleranz ||
        (g - b).abs() > toleranz ||
        (r - b).abs() > toleranz) {
      return false;
    }
  }
  return true;
}

/// Der einmalige Nachlauf für die grau abgelegten Ausschnitte (siehe
/// [erneuereGraueAusschnitte]).
const nachlaufFarbigeAusschnitte = 'nachlauf-farbige-ausschnitte-1';

/// Zeichnet die Gesichtsausschnitte neu, die grau abgelegt wurden (#459).
///
/// **Woher sie kommen.** Von #104 an färbte `computeBlurScore` den
/// 160er-Ausschnitt in place grau, bevor die Erkennung ihn als JPEG ablegte
/// – in der App, am Server und in der Rechenhilfe. Jedes in dieser Zeit
/// erkannte Gesicht steht seither grau in den Personen.
///
/// **Nur, was wirklich grau ist** (siehe [istGrau]), und nur aus Fotos:
/// Das Standbild eines Videos, aus dem ein Gesicht stammt, steht nirgends.
/// Ist auch der neue Ausschnitt grau, war das Foto schwarzweiss; dann
/// bleibt der alte.
///
/// **Ein neuer Name.** Der neue Ausschnitt kommt nach
/// `faces/<id>-2.jpg`, der alte wird gelöscht. Verbundene Geräte holen
/// eine Datei nur, wenn sie unter ihrem Namen fehlt – unter dem alten Namen
/// zeigten sie weiter den grauen. So kommt mit der geänderten Zeile der neue
/// Name an, ebenso im Profilbild der Person.
///
/// **Was wartet.** Gesperrte Fotos werden nicht angefasst – ihr Ausschnitt
/// liegt als Chiffrat da –, Fotos im Papierkorb auch nicht, und eines,
/// dessen Original fehlt (ein getrenntes Laufwerk), lässt sich nicht
/// nachzeichnen. Ihre Gesichter merkt sich die Bibliothek
/// ([offeneAusschnitte]); ein Lauf mit [nur] nimmt sich später nur sie
/// vor.
///
/// In Etappen wie [vergroessereVorschauen]: geordnet nach Aufnahme, ab der
/// Aufnahme nach [ab], höchstens [frist] lang; `weiter == null` heisst
/// fertig. [fortschritt] zählt Gesichter.
Future<({int neu, int offen, String? weiter})> erneuereGraueAusschnitte(
  AppDatabase db,
  StoragePaths paths, {
  Set<String>? nur,
  String? ab,
  Duration? frist,
  bool Function()? abbrechen,
  void Function(int erledigt, int gesamt)? fortschritt,
}) async {
  final f = db.faces, a = db.assets;
  final abfrage =
      db.selectOnly(f).join([innerJoin(a, a.id.equalsExp(f.assetId))])
        ..addColumns([
          f.id,
          f.assetId,
          f.boxX,
          f.boxY,
          f.boxW,
          f.boxH,
          f.cropRelativePath,
          a.type,
          a.isLocked,
          a.isTrashed,
        ])
        ..where(f.cropRelativePath.isNotNull())
        ..orderBy([OrderingTerm.asc(f.assetId), OrderingTerm.asc(f.id)]);
  if (nur != null && nur.length <= 500) abfrage.where(f.id.isIn(nur));

  final bisher = await offeneAusschnitte(paths);
  final erledigt = <String>{};
  final wartet = <String>{};
  final nachAufnahme = <String, List<_Zeile>>{};
  final gefunden = <String>{};
  for (final z in await abfrage.get()) {
    final id = z.read(f.id)!;
    if (nur != null && !nur.contains(id)) continue;
    gefunden.add(id);
    final aufnahme = z.read(f.assetId)!;
    if (ab != null && aufnahme.compareTo(ab) <= 0) continue;
    final ausschnitt = z.read(f.cropRelativePath)!;
    // Schon neu gezeichnet (er trägt einen Zusatz): nach dem Fehler
    // entstanden und farbig.
    if (ausschnitt.replaceAll(r'\', '/') != paths.faceRelativePath(id)) {
      erledigt.add(id);
      continue;
    }
    nachAufnahme
        .putIfAbsent(aufnahme, () => [])
        .add(
          _Zeile(
            id: id,
            kasten: DetectedFace(
              z.read(f.boxX)!,
              z.read(f.boxY)!,
              z.read(f.boxW)!,
              z.read(f.boxH)!,
              1.0,
            ),
            ausschnitt: ausschnitt,
            foto: z.read(a.type) == 'IMAGE',
            gesperrt: z.read(a.isLocked)!,
            papierkorb: z.read(a.isTrashed)!,
          ),
        );
  }
  // Was nachzuholen war und inzwischen gelöscht ist, wartet nicht mehr.
  if (nur != null) erledigt.addAll(nur.difference(gefunden));

  final aufnahmen = nachAufnahme.keys.toList();
  final gesamt = nachAufnahme.values.fold(0, (n, l) => n + l.length);
  var gezaehlt = 0;
  var neu = 0;
  var bearbeitet = 0;
  String? letzte = ab;
  final uhr = Stopwatch()..start();
  fortschritt?.call(0, gesamt);

  Future<({int neu, int offen, String? weiter})> ende(String? weiter) async {
    final offen = bisher.difference(erledigt).union(wartet);
    await _merkeOffene(paths, offen);
    return (neu: neu, offen: offen.length, weiter: weiter);
  }

  var i = 0;
  while (i < aufnahmen.length) {
    // Ein Stapel von rund 200 Ausschnitten wird in einem Isolat geprüft –
    // einer je Aufnahme kostete mehr für das Isolat als für das Bild.
    final stapel = <String>[];
    var groesse = 0;
    while (i < aufnahmen.length && (stapel.isEmpty || groesse < 200)) {
      stapel.add(aufnahmen[i]);
      groesse += nachAufnahme[aufnahmen[i]]!.length;
      i++;
    }
    final zuPruefen = [
      for (final id in stapel)
        for (final z in nachAufnahme[id]!)
          if (z.foto && !z.gesperrt && !z.papierkorb) z,
    ];
    final grau = <String, bool?>{};
    final antworten = zuPruefen.isEmpty
        ? const <bool?>[]
        : await berechne(_sindGrau, [
            for (final z in zuPruefen) _absolut(paths, z.ausschnitt),
          ]);
    for (var k = 0; k < zuPruefen.length; k++) {
      grau[zuPruefen[k].id] = antworten[k];
    }

    for (final id in stapel) {
      if ((abbrechen?.call() ?? false) ||
          (frist != null && bearbeitet > 0 && uhr.elapsed >= frist)) {
        return ende(letzte ?? '');
      }
      final zeilen = nachAufnahme[id]!;
      final erste = zeilen.first;
      if (!erste.foto) {
        // Aus welchem Standbild eines Videos ein Gesicht stammt, steht
        // nirgends; nachzeichnen hiesse raten.
        erledigt.addAll(zeilen.map((z) => z.id));
      } else if (erste.gesperrt || erste.papierkorb) {
        wartet.addAll(zeilen.map((z) => z.id));
      } else {
        final graue = [
          for (final z in zeilen)
            if (grau[z.id] ?? false) z,
        ];
        final unklar = zeilen.any((z) => grau[z.id] == null);
        final ids = zeilen.map((z) => z.id);
        // Mit dem Stand von jetzt, denn die Liste ist vom Beginn des Laufs.
        // Nur nötig, wenn etwas zu tun ist oder sich ein Ausschnitt nicht
        // lesen liess – das Chiffrat eines eben gesperrten Fotos etwa.
        final asset = graue.isNotEmpty || unklar
            ? await db.assetById(id)
            : null;
        if (asset != null && (asset.isLocked || asset.isTrashed)) {
          wartet.addAll(ids);
        } else if (graue.isEmpty || asset == null) {
          erledigt.addAll(ids);
        } else {
          final grauIds = graue.map((z) => z.id).toSet();
          erledigt.addAll(ids.where((g) => !grauIds.contains(g)));
          if (!await _originalDa(paths, asset)) {
            wartet.addAll(grauIds);
          } else {
            final r = await zeichneAusschnitteNeu(
              db,
              paths,
              asset,
              [
                for (final z in graue)
                  (id: z.id, kasten: z.kasten, ausschnitt: z.ausschnitt),
              ],
              ziel: (g) => paths.faceRelativePath(
                g.id,
                naechsterZusatz(g.id, g.ausschnitt),
              ),
              verwerfen: istGrau,
            );
            if (r != null) {
              neu += r.length;
              erledigt.addAll(grauIds);
            } else if ((await db.assetById(id))?.isLocked ?? false) {
              // Inzwischen gesperrt: nach dem Entsperren noch einmal.
              wartet.addAll(grauIds);
            } else {
              // Das Bild lässt sich nicht lesen – das ändert sich nicht.
              erledigt.addAll(grauIds);
            }
          }
        }
      }
      gezaehlt += zeilen.length;
      bearbeitet++;
      letzte = id;
      fortschritt?.call(gezaehlt, gesamt);
    }
  }
  return ende(null);
}

class _Zeile {
  const _Zeile({
    required this.id,
    required this.kasten,
    required this.ausschnitt,
    required this.foto,
    required this.gesperrt,
    required this.papierkorb,
  });

  final String id;
  final DetectedFace kasten;
  final String ausschnitt;
  final bool foto;
  final bool gesperrt;
  final bool papierkorb;
}

String _absolut(StoragePaths paths, String relativ) {
  try {
    return paths.absolute(relativ).path;
  } on ArgumentError {
    return '';
  }
}

/// Im Isolat: je Datei, ob sie ein grauer Ausschnitt ist – `null`, wenn
/// sie fehlt oder sich nicht lesen lässt.
List<bool?> _sindGrau(List<String> dateien) => [
  for (final d in dateien) _istGraueDatei(d),
];

bool? _istGraueDatei(String datei) {
  if (datei.isEmpty) return null;
  try {
    final bild = decodeImageBytes(File(datei).readAsBytesSync());
    return bild == null ? null : istGrau(bild);
  } catch (_) {
    return null;
  }
}

Future<bool> _originalDa(StoragePaths paths, AssetData asset) async {
  try {
    return await (await paths.bereit(lesbarerPfad(asset))).exists();
  } catch (_) {
    return false;
  }
}

/// Die Gesichter, die [erneuereGraueAusschnitte] noch nicht nachzeichnen
/// konnte (gesperrt, im Papierkorb, Original fehlt).
///
/// In einer kleinen Datei der Bibliothek wie der Stand der Modelle, nur auf
/// diesem Rechner: Sie gilt der Ablage hier, nicht der Datenbank, die ein
/// Gerät abgleicht. Fehlt sie oder ist sie beschädigt, wartet nichts.
Future<Set<String>> offeneAusschnitte(StoragePaths paths) async {
  final datei = _offenDatei(paths);
  try {
    if (!await datei.exists()) return {};
    final inhalt = jsonDecode(await datei.readAsString());
    if (inhalt is! Map || inhalt['format'] != 1) return {};
    final ids = inhalt['gesichter'];
    if (ids is! List) return {};
    return {...ids.whereType<String>()};
  } catch (_) {
    return {};
  }
}

Future<void> _merkeOffene(StoragePaths paths, Set<String> ids) async {
  final datei = _offenDatei(paths);
  if (ids.isEmpty) {
    if (await datei.exists()) await datei.delete();
    return;
  }
  await datei.writeAsString(
    jsonEncode({
      'format': 1,
      'gesichter': [...ids]..sort(),
    }),
  );
}

File _offenDatei(StoragePaths paths) =>
    File(p.join(paths.root.path, 'ausschnitte_offen_v1.json'));
