import 'package:flutter/material.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/verbindung.dart';

import '../l10n/app_localizations.dart';
import '../einfuegbares_menue.dart';

/// Die Konten des Servers, für Verwalter (Konto → Konten verwalten):
/// anlegen, Passwort neu setzen, TOTP zurücksetzen, entsperren, entfernen.
class Konten extends StatefulWidget {
  const Konten({super.key, required this.verwaltung});

  final Kontenverwaltung verwaltung;

  @override
  State<Konten> createState() => _KontenState();
}

class _KontenState extends State<Konten> {
  late Future<List<Kontoeintrag>> _konten = widget.verwaltung.liste();

  void _neuLaden() => setState(() {
    _konten = widget.verwaltung.liste();
  });

  Future<void> _tue(Future<void> Function() aktion, {String? erfolg}) async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    String meldung;
    try {
      await aktion();
      meldung = erfolg ?? t.kontoErledigt;
    } on Serverfehler catch (f) {
      meldung = grundAus(f) ?? t.fehlerAllgemein;
    } on KeineVerbindung {
      meldung = t.anmeldenNichtErreichbar;
    }
    bote.showSnackBar(SnackBar(content: Text(meldung)));
    if (mounted) _neuLaden();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.kontenTitel)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt_outlined),
        label: Text(t.kontoAnlegen),
        onPressed: _anlegen,
      ),
      body: FutureBuilder<List<Kontoeintrag>>(
        future: _konten,
        builder: (context, s) {
          if (s.hasError) {
            return Center(
              child: Text(
                s.error is KeineVerbindung
                    ? t.anmeldenNichtErreichbar
                    : t.fehlerAllgemein,
              ),
            );
          }
          final konten = s.data;
          if (konten == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: () async {
              _neuLaden();
              await _konten;
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final k in konten)
                  ListTile(
                    leading: Icon(
                      k.verwalter
                          ? Icons.admin_panel_settings_outlined
                          : Icons.person_outline,
                    ),
                    title: Text(k.du ? '${k.name} · ${t.kontoDu}' : k.name),
                    subtitle: Text(
                      [
                        if (k.verwalter) t.kontoVerwalter,
                        t.kontoGeraete(k.geraete),
                        k.totp ? t.kontoMitTotp : t.kontoOhneTotp,
                        if (k.gesperrt) t.kontoGesperrt,
                      ].join(' · '),
                    ),
                    onTap: k.du ? null : () => _aktionen(k),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _aktionen(Kontoeintrag k) async {
    final t = AppTexte.of(context);
    final wahl = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                k.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(t.kontoPasswortSetzen),
              onTap: () => Navigator.pop(context, 'passwort'),
            ),
            if (k.totp)
              ListTile(
                leading: const Icon(Icons.phonelink_lock_outlined),
                title: Text(t.kontoTotpZuruecksetzen),
                onTap: () => Navigator.pop(context, 'totp'),
              ),
            if (k.gesperrt)
              ListTile(
                leading: const Icon(Icons.lock_open_outlined),
                title: Text(t.kontoEntsperren),
                onTap: () => Navigator.pop(context, 'entsperren'),
              ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined),
              title: Text(t.entfernen),
              onTap: () => Navigator.pop(context, 'entfernen'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (wahl) {
      case 'passwort':
        final e = await showDialog<_Eingabe>(
          context: context,
          builder: (_) => _KontoDialog(
            titel: t.kontoPasswortSetzen,
            text: t.kontoPasswortSetzenText(k.name),
          ),
        );
        if (e != null) {
          await _tue(() => widget.verwaltung.setzePasswort(k.id, e.passwort));
        }
      case 'totp':
        await _tue(
          () => widget.verwaltung.totpZuruecksetzen(k.id),
          erfolg: t.kontoTotpZurueckgesetzt(k.name),
        );
      case 'entsperren':
        await _tue(() => widget.verwaltung.entsperre(k.id));
      case 'entfernen':
        final ja = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.kontoEntfernenTitel(k.name)),
            content: Text(t.kontoEntfernenText),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.abbrechen),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.entfernen),
              ),
            ],
          ),
        );
        if (ja == true) await _tue(() => widget.verwaltung.entferne(k.id));
    }
  }

  Future<void> _anlegen() async {
    final t = AppTexte.of(context);
    final e = await showDialog<_Eingabe>(
      context: context,
      builder: (_) => _KontoDialog(titel: t.kontoAnlegen, mitName: true),
    );
    if (e == null) return;
    await _tue(
      () =>
          widget.verwaltung.legeAn(e.name, e.passwort, verwalter: e.verwalter),
    );
  }
}

typedef _Eingabe = ({String name, String passwort, bool verwalter});

/// Name (beim Anlegen), Passwort zweimal und ob Verwalter – mit denselben
/// Regeln wie auf dem Server.
class _KontoDialog extends StatefulWidget {
  const _KontoDialog({required this.titel, this.text, this.mitName = false});

  final String titel;
  final String? text;
  final bool mitName;

  @override
  State<_KontoDialog> createState() => _KontoDialogState();
}

class _KontoDialogState extends State<_KontoDialog> {
  final _name = TextEditingController();
  final _passwort = TextEditingController();
  final _passwort2 = TextEditingController();
  var _verwalter = false;
  String? _fehler;

  @override
  void dispose() {
    _name.dispose();
    _passwort.dispose();
    _passwort2.dispose();
    super.dispose();
  }

  void _fertig() {
    final t = AppTexte.of(context);
    setState(() {
      _fehler = widget.mitName && !kontonameGueltig(_name.text)
          ? t.anmeldenNameUngueltig
          : _passwort.text.length < passwortMindestlaenge
          ? t.anmeldenPasswortZuKurz(passwortMindestlaenge)
          : _passwort.text != _passwort2.text
          ? t.anmeldenPasswortUngleich
          : null;
    });
    if (_fehler != null) return;
    Navigator.pop<_Eingabe>(context, (
      name: _name.text.trim(),
      passwort: _passwort.text,
      verwalter: _verwalter,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(widget.titel),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.text != null) Text(widget.text!),
          if (widget.mitName)
            TextField(
              contextMenuBuilder: einfuegbaresMenue,
              controller: _name,
              autofocus: true,
              autocorrect: false,
              decoration: InputDecoration(labelText: t.anmeldenName),
            ),
          TextField(
            contextMenuBuilder: einfuegbaresMenue,
            controller: _passwort,
            autofocus: !widget.mitName,
            obscureText: true,
            decoration: InputDecoration(labelText: t.anmeldenPasswort),
          ),
          TextField(
            contextMenuBuilder: einfuegbaresMenue,
            controller: _passwort2,
            obscureText: true,
            decoration: InputDecoration(
              labelText: t.anmeldenPasswortWiederholen,
            ),
            onSubmitted: (_) => _fertig(),
          ),
          if (widget.mitName)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _verwalter,
              onChanged: (v) => setState(() => _verwalter = v ?? false),
              title: Text(t.kontoAlsVerwalter),
            ),
          if (_fehler != null) ...[
            const SizedBox(height: 8),
            Text(
              _fehler!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.abbrechen),
        ),
        FilledButton(onPressed: _fertig, child: Text(t.speichern)),
      ],
    );
  }
}
