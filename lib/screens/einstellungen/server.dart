import 'package:flutter/material.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';

import '../../l10n/app_localizations.dart';
import '../../services/library_location.dart';
import '../../theme/app_spacing.dart';
import '../server_verbinden_screen.dart';
import 'einstellungsstand.dart';
import 'gemeinsam.dart';

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
        if (z != null && z.abgelehnt.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            t.serverAbgelehnt(z.abgelehnt.length),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
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
