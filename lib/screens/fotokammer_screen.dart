import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/fotokammer_dienst.dart';
import '../services/groessentext.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/einfuegbares_menue.dart';
import '../widgets/empty_state.dart';
import '../widgets/mini_location_map.dart';
import '../widgets/selection_action_bar.dart' show confirmDialog;
import '../widgets/star_rating.dart';
import 'home_shell.dart' show Hauptbereich;

/// Legt [ids] aus der Zeitleiste zurück in die Fotokammer (#337) – nach
/// einer Rückfrage, die sagt, was dabei geschieht. Gibt zurück, ob etwas
/// hineinkam.
Future<bool> inDieFotokammer(
  BuildContext context,
  LibraryState library,
  List<String> ids,
) async {
  final d = library.fotokammer;
  if (d == null || ids.isEmpty) return false;
  final t = AppTexte.of(context);
  final bote = ScaffoldMessenger.of(context);
  if (!await d.moeglich(stufe: 2)) {
    bote.showSnackBar(SnackBar(content: Text(t.kammerServerAlt)));
    return false;
  }
  if (!context.mounted) return false;
  final ja = await confirmDialog(
    context,
    t.kammerAufnehmenTitel(ids.length),
    t.kammerAufnehmenText,
    bestaetigen: t.auswInDieKammer,
  );
  if (!ja) return false;
  try {
    final r = await d.aufnehmen(ids);
    final gruende = {
      for (final g in r.gescheitert.values)
        switch (g) {
          'unbekannt' => t.kammerUnbekannt,
          'gesperrt' => t.kammerGesperrt,
          final String text => text,
          null => t.importFehlerUnbekannt,
        },
    };
    bote.showSnackBar(
      SnackBar(
        content: Text(
          [
            t.kammerAufgenommen(r.neu),
            if (r.gescheitert.isNotEmpty)
              t.kammerNichtAufgenommen(
                r.gescheitert.length,
                gruende.join('; '),
              ),
          ].join(' · '),
        ),
        action: r.neu > 0
            ? SnackBarAction(
                label: t.importZurKammer,
                onPressed: () => library.zeigeBereich(Hauptbereich.fotokammer),
              )
            : null,
      ),
    );
    return r.neu > 0;
  } on Object catch (e) {
    bote.showSnackBar(SnackBar(content: Text(t.kammerFehler('$e'))));
    return false;
  }
}

/// Die Fotokammer (#336): Fotos, die schon auf dem Server liegen, aber
/// erst nach „Freigeben“ in die Bibliothek kommen.
///
/// Sichten geht so: Klicken wählt aus, doppelt klicken öffnet ein Foto
/// gross, dort blättern die Pfeiltasten, und die Leertaste wählt aus. Danach die Auswahl freigeben –
/// und mit „Auswahl umkehren“ den Rest verwerfen.
class FotokammerScreen extends StatefulWidget {
  const FotokammerScreen({super.key, required this.dienst, this.alben});

  /// `null` ohne Server (siehe [LibraryState.fotokammer]).
  final Fotokammerdienst? dienst;

  /// Die vorhandenen Alben, als Vorschläge beim Ziel (#349).
  final Future<List<String>> Function()? alben;

  @override
  State<FotokammerScreen> createState() => _FotokammerScreenState();
}

enum _Lage { laedt, ohneServer, serverAlt, fehler, bereit }

class _FotokammerScreenState extends State<FotokammerScreen> {
  var _lage = _Lage.laedt;
  var _eintraege = <Kammereintrag>[];
  final _auswahl = <String>{};
  String? _fehler;

  /// Während Freigeben oder Verwerfen: wie weit.
  (int, int)? _arbeit;

  /// Ob der Server sich Sterne und Ablehnung merkt (#345).
  var _sichten = false;

  /// Ob er beim Freigeben ein Ziel annimmt (#349).
  var _mitZiel = false;

  /// Die Serie jedes Fotos, das in einer liegt (#348).
  Map<String, Kammerserie> get _serieVon => {
    for (final s in _serien)
      for (final f in s.fotos) f.id: s,
  };

  List<Kammerserie> get _serien => kammerserien(_eintraege);

  /// Gilt für das nächste Freigeben. Danach ist es wieder leer, sonst
  /// landete die nächste Serie unbemerkt im selben Album.
  Kammerziel? _ziel;

  Fotokammerdienst? get _dienst => widget.dienst;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  @override
  void didUpdateWidget(FotokammerScreen alt) {
    super.didUpdateWidget(alt);
    // Die Verbindung zum Server kam erst nach dem Öffnen zustande.
    if (!identical(alt.dienst, widget.dienst)) _lade();
  }

  Future<void> _lade() async {
    final d = _dienst;
    if (d == null) {
      setState(() => _lage = _Lage.ohneServer);
      return;
    }
    setState(() => _lage = _Lage.laedt);
    try {
      final stufe = await d.stufe();
      if (stufe < 1) {
        if (mounted) setState(() => _lage = _Lage.serverAlt);
        return;
      }
      final l = await d.liste();
      if (!mounted) return;
      setState(() {
        _sichten = stufe >= 3;
        _mitZiel = stufe >= 4;
        _eintraege = l;
        _auswahl.retainAll(l.map((e) => e.id));
        _lage = _Lage.bereit;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _fehler = '$e';
          _lage = _Lage.fehler;
        });
      }
    }
  }

  void _umschalten(String id) => setState(() {
    if (!_auswahl.remove(id)) _auswahl.add(id);
  });

  Future<void> _freigeben() async {
    final d = _dienst;
    if (d == null || _auswahl.isEmpty) return;
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    final ids = [
      for (final e in _eintraege)
        if (_auswahl.contains(e.id)) e.id,
    ];
    setState(() => _arbeit = (0, ids.length));
    try {
      final r = await d.freigeben(
        ids,
        ziel: _ziel,
        fortschritt: (n, gesamt) {
          if (mounted) setState(() => _arbeit = (n, gesamt));
        },
      );
      _ziel = null;
      bote.showSnackBar(
        SnackBar(
          content: Text(
            [
              t.kammerFreigegeben(r.neu + r.schonDa),
              if (r.gescheitert.isNotEmpty)
                t.kammerNichtFreigegeben(
                  r.gescheitert.length,
                  r.gescheitert.values.whereType<String>().toSet().join('; '),
                ),
            ].join(' · '),
          ),
        ),
      );
    } on Object catch (e) {
      bote.showSnackBar(SnackBar(content: Text(t.kammerFehler('$e'))));
    } finally {
      if (mounted) setState(() => _arbeit = null);
      _auswahl.clear();
      await _lade();
    }
  }

  Future<void> _verwerfen() async {
    final d = _dienst;
    if (d == null || _auswahl.isEmpty) return;
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.kammerVerwerfenTitel(_auswahl.length)),
        content: Text(t.kammerVerwerfenText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.kammerVerwerfen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    setState(() => _arbeit = (0, _auswahl.length));
    try {
      await d.verwerfen(_auswahl.toList());
    } on Object catch (e) {
      bote.showSnackBar(SnackBar(content: Text(t.kammerFehler('$e'))));
    } finally {
      if (mounted) setState(() => _arbeit = null);
      _auswahl.clear();
      await _lade();
    }
  }

  /// Verwirft alles Abgelehnte und gibt den Rest frei (#345). Erst
  /// freigeben: Scheitert das, ist noch nichts gelöscht.
  Future<void> _abschliessen() async {
    final d = _dienst;
    if (d == null) return;
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    // Frisch vom Server: Verworfen wird endgültig, und ein anderes Gerät
    // kann das Urteil inzwischen geändert haben. Freigegeben wird nur, was
    // hier schon zu sehen war (#382): Was inzwischen hinzukam, hat noch
    // niemand gesichtet, und es bleibt in der Kammer.
    final gesehen = {for (final e in _eintraege) e.id};
    // Auch das Warten zählt als Arbeit: Sonst liesse sich der Knopf
    // währenddessen noch einmal drücken (#382).
    if (_arbeit != null) return;
    setState(() => _arbeit = (0, 0));
    final List<Kammereintrag> stand;
    try {
      stand = await d.listeNachUrteilen();
    } on Object catch (e) {
      if (mounted) setState(() => _arbeit = null);
      bote.showSnackBar(SnackBar(content: Text(t.kammerFehler('$e'))));
      return;
    }
    if (!mounted) return;
    setState(() {
      _eintraege = stand;
      _arbeit = null;
    });
    final (:weg, :rest) = kammerAbschluss(stand, gesehen);
    if (weg.isEmpty) return;
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.kammerAbschliessen),
        content: Text(t.kammerAbschliessenText(weg.length, rest.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.kammerAbschliessen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    setState(() => _arbeit = (0, rest.length));
    try {
      final r = await d.freigeben(
        rest,
        ziel: _ziel,
        fortschritt: (n, gesamt) {
          if (mounted) setState(() => _arbeit = (n, gesamt));
        },
      );
      _ziel = null;
      if (r.gescheitert.isNotEmpty) {
        bote.showSnackBar(
          SnackBar(
            content: Text(
              t.kammerNichtFreigegeben(
                r.gescheitert.length,
                r.gescheitert.values.whereType<String>().toSet().join('; '),
              ),
            ),
          ),
        );
        return;
      }
      // Nur, was dann noch abgelehnt ist: Hebt ein anderes Gerät eine
      // Ablehnung auf, während hier noch freigegeben wird, bleibt das Foto
      // (#358, #382). Die Kammer hat keinen Papierkorb.
      await d.verwerfen(weg, nurAbgelehnte: true);
      bote.showSnackBar(
        SnackBar(content: Text(t.kammerFreigegeben(r.neu + r.schonDa))),
      );
    } on Object catch (e) {
      bote.showSnackBar(SnackBar(content: Text(t.kammerFehler('$e'))));
    } finally {
      if (mounted) setState(() => _arbeit = null);
      _auswahl.clear();
      await _lade();
    }
  }

  Future<void> _vergleiche(List<Kammereintrag> fotos) async {
    final d = _dienst;
    if (d == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _Kammervergleich(
          dienst: d,
          fotos: fotos,
          eintraege: _eintraege,
          sichten: _sichten,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Lehnt in jeder Serie alles ab ausser dem Schärfsten (#348). Nur ein
  /// Vormerken: Weg ist noch nichts, und Fotos mit Sternen bleiben.
  Future<void> _duenneAus() async {
    final d = _dienst;
    if (d == null) return;
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    final mitGemessenen = [
      for (final s in _serien)
        if (s.schaerfstes != null) s,
    ];
    final ids = [
      for (final s in mitGemessenen)
        for (final f in s.fotos)
          if (f.id != s.schaerfstes!.id && f.sterne == 0 && !f.abgelehnt) f.id,
    ];
    if (ids.isEmpty) {
      bote.showSnackBar(SnackBar(content: Text(t.kammerAusduennenNichts)));
      return;
    }
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.kammerAusduennen),
        content: Text(t.kammerAusduennenText(ids.length, mitGemessenen.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.kammerAusduennen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    try {
      await d.sichten(ids, abgelehnt: true);
    } on Object catch (e) {
      bote.showSnackBar(SnackBar(content: Text(t.kammerFehler('$e'))));
    }
    await _lade();
  }

  Future<void> _zielWaehlen() async {
    final alben = await widget.alben?.call() ?? const <String>[];
    if (!mounted) return;
    final neu = await showDialog<Kammerziel>(
      context: context,
      builder: (_) => _ZielDialog(start: _ziel, alben: alben),
    );
    if (neu != null && mounted) {
      setState(() => _ziel = neu.leer ? null : neu);
    }
  }

  String _zieltext(AppTexte t, Kammerziel z) => [
    ?z.album,
    ...z.schlagwoerter,
    if (z.hatOrt) t.kammerZielOrtKurz,
  ].join(', ');

  Future<void> _oeffne(int index) async {
    final d = _dienst;
    if (d == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _Kammerbetrachter(
          dienst: d,
          eintraege: _eintraege,
          start: index,
          auswahl: _auswahl,
          umschalten: _umschalten,
          sichten: _sichten,
          serieVon: _serieVon,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final bytes = _eintraege.fold<int>(0, (n, e) => n + e.groesse);
    final arbeit = _arbeit;
    final frei = arbeit == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _auswahl.isEmpty
              ? t.kammerTitel
              : t.kammerAusgewaehlt(_auswahl.length),
        ),
        bottom: _lage == _Lage.bereit && _eintraege.isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.md,
                      bottom: AppSpacing.sm,
                    ),
                    child: Text(
                      [
                        t.kammerUmfang(_eintraege.length, groessentext(bytes)),
                        if (_ziel case final z?)
                          t.kammerZielAnzeige(_zieltext(t, z)),
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          if (_lage == _Lage.bereit && _eintraege.isNotEmpty) ...[
            IconButton(
              tooltip: _auswahl.length == _eintraege.length
                  ? t.kammerKeine
                  : t.kammerAlle,
              onPressed: frei
                  ? () => setState(() {
                      if (_auswahl.length == _eintraege.length) {
                        _auswahl.clear();
                      } else {
                        _auswahl.addAll(_eintraege.map((e) => e.id));
                      }
                    })
                  : null,
              icon: Icon(
                _auswahl.length == _eintraege.length
                    ? Icons.deselect
                    : Icons.select_all,
              ),
            ),
            IconButton(
              tooltip: t.kammerUmkehren,
              onPressed: frei
                  ? () => setState(() {
                      final alle = _eintraege.map((e) => e.id).toSet();
                      final neu = alle.difference(_auswahl);
                      _auswahl
                        ..clear()
                        ..addAll(neu);
                    })
                  : null,
              icon: const Icon(Icons.flip),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              tooltip: t.kammerVergleichen,
              onPressed: frei && _auswahl.length >= 2 && _auswahl.length <= 4
                  ? () => _vergleiche([
                      for (final e in _eintraege)
                        if (_auswahl.contains(e.id)) e,
                    ])
                  : null,
              icon: const Icon(Icons.compare),
            ),
            if (_sichten && _serien.any((s) => s.schaerfstes != null))
              IconButton(
                tooltip: t.kammerAusduennen,
                onPressed: frei ? _duenneAus : null,
                icon: const Icon(Icons.burst_mode_outlined),
              ),
            if (_mitZiel)
              IconButton(
                tooltip: t.kammerZiel,
                isSelected: _ziel != null,
                onPressed: frei ? _zielWaehlen : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                selectedIcon: const Icon(Icons.bookmark_added),
              ),
            if (_eintraege.any((e) => e.abgelehnt)) ...[
              FilledButton.tonalIcon(
                onPressed: frei ? _abschliessen : null,
                icon: const Icon(Icons.done_all, size: 18),
                label: Text(t.kammerAbschliessen),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            OutlinedButton.icon(
              onPressed: frei && _auswahl.isNotEmpty ? _verwerfen : null,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(t.kammerVerwerfen),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.icon(
              onPressed: frei && _auswahl.isNotEmpty ? _freigeben : null,
              icon: const Icon(Icons.check, size: 18),
              label: Text(t.kammerFreigeben),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          IconButton(
            tooltip: t.kammerNeuLaden,
            onPressed: frei ? _lade : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (arbeit != null)
            LinearProgressIndicator(
              value: arbeit.$2 == 0 ? null : arbeit.$1 / arbeit.$2,
            ),
          Expanded(child: _inhalt(t)),
        ],
      ),
    );
  }

  Widget _inhalt(AppTexte t) => switch (_lage) {
    _Lage.laedt => const Center(child: CircularProgressIndicator()),
    _Lage.ohneServer => EmptyState(
      icon: Icons.move_to_inbox_outlined,
      message: t.kammerOhneServer,
    ),
    _Lage.serverAlt => EmptyState(
      icon: Icons.move_to_inbox_outlined,
      message: t.kammerServerAlt,
    ),
    _Lage.fehler => EmptyState(
      icon: Icons.cloud_off_outlined,
      message: t.kammerFehler(_fehler ?? ''),
      actionLabel: t.kammerNeuLaden,
      onAction: _lade,
    ),
    _Lage.bereit when _eintraege.isEmpty => EmptyState(
      icon: Icons.move_to_inbox_outlined,
      message: t.kammerLeer,
    ),
    _Lage.bereit => GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _eintraege.length,
      itemBuilder: (context, i) {
        final e = _eintraege[i];
        final serie = _serieVon[e.id];
        return _Kachel(
          key: ValueKey(e.id),
          eintrag: e,
          dienst: _dienst!,
          serie: serie?.fotos.length,
          schaerfstes: serie?.schaerfstes?.id == e.id,
          gewaehlt: _auswahl.contains(e.id),
          antippen: () => _umschalten(e.id),
          oeffnen: () => _oeffne(i),
        );
      },
    ),
  };
}

/// Fragt, wohin das Freigegebene soll (#349).
class _ZielDialog extends StatefulWidget {
  const _ZielDialog({required this.start, required this.alben});
  final Kammerziel? start;
  final List<String> alben;

  @override
  State<_ZielDialog> createState() => _ZielDialogState();
}

class _ZielDialogState extends State<_ZielDialog> {
  late final _album = TextEditingController(text: widget.start?.album ?? '');
  late final _schlagwoerter = TextEditingController(
    text: widget.start?.schlagwoerter.join(', ') ?? '',
  );
  late double? _breite = widget.start?.breite;
  late double? _laenge = widget.start?.laenge;

  @override
  void dispose() {
    _album.dispose();
    _schlagwoerter.dispose();
    super.dispose();
  }

  void _fertig() {
    final album = _album.text.trim();
    Navigator.pop(
      context,
      Kammerziel(
        album: album.isEmpty ? null : album,
        schlagwoerter: [
          for (final t in _schlagwoerter.text.split(','))
            if (t.trim().isNotEmpty) t.trim(),
        ],
        breite: _breite,
        laenge: _laenge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(t.kammerZiel),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RawAutocomplete<String>(
                textEditingController: _album,
                focusNode: _albumFokus,
                optionsBuilder: (w) => widget.alben.where(
                  (a) => a.toLowerCase().contains(w.text.toLowerCase()),
                ),
                fieldViewBuilder: (context, c, f, _) => TextField(
                  controller: c,
                  focusNode: f,
                  contextMenuBuilder: einfuegbaresMenue,
                  decoration: InputDecoration(labelText: t.kammerZielAlbum),
                ),
                optionsViewBuilder: (context, waehle, optionen) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 200,
                        maxWidth: 420,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final o in optionen)
                            ListTile(
                              dense: true,
                              title: Text(o),
                              onTap: () => waehle(o),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _schlagwoerter,
                contextMenuBuilder: einfuegbaresMenue,
                decoration: InputDecoration(
                  labelText: t.kammerZielSchlagwoerter,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Erst beim Aufklappen: Die Karte lädt Kacheln aus dem Netz.
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(t.kammerZielOrt),
                children: [
                  MiniLocationMap(
                    latitude: _breite,
                    longitude: _laenge,
                    onLocationChanged: (b, l) => setState(() {
                      _breite = b;
                      _laenge = l;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const Kammerziel()),
          child: Text(t.kammerZielLeeren),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(onPressed: _fertig, child: Text(t.allgSpeichern)),
      ],
    );
  }

  final _albumFokus = FocusNode();
}

class _Kachel extends StatefulWidget {
  const _Kachel({
    super.key,
    required this.eintrag,
    required this.dienst,
    required this.gewaehlt,
    required this.antippen,
    required this.oeffnen,
    this.serie,
    this.schaerfstes = false,
  });
  final Kammereintrag eintrag;
  final Fotokammerdienst dienst;

  /// Wie viele Fotos die Serie hat, in der dieses liegt.
  final int? serie;
  final bool schaerfstes;
  final bool gewaehlt;
  final VoidCallback antippen;
  final VoidCallback oeffnen;

  @override
  State<_Kachel> createState() => _KachelState();
}

class _KachelState extends State<_Kachel> {
  /// Ein Klick wählt sofort aus; folgt ein zweiter rasch, öffnet er das
  /// Foto und nimmt den ersten zurück. Mit `onDoubleTap` wartete jeder
  /// einfache Klick erst ab, ob noch einer kommt.
  DateTime? _letzterKlick;

  void _klick() {
    final jetzt = DateTime.now();
    final vorher = _letzterKlick;
    if (vorher != null && jetzt.difference(vorher) < kDoubleTapTimeout) {
      _letzterKlick = null;
      widget.antippen();
      widget.oeffnen();
    } else {
      _letzterKlick = jetzt;
      widget.antippen();
    }
  }

  late final Future<Uint8List?> _bild = widget.eintrag.hatBild
      ? widget.dienst.bild(widget.eintrag.id, klein: true)
      : Future.value();

  @override
  Widget build(BuildContext context) {
    final farbe = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.eintrag.name,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTap: _klick,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ColoredBox(
                color: farbe.surfaceContainerHighest,
                child: FutureBuilder<Uint8List?>(
                  future: _bild,
                  builder: (context, s) => switch (s.data) {
                    final b? => Opacity(
                      opacity: widget.eintrag.abgelehnt ? 0.35 : 1,
                      child: Image.memory(
                        b,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                    null when s.connectionState == ConnectionState.done => Icon(
                      widget.eintrag.istVideo
                          ? Icons.movie_outlined
                          : Icons.image_not_supported_outlined,
                      color: farbe.onSurfaceVariant,
                    ),
                    null => const SizedBox.shrink(),
                  },
                ),
              ),
            ),
            if (widget.serie case final n?)
              Positioned(
                left: 4,
                bottom: 4,
                child: _Serienmarke(anzahl: n, schaerfstes: widget.schaerfstes),
              ),
            if (widget.eintrag.istVideo)
              const Positioned(
                left: 6,
                bottom: 6,
                child: Icon(Icons.play_circle_outline, color: Colors.white),
              ),
            if (widget.eintrag.abgelehnt)
              const Positioned(
                left: 6,
                top: 6,
                child: Icon(Icons.block, color: Colors.redAccent),
              ),
            if (widget.eintrag.sterne > 0)
              Positioned(
                right: 4,
                bottom: 4,
                child: StarRating(value: widget.eintrag.sterne, size: 12),
              ),
            if (widget.gewaehlt)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: farbe.primary, width: 3),
                ),
              ),
            Positioned(
              right: 6,
              top: 6,
              child: Icon(
                widget.gewaehlt ? Icons.check_circle : Icons.circle_outlined,
                color: widget.gewaehlt ? farbe.primary : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Die Serie in der Ecke der Kachel: wie viele Fotos, und ob dieses das
/// schärfste ist.
class _Serienmarke extends StatelessWidget {
  const _Serienmarke({required this.anzahl, required this.schaerfstes});
  final int anzahl;
  final bool schaerfstes;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Tooltip(
      message: schaerfstes ? t.kammerSchaerfstes : t.kammerSerie(anzahl),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.burst_mode, size: 13, color: Colors.white),
              const SizedBox(width: 2),
              Text(
                '$anzahl',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
              if (schaerfstes) ...[
                const SizedBox(width: 3),
                const Icon(
                  Icons.center_focus_strong,
                  size: 13,
                  color: Colors.amber,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Merkt ein Urteil: zeigt es sofort und speichert es am Server. Scheitert
/// das, gilt wieder das alte.
mixin _Urteil<T extends StatefulWidget> on State<T> {
  Fotokammerdienst get _urteilsdienst;
  List<Kammereintrag> get _urteilsliste;

  Future<void> _urteile(Kammereintrag e, {int? sterne, bool? abgelehnt}) async {
    final i = _urteilsliste.indexWhere((x) => x.id == e.id);
    if (i < 0) return;
    final bote = ScaffoldMessenger.of(context);
    final t = AppTexte.of(context);
    setState(() {
      _urteilsliste[i] = e.mit(sterne: sterne, abgelehnt: abgelehnt);
    });
    try {
      await _urteilsdienst.sichten(
        [e.id],
        sterne: sterne,
        abgelehnt: abgelehnt,
      );
    } on Object catch (x) {
      if (mounted) setState(() => _urteilsliste[i] = e);
      bote.showSnackBar(SnackBar(content: Text(t.kammerFehler('$x'))));
    }
  }
}

/// Zwei bis vier Fotos nebeneinander (#348), alle mit demselben Zoom: Wer
/// bei einem auf das Auge geht, sieht es bei allen. Die Pfeile wechseln das
/// Foto, auf das die Tasten wirken.
class _Kammervergleich extends StatefulWidget {
  const _Kammervergleich({
    required this.dienst,
    required this.fotos,
    required this.eintraege,
    required this.sichten,
  });

  final Fotokammerdienst dienst;
  final List<Kammereintrag> fotos;
  final List<Kammereintrag> eintraege;
  final bool sichten;

  @override
  State<_Kammervergleich> createState() => _KammervergleichState();
}

class _KammervergleichState extends State<_Kammervergleich>
    with _Urteil<_Kammervergleich> {
  @override
  Fotokammerdienst get _urteilsdienst => widget.dienst;

  @override
  List<Kammereintrag> get _urteilsliste => widget.eintraege;

  final _zoom = TransformationController();
  final _fokus = FocusNode();
  final _voll = <String, Uint8List>{};
  late final _vorschauen = {
    for (final f in widget.fotos)
      f.id: f.hatBild
          ? widget.dienst.bild(f.id, klein: false)
          : Future<Uint8List?>.value(),
  };
  var _gewaehlt = 0;
  var _vollGeholt = false;

  /// Der aktuelle Stand eines Fotos: Das Urteil ändert sich hier.
  Kammereintrag _stand(Kammereintrag f) =>
      widget.eintraege.firstWhere((e) => e.id == f.id, orElse: () => f);

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_zoomGeaendert);
  }

  @override
  void dispose() {
    _zoom.dispose();
    _fokus.dispose();
    super.dispose();
  }

  void _zoomGeaendert() {
    if (_vollGeholt || _zoom.value.getMaxScaleOnAxis() <= 1.05) return;
    _vollGeholt = true;
    for (final f in widget.fotos) {
      if (f.hatBild) _holeVollbild(f.id);
    }
  }

  Future<void> _holeVollbild(String id) async {
    try {
      final b = await widget.dienst.vollbild(id);
      if (b != null && mounted) setState(() => _voll[id] = b);
    } on Object {
      // Die Vorschau steht ja da.
    }
  }

  void _gehe(int schritt) => setState(() {
    final n = widget.fotos.length;
    _gewaehlt = (_gewaehlt + schritt + n) % n;
  });

  void _sterne(int n) {
    final e = _stand(widget.fotos[_gewaehlt]);
    _urteile(e, sterne: e.sterne == n ? 0 : n, abgelehnt: false);
  }

  void _ablehnen() {
    final e = _stand(widget.fotos[_gewaehlt]);
    final jetzt = !e.abgelehnt;
    _urteile(e, abgelehnt: jetzt, sterne: jetzt ? 0 : null);
  }

  Widget _spalte(AppTexte t, int i) {
    final f = _stand(widget.fotos[i]);
    final gewaehlt = i == _gewaehlt;
    final beste = widget.fotos
        .map(_stand)
        .where((x) => x.schaerfe != null)
        .fold<Kammereintrag?>(
          null,
          (a, b) => a == null || b.schaerfe! > a.schaerfe! ? b : a,
        );
    return GestureDetector(
      onTap: () => setState(() => _gewaehlt = i),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(
            color: gewaehlt ? Colors.white : Colors.white12,
            width: gewaehlt ? 2 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: _vorschauen[f.id],
              builder: (context, s) => switch (_voll[f.id] ?? s.data) {
                final b? => ClipRect(
                  child: InteractiveViewer(
                    transformationController: _zoom,
                    maxScale: 8,
                    child: SizedBox.expand(
                      child: Opacity(
                        opacity: f.abgelehnt ? 0.45 : 1,
                        child: Image.memory(
                          b,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: Colors.black54,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (beste?.id == f.id)
                        Tooltip(
                          message: t.kammerSchaerfstes,
                          child: const Icon(
                            Icons.center_focus_strong,
                            size: 16,
                            color: Colors.amber,
                          ),
                        ),
                      if (f.abgelehnt)
                        const Icon(
                          Icons.block,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                      if (f.sterne > 0) StarRating(value: f.sterne, size: 12),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final n = widget.fotos.length;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _gehe(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _gehe(-1),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        if (widget.sichten) ...{
          for (final (w, taste) in const [
            (0, LogicalKeyboardKey.digit0),
            (1, LogicalKeyboardKey.digit1),
            (2, LogicalKeyboardKey.digit2),
            (3, LogicalKeyboardKey.digit3),
            (4, LogicalKeyboardKey.digit4),
            (5, LogicalKeyboardKey.digit5),
          ])
            SingleActivator(taste): () => _sterne(w),
          const SingleActivator(LogicalKeyboardKey.keyX): _ablehnen,
        },
      },
      child: Focus(
        focusNode: _fokus,
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(t.kammerVergleichTitel(n)),
          ),
          body: n == 4
              ? Column(
                  children: [
                    for (final zeile in const [
                      [0, 1],
                      [2, 3],
                    ])
                      Expanded(
                        child: Row(
                          children: [
                            for (final i in zeile)
                              Expanded(child: _spalte(t, i)),
                          ],
                        ),
                      ),
                  ],
                )
              : Row(
                  children: [
                    for (var i = 0; i < n; i++) Expanded(child: _spalte(t, i)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Ein Foto gross: Pfeiltasten blättern, die Leertaste wählt aus, Esc
/// schliesst. Dazu das Sichten: 1 bis 5 Sterne, X lehnt ab und geht weiter,
/// U nimmt die Ablehnung zurück.
class _Kammerbetrachter extends StatefulWidget {
  const _Kammerbetrachter({
    required this.dienst,
    required this.eintraege,
    required this.start,
    required this.auswahl,
    required this.umschalten,
    this.sichten = false,
    this.serieVon = const {},
  });
  final Fotokammerdienst dienst;
  final List<Kammereintrag> eintraege;
  final int start;
  final Set<String> auswahl;
  final void Function(String id) umschalten;
  final bool sichten;
  final Map<String, Kammerserie> serieVon;

  @override
  State<_Kammerbetrachter> createState() => _KammerbetrachterState();
}

class _KammerbetrachterState extends State<_Kammerbetrachter>
    with _Urteil<_Kammerbetrachter> {
  @override
  Fotokammerdienst get _urteilsdienst => widget.dienst;

  @override
  List<Kammereintrag> get _urteilsliste => widget.eintraege;

  late var _i = widget.start;
  final _fokus = FocusNode();
  final _zoom = TransformationController();

  /// Für welches Foto die volle Auflösung geholt wurde, und das Ergebnis.
  /// Immer nur für eines: Ein 24-MP-Bild belegt dekodiert rund 100 MB.
  String? _vollFuer;
  Uint8List? _voll;
  var _vollLaedt = false;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_zoomGeaendert);
    _vorladen(widget.start + 1);
  }

  /// Erst beim Hineinzoomen: Zum Durchblättern reicht die Vorschau (#342).
  void _zoomGeaendert() {
    if (_zoom.value.getMaxScaleOnAxis() <= 1.05) return;
    final e = widget.eintraege[_i];
    if (!e.hatBild || _vollFuer == e.id) return;
    _vollFuer = e.id;
    setState(() => _vollLaedt = true);
    _holeVollbild(e.id);
  }

  Future<void> _holeVollbild(String id) async {
    Uint8List? b;
    try {
      b = await widget.dienst.vollbild(id);
    } on Object {
      // Die Vorschau steht ja da.
    }
    if (!mounted || _vollFuer != id) return;
    setState(() {
      _voll = b;
      _vollLaedt = false;
    });
  }

  /// Je Foto eine Future, solange der Betrachter offen ist: Ein
  /// FutureBuilder, der bei jedem Aufbau eine neue bekommt, fängt jedes Mal
  /// wieder beim Warten an.
  final _vorschauen = <String, Future<Uint8List?>>{};

  Future<Uint8List?> _vorschau(Kammereintrag e) => _vorschauen[e.id] ??=
      e.hatBild ? widget.dienst.bild(e.id, klein: false) : Future.value();

  /// Das Foto an [i] schon holen, damit Blättern nicht wartet.
  void _vorladen(int i) {
    if (i < 0 || i >= widget.eintraege.length) return;
    _vorschau(widget.eintraege[i]).ignore();
  }

  @override
  void dispose() {
    _zoom.dispose();
    _fokus.dispose();
    super.dispose();
  }

  /// Die Serie des Fotos nebeneinander, höchstens ihre vier schärfsten.
  Future<void> _serieVergleichen(Kammereintrag e) async {
    final serie = widget.serieVon[e.id];
    if (serie == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _Kammervergleich(
          dienst: widget.dienst,
          fotos: serie.schaerfste(4),
          eintraege: widget.eintraege,
          sichten: widget.sichten,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Sterne heben eine Ablehnung auf; dieselbe Zahl noch einmal löscht sie.
  void _sterne(Kammereintrag e, int n) =>
      _urteile(e, sterne: e.sterne == n ? 0 : n, abgelehnt: false);

  void _ablehnen(Kammereintrag e) {
    final jetzt = !e.abgelehnt;
    _urteile(e, abgelehnt: jetzt, sterne: jetzt ? 0 : null);
    if (jetzt) _gehe(1);
  }

  void _gehe(int schritt) {
    final neu = (_i + schritt).clamp(0, widget.eintraege.length - 1);
    if (neu != _i) {
      setState(() {
        _i = neu;
        _voll = null;
        _vollFuer = null;
        _vollLaedt = false;
      });
      _zoom.value = Matrix4.identity();
    }
    _vorladen(neu + schritt);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final e = widget.eintraege[_i];
    final gewaehlt = widget.auswahl.contains(e.id);
    final sprache = Localizations.localeOf(context).toString();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _gehe(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _gehe(-1),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            setState(() => widget.umschalten(e.id)),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        if (widget.sichten) ...{
          for (final (n, taste) in const [
            (0, LogicalKeyboardKey.digit0),
            (1, LogicalKeyboardKey.digit1),
            (2, LogicalKeyboardKey.digit2),
            (3, LogicalKeyboardKey.digit3),
            (4, LogicalKeyboardKey.digit4),
            (5, LogicalKeyboardKey.digit5),
          ])
            SingleActivator(taste): () => _sterne(e, n),
          const SingleActivator(LogicalKeyboardKey.keyX): () => _ablehnen(e),
          const SingleActivator(LogicalKeyboardKey.keyU): () {
            if (e.abgelehnt) _urteile(e, abgelehnt: false);
          },
        },
        const SingleActivator(LogicalKeyboardKey.keyV): () =>
            _serieVergleichen(e),
      },
      child: Focus(
        focusNode: _fokus,
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              '${e.name} · ${DateFormat.yMd(sprache).add_Hm().format(e.datum)}'
              '${e.modell != null ? ' · ${e.modell}' : ''}',
            ),
            actions: [
              if (widget.sichten) ...[
                Tooltip(
                  message: t.kammerSichtenTasten,
                  child: const Icon(Icons.keyboard_outlined, size: 20),
                ),
                const SizedBox(width: AppSpacing.sm),
                StarRating(
                  value: e.sterne,
                  size: 18,
                  onChanged: (n) => _urteile(e, sterne: n, abgelehnt: false),
                ),
                IconButton(
                  tooltip: t.kammerAblehnen,
                  isSelected: e.abgelehnt,
                  color: Colors.white70,
                  selectedIcon: const Icon(
                    Icons.block,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _ablehnen(e),
                  icon: const Icon(Icons.block),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text('${_i + 1} / ${widget.eintraege.length}'),
              const SizedBox(width: AppSpacing.md),
              FilterChip(
                selected: gewaehlt,
                label: Text(t.kammerAuswaehlenTaste),
                onSelected: (_) => setState(() => widget.umschalten(e.id)),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
          ),
          body: Row(
            children: [
              IconButton(
                color: Colors.white70,
                onPressed: _i > 0 ? () => _gehe(-1) : null,
                icon: const Icon(Icons.chevron_left, size: 36),
              ),
              Expanded(
                child: FutureBuilder<Uint8List?>(
                  key: ValueKey(e.id),
                  future: _vorschau(e),
                  builder: (context, s) => switch (s.data) {
                    final b? => Stack(
                      fit: StackFit.expand,
                      children: [
                        InteractiveViewer(
                          transformationController: _zoom,
                          maxScale: 8,
                          // Füllt die Fläche, damit das Bild beim Wechsel
                          // auf die volle Auflösung nicht springt.
                          child: SizedBox.expand(
                            child: Opacity(
                              opacity: e.abgelehnt ? 0.45 : 1,
                              child: Image.memory(
                                _voll ?? b,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        ),
                        if (_vollLaedt)
                          const Positioned(
                            top: AppSpacing.md,
                            right: AppSpacing.md,
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                      ],
                    ),
                    null when s.connectionState == ConnectionState.done =>
                      Center(
                        child: Text(
                          s.hasError ? '${s.error}' : t.kammerKeineVorschau,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    null => const Center(child: CircularProgressIndicator()),
                  },
                ),
              ),
              IconButton(
                color: Colors.white70,
                onPressed: _i < widget.eintraege.length - 1
                    ? () => _gehe(1)
                    : null,
                icon: const Icon(Icons.chevron_right, size: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
