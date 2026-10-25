import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kern/abgleich/oidc_verknuepfung.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:url_launcher/url_launcher.dart';

import '../einfuegbares_menue.dart';
import '../formate.dart';
import '../l10n/app_localizations.dart';

/// Das eigene Konto wie im Browser (web/app.js, zeigeKonto): wer man ist,
/// die Geräte des Kontos zum Abmelden, „Passwort ändern“ und – kennt der
/// Server einen Anbieter – die Verknüpfung mit der Anmeldung dort.
class EigenesKonto extends StatefulWidget {
  const EigenesKonto({
    super.key,
    required this.verbindung,
    required this.abmelden,
    this.oeffne = _imBrowserDerApp,
  });

  final Serververbindung verbindung;

  /// Öffnet die Adresse beim Anbieter – im Browser innerhalb der App, damit
  /// sie im Vordergrund bleibt und ihr Rückweg auf diesem Telefon
  /// (kern/abgleich/oidc_verknuepfung.dart) die Antwort annehmen kann.
  final Future<void> Function(Uri adresse) oeffne;

  static Future<void> _imBrowserDerApp(Uri adresse) async {
    await launchUrl(adresse, mode: LaunchMode.inAppBrowserView);
  }

  /// Dieses Telefon abmelden – wie der Knopf unten auf der Kontoseite.
  final VoidCallback abmelden;

  @override
  State<EigenesKonto> createState() => _EigenesKontoState();
}

class _EigenesKontoState extends State<EigenesKonto> {
  Map<String, Object?>? _konto;
  List<Map<String, Object?>> _geraete = const [];
  bool _oidcMoeglich = false;
  bool _verknuepft = false;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final k = await widget.verbindung.hole('api/v1/konto');
      final g = await widget.verbindung.hole('api/v1/geraete');
      // Ein älterer Server kennt die Frage nicht – dann eben ohne.
      var oidc = false;
      try {
        final z = await widget.verbindung.hole('api/v1/zustand');
        oidc = (z['anmeldung'] as Map?)?['oidc'] == true;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _konto = k;
        _oidcMoeglich = oidc;
        _geraete = [
          for (final x in (g['geraete'] as List? ?? const []))
            (x as Map).cast<String, Object?>(),
        ];
      });
    } catch (_) {
      // Ohne Verbindung bleibt der Abschnitt leer – der Abgleich meldet
      // das schon weiter oben.
    }
  }

  Future<void> _geraetAbmelden(Map<String, Object?> g) async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.eigenGeraetAbmeldenFrage('${g['name']}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.eigenGeraetAbmelden),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    final bote = ScaffoldMessenger.of(context);
    try {
      final r = await widget.verbindung.anfrage(
        'DELETE',
        'api/v1/geraete/${Uri.encodeComponent('${g['id']}')}',
      );
      if (r.statusCode >= 300) throw Serverfehler(r.statusCode, r.body);
      await _lade();
    } catch (x) {
      bote.showSnackBar(SnackBar(content: Text('$x')));
    }
  }

  /// Wie am Rechner (server_eigenes_konto_screen.dart): der Browser geht
  /// zum Anbieter und kehrt über den Server auf einen Port nur auf diesem
  /// Telefon zurück (#182).
  Future<void> _verknuepfen() async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    setState(() => _verknuepft = true);
    bote.showSnackBar(SnackBar(content: Text(t.eigenOidcLaeuft)));
    try {
      final ausgang = await OidcVerknuepfung(
        widget.verbindung,
      ).verknuepfe(antwort: t.eigenOidcSeite, oeffne: widget.oeffne);
      // Die Antwortseite hat ihren Dienst getan; zurück in die App.
      await closeInAppWebView().catchError((_) {});
      bote
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(switch (ausgang) {
              Oidcausgang.verknuepft => t.eigenOidcFertig,
              Oidcausgang.abgelehnt => t.eigenOidcAbgelehnt,
              Oidcausgang.zeitUm => t.eigenOidcZeitUm,
              Oidcausgang.vergeben => t.eigenOidcVergeben,
            }),
          ),
        );
      await _lade();
    } catch (x) {
      bote
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$x')));
    } finally {
      if (mounted) setState(() => _verknuepft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final k = _konto;
    if (k == null) return const SizedBox.shrink();
    final anbieter = [for (final a in (k['oidc'] as List? ?? const [])) '$a'];
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final zeit = datumZeitMittel(sprache);
    final farben = Theme.of(context).colorScheme;
    final dieses = k['geraet'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(
            [
              '${k['name']}',
              if (k['verwalter'] == true) t.kontoVerwalter,
              if (k['totp'] == true) t.eigenTotpEingerichtet,
            ].join(' · '),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            t.eigenGeraete,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final g in _geraete)
          ListTile(
            leading: const Icon(Icons.devices_other_outlined),
            title: Text(
              '${g['name']}${g['id'] == dieses ? ' ${t.eigenDiesesTelefon}' : ''}',
            ),
            subtitle: Text(
              [
                if (DateTime.tryParse('${g['zuletzt']}') case final z?)
                  t.eigenZuletzt(zeit.format(z.toLocal())),
                if ((g['adresse'] ?? '') != '') '${g['adresse']}',
              ].join(' · '),
              style: TextStyle(color: farben.onSurfaceVariant),
            ),
            trailing: TextButton(
              onPressed: g['id'] == dieses
                  ? widget.abmelden
                  : () => _geraetAbmelden(g),
              child: Text(
                g['id'] == dieses ? t.kontoAbmelden : t.eigenGeraetAbmelden,
              ),
            ),
          ),
        // Neue Wiederherstellungscodes – etwa wenn die alten irgendwo offen
        // lagen. Wie im Browser nur mit eingerichtetem zweiten Faktor.
        if (k['totp'] == true)
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: Text(t.anmeldenCodesTitel),
            subtitle: Text(
              t.eigenCodesUebrig(
                (k['wiederherstellungscodes'] as num?)?.toInt() ?? 0,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NeueCodes(verbindung: widget.verbindung),
                ),
              );
              if (mounted) _lade();
            },
          ),
        ListTile(
          leading: const Icon(Icons.password_outlined),
          title: Text(t.eigenPasswortAendern),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PasswortAendern(
                verbindung: widget.verbindung,
                mitCode: k['totp'] == true,
              ),
            ),
          ),
        ),
        if (_oidcMoeglich)
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(t.eigenOidcTitel),
            subtitle: Text(
              anbieter.isEmpty
                  ? t.eigenOidcNicht
                  : t.eigenOidcVerknuepft(anbieter.join(', ')),
              style: TextStyle(color: farben.onSurfaceVariant),
            ),
            trailing: OutlinedButton(
              onPressed: _verknuepft ? null : _verknuepfen,
              child: Text(t.eigenOidcVerknuepfen),
            ),
          ),
      ],
    );
  }
}

/// „Passwort ändern“ – dieselben Felder wie im Browser.
class PasswortAendern extends StatefulWidget {
  const PasswortAendern({
    super.key,
    required this.verbindung,
    required this.mitCode,
  });

  final Serververbindung verbindung;

  /// Mit TOTP verlangt der Server auch den Code.
  final bool mitCode;

  @override
  State<PasswortAendern> createState() => _PasswortAendernState();
}

class _PasswortAendernState extends State<PasswortAendern> {
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
      setState(() => _meldung = t.eigenPasswortUngleich);
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
      for (final c in [_alt, _neu, _neu2, _code]) {
        c.clear();
      }
      setState(() => _meldung = t.eigenPasswortGeaendert);
    } on Serverfehler catch (f) {
      setState(() => _meldung = _fehlertext(f));
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
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: verdeckt,
        autofillHints: hilfe,
        contextMenuBuilder: einfuegbaresMenue,
        keyboardType: verdeckt ? null : TextInputType.number,
        decoration: InputDecoration(
          labelText: name,
          border: const OutlineInputBorder(),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t.eigenPasswortAendern)),
      body: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            feld(_alt, t.eigenPasswortAlt),
            feld(_neu, t.eigenPasswortNeu, hilfe: [AutofillHints.newPassword]),
            feld(
              _neu2,
              t.eigenPasswortNochmal,
              hilfe: [AutofillHints.newPassword],
            ),
            if (widget.mitCode)
              feld(
                _code,
                t.eigenTotpCode,
                hilfe: [AutofillHints.oneTimeCode],
                verdeckt: false,
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _andere,
              title: Text(t.eigenAndereAbmelden),
              onChanged: (w) => setState(() => _andere = w ?? false),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _laeuft ? null : _aendern,
              child: Text(t.eigenAendern),
            ),
            if (_meldung != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_meldung!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Neue Wiederherstellungscodes, bestätigt mit einem Code aus der
/// Authenticator-App – wie auf der Kontoseite im Browser. Die neuen stehen
/// danach markierbar da, mit „Kopieren“.
class NeueCodes extends StatefulWidget {
  const NeueCodes({super.key, required this.verbindung});

  final Serververbindung verbindung;

  @override
  State<NeueCodes> createState() => _NeueCodesState();
}

class _NeueCodesState extends State<NeueCodes> {
  final _code = TextEditingController();
  List<String>? _codes;
  String? _meldung;
  var _laeuft = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _erzeugen() async {
    setState(() {
      _laeuft = true;
      _meldung = null;
    });
    try {
      final d = await widget.verbindung.schicke(
        'api/v1/konto/wiederherstellungscodes',
        {'code': _code.text.trim()},
      );
      _code.clear();
      setState(() {
        _codes = [
          for (final c in (d['wiederherstellungscodes'] as List? ?? const []))
            '$c',
        ];
      });
    } on Serverfehler catch (f) {
      setState(() => _meldung = _fehlertext(f));
    } catch (x) {
      setState(() => _meldung = '$x');
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final codes = _codes;
    return Scaffold(
      appBar: AppBar(title: Text(t.anmeldenCodesTitel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (codes == null) ...[
            Text(t.eigenCodesHinweis),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofillHints: const [AutofillHints.oneTimeCode],
              contextMenuBuilder: einfuegbaresMenue,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t.eigenTotpCode,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _laeuft ? null : _erzeugen(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _laeuft ? null : _erzeugen,
              child: Text(t.eigenCodesNeu),
            ),
          ] else ...[
            Text(t.eigenCodesFertig),
            const SizedBox(height: 12),
            SelectableText(
              codes.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.copy_outlined),
                label: Text(t.kopieren),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: codes.join('\n')),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text(t.eigenCodesKopiert)),
                    );
                },
              ),
            ),
          ],
          if (_meldung != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _meldung!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// Was der Server zu einem Fehler sagt: das Feld `fehler` seiner Antwort,
/// nicht die rohe Antwort samt Klammern.
String _fehlertext(Serverfehler f) {
  try {
    final j = jsonDecode(f.text);
    if (j is Map && j['fehler'] is String) return j['fehler'] as String;
  } on FormatException {
    // kein JSON – dann der Text, wie er ist
  }
  return f.text.isEmpty ? '${f.status}' : f.text;
}
