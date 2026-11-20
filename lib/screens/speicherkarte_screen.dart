import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_auswahl.dart';
import '../l10n/app_localizations.dart';
import '../services/importquittungen.dart' show Kopienbefund;
import '../services/platform/folder_access.dart';
import '../services/speicherkarte.dart';
import '../state/library_state.dart';
import '../widgets/bibliotheksbild.dart';
import '../widgets/pin_dialogs.dart';
import '../widgets/speicherkarte_grafik.dart';
import 'arbeitsvorschauen_screen.dart';
import 'asset_viewer_screen.dart';
import 'referenz_katalog_screen.dart';

class SpeicherkarteScreen extends StatefulWidget {
  const SpeicherkarteScreen({super.key, required this.library});
  final LibraryState library;
  @override
  State<SpeicherkarteScreen> createState() => _SpeicherkarteScreenState();
}

class _SpeicherkarteScreenState extends State<SpeicherkarteScreen> {
  late final _dienst = SpeicherkarteDienst.fuer(
    widget.library.db,
    widget.library.paths,
  );
  late Future<SpeicherkarteStand> _stand = _laden();
  final _fortschritt = ValueNotifier<(int, int)>((0, 0));
  bool _prueft = false, _abbruch = false;
  String? _meldung;
  Future<SpeicherkarteStand> _laden() async =>
      (await _dienst).laden(abgebrochen: () => !mounted);
  void _neu() => setState(() => _stand = _laden());
  @override
  void dispose() {
    _abbruch = true;
    _fortschritt.dispose();
    super.dispose();
  }

  Future<void> _pruefen() async {
    final t = AppTexte.of(context);
    final ziel = await FolderAccess.forCurrentPlatform().pickFolder(
      message: t.speicherkartePruefziel,
    );
    if (ziel == null || !mounted) return;
    String? passphrase;
    setState(() {
      _prueft = true;
      _abbruch = false;
      _meldung = null;
    });
    try {
      final stand = await _stand;
      final hashes = {
        for (final f in stand.fotos.values)
          if (!f.papierkorb) f.sha256,
      };
      if (hashes.isEmpty) {
        if (mounted) {
          setState(() => _meldung = t.speicherkarteKeineAktuellenOriginale);
        }
        return;
      }
      if (await File('${ziel.path}/vault.key').exists()) {
        if (!mounted) return;
        passphrase = await showEnterPassphraseDialog(
          context,
          title: t.backupAuswahlTitel,
        );
        if (passphrase == null) return;
      }
      final katalog = await BackupAuswahl.oeffne(
        ziel.path,
        schemaVersion: widget.library.db.schemaVersion,
        passphrase: passphrase,
        nurPruefsummen: hashes,
      );
      passphrase = null;
      await (await _dienst).pruefe(
        katalog,
        ziel,
        hashes,
        abgebrochen: () => _abbruch || !mounted,
        fortschritt: (n, g) {
          if (mounted) _fortschritt.value = (n, g);
        },
      );
      if (mounted) _neu();
    } on Object {
      if (mounted) setState(() => _meldung = t.speicherkarteFehler);
    } finally {
      passphrase = null;
      if (mounted) setState(() => _prueft = false);
    }
  }

  Future<void> _auswahl(SpeicherkarteStand stand, Speichergruppe g) async {
    if (g == Speichergruppe.arbeitsvorschauen) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArbeitsvorschauenScreen(
            db: widget.library.db,
            paths: widget.library.paths,
          ),
        ),
      );
    } else {
      await _fotos(
        stand.gruppen[g]!.toList()..sort(),
        speichergruppenName(AppTexte.of(context), g),
        papierkorb: g == Speichergruppe.papierkorb,
      );
    }
    if (mounted) _neu();
  }

  Future<void> _fotos(
    List<String> ids,
    String titel, {
    bool papierkorb = false,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _SpeicherTeilmenge(
        library: widget.library,
        ids: ids,
        titel: titel,
        papierkorb: papierkorb,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return PopScope(
      canPop: !_prueft,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.speicherkarteTitel),
          actions: [
            IconButton(
              tooltip: t.ausbauNeuLaden,
              onPressed: _prueft ? null : _neu,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder(
          future: _stand,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(t.speicherkarteFehler));
            }
            final stand = snapshot.data;
            if (stand == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final datum = DateFormat.yMd(
              Localizations.localeOf(context).toString(),
            ).add_Hm();
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  t.speicherkarteText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SpeicherkarteGrafik(
                  stand: stand,
                  beiAuswahl: _prueft ? null : (g) => _auswahl(stand, g),
                ),
                Text(t.speicherkarteStandNurDateien),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _prueft ? null : _pruefen,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: Text(t.speicherkartePruefen),
                    ),
                    OutlinedButton.icon(
                      onPressed: _prueft
                          ? null
                          : () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ReferenzKatalogScreen(
                                    library: widget.library,
                                  ),
                                ),
                              );
                              if (mounted) _neu();
                            },
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(t.katalogTitel),
                    ),
                    if (_prueft)
                      TextButton(
                        onPressed: () => setState(() => _abbruch = true),
                        child: Text(
                          _abbruch
                              ? t.speicherkarteAbbruchNachDatei
                              : t.ausbauAbbrechen,
                        ),
                      ),
                  ],
                ),
                if (_prueft)
                  ValueListenableBuilder(
                    valueListenable: _fortschritt,
                    builder: (context, w, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${t.speicherkartePruefungLaeuft} ${w.$1} / ${w.$2}',
                          ),
                          LinearProgressIndicator(
                            value: w.$2 > 0 ? w.$1 / w.$2 : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_meldung != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(liveRegion: true, child: Text(_meldung!)),
                  ),
                if (stand.nachweiseUnlesbar)
                  Text(t.speicherkarteNachweisUnlesbar),
                if (stand.arbeitsvorschauenUnlesbar)
                  Text(t.arbeitskopienFehler),
                const SizedBox(height: 24),
                Text(
                  t.speicherkarteOrte,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ListTile(
                  leading: const Icon(Icons.computer_outlined),
                  title: Text(t.speicherkarteLokal),
                  subtitle: SelectableText(widget.library.paths.root.path),
                ),
                if (widget.library.verbindung case final v?)
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: Text(t.speicherkarteServer),
                    subtitle: SelectableText(
                      '${v.server.scheme}://${v.server.host}${v.server.hasPort ? ':${v.server.port}' : ''}',
                    ),
                  ),
                for (final e in stand.originalorte.entries)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: SelectableText(e.key),
                    trailing: Text('${e.value}'),
                  ),
                const SizedBox(height: 16),
                Text(
                  t.speicherkarteNachweise,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(t.speicherkarteHistorisch),
                if (stand.nachweise.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(t.speicherkarteKeinZiel),
                  ),
                for (final n in stand.nachweise)
                  Card(
                    child: ExpansionTile(
                      leading: Icon(
                        n.erreichbar
                            ? Icons.verified_outlined
                            : Icons.cloud_off_outlined,
                      ),
                      title: Text(n.ziel),
                      subtitle: Text(
                        '${t.speicherkarteLetztePruefung}: ${datum.format(n.am.toLocal())} · ${n.bestaetigt}${n.erreichbar ? '' : ' · ${t.speicherkarteNichtVerbunden}'}${n.vollstaendig ? '' : ' · ${t.speicherkarteTeilpruefung}'}',
                      ),
                      children: [
                        for (final befund in Kopienbefund.values)
                          ListTile(
                            title: Text(switch (befund) {
                              Kopienbefund.bestaetigt =>
                                t.speicherkarteSicherung,
                              Kopienbefund.fehlt =>
                                t.speicherkarteSicherungFehlt,
                              Kopienbefund.unlesbar => t.katalogFehlerzahl,
                            }),
                            trailing: Text(
                              '${n.befunde.values.where((b) => b == befund).length}',
                            ),
                            onTap: () => _fotos([
                              for (final f in stand.fotos.values)
                                if (n.befunde[f.sha256] == befund &&
                                    !f.papierkorb)
                                  f.id,
                            ], t.speicherkarteNachweise),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Text('${t.speicherkarteGesperrt} (${stand.gesperrt})'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SpeicherTeilmenge extends StatefulWidget {
  const _SpeicherTeilmenge({
    required this.library,
    required this.ids,
    required this.titel,
    this.papierkorb = false,
  });
  final LibraryState library;
  final List<String> ids;
  final String titel;
  final bool papierkorb;
  @override
  State<_SpeicherTeilmenge> createState() => _SpeicherTeilmengeState();
}

class _SpeicherTeilmengeState extends State<_SpeicherTeilmenge> {
  int _seite = 0;
  late Stream<List<AssetData>> _daten = _laden();
  Stream<List<AssetData>> _laden() {
    final ids = widget.ids.skip(_seite * 100).take(100).toList();
    return (widget.library.db.select(widget.library.db.assets)
          ..where((t) => t.id.isIn(ids))
          ..where((t) => t.isLocked.equals(false))
          ..where((t) => t.isTrashed.equals(widget.papierkorb)))
        .watch();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.titel)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: _daten,
              builder: (context, s) {
                if (s.hasError) {
                  return Center(child: Text(t.speicherkarteFehler));
                }
                final rows = s.data;
                if (rows == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final a = rows[i];
                    return ListTile(
                      leading: SizedBox(
                        width: 56,
                        height: 48,
                        child: a.thumbnailRelativePath == null
                            ? const Icon(Icons.photo_outlined)
                            : bibliotheksbild(
                                widget.library.paths,
                                a.thumbnailRelativePath!,
                                fit: BoxFit.cover,
                                cacheWidth: 112,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                      ),
                      title: Text(a.originalFileName),
                      subtitle: Text(a.relativePath),
                      onTap: widget.papierkorb
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AssetViewerScreen(
                                  assets: rows,
                                  initialIndex: i,
                                  paths: widget.library.paths,
                                  db: widget.library.db,
                                  library: widget.library,
                                  onToggleFavorite: (a) =>
                                      widget.library.db.fuehreAus(
                                        FavoritSetzen([a.id], !a.isFavorite),
                                      ),
                                ),
                              ),
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
                onPressed: _seite == 0
                    ? null
                    : () => setState(() {
                        _seite--;
                        _daten = _laden();
                      }),
                child: Text(t.ausbauZurueck),
              ),
              Text('${_seite + 1}'),
              IconButton(
                tooltip: t.speicherkarteDateien,
                onPressed: (_seite + 1) * 100 >= widget.ids.length
                    ? null
                    : () => setState(() {
                        _seite++;
                        _daten = _laden();
                      }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
