import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kern/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../services/kachelvorrat.dart';
import '../../services/meldungsdienst.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eigene_karte_einstellung.dart';
import '../../widgets/kartenquellen_uebersicht.dart';
import '../../widgets/mini_location_map.dart'
    show Kartenstil, setzeCartoSchluessel, setzeKarteHochaufloesend;
import '../kachelmitschnitt_screen.dart';
import '../map_screen.dart' show Kartenansicht;
import 'einstellungsstand.dart';

/// Karte: CARTO-Schlüssel, doppelte Auflösung, Kartenquellen, Vorladen und Mitschnitt.
class KarteGruppe extends StatelessWidget {
  const KarteGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) {
    // Beim Öffnen der Gruppe, nicht beim Aufbau des Bildschirms: Die
    // Gruppeninhalte werden erst gebaut, wenn jemand sie aufklappt
    // (siehe [_Gruppe.inhalt]). [_ladeCartoSchluessel] schützt sich
    // selbst gegen den zweiten Aufruf.
    unawaited(_ladeCartoSchluessel(stand));
    unawaited(_ladeKarteScharf(stand));
    final t = AppTexte.of(context);
    final aktiv = stand.cartoSchluessel.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Der einzige Weg, auf dem die App ohne Knopfdruck mit einem
        // fremden Server spricht – und in jeder Kacheladresse steht, welchen
        // Ausschnitt jemand ansieht. Bis zur 17. Prüfrunde stand das
        // nirgends; der Text zum Ortsverzeichnis daneben betonte sogar
        // „komplett lokal", was für die Geokodierung stimmt und deshalb
        // umso leichter falsch gelesen wird.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.public_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  t.einstKartenNetzHinweis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            t.einstCartoText,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      aktiv ? Icons.check_circle : Icons.dark_mode_outlined,
                      color: aktiv ? context.semantik.erfolg : null,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        aktiv ? t.einstCartoAktiv : t.einstCartoOhne,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: stand.cartoSchluessel,
                        decoration: InputDecoration(
                          labelText: t.einstCartoFeld,
                          hintText: t.einstCartoFeldHinweis,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _speichereCartoSchluessel(stand),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: () => _speichereCartoSchluessel(stand),
                      child: Text(t.allgSpeichern),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  t.einstCartoQuelle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: AppSpacing.xl),
        // Die eigene Quelle steht zwischen CARTO und dem Vorrat, weil sie
        // zu beidem gehört: Sie ist die zweite Stelle, an der ein fremder
        // Schlüssel ins Spiel kommt, und sie ist das, was der Vorrat
        // danach vorlädt.
        // Erst die Auskunft, dann das Eingabefeld: Wer eine eigene Quelle
        // eintraegt, will vorher wissen, was es ueberhaupt gibt und wie
        // tief es traegt.
        // Die doppelte Auflösung steht VOR den Quellen: Sie gilt für alle
        // und ist die eine Stellschraube, die sich am Bildschirm sofort
        // bemerkbar macht.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.hd_outlined),
          title: Text(t.einstKarteScharfTitel),
          subtitle: Text(t.einstKarteScharfText),
          value: stand.karteScharf,
          onChanged: (an) => _karteScharfSetzen(stand, an),
        ),
        const Divider(height: AppSpacing.xl),
        Text(
          t.einstKartenquellenTitel,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        KartenquellenUebersicht(
          library: stand.library,
          // Eine Vorlage mit Schlüssel kann die Übersicht nicht selbst
          // einschalten – sie reicht sie ins Formular durch und scrollt
          // dorthin, damit der Sprung nicht ins Leere geht.
          aufVorlage: (v) {
            stand.eigeneKarte.currentState?.vorlageEinsetzen(v);
            final ziel = stand.eigeneKarte.currentContext;
            if (ziel != null) {
              unawaited(
                Scrollable.ensureVisible(
                  ziel,
                  duration: const Duration(milliseconds: 250),
                  alignment: 0.1,
                ),
              );
            }
          },
        ),
        const Divider(height: AppSpacing.xl),
        Text(
          t.einstEigeneKarteTitel,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        EigeneKarteEinstellung(key: stand.eigeneKarte, library: stand.library),
        const Divider(height: AppSpacing.xl),
        // Der Vorrat. Er steht bei der Karte und nicht bei den Werkzeugen,
        // weil er zum Kartenbild gehört: Wer graue Löcher loswerden will,
        // sucht hier.
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.download_for_offline_outlined),
          title: Text(t.einstVorladenTitel),
          subtitle: Text(
            stand.vorrat == null
                ? t.einstVorladenText
                : t.einstVorladenStand(
                    stand.vorrat!.fertig,
                    stand.vorrat!.gesamt,
                  ),
          ),
          trailing: stand.vorrat == null
              ? const Icon(Icons.chevron_right)
              : SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: stand.vorrat!.gesamt == 0
                        ? null
                        : stand.vorrat!.fertig / stand.vorrat!.gesamt,
                  ),
                ),
          onTap: stand.vorrat == null ? () => _kartenVorladen(stand) : null,
        ),
        // Der Mitschnitt steht bewusst hier und nicht bei den Werkzeugen:
        // Wer graue Kacheln sieht, sucht bei der Karte – und findet dann
        // beides nebeneinander, das Vorladen als Abhilfe und den
        // Mitschnitt als Frage nach dem Warum.
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.troubleshoot_outlined),
          title: Text(t.einstMitschnittTitel),
          subtitle: Text(t.einstMitschnittText),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const KachelmitschnittScreen()),
          ),
        ),
      ],
    );
  }
}

/// Holt den gespeicherten Schlüssel einmalig ins Feld.
Future<void> _ladeCartoSchluessel(Einstellungsstand stand) async {
  if (stand.cartoGeladen) return;
  stand.cartoGeladen = true;
  final wert = await stand.library.db.cartoSchluesselWert();
  if (!stand.aktiv || wert == null) return;
  stand.aendere(() => stand.cartoSchluessel.text = wert);
}

Future<void> _speichereCartoSchluessel(Einstellungsstand stand) async {
  final context = stand.kontext;
  final eingabe = stand.cartoSchluessel.text.trim();
  await stand.library.db.setzeCartoSchluesselWert(eingabe);
  // Auch von Hand setzen und nicht allein auf den Einstellungsstrom in
  // main.dart bauen: Der erreicht diesen Bildschirm zwar auch, aber
  // erst beim nächsten Aufbau. So steht die neue Karte schon da, wenn
  // jemand direkt von hier zur Karte wechselt.
  setzeCartoSchluessel(eingabe);
  if (!context.mounted) return;
  stand.aendere(() {});
  melde.erfolg(
    eingabe.isEmpty
        ? AppTexte.of(context).einstCartoEntfernt
        : AppTexte.of(context).einstCartoGespeichert,
  );
}

Future<void> _ladeKarteScharf(Einstellungsstand stand) async {
  if (stand.karteScharfGeladen) return;
  stand.karteScharfGeladen = true;
  final an = await stand.library.db.karteHochaufloesendWert();
  if (!stand.aktiv) return;
  stand.aendere(() => stand.karteScharf = an);
}

Future<void> _karteScharfSetzen(Einstellungsstand stand, bool an) async {
  stand.aendere(() => stand.karteScharf = an);
  await stand.library.db.setzeKarteHochaufloesend(an);
  // Sofort und nicht erst beim nächsten Start – dieselbe Handhabung wie
  // beim CARTO-Schlüssel und bei der eigenen Quelle.
  setzeKarteHochaufloesend(an);
}

/// Lädt die Kartengebiete der eigenen Fotos auf die Platte.
///
/// **Warum das der bessere Weg ist als ein zweiter Kartenanbieter.**
/// Ein anderer Server löst das Problem nicht, er verschiebt es: Auch
/// er kann klemmen, und graue Löcher entstehen genau dann, wenn eine
/// Kachel im Augenblick des Hinsehens nicht da ist. Wer seine Gebiete
/// einmal vorlädt, ist davon frei – und schont die gespendeten
/// Kachelserver, weil dieselbe Kachel nicht bei jedem Ansehen erneut
/// über die Leitung geht.
Future<void> _kartenVorladen(Einstellungsstand stand) async {
  final context = stand.kontext;
  final t = AppTexte.of(context);
  final verortete = await stand.library.db.assetsWithLocation();
  if (!context.mounted) return;
  final gebiete = gebieteAus([
    for (final a in verortete) (breite: a.latitude!, laenge: a.longitude!),
  ]);
  if (gebiete.isEmpty) {
    melde.warnung(t.einstVorladenKeineOrte);
    return;
  }
  // Erst der Stil, dann die Zahl: Wie viele Kacheln zu laden sind,
  // haengt daran, ob die Karte die doppelte Aufloesung nachbildet -
  // dann liegt jede Anzeigestufe eine Serverstufe hoeher, und die
  // hoechste Stufe hat viermal so viele Kacheln. Vorher stand die Zahl
  // im Dialog, bevor der Stil ueberhaupt feststand.
  //
  // Der gerade gewaehlte Stil, nicht ein fest verdrahteter: Der
  // Speicher haengt an der Adresse, und eine fuer Topo geladene Kachel
  // hilft der hellen Karte nicht.
  final stil = switch (Kartenansicht.ausText(
    await stand.library.db.kartenansicht(),
  )) {
    Kartenansicht.hell => Kartenstil.hell,
    Kartenansicht.topo => Kartenstil.topo,
    // Ohne diese Zeile lüde der Vorrat für die eigene Quelle
    // stillschweigend die dunkle Karte vor – und offline bliebe genau
    // die Karte leer, für die jemand vorgeladen hat.
    Kartenansicht.eigene => Kartenstil.eigene,
    _ => Kartenstil.dunkel,
  };
  if (!context.mounted) return;
  final stufen = vorratStufen(stil, MediaQuery.devicePixelRatioOf(context));
  final kacheln = kachelListe(gebiete, von: stufen.von, bis: stufen.bis);
  final ja = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(t.einstVorladenTitel),
      // Zahl UND geschätzte Grösse: „29.039 Kacheln" sagt niemandem
      // etwas, „rund 850 MB" schon.
      content: Text(
        t.einstVorladenFrage(
          gebiete.length,
          kacheln.length,
          (kacheln.length * 30 / 1024).round(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(t.einstVorladenStarten),
        ),
      ],
    ),
  );
  if (ja != true || !context.mounted) return;

  await stand.vorratLauf?.cancel();
  stand.vorratLauf = ladeVorrat(gebiete, stil, von: stufen.von, bis: stufen.bis)
      .listen(
        (neu) {
          if (context.mounted) stand.aendere(() => stand.vorrat = neu);
        },
        onDone: () {
          final zuletzt = stand.vorrat;
          if (context.mounted) stand.aendere(() => stand.vorrat = null);
          if (zuletzt != null) {
            melde.erfolg(
              t.einstVorladenFertig(zuletzt.geladen, zuletzt.fehler),
            );
          }
        },
      );
}
