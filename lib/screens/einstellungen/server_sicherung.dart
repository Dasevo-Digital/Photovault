import 'package:flutter/material.dart';
import 'package:kern/abgleich/anmeldung.dart' show passwortMindestlaenge;
import 'package:kern/abgleich/konten.dart' show grundAus;
import 'package:kern/abgleich/sicherung.dart';
import 'package:kern/abgleich/verbindung.dart';

import '../../l10n/app_localizations.dart';
import '../../services/meldungsdienst.dart';
import '../../state/library_state.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/einfuegbares_menue.dart';
import 'gemeinsam.dart';

/// Die Sicherung des Servers (Issue #125), für Verwalter: wie sie steht,
/// einrichten, ein neues Ziel annehmen, jetzt sichern.
class ServerSicherungAbschnitt extends StatelessWidget {
  const ServerSicherungAbschnitt(this.library, {super.key});

  final LibraryState library;

  Future<void> _tue(
    BuildContext context,
    Future<Serversicherungsstand> Function(Serververbindung v) aktion, {
    String? erfolg,
  }) async {
    final t = AppTexte.of(context);
    final a = library.abgleich;
    if (a == null) return;
    try {
      await aktion(a.verbindung);
      if (erfolg != null) melde.erfolg(erfolg);
    } on Serverfehler catch (f) {
      melde.fehler(grundAus(f) ?? t.serverFehler);
    } on KeineVerbindung {
      melde.fehler(t.serverNichtErreichbar);
    }
    await library.pruefeServersicherung();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final s = library.serversicherung;
    if (s == null) return const SizedBox.shrink();
    final fehlerfarbe = TextStyle(color: Theme.of(context).colorScheme.error);
    String wann(DateTime d) => datumZeitText(context, d);
    final naechste = s.naechster == null ? '–' : wann(s.naechster!);

    final (text, warnt) = switch (s.stufe) {
      _ when s.laeuft => (t.serverSicherungLaeuft, false),
      'aus' => (t.serverSicherungAus, false),
      'nichtEingerichtet' => (
        t.serverSicherungNichtEingerichtet(s.ziel ?? ''),
        false,
      ),
      'zielFehlt' => (t.serverSicherungZielFehlt, true),
      'fehler' => (t.serverSicherungFehler(s.fehler ?? '–'), true),
      'veraltet' => (
        s.letzterErfolg == null
            ? t.serverSicherungVeraltetNie
            : t.serverSicherungVeraltet(wann(s.letzterErfolg!)),
        true,
      ),
      _ => (
        s.letzterErfolg == null
            ? t.serverSicherungNochNie(naechste)
            : t.serverSicherungOk(wann(s.letzterErfolg!), s.neu, naechste),
        false,
      ),
    };
    final eingerichtet = !const {'aus', 'nichtEingerichtet'}.contains(s.stufe);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t.serverSicherungTitel,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(text, style: warnt ? fehlerfarbe : null),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (s.stufe == 'nichtEingerichtet')
              OutlinedButton.icon(
                icon: const Icon(Icons.lock_outline),
                label: Text(t.serverSicherungEinrichten),
                onPressed: () => _einrichten(context),
              ),
            if (s.stufe == 'zielFehlt')
              OutlinedButton.icon(
                icon: const Icon(Icons.drive_folder_upload_outlined),
                label: Text(t.serverSicherungZielNeu),
                onPressed: () => _zielNeu(context),
              ),
            if (eingerichtet && s.stufe != 'zielFehlt')
              OutlinedButton.icon(
                icon: const Icon(Icons.backup_outlined),
                label: Text(t.serverSicherungJetzt),
                onPressed: s.laeuft
                    ? null
                    : () => _tue(
                        context,
                        Serversicherungsstand.jetzt,
                        erfolg: t.serverSicherungGestartet,
                      ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _einrichten(BuildContext context) async {
    final t = AppTexte.of(context);
    final passphrase = await showDialog<String>(
      context: context,
      builder: (_) => const _PassphraseDialog(),
    );
    if (passphrase == null || !context.mounted) return;
    await _tue(
      context,
      (v) => Serversicherungsstand.einrichten(v, passphrase),
      erfolg: t.serverSicherungGestartet,
    );
  }

  Future<void> _zielNeu(BuildContext context) async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.serverSicherungZielNeu),
        content: Text(t.serverSicherungZielNeuText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.allgUebernehmen),
          ),
        ],
      ),
    );
    if (ja != true || !context.mounted) return;
    await _tue(context, Serversicherungsstand.zielNeu);
  }
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog();

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _eins = TextEditingController();
  final _zwei = TextEditingController();
  String? _fehler;

  @override
  void dispose() {
    _eins.dispose();
    _zwei.dispose();
    super.dispose();
  }

  void _fertig() {
    final t = AppTexte.of(context);
    setState(() {
      _fehler = _eins.text.length < passwortMindestlaenge
          ? t.serverPasswortZuKurz(passwortMindestlaenge)
          : _eins.text != _zwei.text
          ? t.serverPasswortUngleich
          : null;
    });
    if (_fehler == null) Navigator.pop(context, _eins.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(t.serverSicherungEinrichten),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.serverSicherungEinrichtenText),
            TextField(
              contextMenuBuilder: einfuegbaresMenue,
              controller: _eins,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(
                labelText: t.serverSicherungPassphrase,
              ),
            ),
            TextField(
              contextMenuBuilder: einfuegbaresMenue,
              controller: _zwei,
              obscureText: true,
              decoration: InputDecoration(
                labelText: t.serverPasswortWiederholen,
              ),
              onSubmitted: (_) => _fertig(),
            ),
            if (_fehler != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _fehler!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(onPressed: _fertig, child: Text(t.allgFestlegen)),
      ],
    );
  }
}
