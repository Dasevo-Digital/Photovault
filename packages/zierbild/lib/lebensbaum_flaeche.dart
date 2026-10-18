import 'package:flutter/material.dart';

import 'package:kern/services/lebensbaum_bild.dart';
import 'geometrie_ui.dart';
import 'lebensbaum_maler.dart';

/// Der Lebensbaum auf dem Schirm – am Rechner wie auf dem Telefon.
///
/// Unten das Bild, darauf die Schilder, die das Bild nicht schon hat,
/// darüber die Namen von [LebensbaumMaler]. Darüber liegt je Person eine
/// unsichtbare Fläche: zum Antippen – wer tippt, rückt die Person an den
/// Stamm – und damit ein Bildschirmleser die Namen findet, die im Bild
/// nur gemalt sind.
class Lebensbaumflaeche extends StatelessWidget {
  final Lebensbaumbild inhalt;
  final Lebensbaumschild Function(String personId) beschriftung;
  final String titel;
  final String? untertitel;
  final ValueChanged<String> beiTipp;

  /// Ob es für eine Person ein Porträt gibt; `null` heisst: ohne
  /// Porträts. Die Schrift rückt dann darunter.
  final bool Function(String personId)? hatPortrait;

  /// Das Porträt im Kreis mit [radius] – woher es kommt, weiss die App.
  final Widget Function(String personId, double radius)? portraitBild;

  const Lebensbaumflaeche({
    super.key,
    required this.inhalt,
    required this.beschriftung,
    required this.titel,
    required this.beiTipp,
    this.untertitel,
    this.hatPortrait,
    this.portraitBild,
  });

  @override
  Widget build(BuildContext context) {
    final vorlage = inhalt.vorlage;
    final schildBild = vorlage.schildBild;
    final hatPortrait = this.hatPortrait;
    final portraitBild = this.portraitBild;
    final mitPortrait = hatPortrait == null
        ? null
        : {
            for (final id in inhalt.personen)
              if (hatPortrait(id)) id,
          };
    return SizedBox.fromSize(
      size: vorlage.groesse.alsUi,
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
                  rect: p.rahmen.alsUi,
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
                  mitPortrait: mitPortrait,
                ),
              ),
            ),
          ),
          if (portraitBild != null && mitPortrait != null)
            for (final p in inhalt.plaetze)
              for (final (kreis, id) in portraitKreise(p, mitPortrait.contains))
                Positioned.fromRect(
                  rect: kreis.alsUi,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: vorlage.nebenschrift.alsUi,
                          width: kreis.width * 0.04,
                        ),
                      ),
                      child: portraitBild(id, kreis.width / 2),
                    ),
                  ),
                ),
          for (final (rahmen, id) in inhalt.flaechen)
            Positioned.fromRect(
              rect: rahmen.alsUi,
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
