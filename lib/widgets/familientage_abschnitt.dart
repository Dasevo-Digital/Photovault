import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../screens/asset_viewer_screen.dart';
import '../services/familientage.dart';
import '../services/lebenslauf.dart';
import '../services/stammbaum.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import 'asset_thumbnail_tile.dart';

/// Wie viele Familientage der Abschnitt höchstens zeigt.
const _hoechstensTage = 4;

/// Wie viele Fotos je Familientag.
const _hoechstensFotos = 12;

/// Familientage in „Entdecken": Geburtstage, Todestage und Hochzeitstage
/// aus dem Stammbaum, heute und in den nächsten Tagen, mit den Fotos der
/// Menschen darunter. Siehe [familientage].
///
/// Ohne Stammbaum, ohne Lebensdaten oder ohne einen Tag im Vorausblick
/// bleibt der Abschnitt weg – wer keinen Stammbaum führt, soll ihn hier
/// nicht als Lücke sehen.
class FamilientageAbschnitt extends StatefulWidget {
  final LibraryState library;

  /// Für Tests; sonst jetzt.
  final DateTime? heute;

  const FamilientageAbschnitt({super.key, required this.library, this.heute});

  @override
  State<FamilientageAbschnitt> createState() => _FamilientageAbschnittState();
}

typedef _Eintrag = ({
  Familientag tag,
  List<String> namen,
  List<AssetData> fotos,
});

class _FamilientageAbschnittState extends State<FamilientageAbschnitt> {
  late final Future<List<_Eintrag>> _eintraege = _laden();

  Future<List<_Eintrag>> _laden() async {
    final db = widget.library.db;
    final personen = await db.allePersonen();
    if (personen.isEmpty) return const [];
    final nachId = {for (final p in personen) p.id: p};
    final netz = Verwandtschaftsnetz([
      for (final z in await db.alleBeziehungen())
        if (artAusText(z.art) case final art?)
          kante(z.personId, z.andereId, art),
    ]);
    final hochzeiten = <Hochzeit>[
      for (final e in await db.alleEreignisse())
        if (e.datum case final datum?)
          if (ereignisartAusText(e.art) == Ereignisart.hochzeit)
            (
              datum: datum,
              personId: e.personId,
              // Bei mehreren Partnern bleibt offen, wen die Hochzeit
              // betraf; dann steht nur die eingetragene Person da.
              partnerId: netz.partner(e.personId).length == 1
                  ? netz.partner(e.personId).single
                  : null,
            ),
    ];
    final tage = familientage(
      personen: [
        for (final p in personen)
          (id: p.id, geburtsdatum: p.geburtsdatum, sterbedatum: p.sterbedatum),
      ],
      hochzeiten: hochzeiten,
      heute: widget.heute ?? DateTime.now(),
    ).take(_hoechstensTage);

    final ergebnis = <_Eintrag>[];
    for (final tag in tage) {
      final ids = tag.personen.where(nachId.containsKey).toList();
      if (ids.isEmpty) continue;
      ergebnis.add((
        tag: tag,
        namen: [for (final id in ids) nachId[id]!.name],
        fotos: await _fotos(db, ids),
      ));
    }
    return ergebnis;
  }

  /// Bei einem Paar zuerst die Fotos, auf denen beide sind – sonst die
  /// von jedem.
  Future<List<AssetData>> _fotos(AppDatabase db, List<String> ids) async {
    if (ids.length == 1) {
      return (await db.assetsFuerPersonen(ids)).take(_hoechstensFotos).toList();
    }
    final je = [
      for (final id in ids) await db.assetsFuerPersonen([id]),
    ];
    final beiAllen = je.skip(1).fold({
      for (final a in je.first) a.id,
    }, (s, liste) => s.intersection({for (final a in liste) a.id}));
    final alle = await db.assetsFuerPersonen(ids);
    final gemeinsam = [
      for (final a in alle)
        if (beiAllen.contains(a.id)) a,
    ];
    return (gemeinsam.isNotEmpty ? gemeinsam : alle)
        .take(_hoechstensFotos)
        .toList();
  }

  String _wann(AppTexte t, int inTagen) => switch (inTagen) {
    0 => t.familientagHeute,
    1 => t.familientagMorgen,
    _ => t.familientagInTagen(inTagen),
  };

  String _satz(AppTexte t, Familientag tag, List<String> namen) =>
      switch (tag.art) {
        Familientagart.geburtstag =>
          tag.verstorben
              ? t.familientagGeburtstagVerstorben(namen.single, tag.jahre)
              : t.familientagGeburtstag(namen.single, tag.jahre),
        Familientagart.todestag => t.familientagTodestag(
          namen.single,
          tag.jahre,
        ),
        Familientagart.hochzeitstag => t.familientagHochzeitstag(
          namen.join(' & '),
          tag.jahre,
        ),
      };

  void _oeffne(BuildContext context, List<AssetData> fotos, AssetData foto) {
    final library = widget.library;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AssetViewerScreen(
          assets: fotos,
          initialIndex: fotos.indexOf(foto),
          paths: library.paths,
          db: library.db,
          library: library,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return FutureBuilder<List<_Eintrag>>(
      future: _eintraege,
      builder: (context, schnappschuss) {
        final eintraege = schnappschuss.data;
        if (eintraege == null || eintraege.isEmpty) {
          return const SizedBox.shrink();
        }
        final thema = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.familientageTitel, style: thema.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              for (final e in eintraege) ...[
                Row(
                  children: [
                    Icon(
                      switch (e.tag.art) {
                        Familientagart.geburtstag =>
                          e.tag.verstorben
                              ? Icons.local_florist_outlined
                              : Icons.cake_outlined,
                        Familientagart.todestag => Icons.local_florist_outlined,
                        Familientagart.hochzeitstag => Icons.favorite_border,
                      },
                      size: 18,
                      color: thema.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${_wann(t, e.tag.inTagen)} · '
                        '${_satz(t, e.tag, e.namen)}',
                        style: thema.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (e.fotos.isNotEmpty)
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: e.fotos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => SizedBox(
                        width: 96,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: AssetThumbnailTile(
                            asset: Rasterzeile.aus(e.fotos[i]),
                            paths: widget.library.paths,
                            onTap: () => _oeffne(context, e.fotos, e.fotos[i]),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        );
      },
    );
  }
}
