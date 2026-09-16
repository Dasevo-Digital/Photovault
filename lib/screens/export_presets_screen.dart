import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/export_naming.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';

/// Verwaltung benannter Export-Vorgaben.
///
/// Die vier festen Grössen im Export-Dialog decken den schnellen Fall ab;
/// diese Vorgaben den wiederkehrenden. Sie werden nirgends automatisch
/// angewendet – anders als Kamera-Presets, die beim Import von selbst
/// zugreifen –, sondern erscheinen im Export-Dialog als zusätzliche
/// Auswahl. Wer keine anlegt, merkt von der Änderung nichts.
class ExportPresetsScreen extends StatelessWidget {
  final LibraryState library;
  const ExportPresetsScreen({super.key, required this.library});

  Future<void> _bearbeiten(BuildContext context, {ExportPresetData? bestehend}) async {
    // Die belegten Namen wandern in den Editor, statt erst beim Speichern
    // an der `unique`-Spalte aufzulaufen: Der Nutzer soll es erfahren,
    // während er tippt, nicht als Absturz danach.
    final belegt = (await library.db.alleExportPresets())
        .where((v) => v.id != bestehend?.id)
        .map((v) => v.name)
        .toSet();
    if (!context.mounted) return;

    final ergebnis = await showDialog<ExportPresetsCompanion>(
      context: context,
      builder: (context) =>
          _VorgabeEditor(bestehend: bestehend, belegteNamen: belegt),
    );
    if (ergebnis == null) return;
    await library.db.upsertExportPreset(ergebnis);
  }

  Future<void> _loeschen(BuildContext context, ExportPresetData vorgabe) async {
    final t = AppTexte.of(context);
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.exportVorgabeLoeschenTitel),
        content: Text(t.exportVorgabeLoeschenText(vorgabe.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.allgLoeschen)),
        ],
      ),
    );
    if (bestaetigt != true) return;
    await library.db.deleteExportPreset(vorgabe.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.exportVorgabenTitel)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _bearbeiten(context),
        tooltip: t.exportVorgabeNeu,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<ExportPresetData>>(
        stream: library.db.watchExportPresets(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final vorgaben = snap.data!;
          if (vorgaben.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Text(t.exportVorgabenLeer, textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: vorgaben.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final v = vorgaben[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: Text(v.name),
                  subtitle: Text(vorgabeZusammenfassung(t, v)),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: t.allgBearbeiten,
                        onPressed: () => _bearbeiten(context, bestehend: v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: t.allgLoeschen,
                        onPressed: () => _loeschen(context, v),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Eine Vorgabe in einem Satz – für die Liste hier und für den
/// Export-Dialog, damit beide dasselbe sagen.
String vorgabeZusammenfassung(AppTexte t, ExportPresetData v) {
  final teile = <String>[
    if (!v.nachJpeg)
      t.exportUnveraendert
    else if (v.maxKante == null)
      t.exportVorgabeJpegVoll((v.qualitaet * 100).round())
    else
      t.exportVorgabeJpegKante(v.maxKante!, (v.qualitaet * 100).round()),
    v.namensmuster,
    if (!v.xmpDaneben) t.exportVorgabeOhneXmp,
  ];
  return teile.join(' · ');
}

class _VorgabeEditor extends StatefulWidget {
  final ExportPresetData? bestehend;

  /// Namen der übrigen Vorgaben – die Spalte ist `unique`, ein doppelter
  /// Name liefe sonst erst beim Speichern auf einen Datenbankfehler.
  final Set<String> belegteNamen;

  const _VorgabeEditor({this.bestehend, required this.belegteNamen});

  @override
  State<_VorgabeEditor> createState() => _VorgabeEditorState();
}

class _VorgabeEditorState extends State<_VorgabeEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.bestehend?.name ?? '');
  late final TextEditingController _muster = TextEditingController(
      text: widget.bestehend?.namensmuster ?? Namensbaustein.name.muster);
  late final TextEditingController _kante =
      TextEditingController(text: widget.bestehend?.maxKante?.toString() ?? '');

  late bool _nachJpeg = widget.bestehend?.nachJpeg ?? true;
  late double _qualitaet = widget.bestehend?.qualitaet ?? 0.9;
  late bool _xmp = widget.bestehend?.xmpDaneben ?? true;
  String? _fehler;

  @override
  void dispose() {
    _name.dispose();
    _muster.dispose();
    _kante.dispose();
    super.dispose();
  }

  void _speichern() {
    final t = AppTexte.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _fehler = t.exportVorgabeNameNoetig);
      return;
    }
    if (widget.belegteNamen.contains(name)) {
      setState(() => _fehler = t.exportVorgabeNameVergeben);
      return;
    }
    int? kante;
    if (_nachJpeg && _kante.text.trim().isNotEmpty) {
      kante = int.tryParse(_kante.text.trim());
      if (kante == null || kante < 64 || kante > 20000) {
        setState(() => _fehler = t.exportVorgabeKanteUngueltig);
        return;
      }
    }
    final muster = _muster.text.trim();
    if (muster.isEmpty) {
      setState(() => _fehler = t.exportVorgabeMusterNoetig);
      return;
    }

    Navigator.pop(
      context,
      ExportPresetsCompanion(
        // Beim Bearbeiten dieselbe Zeile treffen; beim Anlegen vergibt
        // SQLite die Nummer selbst.
        id: widget.bestehend == null
            ? const Value.absent()
            : Value(widget.bestehend!.id),
        name: Value(name),
        nachJpeg: Value(_nachJpeg),
        maxKante: Value(_nachJpeg ? kante : null),
        qualitaet: Value(_qualitaet),
        namensmuster: Value(muster),
        xmpDaneben: Value(_xmp),
        erstelltAm: Value(widget.bestehend?.erstelltAm ?? DateTime.now()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(widget.bestehend == null
          ? t.exportVorgabeNeuTitel
          : t.exportVorgabeBearbeitenTitel),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(labelText: t.exportVorgabeName),
              ),
              const SizedBox(height: AppSpacing.lg),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.exportVorgabeNachJpeg),
                subtitle: Text(t.exportVorgabeNachJpegHinweis),
                value: _nachJpeg,
                onChanged: (v) => setState(() => _nachJpeg = v),
              ),
              if (_nachJpeg) ...[
                TextField(
                  controller: _kante,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t.exportVorgabeKante,
                    hintText: t.exportVorgabeKanteLeer,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(t.exportVorgabeQualitaet((_qualitaet * 100).round()),
                    style: Theme.of(context).textTheme.labelLarge),
                Slider(
                  value: _qualitaet,
                  min: 0.4,
                  max: 1,
                  divisions: 12,
                  onChanged: (v) => setState(() => _qualitaet = v),
                ),
              ],
              const Divider(height: AppSpacing.xxl),
              TextField(
                controller: _muster,
                decoration: InputDecoration(labelText: t.exportVorgabeMuster),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final baustein in Namensbaustein.values)
                    ActionChip(
                      label: Text(baustein.muster),
                      // Nicht `_muster.text = …`: Dieser Setter räumt die
                      // Schreibmarke weg (`TextSelection.collapsed(-1)`),
                      // und der nächste Tastendruck landet dann am Anfang
                      // statt am Ende. Deshalb Text UND Marke zusammen
                      // setzen – angehängt, Marke dahinter.
                      onPressed: () {
                        final neu = '${_muster.text}${baustein.muster}';
                        _muster.value = TextEditingValue(
                          text: neu,
                          selection: TextSelection.collapsed(offset: neu.length),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(t.exportVorgabeMusterHinweis,
                  style: Theme.of(context).textTheme.bodySmall),
              const Divider(height: AppSpacing.xxl),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.exportVorgabeXmp),
                subtitle: Text(t.exportVorgabeXmpHinweis),
                value: _xmp,
                onChanged: (v) => setState(() => _xmp = v),
              ),
              if (_fehler != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_fehler!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.allgAbbrechen)),
        FilledButton(onPressed: _speichern, child: Text(t.allgSpeichern)),
      ],
    );
  }
}
