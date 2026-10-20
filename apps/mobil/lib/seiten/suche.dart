import 'package:flutter/material.dart';
import 'alben.dart';
import 'package:uuid/uuid.dart';
import 'package:kern/services/intelligente_alben.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/laendernamen.dart';
import 'package:kern/services/search_filters.dart';
import 'package:kern/services/suchlauf.dart';

import '../bilder.dart';
import '../einfuegbares_menue.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'raster.dart';

enum _Art { inhalt, text }

/// Suchen – nach Bildinhalt („Strand bei Sonnenuntergang“) oder nach Text
/// (Schlagwort, Ort, Person, Beschreibung, Dateiname, erkannter Text,
/// Bildbeschreibung, Transkript; siehe `textfundstellen` im Kern).
///
/// Nach Inhalt bettet der Server den Suchtext ein (das Modell dafür gehört
/// nicht aufs Telefon); die Rangfolge rechnet das Telefon mit den
/// abgeglichenen Einbettungen – wie die Desktop-App.
class Suche extends StatefulWidget {
  const Suche({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<Suche> createState() => _SucheState();
}

class _SucheState extends State<Suche> {
  final _feld = TextEditingController();
  var _art = _Art.inhalt;
  var _filter = const Suchfilter();
  Suchauswahl? _auswahl;
  var _laeuft = false;
  List<Rasterzeile>? _treffer;
  String? _hinweis;

  AppDatabase get _db => widget.sitzung.db;

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  Future<void> _suche() async {
    final t = AppTexte.of(context);
    final text = _feld.text.trim();
    if (text.isEmpty && _filter.leer) {
      setState(() {
        _treffer = null;
        _hinweis = t.sucheTextOderFilter;
      });
      return;
    }
    setState(() {
      _laeuft = true;
      _hinweis = null;
    });
    try {
      final inhalt = text.isNotEmpty && _art == _Art.inhalt;
      final vektor = inhalt ? await widget.sitzung.textvektor(text) : null;
      if (inhalt && vektor == null) _hinweis = t.sucheKeinModell;
      // Ohne Modell nach Inhalt: wie bisher im Text suchen.
      final funde = await suchlauf(
        _db,
        text: text,
        art: vektor != null ? Suchart.inhalt : Suchart.text,
        filter: _filter,
        vektor: vektor,
      );
      _treffer = [for (final a in funde) Rasterzeile.aus(a)];
    } catch (_) {
      _hinweis = t.sucheFehler;
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  /// Die Suche als intelligentes Album merken – über den Befehl, damit es
  /// auch am Rechner und im Browser steht.
  Future<void> _merken() async {
    final t = AppTexte.of(context);
    final text = _feld.text.trim();
    final name = await frageAlbumname(context, vorgabe: text);
    if (name == null || !mounted) return;
    await _db.fuehreAus(
      SucheMerken(
        const Uuid().v4(),
        name,
        alsGespeicherteSuche(
          _filter,
          text: text,
          art: _art == _Art.inhalt ? Suchart.inhalt : Suchart.text,
        ),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.sucheAlsAlbumGemerkt(name))));
  }

  Future<void> _filtern() async {
    final auswahl = _auswahl ??= await suchauswahl(_db);
    if (!mounted) return;
    final neu = await showModalBottomSheet<Suchfilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _Filterblatt(
        sitzung: widget.sitzung,
        auswahl: auswahl,
        filter: _filter,
      ),
    );
    if (neu == null || !mounted) return;
    setState(() => _filter = neu);
    await _suche();
  }

  /// Was gerade gefiltert wird, als eine Zeile.
  String _filterzeile(AppTexte t, String sprache) {
    final f = _filter;
    final namen = {
      for (final p in _auswahl?.personen ?? const []) p.id: p.name,
    };
    final datum = DateFormat.yMd(sprache);
    return [
      for (final id in f.personen) namen[id] ?? '?',
      if (f.land != null) [?f.stadt, landAnzeige(f.land, sprache)].join(', '),
      if (f.von != null || f.bis != null)
        '${f.von == null ? '…' : datum.format(f.von!)} – '
            '${f.bis == null ? '…' : datum.format(f.bis!)}',
      if (f.art == MediaTypeFilter.image) t.sucheFilterFotos,
      if (f.art == MediaTypeFilter.video) t.sucheFilterVideos,
      ?f.kamera,
      if (f.favoriten) t.bibFavoriten,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final kopf = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            contextMenuBuilder: einfuegbaresMenue,
            controller: _feld,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _suche(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _art == _Art.inhalt
                  ? t.sucheHinweisInhalt
                  : t.sucheHinweisText,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<_Art>(
                  segments: [
                    ButtonSegment(
                      value: _Art.inhalt,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(t.sucheInhalt),
                    ),
                    ButtonSegment(
                      value: _Art.text,
                      icon: const Icon(Icons.text_fields),
                      label: Text(t.sucheText),
                    ),
                  ],
                  selected: {_art},
                  onSelectionChanged: (s) {
                    setState(() => _art = s.first);
                    if (_feld.text.trim().isNotEmpty) _suche();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: t.sucheFilter,
                isSelected: !_filter.leer,
                icon: const Icon(Icons.tune_rounded),
                onPressed: _filtern,
              ),
            ],
          ),
          if (!_filter.leer)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.sucheFilterZeile(_filterzeile(t, sprache)),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: t.sucheFilterZuruecksetzen,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      setState(() => _filter = const Suchfilter());
                      if (_feld.text.trim().isNotEmpty) _suche();
                    },
                  ),
                ],
              ),
            ),
          if (_laeuft) const LinearProgressIndicator(),
          if (_hinweis != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_hinweis!),
            ),
          if (_treffer != null && _treffer!.isEmpty && !_laeuft)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(t.sucheNichts, textAlign: TextAlign.center),
            ),
          // Wie im Browser (#187): die Suche als intelligentes Album.
          if (_treffer != null && !_laeuft)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _merken,
                icon: const Icon(Icons.saved_search_rounded),
                label: Text(t.sucheAlsAlbum),
              ),
            ),
        ],
      ),
    );
    return AufnahmenRaster(
      sitzung: widget.sitzung,
      zeilen: _treffer ?? const [],
      kopf: kopf,
    );
  }
}

/// Die Filter der Suche – dieselben wie im Browser: Personen (alle müssen
/// drauf sein), Land und Stadt, Zeitraum, Art, Kamera, nur Favoriten.
class _Filterblatt extends StatefulWidget {
  const _Filterblatt({
    required this.sitzung,
    required this.auswahl,
    required this.filter,
  });

  final Sitzung sitzung;
  final Suchauswahl auswahl;
  final Suchfilter filter;

  @override
  State<_Filterblatt> createState() => _FilterblattState();
}

class _FilterblattState extends State<_Filterblatt> {
  late final _personen = {...widget.filter.personen};
  late String? _land = widget.filter.land;
  late String? _stadt = widget.filter.stadt;
  late DateTime? _von = widget.filter.von;
  late DateTime? _bis = widget.filter.bis;
  late MediaTypeFilter _art = widget.filter.art;
  late String? _kamera = widget.filter.kamera;
  late bool _favoriten = widget.filter.favoriten;

  Suchfilter get _ergebnis => Suchfilter(
    personen: [
      for (final p in widget.auswahl.personen)
        if (_personen.contains(p.id)) p.id,
    ],
    land: _land,
    stadt: _stadt,
    von: _von,
    bis: _bis,
    art: _art,
    favoriten: _favoriten,
    kamera: _kamera,
  );

  Future<void> _datum(bool anfang) async {
    final jetzt = DateTime.now();
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: (anfang ? _von : _bis) ?? jetzt,
      firstDate: DateTime(1800),
      lastDate: DateTime(jetzt.year + 1),
    );
    if (gewaehlt == null) return;
    setState(() => anfang ? _von = gewaehlt : _bis = gewaehlt);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final datum = DateFormat.yMd(sprache);
    final staedte =
        widget.auswahl.orte
            .where((o) => o.land == _land)
            .firstOrNull
            ?.staedte ??
        const <String>[];
    Widget titel(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(t.sucheFilter, style: Theme.of(context).textTheme.titleMedium),
            if (widget.auswahl.personen.isNotEmpty) ...[
              titel(t.sucheFilterPersonen),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in widget.auswahl.personen)
                    FilterChip(
                      avatar: SizedBox.square(
                        dimension: 24,
                        child: Personenbild(
                          paths: widget.sitzung.paths,
                          name: p.name,
                          relativ: p.coverFaceCropPath,
                        ),
                      ),
                      label: Text(p.name),
                      selected: _personen.contains(p.id),
                      onSelected: (an) => setState(
                        () => an ? _personen.add(p.id) : _personen.remove(p.id),
                      ),
                    ),
                ],
              ),
            ],
            titel(t.sucheFilterOrt),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _land,
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(t.sucheFilterAlleLaender),
                      ),
                      for (final o in widget.auswahl.orte)
                        DropdownMenuItem(
                          value: o.land,
                          child: Text(landAnzeige(o.land, sprache)),
                        ),
                    ],
                    onChanged: (w) => setState(() {
                      _land = w;
                      _stadt = null;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _stadt,
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(t.sucheFilterAlleStaedte),
                      ),
                      for (final s in staedte)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: staedte.isEmpty
                        ? null
                        : (w) => setState(() => _stadt = w),
                  ),
                ),
              ],
            ),
            titel(t.sucheFilterZeitraum),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _datum(true),
                    child: Text(
                      _von == null ? t.sucheFilterVon : datum.format(_von!),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('–'),
                ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _datum(false),
                    child: Text(
                      _bis == null ? t.sucheFilterBis : datum.format(_bis!),
                    ),
                  ),
                ),
              ],
            ),
            titel(t.sucheFilterArt),
            SegmentedButton<MediaTypeFilter>(
              segments: [
                ButtonSegment(
                  value: MediaTypeFilter.all,
                  label: Text(t.sucheFilterAlles),
                ),
                ButtonSegment(
                  value: MediaTypeFilter.image,
                  label: Text(t.sucheFilterFotos),
                ),
                ButtonSegment(
                  value: MediaTypeFilter.video,
                  label: Text(t.sucheFilterVideos),
                ),
              ],
              selected: {_art},
              onSelectionChanged: (w) => setState(() => _art = w.first),
            ),
            if (widget.auswahl.kameras.isNotEmpty) ...[
              titel(t.sucheFilterKamera),
              DropdownButton<String?>(
                isExpanded: true,
                value: _kamera,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(t.sucheFilterAlleKameras),
                  ),
                  for (final k in widget.auswahl.kameras)
                    DropdownMenuItem(value: k, child: Text(k)),
                ],
                onChanged: (w) => setState(() => _kamera = w),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.sucheFilterFavoriten),
              value: _favoriten,
              onChanged: (w) => setState(() => _favoriten = w),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, const Suchfilter()),
                  child: Text(t.sucheFilterZuruecksetzen),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _ergebnis),
                  child: Text(t.sucheFilterAnwenden),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
