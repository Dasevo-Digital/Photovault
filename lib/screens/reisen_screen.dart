import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/reisefortschritt.dart';
import '../services/reisen.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/ortskachel.dart';
import '../services/meldungsdienst.dart';
import '../widgets/namens_dialog.dart';
import '../widgets/reiseart_anzeige.dart';
import '../widgets/zeitraum_dialog.dart';
import '../widgets/fortschrittsbalken.dart';
import '../services/laendernamen.dart';
import 'laenderliste_screen.dart';
import 'reise_detail_screen.dart';
import 'weltkarte_screen.dart';
import 'aktivitaeten_screen.dart';

/// Die Reisen einer Bibliothek – bestätigte und vorgeschlagene.
///
/// **Der Unterschied zu jedem anderen Reisetagebuch:** Hier steht kein
/// leeres Formular. Aufnahmezeit und Koordinate liegen längst in der
/// Datenbank; was fehlte, war jemand, der sie zusammenliest. Der Nutzer
/// bestätigt und benennt — aus einer Tagebuchpflicht wird eine
/// Bestätigung.
class ReisenScreen extends StatefulWidget {
  final LibraryState library;
  const ReisenScreen({super.key, required this.library});

  @override
  State<ReisenScreen> createState() => _ReisenScreenState();
}

class _ReisenScreenState extends State<ReisenScreen> {
  List<ReisenData> _reisen = const [];

  /// Wie viele Aufnahmen je Reise – für die Wahl beim Zusammenführen.
  Map<String, int> _anzahlen = const {};
  List<Reisevorschlag> _vorschlaege = const [];
  Reisefortschritt? _fortschritt;

  /// Wo jede Reise stattfand – in einer Abfrage für alle, siehe
  /// `AppDatabase.ortsbezugJeReise`.
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
    final reisen = await db.alleReisen();
    final anzahlen = await db.aufnahmenzahlJeReise();
    final roh = await db.aufnahmenFuerReiseerkennung();
    final ohneOrt = await db.aufnahmenOhneKoordinate();
    final zugeordnet = await db.zugeordneteReiseAufnahmen();
    final verworfen = await db.verworfeneReisevorschlaege();
    final besucht = await db.besuchteOrte();
    final orte = await db.ortsbezugJeReise();
    if (!mounted) return;
    // Ohne den GeoNames-Datensatz gibt es keine Länderzahl, gegen die
    // sich zählen liesse – dann bleibt der Balken weg, statt „0 von 0"
    // zu behaupten.
    final verzeichnis = widget.library.geocoder?.laenderverzeichnis;
    final fortschritt = verzeichnis == null
        ? null
        : reisefortschritt(besucht, laenderGesamt: verzeichnis.length);
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).languageCode;
    final vorschlaege = erkenneReisen(
      [
        for (final a in roh)
          (
            id: a.id,
            zeit: a.zeit,
            breite: a.breite,
            laenge: a.laenge,
            // **Hier übersetzt und nicht in der Erkennung.** Der
            // Ländername einer Aufnahme ist englisch – so steht er in
            // der Datenbank, und dort gehört er auch hin, weil er der
            // Schlüssel ist, über den Foto und Katalog zusammenfinden.
            // Der Vorschlag heisst aber nach dem Land, und „Reise:
            // Germany" ist in einer deutschen Oberfläche kein Name,
            // sondern ein Fehler. Die Erkennung selbst bleibt frei vom
            // Übersetzungsapparat – genauso wie bei [ohneOrt].
            land: landAnzeige(a.land, sprache),
            region: a.region,
            stadt: a.stadt,
          ),
      ],
      ohneOrt: t.reisenOhneOrt,
      unverortet: ohneOrt,
      bekannteIds: zugeordnet,
      verworfen: verworfen,
    );
    if (!mounted) return;
    setState(() {
      _reisen = reisen;
      _anzahlen = anzahlen;
      _vorschlaege = vorschlaege;
      _fortschritt = fortschritt;
      _orte = orte;
      _laedt = false;
    });
  }

  /// Bestätigen — mit Rückfrage nach dem Namen.
  ///
  /// Der vorgeschlagene Name steht schon im Feld: Meistens stimmt er, und
  /// dann ist es ein Tastendruck. Wo er nicht stimmt, ist er trotzdem ein
  /// besserer Anfang als ein leeres Feld.
  Future<void> _bestaetigen(Reisevorschlag v) async {
    final t = AppTexte.of(context);
    final sauber = await frageNamen(
      context,
      titel: t.reisenBenennen,
      feldbeschriftung: t.reisenName,
      vorgabe: v.name,
    );
    if (sauber == null || !mounted) return;

    await widget.library.db.reiseAnlegen(
      ReisenCompanion.insert(
        id: const Uuid().v4(),
        name: sauber,
        von: v.von,
        bis: v.bis,
        angelegtAm: DateTime.now(),
      ),
      v.aufnahmeIds,
    );
    await _laden();
  }

  /// Eine Reise von Hand anlegen.
  ///
  /// **Der Weg neben dem Vorschlag, nicht statt seiner.** Erkannt wird nur,
  /// was Fotos hergeben – wer eine Woche ohne Kamera unterwegs war oder
  /// deren Bilder noch nicht importiert hat, hatte bisher keinen Weg,
  /// die Reise trotzdem einzutragen.
  Future<void> _selbstAnlegen() async {
    final t = AppTexte.of(context);
    final angabe = await frageZeitraum(
      context,
      titel: t.reisenSelbstAnlegen,
      db: widget.library.db,
    );
    if (angabe == null || !mounted) return;

    final aufnahmen =
        await widget.library.db.aufnahmenImZeitraum(angabe.von, angabe.bis);
    await widget.library.db.reiseAnlegen(
      ReisenCompanion.insert(
        id: const Uuid().v4(),
        name: angabe.name,
        von: angabe.von,
        bis: angabe.bis,
        angelegtAm: DateTime.now(),
      ),
      [for (final a in aufnahmen) a.id],
    );
    if (!mounted) return;
    melde.erfolg(t.reisenSelbstAngelegt(angabe.name));
    await _laden();
  }

  Future<void> _verwerfen(Reisevorschlag v) async {
    await widget.library.db.verwirfReisevorschlag(v.schluessel);
    await _laden();
  }

  Future<void> _umbenennen(ReisenData reise) async {
    final t = AppTexte.of(context);
    final sauber = await frageNamen(
      context,
      titel: t.reisenUmbenennen,
      feldbeschriftung: t.reisenName,
      vorgabe: reise.name,
    );
    if (sauber == null || !mounted) return;
    await widget.library.db
        .reiseAendern(reise.id, ReisenCompanion(name: Value(sauber)));
    await _laden();
  }

  /// Andere Reisen in [ziel] aufgehen lassen.
  ///
  /// **Das Ziel ist die Reise, in deren Menü man steht.** Sie behält
  /// Namen, Art, Titelbild und Notiz; gewählt wird nur, was
  /// hinzukommt. Andersherum – erst die Quelle wählen, dann das Ziel –
  /// müsste man sich merken, welche der beiden stehenbleibt.
  Future<void> _zusammenfuehren(ReisenData ziel) async {
    final t = AppTexte.of(context);
    final andere = [
      for (final r in _reisen)
        if (r.id != ziel.id) r,
    ];
    if (andere.isEmpty) {
      melde.hinweis(t.reisenZusammenfuehrenAllein);
      return;
    }
    final gewaehlt = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setzen) => AlertDialog(
          title: Text(t.reisenZusammenfuehrenTitel(ziel.name)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.reisenZusammenfuehrenHinweis(ziel.name)),
                const SizedBox(height: AppSpacing.sm),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final r in andere)
                        CheckboxListTile(
                          value: gewaehlt.contains(r.id),
                          onChanged: (an) => setzen(() => an == true
                              ? gewaehlt.add(r.id)
                              : gewaehlt.remove(r.id)),
                          title: Text(r.name),
                          subtitle: Text(reiseUnterzeile(
                              t, Localizations.localeOf(context),
                              von: r.von,
                              bis: r.bis,
                              naechte: naechteZwischen(von: r.von, bis: r.bis),
                              anzahl: _anzahlen[r.id] ?? 0)),
                          dense: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(t.allgAbbrechen)),
            FilledButton(
                onPressed:
                    gewaehlt.isEmpty ? null : () => Navigator.pop(dialog, true),
                child: Text(t.reisenZusammenfuehren)),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final anzahl = gewaehlt.length;
    await widget.library.db.reisenZusammenfuehren(ziel.id, gewaehlt.toList());
    if (!mounted) return;
    melde.erfolg(t.reisenZusammengefuehrt(ziel.name, anzahl));
    await _laden();
  }

  Future<void> _loeschen(ReisenData reise) async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.reisenLoeschen),
        content: Text(t.reisenLoeschenFrage(reise.name)),
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
    await widget.library.db.reiseLoeschen(reise.id);
    await _laden();
  }

  /// Die Zahlen im Kopf: wie viele Reisen, wie viele Orte, wie viele
  /// Aufnahmen. Was null wäre, fällt weg – „0 Orte" ist keine Auskunft,
  /// sondern eine Behauptung über eine Bibliothek ohne Ortsdaten.
  List<String> _kopfzahlen(AppTexte t) {
    final orte = <String>{
      for (final b in _orte.values)
        if (b.ort case final o?) o,
    };
    final aufnahmen =
        _orte.values.fold<int>(0, (summe, b) => summe + b.aufnahmen);
    return [
      t.reisenAnzahl(_reisen.length),
      if (orte.isNotEmpty) t.ortsbezugOrte(orte.length),
      if (aufnahmen > 0) t.reisenAufnahmen(aufnahmen),
    ];
  }

  Future<void> _oeffnen(ReisenData reise) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReiseDetailScreen(library: widget.library, reise: reise),
    ));
    if (mounted) await _laden();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reisenTitel),
        actions: [
          IconButton(
            tooltip: t.reisenSelbstAnlegen,
            icon: const Icon(Icons.add),
            onPressed: _selbstAnlegen,
          ),
          IconButton(
            tooltip: t.weltkarteOeffnen,
            icon: const Icon(Icons.public),
            onPressed: () => Navigator.of(context, rootNavigator: true)
                .push(MaterialPageRoute(
              builder: (_) => WeltkarteScreen(library: widget.library),
            )),
          ),
          IconButton(
            tooltip: t.laenderTitel,
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LaenderlisteScreen(library: widget.library),
            )),
          ),
          IconButton(
            tooltip: t.aktivitaetenOeffnen,
            icon: const Icon(Icons.hiking),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AktivitaetenScreen(library: widget.library),
            )),
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
                  Text(t.reisenSuchtNoch,
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            )
          : _reisen.isEmpty && _vorschlaege.isEmpty
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Center(
                    child: SizedBox(
                      width: 440,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.reisenLeer, textAlign: TextAlign.center),
                          // Ohne den Datensatz kann die App gar nicht
                          // wissen, wo etwas aufgenommen wurde – dann ist
                          // „noch keine Reise" nur die halbe Auskunft.
                          if (widget.library.geocoder == null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              t.fortschrittOhneGeodaten,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
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
                          symbol: Icons.luggage_outlined,
                          titel: t.reisenTitel,
                          zahlen: _kopfzahlen(t),
                        ),
                        if (_fortschritt case final f? when !f.istLeer) ...[
                          Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              onTap: () =>
                                  Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) =>
                                    LaenderlisteScreen(library: widget.library),
                              )),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                child: Fortschrittsbalken(fortschritt: f),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                        ],
                        if (_vorschlaege.isNotEmpty) ...[
                          _Ueberschrift(t.reisenVorschlaege),
                          for (final v in _vorschlaege)
                            _Vorschlagskarte(
                              vorschlag: v,
                              onJa: () => _bestaetigen(v),
                              onNein: () => _verwerfen(v),
                            ),
                          const SizedBox(height: AppSpacing.xl),
                        ],
                        if (_reisen.isNotEmpty)
                          _Ueberschrift(t.reisenBestaetigte)
                        else
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: Text(
                              t.reisenLeer,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ),
                      ]),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                      sliver: Kachelraster(kacheln: [
                        for (final r in _reisen)
                          Reisekachel(
                            key: ValueKey(r.id),
                            reise: r,
                            library: widget.library,
                            ort: ortszeile(t, _orte[r.id],
                                sprache: Localizations.localeOf(context)
                                    .languageCode),
                            onTippen: () => _oeffnen(r),
                            befehle: [
                              (
                                symbol: Icons.drive_file_rename_outline,
                                text: t.reisenUmbenennen,
                                tun: () => _umbenennen(r),
                              ),
                              (
                                symbol: Icons.merge_outlined,
                                text: t.reisenZusammenfuehren,
                                tun: () => _zusammenfuehren(r),
                              ),
                              (
                                symbol: Icons.delete_outline,
                                text: t.reisenLoeschen,
                                tun: () => _loeschen(r),
                              ),
                            ],
                          ),
                      ]),
                    ),
                  ],
                ),
    );
  }
}

/// Zeitraum, Nächte und Zahl der Aufnahmen in einer Zeile.
String reiseUnterzeile(
  AppTexte t,
  Locale locale, {
  required DateTime von,
  required DateTime bis,
  required int naechte,
  required int anzahl,
}) {
  final datum = DateFormat.yMMMd(locale.toString());
  return [
    t.reisenSpanne(datum.format(von), datum.format(bis)),
    t.reisenNaechte(naechte),
    t.reisenAufnahmen(anzahl),
  ].join(' · ');
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
  final Reisevorschlag vorschlag;
  final VoidCallback onJa;
  final VoidCallback onNein;

  const _Vorschlagskarte({
    required this.vorschlag,
    required this.onJa,
    required this.onNein,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
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
                Icon(Icons.luggage_outlined, color: farben.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(vorschlag.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              reiseUnterzeile(t, Localizations.localeOf(context),
                  von: vorschlag.von,
                  bis: vorschlag.bis,
                  naechte: vorschlag.naechte,
                  anzahl: vorschlag.anzahl),
              style: TextStyle(fontSize: 13, color: farben.onSurfaceVariant),
            ),
            if (vorschlag.orte.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  vorschlag.orte.take(6).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onNein, child: Text(t.reisenKeineReise)),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                    onPressed: onJa, child: Text(t.reisenIstEineReise)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Eine Reise als Kachel.
///
/// Eigenes Widget und nicht bloss ein Aufruf von [Ortskachel]: Das
/// Titelbild wird **einmal beim Anlegen** geholt und nicht in `build` –
/// sonst liefe die Abfrage bei jedem Neuaufbau erneut, und eine Liste
/// baut sich oft neu auf. Dieselbe Überlegung wie bei der Zeile, die
/// diese Kachel abgelöst hat.
class Reisekachel extends StatefulWidget {
  final ReisenData reise;
  final LibraryState library;
  final String? ort;
  final VoidCallback onTippen;
  final List<Kachelbefehl> befehle;

  const Reisekachel({
    super.key,
    required this.reise,
    required this.library,
    required this.ort,
    required this.onTippen,
    this.befehle = const [],
  });

  @override
  State<Reisekachel> createState() => _ReisekachelState();
}

class _ReisekachelState extends State<Reisekachel> {
  late final Future<AssetData?> _titelbild = _hole();

  Future<AssetData?> _hole() async {
    final id = widget.reise.titelbildAssetId;
    if (id != null) {
      final gewaehlt = await widget.library.db.assetById(id);
      if (gewaehlt != null) return gewaehlt;
    }
    // Kein gewähltes Titelbild – dann die erste Aufnahme der Reise. Ein
    // gewähltes, das inzwischen gelöscht wurde, fällt auf denselben Weg
    // zurück, statt eine leere Fläche zu zeigen.
    return widget.library.db.ersteAufnahmeDerReise(widget.reise.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return FutureBuilder<AssetData?>(
      future: _titelbild,
      builder: (context, schnappschuss) => Ortskachel(
        bild: schnappschuss.data,
        paths: widget.library.paths,
        // Das Symbol der Art und nicht immer der Koffer: In der Liste
        // sähen ein Einsatz, eine Dienstreise und ein Verwandtenbesuch
        // sonst alle gleich aus.
        symbol: symbolFuerReiseartKennung(widget.reise.art),
        name: widget.reise.name,
        kennzeichen: t.reisenNaechte(
            naechteZwischen(von: widget.reise.von, bis: widget.reise.bis)),
        zeitraum: jahresspanne(widget.reise.von, widget.reise.bis),
        ort: widget.ort,
        onTippen: widget.onTippen,
        befehle: widget.befehle,
      ),
    );
  }
}

/// Die Zahl der Nächte zwischen zwei Zeitpunkten.
///
/// Über die reinen Kalendertage gerechnet und nicht über die Differenz
/// der Zeitpunkte: Wer Freitagabend losfährt und Sonntagmorgen
/// zurückkommt, war zwei Nächte weg – die Stundenrechnung käme auf eine.
int naechteZwischen({required DateTime von, required DateTime bis}) =>
    DateTime(bis.year, bis.month, bis.day)
        .difference(DateTime(von.year, von.month, von.day))
        .inDays;

/// Der Zeitraum, so kurz, dass er auf ein Schildchen passt.
///
/// Auf dem Titelbild ist Platz für ein Jahr, nicht für zwei volle Daten.
/// Über den Jahreswechsel hinweg werden es zwei – „2024" allein wäre
/// dort schlicht falsch.
String jahresspanne(DateTime von, DateTime bis) =>
    von.year == bis.year ? '${von.year}' : '${von.year}–${bis.year}';
