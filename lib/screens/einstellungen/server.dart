import 'package:flutter/material.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/rechenhilfe.dart';
import 'package:kern/abgleich/speicher.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/auswertung/rechenhilfe.dart' show Rechenfaehigkeit;

import '../../l10n/app_localizations.dart';
import '../../services/groessentext.dart';
import '../../services/library_location.dart';
import '../../state/library_state.dart';
import '../../theme/app_spacing.dart';
import '../server_konten_screen.dart';
import '../server_verbinden_screen.dart';
import 'einstellungsstand.dart';
import 'gemeinsam.dart';
import 'server_sicherung.dart';

/// Die Verbindung zu einem Photo Vault Server (Issue #86, Stufe 2): wie
/// es steht, verbinden, trennen.
class ServerGruppe extends StatelessWidget {
  const ServerGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final library = stand.library;
    final v = library.verbindung;
    if (v == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.serverErklaerung),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            icon: const Icon(Icons.cloud_outlined),
            label: Text(t.serverVerbinden),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ServerVerbindenScreen(stand: stand),
              ),
            ),
          ),
        ],
      );
    }
    final z = library.abgleichszustand;
    final zustand = z == null
        ? null
        : z.schemaAnders
        ? (z.appZuAlt ? t.serverAppZuAlt : t.serverZuAlt)
        : z.abgemeldet
        ? t.serverAbgemeldet
        : !z.erreichbar
        ? t.serverOffline(z.ausstehend)
        : z.ausstehend > 0
        ? t.serverSendet(z.ausstehend)
        : t.serverAbgeglichen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            z?.erreichbar ?? false
                ? Icons.cloud_done_outlined
                : Icons.cloud_off_outlined,
          ),
          title: Text(t.serverVerbundenMit(v.server.host)),
          subtitle: Text(t.serverKontoGeraet(v.konto, v.geraet)),
        ),
        if (zustand != null) Text(zustand),
        if (library.serverspeicher
            case Serverspeicher(:final gesamt?, :final frei?) && final sp)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              sp.voll
                  ? t.serverSpeicherVoll
                  : t.serverSpeicherStand(
                      groessentext(frei),
                      groessentext(gesamt),
                    ),
              style: sp.knapp || sp.voll
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          ),
        if (z != null && z.abgelehnt.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            t.serverAbgelehnt(z.abgelehnt.length),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (library.abgleich case final a?) _KontenZugang(a.verbindung),
        if (library.serversicherung != null) ...[
          const Divider(height: AppSpacing.xl),
          ServerSicherungAbschnitt(library),
        ],
        const Divider(height: AppSpacing.xl),
        _Rechenhilfe(library),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          icon: const Icon(Icons.link_off_outlined),
          label: Text(t.serverTrennen),
          onPressed: () => _trenne(stand, v),
        ),
      ],
    );
  }
}

/// „Konten verwalten“ – nur für Verwalter; ob man einer ist, fragt der
/// Knopf einmal beim Server nach.
class _KontenZugang extends StatefulWidget {
  const _KontenZugang(this.verbindung);

  final Serververbindung verbindung;

  @override
  State<_KontenZugang> createState() => _KontenZugangState();
}

class _KontenZugangState extends State<_KontenZugang> {
  late final _verwaltung = Kontenverwaltung(widget.verbindung);
  late final Future<bool> _verwalter = _verwaltung.binVerwalter().catchError(
    (_) => false,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _verwalter,
    builder: (context, s) => s.data != true
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.manage_accounts_outlined),
              label: Text(AppTexte.of(context).serverKontenVerwalten),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ServerKontenScreen(verwaltung: _verwaltung),
                ),
              ),
            ),
          ),
  );
}

/// Für den Server mitrechnen (Issue #104).
class _Rechenhilfe extends StatelessWidget {
  const _Rechenhilfe(this.library);

  final LibraryState library;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final an = library.rechenhilfeAn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.memory_outlined),
          title: Text(t.serverRechenhilfe),
          subtitle: Text(t.serverRechenhilfeText),
          value: an,
          onChanged: library.setzeRechenhilfe,
        ),
        if (an)
          ValueListenableBuilder(
            valueListenable: library.rechenhilfestand,
            builder: (context, s, _) {
              final n = s?.geliefert ?? 0;
              final lage = library.auswertungen.rechenarten.isEmpty
                  ? t.serverRechenhilfeKeinModell
                  : switch (s?.lage) {
                      null || Rechenhilfelage.aus => null,
                      Rechenhilfelage.rechnet => t.serverRechenhilfeRechnet(n),
                      Rechenhilfelage.wartet => t.serverRechenhilfeWartet(n),
                      Rechenhilfelage.offline => t.serverRechenhilfeOffline,
                      Rechenhilfelage.serverZuAlt =>
                        t.serverRechenhilfeServerZuAlt,
                      Rechenhilfelage.abgemeldet => t.serverAbgemeldet,
                    };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?(lage == null ? null : Text(lage)),
                  if ((s?.ausgelassen ?? 0) > 0)
                    Text(t.serverRechenhilfeAusgelassen(s!.ausgelassen)),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Meldet dieses Gerät beim Server ab und macht aus der Kopie eine eigene
/// Bibliothek. Danach startet Photo Vault neu.
Future<void> _trenne(Einstellungsstand stand, Verbindungsdatei v) async {
  final context = stand.kontext;
  final t = AppTexte.of(context);
  final ja = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.serverTrennenTitel),
      content: Text(t.serverTrennenText),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(t.serverTrennenAktion),
        ),
      ],
    ),
  );
  if (ja != true || !context.mounted) return;
  await verlegeBibliothek(
    stand,
    loadingText: t.serverTrennt,
    restartMessage: t.serverGetrennt,
    errorPrefix: t.serverFehler,
    action: () async {
      await stand.library.beendeRechenhilfe();
      await stand.library.abgleich?.beende();
      // Abmelden, wenn der Server erreichbar ist – sonst bleibt das Token
      // dort gültig, bis jemand es abmeldet (Geräteliste, Kommandozeile).
      final s = Serververbindung(v.server, v.token);
      try {
        await s.schicke('api/v1/abmelden', const {});
      } catch (_) {
        // Offline getrennt: die Verbindung hier löst sich trotzdem.
      } finally {
        s.schliesse();
      }
      await Verbindungsdatei.loesche(await LibraryLocation.currentRoot());
      await stand.library.db.close();
    },
  );
}
