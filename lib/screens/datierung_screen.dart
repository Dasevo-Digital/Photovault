import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../services/datierung.dart';
import '../services/meldungsdienst.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import 'asset_viewer_screen.dart';

typedef _Schaetzung = ({AssetData asset, Datierung datierung});

/// **Alte Fotos zeitlich einordnen** – siehe `services/datierung.dart`.
///
/// Gezeigt werden nur Fotos, die alt aussehen: Ein Bildschirmfoto mit
/// geratenem Datum ist auch ohne Schätzung von gestern, und es hier
/// aufzulisten, verdeckte die Fotos, um die es geht.
class DatierungScreen extends StatefulWidget {
  const DatierungScreen({super.key, required this.library});

  final LibraryState library;

  @override
  State<DatierungScreen> createState() => _DatierungScreenState();
}

class _DatierungScreenState extends State<DatierungScreen> {
  /// `null` im Ergebnis: Das Modell der Bildsuche fehlt.
  late final Future<List<_Schaetzung>?> _liste = _laden();
  final Set<String> _uebernommen = {};
  bool _arbeitet = false;

  Future<List<_Schaetzung>?> _laden() async {
    final saetze = await widget.library.datierungssaetze();
    if (saetze == null) return null;
    final kandidaten = await widget.library.db.datierungskandidaten();
    final liste = <_Schaetzung>[
      for (final k in kandidaten)
        (asset: k.asset, datierung: schaetzeDatierung(k.vektor, saetze)),
    ]..removeWhere((s) => !s.datierung.siehtAltAus);
    liste.sort((a, b) => a.datierung.jahr.compareTo(b.datierung.jahr));
    // Schon übernommen, wenn das Datum genau dort steht, wohin
    // [AppDatabase.setzeGeschaetztesJahr] es legt.
    for (final s in liste) {
      if (s.asset.fileCreatedAt == DateTime(s.datierung.jahr, 7, 1, 12)) {
        _uebernommen.add(s.asset.id);
      }
    }
    return liste;
  }

  Future<void> _uebernehmen(List<_Schaetzung> welche) async {
    final t = AppTexte.of(context);
    setState(() => _arbeitet = true);
    for (final s in welche) {
      await widget.library.db.setzeGeschaetztesJahr(
        s.asset.id,
        s.datierung.jahr,
      );
      _uebernommen.add(s.asset.id);
    }
    if (!mounted) return;
    setState(() => _arbeitet = false);
    melde.erfolg(t.datierungUebernommen(welche.length));
  }

  void _oeffnen(List<_Schaetzung> liste, int index) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AssetViewerScreen(
          assets: [for (final s in liste) s.asset],
          initialIndex: index,
          paths: widget.library.paths,
          db: widget.library.db,
          library: widget.library,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.datierungTitel)),
      body: FutureBuilder<List<_Schaetzung>?>(
        future: _liste,
        builder: (context, schnappschuss) {
          if (schnappschuss.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final liste = schnappschuss.data;
          final leer = liste == null
              ? t.datierungOhneModell
              : liste.isEmpty
              ? t.datierungKeine
              : null;
          if (leer != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(leer, textAlign: TextAlign.center),
              ),
            );
          }
          final offen = [
            for (final s in liste!)
              if (s.datierung.belastbar && !_uebernommen.contains(s.asset.id))
                s,
          ];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(t.datierungEinleitung),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.7,
                  ),
                  itemCount: liste.length,
                  itemBuilder: (context, i) => _kachel(context, t, liste, i),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _arbeitet || offen.isEmpty
                          ? null
                          : () => _uebernehmen(offen),
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text(t.datierungAlleUebernehmen(offen.length)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _kachel(
    BuildContext context,
    AppTexte t,
    List<_Schaetzung> liste,
    int i,
  ) {
    final s = liste[i];
    final d = s.datierung;
    final klein = Theme.of(context).textTheme.bodySmall;
    final uebernommen = _uebernommen.contains(s.asset.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: AssetThumbnailTile(
            asset: Rasterzeile.aus(s.asset),
            paths: widget.library.paths,
            onTap: () => _oeffnen(liste, i),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          t.datierungUm('${d.jahr}'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          d.belastbar
              ? t.datierungSpanne('${d.von}', '${d.bis}')
              : t.datierungUnsicher('${d.von}', '${d.bis}'),
          style: klein,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (uebernommen)
          Text(t.datierungIstUebernommen, style: klein)
        else if (d.belastbar)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _arbeitet ? null : () => _uebernehmen([s]),
              child: Text(t.datierungUebernehmen),
            ),
          ),
      ],
    );
  }
}
