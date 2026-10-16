import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/rueckblick.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'betrachter.dart';

/// „Vor x Jahren“ über der Zeitleiste (Issue #130): je ein Kärtchen pro
/// Jahrgang mit Aufnahmen von heute – oder, wenn der Tag nichts hat, aus
/// diesem Monat (siehe [waehleRueckblick] im Kern, dieselbe Wahl wie am
/// Rechner). Ein Tipp öffnet den Jahrgang im Betrachter.
class Erinnerungsstreifen extends StatefulWidget {
  const Erinnerungsstreifen({
    super.key,
    required this.sitzung,
    this.heute,
    this.stand = 0,
  });

  final Sitzung sitzung;

  /// Für Tests; sonst der heutige Tag.
  final DateTime? heute;

  /// Ändert sich das (etwa die Zahl der Aufnahmen), wird neu gefragt.
  final int stand;

  @override
  State<Erinnerungsstreifen> createState() => _ErinnerungsstreifenState();
}

class _ErinnerungsstreifenState extends State<Erinnerungsstreifen> {
  late Future<Rueckblick<AssetData>> _rueckblick = _lade();

  DateTime get _heute => widget.heute ?? DateTime.now();

  Future<Rueckblick<AssetData>> _lade() async {
    final db = widget.sitzung.db;
    final heute = _heute;
    final amTag = await db.assetsOnThisDay(heute);
    final imMonat = amTag.isEmpty
        ? await db.assetsInDiesemMonat(heute)
        : const <AssetData>[];
    return waehleRueckblick(
      amTag: amTag,
      imMonat: imMonat,
      wann: (a) => a.fileCreatedAt.toLocal(),
      heute: heute,
    );
  }

  @override
  void didUpdateWidget(Erinnerungsstreifen alt) {
    super.didUpdateWidget(alt);
    if (alt.stand != widget.stand || alt.heute != widget.heute) {
      _rueckblick = _lade();
    }
  }

  void _oeffne(List<AssetData> dinge) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Betrachter(
        sitzung: widget.sitzung,
        zeilen: [for (final a in dinge) Rasterzeile.aus(a)],
        start: 0,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).toLanguageTag();
    return FutureBuilder<Rueckblick<AssetData>>(
      future: _rueckblick,
      builder: (context, s) {
        final r = s.data;
        if (r == null || r.art == Rueckblickart.keiner) {
          return const SizedBox.shrink();
        }
        final monat = DateFormat.MMMM(
          sprache,
        ).format(DateTime(_heute.year, _heute.month));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                t.erinnerungenTitel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: r.gruppen.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final g = r.gruppen[i];
                  final text = r.art == Rueckblickart.tag
                      ? t.erinnerungenVorJahren(g.jahreHer)
                      : t.erinnerungenMonatVorJahren(monat, g.jahreHer);
                  return _Karte(
                    sitzung: widget.sitzung,
                    titelbild: g.dinge.first,
                    text: text,
                    anzahl: g.dinge.length,
                    onTap: () => _oeffne(g.dinge),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Karte extends StatelessWidget {
  const _Karte({
    required this.sitzung,
    required this.titelbild,
    required this.text,
    required this.anzahl,
    required this.onTap,
  });

  final Sitzung sitzung;
  final AssetData titelbild;
  final String text;
  final int anzahl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 120,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Miniatur(
              paths: sitzung.paths,
              relativ: titelbild.thumbnailRelativePath,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                  ),
                  Text(
                    AppTexte.of(context).erinnerungenAnzahl(anzahl),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
