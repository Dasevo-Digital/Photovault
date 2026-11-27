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

/// Was die Suche im Arbeitsordner gefunden hat.
///
/// [datei] ist das Ergebnis, das übernommen werden kann. [unlesbar] ist
/// die neueste Datei in einem eigenen Format eines Programms – gesetzt,
/// auch wenn es ein lesbares Ergebnis gibt; ob ein Hinweis nötig ist,
/// entscheidet die Oberfläche.
typedef Ergebnisfund = ({File? datei, File? unlesbar});

/// Der Weg zu einem anderen Programm und zurück (#347, #499).
///
/// **Arbeitskopie statt Bibliothek.** Das Programm bekommt eine Kopie des
/// Originals in einem eigenen Ordner je Aufnahme. Die Bibliothek gehört
/// Photo Vault; mit Server liegen die Originale ohnehin nicht hier. Für
/// darktable liegt daneben die Beilage unter dem Namen, den darktable
/// sucht (`IMG_1234.CR3.xmp`, siehe [mitBeilage]).
///
/// **Kein Warten im Hintergrund.** Bearbeiten dauert Stunden oder Tage, und
/// ob eine Datei schon fertig geschrieben ist, sieht man ihr nicht an. Das
/// Ergebnis holt man deshalb von Hand ab. Der Ordner merkt sich dabei, was
/// noch offen ist, über jeden Neustart hinweg: Es gibt keine Liste
/// daneben, die mit ihm auseinanderlaufen könnte.
///
/// **Ein Ordner je Programm** ([ablage], z. B. `PhotoVault-GIMP`), nicht
/// einer für alle. Arbeiten zwei Programme an derselben Aufnahme, wäre in
/// einem gemeinsamen Ordner nicht mehr zu sagen, welche Datei von welchem
/// stammt – und die Beilage von darktable läge zwischen den Dateien von
/// Photoshop. Das Muster gab darktable vor (`PhotoVault-darktable`); sein
/// Ordner ist damit einfach einer dieser Ordner und bleibt, wo er war.
class Bearbeitungsbruecke {
  Bearbeitungsbruecke(
    this.ablage, {
    required this._starte,
    this.mitBeilage = false,
    this.endungen = ergebnisEndungen,
    this.kopieZaehlt = true,
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
  /// sich seit dem Anlegen geändert hat (siehe [_marke]). darktable
  /// schreibt nie in sein Original.
  final bool kopieZaehlt;

  /// Was beim Anlegen über die Kopie festgehalten wird: Grösse und
  /// Änderungszeit. Daran zeigt sich später, ob ein Programm sie
  /// überschrieben hat. Der Inhalt selbst wäre der genauere Vergleich,
  /// aber dafür müsste das Original noch einmal gelesen werden – mit
  /// Server liegt es nicht hier.
  static const _marke = '.photovault-kopie.json';

  Directory ordner(String id) => Directory(p.join(ablage.path, id));
  bool offen(String id) => ordner(id).existsSync();

  File beilage(String id, String name) =>
      File(p.join(ordner(id).path, '${p.basename(name)}.xmp'));

  File kopie(String id, String name) =>
      File(p.join(ordner(id).path, p.basename(name)));

  /// Legt die Kopie (und bei [mitBeilage] die Beilage [xmp]) an und
  /// startet das Programm. `false`: Das Programm liess sich nicht starten,
  /// die Kopie liegt trotzdem bereit. Ist schon eine Arbeitskopie da,
  /// bleibt sie, mitsamt ihrer Bearbeitung.
  Future<bool> oeffne({
    required String id,
    required String name,
    required File original,
    String? xmp,
  }) async {
    await ordner(id).create(recursive: true);
    final ziel = kopie(id, name);
    if (!await ziel.exists()) {
      final teil = File('${ziel.path}.teil');
      await original.copy(teil.path);
      await teil.rename(ziel.path);
      if (mitBeilage && xmp != null) {
        await beilage(id, name).writeAsString(xmp, flush: true);
      }
      if (kopieZaehlt) {
        final stand = await ziel.stat();
        await File(p.join(ordner(id).path, _marke)).writeAsString(
          jsonEncode({
            'groesse': stand.size,
            'zeit': stand.modified.millisecondsSinceEpoch,
          }),
          flush: true,
        );
      }
    }
    return _starte(ziel.path);
  }

  /// Das zuletzt geschriebene Ergebnis, irgendwo im Ordner (darktable legt
  /// es in `darktable_exported/` ab, die anderen meist daneben). Die
  /// Arbeitskopie zählt nur, wenn [kopieZaehlt] und ein Programm sie
  /// überschrieben hat.
  Future<Ergebnisfund> suche(String id, String name) async {
    final platz = ordner(id);
    if (!await platz.exists()) return (datei: null, unlesbar: null);
    final kopiePfad = kopie(id, name).path;
    File? beste, fremd;
    DateTime? zeit, fremdZeit;
    await for (final e in platz.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final endung = p.extension(e.path).toLowerCase();
      final istKopie = p.equals(e.path, kopiePfad);
      // Die Kopie eines PSD-Originals ist kein Hinweis darauf, dass
      // jemand im falschen Format gespeichert hat.
      if (unlesbareEndungen.contains(endung)) {
        if (istKopie) continue;
        final t = await e.lastModified();
        if (fremdZeit == null || t.isAfter(fremdZeit)) {
          fremd = e;
          fremdZeit = t;
        }
        continue;
      }
      if (!endungen.contains(endung)) continue;
      if (istKopie && !(kopieZaehlt && await _ueberschrieben(id, e))) {
        continue;
      }
      final t = await e.lastModified();
      if (zeit == null || t.isAfter(zeit)) {
        beste = e;
        zeit = t;
      }
    }
    return (datei: beste, unlesbar: fremd);
  }

  /// Nur das übernehmbare Ergebnis aus [suche].
  Future<File?> ergebnis(String id, String name) async =>
      (await suche(id, name)).datei;

  /// Ob die Kopie nicht mehr so ist, wie sie angelegt wurde. Ohne Marke
  /// (ein Ordner aus einer Fassung davor) gilt sie als unverändert: Lieber
  /// einmal „nichts gefunden“ als das Original als Bearbeitung übernehmen.
  Future<bool> _ueberschrieben(String id, File kopie) async {
    try {
      final marke = File(p.join(ordner(id).path, _marke));
      if (!await marke.exists()) return false;
      final m = jsonDecode(await marke.readAsString()) as Map;
      final stand = await kopie.stat();
      return m['groesse'] != stand.size ||
          m['zeit'] != stand.modified.millisecondsSinceEpoch;
    } on Object {
      return false;
    }
  }

  /// Räumt die Arbeitskopie weg. Nur unterhalb der [ablage]; ist die
  /// danach leer, geht sie mit – sonst bliebe für jedes einmal benutzte
  /// Programm ein leerer Ordner unter „Bilder“ liegen.
  Future<void> schliesse(String id) async {
    final platz = ordner(id);
    if (p.isWithin(ablage.path, platz.path) && await platz.exists()) {
      await platz.delete(recursive: true);
    }
    try {
      if (await ablage.list().isEmpty) await ablage.delete();
    } on FileSystemException {
      // Nicht leer geworden oder schon weg – beides ist recht.
    }
  }
}
