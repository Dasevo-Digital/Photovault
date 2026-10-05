import 'package:flutter/material.dart';

import '../services/lebensbaum_vorlage.dart';
import 'lebensbaum_maler.dart';

/// Der Lebensbaum auf dem Schirm.
///
/// Unten das Bild der [vorlage], darüber die Namen von [LebensbaumMaler].
/// Darüber liegt je beschriftetem Schild eine unsichtbare Fläche: zum
/// Antippen – wer tippt, rückt die Person an den Stamm – und damit ein
/// Bildschirmleser die Namen findet, die im Bild nur gemalt sind.
class LebensbaumAnsicht extends StatelessWidget {
  final Lebensbaumvorlage vorlage;
  final Lebensbaumbelegung belegung;
  final Lebensbaumschild Function(String personId) beschriftung;
  final String titel;
  final String? untertitel;
  final ValueChanged<String> beiTipp;

  const LebensbaumAnsicht({
    super.key,
    required this.vorlage,
    required this.belegung,
    required this.beschriftung,
    required this.titel,
    required this.beiTipp,
    this.untertitel,
  });

  @override
  Widget build(BuildContext context) {
    final flaechen = <(Rect, String)>[
      for (final MapEntry(key: i, value: id) in belegung.felder.entries)
        (vorlage.felder[i].rahmen, id),
      for (final (i, r) in vorlage.wurzelflaechen(belegung).indexed)
        (r, belegung.wurzel[i]),
    ];
    return SizedBox.fromSize(
      size: vorlage.groesse,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              vorlage.bild,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
              // Bis das Bild da ist, steht die Schrift auf dem Grund der
              // Tafel statt auf einem leeren Fleck.
              frameBuilder: (context, kind, frame, geladen) =>
                  frame == null ? const SizedBox.expand() : kind,
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: LebensbaumMaler(
                  vorlage: vorlage,
                  belegung: belegung,
                  beschriftung: beschriftung,
                  titel: titel,
                  untertitel: untertitel,
                  textRichtung: Directionality.of(context),
                ),
              ),
            ),
          ),
          for (final (rahmen, id) in flaechen)
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
