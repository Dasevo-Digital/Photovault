import 'package:flutter/material.dart' show RangeValues;

/// Was die Vorschau beim Zuschneiden tut, ohne Abspieler und ohne Oberfläche.
///
/// Bis hierher stand im Schnitt das erste Bild des Videos, egal wo die Griffe
/// lagen: Man schnitt nach der Zeitanzeige und sah das Ergebnis erst nach dem
/// Speichern.
///
/// - Beim Ziehen zeigt das Bild die Stelle des bewegten Griffs.
/// - Abspielen spielt genau den gewählten Bereich und hält an dessen Ende.
class Schnittsteuerung {
  Schnittsteuerung({
    required this._bereich,
    required this.springe,
    required this.spiele,
    required this.halte,
  });

  final Future<void> Function(Duration stelle) springe;
  final Future<void> Function() spiele;
  final Future<void> Function() halte;

  RangeValues _bereich;
  RangeValues get bereich => _bereich;

  var _spielt = false;
  bool get spielt => _spielt;

  /// Ein Sprung läuft gerade. Solange zählt nur die letzte Stelle: Beim
  /// Ziehen kommen viel mehr Werte, als der Abspieler Bilder liefern kann,
  /// und jeder einzelne liefe sonst der Maus hinterher.
  var _springt = false;
  Duration? _wartet;

  static Duration _zeit(double sekunden) =>
      Duration(milliseconds: (sekunden * 1000).round());

  /// Ein Griff wurde bewegt. Hält eine laufende Vorschau an: Wer am Griff
  /// zieht, will diese Stelle sehen, nicht die Wiedergabe.
  Future<void> griffBewegt(RangeValues neu) async {
    final alt = _bereich;
    _bereich = neu;
    if (_spielt) {
      _spielt = false;
      await halte();
    }
    await _springe(_zeit(neu.start != alt.start ? neu.start : neu.end));
  }

  Future<void> _springe(Duration stelle) async {
    if (_springt) {
      _wartet = stelle;
      return;
    }
    _springt = true;
    try {
      Duration? naechste = stelle;
      while (naechste != null) {
        await springe(naechste);
        naechste = _wartet;
        _wartet = null;
      }
    } finally {
      _springt = false;
    }
  }

  /// Abspielen oder anhalten. Steht die Stelle ausserhalb des Bereichs oder
  /// an dessen Ende, beginnt die Vorschau am Anfang des Bereichs.
  Future<void> umschalten(Duration stelle) async {
    if (_spielt) {
      _spielt = false;
      await halte();
      return;
    }
    final s = stelle.inMilliseconds / 1000;
    if (s < _bereich.start || s >= _bereich.end - _amEnde) {
      await _springe(_zeit(_bereich.start));
    }
    _spielt = true;
    await spiele();
  }

  /// So nah am Ende zählt als „fertig“: Der Abspieler meldet seine Stelle nur
  /// alle paar Hundertstel, und ein Rest von einem Bild wäre keine Vorschau.
  static const _amEnde = 0.05;

  /// Die Abspielstelle hat sich geändert: Am Ende des Bereichs ist Schluss,
  /// wie im fertigen Schnitt, und die nächste Vorschau beginnt vorn.
  Future<void> stelleGemeldet(Duration stelle) async {
    if (!_spielt || stelle.inMilliseconds / 1000 < _bereich.end) return;
    _spielt = false;
    await halte();
    await _springe(_zeit(_bereich.start));
  }

  /// Der Abspieler hat von selbst aufgehört, etwa am Ende der Datei.
  void angehalten() => _spielt = false;
}
