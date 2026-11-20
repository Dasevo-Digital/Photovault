import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';

import '../l10n/app_localizations.dart';
import '../services/arbeitsvorschauen.dart';
import '../widgets/namens_dialog.dart';
import '../widgets/selection_action_bar.dart' show confirmDialog;
import 'develop_screen.dart';

class ArbeitsvorschauenScreen extends StatefulWidget {
  const ArbeitsvorschauenScreen({
    super.key,
    required this.db,
    required this.paths,
  });
  final AppDatabase db;
  final StoragePaths paths;
  @override
  State<ArbeitsvorschauenScreen> createState() =>
      _ArbeitsvorschauenScreenState();
}

class _ArbeitsvorschauenScreenState extends State<ArbeitsvorschauenScreen> {
  late final _dienst = Arbeitsvorschauen(widget.db, widget.paths);
  late Future<List<ArbeitsvorschauInfo>> _daten = _dienst.liste();
  bool _arbeitet = false;
  String? _meldung;
  Future<void> _bearbeiten(ArbeitsvorschauInfo info) async {
    final t = AppTexte.of(context);
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    Arbeitsbibliothek? arbeit;
    try {
      arbeit = await _dienst.oeffne(info.asset.id);
      if (!mounted) return;
      final gespeichert = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DevelopScreen(
            asset: arbeit!.asset,
            db: arbeit.db,
            paths: arbeit.paths,
            arbeitsvorschau: true,
            farbpfade: widget.paths,
          ),
        ),
      );
      if (gespeichert == true) await _dienst.merkeEntwurf(info.asset.id);
    } on Object {
      if (mounted) setState(() => _meldung = t.arbeitskopienFehler);
    } finally {
      await arbeit?.schliesse();
      if (mounted) {
        setState(() {
          _arbeitet = false;
          _daten = _dienst.liste();
        });
      }
    }
  }

  Future<void> _anwenden(ArbeitsvorschauInfo info) async {
    final t = AppTexte.of(context);
    final name = await frageNamen(
      context,
      titel: t.arbeitskopienAnwenden,
      feldbeschriftung: t.ausbauName,
      vorgabe: t.arbeitskopienEntwurf,
    );
    if (name == null || !mounted) return;
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    try {
      try {
        await _dienst.anwenden(info.asset.id, name);
      } on OfflineKonflikt catch (e) {
        if (!mounted) return;
        if (e.originalGeaendert ||
            !await confirmDialog(
              context,
              t.arbeitskopienKonflikt,
              t.arbeitskopienAlsVariante,
            )) {
          setState(() => _meldung = t.arbeitskopienKonflikt);
          return;
        }
        await _dienst.anwenden(info.asset.id, name, nurNeueVariante: true);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on OfflineKonflikt {
      if (mounted) setState(() => _meldung = t.arbeitskopienKonflikt);
    } on Object {
      if (mounted) setState(() => _meldung = t.arbeitskopienFehler);
    } finally {
      if (mounted) {
        setState(() {
          _arbeitet = false;
          _daten = _dienst.liste();
        });
      }
    }
  }

  Future<void> _entfernen(ArbeitsvorschauInfo info) async {
    final t = AppTexte.of(context);
    if (!await confirmDialog(
      context,
      t.ausbauLoeschen,
      t.arbeitskopienLoeschenFrage,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _arbeitet = true);
    try {
      await _dienst.entfernen(info.asset.id);
    } on Object {
      if (mounted) setState(() => _meldung = t.arbeitskopienFehler);
    } finally {
      if (mounted) {
        setState(() {
          _arbeitet = false;
          _daten = _dienst.liste();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return PopScope(
      canPop: !_arbeitet,
      child: Scaffold(
        appBar: AppBar(title: Text(t.arbeitskopienTitel)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t.arbeitskopienText),
            ),
            if (_arbeitet) const LinearProgressIndicator(),
            if (_meldung != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Semantics(liveRegion: true, child: Text(_meldung!)),
              ),
            Expanded(
              child: FutureBuilder(
                future: _daten,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text(t.arbeitskopienFehler));
                  }
                  final infos = snapshot.data;
                  if (infos == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (infos.isEmpty) {
                    return Center(child: Text(t.arbeitskopienLeer));
                  }
                  return ListView.builder(
                    itemCount: infos.length,
                    itemBuilder: (context, i) {
                      final info = infos[i];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.cloud_off_outlined),
                          title: Text(info.asset.originalFileName),
                          subtitle: Text(
                            info.entwurf
                                ? t.arbeitskopienStatus
                                : t.arbeitskopienBereit,
                          ),
                          onTap: _arbeitet ? null : () => _bearbeiten(info),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: t.arbeitskopienBearbeiten,
                                onPressed: _arbeitet
                                    ? null
                                    : () => _bearbeiten(info),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: t.arbeitskopienAnwenden,
                                onPressed: _arbeitet || !info.entwurf
                                    ? null
                                    : () => _anwenden(info),
                                icon: const Icon(Icons.cloud_upload_outlined),
                              ),
                              IconButton(
                                tooltip: t.ausbauLoeschen,
                                onPressed: _arbeitet
                                    ? null
                                    : () => _entfernen(info),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
