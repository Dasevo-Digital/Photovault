import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/serveradresse.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';

enum _Schritt { eingabe, code, einrichten, codes, laden }

/// Das Telefon mit einem Photo Vault Server verbinden: Adresse, Name,
/// Passwort, dann der Code der Authenticator-App – beim ersten Mal mit
/// deren Einrichtung. Danach holt das Telefon die Bibliothek.
///
/// Anders als am Desktop gibt es hier keinen QR-Code: Die Authenticator-App
/// läuft auf demselben Telefon. Der Knopf öffnet sie mit dem Geheimnis
/// (`otpauth://`); wer eine App ohne diesen Weg hat, tippt es ab.
class Anmelden extends StatefulWidget {
  const Anmelden({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<Anmelden> createState() => _AnmeldenState();
}

class _AnmeldenState extends State<Anmelden> {
  final _adresse = TextEditingController();
  final _name = TextEditingController();
  final _passwort = TextEditingController();
  final _geraet = TextEditingController();
  final _code = TextEditingController();

  var _schritt = _Schritt.eingabe;
  var _arbeitet = false;
  String? _fehler;
  Uri? _server;
  Anmeldung? _anmeldung;
  String? _vorgang;
  AnmeldungTotpEinrichten? _einrichten;
  String? _token;
  List<String>? _codes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_geraet.text.isEmpty) _geraet.text = AppTexte.of(context).geraetVorgabe;
  }

  @override
  void dispose() {
    _anmeldung?.schliesse();
    for (final c in [_adresse, _name, _passwort, _geraet, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _mitArbeit(Future<void> Function() arbeit) async {
    final t = AppTexte.of(context);
    setState(() {
      _arbeitet = true;
      _fehler = null;
    });
    try {
      await arbeit();
    } on KeineVerbindung {
      _fehler = t.anmeldenNichtErreichbar;
    } on Serverfehler {
      _fehler = t.anmeldenKeinServer;
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _anmelden() => _mitArbeit(() async {
    final t = AppTexte.of(context);
    final server = serveradresseAus(_adresse.text);
    if (server == null) {
      _fehler = t.anmeldenNichtErreichbar;
      return;
    }
    if (!ohneTlsErlaubt(server)) {
      _fehler = t.anmeldenNurHttps;
      return;
    }
    _anmeldung?.schliesse();
    final a = _anmeldung = Anmeldung(server);
    _server = server;
    final z = await a.zustand();
    if (((z['protokoll'] as int?) ?? 0) < 2) {
      _fehler = t.anmeldenKeinServer;
      return;
    }
    _verarbeite(
      await a.anmelden(
        _name.text.trim(),
        _passwort.text,
        geraet: _geraet.text.trim(),
      ),
    );
  });

  Future<void> _bestaetigen() => _mitArbeit(() async {
    final v = _vorgang;
    if (v == null) return;
    _verarbeite(await _anmeldung!.bestaetige(v, _code.text.trim()));
  });

  void _verarbeite(Anmeldeschritt s) {
    final t = AppTexte.of(context);
    switch (s) {
      case AnmeldungFertig(:final token, :final wiederherstellungscodes):
        _token = token;
        _codes = wiederherstellungscodes;
        _passwort.clear();
        _code.clear();
        if (wiederherstellungscodes != null) {
          _schritt = _Schritt.codes;
        } else {
          _hole();
        }
      case AnmeldungCode(:final vorgang):
        _vorgang = vorgang;
        _schritt = _Schritt.code;
      case AnmeldungTotpEinrichten(:final vorgang):
        _vorgang = vorgang;
        _einrichten = s;
        _schritt = _Schritt.einrichten;
      case AnmeldungAbgewiesen(:final warte):
        _fehler = warte == null
            ? t.anmeldenFalsch
            : t.anmeldenGebremst(warte.inSeconds + 1);
    }
  }

  /// Die Bibliothek vom Server holen; danach zeigt die App sie.
  void _hole() {
    setState(() => _schritt = _Schritt.laden);
    _mitArbeit(() async {
      await widget.sitzung.verbinde(
        server: _server!,
        konto: _name.text.trim(),
        geraet: _geraet.text.trim(),
        token: _token!,
      );
    }).then((_) {
      if (mounted && _fehler != null) {
        setState(() => _schritt = _Schritt.codes);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.anmeldenTitel)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ..._inhalt(t),
            if (_fehler != null) ...[
              const SizedBox(height: 12),
              Text(
                _fehler!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_arbeitet) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _inhalt(AppTexte t) => switch (_schritt) {
    _Schritt.eingabe => [
      Text(t.anmeldenErklaerung),
      const SizedBox(height: 16),
      TextField(
        controller: _adresse,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: t.anmeldenAdresse,
          hintText: t.anmeldenAdresseHinweis,
        ),
      ),
      TextField(
        controller: _name,
        autocorrect: false,
        decoration: InputDecoration(labelText: t.anmeldenName),
      ),
      TextField(
        controller: _passwort,
        obscureText: true,
        decoration: InputDecoration(labelText: t.anmeldenPasswort),
        onSubmitted: (_) => _arbeitet ? null : _anmelden(),
      ),
      TextField(
        controller: _geraet,
        decoration: InputDecoration(labelText: t.anmeldenGeraet),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _arbeitet ? null : _anmelden,
        child: Text(t.anmeldenAnmelden),
      ),
    ],
    _Schritt.code => [
      Text(t.anmeldenCodeTitel, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(t.anmeldenCodeHinweis),
      _codefeld(),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _arbeitet ? null : _bestaetigen,
        child: Text(t.anmeldenBestaetigen),
      ),
    ],
    _Schritt.einrichten => [
      Text(t.anmeldenTotpTitel, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(t.anmeldenTotpText),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        icon: const Icon(Icons.open_in_new),
        label: Text(t.anmeldenTotpOeffnen),
        // Ohne App für `otpauth://` bleibt das Abtippen; ein Fehler
        // hier wäre nur Lärm.
        onPressed: () => launchUrl(
          Uri.parse(_einrichten!.adresse),
          mode: LaunchMode.externalApplication,
        ).then((_) {}, onError: (_) {}),
      ),
      const SizedBox(height: 12),
      SelectableText(
        _gruppiert(_einrichten!.geheimnis),
        textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
      ),
      TextButton.icon(
        icon: const Icon(Icons.copy_outlined),
        label: Text(t.kopieren),
        onPressed: () =>
            Clipboard.setData(ClipboardData(text: _einrichten!.geheimnis)),
      ),
      _codefeld(),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _arbeitet ? null : _bestaetigen,
        child: Text(t.anmeldenBestaetigen),
      ),
    ],
    _Schritt.codes => [
      Text(
        t.anmeldenCodesTitel,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(t.anmeldenCodesText),
      const SizedBox(height: 12),
      SelectableText(
        _codes!.join('\n'),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
      ),
      TextButton.icon(
        icon: const Icon(Icons.copy_outlined),
        label: Text(t.kopieren),
        onPressed: () =>
            Clipboard.setData(ClipboardData(text: _codes!.join('\n'))),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: _arbeitet ? null : _hole, child: Text(t.weiter)),
    ],
    _Schritt.laden => [Text(t.anmeldenLaedt, textAlign: TextAlign.center)],
  };

  Widget _codefeld() => TextField(
    controller: _code,
    autofocus: true,
    autocorrect: false,
    keyboardType: TextInputType.visiblePassword,
    style: const TextStyle(fontFamily: 'monospace', fontSize: 20),
    onSubmitted: (_) => _arbeitet ? null : _bestaetigen(),
  );

  static String _gruppiert(String s) => [
    for (var i = 0; i < s.length; i += 4)
      s.substring(i, i + 4 > s.length ? s.length : i + 4),
  ].join(' ');
}
