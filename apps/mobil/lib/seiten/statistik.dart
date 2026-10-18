import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/library_stats.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'angaben.dart' show groesseText;

/// Die Statistik der Bibliothek – dieselben Kennzahlen und Diagramme wie im
/// Browser (web/app.js, zeigeStatistik) und auf dem Rechner, aus derselben
/// Rechnung im Kern (`loadLibraryStats`).
class Statistik extends StatelessWidget {
  const Statistik({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  Widget build(BuildContext context) => FutureBuilder<LibraryStats>(
    future: sitzung.db.loadLibraryStats(),
    builder: (context, snap) {
      final s = snap.data;
      if (s == null) return const Center(child: CircularProgressIndicator());
      final t = AppTexte.of(context);
      final sprache = Localizations.localeOf(context).toLanguageTag();
      final zahl = NumberFormat.decimalPattern(sprache);
      final titel = Theme.of(context).textTheme.titleSmall;
      final jahre = s.countsByYear.keys.toList()..sort();
      final monat = DateFormat.MMM(sprache);
      final maxKamera = s.topCameras.fold(
        0,
        (m, k) => k.count > m ? k.count : m,
      );
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (s.totalCount == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(t.statLeer),
            ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 2.3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _Kennzahl(zahl.format(s.totalCount), t.statInsgesamt),
              _Kennzahl(zahl.format(s.imageCount), t.statFotos),
              _Kennzahl(zahl.format(s.videoCount), t.statVideos),
              _Kennzahl(zahl.format(s.favoriteCount), t.statFavoriten),
              _Kennzahl(groesseText(s.totalSizeBytes), t.statSpeicher),
              _Kennzahl(zahl.format(s.trashedCount), t.statPapierkorb),
              _Kennzahl(zahl.format(s.lockedCount), t.statGesperrt),
            ],
          ),
          if (s.totalCount > 0) ...[
            const SizedBox(height: 20),
            Text(t.statProJahr, style: titel),
            const SizedBox(height: 8),
            // Jahre lückenlos vom ersten bis zum letzten, damit leere Jahre
            // sichtbar bleiben – wie im Browser.
            Balken(
              werte: [
                for (var j = jahre.first; j <= jahre.last; j++)
                  ('$j', s.countsByYear[j] ?? 0),
              ],
              zahl: zahl,
            ),
            const SizedBox(height: 20),
            Text(t.statProMonat, style: titel),
            const SizedBox(height: 8),
            Balken(
              werte: [
                for (var m = 1; m <= 12; m++)
                  (monat.format(DateTime(2000, m)), s.countsByMonth[m] ?? 0),
              ],
              zahl: zahl,
            ),
            if (s.topCameras.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(t.statKameras, style: titel),
              const SizedBox(height: 8),
              for (final k in s.topCameras)
                _Kamerazeile(
                  name: k.label,
                  anzahl: k.count,
                  anteil: maxKamera == 0 ? 0 : k.count / maxKamera,
                  zahl: zahl,
                ),
            ],
          ],
        ],
      );
    },
  );
}

class _Kennzahl extends StatelessWidget {
  const _Kennzahl(this.wert, this.name);

  final String wert;
  final String name;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: farben.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              wert,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: farben.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Säulendiagramm wie im Browser: oben die Zahl, die Säule, darunter
/// die Achse. Passen die Säulen nicht nebeneinander, rollt es zur Seite.
class Balken extends StatelessWidget {
  const Balken({super.key, required this.werte, required this.zahl});

  final List<(String, int)> werte;
  final NumberFormat zahl;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final hoechster = werte.fold(0, (m, w) => w.$2 > m ? w.$2 : m);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: farben.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        height: 190,
        child: LayoutBuilder(
          builder: (context, c) {
            const mindestens = 28.0;
            final breite = c.maxWidth - 24;
            final eng = werte.length * mindestens > breite;
            final spalte = eng ? mindestens : breite / werte.length;
            final saeulen = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (achse, wert) in werte)
                  SizedBox(
                    width: spalte,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        children: [
                          Text(
                            wert == 0 ? '' : zahl.format(wert),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 9,
                              color: farben.onSurfaceVariant,
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: hoechster == 0
                                    ? 0
                                    : wert / hoechster,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 40,
                                  ),
                                  decoration: BoxDecoration(
                                    color: farben.primary,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            achse,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 10,
                              color: farben.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: eng
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: saeulen,
                    )
                  : saeulen,
            );
          },
        ),
      ),
    );
  }
}

class _Kamerazeile extends StatelessWidget {
  const _Kamerazeile({
    required this.name,
    required this.anzahl,
    required this.anteil,
    required this.zahl,
  });

  final String name;
  final int anzahl;
  final double anteil;
  final NumberFormat zahl;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: anteil,
                minHeight: 14,
                backgroundColor: farben.primary.withValues(alpha: 0.15),
                color: farben.primary,
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              zahl.format(anzahl),
              textAlign: TextAlign.end,
              style: TextStyle(color: farben.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
