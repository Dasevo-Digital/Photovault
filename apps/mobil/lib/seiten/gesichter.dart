import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/gesichtsuebersicht.dart';
import 'package:uuid/uuid.dart';

import '../bilder.dart';
import '../einfuegbares_menue.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'gesicht_im_foto.dart';

/// Gesichter benennen – wie im Browser (web/app.js, oeffneGesichter) und
/// am Rechner: einer vorhandenen Person zuordnen oder eine neue anlegen,
/// den Vorschlag bestätigen, beiseitelegen oder die Zuordnung lösen. Bei
/// mehreren Gesichtern nimmt ein Tipp eines heraus, das nicht dazugehört.
///
/// `true`, wenn sich etwas geändert hat.
Future<bool> benenneGesichter(
  BuildContext context,
  Sitzung sitzung, {
  required String titel,
  required List<FaceData> gesichter,
  PersonData? vorschlag,
  double? aehnlichkeit,
  PersonData? person,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _Benennen(
          sitzung: sitzung,
          titel: titel,
          gesichter: gesichter,
          vorschlag: vorschlag,
          aehnlichkeit: aehnlichkeit,
          person: person,
        ),
      ),
    ) ??
    false;

class _Benennen extends StatefulWidget {
  const _Benennen({
    required this.sitzung,
    required this.titel,
    required this.gesichter,
    this.vorschlag,
    this.aehnlichkeit,
    this.person,
  });

  final Sitzung sitzung;
  final String titel;
  final List<FaceData> gesichter;
  final PersonData? vorschlag;

  /// Wie ähnlich die Gruppe dem Vorschlag ist – mit ihr lernt die
  /// Schwelle aus der Entscheidung.
  final double? aehnlichkeit;
  final PersonData? person;

  @override
  State<_Benennen> createState() => _BenennenState();
}

class _BenennenState extends State<_Benennen> {
  final _aus = <String>{};
  late final _name = TextEditingController(text: widget.person?.name ?? '');
  List<PersonData> _personen = const [];
  String? _meldung;
  var _laeuft = false;

  AppDatabase get _db => widget.sitzung.db;

  @override
  void initState() {
    super.initState();
    _db.select(_db.people).get().then((p) {
      if (mounted) {
        setState(
          () => _personen =
              [
                for (final x in p)
                  if (x.name.trim().isNotEmpty) x,
              ]..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              ),
        );
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<String> get _ids => [
    for (final g in widget.gesichter)
      if (!_aus.contains(g.id)) g.id,
  ];

  Future<void> _fertig(Future<void> Function(List<String> ids) arbeit) async {
    final t = AppTexte.of(context);
    final ids = _ids;
    if (ids.isEmpty) {
      setState(() => _meldung = t.gesichterKeinGesicht);
      return;
    }
    setState(() {
      _laeuft = true;
      _meldung = null;
    });
    try {
      await arbeit(ids);
      if (mounted) Navigator.pop(context, true);
    } catch (x) {
      if (mounted) {
        setState(() {
          _laeuft = false;
          _meldung = '$x';
        });
      }
    }
  }

  /// Den Rahmen ganz entfernen – für die Stelle, an der kein Gesicht ist.
  /// Nur einzeln: Man soll sehen, was man löscht.
  Future<void> _loeschen() async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.gesichterRahmenLoeschenFrage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.gesichterRahmenLoeschen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    await _fertig((ids) async {
      for (final id in ids) {
        await _db.fuehreAus(GesichtLoeschen(id));
      }
    });
  }

  Future<void> _benennen() async {
    final t = AppTexte.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _meldung = t.gesichterNameFehlt);
      return;
    }
    await _fertig((ids) async {
      // Ein vorhandener Name heisst: diese Person – sonst eine neue.
      final da = _personen
          .where((p) => p.name.trim().toLowerCase() == name.toLowerCase())
          .firstOrNull;
      var personId = da?.id;
      if (personId == null) {
        personId = const Uuid().v4();
        await _db.fuehreAus(PersonAnlegen(personId, name));
      }
      await _db.fuehreAus(GesichterZuordnen(ids, personId));
      await _merke(ids, personId);
    });
  }

  /// Hatte die Gruppe einen Vorschlag, ist die Wahl ein Urteil darüber:
  /// dieselbe Person bestätigt ihn, eine andere lehnt ihn ab. Daraus lernt
  /// die Schwelle der Person – wie am Rechner und im Browser
  /// (gruppeEntschieden im Kern). Beiseitelegen sagt darüber nichts.
  Future<void> _merke(List<String> ids, String personId) async {
    final vorschlag = widget.vorschlag;
    final aehnlichkeit = widget.aehnlichkeit;
    if (vorschlag == null || aehnlichkeit == null) return;
    final b = gruppeEntschieden(
      gruppe: (
        gesichter: widget.gesichter,
        vorschlag: vorschlag,
        aehnlichkeit: aehnlichkeit,
      ),
      zugeordnet: ids,
      personId: personId,
      allgemein: await _db.faceSimilarityThresholdWert(),
    );
    if (b != null) await _db.fuehreAus(b);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final vorschlag = widget.vorschlag;
    final mehrere = widget.gesichter.length > 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.titel, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.3,
              ),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in widget.gesichter)
                      GestureDetector(
                        onTap: mehrere
                            ? () => setState(() {
                                if (!_aus.remove(g.id)) _aus.add(g.id);
                              })
                            : null,
                        child: SizedBox.square(
                          dimension: 64,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Opacity(
                                  opacity: _aus.contains(g.id) ? 0.25 : 1,
                                  child: Personenbild(
                                    paths: widget.sitzung.paths,
                                    name: '?',
                                    relativ: g.cropRelativePath,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: -6,
                                bottom: -6,
                                child: ImFotoKnopf(
                                  beiTipp: () => zeigeGesichtImFoto(
                                    context,
                                    widget.sitzung,
                                    g,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (mehrere)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t.gesichterHinweis,
                  style: TextStyle(
                    color: farben.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            if (vorschlag != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _laeuft
                    ? null
                    : () => _fertig((ids) async {
                        await _db.fuehreAus(
                          GesichterZuordnen(ids, vorschlag.id),
                        );
                        await _merke(ids, vorschlag.id);
                      }),
                child: Text(t.gesichterDasIst(vorschlag.name)),
              ),
            ],
            const SizedBox(height: 12),
            Autocomplete<PersonData>(
              initialValue: TextEditingValue(text: _name.text),
              optionsBuilder: (wert) {
                final s = wert.text.trim().toLowerCase();
                if (s.isEmpty) return const Iterable<PersonData>.empty();
                return _personen
                    .where((p) => p.name.toLowerCase().contains(s))
                    .take(8);
              },
              displayStringForOption: (p) => p.name,
              onSelected: (p) => _name.text = p.name,
              fieldViewBuilder: (context, feld, fokus, absenden) {
                feld.addListener(() => _name.text = feld.text);
                return TextField(
                  controller: feld,
                  focusNode: fokus,
                  contextMenuBuilder: einfuegbaresMenue,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: t.gesichterName,
                    hintText: t.gesichterNamePlatzhalter,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _benennen(),
                );
              },
            ),
            if (_meldung != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_meldung!, style: TextStyle(color: farben.error)),
              ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (widget.gesichter.length == 1)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: farben.error),
                    onPressed: _laeuft ? null : _loeschen,
                    child: Text(t.gesichterRahmenLoeschen),
                  ),
                if (widget.person != null)
                  TextButton(
                    onPressed: _laeuft
                        ? null
                        : () => _fertig((ids) async {
                            for (final id in ids) {
                              await _db.fuehreAus(ZuordnungLoesen(id));
                            }
                          }),
                    child: Text(t.gesichterLoesen),
                  ),
                TextButton(
                  onPressed: _laeuft
                      ? null
                      : () => _fertig(
                          (ids) =>
                              _db.fuehreAus(GesichterBeiseitelegen(ids, true)),
                        ),
                  child: Text(t.gesichterBeiseite),
                ),
                FilledButton.tonal(
                  onPressed: _laeuft ? null : _benennen,
                  child: Text(t.gesichterBenennen),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ähnliche Gesichter ohne Namen, oben auf der Personenseite – dieselben
/// Gruppen wie im Browser (gesichtsuebersicht.dart).
class OhneNamenAbschnitt extends StatefulWidget {
  const OhneNamenAbschnitt({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<OhneNamenAbschnitt> createState() => _OhneNamenAbschnittState();
}

class _OhneNamenAbschnittState extends State<OhneNamenAbschnitt> {
  late Future<(GesichterOhneNamen, int)> _daten = _lade();

  AppDatabase get _db => widget.sitzung.db;

  Future<(GesichterOhneNamen, int)> _lade() async =>
      (await gesichterOhneNamen(_db), await _db.ignoredFacesCount());

  void _neu() => setState(() {
    _daten = _lade();
  });

  void _melde(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Wie das Menü über „Ohne Namen“ am Rechner und im Browser (#192).
  Future<void> _waehle(String wahl) async {
    final t = AppTexte.of(context);
    switch (wahl) {
      case 'ignorieren':
        // Die Gesichter beim Namen, nicht „alle unbenannten“: Der Befehl
        // soll auf jeder Kopie dasselbe tun.
        final ids = [for (final f in await _db.allUnassignedFaces()) f.id];
        if (ids.isNotEmpty) {
          await _db.fuehreAus(GesichterBeiseitelegen(ids, true));
        }
        if (!mounted) return;
        _melde(t.gesichterAlleIgnoriertMeldung(ids.length));
      case 'loeschen':
        final ja = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.gesichterAlleLoeschenTitel),
            content: Text(t.gesichterAlleLoeschenText),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.abbrechen),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.gesichterLoeschen),
              ),
            ],
          ),
        );
        if (ja != true) return;
        final ids = await _db.unbenannteErkennungen();
        if (ids.isNotEmpty) await _db.fuehreAus(GesichterLoeschen(ids));
        if (!mounted) return;
        _melde(t.gesichterGeloeschtMeldung(ids.length));
      case 'ignoriert':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => IgnorierteGesichter(sitzung: widget.sitzung),
          ),
        );
    }
    if (mounted) _neu();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return FutureBuilder<(GesichterOhneNamen, int)>(
      future: _daten,
      builder: (context, snap) {
        final daten = snap.data;
        if (daten == null) return const SizedBox.shrink();
        final (d, ignoriert) = daten;
        // Auch wenn nichts mehr offen ist, solange es Ignorierte gibt:
        // Über das Menü holt man sie zurück.
        if (d.gruppen.isEmpty && ignoriert == 0) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.gesichterOhneNamen,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    t.gesichterAnzahl(d.gesamt),
                    style: TextStyle(color: farben.onSurfaceVariant),
                  ),
                  PopupMenuButton<String>(
                    tooltip: t.betrachterMehr,
                    icon: const Icon(Icons.more_horiz),
                    onSelected: _waehle,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'ignorieren',
                        enabled: d.gesamt > 0,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.visibility_off_outlined),
                          title: Text(t.gesichterAlleIgnorieren),
                          subtitle: Text(
                            t.gesichterAlleIgnorierenHinweis(d.gesamt),
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'loeschen',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.delete_outline),
                          title: Text(t.gesichterAlleLoeschen),
                          subtitle: Text(t.gesichterAlleLoeschenHinweis),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'ignoriert',
                        enabled: ignoriert > 0,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.restore_outlined),
                          title: Text(t.gesichterIgnoriert),
                          subtitle: Text(t.gesichterAnzahl(ignoriert)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (d.gruppen.isNotEmpty)
                SizedBox(
                  // Bild, zwei Zeilen Text und Rand – mit Luft für grössere
                  // Schrift.
                  height:
                      108 +
                      16 +
                      6 +
                      2 * 22 * MediaQuery.textScalerOf(context).scale(1),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: d.gruppen.length.clamp(0, 60),
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final g = d.gruppen[i];
                      final vorschlag = g.vorschlag;
                      return _Gruppenkarte(
                        sitzung: widget.sitzung,
                        gruppe: g,
                        text: vorschlag == null
                            ? t.gesichterWerIstDas
                            : t.gesichterVorschlagFrage(vorschlag.name),
                        anzahl: t.gesichterAnzahl(g.gesichter.length),
                        onTap: () async {
                          final geaendert = await benenneGesichter(
                            context,
                            widget.sitzung,
                            titel: t.gesichterAehnliche(g.gesichter.length),
                            gesichter: g.gesichter,
                            vorschlag: vorschlag,
                            aehnlichkeit: g.aehnlichkeit,
                          );
                          if (geaendert) _neu();
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Gruppenkarte extends StatelessWidget {
  const _Gruppenkarte({
    required this.sitzung,
    required this.gruppe,
    required this.text,
    required this.anzahl,
    required this.onTap,
  });

  final Sitzung sitzung;
  final Gesichtsgruppe gruppe;
  final String text;
  final String anzahl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final bilder = gruppe.gesichter.take(4).toList();
    final form = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: farben.outlineVariant),
    );
    return SizedBox(
      width: 124,
      child: Material(
        color: farben.surfaceContainerLow,
        shape: form,
        child: InkWell(
          customBorder: form,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.square(
                    dimension: 108,
                    child: GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (var i = 0; i < 4; i++)
                          i < bilder.length
                              ? Miniatur(
                                  paths: sitzung.paths,
                                  relativ: bilder[i].cropRelativePath,
                                )
                              : ColoredBox(color: farben.surfaceContainerHigh),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  anzahl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: farben.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Gesichter einer Aufnahme in den Angaben – jedes antippbar.
class GesichterDerAufnahme extends StatefulWidget {
  const GesichterDerAufnahme({
    super.key,
    required this.sitzung,
    required this.assetId,
    this.rahmen,
  });

  final Sitzung sitzung;
  final String assetId;

  /// Um die Gesichter herum – nur, wenn es welche gibt.
  final Widget Function(Widget inhalt)? rahmen;

  @override
  State<GesichterDerAufnahme> createState() => _GesichterDerAufnahmeState();
}

class _GesichterDerAufnahmeState extends State<GesichterDerAufnahme> {
  late Future<List<GesichtAufAufnahme>> _daten = _lade();

  Future<List<GesichtAufAufnahme>> _lade() =>
      gesichterDerAufnahme(widget.sitzung.db, widget.assetId);

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return FutureBuilder<List<GesichtAufAufnahme>>(
      future: _daten,
      builder: (context, snap) {
        final liste = snap.data;
        if (liste == null || liste.isEmpty) return const SizedBox.shrink();
        final inhalt = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final (:gesicht, :person) in liste)
                  Semantics(
                    button: true,
                    label: person?.name ?? t.gesichterWerIstDas,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () async {
                        final geaendert = await benenneGesichter(
                          context,
                          widget.sitzung,
                          titel: person?.name ?? t.gesichterWerIstDas,
                          gesichter: [gesicht],
                          person: person,
                        );
                        if (geaendert && mounted) {
                          setState(() {
                            _daten = _lade();
                          });
                        }
                      },
                      child: SizedBox(
                        width: 56,
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: person == null
                                    ? Border.all(
                                        color: farben.primary,
                                        width: 2,
                                      )
                                    : null,
                              ),
                              child: Personenbild(
                                paths: widget.sitzung.paths,
                                name: person?.name ?? '?',
                                relativ: gesicht.cropRelativePath,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              person?.name ?? '?',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t.gesichterAntippen,
              style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
            ),
          ],
        );
        return widget.rahmen?.call(inhalt) ?? inhalt;
      },
    );
  }
}

/// Zwei Einträge für dieselbe Person: die gewählte geht in [person] auf.
/// `true`, wenn zusammengeführt wurde.
Future<bool> zusammenfuehren(
  BuildContext context,
  Sitzung sitzung,
  PersonData person,
) async {
  final t = AppTexte.of(context);
  final db = sitzung.db;
  final andere = [
    for (final p in await db.select(db.people).get())
      if (p.id != person.id && p.name.trim().isNotEmpty) p,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  if (!context.mounted) return false;
  final wahl = await showDialog<PersonData>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(t.personZusammenfuehrenTitel(person.name)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(t.personZusammenfuehrenText),
        ),
        for (final p in andere)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, p),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 36,
                  child: Personenbild(
                    paths: sitzung.paths,
                    name: p.name,
                    relativ: p.coverFaceCropPath,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(p.name)),
              ],
            ),
          ),
      ],
    ),
  );
  if (wahl == null || !context.mounted) return false;
  final ja = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(t.personZusammenfuehrenFrage(wahl.name, person.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(t.abbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(t.personZusammenfuehren),
        ),
      ],
    ),
  );
  if (ja != true) return false;
  await db.fuehreAus(
    PersonenZusammenfuehren(behalten: person.id, entfernen: wahl.id),
  );
  return true;
}

/// Weitere Fotos einer Person – wie „Vorschläge suchen“ am Rechner und
/// „Weitere Fotos finden“ im Browser: unbenannte Gesichter, die ihr
/// ähnlich genug sind, alle schon gewählt. Was man herausnimmt, gilt als
/// Ablehnung und hebt ihre Schwelle.
///
/// Gibt zurück, wie viele zugeordnet wurden – `null` bei Abbruch.
class WeitereFotos extends StatefulWidget {
  const WeitereFotos({super.key, required this.sitzung, required this.person});

  final Sitzung sitzung;
  final PersonData person;

  @override
  State<WeitereFotos> createState() => _WeitereFotosState();
}

class _WeitereFotosState extends State<WeitereFotos> {
  late final Future<WeitereFotosDaten?> _daten = weitereFotosVon(
    widget.sitzung.db,
    widget.person.id,
  );
  Set<String>? _gewaehlt;
  var _laeuft = false;

  Future<void> _uebernehmen(WeitereFotosDaten d, Set<String> gewaehlt) async {
    setState(() => _laeuft = true);
    try {
      for (final b in vorschlaegeEntschieden(
        personId: widget.person.id,
        vorschlaege: [
          for (final v in d.vorschlaege)
            (faceId: v.gesicht.id, aehnlichkeit: v.aehnlichkeit),
        ],
        angenommen: gewaehlt,
        allgemein: d.allgemein,
      )) {
        await widget.sitzung.db.fuehreAus(b);
      }
      if (mounted) Navigator.pop(context, gewaehlt.length);
    } catch (x) {
      if (!mounted) return;
      setState(() => _laeuft = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$x')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return FutureBuilder<WeitereFotosDaten?>(
      future: _daten,
      builder: (context, snap) {
        final d = snap.data;
        final gewaehlt = _gewaehlt ??= d == null
            ? null
            : {for (final v in d.vorschlaege) v.gesicht.id};
        final alle =
            d != null &&
            gewaehlt != null &&
            gewaehlt.length == d.vorschlaege.length;
        return Scaffold(
          appBar: AppBar(
            title: Text(t.gesichterVorschlaegeFuer(widget.person.name)),
            actions: [
              if (d != null && d.vorschlaege.isNotEmpty)
                TextButton(
                  onPressed: () => setState(
                    () => _gewaehlt = alle
                        ? {}
                        : {for (final v in d.vorschlaege) v.gesicht.id},
                  ),
                  child: Text(
                    alle ? t.gesichterKeineWaehlen : t.gesichterAlleWaehlen,
                  ),
                ),
            ],
          ),
          body: switch ((snap.connectionState, d)) {
            (ConnectionState.done, null) => const SizedBox.shrink(),
            (_, null) => const Center(child: CircularProgressIndicator()),
            (_, final d?) when d.vorschlaege.isEmpty => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t.gesichterNichtsGefunden(d.schwelle.toStringAsFixed(2)),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            (_, final d?) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    t.gesichterVorschlagHinweis,
                    style: TextStyle(color: farben.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 88,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                        ),
                    itemCount: d.vorschlaege.length,
                    itemBuilder: (context, i) {
                      final v = d.vorschlaege[i];
                      final an = gewaehlt!.contains(v.gesicht.id);
                      return Semantics(
                        selected: an,
                        button: true,
                        label: '${(v.aehnlichkeit * 100).round()} %',
                        child: GestureDetector(
                          onTap: () => setState(() {
                            if (!gewaehlt.remove(v.gesicht.id)) {
                              gewaehlt.add(v.gesicht.id);
                            }
                          }),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Opacity(
                                  opacity: an ? 1 : 0.25,
                                  child: Personenbild(
                                    paths: widget.sitzung.paths,
                                    name: '?',
                                    relativ: v.gesicht.cropRelativePath,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: -6,
                                bottom: -6,
                                child: ImFotoKnopf(
                                  beiTipp: () => zeigeGesichtImFoto(
                                    context,
                                    widget.sitzung,
                                    v.gesicht,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: FilledButton(
                      onPressed: _laeuft
                          ? null
                          : () => _uebernehmen(d, gewaehlt!),
                      child: Text(t.gesichterZuordnenAnzahl(gewaehlt!.length)),
                    ),
                  ),
                ),
              ],
            ),
          },
        );
      },
    );
  }
}

/// Die beiseitegelegten Gesichter, wie der Reiter „Ignoriert“ am Rechner
/// und im Browser (#192): antippen wählt aus, „Zurückholen“ stellt sie
/// wieder zu „Ohne Namen“.
class IgnorierteGesichter extends StatefulWidget {
  const IgnorierteGesichter({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<IgnorierteGesichter> createState() => _IgnorierteGesichterState();
}

class _IgnorierteGesichterState extends State<IgnorierteGesichter> {
  late Future<(List<FaceData>, int)> _daten = _lade();
  final _gewaehlt = <String>{};

  AppDatabase get _db => widget.sitzung.db;

  Future<(List<FaceData>, int)> _lade() async =>
      (await _db.ignoredFaces(), await _db.ignoredFacesCount());

  Future<void> _zurueckholen() async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    final ids = _gewaehlt.toList();
    await _db.fuehreAus(GesichterBeiseitelegen(ids, false));
    if (!mounted) return;
    bote
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(t.gesichterZurueckgeholt(ids.length))),
      );
    setState(() {
      _gewaehlt.clear();
      _daten = _lade();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return FutureBuilder<(List<FaceData>, int)>(
      future: _daten,
      builder: (context, snap) {
        final daten = snap.data;
        final gesichter = daten?.$1 ?? const <FaceData>[];
        final gesamt = daten?.$2 ?? 0;
        final alle =
            gesichter.isNotEmpty && _gewaehlt.length == gesichter.length;
        return Scaffold(
          appBar: AppBar(
            title: Text(t.gesichterIgnoriert),
            actions: [
              if (gesichter.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    if (alle) {
                      _gewaehlt.clear();
                    } else {
                      _gewaehlt.addAll([for (final g in gesichter) g.id]);
                    }
                  }),
                  child: Text(
                    alle ? t.auswahlAufheben : t.gesichterAlleWaehlen,
                  ),
                ),
            ],
          ),
          bottomNavigationBar: gesichter.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: FilledButton(
                      onPressed: _gewaehlt.isEmpty ? null : _zurueckholen,
                      child: Text(t.gesichterZurueckholen(_gewaehlt.length)),
                    ),
                  ),
                ),
          body: daten == null
              ? const Center(child: CircularProgressIndicator())
              : gesichter.isEmpty
              ? Center(child: Text(t.gesichterKeineIgnorierten))
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          gesichter.length < gesamt
                              ? t.gesichterIgnoriertErste(
                                  gesichter.length,
                                  gesamt,
                                )
                              : t.gesichterAnzahl(gesamt),
                          style: TextStyle(color: farben.onSurfaceVariant),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(12),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 84,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                            ),
                        itemCount: gesichter.length,
                        itemBuilder: (context, i) {
                          final g = gesichter[i];
                          final an = _gewaehlt.contains(g.id);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (!_gewaehlt.remove(g.id)) _gewaehlt.add(g.id);
                            }),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: DecoratedBox(
                                    position: DecorationPosition.foreground,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: an
                                          ? Border.all(
                                              color: farben.primary,
                                              width: 3,
                                            )
                                          : null,
                                    ),
                                    child: Opacity(
                                      opacity: an ? 1 : 0.6,
                                      child: Personenbild(
                                        paths: widget.sitzung.paths,
                                        name: '?',
                                        relativ: g.cropRelativePath,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: -4,
                                  bottom: -4,
                                  child: ImFotoKnopf(
                                    beiTipp: () => zeigeGesichtImFoto(
                                      context,
                                      widget.sitzung,
                                      g,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
