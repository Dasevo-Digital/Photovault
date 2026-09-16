import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../services/gpx.dart';
import '../services/reiseroute.dart';
import '../widgets/zuordnung_auswahlleiste.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/routenkarte.dart';
import '../widgets/namens_dialog.dart';
import '../widgets/reiseart_anzeige.dart';
import '../widgets/zeitraum_dialog.dart';
import 'asset_viewer_screen.dart';
import 'aufnahmen_waehlen_screen.dart';
import 'reisen_screen.dart' show reiseUnterzeile;
import '../services/meldungsdienst.dart';
import 'aktivitaet_detail_screen.dart';
import 'aktivitaeten_screen.dart' show Aktivitaetszeile;

/// Eine einzelne Reise.
///
/// Ist eine Reise erst benannt, ist die Darstellung fast geschenkt: Die
/// Aufnahmen liegen bereits chronologisch vor, die besuchten Orte stehen
/// aus der Umkehr-Geokodierung an jedem Bild.
class ReiseDetailScreen extends StatefulWidget {
  final LibraryState library;
  final ReisenData reise;

  const ReiseDetailScreen({
    super.key,
    required this.library,
    required this.reise,
  });

  @override
  State<ReiseDetailScreen> createState() => _ReiseDetailScreenState();
}

class _ReiseDetailScreenState extends State<ReiseDetailScreen> {
  late ReisenData _reise = widget.reise;
  List<AssetData> _aufnahmen = const [];
  List<AktivitaetenData> _aktivitaeten = const [];

  /// Was der Reisende zu einzelnen Tagen geschrieben hat, nach Tag.
  ///
  /// **Der fehlende Teil des Tagebuchs.** Die Kapitel nach Tagen gab es
  /// schon; ein Tagebuch besteht aber nicht aus Bildern allein. Die Notiz
  /// an der Reise galt für die ganze Reise – „am dritten Tag hat es
  /// geschüttet" gehört an den dritten Tag.
  Map<DateTime, String> _tagesnotizen = const {};

  /// Die aufgezeichneten Spuren dieser Reise, samt ihren Punkten.
  ///
  /// **Mehrere.** Eine Wanderung hat eine Spur; eine Reise über zehn Tage
  /// hat zehn Dateien, eine je Tag. Sie in eine Liste zu werfen zöge
  /// zwischen den Tagen eine gerade Linie quer über die Karte.
  List<({SpurenData spur, List<SpurpunkteData> punkte})> _spuren = const [];
  bool _laedt = true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final aufnahmen = await widget.library.db.aufnahmenDerReise(_reise.id);
    final frisch = await widget.library.db.reise(_reise.id);
    final aktivitaeten =
        await widget.library.db.aktivitaetenDerReise(_reise.id);
    final notizen = await widget.library.db.reisetagnotizenFuer(_reise.id);
    final spuren = <({SpurenData spur, List<SpurpunkteData> punkte})>[];
    for (final s in await widget.library.db.spurenDerReise(_reise.id)) {
      spuren.add((spur: s, punkte: await widget.library.db.punkteDerSpur(s.id)));
    }
    if (!mounted) return;
    setState(() {
      _aufnahmen = aufnahmen;
      _aktivitaeten = aktivitaeten;
      _tagesnotizen = notizen;
      _spuren = spuren;
      if (frisch != null) _reise = frisch;
      _laedt = false;
    });
  }

  /// Die besuchten Orte, häufigste zuerst – aus den Aufnahmen selbst und
  /// nicht gespeichert: Wer eine Aufnahme aus der Reise nimmt, soll die
  /// Liste sofort ohne sie sehen.
  List<String> get _orte {
    final gezaehlt = <String, int>{};
    for (final a in _aufnahmen) {
      final ort = a.locationCity;
      if (ort == null || ort.isEmpty) continue;
      gezaehlt[ort] = (gezaehlt[ort] ?? 0) + 1;
    }
    return gezaehlt.keys.toList()
      ..sort((a, b) {
        final z = gezaehlt[b]!.compareTo(gezaehlt[a]!);
        return z != 0 ? z : a.compareTo(b);
      });
  }

  Map<String, AssetData> get _nachId =>
      {for (final a in _aufnahmen) a.id: a};

  List<Routenpunkt> get _route => reiseroute([
        for (final a in _aufnahmen)
          if (a.latitude != null && a.longitude != null)
            (
              breite: a.latitude!,
              laenge: a.longitude!,
              zeit: a.fileCreatedAt,
            ),
      ]);

  /// Die Aufenthaltsorte – ein Pin je Ort statt einer je Aufnahme.
  List<Aufenthaltsort> get _orteMitBildern => aufenthaltsorte([
        for (final a in _aufnahmen)
          if (a.latitude != null && a.longitude != null)
            (
              id: a.id,
              breite: a.latitude!,
              laenge: a.longitude!,
              zeit: a.fileCreatedAt,
              stadt: a.locationCity,
            ),
      ]);

  List<Reisetag> get _tage => reisetage([
        for (final a in _aufnahmen)
          (id: a.id, zeit: a.fileCreatedAt, stadt: a.locationCity),
      ]);

  int get _naechte => DateTime(_reise.bis.year, _reise.bis.month, _reise.bis.day)
      .difference(DateTime(_reise.von.year, _reise.von.month, _reise.von.day))
      .inDays;

  Future<void> _umbenennen() async {
    final t = AppTexte.of(context);
    final sauber = await frageNamen(
      context,
      titel: t.reisenUmbenennen,
      feldbeschriftung: t.reisenName,
      vorgabe: _reise.name,
    );
    if (sauber == null || !mounted) return;
    await widget.library.db
        .reiseAendern(_reise.id, ReisenCompanion(name: Value(sauber)));
    await _laden();
  }

  Future<void> _notiz() async {
    final t = AppTexte.of(context);
    final text = await frageNamen(
      context,
      titel: t.reisenNotiz,
      feldbeschriftung: t.reisenNotiz,
      vorgabe: _reise.notiz ?? '',
      mehrzeilig: true,
      leerErlaubt: true,
    );
    if (text == null || !mounted) return;
    await widget.library.db.reiseAendern(
      _reise.id,
      // Leerer Text heisst „keine Notiz" und nicht „eine leere Notiz" –
      // sonst stünde in der Ansicht ein leerer Absatz.
      ReisenCompanion(notiz: Value(text.isEmpty ? null : text)),
    );
    await _laden();
  }

  /// Schreibt oder ändert die Notiz eines Reisetages.
  Future<void> _tagesnotiz(DateTime tag) async {
    final t = AppTexte.of(context);
    final datum =
        DateFormat.yMMMMd(Localizations.localeOf(context).toString());
    final text = await frageNamen(
      context,
      titel: t.reisenTagesnotizTitel(datum.format(tag)),
      feldbeschriftung: t.reisenTagesnotiz,
      vorgabe: _tagesnotizen[DateTime(tag.year, tag.month, tag.day)] ?? '',
      mehrzeilig: true,
      leerErlaubt: true,
    );
    if (text == null || !mounted) return;
    await widget.library.db.setzeReisetagnotiz(_reise.id, tag, text);
    await _laden();
  }

  /// Ein langer Druck öffnet ein Menü und ändert nicht stillschweigend
  /// das Titelbild: Eine Geste, die etwas verändert, ohne es zu sagen,
  /// findet man nur durch Zufall wieder.
  Future<void> _bildmenue(AssetData asset) async {
    final t = AppTexte.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (blatt) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(t.auswAuswaehlen),
              onTap: () {
                Navigator.pop(blatt);
                _auswahlUmschalten(asset.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(t.reisenAlsTitelbild),
              onTap: () {
                Navigator.pop(blatt);
                _titelbild(asset);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _titelbild(AssetData asset) async {
    final t = AppTexte.of(context);
    await widget.library.db.reiseAendern(
        _reise.id, ReisenCompanion(titelbildAssetId: Value(asset.id)));
    await _laden();
    if (!mounted) return;
    melde.erfolg(t.reisenTitelbildGesetzt);
  }

  Future<void> _entfernen() async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.reisenLoeschen),
        content: Text(t.reisenLoeschenFrage(_reise.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t.allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t.allgEntfernen)),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    await widget.library.db.reiseLoeschen(_reise.id);
    if (mounted) Navigator.of(context).pop();
  }

  /// Fotos dazunehmen oder herausnehmen.
  ///
  /// Beim Anlegen kam alles aus dem Zeitraum mit (siehe
  /// `frageZeitraum`); dass eine Reise am Abflugtag noch drei Bilder aus
  /// der Küche enthält, war bis hierher nicht zu ändern.
  /// Die gerade angetippten Fotos – siehe die gleiche Stelle in
  /// `aktivitaet_detail_screen.dart`.
  final Set<String> _auswahl = {};

  void _auswahlUmschalten(String id) => setState(() {
        if (!_auswahl.remove(id)) _auswahl.add(id);
      });

  /// Nimmt die ausgewaehlten Fotos aus der Reise heraus.
  ///
  /// Die Ausgangsmenge kommt aus der Datenbank und nicht aus `_aufnahmen`
  /// – dort fehlt, was im Papierkorb liegt oder gesperrt ist, und beim
  /// Neuschreiben waere es fuer immer weg. An der gewachsenen Bibliothek
  /// standen 33 Zuordnungen genau so auf dem Spiel.
  Future<void> _auswahlEntfernen() async {
    final t = AppTexte.of(context);
    final weg = {..._auswahl};
    if (weg.isEmpty) return;
    final vorher = await widget.library.db.zuordnungenDerReise(_reise.id);
    if (!mounted) return;
    await widget.library.db
        .setzeAufnahmenDerReise(_reise.id, vorher.difference(weg));
    if (!mounted) return;
    setState(_auswahl.clear);
    melde.erfolg(t.aufnahmenEntferntReise(weg.length));
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
    final vorher = await widget.library.db.zuordnungenDerReise(_reise.id);
    if (!mounted) return;
    final neu = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => AufnahmenWaehlenScreen(
          library: widget.library,
          titel: t.aufnahmenWahlTitelReise,
          vorhanden: vorher,
          von: _reise.von,
          bis: _reise.bis,
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
    await widget.library.db.setzeAufnahmenDerReise(_reise.id, neu);
    melde.erfolg(t.aufnahmenWahlGeaendert(dazu, weg));
    await _laden();
  }

  /// Tippen auf einen Pin: nur die Bilder von dort.
  ///
  /// Nicht der Sprung in die vollständige Liste an der passenden Stelle.
  /// „Was habe ich in Rom fotografiert" ist eine eigene Frage, und ein
  /// Betrachter, der danach weiterblättert nach Florenz, beantwortet sie
  /// nur halb.
  /// Die Art der Reise wählen – Reise, Unternehmung, dienstlich, Besuch.
  ///
  /// **Warum sichtbar und nicht im Menü.** In der Bibliothek stehen ein
  /// zweimonatiger Einsatz, eine Gedenkfahrt, eine Firmenveranstaltung
  /// und ein Verwandtenbesuch nebeneinander. Was für eine Art Reise das
  /// war, gehört neben ihren Zeitraum und nicht hinter drei Punkte.
  Future<void> _artWaehlen() async {
    final gewaehlt = await frageReiseart(context, aktuell: _reise.art);
    if (gewaehlt == null || gewaehlt == _reise.art || !mounted) return;
    await widget.library.db.setzeReiseart(_reise.id, gewaehlt);
    await _laden();
  }

  /// Eine Unternehmung innerhalb dieser Reise anlegen.
  ///
  /// **Der Weg, der gefehlt hat.** Aktivitäten entstanden bisher nur im
  /// Aktivitätenbildschirm und fanden ihre Reise über den Kalender. Seit
  /// eine bestätigte Reise keine Vorschläge mehr erzeugt (sie bot
  /// dieselben Fotos ein zweites Mal an, siehe
  /// `aktivitaeten_screen.dart`), muss es hier gehen – dort, wo man die
  /// Reise vor sich hat.
  ///
  /// **Vorbelegt mit der ganzen Reise.** Wer nichts ändert, bekommt die
  /// Reise selbst als eine Unternehmung – mit Spur, Überflug und
  /// Zusammenfassung wie eine Wanderung. Wer den Zeitraum enger zieht,
  /// bekommt ein Kapitel daraus. Beides ist derselbe Handgriff.
  Future<void> _aktivitaetAnlegen() async {
    final t = AppTexte.of(context);
    final angabe = await frageZeitraum(
      context,
      titel: t.reisenAktivitaetAnlegen,
      db: widget.library.db,
      mitArt: true,
      von: _reise.von,
      bis: _reise.bis,
      name: _reise.name,
    );
    if (angabe == null || !mounted) return;

    // **Die Aufnahmen der Reise, nicht die der Bibliothek.** Wer eine
    // Aufnahme aus der Reise genommen hat, will sie auch in deren
    // Unternehmung nicht wiedersehen.
    final vom = DateTime(angabe.von.year, angabe.von.month, angabe.von.day);
    final bis = DateTime(
        angabe.bis.year, angabe.bis.month, angabe.bis.day, 23, 59, 59, 999);
    final ids = [
      for (final a in _aufnahmen)
        if (!a.fileCreatedAt.isBefore(vom) && !a.fileCreatedAt.isAfter(bis))
          a.id,
    ];
    if (ids.isEmpty) {
      melde.hinweis(t.reisenAktivitaetLeer);
      return;
    }

    await widget.library.db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: const Uuid().v4(),
        name: angabe.name,
        art: angabe.art!,
        von: angabe.von,
        bis: angabe.bis,
        reiseId: Value(_reise.id),
        angelegtAm: DateTime.now(),
      ),
      ids,
    );
    if (!mounted) return;
    melde.erfolg(t.reisenAktivitaetAngelegt(angabe.name, ids.length));
    await _laden();
  }

  Future<void> _aktivitaetOeffnen(AktivitaetenData k) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          AktivitaetDetailScreen(library: widget.library, aktivitaet: k),
    ));
    if (mounted) await _laden();
  }

  void _ortOeffnen(Aufenthaltsort ort) {
    final bilder = [
      for (final id in ort.aufnahmeIds)
        if (_nachId[id] case final a?) a,
    ];
    if (bilder.isEmpty) return;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => AssetViewerScreen(
        assets: bilder,
        initialIndex: 0,
        paths: widget.library.paths,
        db: widget.library.db,
        library: widget.library,
        onToggleFavorite: (a) =>
            widget.library.db.setFavorite(a.id, !a.isFavorite),
      ),
    ));
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

  /// Die Spuren als reine Linien – das ist alles, was die Karte braucht.
  List<List<({double breite, double laenge})>> get _spurlinien => [
        for (final e in _spuren)
          if (e.punkte.length > 1)
            [for (final p in e.punkte) (breite: p.breite, laenge: p.laenge)],
      ];

  /// Eine GPX-Datei als Route an diese Reise hängen.
  ///
  /// **Dieselbe Rechnung wie bei einer Aktivität**, nur die andere
  /// Spalte: Was die Datei hergibt, ist eine Messung, und die gehört
  /// neben die aus den Fotos geratene Linie – nicht hinein.
  Future<void> _spurHinzufuegen() async {
    final t = AppTexte.of(context);
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
        reiseId: Value(_reise.id),
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

  Future<void> _spurEntfernen(SpurenData spur) async {
    final t = AppTexte.of(context);
    await widget.library.db.spurLoeschen(spur.id);
    melde.hinweis(t.spurEntferntMeldung);
    await _laden();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_reise.name),
        // Solange geladen wird, keine Knoepfe - siehe die gleiche Stelle
        // in aktivitaet_detail_screen.dart.
        actions: _laedt ? const [] : [
          // Siehe die gleiche Stelle in aktivitaet_detail_screen.dart:
          // Das Herausnehmen hat jetzt einen eigenen Weg, also darf der
          // Knopf ein Pluszeichen tragen und gefunden werden.
          IconButton(
            tooltip: t.aufnahmenHinzufuegen,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _aufnahmenBearbeiten,
          ),
          // **Hinzufügen, nicht ersetzen.** Eine Reise darf mehrere
          // Spuren tragen – eine je Tag. Der Knopf bleibt deshalb immer
          // stehen; weggenommen wird eine einzelne unter der Karte.
          IconButton(
            tooltip: t.reisenAktivitaetAnlegen,
            icon: const Icon(Icons.hiking_outlined),
            onPressed: _aktivitaetAnlegen,
          ),
          IconButton(
            tooltip: t.spurHinzufuegen,
            icon: const Icon(Icons.route_outlined),
            onPressed: _spurHinzufuegen,
          ),
          IconButton(
            tooltip: t.reisenUmbenennen,
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: _umbenennen,
          ),
          IconButton(
            tooltip: t.reisenNotiz,
            icon: const Icon(Icons.notes_outlined),
            onPressed: _notiz,
          ),
          IconButton(
            tooltip: t.reisenLoeschen,
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
                        Row(
                          children: [
                            ActionChip(
                              avatar: Icon(
                                  symbolFuerReiseartKennung(_reise.art),
                                  size: 18),
                              label: Text(
                                  nameFuerReiseartKennung(t, _reise.art)),
                              tooltip: t.reisenArtAendern,
                              visualDensity: VisualDensity.compact,
                              onPressed: _artWaehlen,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                reiseUnterzeile(
                                    t, Localizations.localeOf(context),
                                    von: _reise.von,
                                    bis: _reise.bis,
                                    naechte: _naechte,
                                    anzahl: _aufnahmen.length),
                                style: TextStyle(
                                    fontSize: 13,
                                    color: farben.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                        if (_route.length > 1 || _spuren.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(t.reisenRoute,
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: AppSpacing.xs),
                          Routenkarte(
                            route: _route,
                            orte: _orteMitBildern,
                            nachId: _nachId,
                            paths: widget.library.paths,
                            beiOrt: _ortOeffnen,
                            spuren: _spurlinien,
                          ),
                          if (_spuren.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            for (final e in _spuren)
                              _Spurzeile(
                                spur: e.spur,
                                sprache:
                                    Localizations.localeOf(context).toString(),
                                beimEntfernen: () => _spurEntfernen(e.spur),
                              ),
                          ],
                        ] else if (_aufnahmen.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(t.reisenKeineRoute,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: farben.onSurfaceVariant)),
                        ],
                        if (_reise.notiz case final notiz?
                            when notiz.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(notiz),
                        ],
                        if (_orte.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(t.reisenOrte,
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              for (final ort in _orte.take(20))
                                Chip(
                                  label: Text(ort),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Die Unternehmungen dieser Reise – vor den Tagen, weil
                // sie die Frage „was haben wir gemacht?" beantworten und
                // die Tage nur die Frage „wann".
                // **Immer da, auch leer.** Vorher erschien der
                // Abschnitt erst, wenn schon eine Unternehmung
                // existierte – wer keine hatte, erfuhr nie, dass es sie
                // gibt.
                SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.md, AppSpacing.lg, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.aktivitaetenInDieserReise,
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: AppSpacing.xs),
                          if (_aktivitaeten.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                  bottom: AppSpacing.xs),
                              child: Text(
                                t.reisenOhneAktivitaeten,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ),
                            ),
                          for (final k in _aktivitaeten)
                            Aktivitaetszeile(
                              aktivitaet: k,
                              library: widget.library,
                              // In der Liste einer Reise wäre der Name
                              // bei jeder Zeile derselbe.
                              reisename: null,
                              onTippen: () => _aktivitaetOeffnen(k),
                            ),
                        ],
                      ),
                    ),
                  ),
                // Die Tage als Kapitel. Ein durchgehendes Raster von
                // dreihundertfünfzig Bildern beantwortet die Frage nicht,
                // die man an eine Reise stellt: Was war wann?
                for (final tag in _tage) ...[
                  SliverToBoxAdapter(
                    child: _Tageskopf(
                      tag: tag,
                      anzahl: tag.aufnahmeIds.length,
                      notiz: _tagesnotizen[
                          DateTime(tag.tag.year, tag.tag.month, tag.tag.day)],
                      beimSchreiben: () => _tagesnotiz(tag.tag),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final asset =
                              _nachId[tag.aufnahmeIds[index]];
                          if (asset == null) return const SizedBox.shrink();
                          return AssetThumbnailTile(
                            asset: Rasterzeile.aus(asset),
                            paths: widget.library.paths,
                            selected: _auswahl.contains(asset.id),
                            onTap: () => _auswahl.isEmpty
                                ? _oeffnen(_aufnahmen.indexOf(asset))
                                : _auswahlUmschalten(asset.id),
                            // Der lange Druck oeffnet hier das Bildmenue
                            // (Titelbild setzen) – das gab es schon.
                            // Deshalb steht das Auswaehlen dort als
                            // erster Eintrag drin, statt die Geste zu
                            // ueberschreiben.
                            onLongPress: () => _bildmenue(asset),
                          );
                        },
                        childCount: tag.aufnahmeIds.length,
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.xl)),
              ],
              ),
              if (_auswahl.isNotEmpty)
                ZuordnungAuswahlleiste(
                  anzahl: _auswahl.length,
                  beschriftungEntfernen: t.aufnahmenAusReiseEntfernen,
                  beiAufheben: () => setState(_auswahl.clear),
                  beiEntfernen: _auswahlEntfernen,
                ),
            ]),
    );
  }
}

/// Die Überschrift eines Reisetages.
class _Tageskopf extends StatelessWidget {
  final Reisetag tag;
  final int anzahl;

  /// Was an diesem Tag geschah – `null` heisst „nichts geschrieben".
  final String? notiz;

  final VoidCallback beimSchreiben;

  const _Tageskopf({
    required this.tag,
    required this.anzahl,
    required this.notiz,
    required this.beimSchreiben,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final datum =
        DateFormat.yMMMMEEEEd(Localizations.localeOf(context).toString());
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  tag.ort == null
                      ? t.reisenTag(datum.format(tag.tag))
                      : '${datum.format(tag.tag)} · ${tag.ort}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(t.reisenAufnahmen(anzahl),
                  style:
                      TextStyle(fontSize: 12, color: farben.onSurfaceVariant)),
              const Spacer(),
              // Der Stift steht immer da, auch am leeren Tag: Eine
              // Bedienmoeglichkeit, die erst erscheint, wenn es schon
              // etwas gibt, findet niemand beim ersten Mal.
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: Icon(notiz == null
                    ? Icons.note_add_outlined
                    : Icons.edit_note_outlined),
                tooltip: notiz == null
                    ? t.reisenTagesnotizSchreiben
                    : t.reisenTagesnotizAendern,
                onPressed: beimSchreiben,
              ),
            ],
          ),
          // Der geschriebene Teil des Tagebuchs. Ueber den Bildern und
          // nicht darunter: Er sagt, was man auf ihnen sieht.
          if (notiz != null)
            Padding(
              padding: const EdgeInsets.only(
                  top: AppSpacing.xs, bottom: AppSpacing.xs, right: AppSpacing.xl),
              child: Text(notiz!,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}

/// Die Strecke auf der Karte.
///
/// Ohne Bedienung: Diese Karte beantwortet eine Frage („wo war das?"),
/// sie ist kein Kartenbildschirm. Wer suchen will, hat den unter „Orte".

/// Eine angehängte Spur unter der Karte: Name, Länge, Zeitraum – und der
/// Weg, sie wieder wegzunehmen.
///
/// **Sie steht unter der Karte und nicht in der Kopfleiste.** In der
/// Kopfleiste könnte nur *eine* Spur weggenommen werden; eine Reise hat
/// aber je Tag eine, und welche gemeint ist, sagt nur ihr Name.
class _Spurzeile extends StatelessWidget {
  const _Spurzeile({
    required this.spur,
    required this.sprache,
    required this.beimEntfernen,
  });

  final SpurenData spur;
  final String sprache;
  final VoidCallback beimEntfernen;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final eine =
        NumberFormat.decimalPatternDigits(locale: sprache, decimalDigits: 1);
    return Row(
      children: [
        Icon(Icons.route_outlined, size: 16, color: farben.tertiary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '${spur.name} · ${t.spurKm(eine.format(spur.laengeKm))}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
          ),
        ),
        IconButton(
          tooltip: t.spurEntfernen,
          icon: const Icon(Icons.wrong_location_outlined, size: 18),
          onPressed: beimEntfernen,
        ),
      ],
    );
  }
}
