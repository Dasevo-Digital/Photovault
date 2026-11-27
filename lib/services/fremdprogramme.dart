import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kern/berechne.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/platform/desktop_image_tools.dart';
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

/// Führt ein Programm aus und wartet auf sein Ende.
typedef Prozesslauf =
    Future<ProcessResult> Function(String programm, List<String> argumente);

Future<ProcessResult> _prozess(String programm, List<String> argumente) =>
    Process.run(programm, argumente);

/// Der echte [Systemblick]. [system], [umgebung] und [laufe] lassen sich
/// für die Tests vorgeben; ohne Angabe gilt das laufende System.
class EchterSystemblick implements Systemblick {
  const EchterSystemblick({
    this._system,
    this._umgebung,
    this.laufe = _prozess,
  });

  final String? _system;
  final Map<String, String>? _umgebung;
  final Prozesslauf laufe;

  @override
  String get system => _system ?? Platform.operatingSystem;

  @override
  Map<String, String> get umgebung => _umgebung ?? Platform.environment;

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

  /// Fragt die Registrierung mit `reg.exe` aus dem Systemordner, nicht mit
  /// `reg` über den Suchpfad: Ein `reg.exe` oder `reg.bat` im
  /// Arbeitsordner oder weiter vorn im PATH liefe sonst an seiner Stelle.
  @override
  Future<String?> appPfad(String exe) async {
    if (system != 'windows') return null;
    for (final zweig in const ['HKCU', 'HKLM']) {
      try {
        final r = await laufe(regPfad(umgebung), [
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

/// Wo `reg.exe` liegt: `%SystemRoot%\System32`, ohne die Variable
/// `C:\Windows`.
String regPfad(Map<String, String> umgebung) {
  String? wert(String name) {
    for (final e in umgebung.entries) {
      if (e.key.toLowerCase() == name) return e.value;
    }
    return null;
  }

  final wurzel = wert('systemroot') ?? wert('windir') ?? r'C:\Windows';
  return p.windows.join(wurzel, 'System32', 'reg.exe');
}

/// Ob [pfad] eine `.exe` ist. Unter Windows startet nur eine solche:
/// Eine `.bat` oder `.cmd` reicht CreateProcess an `cmd.exe` weiter, und
/// dort würde ein `&` im Namen der Arbeitskopie zum nächsten Befehl.
bool istExe(String pfad) => p.windows.extension(pfad).toLowerCase() == '.exe';

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

/// Ein Name, unter dem ein Programm liegt. [rang] ordnet die Generationen
/// vor jeder Fassungsnummer; die erste Gruppe von [muster] ist die
/// Fassung innerhalb einer Generation.
typedef _Name = ({RegExp muster, int rang});

/// Die Namen der Programme unter macOS, ohne `.app`. Bei mehreren gewinnt
/// der höchste Rang, darin die neueste Fassung.
///
/// **Jahresfassungen.** Adobe und ON1 hängen das Jahr an den Namen
/// („Adobe Photoshop 2026“, „ON1 Photo RAW 2027“) und legen das Bündel in
/// einen gleichnamigen Ordner unter /Programme. Wer zwei Jahre
/// nebeneinander hat, will das neuere.
///
/// **Nachfolger ohne Nummer.** „Affinity“ allein ist die Nachfolgerin von
/// „Affinity Photo 2“, die Foto, Grafik und Layout vereint; „GIMP“ ist
/// GIMP 3, die Fassung davor hiess „GIMP-2.10“. Nach der Nummer allein
/// verlöre der Nachfolger, weil er keine trägt – deshalb der Rang.
final Map<Bekannt, List<_Name>> _macNamen = {
  Bekannt.darktable: [
    (muster: RegExp(r'^darktable$', caseSensitive: false), rang: 1),
  ],
  Bekannt.on1: [
    (muster: RegExp(r'^ON1 Photo RAW(?: MAX)?(?: (\d{4}))?$'), rang: 1),
  ],
  Bekannt.affinity: [
    (muster: RegExp(r'^Affinity$'), rang: 2),
    (muster: RegExp(r'^Affinity Photo(?: (\d+))?$'), rang: 1),
  ],
  Bekannt.photoshop: [
    (muster: RegExp(r'^Adobe Photoshop(?: CC)?(?: (\d{4}))?$'), rang: 1),
  ],
  Bekannt.gimp: [
    (muster: RegExp(r'^GIMP$', caseSensitive: false), rang: 2),
    (
      muster: RegExp(r'^GIMP[- ](\d+(?:\.\d+)*)$', caseSensitive: false),
      rang: 1,
    ),
  ],
};

/// Wo die Programme unter Windows liegen: im Programmordner, bei Adobe,
/// Affinity und ON1 darunter im Ordner des Herstellers, dann der Ordner
/// des Programms (auch hier mit Jahr oder Fassung) und darin die `.exe`.
///
/// [raenge] ordnet wie unter macOS die Generationen vor der Nummer, nach
/// dem Namen der `.exe` (klein geschrieben); ohne Eintrag Rang 1.
typedef _Windowsort = ({
  String? hersteller,
  RegExp ordner,
  String unterordner,
  RegExp exe,
  List<String> appPfade,
  Map<String, int> raenge,
});

final Map<Bekannt, _Windowsort> _windowsOrte = {
  Bekannt.darktable: (
    hersteller: null,
    ordner: RegExp(r'^darktable$', caseSensitive: false),
    unterordner: 'bin',
    exe: RegExp(r'^darktable\.exe$', caseSensitive: false),
    appPfade: ['darktable.exe'],
    raenge: const {},
  ),
  Bekannt.gimp: (
    hersteller: null,
    ordner: RegExp(r'^GIMP(?: (\d+(?:\.\d+)*))?$', caseSensitive: false),
    unterordner: 'bin',
    // Nicht gimp-console-3.0.exe: Das ist die Fassung ohne Fenster.
    exe: RegExp(r'^gimp-(\d+(?:\.\d+)*)\.exe$', caseSensitive: false),
    appPfade: ['gimp-3.exe', 'gimp-3.0.exe', 'gimp-2.10.exe'],
    raenge: const {},
  ),
  Bekannt.photoshop: (
    hersteller: 'Adobe',
    ordner: RegExp(r'^Adobe Photoshop(?: CC)?(?: (\d{4}))?$'),
    unterordner: '',
    exe: RegExp(r'^Photoshop\.exe$', caseSensitive: false),
    appPfade: ['Photoshop.exe'],
    raenge: const {},
  ),
  Bekannt.affinity: (
    hersteller: 'Affinity',
    ordner: RegExp(r'^(?:Affinity(?: Photo)?|Photo)(?: (\d+))?$'),
    unterordner: '',
    exe: RegExp(r'^(?:Photo|Affinity)\.exe$', caseSensitive: false),
    appPfade: const [],
    // Die Nachfolgerin von Affinity Photo 2 (siehe _macNamen).
    raenge: const {'affinity.exe': 2},
  ),
  Bekannt.on1: (
    hersteller: 'ON1',
    ordner: RegExp(r'^ON1 Photo RAW(?: MAX)?(?: (\d{4}))?$'),
    unterordner: '',
    exe: RegExp(r'^ON1 Photo RAW(?: MAX)?(?: (\d{4}))?\.exe$'),
    appPfade: const [],
    raenge: const {},
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
    for (final MapEntry(key: art, value: namen) in _macNamen.entries) {
      for (final n in namen) {
        final m = n.muster.firstMatch(stamm);
        if (m == null) continue;
        liste.biete(art, pfad.join(ort, name), [
          n.rang,
          ..._fassung(m.groupCount > 0 ? m.group(1) : null),
        ]);
      }
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
      if (!_macNamen.values.any((l) => l.any((n) => n.muster.hasMatch(name)))) {
        continue;
      }
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
            ort.raenge[exe.toLowerCase()] ?? 1,
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
      // Ein Installer kann dort auch eine .bat eintragen (siehe istExe).
      if (ziel != null && istExe(ziel) && await blick.gibtEs(ziel)) {
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
///
/// **Windows.** Gestartet wird nur eine `.exe`, die als gewöhnliche Datei
/// da ist ([gibtEs]); siehe [istExe].
class Programmstarter {
  Programmstarter({
    String? system,
    Map<String, String>? umgebung,
    Future<bool> Function(String pfad)? gibtEs,
    Ausfuehren? ausfuehren,
  }) : system = system ?? Platform.operatingSystem,
       umgebung = umgebung ?? Platform.environment,
       _gibtEs = gibtEs ?? _istDatei,
       _ausfuehren = ausfuehren ?? _echtAusfuehren;

  static Future<bool> _istDatei(String pfad) async {
    try {
      return await FileSystemEntity.type(pfad) == FileSystemEntityType.file;
    } on Object {
      return false;
    }
  }

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
        if (exe == null || !istExe(exe) || !await _gibtEs(exe)) return false;
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

/// Warum ein Ergebnis nicht übernommen werden kann.
enum Unlesbarkeit {
  /// Kein Bild, das Photo Vault lesen kann.
  format,

  /// Abgeschnitten: Das Programm schreibt noch oder ist beim Speichern
  /// abgebrochen.
  unvollstaendig,

  /// Zu gross, um es ohne die Werkzeuge des Systems umzuwandeln (siehe
  /// [ergebnisHoechstensPixel]).
  zuGross,

  /// Ein TIFF (oder ein Farbprofil), das ohne die Werkzeuge des Systems
  /// nicht zuverlässig umzuwandeln ist (siehe [ergebnisAlsJpeg]).
  nurMitWerkzeug,
}

/// Das Ergebnis aus [pfad] lässt sich nicht übernehmen; [grund] sagt,
/// warum. [megapixel] nur bei [Unlesbarkeit.zuGross].
class ErgebnisUnlesbar implements Exception {
  const ErgebnisUnlesbar(
    this.pfad, [
    this.grund = Unlesbarkeit.format,
    this.megapixel,
  ]);
  final String pfad;
  final Unlesbarkeit grund;
  final int? megapixel;

  @override
  String toString() => 'ErgebnisUnlesbar($pfad, ${grund.name})';
}

/// Wie viele Pixel ein Ergebnis höchstens haben darf, das Dart selbst
/// umwandelt: 120 Megapixel, genug für die grössten Kameras (102 MP).
/// Ein 16-Bit-TIFF dieser Grösse belegt dabei schon rund 700 MB. Die
/// Werkzeuge des Systems lesen in Streifen und brauchen die Grenze nicht.
const ergebnisHoechstensPixel = 120 * 1000 * 1000;

/// Der Weg für ein TIFF vor `package:image` (#499): unter macOS ImageIO
/// über den Kanal der App ([Bildwerkzeuge.standard]), sonst libvips
/// ([DesktopImageTools.nurMitVips]). Beide lesen das Farbprofil und jede
/// Kompressionsart. `null`, wenn es den Weg nicht gibt oder er scheitert.
///
/// Unter Linux und Windows bewusst nicht über
/// `Bildwerkzeuge.convertToJpegBytes`: Fehlt libvips, rechnet der dort
/// mit `package:image` weiter – genau dem Weg, der ein TIFF falsch lesen
/// kann, und ohne die Prüfung von [ergebnisAlsJpeg].
Future<Uint8List?> tiffUeberWerkzeug(File datei) async {
  if (Platform.isMacOS) {
    return Bildwerkzeuge.standard.convertToJpegBytes(
      datei,
      maxDimension: null,
      quality: 0.95,
    );
  }
  return DesktopImageTools.nurMitVips(datei, quality: 95);
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
/// **Vollständig.** Ein JPEG muss bis zum Ende seines Bildes reichen
/// ([jpegVollstaendig]); sonst wäre ein halb geschriebenes Ergebnis als
/// Fassung mit grauem Rand in der Bibliothek gelandet.
///
/// **TIFF zuerst über die Werkzeuge des Systems** ([tiff]: Vorgabe
/// [tiffUeberWerkzeug]). Der TIFF-Leser von `package:image` 4.12 liest
/// kein Farbprofil (Tag 34675), übergeht bei Deflate den Prädiktor,
/// rechnet ihn bei 16-Bit-LZW byteweise und verschluckt Fehler im
/// LZW-Strom – heraus kam ein falsches Bild ohne jede Meldung. Er springt
/// nur noch ein, wenn es keinen anderen Weg gibt, und dann nur für TIFFs,
/// die er richtig liest (siehe [_tiffFuerDart]); das Farbprofil setzt
/// Photo Vault selbst. Alles andere lehnt er mit
/// [Unlesbarkeit.nurMitWerkzeug] ab.
///
/// **Angaben.** Das Farbprofil geht mit, die EXIF-Angaben nicht: Ein TIFF
/// trägt in demselben Verzeichnis seine Streifen und Kachelversätze, die
/// in einem JPEG ins Leere zeigten. Aufnahmedatum, Ort und Kamera stehen
/// in der Datenbank und bleiben an der Aufnahme. Eine Drehung aus den
/// Angaben wird vorher ins Bild gerechnet.
///
/// **Speicher.** Dart liest die Datei erst im eigenen Isolat (nur der Pfad
/// geht hinüber, zurück kommt das JPEG ohne Kopie), prüft vor dem
/// Dekodieren die Masse
/// ([ergebnisHoechstensPixel]) und liest nur die erste Seite eines
/// mehrseitigen TIFF.
Future<Uint8List> ergebnisAlsJpeg(
  File datei, {
  Future<Uint8List?> Function(File datei) tiff = tiffUeberWerkzeug,
}) async {
  final kopf = await _kopf(datei);
  if (_istJpeg(kopf)) {
    // Auch das Prüfen läuft im Isolat: Ein JPEG mit 30 MB ist ebenso
    // viele Bytes, durch die es gehen muss.
    final ({Uint8List? jpeg, Unlesbarkeit? grund, int? megapixel}) r;
    try {
      r = await berechne(_jpegLesen, datei.path);
    } on Object {
      throw ErgebnisUnlesbar(datei.path);
    }
    if (r.jpeg case final jpeg?) return jpeg;
    throw ErgebnisUnlesbar(datei.path, r.grund ?? Unlesbarkeit.format);
  }
  if (_istTiff(kopf)) {
    Uint8List? werkzeug;
    try {
      werkzeug = await tiff(datei);
    } on Object {
      werkzeug = null;
    }
    if (werkzeug != null && jpegVollstaendig(werkzeug)) return werkzeug;
  }
  final ({Uint8List? jpeg, Unlesbarkeit? grund, int? megapixel}) r;
  try {
    r = await berechne(_alsJpeg, datei.path);
  } on Object {
    throw ErgebnisUnlesbar(datei.path);
  }
  if (r.jpeg case final jpeg?) return jpeg;
  throw ErgebnisUnlesbar(
    datei.path,
    r.grund ?? Unlesbarkeit.format,
    r.megapixel,
  );
}

Future<Uint8List> _kopf(File datei) async {
  final f = await datei.open();
  try {
    return await f.read(16);
  } finally {
    await f.close();
  }
}

bool _istJpeg(Uint8List b) =>
    b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

bool _istTiff(Uint8List b) =>
    b.length > 3 &&
    ((b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0x00) ||
        (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A));

/// Ob [b] ein vollständiges JPEG ist: vom Anfang über alle Segmente und
/// die Bilddaten bis zum Ende des Hauptbilds (EOI).
///
/// Danach darf noch etwas folgen – manche Kameras und Programme hängen
/// Daten an, MPF ein zweites Bild. Das Vorschaubild im EXIF zählt nicht
/// als Ende: Es steckt in einem Segment, das mit seiner Länge
/// übersprungen wird. In den Bilddaten selbst kann keine Endmarke
/// vorkommen, weil dort jedes 0xFF ein 0x00 hinter sich hat; ein
/// abgeschnittenes JPEG hat also keine.
bool jpegVollstaendig(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return false;
  var i = 2;
  while (i < b.length) {
    if (b[i] != 0xFF) return false;
    // Füllbytes vor einer Marke.
    while (i < b.length && b[i] == 0xFF) {
      i++;
    }
    if (i >= b.length) return false;
    final marke = b[i++];
    if (marke == 0xD9) return true;
    // Marken ohne Länge.
    if (marke == 0x01 || (marke >= 0xD0 && marke <= 0xD7)) continue;
    if (i + 2 > b.length) return false;
    final laenge = (b[i] << 8) | b[i + 1];
    if (laenge < 2) return false;
    i += laenge;
    if (i > b.length) return false;
    if (marke != 0xDA) continue;
    // Bilddaten nach SOS: bis zur nächsten Marke, die weder ein
    // gestopftes 0x00 noch eine Wiederaufsetzmarke ist.
    while (true) {
      if (i + 1 >= b.length) return false;
      if (b[i] == 0xFF) {
        final n = b[i + 1];
        if (n == 0x00 || (n >= 0xD0 && n <= 0xD7)) {
          i += 2;
          continue;
        }
        if (n == 0xFF) {
          i++;
          continue;
        }
        break;
      }
      i++;
    }
  }
  return false;
}

/// Wie gross ein Farbprofil in einem einzigen APP2-Segment höchstens sein
/// darf; der JPEG-Kodierer von `package:image` teilt grössere nicht auf.
const _iccHoechstens = 65519 - 14;

/// Im eigenen Isolat: liest das JPEG unter [pfad] und prüft, ob es
/// vollständig ist.
({Uint8List? jpeg, Unlesbarkeit? grund, int? megapixel}) _jpegLesen(
  String pfad,
) {
  final bytes = File(pfad).readAsBytesSync();
  return jpegVollstaendig(bytes)
      ? (jpeg: bytes, grund: null, megapixel: null)
      : (jpeg: null, grund: Unlesbarkeit.unvollstaendig, megapixel: null);
}

/// Im eigenen Isolat: liest [pfad] und wandelt ihn in ein JPEG.
({Uint8List? jpeg, Unlesbarkeit? grund, int? megapixel}) _alsJpeg(String pfad) {
  ({Uint8List? jpeg, Unlesbarkeit? grund, int? megapixel}) nicht(
    Unlesbarkeit grund, [
    int? megapixel,
  ]) => (jpeg: null, grund: grund, megapixel: megapixel);

  final bytes = File(pfad).readAsBytesSync();
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) return nicht(Unlesbarkeit.format);
  final info = decoder.startDecode(bytes);
  if (info == null) return nicht(Unlesbarkeit.format);
  final (breite, hoehe) = decoder is img.TiffDecoder
      ? switch (decoder.info?.images) {
          final bilder? when bilder.isNotEmpty => (
            bilder.first.width,
            bilder.first.height,
          ),
          _ => (0, 0),
        }
      : (info.width, info.height);
  if (breite <= 0 || hoehe <= 0) return nicht(Unlesbarkeit.format);
  if (breite * hoehe > ergebnisHoechstensPixel) {
    return nicht(Unlesbarkeit.zuGross, (breite * hoehe / 1000000).ceil());
  }

  img.Image? bild;
  img.ExifData? exif;
  if (decoder is img.TiffDecoder) {
    final seite = decoder.info!.images.first;
    if (!_tiffFuerDart(seite)) return nicht(Unlesbarkeit.nurMitWerkzeug);
    bild = decoder.decodeFrame(0);
    exif = decoder.exif;
    // Der Leser übernimmt das Profil nicht; ohne es stünden Farben aus
    // Adobe RGB oder ProPhoto als sRGB da, blass oder grell.
    Uint8List? icc;
    try {
      icc = seite.tags[34675]?.read()?.toData();
    } on Object {
      return nicht(Unlesbarkeit.nurMitWerkzeug);
    }
    if (bild != null && icc != null && icc.isNotEmpty) {
      bild.iccProfile = img.IccProfile(
        'ICC Profile',
        img.IccProfileCompression.none,
        Uint8List.fromList(icc),
      );
    }
  } else {
    // Nur die erste Seite bzw. das erste Bild einer Animation.
    bild = decoder.decode(bytes, frame: 0);
    exif = bild?.exif;
  }
  if (bild == null) return nicht(Unlesbarkeit.format);
  if (bild.iccProfile case final icc?
      when icc.decompressed().length > _iccHoechstens) {
    return nicht(Unlesbarkeit.nurMitWerkzeug);
  }
  final lage = exif?.imageIfd;
  if (lage != null && lage.hasOrientation && lage.orientation != 1) {
    bild.exif = exif!;
    bild = img.bakeOrientation(bild);
  }
  bild
    ..exif = img.ExifData()
    // Durchsichtiges aus einem PNG wird weiss, nicht schwarz.
    ..backgroundColor = img.ColorRgb8(255, 255, 255);
  final jpeg = img.encodeJpg(bild, quality: 95);
  return jpegVollstaendig(jpeg)
      ? (jpeg: jpeg, grund: null, megapixel: null)
      : nicht(Unlesbarkeit.format);
}

/// Ob `package:image` diese TIFF-Seite richtig liest: unkomprimiert,
/// PackBits oder Deflate ohne Prädiktor, mit 8 oder 16 Bit Ganzzahlen.
///
/// Abgelehnt werden LZW (Fehler im Strom werden verschluckt, bei 16 Bit
/// rechnet der Prädiktor byteweise), Deflate mit Prädiktor (wird
/// übergangen), JPEG im TIFF (ein Fehler lässt die Kachel leer),
/// Fax-Kompressionen und Fliesskomma.
bool _tiffFuerDart(img.TiffImage seite) {
  const ohne = 1, deflate = 8, zip = 32946, packBits = 32773;
  return const {ohne, deflate, zip, packBits}.contains(seite.compression) &&
      seite.predictor == 1 &&
      (seite.bitsPerSample == 8 || seite.bitsPerSample == 16) &&
      seite.sampleFormat == img.TiffFormat.uint;
}
