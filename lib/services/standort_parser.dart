import 'dart:convert';

/// Was der Ortungshelfer unter Windows zurückgibt.
///
/// [quelle] steht bewusst mit drin und wird nicht sofort weggeworfen: Ob
/// eine Position aus WLAN-Umgebung oder aus der IP-Adresse stammt, ist
/// der Unterschied zwischen 15 Metern und 271 Kilometern – gemessen am
/// 25.08.2026 auf dem Testrechner. Ein Wert ohne seine Herkunft lässt
/// sich nicht beurteilen.
typedef Ortung = ({
  double breite,
  double laenge,
  double genauigkeit,
  String quelle,
});

/// Quellen, die auf einer echten Messung beruhen.
///
/// `IPAddress` fehlt hier mit Absicht. Der IP-Rückfall lieferte in der
/// Messung den Standort des Netzbetreibers – 271 km entfernt, bei
/// behaupteten 25 km Genauigkeit. Ein Ergebnis, das seinen eigenen Fehler
/// um das Zehnfache unterschätzt, setzt einen Kartenpin, dem der Nutzer
/// glaubt. Lieber gar keine Antwort.
///
/// `Default` und `Obfuscated` fehlen aus demselben Grund: Beide heissen,
/// dass Windows nicht wirklich gemessen hat.
const vertrauenswuerdigeQuellen = {'WiFi', 'Satellite', 'Cellular'};

/// Obergrenze für eine brauchbare Angabe, in Metern.
///
/// Grosszügig gewählt: Eine Funkzellen-Ortung mit ein paar Kilometern ist
/// für „wo ungefähr bin ich" noch nützlich. Es geht hier nur darum, das
/// offensichtlich Wertlose abzufangen, falls eine Quelle einmal etwas
/// durchreicht, das nicht in [vertrauenswuerdigeQuellen] auffällt.
const hoechsteGenauigkeitMeter = 5000.0;

/// Liest die eine JSON-Zeile des Helfers.
///
/// Gibt `null` zurück, wenn nichts Brauchbares dasteht – kaputte Ausgabe,
/// ein gemeldeter Fehler, eine Quelle ohne echte Messung oder eine
/// Genauigkeit jenseits von [hoechsteGenauigkeitMeter]. Wirft nie.
Ortung? parseStandort(String ausgabe) {
  final zeile = ausgabe.trim();
  if (zeile.isEmpty) return null;
  final Object? roh;
  try {
    roh = jsonDecode(zeile);
  } on FormatException {
    return null;
  }
  if (roh is! Map) return null;

  // {"fehler":"..."} ist eine gültige Antwort des Helfers, nur eben keine
  // Position. Kein Sonderfall, kein Protokolleintrag – der Aufrufer sagt
  // dem Nutzer ohnehin nur, dass nichts zu holen war.
  if (roh['fehler'] != null) return null;

  final breite = (roh['breite'] as num?)?.toDouble();
  final laenge = (roh['laenge'] as num?)?.toDouble();
  if (breite == null || laenge == null) return null;
  if (breite.abs() > 90 || laenge.abs() > 180) return null;

  final quelle = roh['quelle'] as String? ?? 'Unknown';
  if (!vertrauenswuerdigeQuellen.contains(quelle)) return null;

  final genauigkeit = (roh['genauigkeit'] as num?)?.toDouble();
  if (genauigkeit == null || genauigkeit <= 0) return null;
  if (genauigkeit > hoechsteGenauigkeitMeter) return null;

  return (
    breite: breite,
    laenge: laenge,
    genauigkeit: genauigkeit,
    quelle: quelle,
  );
}
