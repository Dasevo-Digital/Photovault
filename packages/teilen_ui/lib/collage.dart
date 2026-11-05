import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/services/collage.dart';

import 'geteilte_alben.dart';

// Collagen (#301) – wie im Browser (web/app.js, oeffneCollage): eine
// Vorlage wählen, das Format, Lücke, Ecken und Hintergrund, und welches
// Foto vorn steht. Gezeichnet wird am Server oder, am Rechner ohne Server,
// auf dem Rechner selbst; diese Seite fragt nur nach dem Bild.

/// Was gewählt ist.
class Collagewahl {
  const Collagewahl({
    required this.ids,
    this.vorlage = 'raster',
    this.format = Collageformat.quadrat,
    this.abstand = 0.01,
    this.ecken = 0,
    this.hintergrund = 0xFFFFFF,
  });

  /// Die Fotos in der Reihenfolge der Felder.
  final List<String> ids;
  final String vorlage;
  final Collageformat format;
  final double abstand;
  final double ecken;
  final int hintergrund;

  Collagewahl mit({
    List<String>? ids,
    String? vorlage,
    Collageformat? format,
    double? abstand,
    double? ecken,
    int? hintergrund,
  }) => Collagewahl(
    ids: ids ?? this.ids,
    vorlage: vorlage ?? this.vorlage,
    format: format ?? this.format,
    abstand: abstand ?? this.abstand,
    ecken: ecken ?? this.ecken,
    hintergrund: hintergrund ?? this.hintergrund,
  );

  String get farbtext => '#${hintergrund.toRadixString(16).padLeft(6, '0')}';

  /// Wie der Server sie liest (`POST api/v1/collage`).
  Map<String, Object?> json({bool vorschau = false}) => {
    'ids': ids,
    'vorlage': vorlage,
    'format': format.name,
    'abstand': abstand,
    'ecken': ecken,
    'hintergrund': farbtext,
    if (vorschau) 'vorschau': true,
  };
}

/// Zeichnet eine Collage – klein für die Vorschau, sonst gross.
typedef Collagezeichner =
    Future<Uint8List> Function(Collagewahl wahl, {required bool vorschau});

/// Die Vorschau vom Server.
Collagezeichner collageAmServer(Serververbindung v) =>
    (wahl, {required vorschau}) async {
      final r = await v.anfrage(
        'POST',
        'api/v1/collage',
        kopf: const {'content-type': 'application/json'},
        inhalt: utf8.encode(jsonEncode(wahl.json(vorschau: vorschau))),
        zeitlimit: const Duration(minutes: 3),
      );
      if (r.statusCode != 200) throw Serverfehler(r.statusCode, r.body);
      return r.bodyBytes;
    };

/// Lässt den Server die Collage zeichnen und in die Bibliothek legen; gibt
/// die Kennung der neuen Aufnahme.
Future<String> collageAmServerSpeichern(
  Serververbindung v,
  Collagewahl wahl,
) async {
  final d = await v.schicke(
    'api/v1/collage',
    wahl.json(),
    zeitlimit: const Duration(minutes: 5),
  );
  return '${d['aufnahme']}';
}

/// Die Seite zum Zusammenstellen. [speichere] legt die Collage ab; die
/// Seite schliesst sich danach mit `true`.
class Collageseite extends StatefulWidget {
  const Collageseite({
    super.key,
    required this.ids,
    required this.zeichne,
    required this.speichere,
    this.miniatur,
  });

  final List<String> ids;
  final Collagezeichner zeichne;
  final Future<void> Function(Collagewahl wahl) speichere;

  /// Die Miniatur eines Fotos – für die Reihenfolge.
  final ImageProvider? Function(String id)? miniatur;

  @override
  State<Collageseite> createState() => _CollageseiteState();
}

class _CollageseiteState extends State<Collageseite> {
  late Collagewahl _wahl = Collagewahl(ids: widget.ids);
  Uint8List? _bild;
  var _zeichnet = false;
  var _speichert = false;
  String? _fehler;
  Timer? _verzug;
  var _auftrag = 0;

  static const _farben = [0xFFFFFF, 0x000000, 0x2B2B2B, 0xF3EBDD];

  @override
  void initState() {
    super.initState();
    _zeichne();
  }

  @override
  void dispose() {
    _verzug?.cancel();
    super.dispose();
  }

  void _aendere(Collagewahl neu) {
    setState(() => _wahl = neu);
    _verzug?.cancel();
    _verzug = Timer(const Duration(milliseconds: 250), _zeichne);
  }

  Future<void> _zeichne() async {
    final nummer = ++_auftrag;
    setState(() => _zeichnet = true);
    try {
      final bild = await widget.zeichne(_wahl, vorschau: true);
      if (!mounted || nummer != _auftrag) return;
      setState(() {
        _bild = bild;
        _fehler = null;
      });
    } on Object catch (e) {
      if (!mounted || nummer != _auftrag) return;
      setState(
        () => _fehler = switch (e) {
          Serverfehler(:final text) => text,
          KeineVerbindung() => teilenTexte(context).geteiltOffline,
          _ => '$e',
        },
      );
    } finally {
      if (mounted && nummer == _auftrag) setState(() => _zeichnet = false);
    }
  }

  Future<void> _speichern() async {
    setState(() {
      _speichert = true;
      _fehler = null;
    });
    final weg = Navigator.of(context);
    try {
      await widget.speichere(_wahl);
      weg.pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _speichert = false;
        _fehler = switch (e) {
          Serverfehler(:final text) => text,
          KeineVerbindung() => teilenTexte(context).geteiltOffline,
          _ => '$e',
        };
      });
    }
  }

  String _vorlagenname(BuildContext context, String id) {
    final t = teilenTexte(context);
    return switch (id) {
      'reihe' => t.collageReihe,
      'stapel' => t.collageStapel,
      'gross_links' => t.collageGrossLinks,
      'gross_oben' => t.collageGrossOben,
      _ => t.collageRaster,
    };
  }

  String _formatname(BuildContext context, Collageformat f) {
    final t = teilenTexte(context);
    return switch (f) {
      Collageformat.quadrat => t.collageQuadrat,
      Collageformat.quer => t.collageQuer,
      Collageformat.hoch => t.collageHoch,
      Collageformat.story => t.collageStory,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = teilenTexte(context);
    final farben = Theme.of(context).colorScheme;
    final vorlagen = collagevorlagen(_wahl.ids.length);
    final f = _wahl.format;
    final bild = _bild;
    final einstellungen = <Widget>[
      Text(t.collageVorlage, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in vorlagen)
            Tooltip(
              message: _vorlagenname(context, v.id),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _aendere(_wahl.mit(vorlage: v.id)),
                child: Container(
                  width: 56,
                  height: 56,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: v.id == _wahl.vorlage
                          ? farben.primary
                          : farben.outlineVariant,
                      width: v.id == _wahl.vorlage ? 2 : 1,
                    ),
                  ),
                  child: CustomPaint(
                    painter: _Vorlagenbild(v, farben.onSurfaceVariant),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Text(t.collageFormat, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<Collageformat>(
        segments: [
          for (final x in Collageformat.values)
            ButtonSegment(value: x, label: Text(_formatname(context, x))),
        ],
        selected: {f},
        onSelectionChanged: (w) => _aendere(_wahl.mit(format: w.first)),
      ),
      const SizedBox(height: 16),
      Text(t.collageAbstand),
      Slider(
        value: _wahl.abstand,
        max: 0.05,
        divisions: 10,
        onChanged: (w) => _aendere(_wahl.mit(abstand: w)),
      ),
      Text(t.collageEcken),
      Slider(
        value: _wahl.ecken,
        max: 0.1,
        divisions: 10,
        onChanged: (w) => _aendere(_wahl.mit(ecken: w)),
      ),
      Text(t.collageHintergrund),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        children: [
          for (final c in _farben)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _aendere(_wahl.mit(hintergrund: c)),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(0xFF000000 | c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c == _wahl.hintergrund
                        ? farben.primary
                        : farben.outlineVariant,
                    width: c == _wahl.hintergrund ? 3 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
      if (widget.miniatur case final m?) ...[
        const SizedBox(height: 16),
        Text(
          t.collageReihenfolge,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          t.collageReihenfolgeHinweis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (i, id) in _wahl.ids.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    key: ValueKey('collage-$id'),
                    onTap: i == 0
                        ? null
                        : () => _aendere(
                            _wahl.mit(
                              ids: [id, ..._wahl.ids.where((x) => x != id)],
                            ),
                          ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: switch (m(id)) {
                          final ImageProvider b => Image(
                            image: b,
                            fit: BoxFit.cover,
                          ),
                          null => ColoredBox(
                            color: farben.surfaceContainerHighest,
                          ),
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      if (_fehler case final x?)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(x, style: TextStyle(color: farben.error)),
        ),
    ];
    final vorschau = Center(
      child: AspectRatio(
        aspectRatio: f.breite / f.hoehe,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bild != null)
              Image.memory(bild, gaplessPlayback: true, fit: BoxFit.contain)
            else
              ColoredBox(color: farben.surfaceContainerHighest),
            if (_zeichnet) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(t.collage),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _speichert ? null : _speichern,
              child: _speichert
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t.speichern),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 800
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: vorschau,
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: einstellungen,
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SizedBox(height: c.maxHeight * 0.45, child: vorschau),
                  const SizedBox(height: 16),
                  ...einstellungen,
                ],
              ),
      ),
    );
  }
}

/// Die Vorlage als kleines Bild: ihre Felder als Kästchen.
class _Vorlagenbild extends CustomPainter {
  _Vorlagenbild(this.vorlage, this.farbe);

  final Collagevorlage vorlage;
  final Color farbe;

  @override
  void paint(Canvas canvas, Size size) {
    final pinsel = Paint()..color = farbe.withValues(alpha: 0.55);
    for (final f in vorlage.felder) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            f.x * size.width + 1,
            f.y * size.height + 1,
            f.b * size.width - 2,
            f.h * size.height - 2,
          ),
          const Radius.circular(2),
        ),
        pinsel,
      );
    }
  }

  @override
  bool shouldRepaint(_Vorlagenbild old) =>
      old.vorlage != vorlage || old.farbe != farbe;
}
