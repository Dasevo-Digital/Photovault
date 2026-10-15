import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart' show grundAus;
import 'package:kern/abgleich/serveradresse.dart';
import 'package:kern/abgleich/umzug.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../services/library_location.dart';
import '../services/meldungsdienst.dart';
import '../theme/app_spacing.dart';
import '../widgets/qr_bild.dart';
import 'einstellungen/einstellungsstand.dart';
import 'einstellungen/gemeinsam.dart';
import '../widgets/einfuegbares_menue.dart';

enum _Schritt { eingabe, erstesKonto, code, einrichten, codes, wahl }

/// Verbindet diesen Rechner mit einem Photo Vault Server (Issue #86,
/// Stufe 2): anmelden – mit Zwei-Faktor-Code, beim ersten Mal mit dessen
/// Einrichtung –, dann entweder die Bibliothek des Servers hierher holen
/// oder die Bibliothek dieses Rechners zum Server umziehen.
///
/// Hat der Server noch kein Konto, legt dieser Bildschirm das erste an
/// (aus dem Heimnetz) – mit dem Namen und Passwort, die eben eingegeben
/// wurden, nach einer zweiten Eingabe des Passworts.
///
/// Beides endet mit einem Neustart: Datenbank, Pfade und Zwischenspeicher
/// hängen an der Bibliothek, die beim Start geöffnet wurde.
class ServerVerbindenScreen extends StatefulWidget {
  const ServerVerbindenScreen({
    super.key,
    required this.stand,
    @visibleForTesting this.anmeldungFuer = Anmeldung.new,
  });

  final Einstellungsstand stand;

  /// Wie die Anmeldung an einen Server entsteht – im Test gegen einen
  /// nachgestellten.
  final Anmeldung Function(Uri server) anmeldungFuer;

  @override
  State<ServerVerbindenScreen> createState() => _ServerVerbindenScreenState();
}

class _ServerVerbindenScreenState extends State<ServerVerbindenScreen> {
  final _adresse = TextEditingController();
  final _name = TextEditingController();
  final _passwort = TextEditingController();
  final _passwort2 = TextEditingController();
  final _geraet = TextEditingController(text: Platform.localHostname);
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
  int? _aufnahmenServer;
  int? _aufnahmenHier;

  @override
  void dispose() {
    _anmeldung?.schliesse();
    for (final c in [_adresse, _name, _passwort, _passwort2, _geraet, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _mitArbeit(Future<void> Function() arbeit) async {
    setState(() {
      _arbeitet = true;
      _fehler = null;
    });
    final t = AppTexte.of(context);
    try {
      await arbeit();
    } on KeineVerbindung {
      _fehler = t.serverNichtErreichbar;
    } on Serverfehler {
      _fehler = t.serverKeinPhotoVault;
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _anmelden() => _mitArbeit(() async {
    final t = AppTexte.of(context);
    final server = serveradresseAus(_adresse.text);
    if (server == null) {
      _fehler = t.serverNichtErreichbar;
      return;
    }
    if (!ohneTlsErlaubt(server)) {
      _fehler = t.serverNurHttps;
      return;
    }
    _anmeldung?.schliesse();
    final a = _anmeldung = widget.anmeldungFuer(server);
    _server = server;
    final zustand = await a.zustand();
    if (((zustand['protokoll'] as int?) ?? 0) < 2) {
      _fehler = t.serverKeinPhotoVault;
      return;
    }
    if (zustand['einrichten'] == true) {
      // Noch kein Konto: Name und Passwort von eben werden das erste.
      if (!kontonameGueltig(_name.text)) {
        _fehler = t.serverNameUngueltig;
      } else if (_passwort.text.length < passwortMindestlaenge) {
        _fehler = t.serverPasswortZuKurz(passwortMindestlaenge);
      } else {
        _schritt = _Schritt.erstesKonto;
      }
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

  Future<void> _erstesAnlegen() => _mitArbeit(() async {
    final t = AppTexte.of(context);
    if (_passwort2.text != _passwort.text) {
      _fehler = t.serverPasswortUngleich;
      return;
    }
    try {
      _verarbeite(
        await _anmeldung!.einrichten(
          _name.text.trim(),
          _passwort.text,
          geraet: _geraet.text.trim(),
        ),
      );
      _passwort2.clear();
    } on Serverfehler catch (f) {
      switch (f.status) {
        case 403:
          _fehler = t.serverErstesNurHeimnetz;
        case 409:
          // Jemand war schneller (oder ein zweites Fenster): anmelden.
          _fehler = t.serverSchonEingerichtet;
          _passwort2.clear();
          _schritt = _Schritt.eingabe;
        default:
          _fehler = grundAus(f) ?? t.serverFehler;
      }
    }
  });

  Future<void> _bestaetigen() => _mitArbeit(() async {
    final vorgang = _vorgang;
    if (vorgang == null) return;
    _verarbeite(await _anmeldung!.bestaetige(vorgang, _code.text.trim()));
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
          _schritt = _Schritt.wahl;
          _zaehle();
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
            ? t.serverFalsch
            : t.serverGebremst(warte.inSeconds + 1);
    }
  }

  /// Wie viele Aufnahmen hier und dort liegen – für die Wahl.
  Future<void> _zaehle() async {
    final library = widget.stand.library;
    try {
      final v = Serververbindung(_server!, _token!);
      final b = await v.hole('api/v1/bibliothek');
      v.schliesse();
      final db = library.db;
      final anzahl = db.assets.id.count();
      final hier =
          await (db.selectOnly(db.assets)
                ..addColumns([anzahl])
                ..where(db.assets.isTrashed.equals(false)))
              .getSingle();
      if (!mounted) return;
      setState(() {
        _aufnahmenServer = b['aufnahmen'] as int?;
        _aufnahmenHier = hier.read(anzahl);
      });
    } catch (e) {
      if (mounted) setState(() => _fehler = '$e');
    }
  }

  Verbindungsdatei _verbindungsdatei() => Verbindungsdatei(
    server: _server!,
    konto: _name.text.trim(),
    geraet: _geraet.text.trim(),
    token: _token!,
  );

  /// Holt die Bibliothek des Servers in einen eigenen Ordner, trägt sie
  /// in die Liste ein und öffnet sie beim nächsten Start.
  Future<void> _holeServerbibliothek() async {
    final t = AppTexte.of(context);
    await verlegeBibliothek(
      widget.stand,
      loadingText: t.serverLaedt,
      restartMessage: t.serverFertigNeustart,
      errorPrefix: t.serverFehler,
      action: () async {
        final daten = await LibraryLocation.datenordner();
        final basis = '${_name.text.trim()}-${_server!.host}'.replaceAll(
          RegExp(r'[^A-Za-z0-9._-]'),
          '_',
        );
        var ordner = Directory(p.join(daten.path, 'verbunden', basis));
        for (var i = 2; await ordner.exists(); i++) {
          ordner = Directory(p.join(daten.path, 'verbunden', '$basis-$i'));
        }
        await ordner.create(recursive: true);
        final v = Serververbindung(_server!, _token!);
        try {
          await Abgleich.holeAbzug(
            v,
            File(p.join(ordner.path, 'library.sqlite')),
          );
        } finally {
          v.schliesse();
        }
        await _verbindungsdatei().schreibe(ordner);
        final eintrag = await LibraryLocation.fuegeEigenenOrdnerHinzu(
          ordner,
          name: '${_name.text.trim()} @ ${_server!.host}',
        );
        await LibraryLocation.wechsleZu(eintrag);
        await widget.stand.library.db.close();
      },
    );
  }

  /// Zieht die Bibliothek dieses Rechners auf den Server; danach ist sie
  /// dessen Kopie.
  Future<void> _ziehUm() async {
    final t = AppTexte.of(context);
    final library = widget.stand.library;
    final fortschritt = ValueNotifier<BibliotheksVerschiebefortschritt?>(null);
    var dateien = 0;
    await verlegeBibliothek(
      widget.stand,
      loadingText: t.serverZiehtUm,
      restartMessage: t.serverFertigNeustart,
      errorPrefix: t.serverFehler,
      progress: fortschritt,
      action: () async {
        final v = Serververbindung(_server!, _token!);
        try {
          await for (final s in Umzug(
            v,
            library.db,
            library.paths.root,
          ).laufe()) {
            if (s.datei != null) dateien++;
            fortschritt.value = BibliotheksVerschiebefortschritt(
              kopierteBytes: s.erledigt,
              gesamtBytes: s.gesamt,
              kopierteDateien: dateien,
              gesamtDateien: dateien,
            );
          }
        } finally {
          v.schliesse();
        }
        await _verbindungsdatei().schreibe(await LibraryLocation.currentRoot());
        await library.db.close();
      },
    );
    fortschritt.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.serverVerbindenTitel)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._inhalt(t),
                if (_fehler != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _fehler!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_arbeitet) ...[
                  const SizedBox(height: AppSpacing.md),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _inhalt(AppTexte t) => switch (_schritt) {
    _Schritt.eingabe => [
      Text(t.serverErklaerung),
      const SizedBox(height: AppSpacing.lg),
      TextField(
        contextMenuBuilder: einfuegbaresMenue,
        controller: _adresse,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: t.serverAdresse,
          hintText: t.serverAdresseHinweis,
        ),
      ),
      TextField(
        contextMenuBuilder: einfuegbaresMenue,
        controller: _name,
        autocorrect: false,
        decoration: InputDecoration(labelText: t.serverName),
      ),
      TextField(
        contextMenuBuilder: einfuegbaresMenue,
        controller: _passwort,
        obscureText: true,
        decoration: InputDecoration(labelText: t.serverPasswort),
        onSubmitted: (_) => _arbeitet ? null : _anmelden(),
      ),
      TextField(
        contextMenuBuilder: einfuegbaresMenue,
        controller: _geraet,
        decoration: InputDecoration(labelText: t.serverGeraet),
      ),
      const SizedBox(height: AppSpacing.lg),
      FilledButton(
        onPressed: _arbeitet ? null : _anmelden,
        child: Text(t.serverAnmelden),
      ),
    ],
    _Schritt.erstesKonto => [
      Text(t.serverErstesTitel, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      Text(t.serverErstesText(_name.text.trim())),
      TextField(
        contextMenuBuilder: einfuegbaresMenue,
        controller: _passwort2,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(labelText: t.serverPasswortWiederholen),
        onSubmitted: (_) => _arbeitet ? null : _erstesAnlegen(),
      ),
      const SizedBox(height: AppSpacing.lg),
      // Schmal stehen die Knöpfe untereinander, statt überzulaufen.
      OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.end,
        overflowSpacing: AppSpacing.sm,
        children: [
          TextButton(
            onPressed: _arbeitet
                ? null
                : () => setState(() {
                    _passwort2.clear();
                    _fehler = null;
                    _schritt = _Schritt.eingabe;
                  }),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: _arbeitet ? null : _erstesAnlegen,
            child: Text(t.serverErstesAnlegen),
          ),
        ],
      ),
    ],
    _Schritt.code => [
      Text(t.serverCodeTitel, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      Text(t.serverCodeHinweis),
      _codefeld(),
      const SizedBox(height: AppSpacing.lg),
      FilledButton(
        onPressed: _arbeitet ? null : _bestaetigen,
        child: Text(t.serverBestaetigen),
      ),
    ],
    _Schritt.einrichten => [
      Text(t.serverTotpTitel, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      Text(t.serverTotpText),
      const SizedBox(height: AppSpacing.md),
      Center(child: QrBild(_einrichten!.adresse)),
      const SizedBox(height: AppSpacing.md),
      Center(
        child: SelectableText(
          _gruppiert(_einrichten!.geheimnis),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
        ),
      ),
      _codefeld(),
      const SizedBox(height: AppSpacing.lg),
      FilledButton(
        onPressed: _arbeitet ? null : _bestaetigen,
        child: Text(t.serverBestaetigen),
      ),
    ],
    _Schritt.codes => [
      Text(t.serverCodesTitel, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      Text(t.serverCodesText),
      const SizedBox(height: AppSpacing.md),
      SelectableText(
        _codes!.join('\n'),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_outlined),
            label: Text(t.serverKopieren),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _codes!.join('\n')));
              melde.erfolg(t.serverKopiert);
            },
          ),
          const Spacer(),
          FilledButton(
            onPressed: () {
              setState(() => _schritt = _Schritt.wahl);
              _zaehle();
            },
            child: Text(t.serverWeiter),
          ),
        ],
      ),
    ],
    _Schritt.wahl => [
      Text(t.serverWahlTitel, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.md),
      if (_aufnahmenServer == null)
        const Center(child: CircularProgressIndicator())
      else ...[
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: Text(t.serverServerBib),
            subtitle: Text(t.serverServerBibText(_aufnahmenServer!)),
            onTap: _arbeitet ? null : _holeServerbibliothek,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(t.serverUmziehen),
            subtitle: Text(
              widget.stand.library.verbunden
                  ? t.serverUmziehenSchonVerbunden
                  : _aufnahmenServer! > 0
                  ? t.serverUmziehenNichtLeer
                  : t.serverUmziehenText(_aufnahmenHier ?? 0),
            ),
            enabled:
                !_arbeitet &&
                !widget.stand.library.verbunden &&
                _aufnahmenServer == 0,
            onTap: _ziehUm,
          ),
        ),
      ],
    ],
  };

  Widget _codefeld() => TextField(
    contextMenuBuilder: einfuegbaresMenue,
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
