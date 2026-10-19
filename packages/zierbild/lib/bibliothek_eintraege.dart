/// Wie die Bereiche der Bibliothek aussehen – in Rechner, Handy und
/// Browser gleich.
///
/// Die Farben stehen ebenso im Browser (packages/server/web/app.js,
/// `BIBLIOTHEK`); wer hier eine ändert, ändert sie dort mit. Die Symbole
/// sind die Material-Gegenstücke zu den gezeichneten im Browser.
library;

import 'package:flutter/material.dart';

abstract final class Bibliotheksfarben {
  static const favoriten = Color(0xFFE5484D);
  static const personen = Color(0xFF8E4EC6);
  static const karte = Color(0xFF30A46C);
  static const orte = Color(0xFF00A2C7);
  static const reisen = Color(0xFFF76B15);
  static const stammbaum = Color(0xFFA18072);
  static const statistik = Color(0xFF0090FF);
  static const duplikate = Color(0xFF3E63DD);
  static const papierkorb = Color(0xFF8B8D98);
  static const einstellungen = Color(0xFF12A594);

  // Was es nur am Rechner als eigenen Bereich gibt.
  static const rueckblick = Color(0xFFD6409F);
  static const kalender = Color(0xFF6E56CF);
  static const werkzeuge = Color(0xFF978365);
}

abstract final class Bibliothekssymbole {
  static const fotos = Icons.photo_library_outlined;
  static const fotosGewaehlt = Icons.photo_library;
  static const suche = Icons.search;
  static const alben = Icons.photo_album_outlined;
  static const albenGewaehlt = Icons.photo_album;
  static const bibliothek = Icons.grid_view_outlined;
  static const bibliothekGewaehlt = Icons.grid_view_rounded;

  static const favoriten = Icons.favorite_border_rounded;
  static const personen = Icons.people_outline_rounded;
  static const karte = Icons.place_outlined;
  static const orte = Icons.public_rounded;
  static const reisen = Icons.luggage_outlined;
  static const stammbaum = Icons.account_tree_outlined;
  static const statistik = Icons.bar_chart_rounded;
  static const duplikate = Icons.filter_none_rounded;
  static const papierkorb = Icons.delete_outline_rounded;
  static const einstellungen = Icons.tune_rounded;

  static const rueckblick = Icons.history_rounded;
  static const kalender = Icons.calendar_month_outlined;
  static const werkzeuge = Icons.build_outlined;
}

/// Das Symbol eines Eintrags auf einem Feld seiner Farbe – wie
/// `.farbsymbol` im Browser.
class Farbsymbol extends StatelessWidget {
  const Farbsymbol({
    super.key,
    required this.icon,
    required this.farbe,
    this.groesse = 40,
  });

  final IconData icon;
  final Color farbe;
  final double groesse;

  @override
  Widget build(BuildContext context) {
    final dunkel = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: groesse,
      height: groesse,
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: dunkel ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(groesse * 0.3),
      ),
      child: Icon(icon, color: farbe, size: groesse * 0.55),
    );
  }
}
