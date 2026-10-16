import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'erinnerungen.dart';
import 'raster.dart';

/// Alle Aufnahmen, neueste zuerst, nach Tagen.
class Zeitleiste extends StatelessWidget {
  const Zeitleiste({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Rasterzeile>>(
    stream: sitzung.db.watchRasterzeilen(),
    builder: (context, snap) {
      final zeilen = snap.data;
      if (zeilen == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return RefreshIndicator(
        onRefresh: sitzung.gleicheAb,
        child: zeilen.isEmpty
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      AppTexte.of(context).zeitleisteLeer,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : AufnahmenRaster(
                sitzung: sitzung,
                zeilen: zeilen,
                nachTagen: true,
                kopf: Erinnerungsstreifen(
                  sitzung: sitzung,
                  stand: zeilen.length,
                ),
              ),
      );
    },
  );
}
