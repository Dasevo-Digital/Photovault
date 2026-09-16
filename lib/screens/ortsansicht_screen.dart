import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../services/laenderkatalog.dart';
import '../services/ortsuebersicht.dart';
import '../services/reisefortschritt.dart';
import '../services/search_filters.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/pin_dialogs.dart';
import 'asset_viewer_screen.dart';

/// Was an einem Ort war: Zahlen, die nächste Ebene, die Fotos.
///
/// **Ein Bildschirm für drei Ebenen.** Land, Region und Ort beantworten
/// dieselbe Frage, und wer sie dreimal baut, baut sie dreimal
/// verschieden. Der Unterschied steckt in [Ortsebene] und sonst nirgends.
///
/// Erreichbar aus der Länderliste (Klick auf ein Land) und von der
/// Weltkarte (Klick auf einen Punkt). Von hier führt der Weg weiter nach
/// unten: Land zu Region zu Ort.
class OrtsansichtScreen extends StatefulWidget {
  final LibraryState library;
  final Ortsebene ebene;
  final String schluessel;
  final String name;

  const OrtsansichtScreen({
    super.key,
    required this.library,
    required this.ebene,
    required this.schluessel,
    required this.name,
  });

  @override
  State<OrtsansichtScreen> createState() => _OrtsansichtScreenState();
}

class _OrtsansichtScreenState extends State<OrtsansichtScreen> {
  Ortsuebersicht? _stand;
  List<AssetData> _fotos = const [];
  Landeintragung? _land;
  bool _laeuft = true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  /// Land, Region und Ort als Namen – so, wie die Fotos sie tragen.
  ///
  /// Die Aufnahmen speichern den ausgeschriebenen Namen, die Kataloge
  /// rechnen mit Codes. Für die Fotoabfrage wird also zurückübersetzt.
  ({String? land, String? region, String? ort}) _namen() {
    final geo = widget.library.geocoder;
    switch (widget.ebene) {
      case Ortsebene.land:
        return (
          land: geo?.laenderkatalog.nachIso(widget.schluessel)?.name,
          region: null,
          ort: null
        );
      case Ortsebene.region:
        final punkt = widget.schluessel.indexOf('.');
        if (punkt <= 0) return (land: null, region: null, ort: null);
        final iso = widget.schluessel.substring(0, punkt);
        return (
          land: geo?.laenderkatalog.nachIso(iso)?.name,
          region: widget.name,
          ort: null,
        );
      case Ortsebene.ort:
        // „Land|Region|Ort", genau wie die Ortsmarken es führen.
        final teile = widget.schluessel.split('|');
        if (teile.length < 3) return (land: null, region: null, ort: null);
        return (
          land: teile[0].isEmpty ? null : teile[0],
          region: teile[1].isEmpty ? null : teile[1],
          ort: teile[2],
        );
    }
  }

  Future<void> _laden() async {
    final db = widget.library.db;
    final geo = widget.library.geocoder;
    final angaben = await db.besuchteOrte();
    final marken = await db.alleOrtsmarken();

    // Was der Datensatz unter diesem Ort kennt – auch das Unbesuchte.
    final bekannt = switch (widget.ebene) {
      Ortsebene.land => geo?.regionenVon(widget.schluessel) ?? const [],
      Ortsebene.region => geo?.orteIn(widget.schluessel) ?? const [],
      Ortsebene.ort => const <({String schluessel, String name})>[],
    };

    final stand = ortsuebersicht(
      ebene: widget.ebene,
      schluessel: widget.schluessel,
      name: widget.name,
      angaben: angaben,
      nachIso: geo?.isoNachName ?? const {},
      regionscodes: geo?.regionscodes ?? const {},
      bekannteUnterorte: bekannt,
      marken: [
        for (final m in marken)
          (
            art: m.art,
            schluessel: m.schluessel,
            wert: m.status == 'geplant' ? Markenart.geplant : Markenart.besucht,
          ),
      ],
    );

    final n = _namen();
    final fotos = n.land == null
        ? <AssetData>[]
        : await db.searchAssets(SearchFilters(
            locationCountry: n.land,
            locationState: n.region,
            locationCity: n.ort,
          ));

    if (!mounted) return;
    setState(() {
      _stand = stand;
      _fotos = fotos;
      _land = widget.ebene == Ortsebene.land
          ? geo?.laenderkatalog.nachIso(widget.schluessel)
          : null;
      _laeuft = false;
    });
  }

  Future<void> _markieren(Markenart? wert) async {
    final art = switch (widget.ebene) {
      Ortsebene.land => 'land',
      Ortsebene.region => 'region',
      Ortsebene.ort => 'ort',
    };
    if (wert == null) {
      await widget.library.db.loescheOrtsmarke(art, widget.schluessel);
    } else {
      await widget.library.db.setzeOrtsmarke(OrtsmarkenCompanion.insert(
        art: art,
        schluessel: widget.schluessel,
        name: widget.name,
        status: wert == Markenart.geplant ? 'geplant' : 'besucht',
        angelegtAm: DateTime.now(),
      ));
    }
    await _laden();
  }

  void _weiter(Unterort u) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => OrtsansichtScreen(
            library: widget.library,
            // Unter einem Land liegen Regionen, unter einer Region Orte.
            ebene: widget.ebene == Ortsebene.land
                ? Ortsebene.region
                : Ortsebene.ort,
            schluessel: u.schluessel,
            name: u.name,
          ),
        ))
        // Nach der Rückkehr neu laden: Dort unten konnte eine Marke
        // gesetzt worden sein, und die zählt hier oben mit.
        .then((_) => _laden());
  }

  void _fotoOeffnen(AssetData asset) {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(
          builder: (_) => AssetViewerScreen(
            assets: _fotos,
            initialIndex: _fotos.indexOf(asset),
            paths: widget.library.paths,
            db: widget.library.db,
            library: widget.library,
            onToggleFavorite: (a) =>
                widget.library.db.setFavorite(a.id, !a.isFavorite),
            onDelete: (a) => widget.library.db.moveToTrash([a.id]),
            onLock: (a) async {
              if (await ensureVaultUnlocked(context, widget.library)) {
                await widget.library.lockAsset(a);
              }
            },
          ),
        ))
        .then((_) => _laden());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final stand = _stand;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _laeuft || stand == null
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Kopf(stand: stand, land: _land),
                ),
                SliverToBoxAdapter(
                  child: _Markenwahl(
                    marke: stand.marke,
                    beiWahl: _markieren,
                  ),
                ),
                if (stand.unterorte.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _Abschnitt(widget.ebene == Ortsebene.land
                        ? t.ortRegionen(
                            stand.unterorteBesucht, stand.unterorteGesamt)
                        : t.ortOrte(
                            stand.unterorteBesucht, stand.unterorteGesamt)),
                  ),
                  SliverList.builder(
                    itemCount: stand.unterorte.length,
                    itemBuilder: (_, i) => _Unterortzeile(
                      unterort: stand.unterorte[i],
                      beiTippen: () => _weiter(stand.unterorte[i]),
                    ),
                  ),
                ],
                if (_fotos.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _Abschnitt(t.ortFotos(_fotos.length)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 140,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                      ),
                      itemCount: _fotos.length,
                      itemBuilder: (_, i) => AssetThumbnailTile(
                        asset: Rasterzeile.aus(_fotos[i]),
                        paths: widget.library.paths,
                        onTap: () => _fotoOeffnen(_fotos[i]),
                      ),
                    ),
                  ),
                ],
                if (_fotos.isEmpty && stand.unterorte.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        t.ortNichtsHier,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.xl)),
              ],
            ),
    );
  }
}

/// Flagge, Zahlen, Fortschritt.
class _Kopf extends StatelessWidget {
  final Ortsuebersicht stand;
  final Landeintragung? land;
  const _Kopf({required this.stand, required this.land});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final flagge = land == null ? null : flaggeAus(land!.iso);
    final zeile = [
      if (land?.hauptstadt case final h?) h,
      if (stand.aufnahmen > 0) t.laenderAufnahmen(stand.aufnahmen),
      if (stand.marke == Markenart.besucht) t.laenderVonHand,
      if (stand.marke == Markenart.geplant) t.laenderGeplant,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nicht jede Plattform hat Flaggen in ihrer Schrift. Der Name
          // steht daneben, nicht darin – die Zeile bleibt lesbar.
          if (flagge != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Text(flagge, style: const TextStyle(fontSize: 40)),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stand.name,
                    style: Theme.of(context).textTheme.headlineSmall),
                if (zeile.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(zeile,
                        style: TextStyle(
                            fontSize: 13, color: farben.onSurfaceVariant)),
                  ),
                if (stand.unterorteGesamt > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    // Derselbe schmale Balken wie in der Länderliste – wer
                    // von dort kommt, soll dieselbe Anzeige wiederfinden.
                    child: Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            child: LinearProgressIndicator(
                              value: stand.unterorteBesucht /
                                  stand.unterorteGesamt,
                              minHeight: 5,
                              backgroundColor: farben.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${stand.unterorteBesucht}/${stand.unterorteGesamt}',
                          style: TextStyle(
                              fontSize: 11, color: farben.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Besucht, geplant oder keins von beidem.
class _Markenwahl extends StatelessWidget {
  final Markenart? marke;
  final void Function(Markenart?) beiWahl;
  const _Markenwahl({required this.marke, required this.beiWahl});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          // Ein zweites Antippen nimmt die Marke zurück – derselbe Weg
          // hin wie zurück, wie auf der Weltkarte.
          ChoiceChip(
            avatar: const Icon(Icons.check_circle_outline, size: 18),
            label: Text(t.laenderBesucht),
            selected: marke == Markenart.besucht,
            onSelected: (an) => beiWahl(an ? Markenart.besucht : null),
          ),
          ChoiceChip(
            avatar: const Icon(Icons.flag_outlined, size: 18),
            label: Text(t.laenderGeplant),
            selected: marke == Markenart.geplant,
            onSelected: (an) => beiWahl(an ? Markenart.geplant : null),
          ),
        ],
      ),
    );
  }
}

class _Abschnitt extends StatelessWidget {
  final String titel;
  const _Abschnitt(this.titel);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
        child: Text(titel, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// Eine Region unter einem Land, ein Ort unter einer Region.
class _Unterortzeile extends StatelessWidget {
  final Unterort unterort;
  final VoidCallback beiTippen;
  const _Unterortzeile({required this.unterort, required this.beiTippen});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    // Symbol UND Farbe, nicht nur Farbe: Drei Zustände, die man allein am
    // Farbton unterscheidet, sind für einen Rotgrünblinden einer.
    final (symbol, farbe) = switch (unterort) {
      _ when unterort.aufnahmen > 0 => (Icons.check_circle, farben.primary),
      // Ein eigener Haken und ein Haken eine Ebene tiefer sehen gleich aus:
      // Beides heisst „ohne Foto belegt". Welcher es war, steht eine
      // Ebene weiter, wo man ihn auch wieder wegnehmen kann.
      _ when unterort.marke == Markenart.besucht || unterort.abgeleitet => (
          Icons.check_circle_outline,
          farben.primary
        ),
      // NACH der Ableitung: Ein Vorhaben, in dem schon jemand war, ist
      // kein Vorhaben mehr.
      _ when unterort.marke == Markenart.geplant => (
          Icons.flag_outlined,
          farben.secondary
        ),
      _ => (Icons.circle_outlined, farben.outline),
    };
    return ListTile(
      onTap: beiTippen,
      leading: Icon(symbol, color: farbe),
      title: Text(unterort.name,
          style: unterort.besucht
              ? null
              : TextStyle(color: farben.onSurfaceVariant)),
      subtitle: unterort.aufnahmen > 0
          ? Text(t.laenderAufnahmen(unterort.aufnahmen),
              style: const TextStyle(fontSize: 12))
          : null,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
