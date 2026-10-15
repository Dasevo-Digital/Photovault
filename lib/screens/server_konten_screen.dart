import 'package:flutter/material.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/verbindung.dart';

import '../l10n/app_localizations.dart';
import '../services/meldungsdienst.dart';
import '../theme/app_spacing.dart';

/// Die Konten des Servers, für Verwalter (Einstellungen → Server): anlegen,
/// Passwort neu setzen, TOTP zurücksetzen, entsperren, entfernen – was
/// sonst nur auf der Kommandozeile des Servers ginge.
class ServerKontenScreen extends StatefulWidget {
  const ServerKontenScreen({super.key, required this.verwaltung});

  final Kontenverwaltung verwaltung;

  @override
  State<ServerKontenScreen> createState() => _ServerKontenScreenState();
}

class _ServerKontenScreenState extends State<ServerKontenScreen> {
  late Future<List<Kontoeintrag>> _konten = widget.verwaltung.liste();

  void _neuLaden() => setState(() {
    _konten = widget.verwaltung.liste();
  });

  /// Führt [aktion] aus und meldet, wie es ausging.
  Future<void> _tue(Future<void> Function() aktion, {String? erfolg}) async {
    final t = AppTexte.of(context);
    try {
      await aktion();
      melde.erfolg(erfolg ?? t.serverKontoErledigt);
    } on Serverfehler catch (f) {
      melde.fehler(grundAus(f) ?? t.serverFehler);
    } on KeineVerbindung {
      melde.fehler(t.serverNichtErreichbar);
    }
    if (mounted) _neuLaden();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.serverKontenTitel)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt_outlined),
        label: Text(t.serverKontoAnlegen),
        onPressed: _anlegen,
      ),
      body: FutureBuilder<List<Kontoeintrag>>(
        future: _konten,
        builder: (context, s) {
          if (s.hasError) {
            return Center(
              child: Text(
                s.error is KeineVerbindung
                    ? t.serverNichtErreichbar
                    : t.serverFehler,
              ),
            );
          }
          final konten = s.data;
          if (konten == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xxl * 2,
            ),
            children: [for (final k in konten) _zeile(t, k)],
          );
        },
      ),
    );
  }

  Widget _zeile(AppTexte t, Kontoeintrag k) => ListTile(
    leading: Icon(
      k.verwalter ? Icons.admin_panel_settings_outlined : Icons.person_outline,
    ),
    title: Text(k.du ? '${k.name} · ${t.serverKontoDu}' : k.name),
    subtitle: Text(
      [
        if (k.verwalter) t.serverKontoVerwalter,
        t.serverKontoGeraete(k.geraete),
        k.totp ? t.serverKontoMitTotp : t.serverKontoOhneTotp,
        if (k.gesperrt) t.serverKontoGesperrt,
      ].join(' · '),
    ),
    trailing: k.du
        ? null
        : PopupMenuButton<String>(
            onSelected: (wahl) => switch (wahl) {
              'passwort' => _passwortSetzen(k),
              'totp' => _tue(
                () => widget.verwaltung.totpZuruecksetzen(k.id),
                erfolg: t.serverKontoTotpZurueckgesetzt(k.name),
              ),
              'entsperren' => _tue(() => widget.verwaltung.entsperre(k.id)),
              _ => _entfernen(k),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'passwort',
                child: Text(t.serverKontoPasswortSetzen),
              ),
              if (k.totp)
                PopupMenuItem(
                  value: 'totp',
                  child: Text(t.serverKontoTotpZuruecksetzen),
                ),
              if (k.gesperrt)
                PopupMenuItem(
                  value: 'entsperren',
                  child: Text(t.serverKontoEntsperren),
                ),
              PopupMenuItem(
                value: 'entfernen',
                child: Text(t.serverKontoEntfernen),
              ),
            ],
          ),
  );

  Future<void> _anlegen() async {
    final t = AppTexte.of(context);
    final eingabe = await showDialog<({String name, String passwort, bool v})>(
      context: context,
      builder: (_) => _KontoDialog(titel: t.serverKontoAnlegen, mitName: true),
    );
    if (eingabe == null) return;
    await _tue(
      () => widget.verwaltung.legeAn(
        eingabe.name,
        eingabe.passwort,
        verwalter: eingabe.v,
      ),
    );
  }

  Future<void> _passwortSetzen(Kontoeintrag k) async {
    final t = AppTexte.of(context);
    final eingabe = await showDialog<({String name, String passwort, bool v})>(
      context: context,
      builder: (_) => _KontoDialog(
        titel: t.serverKontoPasswortSetzen,
        text: t.serverKontoPasswortSetzenText(k.name),
      ),
    );
    if (eingabe == null) return;
    await _tue(() => widget.verwaltung.setzePasswort(k.id, eingabe.passwort));
  }

  Future<void> _entfernen(Kontoeintrag k) async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.serverKontoEntfernenTitel(k.name)),
        content: Text(t.serverKontoEntfernenText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.allgEntfernen),
          ),
        ],
      ),
    );
    if (ja == true) await _tue(() => widget.verwaltung.entferne(k.id));
  }
}

/// Name (beim Anlegen), Passwort zweimal und ob Verwalter – mit denselben
/// Regeln wie auf dem Server, damit nichts erst dort scheitert.
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
          ? t.serverNameUngueltig
          : _passwort.text.length < passwortMindestlaenge
          ? t.serverPasswortZuKurz(passwortMindestlaenge)
          : _passwort.text != _passwort2.text
          ? t.serverPasswortUngleich
          : null;
    });
    if (_fehler != null) return;
    Navigator.pop(context, (
      name: _name.text.trim(),
      passwort: _passwort.text,
      v: _verwalter,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(widget.titel),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.text != null) Text(widget.text!),
            if (widget.mitName)
              TextField(
                controller: _name,
                autofocus: true,
                autocorrect: false,
                decoration: InputDecoration(labelText: t.serverName),
              ),
            TextField(
              controller: _passwort,
              autofocus: !widget.mitName,
              obscureText: true,
              decoration: InputDecoration(labelText: t.serverPasswort),
            ),
            TextField(
              controller: _passwort2,
              obscureText: true,
              decoration: InputDecoration(
                labelText: t.serverPasswortWiederholen,
              ),
              onSubmitted: (_) => _fertig(),
            ),
            if (widget.mitName)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _verwalter,
                onChanged: (v) => setState(() => _verwalter = v ?? false),
                title: Text(t.serverKontoAlsVerwalter),
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
        FilledButton(onPressed: _fertig, child: Text(t.allgSpeichern)),
      ],
    );
  }
}
