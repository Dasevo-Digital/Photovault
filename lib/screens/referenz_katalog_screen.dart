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
              Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(e.value),
                  trailing: IconButton(
                    tooltip: t.katalogNeuZuordnen,
                    onPressed: erlaubt && !_arbeitet
                        ? () => _neuZuordnen(e.key)
                        : null,
                    icon: const Icon(Icons.drive_file_move_outline),
                  ),
                ),
              ),
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
