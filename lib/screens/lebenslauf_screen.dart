import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/lebenslauf.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/mini_location_map.dart';

/// Der Lebenslauf einer Person: Geburt, Tod und alles dazwischen.
///
/// Geburt und Tod kommen aus den Spalten der Person, alles andere aus der
/// Ereignistabelle – zusammengeführt und sortiert in [lebenslauf]. Sie
/// lassen sich hier nicht löschen, weil sie hier nicht angelegt wurden;
/// dafür gibt es die Angaben zur Person im Stammbaum.
class LebenslaufScreen extends StatelessWidget {
  final LibraryState library;
  final PersonData person;

  const LebenslaufScreen({super.key, required this.library, required this.person});

  static IconData symbol(Lebenszeile z) {
    if (z.istGeburt) return Icons.child_friendly_outlined;
    if (z.istTod) return Icons.local_florist_outlined;
    return switch (z.art!) {
      Ereignisart.hochzeit => Icons.favorite_outline,
      Ereignisart.umzug => Icons.local_shipping_outlined,
      Ereignisart.beruf => Icons.work_outline,
      Ereignisart.ausbildung => Icons.school_outlined,
      Ereignisart.sonstiges => Icons.event_note_outlined,
    };
  }

  static String beschriftung(AppTexte t, Lebenszeile z) {
    if (z.istGeburt) return t.lebenslaufGeburt;
    if (z.istTod) return t.lebenslaufTod;
    return switch (z.art!) {
      Ereignisart.hochzeit => t.lebenslaufHochzeit,
      Ereignisart.umzug => t.lebenslaufUmzug,
      Ereignisart.beruf => t.lebenslaufBeruf,
      Ereignisart.ausbildung => t.lebenslaufAusbildung,
      Ereignisart.sonstiges => t.lebenslaufSonstiges,
    };
  }

  Future<void> _hinzufuegen(BuildContext context) async {
    final ergebnis = await showDialog<EreignisEingabe>(
      context: context,
      builder: (_) => const _EreignisDialog(),
    );
    if (ergebnis == null) return;
    await library.db.fuegeEreignisHinzu(LebensereignisseCompanion.insert(
      id: const Uuid().v4(),
      personId: person.id,
      art: ereignisartZuText(ergebnis.art),
      datum: Value(ergebnis.datum),
      ort: Value(ergebnis.ort),
      notiz: Value(ergebnis.notiz),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.lebenslaufVon(person.name)),
        actions: [
          IconButton(
            tooltip: t.lebenslaufHinzufuegen,
            icon: const Icon(Icons.add),
            onPressed: () => _hinzufuegen(context),
          ),
        ],
      ),
      body: StreamBuilder<List<LebensereignisseData>>(
        stream: library.db.watchEreignisse(person.id),
        builder: (context, schnappschuss) {
          final roh = schnappschuss.data ?? const <LebensereignisseData>[];
          // Die Koordinaten kommen aus den Rohdaten und nicht durch
          // [lebenslauf] hindurch: Jenes ordnet zwei Quellen zu einer
          // Reihenfolge und hat mit Karten nichts zu tun. Es dafür zu
          // erweitern hiesse, eine geprüfte, reine Funktion für eine
          // Anzeigefrage umzubauen.
          final nachId = {for (final e in roh) e.id: e};

          final zeilen = lebenslauf(
            geburt: person.geburtsdatum,
            tod: person.sterbedatum,
            ereignisse: [
              for (final e in roh)
                (
                  id: e.id,
                  art: ereignisartAusText(e.art),
                  datum: e.datum,
                  ort: e.ort,
                  notiz: e.notiz,
                ),
            ],
          );
          if (zeilen.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: SizedBox(
                  width: 420,
                  child: Text(t.lebenslaufLeer, textAlign: TextAlign.center),
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: zeilen.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final z = zeilen[index];
              final teile = [
                if (z.ort != null && z.ort!.isNotEmpty) z.ort!,
                if (z.notiz != null && z.notiz!.isNotEmpty) z.notiz!,
              ];
              return ListTile(
                leading: Icon(symbol(z)),
                title: Text(beschriftung(t, z)),
                subtitle: teile.isEmpty ? null : Text(teile.join(' · ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      z.datum == null
                          ? t.lebenslaufOhneDatum
                          : '${z.datum!.day}.${z.datum!.month}.${z.datum!.year}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12),
                    ),
                    // Der Ortsknopf nur, wo ein Ort steht – ohne
                    // Ortsnamen gibt es nichts zu verorten.
                    if (z.ereignisId != null &&
                        z.ort != null &&
                        z.ort!.isNotEmpty)
                      _Ortsknopf(
                        library: library,
                        ereignis: nachId[z.ereignisId!]!,
                      ),
                    // Geburt und Tod haben hier keinen Löschknopf: Sie
                    // stehen an der Person, nicht in dieser Liste.
                    if (z.ereignisId != null)
                      IconButton(
                        tooltip: t.allgLoeschen,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => library.db.loescheEreignis(z.ereignisId!),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EreignisDialog extends StatefulWidget {
  const _EreignisDialog();

  @override
  State<_EreignisDialog> createState() => _EreignisDialogState();
}

class _EreignisDialogState extends State<_EreignisDialog> {
  Ereignisart _art = Ereignisart.hochzeit;
  DateTime? _datum;
  final _ort = TextEditingController();
  final _notiz = TextEditingController();

  @override
  void dispose() {
    _ort.dispose();
    _notiz.dispose();
    super.dispose();
  }

  Future<void> _waehleDatum() async {
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: _datum ?? DateTime.now(),
      firstDate: DateTime(1800),
      lastDate: DateTime.now(),
    );
    if (gewaehlt == null || !mounted) return;
    setState(() => _datum = gewaehlt);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(t.lebenslaufHinzufuegen),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<Ereignisart>(
              value: _art,
              isExpanded: true,
              onChanged: (w) => setState(() => _art = w ?? _art),
              items: [
                for (final a in Ereignisart.values)
                  DropdownMenuItem(
                    value: a,
                    child: Text(LebenslaufScreen.beschriftung(
                        t, Lebenszeile(art: a, ereignisId: 'x'))),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _waehleDatum,
                    child: Text(_datum == null
                        ? t.lebenslaufOhneDatum
                        : '${_datum!.day}.${_datum!.month}.${_datum!.year}'),
                  ),
                ),
                IconButton(
                  tooltip: t.allgEntfernen,
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: _datum == null ? null : () => setState(() => _datum = null),
                ),
              ],
            ),
            TextField(
              controller: _ort,
              decoration: InputDecoration(labelText: t.lebenslaufOrt),
            ),
            TextField(
              controller: _notiz,
              decoration: InputDecoration(labelText: t.lebenslaufNotiz),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(t.allgAbbrechen)),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            id: '',
            art: _art,
            datum: _datum,
            ort: _ort.text.trim().isEmpty ? null : _ort.text.trim(),
            notiz: _notiz.text.trim().isEmpty ? null : _notiz.text.trim(),
          )),
          child: Text(t.allgSpeichern),
        ),
      ],
    );
  }
}

/// Der Knopf, mit dem sich der Ort eines Ereignisses ansehen und
/// berichtigen lässt.
///
/// **Warum es diesen Knopf überhaupt gibt.** Die Zuordnung von Ortsname
/// zu Koordinate ist eine Vermutung: „Springfield" trifft in den USA über
/// zwanzig Mal zu, „Paris" gibt es in Frankreich und in Texas. Die Suche
/// entscheidet sich für einen – und muss dem Nutzer die Möglichkeit
/// lassen, das umzustossen, ohne den aufgeschriebenen Namen anzufassen.
///
/// Das Symbol sagt schon vor dem Antippen, woran man ist: ein gefüllter
/// Stecknadelkopf heisst „gefunden", ein durchgestrichener „im
/// Verzeichnis nicht enthalten".
class _Ortsknopf extends StatelessWidget {
  const _Ortsknopf({required this.library, required this.ereignis});

  final LibraryState library;
  final LebensereignisseData ereignis;

  bool get _verortet => ereignis.ortBreite != null;

  Future<void> _oeffnen(BuildContext context) async {
    final t = AppTexte.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ereignis.ort ?? t.lebenslaufOrtAufKarte),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                !library.geoDataAvailable
                    ? t.lebenslaufOrtOhneVerzeichnis
                    : _verortet
                        ? t.lebenslaufOrtErkannt
                        : t.lebenslaufOrtUnbekannt,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              MiniLocationMap(
                latitude: ereignis.ortBreite,
                longitude: ereignis.ortLaenge,
                height: 220,
                onLocationChanged: (breite, laenge) async {
                  await library.db.setzeEreignisort(ereignis.id,
                      breite: breite, laenge: laenge);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
              ),
            ],
          ),
        ),
        actions: [
          if (_verortet)
            TextButton(
              onPressed: () async {
                // Ausdrücklich ohne Ortsnamen anzufassen: „nicht
                // verortet" muss ein erreichbarer Zustand bleiben, sonst
                // liesse sich eine falsche Zuordnung nur durch Löschen
                // des ganzen Ereignisses beheben.
                await library.db.setzeEreignisort(ereignis.id);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: Text(t.lebenslaufOrtEntfernen),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t.allgSchliessen),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return IconButton(
      tooltip: t.lebenslaufOrtAufKarte,
      icon: Icon(
        _verortet ? Icons.place : Icons.wrong_location_outlined,
        size: 18,
        color: _verortet
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onPressed: () => _oeffnen(context),
    );
  }
}
