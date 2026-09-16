import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/blur_detection.dart';
import '../services/raw_formats.dart';
import '../services/search_filters.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'color_label_picker.dart';
import 'star_rating.dart';
import 'profilbild.dart';
import '../services/laendernamen.dart';

/// Panel mit allen kombinierbaren Suchfiltern (Personen, Text-Suche, Tags,
/// Kamera, Zeitraum, Medientyp, Anzeigeoptionen) – analog zu Immichs
/// "Suchoptionen". Wird als Bottom Sheet geöffnet und gibt bei "Suche" die
/// zusammengestellten [SearchFilters] über `Navigator.pop` zurück, bei
/// Abbruch `null`.
class SearchOptionsSheet extends StatefulWidget {
  final LibraryState library;
  final SearchFilters initialFilters;
  const SearchOptionsSheet({super.key, required this.library, required this.initialFilters});

  @override
  State<SearchOptionsSheet> createState() => _SearchOptionsSheetState();
}

class _SearchOptionsSheetState extends State<SearchOptionsSheet> {
  late Set<String> _personIds;
  late SearchTextMode _textMode;
  late final TextEditingController _queryController;
  late Set<String> _tagIds;
  late bool _noTag;
  String? _cameraMake;
  String? _cameraModel;
  String? _lensModel;
  String? _locationCountry;
  String? _locationState;
  String? _locationCity;
  DateTime? _startDate;
  DateTime? _endDate;
  late MediaTypeFilter _mediaType;
  late bool _favoritesOnly;
  late bool _nurGeschaetztesDatum;
  late bool _notInAnyAlbum;
  int? _minRating;
  late Set<String> _colorLabels;
  late Set<String> _formate;
  late final TextEditingController _minIsoController;
  late final TextEditingController _maxIsoController;
  late final TextEditingController _minFNumberController;
  late final TextEditingController _maxFNumberController;
  late final TextEditingController _minFocalLengthController;
  late final TextEditingController _maxFocalLengthController;

  /// UI-Vereinfachung von [SearchFilters.maxSharpnessScore]: statt eines
  /// frei einstellbaren Schwellenwerts nur ein Ja/Nein-Filter mit festem
  /// Richtwert ([blurryScoreThreshold]) – ein manuell eingestellter
  /// Zahlenwert wäre für die meisten Nutzer ohne Kontext zum Score kaum
  /// sinnvoll bedienbar.
  bool _blurryOnly = false;

  final _peopleFilterController = TextEditingController();
  String _peopleFilterText = '';

  /// Siehe [_refreshResultCountIfNeeded].
  String? _countedSignature;
  Future<int>? _resultCountFuture;

  late final Future<List<String>> _cameraMakesFuture = widget.library.db.distinctCameraMakes();
  late final Future<List<String>> _cameraModelsFuture = widget.library.db.distinctCameraModels();
  late final Future<List<String>> _lensModelsFuture = widget.library.db.distinctLensModels();
  late final Future<List<String>> _formateFuture = widget.library.db.distinctDateiformate();

  // Kaskadierend (Land -> Bundesland -> Stadt): jede Ebene schränkt die
  // darunterliegende ein, deshalb nicht `late final`, sondern bei jeder
  // Auswahl über [_onCountryChanged]/[_onStateChanged] neu zugewiesen.
  late final Future<List<String>> _countriesFuture = widget.library.db.distinctCountries();
  late Future<List<String>> _statesFuture;
  late Future<List<String>> _citiesFuture;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilters;
    _personIds = f.personIds.toSet();
    _textMode = f.textMode;
    _queryController = TextEditingController(text: f.query)
      // Löst (wie jede andere Filteränderung) einen Rebuild aus, damit
      // [_refreshResultCountIfNeeded] auch auf Texteingaben reagiert – die
      // übrigen Filter-Widgets tun das bereits über ihr jeweiliges
      // setState() in onChanged.
      ..addListener(() => setState(() {}));
    _tagIds = f.tagIds.toSet();
    _noTag = f.noTag;
    _cameraMake = f.cameraMake;
    _cameraModel = f.cameraModel;
    _lensModel = f.lensModel;
    _locationCountry = f.locationCountry;
    _locationState = f.locationState;
    _locationCity = f.locationCity;
    _statesFuture =
        _locationCountry != null ? widget.library.db.distinctStates(_locationCountry!) : Future.value(const []);
    _citiesFuture =
        _locationState != null ? widget.library.db.distinctCities(_locationState!) : Future.value(const []);
    _startDate = f.startDate;
    _endDate = f.endDate;
    _mediaType = f.mediaType;
    _favoritesOnly = f.favoritesOnly;
    _nurGeschaetztesDatum = f.nurGeschaetztesDatum;
    _notInAnyAlbum = f.notInAnyAlbum;
    _minRating = f.minRating;
    _colorLabels = f.colorLabels.toSet();
    _formate = f.formate.toSet();
    _minIsoController = TextEditingController(text: f.minIso?.toString() ?? '');
    _maxIsoController = TextEditingController(text: f.maxIso?.toString() ?? '');
    _minFNumberController = TextEditingController(text: f.minFNumber?.toString() ?? '');
    _maxFNumberController = TextEditingController(text: f.maxFNumber?.toString() ?? '');
    _minFocalLengthController = TextEditingController(text: f.minFocalLengthMm?.toString() ?? '');
    _maxFocalLengthController = TextEditingController(text: f.maxFocalLengthMm?.toString() ?? '');
    _blurryOnly = f.maxSharpnessScore != null;
  }

  void _onCountryChanged(String? country) {
    setState(() {
      _locationCountry = country;
      _locationState = null;
      _locationCity = null;
      _statesFuture = country != null ? widget.library.db.distinctStates(country) : Future.value(const []);
      _citiesFuture = Future.value(const []);
    });
  }

  void _onStateChanged(String? state) {
    setState(() {
      _locationState = state;
      _locationCity = null;
      _citiesFuture = state != null ? widget.library.db.distinctCities(state) : Future.value(const []);
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _peopleFilterController.dispose();
    _minIsoController.dispose();
    _maxIsoController.dispose();
    _minFNumberController.dispose();
    _maxFNumberController.dispose();
    _minFocalLengthController.dispose();
    _maxFocalLengthController.dispose();
    super.dispose();
  }

  void _clearAll() {
    setState(() {
      _personIds = {};
      _textMode = SearchTextMode.context;
      _queryController.clear();
      _tagIds = {};
      _noTag = false;
      _cameraMake = null;
      _cameraModel = null;
      _lensModel = null;
      _locationCountry = null;
      _locationState = null;
      _locationCity = null;
      _statesFuture = Future.value(const []);
      _citiesFuture = Future.value(const []);
      _startDate = null;
      _endDate = null;
      _mediaType = MediaTypeFilter.all;
      _favoritesOnly = false;
      _nurGeschaetztesDatum = false;
      _notInAnyAlbum = false;
      _minRating = null;
      _colorLabels = {};
      _formate = {};
      _minIsoController.clear();
      _maxIsoController.clear();
      _minFNumberController.clear();
      _maxFNumberController.clear();
      _minFocalLengthController.clear();
      _maxFocalLengthController.clear();
      _blurryOnly = false;
    });
  }

  SearchFilters _buildFilters() => SearchFilters(
        personIds: _personIds.toList(),
        textMode: _textMode,
        query: _queryController.text,
        tagIds: _tagIds.toList(),
        noTag: _noTag,
        cameraMake: _cameraMake,
        cameraModel: _cameraModel,
        lensModel: _lensModel,
        locationCountry: _locationCountry,
        locationState: _locationState,
        locationCity: _locationCity,
        startDate: _startDate,
        endDate: _endDate,
        mediaType: _mediaType,
        favoritesOnly: _favoritesOnly,
        nurGeschaetztesDatum: _nurGeschaetztesDatum,
        notInAnyAlbum: _notInAnyAlbum,
        minRating: _minRating,
        colorLabels: _colorLabels,
        formate: _formate,
        minIso: int.tryParse(_minIsoController.text.trim()),
        maxIso: int.tryParse(_maxIsoController.text.trim()),
        minFNumber: double.tryParse(_minFNumberController.text.trim().replaceAll(',', '.')),
        maxFNumber: double.tryParse(_maxFNumberController.text.trim().replaceAll(',', '.')),
        minFocalLengthMm: double.tryParse(_minFocalLengthController.text.trim().replaceAll(',', '.')),
        maxFocalLengthMm: double.tryParse(_maxFocalLengthController.text.trim().replaceAll(',', '.')),
        maxSharpnessScore: _blurryOnly ? blurryScoreThreshold : null,
      );

  void _search() => Navigator.of(context).pop(_buildFilters());

  /// Berechnet die Trefferzahl für die aktuelle Filterkombination neu, wenn
  /// sie sich seit dem letzten Aufruf tatsächlich geändert hat (Vergleich
  /// über die JSON-Signatur, da [SearchFilters] keine `==` überschreibt) –
  /// verhindert, dass jeder Rebuild (auch ohne Filteränderung) eine neue
  /// DB-Abfrage auslöst. Zeigt einen Hinweis, sobald eine nicht-leere
  /// Filterkombination 0 Treffer liefert, statt dass der Nutzer das Sheet
  /// schließt und sich über eine leere Ergebnisliste wundert.
  void _refreshResultCountIfNeeded() {
    final filters = _buildFilters();
    final signature = jsonEncode(filters.toJson());
    if (signature == _countedSignature) return;
    _countedSignature = signature;
    if (filters.isEmpty) {
      _resultCountFuture = null;
      return;
    }
    // Nur die Zahl, nicht die Treffer: Bei einem weiten Textfilter waeren
    // das 7163 vollstaendige Zeilen – je Tastendruck (88,3 gegen 10,5 ms,
    // siehe [AppDatabase.countSearchResults]).
    _resultCountFuture = widget.library.db.countSearchResults(filters);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _openTagPicker(List<TagData> allTags) async {
    var filter = '';
    final selection = Set<String>.from(_tagIds);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final visible = filter.isEmpty
              ? allTags
              : allTags.where((t) => t.name.toLowerCase().contains(filter.toLowerCase())).toList();
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
                        ? Center(child: Text(AppTexte.of(context).suchoptKeineTags))
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
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppTexte.of(context).allgAbbrechen)),
              FilledButton(
                  onPressed: () => Navigator.pop(context, selection),
                  child: Text(AppTexte.of(context).allgUebernehmen)),
            ],
          );
        },
      ),
    );
    if (result != null && mounted) setState(() => _tagIds = result);
  }

  @override
  Widget build(BuildContext context) {
    _refreshResultCountIfNeeded();
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.tune),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(AppTexte.of(context).suchoptTitel,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: AppTexte.of(context).allgSchliessen,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.lg),
                children: [
                  _buildPeopleSection(),
                  const SizedBox(height: 24),
                  _buildTextModeSection(),
                  const SizedBox(height: 24),
                  _buildTagsSection(),
                  const SizedBox(height: 24),
                  _buildRatingAndColorSection(),
                  const SizedBox(height: 24),
                  _buildCameraSection(),
                  const SizedBox(height: 24),
                  _buildRangeFiltersSection(),
                  const SizedBox(height: 24),
                  _buildLocationSection(),
                  const SizedBox(height: 24),
                  _buildDateSection(),
                  const SizedBox(height: 24),
                  _buildMediaTypeAndDisplaySection(),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_resultCountFuture != null)
              FutureBuilder<int>(
                future: _resultCountFuture,
                builder: (context, snapshot) {
                  final count = snapshot.data;
                  if (count != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 0),
                    child: Text(
                      AppTexte.of(context).suchoptKeineTreffer,
                      style: TextStyle(fontSize: 12, color: context.semantik.warnung),
                    ),
                  );
                },
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                        onPressed: _clearAll, child: Text(AppTexte.of(context).suchoptAllesLeeren)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                        onPressed: _search, child: Text(AppTexte.of(context).suchoptSuchen)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPeopleSection() {
    return StreamBuilder<List<PersonData>>(
      stream: widget.library.db.watchPeople(),
      builder: (context, snapshot) {
        final people = snapshot.data ?? [];
        final filtered = _peopleFilterText.isEmpty
            ? people
            : people
                .where((p) => p.name.toLowerCase().contains(_peopleFilterText.toLowerCase()))
                .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(AppTexte.of(context).navPersonen, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (people.length > 6)
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _peopleFilterController,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: AppTexte.of(context).suchoptPersonenFiltern,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _peopleFilterText = v),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (people.isEmpty)
              Text(AppTexte.of(context).suchoptKeinePersonenBenannt,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            else if (filtered.isEmpty)
              Text(AppTexte.of(context).suchoptKeinePersonenGefunden,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            else
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final person = filtered[index];
                    final selected = _personIds.contains(person.id);
                    return GestureDetector(
                      onTap: () => setState(() {
                        selected ? _personIds.remove(person.id) : _personIds.add(person.id);
                      }),
                      child: SizedBox(
                        width: 76,
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Profilbild(
                                  datei: person.coverFaceCropPath == null
                                      ? null
                                      : widget.library.paths.absolute(
                                          person.coverFaceCropPath!),
                                  radius: 32,
                                  hintergrund: Colors.grey.shade800,
                                  symbolgroesse: 28,
                                ),
                                if (selected)
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black45,
                                      border: Border.all(
                                        color: Theme.of(context).colorScheme.primary,
                                        width: 2,
                                      ),
                                    ),
                                    child: Icon(Icons.check_circle,
                                        color: Theme.of(context).colorScheme.primary, size: 26),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              person.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  String _textModeSectionLabel() => switch (_textMode) {
        SearchTextMode.context => AppTexte.of(context).suchoptNachKontext,
        SearchTextMode.filename => AppTexte.of(context).suchoptNachDateiname,
        SearchTextMode.description => AppTexte.of(context).suchoptNachBeschreibung,
        SearchTextMode.ocr => AppTexte.of(context).suchoptNachOcr,
        SearchTextMode.caption => AppTexte.of(context).suchoptNachCaption,
      };

  Widget _buildTextModeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppTexte.of(context).suchoptTypTitel, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          children: [
            _InlineRadio(
              value: SearchTextMode.context,
              groupValue: _textMode,
              label: AppTexte.of(context).suchoptTypKontext,
              onChanged: (v) => setState(() => _textMode = v),
            ),
            _InlineRadio(
              value: SearchTextMode.filename,
              groupValue: _textMode,
              label: AppTexte.of(context).suchoptTypDateiname,
              onChanged: (v) => setState(() => _textMode = v),
            ),
            _InlineRadio(
              value: SearchTextMode.description,
              groupValue: _textMode,
              label: AppTexte.of(context).suchoptTypBeschreibung,
              onChanged: (v) => setState(() => _textMode = v),
            ),
            _InlineRadio(
              value: SearchTextMode.ocr,
              groupValue: _textMode,
              label: AppTexte.of(context).suchoptTypOcr,
              onChanged: (v) => setState(() => _textMode = v),
            ),
            _InlineRadio(
              value: SearchTextMode.caption,
              groupValue: _textMode,
              label: AppTexte.of(context).suchoptTypCaption,
              onChanged: (v) => setState(() => _textMode = v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(_textModeSectionLabel(), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _queryController,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: switch (_textMode) {
              SearchTextMode.context => AppTexte.of(context).suchoptHintKontext,
              SearchTextMode.filename => AppTexte.of(context).suchoptHintDateiname,
              SearchTextMode.description => AppTexte.of(context).suchoptHintBeschreibung,
              SearchTextMode.ocr => AppTexte.of(context).suchoptHintOcr,
              SearchTextMode.caption => AppTexte.of(context).suchoptHintCaption,
            },
          ),
        ),
        if (_textMode == SearchTextMode.context && !widget.library.clipAvailable)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              AppTexte.of(context).suchoptClipFehlt,
              style: TextStyle(fontSize: 12, color: context.semantik.warnung),
            ),
          ),
        if (_textMode == SearchTextMode.caption && !widget.library.captioningAvailable)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              AppTexte.of(context).suchoptCaptionFehlt,
              style: TextStyle(fontSize: 12, color: context.semantik.warnung),
            ),
          ),
      ],
    );
  }

  Widget _buildTagsSection() {
    return StreamBuilder<List<TagData>>(
      stream: widget.library.db.watchAllTags(),
      builder: (context, snapshot) {
        final allTags = snapshot.data ?? [];
        final selectedTags = allTags.where((t) => _tagIds.contains(t.id)).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppTexte.of(context).suchoptTagsTitel, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            InkWell(
              onTap: _noTag || allTags.isEmpty ? null : () => _openTagPicker(allTags),
              child: InputDecorator(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: AppTexte.of(context).suchoptTagsHint,
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
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _noTag,
              onChanged: (v) => setState(() {
                _noTag = v ?? false;
                if (_noTag) _tagIds = {};
              }),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(AppTexte.of(context).suchoptOhneTag),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRatingAndColorSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppTexte.of(context).suchoptMindestbewertung,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              StarRating(
                value: _minRating ?? 0,
                onChanged: (v) => setState(() => _minRating = v == 0 ? null : v),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppTexte.of(context).suchoptFarbmarkierung,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in colorLabelSwatches.entries)
                    FilterChip(
                      label: Text(_colorLabelName(entry.key)),
                      avatar: CircleAvatar(backgroundColor: entry.value, radius: 8),
                      selected: _colorLabels.contains(entry.key),
                      onSelected: (selected) => setState(() {
                        selected ? _colorLabels.add(entry.key) : _colorLabels.remove(entry.key);
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _colorLabelName(String key) => switch (key) {
        'red' => AppTexte.of(context).farbeRot,
        'yellow' => AppTexte.of(context).farbeGelb,
        'green' => AppTexte.of(context).farbeGruen,
        'blue' => AppTexte.of(context).farbeBlau,
        'purple' => AppTexte.of(context).farbeLila,
        _ => key,
      };

  Widget _buildRangeFiltersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppTexte.of(context).suchoptAufnahmewerte, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _numberField(AppTexte.of(context).suchoptIsoVon, _minIsoController)),
            const SizedBox(width: 12),
            Expanded(child: _numberField(AppTexte.of(context).suchoptIsoBis, _maxIsoController)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _numberField(AppTexte.of(context).suchoptBlendeVon, _minFNumberController)),
            const SizedBox(width: 12),
            Expanded(child: _numberField(AppTexte.of(context).suchoptBlendeBis, _maxFNumberController)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: _numberField(AppTexte.of(context).suchoptBrennweiteVon, _minFocalLengthController)),
            const SizedBox(width: 12),
            Expanded(
                child: _numberField(AppTexte.of(context).suchoptBrennweiteBis, _maxFocalLengthController)),
          ],
        ),
        const SizedBox(height: 4),
        CheckboxListTile(
          value: _blurryOnly,
          onChanged: (v) => setState(() => _blurryOnly = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(AppTexte.of(context).suchoptNurUnscharfe),
        ),
      ],
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
    );
  }

  Widget _buildCameraSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppTexte.of(context).werkzAbschnittKamera, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _cameraDropdown(AppTexte.of(context).suchoptMarke, _cameraMakesFuture,
                  _cameraMake, (v) => setState(() => _cameraMake = v)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _cameraDropdown(AppTexte.of(context).suchoptModell, _cameraModelsFuture,
                  _cameraModel, (v) => setState(() => _cameraModel = v)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _cameraDropdown(AppTexte.of(context).suchoptObjektiv, _lensModelsFuture,
                  _lensModel, (v) => setState(() => _lensModel = v)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _formatAuswahl(),
      ],
    );
  }

  /// Die Dateiformate, die in der Bibliothek tatsaechlich vorkommen.
  ///
  /// Angeboten wird, was da ist - keine feste Liste aller Formate, die
  /// die App lesen koennte. Eine Auswahl, die zu null Treffern fuehrt,
  /// ist keine Auswahl.
  Widget _formatAuswahl() {
    return FutureBuilder<List<String>>(
      future: _formateFuture,
      builder: (context, snapshot) {
        final vorhanden = snapshot.data ?? const <String>[];
        if (vorhanden.isEmpty) return const SizedBox.shrink();

        // Nur die RAW-Formate, die es hier auch gibt. Ein Knopf, der
        // 26 Endungen auswaehlt, von denen 23 nirgends vorkommen, waere
        // eine Auswahl ohne Wirkung.
        final rawVorhanden =
            vorhanden.where(rawDateiformate.contains).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppTexte.of(context).suchoptDateiformat,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (rawVorhanden.isNotEmpty)
                  FilterChip(
                    label: Text(AppTexte.of(context).suchoptNurRaw),
                    // Ausgewaehlt nur, wenn ALLE vorhandenen RAW-Formate
                    // drin sind - sonst saehe der Knopf gesetzt aus,
                    // waehrend die Suche einen Teil davon auslaesst.
                    selected: rawVorhanden.every(_formate.contains),
                    onSelected: (gewaehlt) => setState(() {
                      gewaehlt
                          ? _formate.addAll(rawVorhanden)
                          : _formate.removeAll(rawVorhanden);
                    }),
                  ),
                for (final format in vorhanden)
                  FilterChip(
                    label: Text(format.toUpperCase()),
                    selected: _formate.contains(format),
                    onSelected: (gewaehlt) => setState(() {
                      gewaehlt ? _formate.add(format) : _formate.remove(format);
                    }),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _cameraDropdown(
    String label,
    Future<List<String>> future,
    String? value,
    ValueChanged<String?>? onChanged, {
    /// Wie ein Wert dasteht. Der Wert selbst bleibt, was in der Datenbank
    /// steht – bei Ländern ist das der englische Name.
    String Function(String)? beschriftung,
  }) {
    return FutureBuilder<List<String>>(
      future: future,
      builder: (context, snapshot) {
        final values = snapshot.data ?? [];
        // Falls der aktuell gesetzte Wert (noch) nicht in der geladenen
        // Liste steckt (z.B. während des Ladens), trotzdem als Eintrag
        // anbieten, damit DropdownButtonFormField nicht abstürzt.
        final zeige = beschriftung ?? (v) => v;
        final items = {value, ...values}.whereType<String>().toList()
          ..sort((a, b) => zeige(a).compareTo(zeige(b)));
        return DropdownButtonFormField<String?>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(value: null, child: Text(AppTexte.of(context).allgAlle)),
            for (final v in items)
              DropdownMenuItem(
                  value: v,
                  child: Text(zeige(v), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged,
        );
      },
    );
  }

  Widget _buildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppTexte.of(context).suchoptOrtTitel, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _cameraDropdown(
                AppTexte.of(context).suchoptLand,
                _countriesFuture,
                _locationCountry,
                _onCountryChanged,
                // Die Datenbank führt „Germany"; im Feld steht
                // „Deutschland", und danach ist auch sortiert.
                beschriftung: (v) => landAnzeige(
                    v, Localizations.localeOf(context).languageCode),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _cameraDropdown(AppTexte.of(context).suchoptBundesland, _statesFuture,
                  _locationState, _locationCountry == null ? null : _onStateChanged),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _cameraDropdown(AppTexte.of(context).suchoptStadt, _citiesFuture, _locationCity,
                  _locationState == null ? null : (v) => setState(() => _locationCity = v)),
            ),
          ],
        ),
        if (!widget.library.geoDataAvailable)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              AppTexte.of(context).suchoptGeoFehlt,
              style: TextStyle(fontSize: 12, color: context.semantik.warnung),
            ),
          ),
      ],
    );
  }

  Widget _buildDateSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _dateField(AppTexte.of(context).suchoptAnfangsdatum, _startDate,
              () => _pickDate(isStart: true), () => setState(() => _startDate = null)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _dateField(AppTexte.of(context).suchoptEnddatum, _endDate,
              () => _pickDate(isStart: false), () => setState(() => _endDate = null)),
        ),
      ],
    );
  }

  Widget _dateField(String label, DateTime? value, VoidCallback onTap, VoidCallback onClear) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          child: InputDecorator(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: value != null
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: AppTexte.of(context).suchoptDatumEntfernen,
                      onPressed: onClear,
                    )
                  : const Icon(Icons.calendar_today_outlined, size: 18),
            ),
            child: Text(value != null
                ? DateFormat.yMd(Localizations.localeOf(context).toString()).format(value)
                : AppTexte.of(context).suchoptDatumPlatzhalter),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaTypeAndDisplaySection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppTexte.of(context).suchoptMedientyp, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                children: [
                  _InlineRadio(
                    value: MediaTypeFilter.all,
                    groupValue: _mediaType,
                    label: AppTexte.of(context).allgAlle,
                    onChanged: (v) => setState(() => _mediaType = v),
                  ),
                  _InlineRadio(
                    value: MediaTypeFilter.image,
                    groupValue: _mediaType,
                    label: AppTexte.of(context).suchoptBild,
                    onChanged: (v) => setState(() => _mediaType = v),
                  ),
                  _InlineRadio(
                    value: MediaTypeFilter.video,
                    groupValue: _mediaType,
                    label: AppTexte.of(context).suchoptVideo,
                    onChanged: (v) => setState(() => _mediaType = v),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppTexte.of(context).suchoptAnzeigeoptionen,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _notInAnyAlbum,
                onChanged: (v) => setState(() => _notInAnyAlbum = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(AppTexte.of(context).suchoptInKeinemAlbum),
              ),
              CheckboxListTile(
                value: _favoritesOnly,
                onChanged: (v) => setState(() => _favoritesOnly = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(AppTexte.of(context).suchoptFavoriten),
              ),
              // Der Weg zu den Aufnahmen, deren Datum geraten ist – und
              // damit der Weg, sie mit der Sammelbearbeitung in einem
              // Zug richtigzustellen.
              CheckboxListTile(
                value: _nurGeschaetztesDatum,
                onChanged: (v) =>
                    setState(() => _nurGeschaetztesDatum = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(AppTexte.of(context).sucheDatumGeschaetzt),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Radio-Button + Beschriftung als ein gemeinsam antippbares Element, in
/// einer horizontalen [Wrap] nutzbar – für "Suche nach Typ" und
/// "Medientyp", analog zum Vorbild-Layout.
class _InlineRadio<T> extends StatelessWidget {
  final T value;
  final T groupValue;
  final String label;
  final ValueChanged<T> onChanged;
  const _InlineRadio({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seit Flutter 3.32 nimmt nicht mehr der Knopf selbst Wert und
            // Rückruf entgegen, sondern eine [RadioGroup] darüber. Hier steht
            // sie je Knopf, weil jeder [_InlineRadio] seinen Gruppenwert schon
            // mitbringt – ein gemeinsamer Vorfahre über die ganze Zeile hinweg
            // würde die Aufrufstellen umbauen, ohne etwas zu verbessern.
            RadioGroup<T>(
              groupValue: groupValue,
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
              child: Radio<T>(value: value),
            ),
            Text(label),
          ],
        ),
      ),
    );
  }
}
