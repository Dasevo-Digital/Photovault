import 'package:flutter/widgets.dart';

/// Eine Steuerung für kurze Listen, in denen das Rollen nichts überspringen
/// darf.
///
/// **Warum.** Am Mac rechnet Flutter eine Zeile des Mausrads in 40 Punkte
/// um, und macOS beschleunigt: Ein schnell gedrehtes Rad meldet zehn Zeilen
/// und mehr in einem einzigen Ereignis. Eine Maus über die Fernsteuerung
/// schickt ähnlich grosse Schritte. In der Personenauswahl, deren Liste
/// rund fünf Zeilen hoch ist, sprang ein Schritt über alles hinweg, was
/// gerade zu sehen war – von 40 Personen kamen 21 nie ins Bild und liessen
/// sich nicht anklicken.
///
/// Ein Schritt geht deshalb höchstens um [schrittAnteil] der sichtbaren
/// Höhe weiter; ein gemächlich gedrehtes Rad (40 Punkte je Raste) merkt
/// davon nichts. Dasselbe gilt für einen Wisch über Magic Mouse oder
/// Trackpad, und dessen Schwung danach ist auf
/// [schwungHoehenProSekunde] sichtbare Höhen je Sekunde begrenzt.
///
/// Für lange Ansichten wie die Zeitleiste ist das nichts: Dort soll ein
/// schneller Dreh weit tragen.
class GebremsteRollsteuerung extends ScrollController {
  GebremsteRollsteuerung({
    this.schrittAnteil = 0.5,
    this.schwungHoehenProSekunde = 8,
  });

  final double schrittAnteil;
  final double schwungHoehenProSekunde;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _GebremstePosition(
    steuerung: this,
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class _GebremstePosition extends ScrollPositionWithSingleContext {
  _GebremstePosition({
    required this.steuerung,
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  final GebremsteRollsteuerung steuerung;

  /// Begrenzt [wert] auf ±[anteil] der sichtbaren Höhe. Vor dem ersten
  /// Layout gibt es keine Höhe – dann bleibt der Wert, wie er ist.
  double _begrenzt(double wert, double anteil) {
    if (!hasViewportDimension || viewportDimension <= 0) return wert;
    final grenze = viewportDimension * anteil;
    return wert.clamp(-grenze, grenze);
  }

  @override
  void pointerScroll(double delta) =>
      super.pointerScroll(_begrenzt(delta, steuerung.schrittAnteil));

  @override
  void applyUserOffset(double delta) =>
      super.applyUserOffset(_begrenzt(delta, steuerung.schrittAnteil));

  @override
  void goBallistic(double velocity) =>
      super.goBallistic(_begrenzt(velocity, steuerung.schwungHoehenProSekunde));
}
