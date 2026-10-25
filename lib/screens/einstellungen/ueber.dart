import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:kern/unterstuetzen.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../services/aktualisierungspruefung.dart';
import '../../services/modelltexte.dart';
import '../../services/platform/webseite_oeffnen.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import 'einstellungsstand.dart';
import 'gemeinsam.dart';

/// Über die App: Fassung, Datenbank, Modelle, Aktualisierung, Lizenzen.
class UeberGruppe extends StatelessWidget {
  const UeberGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Card(
        child: FutureBuilder<PackageInfo>(
          future: stand.versionFuture,
          builder: (context, snapshot) {
            final info = snapshot.data;
            final version = info?.version ?? '…';
            // Dieselbe Auswahl wie in der Modellgruppe: Sonst stuende
            // hier auf Englisch fuer immer „9 von 11".
            final katalog = modelleFuerSprache(context, stand.library);
            final modelle = katalog
                .where((e) => stand.library.isModelInstalled(e))
                .toList();
            return Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text('Photo Vault $version'),
                  subtitle: Text(
                    info == null
                        ? ''
                        : AppTexte.of(context).einstBauZeile(
                            info.buildNumber,
                            Platform.operatingSystem,
                            Platform.operatingSystemVersion,
                          ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: Text(AppTexte.of(context).einstDatenbank),
                  subtitle: Text(
                    AppTexte.of(
                      context,
                    ).einstDatenbankStand(stand.library.db.schemaVersion),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.memory_outlined),
                  title: Text(
                    modelle.isEmpty
                        ? AppTexte.of(context).einstKeineModelle
                        : AppTexte.of(
                            context,
                          ).einstModelleGeladen(modelle.length, katalog.length),
                  ),
                  subtitle: Text(
                    modelle.isEmpty
                        ? AppTexte.of(context).einstModelleUnbenutzt
                        : modelle
                              .map(
                                (e) => modellTitel(AppTexte.of(context), e.id),
                              )
                              .join(' · '),
                  ),
                  isThreeLine: modelle.isNotEmpty,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    0,
                  ),
                  child: Text(
                    AppTexte.of(context).einstAktualisierungHinweis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (stand.aktualisierungsstand != null)
                  ListTile(
                    leading: Icon(
                      stand.aktualisierungsstand!.istNeuereVerfuegbar
                          ? Icons.new_releases_outlined
                          : Icons.check_circle_outline,
                      color: stand.aktualisierungsstand!.istNeuereVerfuegbar
                          ? Theme.of(context).colorScheme.primary
                          : context.semantik.erfolg,
                    ),
                    title: Text(
                      stand.aktualisierungsstand!.istNeuereVerfuegbar
                          ? AppTexte.of(context).einstAktualisierungNeuer(
                              stand.aktualisierungsstand!.neueste,
                            )
                          : AppTexte.of(context).einstAktualisierungAktuell,
                    ),
                    subtitle: stand.aktualisierungsstand!.istNeuereVerfuegbar
                        ? Text(stand.aktualisierungsstand!.seitenUrl ?? '')
                        : null,
                  ),
                if (stand.aktualisierungsfehler != null)
                  ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: Text(stand.aktualisierungsfehler!),
                  ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              (stand.pruefeAktualisierung || info == null)
                              ? null
                              : () => _sucheAktualisierung(stand, version),
                          icon: stand.pruefeAktualisierung
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.system_update_alt_outlined),
                          label: Text(
                            AppTexte.of(context).einstNachAktualisierungSuchen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // **Der Weg zu den Lizenzen.** Die App liefert seit dem
                // Zierbaum zwei Schriften mit, und die SIL Open Font
                // License verlangt, dass ihr Text mitgeht. Er ging
                // mit – nur konnte ihn niemand lesen: Es gab keine
                // Übersicht, in der die angemeldeten Lizenzen
                // aufgetaucht wären. Eine Datei im Paket, die
                // unerreichbar ist, erfüllt die Auflage dem Buchstaben
                // nach und dem Sinn nach nicht.
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: Text(AppTexte.of(context).einstLizenzen),
                  subtitle: Text(AppTexte.of(context).einstLizenzenText),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Photo Vault',
                    applicationVersion: version,
                  ),
                ),
                if (!fuerAppStore)
                  ListTile(
                    leading: const Icon(Icons.coffee_outlined),
                    title: Text(AppTexte.of(context).einstUnterstuetzen),
                    subtitle: Text(AppTexte.of(context).einstUnterstuetzenText),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => oeffneWebseite(unterstuetzenAdresse),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

/// Fragt beim öffentlichen Veröffentlichungsverzeichnis nach einer
/// neueren Fassung – nur auf diesen Knopfdruck hin, nie von selbst
/// (siehe Aktualisierungspruefung).
Future<void> _sucheAktualisierung(
  Einstellungsstand stand,
  String installiert,
) async {
  final context = stand.kontext;
  stand.aendere(() {
    stand.pruefeAktualisierung = true;
    stand.aktualisierungsfehler = null;
    stand.aktualisierungsstand = null;
  });
  try {
    final ergebnis = await Aktualisierungspruefung().pruefe(installiert);
    if (context.mounted) {
      stand.aendere(() => stand.aktualisierungsstand = ergebnis);
    }
  } catch (e) {
    if (context.mounted) {
      // Den tatsächlichen Grund nennen statt auf die Internetverbindung
      // zu raten: Beim ersten Fehlerbericht bestand die Verbindung
      // durchaus, die Abfrage war schlicht falsch gestellt.
      stand.aendere(
        () => stand.aktualisierungsfehler = AppTexte.of(context)
            .einstAktualisierungFehler(
              e is DioException
                  ? (e.message ?? e.type.name)
                  : fehlertext(context, e),
            ),
      );
    }
  } finally {
    if (context.mounted) {
      stand.aendere(() => stand.pruefeAktualisierung = false);
    }
  }
}
