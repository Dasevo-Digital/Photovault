import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../services/blur_detection.dart';
import '../services/serienvergleich.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/profilbild.dart';
import '../widgets/star_rating.dart';

/// Die Gesichter einer Serie nebeneinander.
///
/// **Wofür es das gibt.** Aus fünf fast gleichen Aufnahmen die eine
/// herauszusuchen, auf der niemand blinzelt, ist die Arbeit, für die es
/// Narrative Select gibt. Auf einem Foto in Bildschirmgrösse sieht man das
/// nicht – die Köpfe sind dafür zu klein. Nebeneinandergelegte Ausschnitte
/// zeigen es sofort.
///
/// **Es kommt kein neues Modell dazu.** Die Ausschnitte liegen seit der
/// Gesichtserkennung auf der Platte, die Schärfe je Gesicht seit Fassung 61
/// in der Datenbank. Was fehlte, war die Ansicht, die beides
/// nebeneinanderstellt.
///
/// **Zum Augenzustand.** Er steht hier, wenn er vorliegt – und nur hier:
/// direkt neben dem Gesicht, über das er etwas sagt. Als Warnung ohne Bild
/// stand er bis Fassung 63 in der Sichtungsleiste und hatte dort unrecht
/// (siehe `Faces.eyeOpenScore`). Wo das Gesicht danebensteht, kann man
/// eine falsche Zahl sehen und übergehen; wo es fehlt, nicht.
class SerienvergleichScreen extends StatefulWidget {
  final LibraryState library;

  /// Die Aufnahmen der Serie, in Aufnahmereihenfolge.
  final List<AssetData> serie;

  const SerienvergleichScreen({
    super.key,
    required this.library,
    required this.serie,
  });

  @override
  State<SerienvergleichScreen> createState() => _SerienvergleichScreenState();
}

class _SerienvergleichScreenState extends State<SerienvergleichScreen> {
  List<Serienspalte>? _spalten;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final spalten =
        await serienspalten(widget.library.db, widget.serie);
    if (mounted) setState(() => _spalten = spalten);
  }

  Future<void> _bewerte(AssetData asset, int sterne) async {
    await widget.library.db.setRating(asset.id, sterne);
    await _laden();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final spalten = _spalten;
    return Scaffold(
      appBar: AppBar(title: Text(t.serienvergleichTitel)),
      body: spalten == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                  child: Text(
                    spalten.any((s) => s.gesichter.isNotEmpty)
                        ? t.serienvergleichErklaerung
                        : t.serienvergleichOhneGesichter,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Divider(height: AppSpacing.lg),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final spalte in spalten)
                          _Spalte(
                            spalte: spalte,
                            library: widget.library,
                            bestesGesicht: spalte.schaerfsteId ==
                                _besteSpalte(spalten)?.schaerfsteId,
                            beiBewertung: (n) => _bewerte(spalte.asset, n),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Die Aufnahme mit dem schärfsten Gesicht – der Vorschlag, keine
  /// Entscheidung.
  Serienspalte? _besteSpalte(List<Serienspalte> spalten) {
    Serienspalte? beste;
    for (final s in spalten) {
      if (s.besteSchaerfe == null) continue;
      if (beste?.besteSchaerfe == null ||
          s.besteSchaerfe! > beste!.besteSchaerfe!) {
        beste = s;
      }
    }
    return beste;
  }
}

class _Spalte extends StatelessWidget {
  final Serienspalte spalte;
  final LibraryState library;
  final bool bestesGesicht;
  final void Function(int sterne) beiBewertung;

  const _Spalte({
    required this.spalte,
    required this.library,
    required this.bestesGesicht,
    required this.beiBewertung,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: bestesGesicht ? farben.primary : farben.outlineVariant,
          width: bestesGesicht ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 130,
            child: AssetThumbnailTile(
              asset: Rasterzeile.aus(spalte.asset),
              paths: library.paths,
              onTap: () {},
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (bestesGesicht)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(t.serienvergleichSchaerfstes,
                  style: TextStyle(
                      color: farben.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
          // Die Gesichter – der eigentliche Grund für diesen Bildschirm.
          for (final g in spalte.gesichter) ...[
            Row(
              children: [
                Profilbild(
                  datei: g.ausschnitt == null
                      ? null
                      : library.paths.absolute(g.ausschnitt!),
                  radius: 26,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (g.name != null)
                        Text(g.name!,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      Text(
                        g.schaerfe == null
                            ? t.serienvergleichOhneWert
                            : t.serienvergleichSchaerfe(
                                g.schaerfe!.round()),
                        style: TextStyle(
                          fontSize: 11,
                          color: g.schaerfe != null &&
                                  g.schaerfe! < gesichtUnscharfSchwelle
                              ? farben.tertiary
                              : farben.onSurfaceVariant,
                        ),
                      ),
                      if (g.augenOffen != null)
                        Text(
                          t.serienvergleichAugen(
                              (g.augenOffen! * 100).round()),
                          style: TextStyle(
                              fontSize: 11, color: farben.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const Divider(),
          StarRating(value: spalte.asset.rating, onChanged: beiBewertung),
        ],
      ),
    );
  }
}
