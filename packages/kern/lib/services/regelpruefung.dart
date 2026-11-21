import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'reverse_geocoder.dart';

/// Eine einzige Auswertung für Import-Vorschau, Nachbereitung und spätere
/// Auswertung. Ein Probelauf darf keine andere Regelsprache verwenden.
bool regelTrifftZu(
  AutomationRuleData regel, {
  double? breite,
  double? laenge,
  DateTime? datum,
  List<String>? kiTags,
  String? dateiname,
}) => switch (regel.triggerType) {
  'location' =>
    breite != null &&
        laenge != null &&
        regel.regionCenterLat != null &&
        regel.regionCenterLon != null &&
        regel.regionRadiusKm != null &&
        ReverseGeocoder.haversineKm(
              breite,
              laenge,
              regel.regionCenterLat!,
              regel.regionCenterLon!,
            ) <=
            regel.regionRadiusKm!,
  // Ganze Kalendertage, beide eingeschlossen. Der Datumswähler liefert
  // Mitternacht; früher hiess die Grenze `!datum.isAfter(dateTo)`, und ein
  // Foto vom letzten Tag nach 0 Uhr fiel heraus – eine Regel für einen
  // einzelnen Tag traf praktisch nie.
  'dateRange' =>
    datum != null &&
        regel.dateFrom != null &&
        regel.dateTo != null &&
        !datum.isBefore(_tagesbeginn(regel.dateFrom!)) &&
        datum.isBefore(_tagesbeginn(regel.dateTo!, spaeter: 1)),
  'aiTag' =>
    kiTags != null &&
        regel.aiTagTerm != null &&
        kiTags.contains(regel.aiTagTerm),
  'dateiname' =>
    dateiname != null &&
        (regel.aiTagTerm?.trim().isNotEmpty ?? false) &&
        dateiname.toLowerCase().contains(regel.aiTagTerm!.trim().toLowerCase()),
  'dateiendung' =>
    dateiname != null &&
        (regel.aiTagTerm?.trim().isNotEmpty ?? false) &&
        regel.aiTagTerm!
            .split(',')
            .map((s) => s.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), ''))
            .contains(
              p.extension(dateiname).toLowerCase().replaceFirst('.', ''),
            ),
  _ => false,
};

/// Mitternacht des Tages von [d], [spaeter] Tage weiter – in derselben
/// Zeitbasis wie [d], damit ein Tag in UTC nicht um die Zeitverschiebung
/// verrutscht. Über das Datum und nicht über `Duration(days: 1)`: Ein Tag
/// mit Zeitumstellung hat 23 oder 25 Stunden.
DateTime _tagesbeginn(DateTime d, {int spaeter = 0}) => d.isUtc
    ? DateTime.utc(d.year, d.month, d.day + spaeter)
    : DateTime(d.year, d.month, d.day + spaeter);
