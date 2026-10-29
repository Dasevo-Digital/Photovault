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
  'dateRange' =>
    datum != null &&
        regel.dateFrom != null &&
        regel.dateTo != null &&
        !datum.isBefore(regel.dateFrom!) &&
        !datum.isAfter(regel.dateTo!),
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
