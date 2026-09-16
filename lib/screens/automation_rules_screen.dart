import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';

/// Der Name eines Auslösers in der Oberflächensprache.
String _ausloeserName(AppTexte t, String art) => switch (art) {
      'location' => t.regelAusloeserOrt,
      'aiTag' => t.regelAusloeserTag,
      'dateRange' => t.regelAusloeserDatum,
      _ => art,
    };

String _formatDate(BuildContext context, DateTime d) =>
    DateFormat.yMd(Localizations.localeOf(context).toString()).format(d);

/// Verwaltung des Automatisierungs-Regelwerks: pro Regel eine Bedingung
/// (Ort/KI-Tag/Datumsbereich) und Aktionen (Zielalbum, Tags, automatisches
/// Favorisieren), die automatisch angewendet werden, sobald ein Foto die
/// Bedingung erfüllt – Verallgemeinerung der Kamera-Presets (siehe
/// CameraPresetsScreen) auf andere Auslöser. Angewendet wird das in
/// LibraryState.applyAutomationRules, an zwei Stellen je nachdem, wann die
/// Bedingung geprüft werden kann (Import-Zeit für Ort/Datum, nach der
/// KI-Tagging-Stufe der Hintergrundanalyse für KI-Tag).
class AutomationRulesScreen extends StatefulWidget {
  final LibraryState library;
  const AutomationRulesScreen({super.key, required this.library});

  @override
  State<AutomationRulesScreen> createState() => _AutomationRulesScreenState();
}

class _AutomationRulesScreenState extends State<AutomationRulesScreen> {
  late final Future<List<String>> _vocabularyFuture = widget.library.db.aiTagVocabularyTerms();

  Future<void> _editRule({AutomationRuleData? existing}) async {
    final albums = await widget.library.db.watchAlbums().first;
    final allTags = await widget.library.db.alleTags();
    final vocabulary = await _vocabularyFuture;
    final existingTagIds = existing == null
        ? <String>{}
        : (await widget.library.db.tagIdsForAutomationRule(existing.id)).toSet();
    if (!mounted) return;

    final result = await showDialog<_RuleEditResult>(
      context: context,
      builder: (context) => _AutomationRuleEditorDialog(
        existing: existing,
        vocabulary: vocabulary,
        albums: albums,
        allTags: allTags,
        initialTagIds: existingTagIds,
      ),
    );
    if (result == null) return;

    var albumId = result.existingAlbumId;
    if (result.newAlbumName != null) {
      albumId = const Uuid().v4();
      await widget.library.db.createAlbum(
        AlbumsCompanion.insert(id: albumId, name: result.newAlbumName!, createdAt: DateTime.now()),
      );
    }

    final ruleId = existing?.id ?? const Uuid().v4();
    await widget.library.db.upsertAutomationRule(AutomationRulesCompanion.insert(
      id: ruleId,
      name: result.name,
      triggerType: result.triggerType,
      regionCenterLat: Value(result.regionCenterLat),
      regionCenterLon: Value(result.regionCenterLon),
      regionRadiusKm: Value(result.regionRadiusKm),
      aiTagTerm: Value(result.aiTagTerm),
      dateFrom: Value(result.dateFrom),
      dateTo: Value(result.dateTo),
      targetAlbumId: Value(albumId),
      autoFavorite: Value(result.autoFavorite),
    ));
    await widget.library.db.setAutomationRuleTags(ruleId, result.tagIds.toList());
  }

  Future<void> _deleteRule(AutomationRuleData rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppTexte.of(context).regelLoeschenTitel),
        content: Text(AppTexte.of(context).regelLoeschenText(rule.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppTexte.of(context).allgLoeschen)),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.library.db.deleteAutomationRule(rule.id);
    }
  }

  String _conditionSummary(AutomationRuleData rule) {
    switch (rule.triggerType) {
      case 'location':
        if (rule.regionCenterLat == null || rule.regionCenterLon == null || rule.regionRadiusKm == null) {
          return AppTexte.of(context).regelOrtUnvollstaendig;
        }
        return AppTexte.of(context).regelUmkreisUm(
            rule.regionRadiusKm!.toStringAsFixed(0),
            rule.regionCenterLat!.toStringAsFixed(2),
            rule.regionCenterLon!.toStringAsFixed(2));
      case 'aiTag':
        return AppTexte.of(context).regelTagWert(rule.aiTagTerm ?? '–');
      case 'dateRange':
        if (rule.dateFrom == null || rule.dateTo == null) return AppTexte.of(context).regelDatumUnvollstaendig;
        return AppTexte.of(context).regelDatumBereich(
            _formatDate(context, rule.dateFrom!), _formatDate(context, rule.dateTo!));
      default:
        return rule.triggerType;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppTexte.of(context).regelTitel)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editRule(),
        tooltip: AppTexte.of(context).regelNeu,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<AutomationRuleData>>(
        stream: widget.library.db.watchAutomationRules(),
        builder: (context, ruleSnap) {
          if (!ruleSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rules = ruleSnap.data!;
          if (rules.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Text(
                  AppTexte.of(context).regelLeer,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return StreamBuilder<List<AlbumData>>(
            stream: widget.library.db.watchAlbums(),
            builder: (context, albumSnap) {
              final albumNames = {for (final a in albumSnap.data ?? const <AlbumData>[]) a.id: a.name};
              return StreamBuilder<List<TagData>>(
                stream: widget.library.db.watchAllTags(),
                builder: (context, tagSnap) {
                  final tagNames = {for (final t in tagSnap.data ?? const <TagData>[]) t.id: t.name};
                  return StreamBuilder<Map<String, List<String>>>(
                    stream: widget.library.db.watchAllAutomationRuleTagIds(),
                    builder: (context, ruleTagSnap) {
                      final ruleTagIds = ruleTagSnap.data ?? const <String, List<String>>{};
                      return ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: rules.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final rule = rules[index];
                          final actionParts = <String>[
                            if (rule.targetAlbumId != null && albumNames[rule.targetAlbumId] != null)
                              AppTexte.of(context).regelAlbumTeil(albumNames[rule.targetAlbumId]!),
                            if (rule.autoFavorite) AppTexte.of(context).presetFavorisieren,
                            if ((ruleTagIds[rule.id] ?? const []).isNotEmpty)
                              AppTexte.of(context).regelTagsTeil([
                                for (final id in ruleTagIds[rule.id]!)
                                  if (tagNames[id] != null) tagNames[id]!
                              ].join(', ')),
                          ];
                          return Card(
                            child: ListTile(
                              leading: Icon(switch (rule.triggerType) {
                                'location' => Icons.location_on_outlined,
                                'aiTag' => Icons.sell_outlined,
                                'dateRange' => Icons.date_range_outlined,
                                _ => Icons.rule_outlined,
                              }),
                              title: Text(rule.name),
                              subtitle: Text(
                                '${_ausloeserName(AppTexte.of(context), rule.triggerType)}'
                                ' · ${_conditionSummary(rule)}'
                                '${actionParts.isEmpty ? '' : '\n${actionParts.join(' · ')}'}',
                              ),
                              isThreeLine: actionParts.isNotEmpty,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: AppTexte.of(context).allgBearbeiten,
                                    onPressed: () => _editRule(existing: rule),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: AppTexte.of(context).allgLoeschen,
                                    onPressed: () => _deleteRule(rule),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _RuleEditResult {
  final String name;
  final String triggerType;
  final double? regionCenterLat;
  final double? regionCenterLon;
  final double? regionRadiusKm;
  final String? aiTagTerm;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? existingAlbumId;
  final String? newAlbumName;
  final bool autoFavorite;
  final Set<String> tagIds;

  const _RuleEditResult({
    required this.name,
    required this.triggerType,
    this.regionCenterLat,
    this.regionCenterLon,
    this.regionRadiusKm,
    this.aiTagTerm,
    this.dateFrom,
    this.dateTo,
    this.existingAlbumId,
    this.newAlbumName,
    required this.autoFavorite,
    required this.tagIds,
  });
}

class _AutomationRuleEditorDialog extends StatefulWidget {
  final AutomationRuleData? existing;
  final List<String> vocabulary;
  final List<AlbumData> albums;
  final List<TagData> allTags;
  final Set<String> initialTagIds;

  const _AutomationRuleEditorDialog({
    required this.existing,
    required this.vocabulary,
    required this.albums,
    required this.allTags,
    required this.initialTagIds,
  });

  @override
  State<_AutomationRuleEditorDialog> createState() => _AutomationRuleEditorDialogState();
}

class _AutomationRuleEditorDialogState extends State<_AutomationRuleEditorDialog> {
  late final _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  late final _latCtrl = TextEditingController(text: widget.existing?.regionCenterLat?.toString() ?? '');
  late final _lonCtrl = TextEditingController(text: widget.existing?.regionCenterLon?.toString() ?? '');
  late double _radiusKm = widget.existing?.regionRadiusKm ?? 25;
  late final _newAlbumCtrl = TextEditingController();
  late String _triggerType = widget.existing?.triggerType ?? 'location';
  String? _aiTagTerm;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  AlbumData? _selectedAlbum;
  late bool _autoFavorite = widget.existing?.autoFavorite ?? false;
  late Set<String> _tagIds = Set.of(widget.initialTagIds);
  String? _error;

  @override
  void initState() {
    super.initState();
    _aiTagTerm = widget.existing?.aiTagTerm ?? (widget.vocabulary.isEmpty ? null : widget.vocabulary.first);
    _dateFrom = widget.existing?.dateFrom;
    _dateTo = widget.existing?.dateTo;
    final targetId = widget.existing?.targetAlbumId;
    if (targetId != null) {
      final matches = widget.albums.where((a) => a.id == targetId);
      _selectedAlbum = matches.isEmpty ? null : matches.first;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _newAlbumCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() => isFrom ? _dateFrom = picked : _dateTo = picked);
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = AppTexte.of(context).regelNameNoetig);
      return;
    }

    double? lat, lon, radius;
    String? aiTagTerm;
    DateTime? dateFrom, dateTo;

    switch (_triggerType) {
      case 'location':
        lat = double.tryParse(_latCtrl.text.trim().replaceAll(',', '.'));
        lon = double.tryParse(_lonCtrl.text.trim().replaceAll(',', '.'));
        if (lat == null || lon == null) {
          setState(() => _error = AppTexte.of(context).regelKoordinatenUngueltig);
          return;
        }
        // Ohne diese Prüfung speicherte die Regel klaglos einen unmöglichen
        // Wert (z.B. vertauschte Ziffern) und traf danach einfach nie zu,
        // ohne dass der Nutzer je einen Hinweis bekäme (Audit-Fund).
        if (lat < -90 || lat > 90) {
          setState(() => _error = AppTexte.of(context).regelBreitengradBereich);
          return;
        }
        if (lon < -180 || lon > 180) {
          setState(() => _error = AppTexte.of(context).regelLaengengradBereich);
          return;
        }
        radius = _radiusKm;
      case 'aiTag':
        if (_aiTagTerm == null) {
          setState(() => _error = AppTexte.of(context).regelTagWaehlen);
          return;
        }
        aiTagTerm = _aiTagTerm;
      case 'dateRange':
        if (_dateFrom == null || _dateTo == null) {
          setState(() => _error = AppTexte.of(context).regelDatumWaehlen);
          return;
        }
        if (_dateFrom!.isAfter(_dateTo!)) {
          setState(() => _error = AppTexte.of(context).regelDatumReihenfolge);
          return;
        }
        dateFrom = _dateFrom;
        dateTo = _dateTo;
    }

    final newAlbumName = _newAlbumCtrl.text.trim();
    Navigator.pop(
      context,
      _RuleEditResult(
        name: name,
        triggerType: _triggerType,
        regionCenterLat: lat,
        regionCenterLon: lon,
        regionRadiusKm: radius,
        aiTagTerm: aiTagTerm,
        dateFrom: dateFrom,
        dateTo: dateTo,
        existingAlbumId: newAlbumName.isEmpty ? _selectedAlbum?.id : null,
        newAlbumName: newAlbumName.isEmpty ? null : newAlbumName,
        autoFavorite: _autoFavorite,
        tagIds: _tagIds,
      ),
    );
  }

  Widget _buildConditionFields() {
    switch (_triggerType) {
      case 'location':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latCtrl,
                    decoration: InputDecoration(labelText: AppTexte.of(context).regelBreitengrad),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lonCtrl,
                    decoration: InputDecoration(labelText: AppTexte.of(context).regelLaengengrad),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(AppTexte.of(context).regelUmkreis(_radiusKm.toStringAsFixed(0))),
            Slider(
              value: _radiusKm,
              min: 1,
              max: 200,
              divisions: 199,
              label: '${_radiusKm.toStringAsFixed(0)} km',
              onChanged: (v) => setState(() => _radiusKm = v),
            ),
          ],
        );
      case 'aiTag':
        return widget.vocabulary.isEmpty
            ? Text(AppTexte.of(context).regelKeinVokabular)
            : DropdownButtonFormField<String>(
                initialValue: _aiTagTerm,
                isExpanded: true,
                decoration: InputDecoration(labelText: AppTexte.of(context).regelTagBegriff),
                items: [
                  for (final term in widget.vocabulary) DropdownMenuItem(value: term, child: Text(term)),
                ],
                onChanged: (v) => setState(() => _aiTagTerm = v),
              );
      case 'dateRange':
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDate(isFrom: true),
                child: Text(_dateFrom == null
                    ? AppTexte.of(context).suchoptAnfangsdatum
                    : _formatDate(context, _dateFrom!)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDate(isFrom: false),
                child: Text(_dateTo == null
                    ? AppTexte.of(context).suchoptEnddatum
                    : _formatDate(context, _dateTo!)),
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTags = widget.allTags.where((t) => _tagIds.contains(t.id)).toList();
    return AlertDialog(
      title: Text(widget.existing == null
          ? AppTexte.of(context).regelNeuTitel
          : AppTexte.of(context).regelBearbeitenTitel),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: AppTexte.of(context).regelNameFeld),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _triggerType,
                isExpanded: true,
                decoration: InputDecoration(labelText: AppTexte.of(context).regelBedingung),
                items: [
                  for (final art in const ['location', 'aiTag', 'dateRange'])
                    DropdownMenuItem(
                        value: art,
                        child: Text(_ausloeserName(AppTexte.of(context), art))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _triggerType = v);
                },
              ),
              const SizedBox(height: 12),
              _buildConditionFields(),
              const SizedBox(height: 16),
              DropdownButtonFormField<AlbumData?>(
                initialValue: _selectedAlbum,
                isExpanded: true,
                decoration: InputDecoration(labelText: AppTexte.of(context).presetZielalbum),
                items: [
                  DropdownMenuItem<AlbumData?>(value: null, child: Text(AppTexte.of(context).presetKeinAlbum)),
                  for (final a in widget.albums) DropdownMenuItem<AlbumData?>(value: a, child: Text(a.name)),
                ],
                // Beide Felder meinen dasselbe Ziel (Zielalbum) – ohne das
                // gegenseitige Leeren würde die zuletzt beim Speichern
                // gelesene Eingabe die andere still überschreiben, ohne dass
                // der Nutzer merkt, welche "gewonnen" hat (Audit-Fund).
                onChanged: (a) => setState(() {
                  _selectedAlbum = a;
                  if (a != null) _newAlbumCtrl.clear();
                }),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _newAlbumCtrl,
                decoration: InputDecoration(labelText: AppTexte.of(context).presetNeuesAlbum),
                onChanged: (text) {
                  if (text.trim().isNotEmpty && _selectedAlbum != null) {
                    setState(() => _selectedAlbum = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AppTexte.of(context).presetFavorisieren),
                value: _autoFavorite,
                onChanged: (v) => setState(() => _autoFavorite = v),
              ),
              const SizedBox(height: 8),
              Text(AppTexte.of(context).suchoptTagsTitel, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              InkWell(
                onTap: () async {
                  var filter = '';
                  final selection = Set<String>.from(_tagIds);
                  final result = await showDialog<Set<String>>(
                    context: context,
                    builder: (context) => StatefulBuilder(
                      builder: (context, setDialogState) {
                        final visible = filter.isEmpty
                            ? widget.allTags
                            : widget.allTags.where((t) => t.name.toLowerCase().contains(filter.toLowerCase())).toList();
                        return AlertDialog(
                          title: Text(AppTexte.of(context).suchoptTagsWaehlen),
                          content: SizedBox(
                            width: 360,
                            height: 420,
                            child: Column(
                              children: [
                                TextField(
                                  autofocus: true,
                                  decoration: InputDecoration(
                                    hintText: AppTexte.of(context).suchoptTagsFiltern,
                                    prefixIcon: const Icon(Icons.search),
                                    isDense: true,
                                  ),
                                  onChanged: (v) => setDialogState(() => filter = v),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: visible.isEmpty
                                      ? Center(child: Text(AppTexte.of(context).presetKeineTags))
                                      : ListView(
                                          children: [
                                            for (final tag in visible)
                                              CheckboxListTile(
                                                value: selection.contains(tag.id),
                                                title: Text(tag.name),
                                                onChanged: (checked) => setDialogState(() {
                                                  checked == true ? selection.add(tag.id) : selection.remove(tag.id);
                                                }),
                                              ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: Text(AppTexte.of(context).allgAbbrechen)),
                            FilledButton(
                                onPressed: () => Navigator.pop(context, selection), child: Text(AppTexte.of(context).allgUebernehmen)),
                          ],
                        );
                      },
                    ),
                  );
                  if (result != null && mounted) setState(() => _tagIds = result);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: AppTexte.of(context).presetTagsWaehlenPlatzhalter,
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                    isDense: true,
                  ),
                  child: selectedTags.isEmpty
                      ? null
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in selectedTags)
                              Chip(
                                label: Text(tag.name),
                                onDeleted: () => setState(() => _tagIds.remove(tag.id)),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppTexte.of(context).allgAbbrechen)),
        FilledButton(onPressed: _save, child: Text(AppTexte.of(context).allgSpeichern)),
      ],
    );
  }
}
