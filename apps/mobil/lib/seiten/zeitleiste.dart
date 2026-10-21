import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/listenangaben.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/listengliederung.dart';
import 'package:kern/services/sortierung.dart';

import '../l10n/app_localizations.dart';
import '../lokal/ungesichert.dart';
import '../sicherung/dienst.dart';
import '../sitzung.dart';
import 'ansichtsleiste.dart';
import 'erinnerungen.dart';
import 'raster.dart';
import 'sicherung.dart';

/// Alle Aufnahmen, neueste zuerst, nach Tagen – die vom Server und
/// dazwischen die, die nur auf dem Telefon liegen (Issue #127). Darüber
/// die Ansichtsleiste (Issue #194): andere Reihenfolgen, Form, Grösse.
class Zeitleiste extends StatefulWidget {
  const Zeitleiste({super.key, required this.sitzung, this.nachOben});

  final Sitzung sitzung;

  /// Zählt hoch, wenn die Zeitleiste zu den neuesten zurück soll.
  final Listenable? nachOben;

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

  // Die Liste (Issue #195): Ansicht, Gliederung und Spalten, wie zuletzt
  // gebaut – ein Neubau nur, wenn sich eins davon ändert.
  late var _alsListe = sitzung.alsListe;
  late var _gliederung = sitzung.gliederung;
  late var _spalten = sitzung.listenspalten.alsText();

  // Die Angaben, die die Liste über die Rasterzeile hinaus zeigt – für
  // genau die Liste, für die sie geholt wurden.
  Map<String, Listenangaben> _angaben = const {};
  List<Rasterzeile>? _angabenFuer;
  List<Rasterzeile>? _angabenHolt;

  void _sitzungGeaendert() {
    final s = sitzung;
    final spalten = s.listenspalten.alsText();
    final sortierung = s.sortierung != _sortierung;
    if (!sortierung &&
        s.alsListe == _alsListe &&
        s.gliederung == _gliederung &&
        spalten == _spalten) {
      return;
    }
    setState(() {
      _alsListe = s.alsListe;
      _gliederung = s.gliederung;
      _spalten = spalten;
      if (sortierung) {
        _sortierung = s.sortierung;
        _strom = _neuerStrom();
      }
    });
  }

  void _holeAngaben(List<Rasterzeile> zeilen) {
    if (identical(zeilen, _angabenFuer) || identical(zeilen, _angabenHolt)) {
      return;
    }
    _angabenHolt = zeilen;
    sitzung.db.listenangaben([for (final z in zeilen) z.id]).then((a) {
      if (!mounted || !identical(_angabenHolt, zeilen)) return;
      setState(() {
        _angaben = a;
        _angabenFuer = zeilen;
      });
    });
  }

  /// Nach Kamera: die Gruppen alphabetisch, ohne Angabe am Ende, darin die
  /// Reihenfolge wie geholt – dieselbe Regel wie am Rechner.
  List<Rasterzeile> _nachKamera(List<Rasterzeile> zeilen) {
    final gruppen = <String, List<Rasterzeile>>{};
    for (final z in zeilen) {
      final k =
          kamerabezeichnungAus(z.cameraMake, _angaben[z.id]?.kameramodell) ??
          '';
      gruppen.putIfAbsent(k, () => []).add(z);
    }
    final schluessel = gruppen.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return [for (final k in schluessel) ...gruppen[k]!];
  }

  List<Rasterzeile>? _kameraVon;
  Map<String, Listenangaben>? _kameraMit;
  List<Rasterzeile> _kameraListe = const [];

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
          var zeilen = gemischt.zeilen;
          final nachDatum = nachAufnahmedatum(_sortierung);
          final gliederung = nachDatum ? _gliederung : ListenGruppierung.keine;
          if (_alsListe) {
            _holeAngaben(server);
            if (gliederung == ListenGruppierung.kamera) {
              if (!identical(_kameraVon, zeilen) ||
                  !identical(_kameraMit, _angaben)) {
                _kameraListe = _nachKamera(zeilen);
                _kameraVon = zeilen;
                _kameraMit = _angaben;
              }
              zeilen = _kameraListe;
            }
          }
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
                    nachTagen: nachDatum,
                    nachOben: widget.nachOben,
                    liste: _alsListe
                        ? Listenansicht(
                            angaben: _angaben,
                            gliederung: gliederung,
                            spalten: sitzung.listenspalten,
                          )
                        : null,
                    kopf: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (lokal.isNotEmpty && d != null)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.cloud_off_outlined),
                            title: Text(t.lokalAnzahl(lokal.length)),
                            // Was gerade geschieht oder worauf es wartet –
                            // sonst sah ein Tipp auf „Jetzt sichern“ aus,
                            // als täte er nichts (#204).
                            subtitle: switch ((d.laeuft, d.wartet)) {
                              (true, _) => Text(
                                switch (d.fortschritt?.datei) {
                                  final f? => t.sicherungLaedt(f),
                                  null => t.sicherungLaeuft,
                                },
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              (_, Wartegrund.wlan) => Text(
                                t.sicherungWartetWlan,
                              ),
                              (_, Wartegrund.netz) => Text(
                                t.sicherungWartetNetz,
                              ),
                              (_, Wartegrund.hintergrund) => Text(
                                t.sicherungImHintergrund,
                              ),
                              _ => null,
                            },
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    Sicherungsseite(dienst: d, db: sitzung.db),
                              ),
                            ),
                            trailing: TextButton(
                              onPressed: d.laeuft
                                  ? null
                                  : () => jetztSichern(
                                      context,
                                      d,
                                      db: sitzung.db,
                                    ),
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
