/// Zeitangaben aus Anfragen in Millisekunden seit 1970 (#436).
///
/// `DateTime.fromMillisecondsSinceEpoch` wirft ausserhalb von ±8,64e15,
/// und manches Dateisystem lehnt eine Änderungszeit lange vorher ab. Eine
/// Zahl, die ein Gerät, ein Browser oder ein Gast schickt, wurde bisher
/// ungeprüft übernommen und warf erst später – nach dem Hochladen, mitten
/// im Import, und jedes Mal wieder.
library;

/// Die früheste Zeit, die als Datei- oder Aufnahmezeit gilt:
/// 1. Januar 1800 UTC. Ältere Fotos gibt es nicht.
const fruehesteZeit = -5364662400000;

/// Die späteste: 1. Januar 2200 UTC – weit genug für falsch gestellte
/// Uhren, früh genug für jedes Dateisystem.
const spaetesteZeit = 7258118400000;

/// [ms], wenn es eine Datei- oder Aufnahmezeit sein kann; sonst `null`.
int? zeitInMs(Object? ms) =>
    ms is int && ms >= fruehesteZeit && ms <= spaetesteZeit ? ms : null;

/// Dasselbe aus dem Text einer Anfrage (`?geaendert=…`).
int? zeitAusText(String? text) => zeitInMs(int.tryParse(text ?? ''));

/// Der Zeitpunkt zu [ms], wenn es einer sein kann; sonst `null`.
DateTime? zeitpunktAus(Object? ms) {
  final m = zeitInMs(ms);
  return m == null ? null : DateTime.fromMillisecondsSinceEpoch(m);
}
