import '../services/umzugsquelle.dart';
import 'package:kern/services/beilagenangaben.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/services/import_plan.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../services/groessentext.dart';
import '../state/library_state.dart';
import 'automation_rules_screen.dart';

class ImportPlanScreen extends StatefulWidget {
  const ImportPlanScreen({
    super.key,
    required this.library,
    required this.dateien,
    this.umzug,
  });
  final LibraryState library;
  final List<String> dateien;
  final Umzugsquelle? umzug;

  @override
  State<ImportPlanScreen> createState() => _ImportPlanScreenState();
}

class _ImportPlanScreenState extends State<ImportPlanScreen> {
  late final _dienst = ImportPlanDienst(
    widget.library.db,
    widget.library.importService,
  );
  ImportPlan? _plan;
  final _auswahl = <String>{};
  final _mitAngaben = <String>{};
  var _erledigt = 0;
  var _lauf = 0;
  var _bestaetigt = false;
  var _serverAlt = false;
  var _fehlgeschlagen = false;

  /// Ob der Server eine Fotokammer hat (#336) – und ob sie gewählt ist.
  /// Die Wahl gilt bis zum Beenden der App weiter.
  var _kammerMoeglich = false;
  static var _kammerZuletzt = false;
  var _kammer = _kammerZuletzt;

  @override
  void initState() {
    super.initState();
    _pruefe();
  }

  @override
  void dispose() {
    _lauf++;
    super.dispose();
  }

  Future<void> _pruefe() async {
    final lauf = ++_lauf;
    setState(() {
      _plan = null;
      _erledigt = 0;
      _fehlgeschlagen = false;
    });
    try {
      if (widget.library.abgleich case final a?) {
        final z = await a.verbindung.hole('api/v1/zustand');
        _serverAlt =
            ((z['funktionen'] as Map?)?['importplan'] as int? ?? 0) < 2 ||
            (widget.umzug != null &&
                ((z['funktionen'] as Map?)?['umzug'] as int? ?? 0) < 1);
        _kammerMoeglich =
            ((z['funktionen'] as Map?)?['fotokammer'] as int? ?? 0) >= 1;
      }
      final plan = await _dienst.erstelle(
        widget.dateien,
        abgebrochen: () => !mounted || lauf != _lauf,
        fortschritt: (n, _) {
          if (mounted && lauf == _lauf) setState(() => _erledigt = n);
        },
      );
      widget.umzug?.verbindeDubletten(plan);
      if (!mounted || lauf != _lauf) return;
      setState(() {
        _plan = plan;
        _mitAngaben
          ..clear()
          ..addAll(widget.umzug?.beilagen.keys ?? const <String>[]);
        _auswahl
          ..clear()
          ..addAll(
            plan.eintraege
                .where((e) => e.art == ImportPlanArt.neu)
                .map((e) => e.pfad),
          );
      });
    } on Object {
      if (mounted && lauf == _lauf) setState(() => _fehlgeschlagen = true);
    }
  }

  Future<void> _importiere() async {
    var plan = _plan;
    if (plan == null || plan.eintraege.isEmpty || _serverAlt) return;
    setState(() => _bestaetigt = true);
    try {
      if (plan.regelstand != await _dienst.aktuellerRegelstand()) {
        if (mounted) setState(() => _fehlgeschlagen = true);
        return;
      }
      if (widget.umzug case final quelle?) {
        plan = ImportPlan(
          eintraege: [
            for (final e in plan.eintraege)
              e.mitBeilage(
                (_mitAngaben.contains(e.pfad)
                        ? quelle.beilagen[e.pfad]
                        : null) ??
                    const Beilagenangaben(),
              ),
          ],
          regelstand: plan.regelstand,
          am: plan.am,
          spaetereRegeln: plan.spaetereRegeln,
          dateiregeln: plan.dateiregeln,
          umzug: true,
        );
      }
      final kammer = _kammerMoeglich && _kammer;
      _kammerZuletzt = _kammer;
      if (mounted) {
        Navigator.pop(
          context,
          plan.auswahl(_auswahl, mitAusgelassenen: true).mitKammer(kammer),
        );
      }
    } on Object {
      if (mounted) setState(() => _fehlgeschlagen = true);
    } finally {
      if (mounted) setState(() => _bestaetigt = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final plan = _plan;
    final bytes =
        plan?.eintraege
            .where((e) => _auswahl.contains(e.pfad))
            .fold<int>(0, (n, e) => n + (e.angaben?.bytes ?? 0)) ??
        0;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.importPlanTitel),
        actions: [
          TextButton.icon(
            onPressed: plan == null || _bestaetigt
                ? null
                : () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AutomationRulesScreen(library: widget.library),
                      ),
                    );
                    if (mounted) await _pruefe();
                  },
            icon: const Icon(Icons.rule_outlined),
            label: Text(t.importPlanRegeln),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.umzug == null
                      ? t.importPlanHinweis
                      : t.umzugPlanHinweis,
                ),
                if (plan != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    t.importPlanBilanz(
                      _auswahl.length,
                      groessentext(bytes),
                      plan.eintraege
                          .where(
                            (e) => const [
                              ImportPlanArt.vorhanden,
                              ImportPlanArt.doppelt,
                            ].contains(e.art),
                          )
                          .length,
                      plan.eintraege
                          .where(
                            (e) => const [
                              ImportPlanArt.format,
                              ImportPlanArt.fehler,
                            ].contains(e.art),
                          )
                          .length,
                    ),
                  ),
                  if (plan.spaetereRegeln > 0)
                    Text(t.importPlanSpaeter(plan.spaetereRegeln)),
                ],
                if (_serverAlt) Text(t.importPlanServerAlt),
                if (_kammerMoeglich && plan != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _kammer,
                    onChanged: _bestaetigt
                        ? null
                        : (v) => setState(() => _kammer = v),
                    title: Text(t.importKammerSchalter),
                    subtitle: Text(t.importKammerHinweis),
                  ),
                if (_fehlgeschlagen) ...[
                  Text(t.importPlanGeaendert),
                  OutlinedButton(
                    onPressed: _pruefe,
                    child: Text(t.importPlanErneut),
                  ),
                ],
              ],
            ),
          ),
          if (plan == null && !_fehlgeschlagen) ...[
            LinearProgressIndicator(
              value: widget.dateien.isEmpty
                  ? null
                  : _erledigt / widget.dateien.length,
            ),
            Text(t.importPlanFortschritt(_erledigt, widget.dateien.length)),
          ],
          Expanded(
            child: plan == null
                ? const SizedBox.shrink()
                : ListView.builder(
                    itemCount: plan.eintraege.length,
                    itemBuilder: (context, i) {
                      final e = plan.eintraege[i];
                      final status = switch (e.art) {
                        ImportPlanArt.neu => t.importPlanNeu,
                        ImportPlanArt.vorhanden => t.importPlanVorhanden,
                        ImportPlanArt.doppelt => t.importPlanDoppelt,
                        ImportPlanArt.format => t.importPlanFormat,
                        ImportPlanArt.fehler => t.importPlanFehler,
                        ImportPlanArt.beilage => t.importPlanBeilage(
                          p.basename(e.beilageZu ?? ''),
                        ),
                      };
                      final metadata = widget.umzug?.beilagen[e.pfad];
                      return Column(
                        children: [
                          CheckboxListTile(
                            value: _auswahl.contains(e.pfad),
                            onChanged: e.art != ImportPlanArt.neu || _bestaetigt
                                ? null
                                : (v) => setState(() {
                                    if (v ?? false) {
                                      _auswahl.add(e.pfad);
                                    } else {
                                      _auswahl.remove(e.pfad);
                                    }
                                  }),
                            title: Text(p.basename(e.pfad)),
                            subtitle: Text(
                              [
                                status,
                                if (e.angaben case final a?)
                                  '${DateFormat.yMd(Localizations.localeOf(context).toString()).format(a.datum)}${a.datumGeschaetzt ? ' · ${t.importPlanDatumGeschaetzt}' : ''}',
                                if (e.alben.isNotEmpty)
                                  t.importPlanAlben(e.alben.join(', ')),
                                if (e.tags.isNotEmpty)
                                  t.importPlanTags(e.tags.join(', ')),
                                if (e.favorit) t.importPlanFavorit,
                                if (e.regeln.isNotEmpty)
                                  t.importPlanTreffer(e.regeln.join(', ')),
                                if (metadata != null) ...[
                                  if (metadata.aufgenommenAm case final d?)
                                    t.umzugDatum(d.toLocal().toIso8601String()),
                                  if (metadata.sterne case final n?)
                                    t.umzugSterne(n),
                                  ?metadata.beschreibung,
                                  if (metadata.alben.isNotEmpty)
                                    t.importPlanAlben(
                                      metadata.alben.join(', '),
                                    ),
                                  if (metadata.schlagwoerter.isNotEmpty)
                                    t.importPlanTags(
                                      metadata.schlagwoerter.join(', '),
                                    ),
                                  if (metadata.breite != null)
                                    t.umzugOrt(
                                      '${metadata.breite}, ${metadata.laenge}',
                                    ),
                                ],
                                if (widget.umzug?.fehler.contains(e.pfad) ??
                                    false)
                                  t.umzugBeilageFehler,
                                if (widget.umzug?.konflikte[e.pfad]
                                    case final werte?) ...[
                                  t.umzugKonflikt,
                                  ...werte,
                                ],
                                if (e.regelnOhneZiel.isNotEmpty)
                                  t.importPlanZielGeloescht(
                                    e.regelnOhneZiel.join(', '),
                                  ),
                              ].join('\n'),
                            ),
                          ),
                          if (metadata != null && e.art == ImportPlanArt.neu)
                            CheckboxListTile(
                              dense: true,
                              title: Text(t.umzugAngabenUebernehmen),
                              value: _mitAngaben.contains(e.pfad),
                              onChanged: _bestaetigt
                                  ? null
                                  : (an) => setState(() {
                                      an == true
                                          ? _mitAngaben.add(e.pfad)
                                          : _mitAngaben.remove(e.pfad);
                                    }),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t.allgAbbrechen),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed:
                        plan == null ||
                            plan.eintraege.isEmpty ||
                            _fehlgeschlagen ||
                            _bestaetigt ||
                            _serverAlt
                        ? null
                        : _importiere,
                    child: Text(
                      _auswahl.isEmpty
                          ? t.quittungSpeichern
                          : _kammerMoeglich && _kammer
                          ? t.importPlanStartenKammer(_auswahl.length)
                          : t.importPlanStarten(_auswahl.length),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
