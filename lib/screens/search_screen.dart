import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../widgets/namens_dialog.dart' show MitTextsteuerung;
import '../services/clip_service.dart';
import '../services/search_filters.dart';
import '../services/sortierung.dart';
import '../services/suchsatz.dart';
import '../services/videostandbilder.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/pin_dialogs.dart';
import '../widgets/search_options_sheet.dart';
import '../widgets/rasterbedienung.dart';
import '../widgets/selection_action_bar.dart';
import '../widgets/sortierungswahl.dart';
import 'asset_viewer_screen.dart';

class SearchScreen extends StatefulWidget {
  final LibraryState library;

  /// Filter, mit denen der Bildschirm aufgeht – und die er sofort
  /// ausfuehrt.
  ///
  /// **Wofuer.** Ein intelligentes Album ist eine gespeicherte Suche, und
  /// eines zu oeffnen heisst, genau diese Suche laufen zu lassen. Statt
  /// die Trefferansicht ein viertes Mal nachzubauen (Zeitleiste, Album,
  /// Suche haben sie bereits), oeffnet das Album diesen Bildschirm mit
  /// seinen Filtern. Der Nebeneffekt ist der eigentliche Gewinn: Man kann
  /// darin weitersuchen, statt in einer Sackgasse zu stehen.
  final SearchFilters? startFilter;

  /// Ueberschrift, wenn der Bildschirm als eigene Seite aufgeht. `null`
  /// heisst: Er sitzt in einem Reiter und braucht keine.
  final String? titel;

  const SearchScreen({
    super.key,
    required this.library,
    this.startFilter,
    this.titel,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with Rasterbedienung<SearchScreen, AssetData> {
  final _queryCtrl = TextEditingController();
  SearchFilters _filters = const SearchFilters();
  bool _loading = false;
  /// Erklärt eine ungewöhnlich lange Wartezeit – bisher nur das
  /// einmalige Laden des Bildsuche-Modells. Null, solange es nichts
  /// zu erklären gibt.
  String? _statusText;
  bool _searched = false;

  /// Die Treffer in der Reihenfolge, in der die Suche sie gefunden hat –
  /// bei der Bildersuche nach Ähnlichkeit, sonst nach Aufnahmedatum.
  ///
  /// Getrennt von [_results], weil sich diese Reihenfolge durch keine
  /// Spalte nachbilden lässt: Wer auf „Fundreihenfolge" zurückstellt,
  /// bekäme sie sonst nicht wieder.
  List<AssetData> _funde = [];

  /// Die Treffer so, wie sie dastehen – [_funde] in der eingestellten
  /// Reihenfolge.
  List<AssetData> _results = [];

  /// Wonach die Treffer geordnet werden; `null` heisst Fundreihenfolge.
  ///
  /// **In Dart geordnet und nicht im `ORDER BY`.** Die Suche holt ihre
  /// Treffer vollständig statt seitenweise, und bei der Bildersuche
  /// entsteht die Reihenfolge überhaupt erst danach, aus den
  /// Ähnlichkeiten. Ein zweites `ORDER BY` in der Abfrage würde die
  /// zweite Hälfte davon gar nicht erreichen.
  Rastersortierung? _sortierung;
  String? _error;
  final Set<String> _selected = {};

  /// Siehe [Rasterbedienung]. Anders als Zeitleiste und Album hängt die
  /// Trefferliste an keinem Datenstrom – nach einer Bewertung per Taste muss
  /// sie deshalb selbst nachgeladen werden, sonst zeigten die Kacheln weiter
  /// die alten Sterne.
  int _spalten = 1;

  /// Was der Satzleser aus der letzten Eingabe herausgelesen hat (siehe
  /// `suchsatz.dart`). Wird unter dem Feld angezeigt – eine Suche, die
  /// stillschweigend etwas anderes tut, als dasteht, ist die schlimmste Art
  /// von Suche.
  List<Satzfund> _satzfunde = const [];

  /// Die Wortlisten aus der Bibliothek, einmal je Sitzung geholt. Personen
  /// und Orte ändern sich selten, und die Abfrage bei jedem Tastendruck
  /// erneut zu stellen wäre bei 8000 Aufnahmen spürbar.
  Suchvokabular? _vokabular;

  @override
  Set<String> get auswahl => _selected;

  @override
  AppDatabase get rasterDb => widget.library.db;

  @override
  List<AssetData> get rasterAssets => _results;

  @override
  String rasterKennung(AssetData zeile) => zeile.id;

  @override
  ({bool favorit, String? farbe}) rasterMerkmale(AssetData zeile) =>
      (favorit: zeile.isFavorite, farbe: zeile.colorLabel);

  @override
  int get rasterSpalten => _spalten;

  @override
  void rasterOeffne(AssetData asset) {
    final index = _results.indexWhere((a) => a.id == asset.id);
    if (index >= 0) _openViewer(index);
  }

  @override
  Future<void> rasterAktualisieren() async {
    final frisch =
        await widget.library.db.assetsByIds([for (final a in _funde) a.id]);
    if (mounted) setState(() => _zeigeFunde(frisch));
  }

  /// Übernimmt eine Trefferliste und ordnet sie nach [_sortierung].
  ///
  /// Nur innerhalb eines `setState` aufrufen – die Methode setzt bloss
  /// die beiden Felder.
  void _zeigeFunde(List<AssetData> funde) {
    _funde = funde;
    final s = _sortierung;
    _results = s == null
        ? funde
        : (List<AssetData>.of(funde)..sort(sortierungVergleicher(s)));
  }

  void _setzeSortierung(Rastersortierung? wahl) {
    if (wahl == _sortierung) return;
    setState(() {
      _sortierung = wahl;
      // Wie in der Zeitleiste: Der Rahmen darf nicht auf einem anderen
      // Foto wieder auftauchen.
      aktiveKachel = null;
      anker = null;
      _zeigeFunde(_funde);
    });
  }

  /// Siehe [Rasterbedienung.rasterUmschalten]: Der Anker gehoert dazu.
  void _toggleSelected(String id) => rasterUmschalten(id);

  void _openViewer(int index) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: _results,
        initialIndex: index,
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

  /// Fragt einen Namen ab und speichert die aktuellen Filter als
  /// "Intelligentes Album" (siehe AppDatabase.createSavedSearch) – läuft bei
  /// jedem Antippen live gegen die aktuelle Bibliothek, statt (wie ein
  /// normales Album) eine feste Foto-Liste festzuhalten.
  Future<void> _saveCurrentSearch() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => MitTextsteuerung(
          builder: (context, ctrl) => AlertDialog(
        title: Text(AppTexte.of(context).sucheSpeichernTitel),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: AppTexte.of(context).allgName),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: Text(AppTexte.of(context).allgSpeichern)),
                ],
              )),
    );
    if (name == null || name.isEmpty) return;
    await widget.library.db.createSavedSearch(const Uuid().v4(), name, _filters);
  }

  Future<void> _loadSavedSearch(SearchFilters filters) async {
    setState(() {
      _filters = filters;
      _queryCtrl.text = filters.query;
    });
    await _runSearch();
  }

  Future<void> _openSearchOptions() async {
    final result = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SearchOptionsSheet(library: widget.library, initialFilters: _filters),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filters = result;
      _queryCtrl.text = result.query;
    });
    await _runSearch();
  }

  Future<Suchvokabular> _holeVokabular() async {
    final vorhanden = _vokabular;
    if (vorhanden != null) return vorhanden;
    final db = widget.library.db;
    // Einmalige Abfragen und keine Ströme: Ein `watch(...).first` hängt
    // einen Beobachter an die Tabelle, lässt bei Abbruch einen Zeitgeber
    // zurück und wirft in einer frisch angelegten Bibliothek „Bad state: No
    // element". Genau daran ist der Prüfstand hier zuerst gescheitert.
    final personen = await db.allePersonen();
    final schlagwoerter = await db.alleTags();
    final neu = Suchvokabular(
      personen: {for (final p in personen) p.id: p.name},
      schlagwoerter: {for (final t in schlagwoerter) t.id: t.name},
      kameras: await db.distinctCameraModels(),
      laender: await db.distinctCountries(),
      regionen: await db.distinctAlleStates(),
      staedte: await db.distinctAlleCities(),
    );
    _vokabular = neu;
    return neu;
  }

  /// Die Eingabe erst deuten, dann suchen.
  ///
  /// **Nur von Hand ausgelöst**, nicht aus [_runSearch]: Eine gespeicherte
  /// Suche und das Optionen-Fenster liefern fertige Kriterien. Sie durch den
  /// Satzleser zu schicken hiesse, dass eine gespeicherte Suche morgen etwas
  /// anderes finden könnte als heute – genau die Zusage, die ein
  /// intelligentes Album gibt.
  ///
  /// Gedeutet wird nur die Bildsuche. In den anderen Textarten (Dateiname,
  /// Beschreibung, erkannter Text) ist die Eingabe wörtlich gemeint; wer dort
  /// nach „2019" sucht, meint die Zeichenfolge und keinen Zeitraum.
  Future<void> _satzSuche() async {
    final eingabe = _queryCtrl.text.trim();
    if (eingabe.isEmpty || _filters.textMode != SearchTextMode.context) {
      setState(() => _satzfunde = const []);
      await _runSearch();
      return;
    }
    final deutung = deuteSuchsatz(
      eingabe,
      vokabular: await _holeVokabular(),
      heute: DateTime.now(),
      grundlage: _filters,
    );
    if (!mounted) return;
    setState(() {
      _satzfunde = deutung.funde;
      if (deutung.hatVerstanden) {
        _filters = deutung.filter;
        _queryCtrl.text = deutung.rest;
      }
    });
    await _runSearch();
  }

  /// Nimmt die Deutung zurück: der ursprüngliche Satz wieder ins Feld, alle
  /// daraus abgeleiteten Kriterien weg.
  Future<void> _satzVerwerfen(String urspruenglich) async {
    setState(() {
      _satzfunde = const [];
      _filters = SearchFilters(textMode: _filters.textMode, query: urspruenglich);
      _queryCtrl.text = urspruenglich;
    });
    await _runSearch();
  }

  /// Warum nichts zurückkam, wenn es nicht an der Suchanfrage lag.
  ///
  /// Zwei Suchweisen brauchen einen Durchgang über die Bibliothek, bevor
  /// sie überhaupt etwas finden können: die KI-Bildsuche (CLIP) und die
  /// Suche im erkannten Text (OCR). Wer die App neu aufsetzt, hat beides
  /// noch nicht – und bekam dann "Keine Treffer" zu sehen. Das ist die
  /// falsche Auskunft: Gesucht wurde in einem leeren Verzeichnis.
  String? _leerGrund;

  Future<void> _runSearch() async {
    if (_filters.isEmpty) return;
    setState(() {
      _loading = true;
      _searched = true;
      _error = null;
      _leerGrund = null;
    });
    try {
      final query = _filters.query.trim();
      List<AssetData> results;
      final kontextSuche = _filters.textMode == SearchTextMode.context && query.isNotEmpty;

      Float32List? queryVector;
      if (kontextSuche) {
        // Nur der Text-Encoder – der Bildteil wird für eine Suchanfrage
        // nicht gebraucht (siehe LibraryState.clipTextHalter).
        final halter = widget.library.clipTextHalter;
        if (!halter.installiert) {
          // Ohne diese Meldung fiel die Suche stillschweigend auf eine
          // Suche ohne Suchbegriff zurück und lieferte einfach die
          // neuesten Fotos – für den Nutzer nicht von einem Treffer zu
          // unterscheiden (Audit-Fund).
          setState(() => _error = AppTexte.of(context).sucheModellFehlt);
          return;
        }
        // Beim ersten Mal wird ein mehrere hundert MB grosses Modell
        // geladen; das dauert spürbar und soll nicht wie eine langsame
        // Suche aussehen.
        if (!halter.istGeladen) {
          setState(() => _statusText = AppTexte.of(context).sucheModellLaedt);
        }
        // Der Text-Encoder versteht nur Englisch. Ist das Übersetzungs-
        // modell installiert und eingeschaltet, geht die Anfrage vorher
        // hindurch – sonst unverändert (siehe LibraryState.insEnglische).
        final anfrage = await widget.library.insEnglische(query);
        queryVector = await halter.mit((c) => c.embedText(anfrage));
        if (mounted) setState(() => _statusText = null);
      }

      if (queryVector != null) {
        // Bei Videos sind hier auch die weiteren Standbilder dabei –
        // ein Video ist nicht mehr ein einziges Bild (siehe
        // [LibraryState.suchkandidaten]).
        final embeddings = await widget.library.suchkandidaten();
        if (embeddings.isEmpty) {
          if (!mounted) return;
          setState(() {
            _zeigeFunde(const []);
            _leerGrund = AppTexte.of(context).sucheOhneEmbeddings;
          });
          return;
        }

        // Reihenfolge ist entscheidend: ERST die übrigen Filter anwenden,
        // DANN innerhalb dieser Treffermenge nach Ähnlichkeit ranken.
        // Andersherum (Audit-Fund) entschied das bibliotheksweite Top-200
        // darüber, was der Filter überhaupt noch zu sehen bekam: Wer
        // "Sonnenuntergang" sucht und zusätzlich auf ein Album einschränkt,
        // verlor damit jeden Treffer, der es global nicht unter die besten
        // 200 geschafft hatte – auch wenn das Album nur fünf Fotos umfasst.
        // Ohne gesetzte Filter bleibt das Ergebnis dasselbe wie zuvor.
        //
        // **Nur die Kennungen.** Gebraucht wird hier eine Frage nach
        // Zugehörigkeit – „darf diese Aufnahme in die Rangfolge?" –, und
        // dafür die vollen Zeilen aller 7163 Kandidaten zu lesen kostete
        // 81 ms je Suche. Die Kennungen kosten 4,3 ms; die 200 Zeilen,
        // die am Ende wirklich gezeigt werden, holt `assetsByIds`
        // danach für 2,6 ms.
        final erlaubt = (await widget.library.db.searchAssetIds(_filters)).toSet();
        final kandidaten = <String, Float32List>{
          for (final e in embeddings.entries)
            if (erlaubt.contains(
                LibraryState.aufnahmeAusSuchschluessel(e.key)))
              e.key: e.value,
        };
        // Etwas mehr als die 200, die am Ende stehen sollen: Ein Video
        // kann mit mehreren Standbildern in der Rangfolge auftauchen, und
        // die fallen gleich wieder zusammen.
        final ranked = ClipService.rankBySimilarity(queryVector, kandidaten,
            topK: 200 * (1 + videoStandbilderHoechstens));
        // searchAssets sortiert nach Datum – hier zählt die Ähnlichkeit.
        // Je Aufnahme zählt ihr bestes Standbild; die Rangfolge kommt
        // absteigend, das erste Auftreten ist also das beste.
        final gesehen = <String>{};
        final rangfolge = [
          for (final e in ranked)
            if (gesehen.add(LibraryState.aufnahmeAusSuchschluessel(e.key)))
              LibraryState.aufnahmeAusSuchschluessel(e.key),
        ].take(200).toList();
        // `assetsByIds` behält die übergebene Reihenfolge bei – die
        // Rangfolge nach Ähnlichkeit übersteht den Umweg also.
        results = await widget.library.db.assetsByIds(rangfolge);
      } else {
        results = await widget.library.db.searchAssets(_filters);
      }
      // Erst fragen, wenn wirklich nichts kam: Der Zähler läuft über die
      // ganze Bibliothek, und das ist kein Preis für jede Suche.
      String? grund;
      if (results.isEmpty && _filters.textMode == SearchTextMode.ocr) {
        if (await widget.library.db.zaehleMitErkanntemText() == 0) {
          if (!mounted) return;
          grund = AppTexte.of(context).sucheOhneTexterkennung;
        }
      }
      if (!mounted) return;
      setState(() {
        _zeigeFunde(results);
        _leerGrund = grund;
      });
    } on ModellUnbrauchbar catch (e) {
      // Eigener Zweig, weil hier etwas zu TUN ist: Der Rohtext war eine
      // C++-Zusicherung mit den Pfaden eines fremden Bauservers.
      if (!mounted) return;
      setState(
          () => _error = AppTexte.of(context).sucheModellUnbrauchbar(e.datei));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppTexte.of(context).sucheFehlgeschlagen('$e'));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = null;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final start = widget.startFilter;
    if (start == null) return;
    _filters = start;
    _queryCtrl.text = start.query;
    // Erst nach dem ersten Aufbau: `_runSearch` setzt Zustand und will
    // im Fehlerfall an `AppTexte.of(context)`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_runSearch());
    });
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inhalt = _inhalt(context);
    final titel = widget.titel;
    return titel == null
        ? inhalt
        : Scaffold(appBar: AppBar(title: Text(titel)), body: inhalt);
  }

  Widget _inhalt(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: TextField(
            controller: _queryCtrl,
            decoration: InputDecoration(
              hintText: switch (_filters.textMode) {
                SearchTextMode.context => AppTexte.of(context).suchePlatzhalterKontext,
                SearchTextMode.filename => AppTexte.of(context).suchePlatzhalterDateiname,
                SearchTextMode.description => AppTexte.of(context).suchePlatzhalterBeschreibung,
                SearchTextMode.ocr => AppTexte.of(context).suchePlatzhalterText,
                SearchTextMode.caption => AppTexte.of(context).suchePlatzhalterBildunterschrift,
              },
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_filters.isEmpty)
                    IconButton(
                      icon: const Icon(Icons.bookmark_add_outlined),
                      tooltip: AppTexte.of(context).sucheSpeichernTitel,
                      onPressed: _saveCurrentSearch,
                    ),
                  IconButton(
                    icon: Badge(isLabelVisible: !_filters.isEmpty, child: const Icon(Icons.tune)),
                    tooltip: AppTexte.of(context).sucheOptionen,
                    onPressed: _openSearchOptions,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    tooltip: AppTexte.of(context).sucheAusloesen,
                    onPressed: _loading ? null : _satzSuche,
                  ),
                ],
              ),
            ),
            onChanged: (v) => setState(() => _filters = _filters.copyWith(query: v)),
            onSubmitted: (_) => _satzSuche(),
          ),
        ),
        if (_satzfunde.isNotEmpty) _Satzmarken(funde: _satzfunde, beiVerwerfen: _satzVerwerfen),
        StreamBuilder<List<SavedSearchData>>(
          stream: widget.library.db.watchSavedSearches(),
          builder: (context, snapshot) {
            final saved = snapshot.data ?? [];
            if (saved.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, bottom: AppSpacing.md),
              child: SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: saved.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final entry = saved[index];
                    return InputChip(
                      avatar: const Icon(Icons.bookmark, size: 18),
                      label: Text(entry.name),
                      onPressed: () => _loadSavedSearch(widget.library.db.decodeSavedSearchFilters(entry.filtersJson)),
                      onDeleted: () => widget.library.db.deleteSavedSearch(entry.id),
                    );
                  },
                ),
              ),
            );
          },
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_statusText != null)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: Text(
              _statusText!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.all(AppSpacing.sm), child: Text(_error!)),
        // Die Reihenfolge erscheint erst mit Treffern: ein Knopf ueber
        // einer leeren Flaeche haette nichts zu ordnen.
        if (_searched && _results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Sortierungswahl(
                  gewaehlt: _sortierung,
                  beiWahl: _setzeSortierung,
                  mitFundreihenfolge: true,
                ),
              ],
            ),
          ),
        Expanded(
          child: !_searched
              ? Center(child: Text(AppTexte.of(context).sucheAnleitung))
              : _results.isEmpty && !_loading
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          _leerGrund ?? AppTexte.of(context).sucheKeineTreffer,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : mitTastatur(
                      kind: Stack(
                      children: [
                        LayoutBuilder(builder: (context, constraints) {
                          _spalten = flachesRasterSpalten(constraints.maxWidth,
                              seitenpolster: AppSpacing.md * 2);
                          return GridView.builder(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 160,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                            ),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final asset = _results[index];
                              final kachel = AssetThumbnailTile(
                                asset: Rasterzeile.aus(asset),
                                paths: widget.library.paths,
                                selected: _selected.contains(asset.id),
                                onLongPress: () => _toggleSelected(asset.id),
                                onTap: () => rasterKlick(asset),
                              );
                              return asset.id == aktiveKachel
                                  ? AktiveKachelRahmen(child: kachel)
                                  : kachel;
                            },
                          );
                        }),
                        if (_selected.isNotEmpty)
                          SelectionActionBar(
                            count: _selected.length,
                            onClear: () => setState(_selected.clear),
                            onCompare: vergleichsAktion(context, widget.library, _selected.toList()),

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
                              final selectedAssets = _results.where((a) => _selected.contains(a.id)).toList();
                              await runBatchExport(context, widget.library, selectedAssets);
                              if (mounted) setState(_selected.clear);
                            },
                            onDelete: _deleteSelected,
                          ),
                      ],
                    )),
        ),
      ],
    );
  }
}

/// Was der Satzleser aus der Eingabe gemacht hat, als Reihe von Marken.
///
/// Steht sichtbar unter dem Suchfeld und nicht in einem Hinweisfenster:
/// Wer „5 Sterne" tippt und plötzlich weniger Treffer bekommt, muss ohne
/// Suchen erkennen können, warum – und es mit einem Klick zurücknehmen.
class _Satzmarken extends StatelessWidget {
  final List<Satzfund> funde;
  final void Function(String urspruenglich) beiVerwerfen;

  const _Satzmarken({required this.funde, required this.beiVerwerfen});

  static String _artName(AppTexte t, Satzfundart art) => switch (art) {
        Satzfundart.person => t.navPersonen,
        Satzfundart.schlagwort => t.suchoptTagsTitel,
        Satzfundart.kamera => t.allgKamera,
        Satzfundart.ort => t.xmpFeldStandort,
        Satzfundart.zeitraum => t.famstatZeitraum,
        Satzfundart.bewertung => t.infoBewertung,
        Satzfundart.farbmarke => t.suchoptFarbmarkierung,
        Satzfundart.medienart => t.suchoptMedientyp,
        Satzfundart.favorit => t.auswFavorisieren,
        Satzfundart.schaerfe => t.suchoptNurUnscharfe,
        Satzfundart.iso => t.suchoptIso,
        Satzfundart.datumsherkunft => t.sucheDatumGeschaetzt,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    // Der Satz, wie er dastand – aus den Wortlauten wieder zusammengesetzt
    // reicht nicht, deshalb nimmt „Verwerfen" die Wortlaute in der
    // Reihenfolge der Funde plus den Rest.
    final urspruenglich = [for (final f in funde) f.wortlaut].join(' ');
    return Padding(
      padding: const EdgeInsets.only(
          left: AppSpacing.lg, right: AppSpacing.lg, bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in funde)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                      f.wert.isEmpty
                          ? _artName(t, f.art)
                          : '${_artName(t, f.art)}: ${f.wert}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.undo, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: t.sucheSatzVerwerfen,
            onPressed: () => beiVerwerfen(urspruenglich),
          ),
        ],
      ),
    );
  }
}
