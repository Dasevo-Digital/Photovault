import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'duplikate.dart';
import 'einstellungen.dart';
import 'karte.dart';
import 'personen.dart';
import 'raster.dart';
import 'reisen.dart';
import 'stammbaum.dart';
import 'statistik.dart';

/// Was nicht in die Zeitleiste gehört, gesammelt wie in Immich: oben
/// Favoriten, Papierkorb, Orte, Personen und Reisen (samt Aktivitäten) als
/// Knöpfe, darunter die Personen mit ihren Gesichtern.
class Bibliothek extends StatelessWidget {
  const Bibliothek({super.key, required this.sitzung});

  final Sitzung sitzung;

  void _oeffne(BuildContext context, String titel, Widget inhalt) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(titel)),
            body: inhalt,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 3.2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            _Knopf(
              icon: Icons.favorite_border,
              text: t.bibFavoriten,
              onTap: () =>
                  _oeffne(context, t.bibFavoriten, Favoriten(sitzung: sitzung)),
            ),
            _Knopf(
              icon: Icons.delete_outline,
              text: t.bibPapierkorb,
              onTap: () => _oeffne(
                context,
                t.bibPapierkorb,
                Papierkorb(sitzung: sitzung),
              ),
            ),
            _Knopf(
              icon: Icons.map_outlined,
              text: t.navKarte,
              onTap: () =>
                  _oeffne(context, t.navKarte, Karte(sitzung: sitzung)),
            ),
            _Knopf(
              icon: Icons.people_outline,
              text: t.navPersonen,
              onTap: () =>
                  _oeffne(context, t.navPersonen, Personen(sitzung: sitzung)),
            ),
            _Knopf(
              icon: Icons.luggage_outlined,
              text: t.bibReisen,
              onTap: () =>
                  _oeffne(context, t.bibReisen, ReisenSeite(sitzung: sitzung)),
            ),
            _Knopf(
              icon: Icons.bar_chart,
              text: t.bibStatistik,
              onTap: () =>
                  _oeffne(context, t.bibStatistik, Statistik(sitzung: sitzung)),
            ),
            _Knopf(
              icon: Icons.copy_all_outlined,
              text: t.bibDuplikate,
              onTap: () =>
                  _oeffne(context, t.bibDuplikate, Duplikate(sitzung: sitzung)),
            ),
            _Knopf(
              icon: Icons.account_tree_outlined,
              text: t.bibStammbaum,
              onTap: () => Navigator.of(context).push(stammbaumWeg(sitzung)),
            ),
            _Knopf(
              icon: Icons.tune,
              text: t.bibEinstellungen,
              onTap: () => _oeffne(
                context,
                t.bibEinstellungen,
                Einstellungen(sitzung: sitzung),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                t.navPersonen,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () =>
                  _oeffne(context, t.navPersonen, Personen(sitzung: sitzung)),
              child: Text(t.bibAlle),
            ),
          ],
        ),
        SizedBox(
          height: 112,
          child: StreamBuilder<List<PersonData>>(
            stream: sitzung.db.watchPeople(),
            builder: (context, snap) {
              final personen =
                  [
                    for (final p in snap.data ?? const <PersonData>[])
                      if (p.name.trim().isNotEmpty) p,
                  ]..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );
              if (personen.isEmpty) {
                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    t.personenLeer,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: personen.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final p = personen[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(40),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PersonSeite(sitzung: sitzung, person: p),
                      ),
                    ),
                    child: SizedBox(
                      width: 76,
                      child: Column(
                        children: [
                          SizedBox.square(
                            dimension: 76,
                            child: Personenbild(
                              paths: sitzung.paths,
                              name: p.name,
                              relativ: p.coverFaceCropPath,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Knopf extends StatelessWidget {
  const _Knopf({required this.icon, required this.text, required this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Material(
      color: farben.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, color: farben.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alle Favoriten, nach Tagen.
class Favoriten extends StatelessWidget {
  const Favoriten({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Rasterzeile>>(
    stream: sitzung.db.watchRasterzeilen(favoritesOnly: true),
    builder: (context, snap) {
      final zeilen = snap.data;
      if (zeilen == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (zeilen.isEmpty) {
        return Center(child: Text(AppTexte.of(context).bibFavoritenLeer));
      }
      return AufnahmenRaster(sitzung: sitzung, zeilen: zeilen, nachTagen: true);
    },
  );
}

/// Was im Papierkorb liegt – zurückholen geht hier, endgültig löschen am
/// Rechner.
class Papierkorb extends StatelessWidget {
  const Papierkorb({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AssetData>>(
    stream: sitzung.db.watchTrash(),
    builder: (context, snap) {
      final t = AppTexte.of(context);
      final daten = snap.data;
      if (daten == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (daten.isEmpty) return Center(child: Text(t.bibPapierkorbLeer));
      return AufnahmenRaster(
        sitzung: sitzung,
        zeilen: [for (final a in daten) Rasterzeile.aus(a)],
        papierkorb: true,
        kopf: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            t.bibPapierkorbHinweis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    },
  );
}
