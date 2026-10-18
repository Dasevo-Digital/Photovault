import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/stammbaum.dart';
import 'package:kern/services/stammbaumansicht.dart';
import 'package:kern/services/zierbaum.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'lebensbaum.dart';

/// Der Weg zum Stammbaum – mit Titelleiste, wie die Seiten der Bibliothek.
Route<void> stammbaumWeg(Sitzung sitzung, {String? fokus}) =>
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(AppTexte.of(context).bibStammbaum)),
        body: Stammbaum(sitzung: sitzung, fokus: fokus),
      ),
    );

/// Der Stammbaum um eine Person – dasselbe Bild wie im Browser (web/app.js,
/// baumSvg): ein Band je Generation, Haushalte nebeneinander, Äste von den
/// Elternhäusern zu den Kindern. Ein Tipp auf eine Person rückt sie in die
/// Mitte; zwei Finger zoomen. Das Geflecht rechnet der Kern
/// (stammbaumansicht.dart), wie für den Server.
class Stammbaum extends StatefulWidget {
  const Stammbaum({super.key, required this.sitzung, this.fokus});

  final Sitzung sitzung;

  /// Die Person in der Mitte; ohne die zuletzt am Rechner gewählte.
  final String? fokus;

  @override
  State<Stammbaum> createState() => _StammbaumState();
}

class _StammbaumState extends State<Stammbaum> {
  late String? _fokus = widget.fokus;
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
                  if (s.fokus != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        lebensbaumWeg(widget.sitzung, fokus: s.fokus),
                      ),
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
                  // Eine andere Person in der Mitte: neu einpassen.
                  key: ValueKey(s.fokus),
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

class _Baum extends StatefulWidget {
  const _Baum({
    super.key,
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
  State<_Baum> createState() => _BaumState();
}

class _BaumState extends State<_Baum> {
  final _steuerung = TransformationController();
  var _eingepasst = false;

  @override
  void dispose() {
    _steuerung.dispose();
    super.dispose();
  }

  Sitzung get sitzung => widget.sitzung;
  Stammbaumansicht get ansicht => widget.ansicht;
  void waehle(String id) => widget.waehle(id);

  @override
  Widget build(BuildContext context) {
    final g = widget.geflecht;
    final nachId = {for (final p in ansicht.personen) p.id: p};
    // Die Plätze rechnet der Kern wie für den Rechner (zierbaumplan):
    // Kinder unter ihren Elternhäusern statt der Reihe nach.
    final plan = ansicht.plan!;
    final gesamt = plan.breite;
    final hoehe = plan.hoehe;
    final farben = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        // Zu Beginn der ganze Baum in der Breite – heranzoomen geht mit
        // zwei Fingern.
        if (!_eingepasst) {
          _eingepasst = true;
          final massstab = math.min(1.0, c.maxWidth / gesamt);
          _steuerung.value = Matrix4.diagonal3Values(massstab, massstab, 1);
        }
        return InteractiveViewer(
          transformationController: _steuerung,
          constrained: false,
          minScale: 0.2,
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
                      plan: plan,
                      linie: farben.onSurfaceVariant,
                      paar: farben.primary,
                    ),
                  ),
                ),
                for (final schild in plan.schilder)
                  Positioned(
                    left: schild.links,
                    top: schild.oben - 20,
                    width: schild.breite,
                    height: schild.hoehe + 40,
                    child: _Karte(
                      sitzung: sitzung,
                      person: nachId[schild.personId],
                      fokus: schild.personId == ansicht.fokus,
                      oben: g.weitereOben[schild.personId] ?? false,
                      unten: g.weitereUnten[schild.personId] ?? false,
                      onTap: () => waehle(schild.personId),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Aeste extends CustomPainter {
  _Aeste({required this.plan, required this.linie, required this.paar});

  final Zierbaumplan plan;
  final Color linie;
  final Color paar;

  @override
  void paint(Canvas canvas, Size size) {
    final ast = Paint()
      ..color = linie
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    // Vom Schild oben in einer Kurve zur Mitte des Elternhauses – wie im
    // Browser und am Rechner.
    for (final a in plan.aeste) {
      canvas.drawPath(
        Path()
          ..moveTo(a.vonX, a.vonY)
          ..cubicTo(a.vonX, a.steuer1Y, a.nachX, a.steuer2Y, a.nachX, a.nachY),
        ast,
      );
    }
    // Partner: auf Höhe der Bilder verbunden.
    final p = Paint()
      ..color = paar
      ..strokeWidth = 2;
    for (final b in plan.baender) {
      final y = b.y - stammbaumMasse.schildHoehe / 2 + 46;
      canvas.drawLine(Offset(b.vonX, y), Offset(b.nachX, y), p);
    }
  }

  @override
  bool shouldRepaint(_Aeste alt) =>
      alt.plan != plan || alt.linie != linie || alt.paar != paar;
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
