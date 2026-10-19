import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/oidc_verknuepfung.dart';
import 'package:kern/abgleich/verbindung.dart';

import '../l10n/app_localizations.dart';
import '../services/meldungsdienst.dart';
import '../services/platform/webseite_oeffnen.dart';
import '../theme/app_spacing.dart';
import '../widgets/einfuegbares_menue.dart';

/// Das eigene Konto auf dem Server, wie in Browser und Handy: wer man ist,
/// die Geräte des Kontos zum Abmelden, „Passwort ändern“ – und die
/// Verknüpfung mit der Anmeldung beim Anbieter (OIDC), wenn der Server
/// eine kennt (Issue #110).
class ServerEigenesKontoScreen extends StatefulWidget {
  const ServerEigenesKontoScreen({super.key, required this.verbindung});

  final Serververbindung verbindung;

  @override
  State<ServerEigenesKontoScreen> createState() =>
      _ServerEigenesKontoScreenState();
}

class _ServerEigenesKontoScreenState extends State<ServerEigenesKontoScreen> {
  Map<String, Object?>? _konto;
  List<Map<String, Object?>> _geraete = const [];
  bool _oidcMoeglich = false;
  bool _verknuepft = false;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final k = await widget.verbindung.hole('api/v1/konto');
      final g = await widget.verbindung.hole('api/v1/geraete');
      final z = await widget.verbindung.hole('api/v1/zustand');
      if (!mounted) return;
      setState(() {
        _konto = k;
        _geraete = [
          for (final x in (g['geraete'] as List? ?? const []))
            (x as Map).cast<String, Object?>(),
        ];
        _oidcMoeglich = (z['anmeldung'] as Map?)?['oidc'] == true;
        _fehler = null;
      });
    } catch (x) {
      if (mounted) setState(() => _fehler = '$x');
    }
  }

  Future<void> _geraetAbmelden(Map<String, Object?> g) async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.serverGeraetAbmeldenFrage('${g['name']}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.serverGeraetAbmelden),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    try {
      final r = await widget.verbindung.anfrage(
        'DELETE',
        'api/v1/geraete/${Uri.encodeComponent('${g['id']}')}',
      );
      if (r.statusCode >= 300) throw Serverfehler(r.statusCode, r.body);
      await _lade();
    } catch (x) {
      melde.warnung('$x');
    }
  }

  Future<void> _verknuepfen() async {
    final t = AppTexte.of(context);
    setState(() => _verknuepft = true);
    melde.hinweis(t.serverOidcLaeuft);
    try {
      final ausgang = await OidcVerknuepfung(widget.verbindung).verknuepfe(
        antwort: t.serverOidcSeite,
        oeffne: (adresse) => oeffneWebseite('$adresse'),
      );
      switch (ausgang) {
        case Oidcausgang.verknuepft:
          melde.hinweis(t.serverOidcFertig);
        case Oidcausgang.abgelehnt:
          melde.warnung(t.serverOidcAbgelehnt);
        case Oidcausgang.zeitUm:
          melde.warnung(t.serverOidcZeitUm);
        case Oidcausgang.vergeben:
          melde.warnung(t.serverOidcVergeben);
      }
      await _lade();
    } catch (x) {
      melde.warnung('$x');
    } finally {
      if (mounted) setState(() => _verknuepft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final k = _konto;
    final zeit = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).add_Hm();
    final anbieter = [for (final a in (k?['oidc'] as List? ?? const [])) '$a'];
    return Scaffold(
      appBar: AppBar(title: Text(t.serverEigenesKontoTitel)),
      body: k == null
          ? Center(
              child: _fehler == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Text(_fehler!),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    [
                      '${k['name']}',
                      if (k['verwalter'] == true) t.serverKontoVerwalter,
                      k['totp'] == true
                          ? t.serverKontoMitTotp
                          : t.serverKontoOhneTotp,
                    ].join(' · '),
                  ),
                ),
                const Divider(),
                Text(
                  t.serverGeraeteTitel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final g in _geraete)
                  ListTile(
                    leading: const Icon(Icons.devices_other_outlined),
                    title: Text(
                      g['id'] == k['geraet']
                          ? '${g['name']} (${t.serverDiesesGeraet})'
                          : '${g['name']}',
                    ),
                    subtitle: Text(
                      [
                        if (DateTime.tryParse('${g['zuletzt']}') case final z?)
                          t.serverGeraetZuletzt(zeit.format(z.toLocal())),
                        if ((g['adresse'] ?? '') != '') '${g['adresse']}',
                      ].join(' · '),
                      style: TextStyle(color: farben.onSurfaceVariant),
                    ),
                    // Dieser Rechner meldet sich über „Trennen“ ab – dort
                    // steht, was mit der Bibliothek geschieht.
                    trailing: g['id'] == k['geraet']
                        ? null
                        : TextButton(
                            onPressed: () => _geraetAbmelden(g),
                            child: Text(t.serverGeraetAbmelden),
                          ),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.password_outlined),
                  title: Text(t.serverPasswortAendern),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _PasswortDialog(
                      verbindung: widget.verbindung,
                      mitCode: k['totp'] == true,
                    ),
                  ),
                ),
                if (_oidcMoeglich) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: Text(t.serverOidcTitel),
                    subtitle: Text(
                      anbieter.isEmpty
                          ? t.serverOidcNicht
                          : t.serverOidcVerknuepft(anbieter.join(', ')),
                    ),
                    trailing: OutlinedButton(
                      onPressed: _verknuepft ? null : _verknuepfen,
                      child: Text(t.serverOidcVerknuepfen),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// „Passwort ändern“ – dieselben Felder wie in Browser und Handy.
class _PasswortDialog extends StatefulWidget {
  const _PasswortDialog({required this.verbindung, required this.mitCode});

  final Serververbindung verbindung;
  final bool mitCode;

  @override
  State<_PasswortDialog> createState() => _PasswortDialogState();
}

class _PasswortDialogState extends State<_PasswortDialog> {
  final _alt = TextEditingController();
  final _neu = TextEditingController();
  final _neu2 = TextEditingController();
  final _code = TextEditingController();
  var _andere = false;
  var _laeuft = false;
  String? _meldung;

  @override
  void dispose() {
    for (final c in [_alt, _neu, _neu2, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _aendern() async {
    final t = AppTexte.of(context);
    if (_neu.text != _neu2.text) {
      setState(() => _meldung = t.serverPasswortUngleich);
      return;
    }
    setState(() {
      _laeuft = true;
      _meldung = null;
    });
    try {
      await widget.verbindung.schicke('api/v1/konto/passwort', {
        'alt': _alt.text,
        'neu': _neu.text,
        if (_code.text.trim().isNotEmpty) 'code': _code.text.trim(),
        'andereAbmelden': _andere,
      });
      if (!mounted) return;
      Navigator.pop(context);
      melde.hinweis(t.serverPasswortGeaendert);
    } on Serverfehler catch (f) {
      setState(() => _meldung = f.text.isEmpty ? '${f.status}' : f.text);
    } catch (x) {
      setState(() => _meldung = '$x');
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    Widget feld(
      TextEditingController c,
      String name, {
      List<String> hilfe = const [AutofillHints.password],
      bool verdeckt = true,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: c,
        obscureText: verdeckt,
        autofillHints: hilfe,
        contextMenuBuilder: einfuegbaresMenue,
        decoration: InputDecoration(
          labelText: name,
          border: const OutlineInputBorder(),
        ),
      ),
    );
    return AlertDialog(
      title: Text(t.serverPasswortAendern),
      content: SizedBox(
        width: 380,
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              feld(_alt, t.serverPasswortAlt),
              feld(
                _neu,
                t.serverPasswortNeu,
                hilfe: const [AutofillHints.newPassword],
              ),
              feld(
                _neu2,
                t.serverPasswortWiederholen,
                hilfe: const [AutofillHints.newPassword],
              ),
              if (widget.mitCode)
                feld(
                  _code,
                  t.serverTotpCode,
                  hilfe: const [AutofillHints.oneTimeCode],
                  verdeckt: false,
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _andere,
                title: Text(t.serverAndereAbmelden),
                onChanged: (w) => setState(() => _andere = w ?? false),
              ),
              if (_meldung != null)
                Text(
                  _meldung!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(
          onPressed: _laeuft ? null : _aendern,
          child: Text(t.serverAendern),
        ),
      ],
    );
  }
}
