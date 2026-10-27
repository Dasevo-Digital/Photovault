import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/stammbaum.dart';
import 'package:kern/services/stammbaumansicht.dart';
import 'package:kern/services/verwandtschaftstext.dart';
import 'package:kern/services/zierbaum.dart';
import 'package:zierbild/zierbaum_farben.dart';
import 'package:zierbild/zierbaum_maler.dart';
import 'package:zierbild/zierbaum_schild.dart';

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

  /// Wie weit der Baum reicht (#233) – `null`, solange hier nichts
  /// gewählt ist: dann gilt, was am Rechner zuletzt eingestellt war.
  int? _oben, _unten;
  String? _kreis;
  late Future<Stammbaumansicht> _daten = _lade();

  Future<Stammbaumansicht> _lade() => stammbaumansicht(
    widget.sitzung.db,
    fokus: _fokus,
    oben: _oben,
    unten: _unten,
    kreis: _kreis,
  );

  void _neu(void Function() aenderung) => setState(() {
    aenderung();
    _daten = _lade();
  });

  void _waehle(String id) => _neu(() => _fokus = id);

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
          // Nur wenn wirklich nichts eingetragen ist – eine enge Wahl
          // lässt die Mitte auch allein stehen.
          if (g != null &&
              g.haushalte.length == 1 &&
              g.haushalte.single.personen.length == 1 &&
              !s.verwandt.contains(s.fokus))
            t.baumKeineVerwandtschaft,
          if (g != null && g.verschwiegen > 0)
            t.baumVerschwiegen(g.verschwiegen),
        ];
        final sortiert = [
          ...s.personen,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        final u = s.umfang;
        DropdownButton<T> wahl<T>(
          T wert,
          List<(T, String)> werte,
          void Function(T) gewaehlt, {
          bool breit = false,
        }) => DropdownButton<T>(
          value: wert,
          isExpanded: breit,
          items: [
            for (final (w, text) in werte)
              DropdownMenuItem(
                value: w,
                child: Text(text, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (w) {
            if (w != null) gewaehlt(w);
          },
        );
        Widget feld(String name, Widget kind) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(name), const SizedBox(width: 6), kind],
        );
        Widget breitesFeld(String name, Widget kind) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name),
            const SizedBox(width: 6),
            Flexible(child: kind),
          ],
        );
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
            if (s.fokus != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: Wrap(
                  spacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    feld(
                      t.lbNachOben,
                      wahl(u.oben, [
                        for (var n = 1; n <= geflechtMaxGenerationen; n++)
                          (n, '$n'),
                      ], (w) => _neu(() => _oben = w)),
                    ),
                    feld(
                      t.lbNachUnten,
                      wahl(u.unten, [
                        for (var n = 0; n <= geflechtMaxGenerationen; n++)
                          (n, '$n'),
                      ], (w) => _neu(() => _unten = w)),
                    ),
                    // Die längste Wahl darf schrumpfen: „Mit angeheirateten
                    // Familien" passt auf ein schmales Telefon nicht neben
                    // „Kreis" und lief rechts über den Rand.
                    breitesFeld(
                      t.lbKreis,
                      wahl(breit: true, u.kreis, [
                        (Verwandtenkreis.linie, t.lbDirekteLinie),
                        (Verwandtenkreis.geschwister, t.lbMitGeschwistern),
                        (Verwandtenkreis.alle, t.baumKreisAngeheiratet),
                        (Verwandtenkreis.cousins, t.baumKreisCousins),
                        (
                          Verwandtenkreis.cousinsZweitenGrades,
                          t.baumKreisCousinsZweitenGrades,
                        ),
                      ], (w) => _neu(() => _kreis = w.name)),
                    ),
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
                  // Eine andere Person in der Mitte oder ein anderer
                  // Umfang: neu einpassen.
                  key: ValueKey((s.fokus, u)),
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

/// Wie weit der Baum sich wegzoomen lässt und wie nah heran – dieselben
/// Grenzen wie am Rechner und im Browser.
const _kleinsterZoom = 0.25;
const _groessterZoom = 3.0;
const _zoomschritt = 1.25;

/// Der Zierbaum wie am Rechner (#234): Grund, Stamm, Äste und Ranken aus
/// [ZierbaumMaler], darüber die Schilder aus [Zierbaumschild] – derselbe
/// Code wie dort, nur das Porträt kommt vom Server.
class _BaumState extends State<_Baum> {
  final _steuerung = TransformationController();
  Size? _eingepasstFuer;

  @override
  void dispose() {
    _steuerung.dispose();
    super.dispose();
  }

  Sitzung get sitzung => widget.sitzung;
  Stammbaumansicht get ansicht => widget.ansicht;

  /// Erst den ganzen Baum einmitten; fällt das Schild der Mitte dabei aus
  /// dem Bild, auf dieses Schild rücken – wie am Rechner und im Browser.
  void _ersterBlick(Zierbaumplan plan, Size fenster) {
    var x = fenster.width / 2 - plan.breite / 2;
    var y = fenster.height / 2 - plan.hoehe / 2;
    final s = plan.schilder.where((k) => k.personId == ansicht.fokus);
    if (s.isNotEmpty) {
      final k = s.first;
      final drin =
          x + k.links >= 0 &&
          y + k.oben >= 0 &&
          x + k.rechts <= fenster.width &&
          y + k.unten <= fenster.height;
      if (!drin) {
        x = fenster.width / 2 - k.mitteX;
        y = fenster.height / 2 - k.mitteY;
      }
    }
    _steuerung.value = Matrix4.translationValues(x, y, 0);
  }

  void _zoomen(double faktor, Size fenster) {
    final alt = _steuerung.value.getMaxScaleOnAxis();
    final neu = (alt * faktor).clamp(_kleinsterZoom, _groessterZoom);
    final k = neu / alt;
    final mx = fenster.width / 2, my = fenster.height / 2;
    _steuerung.value = Matrix4.identity()
      ..translateByDouble(mx, my, 0, 1)
      ..scaleByDouble(k, k, k, 1)
      ..translateByDouble(-mx, -my, 0, 1)
      ..multiply(_steuerung.value);
  }

  /// „Ganz zeigen": eingepasst, aber nie über die eigene Grösse hinaus.
  void _ganz(Zierbaumplan plan, Size fenster) {
    final s = math
        .min(fenster.width / plan.breite, fenster.height / plan.hoehe)
        .clamp(_kleinsterZoom, 1.0);
    _steuerung.value = Matrix4.identity()
      ..translateByDouble(
        (fenster.width - plan.breite * s) / 2,
        (fenster.height - plan.hoehe * s) / 2,
        0,
        1,
      )
      ..scaleByDouble(s, s, s, 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final g = widget.geflecht;
    final nachId = {for (final p in ansicht.personen) p.id: p};
    final plan = ansicht.plan!;
    final farben = Zierbaumfarben.fuer(Theme.of(context).brightness);
    final texte = Verwandtschaftstexte.fuer(
      Localizations.localeOf(context).languageCode,
    );
    const masse = Schildmasse();

    String? bezeichnung(String id) {
      final x = ansicht.schilder[id];
      if (x == null || id == ansicht.fokus) return null;
      final u = x.umweg;
      final grad = x.grad;
      if (u != null) {
        return texte.ueberWeg(
          texte.grad(u.schritt, x.person.geschlecht),
          texte.grad(u.ueberGrad, u.ueber.geschlecht),
          u.ueber.name,
        );
      }
      return grad == null ? null : texte.grad(grad, x.person.geschlecht);
    }

    return LayoutBuilder(
      builder: (context, c) {
        final fenster = Size(c.maxWidth, c.maxHeight);
        if (_eingepasstFuer != fenster) {
          _eingepasstFuer = fenster;
          _ersterBlick(plan, fenster);
        }
        return Stack(
          children: [
            // Der Grund steht still hinter dem Baum und füllt die Fläche.
            Positioned.fill(
              child: CustomPaint(painter: Zierbaumgrund(farben: farben)),
            ),
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _steuerung,
                constrained: false,
                minScale: _kleinsterZoom,
                maxScale: _groessterZoom,
                boundaryMargin: EdgeInsets.symmetric(
                  horizontal: fenster.width,
                  vertical: fenster.height,
                ),
                child: MediaQuery.withNoTextScaling(
                  child: SizedBox(
                    width: plan.breite,
                    height: plan.hoehe,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: ZierbaumMaler(
                              plan: plan,
                              farben: farben,
                              malGrund: false,
                              fokusId: ansicht.fokus,
                            ),
                          ),
                        ),
                        if (ansicht.familienname case final name?)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 28,
                            child: Text(
                              name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: farben.familienname,
                                fontSize: 46,
                                letterSpacing: 2,
                                fontFamily: zierschriftGross,
                              ),
                            ),
                          ),
                        for (final schild in plan.schilder)
                          Positioned(
                            left: schild.links,
                            top: schild.oben,
                            width: schild.breite,
                            height: schild.hoehe,
                            child: _schild(
                              schild.personId,
                              nachId[schild.personId],
                              bezeichnung(schild.personId),
                              farben,
                              masse,
                              g,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x9E12100E),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (symbol, hinweis, tun) in [
                      (
                        Icons.add,
                        t.baumVergroessern,
                        () => _zoomen(_zoomschritt, fenster),
                      ),
                      (
                        Icons.remove,
                        t.baumVerkleinern,
                        () => _zoomen(1 / _zoomschritt, fenster),
                      ),
                      (
                        Icons.fit_screen,
                        t.baumGanzZeigen,
                        () => _ganz(plan, fenster),
                      ),
                    ])
                      IconButton(
                        tooltip: hinweis,
                        color: const Color(0xFFF3E6C8),
                        icon: Icon(symbol),
                        onPressed: tun,
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _schild(
    String id,
    PersonData? person,
    String? bezug,
    Zierbaumfarben farben,
    Schildmasse masse,
    Stammbaumgeflecht g,
  ) {
    final name = person?.name ?? '?';
    final bild = person?.coverFaceCropPath;
    return Semantics(
      button: true,
      label: [name, ?bezug, ?ansicht.schilder[id]?.lebensspanne].join(', '),
      child: Zierbaumschild(
        text: Schildtext(
          name: name,
          verwandtschaft: bezug,
          lebensspanne: ansicht.schilder[id]?.lebensspanne,
        ),
        farben: farben,
        masse: masse,
        istMitte: id == ansicht.fokus,
        weitereOben: g.weitereOben[id] ?? false,
        weitereUnten: g.weitereUnten[id] ?? false,
        onTap: () => widget.waehle(id),
        portrait: SizedBox.square(
          dimension: masse.portraitRadius * 2,
          child: bild == null
              ? CircleAvatar(
                  backgroundColor: farben.schildUnten,
                  child: Icon(
                    Icons.person_outline,
                    size: masse.portraitRadius + 1,
                    color: farben.schildRand,
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: farben.schildUnten,
                    shape: BoxShape.circle,
                  ),
                  child: Personenbild(
                    paths: sitzung.paths,
                    name: name,
                    relativ: bild,
                  ),
                ),
        ),
      ),
    );
  }
}
