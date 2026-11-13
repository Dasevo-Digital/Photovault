/// Einmalige Nachläufe an den Bilddateien einer Bibliothek: was ein Fehler
/// beim Import hinterlassen hat, wird für die schon vorhandenen Aufnahmen
/// nachgeholt. Wer sie aufruft, merkt sich ihren Schlüssel in den
/// Aufgabenläufen, sodass jeder je Bibliothek genau einmal läuft.
library;

import 'dart:io';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'asset_display_path.dart' show hatAnsichtsbild;
import 'dateikopf.dart';
import 'import_service.dart';
import 'storage_paths.dart';

/// Die echte Bildgrösse statt der Grösse der Vorschau (siehe
/// dateikopf.dart).
const nachlaufOriginalmasse = 'nachlauf-originalmasse-1';

/// Neue Vorschauen für DNG-Dateien, die LibRaw zu dunkel entwickelt hat.
const nachlaufRohvorschau = 'nachlauf-rohvorschau-1';

/// Vorschauen aus der Zeit vor [vorschauKante] 3000 neu erzeugen (#332).
const nachlaufVorschaukante = 'nachlauf-vorschaukante-1';

/// Ansichtsbilder für grosse JPEG aus der Zeit davor (#333).
const nachlaufAnsichtsbilder = 'nachlauf-ansichtsbilder-1';

/// Was früher die längste Vorschau war: Kleinere Fotos ändern sich nicht.
const _alteVorschauKante = 2048;

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

/// Bringt Vorschauen auf [vorschauKante], höchstens [frist] lang (#332).
///
/// Bei 48 Megapixeln dauert eine Wandlung Sekunden, eine Bibliothek also
/// Stunden. Darum in Etappen: Danach kommt wieder an die Reihe, was neu
/// hochgeladen wurde, und die nächste Etappe macht bei `weiter` weiter;
/// `weiter == null` heisst fertig. Geht der Server dazwischen aus, beginnt
/// die Suche von vorn, überspringt aber, was schon gross genug ist – das
/// steht im Kopf der Datei.
///
/// Neue Dateien bekommen einen neuen Namen, damit verbundene Geräte sie
/// holen (siehe [erneuereRohvorschauen]). Die Miniatur bleibt, also auch die
/// Zeile im Raster.
Future<({int neu, String? weiter})> vergroessereVorschauen(
  AppDatabase db,
  StoragePaths paths,
  ImportService importe, {
  String? ab,
  Duration frist = const Duration(minutes: 2),
  bool Function()? abbrechen,
}) async {
  final kandidaten =
      await (db.selectOnly(db.assets)
            ..addColumns([db.assets.id])
            ..where(
              db.assets.type.equals('IMAGE') &
                  db.assets.previewRelativePath.isNotNull() &
                  db.assets.isLocked.equals(false) &
                  (db.assets.widthPx.isBiggerThanValue(_alteVorschauKante) |
                      db.assets.heightPx.isBiggerThanValue(_alteVorschauKante)),
            )
            ..orderBy([OrderingTerm.asc(db.assets.id)]))
          .map((z) => z.read(db.assets.id)!)
          .get();
  final uhr = Stopwatch()..start();
  var neu = 0;
  for (var i = 0; i < kandidaten.length; i++) {
    final id = kandidaten[i];
    if (ab != null && id.compareTo(ab) <= 0) continue;
    if ((abbrechen?.call() ?? false) || (neu > 0 && uhr.elapsed >= frist)) {
      // Die nächste Etappe beginnt mit dieser Aufnahme. Mindestens eine je
      // Etappe: Sonst käme ein Foto, das länger dauert als die Frist, nie dran.
      return (neu: neu, weiter: i == 0 ? '' : kandidaten[i - 1]);
    }
    final a = await db.assetById(id);
    final vorschau = a?.previewRelativePath;
    // Ein Ansichtsbild (#333) ist schon so gross, wie es sein soll; neu
    // geschrieben verlöre es seinen Namen und gälte als Vorschau.
    if (a == null || vorschau == null || hatAnsichtsbild(a)) continue;
    final quelle = paths.absolute(a.relativePath);
    if (!await quelle.exists()) continue;
    if (await _schonGross(paths.absolute(vorschau), a)) continue;
    final relativ = await importe.erneuereVorschau(
      quelle,
      a.id,
      zusatz: naechsterZusatz(a.id, vorschau),
    );
    if (relativ == null) continue;
    await db.updateThumbnailInfo(a.id, previewRelativePath: relativ);
    try {
      final alt = paths.absolute(vorschau);
      if (await alt.exists()) await alt.delete();
    } on FileSystemException {
      // Ein Rest bleibt liegen; die Integritätsprüfung findet ihn.
    }
    neu++;
  }
  return (neu: neu, weiter: null);
}

/// Legt grossen JPEG ein Ansichtsbild daneben (#333), höchstens [frist]
/// lang – in Etappen wie [vergroessereVorschauen], denn bei Tausenden
/// Kamerafotos dauert das Stunden.
///
/// Nur dort aufzurufen, wo [ImportService.ansichtsbilder] gilt (am Server).
/// Was eines bekommen hat, fällt aus der Suche heraus; nach einem Neustart
/// geht es also beim nächsten weiter, ohne eine Datei zu öffnen. Die Zeile
/// bekommt nur die Vorschau – Miniatur und Masse bleiben –, und mit ihr
/// erfahren die Geräte davon.
///
/// Auch was im Papierkorb liegt, entwickelt oder restauriert ist (#382):
/// Der Nachlauf läuft je Bibliothek nur einmal. Zurückgeholt, auf das
/// Original zurückgesetzt oder ohne Restaurierung zeigt der Betrachter
/// wieder das Original, und ohne Ansichtsbild lüden Handy und Browser es
/// ganz.
Future<({int neu, String? weiter})> ergaenzeAnsichtsbilder(
  AppDatabase db,
  StoragePaths paths,
  ImportService importe, {
  String? ab,
  Duration frist = const Duration(minutes: 2),
  bool Function()? abbrechen,
}) async {
  final t = db.assets;
  final kandidaten =
      await (db.selectOnly(t)
            ..addColumns([t.id])
            ..where(
              t.type.equals('IMAGE') &
                  t.previewRelativePath.isNull() &
                  t.isLocked.equals(false) &
                  (t.relativePath.like('%.jpg') |
                      t.relativePath.like('%.jpeg')) &
                  t.fileSizeBytes.isBiggerThanValue(ansichtsbildAb) &
                  (t.widthPx.isBiggerThanValue(vorschauKante) |
                      t.heightPx.isBiggerThanValue(vorschauKante)),
            )
            ..orderBy([OrderingTerm.asc(t.id)]))
          .map((z) => z.read(t.id)!)
          .get();
  final uhr = Stopwatch()..start();
  var neu = 0, versucht = 0;
  for (var i = 0; i < kandidaten.length; i++) {
    final id = kandidaten[i];
    if (ab != null && id.compareTo(ab) <= 0) continue;
    // Versucht statt gelungen: Scheitert der Wandler an jedem Foto, endet
    // die Etappe trotzdem nach der Frist.
    if ((abbrechen?.call() ?? false) ||
        (versucht > 0 && uhr.elapsed >= frist)) {
      return (neu: neu, weiter: i == 0 ? '' : kandidaten[i - 1]);
    }
    final a = await db.assetById(id);
    if (a == null || a.previewRelativePath != null) continue;
    final original = paths.absolute(a.relativePath);
    if (!await original.exists()) continue;
    versucht++;
    final relativ = await importe.erzeugeAnsichtsbild(
      original,
      a.id,
      breite: a.widthPx,
      hoehe: a.heightPx,
    );
    if (relativ == null) continue;
    await db.updateThumbnailInfo(a.id, previewRelativePath: relativ);
    neu++;
  }
  return (neu: neu, weiter: null);
}

/// Ob die Vorschau schon so gross ist, wie sie werden kann. Die ersten
/// 64 KB genügen: Eine Vorschau trägt keine langen Angaben vor den Massen.
Future<bool> _schonGross(File vorschau, AssetData a) async {
  try {
    final zugriff = await vorschau.open();
    final Uint8List kopf;
    try {
      kopf = await zugriff.read(64 * 1024);
    } finally {
      await zugriff.close();
    }
    final masse = jpegMasse(kopf);
    if (masse == null) return false;
    final lang = masse.$1 > masse.$2 ? masse.$1 : masse.$2;
    final original = (a.widthPx ?? 0) > (a.heightPx ?? 0)
        ? (a.widthPx ?? 0)
        : (a.heightPx ?? 0);
    return lang >= vorschauKante || lang >= original;
  } on FileSystemException {
    return false;
  }
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
