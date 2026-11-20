import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/speicherinventar.dart';

String _titel(AppTexte t, Speicherorteintrag ort) => switch (ort.art) {
  Speicherortart.bibliothek => t.speicherinventarBibliothek(ort.name),
  Speicherortart.dateien => t.speicherinventarDateien(ort.name),
  Speicherortart.sicherung => t.speicherinventarSicherung(ort.name),
};

/// Der konkrete Pfad bleibt sichtbar, auch bei abgezogenem Datenträger.
/// Verbindungen beschreiben Zuordnungen, nicht mehrere unabhängige Kopien.
class SpeicherinventarGrafik extends StatelessWidget {
  const SpeicherinventarGrafik({super.key, required this.stand});
  final SpeicherinventarStand stand;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context), farben = Theme.of(context).colorScheme;
    final gruppen = <String, List<Speicherorteintrag>>{};
    for (final ort in stand.orte) {
      gruppen
          .putIfAbsent(
            ort.laufwerk == null
                ? 'unbekannt'
                : '${ort.laufwerkHistorisch ? 'historisch:' : ''}${ort.laufwerk!.id}',
            () => [],
          )
          .add(ort);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.computer_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                t.speicherinventarGeraet,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (stand.listeUnlesbar)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(t.speicherinventarListeFehler),
          ),
        for (final gruppe in gruppen.entries)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: farben.outlineVariant, width: 2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.storage_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    gruppe.value.first.laufwerk?.name ??
                                        t.speicherinventarLaufwerkUnbekannt,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  if (gruppe.value.first.laufwerk case final l?)
                                    SelectableText(l.pfad),
                                ],
                              ),
                            ),
                          ],
                        ),
                        for (final ort in gruppe.value)
                          Padding(
                            padding: const EdgeInsets.only(top: 16, left: 12),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: farben.outlineVariant,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _Ort(ort: ort),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () => _details(context, ort),
                                        icon: const Icon(Icons.info_outline),
                                        label: Text(t.speicherinventarDetails),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _details(BuildContext context, Speicherorteintrag ort) =>
      showDialog<void>(
        context: context,
        builder: (context) {
          final t = AppTexte.of(context);
          return AlertDialog(
            title: Text(_titel(t, ort)),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Ort(ort: ort),
                  const SizedBox(height: 16),
                  Text(t.speicherinventarDetailHinweis),
                  if (ort.pruefung != null) ...[
                    const SizedBox(height: 12),
                    Text(t.speicherkarteHistorisch),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t.allgSchliessen),
              ),
            ],
          );
        },
      );
}

class _Ort extends StatelessWidget {
  const _Ort({required this.ort});
  final Speicherorteintrag ort;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final datum = DateFormat.yMd(
      Localizations.localeOf(context).toString(),
    ).add_Hm();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(switch (ort.art) {
              Speicherortart.bibliothek => Icons.photo_library_outlined,
              Speicherortart.dateien => Icons.folder_outlined,
              Speicherortart.sicherung => Icons.history_outlined,
            }),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _titel(t, ort),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        if (ort.aktiv)
          Text(
            t.speicherinventarAktiv,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        SelectableText(ort.pfad),
        if (ort.aufgeloesterPfad case final jetzt? when jetzt != ort.pfad) ...[
          Text(t.speicherinventarJetztUnter),
          SelectableText(jetzt),
        ],
        if (ort.weiterePfade.isNotEmpty) ...[
          Text(t.speicherinventarWeiterePfade),
          for (final pfad in ort.weiterePfade) SelectableText(pfad),
        ],
        Text(
          ort.erreichbar
              ? t.speicherinventarErreichbar
              : t.speicherinventarNichtErreichbar,
        ),
        if (ort.laufwerkHistorisch) Text(t.speicherinventarHistorisch),
        if (ort.nachweiseUnlesbar) Text(t.speicherkarteNachweisUnlesbar),
        if (ort.art == Speicherortart.bibliothek && !ort.erreichbar)
          Text(t.speicherinventarKeineNachweise),
        if (ort.art == Speicherortart.bibliothek &&
            ort.erreichbar &&
            !ort.katalogVorhanden &&
            !ort.aktiv)
          Text(t.speicherinventarKeinKatalog),
        if (ort.pruefung case final n?) ...[
          Text(
            t.speicherinventarNachweis(
              datum.format(n.am.toLocal()),
              n.bestaetigt,
            ),
          ),
          if (!n.abgeschlossen) Text(t.speicherkarteTeilpruefung),
        ],
      ],
    );
  }
}
