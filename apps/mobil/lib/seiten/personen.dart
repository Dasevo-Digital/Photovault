import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
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
      if (personen.isEmpty) {
        return Center(child: Text(AppTexte.of(context).personenLeer));
      }
      return GridView.builder(
        padding: const EdgeInsets.all(12),
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
                  child: ClipOval(
                    child: Miniatur(
                      paths: sitzung.paths,
                      relativ: p.coverFaceCropPath,
                    ),
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
    appBar: AppBar(title: Text(person.name)),
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
