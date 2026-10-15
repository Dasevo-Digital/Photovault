import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/speicher.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/services/groessentext.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'konten.dart';
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
                        : z.schemaAnders
                        ? (z.appZuAlt ? t.appZuAlt : t.serverZuAlt)
                        : z.abgemeldet
                        ? t.abgemeldetHinweis
                        : !z.erreichbar
                        ? t.offline(z.ausstehend)
                        : z.ausstehend > 0
                        ? t.kontoSendet(z.ausstehend)
                        : t.kontoAbgeglichen,
                  ),
                ),
                if (sitzung.serverspeicher
                    case Serverspeicher(:final gesamt?, :final frei?) &&
                        final sp)
                  ListTile(
                    leading: Icon(
                      Icons.storage_outlined,
                      color: sp.knapp || sp.voll
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    title: Text(
                      sp.voll
                          ? t.speicherVoll
                          : t.speicherStand(
                              groessentext(frei),
                              groessentext(gesamt),
                            ),
                    ),
                  ),
              ],
              if (sitzung.serversicherung case final sv? when sv.stufe != 'aus')
                ListTile(
                  leading: Icon(
                    Icons.backup_outlined,
                    color: sv.warnt
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  title: Text(
                    sv.warnt
                        ? t.serverSicherungWarnung
                        : sv.letzterErfolg != null
                        ? t.serverSicherungStand(
                            DateFormat.yMd(
                              Localizations.localeOf(context).toString(),
                            ).add_Hm().format(sv.letzterErfolg!),
                          )
                        : t.serverSicherungOffen,
                  ),
                ),
              if (sitzung.abgleich != null) _Zwischenspeicherzeile(sitzung),
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
              if (sitzung.abgleich case final a?) _KontenZugang(a.verbindung),
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

/// „Konten verwalten“ – nur für Verwalter; ob man einer ist, fragt die
/// Zeile einmal beim Server nach.
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
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return FutureBuilder<bool>(
      future: _verwalter,
      builder: (context, s) => s.data != true
          ? const SizedBox.shrink()
          : ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: Text(t.kontenVerwalten),
              subtitle: Text(t.kontenVerwaltenHinweis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Konten(verwaltung: _verwaltung),
                ),
              ),
            ),
    );
  }
}

/// Wie viel Platz die vom Server geholten Vorschauen und Originale auf
/// dem Telefon belegen – mit Grenze zum Wählen und einem Knopf zum Leeren
/// (Issue #131).
class _Zwischenspeicherzeile extends StatefulWidget {
  const _Zwischenspeicherzeile(this.sitzung);

  final Sitzung sitzung;

  @override
  State<_Zwischenspeicherzeile> createState() => _ZwischenspeicherzeileState();
}

class _ZwischenspeicherzeileState extends State<_Zwischenspeicherzeile> {
  late Future<int> _groesse = widget.sitzung.zwischenspeicher.groesse();

  static const _stufenMb = [512, 1024, 2048, 5120, 0];

  void _neuMessen() =>
      setState(() => _groesse = widget.sitzung.zwischenspeicher.groesse());

  Future<void> _leeren() async {
    await widget.sitzung.zwischenspeicher.leere();
    if (mounted) _neuMessen();
  }

  Future<void> _grenze() async {
    final t = AppTexte.of(context);
    final jetzt = widget.sitzung.zwischenspeicherGrenzeMb;
    final mb = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(t.kontoZwischenspeicherGrenze),
        children: [
          RadioGroup<int>(
            groupValue: jetzt,
            onChanged: (w) => Navigator.pop(context, w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in _stufenMb)
                  RadioListTile<int>(
                    value: s,
                    title: Text(
                      s == 0
                          ? t.kontoZwischenspeicherOhneGrenze
                          : groessentext(s << 20),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (mb == null || mb == jetzt) return;
    await widget.sitzung.setzeZwischenspeicherGrenze(mb);
    if (mounted) _neuMessen();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final mb = widget.sitzung.zwischenspeicherGrenzeMb;
    return FutureBuilder<int>(
      future: _groesse,
      builder: (context, s) {
        final belegt = s.data == null ? '…' : groessentext(s.data!);
        return ListTile(
          leading: const Icon(Icons.sd_storage_outlined),
          title: Text(t.kontoZwischenspeicher),
          subtitle: Text(
            mb == 0
                ? t.kontoZwischenspeicherOhneGrenzeStand(belegt)
                : t.kontoZwischenspeicherStand(belegt, groessentext(mb << 20)),
          ),
          trailing: TextButton(
            onPressed: _leeren,
            child: Text(t.kontoZwischenspeicherLeeren),
          ),
          onTap: _grenze,
        );
      },
    );
  }
}
