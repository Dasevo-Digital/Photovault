import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import 'package:kern/services/rueckblickseite.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/diashow_export.dart';
import '../widgets/fotobuch_export.dart';
import 'asset_viewer_screen.dart';
import 'reise_detail_screen.dart';

/// **Erinnerungen** – mehr als der eine Tag, den „Entdecken“ zeigt.
///
/// Der Rückblick in „Entdecken“ zeigt heute und ist morgen fort. Wer ihn
/// an einem Tag nicht geöffnet hat, sieht ihn erst in einem Jahr wieder.
/// Hier stehen deshalb die letzten zwei Wochen, und was davon bleiben
/// soll, wird gemerkt – wie bei Immich seit 3.2. Dazu die Reisen mit den
/// meisten Lieblingsfotos.
class ErinnerungenScreen extends StatefulWidget {
  const ErinnerungenScreen({super.key, required this.library});

  final LibraryState library;

  @override
  State<ErinnerungenScreen> createState() => _ErinnerungenScreenState();
}

typedef _Stand = Erinnerungsstand;

class _ErinnerungenScreenState extends State<ErinnerungenScreen> {
  final _heute = DateUtils.dateOnly(DateTime.now());
  late Future<_Stand> _stand = _laden();

  Future<_Stand> _laden() => erinnerungsstand(widget.library.db, heute: _heute);

  void _neuLaden() => setState(() {
    _stand = _laden();
  });

  String _datum(BuildContext context, DateTime d) =>
      DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(d);

  Future<void> _merken(Erinnerung e, String titel) async {
    await widget.library.db.fuehreAus(
      ErinnerungMerken(
        erinnerungId: erinnerungsKennung(e.tag, e.jahreHer),
        titel: titel,
        tag: DateTime(e.tag.year - e.jahreHer, e.tag.month, e.tag.day),
        ids: [for (final a in e.dinge) a.id],
      ),
    );
    if (mounted) _neuLaden();
  }

  Future<void> _vergessen(String id) async {
    await widget.library.db.fuehreAus(ErinnerungVergessen(id));
    if (mounted) _neuLaden();
  }

  void _oeffnen(List<AssetData> dinge, int index) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AssetViewerScreen(
          assets: dinge,
          initialIndex: index,
          paths: widget.library.paths,
          db: widget.library.db,
          library: widget.library,
          onToggleFavorite: (a) =>
              widget.library.db.fuehreAus(FavoritSetzen([a.id], !a.isFavorite)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.erinnerungenTitel)),
      body: FutureBuilder<_Stand>(
        future: _stand,
        builder: (context, schnappschuss) {
          final s = schnappschuss.data;
          if (s == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final gemerkteIds = {for (final g in s.gemerkt) g.e.id};
          final titel = Theme.of(context).textTheme.titleMedium;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (s.gemerkt.isNotEmpty) ...[
                Text(t.erinnerungenGemerkt, style: titel),
                const SizedBox(height: AppSpacing.sm),
                for (final g in s.gemerkt)
                  if (g.dinge.isNotEmpty)
                    _Gruppe(
                      ueberschrift: g.e.titel,
                      dinge: g.dinge,
                      library: widget.library,
                      gemerkt: true,
                      onMerken: () => _vergessen(g.e.id),
                      onOeffnen: (i) => _oeffnen(g.dinge, i),
                      dateiname: 'erinnerung-${g.e.id}.mp4',
                    ),
                const SizedBox(height: AppSpacing.lg),
              ],
              Text(t.erinnerungenLetzteTage, style: titel),
              const SizedBox(height: AppSpacing.sm),
              if (s.letzte.isEmpty)
                Text(t.erinnerungenKeine)
              else
                for (final e in s.letzte)
                  Builder(
                    builder: (context) {
                      final kopf = t.erinnerungenTagVorJahren(
                        _datum(
                          context,
                          DateTime(
                            e.tag.year - e.jahreHer,
                            e.tag.month,
                            e.tag.day,
                          ),
                        ),
                        e.jahreHer,
                      );
                      final id = erinnerungsKennung(e.tag, e.jahreHer);
                      return _Gruppe(
                        ueberschrift: kopf,
                        dinge: e.dinge,
                        library: widget.library,
                        gemerkt: gemerkteIds.contains(id),
                        onMerken: gemerkteIds.contains(id)
                            ? () => _vergessen(id)
                            : () => _merken(e, kopf),
                        onOeffnen: (i) => _oeffnen(e.dinge, i),
                        dateiname: 'erinnerung-$id.mp4',
                      );
                    },
                  ),
              if (s.reisen.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(t.erinnerungenSchoensteReisen, style: titel),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final r in s.reisen)
                      ActionChip(
                        avatar: const Icon(Icons.luggage_outlined),
                        label: Text(
                          t.erinnerungenReise(
                            r.reise.name,
                            '${r.reise.von.year}',
                            r.lieblinge,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReiseDetailScreen(
                              library: widget.library,
                              reise: r.reise,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Gruppe extends StatelessWidget {
  const _Gruppe({
    required this.ueberschrift,
    required this.dinge,
    required this.library,
    required this.gemerkt,
    required this.onMerken,
    required this.onOeffnen,
    required this.dateiname,
  });

  final String ueberschrift;
  final List<AssetData> dinge;
  final LibraryState library;
  final bool gemerkt;
  final VoidCallback onMerken;
  final void Function(int index) onOeffnen;
  final String dateiname;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ueberschrift,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: gemerkt
                    ? t.erinnerungenVergessen
                    : t.erinnerungenMerken,
                icon: Icon(gemerkt ? Icons.bookmark : Icons.bookmark_border),
                visualDensity: VisualDensity.compact,
                onPressed: onMerken,
              ),
              IconButton(
                tooltip: t.diashowAlsVideo,
                icon: const Icon(Icons.movie_creation_outlined),
                visualDensity: VisualDensity.compact,
                onPressed: () => diashowExportieren(
                  context,
                  library,
                  dinge,
                  titel: ueberschrift,
                  dateiname: dateiname,
                ),
              ),
              IconButton(
                tooltip: t.fotobuchAlsPdf,
                icon: const Icon(Icons.menu_book_outlined),
                visualDensity: VisualDensity.compact,
                onPressed: () => fotobuchExportieren(
                  context,
                  library,
                  dinge,
                  titel: ueberschrift,
                  dateiname: mitPdfEndung(dateiname),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: dinge.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => SizedBox(
                width: 120,
                child: AssetThumbnailTile(
                  asset: Rasterzeile.aus(dinge[i]),
                  paths: library.paths,
                  onTap: () => onOeffnen(i),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
