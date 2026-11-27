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
class Bearbeitungsprogramme extends ChangeNotifier {
  Bearbeitungsprogramme({
    required this.basis,
    required this._einstellungen,
    String? system,
    Future<Map<Bekannt, String>> Function()? erkenne,
    Programmstarter? starter,
    Future<String?> Function(String? titel)? waehle,
    Future<bool> Function(String ordner)? zeigeOrdner,
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
  final Future<File> Function() _einstellungen;
  final Future<Map<Bekannt, String>> Function() _erkenne;
  final Programmstarter _starter;
  final Future<String?> Function(String? titel) _waehle;
  final Future<bool> Function(String) _zeigeOrdner;

  Map<Bekannt, String> _gefunden = const {};
  Map<String, bool> _schalter = {};
  List<({String name, String pfad, String ordner})> _eigene = [];
  final _bruecken = <String, Bearbeitungsbruecke>{};
  Future<void>? _laeuft;
  bool _geladen = false;
  bool _eingelesen = false;

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
    if (!_eingelesen) {
      await _einlesen();
      _eingelesen = true;
    }
    try {
      _gefunden = await _erkenne();
    } on Object catch (e) {
      debugPrint('Programme nicht erkannt: $e');
    }
    _geladen = true;
    notifyListeners();
  }

  Future<void> _einlesen() async {
    try {
      final datei = await _einstellungen();
      if (!await datei.exists()) return;
      final j = jsonDecode(await datei.readAsString());
      if (j is! Map || j['fassung'] != 1) return;
      _schalter = {
        for (final MapEntry(:key, :value)
            in ((j['schalter'] as Map?) ?? const {}).entries)
          if (value is bool) '$key': value,
      };
      _eigene = [
        for (final e in (j['eigene'] as List?) ?? const [])
          if (e is Map &&
              e['name'] is String &&
              e['pfad'] is String &&
              e['ordner'] is String)
            (
              name: e['name'] as String,
              pfad: e['pfad'] as String,
              ordner: e['ordner'] as String,
            ),
      ];
    } on Object catch (e) {
      // Eine kaputte Datei kostet die Einstellung, nicht das Menü.
      debugPrint('bearbeiten_in.json nicht lesbar: $e');
    }
  }

  /// Vor jeder Änderung: Ist die Datei noch nicht gelesen, schriebe das
  /// Speichern sonst eine leere Liste über die eigenen Programme.
  Future<void> _eingelesenAbwarten() async {
    if (!_eingelesen) await laden();
  }

  Future<void> _speichern() async {
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
    _eigene = [
      ..._eigene,
      (name: name, pfad: pfad, ordner: _freierOrdner(name)),
    ];
    _schalter.remove(_eigenKennung(pfad));
    notifyListeners();
    await _speichern();
    return alle.firstWhere((y) => y.kennung == _eigenKennung(pfad));
  }

  /// Entfernt ein selbst gewähltes Programm. Seine Arbeitskopien bleiben
  /// liegen; der Ordner gehört dem Nutzer, und darin kann eine halbe
  /// Bearbeitung stecken.
  Future<void> entferne(String kennung) async {
    await _eingelesenAbwarten();
    _eigene = [
      for (final e in _eigene)
        if (_eigenKennung(e.pfad) != kennung) e,
    ];
    _schalter.remove(kennung);
    _bruecken.remove(kennung);
    notifyListeners();
    await _speichern();
  }

  bool _gleich(String a, String b) => system == 'windows'
      ? p.windows.equals(a, b)
      : p.posix.equals(p.posix.normalize(a), p.posix.normalize(b));

  /// Ein Ordnername, den kein anderes Programm hat. Er wird beim
  /// Hinzufügen festgelegt und gespeichert, nicht jedes Mal aus dem Namen
  /// abgeleitet: Hiesse ein zweites Programm genauso, verschöbe sich sonst
  /// die Nummer, sobald das erste entfernt wird – und eine offene
  /// Arbeitskopie fände sich nicht mehr.
  String _freierOrdner(String name) {
    final sauber = name.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '_').trim();
    final stamm = 'PhotoVault-${sauber.isEmpty ? 'Programm' : sauber}';
    final belegt = {
      for (final art in Bekannt.values) art.ordner.toLowerCase(),
      for (final e in _eigene) e.ordner.toLowerCase(),
    };
    var kandidat = stamm;
    for (var n = 2; belegt.contains(kandidat.toLowerCase()); n++) {
      kandidat = '$stamm $n';
    }
    return kandidat;
  }

  /// Der Weg zu [programm]: ein Ordner je Programm unter [basis].
  Bearbeitungsbruecke bruecke(Fremdprogramm programm) {
    final ablage = Directory(p.join(basis.path, programm.ordner));
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
        ? DarktableBruecke(ablage, starte: starte)
        : Bearbeitungsbruecke(ablage, starte: starte);
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
