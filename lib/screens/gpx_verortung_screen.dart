import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/gpx.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../services/meldungsdienst.dart';

/// Fotos aus einer GPX-Spur verorten.
///
/// Der zweite – und größere – Nutzen des GPX-Einlesens: An der echten
/// Bibliothek tragen nur 1092 von 7988 Aufnahmen eine Koordinate. Alles
/// andere ist für Karte, Globus, Reiseerkennung und Länderzähler
/// unsichtbar. Eine Aufzeichnung vom Handy oder vom Wanderlogger holt
/// einen Teil davon zurück.
class GpxVerortungScreen extends StatefulWidget {
  final LibraryState library;
  const GpxVerortungScreen({super.key, required this.library});

  @override
  State<GpxVerortungScreen> createState() => _GpxVerortungScreenState();
}

class _GpxVerortungScreenState extends State<GpxVerortungScreen> {
  List<Spurpunkt>? _spur;

  /// Aufnahmen ohne Koordinate – die einzigen, um die es hier geht.
  List<({String id, DateTime zeit})> _kandidaten = const [];

  Duration _versatz = Duration.zero;
  String? _fehler;
  bool _arbeitet = false;

  int get _treffer => _spur == null
      ? 0
      : verorteAusSpur(_spur!, _kandidaten, versatz: _versatz).length;

  Future<void> _waehlen() async {
    final t = AppTexte.of(context);
    final wahl = await FilePicker.platform.pickFiles(
      dialogTitle: t.gpxDateiWaehlen,
      type: FileType.custom,
      allowedExtensions: const ['gpx'],
    );
    if (wahl == null || wahl.files.isEmpty || !mounted) return;
    final pfad = wahl.files.first.path;
    if (pfad == null) return;

    setState(() {
      _arbeitet = true;
      _fehler = null;
    });
    List<Spurpunkt> spur;
    try {
      spur = liesGpx(await File(pfad).readAsString());
    } on GpxFehler catch (f) {
      if (!mounted) return;
      setState(() {
        _arbeitet = false;
        _spur = null;
        _fehler = switch (f.grund) {
          GpxAbbruch.keinGpx => t.gpxFehlerKeinGpx,
          GpxAbbruch.ohneZeit => t.gpxFehlerOhneZeit,
          GpxAbbruch.leer => t.gpxFehlerLeer,
        };
      });
      return;
    }

    // Nur Aufnahmen im Umfeld der Spur: Ein Tag Luft an beiden Enden
    // deckt jeden Zeitversatz ab, den es geben kann (±14 Stunden), ohne
    // die ganze Bibliothek durchzurechnen.
    final alle = await widget.library.db.aufnahmenOhneKoordinate();
    final von = spur.first.zeit.subtract(const Duration(days: 1));
    final bis = spur.last.zeit.add(const Duration(days: 1));
    final kandidaten = [
      for (final a in alle)
        if (!a.zeit.toUtc().isBefore(von) && !a.zeit.toUtc().isAfter(bis)) a,
    ];
    if (!mounted) return;
    setState(() {
      _spur = spur;
      _kandidaten = kandidaten;
      _versatz = besterVersatz(spur, [for (final a in kandidaten) a.zeit]);
      _arbeitet = false;
    });
  }

  Future<void> _verorten() async {
    final spur = _spur;
    if (spur == null) return;
    final t = AppTexte.of(context);
    final geo = widget.library.geocoder;
    final verortungen = verorteAusSpur(spur, _kandidaten, versatz: _versatz);
    setState(() => _arbeitet = true);

    await widget.library.db.setzeOrte([
      for (final v in verortungen)
        // Einmal nachschlagen und nicht dreimal: Die Suche geht über
        // hunderttausend Städte, und drei gleiche Anfragen je Foto wären
        // bei tausend Fotos dreitausend Durchgänge zu viel.
        if (geo?.lookup(v.breite, v.laenge) case final ort?)
          (
            assetId: v.assetId,
            breite: v.breite,
            laenge: v.laenge,
            // Die Namen gleich mit – sonst stünden hinterher Punkte auf
            // der Karte, aber keine Länder im Reisezähler.
            land: ort.country,
            region: ort.state,
            ort: ort.city,
          )
        else
          (
            assetId: v.assetId,
            breite: v.breite,
            laenge: v.laenge,
            land: null,
            region: null,
            ort: null,
          ),
    ]);
    if (!mounted) return;
    setState(() {
      _arbeitet = false;
      // Die verorteten Aufnahmen sind keine Kandidaten mehr – sonst
      // stünde nach dem Verorten dieselbe Zahl noch einmal da.
      final erledigt = {for (final v in verortungen) v.assetId};
      _kandidaten = [
        for (final a in _kandidaten)
          if (!erledigt.contains(a.id)) a,
      ];
    });
    melde.erfolg(t.gpxFertig(verortungen.length));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final datum =
        DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_Hm();
    final spur = _spur;

    return Scaffold(
      appBar: AppBar(title: Text(t.gpxTitel)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(t.gpxErklaerung),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.tonalIcon(
            onPressed: _arbeitet ? null : _waehlen,
            icon: const Icon(Icons.route_outlined),
            label: Text(t.gpxDateiWaehlen),
          ),
          if (_fehler != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(_fehler!, style: TextStyle(color: farben.error)),
          ],
          if (spur != null) ...[
            const SizedBox(height: AppSpacing.xl),
            Text(
              t.gpxSpur(spur.length, datum.format(spur.first.zeit.toLocal()),
                  datum.format(spur.last.zeit.toLocal())),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(t.gpxVersatz,
                style: Theme.of(context).textTheme.titleSmall),
            Row(
              children: [
                IconButton(
                  tooltip: '−30',
                  icon: const Icon(Icons.remove),
                  onPressed: () => setState(
                      () => _versatz -= const Duration(minutes: 30)),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    _versatzText(_versatz),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
                IconButton(
                  tooltip: '+30',
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(
                      () => _versatz += const Duration(minutes: 30)),
                ),
              ],
            ),
            Text(t.gpxVersatzHinweis,
                style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.lg),
            if (_kandidaten.isEmpty)
              Text(t.gpxKeineKandidaten,
                  style: TextStyle(color: farben.onSurfaceVariant))
            else ...[
              Text(t.gpxTreffer(_treffer),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _arbeitet || _treffer == 0 ? null : _verorten,
                child: Text(t.gpxVerorten),
              ),
            ],
          ],
          if (_arbeitet) ...[
            const SizedBox(height: AppSpacing.xl),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}

/// „+2:00" statt „7200000000" – und mit Vorzeichen, weil es hier auf die
/// Richtung ankommt.
String _versatzText(Duration d) {
  final zeichen = d.isNegative ? '−' : '+';
  final gesamt = d.abs();
  final stunden = gesamt.inHours;
  final minuten = gesamt.inMinutes % 60;
  return '$zeichen$stunden:${minuten.toString().padLeft(2, '0')}';
}
