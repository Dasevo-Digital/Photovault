import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../services/stammbaum.dart';
import '../services/verwandtschaftsgrad.dart';

/// Setzt einen berechneten [Grad] in die Sprache der Oberfläche um.
///
/// Getrennt von der Berechnung, weil beides verschieden altert: Die
/// Verwandtschaftsrechnung ist über Sprachen hinweg dieselbe, die
/// Bezeichnungen sind es nicht. Deutsch und Englisch bauen die Stufen
/// zwar beide durch Vorsilben („Ur-", „great-"), aber unterschiedlich
/// genug, dass ein im Quelltext zusammengesetztes Wort in einer der
/// beiden Sprachen falsch würde. Deshalb ein eigener Baustein je Stufe –
/// und ab der fünften eine ausgeschriebene Auskunft statt eines Wortes,
/// das es nicht mehr gibt.
String verwandtschaftText(BuildContext context, Grad grad, Geschlecht? geschlecht) {
  final t = AppTexte.of(context);
  final g = auswahlwert(geschlecht);

  switch (grad.art) {
    case Gradart.selbst:
      return t.gradSelbst;

    case Gradart.vorfahre:
      // Die Art der Elternschaft zählt nur eine Stufe weit – siehe
      // [Grad.elternArt].
      if (grad.elternArt == Verwandtschaft.adoptivelternteil) {
        return t.gradAdoptiveltern(g);
      }
      if (grad.elternArt == Verwandtschaft.pflegeelternteil) {
        return t.gradPflegeeltern(g);
      }
      return switch (grad.aufwaerts) {
        1 => t.gradEltern(g),
        2 => t.gradGrosseltern(g),
        3 => t.gradUrgrosseltern(g),
        4 => t.gradUrurgrosseltern(g),
        _ => t.gradVorfahreN(grad.aufwaerts),
      };

    case Gradart.nachkomme:
      if (grad.elternArt == Verwandtschaft.adoptivelternteil) {
        return t.gradAdoptivkind(g);
      }
      if (grad.elternArt == Verwandtschaft.pflegeelternteil) {
        return t.gradPflegekind(g);
      }
      return switch (grad.abwaerts) {
        1 => t.gradKind(g),
        2 => t.gradEnkel(g),
        3 => t.gradUrenkel(g),
        4 => t.gradUrurenkel(g),
        _ => t.gradNachkommeN(grad.abwaerts),
      };

    case Gradart.geschwister:
      return grad.halb ? t.gradHalbgeschwister(g) : t.gradGeschwister(g);

    case Gradart.geschwisterkind:
      return switch (grad.abwaerts) {
        2 => t.gradNeffeNichte(g),
        3 => t.gradGrossneffeNichte(g),
        _ => t.gradGeschwisterNachkommeN(grad.abwaerts),
      };

    case Gradart.vorfahrengeschwister:
      return switch (grad.aufwaerts) {
        2 => t.gradOnkelTante(g),
        3 => t.gradGrossonkelTante(g),
        _ => t.gradVorfahrengeschwisterN(grad.aufwaerts),
      };

    case Gradart.cousin:
      final grund = t.gradCousin(g, grad.cousinGrad);
      // „Einmal entfernt" heißt: die beiden stehen in verschiedenen
      // Generationen. Ohne diesen Zusatz hießen der Cousin und dessen
      // Kind gleich.
      return grad.entfernung == 0
          ? grund
          : t.gradEntfernt(grad.entfernung, grund);

    case Gradart.partner:
      return t.gradPartner(g);
    case Gradart.schwager:
      return t.gradSchwager(g);
    case Gradart.schwiegerelternteil:
      return t.gradSchwiegereltern(g);
    case Gradart.schwiegerkind:
      return t.gradSchwiegerkind(g);
    case Gradart.stiefelternteil:
      return t.gradStiefeltern(g);
    case Gradart.stiefkind:
      return t.gradStiefkind(g);
    case Gradart.stiefgeschwister:
      return t.gradStiefgeschwister(g);
    case Gradart.angeheiratet:
      return t.gradAngeheiratet;
    case Gradart.keine:
      return t.gradKeine;
  }
}

/// Der Satz für jemanden, den kein einzelnes Wort trifft – „Mutter von
/// Schwager Michael".
///
/// [geschlecht] gehört zur gesuchten Person und bestimmt den ersten Teil,
/// [geschlechtZwischen] zur Zwischenperson und den zweiten. Beide werden
/// wirklich gebraucht: „Mutter von Schwägerin Anna" und „Vater von
/// Schwager Michael" unterscheiden sich in beiden Hälften.
String verwandtschaftUeberWegText(
  BuildContext context,
  Umweg umweg,
  String nameDerZwischenperson, {
  Geschlecht? geschlecht,
  Geschlecht? geschlechtZwischen,
}) {
  final t = AppTexte.of(context);
  return t.gradUeberWeg(
    verwandtschaftText(context, umweg.schritt, geschlecht),
    verwandtschaftText(context, umweg.ueberGrad, geschlechtZwischen),
    nameDerZwischenperson,
  );
}
