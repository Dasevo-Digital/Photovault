import 'package:flutter/material.dart';

export 'zierschrift.dart';

/// Die Farben des Zierbaums.
///
/// **Warum ein Wertobjekt und keine Verzweigung im Maler.** Der Baum wird
/// an zwei Stellen gezeichnet: auf dem Bildschirm und – sehr viel grösser
/// – für die Tafel zum Aufhängen. Fragte der Maler selbst nach dem
/// Erscheinungsbild, malte der Prüfstand die eine Fassung und das Papier
/// die andere, ohne dass es jemandem auffiele. So wird die Wahl einmal
/// getroffen und danach durchgereicht.
///
/// **Zwei Fassungen, weil eine gelogen wäre.** Gold lebt vom dunklen
/// Grund; auf Weiss wird daraus ein schmutziges Gelb. Wer tagsüber hell
/// arbeitet, bekommt deshalb Bronze auf Pergament statt einer
/// aufgehellten Notlösung.
@immutable
class Zierbaumfarben {
  /// Der Grund, aussen.
  final Color grundAussen;

  /// Der Grund in der Mitte – dorthin geht der warme Schein.
  final Color grundInnen;

  /// Stamm und Äste, am Stamm.
  final Color holzDunkel;

  /// Stamm und Äste, an den Spitzen.
  final Color holzHell;

  /// Die Ranken, die nichts bedeuten.
  final Color ranken;

  /// Das Schild selbst.
  final Color schildOben;
  final Color schildUnten;
  final Color schildRand;

  /// Der Name auf dem Schild.
  final Color schrift;

  /// Die Verwandtschaft darunter.
  final Color nebenschrift;

  /// Das Schild der Person in der Mitte hebt sich ab.
  final Color mitteRand;

  /// Der Familienname unten.
  final Color familienname;

  /// Der Staub.
  final Color staub;

  const Zierbaumfarben({
    required this.grundAussen,
    required this.grundInnen,
    required this.holzDunkel,
    required this.holzHell,
    required this.ranken,
    required this.schildOben,
    required this.schildUnten,
    required this.schildRand,
    required this.schrift,
    required this.nebenschrift,
    required this.mitteRand,
    required this.familienname,
    required this.staub,
  });

  /// Gold auf dunklem Grund.
  static const dunkel = Zierbaumfarben(
    grundAussen: Color(0xFF120A06),
    grundInnen: Color(0xFF3A1E0C),
    holzDunkel: Color(0xFF8A6013),
    holzHell: Color(0xFFE8C271),
    ranken: Color(0xFFB08637),
    schildOben: Color(0xFFF6DFA4),
    schildUnten: Color(0xFFC9992F),
    schildRand: Color(0xFF7A5410),
    schrift: Color(0xFF2A1B05),
    nebenschrift: Color(0xFF5C4212),
    mitteRand: Color(0xFFFFF0C4),
    familienname: Color(0xFFE8C271),
    staub: Color(0xFFFFD980),
  );

  /// Bronze auf Pergament.
  ///
  /// Nicht die dunkle Fassung mit vertauschten Werten: Dieselben
  /// Goldtöne auf hellem Grund verlieren jeden Halt. Die Töne sind
  /// deshalb satter und dunkler, und der Grund trägt einen Stich ins
  /// Warme statt ins Weisse.
  static const hell = Zierbaumfarben(
    grundAussen: Color(0xFFE8DCC2),
    grundInnen: Color(0xFFF7EFDC),
    holzDunkel: Color(0xFF6B4A1E),
    holzHell: Color(0xFFA97C33),
    ranken: Color(0xFFB39154),
    schildOben: Color(0xFFFFF8E6),
    schildUnten: Color(0xFFE3CD95),
    schildRand: Color(0xFF9A7527),
    schrift: Color(0xFF2E2008),
    nebenschrift: Color(0xFF6B5426),
    mitteRand: Color(0xFF6B4A1E),
    familienname: Color(0xFF6B4A1E),
    staub: Color(0xFFC9A96A),
  );

  /// Zwei Farbsätze sind gleich, wenn jede Farbe gleich ist.
  ///
  /// Für `shouldRepaint`: Sonst gälte jeder neu gebaute Satz als anders.
  @override
  bool operator ==(Object other) =>
      other is Zierbaumfarben &&
      other.grundAussen == grundAussen &&
      other.grundInnen == grundInnen &&
      other.holzDunkel == holzDunkel &&
      other.holzHell == holzHell &&
      other.ranken == ranken &&
      other.schildOben == schildOben &&
      other.schildUnten == schildUnten &&
      other.schildRand == schildRand &&
      other.schrift == schrift &&
      other.nebenschrift == nebenschrift &&
      other.mitteRand == mitteRand &&
      other.familienname == familienname &&
      other.staub == staub;

  @override
  int get hashCode => Object.hash(
    grundAussen,
    grundInnen,
    holzDunkel,
    holzHell,
    ranken,
    schildOben,
    schildUnten,
    schildRand,
    schrift,
    nebenschrift,
    mitteRand,
    familienname,
    staub,
  );

  /// Die Fassung, die zum Erscheinungsbild passt.
  static Zierbaumfarben fuer(Brightness helligkeit) =>
      helligkeit == Brightness.dark ? dunkel : hell;
}
