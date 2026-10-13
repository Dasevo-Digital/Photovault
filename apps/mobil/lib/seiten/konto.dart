import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'sicherung.dart';

/// Womit das Telefon verbunden ist, wie der Abgleich steht – und abmelden.
class Konto extends StatelessWidget {
  const Konto({super.key, required this.sitzung});

  final Sitzung sitzung;

  Future<void> _abmelden(BuildContext context) async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.kontoAbmeldenTitel),
        content: Text(t.kontoAbmeldenText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.kontoAbmelden),
          ),
        ],
      ),
    );
    if (ja != true || !context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await sitzung.abmelden();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return ListenableBuilder(
      listenable: sitzung,
      builder: (context, _) {
        final v = sitzung.verbindung;
        final z = sitzung.abgleichszustand;
        return Scaffold(
          appBar: AppBar(title: Text(t.kontoTitel)),
          body: ListView(
            children: [
              if (v != null) ...[
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(v.server.host),
                  subtitle: Text(t.kontoKontoGeraet(v.konto, v.geraet)),
                ),
                ListTile(
                  leading: Icon(
                    z?.erreichbar ?? false
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                  ),
                  title: Text(
                    z == null
                        ? t.kontoVerbindet
                        : z.abgemeldet
                        ? t.abgemeldetHinweis
                        : !z.erreichbar
                        ? t.offline(z.ausstehend)
                        : z.ausstehend > 0
                        ? t.kontoSendet(z.ausstehend)
                        : t.kontoAbgeglichen,
                  ),
                ),
              ],
              if (sitzung.sicherung case final d?)
                ListenableBuilder(
                  listenable: d,
                  builder: (context, _) => ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: Text(t.sicherungTitel),
                    subtitle: Text(sicherungKurz(t, d)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Sicherungsseite(dienst: d),
                      ),
                    ),
                  ),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(t.kontoAbmelden),
                subtitle: Text(t.kontoAbmeldenHinweis),
                onTap: () => _abmelden(context),
              ),
            ],
          ),
        );
      },
    );
  }
}
