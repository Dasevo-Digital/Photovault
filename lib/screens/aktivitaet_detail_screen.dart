import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../services/bilddekodierung.dart';
import '../services/wanderobjekte.dart';
import '../services/aktivitaeten.dart';
import '../services/gpx.dart';
import '../services/meldungsdienst.dart';
import '../services/reiseroute.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/zuordnung_auswahlleiste.dart';
import '../widgets/aktivitaetsart_anzeige.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/hoehenprofil.dart';
import '../widgets/namens_dialog.dart';
import '../widgets/routenkarte.dart';
import 'asset_viewer_screen.dart';
import 'aufnahmen_waehlen_screen.dart';
import 'gelaende_screen.dart';

/// Eine einzelne Aktivität.
///
/// Dieselbe Karte wie bei einer Reise, nur kleiner: eine Wanderung ist
/// eine Strecke, und eine Strecke will man sehen. Die Zahl darunter —
/// Dauer und Kilometer — wird aus den Aufnahmen gerechnet und **nicht**
/// gespeichert: Wer ein Bild aus der Aktivität nimmt, soll die Strecke
/// sofort ohne es sehen.
class AktivitaetDetailScreen extends StatefulWidget {
  final LibraryState library;
  final AktivitaetenData aktivitaet;

  const AktivitaetDetailScreen({
    super.key,
    required this.library,
    required this.aktivitaet,
  });

  @override
  State<AktivitaetDetailScreen> createState() => _AktivitaetDetailScreenState();
}

class _AktivitaetDetailScreenState extends State<AktivitaetDetailScreen> {
  late AktivitaetenData _k = widget.aktivitaet;
  List<AssetData> _aufnahmen = const [];
  String? _reisename;
  SpurenData? _spur;
  List<SpurpunkteData> _spurpunkte = const [];

  /// Der Punkt, auf den das Höhenprofil gerade zeigt – für die Marke auf
  /// der Karte.
  int? _stelle;

  bool _laedt = true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final db = widget.library.db;
    final aufnahmen = await db.aufnahmenDerAktivitaet(_k.id);
    final frisch = await db.aktivitaet(_k.id);
    final reise = (frisch ?? _k).reiseId;
    final name = reise == null ? null : (await db.reise(reise))?.name;
    final spur = (await db.spurenDerAktivitaet(_k.id)).firstOrNull;
    final punkte =
        spur == null ? <SpurpunkteData>[] : await db.punkteDerSpur(spur.id);
    if (!mounted) return;
    setState(() {
      _aufnahmen = aufnahmen;
      if (frisch != null) _k = frisch;
      _reisename = name;
      _spur = spur;
      _spurpunkte = punkte;
      _stelle = null;
      _laedt = false;
    });
  }

  /// Die Kennung, wie sie in der Datenbank steht – auch eine selbst
  /// eingetragene Art. Über die Aufzählung zu gehen machte aus
  /// „Konzert" ein „Sonstiges".
  String get _art => _k.art;

  Map<String, AssetData> get _nachId => {for (final a in _aufnahmen) a.id: a};

  List<({double breite, double laenge, DateTime zeit})> get _punkte => [
        for (final a in _aufnahmen)
          if (a.latitude != null && a.longitude != null)
            (breite: a.latitude!, laenge: a.longitude!, zeit: a.fileCreatedAt),
      ];

  List<Routenpunkt> get _route =>
      // Hundert Meter statt eines Kilometers: Auf einer Wanderung ist ein
      // Kilometer die halbe Strecke, und die Linie wäre ein Strich
      // zwischen Anfang und Ende.
      reiseroute(_punkte, mindestabstandKm: 0.1);

  List<Aufenthaltsort> get _orte => aufenthaltsorte([
        for (final a in _aufnahmen)
          if (a.latitude != null && a.longitude != null)
            (
              id: a.id,
              breite: a.latitude!,
              laenge: a.longitude!,
              zeit: a.fileCreatedAt,
              stadt: a.locationCity,
            ),
      ],
          // Zweihundert Meter: Auf fünfzehn Kilometern – dem Mass für
          // eine Reise – wäre die ganze Wanderung ein einziger Pin.
          radiusKm: 0.2);

  double get _streckeKm => strecke(_punkte);

  Duration get _dauer => _k.bis.difference(_k.von);

  /// Die Punkte des Profils – aus der Spur, nicht aus den Fotos.
  ///
  /// **Was das Gerät gemessen hat, ist die Aussage.** Die Fotos ergeben
  /// eine Vermutung über den Weg; die Aufzeichnung ist der Weg.
  List<Profilpunkt> get _profil => profilpunkte([
        for (final p in _spurpunkte)
          (breite: p.breite, laenge: p.laenge, hoehe: p.hoehe),
      ]);

  List<({double breite, double laenge})> get _spurlinie =>
      [for (final p in _spurpunkte) (breite: p.breite, laenge: p.laenge)];

  /// Wo die Marke auf der Karte steht, während jemand über das Profil
  /// fährt.
  ///
  /// Über den mitgeführten Index und nicht über die Strecke: Das Profil
  /// kennt nur die Punkte **mit** Höhe, sein eigener Index ist also
  /// nicht der Index in der Spur.
  ({double breite, double laenge})? get _stelleAufKarte {
    final i = _stelle;
    if (i == null || i >= _profil.length) return null;
    final p = _spurpunkte[_profil[i].index];
    return (breite: p.breite, laenge: p.laenge);
  }

  /// Was die Sprachausgabe vom Profil erfährt. Ein `CustomPaint` ist
  /// für sie sonst eine leere Fläche.
  String _profilbeschreibung(AppTexte t, NumberFormat zahl) {
    final hoehen = [for (final p in _profil) p.hoehe];
    return t.spurProfilBeschreibung(
      zahl.format(_profil.last.km),
      hoehen.reduce((a, b) => a < b ? a : b).round(),
      hoehen.reduce((a, b) => a > b ? a : b).round(),
      (_spur?.aufstieg ?? 0).round(),
    );
  }

  Future<void> _spurHinzufuegen() async {
    final t = AppTexte.of(context);
    if (_spur != null) {
      melde.warnung(t.spurSchonDa);
      return;
    }
    final wahl = await FilePicker.platform.pickFiles(
      dialogTitle: t.gpxDateiWaehlen,
      type: FileType.custom,
      allowedExtensions: const ['gpx'],
    );
    final pfad = wahl?.files.firstOrNull?.path;
    if (pfad == null || !mounted) return;

    List<Rohpunkt> punkte;
    try {
      punkte = liesGpxPunkte(await File(pfad).readAsString());
    } on GpxFehler catch (f) {
      if (!mounted) return;
      melde.fehler(switch (f.grund) {
        GpxAbbruch.keinGpx => t.gpxFehlerKeinGpx,
        GpxAbbruch.ohneZeit => t.gpxFehlerOhneZeit,
        GpxAbbruch.leer => t.gpxFehlerLeer,
      });
      return;
    } on FileSystemException catch (e) {
      if (!mounted) return;
      melde.fehler('$e');
      return;
    }

    final zahlen = spurkennzahlen(punkte);
    final id = const Uuid().v4();
    final name = pfad.split(Platform.pathSeparator).last;
    await widget.library.db.spurAnlegen(
      SpurenCompanion.insert(
        id: id,
        name: name,
        quelle: pfad,
        aktivitaetId: Value(_k.id),
        von: Value(zahlen.von),
        bis: Value(zahlen.bis),
        punktzahl: zahlen.punktzahl,
        laengeKm: zahlen.laengeKm,
        aufstieg: Value(zahlen.aufstieg),
        abstieg: Value(zahlen.abstieg),
        angelegtAm: DateTime.now(),
      ),
      [
        for (final (i, p) in punkte.indexed)
          SpurpunkteCompanion.insert(
            spurId: id,
            nummer: i,
            breite: p.breite,
            laenge: p.laenge,
            hoehe: Value(p.hoehe),
            zeit: Value(p.zeit),
          ),
      ],
    );
    if (!mounted) return;
    melde.erfolg(t.spurHinzugefuegtMeldung(
        name,
        NumberFormat.decimalPatternDigits(
                locale: Localizations.localeOf(context).toString(),
                decimalDigits: 1)
            .format(zahlen.laengeKm)));
    await _laden();
  }

  Future<void> _gelaendeOeffnen() async {
    // Die gemerkte Auflage der Geländeansicht – Grund, Ebenen,
    // Höhenlinien. Nachgeschlagen wird sie hier, weil der
    // Geländebildschirm die Bibliothek nicht kennt.
    //
    // **Nicht mehr die Karte des Kartenbildschirms.** Bis Version 3.4.1
    // erbte die Landschaft dessen Stil, in der Annahme, wer dort ein
    // Luftbild gewählt habe, wolle es auch hier. Seit die Landschaft
    // eigene Ebenen kennt – Wanderwege, Beschriftung, Höhenlinien –
    // trägt sie eine eigene Wahl, und die abzuleiten hiesse, drei
    // Schalter zu erraten.
    final auflage = await widget.library.db.gelaendeKarteWert();
    // Und die Tageszeit, aus demselben Grund an derselben Stelle.
    final stimmung = await widget.library.db.gelaendeStimmungWert();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => GelaendeScreen(
        titel: _k.name,
        auflage: auflage,
        stimmung: stimmung,
        beimStimmungswechsel: widget.library.db.setzeGelaendeStimmung,
        beimKartenwechsel: widget.library.db.setzeGelaendeKarte,
        wanderobjekte: _wanderobjekte,
        fotos: _flugfotos(),
        spur: [
          for (final p in _spurpunkte)
            (breite: p.breite, laenge: p.laenge, hoehe: p.hoehe, zeit: p.zeit),
        ],
      ),
    ));
  }

  /// Die verorteten Fotos der Aktivität – für den Ueberflug.
  ///
  /// **Nur die mit Koordinate.** Ein Foto ohne Ort hat keine Stelle auf
  /// der Spur; es beim Start einzublenden waere geraten. Die Vorschau
  /// kommt aus dem Vorschauordner der Bibliothek und nicht aus der
  /// Originaldatei: Ein RAW von fuenfzig Megabyte waehrend eines Fluges
  /// zu dekodieren ruckelt, und die Vorschau reicht fuer 240 Punkte
  /// zehnmal.
  List<Gelaendefoto> _flugfotos() {
    final uhrzeit = DateFormat.Hm(
        Localizations.localeOf(context).toLanguageTag());
    return [
      for (final a in _aufnahmen)
        if (a.latitude != null &&
            a.longitude != null &&
            a.thumbnailRelativePath != null)
          (
            breite: a.latitude!,
            laenge: a.longitude!,
            // Gedeckelt und nicht roh: Ein Vorschaubild ist zwar klein,
            // aber die Regel gilt fuer jede Datei (siehe
            // `bilddekodierung_test.dart`), und 240 Punkte reichen dem
            // Flugbild.
            bild: begrenztesBild(
                widget.library.paths.absolute(a.thumbnailRelativePath!),
                kante: 480),
            unterschrift: uhrzeit.format(a.fileCreatedAt.toLocal()),
          ),
    ];
  }

  /// Gipfel, Hütten und Quellen zum Ausschnitt – aus der Bibliothek,
  /// sonst von Overpass.
  ///
  /// **Die Bibliothek zuerst**, und das ist keine Bequemlichkeit:
  /// Overpass wird ehrenamtlich betrieben und drosselt bei zu vielen
  /// Anfragen. Eine Tour, die schon einmal angesehen wurde, fragt
  /// niemanden mehr – auch nicht nach einem Neustart und auch nicht ohne
  /// Netz.
  Future<List<Wanderobjekt>> _wanderobjekte({
    required double sued,
    required double west,
    required double nord,
    required double ost,
  }) async {
    final zeilen = await widget.library.db.wanderpunkteFuer(
      sued: sued,
      west: west,
      nord: nord,
      ost: ost,
      holen: () async {
        final klient = http.Client();
        try {
          final frisch = await holeWanderobjekte(
              sued: sued, west: west, nord: nord, ost: ost, netz: klient);
          if (frisch == null) return null;
          return [
            for (final o in frisch)
              (
                osmId: o.osmId,
                artNr: o.art.index,
                breite: o.breite,
                laenge: o.laenge,
                name: o.name,
                hoehe: o.hoehe
              ),
          ];
        } finally {
          klient.close();
        }
      },
    );
    return [
      for (final z in zeilen)
        if (z.artNr >= 0 && z.artNr < Wanderart.values.length)
          Wanderobjekt(
            osmId: z.osmId,
            art: Wanderart.values[z.artNr],
            breite: z.breite,
            laenge: z.laenge,
            name: z.name,
            hoehe: z.hoehe,
          ),
    ];
  }

  Future<void> _spurEntfernen() async {
    final spur = _spur;
    if (spur == null) return;
    final t = AppTexte.of(context);
    await widget.library.db.spurLoeschen(spur.id);
    melde.hinweis(t.spurEntferntMeldung);
    await _laden();
  }

  Future<void> _umbenennen() async {
    final t = AppTexte.of(context);
    final sauber = await frageNamen(
      context,
      titel: t.aktivitaetenUmbenennen,
      feldbeschriftung: t.aktivitaetenName,
      vorgabe: _k.name,
    );
    if (sauber == null) return;
    await widget.library.db
        .aktivitaetAendern(_k.id, AktivitaetenCompanion(name: Value(sauber)));
    await _laden();
  }

  Future<void> _artAendern() async {
    final gewaehlt = await frageAktivitaetsart(context,
        db: widget.library.db, aktuell: _k.art);
    if (gewaehlt == null) return;
    await widget.library.db
        .aktivitaetAendern(_k.id, AktivitaetenCompanion(art: Value(gewaehlt)));
    await _laden();
  }

  /// Fotos dazunehmen oder herausnehmen.
  ///
  /// Die Erkennung schneidet an einer Lücke von anderthalb Stunden – das
  /// trifft oft, aber nicht immer: Das Foto vom Vorabend gehört manchmal
  /// dazu und das aus der Mittagspause manchmal nicht. Bis hierher liess
  /// sich daran nichts ändern; die Zuordnung entstand einmal beim
  /// Bestätigen und blieb dann, wie sie war.
  /// Die gerade angetippten Fotos.
  ///
  /// Leer heisst „kein Auswahlmodus": Solange nichts ausgewaehlt ist,
  /// oeffnet ein Tipp wie bisher den Betrachter. Sobald etwas drin
  /// steht, waehlt ein Tipp aus und ab. Dasselbe Verhalten wie im
  /// Albumbildschirm - wer es dort kennt, muss es hier nicht neu lernen.
  final Set<String> _auswahl = {};

  void _auswahlUmschalten(String id) => setState(() {
        if (!_auswahl.remove(id)) _auswahl.add(id);
      });

  /// Nimmt die ausgewaehlten Fotos aus der Aktivitaet heraus.
  ///
  /// Die neue Menge wird aus der **Datenbank** gebildet und nicht aus der
  /// Liste im Bild: `_aufnahmen` laesst weg, was im Papierkorb liegt oder
  /// gesperrt ist. Wer sie als Ausgangsmenge naehme, wuerde beim
  /// Neuschreiben genau diese Zuordnungen mit vernichten - derselbe
  /// Fehler, der beim Fotowaehler schon einmal Zuordnungen gekostet hat.
  Future<void> _auswahlEntfernen() async {
    final t = AppTexte.of(context);
    final weg = {..._auswahl};
    if (weg.isEmpty) return;
    final vorher = await widget.library.db.zuordnungenDerAktivitaet(_k.id);
    if (!mounted) return;
    await widget.library.db
        .setzeAufnahmenDerAktivitaet(_k.id, vorher.difference(weg));
    if (!mounted) return;
    setState(_auswahl.clear);
    melde.erfolg(t.aufnahmenEntferntAktivitaet(weg.length));
    await _laden();
  }

  Future<void> _aufnahmenBearbeiten() async {
    final t = AppTexte.of(context);
    // **Aus der Datenbank, nicht aus der Liste im Bild.** `_aufnahmen`
    // ist eine Ansicht: Sie laesst weg, was im Papierkorb liegt oder
    // gesperrt ist, und sie ist leer, solange `_laden()` noch laeuft -
    // die Knoepfe der Titelleiste stehen aber schon da. Beim Sichern
    // wird die Zuordnungstabelle geleert und neu geschrieben; alles, was
    // hier fehlt, waere danach endgueltig weg, ohne dass jemand es
    // angetippt haette. Gemessen an einem Fall mit drei Zuordnungen:
    // ein einziger Haken liess eine uebrig.
    final vorher = await widget.library.db.zuordnungenDerAktivitaet(_k.id);
    if (!mounted) return;
    final neu = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => AufnahmenWaehlenScreen(
          library: widget.library,
          titel: t.aufnahmenWahlTitelAktivitaet,
          vorhanden: vorher,
          von: _k.von,
          bis: _k.bis,
        ),
      ),
    );
    if (neu == null || !mounted) return;
    final dazu = neu.difference(vorher).length;
    final weg = vorher.difference(neu).length;
    if (dazu == 0 && weg == 0) {
      melde.hinweis(t.aufnahmenWahlUnveraendert);
      return;
    }
    await widget.library.db.setzeAufnahmenDerAktivitaet(_k.id, neu);
    melde.erfolg(t.aufnahmenWahlGeaendert(dazu, weg));
    await _laden();
  }

  Future<void> _notiz() async {
    final t = AppTexte.of(context);
    final sauber = await frageNamen(
      context,
      titel: t.aktivitaetenNotiz,
      feldbeschriftung: t.aktivitaetenNotiz,
      vorgabe: _k.notiz ?? '',
      mehrzeilig: true,
      leerErlaubt: true,
    );
    if (sauber == null) return;
    await widget.library.db.aktivitaetAendern(
        _k.id,
        AktivitaetenCompanion(
            notiz: Value(sauber.isEmpty ? null : sauber)));
    await _laden();
  }

  Future<void> _entfernen() async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.aktivitaetenLoeschen),
        content: Text(t.aktivitaetenLoeschenFrage(_k.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.aktivitaetenLoeschen)),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    await widget.library.db.aktivitaetLoeschen(_k.id);
    melde.hinweis(t.aktivitaetenEntfernt(_k.name));
    if (mounted) Navigator.of(context).pop();
  }

  void _oeffnen(int index) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: _aufnahmen,
        initialIndex: index,
        paths: widget.library.paths,
        db: widget.library.db,
        library: widget.library,
        onToggleFavorite: (a) =>
            widget.library.db.setFavorite(a.id, !a.isFavorite),
      ),
    ));
  }

  void _ortOeffnen(Aufenthaltsort ort) {
    final index = _aufnahmen.indexWhere((a) => a.id == ort.aufnahmeIds.first);
    if (index >= 0) _oeffnen(index);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final locale = Localizations.localeOf(context);
    final farben = Theme.of(context).colorScheme;
    final zahl = NumberFormat.decimalPatternDigits(
        locale: locale.toString(), decimalDigits: 1);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(symbolFuerKennung(_art), size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(_k.name)),
          ],
        ),
        // **Solange geladen wird, keine Knoepfe.** Der Rumpf zeigt dann
        // einen Ladekreis, die Titelleiste stand aber schon vollstaendig
        // da - und ihre Knoepfe arbeiteten auf Feldern, die `_laden()`
        // erst noch fuellt. Beim Bearbeiten der Fotos kostete das
        // Zuordnungen (siehe `_aufnahmenBearbeiten`); beim Spur-Knopf
        // waere eine zweite Spur an einer Aktivitaet entstanden, die
        // schon eine hat, weil `_spur` noch null ist und deshalb
        // "hinzufuegen" statt "entfernen" dasteht.
        actions: _laedt ? const [] : [
          if (_spur != null)
            IconButton(
              tooltip: t.gelaendeOeffnen,
              icon: const Icon(Icons.landscape_outlined),
              onPressed: _gelaendeOeffnen,
            ),
          if (_spur == null)
            IconButton(
              tooltip: t.spurHinzufuegen,
              icon: const Icon(Icons.route_outlined),
              onPressed: _spurHinzufuegen,
            )
          else
            IconButton(
              tooltip: t.spurEntfernen,
              icon: const Icon(Icons.wrong_location_outlined),
              onPressed: _spurEntfernen,
            ),
          // **Jetzt wirklich ein Pluszeichen.** Bis hierher stand hier ein
          // Bibliothekssymbol, mit der Begründung, der Knopf nehme Fotos
          // auch heraus – ein Pluszeichen sage das nicht. Das stimmte,
          // und es hat den Knopf unauffindbar gemacht: Zwischen sechs
          // weiteren Symbolen wurde er als „Fotos hinzufügen" gelesen und
          // deshalb gar nicht erst gesucht. Das Herausnehmen hat
          // inzwischen einen eigenen Weg (Fotos antippen, Leiste unten),
          // also darf der Knopf heissen, was er tut.
          IconButton(
            tooltip: t.aufnahmenHinzufuegen,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _aufnahmenBearbeiten,
          ),
          IconButton(
            tooltip: t.aktivitaetenArtAendern,
            icon: const Icon(Icons.category_outlined),
            onPressed: _artAendern,
          ),
          IconButton(
            tooltip: t.aktivitaetenUmbenennen,
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: _umbenennen,
          ),
          IconButton(
            tooltip: t.aktivitaetenNotiz,
            icon: const Icon(Icons.notes_outlined),
            onPressed: _notiz,
          ),
          IconButton(
            tooltip: t.aktivitaetenLoeschen,
            icon: const Icon(Icons.delete_outline),
            onPressed: _entfernen,
          ),
        ],
      ),
      body: _laedt
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                        AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            nameFuerKennung(t, _art),
                            DateFormat.yMMMd(locale.toString())
                                .format(_k.von),
                            dauertext(t, _dauer),
                            if (_streckeKm > 0)
                              streckentext(t, locale, _streckeKm),
                            t.aktivitaetenAufnahmen(_aufnahmen.length),
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 13, color: farben.onSurfaceVariant),
                        ),
                        if (_reisename case final r?)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(t.aktivitaetenZuReise(r),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: farben.onSurfaceVariant)),
                          ),
                        if (_route.length > 1 ||
                            _spurlinie.length > 1) ...[
                          const SizedBox(height: AppSpacing.md),
                          Routenkarte(
                            route: _route,
                            orte: _orte,
                            nachId: _nachId,
                            paths: widget.library.paths,
                            beiOrt: _ortOeffnen,
                            hoehe: 260,
                            spuren: [if (_spurlinie.length > 1) _spurlinie],
                            stelle: _stelleAufKarte,
                          ),
                        ] else if (_aufnahmen.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(t.aktivitaetenKeineRoute,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: farben.onSurfaceVariant)),
                        ],
                        if (_spur case final spur?) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(t.spurTitel,
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            [
                              spur.aufstieg == null
                                  ? t.spurKennzahlenOhneHoehe(
                                      zahl.format(spur.laengeKm))
                                  : t.spurKennzahlen(
                                      zahl.format(spur.laengeKm),
                                      spur.aufstieg!.round(),
                                      (spur.abstieg ?? 0).round()),
                              t.spurPunkte(spur.punktzahl),
                            ].join(' · '),
                            style: TextStyle(
                                fontSize: 13, color: farben.onSurfaceVariant),
                          ),
                          if (_profil.length > 1) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(t.spurHoehenprofil,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: farben.onSurfaceVariant)),
                            const SizedBox(height: AppSpacing.xs),
                            Hoehenprofil(
                              punkte: _profil,
                              beschreibung: _profilbeschreibung(t, zahl),
                              beiStelle: (i) => setState(() => _stelle = i),
                            ),
                          ] else
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: AppSpacing.xs),
                              child: Text(t.spurOhneHoehen,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: farben.onSurfaceVariant)),
                            ),
                        ],
                        if (_k.notiz case final notiz? when notiz.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.md),
                            child: Text(notiz),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 160,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final a = _aufnahmen[index];
                        final gewaehlt = _auswahl.contains(a.id);
                        return AssetThumbnailTile(
                          asset: Rasterzeile.aus(a),
                          paths: widget.library.paths,
                          selected: gewaehlt,
                          // Erst auswaehlen, dann tippen: Solange nichts
                          // gewaehlt ist, oeffnet ein Tipp den Betrachter.
                          onTap: () => _auswahl.isEmpty
                              ? _oeffnen(index)
                              : _auswahlUmschalten(a.id),
                          onLongPress: () => _auswahlUmschalten(a.id),
                        );
                      },
                      childCount: _aufnahmen.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.xl)),
              ],
              ),
              if (_auswahl.isNotEmpty)
                ZuordnungAuswahlleiste(
                  anzahl: _auswahl.length,
                  beschriftungEntfernen: t.aufnahmenAusAktivitaetEntfernen,
                  beiAufheben: () => setState(_auswahl.clear),
                  beiEntfernen: _auswahlEntfernen,
                ),
            ]),
    );
  }
}
