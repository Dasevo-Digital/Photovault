import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/sortierung.dart';

/// Der Name einer Reihenfolge in der Sprache der Oberfläche.
String sortierungName(AppTexte t, Rastersortierung s) => switch (s) {
      Rastersortierung.aufnahmeNeu => t.sortAufnahmeNeu,
      Rastersortierung.aufnahmeAlt => t.sortAufnahmeAlt,
      Rastersortierung.importNeu => t.sortImportNeu,
      Rastersortierung.name => t.sortName,
      Rastersortierung.bewertung => t.sortBewertung,
      Rastersortierung.groesse => t.sortGroesse,
    };

/// Das Symbol zu einer Reihenfolge.
IconData sortierungSymbol(Rastersortierung s) => switch (s) {
      Rastersortierung.aufnahmeNeu => Icons.south,
      Rastersortierung.aufnahmeAlt => Icons.north,
      Rastersortierung.importNeu => Icons.file_download_outlined,
      Rastersortierung.name => Icons.sort_by_alpha,
      Rastersortierung.bewertung => Icons.star_outline,
      Rastersortierung.groesse => Icons.data_usage_outlined,
    };

/// Der Menüwert für „Fundreihenfolge".
///
/// **Warum ein eigener Wert und nicht `null`.** `PopupMenuButton` deutet
/// `null` als „abgebrochen" und ruft `onSelected` dann gar nicht auf –
/// der Eintrag wäre still wirkungslos. Aufgefallen ist das erst am Test,
/// der nach dem Umsortieren wieder zurückstellte.
enum _Fundreihenfolge { wert }

const Object _fundreihenfolge = _Fundreihenfolge.wert;

/// Wonach eine Kachelwand ordnet – als Menü hinter einem Symbol.
///
/// **Ein Baustein für Zeitleiste und Suche.** Beide brauchen dieselbe
/// Liste, und zwei Listen wären zwei Listen, die auseinanderlaufen,
/// sobald jemand nur eine anfasst. Die Suche kennt zusätzlich die
/// **Fundreihenfolge** – bei einer Bildersuche steht dort die Ähnlichkeit,
/// und die lässt sich durch keine Spalte nachbilden. Sie ist `null`.
class Sortierungswahl extends StatelessWidget {
  const Sortierungswahl({
    super.key,
    required this.gewaehlt,
    required this.beiWahl,
    this.mitFundreihenfolge = false,
  });

  /// Die aktuelle Wahl; `null` heisst Fundreihenfolge.
  final Rastersortierung? gewaehlt;

  final ValueChanged<Rastersortierung?> beiWahl;

  /// Ob „Fundreihenfolge" als erster Eintrag angeboten wird.
  final bool mitFundreihenfolge;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final gewaehltesSymbol =
        gewaehlt == null ? Icons.sort : sortierungSymbol(gewaehlt!);
    return PopupMenuButton<Object>(
      tooltip: t.sortReihenfolge,
      // Zwei Symbole nebeneinander: das allgemeine „Sortieren" sagt, was
      // der Knopf tut, das zweite, was gerade gilt. Ohne das zweite müsste
      // man das Menü öffnen, um die eingestellte Reihenfolge zu sehen.
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sort, size: 20),
          Icon(gewaehltesSymbol, size: 14),
        ],
      ),
      onSelected: (wert) =>
          beiWahl(wert is Rastersortierung ? wert : null),
      itemBuilder: (context) => [
        if (mitFundreihenfolge)
          CheckedPopupMenuItem<Object>(
            value: _fundreihenfolge,
            checked: gewaehlt == null,
            child: Text(t.sortFundreihenfolge),
          ),
        for (final s in Rastersortierung.values)
          CheckedPopupMenuItem<Object>(
            value: s,
            checked: gewaehlt == s,
            child: Text(sortierungName(t, s)),
          ),
      ],
    );
  }
}
