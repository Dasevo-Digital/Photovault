import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/verbindung.dart';

import 'geteilte_alben.dart';

// Alben, die sich selbst füllen (#298), und was ein Partner sieht (#299) –
// wie im Browser (web/app.js, oeffneRegelDialog): Personen wählen,
// wahlweise ein Tag. Beim Album dazu, ob eine der Personen genügt oder
// alle zusammen drauf sein müssen; bei der Partnerfreigabe genügt eine.
// Gerechnet wird am Server; ein Gerät sagt ihm nur, was gelten soll.

String _k(String s) => Uri.encodeComponent(s);

/// Eine Person der eigenen Bibliothek, wie der Server sie nennt.
class Regelperson {
  const Regelperson(this.id, this.name, {this.anzahl = 0, this.bild});

  final String id;
  final String name;
  final int anzahl;

  /// Der Gesichtsausschnitt unter `api/v1/dateien/…`.
  final String? bild;
}

/// Was gelten soll: [personen], wahlweise [alle] zusammen und ab [ab].
class Regel {
  const Regel({
    this.personen = const [],
    this.alle = false,
    this.ab,
    this.fehlend = 0,
  });

  factory Regel.aus(Map<String, Object?> j) => Regel(
    personen: [
      for (final p in (j['personen'] as List? ?? const []))
        if (p case {'id': final String id, 'name': final String name})
          Regelperson(id, name),
    ],
    alle: j['alle'] == true,
    ab: switch (j['ab']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    },
    fehlend: (j['fehlend'] as num?)?.toInt() ?? 0,
  );

  final List<Regelperson> personen;
  final bool alle;
  final DateTime? ab;

  /// Gewählte Personen, die es nicht mehr gibt (zusammengeführt).
  final int fehlend;

  /// Nichts eingeschränkt. Fehlende Personen zählen mit: Der Server filtert
  /// weiter nach ihnen, auch wenn keine Namen mehr übrig sind.
  bool get leer => personen.isEmpty && ab == null && fehlend == 0;
}

String _tag(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// „mit Anna, Ben · ab 01.01.2020“ – für Album und Partner.
String regelText(BuildContext context, Regel r) {
  final t = teilenTexte(context);
  final teile = <String>[];
  final namen = [for (final p in r.personen) p.name];
  if (namen.isNotEmpty) {
    teile.add(
      r.alle
          ? t.regelZusammen(namen.join(' & '))
          : t.regelMit(namen.join(', ')),
    );
  }
  if (r.fehlend > 0) teile.add(t.regelPersonenFehlen(r.fehlend));
  if (r.ab case final ab?) {
    teile.add(
      t.regelAb(
        DateFormat.yMd(Localizations.localeOf(context).toString()).format(ab),
      ),
    );
  }
  return teile.join(' · ');
}

Future<Map<String, Object?>> _mitJson(
  Serververbindung v,
  String methode,
  String pfad,
  Object inhalt,
) async {
  final r = await v.anfrage(
    methode,
    pfad,
    kopf: const {'content-type': 'application/json'},
    inhalt: utf8.encode(jsonEncode(inhalt)),
    zeitlimit: const Duration(minutes: 2),
  );
  if (r.statusCode >= 300) throw Serverfehler(r.statusCode, r.body);
  if (r.bodyBytes.isEmpty) return const {};
  final j = jsonDecode(utf8.decode(r.bodyBytes));
  return j is Map ? j.cast<String, Object?>() : const {};
}

/// Die Regel von [albumId] – `null` ohne Regel; [Serverfehler] 404 von
/// einem Server, der keine Regeln kennt.
Future<Regel?> albumregel(Serververbindung v, String albumId) async {
  final d = await v.hole('api/v1/alben/${_k(albumId)}/regel');
  return switch (d['regel']) {
    final Map<Object?, Object?> m => Regel.aus(m.cast<String, Object?>()),
    _ => null,
  };
}

/// Zeigt [kind] am Rechner als Dialog, am Telefon als Blatt von unten.
Future<T?> _zeige<T>(BuildContext context, Widget kind) {
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<T>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: kind,
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => kind,
  );
}

/// „Automatisch füllen“ für das eigene Album [albumId]. `true`, wenn sich
/// etwas geändert hat.
Future<bool> albumAutomatischFuellen(
  BuildContext context,
  Serververbindung verbindung, {
  required String albumId,
  required String titel,
  Regel? vorher,
}) async {
  final bote = ScaffoldMessenger.of(context);
  final t = teilenTexte(context);
  final ergebnis = await _zeige<_Ausgang>(
    context,
    _Regelblatt(
      verbindung: verbindung,
      titel: t.automatischTitel(titel),
      hinweis: t.automatischHinweis,
      mitArt: true,
      vorher: vorher,
      speichern: (r) async {
        if (r.personen.isEmpty) throw _Hinweis(t.regelMindestensEine);
        final d = await _mitJson(
          verbindung,
          'PUT',
          'api/v1/alben/${_k(albumId)}/regel',
          {
            'personen': [for (final p in r.personen) p.id],
            'alle': r.alle,
            'ab': r.ab == null ? null : _tag(r.ab!),
          },
        );
        return _Ausgang.gespeichert((d['dazu'] as num?)?.toInt() ?? 0);
      },
      entfernen: vorher == null
          ? null
          : () async {
              final r = await verbindung.anfrage(
                'DELETE',
                'api/v1/alben/${_k(albumId)}/regel',
              );
              if (r.statusCode >= 300) throw Serverfehler(r.statusCode, r.body);
              return const _Ausgang.entfernt();
            },
    ),
  );
  if (ergebnis == null) return false;
  bote.showSnackBar(
    SnackBar(
      content: Text(
        ergebnis.entfernt
            ? t.automatischAusGemacht
            : t.automatischDazu(ergebnis.dazu),
      ),
    ),
  );
  return true;
}

/// „Einschränken“: was [name] von der eigenen Bibliothek sieht (#299).
/// `true`, wenn sich etwas geändert hat.
Future<bool> partnerEinschraenken(
  BuildContext context,
  Serververbindung verbindung, {
  required String konto,
  required String name,
  Regel? vorher,
}) async {
  final t = teilenTexte(context);
  final ergebnis = await _zeige<_Ausgang>(
    context,
    _Regelblatt(
      verbindung: verbindung,
      titel: t.partnerWasSieht(name),
      hinweis: t.partnerEinschraenkenHinweis(name),
      mitArt: false,
      vorher: vorher,
      speichern: (r) async {
        await _mitJson(verbindung, 'PUT', 'api/v1/partner/${_k(konto)}', {
          'ab': r.ab == null ? null : _tag(r.ab!),
          'personen': [for (final p in r.personen) p.id],
        });
        return const _Ausgang.gespeichert(0);
      },
    ),
  );
  return ergebnis != null;
}

class _Ausgang {
  const _Ausgang.gespeichert(this.dazu) : entfernt = false;
  const _Ausgang.entfernt() : dazu = 0, entfernt = true;

  final int dazu;
  final bool entfernt;
}

/// Ein Fehler, den der Nutzer selbst behebt – ohne Serverwortlaut.
class _Hinweis implements Exception {
  const _Hinweis(this.text);
  final String text;
}

class _Regelblatt extends StatefulWidget {
  const _Regelblatt({
    required this.verbindung,
    required this.titel,
    required this.hinweis,
    required this.mitArt,
    required this.speichern,
    this.vorher,
    this.entfernen,
  });

  final Serververbindung verbindung;
  final String titel;
  final String hinweis;

  /// Ob „eine oder alle zusammen“ zur Wahl steht (nur beim Album).
  final bool mitArt;
  final Regel? vorher;
  final Future<_Ausgang> Function(Regel r) speichern;
  final Future<_Ausgang> Function()? entfernen;

  @override
  State<_Regelblatt> createState() => _RegelblattState();
}

class _RegelblattState extends State<_Regelblatt> {
  static const _hoechstens = 20;

  List<Regelperson>? _personen;
  late final Set<String> _gewaehlt = {
    for (final p in widget.vorher?.personen ?? const <Regelperson>[]) p.id,
  };
  late bool _alle = widget.vorher?.alle ?? false;
  late DateTime? _ab = widget.vorher?.ab;
  var _suche = '';
  var _arbeitet = false;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final d = await widget.verbindung.hole('api/v1/personen');
      if (!mounted) return;
      setState(() {
        _personen = [
          for (final p in (d['personen'] as List? ?? const []))
            if (p case {'id': final String id, 'name': final String name})
              if (name.trim().isNotEmpty)
                Regelperson(
                  id,
                  name,
                  anzahl: (p['anzahl'] as num?)?.toInt() ?? 0,
                  bild: p['bild'] as String?,
                ),
        ];
      });
    } on Object {
      if (mounted) {
        setState(() {
          _personen = const [];
          _fehler = teilenTexte(context).geteiltOffline;
        });
      }
    }
  }

  Future<void> _fuehreAus(Future<_Ausgang> Function() schritt) async {
    setState(() {
      _arbeitet = true;
      _fehler = null;
    });
    try {
      final a = await schritt();
      if (mounted) Navigator.of(context).pop(a);
    } on _Hinweis catch (h) {
      if (mounted) setState(() => _fehler = h.text);
    } on Serverfehler catch (e) {
      if (mounted) setState(() => _fehler = e.text);
    } on KeineVerbindung {
      if (mounted) {
        setState(() => _fehler = teilenTexte(context).geteiltOffline);
      }
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _waehleTag() async {
    final jetzt = DateTime.now();
    final t = await showDatePicker(
      context: context,
      initialDate: _ab ?? DateTime(jetzt.year, 1, 1),
      firstDate: DateTime(1800),
      lastDate: DateTime(jetzt.year + 1, 12, 31),
    );
    if (t != null && mounted) setState(() => _ab = t);
  }

  @override
  Widget build(BuildContext context) {
    final t = teilenTexte(context);
    final personen = _personen;
    final q = _suche.trim().toLowerCase();
    final passend = personen == null
        ? const <Regelperson>[]
        : ([
            for (final p in personen)
              if (q.isEmpty || p.name.toLowerCase().contains(q)) p,
          ]..sort(
            (a, b) =>
                (_gewaehlt.contains(b.id) ? 1 : 0) -
                (_gewaehlt.contains(a.id) ? 1 : 0),
          ));
    final ort = Localizations.localeOf(context).toString();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.titel, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(widget.hinweis, style: Theme.of(context).textTheme.bodySmall),
          if ((widget.vorher?.fehlend ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(t.regelPersonenFehlen(widget.vorher!.fehlend)),
            ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: t.personSuchen,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (w) => setState(() => _suche = w),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: personen == null
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : passend.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      personen.isEmpty
                          ? t.keinePersonenMitNamen
                          : t.keinePersonGefunden,
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in passend.take(300))
                        CheckboxListTile(
                          dense: true,
                          value: _gewaehlt.contains(p.id),
                          onChanged: (an) => setState(() {
                            if (an ?? false) {
                              _gewaehlt.add(p.id);
                            } else {
                              _gewaehlt.remove(p.id);
                            }
                          }),
                          secondary: CircleAvatar(
                            radius: 16,
                            foregroundImage: p.bild == null
                                ? null
                                : FernBild(
                                    widget.verbindung,
                                    'api/v1/dateien/${p.bild}',
                                  ),
                            child: Text(p.name.characters.first.toUpperCase()),
                          ),
                          title: Text(p.name),
                          subtitle: Text('${p.anzahl}'),
                        ),
                    ],
                  ),
          ),
          if (widget.mitArt) ...[
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(t.regelEine)),
                ButtonSegment(value: true, label: Text(t.regelAlle)),
              ],
              selected: {_alle},
              onSelectionChanged: (w) => setState(() => _alle = w.first),
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(t.aufgenommenAb),
            subtitle: Text(
              _ab == null ? t.jedesDatum : DateFormat.yMd(ort).format(_ab!),
            ),
            onTap: _waehleTag,
            trailing: _ab == null
                ? null
                : IconButton(
                    tooltip: t.entfernen,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _ab = null),
                  ),
          ),
          if (_fehler case final f?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                f,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              if (widget.entfernen case final weg?)
                TextButton(
                  onPressed: _arbeitet ? null : () => _fuehreAus(weg),
                  child: Text(t.automatischAus),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t.abbrechen),
              ),
              FilledButton(
                onPressed: _arbeitet
                    ? null
                    : () {
                        if (_gewaehlt.length > _hoechstens) {
                          setState(() => _fehler = t.regelHoechstens);
                          return;
                        }
                        final namen = {
                          for (final p in personen ?? const <Regelperson>[])
                            p.id: p.name,
                          for (final p
                              in widget.vorher?.personen ??
                                  const <Regelperson>[])
                            p.id: p.name,
                        };
                        _fuehreAus(
                          () => widget.speichern(
                            Regel(
                              personen: [
                                for (final id in _gewaehlt)
                                  Regelperson(id, namen[id] ?? id),
                              ],
                              alle: _alle,
                              ab: _ab,
                            ),
                          ),
                        );
                      },
                child: Text(t.speichern),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Der Knopf „Automatisch füllen“ an einem eigenen Album – nur an einem
/// Server, der es kann. Gefüllt erscheint er ausgefüllt.
class Albumregelknopf extends StatefulWidget {
  const Albumregelknopf({
    super.key,
    required this.verbindung,
    required this.albumId,
    required this.titel,
  });

  final Serververbindung verbindung;
  final String albumId;
  final String titel;

  @override
  State<Albumregelknopf> createState() => _AlbumregelknopfState();
}

class _AlbumregelknopfState extends State<Albumregelknopf> {
  var _kann = false;
  Regel? _regel;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final r = await albumregel(widget.verbindung, widget.albumId);
      if (mounted) {
        setState(() {
          _kann = true;
          _regel = r;
        });
      }
    } on Object {
      // Älterer Server oder kein Netz: dann ohne Knopf.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_kann) return const SizedBox.shrink();
    final t = teilenTexte(context);
    final r = _regel;
    return IconButton(
      tooltip: r == null
          ? t.automatischFuellen
          : '${t.automatischFuellen}: ${regelText(context, r)}',
      isSelected: r != null,
      icon: const Icon(Icons.auto_awesome_outlined),
      selectedIcon: const Icon(Icons.auto_awesome),
      onPressed: () async {
        final anders = await albumAutomatischFuellen(
          context,
          widget.verbindung,
          albumId: widget.albumId,
          titel: widget.titel,
          vorher: r,
        );
        if (anders) await _lade();
      },
    );
  }
}
