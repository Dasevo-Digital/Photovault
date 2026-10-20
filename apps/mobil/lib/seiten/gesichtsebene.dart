import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/gesichtsuebersicht.dart';

import '../sitzung.dart';

/// Die Gesichter eines Fotos als Rahmen darüber – und ein Gesicht von Hand
/// aufziehen (Issue #190), wie am Rechner und im Browser. Liegt im Bild,
/// das PhotoView zoomt; die Rahmen wachsen also mit.
///
/// Farben wie dort: benannt grün, unbenannt orange, beiseitegelegt grau.
class Gesichtsebene extends StatelessWidget {
  const Gesichtsebene({
    super.key,
    required this.sitzung,
    required this.zeile,
    required this.stand,
    required this.aufziehen,
    required this.beiTipp,
    required this.beiRahmen,
  });

  final Sitzung sitzung;
  final Rasterzeile zeile;

  /// Zählt hoch, wenn sich die Gesichter geändert haben – dann neu laden.
  final int stand;
  final bool aufziehen;
  final void Function(GesichtAufAufnahme g) beiTipp;

  /// Der aufgezogene Rahmen in Anteilen des Bildes.
  final void Function(Rect kasten) beiRahmen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      // Wo das Bild in der Fläche liegt: BoxFit.contain, mittig – mit den
      // gedrehten Massen, nach denen auch das Raster legt.
      final w = zeile.widthPx, h = zeile.heightPx;
      final bild = w != null && h != null && w > 0 && h > 0
          ? Size(w.toDouble(), h.toDouble())
          : const Size(4, 3);
      final ziel = applyBoxFit(BoxFit.contain, bild, c.biggest).destination;
      final rahmen = Alignment.center.inscribe(ziel, Offset.zero & c.biggest);
      return Stack(
        children: [
          Positioned.fromRect(
            rect: rahmen,
            child: FutureBuilder<List<GesichtAufAufnahme>>(
              key: ValueKey('${zeile.id}-$stand'),
              future: gesichterDerAufnahme(sitzung.db, zeile.id),
              builder: (context, s) => _Flaeche(
                gesichter: s.data ?? const [],
                aufziehen: aufziehen,
                beiTipp: beiTipp,
                beiRahmen: beiRahmen,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _Flaeche extends StatefulWidget {
  const _Flaeche({
    required this.gesichter,
    required this.aufziehen,
    required this.beiTipp,
    required this.beiRahmen,
  });

  final List<GesichtAufAufnahme> gesichter;
  final bool aufziehen;
  final void Function(GesichtAufAufnahme g) beiTipp;
  final void Function(Rect kasten) beiRahmen;

  @override
  State<_Flaeche> createState() => _FlaecheState();
}

class _FlaecheState extends State<_Flaeche> {
  Offset? _von;
  Offset? _bis;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final groesse = c.biggest;
      Offset innen(Offset p) => Offset(
        p.dx.clamp(0.0, groesse.width),
        p.dy.clamp(0.0, groesse.height),
      );
      final zug = _von != null && _bis != null
          ? Rect.fromPoints(_von!, _bis!)
          : null;
      return GestureDetector(
        behavior: widget.aufziehen
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onPanStart: widget.aufziehen
            ? (d) => setState(() {
                _von = innen(d.localPosition);
                _bis = _von;
              })
            : null,
        onPanUpdate: widget.aufziehen
            ? (d) => setState(() => _bis = innen(d.localPosition))
            : null,
        onPanEnd: widget.aufziehen
            ? (_) {
                // Aus dem Zustand, nicht aus [zug]: Der stammt aus dem
                // letzten Aufbau, und zwischen Bewegung und Loslassen liegt
                // nicht immer einer.
                final von = _von, bis = _bis;
                final r = von == null || bis == null
                    ? null
                    : Rect.fromPoints(von, bis);
                setState(() => _von = _bis = null);
                if (r == null || groesse.width <= 0 || groesse.height <= 0) {
                  return;
                }
                widget.beiRahmen(
                  Rect.fromLTWH(
                    r.left / groesse.width,
                    r.top / groesse.height,
                    r.width / groesse.width,
                    r.height / groesse.height,
                  ),
                );
              }
            : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final g in widget.gesichter)
              Positioned(
                left: g.gesicht.boxX * groesse.width,
                top: g.gesicht.boxY * groesse.height,
                width: g.gesicht.boxW * groesse.width,
                height: g.gesicht.boxH * groesse.height,
                child: IgnorePointer(
                  ignoring: widget.aufziehen,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.beiTipp(g),
                    child: _Rahmen(g: g),
                  ),
                ),
              ),
            if (zug != null)
              Positioned.fromRect(
                rect: zug,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.12),
                      border: Border.all(color: Colors.cyanAccent, width: 2),
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

class _Rahmen extends StatelessWidget {
  const _Rahmen({required this.g});

  final GesichtAufAufnahme g;

  @override
  Widget build(BuildContext context) {
    final f = g.gesicht;
    final farbe = f.isIgnored
        ? Colors.grey
        : g.person != null
        ? Colors.greenAccent
        : Colors.orangeAccent;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: farbe, width: 2),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        // Der Name unter dem Rahmen, darf breiter sein als das Gesicht.
        if (g.person != null)
          Positioned(
            left: -2,
            bottom: -20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                g.person!.name,
                maxLines: 1,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }
}

/// Legt ein aufgezogenes Gesicht am Server an – die Kopie des Telefons darf
/// nicht selbst schreiben – und wartet, bis es über den Abgleich hier ist.
/// `null`, wenn das nicht ging.
Future<FaceData?> gesichtAmServerAnlegen(
  Sitzung sitzung,
  String assetId,
  Rect kasten,
) async {
  final a = sitzung.abgleich;
  if (a == null) return null;
  final antwort = await a.verbindung.schicke(
    'api/v1/aufnahmen/${Uri.encodeComponent(assetId)}/gesichter',
    {
      'kasten': [kasten.left, kasten.top, kasten.width, kasten.height],
    },
  );
  final id = (antwort['gesicht']! as Map)['id']! as String;
  for (var i = 0; i < 25; i++) {
    await sitzung.gleicheAb();
    final da = (await sitzung.db.facesForAsset(
      assetId,
    )).where((f) => f.id == id).firstOrNull;
    if (da != null) return da;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return null;
}
