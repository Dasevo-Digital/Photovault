import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:kern/services/lebensbaum.dart';
import 'package:kern/services/lebensbaum_vorlage.dart';
import 'package:kern/services/lebensbaumansicht.dart';
import 'package:kern/services/verwandtschaftstext.dart';
import 'package:kern/services/stammbaum.dart' show Verwandtenkreis;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zierbild/geometrie_ui.dart';
import 'package:zierbild/lebensbaum_flaeche.dart';
import 'package:zierbild/lebensbaum_maler.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'stammbaum.dart';

/// Der Weg zum Lebensbaum – mit Titelleiste, wie die Seiten der Bibliothek.
Route<void> lebensbaumWeg(Sitzung sitzung, {String? fokus}) =>
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(AppTexte.of(context).baumLebensbaum)),
        body: Lebensbaum(sitzung: sitzung, fokus: fokus),
      ),
    );

/// Der Lebensbaum – dieselbe Anordnung, dieselben Vorlagen und dieselbe
/// Beschriftung wie am Rechner und im Browser (web/lebensbaum.js): Die
/// Anordnung rechnet der Kern (lebensbaumansicht.dart), gemalt wird mit
/// dem Maler des Rechners (Paket zierbild). Ein Tipp auf eine Person setzt
/// sie an den Stamm.
class Lebensbaum extends StatefulWidget {
  const Lebensbaum({super.key, required this.sitzung, this.fokus});

  final Sitzung sitzung;
  final String? fokus;

  @override
  State<Lebensbaum> createState() => _LebensbaumState();
}

class _LebensbaumState extends State<Lebensbaum> {
  late String? _fokus = widget.fokus;
  String? _richtung, _stil, _kreis;
  int? _generationen, _oben, _unten;
  var _portraits = true;
  late Future<Lebensbaumansicht> _daten = _lade();
  final _bild = GlobalKey();

  Future<Lebensbaumansicht> _lade() => lebensbaumansicht(
    widget.sitzung.db,
    fokus: _fokus,
    richtung: _richtung,
    stil: _stil,
    kreis: _kreis,
    generationen: _generationen,
    oben: _oben,
    unten: _unten,
  );

  void _neu(void Function() aenderung) => setState(() {
    aenderung();
    _daten = _lade();
  });

  Future<void> _speichern() async {
    final rand = _bild.currentContext?.findRenderObject();
    if (rand is! RenderRepaintBoundary) return;
    // Zwei Bildpunkte je Einheit der Vorlage – wie im Browser, scharf
    // genug zum Drucken.
    final bild = await rand.toImage(pixelRatio: 2);
    final png = await bild.toByteData(format: ui.ImageByteFormat.png);
    bild.dispose();
    if (png == null) return;
    final datei = File(
      '${(await getTemporaryDirectory()).path}/lebensbaum.png',
    );
    await datei.writeAsBytes(png.buffer.asUint8List(), flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(datei.path)]));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return FutureBuilder<Lebensbaumansicht>(
      future: _daten,
      builder: (context, snap) {
        final l = snap.data;
        if (l == null) return const Center(child: CircularProgressIndicator());
        final bild = l.bild;
        if (bild == null || l.fokus == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(t.baumKeinePersonen, textAlign: TextAlign.center),
            ),
          );
        }
        final sprache = Localizations.localeOf(context).languageCode;
        final texte = Verwandtschaftstexte.fuer(sprache);
        final o = l.optionen;
        final familie = o.richtung == Lebensbaumrichtung.familie;
        final fokusName = l.alle.firstWhere((p) => p.id == l.fokus).name;
        Lebensbaumschild beschriftung(String id) {
          final x = l.personen[id];
          if (x == null) {
            return (name: '?', lebensspanne: null, bezeichnung: null);
          }
          final u = x.umweg;
          final grad = x.grad;
          return (
            name: x.person.name,
            lebensspanne: x.lebensspanne,
            bezeichnung: u != null
                ? texte.ueberWeg(
                    texte.grad(u.schritt, x.person.geschlecht),
                    texte.grad(u.ueberGrad, u.ueber.geschlecht),
                    u.ueber.name,
                  )
                : grad == null
                ? null
                : texte.grad(grad, x.person.geschlecht),
          );
        }

        final sortiert = [
          ...l.alle,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        DropdownButton<T> wahl<T>(
          T wert,
          List<(T, String)> werte,
          void Function(T) gewaehlt,
        ) => DropdownButton<T>(
          value: wert,
          items: [
            for (final (w, text) in werte)
              DropdownMenuItem(value: w, child: Text(text)),
          ],
          onChanged: (w) {
            if (w != null) gewaehlt(w);
          },
        );
        Widget feld(String name, Widget kind) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(name), const SizedBox(width: 6), kind],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Wrap(
                spacing: 14,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  feld(
                    t.baumPerson,
                    DropdownButton<String>(
                      value: l.fokus,
                      items: [
                        for (final p in sortiert)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: (id) {
                        if (id != null) _neu(() => _fokus = id);
                      },
                    ),
                  ),
                  feld(
                    t.lbStil,
                    wahl(o.stil, [
                      (Lebensbaumstil.pergament, t.lbPergament),
                      (Lebensbaumstil.landschaft, t.lbLandschaft),
                      (Lebensbaumstil.wappen, t.lbWappen),
                      (Lebensbaumstil.gold, t.lbGold),
                    ], (w) => _neu(() => _stil = w.name)),
                  ),
                  feld(
                    t.lbZeigt,
                    wahl(o.richtung, [
                      (Lebensbaumrichtung.vorfahren, t.lbVorfahren),
                      (Lebensbaumrichtung.nachkommen, t.lbNachkommen),
                      (Lebensbaumrichtung.paar, t.lbPaar),
                      (Lebensbaumrichtung.familie, t.lbFamilie),
                    ], (w) => _neu(() => _richtung = w.name)),
                  ),
                  if (!familie)
                    feld(
                      t.lbGenerationen,
                      wahl(o.generationen, [
                        for (var n = 2; n <= 6; n++) (n, '$n'),
                      ], (w) => _neu(() => _generationen = w)),
                    ),
                  if (familie) ...[
                    feld(
                      t.lbNachOben,
                      wahl(o.oben, [
                        for (var n = 1; n <= 3; n++) (n, '$n'),
                      ], (w) => _neu(() => _oben = w)),
                    ),
                    feld(
                      t.lbNachUnten,
                      wahl(o.unten, [
                        for (var n = 0; n <= 3; n++) (n, '$n'),
                      ], (w) => _neu(() => _unten = w)),
                    ),
                    feld(
                      t.lbKreis,
                      wahl(o.kreis, [
                        (Verwandtenkreis.linie, t.lbDirekteLinie),
                        (Verwandtenkreis.geschwister, t.lbMitGeschwistern),
                        (Verwandtenkreis.alle, t.lbAlle),
                      ], (w) => _neu(() => _kreis = w.name)),
                    ),
                  ],
                  feld(
                    t.lbPortraits,
                    Switch(
                      value: _portraits,
                      onChanged: (an) => setState(() => _portraits = an),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _speichern,
                    icon: const Icon(Icons.ios_share),
                    label: Text(t.lbSpeichern),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      stammbaumWeg(widget.sitzung, fokus: l.fokus),
                    ),
                    child: Text(t.lbStammbaum),
                  ),
                ],
              ),
            ),
            if (bild.verschwiegen > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Text(
                  t.baumVerschwiegen(bild.verschwiegen),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Expanded(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _bild,
                      child: SizedBox.fromSize(
                        size: bild.vorlage.groesse.alsUi,
                        child: Lebensbaumflaeche(
                          inhalt: bild,
                          beschriftung: beschriftung,
                          titel: texte.titel(
                            l.nachname,
                            kurz: bild.vorlage.untertitel != null,
                          ),
                          untertitel: bild.vorlage.untertitel == null
                              ? null
                              : texte.untertitel(o.richtung, fokusName),
                          beiTipp: (id) {
                            if (id != l.fokus) _neu(() => _fokus = id);
                          },
                          hatPortrait: _portraits
                              ? (id) =>
                                    l.personen[id]?.person.coverFaceCropPath !=
                                    null
                              : null,
                          portraitBild: _portraits
                              ? (id, radius) => Personenbild(
                                  paths: widget.sitzung.paths,
                                  name: l.personen[id]?.person.name ?? '?',
                                  relativ:
                                      l.personen[id]?.person.coverFaceCropPath,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
