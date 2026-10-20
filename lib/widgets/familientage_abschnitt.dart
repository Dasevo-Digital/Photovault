import 'package:flutter/material.dart';

import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../screens/asset_viewer_screen.dart';
import 'package:kern/services/familientage.dart';
import 'package:kern/services/rueckblickseite.dart';
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

typedef _Eintrag = FamilientagMitFotos;

class _FamilientageAbschnittState extends State<FamilientageAbschnitt> {
  late final Future<List<_Eintrag>> _eintraege = familientageMitFotos(
    widget.library.db,
    heute: widget.heute ?? DateTime.now(),
    hoechstensTage: _hoechstensTage,
    hoechstensFotos: _hoechstensFotos,
  );

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
