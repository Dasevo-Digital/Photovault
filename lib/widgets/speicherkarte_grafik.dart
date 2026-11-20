import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../services/speicherkarte.dart';

String speichergruppenName(AppTexte t, Speichergruppe g) => switch (g) {
  Speichergruppe.bibliothek => t.speicherkarteLokal,
  Speichergruppe.extern => t.speicherkarteExtern,
  Speichergruppe.server => t.speicherkarteServer,
  Speichergruppe.kopien => t.speicherkarteKopie,
  Speichergruppe.arbeitsvorschauen => t.arbeitskopienTitel,
  Speichergruppe.nachgewiesen => t.speicherkarteSicherung,
  Speichergruppe.unbekannt => t.speicherkarteUngeprueft,
  Speichergruppe.fehlt => t.speicherkarteFehlt,
  Speichergruppe.papierkorb => t.speicherkartePapierkorb,
};

/// Verteilungskarte mit bedienbaren Knoten und denselben lesbaren Angaben
/// für Vorlesefunktionen. Verbindungen zeigen Zuordnungen und keine Transfers.
class SpeicherkarteGrafik extends StatelessWidget {
  const SpeicherkarteGrafik({super.key, required this.stand, this.beiAuswahl});
  final SpeicherkarteStand stand;
  final ValueChanged<Speichergruppe>? beiAuswahl;
  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context), farben = Theme.of(context).colorScheme;
    final zahlen = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );
    const gruppen = [
      Speichergruppe.bibliothek,
      Speichergruppe.extern,
      Speichergruppe.server,
      Speichergruppe.nachgewiesen,
      Speichergruppe.arbeitsvorschauen,
      Speichergruppe.unbekannt,
    ];
    const icons = [
      Icons.storage_outlined,
      Icons.folder_outlined,
      Icons.cloud_outlined,
      Icons.verified_user_outlined,
      Icons.cloud_off_outlined,
      Icons.help_outline,
    ];
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final breite = math.max(c.maxWidth, 720.0),
                karte = (breite - 64) / 3;
            final rects = [
              Rect.fromLTWH(breite / 2 - 110, 8, 220, 116),
              for (var i = 0; i < 6; i++)
                Rect.fromLTWH(
                  8 + (i % 3) * (karte + 24),
                  165 + (i ~/ 3) * 142,
                  karte,
                  108,
                ),
            ];
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: breite,
                height: 432,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: CustomPaint(
                          painter: _Verbindungen(rects, farben.outlineVariant),
                        ),
                      ),
                    ),
                    Positioned.fromRect(
                      rect: rects.first,
                      child: Card(
                        color: farben.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(t.speicherkarteBestand),
                              Text(
                                zahlen.format(stand.gesamt),
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < 6; i++)
                      Positioned.fromRect(
                        rect: rects[i + 1],
                        child: Card(
                          child: InkWell(
                            onTap:
                                beiAuswahl == null ||
                                    stand.anzahl(gruppen[i]) == 0
                                ? null
                                : () => beiAuswahl!(gruppen[i]),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Icon(
                                    icons[i],
                                    color:
                                        gruppen[i] == Speichergruppe.unbekannt
                                        ? farben.tertiary
                                        : farben.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          speichergruppenName(t, gruppen[i]),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          zahlen.format(
                                            stand.anzahl(gruppen[i]),
                                          ),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.headlineSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final g in [
              Speichergruppe.kopien,
              Speichergruppe.fehlt,
              Speichergruppe.papierkorb,
            ])
              ActionChip(
                label: Text(
                  '${speichergruppenName(t, g)}: ${zahlen.format(stand.anzahl(g))}',
                ),
                onPressed: beiAuswahl == null || stand.anzahl(g) == 0
                    ? null
                    : () => beiAuswahl!(g),
              ),
          ],
        ),
      ],
    );
  }
}

class _Verbindungen extends CustomPainter {
  const _Verbindungen(this.rects, this.farbe);
  final List<Rect> rects;
  final Color farbe;
  @override
  void paint(Canvas canvas, Size size) {
    final stift = Paint()
      ..color = farbe
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < rects.length; i++) {
      final start = rects.first.bottomCenter, ende = rects[i].topCenter;
      final weg = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx,
          (start.dy + ende.dy) / 2,
          ende.dx,
          (start.dy + ende.dy) / 2,
          ende.dx,
          ende.dy,
        );
      canvas.drawPath(weg, stift);
    }
  }

  @override
  bool shouldRepaint(_Verbindungen alt) =>
      alt.farbe != farbe || alt.rects.first != rects.first;
}
