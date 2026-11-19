import 'dart:convert';

/// Ausschlüsse für automatische Rückblicke, gemeinsam für die Bibliothek.
class Erinnerungsfilter {
  Erinnerungsfilter({
    Iterable<String> personen = const [],
    Iterable<String> alben = const [],
    Iterable<({String von, String bis})> zeitraeume = const [],
  }) : personen = _kennungen(personen),
       alben = _kennungen(alben),
       zeitraeume = List.unmodifiable(zeitraeume) {
    if (this.zeitraeume.length > 50) {
      throw const FormatException('pv_erinnerungsfilter_umfang');
    }
    for (final z in this.zeitraeume) {
      if (tag(z.von).isAfter(tag(z.bis))) {
        throw const FormatException('pv_erinnerungsfilter_datum');
      }
    }
  }

  final List<String> personen, alben;
  final List<({String von, String bis})> zeitraeume;

  static List<String> _kennungen(Iterable<String> werte) {
    final liste = werte.toSet().toList()..sort();
    if (liste.length > 500 || liste.any((s) => s.isEmpty || s.length > 100)) {
      throw const FormatException('pv_erinnerungsfilter_kennungen');
    }
    return List.unmodifiable(liste);
  }

  static DateTime tag(String s) {
    final datum = DateTime.tryParse(s);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) ||
        datum == null ||
        datum.year < 1 ||
        datum.year.toString().padLeft(4, '0') != s.substring(0, 4) ||
        datum.month.toString().padLeft(2, '0') != s.substring(5, 7) ||
        datum.day.toString().padLeft(2, '0') != s.substring(8, 10)) {
      throw const FormatException('pv_erinnerungsfilter_datum');
    }
    return DateTime(datum.year, datum.month, datum.day);
  }

  bool get leer => personen.isEmpty && alben.isEmpty && zeitraeume.isEmpty;

  bool schliesstTagAus(DateTime datum) {
    final d = DateTime(datum.year, datum.month, datum.day);
    return zeitraeume.any(
      (z) => !d.isBefore(tag(z.von)) && !d.isAfter(tag(z.bis)),
    );
  }

  Map<String, Object?> alsJson() => {
    'fassung': 1,
    'personen': personen,
    'alben': alben,
    'zeitraeume': [
      for (final z in zeitraeume) {'von': z.von, 'bis': z.bis},
    ],
  };

  String kodiert() => jsonEncode(alsJson());

  factory Erinnerungsfilter.ausJson(Object? wert) {
    if (wert is! Map || wert['fassung'] != 1) {
      throw const FormatException('pv_erinnerungsfilter_format');
    }
    return Erinnerungsfilter(
      personen: (wert['personen'] as List).cast<String>(),
      alben: (wert['alben'] as List).cast<String>(),
      zeitraeume: [
        for (final z in wert['zeitraeume'] as List)
          (von: (z as Map)['von'] as String, bis: z['bis'] as String),
      ],
    );
  }
}
