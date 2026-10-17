/// Einmalige Nachläufe an den Bilddateien einer Bibliothek: was ein Fehler
/// beim Import hinterlassen hat, wird für die schon vorhandenen Aufnahmen
/// nachgeholt. Wer sie aufruft, merkt sich ihren Schlüssel in den
/// Aufgabenläufen, sodass jeder je Bibliothek genau einmal läuft.
library;

import 'dart:io';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'dateikopf.dart';
import 'import_service.dart';
import 'storage_paths.dart';

/// Die echte Bildgrösse statt der Grösse der Vorschau (siehe
/// dateikopf.dart).
const nachlaufOriginalmasse = 'nachlauf-originalmasse-1';

/// Neue Vorschauen für DNG-Dateien, die LibRaw zu dunkel entwickelt hat.
const nachlaufRohvorschau = 'nachlauf-rohvorschau-1';

/// Formate, deren Grösse bisher aus der gewandelten Vorschau kam.
const _gewandelteFormate = {
  'heic', 'heif', 'avif', 'avifs', 'psd', 'tif', 'tiff', //
  'dng', 'cr2', 'cr3', 'nef', 'nrw', 'arw', 'srf', 'sr2', 'orf', 'rw2',
  'raf', 'pef', 'srw', 'raw', 'rwl', '3fr', 'iiq', 'erf', 'kdc', 'dcr',
  'mos', 'mef', 'mrw', 'x3f',
};

/// Trägt für HEIC, RAW, PSD und grosse TIFF die Grösse aus dem Dateikopf
/// nach. Gibt zurück, wie viele Aufnahmen eine neue Grösse bekamen.
///
/// Gesperrte Aufnahmen bleiben aussen vor: Ihr Original liegt
/// verschlüsselt, und sein Kopf ist nicht zu lesen.
Future<int> berichtigeOriginalmasse(
  AppDatabase db,
  StoragePaths paths, {
  bool Function()? abbrechen,
}) async {
  final kandidaten =
      await (db.select(db.assets)..where(
            (t) =>
                t.dateiformat.isIn(_gewandelteFormate) &
                t.isLocked.equals(false) &
                t.widthPx.isNotNull() &
                t.heightPx.isNotNull(),
          ))
          .get();
  var geaendert = 0;
  for (final a in kandidaten) {
    if (abbrechen?.call() ?? false) break;
    final datei = paths.absolute(a.relativePath);
    if (!await datei.exists()) continue;
    final echt = echteMasse(datei, a.widthPx, a.heightPx);
    if (echt.$1 == a.widthPx && echt.$2 == a.heightPx) continue;
    await db.updateThumbnailInfo(a.id, widthPx: echt.$1, heightPx: echt.$2);
    geaendert++;
  }
  return geaendert;
}

/// Erzeugt Miniatur und Vorschau jedes DNG neu, das lineare Bilddaten
/// trägt (Apple ProRAW und ähnliche) – der Wandler nimmt dafür jetzt das
/// eingebettete Bild der Kamera. Gibt zurück, wie viele neu entstanden.
///
/// Nur dort aufzurufen, wo der Wandler LibRaw ist (Server, Linux,
/// Windows); unter macOS entwickelt Core Image richtig.
///
/// Die neuen Dateien bekommen einen neuen Namen. Ein verbundenes Gerät hält
/// Miniaturen unter ihrem Namen vor; eine neue Datei unter dem alten Namen
/// sähe es nie. So kommt mit der geänderten Zeile der neue Name an, und das
/// Gerät holt die neue Datei. Die alten Dateien werden danach gelöscht.
Future<int> erneuereRohvorschauen(
  AppDatabase db,
  StoragePaths paths,
  ImportService importe, {
  bool Function()? abbrechen,
  void Function(int erledigt, int gesamt)? fortschritt,
}) async {
  final kandidaten =
      await (db.select(db.assets)..where(
            (t) => t.dateiformat.equals('dng') & t.isLocked.equals(false),
          ))
          .get();
  var neu = 0;
  for (var i = 0; i < kandidaten.length; i++) {
    if (abbrechen?.call() ?? false) break;
    fortschritt?.call(i, kandidaten.length);
    final a = kandidaten[i];
    final datei = paths.absolute(a.relativePath);
    if (!await datei.exists()) continue;
    final kopf = leseRohkopf(datei);
    if (kopf == null || !kopf.linear || kopf.groesstes == null) continue;
    final zusatz = naechsterZusatz(a.id, a.thumbnailRelativePath);
    final r = await importe.generateThumbnailAndPreview(
      datei,
      a.id,
      '.dng',
      zusatz: zusatz,
    );
    final miniatur = r.thumbnailRelativePath;
    if (miniatur == null) continue;
    await db.updateThumbnailInfo(
      a.id,
      thumbnailRelativePath: miniatur,
      previewRelativePath: r.previewRelativePath,
      widthPx: r.width,
      heightPx: r.height,
    );
    for (final alt in [a.thumbnailRelativePath, a.previewRelativePath]) {
      if (alt == null || alt == miniatur || alt == r.previewRelativePath) {
        continue;
      }
      try {
        final f = paths.absolute(alt);
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // Ein Rest bleibt liegen; die Integritätsprüfung findet ihn.
      }
    }
    neu++;
  }
  fortschritt?.call(kandidaten.length, kandidaten.length);
  return neu;
}

/// Der nächste freie Zusatz für einen neu erzeugten Dateinamen: aus
/// `…/<id>.jpg` wird `-2`, aus `…/<id>-2.jpg` wird `-3`.
///
/// Am Namen der Aufnahme festgemacht und nicht an einer Zahl am Ende: Die
/// Kennung selbst ist eine UUID mit Bindestrichen, und ihr letzter Teil
/// kann nur aus Ziffern bestehen.
String naechsterZusatz(String id, String? pfad) {
  if (pfad == null) return '-2';
  final name = pfad.split('/').last;
  final m = RegExp('^${RegExp.escape(id)}-(\\d+)\\.jpg\$').firstMatch(name);
  final jetzt = m == null ? 1 : int.parse(m.group(1)!);
  return '-${jetzt + 1}';
}
