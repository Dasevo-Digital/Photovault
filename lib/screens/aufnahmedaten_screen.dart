import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/datumsvorschlag.dart';
import '../l10n/app_localizations.dart';
import '../services/meldungsdienst.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import 'asset_viewer_screen.dart';

/// Das vorgeschlagene Datum zum Lesen: ohne Uhrzeit, wenn der Name nur den
/// Tag nennt.
String vorschlagsdatumText(String sprache, Datumsvorschlag v) =>
    (v.geschaetzt
            ? DateFormat.yMMMd(sprache)
            : DateFormat.yMMMd(sprache).add_Hm())
        .format(v.neu.toLocal());

/// **Aufnahmedaten aus dem Dateinamen** (#203) – wie im Browser
/// („Aufnahmedaten“) und auf dem Telefon, nach denselben Regeln
/// (`kern/services/datumsvorschlag.dart`). Übernommen wird über den Befehl
/// `AufnahmedatenSetzen`, verbunden also auch für alle anderen Geräte.
class AufnahmedatenScreen extends StatefulWidget {
  const AufnahmedatenScreen({super.key, required this.library});

  final LibraryState library;

  @override
  State<AufnahmedatenScreen> createState() => _AufnahmedatenScreenState();
}

class _AufnahmedatenScreenState extends State<AufnahmedatenScreen> {
  late Future<List<(Datumsvorschlag, AssetData)>> _liste = _laden();
  final Set<String> _gewaehlt = {};
  final Set<String> _uebernommen = {};
  bool _arbeitet = false;

  Future<List<(Datumsvorschlag, AssetData)>> _laden() async {
    final liste = <(Datumsvorschlag, AssetData)>[];
    for (final v in await widget.library.pruefeAufnahmedaten()) {
      final a = await widget.library.db.assetById(v.id);
      if (a != null) liste.add((v, a));
    }
    _gewaehlt
      ..clear()
      ..addAll([for (final (v, _) in liste) v.id]);
    return liste;
  }

  Future<void> _uebernehmen(List<Datumsvorschlag> welche) async {
    final t = AppTexte.of(context);
    setState(() => _arbeitet = true);
    for (var i = 0; i < welche.length; i += 200) {
      await widget.library.db.fuehreAus(
        AufnahmedatenSetzen([
          for (final v in welche.skip(i).take(200)) v.alsEintrag,
        ]),
      );
    }
    _uebernommen.addAll([for (final v in welche) v.id]);
    _gewaehlt.removeAll(_uebernommen);
    if (!mounted) return;
    setState(() => _arbeitet = false);
    melde.erfolg(t.aufnahmedatenUebernommen(welche.length));
  }

  void _oeffnen(List<AssetData> liste, int index) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AssetViewerScreen(
          assets: liste,
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
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final datumZeit = DateFormat.yMMMd(sprache).add_Hm();
    final leise = TextStyle(color: Theme.of(context).colorScheme.outline);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.aufnahmedatenTitel),
        actions: [
          IconButton(
            tooltip: MaterialLocalizations.of(
              context,
            ).refreshIndicatorSemanticLabel,
            icon: const Icon(Icons.refresh),
            onPressed: _arbeitet
                ? null
                : () => setState(() {
                    _uebernommen.clear();
                    _liste = _laden();
                  }),
          ),
        ],
      ),
      body: FutureBuilder<List<(Datumsvorschlag, AssetData)>>(
        future: _liste,
        builder: (context, schnappschuss) {
          if (schnappschuss.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (schnappschuss.hasError) {
            return Center(child: Text('${schnappschuss.error}'));
          }
          final liste = [
            for (final e in schnappschuss.data!)
              if (!_uebernommen.contains(e.$1.id)) e,
          ];
          if (liste.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(t.aufnahmedatenKeine, textAlign: TextAlign.center),
              ),
            );
          }
          final aufnahmen = [for (final (_, a) in liste) a];
          final gewaehlt = [
            for (final (v, _) in liste)
              if (_gewaehlt.contains(v.id)) v,
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
                child: Text(t.aufnahmedatenEinleitung),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: liste.length,
                  itemBuilder: (context, i) {
                    final (v, a) = liste[i];
                    final bisher =
                        '${datumZeit.format(v.bisher.toLocal())}'
                        '${v.bisherGeschaetzt ? ' (${t.aufnahmedatenGeschaetzt})' : ''}';
                    return CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _gewaehlt.contains(v.id),
                      onChanged: _arbeitet
                          ? null
                          : (an) => setState(
                              () => an == true
                                  ? _gewaehlt.add(v.id)
                                  : _gewaehlt.remove(v.id),
                            ),
                      secondary: SizedBox(
                        width: 56,
                        height: 56,
                        child: AssetThumbnailTile(
                          asset: Rasterzeile.aus(a),
                          paths: widget.library.paths,
                          onTap: () => _oeffnen(aufnahmen, i),
                        ),
                      ),
                      title: Text(
                        v.dateiname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '$bisher → ${vorschlagsdatumText(sprache, v)}\n',
                            ),
                            TextSpan(
                              style: leise,
                              text: [
                                v.quelle == Datumsquelle.dateiUndName
                                    ? t.aufnahmedatenLautDatei
                                    : t.aufnahmedatenLautName,
                                if (v.geschaetzt) t.aufnahmedatenNurTag,
                              ].join(' · '),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _arbeitet || gewaehlt.isEmpty
                          ? null
                          : () => _uebernehmen(gewaehlt),
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text(t.aufnahmedatenUebernehmen(gewaehlt.length)),
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
}
