/// Kalenderbereiche sind halboffen und immer in UTC beschrieben. Sie sind
/// keine behaupteten Aufnahmezeitpunkte und ersetzen keine EXIF-Uhrzeit.
enum Datierungsgenauigkeit { tag, monat, jahr, zeitraum }

enum Datierungsquelle {
  manuell,
  beschriftung,
  ueberlieferung,
  datei,
  dateiname,
  unbekannt,
}

class AufnahmeDatierung {
  AufnahmeDatierung._(
    this.von,
    this.bis,
    this.genauigkeit,
    this.quelle,
    this.hinweis,
  ) {
    if (!von.isUtc ||
        !bis.isUtc ||
        von.year < 1 ||
        bis.year > 9999 ||
        !bis.isAfter(von) ||
        [von, bis].any(
          (d) =>
              d.hour != 0 ||
              d.minute != 0 ||
              d.second != 0 ||
              d.millisecond != 0 ||
              d.microsecond != 0,
        ) ||
        (hinweis != null &&
            (hinweis!.length > 160 ||
                RegExp(r'[\x00-\x1f\x7f]').hasMatch(hinweis!)))) {
      throw const FormatException('pv_datierung');
    }
    final korrekt = switch (genauigkeit) {
      Datierungsgenauigkeit.tag => bis == von.add(const Duration(days: 1)),
      Datierungsgenauigkeit.monat =>
        von.day == 1 && bis == DateTime.utc(von.year, von.month + 1),
      Datierungsgenauigkeit.jahr =>
        von.day == 1 && von.month == 1 && bis == DateTime.utc(von.year + 1),
      Datierungsgenauigkeit.zeitraum => true,
    };
    if (!korrekt) throw const FormatException('pv_datierung');
  }
  final DateTime von, bis;
  final Datierungsgenauigkeit genauigkeit;
  final Datierungsquelle quelle;
  final String? hinweis;

  factory AufnahmeDatierung.jahr(
    int jahr, {
    Datierungsquelle quelle = Datierungsquelle.unbekannt,
    String? hinweis,
  }) => AufnahmeDatierung._(
    DateTime.utc(jahr),
    DateTime.utc(jahr + 1),
    Datierungsgenauigkeit.jahr,
    quelle,
    hinweis,
  );
  factory AufnahmeDatierung.monat(
    int jahr,
    int monat, {
    Datierungsquelle quelle = Datierungsquelle.unbekannt,
    String? hinweis,
  }) {
    if (monat < 1 || monat > 12) throw const FormatException('pv_datierung');
    return AufnahmeDatierung._(
      DateTime.utc(jahr, monat),
      DateTime.utc(jahr, monat + 1),
      Datierungsgenauigkeit.monat,
      quelle,
      hinweis,
    );
  }
  factory AufnahmeDatierung.tag(
    DateTime datum, {
    Datierungsquelle quelle = Datierungsquelle.unbekannt,
    String? hinweis,
  }) => AufnahmeDatierung._(
    DateTime.utc(datum.year, datum.month, datum.day),
    DateTime.utc(datum.year, datum.month, datum.day + 1),
    Datierungsgenauigkeit.tag,
    quelle,
    hinweis,
  );
  factory AufnahmeDatierung.zeitraum(
    DateTime von,
    DateTime bisEinschliesslich, {
    Datierungsquelle quelle = Datierungsquelle.unbekannt,
    String? hinweis,
  }) => AufnahmeDatierung._(
    DateTime.utc(von.year, von.month, von.day),
    DateTime.utc(
      bisEinschliesslich.year,
      bisEinschliesslich.month,
      bisEinschliesslich.day + 1,
    ),
    Datierungsgenauigkeit.zeitraum,
    quelle,
    hinweis,
  );

  static DateTime _datum(String text) {
    if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(text)) {
      throw const FormatException('pv_datierung');
    }
    final d = DateTime.parse('${text}T00:00:00Z');
    if (_text(d) != text) throw const FormatException('pv_datierung');
    return d;
  }

  static String _text(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  factory AufnahmeDatierung.aus(Map<String, Object?> j) {
    if (j.keys.any(
      (s) => !{'von', 'bis', 'genauigkeit', 'quelle', 'hinweis'}.contains(s),
    )) {
      throw const FormatException('pv_datierung');
    }
    return AufnahmeDatierung._(
      _datum(j['von'] as String),
      _datum(j['bis'] as String),
      Datierungsgenauigkeit.values.byName(j['genauigkeit'] as String),
      Datierungsquelle.values.byName(j['quelle'] as String? ?? 'unbekannt'),
      j['hinweis'] as String?,
    );
  }
  Map<String, Object?> alsJson() => {
    'von': _text(von),
    'bis': _text(bis),
    'genauigkeit': genauigkeit.name,
    'quelle': quelle.name,
    'hinweis': hinweis,
  };
  String beschreibung({
    required String Function(DateTime) tag,
    required String Function(DateTime) monat,
  }) => switch (genauigkeit) {
    Datierungsgenauigkeit.jahr => '${von.year}',
    Datierungsgenauigkeit.monat => monat(von),
    Datierungsgenauigkeit.tag => tag(von),
    Datierungsgenauigkeit.zeitraum =>
      '${tag(von)} – ${tag(bis.subtract(const Duration(days: 1)))}',
  };
  String get jahresangabe {
    final letztes = bis.subtract(const Duration(days: 1)).year;
    return von.year == letztes ? '${von.year}' : '${von.year}–$letztes';
  }

  /// Dateiname aus den bekannten Kalenderteilen, ohne Uhrzeit oder erfundene Tage.
  String get dateinamensdatum => switch (genauigkeit) {
    Datierungsgenauigkeit.jahr => _text(von).substring(0, 4),
    Datierungsgenauigkeit.monat => _text(von).substring(0, 7),
    Datierungsgenauigkeit.tag => _text(von),
    Datierungsgenauigkeit.zeitraum =>
      '${_text(von)}_${_text(bis.subtract(const Duration(days: 1)))}',
  };
  bool ueberlappt(DateTime anfang, DateTime endeExklusiv) =>
      von.isBefore(endeExklusiv) && bis.isAfter(anfang);
}

/// Die Kalenderfelder werden unabhängig von der Rechnerzeitzone gelesen.
DateTime kalenderAnker(DateTime datum) {
  final d = datum.toUtc();
  return DateTime(d.year, d.month, d.day);
}
