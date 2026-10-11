import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../services/groessentext.dart';
import '../../theme/app_spacing.dart';
import '../trash_screen.dart';
import 'einstellungsstand.dart';
import 'gemeinsam.dart';

/// Der Papierkorb und seine automatische Leerung.
class PapierkorbGruppe extends StatelessWidget {
  const PapierkorbGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          AppTexte.of(context).einstPapierkorbText,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Card(
        child: FutureBuilder<TrashSettingsData?>(
          future: stand.trashSettingsFuture,
          builder: (context, snapshot) {
            final config = snapshot.data;
            final enabled = config?.autoDeleteEnabled ?? false;
            final afterDays = config?.autoDeleteAfterDays ?? 30;
            final lastRun = config?.lastPurgeAt;

            return Column(
              children: [
                // **Der Weg in den Papierkorb selbst.** Er fehlte seit
                // dem ersten Commit: TrashScreen war vollständig
                // gebaut - Wiederherstellen, endgültig Löschen, leerer
                // Zustand, alle Texte - und wurde von keiner einzigen
                // Stelle aufgerufen. Gelöschte Fotos lagen also in
                // einem Behälter, den niemand öffnen konnte, bis die
                // automatische Leerung sie nach dreissig Tagen
                // endgültig entfernte. Die Duplikatsuche versprach
                // dabei ausdrücklich „über den Papierkorb
                // wiederherstellbar".
                //
                // Hier und nicht in der Leiste: Der gesperrte Ordner
                // wird ebenso von den Einstellungen aus geöffnet, und
                // seine Einstellung steht daneben.
                StreamBuilder<Papierkorbumfang>(
                  // **Wieviel Platz hier liegt, stand nirgends.** An
                  // einer gewachsenen Bibliothek waren es 619
                  // Aufnahmen und 6,01 GB – sieben Prozent des
                  // Bestands, unsichtbar. Die Zahl der Fotos allein
                  // sagt darüber nichts: 619 Bildschirmfotos wären
                  // ein Bruchteil davon.
                  //
                  // Beides rechnet die Datenbank, statt jede Zeile des
                  // Papierkorbs herzuschicken: 0,3 statt 13,0 ms je
                  // Abo, und dieser Aufbau läuft bei jeder Meldung des
                  // Bibliothekszustands.
                  stream: stand.library.db.watchPapierkorbUmfang(),
                  builder: (context, papierkorb) {
                    final anzahl = papierkorb.data?.anzahl ?? 0;
                    final platz = papierkorb.data?.bytes ?? 0;
                    return ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: Text(AppTexte.of(context).papierkorbTitel),
                      subtitle: Text(
                        anzahl == 0
                            ? AppTexte.of(context).papierkorbLeer
                            : AppTexte.of(
                                context,
                              ).papierkorbUmfang(anzahl, groessentext(platz)),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TrashScreen(library: stand.library),
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: enabled,
                  onChanged: (v) async {
                    await stand.library.db.setTrashAutoDeleteConfig(enabled: v);
                    if (stand.aktiv) stand.reloadTrashSettings();
                  },
                  title: Text(AppTexte.of(context).allgAktiv),
                  subtitle: Text(AppTexte.of(context).einstPapierkorbAus),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.timelapse_outlined),
                  title: Text(AppTexte.of(context).einstNachTagen),
                  trailing: DropdownButton<int>(
                    value: afterDays,
                    items: [
                      for (final tage in [7, 14, 30, 60, 90])
                        DropdownMenuItem(
                          value: tage,
                          child: Text(
                            AppTexte.of(context).einstTageDropdown(tage),
                          ),
                        ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      await stand.library.db.setTrashAutoDeleteConfig(
                        enabled: enabled,
                        afterDays: v,
                      );
                      if (stand.aktiv) stand.reloadTrashSettings();
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(AppTexte.of(context).einstLetzterLauf),
                  subtitle: Text(
                    lastRun == null
                        ? AppTexte.of(context).einstNieAusgefuehrt
                        : datumZeitText(context, lastRun),
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
