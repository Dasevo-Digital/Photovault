import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'package:kern/services/geo_data_catalog.dart';
import '../../services/meldungsdienst.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import 'einstellungsstand.dart';
import 'gemeinsam.dart';

/// Das Ortsverzeichnis für die Geokodierung.
class StandortdatenGruppe extends StatelessWidget {
  const StandortdatenGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          AppTexte.of(context).einstOrteText,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: Icon(
            stand.library.geoDataAvailable
                ? Icons.check_circle
                : Icons.cloud_download_outlined,
            color: stand.library.geoDataAvailable
                ? context.semantik.erfolg
                : null,
          ),
          title: Text(AppTexte.of(context).einstGeoTitel),
          subtitle: Text(
            AppTexte.of(context).einstGeoText(GeoDataCatalog.license),
          ),
          trailing: stand.downloadingGeoData
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : stand.library.geoDataAvailable
              ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: AppTexte.of(context).einstGeoLoeschen,
                  onPressed: () => _deleteGeoData(stand),
                )
              : FilledButton(
                  onPressed: () => _downloadGeoData(stand),
                  child: Text(AppTexte.of(context).allgHerunterladen),
                ),
        ),
      ),
    ],
  );
}

Future<void> _downloadGeoData(Einstellungsstand stand) async {
  final context = stand.kontext;
  stand.aendere(() {
    stand.downloadingGeoData = true;
    stand.geoDataProgress = 0;
  });
  // Siehe [Fortschrittsblatt]: Ein Klick in die Seitenleiste schliesst das
  // Blatt, das Laden läuft weiter und wird danach auch eingelesen.
  final blatt = Fortschrittsblatt<double>.zeige(
    context,
    0,
    (context, fortschritt) => Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppTexte.of(context).einstGeoLaedt,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: fortschritt > 0 ? fortschritt : null),
          const SizedBox(height: 8),
          Text('${(fortschritt * 100).toStringAsFixed(0)} %'),
        ],
      ),
    ),
  );

  try {
    await for (final p in stand.library.geoDataDownloadService.download()) {
      stand.geoDataProgress = p.fraction;
      blatt.setze(p.fraction);
    }
    await stand.library.reloadGeoData();
  } catch (e) {
    if (context.mounted) {
      melde.fehler(fehlertext(context, e));
    }
  } finally {
    blatt.schliesse();
    if (stand.aktiv) stand.aendere(() => stand.downloadingGeoData = false);
  }
}

Future<void> _deleteGeoData(Einstellungsstand stand) async {
  await stand.library.geoDataDownloadService.deleteAll();
  await stand.library.reloadGeoData();
  if (!stand.aktiv) return;
  stand.aendere(() {});
}
