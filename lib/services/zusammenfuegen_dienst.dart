import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:kern/abgleich/tus.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/asset_display_path.dart' show lesbarerPfad;
import 'package:kern/services/dateikennung.dart';
import 'package:kern/services/zusammenfuegen/ablage.dart';
import 'package:kern/services/zusammenfuegen/zusammenfuegen.dart';
import 'package:path/path.dart' as p;

import '../state/library_state.dart';
import 'native_image_converter.dart';

/// Unter diesem Schlüssel steht ein Zusammenfügen (#498) in der
/// Aufgabenleiste. Ein fester Schlüssel und kein neuer je Lauf: Zwei
/// Panoramen zugleich hielten zweimal ein halbes Gigabyte, und die
/// Aufgabenleiste weist ein zweites ab, solange das erste läuft.
const zusammenfuegenSchluessel = 'zusammenfuegen';

/// Was ein gelungener Lauf meldet: die neue Aufnahme, und wie viele der
/// Quellen darin stecken – ein Panorama nimmt nur, was sich verbinden
/// liess.
class Fuegeausgang {
  const Fuegeausgang(this.assetId, this.verwendet, this.angeboten);

  final String assetId;
  final int verwendet;
  final int angeboten;
}

/// Die Aufnahmen aus [ids], die als Quelle taugen ([alsQuelleGeeignet]),
/// nach Aufnahmezeit, und wie viele herausfielen.
Future<({List<AssetData> quellen, int ausgelassen})> zusammenfuegbare(
  AppDatabase db,
  List<String> ids,
) async {
  final alle = await db.assetsByIds(ids);
  final quellen = [
    for (final a in alle)
      if (alsQuelleGeeignet(a)) a,
  ]..sort((a, b) => a.fileCreatedAt.compareTo(b.fileCreatedAt));
  return (quellen: quellen, ausgelassen: ids.length - quellen.length);
}

/// Fügt [quellen] zu einem Bild der Art [art] zusammen und legt es als
/// Variante vor ihnen ab – als Strom für die Aufgabenleiste (0 bis 100).
///
/// Drei Abschnitte: die Quellen lesbar bereitstellen (bis 15), im eigenen
/// Isolat rechnen (bis 95), ablegen. Wer abbricht, beendet das Isolat
/// sofort; der Arbeitsordner wird in jedem Fall geräumt. Scheitert es,
/// endet der Strom mit dem Fehler – [Zusammenfuegefehler] für die
/// bekannten Gründe.
Stream<ImportProgress> zusammenfuegenLauf(
  LibraryState library, {
  required List<AssetData> quellen,
  required Fuegeart art,
  bool ausrichten = true,
  bool drehung = true,
  bool zuschneiden = true,
  void Function(Fuegeausgang ausgang)? fertig,
}) async* {
  const gesamt = 100;
  final arbeit = await Directory.systemTemp.createTemp('pv_fuegen_');
  try {
    yield ImportProgress(0, gesamt);
    final dateien = <String>[];
    for (var i = 0; i < quellen.length; i++) {
      dateien.add(await _bereitstellen(library, quellen[i], arbeit, i, art));
      yield ImportProgress(
        (i + 1) * 15 ~/ quellen.length,
        gesamt,
        currentFile: quellen[i].originalFileName,
      );
    }
    Fuegeergebnis? ergebnis;
    await for (final s in fuegeZusammen(
      Fuegeauftrag(
        art: art,
        dateien: dateien,
        ziel: p.join(arbeit.path, 'ergebnis.jpg'),
        brennweiten35: [for (final q in quellen) q.focalLength35mm],
        ausrichten: ausrichten,
        drehung: drehung,
        zuschneiden: zuschneiden,
      ),
    )) {
      if (s.ergebnis != null) {
        ergebnis = s.ergebnis;
      } else {
        yield ImportProgress(
          15 + s.erledigt * 80 ~/ math.max(1, s.gesamt),
          gesamt,
        );
      }
    }
    final e = ergebnis;
    if (e == null) throw StateError('pv_fuegen_ohne_ergebnis');
    final verwendet = [for (final i in e.verwendet) quellen[i]];
    final leit = leitquelle(verwendet);
    final id = await legeZusammengefuegtesAb(
      db: library.db,
      quellen: verwendet,
      jpeg: await File(e.datei).readAsBytes(),
      art: art,
      einlesen: (jpeg, name) => library.verbunden
          ? _hochladen(library, jpeg, name, leit.fileCreatedAt)
          : library.sichereNeuesFoto(jpeg, name),
    );
    fertig?.call(Fuegeausgang(id, verwendet.length, quellen.length));
    yield ImportProgress(gesamt, gesamt, assetId: id, getan: 1);
  } finally {
    try {
      await arbeit.delete(recursive: true);
    } on FileSystemException {
      // Liegt im Temp-Ordner und wird dort ohnehin geräumt.
    }
  }
}

/// Macht aus [a] eine Datei, die das Isolat lesen kann (JPEG oder PNG),
/// und gibt ihren Pfad.
///
/// **Aus dem Original, nicht aus der Entwicklung.** Eine Belichtungsreihe
/// lebt davon, dass ihre Aufnahmen verschieden belichtet sind; eine je
/// Bild nachgeregelte Belichtung verschöbe genau das. Das Ergebnis lässt
/// sich danach entwickeln wie jedes Foto.
///
/// Ein JPEG oder PNG wird gelesen, wie es in der Bibliothek liegt (mit
/// Server vorher geholt, `paths.bereit`). Alles andere – HEIC, RAW, ein
/// JPEG über der Grösse, die das Ergebnis braucht – wandeln die
/// Bildwerkzeuge (RAW mit Objektivkorrektur, wie für die Vorschau). Geht
/// auch das nicht, bleibt die lesbare Fassung ([lesbarerPfad], die
/// Vorschau mit gut 2000 Punkten); dann wird das Ergebnis eben kleiner.
Future<String> _bereitstellen(
  LibraryState library,
  AssetData a,
  Directory arbeit,
  int nummer,
  Fuegeart art,
) async {
  final grenze = art.quellenPixel;
  final File original;
  try {
    original = await library.paths.bereit(a.relativePath);
  } on Object {
    throw Zusammenfuegefehler(Fuegegrund.unlesbar, quelle: nummer);
  }
  final kennung = await _kennung(original);
  final b = a.widthPx ?? 0, h = a.heightPx ?? 0;
  final zuGross = b * h > grenze;
  if ((kennung == '.jpg' || kennung == '.png') && !zuGross) {
    return original.path;
  }
  final kante = zuGross
      ? (math.max(b, h) * math.sqrt(grenze / (b * h))).floor()
      : null;
  final jpeg = await NativeImageConverter.convertToJpegBytes(
    original,
    maxDimension: kante,
    quality: 0.95,
  );
  if (jpeg != null) {
    final ziel = File(p.join(arbeit.path, 'quelle_$nummer.jpg'));
    await ziel.writeAsBytes(jpeg, flush: true);
    return ziel.path;
  }
  if (kennung == '.jpg' || kennung == '.png') return original.path;
  try {
    final lesbar = await library.paths.bereit(lesbarerPfad(a));
    final k = await _kennung(lesbar);
    if (k == '.jpg' || k == '.png') return lesbar.path;
  } on Object {
    // Unten gemeldet.
  }
  throw Zusammenfuegefehler(Fuegegrund.unlesbar, quelle: nummer);
}

Future<String?> _kennung(File datei) async {
  try {
    final r = await datei.open();
    try {
      return kennungAus(await r.read(kennungBytes));
    } finally {
      await r.close();
    }
  } on FileSystemException {
    return null;
  }
}

/// Verbunden geht das Ergebnis zum Server wie jeder Import (tus,
/// `api/v1/hochladen`); er liest Zeit und Ort aus der Datei und meldet die
/// neue Kennung. Danach holt der Abgleich die Zeile, und der
/// Variantenstapel geht als Befehl hinterher.
Future<String?> _hochladen(
  LibraryState library,
  Uint8List jpeg,
  String name,
  DateTime zeit,
) async {
  final a = library.abgleich;
  if (a == null) throw StateError('pv_nicht_verbunden');
  final ordner = await Directory.systemTemp.createTemp('pv_fuegen_hoch_');
  try {
    final datei = File(p.join(ordner.path, name));
    await datei.writeAsBytes(jpeg, flush: true);
    final kopf = await TusHochladen(a.verbindung).lade(
      datei,
      'api/v1/hochladen',
      {'filename': name, 'geaendert': '${zeit.millisecondsSinceEpoch}'},
    );
    switch (kopf['pv-ausgang']) {
      case 'imported':
        await a.empfange();
        return kopf['pv-aufnahme'];
      case 'duplicateSkipped':
        return null;
      default:
        throw StateError(
          Uri.decodeComponent(kopf['pv-fehler'] ?? 'pv_import_gescheitert'),
        );
    }
  } finally {
    await ordner.delete(recursive: true);
  }
}
