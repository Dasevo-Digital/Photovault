import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../services/asset_grouping.dart';
import '../theme/app_spacing.dart';
import '../state/library_state.dart';
import '../widgets/empty_state.dart';
import '../widgets/asset_list_view.dart';
import '../services/listenspalten.dart';
import '../services/sortierung.dart';
import '../widgets/month_grouped_asset_grid.dart';
import '../widgets/timeline_grid_layout.dart';
import '../widgets/pin_dialogs.dart';
import '../widgets/rasterbedienung.dart';
import '../widgets/selection_action_bar.dart';
import '../widgets/sortierungswahl.dart';
import 'asset_viewer_screen.dart';
import 'import_progress_sheet.dart';
import '../widgets/stromhalter.dart';

class TimelineScreen extends StatefulWidget {
  final LibraryState library;

  /// Siehe [MonthGroupedAssetGrid.highlightAssetId].
  final String? highlightAssetId;

  /// Jede Änderung springt zu den neuesten Fotos – ausgelöst vom Tippen
  /// auf das Zeitleisten-Symbol in der Navigation.
  final ValueListenable<int>? nachObenSignal;

  const TimelineScreen({
    super.key,
    required this.library,
    this.highlightAssetId,
    this.nachObenSignal,
  });

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> with Rasterbedienung<TimelineScreen, Rasterzeile> {
  // Wachsendes Ladefenster statt auf einen Schlag die komplette Bibliothek zu
  // laden: `watchRasterzeilen(limit: _windowSize)` bleibt dank
  // `idx_assets_trashed_locked_created` auch für ein großes Fenster ein
  // günstiger Index-Walk statt eines vollen Tabellen-Scans (SQLite kann die
  // ersten N Zeilen in Sortierreihenfolge direkt aus dem Index lesen). Wird
  // beim Scrollen nahe ans Ende erweitert (siehe [_maybeGrowWindow]) und bei
  // Bedarf vorab für "Foto in der Timeline anzeigen" (siehe
  // [_resolveHighlight]).
  static const _initialWindowSize = 600;
  static const _windowGrowth = 600;
  int _windowSize = _initialWindowSize;
  bool _resolvingHighlight = false;

  final Set<String> _selected = {};

  /// Der Datenstrom der Zeitleiste, festgehalten über Neubauten hinweg.
  ///
  /// Stand er direkt im `stream:`, wurde er bei JEDEM Neubau neu abonniert –
  /// und jedes Abo führt die Abfrage von vorn aus. Neubauten löst hier schon
  /// jeder Pfeiltastendruck aus (siehe [Rasterbedienung]) und jeder Klick in
  /// der Mehrfachauswahl. An der gewachsenen Bibliothek waren das 5,1 ms je
  /// Tastendruck beim Startfenster und 35,9 ms, sobald es auf die ganze
  /// Bibliothek gewachsen war. Siehe [Stromhalter].
  final _zeitleiste = Stromhalter<List<Rasterzeile>>();

  /// **Die Listenansicht braucht mehr.** Sie zeigt Blende, Belichtung,
  /// Brennweite, ISO, Objektiv, Dateigrösse und den Ort – acht Spalten,
  /// die eine [Rasterzeile] nicht trägt und auch nicht tragen soll. Wer
  /// sie sehen will, bezahlt die volle Zeile; wer im Raster bleibt, nicht.
  final _liste = Stromhalter<List<AssetData>>();

  /// Was der Datenstrom zuletzt geliefert hat, plus die Spaltenzahl, die das
  /// Raster daraus gemacht hat – beides braucht [Rasterbedienung] beim
  /// Tastendruck, also ausserhalb von `build`.
  List<Rasterzeile> _geladen = const [];
  int _spalten = 1;

  @override
  Set<String> get auswahl => _selected;

  @override
  AppDatabase get rasterDb => widget.library.db;

  @override
  List<Rasterzeile> get rasterAssets => _geladen;

  @override
  String rasterKennung(Rasterzeile zeile) => zeile.id;

  @override
  ({bool favorit, String? farbe}) rasterMerkmale(Rasterzeile zeile) =>
      (favorit: zeile.isFavorite, farbe: zeile.colorLabel);

  @override
  int get rasterSpalten => _spalten;

  /// In der Listenansicht steht alles untereinander – eine Spalte, eine
  /// Gruppe. Sonst die Monatsgruppen, die das Raster auch malt.
  @override
  List<List<String>> get rasterGruppen {
    // Ohne Gliederung ist alles eine Gruppe – die Tastatur muss dieselbe
    // Einteilung sehen wie das Raster, sonst springt der Zeiger woanders
    // hin als der Rahmen.
    if (_alsListe || !_gliedert) return [[for (final a in _geladen) a.id]];
    final m = monatsgruppen(_geladen, absteigend: sortierungAbsteigend(_sortierung));
    return [for (final k in m.schluessel) [for (final a in m.gruppen[k]!) a.id]];
  }

  /// Bei bündigen Reihen stehen mal drei und mal dreizehn Fotos
  /// nebeneinander – dann genügt eine Spaltenzahl nicht, um zu wissen, wo
  /// „nach unten" hinführt.
  @override
  List<List<int>>? get rasterReihenlaengen {
    if (_alsListe ||
        _form != Zeitleistenform.reihen ||
        _rasterbreite <= 0) {
      return null;
    }
    // Dieselbe Einteilung wie [rasterGruppen] – sonst zählt die eine
    // Rechnung Reihen in Gruppen, die die andere gar nicht kennt.
    final gruppen = _gliedert
        ? () {
            final m = monatsgruppen(_geladen,
                absteigend: sortierungAbsteigend(_sortierung));
            return [for (final k in m.schluessel) m.gruppen[k]!];
          }()
        : [_geladen];
    return [
      for (final g in gruppen)
        [
          for (final r in zeitleisteReihen(g, _rasterbreite,
              kachelbreite: _kachelbreite))
            r.plaetze.length
        ]
    ];
  }

  /// Die Breite, die dem Raster bleibt – vom `LayoutBuilder` gesetzt, weil
  /// die Reihen ohne sie nicht zu rechnen sind.
  double _rasterbreite = 0;

  @override
  void rasterOeffne(Rasterzeile asset) => _openViewer(_geladen, asset);

  /// Raster oder Liste, und wonach die Liste gegliedert wird.
  ///
  /// Nur für diese Sitzung: In den Einstellungen abgelegt wäre es eine
  /// Datenbankspalte für eine Wahl, die man im Lauf einer Sichtung
  /// mehrfach umlegt.
  bool _alsListe = false;
  ListenGruppierung _gruppierung = ListenGruppierung.monat;

  /// Wie gross die Kacheln sind – siehe [zeitleisteKachelstufen].
  ///
  /// Anders als Raster/Liste **wird das gemerkt**: Es ist keine Wahl, die
  /// man im Lauf einer Sichtung mehrfach umlegt, sondern wie man seine
  /// Bibliothek ansieht.
  int _kachelstufe = zeitleisteKachelstufeVorgabe;

  double get _kachelbreite => zeitleisteKachelbreite(_kachelstufe);

  /// Quadrate oder buendige Reihen. Aus demselben Grund gemerkt wie die
  /// Kachelgroesse: Es ist keine Wahl, die man im Lauf einer Sichtung
  /// mehrfach umlegt, sondern wie man seine Bibliothek ansieht.
  Zeitleistenform _form = zeitleisteFormVorgabe;

  /// Welche Spalten die Listenansicht zeigt und wie breit sie sind.
  /// Ebenfalls gemerkt: Wer sich seine Spalten einrichtet, richtet sie
  /// einmal ein.
  Listenspaltenwahl _listenspalten = Listenspaltenwahl.vorgabe;

  /// Wonach geordnet wird – siehe [Rastersortierung]. Aus demselben Grund
  /// gemerkt wie Kachelgrösse und Form.
  Rastersortierung _sortierung = rastersortierungVorgabe;

  /// Nur nach dem Aufnahmedatum darf nach Monaten gegliedert werden –
  /// siehe [MonthGroupedAssetGrid.gliedern].
  bool get _gliedert => nachAufnahmedatum(_sortierung);

  /// Was die Liste wirklich gliedert. Ohne Zeitbezug in der Reihenfolge
  /// wäre eine Monatsüberschrift eine Behauptung über eine Gruppe, in der
  /// jedes Jahr vorkommen kann.
  ListenGruppierung get _wirksameGruppierung =>
      _gliedert ? _gruppierung : ListenGruppierung.keine;

  @override
  void initState() {
    super.initState();
    _ladeKachelstufe();
    final id = widget.highlightAssetId;
    if (id != null) _resolveHighlight(id);
  }

  Future<void> _ladeKachelstufe() async {
    final stufe = await widget.library.db.zeitleisteKachelstufeWert();
    final spalten = await widget.library.db.listenspaltenWahl();
    final form = await widget.library.db.zeitleisteFormWert();
    final sortierung = await widget.library.db.zeitleisteSortierungWert();
    if (mounted) {
      setState(() {
        _kachelstufe = stufe;
        _listenspalten = spalten;
        _form = form;
        _sortierung = sortierung;
      });
    }
  }

  void _setzeSortierung(Rastersortierung? wahl) {
    if (wahl == null || wahl == _sortierung) return;
    setState(() {
      _sortierung = wahl;
      // Die Kachel unter dem Rahmen wandert beim Umsortieren woanders
      // hin; ein Rahmen, der auf einem anderen Foto wieder auftaucht,
      // wäre eine falsche Auskunft darüber, wo man gerade steht.
      aktiveKachel = null;
      anker = null;
    });
    // Ohne `await`, aus demselben Grund wie bei der Kachelgroesse.
    unawaited(widget.library.db.setzeZeitleisteSortierung(wahl));
  }

  void _wechsleForm() {
    final neue = _form == Zeitleistenform.quadrate
        ? Zeitleistenform.reihen
        : Zeitleistenform.quadrate;
    setState(() => _form = neue);
    // Ohne `await`, aus demselben Grund wie bei der Kachelgroesse: Wer
    // umschaltet, soll nicht auf die Platte warten.
    unawaited(widget.library.db.setzeZeitleisteForm(neue));
  }

  void _setzeSpalten(Listenspaltenwahl wahl) {
    setState(() => _listenspalten = wahl);
    unawaited(widget.library.db.setzeListenspalten(wahl));
  }

  void _zoome({required bool groesser}) {
    final neue = naechsteKachelstufe(_kachelstufe, groesser: groesser);
    if (neue == _kachelstufe) return;
    setState(() => _kachelstufe = neue);
    // Ohne `await`: Wer an der Groesse dreht, soll nicht auf die Platte
    // warten. Faellt das Schreiben aus, ist der Preis eine Stufe, die
    // beim naechsten Start wieder auf der alten steht.
    unawaited(widget.library.db.setzeZeitleisteKachelstufe(neue));
  }

  @override
  void didUpdateWidget(covariant TimelineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.highlightAssetId;
    if (id != null && id != oldWidget.highlightAssetId) _resolveHighlight(id);
  }

  /// Öffnet das Ladefenster VORAB weit genug, um das Ziel-Foto zu enthalten
  /// (auch wenn es weit "unten" in einer sehr großen Bibliothek liegt) –
  /// muss abgeschlossen sein, BEVOR [MonthGroupedAssetGrid] mit gesetztem
  /// `highlightAssetId` baut, sonst würde dessen eigene (nur einmal pro ID
  /// ausgeführte) Scroll-Logik das Foto in einem noch zu schmalen Ausschnitt
  /// nicht finden und fälschlich "nicht gefunden" melden.
  Future<void> _resolveHighlight(String assetId) async {
    setState(() => _resolvingHighlight = true);
    final rank = await widget.library.db.timelineRankOfAsset(assetId);
    if (!mounted) return;
    setState(() {
      if (rank != null) _windowSize = math.max(_windowSize, rank + 1 + _windowGrowth);
      _resolvingHighlight = false;
    });
  }

  /// Nur erweitern, wenn das Fenster tatsächlich voll ausgeschöpft ist – bei
  /// weniger geladenen Fotos als [_windowSize] ist die Bibliothek bereits
  /// vollständig geladen, es gibt nichts mehr nachzuladen.
  void _maybeGrowWindow(int loadedCount) {
    if (loadedCount < _windowSize) return;
    setState(() => _windowSize += _windowGrowth);
  }

  /// Siehe [Rasterbedienung.rasterUmschalten]: Der Anker gehoert dazu.
  void _toggle(String id) => rasterUmschalten(id);

  /// Auf die Monatsüberschrift getippt: alle Fotos/Videos des Monats
  /// auswählen – oder, falls bereits alle ausgewählt sind, wieder abwählen.
  void _toggleGroup(List<Rasterzeile> groupAssets) =>
      rasterGruppeUmschalten([for (final a in groupAssets) a.id]);

  /// Bei einem Serien-Titelbild (siehe StackReviewScreen) werden nur die
  /// Stapel-Mitglieder geöffnet statt der vollen Timeline-Liste – sonst
  /// ließe sich eine gestapelte Serie nie durchblättern, da alle anderen
  /// Mitglieder ja absichtlich aus der Rasteransicht ausgeblendet sind.
  ///
  /// **Hier werden die vollen Zeilen nachgeholt.** Das Raster arbeitet mit
  /// der schmalen [Rasterzeile]; der Betrachter braucht alles – Blende,
  /// Brennweite, Beschriftung, Entwicklungsstand. Nachgeholt wird beim
  /// Antippen und nicht vorgehalten: An der gewachsenen Bibliothek kostet
  /// das rund achtzig Millisekunden, und die liegen hinter der
  /// Übergangsanimation des Bildschirmwechsels. Vorgehalten kosteten sie
  /// dasselbe – nur bei **jeder** Änderung an der Tabelle statt einmal
  /// beim Öffnen.
  Future<void> _openViewer(List<Rasterzeile> zeilen, Rasterzeile zeile) async {
    final viewerAssets = (zeile.isStackCover && zeile.stackId != null)
        ? await widget.library.db.assetsInStack(zeile.stackId!)
        : await widget.library.db
            .assetsByIds([for (final z in zeilen) z.id]);
    if (!mounted) return;
    final initialIndex = viewerAssets.indexWhere((a) => a.id == zeile.id);
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: viewerAssets,
        initialIndex: initialIndex < 0 ? 0 : initialIndex,
        paths: widget.library.paths,
        db: widget.library.db,
        library: widget.library,
        onToggleFavorite: (a) => widget.library.db.setFavorite(a.id, !a.isFavorite),
        onDelete: (a) => widget.library.db.moveToTrash([a.id]),
        onLock: (a) async {
          if (await ensureVaultUnlocked(context, widget.library)) {
            await widget.library.lockAsset(a);
          }
        },
      ),
    ));
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    final confirmed = await confirmDialog(
      context,
      AppTexte.of(context).loeschenTitel(ids.length),
      AppTexte.of(context).loeschenHinweis(ids.length),
    );
    if (!confirmed) return;
    await widget.library.db.moveToTrash(ids);
    if (mounted) setState(_selected.clear);
  }



  /// Die schmale Leiste über der Ansicht: Raster oder Liste, und – nur bei
  /// der Liste – wonach gegliedert wird.
  ///
  /// Die Gliederung erscheint erst mit der Liste, weil das Raster
  /// grundsätzlich nach Monaten gegliedert ist; ein Wahlfeld daneben, das
  /// nichts bewirkt, wäre irreführend.
  Widget _ansichtsLeiste(BuildContext context) {
    final t = AppTexte.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
      child: Row(
        children: [
          SegmentedButton<bool>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.grid_view, size: 16),
                tooltip: t.ansichtRaster,
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.view_list_outlined, size: 16),
                tooltip: t.ansichtListe,
              ),
            ],
            selected: {_alsListe},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _alsListe = s.first),
          ),
          if (_alsListe && _gliedert) ...[
            const SizedBox(width: AppSpacing.md),
            DropdownButton<ListenGruppierung>(
              value: _gruppierung,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                    value: ListenGruppierung.monat, child: Text(t.gruppeMonat)),
                DropdownMenuItem(
                    value: ListenGruppierung.kamera, child: Text(t.gruppeKamera)),
                DropdownMenuItem(
                    value: ListenGruppierung.keine, child: Text(t.gruppeKeine)),
              ],
              onChanged: (wahl) =>
                  setState(() => _gruppierung = wahl ?? ListenGruppierung.monat),
            ),
          ],
          const Spacer(),
          // Die Reihenfolge gilt fuer beide Ansichten, steht also vor der
          // Trennung in Raster und Liste.
          Sortierungswahl(
              gewaehlt: _sortierung, beiWahl: _setzeSortierung),
          // Kleiner heisst mehr Fotos und damit mehr Monate auf einmal.
          // Nur im Raster: In der Liste steht ohnehin alles
          // untereinander, und ein Knopf, der nichts bewirkt, waere
          // irrefuehrend - dieselbe Regel wie bei der Gliederung.
          if (!_alsListe) ...[
            // Die Form vor der Groesse: Sie entscheidet, was die beiden
            // Zoomknoepfe daneben ueberhaupt bedeuten - Kachelbreite bei
            // Quadraten, Reihenhoehe bei Reihen.
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _form == Zeitleistenform.quadrate
                  ? t.zeitleisteFormReihen
                  : t.zeitleisteFormQuadrate,
              icon: Icon(
                  _form == Zeitleistenform.quadrate
                      ? Icons.view_stream_outlined
                      : Icons.grid_view_outlined,
                  size: 20),
              onPressed: _wechsleForm,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: t.zeitleisteKleiner,
              icon: const Icon(Icons.zoom_out, size: 20),
              onPressed:
                  _kachelstufe == 0 ? null : () => _zoome(groesser: false),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: t.zeitleisteGroesser,
              icon: const Icon(Icons.zoom_in, size: 20),
              onPressed: _kachelstufe == zeitleisteKachelstufen.length - 1
                  ? null
                  : () => _zoome(groesser: true),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvingHighlight) return const Center(child: CircularProgressIndicator());
    return _alsListe ? _mitVollenZeilen() : _mitSchmalenZeilen();
  }

  /// Der Regelfall: das Raster, mit den zwanzig Spalten, die es anfasst.
  Widget _mitSchmalenZeilen() {
    return StreamBuilder<List<Rasterzeile>>(
      stream: _zeitleiste.hole(
          (_windowSize, _sortierung),
          () => widget.library.db.watchRasterzeilen(
              limit: _windowSize, sortierung: _sortierung)),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return _inhalt(context, snapshot.data!, null);
      },
    );
  }

  /// Die Listenansicht, mit allem.
  ///
  /// Die schmalen Zeilen entstehen hier aus den vollen – einmal je
  /// Meldung des Stroms und nicht bei jedem Neuaufbau, damit die
  /// Tastensteuerung dieselbe Liste sieht wie das Raster.
  Widget _mitVollenZeilen() {
    return StreamBuilder<List<AssetData>>(
      stream: _liste.hole(
          (_windowSize, _sortierung),
          () => widget.library.db
              .watchTimeline(limit: _windowSize, sortierung: _sortierung)),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final voll = snapshot.data!;
        if (!identical(voll, _volleQuelle)) {
          _volleQuelle = voll;
          _volleZeilen = [for (final a in voll) Rasterzeile.aus(a)];
        }
        return _inhalt(context, _volleZeilen, voll);
      },
    );
  }

  List<AssetData>? _volleQuelle;
  List<Rasterzeile> _volleZeilen = const [];

  Widget _inhalt(
      BuildContext context, List<Rasterzeile> assets, List<AssetData>? voll) {
    {
      {
        _geladen = assets;
        if (assets.isEmpty) {
          return EmptyState(
            icon: Icons.photo_outlined,
            message: AppTexte.of(context).timelineLeer,
            actionLabel: AppTexte.of(context).importierenTooltip,
            onAction: () => showImportSheet(context, widget.library),
          );
        }

        return mitTastatur(
            kind: Stack(
          children: [
            Column(
              children: [
                _ansichtsLeiste(context),
                Expanded(
                  // Die Spaltenzahl steht nur hier fest, wird aber beim
                  // Tastendruck gebraucht – dort gibt es keine Constraints.
                  child: LayoutBuilder(builder: (context, constraints) {
                    final mitZeitstrahl = _gliedert &&
                        rasterMitZeitstrahl(monatsgruppen(assets,
                                absteigend: sortierungAbsteigend(_sortierung))
                            .schluessel
                            .length);
                    _rasterbreite = rasterGridbreite(constraints.maxWidth,
                        mitZeitstrahl: mitZeitstrahl);
                    _spalten = _alsListe
                        ? 1
                        : rasterSpaltenzahl(
                            constraints.maxWidth,
                            mitZeitstrahl: mitZeitstrahl,
                            kachelbreite: _kachelbreite,
                          );
                    return _alsListe
                        ? AssetListView(
                            assets: voll ?? const [],
                            paths: widget.library.paths,
                            gruppierung: _wirksameGruppierung,
                            absteigend: sortierungAbsteigend(_sortierung),
                            selectedIds: _selected,
                            highlightAssetId: widget.highlightAssetId,
                            nachObenSignal: widget.nachObenSignal,
                            spalten: _listenspalten,
                            onSpalten: _setzeSpalten,
                            onLongPress: (asset) => _toggle(asset.id),
                            // Die Liste haelt volle Zeilen, die Auswahl
                            // arbeitet mit schmalen - umgesetzt wird ueber
                            // die Kennung, nicht ueber das Objekt.
                            onTap: (asset) => rasterKlick(
                                Rasterzeile.aus(asset)),
                          )
                        : MonthGroupedAssetGrid(
                            assets: assets,
                            paths: widget.library.paths,
                            highlightAssetId: widget.highlightAssetId,
                            aktiveKachelId: aktiveKachel,
                            nachObenSignal: widget.nachObenSignal,
                            selectedIds: _selected,
                            onLongPress: (asset) => _toggle(asset.id),
                            onHeaderTap: _toggleGroup,
                            onTap: rasterKlick,
                            kachelbreite: _kachelbreite,
                            form: _form,
                            gliedern: _gliedert,
                            absteigend: sortierungAbsteigend(_sortierung),
                            onScrollNearEnd: () => _maybeGrowWindow(assets.length),
                          );
                  }),
                ),
              ],
            ),
            if (_selected.isNotEmpty)
              SelectionActionBar(
                count: _selected.length,
                onClear: () => setState(_selected.clear),
                onCompare: vergleichsAktion(context, widget.library, _selected.toList()),
                // Nur sichtbar, wenn tatsächlich Einstellungen kopiert
                // wurden – ein Knopf, der meistens nichts tun kann, wäre
                // in einer Leiste mit neun Symbolen nur Rauschen.
                onPasteDevelop: widget.library.hatKopierteEntwicklung
                    ? () async {
                        await runBatchPasteDevelop(context, widget.library, _selected.toList());
                        if (mounted) setState(_selected.clear);
                      }
                    : null,
                onApplyPreset: () =>
                    runBatchApplyPreset(context, widget.library, _selected.toList()),
                onFavorite: () async {
                  await runBatchFavorite(widget.library, _selected.toList());
                  if (mounted) setState(_selected.clear);
                },
                onAddToAlbum: () async {
                  await runBatchAddToAlbumDialog(context, widget.library, _selected.toList());
                  if (mounted) setState(_selected.clear);
                },
                onTag: () async {
                  await runBatchTagDialog(context, widget.library, _selected.toList());
                  if (mounted) setState(_selected.clear);
                },
                onSetRating: () async {
                  await runBatchSetRating(context, widget.library, _selected.toList());
                  if (mounted) setState(_selected.clear);
                },
                onSetColorLabel: () async {
                  await runBatchSetColorLabel(context, widget.library, _selected.toList());
                  if (mounted) setState(_selected.clear);
                },
                onEditMetadata: () async {
                  await runBatchEditMetadataDialog(context, widget.library, _selected.toList());
                  if (mounted) setState(_selected.clear);
                },
                onExport: () async {
                  // Die Ausfuhr schreibt Beipackzettel und braucht dafuer
                  // die ganze Zeile - hier nachgeholt statt vorgehalten.
                  final selectedAssets = await widget.library.db
                      .assetsByIds(_selected.toList());
                  if (!context.mounted) return;
                  await runBatchExport(context, widget.library, selectedAssets);
                  if (mounted) setState(_selected.clear);
                },
                onDelete: _deleteSelected,
              ),
          ],
        ));
      }
    }
  }
}
