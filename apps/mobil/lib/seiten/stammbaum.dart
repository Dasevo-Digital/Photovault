import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/stammbaum.dart';
import 'package:kern/services/stammbaumansicht.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Der Stammbaum um eine Person – dasselbe Bild wie im Browser (web/app.js,
/// baumSvg): ein Band je Generation, Haushalte nebeneinander, Äste von den
/// Elternhäusern zu den Kindern. Ein Tipp auf eine Person rückt sie in die
/// Mitte; zwei Finger zoomen. Das Geflecht rechnet der Kern
/// (stammbaumansicht.dart), wie für den Server.
class Stammbaum extends StatefulWidget {
  const Stammbaum({super.key, required this.sitzung, this.lebensbaum});

  final Sitzung sitzung;

  /// Öffnet den Lebensbaum für eine Person – vom Knopf über dem Baum.
  final void Function(String personId)? lebensbaum;

  @override
  State<Stammbaum> createState() => _StammbaumState();
}

// Die Masse des Browsers: Karte, Abstände, Bandhöhe, Rand.
const _kB = 118.0, _kH = 140.0, _abstand = 10.0, _hausAbstand = 36.0;
const _bandH = 200.0, _rand = 24.0;

class _StammbaumState extends State<Stammbaum> {
  String? _fokus;
  late Future<Stammbaumansicht> _daten = _lade();

  Future<Stammbaumansicht> _lade() =>
      stammbaumansicht(widget.sitzung.db, fokus: _fokus);

  void _waehle(String id) => setState(() {
    _fokus = id;
    _daten = _lade();
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return FutureBuilder<Stammbaumansicht>(
      future: _daten,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) return const Center(child: CircularProgressIndicator());
        final g = s.geflecht;
        final farben = Theme.of(context).colorScheme;
        final hinweise = [
          if (g == null) t.baumKeinePersonen,
          if (g != null &&
              g.haushalte.length == 1 &&
              g.haushalte.single.personen.length == 1)
            t.baumKeineVerwandtschaft,
          if (g != null && g.verschwiegen > 0)
            t.baumVerschwiegen(g.verschwiegen),
        ];
        final sortiert = [
          ...s.personen,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Text(t.baumPerson),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: s.fokus,
                      items: [
                        for (final p in sortiert)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              s.verwandt.contains(p.id)
                                  ? p.name
                                  : t.baumOhneVerwandtschaft(p.name),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) _waehle(id);
                      },
                    ),
                  ),
                  if (widget.lebensbaum != null && s.fokus != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => widget.lebensbaum!(s.fokus!),
                      child: Text(t.baumLebensbaum),
                    ),
                  ],
                ],
              ),
            ),
            if (hinweise.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Text(
                  hinweise.join(' '),
                  style: TextStyle(color: farben.onSurfaceVariant),
                ),
              ),
            if (g != null)
              Expanded(
                child: _Baum(
                  sitzung: widget.sitzung,
                  ansicht: s,
                  geflecht: g,
                  waehle: _waehle,
                ),
              ),
          ],
        );
      },
    );
  }
}

typedef _Lage = ({double x, double y, double mitte});

class _Baum extends StatelessWidget {
  const _Baum({
    required this.sitzung,
    required this.ansicht,
    required this.geflecht,
    required this.waehle,
  });

  final Sitzung sitzung;
  final Stammbaumansicht ansicht;
  final Stammbaumgeflecht geflecht;
  final void Function(String) waehle;

  @override
  Widget build(BuildContext context) {
    final g = geflecht;
    final nachId = {for (final p in ansicht.personen) p.id: p};
    final baender = {for (final h in g.haushalte) g.band[h.id] ?? 0}.toList()
      ..sort();
    double breiteVon(Haushalt h) =>
        h.personen.length * _kB + (h.personen.length - 1) * _abstand;
    final bandBreite = <int, double>{
      for (final b in baender)
        b: [
          for (final h in g.haushalte)
            if ((g.band[h.id] ?? 0) == b) breiteVon(h),
        ].fold<double>(0, (s, w) => s + w),
    };
    for (final b in baender) {
      final n = g.haushalte.where((h) => (g.band[h.id] ?? 0) == b).length;
      bandBreite[b] = bandBreite[b]! + (n - 1) * _hausAbstand;
    }
    final gesamt = bandBreite.values.fold<double>(0, math.max) + 2 * _rand;
    final hoehe = baender.length * _bandH + 2 * _rand;
    final lage = <String, _Lage>{};
    final hausLage = <String, ({double mitte, double unten})>{};
    final paare = <Offset>[];
    for (final (zeile, b) in baender.indexed) {
      final y = _rand + zeile * _bandH + 20;
      var x = (gesamt - bandBreite[b]!) / 2;
      for (final h in g.haushalte.where((h) => (g.band[h.id] ?? 0) == b)) {
        final links = x;
        for (final (i, id) in h.personen.indexed) {
          final px = x + i * (_kB + _abstand);
          lage[id] = (x: px, y: y, mitte: px + _kB / 2);
          if (i > 0) paare.add(Offset(px - _abstand, y + 46));
        }
        final breite = breiteVon(h);
        hausLage[h.id] = (mitte: links + breite / 2, unten: y + _kH);
        x += breite + _hausAbstand;
      }
    }
    final aeste = <List<Offset>>[];
    for (final MapEntry(key: kind, value: haeuser)
        in g.elternhaeuserVon.entries) {
      final k = lage[kind];
      if (k == null) continue;
      for (final hid in haeuser) {
        final h = hausLage[hid];
        if (h == null) continue;
        final mitteY = (h.unten + k.y) / 2;
        aeste.add([
          Offset(h.mitte, h.unten),
          Offset(h.mitte, mitteY),
          Offset(k.mitte, mitteY),
          Offset(k.mitte, k.y),
        ]);
      }
    }
    final farben = Theme.of(context).colorScheme;
    return InteractiveViewer(
      constrained: false,
      minScale: 0.3,
      maxScale: 2.5,
      boundaryMargin: const EdgeInsets.all(200),
      child: SizedBox(
        width: gesamt,
        height: hoehe,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _Aeste(
                  aeste: aeste,
                  paare: paare,
                  linie: farben.onSurfaceVariant,
                  paar: farben.primary,
                ),
              ),
            ),
            for (final MapEntry(key: id, value: l) in lage.entries)
              Positioned(
                left: l.x,
                top: l.y - 20,
                width: _kB,
                height: _kH + 40,
                child: _Karte(
                  sitzung: sitzung,
                  person: nachId[id],
                  fokus: id == ansicht.fokus,
                  oben: g.weitereOben[id] ?? false,
                  unten: g.weitereUnten[id] ?? false,
                  onTap: () => waehle(id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Aeste extends CustomPainter {
  _Aeste({
    required this.aeste,
    required this.paare,
    required this.linie,
    required this.paar,
  });

  final List<List<Offset>> aeste;
  final List<Offset> paare;
  final Color linie;
  final Color paar;

  @override
  void paint(Canvas canvas, Size size) {
    final ast = Paint()
      ..color = linie
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final a in aeste) {
      canvas.drawPath(
        Path()
          ..moveTo(a.first.dx, a.first.dy)
          ..lineTo(a[1].dx, a[1].dy)
          ..lineTo(a[2].dx, a[2].dy)
          ..lineTo(a[3].dx, a[3].dy),
        ast,
      );
    }
    final p = Paint()
      ..color = paar
      ..strokeWidth = 2;
    for (final o in paare) {
      canvas.drawLine(o, o.translate(_abstand, 0), p);
    }
  }

  @override
  bool shouldRepaint(_Aeste alt) =>
      alt.aeste != aeste || alt.paare != paare || alt.linie != linie;
}

/// Lange Namen auf zwei Zeilen, am letzten Leerzeichen vor der Grenze –
/// wie im Browser.
List<String> namenszeilen(String name) {
  final zeilen = <String>[];
  var rest = name.trim();
  while (rest.isNotEmpty && zeilen.length < 2) {
    if (rest.length <= 16 || zeilen.length == 1) {
      zeilen.add(rest.length > 16 ? '${rest.substring(0, 15)}…' : rest);
      break;
    }
    final schnitt = rest.lastIndexOf(' ', 16);
    if (schnitt < 4) {
      zeilen.add('${rest.substring(0, 15)}…');
      break;
    }
    zeilen.add(rest.substring(0, schnitt));
    rest = rest.substring(schnitt + 1);
  }
  return zeilen;
}

/// „1950 – 2001“, „1950 –“, „? – 2001“ – wie im Browser.
String lebensjahre(PersonData p) {
  final g = p.geburtsdatum, t = p.sterbedatum;
  if (g == null && t == null) return '';
  return '${g?.year ?? '?'} –${t == null ? '' : ' ${t.year}'}';
}

class _Karte extends StatelessWidget {
  const _Karte({
    required this.sitzung,
    required this.person,
    required this.fokus,
    required this.oben,
    required this.unten,
    required this.onTap,
  });

  final Sitzung sitzung;
  final PersonData? person;
  final bool fokus;
  final bool oben;
  final bool unten;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final p = person;
    final name = p?.name ?? '?';
    final pfeil = TextStyle(color: farben.onSurfaceVariant, fontSize: 12);
    return Column(
      children: [
        SizedBox(height: 20, child: oben ? Text('▲', style: pfeil) : null),
        Expanded(
          child: Material(
            color: farben.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: fokus ? farben.primary : farben.outlineVariant,
                width: fokus ? 3 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                child: Column(
                  children: [
                    SizedBox.square(
                      dimension: 64,
                      child: Personenbild(
                        paths: sitzung.paths,
                        name: name,
                        relativ: p?.coverFaceCropPath,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final z in namenszeilen(name))
                      Text(
                        z,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(fontSize: 12, height: 1.15),
                      ),
                    if (p != null && lebensjahre(p).isNotEmpty)
                      Text(
                        lebensjahre(p),
                        style: TextStyle(
                          fontSize: 11,
                          color: farben.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 20, child: unten ? Text('▼', style: pfeil) : null),
      ],
    );
  }
}
