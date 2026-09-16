import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/month_grouped_asset_grid.dart';
import '../widgets/rasterbedienung.dart';
import '../widgets/pin_dialogs.dart';
import '../widgets/selection_action_bar.dart';
import 'asset_viewer_screen.dart';
import '../widgets/stromhalter.dart';

/// Jahresübersicht: eine Kachel pro Jahr mit Titelbild (neuestes Foto des
/// Jahres) und Foto-/Videoanzahl – zum schnellen Einstieg in ein bestimmtes
/// Jahr, ohne die komplette Timeline durchscrollen zu müssen.
/// Kantenlaenge einer Monatskachel – zugleich die Dekodiergroesse des
/// Vorschaubilds darin.
const double _kachelKante = 200;

class CalendarScreen extends StatelessWidget {
  final LibraryState library;
  const CalendarScreen({super.key, required this.library});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<int, int>>(
      stream: library.db.watchAssetCountsByYear(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final countByYear = snapshot.data!;
        if (countByYear.isEmpty) {
          return Center(child: Text(AppTexte.of(context).kalenderLeer));
        }

        final years = countByYear.keys.toList()..sort((a, b) => b.compareTo(a));

        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 320,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.3,
          ),
          itemCount: years.length,
          itemBuilder: (context, index) {
            final year = years[index];
            return _YearCard(
              titel: '$year',
              assetCount: countByYear[year]!,
              library: library,
              titelbild: () => library.db.newestAssetForYear(year),
              // Erst der Monat, dann die Fotos: Ein Jahrgang von 1.400
              // Aufnahmen ist als eine Liste keine Übersicht mehr, und ein
              // bestimmter Monat war darin nur durch Scrollen zu finden.
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    MonatsuebersichtScreen(library: library, jahr: year),
              )),
            );
          },
        );
      },
    );
  }
}

/// Lädt sein Titelbild (neuestes Foto des Jahres) einmalig selbst, statt es
/// von [CalendarScreen] vorgeladen zu bekommen – so muss dessen
/// Jahresübersicht nur noch die günstige Zählung (`watchAssetCountsByYear`)
/// laden, nicht mehr die komplette Bibliothek, nur um pro Jahr das neueste
/// Foto herauszusuchen.
class _YearCard extends StatefulWidget {
  /// Was gross auf der Kachel steht – eine Jahreszahl oder ein Monatsname.
  final String titel;
  final int assetCount;
  final LibraryState library;
  final VoidCallback onTap;

  /// Wie das Titelbild geholt wird. Als Rückruf und nicht als fertiges
  /// Bild, damit die Übersicht darüber nur die günstige Zählung laden
  /// muss und nicht die halbe Bibliothek.
  final Future<AssetData?> Function() titelbild;

  const _YearCard({
    required this.titel,
    required this.assetCount,
    required this.library,
    required this.onTap,
    required this.titelbild,
  });

  @override
  State<_YearCard> createState() => _YearCardState();
}

class _YearCardState extends State<_YearCard> {
  late final Future<AssetData?> _coverFuture = widget.titelbild();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade900,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<AssetData?>(
              future: _coverFuture,
              builder: (context, snapshot) {
                final thumbPath = snapshot.data?.thumbnailRelativePath;
                if (thumbPath == null) return const SizedBox.shrink();
                return Image.file(
                  widget.library.paths.absolute(thumbPath),
                  fit: BoxFit.cover,
                  cacheWidth: (_kachelKante *
                          MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                );
              },
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.35, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.titel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppTexte.of(context).kalenderAnzahlFotos(widget.assetCount),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Die Monate eines Jahres – eine Kachel je Monat, mit Titelbild und
/// Anzahl.
///
/// **Die Zwischenstufe zwischen Jahr und Foto.** Vorher führte ein Klick
/// aufs Jahr unmittelbar in alle Aufnahmen des Jahres; an einem Jahrgang
/// von 1.400 Bildern ist das keine Übersicht mehr, sondern eine lange
/// Liste, in der ein bestimmter Monat nur durch Scrollen zu finden war.
///
/// Gezeigt werden **nur Monate mit Aufnahmen**. Zwölf Kacheln, von denen
/// sieben leer sind, sagen weniger als fünf volle.
class MonatsuebersichtScreen extends StatelessWidget {
  final LibraryState library;
  final int jahr;

  const MonatsuebersichtScreen({
    super.key,
    required this.library,
    required this.jahr,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).toString();
    return Scaffold(
      appBar: AppBar(
        title: Text('$jahr'),
        actions: [
          // Der alte Weg bleibt erreichbar: Wer das ganze Jahr am Stück
          // sehen will, soll dafür nicht durch zwölf Monate gehen.
          TextButton.icon(
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: Text(t.kalenderGanzesJahr),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => YearDetailScreen(library: library, year: jahr),
            )),
          ),
        ],
      ),
      body: StreamBuilder<Map<int, int>>(
        stream: library.db.watchAssetCountsByMonth(jahr),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final proMonat = snapshot.data!;
          if (proMonat.isEmpty) {
            return Center(child: Text(t.kalenderJahrLeer));
          }
          // Neueste zuerst – dieselbe Richtung wie die Jahre darüber und
          // wie die Zeitleiste.
          final monate = proMonat.keys.toList()..sort((a, b) => b.compareTo(a));
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.3,
            ),
            itemCount: monate.length,
            itemBuilder: (context, i) {
              final monat = monate[i];
              return _YearCard(
                titel: DateFormat.MMMM(sprache).format(DateTime(jahr, monat)),
                assetCount: proMonat[monat]!,
                library: library,
                titelbild: () => library.db.newestAssetForMonth(jahr, monat),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => YearDetailScreen(
                      library: library, year: jahr, monat: monat),
                )),
              );
            },
          );
        },
      ),
    );
  }
}

/// Alle Fotos/Videos eines Jahres **oder eines Monats**, gruppiert – wie
/// die Timeline, nur auf einen Zeitraum eingeschränkt (Einstieg über
/// [CalendarScreen] und [MonatsuebersichtScreen]).
class YearDetailScreen extends StatefulWidget {
  final LibraryState library;
  final int year;

  /// Auf diesen Monat eingeschränkt, oder `null` für das ganze Jahr.
  ///
  /// Der Unterschied ist nicht nur der Ausschnitt: Über ein Jahr wird
  /// nach Monaten gegliedert, über einen Monat nach **Tagen**. Sonst
  /// gäbe es dort genau eine Gruppe, und der Zeitstrahl daneben fiele
  /// mangels zweiter Gruppe weg (siehe [rasterMitZeitstrahl]).
  final int? monat;

  const YearDetailScreen({
    super.key,
    required this.library,
    required this.year,
    this.monat,
  });

  @override
  State<YearDetailScreen> createState() => _YearDetailScreenState();
}

class _YearDetailScreenState extends State<YearDetailScreen>
    with Rasterbedienung<YearDetailScreen, AssetData> {
  final Set<String> _selected = {};

  /// Siehe [Stromhalter]: Direkt im `stream:` erzeugt, fragte dieser Strom
  /// bei jedem Neubau von vorn – und Neubauten löst hier jeder Pfeiltasten-
  /// druck und jeder Klick in der Mehrfachauswahl aus. An einem Jahrgang von
  /// 1373 Aufnahmen gemessen: 5,8 ms je Neubau.
  final _jahresstrom = Stromhalter<List<AssetData>>();

  /// Siehe [Rasterbedienung]: beim Tastendruck gibt es weder den Datenstrom
  /// noch die Constraints.
  List<AssetData> _geladen = const [];
  int _spalten = 1;

  @override
  Set<String> get auswahl => _selected;

  @override
  AppDatabase get rasterDb => widget.library.db;

  @override
  List<AssetData> get rasterAssets => _geladen;

  @override
  String rasterKennung(AssetData zeile) => zeile.id;

  @override
  ({bool favorit, String? farbe}) rasterMerkmale(AssetData zeile) =>
      (favorit: zeile.isFavorite, farbe: zeile.colorLabel);

  @override
  int get rasterSpalten => _spalten;

  /// Ob nach Tagen gegliedert wird – genau dann, wenn ein Monat gemeint
  /// ist.
  bool get _nachTag => widget.monat != null;

  ({List<int> schluessel, Map<int, List<Rasterzeile>> gruppen}) _gruppen(
          List<Rasterzeile> a) =>
      _nachTag ? tagesgruppen(a) : monatsgruppen(a);

  /// Die schmalen Zeilen fürs Raster, aus den vollen abgeleitet.
  ///
  /// **Warum der Kalender die vollen behält.** Ein Jahr sind ein paar
  /// hundert bis zweitausend Aufnahmen – da lohnt die eigene Abfrage
  /// nicht, und der Betrachter, den ein Klick öffnet, bräuchte sie
  /// ohnehin. Umgewandelt wird deshalb einmal je Meldung des Stroms und
  /// nicht bei jedem Neuaufbau.
  List<AssetData>? _zeilenQuelle;
  List<Rasterzeile> _zeilen = const [];

  List<Rasterzeile> _zeilenFuer(List<AssetData> voll) {
    if (!identical(voll, _zeilenQuelle)) {
      _zeilenQuelle = voll;
      _zeilen = [for (final a in voll) Rasterzeile.aus(a)];
    }
    return _zeilen;
  }

  /// Die volle Zeile zu einer schmalen – für alles, was hinter dem
  /// Raster liegt.
  AssetData? _vollZu(Rasterzeile z) {
    for (final a in _geladen) {
      if (a.id == z.id) return a;
    }
    return null;
  }

  @override
  List<List<String>> get rasterGruppen {
    final m = _gruppen(_zeilenFuer(_geladen));
    return [for (final k in m.schluessel) [for (final a in m.gruppen[k]!) a.id]];
  }

  @override
  void rasterOeffne(AssetData asset) => _openViewer(_geladen, asset);

  /// Siehe [Rasterbedienung.rasterUmschalten]: Der Anker gehoert dazu.
  void _toggle(String id) => rasterUmschalten(id);

  /// Auf die Monatsüberschrift getippt: alle Fotos/Videos des Monats
  /// auswählen – oder, falls bereits alle ausgewählt sind, wieder abwählen.
  void _toggleGruppe(List<String> kennungen) =>
      rasterGruppeUmschalten(kennungen);

  void _openViewer(List<AssetData> assets, AssetData asset) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: assets,
        initialIndex: assets.indexOf(asset),
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

  String _titel(BuildContext context) {
    if (widget.monat == null) return '${widget.year}';
    return DateFormat.yMMMM(Localizations.localeOf(context).toString())
        .format(DateTime(widget.year, widget.monat!));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titel(context))),
      body: StreamBuilder<List<AssetData>>(
        // Der Schlüssel muss den Monat mittragen, sonst lieferte der
        // Halter beim Wechsel von Juli nach August weiter den Juli.
        stream: _jahresstrom.hole(
            widget.year * 100 + (widget.monat ?? 0),
            () => widget.monat == null
                ? widget.library.db.watchTimelineForYear(widget.year)
                : widget.library.db
                    .watchTimelineForMonth(widget.year, widget.monat!)),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final yearAssets = snapshot.data!;
          _geladen = yearAssets;
          if (yearAssets.isEmpty) {
            return Center(child: Text(AppTexte.of(context).kalenderJahrLeer));
          }
          return mitTastatur(
              kind: Stack(
            children: [
              LayoutBuilder(builder: (context, constraints) {
                final zeilen = _zeilenFuer(yearAssets);
                _spalten = rasterSpaltenzahl(
                  constraints.maxWidth,
                  mitZeitstrahl: rasterMitZeitstrahl(
                      _gruppen(zeilen).schluessel.length),
                );
                return MonthGroupedAssetGrid(
                  nachTag: _nachTag,
                  assets: zeilen,
                  paths: widget.library.paths,
                  selectedIds: _selected,
                  aktiveKachelId: aktiveKachel,
                  onLongPress: (asset) => _toggle(asset.id),
                  onHeaderTap: (gruppe) => _toggleGruppe(
                      [for (final z in gruppe) z.id]),
                  onTap: (z) {
                    final voll = _vollZu(z);
                    if (voll != null) rasterKlick(voll);
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
                    final selectedAssets = yearAssets.where((a) => _selected.contains(a.id)).toList();
                    await runBatchExport(context, widget.library, selectedAssets);
                    if (mounted) setState(_selected.clear);
                  },
                  onDelete: _deleteSelected,
                ),
            ],
          ));
        },
      ),
    );
  }
}
