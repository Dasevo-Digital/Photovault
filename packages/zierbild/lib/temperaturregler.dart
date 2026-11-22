/// Die Spur des Temperaturreglers – am Rechner und auf dem Handy gleich.
library;

import 'package:flutter/material.dart';
import 'package:kern/services/weissabgleich.dart';

/// Die Farben des Verlaufs: was der Regler an dieser Stelle mit dem Bild
/// macht. Links (tiefe Kelvin-Zahl) wird es blauer, rechts gelber, an
/// [neutraleTemperatur] bleibt es, wie es ist (#466).
const temperaturBlau = Color(0xFF3D7BE0);
const temperaturNeutral = Color(0xFFDCDCDC);
const temperaturGelb = Color(0xFFE8B830);

/// Wo im Regler von [min] bis [max] die neutrale Temperatur liegt (0..1).
double neutraleStelle(double min, double max) =>
    ((neutraleTemperatur - min) / (max - min)).clamp(0.0, 1.0);

/// Der Verlauf von [temperaturBlau] über [temperaturNeutral] (bei 6500 K)
/// nach [temperaturGelb].
LinearGradient temperaturVerlauf({
  double min = temperaturMin,
  double max = temperaturMax,
  TextDirection richtung = TextDirection.ltr,
}) => LinearGradient(
  begin: richtung == TextDirection.ltr
      ? Alignment.centerLeft
      : Alignment.centerRight,
  end: richtung == TextDirection.ltr
      ? Alignment.centerRight
      : Alignment.centerLeft,
  colors: const [temperaturBlau, temperaturNeutral, temperaturGelb],
  stops: [0, neutraleStelle(min, max), 1],
);

/// Eine Reglerspur, die statt der Füllung bis zum Knopf den Verlauf der
/// Wirkung zeigt. Ausgeschaltet (automatischer Weissabgleich) wird sie
/// blass.
class TemperaturSpur extends SliderTrackShape with BaseSliderTrackShape {
  const TemperaturSpur({this.min = temperaturMin, this.max = temperaturMax});

  final double min;
  final double max;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final hoehe = sliderTheme.trackHeight ?? 4;
    if (hoehe <= 0) return;
    final rechteck = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final farbe = Paint()
      ..shader = temperaturVerlauf(
        min: min,
        max: max,
        richtung: textDirection,
      ).createShader(rechteck);
    final deckung = 0.35 + 0.65 * enableAnimation.value;
    context.canvas
      ..saveLayer(
        rechteck,
        Paint()..color = Color.fromRGBO(0, 0, 0, deckung.clamp(0.0, 1.0)),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(rechteck, Radius.circular(rechteck.height / 2)),
        farbe,
      )
      ..restore();
  }
}
