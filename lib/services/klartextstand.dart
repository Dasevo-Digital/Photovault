import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

/// Was im Klartext-Zwischenspeicher des gesperrten Ordners liegt, in der
/// Reihenfolge der letzten Herausgabe, mit der Summe der Grössen (#434).
///
/// Bis hierher wurde nach jeder neuen Entschlüsselung der ganze Ordner
/// aufgelistet und jede Datei abgefragt. Wer einen gesperrten Ordner mit
/// 1000 Fotos öffnete, löste so rund eine halbe Million Dateiabfragen aus,
/// und das Raster wurde zäh. Jetzt wird der Ordner einmal eingelesen; danach
/// führt der Stand selbst Buch.
///
/// Die Reihenfolge stammt von den Herausgaben, nicht von der Zugriffszeit
/// der Dateien – die führt nicht jedes Dateisystem nach.
class Klartextstand {
  Klartextstand._(this.ordner);

  final Directory ordner;

  /// Name → Grösse, das am längsten nicht Herausgegebene zuerst.
  final _stuecke = <String, int>{};
  var _summe = 0;

  /// So viele zuletzt herausgegebene Stücke weichen nie, auch über der
  /// Grenze. Bis hierher blieb nur das eben entschlüsselte: Ein gesperrtes
  /// Video über der Grenze war bei der nächsten Miniatur wieder weg und
  /// musste beim nächsten Öffnen erneut lange entschlüsselt werden.
  static const geschont = 8;

  /// Wie viele Bytes der Stand zählt.
  int get summe => _summe;

  /// Liest, was in [ordner] schon liegt – das am längsten nicht
  /// Angesehene zuerst. Halbe Dateien eines laufenden Entschlüsselns
  /// (`<name>.<zeit>`) zählen nicht; sie gehören dem, der sie schreibt.
  static Future<Klartextstand> lies(Directory ordner) async {
    final stand = Klartextstand._(ordner);
    final gefunden = <(String, DateTime, int)>[];
    try {
      await for (final e in ordner.list(followLinks: false)) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        if (_teil.hasMatch(name)) continue;
        try {
          final st = await e.stat();
          gefunden.add((name, st.accessed, st.size));
        } on FileSystemException {
          // Gerade weggeräumt.
        }
      }
    } on FileSystemException {
      // Den Ordner gibt es (noch) nicht.
    }
    gefunden.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (name, _, groesse) in gefunden) {
      stand.vermerke(name, groesse);
    }
    return stand;
  }

  static final _teil = RegExp(r'^[0-9a-f]{64}\.\d+$');

  /// [name] ist eben mit [groesse] Bytes entstanden und herausgegeben.
  void vermerke(String name, int groesse) {
    _summe -= _stuecke.remove(name) ?? 0;
    _stuecke[name] = groesse;
    _summe += groesse;
  }

  /// [name] wurde aus dem Zwischenspeicher wieder herausgegeben.
  void beruehre(String name) {
    final groesse = _stuecke.remove(name);
    if (groesse != null) _stuecke[name] = groesse;
  }

  /// Wirft die am längsten nicht herausgegebenen Stücke weg, bis die
  /// Summe wieder unter [grenze] liegt – ausser den [geschont] jüngsten.
  /// Ein weggeworfenes Stück ist kein Verlust: Der nächste Zugriff
  /// entschlüsselt es erneut.
  Future<void> kuerze(int grenze) async {
    if (_summe <= grenze) return;
    final namen = _stuecke.keys.toList();
    for (final name in namen.take(math.max(0, namen.length - geschont))) {
      if (_summe <= grenze) break;
      try {
        await File(p.join(ordner.path, name)).delete();
      } on PathNotFoundException {
        // Schon weg – zählt nicht mehr.
      } on FileSystemException {
        // Gerade in Benutzung (Windows) – dann eben das nächste.
        continue;
      }
      // Ein gleichzeitiges Kürzen kann es schon ausgetragen haben.
      _summe -= _stuecke.remove(name) ?? 0;
    }
  }
}
