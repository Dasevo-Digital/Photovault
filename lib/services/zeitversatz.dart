/// Der Zeitzonenversatz einer Aufnahme – die Angabe, die jede vierte
/// Datei trägt und die bis zur 7. Vergleichsauflage niemand las.
///
/// **Wie gross die Lücke war.** 126 Dateien quer durch die echte
/// Bibliothek gezogen: 34 tragen `OffsetTimeOriginal`, also 27 %. Im
/// ganzen Quelltext gab es für dieses Feld **null** Fundstellen.
///
/// **Was das praktisch heisst.** Die 228 Aufnahmen aus Mazār-e Sharīf
/// stehen unter der Uhrzeit der Kamera, und die App konnte nicht sagen,
/// ob das 16 Uhr in Berlin oder 18:30 vor Ort war. digiKam hat im Juni
/// 2026 dafür sein Datenbankschema erweitert.
///
/// **Warum es trotzdem der kleinste der fünf Punkte ist.** Es geht nicht
/// um Richtigkeit, sondern um eine Auskunft: Der GPX-Abgleich sucht den
/// Versatz längst selbst (`gpx.dart`, jede halbe Stunde von −14 bis +14),
/// und der Aufnahmezeitpunkt bleibt genau der, der er war – die Ortszeit
/// der Kamera. Der Versatz sagt nur dazu, in welcher Zone diese Ortszeit
/// galt.
library;

import 'package:exif/exif.dart';

/// Liest `OffsetTimeOriginal` und gibt den Versatz in Minuten – `null`,
/// wenn die Datei keinen trägt oder er nicht lesbar ist.
///
/// Die Rangfolge entspricht der des Aufnahmedatums (siehe
/// `ImportService._rohesExifDatum`): `OffsetTimeOriginal` gehört zum
/// Auslösezeitpunkt, `OffsetTimeDigitized` zur Digitalisierung, `OffsetTime`
/// zum Änderungszeitpunkt.
int? zeitversatzAusTags(Map<String, IfdTag> tags) => zeitversatzAusText(
      tags['EXIF OffsetTimeOriginal']?.printable ??
          tags['EXIF OffsetTimeDigitized']?.printable ??
          tags['EXIF OffsetTime']?.printable,
    );

/// Wandelt `"+02:00"`, `"-04:30"` oder `"Z"` in Minuten.
///
/// **Was hier alles nicht durchgeht.** Das Feld ist ein Freitextfeld, und
/// Kameras füllen es unterschiedlich sorgfältig. `"   "` (drei Leerzeichen)
/// ist der Standardwert einer Kamera, die keine Zone kennt, und muss
/// `null` ergeben statt 0 – sonst behauptete jede solche Datei, sie sei in
/// Greenwich entstanden.
///
/// **Und `"+00:00"` ist dasselbe in Grün.** Das ist keine Vermutung,
/// sondern nachgezählt: In der echten Bibliothek tragen **131 Aufnahmen**
/// diesen Wert, alle 131 von einer Canon EOS R10, und keine einzige
/// andere Zone kommt von dieser Kamera. Von den 131 sind **34 als in
/// Deutschland aufgenommen verortet**, und die übrigen entstanden im
/// November und Dezember zwischen 04:32 und 18:56. Deutschland ist nie
/// UTC+0. Der Wert ist die Werkseinstellung einer Kamera, an der die Zone
/// nie gestellt wurde – dieselbe Art Angabe wie `0000:00:00` beim Datum,
/// und sie hier zu glauben wäre derselbe Fehler.
///
/// `"Z"` bleibt dagegen 0: Das ist eine ausdrückliche Angabe und kein
/// Vorgabewert.
int? zeitversatzAusText(String? text) {
  if (text == null) return null;
  final roh = text.trim();
  if (roh.isEmpty) return null;
  if (roh == 'Z') return 0;

  final treffer =
      RegExp(r'^([+-])(\d{1,2}):?(\d{2})$').firstMatch(roh.replaceAll(' ', ''));
  if (treffer == null) return null;
  final stunden = int.parse(treffer.group(2)!);
  final minuten = int.parse(treffer.group(3)!);
  // Die aeussersten echten Zonen sind -12:00 und +14:00. Alles darueber
  // ist ein Lesefehler und keine Zeitzone.
  if (stunden > 14 || minuten > 59) return null;
  final gesamt = stunden * 60 + minuten;
  if (gesamt > 14 * 60) return null;
  // Siehe oben: ein geschriebenes „+00:00" ist die Werkseinstellung, kein
  // Befund.
  if (gesamt == 0) return null;
  return treffer.group(1) == '-' ? -gesamt : gesamt;
}

/// Der Versatz, wie er neben der Uhrzeit steht: `UTC+2`, `UTC+4:30`,
/// `UTC−3:30`, `UTC`.
///
/// Mit dem typografischen Minus, nicht mit dem Bindestrich: Neben einer
/// Uhrzeit gelesen ist der Bindestrich zu leicht ein Trennstrich.
String zeitversatzText(int minuten) {
  if (minuten == 0) return 'UTC';
  final vorzeichen = minuten < 0 ? '−' : '+';
  final betrag = minuten.abs();
  final stunden = betrag ~/ 60;
  final rest = betrag % 60;
  return rest == 0
      ? 'UTC$vorzeichen$stunden'
      : 'UTC$vorzeichen$stunden:${rest.toString().padLeft(2, '0')}';
}
