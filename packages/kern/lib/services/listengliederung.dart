/// Wie die Liste der Aufnahmen gegliedert ist und wie ihre Angaben
/// geschrieben werden – am Rechner, im Browser (nachgebaut in `app.js`)
/// und auf dem Handy (Issue #195). Eine Regel, damit „Canon EOS R10“ und
/// „1/250“ überall gleich aussehen.
library;

/// Wonach die Liste gegliedert wird.
enum ListenGruppierung {
  /// Wie das Raster: ein Abschnitt je Monat, neueste zuerst.
  monat,

  /// Ein Abschnitt je Tag – die Liste kennt keine Monatsüberschrift
  /// darüber, der Abschnitt nennt deshalb das volle Datum.
  tag,

  /// Ein Abschnitt je Kameramodell – die Arbeitsweise, wenn man eine
  /// Reihe mit zwei Gehäusen fotografiert hat und beide getrennt
  /// durchsehen will.
  kamera,

  /// Keine Gliederung, eine durchgehende Liste.
  keine,
}

/// Die Kamerabezeichnung aus Hersteller und Modell, oder `null`, wenn
/// keine bekannt ist.
///
/// Hersteller und Modell werden nicht doppelt geschrieben – Canon steht in
/// beiden EXIF-Feldern („Canon" und „Canon EOS R10"). Dieselbe Regel wie
/// beim Namensmuster im Export.
String? kamerabezeichnungAus(String? hersteller, String? modell) {
  final h = hersteller?.trim() ?? '';
  final m = modell?.trim() ?? '';
  if (m.isEmpty && h.isEmpty) return null;
  if (m.isEmpty) return h;
  if (h.isEmpty) return m;
  if (m.toLowerCase().startsWith(h.toLowerCase())) return m;
  return '$h $m';
}

/// Belichtungsangaben in der Schreibweise, die auf jedem Gehäuse steht.
///
/// Die Verschlusszeit als Bruch, sobald sie kürzer als eine Sekunde ist –
/// „0,004 s" liest niemand, „1/250" jeder.
String belichtungstext({
  double? brennweite,
  double? blende,
  double? zeit,
  int? iso,
}) {
  final teile = <String>[];
  if (brennweite != null) teile.add('${brennweite.round()} mm');
  if (blende != null) teile.add('f/${blende.toStringAsFixed(1)}');
  if (zeit != null && zeit > 0) {
    teile.add(
      zeit >= 1 ? '${zeit.toStringAsFixed(1)} s' : '1/${(1 / zeit).round()}',
    );
  }
  if (iso != null) teile.add('ISO $iso');
  return teile.join(' · ');
}

/// Der Ort für die Liste: Stadt und Land, was davon bekannt ist.
String ortstext(String? stadt, String? land) => [
  if (stadt != null && stadt.isNotEmpty) stadt,
  if (land != null && land.isNotEmpty) land,
].join(', ');
