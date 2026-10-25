import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:kern/db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/meldungsdienst.dart';
import '../services/scan_workspace.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/einfuegbares_menue.dart';

/// Sicherer Arbeitsbereich für Flachbettscans: Eine oder mehrere
/// Quelldateien werden analysiert, erkannte Papierfotos lassen sich vor dem
/// Import einzeln abwählen und drehen. Erst der bestätigte Ausschnitt wird
/// als neue Aufnahme importiert; der Scan selbst bleibt unangetastet.
class ScanWorkspaceScreen extends StatefulWidget {
  const ScanWorkspaceScreen({super.key, required this.library});

  final LibraryState library;

  @override
  State<ScanWorkspaceScreen> createState() => _ScanWorkspaceScreenState();
}

class _ScanWorkspaceScreenState extends State<ScanWorkspaceScreen> {
  final _beschreibung = TextEditingController();
  final List<_ScanQuelle> _quellen = [];
  bool _beschaeftigt = false;
  bool _paarweise = false;
  bool _restaurieren = false;
  DateTime? _datum;
  int _fortschritt = 0;
  int _gesamt = 0;

  bool get _restaurierungVerfuegbar =>
      widget.library.restoreQueue.restoreHalter?.installiert == true;

  List<(_ScanQuelle, _ScanKandidat)> get _auswahl => [
    for (final q in _quellen)
      for (final k in q.kandidaten)
        if (k.ausgewaehlt) (q, k),
  ];

  @override
  void dispose() {
    _beschreibung.dispose();
    super.dispose();
  }

  Future<void> _dateienWaehlen() async {
    final dateien = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'bmp', 'tif', 'tiff'],
      dialogTitle: AppTexte.of(context).scanDateienWaehlen,
    );
    final pfade = dateien.map((f) => f.path).whereType<String>().toList();
    if (pfade.isEmpty || !mounted) return;
    setState(() {
      _beschaeftigt = true;
      _fortschritt = 0;
      _gesamt = pfade.length;
    });
    try {
      final neu = <_ScanQuelle>[];
      for (final pfad in pfade) {
        final bytes = await File(pfad).readAsBytes();
        final analyse = await Isolate.run(() => analysiereScan(bytes));
        neu.add(_ScanQuelle.aus(pfad, bytes, analyse));
        if (mounted) setState(() => _fortschritt++);
      }
      if (mounted) setState(() => _quellen.addAll(neu));
    } catch (e) {
      if (mounted) melde.fehler(AppTexte.of(context).scanFehler('$e'));
    } finally {
      if (mounted) setState(() => _beschaeftigt = false);
    }
  }

  Future<void> _ganzenScanVerwenden(_ScanQuelle quelle) async {
    setState(() => _beschaeftigt = true);
    try {
      final bereich = ScanBereich(
        x: 0,
        y: 0,
        breite: quelle.breite,
        hoehe: quelle.hoehe,
      );
      final vorschau = await Isolate.run(
        () => erzeugeScanVorschau(quelle.bytes, bereich),
      );
      if (mounted) {
        setState(() {
          quelle.kandidaten
            ..clear()
            ..add(_ScanKandidat(bereich, vorschau));
        });
      }
    } finally {
      if (mounted) setState(() => _beschaeftigt = false);
    }
  }

  Future<void> _datumWaehlen() async {
    final datum = await showDatePicker(
      context: context,
      firstDate: DateTime(1800),
      lastDate: DateTime.now(),
      initialDate: _datum ?? DateTime.now(),
    );
    if (datum != null && mounted) setState(() => _datum = datum);
  }

  Future<void> _importieren() async {
    final auswahl = _auswahl;
    final t = AppTexte.of(context);
    if (auswahl.isEmpty) {
      melde.hinweis(t.scanKeineAuswahl);
      return;
    }
    if (_paarweise && auswahl.length.isOdd) {
      melde.warnung(t.scanUngerade);
      return;
    }

    setState(() {
      _beschaeftigt = true;
      _fortschritt = 0;
      _gesamt = auswahl.length * 2;
    });
    final temp = await Directory.systemTemp.createTemp('photo_vault_scan_');
    var duplikate = 0, fehler = 0;
    final importiert = <String>[];
    try {
      final dateipfade = <String>[];
      for (var i = 0; i < auswahl.length; i++) {
        final (quelle, kandidat) = auswahl[i];
        final bytes = await Isolate.run(
          () => erzeugeScanJpeg(
            quelle.bytes,
            kandidat.bereich,
            vierteldrehungen: kandidat.drehungen,
          ),
        );
        final basis = p.basenameWithoutExtension(quelle.pfad);
        final ziel = File(
          p.join(
            temp.path,
            '${basis}_${(i + 1).toString().padLeft(3, '0')}.jpg',
          ),
        );
        await ziel.writeAsBytes(bytes, flush: true);
        dateipfade.add(ziel.path);
        if (mounted) setState(() => _fortschritt++);
      }

      await for (final stand in widget.library.importFiles(dateipfade)) {
        if (stand.assetId != null) importiert.add(stand.assetId!);
        if (stand.duplikat) duplikate++;
        if (stand.gescheitert) fehler++;
        if (mounted) setState(() => _fortschritt++);
      }
      final text = _beschreibung.text.trim();
      if (text.isNotEmpty && importiert.isNotEmpty) {
        await widget.library.db.fuehreAus(BeschreibungSetzen(importiert, text));
      }
      if (_datum != null && importiert.isNotEmpty) {
        await widget.library.setzeAufnahmedatumVonHand(importiert, _datum!);
      }
      if (_paarweise) {
        if (importiert.length.isEven) {
          for (var i = 0; i < importiert.length; i += 2) {
            await widget.library.db.fuehreAus(
              VariantenBilden(const Uuid().v4(), [
                importiert[i],
                importiert[i + 1],
              ], importiert[i]),
            );
          }
        } else if (mounted) {
          melde.warnung(t.scanPaarNichtGestapelt);
        }
      }
      if (_restaurieren) {
        for (final id in importiert) {
          await widget.library.restoreQueue.enqueue(id);
        }
      }
      if (mounted) {
        melde.erfolg(t.scanFertig(importiert.length, duplikate, fehler));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) melde.fehler(t.scanFehler('$e'));
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
      if (mounted) setState(() => _beschaeftigt = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final auswahl = _auswahl.length;
    return Scaffold(
      appBar: AppBar(title: Text(t.scanTitel)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(t.scanText),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _beschaeftigt ? null : _dateienWaehlen,
            icon: const Icon(Icons.document_scanner_outlined),
            label: Text(t.scanDateienWaehlen),
          ),
          if (_beschaeftigt) ...[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(
              value: _gesamt == 0 ? null : _fortschritt / _gesamt,
            ),
          ],
          if (_quellen.isEmpty && !_beschaeftigt) ...[
            const SizedBox(height: AppSpacing.xl),
            Center(child: Text(t.scanNochKeine)),
          ],
          for (final quelle in _quellen) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.basename(quelle.pfad),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _beschaeftigt
                      ? null
                      : () => _ganzenScanVerwenden(quelle),
                  child: Text(t.scanGanzesBild),
                ),
              ],
            ),
            Text(t.scanErkannt(quelle.kandidaten.length)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < quelle.kandidaten.length; i++)
                  _KandidatenKarte(
                    kandidat: quelle.kandidaten[i],
                    nummer: i + 1,
                    beiAenderung: () => setState(() {}),
                  ),
              ],
            ),
          ],
          if (_quellen.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _beschreibung,
              contextMenuBuilder: einfuegbaresMenue,
              decoration: InputDecoration(
                labelText: t.scanBeschreibung,
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                _datum == null
                    ? t.scanDatumKeins
                    : MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(_datum!),
              ),
              trailing: _datum == null
                  ? null
                  : IconButton(
                      tooltip: t.allgLoeschen,
                      onPressed: () => setState(() => _datum = null),
                      icon: const Icon(Icons.close),
                    ),
              onTap: _datumWaehlen,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.scanPaarweise),
              subtitle: Text(t.scanPaarweiseText),
              value: _paarweise,
              onChanged: (v) => setState(() => _paarweise = v),
            ),
            if (_restaurierungVerfuegbar)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.scanRestaurieren),
                subtitle: Text(t.scanRestaurierenText),
                value: _restaurieren,
                onChanged: (v) => setState(() => _restaurieren = v),
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _beschaeftigt || auswahl == 0 ? null : _importieren,
              icon: const Icon(Icons.library_add_outlined),
              label: Text(t.scanImportieren(auswahl)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanQuelle {
  _ScanQuelle(this.pfad, this.bytes, this.breite, this.hoehe, this.kandidaten);

  factory _ScanQuelle.aus(String pfad, Uint8List bytes, ScanAnalyse analyse) =>
      _ScanQuelle(pfad, bytes, analyse.breite, analyse.hoehe, [
        for (final v in analyse.vorschauen) _ScanKandidat(v.bereich, v.jpeg),
      ]);

  final String pfad;
  final Uint8List bytes;
  final int breite, hoehe;
  final List<_ScanKandidat> kandidaten;
}

class _ScanKandidat {
  _ScanKandidat(this.bereich, this.vorschau);
  final ScanBereich bereich;
  final Uint8List vorschau;
  bool ausgewaehlt = true;
  int drehungen = 0;
}

class _KandidatenKarte extends StatelessWidget {
  const _KandidatenKarte({
    required this.kandidat,
    required this.nummer,
    required this.beiAenderung,
  });

  final _ScanKandidat kandidat;
  final int nummer;
  final VoidCallback beiAenderung;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: RotatedBox(
                  quarterTurns: kandidat.drehungen,
                  child: Image.memory(kandidat.vorschau, fit: BoxFit.contain),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(t.scanFotoNummer(nummer)),
                value: kandidat.ausgewaehlt,
                onChanged: (v) {
                  kandidat.ausgewaehlt = v ?? false;
                  beiAenderung();
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: t.scanLinksDrehen,
                    onPressed: () {
                      kandidat.drehungen = (kandidat.drehungen + 3) % 4;
                      beiAenderung();
                    },
                    icon: const Icon(Icons.rotate_left),
                  ),
                  IconButton(
                    tooltip: t.scanRechtsDrehen,
                    onPressed: () {
                      kandidat.drehungen = (kandidat.drehungen + 1) % 4;
                      beiAenderung();
                    },
                    icon: const Icon(Icons.rotate_right),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
