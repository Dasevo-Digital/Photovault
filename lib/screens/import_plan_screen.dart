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
  });
  final LibraryState library;
  final List<String> dateien;

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
  var _erledigt = 0;
  var _lauf = 0;
  var _bestaetigt = false;
  var _serverAlt = false;
  var _fehlgeschlagen = false;

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
            ((z['funktionen'] as Map?)?['importplan'] as int? ?? 0) < 2;
      }
      final plan = await _dienst.erstelle(
        widget.dateien,
        abgebrochen: () => !mounted || lauf != _lauf,
        fortschritt: (n, _) {
          if (mounted && lauf == _lauf) setState(() => _erledigt = n);
        },
      );
      if (!mounted || lauf != _lauf) return;
      setState(() {
        _plan = plan;
        _auswahl
          ..clear()
          ..addAll(
            plan.eintraege
                .where((e) => e.art == ImportPlanArt.neu && !e.ungueltigeZiele)
                .map((e) => e.pfad),
          );
      });
    } on Object {
      if (mounted && lauf == _lauf) setState(() => _fehlgeschlagen = true);
    }
  }

  Future<void> _importiere() async {
    final plan = _plan;
    if (plan == null || _auswahl.isEmpty || _serverAlt) return;
    setState(() => _bestaetigt = true);
    try {
      if (plan.regelstand != await _dienst.aktuellerRegelstand()) {
        if (mounted) setState(() => _fehlgeschlagen = true);
        return;
      }
      if (mounted) Navigator.pop(context, plan.auswahl(_auswahl));
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
                Text(t.importPlanHinweis),
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
                      };
                      return CheckboxListTile(
                        value: _auswahl.contains(e.pfad),
                        onChanged:
                            e.art != ImportPlanArt.neu ||
                                e.ungueltigeZiele ||
                                _bestaetigt
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
                            if (e.ungueltigeZiele) t.importPlanUngueltigeZiele,
                          ].join('\n'),
                        ),
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
                            _auswahl.isEmpty ||
                            _fehlgeschlagen ||
                            _bestaetigt ||
                            _serverAlt
                        ? null
                        : _importiere,
                    child: Text(t.importPlanStarten(_auswahl.length)),
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
