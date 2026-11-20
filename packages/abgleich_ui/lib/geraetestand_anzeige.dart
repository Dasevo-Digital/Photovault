import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'l10n/sync_texte.dart';

/// Ausschließlich vom jeweiligen Gerät gemeldete Angaben. Fehlende und
/// veraltete Meldungen werden nicht als bestätigte Kompatibilität ausgegeben.
class GeraetestandAnzeige extends StatelessWidget {
  const GeraetestandAnzeige({
    super.key,
    required this.daten,
    required this.zielSchema,
  });
  final Map<String, Object?> daten;
  final int zielSchema;

  @override
  Widget build(BuildContext context) {
    final t = SyncTexte.of(context);
    final zeit = DateFormat.yMd(
      Localizations.localeOf(context).toString(),
    ).add_Hm();
    final gemeldet = DateTime.tryParse('${daten['clientGemeldet']}');
    final sync = DateTime.tryParse('${daten['clientAbgleich']}');
    final schema = daten['clientSchema'];
    final version = daten['clientFassung'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          version is String
              ? t.geraetVersion(version)
              : t.geraetVersionUnbekannt,
        ),
        if (daten['clientPlattform'] case final String plattform)
          Text(plattform),
        Text(
          schema is int
              ? t.geraetSchema(schema, zielSchema)
              : t.geraetSchemaUnbekannt,
        ),
        if (schema is int && schema != zielSchema)
          Text(
            t.geraetAktualisieren,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Text(
          daten['clientOffen'] is int
              ? t.geraetOffen(daten['clientOffen']! as int)
              : t.geraetOffenUnbekannt,
        ),
        Text(
          sync == null
              ? t.geraetKeinAbgleich
              : t.geraetAbgleich(zeit.format(sync.toLocal())),
        ),
        if (gemeldet != null)
          Text(t.geraetGemeldet(zeit.format(gemeldet.toLocal()))),
        if (gemeldet == null ||
            DateTime.now().difference(gemeldet) > const Duration(days: 7))
          Text(t.geraetStandUnbekannt),
      ],
    );
  }
}

class GeraeteAktualisierungsplan extends StatelessWidget {
  const GeraeteAktualisierungsplan({
    super.key,
    required this.geraete,
    required this.zielSchema,
  });
  final List<Map<String, Object?>> geraete;
  final int zielSchema;

  @override
  Widget build(BuildContext context) {
    final t = SyncTexte.of(context);
    final betroffen = geraete
        .where((g) => g['clientSchema'] != zielSchema)
        .toList();
    final ausstehend = geraete.any(
      (g) => g['clientOffen'] is int && (g['clientOffen']! as int) > 0,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.geraetePlanTitel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(t.geraetePlanText),
            if (ausstehend) Text(t.geraeteErstAbgleichen),
            if (betroffen.isNotEmpty)
              Text(
                t.geraetePlanBetroffen(
                  betroffen
                      .map((g) => '${g['name'] ?? t.geraetVersionUnbekannt}')
                      .join(', '),
                ),
              ),
            Text(t.geraeteHistorisch),
          ],
        ),
      ),
    );
  }
}
