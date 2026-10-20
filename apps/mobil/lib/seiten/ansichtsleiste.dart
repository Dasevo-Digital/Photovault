import 'package:flutter/material.dart';
import 'package:kern/services/rasterstufen.dart';
import 'package:kern/services/sortierung.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Die Leiste über der Zeitleiste (Issue #194) – wie am Rechner und im
/// Browser: die Reihenfolge, nach Tagen oder nur nach Monaten gegliedert,
/// quadratische Kacheln oder bündige Reihen und grösser oder kleiner.
/// Die Wahl gilt für dieses Gerät.
class Ansichtsleiste extends StatelessWidget {
  const Ansichtsleiste({super.key, required this.sitzung});

  final Sitzung sitzung;

  static String sortierungText(AppTexte t, Rastersortierung s) => switch (s) {
    Rastersortierung.aufnahmeNeu => t.sortAufnahmeNeu,
    Rastersortierung.aufnahmeAlt => t.sortAufnahmeAlt,
    Rastersortierung.importNeu => t.sortImportNeu,
    Rastersortierung.name => t.sortName,
    Rastersortierung.bewertung => t.sortBewertung,
    Rastersortierung.groesse => t.sortGroesse,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sitzung,
    builder: (context, _) {
      final t = AppTexte.of(context);
      final s = sitzung;
      final reihen = s.form == Zeitleistenform.reihen;
      final spalten = s.rasterspalten;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Rastersortierung>(
                  isExpanded: true,
                  isDense: true,
                  value: s.sortierung,
                  hint: Text(t.ansichtReihenfolge),
                  items: [
                    for (final x in Rastersortierung.values)
                      DropdownMenuItem(
                        value: x,
                        child: Text(
                          sortierungText(t, x),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (x) => s.setzeAnsicht(sortierung: x),
                ),
              ),
            ),
            // Monate und Tage gibt es nur nach dem Aufnahmedatum.
            if (nachAufnahmedatum(s.sortierung))
              IconButton(
                tooltip: s.nurMonate ? t.ansichtNachTagen : t.ansichtNurMonate,
                isSelected: !s.nurMonate,
                icon: const Icon(Icons.calendar_view_day_outlined),
                selectedIcon: const Icon(Icons.calendar_view_day),
                onPressed: () => s.setzeAnsicht(nurMonate: !s.nurMonate),
              ),
            IconButton(
              tooltip: reihen ? t.ansichtQuadrate : t.ansichtReihen,
              icon: Icon(
                reihen ? Icons.grid_view_outlined : Icons.view_stream_outlined,
              ),
              onPressed: () => s.setzeAnsicht(
                form: reihen
                    ? Zeitleistenform.quadrate
                    : Zeitleistenform.reihen,
              ),
            ),
            // Kleiner heisst mehr Fotos nebeneinander.
            IconButton(
              tooltip: t.ansichtKleiner,
              icon: const Icon(Icons.zoom_out),
              onPressed: spalten >= 6
                  ? null
                  : () => s.setzeRasterspalten(spalten + 1),
            ),
            IconButton(
              tooltip: t.ansichtGroesser,
              icon: const Icon(Icons.zoom_in),
              onPressed: spalten <= 2
                  ? null
                  : () => s.setzeRasterspalten(spalten - 1),
            ),
          ],
        ),
      );
    },
  );
}
