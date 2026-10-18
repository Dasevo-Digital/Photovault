import 'package:flutter/material.dart';
import 'package:kern/abgleich/verbindung.dart';

import '../einfuegbares_menue.dart';
import '../formate.dart';
import '../l10n/app_localizations.dart';

/// Das eigene Konto wie im Browser (web/app.js, zeigeKonto): wer man ist,
/// die Geräte des Kontos zum Abmelden und „Passwort ändern“.
class EigenesKonto extends StatefulWidget {
  const EigenesKonto({
    super.key,
    required this.verbindung,
    required this.abmelden,
  });

  final Serververbindung verbindung;

  /// Dieses Telefon abmelden – wie der Knopf unten auf der Kontoseite.
  final VoidCallback abmelden;

  @override
  State<EigenesKonto> createState() => _EigenesKontoState();
}

class _EigenesKontoState extends State<EigenesKonto> {
  Map<String, Object?>? _konto;
  List<Map<String, Object?>> _geraete = const [];

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final k = await widget.verbindung.hole('api/v1/konto');
      final g = await widget.verbindung.hole('api/v1/geraete');
      if (!mounted) return;
      setState(() {
        _konto = k;
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

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final k = _konto;
    if (k == null) return const SizedBox.shrink();
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
