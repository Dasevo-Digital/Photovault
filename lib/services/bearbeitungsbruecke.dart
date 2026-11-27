import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Was ein Programm als Ergebnis ablegen darf, damit Photo Vault es
/// übernimmt: JPEG, TIFF und PNG (#499). TIFF und PNG werden beim
/// Übernehmen zu JPEG (siehe `ergebnisAlsJpeg`), denn eine neue Fassung
/// ist in der Bibliothek immer ein JPEG (`speichereBearbeitung`).
const ergebnisEndungen = {'.jpg', '.jpeg', '.tif', '.tiff', '.png'};

/// Eigene Formate der Programme. Sie zählen nicht als Ergebnis – Photo
/// Vault kann keines davon lesen –, aber wer nur so eine Datei
/// hinterlassen hat, bekommt den Hinweis, zusätzlich als JPEG oder TIFF zu
/// speichern, statt eines rätselhaften „nichts gefunden“.
///
/// `.psd`/`.psb` Photoshop, `.afphoto` Affinity Photo (bis 2), `.af` das
/// neue Affinity, `.xcf` GIMP („Speichern“ schreibt dort immer XCF, JPEG
/// gibt es nur über „Exportieren“ und „Überschreiben“), `.onphoto` ON1.
/// Die `.on1`-Beilage von ON1 gehört nicht dazu: Sie entsteht von selbst,
/// sobald man ein Bild dort anfasst, und ist kein gespeichertes Bild.
const unlesbareEndungen = {
  '.psd',
  '.psb',
  '.afphoto',
  '.af',
  '.xcf',
  '.onphoto',
};

/// Was ein Dateimanager von sich aus in einen Ordner legt. Es hält einen
/// Arbeitsordner nicht am Leben.
const _beiwerk = {'.ds_store', 'thumbs.db', 'desktop.ini'};

/// Was die Suche im Arbeitsordner gefunden hat.
///
/// [datei] ist das Ergebnis, das übernommen werden kann. [unlesbar] ist
/// die neueste Datei in einem eigenen Format eines Programms – gesetzt,
/// auch wenn es ein lesbares Ergebnis gibt; ob ein Hinweis nötig ist,
/// entscheidet die Oberfläche.
typedef Ergebnisfund = ({File? datei, File? unlesbar});

/// Wie es um den Arbeitsordner einer Aufnahme steht.
enum Arbeitsstand {
  /// Es gibt keinen.
  keiner,

  /// Die Arbeitskopie liegt bereit; ein Ergebnis kann übernommen werden.
  offen,

  /// Das Ergebnis ist übernommen (oder die Aufnahme gesperrt), aber das
  /// Programm hat Dateien hinterlassen, etwa ein PSD mit Ebenen. Photo
  /// Vault löscht sie nicht; sie liegen da, bis man sie selbst wegräumt.
  arbeitsdateien,
}

/// Unter welchem Namen die Arbeitskopie einer Aufnahme liegt (#499).
///
/// Der Name der Aufnahme mit der Endung der Datei, wie sie in der
/// Bibliothek liegt. Nach einer Bearbeitung ist eine CR3 oder HEIC dort
/// ein JPEG, ihr Name aber bleibt `IMG_1234.CR3`; eine Kopie unter diesem
/// Namen wäre ein JPEG mit falscher Endung, an dem ein Programm scheitert
/// oder das es als RAW öffnen will. [frueher] ist der Name, unter dem
/// eine Fassung davor die Kopie anlegte – nur gesetzt, wenn er sich
/// unterscheidet, damit ein schon offener Ordner weiter gefunden wird.
({String name, String? frueher}) arbeitsname(
  String originalFileName,
  String relativePath,
) {
  final name = p.basename(originalFileName);
  final endung = p.extension(relativePath);
  if (endung.isEmpty ||
      p.extension(name).toLowerCase() == endung.toLowerCase()) {
    return (name: name, frueher: null);
  }
  return (name: p.setExtension(name, endung), frueher: name);
}

Future<void> _schlafe(Duration d) => Future<void>.delayed(d);

/// Der Weg zu einem anderen Programm und zurück (#347, #499).
///
/// **Arbeitskopie statt Bibliothek.** Das Programm bekommt eine Kopie des
/// Originals in einem eigenen Ordner je Aufnahme. Die Bibliothek gehört
/// Photo Vault; mit Server liegen die Originale ohnehin nicht hier. Für
/// darktable liegt daneben die Beilage unter dem Namen, den darktable
/// sucht (`IMG_1234.CR3.xmp`, siehe [mitBeilage]).
///
/// **Kein Warten im Hintergrund.** Bearbeiten dauert Stunden oder Tage.
/// Das Ergebnis holt man deshalb von Hand ab, und auch dann wird es erst
/// genommen, wenn es fertig geschrieben aussieht ([fertig]). Der Ordner
/// merkt sich, was noch offen ist, über jeden Neustart hinweg: Es gibt
/// keine Liste daneben, die mit ihm auseinanderlaufen könnte.
///
/// **Ein Ordner je Programm** ([ablage], z. B. `PhotoVault-GIMP`), nicht
/// einer für alle. Arbeiten zwei Programme an derselben Aufnahme, wäre in
/// einem gemeinsamen Ordner nicht mehr zu sagen, welche Datei von welchem
/// stammt – und die Beilage von darktable läge zwischen den Dateien von
/// Photoshop. Das Muster gab darktable vor (`PhotoVault-darktable`); sein
/// Ordner ist damit einfach einer dieser Ordner und bleibt, wo er war.
///
/// **Was Photo Vault gehört.** Die Kopie, die Beilage und die Marke
/// ([marke]) legt Photo Vault an und räumt sie auch weg. Was ein Programm
/// sonst in den Ordner schreibt – ein PSD mit Ebenen, eine XCF, die
/// `.on1` mit der Bearbeitung –, ist die Arbeit des Nutzers und wird nie
/// gelöscht (siehe [nachUebernahme], [raeumeKlartextWeg]). Gelöscht wird
/// nur in einem echten Ordner unterhalb der [ablage], nie durch einen
/// Verweis hindurch.
class Bearbeitungsbruecke {
  Bearbeitungsbruecke(
    this.ablage, {
    required this._starte,
    this.mitBeilage = false,
    this.endungen = ergebnisEndungen,
    this.kopieZaehlt = true,
    this.ruhe = const Duration(seconds: 2),
    this._warte = _schlafe,
  });

  /// Der Ordner des Programms; darunter ein Ordner je Aufnahme.
  final Directory ablage;
  final Future<bool> Function(String datei) _starte;

  /// Ob neben der Kopie eine XMP-Beilage liegt (darktable).
  final bool mitBeilage;

  /// Welche Dateien als Ergebnis zählen.
  final Set<String> endungen;

  /// Ob die Arbeitskopie selbst das Ergebnis sein kann.
  ///
  /// Photoshop und GIMP speichern ein JPEG oder TIFF auf Wunsch an seinen
  /// Platz zurück („Speichern“ bzw. „Überschreiben“). Dann gibt es keine
  /// zweite Datei, und die Kopie ist das Ergebnis – aber nur, wenn sie
  /// sich seit dem Anlegen geändert hat (siehe [marke]). darktable
  /// schreibt nie in sein Original.
  final bool kopieZaehlt;

  /// Wie lange eine Datei unverändert gelegen haben muss, ehe sie als
  /// fertig geschrieben gilt (siehe [fertig]).
  final Duration ruhe;
  final Future<void> Function(Duration) _warte;

  /// Was Photo Vault im Ordner einer Aufnahme festhält:
  ///
  /// - `kopie`: der Name der Arbeitskopie. Er steht hier, weil er nicht
  ///   immer der Name der Aufnahme ist (siehe [arbeitsname]).
  /// - `groesse`, `zeit`: Grösse und Änderungszeit der Kopie beim Anlegen.
  ///   Daran zeigt sich später, ob ein Programm sie überschrieben hat. Der
  ///   Inhalt wäre der genauere Vergleich, aber dafür müsste das Original
  ///   noch einmal gelesen werden – mit Server liegt es nicht hier.
  /// - `ab`: Nur was danach geschrieben wurde, zählt. Gesetzt nach einem
  ///   Übernehmen, bei dem Arbeitsdateien liegen blieben: Ein älteres
  ///   JPEG daneben ist dann kein neues Ergebnis.
  ///
  /// Ohne `kopie` und `groesse` ist der Ordner im Stand
  /// [Arbeitsstand.arbeitsdateien]. Ein Ordner ganz ohne Marke stammt von
  /// darktable vor #499 und gilt als offen.
  static const marke = '.photovault-kopie.json';

  Directory ordner(String id) => Directory(p.join(ablage.path, id));

  File _markeIn(String id) => File(p.join(ordner(id).path, marke));

  Future<Map<String, Object?>?> _liesMarke(String id) async {
    try {
      final f = _markeIn(id);
      if (await FileSystemEntity.type(f.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final j = jsonDecode(await f.readAsString());
      return j is Map ? j.cast<String, Object?>() : null;
    } on Object {
      return null;
    }
  }

  Future<void> _schreibeMarke(String id, Map<String, Object?> inhalt) async {
    final f = _markeIn(id);
    final teil = File('${f.path}.teil');
    await teil.writeAsString(jsonEncode(inhalt), flush: true);
    await teil.rename(f.path);
  }

  static bool _mitKopie(Map<String, Object?>? m) =>
      m == null || m['kopie'] != null || m['groesse'] != null;

  static DateTime? _ab(Map<String, Object?>? m) => switch (m?['ab']) {
    final int t => DateTime.fromMillisecondsSinceEpoch(t),
    _ => null,
  };

  /// Ein Dateiname ohne Ordner – was aus der Marke kommt, darf nicht aus
  /// dem Ordner hinausführen.
  static bool _einfacherName(String n) =>
      n.isNotEmpty && n != '.' && n != '..' && n == p.basename(n);

  Future<bool> _istOrdner(String pfad) async =>
      await FileSystemEntity.type(pfad, followLinks: false) ==
      FileSystemEntityType.directory;

  /// Ob in [platz] gelöscht werden darf: ein echter Ordner unterhalb der
  /// [ablage], und auch die Ablage selbst ist kein Verweis. Ein Verweis
  /// liesse ein rekursives Löschen an einem ganz anderen Ort ankommen.
  Future<bool> _sicher(Directory platz) async =>
      p.isWithin(ablage.path, platz.path) &&
      await _istOrdner(ablage.path) &&
      await _istOrdner(platz.path);

  /// Wie es um den Ordner der Aufnahme [id] steht. Liest nur die Marke,
  /// nicht den Ordner – das Vollbild fragt es bei jedem Blättern.
  Future<Arbeitsstand> stand(String id) async {
    if (!await _istOrdner(ordner(id).path)) return Arbeitsstand.keiner;
    return _mitKopie(await _liesMarke(id))
        ? Arbeitsstand.offen
        : Arbeitsstand.arbeitsdateien;
  }

  /// Ob für [id] eine Arbeitskopie bereitliegt.
  Future<bool> offen(String id) async => await stand(id) == Arbeitsstand.offen;

  /// Der Name, unter dem die Kopie liegt: aus der Marke, sonst (ein
  /// Ordner von vor #499) [name] oder [frueher], wenn es die Datei gibt.
  /// `null`, wenn es keine Kopie gibt.
  Future<String?> _kopiename(
    String id,
    Map<String, Object?>? m,
    String name,
    String? frueher,
  ) async {
    if (!_mitKopie(m)) return null;
    if (m?['kopie'] case final String n when _einfacherName(n)) return n;
    for (final n in [name, ?frueher]) {
      final b = p.basename(n);
      if (await File(p.join(ordner(id).path, b)).exists()) return b;
    }
    return null;
  }

  /// Die Arbeitskopie: die vorhandene, sonst wo sie hinkäme.
  Future<File> kopie(String id, String name, {String? frueher}) async {
    final n = await _kopiename(id, await _liesMarke(id), name, frueher);
    return File(p.join(ordner(id).path, n ?? p.basename(name)));
  }

  /// Die Beilage für darktable neben der Kopie (`IMG_1234.CR3.xmp`).
  Future<File> beilage(String id, String name, {String? frueher}) async =>
      File('${(await kopie(id, name, frueher: frueher)).path}.xmp');

  /// Legt die Kopie (und bei [mitBeilage] die Beilage [xmp]) an und
  /// startet das Programm. `false`: Das Programm liess sich nicht starten,
  /// die Kopie liegt trotzdem bereit. Ist schon eine Arbeitskopie da,
  /// bleibt sie, mitsamt ihrer Bearbeitung.
  ///
  /// Liegen nach einem früheren Übernehmen noch Arbeitsdateien im Ordner,
  /// kommt die neue Kopie dazu; heisst eine davon schon so, bekommt die
  /// Kopie einen freien Namen (`IMG_1234 (2).jpg`), statt sie zu
  /// überschreiben.
  Future<bool> oeffne({
    required String id,
    required String name,
    String? frueher,
    required File original,
    String? xmp,
  }) async {
    final platz = ordner(id);
    if (!p.isWithin(ablage.path, platz.path)) {
      throw ArgumentError.value(id, 'id');
    }
    await platz.create(recursive: true);
    final m = await _liesMarke(id);
    final vorhanden = await _kopiename(id, m, name, frueher);
    var ziel = vorhanden == null ? null : File(p.join(platz.path, vorhanden));
    if (ziel == null || !await ziel.exists()) {
      ziel = await _freierPlatz(platz, p.basename(name));
      final teil = File('${ziel.path}.teil');
      await original.copy(teil.path);
      await teil.rename(ziel.path);
      if (mitBeilage && xmp != null) {
        await File('${ziel.path}.xmp').writeAsString(xmp, flush: true);
      }
      final stand = await ziel.stat();
      await _schreibeMarke(id, {
        'kopie': p.basename(ziel.path),
        'groesse': stand.size,
        'zeit': stand.modified.millisecondsSinceEpoch,
        if (m?['ab'] case final int ab) 'ab': ab,
      });
    }
    return _starte(ziel.path);
  }

  Future<File> _freierPlatz(Directory platz, String name) async {
    Future<bool> frei(String n) async =>
        !await File(p.join(platz.path, n)).exists() &&
        !(mitBeilage && await File(p.join(platz.path, '$n.xmp')).exists());
    if (await frei(name)) return File(p.join(platz.path, name));
    final stamm = p.basenameWithoutExtension(name);
    final endung = p.extension(name);
    for (var i = 2; ; i++) {
      final n = '$stamm ($i)$endung';
      if (await frei(n)) return File(p.join(platz.path, n));
    }
  }

  /// Das zuletzt geschriebene Ergebnis, irgendwo im Ordner (darktable legt
  /// es in `darktable_exported/` ab, die anderen meist daneben). Die
  /// Arbeitskopie zählt nur, wenn [kopieZaehlt] und ein Programm sie
  /// überschrieben hat.
  ///
  /// **Eindeutig.** Bei gleicher Änderungszeit – ein Programm schreibt
  /// JPEG und TIFF in derselben Sekunde, manche Dateisysteme kennen nur
  /// ganze oder doppelte Sekunden – entscheidet der Pfad, nicht die
  /// zufällige Reihenfolge, in der das Dateisystem auflistet.
  Future<Ergebnisfund> suche(String id, String name, {String? frueher}) async {
    final platz = ordner(id);
    if (!await _istOrdner(platz.path)) return (datei: null, unlesbar: null);
    final m = await _liesMarke(id);
    final kn = await _kopiename(id, m, name, frueher);
    final kopiePfad = kn == null ? null : p.join(platz.path, kn);
    final ab = _ab(m);
    ({File f, DateTime t})? beste, fremd;
    bool vorne(File f, DateTime t, ({File f, DateTime t})? bisher) =>
        bisher == null ||
        t.isAfter(bisher.t) ||
        (t == bisher.t && f.path.compareTo(bisher.f.path) < 0);
    await for (final e in platz.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final basis = p.basename(e.path);
      if (basis == marke || basis.endsWith('.teil')) continue;
      final endung = p.extension(e.path).toLowerCase();
      final unlesbar = unlesbareEndungen.contains(endung);
      if (!unlesbar && !endungen.contains(endung)) continue;
      final istKopie = kopiePfad != null && p.equals(e.path, kopiePfad);
      final FileStat stand;
      try {
        stand = await e.stat();
      } on FileSystemException {
        continue;
      }
      final t = stand.modified;
      if (ab != null && !t.isAfter(ab)) continue;
      if (unlesbar) {
        // Die Kopie eines PSD-Originals ist kein Hinweis darauf, dass
        // jemand im falschen Format gespeichert hat.
        if (istKopie) continue;
        if (vorne(e, t, fremd)) fremd = (f: e, t: t);
        continue;
      }
      if (istKopie && !(kopieZaehlt && _ueberschrieben(m, stand))) continue;
      if (vorne(e, t, beste)) beste = (f: e, t: t);
    }
    return (datei: beste?.f, unlesbar: fremd?.f);
  }

  /// Nur das übernehmbare Ergebnis aus [suche].
  Future<File?> ergebnis(String id, String name, {String? frueher}) async =>
      (await suche(id, name, frueher: frueher)).datei;

  /// Ob die Kopie nicht mehr so ist, wie sie angelegt wurde. Ohne Marke
  /// (ein Ordner aus einer Fassung davor) gilt sie als unverändert: Lieber
  /// einmal „nichts gefunden“ als das Original als Bearbeitung übernehmen.
  static bool _ueberschrieben(Map<String, Object?>? m, FileStat kopie) =>
      m != null &&
      m['groesse'] != null &&
      (m['groesse'] != kopie.size ||
          m['zeit'] != kopie.modified.millisecondsSinceEpoch);

  /// Ob [datei] fertig geschrieben aussieht.
  ///
  /// Ob ein Programm eine Datei noch schreibt, sieht man ihr nicht an; ein
  /// halbes TIFF oder JPEG lässt sich oft sogar öffnen und ergäbe ein Bild
  /// mit grauem unterem Rand. Deshalb gilt: zuletzt vor mindestens [ruhe]
  /// geändert, und zwischen zwei Blicken weder grösser noch neuer
  /// geworden. Ist sie jünger, wird der Rest abgewartet. Eine Datei aus
  /// der Zukunft (die Uhr eines Netzlaufwerks geht vor) wartet höchstens
  /// [ruhe].
  Future<bool> fertig(File datei) async {
    try {
      final vorher = await datei.stat();
      var pause = ruhe - DateTime.now().difference(vorher.modified);
      if (pause > ruhe) pause = ruhe;
      final mindestens = ruhe ~/ 4;
      if (pause < mindestens) pause = mindestens;
      await _warte(pause);
      final nachher = await datei.stat();
      return nachher.type == FileSystemEntityType.file &&
          nachher.size == vorher.size &&
          nachher.modified == vorher.modified;
    } on FileSystemException {
      return false;
    }
  }

  /// Nach dem Übernehmen von [genommen] (#499).
  ///
  /// **Weg gehen nur die Kopie, die Marke und [genommen] selbst.** Was das
  /// Programm sonst hinterlassen hat – das PSD mit den Ebenen, die XCF,
  /// die `.on1` mit der Bearbeitung, die XMP von Camera Raw –, bleibt:
  /// Photo Vault kann nichts davon lesen, aber es ist oft die eigentliche
  /// Arbeit, und es gibt keinen Weg zurück, wenn es weg ist. Bis 3.69
  /// ging hier der ganze Ordner.
  ///
  /// Bleibt etwas, steht der Ordner danach im Stand
  /// [Arbeitsstand.arbeitsdateien], und nur was später geschrieben wird,
  /// zählt wieder als Ergebnis. Bleibt nichts, geht er mit ([schliesse]).
  /// Liefert, ob etwas blieb.
  Future<bool> nachUebernahme(
    String id,
    File genommen, {
    required String name,
    String? frueher,
  }) async {
    final platz = ordner(id);
    if (!await _sicher(platz)) return false;
    final m = await _liesMarke(id);
    final kn = await _kopiename(id, m, name, frueher);
    DateTime? ab;
    try {
      ab = await genommen.lastModified();
    } on FileSystemException {
      ab = null;
    }
    for (final f in [genommen, if (kn != null) File(p.join(platz.path, kn))]) {
      await _loescheDatei(platz, f);
    }
    return _blieb(id, ab);
  }

  /// Beim Sperren und beim endgültigen Löschen der Aufnahme [id] (#499):
  /// Die Arbeitskopie ist Klartext des Fotos und hat dann hier nichts mehr
  /// zu suchen.
  ///
  /// Sofort weg geht, was Photo Vault hineingelegt hat: die Kopie, solange
  /// sie unverändert ist, die Beilage mit Sternen und Schlagwörtern und
  /// die Marke. Was ein Programm geschrieben hat – auch eine überschriebene
  /// Kopie –, bleibt; es könnte die Arbeit von Stunden sein. Liefert den
  /// Ordner, wenn etwas blieb – der Aufrufer weist dann darauf hin –,
  /// sonst `null`.
  Future<Directory?> raeumeKlartextWeg(String id) async {
    final platz = ordner(id);
    if (!await _sicher(platz)) return null;
    final m = await _liesMarke(id);
    final weg = <File>[];
    if (m?['kopie'] case final String n when _einfacherName(n)) {
      final kopie = File(p.join(platz.path, n));
      if (await kopie.exists() &&
          !(kopieZaehlt && _ueberschrieben(m, await kopie.stat()))) {
        weg.add(kopie);
      }
      if (mitBeilage) weg.add(File('${kopie.path}.xmp'));
    } else if (m == null && mitBeilage) {
      // Ein Ordner von darktable vor #499: Kopie und Beilage liegen als
      // Paar oben im Ordner, eine Marke gab es nicht.
      await for (final e in platz.list(followLinks: false)) {
        final beilage = File('${e.path}.xmp');
        if (e is File &&
            p.extension(e.path).toLowerCase() != '.xmp' &&
            await beilage.exists()) {
          weg.addAll([e, beilage]);
        }
      }
    }
    for (final f in weg) {
      await _loescheDatei(platz, f);
    }
    return await _blieb(id, DateTime.now()) ? platz : null;
  }

  /// Räumt Marke, Reste halber Kopien und leere Unterordner weg. Liegt
  /// dann nichts mehr da, geht der Ordner; sonst hält eine neue Marke fest,
  /// dass es keine Kopie mehr gibt und nur Späteres als [ab] zählt.
  Future<bool> _blieb(String id, DateTime? ab) async {
    final platz = ordner(id);
    await for (final e in platz.list(followLinks: false)) {
      final b = p.basename(e.path);
      if (e is File && (b == marke || b.endsWith('.teil'))) {
        await _loescheDatei(platz, e);
      }
    }
    await _raeumeLeereOrdner(platz);
    if (!await _hatArbeitsdateien(platz)) {
      await schliesse(id);
      return false;
    }
    await _schreibeMarke(id, {'ab': ?ab?.millisecondsSinceEpoch});
    return true;
  }

  Future<void> _loescheDatei(Directory platz, File f) async {
    if (!p.isWithin(platz.path, f.path)) return;
    try {
      if (await FileSystemEntity.type(f.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await f.delete();
      }
    } on FileSystemException {
      // Schon weg oder nicht löschbar – dann bleibt sie eben liegen.
    }
  }

  /// Leere Unterordner, von innen nach aussen – etwa `ausgabe/`, aus dem
  /// gerade das Ergebnis kam.
  Future<void> _raeumeLeereOrdner(Directory platz) async {
    final ordner = [
      await for (final e in platz.list(recursive: true, followLinks: false))
        if (e is Directory) e,
    ]..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final o in ordner) {
      try {
        if (await o.list().isEmpty) await o.delete();
      } on FileSystemException {
        // Nicht leer oder nicht löschbar.
      }
    }
  }

  Future<bool> _hatArbeitsdateien(Directory platz) async {
    await for (final e in platz.list(recursive: true, followLinks: false)) {
      if (e is Directory) continue;
      final b = p.basename(e.path);
      if (_beiwerk.contains(b.toLowerCase())) continue;
      if (e is File && (b == marke || b.endsWith('.teil'))) continue;
      return true;
    }
    return false;
  }

  /// Räumt den ganzen Ordner der Aufnahme weg – für darktable nach dem
  /// Übernehmen, sonst nur, wenn darin nichts mehr liegt als Beiwerk. Nur
  /// unterhalb der [ablage] und nie durch einen Verweis hindurch; ist die
  /// Ablage danach leer, geht sie mit – sonst bliebe für jedes einmal
  /// benutzte Programm ein leerer Ordner unter „Bilder“ liegen.
  Future<void> schliesse(String id) async {
    final platz = ordner(id);
    if (await _sicher(platz)) await platz.delete(recursive: true);
    try {
      if (await _istOrdner(ablage.path) && await ablage.list().isEmpty) {
        await ablage.delete();
      }
    } on FileSystemException {
      // Nicht leer geworden oder schon weg – beides ist recht.
    }
  }
}
