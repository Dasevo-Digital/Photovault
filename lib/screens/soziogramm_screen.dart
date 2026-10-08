import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/soziogramm.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/profilbild.dart';
import 'asset_viewer_screen.dart';

typedef _Stand = ({
  Soziogramm netz,
  Map<String, Offset> lage,
  Map<String, PersonData> personen,

  /// Person -> ihre Fotos, für „gemeinsame Fotos öffnen".
  Map<String, Set<String>> fotos,
});

/// **Wer mit wem auf Fotos ist** – siehe [soziogramm].
class SoziogrammScreen extends StatefulWidget {
  final LibraryState library;
  const SoziogrammScreen({super.key, required this.library});

  @override
  State<SoziogrammScreen> createState() => _SoziogrammScreenState();
}

class _SoziogrammScreenState extends State<SoziogrammScreen> {
  late final Future<_Stand> _stand = _laden();
  String? _gewaehlt;

  Future<_Stand> _laden() async {
    final db = widget.library.db;
    final auftritte = await db.personenAuftritte();
    final netz = soziogramm(auftritte);
    final fotos = <String, Set<String>>{};
    for (final a in auftritte) {
      (fotos[a.personId] ??= {}).add(a.assetId);
    }
    return (
      netz: netz,
      lage: soziogrammAnordnung(netz),
      personen: {
        for (final p in await db.allePersonen())
          if (netz.personen.containsKey(p.id)) p.id: p,
      },
      fotos: fotos,
    );
  }

  Future<void> _gemeinsameOeffnen(_Stand s, String a, String b) async {
    final ids = s.fotos[a]!.intersection(s.fotos[b]!).toList();
    final aufnahmen = await widget.library.db.assetsByIds(ids)
      ..sort((x, y) => y.fileCreatedAt.compareTo(x.fileCreatedAt));
    if (aufnahmen.isEmpty || !mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AssetViewerScreen(
          assets: aufnahmen,
          initialIndex: 0,
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
      appBar: AppBar(title: Text(t.soziogrammTitel)),
      body: FutureBuilder<_Stand>(
        future: _stand,
        builder: (context, schnappschuss) {
          final s = schnappschuss.data;
          if (s == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.netz.istLeer) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(t.soziogrammLeer, textAlign: TextAlign.center),
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, platz) {
              final breit = platz.maxWidth > 900;
              final netz = _netzbild(context, s);
              final liste = _verbindungen(context, t, s);
              return breit
                  ? Row(
                      children: [
                        Expanded(child: netz),
                        SizedBox(width: 320, child: liste),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(flex: 3, child: netz),
                        Expanded(flex: 2, child: liste),
                      ],
                    );
            },
          );
        },
      ),
    );
  }

  Widget _netzbild(BuildContext context, _Stand s) {
    const flaeche = Size(1000, 800);
    const radius = 26.0;
    final farbe = Theme.of(context).colorScheme;
    Offset punkt(String id) =>
        Offset(s.lage[id]!.dx * flaeche.width, s.lage[id]!.dy * flaeche.height);
    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(200),
      minScale: 0.3,
      maxScale: 3,
      child: SizedBox.fromSize(
        size: flaeche,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _Linien(
                  kanten: s.netz.kanten,
                  punkt: punkt,
                  gewaehlt: _gewaehlt,
                  farbe: farbe.primary,
                  blass: farbe.outlineVariant,
                ),
              ),
            ),
            for (final id in s.netz.personen.keys)
              Positioned(
                left: punkt(id).dx - 50,
                top: punkt(id).dy - radius,
                width: 100,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _gewaehlt = _gewaehlt == id ? null : id),
                  child: Column(
                    children: [
                      DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _gewaehlt == id
                                ? farbe.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: Profilbild(
                          datei: s.personen[id]?.coverFaceCropPath == null
                              ? null
                              : widget.library.paths.absolute(
                                  s.personen[id]!.coverFaceCropPath!,
                                ),
                          radius: radius,
                        ),
                      ),
                      Text(
                        s.personen[id]?.name ?? '?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Die Verbindungen der gewählten Person – oder, ohne Wahl, die
  /// stärksten des ganzen Netzes.
  Widget _verbindungen(BuildContext context, AppTexte t, _Stand s) {
    final gewaehlt = _gewaehlt;
    final kanten = gewaehlt == null
        ? s.netz.kanten.take(20).toList()
        : [
            for (final k in s.netz.kanten)
              if (k.a == gewaehlt || k.b == gewaehlt) k,
          ];
    String name(String id) => s.personen[id]?.name ?? '?';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            gewaehlt == null
                ? t.soziogrammStaerkste
                : t.soziogrammVerbindungenVon(name(gewaehlt)),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final k in kanten)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                gewaehlt == null
                    ? '${name(k.a)} & ${name(k.b)}'
                    : name(k.a == gewaehlt ? k.b : k.a),
              ),
              trailing: Text(t.soziogrammGemeinsam(k.fotos)),
              onTap: () => _gemeinsameOeffnen(s, k.a, k.b),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            t.soziogrammHinweis,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Linien extends CustomPainter {
  final List<Soziogrammkante> kanten;
  final Offset Function(String) punkt;
  final String? gewaehlt;
  final Color farbe;
  final Color blass;

  _Linien({
    required this.kanten,
    required this.punkt,
    required this.gewaehlt,
    required this.farbe,
    required this.blass,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (kanten.isEmpty) return;
    final staerkste = kanten.first.fotos;
    // Die schwachen zuerst, damit die starken obenauf liegen.
    for (final k in kanten.reversed) {
      final betrifft = gewaehlt == null || k.a == gewaehlt || k.b == gewaehlt;
      final anteil = k.fotos / staerkste;
      canvas.drawLine(
        punkt(k.a),
        punkt(k.b),
        Paint()
          ..color = (betrifft ? farbe : blass).withValues(
            alpha: betrifft ? 0.25 + 0.6 * anteil : 0.25,
          )
          ..strokeWidth = 1 + 7 * math.sqrt(anteil)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_Linien alt) =>
      alt.gewaehlt != gewaehlt || alt.kanten != kanten || alt.farbe != farbe;
}
