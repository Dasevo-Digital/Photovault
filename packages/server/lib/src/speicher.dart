import 'dart:async';
import 'dart:io';

import 'package:kern/protokoll.dart';

/// Wie es um den Speicher steht: genug, knapp (Warnung) oder voll (keine
/// neuen Uploads mehr).
enum Speicherstufe { ausreichend, knapp, voll }

/// Der Platz auf dem Dateisystem der Daten, in Bytes.
class Speicherstand {
  const Speicherstand({required this.gesamt, required this.frei});

  final int gesamt;
  final int frei;

  double get anteilBelegt => gesamt <= 0 ? 0 : (gesamt - frei) / gesamt;
}

/// Liest die Ausgabe von `df -Pk` – das Format, das POSIX vorschreibt:
/// eine Kopfzeile, dann `Dateisystem 1024-Blöcke Belegt Verfügbar
/// Anteil Eingehängt`. Ein langer Gerätename steht dank `-P` in derselben
/// Zeile.
Speicherstand? speicherAusDf(String ausgabe) {
  final zeilen = ausgabe.trim().split('\n');
  if (zeilen.length < 2) return null;
  final spalten = zeilen.last.trim().split(RegExp(r'\s+'));
  if (spalten.length < 6) return null;
  final bloecke = int.tryParse(spalten[1]);
  final verfuegbar = int.tryParse(spalten[3]);
  if (bloecke == null || verfuegbar == null) return null;
  return Speicherstand(gesamt: bloecke * 1024, frei: verfuegbar * 1024);
}

Future<Speicherstand?> _df(Directory ort) async {
  try {
    final r = await Process.run('df', ['-Pk', ort.path]);
    return r.exitCode == 0 ? speicherAusDf('${r.stdout}') : null;
  } on ProcessException {
    return null;
  }
}

/// Hält den freien Platz unter den Daten im Blick (Issue #123).
///
/// **Knapp** heisst: höchstens noch [warnAnteil] frei geblieben – oder
/// weniger als [warnFrei], damit auch eine grosse Platte rechtzeitig
/// warnt. Dann warnen die Apps. **Voll** heisst: weniger als [mindestFrei].
/// Dann nimmt der Server keine neuen Uploads an, denn eine Platte, die
/// mitten im Schreiben der Datenbank voll läuft, kann sie beschädigen –
/// alles andere läuft weiter.
///
/// Jeder Wechsel der Stufe steht im Protokoll.
class Speicherwaechter {
  Speicherwaechter(
    this.ort, {
    this.warnAnteil = 0.85,
    this.warnFrei = 10 * _gb,
    this.mindestFrei = 2 * _gb,
    this.takt = const Duration(minutes: 5),
    Future<Speicherstand?> Function(Directory ort)? messung,
  }) : _messung = messung ?? _df;

  static const _gb = 1000 * 1000 * 1000;

  final Directory ort;
  final double warnAnteil;
  final int warnFrei;
  final int mindestFrei;
  final Duration takt;
  final Future<Speicherstand?> Function(Directory ort) _messung;

  Speicherstand? _stand;
  Speicherstand? get stand => _stand;
  Speicherstufe? _stufe;

  /// `null`, solange nichts gemessen werden konnte (kein `df`).
  Speicherstufe? get stufe => _stufe;
  bool get voll => _stufe == Speicherstufe.voll;

  Timer? _uhr;

  Speicherstufe stufeFuer(Speicherstand s) => s.frei < mindestFrei
      ? Speicherstufe.voll
      : s.frei < warnFrei || s.anteilBelegt >= warnAnteil
      ? Speicherstufe.knapp
      : Speicherstufe.ausreichend;

  Future<void> pruefe() async {
    final s = await _messung(ort);
    if (s == null) return;
    _stand = s;
    final neu = stufeFuer(s);
    final vorher = _stufe;
    _stufe = neu;
    if (neu == vorher) return;
    final text =
        '${_zahl(s.frei)} GB frei von ${_zahl(s.gesamt)} GB '
        '(${(s.anteilBelegt * 100).round()} % belegt)';
    protokoll(switch (neu) {
      Speicherstufe.ausreichend =>
        vorher == null
            ? 'Speicher: $text'
            : 'Speicher wieder ausreichend: $text',
      Speicherstufe.knapp => 'Speicher knapp: $text',
      Speicherstufe.voll =>
        'Speicher voll: $text – neue Uploads werden abgewiesen',
    });
  }

  static String _zahl(int bytes) => (bytes / _gb).toStringAsFixed(1);

  void starte() {
    unawaited(pruefe());
    _uhr = Timer.periodic(takt, (_) => pruefe());
  }

  void beende() => _uhr?.cancel();

  Map<String, Object?> alsJson() => {
    'stufe': _stufe?.name ?? 'unbekannt',
    if (_stand case final s?) ...{
      'gesamt': s.gesamt,
      'frei': s.frei,
      'belegt': double.parse(s.anteilBelegt.toStringAsFixed(4)),
    },
    'warnungAb': warnAnteil,
    'mindestFrei': mindestFrei,
  };
}
