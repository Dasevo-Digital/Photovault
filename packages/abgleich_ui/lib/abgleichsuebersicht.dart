import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/abgleich.dart';

import 'l10n/sync_texte.dart';

/// Dieselben Entscheidungen am Rechner und auf dem Telefon.
class Abgleichsuebersicht extends StatelessWidget {
  const Abgleichsuebersicht({super.key, required this.abgleich});
  final Abgleich abgleich;

  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    delegates: const [SyncTexte.delegate],
    child: _Uebersicht(abgleich),
  );
}

class _Uebersicht extends StatefulWidget {
  const _Uebersicht(this.abgleich);
  final Abgleich abgleich;
  @override
  State<_Uebersicht> createState() => _UebersichtState();
}

class _UebersichtState extends State<_Uebersicht> {
  StreamSubscription<Abgleichszustand>? _abo;
  List<Abgleichsfall> _faelle = [];
  bool _arbeitet = false, _fehler = false, _mehr = false;
  int _limit = 100;
  int _lauf = 0;

  @override
  void initState() {
    super.initState();
    _abo = widget.abgleich.zustand.listen((_) => _lade());
    _lade();
  }

  @override
  void dispose() {
    _lauf++;
    _abo?.cancel();
    super.dispose();
  }

  Future<void> _lade() async {
    final lauf = ++_lauf;
    try {
      final faelle = <Abgleichsfall>[];
      for (var offset = 0; offset < _limit; offset += 100) {
        final seite = await widget.abgleich.faelle(limit: 101, offset: offset);
        faelle.addAll(seite.take(100));
        if (seite.length <= 100) break;
        if (offset + 100 == _limit) faelle.add(seite.last);
      }
      if (!mounted || lauf != _lauf) return;
      setState(() {
        _faelle = faelle.take(_limit).toList();
        _mehr = faelle.length > _limit;
      });
    } catch (_) {
      if (mounted && lauf == _lauf) setState(() => _fehler = true);
    }
  }

  Future<void> _abgleichen() async {
    setState(() {
      _arbeitet = true;
      _fehler = false;
    });
    try {
      await widget.abgleich.sende();
      await widget.abgleich.empfange();
    } catch (_) {
      if (mounted) setState(() => _fehler = true);
    } finally {
      await _lade();
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _oeffne(Abgleichsfall fall) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Localizations.override(
          context: context,
          delegates: const [SyncTexte.delegate],
          child: _Entscheidung(widget.abgleich, fall),
        ),
      ),
    );
    await _lade();
  }

  @override
  Widget build(BuildContext context) {
    final t = SyncTexte.of(context);
    final z = widget.abgleich.zustandJetzt;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.titel),
        actions: [
          IconButton(
            tooltip: t.aktualisieren,
            onPressed: _arbeitet ? null : _abgleichen,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_arbeitet) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(t.anzahl(z.ausstehend, z.faelle)),
          ),
          if (z.serverOhneKonfliktpruefung)
            Padding(padding: const EdgeInsets.all(16), child: Text(t.alt)),
          if (_fehler)
            Padding(padding: const EdgeInsets.all(16), child: Text(t.fehler)),
          Expanded(
            child: _faelle.isEmpty
                ? Center(child: Text(t.leer))
                : ListView.builder(
                    itemCount: _faelle.length + (_mehr ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _faelle.length) {
                        return TextButton(
                          onPressed: () {
                            setState(() => _limit += 100);
                            _lade();
                          },
                          child: Text(t.mehr),
                        );
                      }
                      final f = _faelle[i];
                      return ListTile(
                        leading: Icon(
                          f.ausstehend
                              ? Icons.schedule
                              : Icons.sync_problem_outlined,
                        ),
                        title: Text(_aktion(t, f)),
                        subtitle: Text(
                          '${_status(t, f)}\n${t.fotos(f.fotoIds.length)} · ${DateFormat.yMd(Localizations.localeOf(context).toString()).add_Hm().format(f.am)}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _oeffne(f),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

String _aktion(SyncTexte t, Abgleichsfall f) => switch (f.befehl['art']) {
  'favoritSetzen' => t.favorit,
  'bewertungSetzen' => t.bewertung,
  'farbmarkeSetzen' => t.farbe,
  'beschreibungSetzen' => t.beschreibung,
  final String s when s.toLowerCase().contains('album') => t.album,
  final String s when s.toLowerCase().contains('tag') => t.tag,
  final String s
      when s.toLowerCase().contains('person') ||
          s.toLowerCase().contains('gesicht') =>
    t.person,
  _ => t.unbekannt,
};

String _status(SyncTexte t, Abgleichsfall f) => !f.lesbar
    ? t.unlesbar
    : f.ausstehend
    ? t.wartet
    : f.grund == 'pv_sync_auswahl'
    ? t.zuGross
    : f.grund == 'pv_sync_konflikt'
    ? t.konflikt
    : t.abgelehnt;

class _Entscheidung extends StatefulWidget {
  const _Entscheidung(this.abgleich, this.fall);
  final Abgleich abgleich;
  final Abgleichsfall fall;
  @override
  State<_Entscheidung> createState() => _EntscheidungState();
}

class _EntscheidungState extends State<_Entscheidung> {
  Abgleichsvergleich? _vergleich;
  List<({String aufnahme, String feld, String server, String eigen})> _werte =
      [];
  bool _arbeitet = true, _fehler = false, _geaendert = false, _komplex = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vergleich == null && !_fehler) _lade();
  }

  Future<void> _lade() async {
    try {
      final v = await widget.abgleich.vergleiche(widget.fall);
      if (!mounted) return;
      final t = SyncTexte.of(context);
      final werte =
          <({String aufnahme, String feld, String server, String eigen})>[];
      var komplex = false;
      // Nie Werte oder Namen gesperrter Aufnahmen aufbauen, auch nicht
      // aus der verschlüsselten ursprünglichen Absicht.
      if (!v.geschuetzt) {
        details:
        for (var i = 0; i < v.fall.basis.length; i++) {
          final b = v.fall.basis[i];
          for (final s in b.spalten) {
            if (werte.length >= 200) {
              komplex = true;
              break details;
            }
            if (s == 'is_locked' || s == 'is_trashed' || s == 'id') continue;
            final label = _feld(t, s);
            if (label == null) {
              komplex = true;
              continue;
            }
            final eigen = await _wert(t, s, b.gewollt?[s]);
            final server = await _wert(t, s, v.serverwerte[i]?[s]);
            final zeile = (
              aufnahme: b.fotos
                  .map((id) => v.fotobezeichnungen[id])
                  .whereType<String>()
                  .join(', '),
              feld: label,
              server: server,
              eigen: eigen,
            );
            if (!werte.contains(zeile) && werte.length < 200) werte.add(zeile);
            if (werte.length == 200) komplex = true;
          }
        }
      }
      if (mounted) {
        setState(() {
          _vergleich = v;
          _werte = werte;
          _komplex = komplex;
          _arbeitet = false;
          _fehler = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _arbeitet = false;
          _fehler = true;
        });
      }
    }
  }

  Future<String> _wert(SyncTexte t, String feld, Object? wert) async {
    if (wert == null || wert == '') return t.kein;
    if (feld == 'is_favorite' || wert is bool) {
      return wert == 1 || wert == true ? t.ja : t.nein;
    }
    final db = widget.abgleich.db;
    if (wert is String) {
      if (feld == 'album_id' || feld == 'target_album_id') {
        return (await (db.select(
              db.albums,
            )..where((t) => t.id.equals(wert))).getSingleOrNull())?.name ??
            t.kein;
      }
      if (feld == 'tag_id') {
        return (await (db.select(
              db.tags,
            )..where((t) => t.id.equals(wert))).getSingleOrNull())?.name ??
            t.kein;
      }
      if (feld == 'person_id') {
        return (await (db.select(
              db.people,
            )..where((t) => t.id.equals(wert))).getSingleOrNull())?.name ??
            t.kein;
      }
      return wert.length > 500 ? '${wert.substring(0, 500)}…' : wert;
    }
    if (wert is num) {
      if (feld == 'file_created_at') {
        return DateFormat.yMd(t.localeName).add_Hm().format(
          DateTime.fromMillisecondsSinceEpoch(wert.toInt() * 1000),
        );
      }
      return '$wert';
    }
    return t.komplex;
  }

  Future<void> _entscheide(bool eigen) async {
    final t = SyncTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(eigen ? t.anwenden : t.behalten),
        content: Text(t.entscheidung),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.bestaetigen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    setState(() {
      _arbeitet = true;
      _fehler = false;
      _geaendert = false;
    });
    try {
      if (eigen) {
        await widget.abgleich.erneutAnwenden(_vergleich!);
      } else {
        await widget.abgleich.behalteServerstand(widget.fall);
      }
      if (mounted) Navigator.pop(context);
    } on AbgleichsstandGeaendert {
      if (mounted) setState(() => _geaendert = true);
      await _lade();
    } catch (_) {
      if (mounted) {
        setState(() {
          _arbeitet = false;
          _fehler = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SyncTexte.of(context), v = _vergleich;
    return Scaffold(
      appBar: AppBar(title: Text(_aktion(t, widget.fall))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _status(t, widget.fall),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_arbeitet) const LinearProgressIndicator(),
          if (_geaendert) Text(t.geaendert),
          if (_fehler) ...[
            Text(t.fehler),
            TextButton(
              onPressed: _arbeitet ? null : _lade,
              child: Text(t.aktualisieren),
            ),
          ],
          if (v != null) ...[
            Text(t.fotos(widget.fall.fotoIds.length)),
            if (v.geschuetzt)
              Text(t.geschuetzt)
            else ...[
              for (final name in v.fotonamen) Text(name),
              if (v.entfernt) Text(t.entfernt),
              if (widget.fall.ausstehend)
                Text(t.wartetText)
              else
                Text(
                  widget.fall.grund == 'pv_sync_konflikt'
                      ? t.grundKonflikt
                      : t.grundAbgelehnt,
                ),
              for (final w in _werte)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (w.aufnahme.isNotEmpty) Text(w.aufnahme),
                        Text(
                          w.feld,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (!widget.fall.ausstehend)
                          SelectableText('${t.server}: ${w.server}'),
                        SelectableText('${t.eigen}: ${w.eigen}'),
                      ],
                    ),
                  ),
                ),
              if (_komplex) Text(t.komplex),
            ],
            if (!widget.fall.ausstehend) ...[
              const SizedBox(height: 16),
              Text(t.entscheidung),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _arbeitet ? null : () => _entscheide(false),
                child: Text(t.behalten),
              ),
              FilledButton(
                onPressed:
                    _arbeitet ||
                        !widget.fall.lesbar ||
                        v.geschuetzt ||
                        v.entfernt
                    ? null
                    : () => _entscheide(true),
                child: Text(t.anwenden),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

String? _feld(SyncTexte t, String feld) => switch (feld) {
  'is_favorite' => t.wertFavorit,
  'rating' => t.wertBewertung,
  'color_label' => t.wertFarbe,
  'description' => t.wertBeschreibung,
  'name' || 'original_file_name' => t.wertName,
  'file_created_at' => t.wertDatum,
  'album_id' || 'target_album_id' => t.wertAlbum,
  'tag_id' => t.wertTag,
  'person_id' => t.wertPerson,
  'country' || 'state' || 'city' || 'location' => t.wertOrt,
  'latitude' => t.wertBreite,
  'longitude' => t.wertLaenge,
  _ => null,
};
