import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'bearbeitungsbruecke.dart';
import 'darktable_bruecke.dart';
import 'fremdprogramme.dart';
import 'library_location.dart';
import 'platform/reveal_in_file_manager.dart';

/// Welche Programme unter „Bearbeiten in“ stehen, und die Wege zu ihnen
/// (#499).
///
/// **Was gilt, wenn nichts eingestellt ist.** Ein bekanntes Programm steht
/// im Menü, wenn es gefunden wurde. darktable steht immer da, wie vor
/// #499: Seine Erkennung sieht nicht jeden Ort (eigene Pfade, ein
/// darktable aus dem Flatpak neben einem Photo Vault aus dem Flatpak), und
/// auch ohne Start ist der Weg nützlich – die Arbeitskopie liegt bereit,
/// ihr Ordner geht auf, und eine fertige Bearbeitung rendert auf Wunsch
/// der Server. Selbst gewählte Programme stehen da, bis man sie
/// ausschaltet oder entfernt.
///
/// **Wo die Einstellung liegt.** In `bearbeiten_in.json` im Datenordner
/// der App, nicht in der Datenbank – wie `sicherungsziel.json`. Ein
/// Programmpfad gilt nur auf diesem Rechner; die Datenbank wandert in
/// jede Sicherung und kann auf einem anderen System geöffnet werden, wo
/// `/Applications/GIMP.app` nichts bedeutet.
///
/// **Erkannt wird einmal je Programmlauf** ([laden]), beim Öffnen der
/// Einstellungen neu: Wer dort nachsieht, hat vielleicht gerade etwas
/// installiert. Das Menü fragt nie selbst nach – es baut sich bei jedem
/// Rechtsklick auf und muss sofort stehen.
///
/// **Ordnernamen werden nie zweimal vergeben.** Ein entferntes Programm
/// behält seinen Ordner in der Einstellung (`frueher`); ein neues
/// gleichen Namens bekommt einen anderen. Sonst „fände“ es die
/// Arbeitskopien des alten und böte an, sie als sein Ergebnis zu
/// übernehmen. Wer dasselbe Programm wieder aufnimmt, bekommt seinen
/// alten Ordner zurück.
class Bearbeitungsprogramme extends ChangeNotifier {
  Bearbeitungsprogramme({
    required this.basis,
    required this._einstellungen,
    String? system,
    Future<Map<Bekannt, String>> Function()? erkenne,
    Programmstarter? starter,
    Future<String?> Function(String? titel)? waehle,
    Future<bool> Function(String ordner)? zeigeOrdner,
    this.ruhe = const Duration(seconds: 2),
  }) : system = system ?? Platform.operatingSystem,
       _erkenne =
           erkenne ?? (() => erkenneProgramme(const EchterSystemblick())),
       _starter = starter ?? Programmstarter(),
       _waehle = waehle ?? _waehleMitDialog,
       _zeigeOrdner = zeigeOrdner ?? revealInFileManager;

  /// Die eine Liste der App. Einstellungen und Vollbild teilen sie: Was in
  /// den Einstellungen umgeschaltet wird, steht beim nächsten Rechtsklick
  /// im Menü, auch in einem schon offenen Vollbild.
  static final standard = Bearbeitungsprogramme(
    basis: Directory(arbeitsordnerBasis()),
    einstellungen: () async => File(
      p.join((await LibraryLocation.datenordner()).path, 'bearbeiten_in.json'),
    ),
  );

  /// Wo die Ordner der Arbeitskopien liegen (siehe [arbeitsordnerBasis]).
  final Directory basis;

  /// Wie `Platform.operatingSystem`.
  final String system;

  /// Wie lange ein Ergebnis unverändert liegen muss, ehe es übernommen
  /// wird (siehe [Bearbeitungsbruecke.fertig]).
  final Duration ruhe;
  final Future<File> Function() _einstellungen;
  final Future<Map<Bekannt, String>> Function() _erkenne;
  final Programmstarter _starter;
  final Future<String?> Function(String? titel) _waehle;
  final Future<bool> Function(String) _zeigeOrdner;

  Map<Bekannt, String> _gefunden = const {};
  Map<String, bool> _schalter = {};
  List<({String name, String pfad, String ordner})> _eigene = [];

  /// Entfernte eigene Programme: ihr Ordner bleibt vergeben.
  List<({String pfad, String ordner})> _frueher = [];
  final _bruecken = <String, Bearbeitungsbruecke>{};
  Future<void>? _laeuft;
  Future<void>? _einlesen;
  Future<void> _speicherkette = Future.value();
  bool _geladen = false;

  /// Ob die Erkennung schon einmal gelaufen ist.
  bool get geladen => _geladen;

  /// Ob Photo Vault als Flatpak läuft und deshalb nichts starten kann
  /// (siehe [Programmstarter]).
  bool get imFlatpak =>
      system == 'linux' && _starter.umgebung.containsKey('FLATPAK_ID');

  /// Alle Programme dieses Systems, die bekannten zuerst.
  List<Fremdprogramm> get alle => [
    for (final art in Bekannt.values)
      if (art.gibtEsAuf(system))
        Fremdprogramm.bekannt(
          art,
          pfad: _gefunden[art],
          aktiv:
              _schalter[art.name] ??
              (art == Bekannt.darktable || _gefunden.containsKey(art)),
        ),
    for (final e in _eigene)
      Fremdprogramm(
        kennung: _eigenKennung(e.pfad),
        name: e.name,
        ordner: e.ordner,
        pfad: e.pfad,
        aktiv: _schalter[_eigenKennung(e.pfad)] ?? true,
      ),
  ];

  /// Was im Menü steht.
  List<Fremdprogramm> get aktive => [
    for (final x in alle)
      if (x.aktiv) x,
  ];

  static String _eigenKennung(String pfad) => 'eigen:$pfad';

  /// Liest die Einstellung und sucht die Programme. Läuft schon eine
  /// Suche, wartet es auf diese. [neu] sucht noch einmal, auch wenn schon
  /// gesucht wurde.
  Future<void> laden({bool neu = false}) {
    if (_geladen && !neu) return Future.value();
    return _laeuft ??= _lade().whenComplete(() => _laeuft = null);
  }

  Future<void> _lade() async {
    await _eingelesenAbwarten();
    try {
      _gefunden = await _erkenne();
    } on Object catch (e) {
      debugPrint('Programme nicht erkannt: $e');
    }
    _geladen = true;
    notifyListeners();
  }

  /// Wie ein Arbeitsordner heissen darf (#499). Was aus der Datei kommt,
  /// wird geprüft, ehe es ein Pfad wird: Ein absoluter Pfad oder `..`
  /// führte aus [basis] hinaus, und beim Aufräumen würde dort gelöscht.
  static final _ordnerMuster = RegExp(r'^PhotoVault-[A-Za-z0-9 ._-]+$');

  static bool _gueltigerOrdner(String ordner) =>
      _ordnerMuster.hasMatch(ordner) &&
      !ordner.contains('..') &&
      !ordner.endsWith('.') &&
      !ordner.endsWith(' ');

  Future<void> _liesEin() async {
    final File datei;
    try {
      datei = await _einstellungen();
      if (!await datei.exists()) return;
    } on Object catch (e) {
      debugPrint('bearbeiten_in.json nicht erreichbar: $e');
      return;
    }
    Object? j;
    try {
      j = jsonDecode(await datei.readAsString());
    } on Object catch (e) {
      debugPrint('bearbeiten_in.json nicht lesbar: $e');
      j = null;
    }
    if (j is! Map || j['fassung'] != 1) {
      // Eine kaputte Datei kostet die Einstellung, nicht das Menü – und
      // wird beiseitegelegt statt beim nächsten Speichern überschrieben.
      // Wer sie von Hand bearbeitet hat, findet sie dort wieder.
      try {
        await datei.rename('${datei.path}.kaputt');
      } on FileSystemException catch (e) {
        debugPrint('bearbeiten_in.json nicht beiseitegelegt: $e');
      }
      return;
    }
    _schalter = {
      for (final MapEntry(:key, :value)
          in ((j['schalter'] as Map?) ?? const {}).entries)
        if (value is bool) '$key': value,
    };
    _frueher = [
      for (final e in (j['frueher'] as List?) ?? const [])
        if (e is Map &&
            e['pfad'] is String &&
            e['ordner'] is String &&
            _gueltigerOrdner(e['ordner'] as String))
          (pfad: e['pfad'] as String, ordner: e['ordner'] as String),
    ];
    _eigene = [];
    var neuVergeben = false;
    for (final e in (j['eigene'] as List?) ?? const []) {
      if (e is! Map ||
          e['name'] is! String ||
          e['pfad'] is! String ||
          e['ordner'] is! String) {
        continue;
      }
      final name = e['name'] as String;
      final ordner = e['ordner'] as String;
      // Ungültig oder schon vergeben (der Ordner von darktable, ein
      // zweites Mal derselbe): ein frischer Name statt eines fremden
      // Ordners.
      final gut =
          _gueltigerOrdner(ordner) && !_belegt().contains(ordner.toLowerCase());
      neuVergeben |= !gut;
      _eigene.add((
        name: name,
        pfad: e['pfad'] as String,
        ordner: gut ? ordner : _freierOrdner(name),
      ));
    }
    // Gleich festhalten: Beim nächsten Start läge unter dem frischen Namen
    // vielleicht schon ein Ordner, und er bekäme wieder einen anderen.
    if (neuVergeben) await _speichern();
  }

  /// Vor jeder Änderung: Ist die Datei noch nicht gelesen, schriebe das
  /// Speichern sonst eine leere Liste über die eigenen Programme. Liest
  /// nur die Datei, sucht keine Programme.
  Future<void> _eingelesenAbwarten() => _einlesen ??= _liesEin();

  /// Schreibt die Einstellung. Nacheinander, nie zwei Schreiber zugleich:
  /// Beide schrieben in dieselbe `.neu`-Datei, und der zweite fände sie
  /// beim Umbenennen nicht mehr. Geschrieben wird der Stand beim
  /// Schreiben, also immer der neueste.
  Future<void> _speichern() {
    final lauf = _speicherkette.then((_) => _schreibe());
    _speicherkette = lauf.catchError((Object _) {});
    return lauf;
  }

  Future<void> _schreibe() async {
    final datei = await _einstellungen();
    await datei.parent.create(recursive: true);
    final teil = File('${datei.path}.neu');
    await teil.writeAsString(
      jsonEncode({
        'fassung': 1,
        'schalter': _schalter,
        'eigene': [
          for (final e in _eigene)
            {'name': e.name, 'pfad': e.pfad, 'ordner': e.ordner},
        ],
        'frueher': [
          for (final e in _frueher) {'pfad': e.pfad, 'ordner': e.ordner},
        ],
      }),
      flush: true,
    );
    await teil.rename(datei.path);
  }

  /// Schaltet ein Programm im Menü ein oder aus.
  Future<void> schalte(String kennung, bool an) async {
    await _eingelesenAbwarten();
    _schalter[kennung] = an;
    notifyListeners();
    await _speichern();
  }

  /// Nimmt das Programm unter [pfad] auf („Anderes Programm …“) und
  /// liefert es, eingeschaltet. Ist es schon bekannt – gefunden oder
  /// früher gewählt –, wird kein zweiter Eintrag daraus.
  Future<Fremdprogramm> fuegeHinzu(String pfad) async {
    await _eingelesenAbwarten();
    for (final x in alle) {
      if (x.pfad != null && _gleich(x.pfad!, pfad)) {
        if (!x.aktiv) await schalte(x.kennung, true);
        return alle.firstWhere((y) => y.kennung == x.kennung);
      }
    }
    final name = programmnameAus(pfad);
    final alt = _frueher.where((e) => _gleich(e.pfad, pfad)).firstOrNull;
    _frueher = [
      for (final e in _frueher)
        if (e != alt) e,
    ];
    _eigene = [
      ..._eigene,
      (name: name, pfad: pfad, ordner: alt?.ordner ?? _freierOrdner(name)),
    ];
    _schalter.remove(_eigenKennung(pfad));
    notifyListeners();
    await _speichern();
    return alle.firstWhere((y) => y.kennung == _eigenKennung(pfad));
  }

  /// Entfernt ein selbst gewähltes Programm. Sein Ordner bleibt vergeben
  /// (siehe oben).
  ///
  /// Mit [kopienWeg] räumt es vorher seine Arbeitskopien weg, wie beim
  /// Sperren ([Bearbeitungsbruecke.raeumeKlartextWeg]): Was Photo Vault
  /// hineingelegt hat, geht; was das Programm gespeichert hat, bleibt.
  /// Liefert die Ordner, in denen etwas blieb. Ohne [kopienWeg] bleibt
  /// alles liegen – darin kann eine halbe Bearbeitung stecken.
  Future<List<Directory>> entferne(
    String kennung, {
    bool kopienWeg = false,
  }) async {
    await _eingelesenAbwarten();
    final geblieben = <Directory>[];
    final programm = alle.where((x) => x.kennung == kennung).firstOrNull;
    if (programm == null || !programm.eigenes) return geblieben;
    if (kopienWeg) {
      final b = bruecke(programm);
      for (final id in await _aufnahmenIn(b.ablage)) {
        if (await b.raeumeKlartextWeg(id) case final d?) geblieben.add(d);
      }
    }
    _eigene = [
      for (final e in _eigene)
        if (_eigenKennung(e.pfad) != kennung) e,
    ];
    _frueher = [..._frueher, (pfad: programm.pfad!, ordner: programm.ordner)];
    _schalter.remove(kennung);
    _bruecken.remove(kennung);
    notifyListeners();
    await _speichern();
    return geblieben;
  }

  /// Ob im Ordner von [programm] noch Arbeitsordner liegen.
  Future<bool> hatArbeitsordner(Fremdprogramm programm) async =>
      (await _aufnahmenIn(bruecke(programm).ablage)).isNotEmpty;

  /// Die Aufnahmen, für die unter [ablage] ein Ordner liegt.
  Future<List<String>> _aufnahmenIn(Directory ablage) async {
    try {
      return [
        await for (final e in ablage.list(followLinks: false))
          if (e is Directory) p.basename(e.path),
      ];
    } on FileSystemException {
      return const [];
    }
  }

  /// Beim Sperren und beim endgültigen Löschen von [ids] (#499): räumt in
  /// jedem Arbeitsordner auf, was Photo Vault für diese Aufnahmen angelegt
  /// hat (siehe [Bearbeitungsbruecke.raeumeKlartextWeg]) – auch in denen
  /// entfernter Programme und in Ordnern, die keine Einstellung mehr
  /// kennt. Liefert die Ordner, in denen Dateien eines Programms liegen
  /// blieben.
  Future<List<Directory>> raeumeKlartextWeg(Iterable<String> ids) async {
    final kennungen = ids.toSet();
    if (kennungen.isEmpty) return const [];
    await _eingelesenAbwarten();
    final eigene = [for (final x in alle) bruecke(x)];
    final bekannt = {for (final b in eigene) p.normalize(b.ablage.path)};
    // Ordner, die keine Einstellung mehr kennt. Unter „Bilder“ kann auch
    // anderes so heissen (eine Sicherung „PhotoVault-Backup“); dort wird
    // nur angefasst, was eine Marke als Arbeitsordner ausweist.
    final fremde = <Bearbeitungsbruecke>[];
    try {
      await for (final e in basis.list(followLinks: false)) {
        if (e is! Directory ||
            !_gueltigerOrdner(p.basename(e.path)) ||
            bekannt.contains(p.normalize(e.path))) {
          continue;
        }
        fremde.add(Bearbeitungsbruecke(e, starte: (_) async => false));
      }
    } on FileSystemException {
      // Keine Basis, also auch nichts aufzuräumen.
    }
    final geblieben = <Directory>[];
    for (final id in kennungen) {
      for (final b in [...eigene, ...fremde]) {
        try {
          if (fremde.contains(b) &&
              !await File(
                p.join(b.ordner(id).path, Bearbeitungsbruecke.marke),
              ).exists()) {
            continue;
          }
          if (await b.raeumeKlartextWeg(id) case final d?) geblieben.add(d);
        } on Object catch (e) {
          debugPrint('Arbeitskopie von $id unter ${b.ablage.path}: $e');
        }
      }
    }
    return geblieben;
  }

  bool _gleich(String a, String b) => system == 'windows'
      ? p.windows.equals(a, b)
      : p.posix.equals(p.posix.normalize(a), p.posix.normalize(b));

  /// Ein Ordnername, den kein anderes Programm hat. Er wird beim
  /// Hinzufügen festgelegt und gespeichert, nicht jedes Mal aus dem Namen
  /// abgeleitet: Hiesse ein zweites Programm genauso, verschöbe sich sonst
  /// die Nummer, sobald das erste entfernt wird – und eine offene
  /// Arbeitskopie fände sich nicht mehr.
  ///
  /// Vergeben sind die Ordner der bekannten und der eigenen Programme, die
  /// entfernter Programme und jeder Ordner, der unter [basis] schon liegt
  /// – auch einer, den keine Einstellung mehr kennt.
  String _freierOrdner(String name) {
    final sauber = name
        .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '_')
        .replaceAll('..', '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    final stamm = 'PhotoVault-${sauber.isEmpty ? 'Programm' : sauber}';
    final belegt = _belegt();
    bool frei(String k) =>
        !belegt.contains(k.toLowerCase()) &&
        FileSystemEntity.typeSync(p.join(basis.path, k), followLinks: false) ==
            FileSystemEntityType.notFound;
    var kandidat = stamm;
    for (var n = 2; !frei(kandidat); n++) {
      kandidat = '$stamm $n';
    }
    return kandidat;
  }

  Set<String> _belegt() => {
    for (final art in Bekannt.values) art.ordner.toLowerCase(),
    for (final e in _eigene) e.ordner.toLowerCase(),
    for (final e in _frueher) e.ordner.toLowerCase(),
  };

  /// Der Weg zu [programm]: ein Ordner je Programm unter [basis].
  Bearbeitungsbruecke bruecke(Fremdprogramm programm) {
    final ablage = Directory(p.join(basis.path, programm.ordner));
    if (!p.isWithin(basis.path, ablage.path)) {
      throw StateError('pv_arbeitsordner_ausserhalb: ${programm.ordner}');
    }
    // Der Start fragt die Liste beim Klick, nicht beim Anlegen der Brücke:
    // Zwischen beidem kann die Erkennung den Pfad gefunden haben.
    Future<bool> starte(String datei) => _starter.starte(
      alle.firstWhere(
        (x) => x.kennung == programm.kennung,
        orElse: () => programm,
      ),
      datei,
    );
    return _bruecken[programm.kennung] ??= programm.art == Bekannt.darktable
        ? DarktableBruecke(ablage, starte: starte, ruhe: ruhe)
        : Bearbeitungsbruecke(ablage, starte: starte, ruhe: ruhe);
  }

  /// Fragt nach einem Programm; `null`, wenn abgebrochen.
  Future<String?> waehle(String? titel) => _waehle(titel);

  /// Öffnet den Ordner einer Arbeitskopie im Dateimanager.
  Future<bool> zeigeOrdner(String ordner) => _zeigeOrdner(ordner);
}

/// Der Name, unter dem ein gewähltes Programm im Menü steht: der
/// Dateiname ohne `.app` bzw. `.exe`.
String programmnameAus(String pfad) {
  final name = pfad.contains(r'\')
      ? p.windows.basename(pfad)
      : p.posix.basename(p.posix.normalize(pfad));
  final endung = p.extension(name).toLowerCase();
  return endung == '.app' || endung == '.exe'
      ? name.substring(0, name.length - endung.length)
      : name;
}

/// Die Auswahl eines Programms: unter macOS ein `.app`-Bündel aus
/// /Programme, unter Windows eine `.exe`, unter Linux jede Datei (ein
/// Programm hat dort keine Endung).
Future<String?> _waehleMitDialog(String? titel) async {
  final wahl = Platform.isMacOS
      ? await FilePicker.pickFile(
          dialogTitle: titel,
          initialDirectory: '/Applications',
          type: FileType.custom,
          allowedExtensions: const ['app'],
        )
      : Platform.isWindows
      ? await FilePicker.pickFile(
          dialogTitle: titel,
          type: FileType.custom,
          allowedExtensions: const ['exe'],
        )
      : await FilePicker.pickFile(dialogTitle: titel);
  return wahl?.path;
}
