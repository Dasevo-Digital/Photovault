import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../services/library_location.dart';
import '../../services/meldungsdienst.dart';
import '../../theme/app_spacing.dart';
import 'einstellungsstand.dart';

/// Der überwachte Ordner, aus dem neue Fotos von selbst übernommen werden.
class UeberwachterOrdnerGruppe extends StatelessWidget {
  const UeberwachterOrdnerGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Card(
        child: FutureBuilder<({String pfad, String? token})?>(
          future: stand.ueberwachterOrdnerFuture,
          builder: (context, snapshot) {
            final eintrag = snapshot.data;
            return Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_special_outlined),
                  title: Text(
                    eintrag == null
                        ? AppTexte.of(context).einstUeberwachtKeiner
                        : eintrag.pfad,
                  ),
                  subtitle: Text(
                    eintrag == null
                        ? AppTexte.of(context).einstUeberwachtErklaerung
                        : AppTexte.of(context).einstUeberwachtAktiv,
                  ),
                  isThreeLine: eintrag == null,
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _waehleUeberwachtenOrdner(stand),
                          icon: const Icon(Icons.folder_open_outlined),
                          label: Text(
                            eintrag == null
                                ? AppTexte.of(context).einstUeberwachtWaehlen
                                : AppTexte.of(
                                    context,
                                  ).einstUeberwachtAndererWaehlen,
                          ),
                        ),
                      ),
                      if (eintrag != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _beendeUeberwachung(stand),
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: Text(
                              AppTexte.of(context).einstUeberwachtBeenden,
                            ),
                          ),
                        ),
                      ],
                    ],
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

Future<void> _waehleUeberwachtenOrdner(Einstellungsstand stand) async {
  final context = stand.kontext;
  final picked = await LibraryLocation.pickFolder(
    dialogMessage: AppTexte.of(context).einstUeberwachtAuswahl,
  );
  if (picked == null || !context.mounted) return;
  await stand.library.db.setzeUeberwachtenOrdner(
    pfad: picked.path,
    token: picked.token,
  );
  if (!context.mounted) return;
  stand.aendere(() {
    stand.ueberwachterOrdnerFuture = stand.library.db.ueberwachterOrdner();
  });
  final neue = await stand.library.pruefeUeberwachtenOrdner();
  if (!context.mounted) return;
  melde.hinweis(
    neue > 0
        ? AppTexte.of(context).einstUeberwachtUebernommen(neue)
        : AppTexte.of(context).einstUeberwachtNichtsNeues,
  );
}

Future<void> _beendeUeberwachung(Einstellungsstand stand) async {
  await stand.library.db.setzeUeberwachtenOrdner(pfad: null, token: null);
  if (!stand.aktiv) return;
  stand.aendere(() {
    stand.ueberwachterOrdnerFuture = stand.library.db.ueberwachterOrdner();
  });
}
