import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../services/suchfehler.dart';
import '../services/embedding_similarity.dart';
import '../services/duplicate_selection.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/pin_dialogs.dart';
import 'asset_viewer_screen.dart';
import 'second_library_compare_screen.dart';
import '../services/meldungsdienst.dart';

/// Gruppiert Fotos, deren CLIP-Bild-Embeddings sich sehr ähnlich sind
/// (Kosinus-Ähnlichkeit über einer einstellbaren Schwelle). Das findet nicht
/// nur exakte Duplikate (die werden beim Import bereits per Prüfsumme
/// ausgeschlossen), sondern auch inhaltlich sehr ähnliche Aufnahmen, z.B.
/// mehrere Fotos derselben Szene in Serie.
class DuplicatesScreen extends StatefulWidget {
  final LibraryState library;
  const DuplicatesScreen({super.key, required this.library});

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  double _threshold = 0.92;
  bool _loading = true;
  Suchfehlerstand? _error;
  List<List<AssetData>> _groups = [];

  /// Wie viele Paare der Nutzer von der Suche ausgenommen hat – für die
  /// Kopfzeile und den Knopf zum Zurücknehmen.
  int _ausnahmen = 0;

  /// Fotos in allen Gruppen zusammen. Die zweite Zahl neben der Zahl der
  /// Gruppen: „7 Gruppen" allein sagt nicht, ob dahinter 14 oder 60 Fotos
  /// stehen.
  int get _fotosInGruppen =>
      _groups.fold(0, (summe, gruppe) => summe + gruppe.length);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (!widget.library.clipAvailable) {
        setState(() {
          _error = const Suchfehlerstand(Suchfehler.clipFehlt);
          _groups = [];
        });
        return;
      }

      final embeddings = await widget.library.cachedEmbeddings();
      final ausnahmen = await widget.library.db.duplikatAusnahmeSchluessel();
      // Der paarweise Vergleich läuft in einem eigenen Isolate (siehe
      // [findDuplicateGroups]), damit die UI bei größeren Bibliotheken
      // währenddessen nicht einfriert.
      final groupIdLists = await compute(
        findDuplicateGroups,
        DuplicateSearchParams(embeddings, _threshold, ausnahmen: ausnahmen),
      );

      // Eine Abfrage fuer alle Gruppen statt einer je Gruppe: Die
      // Datenbank liegt auf einem eigenen Isolate, jede Abfrage ist ein
      // Hin- und Rueckweg. Bei 324 Gruppen waren das 52,2 statt 12,6 ms.
      final alleIds = <String>{for (final idList in groupIdLists) ...idList};
      final geladen = await widget.library.db.assetsByIds(alleIds.toList());
      final nachId = {for (final a in geladen) a.id: a};

      final groups = <List<AssetData>>[];
      for (final idList in groupIdLists) {
        final assets = [
          for (final id in idList)
            if (nachId[id] != null) nachId[id]!
        ];
        if (assets.length >= 2) groups.add(assets);
      }

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _ausnahmen = ausnahmen.length;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = Suchfehlerstand(Suchfehler.gescheitert, '$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Behält je Gruppe das beste Foto und verschiebt den Rest in den
  /// Papierkorb – erst nach Vorschau und Bestätigung. Die Regeln stehen in
  /// services/duplicate_selection.dart; Gruppen mit mehreren favorisierten
  /// oder bewerteten Fotos bleiben bewusst unangetastet.
  Future<void> _alleKopienLoeschen() async {
    final vorschau = berechneLoeschVorschau(_groups);

    if (vorschau.zuLoeschen.isEmpty) {
      if (!mounted) return;
      melde.hinweis(vorschau.uebersprungeneGruppen > 0
          ? AppTexte.of(context).duplNichtsLoeschbar
          : AppTexte.of(context).duplNichtsZuLoeschen);
      return;
    }

    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppTexte.of(context).duplPapierkorbTitel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppTexte.of(context).duplPapierkorbAnzahl(
                vorschau.zuLoeschen.length, _groups.length)),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppTexte.of(context).duplBehaltenRegel,
              style: const TextStyle(fontSize: 12),
            ),
            if (vorschau.uebersprungeneGruppen > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppTexte.of(context).duplUebersprungen(vorschau.uebersprungeneGruppen),
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppTexte.of(context).duplRueckgaengig,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppTexte.of(context).duplInPapierkorb),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;

    await widget.library.db.moveToTrash(vorschau.zuLoeschen.map((a) => a.id).toList());
    if (!mounted) return;
    melde.erfolg(AppTexte.of(context).duplVerschoben(vorschau.zuLoeschen.length));
    await _load();
  }

  /// Nimmt eine Gruppe künftig von der Suche aus.
  ///
  /// Die Gruppe verschwindet sofort aus der Liste, statt einen neuen
  /// Durchlauf anzustossen: Der kostet bei grossen Bibliotheken spürbar
  /// Zeit, und am Ergebnis ändert sich nichts ausser dieser einen Gruppe.
  Future<void> _gruppeIgnorieren(List<AssetData> group) async {
    final ids = group.map((a) => a.id).toList();
    await widget.library.db.ignoriereDuplikatgruppe(ids);
    if (!mounted) return;
    final neueZahl = await widget.library.db.zaehleDuplikatAusnahmen();
    if (!mounted) return;
    setState(() {
      _groups.remove(group);
      _ausnahmen = neueZahl;
    });
    melde.hinweis(
      AppTexte.of(context).duplGruppeIgnoriert(group.length),
      aktion: (
        beschriftung: AppTexte.of(context).allgRueckgaengig,
        // Einzeln zurücknehmen statt alles: Wer sich vertippt hat, will
        // diese eine Gruppe zurück, nicht die Arbeit einer halben Stunde.
        beiDruck: () async {
          await widget.library.db.hebeDuplikatgruppeAuf(ids);
          await _load();
        },
      ),
    );
  }

  Future<void> _ausnahmenZuruecknehmen() async {
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppTexte.of(context).duplAusnahmenTitel),
        content: Text(AppTexte.of(context).duplAusnahmenFrage(_ausnahmen)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppTexte.of(context).duplAusnahmenLoeschen)),
        ],
      ),
    );
    if (bestaetigt != true) return;
    await widget.library.db.loescheDuplikatAusnahmen();
    await _load();
  }

  Future<void> _moveToTrash(AssetData asset, List<AssetData> group) async {
    await widget.library.db.moveToTrash([asset.id]);
    if (!mounted) return;
    setState(() {
      group.remove(asset);
      if (group.length < 2) _groups.remove(group);
    });
  }

  Future<void> _moveToLocked(AssetData asset, List<AssetData> group) async {
    if (!await ensureVaultUnlocked(context, widget.library)) return;
    await widget.library.lockAsset(asset);
    if (!mounted) return;
    setState(() {
      group.remove(asset);
      if (group.length < 2) _groups.remove(group);
    });
  }

  /// Übernimmt die hilfreichen Metadaten aller Kopien auf eine bewusst
  /// gewählte Aufnahme. Anders als „Löschen" geht dabei kein Tag, Album,
  /// Favorit oder Stern verloren; die Quellbilder bleiben im Papierkorb und
  /// können dort weiterhin zurückgeholt werden.
  Future<void> _gruppeZusammenfuehren(List<AssetData> gruppe) async {
    var behalten = besterDerGruppe(gruppe);
    var beschreibungenVerbinden = true;
    final t = AppTexte.of(context);
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(t.duplZusammenfuehrenTitel),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.duplZusammenfuehrenText(gruppe.length)),
                const SizedBox(height: AppSpacing.md),
                Text(t.duplBehaltenAuswahl, style: Theme.of(context).textTheme.titleSmall),
                RadioGroup<String>(
                  groupValue: behalten.id,
                  onChanged: (id) {
                    if (id == null) return;
                    setDialogState(() => behalten =
                        gruppe.firstWhere((asset) => asset.id == id));
                  },
                  child: Column(
                    children: [
                      for (final asset in gruppe)
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: asset.id,
                          title: Text(asset.originalFileName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(t.duplBehaltenDetails(
                              asset.rating, asset.isFavorite ? 1 : 0)),
                        ),
                    ],
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: beschreibungenVerbinden,
                  onChanged: (value) => setDialogState(
                      () => beschreibungenVerbinden = value ?? true),
                  title: Text(t.duplBeschreibungenVerbinden),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(t.allgAbbrechen)),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(t.duplZusammenfuehren)),
          ],
        ),
      ),
    );
    if (bestaetigt != true) return;
    await widget.library.db.fuehreDuplikateZusammen(
      behaltenId: behalten.id,
      duplikatIds: gruppe.map((asset) => asset.id).toList(),
      beschreibungenVerbinden: beschreibungenVerbinden,
    );
    if (!mounted) return;
    setState(() => _groups.remove(gruppe));
    melde.erfolg(t.duplZusammengefuehrt(gruppe.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppTexte.of(context).duplTitel),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SecondLibraryCompareScreen(library: widget.library),
            )),
            icon: const Icon(Icons.folder_copy_outlined),
            label: Text(AppTexte.of(context).duplZweiteBibliothek),
          ),
          if (_groups.isNotEmpty)
            TextButton.icon(
              onPressed: _alleKopienLoeschen,
              icon: const Icon(Icons.auto_delete_outlined),
              label: Text(AppTexte.of(context).duplAlleKopienLoeschen),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: Row(
              children: [
                Text(AppTexte.of(context).duplAehnlichkeit),
                Expanded(
                  child: Slider(
                    value: _threshold,
                    min: 0.80,
                    max: 0.99,
                    divisions: 19,
                    label: _threshold.toStringAsFixed(2),
                    onChanged: (v) => setState(() => _threshold = v),
                    onChangeEnd: (_) => _load(),
                  ),
                ),
                Text(_threshold.toStringAsFixed(2)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              AppTexte.of(context).duplSchwelleHinweis,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _groups.isEmpty
                          ? AppTexte.of(context).duplNichtsGefunden
                          : AppTexte.of(context)
                              .duplGefunden(_groups.length, _fotosInGruppen),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (_ausnahmen > 0)
                    TextButton.icon(
                      onPressed: _ausnahmenZuruecknehmen,
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      label: Text(AppTexte.of(context).duplAusnahmenZahl(_ausnahmen)),
                    ),
                ],
              ),
            ),
          const Divider(height: 16),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(_error!.satz(AppTexte.of(context)),
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(AppTexte.of(context).duplKeineGruppen, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _groups.length,
      itemBuilder: (context, groupIndex) {
        final group = _groups[groupIndex];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppTexte.of(context).duplGruppe(groupIndex + 1, group.length),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _gruppeIgnorieren(group),
                    icon: const Icon(Icons.visibility_off_outlined, size: 18),
                    label: Text(AppTexte.of(context).duplGruppeIgnorieren),
                  ),
                  TextButton.icon(
                    onPressed: () => _gruppeZusammenfuehren(group),
                    icon: const Icon(Icons.merge_type_outlined, size: 18),
                    label: Text(AppTexte.of(context).duplZusammenfuehren),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: group.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final asset = group[index];
                    return SizedBox(
                      width: 140,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: AssetThumbnailTile(
                              asset: Rasterzeile.aus(asset),
                              paths: widget.library.paths,
                              onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                                builder: (_) => AssetViewerScreen(
                                  assets: group,
                                  initialIndex: index,
                                  paths: widget.library.paths,
                                  db: widget.library.db,
                                  library: widget.library,
                                  onToggleFavorite: (a) =>
                                      widget.library.db.setFavorite(a.id, !a.isFavorite),
                                  onDelete: (a) => _moveToTrash(a, group),
                                  onLock: (a) => _moveToLocked(a, group),
                                ),
                              )),
                            ),
                          ),
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                                tooltip: AppTexte.of(context).duplVerschiebenTooltip,
                                onPressed: () => _moveToTrash(asset, group),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
