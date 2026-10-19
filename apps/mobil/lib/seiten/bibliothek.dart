import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'duplikate.dart';
import 'einstellungen.dart';
import 'karte.dart';
import 'orte.dart';
import 'personen.dart';
import 'raster.dart';
import 'reisen.dart';
import 'stammbaum.dart';
import 'statistik.dart';

/// Die Farben der Einträge – dieselben wie im Browser
/// (packages/server/web/app.js, BIBLIOTHEK), damit beide gleich aussehen.
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
}

typedef _Eintrag = ({
  IconData icon,
  String text,
  Color farbe,
  VoidCallback onTap,
});

/// Was nicht in die Zeitleiste gehört – wie im Browser gegliedert: oben die
/// Personen mit ihren Gesichtern, darunter „Entdecken“ als Kacheln und
/// „Verwalten“ als Liste, jeder Eintrag mit eigener Farbe.
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
    final List<_Eintrag> entdecken = [
      (
        icon: Icons.favorite_border_rounded,
        text: t.bibFavoriten,
        farbe: Bibliotheksfarben.favoriten,
        onTap: () =>
            _oeffne(context, t.bibFavoriten, Favoriten(sitzung: sitzung)),
      ),
      (
        icon: Icons.people_outline_rounded,
        text: t.navPersonen,
        farbe: Bibliotheksfarben.personen,
        onTap: () =>
            _oeffne(context, t.navPersonen, Personen(sitzung: sitzung)),
      ),
      (
        icon: Icons.place_outlined,
        text: t.navKarte,
        farbe: Bibliotheksfarben.karte,
        onTap: () => _oeffne(context, t.navKarte, Karte(sitzung: sitzung)),
      ),
      (
        icon: Icons.public_rounded,
        text: t.bibOrte,
        farbe: Bibliotheksfarben.orte,
        onTap: () => _oeffne(context, t.bibOrte, Orte(sitzung: sitzung)),
      ),
      (
        icon: Icons.luggage_outlined,
        text: t.bibReisen,
        farbe: Bibliotheksfarben.reisen,
        onTap: () =>
            _oeffne(context, t.bibReisen, ReisenSeite(sitzung: sitzung)),
      ),
      (
        icon: Icons.account_tree_outlined,
        text: t.bibStammbaum,
        farbe: Bibliotheksfarben.stammbaum,
        onTap: () => Navigator.of(context).push(stammbaumWeg(sitzung)),
      ),
      (
        icon: Icons.bar_chart_rounded,
        text: t.bibStatistik,
        farbe: Bibliotheksfarben.statistik,
        onTap: () =>
            _oeffne(context, t.bibStatistik, Statistik(sitzung: sitzung)),
      ),
    ];
    final List<_Eintrag> verwalten = [
      (
        icon: Icons.filter_none_rounded,
        text: t.bibDuplikate,
        farbe: Bibliotheksfarben.duplikate,
        onTap: () =>
            _oeffne(context, t.bibDuplikate, Duplikate(sitzung: sitzung)),
      ),
      (
        icon: Icons.delete_outline_rounded,
        text: t.bibPapierkorb,
        farbe: Bibliotheksfarben.papierkorb,
        onTap: () =>
            _oeffne(context, t.bibPapierkorb, Papierkorb(sitzung: sitzung)),
      ),
      (
        icon: Icons.tune_rounded,
        text: t.bibEinstellungen,
        farbe: Bibliotheksfarben.einstellungen,
        onTap: () => _oeffne(
          context,
          t.bibEinstellungen,
          Einstellungen(sitzung: sitzung),
        ),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _Abschnittskopf(
          t.navPersonen,
          aktion: TextButton(
            onPressed: () =>
                _oeffne(context, t.navPersonen, Personen(sitzung: sitzung)),
            child: Text(t.bibAlle),
          ),
        ),
        SizedBox(height: 112, child: _Personenstreifen(sitzung: sitzung)),
        const SizedBox(height: 20),
        _Abschnittskopf(t.bibEntdecken),
        LayoutBuilder(
          builder: (context, c) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              // Wie im Browser: Kacheln ab 160 Punkt Breite.
              crossAxisCount: (c.maxWidth / 170).floor().clamp(2, 4),
              mainAxisExtent: 70,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: entdecken.length,
            itemBuilder: (context, i) => _Kachel(entdecken[i]),
          ),
        ),
        const SizedBox(height: 20),
        _Abschnittskopf(t.bibVerwalten),
        _Liste(verwalten),
      ],
    );
  }
}

class _Abschnittskopf extends StatelessWidget {
  const _Abschnittskopf(this.titel, {this.aktion});

  final String titel;
  final Widget? aktion;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            titel,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        ?aktion,
      ],
    ),
  );
}

/// Das Symbol eines Eintrags auf einem Feld seiner Farbe.
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

/// Ein Eintrag aus „Entdecken“: Kachel mit Rand, Symbol und Name.
class _Kachel extends StatelessWidget {
  const _Kachel(this.eintrag);

  final _Eintrag eintrag;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final form = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: farben.outlineVariant),
    );
    return Material(
      color: farben.surfaceContainerLow,
      shape: form,
      child: InkWell(
        customBorder: form,
        onTap: eintrag.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Farbsymbol(icon: eintrag.icon, farbe: eintrag.farbe),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  eintrag.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Die Einträge aus „Verwalten“ als zusammenhängende Liste.
class _Liste extends StatelessWidget {
  const _Liste(this.eintraege);

  final List<_Eintrag> eintraege;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Material(
      color: farben.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: farben.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < eintraege.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: farben.outlineVariant),
            InkWell(
              onTap: eintraege[i].onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Farbsymbol(
                      icon: eintraege[i].icon,
                      farbe: eintraege[i].farbe,
                      groesse: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        eintraege[i].text,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: farben.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Die benannten Personen mit ihren Gesichtern, zum Seitwärtsrollen.
class _Personenstreifen extends StatelessWidget {
  const _Personenstreifen({required this.sitzung});

  final Sitzung sitzung;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return StreamBuilder<List<PersonData>>(
      stream: sitzung.db.watchPeople(),
      builder: (context, snap) {
        final personen = [
          for (final p in snap.data ?? const <PersonData>[])
            if (p.name.trim().isNotEmpty) p,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
                  builder: (_) => PersonSeite(sitzung: sitzung, person: p),
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
