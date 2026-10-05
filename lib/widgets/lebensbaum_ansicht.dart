import 'package:flutter/material.dart';

import '../services/lebensbaum.dart';
import 'lebensbaum_maler.dart';

/// Der Lebensbaum auf dem Schirm.
///
/// Gemalt wird alles von [LebensbaumMaler]. Darüber liegt je Schild eine
/// unsichtbare Fläche: zum Antippen – wer tippt, rückt die Person an den
/// Stamm – und damit ein Bildschirmleser die Namen findet, die im Bild nur
/// als Pinselstriche vorkommen.
class LebensbaumAnsicht extends StatelessWidget {
  final Lebensbaumplan plan;
  final Lebensbaummasse masse;
  final Lebensbaumfarben farben;
  final Lebensbaumschild Function(String personId) beschriftung;
  final String titel;
  final ValueChanged<String> beiTipp;

  const LebensbaumAnsicht({
    super.key,
    required this.plan,
    required this.masse,
    required this.farben,
    required this.beschriftung,
    required this.titel,
    required this.beiTipp,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: plan.breite,
      height: plan.hoehe,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: LebensbaumMaler(
                  plan: plan,
                  masse: masse,
                  farben: farben,
                  beschriftung: beschriftung,
                  titel: titel,
                  textRichtung: Directionality.of(context),
                ),
              ),
            ),
          ),
          for (final k in plan.knoten)
            for (var i = 0; i < k.schilder.length; i++)
              Positioned.fromRect(
                rect: k.schilder[i],
                child: _Flaeche(
                  inhalt: beschriftung(k.personen[i]),
                  beiTipp: () => beiTipp(k.personen[i]),
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
      label: [inhalt.name, ?inhalt.lebensspanne].join(', '),
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
