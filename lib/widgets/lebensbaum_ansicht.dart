import 'package:flutter/material.dart';

import '../services/lebensbaum_bild.dart';
import 'lebensbaum_maler.dart';

/// Der Lebensbaum auf dem Schirm.
///
/// Unten das Bild, darauf die Schilder, die das Bild nicht schon hat,
/// darüber die Namen von [LebensbaumMaler]. Darüber liegt je Person eine
/// unsichtbare Fläche: zum Antippen – wer tippt, rückt die Person an den
/// Stamm – und damit ein Bildschirmleser die Namen findet, die im Bild
/// nur gemalt sind.
class LebensbaumAnsicht extends StatelessWidget {
  final Lebensbaumbild inhalt;
  final Lebensbaumschild Function(String personId) beschriftung;
  final String titel;
  final String? untertitel;
  final ValueChanged<String> beiTipp;

  const LebensbaumAnsicht({
    super.key,
    required this.inhalt,
    required this.beschriftung,
    required this.titel,
    required this.beiTipp,
    this.untertitel,
  });

  @override
  Widget build(BuildContext context) {
    final vorlage = inhalt.vorlage;
    final schildBild = vorlage.schildBild;
    return SizedBox.fromSize(
      size: vorlage.groesse,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              inhalt.hintergrund,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
              // Bis das Bild da ist, steht die Schrift auf dem Grund der
              // Tafel statt auf einem leeren Fleck.
              frameBuilder: (context, kind, frame, geladen) =>
                  frame == null ? const SizedBox.expand() : kind,
            ),
          ),
          if (schildBild != null)
            for (final p in inhalt.plaetze)
              if (p.zuSetzen)
                Positioned.fromRect(
                  rect: p.rahmen,
                  child: Image.asset(
                    schildBild,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                    excludeFromSemantics: true,
                  ),
                ),
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: LebensbaumMaler(
                  inhalt: inhalt,
                  beschriftung: beschriftung,
                  titel: titel,
                  untertitel: untertitel,
                  textRichtung: Directionality.of(context),
                ),
              ),
            ),
          ),
          for (final (rahmen, id) in inhalt.flaechen)
            Positioned.fromRect(
              rect: rahmen,
              child: _Flaeche(
                inhalt: beschriftung(id),
                beiTipp: () => beiTipp(id),
              ),
            ),
        ],
      ),
    );
  }
}

class _Flaeche extends StatelessWidget {
  final Lebensbaumschild inhalt;
  final VoidCallback beiTipp;

  const _Flaeche({required this.inhalt, required this.beiTipp});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: [
        ?inhalt.bezeichnung,
        inhalt.name,
        ?inhalt.lebensspanne,
      ].join(', '),
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: beiTipp,
        ),
      ),
    );
  }
}
