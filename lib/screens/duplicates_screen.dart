import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import '../services/suchfehler.dart';
import 'package:kern/services/embedding_similarity.dart';
import 'package:kern/services/duplicate_selection.dart';
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
            if (nachId[id] != null) nachId[id]!,
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
  /// kern/services/duplicate_selection.dart; Gruppen mit mehreren favorisierten
  /// oder bewerteten Fotos bleiben bewusst unangetastet.
  Future<void> _alleKopienLoeschen() async {
    final vorschau = berechneLoeschVorschau(_groups);

    if (vorschau.zuLoeschen.isEmpty) {
      if (!mounted) return;
      melde.hinweis(
        vorschau.uebersprungeneGruppen > 0
            ? AppTexte.of(context).duplNichtsLoeschbar
            : AppTexte.of(context).duplNichtsZuLoeschen,
      );
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
            Text(
              AppTexte.of(context).duplPapierkorbAnzahl(
                vorschau.zuLoeschen.length,
                _groups.length,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppTexte.of(context).duplBehaltenRegel,
              style: const TextStyle(fontSize: 12),
            ),
            if (vorschau.uebersprungeneGruppen > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppTexte.of(
                  context,
                ).duplUebersprungen(vorschau.uebersprungeneGruppen),
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppTexte.of(context).allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppTexte.of(context).duplInPapierkorb),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;

    // Wie im Browser: je Gruppe zusammenführen statt nur wegwerfen –
    // Schlagwörter, Alben, Favorit und Sterne der Kopien gehen auf das
    // behaltene Foto über (#208).
    for (final gruppe in _groups) {
      final weg = zuLoeschendeDerGruppe(gruppe);
      if (weg.isEmpty) continue;
      await widget.library.db.fuehreAus(
        DuplikateZusammenfuehren(
          behaltenId: besterDerGruppe(gruppe).id,
          duplikatIds: [for (final a in weg) a.id],
          beschreibungenVerbinden: true,
        ),
      );
    }
    if (!mounted) return;
    melde.erfolg(
      AppTexte.of(context).duplVerschoben(vorschau.zuLoeschen.length),
    );
    await _load();
  }

  /// Nimmt eine Gruppe künftig von der Suche aus.
  ///
  /// Die Gruppe verschwindet sofort aus der Liste, statt einen neuen
  /// Durchlauf anzustossen: Der kostet bei grossen Bibliotheken spürbar
  /// Zeit, und am Ergebnis ändert sich nichts ausser dieser einen Gruppe.
  Future<void> _gruppeIgnorieren(List<AssetData> group) async {
    final ids = group.map((a) => a.id).toList();
    await widget.library.db.fuehreAus(DuplikatgruppeIgnorieren(ids));
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
          await widget.library.db.fuehreAus(DuplikatgruppeAufheben(ids));
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
            child: Text(AppTexte.of(context).allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppTexte.of(context).duplAusnahmenLoeschen),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;
    await widget.library.db.fuehreAus(const DuplikatAusnahmenLoeschen());
    await _load();
  }

  Future<void> _moveToTrash(AssetData asset, List<AssetData> group) async {
    await widget.library.db.fuehreAus(InDenPapierkorb([asset.id]));
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

  /// „Behalten“ wie im Browser: Dieses Foto bleibt, die übrigen der Gruppe
  /// gehen in den Papierkorb – zusammengeführt, also mit ihren
  /// Schlagwörtern, Alben, Favoriten und Sternen auf diesem Foto.
  Future<void> _behalten(List<AssetData> gruppe, AssetData asset) async {
    final t = AppTexte.of(context);
    final andere = [
      for (final a in gruppe)
        if (a.id != asset.id) a.id,
    ];
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          andere.length == 1
              ? t.duplBehaltenEine(asset.originalFileName)
              : t.duplBehaltenMehrere(asset.originalFileName, andere.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.duplBehalten),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;
    await widget.library.db.fuehreAus(
      DuplikateZusammenfuehren(
        behaltenId: asset.id,
        duplikatIds: andere,
        beschreibungenVerbinden: true,
      ),
    );
    if (!mounted) return;
    setState(() => _groups.remove(gruppe));
    melde.erfolg(t.duplZusammengefuehrt(andere.length));
  }

  static String _prozent(double w) => '${(w * 100).round()} %';

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final loeschbar = _groups.fold(
      0,
      (n, g) => n + zuLoeschendeDerGruppe(g).length,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(t.duplTitel),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    SecondLibraryCompareScreen(library: widget.library),
              ),
            ),
            icon: const Icon(Icons.folder_copy_outlined),
            label: Text(t.duplZweiteBibliothek),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wie im Browser (web/app.js, zeigeDuplikate, #208): oben
          // Ähnlichkeit und „Kopien in den Papierkorb“, darunter der
          // Hinweis, dann je Gruppe eine Karte.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                Text(t.duplAehnlichkeit),
                Expanded(
                  child: Slider(
                    value: _threshold,
                    min: 0.80,
                    max: 0.99,
                    divisions: 19,
                    label: _prozent(_threshold),
                    onChanged: (v) => setState(() => _threshold = v),
                    onChangeEnd: (_) => _load(),
                  ),
                ),
                Text(_prozent(_threshold)),
                if (!_loading && loeschbar > 0) ...[
                  const SizedBox(width: AppSpacing.md),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: farben.error,
                      foregroundColor: farben.onError,
                    ),
                    onPressed: _alleKopienLoeschen,
                    child: Text(t.duplKopienInPapierkorb(loeschbar)),
                  ),
                ],
              ],
            ),
          ),
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _groups.isEmpty
                              ? t.duplNichtsGefunden
                              : t.duplGefunden(_groups.length, _fotosInGruppen),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          _groups.isEmpty
                              ? t.duplSchwelleHinweis
                              : t.duplRegelHinweis,
                          style: TextStyle(
                            fontSize: 12,
                            color: farben.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_ausnahmen > 0)
                    TextButton.icon(
                      onPressed: _ausnahmenZuruecknehmen,
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      label: Text(t.duplAusnahmenZahl(_ausnahmen)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
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
          child: Text(
            _error!.satz(AppTexte.of(context)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            AppTexte.of(context).duplKeineGruppen,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: _groups.length,
      itemBuilder: (context, i) => _gruppenkarte(context, _groups[i]),
    );
  }

  /// Eine Gruppe als Karte wie im Browser: Kopf mit Zahl und „Keine
  /// Duplikate“, darunter jedes Foto mit Grösse, Datum, Favorit, Sternen
  /// und „Behalten“. Umrandet ist das, was das Aufräumen behielte.
  Widget _gruppenkarte(BuildContext context, List<AssetData> gruppe) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final datumZeit = DateFormat.yMMMd(sprache).add_Hm();
    final beste = besterDerGruppe(gruppe);
    final vonHand = zuLoeschendeDerGruppe(gruppe).isEmpty;
    void oeffne(int index) => Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AssetViewerScreen(
          assets: gruppe,
          initialIndex: index,
          paths: widget.library.paths,
          db: widget.library.db,
          library: widget.library,
          onToggleFavorite: (a) =>
              widget.library.db.fuehreAus(FavoritSetzen([a.id], !a.isFavorite)),
          onDelete: (a) => _moveToTrash(a, gruppe),
          onLock: (a) => _moveToLocked(a, gruppe),
        ),
      ),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    vonHand
                        ? t.duplNurVonHand(gruppe.length)
                        : t.duplAufnahmen(gruppe.length),
                    style: TextStyle(color: farben.onSurfaceVariant),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => _gruppeIgnorieren(gruppe),
                  child: Text(t.duplGruppeIgnorieren),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 262,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: gruppe.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final a = gruppe[index];
                  final behalten = a.id == beste.id;
                  final angaben = [
                    if (a.widthPx != null && a.heightPx != null)
                      '${a.widthPx} × ${a.heightPx}',
                    datumZeit.format(a.fileCreatedAt.toLocal()),
                    if (a.isFavorite) '♥',
                    if (a.rating > 0) '★' * a.rating,
                  ].join(' · ');
                  return SizedBox(
                    width: 150,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: behalten
                                ? Border.all(color: farben.primary, width: 3)
                                : null,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: AssetThumbnailTile(
                            asset: Rasterzeile.aus(a),
                            paths: widget.library.paths,
                            onTap: () => oeffne(index),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Tooltip(
                          message: a.originalFileName,
                          child: Text(
                            a.originalFileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          angaben,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: farben.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        behalten
                            ? FilledButton(
                                onPressed: () => _behalten(gruppe, a),
                                child: Text(t.duplBehalten),
                              )
                            : OutlinedButton(
                                onPressed: () => _behalten(gruppe, a),
                                child: Text(t.duplBehalten),
                              ),
                      ],
                    ),
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
