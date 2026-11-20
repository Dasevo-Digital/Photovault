import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kern/services/backup_auswahl.dart';
import 'package:kern/services/backup_service.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../services/platform/folder_access.dart';
import '../services/speicherkarte.dart';
import '../services/speicherschutz.dart';
import '../state/library_state.dart';
import '../services/groessentext.dart';
import '../widgets/pin_dialogs.dart';

class SpeicherschutzScreen extends StatefulWidget {
  const SpeicherschutzScreen({super.key, required this.library});
  final LibraryState library;
  @override
  State<SpeicherschutzScreen> createState() => _SpeicherschutzScreenState();
}

class _SpeicherschutzScreenState extends State<SpeicherschutzScreen> {
  PickedFolder? _originalort, _sicherungsort;
  Speicherschutzplan? _plan;
  bool _arbeitet = false,
      _unabhaengig = false,
      _abbruch = false,
      _verschluesselt = true;
  String? _meldung;
  (int, int) _fortschritt = (0, 0);
  Future<Speicherschutz> _dienst() async => Speicherschutz(
    widget.library.db,
    widget.library.paths,
    nachweise: await SpeicherkarteDienst.fuer(
      widget.library.db,
      widget.library.paths,
    ),
  );
  @override
  void dispose() {
    _abbruch = true;
    super.dispose();
  }

  String _fehler(Object fehler) {
    final t = AppTexte.of(context);
    return fehler is SpeicherschutzFehler
        ? switch (fehler.grund) {
            SpeicherschutzGrund.datentraeger => t.schutzDatentraeger,
            SpeicherschutzGrund.bestaetigung => t.schutzBestaetigungFehlt,
            SpeicherschutzGrund.konflikt => t.schutzKonflikt,
            SpeicherschutzGrund.kopieFehlt => t.schutzKopieFehlt,
            SpeicherschutzGrund.referenzen => t.schutzNurLokal,
            SpeicherschutzGrund.ziel => t.schutzZielFehler,
          }
        : t.schutzFehler;
  }

  void _fort(int n, int gesamt) {
    if (mounted) setState(() => _fortschritt = (n, gesamt));
  }

  Future<void> _arbeite(Future<void> Function() aktion) async {
    setState(() {
      _arbeitet = true;
      _abbruch = false;
      _meldung = null;
      _fortschritt = (0, 0);
      _plan = null;
    });
    try {
      await aktion();
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _meldung = _abbruch
              ? AppTexte.of(context).schutzAbgebrochen
              : _fehler(e),
        );
      }
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _waehle(bool original) async {
    final ort = await FolderAccess.forCurrentPlatform().pickFolder(
      message: original
          ? AppTexte.of(context).schutzOriginalort
          : AppTexte.of(context).schutzSicherungsort,
    );
    if (ort == null || !mounted) return;
    setState(() {
      if (original) {
        _originalort = ort;
      } else {
        _sicherungsort = ort;
      }
      _unabhaengig = false;
      _plan = null;
    });
  }

  Future<void> _kopieren() => _arbeite(() async {
    final dienst = await _dienst();
    final n = await dienst.originalkopienAnlegen(
      _originalort!,
      abgebrochen: () => _abbruch || !mounted,
      fortschritt: _fort,
    );
    if (mounted) {
      setState(() {
        _plan = null;
        _meldung = AppTexte.of(context).schutzKopiert(n);
      });
    }
  });
  Future<void> _sichern() async {
    final t = AppTexte.of(context);
    final ziel = await FolderAccess.forCurrentPlatform().pickFolder(
      message: t.einstBackupZielWaehlen,
    );
    if (ziel == null || !mounted) return;
    if (_verschluesselt &&
        !await ensureBackupKeyAvailable(context, widget.library)) {
      return;
    }
    if (!mounted) return;
    final root = ziel.unterordner(BackupService.backupFolderName);
    await _arbeite(() async {
      await (await _dienst()).pruefeSicherungsziel(ziel);
      await for (final f in widget.library.runManualBackup(
        ziel.path,
        encrypt: _verschluesselt,
      )) {
        _fort(f.done, f.total);
        if (_abbruch) break;
      }
      if (mounted) {
        setState(() {
          _sicherungsort = root;
          _plan = null;
          _unabhaengig = false;
          _meldung = _abbruch ? t.schutzAbgebrochen : t.schutzSicherungAngelegt;
        });
      }
    });
  }

  Future<BackupAuswahl?> _sicherung() async {
    final ort = _sicherungsort!;
    final real = ort.token.isEmpty
        ? ort.path
        : await FolderAccess.forCurrentPlatform().resolveRoot(
            path: ort.path,
            token: ort.token,
          );
    if (real == null) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.ziel);
    }
    String? pass;
    try {
      if (await File(p.join(real, 'vault.key')).exists()) {
        if (!mounted) return null;
        pass = await showEnterPassphraseDialog(
          context,
          title: AppTexte.of(context).backupAuswahlTitel,
        );
        if (pass == null) return null;
      }
      return await BackupAuswahl.oeffne(
        real,
        schemaVersion: widget.library.db.schemaVersion,
        passphrase: pass,
      );
    } finally {
      pass = null;
    }
  }

  Future<void> _pruefen() async {
    await _arbeite(() async {
      final sicherung = await _sicherung();
      if (sicherung == null || !mounted) return;
      final plan = await (await _dienst()).pruefe(
        _originalort!,
        _sicherungsort!,
        sicherung,
        unabhaengigkeitBestaetigt: _unabhaengig,
        abgebrochen: () => _abbruch || !mounted,
        fortschritt: _fort,
      );
      if (mounted) setState(() => _plan = plan);
    });
  }

  Future<void> _freigeben() async {
    final plan = _plan!, t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.schutzFreigeben),
        content: Text(
          t.schutzFreigebenFrage(
            plan.kandidaten.length,
            groessentext(plan.bytes),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.schutzFreigeben),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    await _arbeite(() async {
      final r = await (await _dienst()).freigeben(
        plan,
        bestaetigt: true,
        abgebrochen: () => _abbruch || !mounted,
        fortschritt: _fort,
      );
      if (mounted) {
        setState(() {
          _plan = null;
          _meldung = t.schutzFreigegeben(r.dateien, groessentext(r.bytes));
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final erlaubt =
        !widget.library.verbunden && widget.library.paths.referenzen != null;
    return PopScope(
      canPop: !_arbeitet,
      child: Scaffold(
        appBar: AppBar(title: Text(t.schutzTitel)),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(t.schutzText),
            if (!erlaubt) Text(t.schutzNurLokal),
            const SizedBox(height: 16),
            Text(
              t.schutzSchrittOriginal,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_originalort != null) SelectableText(_originalort!.path),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: erlaubt && !_arbeitet ? () => _waehle(true) : null,
                  child: Text(t.schutzOriginalort),
                ),
                FilledButton(
                  onPressed: erlaubt && !_arbeitet && _originalort != null
                      ? _kopieren
                      : null,
                  child: Text(t.schutzKopienAnlegen),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              t.schutzSchrittSicherung,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_sicherungsort != null) SelectableText(_sicherungsort!.path),
            SwitchListTile(
              value: _verschluesselt,
              onChanged: _arbeitet
                  ? null
                  : (v) => setState(() => _verschluesselt = v),
              title: Text(t.schutzVerschluesselt),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: erlaubt && !_arbeitet
                      ? () => _waehle(false)
                      : null,
                  child: Text(t.schutzSicherungsort),
                ),
                FilledButton(
                  onPressed: erlaubt && !_arbeitet ? _sichern : null,
                  child: Text(t.schutzSicherungErstellen),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              t.schutzSchrittPruefen,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            CheckboxListTile(
              value: _unabhaengig,
              onChanged: _arbeitet
                  ? null
                  : (v) => setState(() {
                      _unabhaengig = v ?? false;
                      _plan = null;
                    }),
              title: Text(t.schutzUnabhaengig),
            ),
            Text(t.speicherinventarLaufwerkHinweis),
            FilledButton(
              onPressed:
                  erlaubt &&
                      !_arbeitet &&
                      _originalort != null &&
                      _sicherungsort != null &&
                      _unabhaengig
                  ? _pruefen
                  : null,
              child: Text(t.schutzPruefen),
            ),
            if (_plan case final plan?) ...[
              const SizedBox(height: 16),
              Text(
                t.schutzPlan(
                  plan.kandidaten.length,
                  plan.geprueft,
                  groessentext(plan.bytes),
                ),
              ),
              Text(t.schutzNachFreigabe),
              FilledButton(
                onPressed:
                    !_arbeitet && _unabhaengig && plan.kandidaten.isNotEmpty
                    ? _freigeben
                    : null,
                child: Text(t.schutzFreigeben),
              ),
            ],
            if (_arbeitet) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _fortschritt.$2 > 0
                    ? (_fortschritt.$1 / _fortschritt.$2).clamp(0, 1)
                    : null,
              ),
              Text('${_fortschritt.$1} / ${_fortschritt.$2}'),
              TextButton(
                onPressed: _abbruch
                    ? null
                    : () => setState(() => _abbruch = true),
                child: Text(
                  _abbruch
                      ? t.speicherkarteAbbruchNachDatei
                      : t.ausbauAbbrechen,
                ),
              ),
            ],
            if (_meldung != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Semantics(liveRegion: true, child: Text(_meldung!)),
              ),
          ],
        ),
      ),
    );
  }
}
