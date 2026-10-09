import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../services/dokumenterkennung.dart';
import '../services/meldungsdienst.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/pin_dialogs.dart';
import 'asset_viewer_screen.dart';

typedef Dokumentvorschlag = ({AssetData asset, Dokumentfund fund});

/// Alle offen liegenden Aufnahmen, deren erkannter Text nach einem
/// Ausweis oder einer Karte aussieht – siehe [dokumentImText].
Future<List<Dokumentvorschlag>> ladeDokumentvorschlaege(AppDatabase db) async {
  final funde = <String, Dokumentfund>{};
  for (final (:id, :text) in await db.texteFuerDokumentsuche()) {
    final fund = dokumentImText(text);
    if (fund != null) funde[id] = fund;
  }
  final aufnahmen = await db.assetsByIds(funde.keys.toList())
    ..sort((a, b) => b.fileCreatedAt.compareTo(a.fileCreatedAt));
  return [for (final a in aufnahmen) (asset: a, fund: funde[a.id]!)];
}

String dokumentartText(AppTexte t, Dokumentart art) => switch (art) {
  Dokumentart.reisepass => t.dokumentArtReisepass,
  Dokumentart.ausweis => t.dokumentArtAusweis,
  Dokumentart.fuehrerschein => t.dokumentArtFuehrerschein,
  Dokumentart.aufenthaltstitel => t.dokumentArtAufenthaltstitel,
  Dokumentart.karte => t.dokumentArtKarte,
};

String _grundText(AppTexte t, Dokumentgrund grund) => switch (grund) {
  Dokumentgrund.pruefzeile => t.dokumentGrundPruefzeile,
  Dokumentgrund.kartennummer => t.dokumentGrundKartennummer,
  Dokumentgrund.schluesselwort => t.dokumentGrundSchluesselwort,
};

/// **Ausweise und Karten in den gesperrten Ordner** – vorgeschlagen,
/// nicht verschoben.
///
/// Alle Funde sind zu Beginn ausgewählt: Der übliche Fall ist, dass ein
/// fotografierter Ausweis weg soll. Was bleiben darf, wird abgewählt und
/// kann ausdrücklich verworfen werden; sonst stünde es beim nächsten
/// Öffnen wieder hier.
class DokumenteScreen extends StatefulWidget {
  const DokumenteScreen({super.key, required this.library});

  final LibraryState library;

  @override
  State<DokumenteScreen> createState() => _DokumenteScreenState();
}

class _DokumenteScreenState extends State<DokumenteScreen> {
  late Future<List<Dokumentvorschlag>> _liste = _laden();
  Set<String> _gewaehlt = {};
  bool _arbeitet = false;

  Future<List<Dokumentvorschlag>> _laden() async {
    final liste = await ladeDokumentvorschlaege(widget.library.db);
    _gewaehlt = {for (final v in liste) v.asset.id};
    return liste;
  }

  void _neuLaden() => setState(() {
    _liste = _laden();
  });

  Future<void> _sperren(List<Dokumentvorschlag> liste) async {
    final t = AppTexte.of(context);
    if (!await ensureVaultUnlocked(context, widget.library)) return;
    setState(() => _arbeitet = true);
    var anzahl = 0;
    try {
      for (final v in liste) {
        if (!_gewaehlt.contains(v.asset.id)) continue;
        await widget.library.lockAsset(v.asset);
        anzahl++;
      }
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
    melde.erfolg(t.dokumenteGesperrt(anzahl));
    if (mounted) _neuLaden();
  }

  Future<void> _verwerfen() async {
    setState(() => _arbeitet = true);
    await widget.library.db.verwirfDokumentvorschlaege(_gewaehlt);
    if (!mounted) return;
    setState(() => _arbeitet = false);
    _neuLaden();
  }

  void _oeffnen(List<Dokumentvorschlag> liste, int index) {
    final aufnahmen = [for (final v in liste) v.asset];
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AssetViewerScreen(
          assets: aufnahmen,
          initialIndex: index,
          paths: widget.library.paths,
          db: widget.library.db,
          library: widget.library,
          onLock: (a) async {
            if (await ensureVaultUnlocked(context, widget.library)) {
              await widget.library.lockAsset(a);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.dokumenteTitel)),
      body: FutureBuilder<List<Dokumentvorschlag>>(
        future: _liste,
        builder: (context, schnappschuss) {
          final liste = schnappschuss.data;
          if (liste == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (liste.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(t.dokumenteKeine, textAlign: TextAlign.center),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(t.dokumenteEinleitung),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: liste.length,
                  itemBuilder: (context, i) {
                    final v = liste[i];
                    return Column(
                      children: [
                        Expanded(
                          child: AssetThumbnailTile(
                            asset: Rasterzeile.aus(v.asset),
                            paths: widget.library.paths,
                            selected: _gewaehlt.contains(v.asset.id),
                            onTap: () => setState(() {
                              if (!_gewaehlt.remove(v.asset.id)) {
                                _gewaehlt.add(v.asset.id);
                              }
                            }),
                            onDoubleTap: () => _oeffnen(liste, i),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${dokumentartText(t, v.fund.art)} · '
                          '${_grundText(t, v.fund.grund)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton(
                        onPressed: _arbeitet || _gewaehlt.isEmpty
                            ? null
                            : _verwerfen,
                        child: Text(t.dokumenteVerwerfen),
                      ),
                      FilledButton.icon(
                        onPressed: _arbeitet || _gewaehlt.isEmpty
                            ? null
                            : () => _sperren(liste),
                        icon: _arbeitet
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_outline),
                        label: Text(t.dokumenteSperren(_gewaehlt.length)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
