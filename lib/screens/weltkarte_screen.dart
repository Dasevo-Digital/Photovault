import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/gebietsgrenzen.dart';
import '../services/ortsuebersicht.dart' show Ortsebene;
import '../services/reisefortschritt.dart';
import '../services/reverse_geocoder.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import 'ortsansicht_screen.dart';
import '../services/meldungsdienst.dart';
import '../widgets/zoomsteuerung.dart';
import '../widgets/mini_location_map.dart'
    show Kachelschicht, buildMapAttribution, kartenHoechsteStufe;
import '../widgets/wisch_zoom.dart';
import '../services/laenderkatalog.dart';

/// Die Welt als Karte: wo du warst, und wo du hinwillst.
///
/// **Ein Klick markiert.** Oben steht, worauf er zielt – Land, Region oder
/// Ort. Was markiert ist, ist ausgemalt; ein zweiter Klick auf dieselbe
/// Fläche nimmt die Marke zurück.
///
/// **Die Karte zeigt zwei verschiedene Dinge und sagt welches.** Was aus
/// den Fotos kommt, ist ein Beleg; was von Hand gesetzt wurde, eine
/// Angabe. Sie sehen deshalb nicht gleich aus – eine Fläche, der man nicht
/// ansieht, woher sie stammt, ist die Sorte Karte, der man nach einem Jahr
/// nicht mehr glaubt.
class WeltkarteScreen extends StatefulWidget {
  final LibraryState library;
  const WeltkarteScreen({super.key, required this.library});

  @override
  State<WeltkarteScreen> createState() => _WeltkarteScreenState();
}

/// Welche Art Marke ein Punkt auf der Karte ist.
enum _Ebene { land, region, ort }

/// Ein Punkt auf der Weltkarte.
class _Kartenpunkt {
  final _Ebene ebene;
  final String schluessel;
  final String name;
  final double breite;
  final double laenge;

  /// Wie viele Aufnahmen dahinterstehen. 0 heisst: nur von Hand gesetzt.
  final int aufnahmen;

  final Markenart? marke;

  const _Kartenpunkt({
    required this.ebene,
    required this.schluessel,
    required this.name,
    required this.breite,
    required this.laenge,
    required this.aufnahmen,
    required this.marke,
  });

  bool get belegt => aufnahmen > 0;
  bool get geplant => marke == Markenart.geplant && !belegt;

  /// Von Hand gesetzt und durch kein Foto belegt.
  bool get vonHand => marke == Markenart.besucht && !belegt;
}

/// Ein Punkt, für den ein Umriss vorliegt.
class _Flaeche {
  final _Kartenpunkt punkt;
  final Gebiet gebiet;
  const _Flaeche(this.punkt, this.gebiet);
}

class _WeltkarteScreenState extends State<WeltkarteScreen> {
  final _karte = MapController();
  List<_Kartenpunkt>? _punkte;
  List<_Flaeche> _flaechen = const [];
  Gebietsgrenzen? _grenzen;

  /// Worauf ein Klick zielt.
  _Ebene _stufe = _Ebene.land;

  /// Ob ein Klick „besucht" oder „geplant" setzt.
  bool _alsGeplant = false;

  final _sichtbar = {_Ebene.land, _Ebene.region, _Ebene.ort};

  @override
  void initState() {
    super.initState();
    _laden();
  }

  /// Ein Zoomschritt über die Knöpfe.
  ///
  /// Selbst geklemmt, weil `move` die Grenze aus den Kartenoptionen
  /// nicht kennt: Ohne die Klemmung zöge der Knopf die Karte über die
  /// höchste Stufe hinaus, für die es Kacheln gibt, und man stünde vor
  /// grauen Flächen.
  void _zoomen(double schritt) {
    final kamera = _karte.camera;
    final grenze = kartenHoechsteStufe(context);
    final neu = (kamera.zoom + schritt).clamp(kamera.minZoom ?? 0.0, grenze);
    if (neu == kamera.zoom) return;
    _karte.move(kamera.center, neu);
  }

  /// Die Umrisse liegen als eigene Datei bei; ohne sie bleibt die Karte
  /// bei Punkten. Deshalb wird ihr Fehlen abgefangen und nicht geworfen.
  Future<Gebietsgrenzen?> _grenzenLaden() async {
    if (_grenzen != null) return _grenzen;
    try {
      final daten = await rootBundle.load('assets/geo/gebiete.bin.gz');
      return _grenzen = Gebietsgrenzen.ausGepackt(
          daten.buffer.asUint8List(daten.offsetInBytes, daten.lengthInBytes));
    } catch (_) {
      return null;
    }
  }

  Future<void> _laden() async {
    final geo = widget.library.geocoder;
    final grenzen = await _grenzenLaden();
    if (geo == null) {
      if (mounted) {
        setState(() {
          _punkte = const [];
          _flaechen = const [];
        });
      }
      return;
    }
    final besucht = await widget.library.db.besuchteOrte();
    final marken = await widget.library.db.alleOrtsmarken();
    if (!mounted) return;
    final punkte = _sammle(
        geo, besucht, marken, Localizations.localeOf(context).languageCode);
    setState(() {
      _punkte = punkte;
      _flaechen = _umrisse(punkte, grenzen);
    });
  }

  /// Zu jedem Punkt seinen Umriss, soweit einer vorliegt.
  ///
  /// Siebzehn der 252 Länder haben keinen – der Vatikan ist zu klein, die
  /// Niederländischen Antillen gibt es nicht mehr. Für die bleibt der
  /// Punkt die einzige Darstellung, und das ist der Grund, warum die
  /// Punkte nicht durch die Flächen ersetzt werden.
  List<_Flaeche> _umrisse(List<_Kartenpunkt> punkte, Gebietsgrenzen? grenzen) {
    if (grenzen == null) return const [];
    final raus = <_Flaeche>[];
    for (final p in punkte) {
      final gebiet = switch (p.ebene) {
        _Ebene.land => grenzen.land(p.schluessel),
        _Ebene.region => grenzen.region(p.schluessel),
        _Ebene.ort => null,
      };
      if (gebiet != null) raus.add(_Flaeche(p, gebiet));
    }
    // Grosse zuerst zeichnen: Sonst deckt Brandenburg Berlin zu.
    raus.sort((a, b) =>
        b.gebiet.vergleichsflaeche.compareTo(a.gebiet.vergleichsflaeche));
    return raus;
  }

  /// Baut aus Fotos und Marken die Punktmenge.
  ///
  /// Fotos zuerst, Marken danach: Eine Marke auf einem Land, aus dem es
  /// ohnehin Fotos gibt, soll den Punkt nicht verdoppeln, sondern ihn
  /// zusätzlich als „von Hand" ausweisen.
  List<_Kartenpunkt> _sammle(
    ReverseGeocoder geo,
    List<Besuchsangabe> besucht,
    List<OrtsmarkenData> marken,
    String sprache,
  ) {
    final aufnahmenJeLand = <String, int>{};
    final regionen = <String, String>{}; // Code -> Name
    final orte = <String, ({String name, String iso})>{};

    for (final a in besucht) {
      final land = a.land;
      if (land == null) continue;
      final iso = geo.isoNachName[land];
      if (iso == null) continue;
      aufnahmenJeLand[iso] = (aufnahmenJeLand[iso] ?? 0) + a.anzahl;
      final region = a.region;
      if (region != null && region.isNotEmpty) {
        final code = geo.regionscodes['$iso|$region'];
        if (code != null) regionen[code] = region;
      }
      final ort = a.ort;
      if (ort != null && ort.isNotEmpty) {
        orte['$iso|$ort'] = (name: ort, iso: iso);
      }
    }

    final landmarken = <String, Markenart>{};
    final regionsmarken = <String, Markenart>{};
    final ortsmarken = <String, Markenart>{};
    for (final m in marken) {
      final wert =
          m.status == 'geplant' ? Markenart.geplant : Markenart.besucht;
      switch (m.art) {
        case 'land':
          landmarken[m.schluessel.toUpperCase()] = wert;
        case 'region':
          regionsmarken[m.schluessel] = wert;
          regionen.putIfAbsent(m.schluessel, () => m.name);
        case 'ort':
          final teile = m.schluessel.split('|');
          if (teile.length < 3) continue;
          final iso = geo.isoNachName[teile[0]] ?? teile[0].toUpperCase();
          ortsmarken['$iso|${teile[2]}'] = wert;
          orte.putIfAbsent(
              '$iso|${teile[2]}', () => (name: teile[2], iso: iso));
      }
    }

    final ergebnis = <_Kartenpunkt>[];

    for (final iso in {...aufnahmenJeLand.keys, ...landmarken.keys}) {
      final punkt = geo.landpunkt(iso);
      if (punkt == null) continue;
      ergebnis.add(_Kartenpunkt(
        ebene: _Ebene.land,
        schluessel: iso,
        // Der angezeigte Name der Marke – auf Deutsch, wo es einen gibt.
        // Der Schlüssel bleibt der Code, gespeichert wird nichts hiervon.
        name: geo.laenderkatalog.nachIso(iso)?.anzeige(sprache) ?? iso,
        breite: punkt.breite,
        laenge: punkt.laenge,
        aufnahmen: aufnahmenJeLand[iso] ?? 0,
        marke: landmarken[iso],
      ));
    }

    for (final e in regionen.entries) {
      final punkt = geo.regionspunkt(e.key);
      if (punkt == null) continue;
      ergebnis.add(_Kartenpunkt(
        ebene: _Ebene.region,
        schluessel: e.key,
        name: e.value,
        breite: punkt.breite,
        laenge: punkt.laenge,
        // Eine Region gilt als belegt, sobald ein Foto sie nennt – die
        // Zahl der Aufnahmen steht am Land, nicht hier.
        aufnahmen: regionsmarken.containsKey(e.key) ? 0 : 1,
        marke: regionsmarken[e.key],
      ));
    }

    for (final e in orte.entries) {
      final punkt = geo.ortspunkt(e.value.iso, e.value.name);
      if (punkt == null) continue;
      ergebnis.add(_Kartenpunkt(
        ebene: _Ebene.ort,
        schluessel: e.key,
        name: e.value.name,
        breite: punkt.breite,
        laenge: punkt.laenge,
        aufnahmen: ortsmarken.containsKey(e.key) ? 0 : 1,
        marke: ortsmarken[e.key],
      ));
    }

    return ergebnis;
  }

  // -------------------------------------------------------------------
  // Der Klick
  // -------------------------------------------------------------------

  /// Ein Tippen auf die Karte – markiert auf der eingestellten Stufe.
  ///
  /// **Der Umriss entscheidet, nicht die nächste Stadt.** Beide Wege
  /// stehen bereit, und sie sind nicht gleich gut: Über den Umriss
  /// gefragt liegt Flensburg in Schleswig-Holstein; über die nächste
  /// Stadt gefragt liegt es dort, wo zufällig die dichteste Stadt steht.
  /// Auf offener See sagt der Umriss „kein Land", die Städtesuche noch
  /// ein Land in dreihundert Kilometern Entfernung.
  Future<void> _klick(ll.LatLng stelle) async {
    final geo = widget.library.geocoder;
    final t = AppTexte.of(context);
    final ziel =
        _ziel(stelle, geo, Localizations.localeOf(context).languageCode);
    if (ziel == null) {
      _sage(t.weltkarteKeinOrt);
      return;
    }

    // Steht dort schon eine Marke von Hand, nimmt derselbe Klick sie weg.
    final vorhanden = _punkte?.where((p) =>
        p.ebene == _stufe &&
        p.schluessel == ziel.schluessel &&
        p.marke != null);
    if (vorhanden != null && vorhanden.isNotEmpty) {
      await widget.library.db.loescheOrtsmarke(_stufe.name, ziel.schluessel);
      await _laden();
      if (mounted) _sage(t.weltkarteMarkeWeggenommen(ziel.anzeige));
      return;
    }

    // Was die Fotos belegen, braucht keinen Haken. Ihn trotzdem zu setzen
    // würde die Herkunft der Angabe verwischen.
    final belegt = _punkte?.any((p) =>
        p.ebene == _stufe && p.schluessel == ziel.schluessel && p.belegt);
    if (belegt == true && !_alsGeplant) {
      _sage(t.weltkarteSchonBelegt(ziel.anzeige));
      return;
    }

    await _setze(_stufe.name, ziel.schluessel, ziel.name,
        breite: ziel.breite, laenge: ziel.laenge);
  }

  /// Worauf der Klick auf der eingestellten Stufe zeigt.
  ///
  /// **Zwei Namen und nicht einer.** [name] ist der englische – er geht
  /// in die Datenbank, weil eine Marke nicht davon abhängen darf, in
  /// welcher Sprache sie gesetzt wurde. [anzeige] ist der übersetzte,
  /// und der gehört in die Meldung: „Marke bei Germany weggenommen" ist
  /// in einer deutschen Oberfläche keine Auskunft, sondern eine Panne.
  ({String schluessel, String name, String anzeige, double? breite,
      double? laenge})? _ziel(
      ll.LatLng stelle, ReverseGeocoder? geo, String sprache) {
    final grenzen = _grenzen;
    final iso = grenzen?.landBei(stelle.latitude, stelle.longitude);
    final treffer = geo?.lookup(stelle.latitude, stelle.longitude);

    switch (_stufe) {
      case _Ebene.land:
        final code = iso ??
            (treffer?.country == null
                ? null
                : geo?.isoNachName[treffer!.country!]);
        if (code == null) return null;
        final land = geo?.laenderkatalog.nachIso(code);
        return (
          schluessel: code,
          name: land?.name ?? code,
          anzeige: land?.anzeige(sprache) ?? code,
          breite: null,
          laenge: null,
        );

      case _Ebene.region:
        final land = iso ??
            (treffer?.country == null
                ? null
                : geo?.isoNachName[treffer!.country!]);
        if (land == null) return null;
        var code =
            grenzen?.regionBei(stelle.latitude, stelle.longitude, imLand: land);
        code ??= treffer?.state == null
            ? null
            : geo?.regionscodes['$land|${treffer!.state}'];
        if (code == null) return null;
        // Der ausgeschriebene Name kommt aus dem Datensatz, nicht aus dem
        // Umriss – die Umrissdatei führt nur Schlüssel.
        final name = _punkte
                ?.where((p) => p.ebene == _Ebene.region && p.schluessel == code)
                .map((p) => p.name)
                .firstOrNull ??
            treffer?.state ??
            code;
        return (
          schluessel: code,
          name: name,
          anzeige: name,
          breite: null,
          laenge: null,
        );

      case _Ebene.ort:
        // Für den Ort gibt es keinen Umriss – hier ist die nächste Stadt
        // die einzige Auskunft. Ohne Land daneben wäre der Schlüssel
        // mehrdeutig: „Springfield" gibt es über zwanzigmal.
        if (treffer == null) return null;
        if (iso == null && treffer.country == null) return null;
        return (
          schluessel:
              '${treffer.country ?? ''}|${treffer.state ?? ''}|${treffer.city}',
          name: treffer.city,
          anzeige: treffer.city,
          breite: stelle.latitude,
          laenge: stelle.longitude,
        );
    }
  }

  void _sage(String text) =>
      melde.hinweis(text);

  Future<void> _setze(String art, String schluessel, String name,
      {double? breite, double? laenge}) async {
    await widget.library.db.setzeOrtsmarke(OrtsmarkenCompanion.insert(
      art: art,
      schluessel: schluessel,
      name: name,
      status: _alsGeplant ? 'geplant' : 'besucht',
      angelegtAm: DateTime.now(),
      breite: Value(breite),
      laenge: Value(laenge),
    ));
    await _laden();
    if (!mounted) return;
    _sage(AppTexte.of(context).weltkarteMarkeGesetzt(name));
  }

  /// Ein Klick auf eine Marke führt in den Ort.
  ///
  /// Vorher stand hier ein Blatt mit zwei Knöpfen zum Markieren. Die
  /// naheliegendere Frage an einen Punkt auf einer Fotokarte ist „was war
  /// hier?", und die beantwortet die Ortsansicht — samt der
  /// Markierknöpfe, die vorher das Blatt trug.
  ///
  /// **Warum das Blatt ganz weg ist und nicht auf den langen Druck
  /// wandert:** Die Marke trägt einen Tooltip, und der verschluckt den
  /// langen Druck selbst. Ein zweiter Weg zum Markieren wäre ohnehin
  /// einer zu viel — auf die freie Fläche zu klicken setzt und nimmt die
  /// Marke weiterhin, und in der Ortsansicht stehen beide Knöpfe.
  void _ortOeffnen(_Kartenpunkt p) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => OrtsansichtScreen(
            library: widget.library,
            ebene: switch (p.ebene) {
              _Ebene.land => Ortsebene.land,
              _Ebene.region => Ortsebene.region,
              _Ebene.ort => Ortsebene.ort,
            },
            // Die Weltkarte führt Orte als „ISO|Ort", die Ortsmarken und
            // die Ortsansicht als „Land|Region|Ort". Umgerechnet wird
            // hier, wo beide Schreibweisen bekannt sind.
            schluessel: p.ebene == _Ebene.ort
                ? _ortsschluessel(p)
                : p.schluessel,
            name: p.name,
          ),
        ))
        .then((_) => _laden());
  }

  /// „DE|Hamburg" wird zu „Germany|Hamburg|Hamburg".
  String _ortsschluessel(_Kartenpunkt p) {
    final geo = widget.library.geocoder;
    final teile = p.schluessel.split('|');
    if (teile.length < 2 || geo == null) return p.schluessel;
    final land = geo.laenderkatalog.nachIso(teile[0])?.name ?? teile[0];
    // Die Region steht im Schlüssel der Karte nicht drin; sie kommt aus
    // dem Punkt, der zu diesem Ort gehört.
    final punkt = geo.ortspunkt(teile[0], teile[1]);
    final region = punkt == null
        ? ''
        : (geo.lookup(punkt.breite, punkt.laenge)?.state ?? '');
    return '$land|$region|${teile[1]}';
  }

  /// Die Namen der drei Ebenen in derselben Reihenfolge wie auf dem
  /// Schirm – Menü und Leiste sollen nicht auseinanderlaufen.
  List<(_Ebene, String)> _ebenennamen(AppTexte t) => [
        (_Ebene.land, t.weltkarteLaender),
        (_Ebene.region, t.weltkarteRegionen),
        (_Ebene.ort, t.weltkarteOrte),
      ];

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final punkte = _punkte;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.weltkarteTitel),
        actions: [
          PopupMenuButton<_Ebene>(
            icon: const Icon(Icons.layers_outlined),
            tooltip: t.weltkarteEbenen,
            onSelected: (ebene) => setState(() {
              if (!_sichtbar.remove(ebene)) _sichtbar.add(ebene);
            }),
            itemBuilder: (_) => [
              for (final (ebene, text) in _ebenennamen(t))
                CheckedPopupMenuItem(
                  value: ebene,
                  checked: _sichtbar.contains(ebene),
                  child: Text(text),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: t.weltkarteLegende,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (blatt) => AlertDialog(
                title: Text(t.weltkarteLegende),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.weltkarteLegendeFotos),
                    const SizedBox(height: AppSpacing.sm),
                    Text(t.weltkarteLegendeHand),
                    const SizedBox(height: AppSpacing.sm),
                    Text(t.weltkarteLegendeGeplant),
                    const SizedBox(height: AppSpacing.md),
                    Text(t.weltkarteOhneUmriss,
                        style: Theme.of(blatt).textTheme.bodySmall),
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(blatt),
                      child: Text(
                          MaterialLocalizations.of(blatt).closeButtonLabel)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: punkte == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Wisch-Zoom aussen herum: Eine Magic Mouse hat kein
                // Rad, und die Kartenbibliothek macht aus einer solchen
                // Geste eine Verschiebung. Siehe [WischZoom].
                WischZoom(
                  steuerung: _karte,
                  groesserZoom: kartenHoechsteStufe(context),
                  child: FlutterMap(
                  mapController: _karte,
                  options: MapOptions(
                    initialCenter: const ll.LatLng(30, 10),
                    initialZoom: 2,
                    maxZoom: kartenHoechsteStufe(context),
                    onTap: (_, stelle) => _klick(stelle),
                  ),
                  children: [
                    const Kachelschicht(),
                    // Nur gezeichnet, nicht bedienbar: Die Frage, welches
                    // Gebiet unter dem Zeiger liegt, beantwortet _klick
                    // selbst – und genauer, als hitNotifier es könnte,
                    // weil dort bei Überschneidung die kleinere Fläche
                    // gewinnt.
                    PolygonLayer(polygons: _polygone(context)),
                    MarkerLayer(markers: [
                      // Länder zuletzt, damit sie über den Orten liegen –
                      // sonst verdeckt eine Stadt ihr eigenes Land.
                      for (final ebene in [
                        _Ebene.ort,
                        _Ebene.region,
                        _Ebene.land
                      ])
                        if (_sichtbar.contains(ebene))
                          for (final p in punkte)
                            if (p.ebene == ebene)
                              Marker(
                                point: ll.LatLng(p.breite, p.laenge),
                                width: 26,
                                height: 26,
                                child: GestureDetector(
                                  onTap: () => _ortOeffnen(p),
                                  child: _Marke(punkt: p),
                                ),
                              ),
                    ]),
                    buildMapAttribution(context),
                  ],
                ),
                ),
                // Über der Karte, aber links von der Legende: Rechts
                // unten sitzt bei flutter_map der Quellenhinweis.
                Positioned(
                  right: 8,
                  bottom: 40,
                  child: Zoomsteuerung(
                    beiNaeher: () => _zoomen(1),
                    beiWeiter: () => _zoomen(-1),
                  ),
                ),
              ],
            ),
      // Unten und nicht als Karte über dem Bild: Die Leiste ist ständig
      // im Gebrauch, und eine Karte in der Ecke verdeckt genau das Land,
      // das man anklicken will.
      bottomNavigationBar: punkte == null
          ? null
          : _Markierleiste(
              stufe: _stufe,
              alsGeplant: _alsGeplant,
              namen: _ebenennamen(t),
              beiStufe: (s) => setState(() => _stufe = s),
              beiGeplant: (an) => setState(() => _alsGeplant = an),
            ),
    );
  }

  /// Die ausgemalten Gebiete.
  ///
  /// **Drei Zustände, zwei Merkmale.** Füllung *und* Rand tragen die
  /// Unterscheidung: belegt ist voll und durchgezogen, von Hand blass und
  /// gepunktet, geplant fast leer und gestrichelt. Nur über den Farbton
  /// getrennt wären es für einen Rotgrünblinden drei gleiche Flächen.
  List<Polygon> _polygone(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final raus = <Polygon>[];
    for (final f in _flaechen) {
      if (!_sichtbar.contains(f.punkt.ebene)) continue;
      final p = f.punkt;
      // Derselbe Farbton wie in der Länderliste: Dort ist „geplant"
      // secondary, „teilweise" tertiary. Zwei Bildschirme, die dieselbe
      // Sache verschieden färben, kosten mehr, als sie einbringen.
      final grundfarbe = p.geplant ? farben.secondary : farben.primary;
      // Eine Region liegt in ihrem Land: Ihre Füllung addiert sich zu
      // dessen. Sie darf deshalb für sich blasser sein.
      final tiefe = p.ebene == _Ebene.region ? 0.6 : 1.0;
      final (fuellung, muster) = switch (p) {
        _ when p.geplant => (
            0.06 * tiefe,
            // Nicht const: der Konstruktor prüft die Längen selbst.
            StrokePattern.dashed(segments: const [8, 6])
          ),
        _ when p.vonHand => (
            0.14 * tiefe,
            const StrokePattern.dotted(spacingFactor: 2)
          ),
        _ => (0.28 * tiefe, const StrokePattern.solid()),
      };
      for (final ring in f.gebiet.ringe) {
        raus.add(Polygon(
          points: [
            for (final punkt in ring) ll.LatLng(punkt.breite, punkt.laenge)
          ],
          color: grundfarbe.withValues(alpha: fuellung),
          borderColor: grundfarbe.withValues(alpha: 0.85),
          borderStrokeWidth: p.ebene == _Ebene.land ? 1.6 : 1.2,
          pattern: muster,
        ));
      }
    }
    return raus;
  }
}

/// Ein Punkt auf der Karte.
///
/// Belegt, von Hand oder geplant unterscheiden sich in **Füllung und
/// Rand**, nicht nur im Farbton: Drei Zustände, die man nur an der Farbe
/// auseinanderhält, sind für einen Rotgrünblinden ein Zustand.
class _Marke extends StatelessWidget {
  final _Kartenpunkt punkt;
  const _Marke({required this.punkt});

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final gross = punkt.ebene == _Ebene.land;
    final groesse = gross ? 18.0 : (punkt.ebene == _Ebene.region ? 13.0 : 10.0);
    final farbe = punkt.geplant ? farben.secondary : farben.primary;
    return Tooltip(
      message: punkt.name,
      child: Center(
        child: Container(
          width: groesse,
          height: groesse,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Geplantes bleibt hohl. Was belegt ist, ist gefüllt.
            color: punkt.geplant ? Colors.transparent : farbe,
            border: Border.all(
              color: punkt.geplant ? farbe : Colors.white,
              width: punkt.geplant ? 2.5 : 1.5,
            ),
          ),
          // Von Hand gesetzt, ohne ein einziges Foto: ein Punkt in der
          // Mitte. Damit sieht man einer Marke an, worauf sie beruht.
          child: punkt.belegt || punkt.geplant
              ? null
              : Center(
                  child: Container(
                    width: groesse / 3,
                    height: groesse / 3,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.white),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Worauf der Klick zielt und was er setzt.
class _Markierleiste extends StatelessWidget {
  final _Ebene stufe;
  final bool alsGeplant;
  final List<(_Ebene, String)> namen;
  final void Function(_Ebene) beiStufe;
  final void Function(bool) beiGeplant;

  const _Markierleiste({
    required this.stufe,
    required this.alsGeplant,
    required this.namen,
    required this.beiStufe,
    required this.beiGeplant,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          // Umbrechen statt abschneiden: In einem schmalen Fenster rutscht
          // der Geplant-Schalter in die zweite Zeile, statt zu verschwinden.
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(t.weltkarteKlickMarkiert,
                  style: Theme.of(context).textTheme.labelLarge),
              SegmentedButton<_Ebene>(
                segments: [
                  for (final (ebene, text) in namen)
                    ButtonSegment(value: ebene, label: Text(text)),
                ],
                selected: {stufe},
                showSelectedIcon: false,
                onSelectionChanged: (wahl) => beiStufe(wahl.first),
              ),
              FilterChip(
                label: Text(t.laenderGeplant),
                selected: alsGeplant,
                visualDensity: VisualDensity.compact,
                onSelected: beiGeplant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
