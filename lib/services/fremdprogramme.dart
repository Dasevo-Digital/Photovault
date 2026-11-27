import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kern/berechne.dart';
import 'package:path/path.dart' as p;

/// Die Programme, die Photo Vault von sich aus kennt (#499).
///
/// [name] ist die Kennung in der Einstellungsdatei, [anzeigename] steht
/// im Menü. Beide sind Eigennamen und werden nicht übersetzt. [ordner]
/// ist der Arbeitsordner (siehe [Bearbeitungsbruecke]); der von darktable
/// heisst so seit #347 und darf sich nicht ändern, sonst fänden sich
/// offene Arbeitskopien nicht wieder.
enum Bekannt {
  darktable('darktable', 'darktable'),
  on1('ON1 Photo RAW', 'ON1'),
  affinity('Affinity Photo', 'Affinity'),
  photoshop('Adobe Photoshop', 'Photoshop'),
  gimp('GIMP', 'GIMP');

  const Bekannt(this.anzeigename, this._ordnerteil);

  final String anzeigename;
  final String _ordnerteil;

  String get ordner => 'PhotoVault-$_ordnerteil';

  /// Ob es das Programm auf [system] überhaupt gibt (Werte wie
  /// `Platform.operatingSystem`). ON1, Affinity und Photoshop gibt es für
  /// Linux nicht; sie dort als „nicht gefunden“ aufzuführen, wäre nur
  /// Rauschen.
  bool gibtEsAuf(String system) => switch (this) {
    darktable || gimp => true,
    on1 || affinity || photoshop => system != 'linux',
  };
}

/// Ein Programm, in dem man ein Foto bearbeiten kann – bekannt oder vom
/// Nutzer selbst gewählt („Anderes Programm …“).
class Fremdprogramm {
  const Fremdprogramm({
    required this.kennung,
    required this.name,
    required this.ordner,
    this.art,
    this.pfad,
    this.aktiv = true,
  });

  factory Fremdprogramm.bekannt(
    Bekannt art, {
    String? pfad,
    bool aktiv = true,
  }) => Fremdprogramm(
    kennung: art.name,
    name: art.anzeigename,
    ordner: art.ordner,
    art: art,
    pfad: pfad,
    aktiv: aktiv,
  );

  /// Schlüssel in der Einstellungsdatei: der Name von [Bekannt] oder
  /// `eigen:<pfad>`.
  final String kennung;
  final String name;

  /// Der Name des Arbeitsordners (siehe [Bekannt.ordner]).
  final String ordner;

  /// `null` bei einem selbst gewählten Programm.
  final Bekannt? art;

  /// Wo das Programm liegt: das `.app`-Bündel, die `.exe` oder das
  /// ausführbare Programm. `null`, wenn ein bekanntes nicht gefunden
  /// wurde.
  final String? pfad;

  /// Ob es im Menü „Bearbeiten in“ steht.
  final bool aktiv;

  bool get eigenes => art == null;
}

/// Was die Erkennung vom System wissen muss. Eine eigene Schicht, damit
/// die Tests ein Mac-, Windows- oder Linux-Dateisystem nachstellen können,
/// ohne dass auf dem Prüfrechner irgendetwas installiert sein muss.
abstract interface class Systemblick {
  /// Wie `Platform.operatingSystem`: `macos`, `windows`, `linux`.
  String get system;
  Map<String, String> get umgebung;

  /// Die Namen der Einträge in [ordner]; leer, wenn es ihn nicht gibt oder
  /// die Sandbox nicht hineinsehen lässt.
  Future<List<String>> namenIn(String ordner);
  Future<bool> gibtEs(String pfad);

  /// Der Eintrag „App Paths“ der Windows-Registrierung für [exe], wenn
  /// ihn ein Installer gesetzt hat.
  Future<String?> appPfad(String exe);
}

/// Der echte [Systemblick].
class EchterSystemblick implements Systemblick {
  const EchterSystemblick();

  @override
  String get system => Platform.operatingSystem;

  @override
  Map<String, String> get umgebung => Platform.environment;

  @override
  Future<List<String>> namenIn(String ordner) async {
    try {
      return [
        await for (final e in Directory(ordner).list(followLinks: false))
          p.basename(e.path),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<bool> gibtEs(String pfad) async {
    try {
      return await FileSystemEntity.type(pfad) != FileSystemEntityType.notFound;
    } on Object {
      return false;
    }
  }

  @override
  Future<String?> appPfad(String exe) async {
    if (!Platform.isWindows) return null;
    for (final zweig in const ['HKCU', 'HKLM']) {
      try {
        final r = await Process.run('reg', [
          'query',
          '$zweig\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\$exe',
          '/ve',
        ]);
        if (r.exitCode != 0) continue;
        final wert = appPfadAus('${r.stdout}', umgebung);
        if (wert != null) return wert;
      } on Object {
        continue;
      }
    }
    return null;
  }
}

/// Liest den Standardwert aus der Ausgabe von `reg query … /ve`:
///
///     (Standard)    REG_SZ    C:\Program Files\Adobe\…\Photoshop.exe
///
/// Der Name der ersten Spalte hängt an der Sprache von Windows, die Art
/// nicht. `%ProgramFiles%` und Ähnliches werden aufgelöst, Anführungs-
/// zeichen entfernt.
String? appPfadAus(String ausgabe, Map<String, String> umgebung) {
  final zeile = RegExp(
    r'REG_(?:EXPAND_)?SZ\s+(.+)$',
    multiLine: true,
  ).firstMatch(ausgabe);
  if (zeile == null) return null;
  final wert = zeile.group(1)!.trim().replaceAll('"', '').replaceAllMapped(
    RegExp('%([^%]+)%'),
    (m) {
      final name = m.group(1)!.toLowerCase();
      for (final e in umgebung.entries) {
        if (e.key.toLowerCase() == name) return e.value;
      }
      return m.group(0)!;
    },
  );
  return wert.isEmpty ? null : wert;
}

/// Die Namen der Programme unter macOS, ohne `.app`. Die erste Gruppe ist
/// die Fassung, nach der bei mehreren die neueste gewinnt.
///
/// **Jahresfassungen.** Adobe und ON1 hängen das Jahr an den Namen
/// („Adobe Photoshop 2026“, „ON1 Photo RAW 2027“) und legen das Bündel in
/// einen gleichnamigen Ordner unter /Programme. Wer zwei Jahre
/// nebeneinander hat, will das neuere.
final _macNamen = {
  Bekannt.darktable: RegExp(r'^darktable$', caseSensitive: false),
  Bekannt.on1: RegExp(r'^ON1 Photo RAW(?: MAX)?(?: (\d{4}))?$'),
  // „Affinity“ allein ist die Nachfolgerin, die Foto, Grafik und Layout
  // vereint.
  Bekannt.affinity: RegExp(r'^Affinity(?: Photo(?: (\d+))?)?$'),
  Bekannt.photoshop: RegExp(r'^Adobe Photoshop(?: CC)?(?: (\d{4}))?$'),
  Bekannt.gimp: RegExp(r'^GIMP(?:[- ](\d+(?:\.\d+)*))?$', caseSensitive: false),
};

/// Wo die Programme unter Windows liegen: im Programmordner, bei Adobe,
/// Affinity und ON1 darunter im Ordner des Herstellers, dann der Ordner
/// des Programms (auch hier mit Jahr oder Fassung) und darin die `.exe`.
typedef _Windowsort = ({
  String? hersteller,
  RegExp ordner,
  String unterordner,
  RegExp exe,
  List<String> appPfade,
});

final Map<Bekannt, _Windowsort> _windowsOrte = {
  Bekannt.darktable: (
    hersteller: null,
    ordner: RegExp(r'^darktable$', caseSensitive: false),
    unterordner: 'bin',
    exe: RegExp(r'^darktable\.exe$', caseSensitive: false),
    appPfade: ['darktable.exe'],
  ),
  Bekannt.gimp: (
    hersteller: null,
    ordner: RegExp(r'^GIMP(?: (\d+(?:\.\d+)*))?$', caseSensitive: false),
    unterordner: 'bin',
    // Nicht gimp-console-3.0.exe: Das ist die Fassung ohne Fenster.
    exe: RegExp(r'^gimp-(\d+(?:\.\d+)*)\.exe$', caseSensitive: false),
    appPfade: ['gimp-3.exe', 'gimp-3.0.exe', 'gimp-2.10.exe'],
  ),
  Bekannt.photoshop: (
    hersteller: 'Adobe',
    ordner: RegExp(r'^Adobe Photoshop(?: CC)?(?: (\d{4}))?$'),
    unterordner: '',
    exe: RegExp(r'^Photoshop\.exe$', caseSensitive: false),
    appPfade: ['Photoshop.exe'],
  ),
  Bekannt.affinity: (
    hersteller: 'Affinity',
    ordner: RegExp(r'^(?:Affinity(?: Photo)?|Photo)(?: (\d+))?$'),
    unterordner: '',
    exe: RegExp(r'^(?:Photo|Affinity)\.exe$', caseSensitive: false),
    appPfade: const [],
  ),
  Bekannt.on1: (
    hersteller: 'ON1',
    ordner: RegExp(r'^ON1 Photo RAW(?: MAX)?(?: (\d{4}))?$'),
    unterordner: '',
    exe: RegExp(r'^ON1 Photo RAW(?: MAX)?(?: (\d{4}))?\.exe$'),
    appPfade: const [],
  ),
};

/// Unter Linux: Befehle im PATH und die Kennungen der Flatpaks.
final _linuxBefehle = {
  Bekannt.darktable: ['darktable'],
  Bekannt.gimp: ['gimp', 'gimp-3', 'gimp-3.0', 'gimp-2.10'],
};
final _linuxFlatpaks = {
  Bekannt.darktable: 'org.darktable.Darktable',
  Bekannt.gimp: 'org.gimp.GIMP',
};

/// Sucht die bekannten Programme; liefert, was gefunden wurde, mit Pfad.
///
/// **macOS:** /Programme und ~/Programme, dort die Bündel und eine Ebene
/// tiefer (Adobe und ON1 legen einen Ordner um das Bündel). Gestartet
/// wird mit `open -a <Bündel>`, das braucht keinen Zugriff auf das
/// Bündel selbst. In der Sandbox zeigt HOME in den Container; der
/// Heimordner davor ist der echte. Lässt die Sandbox ihn nicht lesen,
/// bleibt es bei /Programme.
///
/// **Windows:** die Programmordner (64 und 32 Bit, und
/// `%LOCALAPPDATA%\Programs` für Installationen nur für einen Nutzer),
/// danach die „App Paths“ der Registrierung. Was aus dem Microsoft Store
/// kommt, liegt unter WindowsApps und lässt sich nicht als `.exe`
/// starten – das findet die Erkennung bewusst nicht.
///
/// **Linux:** der PATH, dann installierte Flatpaks. Läuft Photo Vault
/// selbst als Flatpak, wird nichts gesucht: Aus der Sandbox heraus lässt
/// sich kein anderes Programm starten (siehe [Programmstarter]), und ein
/// „gefunden“, das dann doch nicht startet, wäre irreführend.
Future<Map<Bekannt, String>> erkenneProgramme(Systemblick blick) async {
  final gefunden = <Bekannt, String>{};
  switch (blick.system) {
    case 'macos':
      gefunden.addAll(await _erkenneMac(blick));
    case 'windows':
      gefunden.addAll(await _erkenneWindows(blick));
    case 'linux':
      gefunden.addAll(await _erkenneLinux(blick));
  }
  return gefunden;
}

/// Fassungsnummer aus einer Gruppe wie `2027` oder `2.10`; ohne Nummer
/// die niedrigste.
List<int> _fassung(String? text) => [
  for (final teil in (text ?? '').split('.')) ?int.tryParse(teil),
];

int _vergleiche(List<int> a, List<int> b) {
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : -1, y = i < b.length ? b[i] : -1;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Merkt sich je Programm den Kandidaten mit der höchsten Fassung; bei
/// gleicher Fassung bleibt der zuerst gefundene (der Ordner des Systems
/// vor dem des Nutzers).
class _Bestenliste {
  final _beste = <Bekannt, ({String pfad, List<int> fassung})>{};

  void biete(Bekannt art, String pfad, List<int> fassung) {
    final bisher = _beste[art];
    if (bisher == null || _vergleiche(fassung, bisher.fassung) > 0) {
      _beste[art] = (pfad: pfad, fassung: fassung);
    }
  }

  Map<Bekannt, String> get ergebnis => {
    for (final e in _beste.entries) e.key: e.value.pfad,
  };
}

Future<Map<Bekannt, String>> _erkenneMac(Systemblick blick) async {
  final pfad = p.posix;
  final heim = blick.umgebung['HOME'];
  // /Users/x/Library/Containers/<Kennung>/Data → /Users/x
  final echt = heim == null
      ? null
      : heim.contains('/Library/Containers/')
      ? heim.substring(0, heim.indexOf('/Library/Containers/'))
      : heim;
  final orte = ['/Applications', if (echt != null) '$echt/Applications'];
  final liste = _Bestenliste();
  void pruefe(String name, String ort) {
    if (!name.endsWith('.app')) return;
    final stamm = name.substring(0, name.length - 4);
    for (final MapEntry(key: art, value: muster) in _macNamen.entries) {
      final m = muster.firstMatch(stamm);
      if (m == null) continue;
      liste.biete(
        art,
        pfad.join(ort, name),
        _fassung(m.groupCount > 0 ? m.group(1) : null),
      );
    }
  }

  for (final ort in orte) {
    for (final name in await blick.namenIn(ort)) {
      if (name.endsWith('.app')) {
        pruefe(name, ort);
        continue;
      }
      // Nur in Ordner hinein, die wie eines der Programme heissen – nicht
      // in jeden Ordner unter /Programme.
      if (!_macNamen.values.any((m) => m.hasMatch(name))) continue;
      final innen = pfad.join(ort, name);
      for (final buendel in await blick.namenIn(innen)) {
        pruefe(buendel, innen);
      }
    }
  }
  return liste.ergebnis;
}

Future<Map<Bekannt, String>> _erkenneWindows(Systemblick blick) async {
  final pfad = p.windows;
  final u = {for (final e in blick.umgebung.entries) e.key.toLowerCase(): e};
  String? wert(String name) => u[name.toLowerCase()]?.value;
  final wurzeln = <String>[];
  for (final w in [
    wert('ProgramW6432'),
    wert('ProgramFiles'),
    wert('ProgramFiles(x86)'),
    if (wert('LOCALAPPDATA') case final l?) pfad.join(l, 'Programs'),
  ]) {
    if (w != null && !wurzeln.any((x) => pfad.equals(x, w))) wurzeln.add(w);
  }
  if (wurzeln.isEmpty) wurzeln.add(r'C:\Program Files');

  final liste = _Bestenliste();
  for (final MapEntry(key: art, value: ort) in _windowsOrte.entries) {
    for (final wurzel in wurzeln) {
      final basis = ort.hersteller == null
          ? wurzel
          : pfad.join(wurzel, ort.hersteller);
      for (final ordner in await blick.namenIn(basis)) {
        final mo = ort.ordner.firstMatch(ordner);
        if (mo == null) continue;
        final innen = ort.unterordner.isEmpty
            ? pfad.join(basis, ordner)
            : pfad.join(basis, ordner, ort.unterordner);
        for (final exe in await blick.namenIn(innen)) {
          final me = ort.exe.firstMatch(exe);
          if (me == null) continue;
          liste.biete(art, pfad.join(innen, exe), [
            ..._fassung(mo.groupCount > 0 ? mo.group(1) : null),
            ..._fassung(me.groupCount > 0 ? me.group(1) : null),
          ]);
        }
      }
    }
  }
  final gefunden = liste.ergebnis;
  // Die Registrierung nur, wo die Ordner nichts ergaben: Sie kennt das
  // Programm auch auf einem anderen Laufwerk, aber nicht jeder Installer
  // trägt sich dort ein.
  for (final MapEntry(key: art, value: ort) in _windowsOrte.entries) {
    if (gefunden.containsKey(art)) continue;
    for (final exe in ort.appPfade) {
      final ziel = await blick.appPfad(exe);
      if (ziel != null && await blick.gibtEs(ziel)) {
        gefunden[art] = ziel;
        break;
      }
    }
  }
  return gefunden;
}

Future<Map<Bekannt, String>> _erkenneLinux(Systemblick blick) async {
  final pfad = p.posix;
  final u = blick.umgebung;
  if (u.containsKey('FLATPAK_ID')) return const {};
  final gefunden = <Bekannt, String>{};
  final suchpfade = [
    for (final teil in (u['PATH'] ?? '').split(':'))
      if (teil.trim().isNotEmpty) teil.trim(),
  ];
  for (final MapEntry(key: art, value: befehle) in _linuxBefehle.entries) {
    suche:
    for (final befehl in befehle) {
      for (final ordner in suchpfade) {
        final voll = pfad.join(ordner, befehl);
        if (await blick.gibtEs(voll)) {
          gefunden[art] = voll;
          break suche;
        }
      }
    }
  }
  // Flatpaks legen ein Startskript unter exports/bin ab, das die Datei
  // weiterreicht; es lässt sich starten wie jedes andere Programm.
  final exporte = [
    '/var/lib/flatpak/exports/bin',
    if (u['HOME'] case final h?)
      pfad.join(h, '.local/share/flatpak/exports/bin'),
  ];
  for (final MapEntry(key: art, value: kennung) in _linuxFlatpaks.entries) {
    if (gefunden.containsKey(art)) continue;
    for (final ordner in exporte) {
      final voll = pfad.join(ordner, kennung);
      if (await blick.gibtEs(voll)) {
        gefunden[art] = voll;
        break;
      }
    }
  }
  return gefunden;
}

/// Führt [programm] mit [argumente] aus. Mit [warten] zählt der
/// Rückgabewert des Programms (für `open -a` unter macOS, das sofort
/// zurückkehrt und mit einem Fehler meldet, wenn es das Programm nicht
/// gibt), sonst nur, ob es sich starten liess.
typedef Ausfuehren =
    Future<bool> Function(
      String programm,
      List<String> argumente, {
      required bool warten,
    });

Future<bool> _echtAusfuehren(
  String programm,
  List<String> argumente, {
  required bool warten,
}) async {
  try {
    if (warten) {
      final r = await Process.run(programm, argumente);
      return r.exitCode == 0;
    }
    await Process.start(programm, argumente, mode: ProcessStartMode.detached);
    return true;
  } on ProcessException {
    return false;
  }
}

/// Startet ein [Fremdprogramm] mit einer Datei.
///
/// Ohne gefundenen Pfad gilt für darktable der Weg von vor #499 (siehe
/// `starteDarktable`). Ein anderes bekanntes Programm ohne Pfad versucht
/// es unter macOS über seinen Namen – `open -a GIMP` findet GIMP auch an
/// einem Ort, an dem die Erkennung nicht gesucht hat –, sonst gilt es als
/// nicht gestartet, und die Oberfläche öffnet den Ordner der
/// Arbeitskopie.
///
/// **Flatpak.** Aus der Sandbox des Flatpaks heraus ist kein Programm des
/// Systems erreichbar; dafür bräuchte die App `flatpak-spawn --host` und
/// damit die Erlaubnis, beliebige Befehle ausserhalb auszuführen. Das ist
/// mehr, als eine Fotoverwaltung haben sollte. Es bleibt deshalb beim
/// geöffneten Ordner, wie bisher bei darktable.
class Programmstarter {
  Programmstarter({
    String? system,
    Map<String, String>? umgebung,
    Future<bool> Function(String pfad)? gibtEs,
    Ausfuehren? ausfuehren,
  }) : system = system ?? Platform.operatingSystem,
       umgebung = umgebung ?? Platform.environment,
       _gibtEs = gibtEs ?? const EchterSystemblick().gibtEs,
       _ausfuehren = ausfuehren ?? _echtAusfuehren;

  final String system;
  final Map<String, String> umgebung;
  final Future<bool> Function(String) _gibtEs;
  final Ausfuehren _ausfuehren;

  Future<bool> starte(Fremdprogramm programm, String datei) async {
    final darktable = programm.art == Bekannt.darktable;
    switch (system) {
      case 'macos':
        final ziel = programm.pfad ?? programm.art?.anzeigename;
        if (ziel == null) return false;
        return _ausfuehren('open', ['-a', ziel, datei], warten: true);
      case 'windows':
        final wurzel = umgebung['ProgramFiles'] ?? r'C:\Program Files';
        final exe =
            programm.pfad ??
            (darktable
                ? p.windows.join(wurzel, 'darktable', 'bin', 'darktable.exe')
                : null);
        if (exe == null || !await _gibtEs(exe)) return false;
        return _ausfuehren(exe, [datei], warten: false);
      case 'linux':
        if (umgebung.containsKey('FLATPAK_ID')) return false;
        final befehl = programm.pfad ?? (darktable ? 'darktable' : null);
        if (befehl == null) return false;
        return _ausfuehren(befehl, [datei], warten: false);
    }
    return false;
  }
}

/// Das Ergebnis aus [datei] ist kein Bild, das Photo Vault lesen kann.
class ErgebnisUnlesbar implements Exception {
  const ErgebnisUnlesbar(this.pfad);
  final String pfad;

  @override
  String toString() => 'ErgebnisUnlesbar($pfad)';
}

/// Die Bytes für `speichereNeueFassung`: ein JPEG.
///
/// Eine neue Fassung ist in der Bibliothek immer ein JPEG – sowohl
/// `speichereBearbeitung` als auch der Weg über den Server legen die Bytes
/// unter `.jpg` ab. Ein JPEG geht unverändert durch (erkannt am Inhalt,
/// nicht an der Endung), TIFF und PNG werden einmal zu JPEG in Qualität 95.
/// Das kostet die 16 Bit eines TIFF; die Bibliothek hätte sie ohnehin nicht
/// gehalten.
///
/// **Angaben.** Das Farbprofil geht mit, die EXIF-Angaben nicht: Ein TIFF
/// trägt in demselben Verzeichnis seine Streifen und Kachelversätze, die
/// in einem JPEG ins Leere zeigten. Aufnahmedatum, Ort und Kamera stehen
/// in der Datenbank und bleiben an der Aufnahme. Eine Drehung aus den
/// Angaben wird vorher ins Bild gerechnet.
Future<Uint8List> ergebnisAlsJpeg(File datei) async {
  final bytes = await datei.readAsBytes();
  if (bytes.length > 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return bytes;
  }
  Uint8List? jpeg;
  try {
    jpeg = await berechne(_alsJpeg, bytes);
  } on Object {
    jpeg = null;
  }
  if (jpeg == null) throw ErgebnisUnlesbar(datei.path);
  return jpeg;
}

Uint8List? _alsJpeg(Uint8List bytes) {
  var bild = img.decodeImage(bytes);
  if (bild == null) return null;
  final ifd = bild.exif.imageIfd;
  if (ifd.hasOrientation && ifd.orientation != 1) {
    bild = img.bakeOrientation(bild);
  }
  bild
    ..exif = img.ExifData()
    // Durchsichtiges aus einem PNG wird weiss, nicht schwarz.
    ..backgroundColor = img.ColorRgb8(255, 255, 255);
  return img.encodeJpg(bild, quality: 95);
}
