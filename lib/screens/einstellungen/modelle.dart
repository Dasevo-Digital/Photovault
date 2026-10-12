import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kern/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../services/groessentext.dart';
import '../../services/meldungsdienst.dart';
import 'package:kern/services/model_catalog.dart';
import '../../services/modelltexte.dart';
import 'package:kern/services/model_download_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import 'einstellungsstand.dart';
import 'gemeinsam.dart';

/// Die KI-Modelle: laden, löschen, prüfen, und die Schalter, die an ihnen hängen.
class ModelleGruppe extends StatelessWidget {
  const ModelleGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          AppTexte.of(context).einstKiHinweis,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      FutureBuilder<bool>(
        key: const ValueKey('auto-analyse'),
        future: stand.einmal(
          EinstellungsAbfrage.autoanalyse,
          stand.library.db.autoAnalyzeAfterImportEnabled,
        ),
        builder: (context, snapshot) {
          final an = snapshot.data ?? true;
          return Card(
            child: SwitchListTile(
              value: an,
              onChanged: (v) async {
                await stand.library.db.fuehreAus(AuswertenNachImportSetzen(v));
                if (stand.aktiv) {
                  stand.neuFragen(EinstellungsAbfrage.autoanalyse);
                }
              },
              secondary: const Icon(Icons.schedule_outlined),
              title: Text(AppTexte.of(context).einstAutoAnalyseTitel),
              isThreeLine: true,
              subtitle: Text(AppTexte.of(context).einstAutoAnalyseText),
            ),
          );
        },
      ),
      // Beide Schalter übersetzen zwischen Englisch und Deutsch. Steht die
      // Oberfläche auf Englisch, sind sie gegenstandslos: Beschreibungen
      // und Vokabular liegen dann bereits in der Sprache vor, in der man
      // sucht. Ausgeblendet statt wirkungslos angeboten – die gespeicherte
      // Einstellung bleibt erhalten und ist beim Zurückwechseln wieder da.
      if (Localizations.localeOf(context).languageCode == 'de') ...[
        _uebersetzungsSchalter(
          stand,
          icon: Icons.translate_outlined,
          titel: AppTexte.of(context).einstUebersetzeBeschreibungTitel,
          beschreibung: AppTexte.of(context).einstUebersetzeBeschreibungText,
          installiert: stand.library.uebersetzungEnDeHalter.installiert,
          lesen: stand.library.db.uebersetzeBeschreibungen,
          schreiben: stand.library.db.setzeUebersetzeBeschreibungen,
        ),
        _uebersetzungsSchalter(
          stand,
          icon: Icons.search_outlined,
          titel: AppTexte.of(context).einstUebersetzeSucheTitel,
          beschreibung: AppTexte.of(context).einstUebersetzeSucheText,
          installiert: stand.library.uebersetzungDeEnHalter.installiert,
          lesen: stand.library.db.uebersetzeSucheUndTags,
          schreiben: (an) async {
            await stand.library.db.fuehreAus(SucheUebersetzenSetzen(an));
            // Die zwischengespeicherten Begriffs-Vektoren stammen sonst
            // noch aus der anderen Sprache und die Umstellung bliebe bis
            // zum nächsten Programmstart wirkungslos.
            stand.library.aiTaggingService.leereBegriffsCache();
          },
        ),
      ],
      const SizedBox(height: 12),
      // Zwoelf Modelle einzeln anzutippen und jedes Mal zu warten, war
      // der erste Weg, den ein neuer Nutzer vor sich hatte - einen Knopf
      // dafuer gab es nicht. Er laedt nur, was fehlt: Wer die
      // Uebersetzung nicht braucht, loescht sie danach einmal und
      // bekommt sie nicht wieder aufgedraengt.
      Builder(
        builder: (context) {
          final fehlende = [
            for (final e in modelleFuerSprache(context, stand.library))
              if (!stand.library.isModelInstalled(e)) e,
          ];
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                onPressed: (fehlende.isEmpty || stand.downloading.isNotEmpty)
                    ? null
                    : () => _alleModelleLaden(stand, fehlende),
                label: Text(
                  fehlende.isEmpty
                      ? AppTexte.of(context).einstAlleModelleDa
                      : AppTexte.of(
                          context,
                        ).einstAlleModelleLaden(fehlende.length),
                ),
              ),
            ),
          );
        },
      ),
      for (final entry in modelleFuerSprache(context, stand.library))
        _ModelCard(
          entry: entry,
          installed: stand.library.isModelInstalled(entry),
          downloading: stand.downloading.contains(entry.id),
          groesse: stand.library.isModelInstalled(entry)
              ? groessentext(
                  stand.library.modelDownloadService.belegteBytes(entry),
                )
              : null,
          onDownload: () => _downloadModel(stand, entry),
          onDelete: () => _deleteModel(stand, entry),
        ),
      // Der Modellordner wächst schnell auf über ein Gigabyte, ohne dass
      // das bisher irgendwo stand.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          AppTexte.of(context).einstModelleBelegterPlatz(
            groessentext(stand.library.modelDownloadService.gesamteBytes()),
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      // Die Prüfsumme im Katalog wirkte bis zur 21. Prüfrunde genau
      // einmal – beim Herunterladen. Danach entschied allein, ob die
      // Datei da ist. Hier ist der Weg, sie noch einmal zu befragen.
      Card(
        child: ListTile(
          leading: const Icon(Icons.verified_outlined),
          title: Text(AppTexte.of(context).einstModellePruefenTitel),
          subtitle: Text(AppTexte.of(context).einstModellePruefenText),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pruefeModelle(stand),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.face_outlined),
          title: Text(AppTexte.of(context).einstGesichtserkennungAktiv),
          subtitle: Text(
            stand.library.faceDetectionAvailable
                ? (stand.library.faceRecognitionAvailable
                      ? AppTexte.of(context).einstGesichtserkennungBeides
                      : AppTexte.of(context).einstNurErkennung)
                : AppTexte.of(context).einstGesichtserkennungInaktiv,
          ),
        ),
      ),
    ],
  );
}

/// Ein Schalter für eine Übersetzungsrichtung.
///
/// Ohne das zugehörige Modell bleibt er sichtbar, aber abgeschaltet, und
/// sagt warum – ein Schalter, der ohne Erklärung nichts tut, ist
/// schlimmer als keiner. Die Modellkarte dazu steht direkt darunter.
Widget _uebersetzungsSchalter(
  Einstellungsstand stand, {
  required IconData icon,
  required String titel,
  required String beschreibung,
  required bool installiert,
  required Future<bool> Function() lesen,
  required Future<void> Function(bool) schreiben,
}) {
  return FutureBuilder<bool>(
    key: ValueKey((EinstellungsAbfrage.uebersetzung, titel)),
    future: stand.einmal((EinstellungsAbfrage.uebersetzung, titel), lesen),
    builder: (context, snapshot) {
      final an = snapshot.data ?? false;
      return Card(
        child: SwitchListTile(
          value: an && installiert,
          onChanged: installiert
              ? (v) async {
                  await schreiben(v);
                  if (stand.aktiv) {
                    stand.neuFragen((EinstellungsAbfrage.uebersetzung, titel));
                  }
                }
              : null,
          secondary: Icon(icon),
          isThreeLine: true,
          title: Text(titel),
          subtitle: Text(
            installiert
                ? beschreibung
                : AppTexte.of(context).einstModellNichtGeladen(beschreibung),
            style: TextStyle(
              fontSize: 12,
              color: installiert ? null : Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
    },
  );
}

/// Rechnet die Prüfsummen aller installierten Modelle nach.
///
/// Warum das nicht beim Programmstart läuft: Der Durchgang kostet
/// gemessen rund 2,6 Sekunden (CLIP allein 1,12 s für 606 MB). Das ist
/// wenig genug für einen Knopf und zu viel für jeden Start.
Future<void> _pruefeModelle(Einstellungsstand stand) async {
  final context = stand.kontext;
  var laeuft = '';
  void Function(void Function())? blattSetState;

  // Wie beim Herunterladen bewusst ohne `await`: Das Future des Sheets
  // löst erst beim Schliessen auf, die Prüfung darunter liefe sonst nie.
  showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setBlattState) {
        blattSetState = setBlattState;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppTexte.of(context).einstModellePruefenTitel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                AppTexte.of(context).einstModellePruefenLaeuft(laeuft),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    ),
  );

  List<Modellbefund> befunde = const [];
  try {
    befunde = await stand.library.modelDownloadService.pruefeAlleInstallierten(
      ModelCatalog.all,
      fortschritt: (datei) {
        laeuft = datei;
        blattSetState?.call(() {});
      },
    );
  } finally {
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
  if (!context.mounted) return;

  final auffaellig = befunde.where((b) => !b.inOrdnung).toList();
  if (befunde.isEmpty) {
    melde.hinweis(AppTexte.of(context).einstModellePruefenNichtsDa);
    return;
  }
  if (auffaellig.isEmpty) {
    melde.erfolg(
      AppTexte.of(context).einstModellePruefenAlleGut(befunde.length),
    );
    return;
  }
  // Ein Fund gehört nicht in eine Meldung, die nach acht Sekunden
  // verblasst: Er verlangt eine Handlung, und die Dateinamen muss man
  // lesen können.
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppTexte.of(context).einstModellePruefenBefundTitel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppTexte.of(context).einstModellePruefenBefundText),
          const SizedBox(height: AppSpacing.md),
          for (final b in auffaellig)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '${b.dateiname} – ${_zustandstext(context, b.zustand)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppTexte.of(context).allgSchliessen),
        ),
      ],
    ),
  );
}

String _zustandstext(BuildContext context, Modellzustand zustand) =>
    switch (zustand) {
      Modellzustand.fehlt => AppTexte.of(context).einstModellZustandFehlt,
      Modellzustand.zuKurz => AppTexte.of(context).einstModellZustandZuKurz,
      Modellzustand.weichtAb => AppTexte.of(context).einstModellZustandWeichtAb,
      // Kommt hier nicht an – `auffaellig` filtert ihn weg. Ein
      // `default` würde einen neuen Zustand stillschweigend schlucken.
      Modellzustand.stimmt => '',
    };

Future<void> _downloadModel(
  Einstellungsstand stand,
  ModelCatalogEntry entry,
) async {
  final context = stand.kontext;
  stand.aendere(() => stand.downloading.add(entry.id));
  double progress = 0;
  void Function(void Function())? sheetSetState;

  // WICHTIG: hier bewusst NICHT auf showModalBottomSheet warten – das
  // Future davon löst erst auf, wenn das Sheet geschlossen wird (also
  // erst im finally unten). Würden wir hier awaiten, würde der Code
  // darunter (der eigentliche Download) nie ausgeführt werden.
  showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) {
        sheetSetState = setSheetState;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppTexte.of(
                  context,
                ).einstModellLaedt(modellTitel(AppTexte.of(context), entry.id)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              // Bei einer Reihe steht sonst zwoelfmal dasselbe Fenster da
              // und man weiss nicht, wie weit es noch ist.
              if (stand.reihenstand != null) ...[
                const SizedBox(height: 4),
                Text(
                  AppTexte.of(context).einstAlleModelleLaeuft(
                    stand.reihenstand!.$1,
                    stand.reihenstand!.$2,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress > 0 ? progress : null),
              const SizedBox(height: 8),
              Text('${(progress * 100).toStringAsFixed(0)} %'),
            ],
          ),
        );
      },
    ),
  );

  try {
    await for (final p in stand.library.modelDownloadService.download(entry)) {
      progress = p.fraction;
      sheetSetState?.call(() {});
    }
    await stand.library.reloadModels();
  } catch (e) {
    if (context.mounted) {
      melde.fehler(fehlertext(context, e));
    }
  } finally {
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    stand.aendere(() => stand.downloading.remove(entry.id));
  }
}

/// Holt alle noch fehlenden Modelle nacheinander.
///
/// Nacheinander und nicht gleichzeitig: Es sind zusammen ueber ein
/// Gigabyte, und zwoelf offene Verbindungen machen keine davon
/// schneller - sie machen nur den Fortschritt unlesbar. Bricht eines
/// ab, laufen die uebrigen weiter; [_downloadModel] meldet den Fehler
/// selbst und der naechste Anlauf holt genau das eine nach.
Future<void> _alleModelleLaden(
  Einstellungsstand stand,
  List<ModelCatalogEntry> fehlende,
) async {
  for (var i = 0; i < fehlende.length; i++) {
    if (!stand.aktiv) return;
    stand.aendere(() => stand.reihenstand = (i + 1, fehlende.length));
    await _downloadModel(stand, fehlende[i]);
  }
  if (stand.aktiv) stand.aendere(() => stand.reihenstand = null);
}

Future<void> _deleteModel(
  Einstellungsstand stand,
  ModelCatalogEntry entry,
) async {
  await stand.library.modelDownloadService.deleteEntry(entry);
  await stand.library.reloadModels();
  if (!stand.aktiv) return;
  stand.aendere(() {});
}

class _ModelCard extends StatelessWidget {
  final ModelCatalogEntry entry;
  final bool installed;
  final bool downloading;

  /// Belegter Platz, bereits lesbar formatiert – null, solange das Modell
  /// nicht installiert ist. Vorher lässt sich die Grösse nicht angeben:
  /// Der Katalog führt nur Dateinamen und Prüfsummen, keine Längen.
  final String? groesse;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _ModelCard({
    required this.entry,
    required this.installed,
    required this.downloading,
    required this.groesse,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          installed ? Icons.check_circle : Icons.cloud_download_outlined,
          color: installed ? context.semantik.erfolg : null,
        ),
        title: Text(modellTitel(AppTexte.of(context), entry.id)),
        subtitle: Text(
          [
            modellBeschreibung(AppTexte.of(context), entry.id),
            AppTexte.of(context).einstModellLizenzZeile(
                  modellLizenz(AppTexte.of(context), entry.id),
                ) +
                (groesse != null ? ' · $groesse' : ''),
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: downloading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : installed
            ? IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: AppTexte.of(context).einstModellLoeschen,
                onPressed: onDelete,
              )
            : FilledButton(
                onPressed: onDownload,
                child: Text(AppTexte.of(context).allgHerunterladen),
              ),
      ),
    );
  }
}
