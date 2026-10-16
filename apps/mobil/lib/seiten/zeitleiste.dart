import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';

import '../l10n/app_localizations.dart';
import '../lokal/ungesichert.dart';
import '../sitzung.dart';
import 'erinnerungen.dart';
import 'raster.dart';

/// Alle Aufnahmen, neueste zuerst, nach Tagen – die vom Server und
/// dazwischen die, die nur auf dem Telefon liegen (Issue #127).
class Zeitleiste extends StatelessWidget {
  const Zeitleiste({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Rasterzeile>>(
    stream: sitzung.db.watchRasterzeilen(),
    builder: (context, snap) {
      final server = snap.data;
      if (server == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final d = sitzung.sicherung;
      return ListenableBuilder(
        listenable: Listenable.merge([?d]),
        builder: (context, _) {
          final t = AppTexte.of(context);
          final lokal = d?.ungesichert ?? const <LokaleAufnahme>[];
          final gemischt = mischeMitServer(server, lokal);
          final zeilen = gemischt.zeilen;
          return RefreshIndicator(
            onRefresh: () async {
              await sitzung.gleicheAb();
              await d?.zaehleUngesicherte();
            },
            child: zeilen.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          t.zeitleisteLeer,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : AufnahmenRaster(
                    sitzung: sitzung,
                    zeilen: zeilen,
                    lokal: gemischt.lokal,
                    nachTagen: true,
                    kopf: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (lokal.isNotEmpty && d != null)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.cloud_off_outlined),
                            title: Text(t.lokalAnzahl(lokal.length)),
                            trailing: TextButton(
                              onPressed: d.laeuft ? null : d.sichere,
                              child: Text(t.lokalJetztSichern),
                            ),
                          ),
                        Erinnerungsstreifen(
                          sitzung: sitzung,
                          stand: server.length,
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
