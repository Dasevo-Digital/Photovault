import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../services/aktivitaeten.dart';
import '../services/meldungsdienst.dart';
import '../services/reisen.dart' show zuhause;
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/aktivitaetsart_anzeige.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/ortskachel.dart';
import '../widgets/namens_dialog.dart';
import '../widgets/zeitraum_dialog.dart';
import 'aktivitaet_detail_screen.dart';
import 'asset_viewer_screen.dart';

/// Die Aktivitäten: Wanderungen, Radtouren, Ausflüge.
///
/// **Vorschlagen statt verlangen**, wie bei den Reisen. Andere Programme
/// stellen ein leeres Formular hin; hier steht die Frage: „Am 14. Juni
/// liegen acht Bilder über dreieinhalb Stunden und zwölf Kilometer bei
/// Goslar – war das eine Wanderung?"
class AktivitaetenScreen extends StatefulWidget {
  final LibraryState library;

  const AktivitaetenScreen({super.key, required this.library});

  @override
  State<AktivitaetenScreen> createState() => _AktivitaetenScreenState();
}

class _AktivitaetenScreenState extends State<AktivitaetenScreen> {
  List<AktivitaetenData> _aktivitaeten = const [];
  List<Aktivitaetsvorschlag> _vorschlaege = const [];
  Map<String, String> _reisenamen = const {};

  /// Wo jede Aktivität stattfand – in einer Abfrage für alle, siehe
  /// `AppDatabase.ortsbezugJeAktivitaet`.
  Map<String, Ortsbezug> _orte = const {};
  bool _laedt = true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _laedt = true);
    final db = widget.library.db;
    final aktivitaeten = await db.alleAktivitaeten();
    final reisen = await db.alleReisen();
    final roh = await db.aufnahmenFuerReiseerkennung();
    // **Was in einer bestätigten Reise steht, wird nicht noch einmal
    // vorgeschlagen.**
    //
    // Eine bestätigte Reise ist eine Entscheidung: Diese Aufnahmen
    // gehören zusammen und tragen einen Namen. Die Aktivitätserkennung
    // sah sie trotzdem weiter als freies Material und bot dieselben
    // Fotos ein zweites Mal an – bei der Reise „Mazār-e Sharīf – ISAF"
    // stammten zwei von vier Vorschlägen aus ihren Aufnahmen, einer
    // davon zu 28 von 28. Wer beide bestätigt, hat dasselbe zweimal in
    // der Bibliothek.
    //
    // Innerhalb einer Reise entsteht eine Aktivität deshalb von Hand –
    // im Reisebildschirm, wo man die Reise vor sich hat (siehe
    // `reise_detail_screen.dart`).
    final belegt = {
      ...await db.zugeordneteAktivitaetsAufnahmen(),
      ...(await db.reiseJeAufnahme()).keys,
    };
    final verworfen = await db.verworfeneAktivitaetsvorschlaege();
    final orte = await db.ortsbezugJeAktivitaet();
    if (!mounted) return;
    final t = AppTexte.of(context);

    final fuerErkennung = [
      for (final a in roh)
        (
          id: a.id,
          zeit: a.zeit,
          breite: a.breite,
          laenge: a.laenge,
          stadt: a.stadt,
        ),
    ];
    final vorschlaege = erkenneAktivitaeten(
      fuerErkennung,
      ohneOrt: t.aktivitaetenOhneOrt,
      // Derselbe Wohnort wie bei der Reiseerkennung – aus denselben
      // Aufnahmen geschlossen, damit „weit weg" beide Male dasselbe
      // heisst.
      wohnort: zuhause([
        for (final a in roh)
          (
            id: a.id,
            zeit: a.zeit,
            breite: a.breite,
            laenge: a.laenge,
            land: a.land,
            region: a.region,
            stadt: a.stadt,
          ),
      ]),
      bekannteIds: belegt,
      verworfen: verworfen,
    );

    if (!mounted) return;
    setState(() {
      _aktivitaeten = aktivitaeten;
      _vorschlaege = vorschlaege;
      _reisenamen = {for (final r in reisen) r.id: r.name};
      _orte = orte;
      _laedt = false;
    });
  }

  /// Bestätigen – mit Rückfrage nach dem Namen, wie bei den Reisen. Der
  /// vorgeschlagene Name steht schon im Feld.
  Future<void> _bestaetigen(Aktivitaetsvorschlag v) async {
    final t = AppTexte.of(context);
    final sauber = await frageNamen(
      context,
      titel: t.aktivitaetenBenennen,
      feldbeschriftung: t.aktivitaetenName,
      vorgabe: v.name,
    );
    if (sauber == null || !mounted) return;

    final db = widget.library.db;
    final reisen = await db.alleReisen();
    final zuordnung = await db.reiseJeAufnahme();
    final reiseId = reiseFuerAktivitaet(
      aufnahmeIds: v.aufnahmeIds,
      von: v.von,
      reiseJeAufnahme: zuordnung,
      reisen: [for (final r in reisen) (id: r.id, von: r.von, bis: r.bis)],
    );

    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: const Uuid().v4(),
        name: sauber,
        art: v.art.kennung,
        von: v.von,
        bis: v.bis,
        reiseId: Value(reiseId),
        angelegtAm: DateTime.now(),
      ),
      v.aufnahmeIds,
    );
    melde.erfolg(t.aktivitaetenAngelegt(sauber));
    await _laden();
  }

  /// Eine Aktivität von Hand anlegen – der Weg neben dem Vorschlag.
  ///
  /// Erkannt wird nur, was Fotos hergeben: vier Bilder über eine
  /// Dreiviertelstunde und zwei Kilometer Weg. Die Radtour, von der es
  /// zwei Bilder gibt, fällt durch dieses Raster – ohne dass sie deshalb
  /// nicht stattgefunden hätte.
  Future<void> _selbstAnlegen() async {
    final t = AppTexte.of(context);
    final db = widget.library.db;
    final angabe = await frageZeitraum(
      context,
      titel: t.aktivitaetenSelbstAnlegen,
      db: db,
      mitArt: true,
    );
    if (angabe == null || !mounted) return;

    final aufnahmen = await db.aufnahmenImZeitraum(angabe.von, angabe.bis);
    final ids = [for (final a in aufnahmen) a.id];
    // Dieselbe Zuordnung wie beim bestätigten Vorschlag: Liegt der
    // Zeitraum in einer Reise, wird die Aktivität deren Kapitel.
    final reisen = await db.alleReisen();
    final reiseId = reiseFuerAktivitaet(
      aufnahmeIds: ids,
      von: angabe.von,
      reiseJeAufnahme: await db.reiseJeAufnahme(),
      reisen: [for (final r in reisen) (id: r.id, von: r.von, bis: r.bis)],
    );

    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: const Uuid().v4(),
        name: angabe.name,
        art: angabe.art!,
        von: angabe.von,
        bis: angabe.bis,
        reiseId: Value(reiseId),
        angelegtAm: DateTime.now(),
      ),
      ids,
    );
    if (!mounted) return;
    melde.erfolg(t.aktivitaetenSelbstAngelegt(angabe.name));
    await _laden();
  }

  Future<void> _verwerfen(Aktivitaetsvorschlag v) async {
    await widget.library.db.verwirfAktivitaetsvorschlag(v.schluessel);
    await _laden();
  }

  List<AktivitaetenData> get _ohneReise => [
        for (final k in _aktivitaeten)
          if (k.reiseId == null) k
      ];

  List<AktivitaetenData> get _mitReise => [
        for (final k in _aktivitaeten)
          if (k.reiseId != null) k
      ];

  /// Die Zahlen im Kopf – wie bei den Reisen, und nach derselben Regel:
  /// Was null wäre, fällt weg.
  List<String> _kopfzahlen(AppTexte t) => [
        t.aktivitaetenAnzahl(_aktivitaeten.length),
        if (_mitReise.isNotEmpty) t.aktivitaetenMitReise(_mitReise.length),
        if (_ohneReise.isNotEmpty)
          t.aktivitaetenOhneReiseZahl(_ohneReise.length),
      ];

  Future<void> _umbenennen(AktivitaetenData k) async {
    final t = AppTexte.of(context);
    final sauber = await frageNamen(
      context,
      titel: t.aktivitaetenUmbenennen,
      feldbeschriftung: t.aktivitaetenName,
      vorgabe: k.name,
    );
    if (sauber == null || !mounted) return;
    await widget.library.db
        .aktivitaetAendern(k.id, AktivitaetenCompanion(name: Value(sauber)));
    await _laden();
  }

  Future<void> _loeschen(AktivitaetenData k) async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.aktivitaetenLoeschen),
        content: Text(t.aktivitaetenLoeschenFrage(k.name)),
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
    await widget.library.db.aktivitaetLoeschen(k.id);
    await _laden();
  }

  /// Die Kacheln einer der beiden Listen.
  List<Widget> _kacheln(AppTexte t, List<AktivitaetenData> welche,
          {required bool mitReisename}) =>
      [
        for (final k in welche)
          Aktivitaetskachel(
            key: ValueKey(k.id),
            aktivitaet: k,
            library: widget.library,
            reisename: mitReisename ? _reisenamen[k.reiseId] : null,
            ort: ortszeile(t, _orte[k.id],
                sprache: Localizations.localeOf(context).languageCode),
            onTippen: () => _oeffnen(k),
            befehle: [
              (
                symbol: Icons.drive_file_rename_outline,
                text: t.aktivitaetenUmbenennen,
                tun: () => _umbenennen(k),
              ),
              (
                symbol: Icons.delete_outline,
                text: t.aktivitaetenLoeschen,
                tun: () => _loeschen(k),
              ),
            ],
          ),
      ];

  Future<void> _oeffnen(AktivitaetenData k) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          AktivitaetDetailScreen(library: widget.library, aktivitaet: k),
    ));
    if (mounted) await _laden();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.aktivitaetenTitel),
        actions: [
          IconButton(
            tooltip: t.aktivitaetenSelbstAnlegen,
            icon: const Icon(Icons.add),
            onPressed: _laedt ? null : _selbstAnlegen,
          ),
          IconButton(
            tooltip: t.reisenAktualisieren,
            icon: const Icon(Icons.refresh),
            onPressed: _laedt ? null : _laden,
          ),
        ],
      ),
      body: _laedt
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppSpacing.lg),
                  Text(t.aktivitaetenSuchtNoch,
                      style: TextStyle(color: farben.onSurfaceVariant)),
                ],
              ),
            )
          : _aktivitaeten.isEmpty && _vorschlaege.isEmpty
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Center(
                    child: SizedBox(
                      width: 440,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.aktivitaetenLeer, textAlign: TextAlign.center),
                          // Ohne den Datensatz weiss die App nicht, wo
                          // etwas aufgenommen wurde – dann ist „noch
                          // keine Aktivität" nur die halbe Auskunft.
                          if (widget.library.geocoder == null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              t.fortschrittOhneGeodaten,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: farben.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      sliver: SliverList.list(children: [
                        Uebersichtskopf(
                          symbol: Icons.hiking,
                          titel: t.aktivitaetenTitel,
                          zahlen: _kopfzahlen(t),
                        ),
                        if (_vorschlaege.isNotEmpty) ...[
                          _Ueberschrift(t.aktivitaetenVorschlaege),
                          for (final v in _vorschlaege)
                            _Vorschlagskarte(
                              library: widget.library,
                              vorschlag: v,
                              onJa: () => _bestaetigen(v),
                              onNein: () => _verwerfen(v),
                            ),
                          const SizedBox(height: AppSpacing.xl),
                        ],
                        // Zwei Listen und nicht eine: Die Sonntagswanderung
                        // vor der Haustür sucht man anders als die Wanderung
                        // im Südtirol-Urlaub – die eine über das Datum, die
                        // andere über die Reise.
                        if (_ohneReise.isNotEmpty)
                          _Ueberschrift(t.aktivitaetenOhneReise),
                      ]),
                    ),
                    SliverPadding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      sliver: Kachelraster(
                          kacheln:
                              _kacheln(t, _ohneReise, mitReisename: false)),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      sliver: SliverList.list(children: [
                        if (_mitReise.isNotEmpty)
                          _Ueberschrift(t.aktivitaetenBestaetigte),
                      ]),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                      sliver: Kachelraster(
                          kacheln: _kacheln(t, _mitReise, mitReisename: true)),
                    ),
                  ],
                ),
    );
  }
}

class _Ueberschrift extends StatelessWidget {
  final String text;
  const _Ueberschrift(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _Vorschlagskarte extends StatelessWidget {
  final LibraryState library;
  final Aktivitaetsvorschlag vorschlag;
  final VoidCallback onJa;
  final VoidCallback onNein;

  const _Vorschlagskarte({
    required this.library,
    required this.vorschlag,
    required this.onJa,
    required this.onNein,
  });

  /// So viele Bilder stehen auf der Karte.
  ///
  /// Genug, um zu erkennen, worum es geht, und wenige genug, dass die
  /// Karte eine Karte bleibt. Wer mehr sehen will, tippt eines an.
  static const _bilder = 5;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final locale = Localizations.localeOf(context);
    final farben = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(symbolFuerArt(vorschlag.art), color: farben.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(vorschlag.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                nameFuerArt(t, vorschlag.art),
                DateFormat.yMMMd(locale.toString()).format(vorschlag.von),
                dauertext(t, vorschlag.dauer),
                streckentext(t, locale, vorschlag.streckeKm),
                t.aktivitaetenAufnahmen(vorschlag.anzahl),
              ].join(' · '),
              style: TextStyle(fontSize: 13, color: farben.onSurfaceVariant),
            ),
            // **Ohne Bild ist die Frage nicht zu beantworten.** Bis
            // hierher stand auf der Karte „Wanderung, 12 km, 47
            // Aufnahmen" und sonst nichts – zu bejahen war das nur auf
            // gut Glück. Die Aufnahmen liegen im Vorschlag ohnehin
            // schon (`aufnahmeIds`), sie wurden nur nie gezeigt.
            const SizedBox(height: AppSpacing.md),
            _Vorschaureihe(library: library, vorschlag: vorschlag),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onNein, child: Text(t.aktivitaetenKeine)),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                    onPressed: onJa, child: Text(t.aktivitaetenIstEine)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Die Bilder eines Vorschlags, damit man ihn beurteilen kann.
///
/// Eigenes Widget und nicht in [_Vorschlagskarte] eingebaut: Die Karte
/// selbst ist zustandslos und soll es bleiben; das Nachladen der
/// Aufnahmen gehört hierher.
class _Vorschaureihe extends StatelessWidget {
  final LibraryState library;
  final Aktivitaetsvorschlag vorschlag;

  const _Vorschaureihe({required this.library, required this.vorschlag});

  @override
  Widget build(BuildContext context) {
    final gezeigt =
        vorschlag.aufnahmeIds.take(_Vorschlagskarte._bilder).toList();
    if (gezeigt.isEmpty) return const SizedBox.shrink();
    final weitere = vorschlag.anzahl - gezeigt.length;
    return SizedBox(
      height: 72,
      child: FutureBuilder<List<AssetData>>(
        future: library.db.assetsByIds(gezeigt),
        builder: (context, schnappschuss) {
          final aufnahmen = schnappschuss.data;
          if (aufnahmen == null) return const SizedBox.shrink();
          // Die Datenbank gibt die Zeilen in ihrer eigenen Reihenfolge
          // zurück; der Vorschlag ist chronologisch sortiert, und das
          // ist die Reihenfolge, in der man eine Aktivität ansieht.
          final nachId = {for (final a in aufnahmen) a.id: a};
          return Row(
            children: [
              for (final id in gezeigt)
                if (nachId[id] case final a?)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: SizedBox(
                      width: 72,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: AssetThumbnailTile(
                          asset: Rasterzeile.aus(a),
                          paths: library.paths,
                          onTap: () =>
                              Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (_) => AssetViewerScreen(
                                assets: aufnahmen,
                                initialIndex: aufnahmen.indexOf(a),
                                paths: library.paths,
                                db: library.db,
                                library: library,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              if (weitere > 0)
                Text(
                  AppTexte.of(context).aktivitaetenWeitere(weitere),
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Eine Aktivität als Kachel – die Übersicht.
///
/// Neben [Aktivitaetszeile] und nicht statt ihr: Die Zeile steht weiter
/// **innerhalb einer Reise** (siehe `reise_detail_screen.dart`). Dort
/// sind die Aktivitäten Kapitel in zeitlicher Folge, und eine Reihe
/// grosser Kacheln unter der Karte einer einzelnen Reise beantwortete
/// keine Frage, die die Zeile nicht schon beantwortet.
class Aktivitaetskachel extends StatefulWidget {
  final AktivitaetenData aktivitaet;
  final LibraryState library;

  /// Der Name der Reise, zu der sie gehört – oder `null`. In der Liste
  /// der einzelnen Aktivitäten bleibt er weg: Dort gibt es keine.
  final String? reisename;

  final String? ort;
  final VoidCallback onTippen;
  final List<Kachelbefehl> befehle;

  const Aktivitaetskachel({
    super.key,
    required this.aktivitaet,
    required this.library,
    required this.reisename,
    required this.ort,
    required this.onTippen,
    this.befehle = const [],
  });

  @override
  State<Aktivitaetskachel> createState() => _AktivitaetskachelState();
}

class _AktivitaetskachelState extends State<Aktivitaetskachel> {
  /// Einmal beim Anlegen geholt und nicht in `build` – sonst liefe die
  /// Abfrage bei jedem Neuaufbau erneut.
  late final Future<AssetData?> _bild =
      widget.library.db.ersteAufnahmeDerAktivitaet(widget.aktivitaet.id);

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final art = widget.aktivitaet.art;
    final datum = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    // Die Reise gehört zum Ort und nicht in eine eigene Zeile: Beides
    // beantwortet „wo war das?", und zwei Zeilen dafür machten die
    // Kachel höher, ohne mehr zu sagen. Bleibt beides leer, entfällt die
    // Zeile ganz - siehe [ortszeile].
    final unterzeile = [
      if (widget.ort case final o?) o,
      if (widget.reisename case final r?) t.aktivitaetenZuReise(r),
    ].join(' · ');
    return FutureBuilder<AssetData?>(
      future: _bild,
      builder: (context, schnappschuss) => Ortskachel(
        bild: schnappschuss.data,
        paths: widget.library.paths,
        symbol: symbolFuerKennung(art),
        name: widget.aktivitaet.name,
        kennzeichen: nameFuerKennung(t, art),
        // Bei einer Aktivität ist das volle Datum die Auskunft, nicht das
        // Jahr: Sie dauert Stunden, keine Wochen, und „2024" beantwortete
        // die Frage „wann war das?" nicht einmal ungefähr.
        zeitraum: datum.format(widget.aktivitaet.von),
        ort: unterzeile.isEmpty ? null : unterzeile,
        onTippen: widget.onTippen,
        befehle: widget.befehle,
      ),
    );
  }
}

/// Eine Aktivität als Zeile – in der Liste und als Kapitel einer Reise.
class Aktivitaetszeile extends StatefulWidget {
  final AktivitaetenData aktivitaet;
  final LibraryState library;

  /// Der Name der Reise, zu der sie gehört – oder `null`. In der Liste
  /// einer Reise bleibt er weg: Dort wäre er bei jeder Zeile derselbe.
  final String? reisename;

  final VoidCallback onTippen;

  const Aktivitaetszeile({
    super.key,
    required this.aktivitaet,
    required this.library,
    required this.reisename,
    required this.onTippen,
  });

  @override
  State<Aktivitaetszeile> createState() => _AktivitaetszeileState();
}

class _AktivitaetszeileState extends State<Aktivitaetszeile> {
  /// Einmal beim Anlegen der Zeile geholt und nicht in `build` – sonst
  /// liefe die Abfrage bei jedem Neuaufbau erneut.
  late final Future<AssetData?> _bild =
      widget.library.db.ersteAufnahmeDerAktivitaet(widget.aktivitaet.id);

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final locale = Localizations.localeOf(context);
    final art = widget.aktivitaet.art;
    final dauer = widget.aktivitaet.bis.difference(widget.aktivitaet.von);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: SizedBox(
          width: 52,
          height: 52,
          child: FutureBuilder<AssetData?>(
            future: _bild,
            builder: (context, schnappschuss) {
              final asset = schnappschuss.data;
              if (asset == null) {
                return Center(child: Icon(symbolFuerKennung(art)));
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: AssetThumbnailTile(
                  asset: Rasterzeile.aus(asset),
                  paths: widget.library.paths,
                  onTap: widget.onTippen,
                ),
              );
            },
          ),
        ),
        title: Row(
          children: [
            Icon(symbolFuerKennung(art),
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(widget.aktivitaet.name)),
          ],
        ),
        subtitle: Text([
          nameFuerKennung(t, art),
          DateFormat.yMMMd(locale.toString()).format(widget.aktivitaet.von),
          dauertext(t, dauer),
          if (widget.reisename case final r?) t.aktivitaetenZuReise(r),
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onTippen,
      ),
    );
  }
}
