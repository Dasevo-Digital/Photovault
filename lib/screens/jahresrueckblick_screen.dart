import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../services/jahresrueckblick.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/diashow_export.dart';
import '../widgets/profilbild.dart';
import 'asset_viewer_screen.dart';
import 'person_detail_screen.dart';
import 'reise_detail_screen.dart';

/// Das Jahr, das „Entdecken" anbietet: bis Februar das vergangene, danach
/// das laufende – im Januar ist vom neuen Jahr noch nichts zu sehen.
int jahresrueckblickJahr(DateTime heute) =>
    heute.month <= 2 ? heute.year - 1 : heute.year;

typedef _Inhalt = ({
  Jahreszahlen zahlen,
  List<AssetData> auswahl,
  List<({PersonData person, int anzahl})> personen,
  List<ReisenData> reisen,
});

/// **Ein Jahr in Zahlen und Bildern** – siehe [jahresauswahl].
class JahresrueckblickScreen extends StatefulWidget {
  final LibraryState library;
  final int jahr;

  const JahresrueckblickScreen({
    super.key,
    required this.library,
    required this.jahr,
  });

  @override
  State<JahresrueckblickScreen> createState() => _JahresrueckblickScreenState();
}

class _JahresrueckblickScreenState extends State<JahresrueckblickScreen> {
  late int _jahr = widget.jahr;
  late Future<_Inhalt> _inhalt = _laden(_jahr);

  void _wechsle(int jahr) => setState(() {
    _jahr = jahr;
    _inhalt = _laden(jahr);
  });

  Future<_Inhalt> _laden(int jahr) async {
    final db = widget.library.db;
    final von = DateTime(jahr), bis = DateTime(jahr, 12, 31);
    final aufnahmen = await db.aufnahmenImZeitraum(von, bis);
    final daten = [
      for (final a in aufnahmen)
        (
          id: a.id,
          wann: a.fileCreatedAt,
          video: a.type == 'VIDEO',
          favorit: a.isFavorite,
          bewertung: a.rating,
          schaerfe: a.sharpnessScore,
          land: a.locationCountry,
          ort: a.locationCity,
          datumGeraten: a.datumGeschaetzt,
        ),
    ];
    final nachId = {for (final a in aufnahmen) a.id: a};
    return (
      zahlen: jahreszahlen(daten),
      auswahl: [for (final id in jahresauswahl(daten)) nachId[id]!],
      personen: await db.personenImZeitraum(von, bis),
      reisen: [
        for (final r in await db.alleReisen())
          if (r.von.year <= jahr && r.bis.year >= jahr) r,
      ]..sort((a, b) => a.von.compareTo(b.von)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final heute = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Text(t.jahresrueckblickTitel(_jahr)),
        actions: [
          IconButton(
            tooltip: t.jahresrueckblickVorjahr,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _wechsle(_jahr - 1),
          ),
          IconButton(
            tooltip: t.jahresrueckblickFolgejahr,
            icon: const Icon(Icons.chevron_right),
            onPressed: _jahr >= heute.year ? null : () => _wechsle(_jahr + 1),
          ),
        ],
      ),
      body: FutureBuilder<_Inhalt>(
        future: _inhalt,
        builder: (context, schnappschuss) {
          final inhalt = schnappschuss.data;
          if (inhalt == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final z = inhalt.zahlen;
          if (z.fotos + z.videos == 0) {
            return Center(child: Text(t.jahresrueckblickLeer(_jahr)));
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _kennzahlen(context, t, z),
              const SizedBox(height: AppSpacing.lg),
              _monate(context, z),
              if (inhalt.auswahl.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _ueberschrift(
                  context,
                  t.jahresrueckblickAuswahl,
                  aktion: IconButton(
                    tooltip: t.diashowAlsVideo,
                    icon: const Icon(Icons.movie_creation_outlined),
                    onPressed: () => diashowExportieren(
                      context,
                      widget.library,
                      inhalt.auswahl,
                      titel: t.jahresrueckblickTitel(_jahr),
                      untertitel: t.jahresrueckblickUmfang(z.fotos, z.tage),
                      dateiname: 'jahresrueckblick-$_jahr.mp4',
                    ),
                  ),
                ),
                _auswahl(context, inhalt.auswahl),
              ],
              if (inhalt.personen.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _ueberschrift(context, t.jahresrueckblickPersonen),
                _personen(context, t, inhalt.personen),
              ],
              if (inhalt.reisen.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _ueberschrift(context, t.jahresrueckblickReisen),
                for (final r in inhalt.reisen)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.luggage_outlined),
                    title: Text(r.name),
                    subtitle: Text(_zeitraum(context, r.von, r.bis)),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReiseDetailScreen(
                          library: widget.library,
                          reise: r,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _ueberschrift(BuildContext context, String text, {Widget? aktion}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.titleMedium),
            ),
            ?aktion,
          ],
        ),
      );

  Widget _kennzahlen(BuildContext context, AppTexte t, Jahreszahlen z) {
    final sprache = Localizations.localeOf(context).toString();
    final monat = z.staerksterMonat;
    final werte = [
      (t.jahresrueckblickFotos, '${z.fotos}'),
      if (z.videos > 0) (t.jahresrueckblickVideos, '${z.videos}'),
      (t.jahresrueckblickTage, '${z.tage}'),
      if (z.laender.isNotEmpty)
        (t.jahresrueckblickLaender, '${z.laender.length}'),
      if (z.orte.isNotEmpty) (t.jahresrueckblickOrte, '${z.orte.length}'),
      if (monat != null)
        (
          t.jahresrueckblickStaerksterMonat,
          DateFormat.MMMM(sprache).format(DateTime(_jahr, monat)),
        ),
    ];
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final (beschriftung, wert) in werte)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wert, style: Theme.of(context).textTheme.headlineSmall),
                  Text(beschriftung),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Zwölf Balken, einer je Monat – wann im Jahr fotografiert wurde.
  Widget _monate(BuildContext context, Jahreszahlen z) {
    final sprache = Localizations.localeOf(context).toString();
    final hoechster = z.jeMonat.reduce((a, b) => a > b ? a : b);
    final farbe = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var m = 0; m < 12; m++)
            Expanded(
              child: Tooltip(
                message: '${z.jeMonat[m]}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: hoechster == 0
                          ? 0
                          : 80 * z.jeMonat[m] / hoechster,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: farbe,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat.MMM(sprache).format(DateTime(_jahr, m + 1)),
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.clip,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _auswahl(BuildContext context, List<AssetData> auswahl) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final a in auswahl)
        SizedBox(
          width: 120,
          height: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: AssetThumbnailTile(
              asset: Rasterzeile.aus(a),
              paths: widget.library.paths,
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => AssetViewerScreen(
                    assets: auswahl,
                    initialIndex: auswahl.indexOf(a),
                    paths: widget.library.paths,
                    db: widget.library.db,
                    library: widget.library,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _personen(
    BuildContext context,
    AppTexte t,
    List<({PersonData person, int anzahl})> personen,
  ) => Wrap(
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.md,
    children: [
      for (final (:person, :anzahl) in personen)
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PersonDetailScreen(library: widget.library, person: person),
            ),
          ),
          child: SizedBox(
            width: 88,
            child: Column(
              children: [
                Profilbild(
                  datei: person.coverFaceCropPath == null
                      ? null
                      : widget.library.paths.absolute(
                          person.coverFaceCropPath!,
                        ),
                  radius: 32,
                ),
                const SizedBox(height: 4),
                Text(
                  person.name.isEmpty ? '—' : person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  t.jahresrueckblickAufnahmen(anzahl),
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  String _zeitraum(BuildContext context, DateTime von, DateTime bis) {
    final f = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    return '${f.format(von)} – ${f.format(bis)}';
  }
}
