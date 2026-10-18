import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'gesichter.dart';
import 'raster.dart';

/// Die benannten Personen, jede mit ihrem Gesicht.
class Personen extends StatelessWidget {
  const Personen({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<PersonData>>(
    stream: sitzung.db.watchPeople(),
    builder: (context, snap) {
      final alle = snap.data;
      if (alle == null) return const Center(child: CircularProgressIndicator());
      final personen = [
        for (final p in alle)
          if (p.name.trim().isNotEmpty) p,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      // Oben die Gesichter ohne Namen (wie im Browser), darunter alle
      // benannten.
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: OhneNamenAbschnitt(sitzung: sitzung)),
          if (personen.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(AppTexte.of(context).personenLeer)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: _personenGitter(personen),
            ),
        ],
      );
    },
  );

  Widget _personenGitter(List<PersonData> personen) => SliverGrid.builder(
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 120,
      mainAxisSpacing: 16,
      crossAxisSpacing: 12,
      childAspectRatio: 0.78,
    ),
    itemCount: personen.length,
    itemBuilder: (context, i) {
      final p = personen[i];
      return InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PersonSeite(sitzung: sitzung, person: p),
          ),
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
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
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    },
  );
}

/// Die Aufnahmen einer Person.
class PersonSeite extends StatelessWidget {
  const PersonSeite({super.key, required this.sitzung, required this.person});

  final Sitzung sitzung;
  final PersonData person;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(person.name),
      actions: [
        IconButton(
          tooltip: AppTexte.of(context).personZusammenfuehren,
          icon: const Icon(Icons.merge_type_rounded),
          onPressed: () async {
            if (await zusammenfuehren(context, sitzung, person) &&
                context.mounted) {
              // Neu laden: Die Fotos der anderen gehören jetzt dazu.
              await Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => PersonSeite(sitzung: sitzung, person: person),
                ),
              );
            }
          },
        ),
      ],
    ),
    body: FutureBuilder<List<AssetData>>(
      future: sitzung.db.assetsFuerPersonen([person.id]),
      builder: (context, snap) {
        final a = snap.data;
        if (a == null) return const Center(child: CircularProgressIndicator());
        final zeilen = [
          for (final x in a)
            if (!x.isLocked && !x.isTrashed) Rasterzeile.aus(x),
        ]..sort((x, y) => y.fileCreatedAt.compareTo(x.fileCreatedAt));
        return AufnahmenRaster(
          sitzung: sitzung,
          zeilen: zeilen,
          nachTagen: true,
        );
      },
    ),
  );
}
