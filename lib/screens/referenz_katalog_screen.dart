import 'package:intl/intl.dart';
import '../services/referenz_abgleich.dart';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kern/services/original_referenzen.dart';
import 'package:kern/services/referenz_katalog.dart';

import '../l10n/app_localizations.dart';
import '../services/platform/folder_access.dart';
import '../state/library_state.dart';
import '../widgets/einfuegbares_menue.dart';

class ReferenzKatalogScreen extends StatefulWidget {
  const ReferenzKatalogScreen({super.key, required this.library});
  final LibraryState library;
  @override
  State<ReferenzKatalogScreen> createState() => _ReferenzKatalogScreenState();
}

class _ReferenzKatalogScreenState extends State<ReferenzKatalogScreen> {
  final _ausschluesse = TextEditingController(
    text: '**/.git/**\n**/@eaDir/**\n**/.Trash/**',
  );
  bool _arbeitet = false, _abbruch = false;
  Katalogfortschritt? _fortschritt;
  String? _meldung;
  ReferenzKatalog get _dienst => ReferenzKatalog(
    widget.library.db,
    widget.library.paths,
    widget.library.importService,
  );
  @override
  void dispose() {
    _abbruch = true;
    _ausschluesse.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final t = AppTexte.of(context);
    final ort = await FolderAccess.forCurrentPlatform().pickFolder(
      message: t.katalogOrdnerWaehlen,
    );
    if (ort == null || !mounted) return;
    setState(() {
      _arbeitet = true;
      _abbruch = false;
      _meldung = null;
      _fortschritt = null;
    });
    try {
      final refs = widget.library.paths.referenzen!;
      final id = await refs.ordnerHinzufuegen(Directory(ort.path));
      await refs.merkeZugriff(id, ort.token);
      await for (final s in _dienst.scanne(
        Directory(ort.path),
        ausschliessen: _ausschluesse.text.split('\n'),
        abgebrochen: () => _abbruch,
      )) {
        if (mounted) setState(() => _fortschritt = s);
      }
    } on ReferenzAbbruch {
      if (mounted) setState(() => _meldung = t.katalogAbgebrochen);
    } on Object {
      if (mounted) setState(() => _meldung = t.katalogFehler);
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _neuZuordnen(String id) async {
    final t = AppTexte.of(context);
    final neu = await FolderAccess.forCurrentPlatform().pickFolder(
      message: t.katalogNeuZuordnen,
    );
    if (neu == null || !mounted) return;
    setState(() {
      _arbeitet = true;
      _abbruch = false;
      _meldung = null;
    });
    try {
      await widget.library.paths.referenzen!.ordnerNeuZuordnen(
        id,
        Directory(neu.path),
        abgebrochen: () => _abbruch,
      );
      await widget.library.paths.referenzen!.merkeZugriff(id, neu.token);
      await widget.library.referenzAbgleich?.bestaetigeNeueZuordnung(id);
      if (mounted) setState(() => _meldung = t.katalogGeprueft);
    } on Object {
      if (mounted) setState(() => _meldung = t.katalogFehler);
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _pruefeReferenzen(String id) async {
    final dienst = widget.library.referenzAbgleich;
    if (dienst == null) return;
    setState(() {
      _arbeitet = true;
      _abbruch = false;
      _meldung = null;
    });
    try {
      await dienst.pruefe(
        id,
        ausschliessen: _ausschluesse.text.split('\n'),
        abgebrochen: () => _abbruch || !mounted,
      );
    } on ReferenzAbbruch {
      if (mounted) {
        setState(() => _meldung = AppTexte.of(context).katalogAbgebrochen);
      }
    } on Object {
      if (mounted) {
        setState(() => _meldung = AppTexte.of(context).katalogFehler);
      }
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _planeReferenzen(String id, int stunden) async {
    try {
      await widget.library.referenzAbgleich?.plane(
        id,
        stunden == 0 ? null : stunden,
        ausschliessen: _ausschluesse.text.split('\n'),
      );
      if (mounted) setState(() {});
    } on Object {
      if (mounted) {
        setState(() => _meldung = AppTexte.of(context).katalogFehler);
      }
    }
  }

  Future<void> _uebernehmePlan(ReferenzPruefplan plan) async {
    final t = AppTexte.of(context);
    final n = plan.eintraege
        .where((e) => e.art == ReferenzAenderung.neu)
        .length;
    final ja = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.katalogAbgleichUebernehmen),
        content: Text(t.katalogAbgleichFrage(n)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.allgUebernehmen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    setState(() {
      _arbeitet = true;
      _abbruch = false;
    });
    try {
      await widget.library.referenzAbgleich?.uebernehmeNeue(
        plan,
        abgebrochen: () => _abbruch || !mounted,
      );
    } on Object {
      if (mounted) setState(() => _meldung = t.katalogFehler);
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Widget _referenzOrdner(String id, String pfad, bool erlaubt) {
    final t = AppTexte.of(context);
    final dienst = widget.library.referenzAbgleich;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<void>(
          future: dienst?.laden(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text(t.katalogFehler);
            final plan = dienst?.plaene[id];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(pfad),
                if (dienst?.intervalle[id] case final stunden?)
                  Text(t.katalogAbgleichIntervall(stunden)),
                if (plan != null) ...[
                  Text(
                    t.katalogAbgleichStand(
                      DateFormat.yMd(
                        Localizations.localeOf(context).toString(),
                      ).add_Hm().format(plan.am.toLocal()),
                    ),
                  ),
                  if (!plan.erreichbar)
                    Text(t.speicherinventarNichtErreichbar)
                  else if (!plan.vollstaendig)
                    Text(t.katalogAbgleichUnvollstaendig)
                  else ...[
                    Text(
                      t.katalogAbgleichZahlen(
                        plan.eintraege
                            .where((e) => e.art == ReferenzAenderung.neu)
                            .length,
                        plan.eintraege
                            .where((e) => e.art == ReferenzAenderung.geaendert)
                            .length,
                        plan.eintraege
                            .where((e) => e.art == ReferenzAenderung.fehlt)
                            .length,
                      ),
                    ),
                    Text(t.katalogAbgleichKonflikte),
                    if (plan.eintraege.isNotEmpty)
                      ExpansionTile(
                        title: Text(t.katalogAbgleichVorschau),
                        children: [
                          for (final e in plan.eintraege.take(100))
                            ListTile(
                              title: Text(e.relativ),
                              subtitle: Text(switch (e.art) {
                                ReferenzAenderung.neu => t.katalogNeu,
                                ReferenzAenderung.geaendert =>
                                  t.katalogAbgleichGeaendert,
                                ReferenzAenderung.fehlt => t.speicherkarteFehlt,
                              }),
                            ),
                          if (plan.eintraege.length > 100)
                            Text(t.katalogAbgleichMehr),
                        ],
                      ),
                  ],
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: erlaubt && !_arbeitet
                          ? () => _pruefeReferenzen(id)
                          : null,
                      child: Text(t.katalogAbgleichPruefen),
                    ),
                    PopupMenuButton<int>(
                      enabled: erlaubt && !_arbeitet,
                      tooltip: t.katalogAbgleichPlanen,
                      onSelected: (v) => _planeReferenzen(id, v),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 0,
                          child: Text(t.katalogAbgleichAus),
                        ),
                        for (final stunden in [1, 24, 168])
                          PopupMenuItem(
                            value: stunden,
                            child: Text(t.katalogAbgleichIntervall(stunden)),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(t.katalogAbgleichPlanen),
                      ),
                    ),
                    if (plan != null &&
                        plan.erreichbar &&
                        plan.vollstaendig &&
                        plan.eintraege.any(
                          (e) => e.art == ReferenzAenderung.neu,
                        ))
                      FilledButton(
                        onPressed: erlaubt && !_arbeitet
                            ? () => _uebernehmePlan(plan)
                            : null,
                        child: Text(t.katalogAbgleichUebernehmen),
                      ),
                    TextButton.icon(
                      onPressed: erlaubt && !_arbeitet
                          ? () => _neuZuordnen(id)
                          : null,
                      icon: const Icon(Icons.drive_file_move_outline),
                      label: Text(t.katalogNeuZuordnen),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) => _inhalt(context),
  );

  Widget _inhalt(BuildContext context) {
    final t = AppTexte.of(context);
    final refs = widget.library.paths.referenzen;
    final erlaubt = !widget.library.verbunden && refs != null;
    return PopScope(
      canPop: !_arbeitet,
      child: Scaffold(
        appBar: AppBar(title: Text(t.katalogTitel)),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(t.katalogText),
            Text(t.katalogGrenzen),
            Text(t.katalogAbgleichText),
            if (widget.library.verbunden)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(t.katalogNurLokal),
              ),
            if (widget.library.paths.referenzenLadefehler)
              Text(t.katalogNichtLesbar),
            const SizedBox(height: 16),
            TextField(
              controller: _ausschluesse,
              enabled: !_arbeitet,
              minLines: 3,
              maxLines: 6,
              contextMenuBuilder: einfuegbaresMenue,
              decoration: InputDecoration(
                labelText: t.katalogAusschluesse,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: erlaubt && !_arbeitet ? _scan : null,
                  icon: const Icon(Icons.folder_open),
                  label: Text(t.katalogOrdnerHinzufuegen),
                ),
                OutlinedButton.icon(
                  onPressed: _arbeitet
                      ? null
                      : () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ReferenzDateienScreen(
                                library: widget.library,
                              ),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(t.katalogDateien),
                ),
                if (_arbeitet)
                  TextButton(
                    onPressed: () => setState(() => _abbruch = true),
                    child: Text(t.ausbauAbbrechen),
                  ),
              ],
            ),
            if (_arbeitet)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
            if (_fortschritt case final s?) ...[
              const SizedBox(height: 16),
              Text(
                '${t.katalogGelesen}: ${s.gelesen} · ${t.katalogNeu}: ${s.neu} · ${t.katalogDoppelt}: ${s.doppelt} · ${t.katalogFehlerzahl}: ${s.fehler}',
              ),
              Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            if (_meldung != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Semantics(liveRegion: true, child: Text(_meldung!)),
              ),
            const SizedBox(height: 24),
            if (refs?.ordner.isEmpty ?? true) Text(t.katalogLeer),
            for (final e
                in refs?.ordner.entries ?? const <MapEntry<String, String>>[])
              _referenzOrdner(e.key, e.value, erlaubt),
          ],
        ),
      ),
    );
  }
}

class ReferenzDateienScreen extends StatefulWidget {
  const ReferenzDateienScreen({super.key, required this.library});
  final LibraryState library;
  @override
  State<ReferenzDateienScreen> createState() => _ReferenzDateienScreenState();
}

class _ReferenzDateienScreenState extends State<ReferenzDateienScreen> {
  int _seite = 0;
  bool _arbeitet = false;
  String? _meldung;
  late Future<List<Map<String, Object?>>> _daten = _laden();
  Future<List<Map<String, Object?>>> _laden() async => [
    for (final r
        in await widget.library.db
            .customSelect(
              "SELECT id, original_file_name, relative_path FROM assets WHERE relative_path LIKE 'referenzen/%' AND is_locked = 0 AND is_trashed = 0 ORDER BY id LIMIT 101 OFFSET ?",
              variables: [Variable.withInt(_seite * 100)],
            )
            .get())
      r.data,
  ];
  void _neu() {
    setState(() => _daten = _laden());
  }

  Future<void> _uebernehmen(String id) async {
    final t = AppTexte.of(context);
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    try {
      await ReferenzKatalog(
        widget.library.db,
        widget.library.paths,
        widget.library.importService,
      ).uebernehmen(id);
    } on Object {
      if (mounted) setState(() => _meldung = t.katalogFehler);
    } finally {
      if (mounted) {
        setState(() => _arbeitet = false);
        _neu();
      }
    }
  }

  Future<void> _zuordnen(String pfad) async {
    final t = AppTexte.of(context);
    final ordner = await FolderAccess.forCurrentPlatform().pickFolder(
      message: t.katalogOrdnerWaehlen,
    );
    if (ordner == null || !mounted) return;
    final file = await FilePicker.pickFile(initialDirectory: ordner.path);
    if (file?.path == null || !mounted) return;
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    try {
      final refs = widget.library.paths.referenzen!;
      final id = await refs.ordnerHinzufuegen(Directory(ordner.path));
      await refs.merkeZugriff(id, ordner.token);
      await refs.dateiNeuZuordnen(pfad, id, File(file!.path!));
      if (mounted) setState(() => _meldung = t.katalogGeprueft);
    } on Object {
      if (mounted) setState(() => _meldung = t.katalogFehler);
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return PopScope(
      canPop: !_arbeitet,
      child: Scaffold(
        appBar: AppBar(title: Text(t.katalogDateien)),
        body: Column(
          children: [
            if (_arbeitet) const LinearProgressIndicator(),
            if (_meldung != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_meldung!),
              ),
            Expanded(
              child: FutureBuilder(
                future: _daten,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text(t.katalogFehler));
                  }
                  final rows = snapshot.data;
                  if (rows == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView.builder(
                    itemCount: rows.length.clamp(0, 100),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final pfad = r['relative_path']! as String;
                      final zuordnung =
                          widget.library.paths.referenzen?.dateien[pfad];
                      return ListTile(
                        title: Text(r['original_file_name']! as String),
                        subtitle: Text(
                          zuordnung?.relativ ?? t.katalogNichtLesbar,
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: t.katalogOriginalZuordnen,
                              onPressed: _arbeitet
                                  ? null
                                  : () => _zuordnen(pfad),
                              icon: const Icon(Icons.find_in_page_outlined),
                            ),
                            IconButton(
                              tooltip: t.katalogVerwaltet,
                              onPressed: _arbeitet
                                  ? null
                                  : () => _uebernehmen(r['id']! as String),
                              icon: const Icon(Icons.file_download_outlined),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: !_arbeitet && _seite > 0
                      ? () {
                          _seite--;
                          _neu();
                        }
                      : null,
                  child: Text(t.ausbauZurueck),
                ),
                Text('${_seite + 1}'),
                TextButton(
                  onPressed: !_arbeitet
                      ? () async {
                          final r = await _daten;
                          if (r.length > 100 && mounted) {
                            _seite++;
                            _neu();
                          }
                        }
                      : null,
                  child: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
