import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/sortierung.dart';

import '../l10n/app_localizations.dart';
import '../lokal/ungesichert.dart';
import '../sitzung.dart';
import 'ansichtsleiste.dart';
import 'erinnerungen.dart';
import 'raster.dart';

/// Alle Aufnahmen, neueste zuerst, nach Tagen – die vom Server und
/// dazwischen die, die nur auf dem Telefon liegen (Issue #127). Darüber
/// die Ansichtsleiste (Issue #194): andere Reihenfolgen, Form, Grösse.
class Zeitleiste extends StatefulWidget {
  const Zeitleiste({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<Zeitleiste> createState() => _ZeitleisteState();
}

class _ZeitleisteState extends State<Zeitleiste> {
  Sitzung get sitzung => widget.sitzung;

  // Der Strom bleibt, bis sich die Reihenfolge ändert – nicht bei jedem
  // Aufbau ein neues Abo.
  late var _sortierung = sitzung.sortierung;
  late var _strom = _neuerStrom();

  Stream<List<Rasterzeile>> _neuerStrom() =>
      sitzung.db.watchRasterzeilen(sortierung: _sortierung);

  void _sitzungGeaendert() {
    if (sitzung.sortierung == _sortierung) return;
    setState(() {
      _sortierung = sitzung.sortierung;
      _strom = _neuerStrom();
    });
  }

  @override
  void initState() {
    super.initState();
    sitzung.addListener(_sitzungGeaendert);
  }

  @override
  void dispose() {
    sitzung.removeListener(_sitzungGeaendert);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Rasterzeile>>(
    stream: _strom,
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
          // Was nur auf dem Telefon liegt, steht nach seinem Datum
          // dazwischen – das geht nur in der gewohnten Reihenfolge.
          final mischen = _sortierung == rastersortierungVorgabe;
          final lokal = mischen
              ? d?.ungesichert ?? const <LokaleAufnahme>[]
              : const <LokaleAufnahme>[];
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
                    nachTagen: nachAufnahmedatum(_sortierung),
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
                        Ansichtsleiste(sitzung: sitzung),
                      ],
                    ),
                  ),
          );
        },
      );
    },
  );
}
