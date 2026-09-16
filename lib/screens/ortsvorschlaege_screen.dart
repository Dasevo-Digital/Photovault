import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../services/ortsvorschlag.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/selection_action_bar.dart';

/// Schlägt vor, was unverortete Aufnahmen von ihren zeitlichen Nachbarn
/// erben könnten – **als Vorschlag, nicht als Eintragung**.
///
/// Muster wie [StackReviewScreen]: Bündel, je Bündel „Übernehmen" oder
/// „Verwerfen", ein „nein" wird gemerkt, und weil 56 Bündel einzeln zu
/// bestätigen zu viel ist, gibt es „alle übernehmen".
///
/// **Warum ein Bildschirm und kein stiller Nachtrag.** Ein geerbter Ort
/// ist eine begründete Vermutung, keine Messung. Die vergangene Woche hat
/// gezeigt, wie schnell eine gemessene Koordinate überschrieben ist –
/// eine Vermutung ohne Rückfrage einzutragen wäre derselbe Fehler eine
/// Stufe früher. Deshalb steht neben jedem Bündel, worauf es sich stützt:
/// wie viele verortete Nachbarn, wie weit entfernt.
class OrtsvorschlaegeScreen extends StatefulWidget {
  final LibraryState library;
  const OrtsvorschlaegeScreen({super.key, required this.library});

  @override
  State<OrtsvorschlaegeScreen> createState() => _OrtsvorschlaegeScreenState();
}

class _OrtsvorschlaegeScreenState extends State<OrtsvorschlaegeScreen> {
  bool _laedt = true;
  bool _uebernimmtAlle = false;
  List<Ortsbuendel> _buendel = const [];

  /// Die Aufnahmen je Bündel – für die Vorschaubilder. Erst geladen,
  /// wenn die Bündel stehen: Der Rechenkern kennt nur Kennungen.
  final Map<String, List<AssetData>> _aufnahmen = {};

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _laedt = true);
    final buendel = await widget.library.ortsvorschlagsbuendel();
    // Eine Abfrage für alle Bündel, nicht eine je Bündel – dieselbe
    // Rechnung wie bei den Serienvorschlägen.
    final alle = <String>[
      for (final b in buendel) ...[for (final v in b.vorschlaege) v.assetId],
    ];
    final geladen = await widget.library.db.assetsByIds(alle);
    final nachId = {for (final a in geladen) a.id: a};
    if (!mounted) return;
    setState(() {
      _buendel = buendel;
      _aufnahmen
        ..clear()
        ..addEntries(buendel.map((b) => MapEntry(b.schluessel, [
              for (final v in b.vorschlaege)
                if (nachId[v.assetId] case final a?) a,
            ])));
      _laedt = false;
    });
  }

  Future<void> _uebernimm(int i) async {
    final b = _buendel[i];
    await widget.library.uebernimmOrtsbuendel(b);
    if (!mounted) return;
    setState(() => _buendel = [..._buendel]..removeAt(i));
  }

  Future<void> _verwirf(int i) async {
    final b = _buendel[i];
    await widget.library.db.verwirfOrtsvorschlag(b.schluessel);
    if (!mounted) return;
    setState(() => _buendel = [..._buendel]..removeAt(i));
  }

  Future<void> _frageAlle() async {
    final t = AppTexte.of(context);
    final aufnahmen =
        _buendel.fold<int>(0, (n, b) => n + b.vorschlaege.length);
    final ja = await confirmDialog(context, t.ortVorschlagAlleFrageTitel,
        t.ortVorschlagAlleFrage(_buendel.length, aufnahmen));
    if (!ja || !mounted) return;
    setState(() => _uebernimmtAlle = true);
    try {
      // In einem Zug: je Bündel eine eigene Buchung wäre ein eigener Hin-
      // und Rückweg zum Datenbank-Isolate.
      for (final b in [..._buendel]) {
        await widget.library.uebernimmOrtsbuendel(b);
      }
      if (!mounted) return;
      setState(() => _buendel = const []);
    } finally {
      if (mounted) setState(() => _uebernimmtAlle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.ortVorschlagTitel),
        actions: [
          if (_buendel.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton.tonalIcon(
                onPressed: _uebernimmtAlle ? null : _frageAlle,
                icon: _uebernimmtAlle
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.done_all),
                label: Text(t.ortVorschlagAlleUebernehmen(_buendel.length)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: Text(
              t.ortVorschlagErklaerung,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const Divider(height: 16),
          Expanded(child: _rumpf()),
        ],
      ),
    );
  }

  Widget _rumpf() {
    final t = AppTexte.of(context);
    if (_laedt) return const Center(child: CircularProgressIndicator());
    if (_buendel.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(t.ortVorschlagKeine, textAlign: TextAlign.center),
        ),
      );
    }
    final sprache = Localizations.localeOf(context).toString();
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _buendel.length,
      itemBuilder: (context, i) {
        final b = _buendel[i];
        final aufnahmen = _aufnahmen[b.schluessel] ?? const <AssetData>[];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${DateFormat.yMMMMd(sprache).format(b.tag)} · '
                          '${t.ortVorschlagAnzahl(b.vorschlaege.length)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        // Worauf sich der Vorschlag stützt. Ohne diese
                        // Zeile wäre er eine Behauptung.
                        Text(
                          t.ortVorschlagBegruendung(
                              _nachbarn(b), b.groessterAbstand.inMinutes),
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _verwirf(i),
                    child: Text(AppTexte.of(context).allgVerwerfen),
                  ),
                  FilledButton(
                    onPressed: () => _uebernimm(i),
                    child: Text(AppTexte.of(context).allgUebernehmen),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: aufnahmen.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, k) => SizedBox(
                    width: 110,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: AssetThumbnailTile(
                        asset: Rasterzeile.aus(aufnahmen[k]),
                        paths: widget.library.paths,
                        onTap: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Die kleinste Zahl verorteter Nachbarn im Bündel – die vorsichtigste
  /// Auskunft darüber, worauf der Vorschlag steht.
  int _nachbarn(Ortsbuendel b) =>
      b.vorschlaege.map((v) => v.nachbarn).reduce((a, c) => a < c ? a : c);
}
