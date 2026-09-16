import 'package:flutter/material.dart';

import '../db/database.dart';
import '../services/sanduhr.dart';
import '../services/stammbaum.dart';
import '../theme/app_spacing.dart';

/// Ein Kasten in der Sanduhr. Kleiner als die Karten der Baum-Ansicht –
/// dort stehen drei Personen, hier bis zu fünfzehn.
const double _kastenBreite = 116;
const double _kastenHoehe = 56;
const double _spaltenAbstand = AppSpacing.md;
const double _reihenAbstand = 44;

/// Die Sanduhr: Vorfahren nach oben, Nachkommen nach unten, die gewählte
/// Person in der Taille.
///
/// Anders als die Baum-Ansicht zeigt sie mehrere Generationen – möglich
/// geworden durch die Anordnung in [ordneSanduhr], die jedem Vorfahren
/// seinen eigenen Platz über seinem Kind gibt. Deshalb bleibt hier jede
/// Linie eindeutig, auch über drei Generationen.
class SanduhrAnsicht extends StatelessWidget {
  final Sanduhr sanduhr;
  final Map<String, PersonData> personen;
  final String fokusId;
  final void Function(String personId) onTippen;

  const SanduhrAnsicht({
    super.key,
    required this.sanduhr,
    required this.personen,
    required this.fokusId,
    required this.onTippen,
  });

  Offset _lage(Sanduhrknoten k) => Offset(
        (k.spalte - sanduhr.vonSpalte) * (_kastenBreite + _spaltenAbstand),
        (k.reihe - sanduhr.obersteReihe) * (_kastenHoehe + _reihenAbstand),
      );

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final breite = (sanduhr.bisSpalte - sanduhr.vonSpalte) *
            (_kastenBreite + _spaltenAbstand) +
        _kastenBreite;
    final hoehe = (sanduhr.untersteReihe - sanduhr.obersteReihe) *
            (_kastenHoehe + _reihenAbstand) +
        _kastenHoehe;
    final lagen = {for (final k in sanduhr.knoten) k.personId: _lage(k)};

    return LayoutBuilder(
      builder: (context, platz) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: platz.maxWidth,
              minHeight: platz.maxHeight,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: SizedBox(
                  width: breite,
                  height: hoehe,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _KantenMaler(
                            kanten: sanduhr.kanten,
                            lagen: lagen,
                            farbe: farben.outlineVariant,
                            betont: farben.outline,
                          ),
                        ),
                      ),
                      for (final k in sanduhr.knoten)
                        if (personen[k.personId] case final person?)
                          Positioned(
                            left: _lage(k).dx,
                            top: _lage(k).dy,
                            width: _kastenBreite,
                            height: _kastenHoehe,
                            child: _Kasten(
                              person: person,
                              istFokus: k.personId == fokusId,
                              istPartner: k.istPartner,
                              onTippen: () => onTippen(k.personId),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Kasten extends StatelessWidget {
  final PersonData person;
  final bool istFokus;
  final bool istPartner;
  final VoidCallback onTippen;

  const _Kasten({
    required this.person,
    required this.istFokus,
    required this.istPartner,
    required this.onTippen,
  });

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final spanne = lebensspanne(person.geburtsdatum, person.sterbedatum);
    return Semantics(
      label: person.name,
      button: true,
      child: InkWell(
        onTap: istFokus ? null : onTippen,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: istFokus ? farben.primaryContainer : farben.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: istFokus ? farben.primary : farben.outlineVariant,
              width: istFokus ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: istFokus ? FontWeight.w600 : FontWeight.w400,
                  color: istFokus ? farben.onPrimaryContainer : farben.onSurface,
                ),
              ),
              if (spanne != null)
                Text(spanne,
                    style: TextStyle(fontSize: 10, color: farben.onSurfaceVariant)),
              if (istPartner)
                Text('∞',
                    style: TextStyle(fontSize: 10, color: farben.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zeichnet die Verbindungen unter den Kästen.
class _KantenMaler extends CustomPainter {
  final List<Sanduhrkante> kanten;
  final Map<String, Offset> lagen;
  final Color farbe;
  final Color betont;

  const _KantenMaler({
    required this.kanten,
    required this.lagen,
    required this.farbe,
    required this.betont,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final k in kanten) {
      final von = lagen[k.vonId];
      final zu = lagen[k.zuId];
      if (von == null || zu == null) continue;

      final stift = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = k.art == Verwandtschaft.partner ? betont : farbe;

      if (k.art == Verwandtschaft.partner) {
        // Waagerecht von Kastenrand zu Kastenrand.
        final links = von.dx < zu.dx ? von : zu;
        final rechts = von.dx < zu.dx ? zu : von;
        final y = links.dy + _kastenHoehe / 2;
        canvas.drawLine(Offset(links.dx + _kastenBreite, y),
            Offset(rechts.dx, y), stift);
        continue;
      }

      // Kind -> Elternteil, also von unten nach oben. In drei Strecken
      // statt als Schräge: Eine gerade Linie durch die Reihe hindurch
      // liefe quer über fremde Kästen.
      final kind = von.dy > zu.dy ? von : zu;
      final elternteil = von.dy > zu.dy ? zu : von;
      final kindX = kind.dx + _kastenBreite / 2;
      final elternX = elternteil.dx + _kastenBreite / 2;
      final oben = elternteil.dy + _kastenHoehe;
      final unten = kind.dy;
      final mitte = (oben + unten) / 2;

      final pfad = Path()
        ..moveTo(kindX, unten)
        ..lineTo(kindX, mitte)
        ..lineTo(elternX, mitte)
        ..lineTo(elternX, oben);

      // Adoption und Pflege gestrichelt – dieselbe Unterscheidung wie im
      // Fächer, damit sie überall dasselbe bedeutet.
      canvas.drawPath(
        k.art == Verwandtschaft.elternteil ? pfad : _gestrichelt(pfad),
        stift,
      );
    }
  }

  Path _gestrichelt(Path pfad, {double strich = 5, double luecke = 4}) {
    final ergebnis = Path();
    for (final teil in pfad.computeMetrics()) {
      var pos = 0.0;
      while (pos < teil.length) {
        final bis = pos + strich < teil.length ? pos + strich : teil.length;
        ergebnis.addPath(teil.extractPath(pos, bis), Offset.zero);
        pos = bis + luecke;
      }
    }
    return ergebnis;
  }

  @override
  bool shouldRepaint(_KantenMaler alt) =>
      alt.kanten != kanten || alt.lagen != lagen || alt.farbe != farbe;
}
