import 'dart:async';
import 'dart:typed_data';

import 'package:abgleich_ui/fotokammer_dienst.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Die Fotokammer am Handy (#350): unterwegs sichten, was schon auf dem
/// Server liegt, aber noch nicht in der Bibliothek.
///
/// Antippen öffnet ein Foto, langes Drücken wählt aus. Beim Sichten vergibt
/// man Sterne oder lehnt ab; „Sichtung abschliessen“ verwirft das Abgelehnte
/// und gibt den Rest frei.
class FotokammerSeite extends StatefulWidget {
  const FotokammerSeite({super.key, required this.dienst});

  final Fotokammerdienst dienst;

  @override
  State<FotokammerSeite> createState() => _FotokammerSeiteState();
}

enum _Lage { laedt, serverAlt, fehler, bereit }

class _FotokammerSeiteState extends State<FotokammerSeite> {
  var _lage = _Lage.laedt;
  var _eintraege = <Kammereintrag>[];
  final _auswahl = <String>{};
  String? _fehler;
  var _sichten = false;
  var _arbeitet = false;

  Fotokammerdienst get _d => widget.dienst;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final stufe = await _d.stufe();
      if (stufe < 1) {
        if (mounted) setState(() => _lage = _Lage.serverAlt);
        return;
      }
      final l = await _d.liste();
      if (!mounted) return;
      setState(() {
        _sichten = stufe >= 3;
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

  void _melde(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _umschalten(String id) => setState(() {
    if (!_auswahl.remove(id)) _auswahl.add(id);
  });

  Future<void> _mitArbeit(Future<void> Function() was) async {
    final t = AppTexte.of(context);
    setState(() => _arbeitet = true);
    try {
      await was();
    } on Object catch (e) {
      if (mounted) _melde(t.kammerFehler('$e'));
    } finally {
      if (mounted) setState(() => _arbeitet = false);
      _auswahl.clear();
      await _lade();
    }
  }

  Future<void> _freigeben() => _mitArbeit(() async {
    final t = AppTexte.of(context);
    final r = await _d.freigeben(_auswahl.toList());
    if (mounted) _melde(t.kammerFreigegeben(r.neu + r.schonDa));
  });

  Future<void> _verwerfen() async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.kammerVerwerfenTitel(_auswahl.length)),
        content: Text(t.kammerVerwerfenText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.kammerVerwerfen),
          ),
        ],
      ),
    );
    if (ja != true) return;
    await _mitArbeit(() => _d.verwerfen(_auswahl.toList()));
  }

  /// Frisch vom Server: Verworfen wird endgültig, und ein anderes Gerät
  /// kann das Urteil inzwischen geändert haben.
  Future<void> _abschliessen() async {
    final t = AppTexte.of(context);
    // Freigegeben wird nur, was hier schon zu sehen war (#382).
    final gesehen = {for (final e in _eintraege) e.id};
    final List<Kammereintrag> stand;
    try {
      await _d.urteileAngekommen();
      stand = await _d.liste();
    } on Object catch (e) {
      _melde(t.kammerFehler('$e'));
      return;
    }
    if (!mounted) return;
    setState(() => _eintraege = stand);
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
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.kammerAbschliessen),
          ),
        ],
      ),
    );
    if (ja != true) return;
    await _mitArbeit(() async {
      // Erst freigeben: Scheitert das, ist noch nichts gelöscht.
      final r = await _d.freigeben(rest);
      if (r.gescheitert.isNotEmpty) {
        if (mounted) _melde(t.kammerFehler(r.gescheitert.values.join('; ')));
        return;
      }
      await _d.verwerfen(weg, nurAbgelehnte: true);
      if (mounted) _melde(t.kammerFreigegeben(r.neu + r.schonDa));
    });
  }

  Future<void> _oeffne(int i) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _Kammerbetrachter(
          dienst: _d,
          eintraege: _eintraege,
          start: i,
          sichten: _sichten,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final auswahl = _auswahl.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          auswahl ? t.kammerAusgewaehlt(_auswahl.length) : t.kammerTitel,
        ),
        actions: [
          if (_eintraege.any((e) => e.abgelehnt))
            IconButton(
              tooltip: t.kammerAbschliessen,
              onPressed: _arbeitet ? null : _abschliessen,
              icon: const Icon(Icons.done_all),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_arbeitet) const LinearProgressIndicator(),
          Expanded(child: _inhalt(t)),
        ],
      ),
      bottomNavigationBar: !auswahl
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _arbeitet ? null : _verwerfen,
                        child: Text(t.kammerVerwerfen),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _arbeitet ? null : _freigeben,
                        child: Text(t.kammerFreigeben),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _inhalt(AppTexte t) => switch (_lage) {
    _Lage.laedt => const Center(child: CircularProgressIndicator()),
    _Lage.serverAlt => Center(child: Text(t.kammerServerAlt)),
    _Lage.fehler => Center(child: Text(t.kammerFehler(_fehler ?? ''))),
    _Lage.bereit when _eintraege.isEmpty => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(t.kammerLeer, textAlign: TextAlign.center),
      ),
    ),
    _Lage.bereit => RefreshIndicator(
      onRefresh: _lade,
      child: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
        ),
        itemCount: _eintraege.length,
        itemBuilder: (context, i) {
          final e = _eintraege[i];
          return _Kachel(
            key: ValueKey(e.id),
            eintrag: e,
            dienst: _d,
            gewaehlt: _auswahl.contains(e.id),
            antippen: () =>
                _auswahl.isNotEmpty ? _umschalten(e.id) : _oeffne(i),
            halten: () => _umschalten(e.id),
          );
        },
      ),
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
    required this.halten,
  });

  final Kammereintrag eintrag;
  final Fotokammerdienst dienst;
  final bool gewaehlt;
  final VoidCallback antippen;
  final VoidCallback halten;

  @override
  State<_Kachel> createState() => _KachelState();
}

class _KachelState extends State<_Kachel> {
  late final Future<Uint8List?> _bild = widget.eintrag.hatBild
      ? widget.dienst.bild(widget.eintrag.id, klein: true)
      : Future.value();

  @override
  Widget build(BuildContext context) {
    final e = widget.eintrag;
    final farbe = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: widget.antippen,
      onLongPress: widget.halten,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: farbe.surfaceContainerHighest,
            child: FutureBuilder<Uint8List?>(
              future: _bild,
              builder: (context, s) => switch (s.data) {
                final b? => Opacity(
                  opacity: e.abgelehnt ? 0.35 : 1,
                  child: Image.memory(b, fit: BoxFit.cover),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
          if (e.abgelehnt)
            const Positioned(
              left: 4,
              top: 4,
              child: Icon(Icons.block, color: Colors.redAccent, size: 18),
            ),
          if (e.sterne > 0)
            Positioned(
              right: 4,
              bottom: 2,
              child: Text(
                '★' * e.sterne,
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 11,
                  shadows: [Shadow(blurRadius: 3)],
                ),
              ),
            ),
          if (widget.gewaehlt)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: farbe.primary, width: 3),
                ),
              ),
            ),
          if (widget.gewaehlt)
            Positioned(
              right: 4,
              top: 4,
              child: Icon(Icons.check_circle, color: farbe.primary, size: 20),
            ),
        ],
      ),
    );
  }
}

/// Ein Foto gross: wischen blättert, zwei Finger zoomen, unten Sterne und
/// Ablehnen.
class _Kammerbetrachter extends StatefulWidget {
  const _Kammerbetrachter({
    required this.dienst,
    required this.eintraege,
    required this.start,
    required this.sichten,
  });

  final Fotokammerdienst dienst;
  final List<Kammereintrag> eintraege;
  final int start;
  final bool sichten;

  @override
  State<_Kammerbetrachter> createState() => _KammerbetrachterState();
}

class _KammerbetrachterState extends State<_Kammerbetrachter> {
  late final _seiten = PageController(initialPage: widget.start);
  late var _i = widget.start;

  /// Solange gezoomt ist, verschiebt ein Wischen das Bild statt zu blättern.
  var _gezoomt = false;

  @override
  void dispose() {
    _seiten.dispose();
    super.dispose();
  }

  /// Zeigt das Urteil sofort; scheitert das Speichern, gilt wieder das alte.
  Future<void> _urteile(Kammereintrag e, {int? sterne, bool? abgelehnt}) async {
    final i = widget.eintraege.indexWhere((x) => x.id == e.id);
    if (i < 0) return;
    final bote = ScaffoldMessenger.of(context);
    final t = AppTexte.of(context);
    setState(() {
      widget.eintraege[i] = e.mit(sterne: sterne, abgelehnt: abgelehnt);
    });
    try {
      await widget.dienst.sichten([e.id], sterne: sterne, abgelehnt: abgelehnt);
    } on Object catch (x) {
      if (mounted) setState(() => widget.eintraege[i] = e);
      bote.showSnackBar(SnackBar(content: Text(t.kammerFehler('$x'))));
    }
  }

  void _ablehnen(Kammereintrag e) {
    final jetzt = !e.abgelehnt;
    unawaited(_urteile(e, abgelehnt: jetzt, sterne: jetzt ? 0 : null));
    if (jetzt && _i < widget.eintraege.length - 1) {
      _seiten.nextPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final e = widget.eintraege[_i];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(e.name, style: const TextStyle(fontSize: 15)),
        actions: [
          Center(child: Text('${_i + 1} / ${widget.eintraege.length}')),
          const SizedBox(width: 12),
        ],
      ),
      body: PageView.builder(
        controller: _seiten,
        physics: _gezoomt ? const NeverScrollableScrollPhysics() : null,
        itemCount: widget.eintraege.length,
        onPageChanged: (i) => setState(() {
          _i = i;
          _gezoomt = false;
        }),
        itemBuilder: (context, i) => _Bild(
          key: ValueKey(widget.eintraege[i].id),
          eintrag: widget.eintraege[i],
          dienst: widget.dienst,
          gezoomt: (z) {
            if (z != _gezoomt) setState(() => _gezoomt = z);
          },
        ),
      ),
      bottomNavigationBar: !widget.sichten
          ? null
          : SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var n = 1; n <= 5; n++)
                    IconButton(
                      tooltip: '$n',
                      color: Colors.amber,
                      onPressed: () => _urteile(
                        e,
                        sterne: e.sterne == n ? 0 : n,
                        abgelehnt: false,
                      ),
                      icon: Icon(
                        n <= e.sterne ? Icons.star : Icons.star_border,
                      ),
                    ),
                  IconButton(
                    tooltip: t.kammerAblehnen,
                    color: e.abgelehnt ? Colors.redAccent : Colors.white70,
                    onPressed: () => _ablehnen(e),
                    icon: const Icon(Icons.block),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Die Vorschau; beim Hineinzoomen die volle Auflösung, wie am Rechner.
class _Bild extends StatefulWidget {
  const _Bild({
    super.key,
    required this.eintrag,
    required this.dienst,
    required this.gezoomt,
  });

  final Kammereintrag eintrag;
  final Fotokammerdienst dienst;
  final ValueChanged<bool> gezoomt;

  @override
  State<_Bild> createState() => _BildState();
}

class _BildState extends State<_Bild> {
  final _zoom = TransformationController();
  late final Future<Uint8List?> _vorschau = widget.eintrag.hatBild
      ? widget.dienst.bild(widget.eintrag.id, klein: false)
      : Future.value();
  Uint8List? _voll;
  var _geholt = false;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_zoomGeaendert);
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _zoomGeaendert() {
    final gross = _zoom.value.getMaxScaleOnAxis() > 1.05;
    widget.gezoomt(gross);
    if (gross && !_geholt && widget.eintrag.hatBild) {
      _geholt = true;
      unawaited(_holeVollbild());
    }
  }

  Future<void> _holeVollbild() async {
    Uint8List? b;
    try {
      b = await widget.dienst.vollbild(widget.eintrag.id);
    } on Object {
      // Die Vorschau steht ja da.
    }
    if (mounted && b != null) setState(() => _voll = b);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _vorschau,
    builder: (context, s) => switch (s.data) {
      final b? => InteractiveViewer(
        transformationController: _zoom,
        maxScale: 8,
        child: SizedBox.expand(
          child: Opacity(
            opacity: widget.eintrag.abgelehnt ? 0.45 : 1,
            child: Image.memory(
              _voll ?? b,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
      null when s.connectionState == ConnectionState.done => Center(
        child: Text(
          AppTexte.of(context).kammerKeineVorschau,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
      null => const Center(child: CircularProgressIndicator()),
    },
  );
}
