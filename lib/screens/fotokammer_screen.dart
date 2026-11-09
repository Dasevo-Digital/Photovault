import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/fotokammer_dienst.dart';
import '../services/groessentext.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/selection_action_bar.dart' show confirmDialog;
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
  const FotokammerScreen({super.key, required this.dienst});

  /// `null` ohne Server (siehe [LibraryState.fotokammer]).
  final Fotokammerdienst? dienst;

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
      if (!await d.moeglich()) {
        if (mounted) setState(() => _lage = _Lage.serverAlt);
        return;
      }
      final l = await d.liste();
      if (!mounted) return;
      setState(() {
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
        fortschritt: (n, gesamt) {
          if (mounted) setState(() => _arbeit = (n, gesamt));
        },
      );
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
                      t.kammerUmfang(_eintraege.length, groessentext(bytes)),
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
        return _Kachel(
          key: ValueKey(e.id),
          eintrag: e,
          dienst: _dienst!,
          gewaehlt: _auswahl.contains(e.id),
          antippen: () => _umschalten(e.id),
          oeffnen: () => _oeffne(i),
        );
      },
    ),
  };
}

class _Kachel extends StatefulWidget {
  const _Kachel({
    super.key,
    required this.eintrag,
    required this.dienst,
    required this.gewaehlt,
    required this.antippen,
    required this.oeffnen,
  });
  final Kammereintrag eintrag;
  final Fotokammerdienst dienst;
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
                    final b? => Image.memory(
                      b,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
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
            if (widget.eintrag.istVideo)
              const Positioned(
                left: 6,
                bottom: 6,
                child: Icon(Icons.play_circle_outline, color: Colors.white),
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

/// Ein Foto gross: Pfeiltasten blättern, die Leertaste wählt aus, Esc
/// schliesst.
class _Kammerbetrachter extends StatefulWidget {
  const _Kammerbetrachter({
    required this.dienst,
    required this.eintraege,
    required this.start,
    required this.auswahl,
    required this.umschalten,
  });
  final Fotokammerdienst dienst;
  final List<Kammereintrag> eintraege;
  final int start;
  final Set<String> auswahl;
  final void Function(String id) umschalten;

  @override
  State<_Kammerbetrachter> createState() => _KammerbetrachterState();
}

class _KammerbetrachterState extends State<_Kammerbetrachter> {
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
                            child: Image.memory(
                              _voll ?? b,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
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
