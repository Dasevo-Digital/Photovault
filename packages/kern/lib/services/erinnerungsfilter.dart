import 'dart:convert';

/// Ausschlüsse für automatische Rückblicke, gemeinsam für die Bibliothek.
/// Kalendergrenzen werden beim Anlegen in UTC-Zeitpunkte übersetzt. Andere
/// Rechner werten dieselben gespeicherten Grenzen aus.
class Erinnerungsfilter {
  factory Erinnerungsfilter({
    Iterable<String> personen = const [],
    Iterable<String> alben = const [],
    Iterable<({String von, String bis})> zeitraeume = const [],
  }) => Erinnerungsfilter.ausJson({
    'fassung': 2,
    'personen': personen.toList(),
    'alben': alben.toList(),
    'zeitraeume': [for (final z in zeitraeume) _neuerZeitraum(z)],
  });

  Erinnerungsfilter._(
    this.personen,
    this.alben,
    this.zeitraeume,
    this._grenzen,
  );
  final List<String> personen, alben;
  final List<({String von, String bis})> zeitraeume;
  final List<({DateTime von, DateTime bis})?> _grenzen;

  bool get zeitbezugFehlt => _grenzen.any((g) => g == null);
  bool get leer => personen.isEmpty && alben.isEmpty && zeitraeume.isEmpty;
  List<({DateTime von, DateTime bis})> get zeitgrenzen {
    if (zeitbezugFehlt) {
      throw const FormatException('pv_erinnerungsfilter_zeitbezug');
    }
    return _grenzen.cast<({DateTime von, DateTime bis})>();
  }

  static List<String> _kennungen(Iterable<String> werte) {
    final liste = werte.toSet().toList()..sort();
    if (liste.length > 500 || liste.any((s) => s.isEmpty || s.length > 100)) {
      throw const FormatException('pv_erinnerungsfilter_kennungen');
    }
    return List.unmodifiable(liste);
  }

  static DateTime tag(String s) {
    final datum = DateTime.tryParse('${s}T00:00:00Z');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) ||
        datum == null ||
        datum.year < 1 ||
        datum.year.toString().padLeft(4, '0') != s.substring(0, 4) ||
        datum.month.toString().padLeft(2, '0') != s.substring(5, 7) ||
        datum.day.toString().padLeft(2, '0') != s.substring(8, 10)) {
      throw const FormatException('pv_erinnerungsfilter_datum');
    }
    return datum;
  }

  static Map<String, Object?> _neuerZeitraum(({String von, String bis}) z) {
    final von = tag(z.von), bis = tag(z.bis);
    if (von.isAfter(bis)) {
      throw const FormatException('pv_erinnerungsfilter_datum');
    }
    return {
      'von': z.von,
      'bis': z.bis,
      'vonUtc': DateTime(
        von.year,
        von.month,
        von.day,
      ).toUtc().toIso8601String(),
      'bisUtc': DateTime(
        bis.year,
        bis.month,
        bis.day + 1,
      ).toUtc().toIso8601String(),
    };
  }

  bool schliesstTagAus(DateTime datum) =>
      zeitgrenzen.any((z) => !datum.isBefore(z.von) && datum.isBefore(z.bis));

  Map<String, Object?> _zeitraum(int i) => {
    'von': zeitraeume[i].von,
    'bis': zeitraeume[i].bis,
    if (_grenzen[i] case final g?) ...{
      'vonUtc': g.von.toIso8601String(),
      'bisUtc': g.bis.toIso8601String(),
    },
  };
  Map<String, Object?> alsJson() => {
    'fassung': 2,
    'personen': personen,
    'alben': alben,
    'zeitraeume': [for (var i = 0; i < zeitraeume.length; i++) _zeitraum(i)],
  };
  String kodiert() => jsonEncode(alsJson());

  /// Bewahrt bestehende Zeitpunkte. Nur neue oder ausdrücklich bestätigte
  /// alte Zeiträume erhalten den Zeitbezug des bearbeitenden Geräts.
  Erinnerungsfilter mitAuswahl({
    required Iterable<String> personen,
    required Iterable<String> alben,
    required Iterable<({String von, String bis})> zeitraeume,
  }) {
    final benutzt = <int>{};
    Map<String, Object?> zeitraum(({String von, String bis}) z) {
      for (var i = 0; i < this.zeitraeume.length; i++) {
        if (this.zeitraeume[i] == z && _grenzen[i] != null && benutzt.add(i)) {
          return _zeitraum(i);
        }
      }
      return _neuerZeitraum(z);
    }

    return Erinnerungsfilter.ausJson({
      'fassung': 2,
      'personen': personen.toList(),
      'alben': alben.toList(),
      'zeitraeume': [for (final z in zeitraeume) zeitraum(z)],
    });
  }

  Erinnerungsfilter vereinigtMit(
    Erinnerungsfilter anderer, {
    Map<String, String> albenZuordnung = const {},
  }) => Erinnerungsfilter.ausJson({
    'fassung': 2,
    'personen': {...personen, ...anderer.personen}.toList(),
    'alben': {
      ...alben,
      for (final id in anderer.alben) albenZuordnung[id] ?? id,
    }.toList(),
    'zeitraeume': {
      for (final f in [this, anderer])
        for (var i = 0; i < f.zeitraeume.length; i++)
          jsonEncode(f._zeitraum(i)),
    }.map(jsonDecode).toList(),
  });

  factory Erinnerungsfilter.ausJson(Object? wert) {
    if (wert is! Map || !{1, 2}.contains(wert['fassung'])) {
      throw const FormatException('pv_erinnerungsfilter_format');
    }
    try {
      final zeiten = <({String von, String bis})>[];
      final grenzen = <({DateTime von, DateTime bis})?>[];
      final liste = wert['zeitraeume'] as List;
      if (liste.length > 50) {
        throw const FormatException('pv_erinnerungsfilter_umfang');
      }
      for (final z in liste.cast<Map>()) {
        final von = tag(z['von'] as String), bis = tag(z['bis'] as String);
        if (von.isAfter(bis)) {
          throw const FormatException('pv_erinnerungsfilter_datum');
        }
        zeiten.add((von: z['von'] as String, bis: z['bis'] as String));
        if (wert['fassung'] == 1 ||
            (z['vonUtc'] == null && z['bisUtc'] == null)) {
          grenzen.add(null);
        } else {
          DateTime grenze(Object? text, DateTime kalender) {
            final d = text is String && text.endsWith('Z')
                ? DateTime.tryParse(text)
                : null;
            if (d == null ||
                d.difference(kalender).inSeconds.abs() > 86400 ||
                d.millisecond != 0 ||
                d.microsecond != 0) {
              throw const FormatException('pv_erinnerungsfilter_datum');
            }
            return d;
          }

          final start = grenze(z['vonUtc'], von);
          final ende = grenze(
            z['bisUtc'],
            DateTime.utc(bis.year, bis.month, bis.day + 1),
          );
          if (start.isAfter(ende)) {
            throw const FormatException('pv_erinnerungsfilter_datum');
          }
          grenzen.add((von: start, bis: ende));
        }
      }
      return Erinnerungsfilter._(
        _kennungen((wert['personen'] as List).cast<String>()),
        _kennungen((wert['alben'] as List).cast<String>()),
        List.unmodifiable(zeiten),
        List.unmodifiable(grenzen),
      );
    } on TypeError {
      throw const FormatException('pv_erinnerungsfilter_format');
    }
  }
}
