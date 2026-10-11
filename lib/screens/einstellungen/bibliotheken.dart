import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../services/library_location.dart';
import '../../services/meldungsdienst.dart';
import '../../theme/app_spacing.dart';
import 'einstellungsstand.dart';
import 'gemeinsam.dart';

/// Die bekannten Bibliotheken: wechseln, hinzufügen, aus der Liste nehmen.
class BibliothekenGruppe extends StatelessWidget {
  const BibliothekenGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Card(
        child: FutureBuilder<List<BibliothekMitZustand>>(
          future: stand.bibliothekenFuture,
          builder: (context, snapshot) {
            final eintraege = snapshot.data;
            if (eintraege == null) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return Column(
              children: [
                for (final b in eintraege)
                  ListTile(
                    leading: Icon(
                      b.istAktiv
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: b.istAktiv
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      b.eintrag.name,
                      style: b.erreichbar
                          ? null
                          : TextStyle(color: Theme.of(context).disabledColor),
                    ),
                    subtitle: Text(
                      b.erreichbar
                          ? b.eintrag.path
                          : AppTexte.of(context).einstBibNichtGefunden,
                    ),
                    // `enabled` steuert die Einfärbung, nicht die
                    // Antippbarkeit: Die aktive Bibliothek ist zwar nicht
                    // antippbar (man ist ja schon drin), darf aber nicht
                    // ausgegraut erscheinen – ausgegraut heißt hier
                    // "nicht erreichbar".
                    enabled: b.erreichbar,
                    onTap: b.erreichbar && !b.istAktiv
                        ? () => _wechsleBibliothek(stand, b)
                        : null,
                    // Der Standardordner lässt sich nicht entfernen: Er
                    // wird erzeugt, nicht gespeichert, und es gibt ihn
                    // immer. Ihm einen Knopf zu geben, der nichts tut,
                    // war der Fehler der ersten Fassung.
                    trailing: b.istAktiv
                        ? Text(AppTexte.of(context).einstBibAktiv)
                        : b.entfernbar
                        ? IconButton(
                            icon: const Icon(Icons.playlist_remove),
                            tooltip: AppTexte.of(
                              context,
                            ).einstBibAusListeEntfernen,
                            onPressed: () => _entferneBibliothek(stand, b),
                          )
                        : Text(
                            AppTexte.of(context).einstBibImmerVorhanden,
                            style: const TextStyle(fontSize: 12),
                          ),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _bibliothekHinzufuegen(stand),
                          icon: const Icon(Icons.library_add_outlined),
                          label: Text(AppTexte.of(context).einstBibHinzufuegen),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Text(
                    AppTexte.of(context).einstBibWechselHinweis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

/// Wechselt die geöffnete Bibliothek. Verschiebt NICHTS – siehe
/// [LibraryLocation.wechsleZu]. Danach ist ein Neustart nötig, weil
/// Datenbankverbindung, StoragePaths und sämtliche Zwischenspeicher am
/// alten Ort hängen.
Future<void> _wechsleBibliothek(
  Einstellungsstand stand,
  BibliothekMitZustand ziel,
) async {
  final context = stand.kontext;
  final bestaetigt = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        AppTexte.of(context).einstBibWechselnTitel(ziel.eintrag.name),
      ),
      content: Text(AppTexte.of(context).einstBibWechselnText),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppTexte.of(context).allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(AppTexte.of(context).einstBibWechselnAktion),
        ),
      ],
    ),
  );
  if (bestaetigt != true || !context.mounted) return;

  await verlegeBibliothek(
    stand,
    loadingText: AppTexte.of(context).einstBibWechselnLaeuft,
    restartMessage: AppTexte.of(context).einstBibGewechselt,
    errorPrefix: AppTexte.of(context).einstWechselnFehlgeschlagen,
    action: () async {
      // Reihenfolge mit Bedacht: ERST den Zeiger schreiben, DANN die
      // Datenbank schliessen. Andersherum liefe die App bei einem Fehler
      // im Schreibvorgang mit geschlossener Datenbank weiter und wäre
      // unbrauchbar, obwohl gar nichts passiert ist. Das Schliessen ist
      // hier ohnehin nur Höflichkeit vor dem Beenden (WAL sauber
      // abschliessen) – der Wechsel selbst rührt die Bibliothek nicht an.
      await LibraryLocation.wechsleZu(ziel.eintrag);
      await stand.library.db.close();
    },
  );
}

/// Nimmt einen Ordner in die Liste auf, ohne ihn zu öffnen.
Future<void> _bibliothekHinzufuegen(Einstellungsstand stand) async {
  final context = stand.kontext;
  final picked = await LibraryLocation.pickFolder(
    dialogMessage: AppTexte.of(context).einstBibHinzufuegenAuswahl,
  );
  if (picked == null || !context.mounted) return;

  final vorhanden = File(p.join(picked.path, 'library.sqlite')).existsSync();
  await LibraryLocation.fuegeHinzu(picked);
  if (!context.mounted) return;
  stand.aendere(() {
    stand.bibliothekenFuture = LibraryLocation.bekannte();
  });
  melde.erfolg(
    vorhanden
        ? AppTexte.of(context).einstBibBestehendHinzugefuegt
        : AppTexte.of(context).einstBibLeerHinzugefuegt,
  );
}

/// Streicht einen Eintrag aus der Liste. Die Fotos bleiben, wo sie sind.
Future<void> _entferneBibliothek(
  Einstellungsstand stand,
  BibliothekMitZustand b,
) async {
  final context = stand.kontext;
  final bestaetigt = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppTexte.of(context).einstBibEntfernenTitel(b.eintrag.name)),
      content: Text(AppTexte.of(context).einstBibEntfernenText),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppTexte.of(context).allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(AppTexte.of(context).allgEntfernen),
        ),
      ],
    ),
  );
  if (bestaetigt != true) return;
  final entfernt = await LibraryLocation.entferneAusListe(b.eintrag.path);
  if (!context.mounted) return;
  stand.aendere(() {
    stand.bibliothekenFuture = LibraryLocation.bekannte();
  });
  if (!entfernt) {
    melde.warnung(AppTexte.of(context).einstBibNichtEntfernbar);
  }
}
