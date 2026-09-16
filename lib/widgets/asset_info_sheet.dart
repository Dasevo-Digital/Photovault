import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/zeitversatz.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../screens/person_detail_screen.dart';
import '../screens/serienvergleich_screen.dart';
import '../services/reverse_geocoder.dart';
import '../services/asset_format.dart';
import '../services/bearbeitung_zuruecknehmen.dart';
import '../services/storage_paths.dart';
import '../services/textstellen.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import 'color_label_picker.dart';
import 'mini_location_map.dart';
import 'person_picker_dialog.dart';
import 'star_rating.dart';
import 'selection_action_bar.dart' show confirmDialog;
import '../services/meldungsdienst.dart';
import 'profilbild.dart';
import '../services/laendernamen.dart';

/// Info-Ansicht für ein einzelnes Asset (Foto/Video) in der Vollbildvorschau
/// – Layout angelehnt an Google Fotos: Zeilen mit Icon, Titel und optionalem
/// Untertext statt Label/Wert-Paaren, randlose Karte am unteren Ende statt
/// eingerahmt. Zeigt Beschreibung, zugeordnete Personen, Aufnahmedatum,
/// Datei-/Kamera-Metadaten, Tags und Ort – vieles davon direkt korrigierbar,
/// z.B. wenn die EXIF-Daten fehlen oder falsch sind, oder für Videos, die
/// grundsätzlich keine EXIF-GPS-Daten haben.
///
/// Ruft [onUpdated] nach jeder Änderung mit dem frisch aus der DB gelesenen
/// Asset auf, damit die aufrufende Vollbildansicht ihre Anzeige (Favorit,
/// Datum im Titel, …) synchron halten kann.
class AssetInfoSheet extends StatefulWidget {
  final AssetData asset;
  final AppDatabase db;
  final StoragePaths paths;
  final void Function(AssetData updated) onUpdated;
  final VoidCallback onClose;

  const AssetInfoSheet({
    super.key,
    required this.asset,
    required this.db,
    required this.paths,
    required this.onUpdated,
    required this.onClose,
  });

  @override
  State<AssetInfoSheet> createState() => _AssetInfoSheetState();
}

/// Eine auf diesem Foto erkannte, benannte Person samt dem Gesichts-Crop
/// AUS DIESEM FOTO (nicht dem globalen Profilbild der Person) – für die
/// Avatar-Reihe in der "Personen"-Sektion.
class _AssetFace {
  final PersonData person;
  final String? cropRelativePath;
  const _AssetFace(this.person, this.cropRelativePath);
}

class _AssetInfoSheetState extends State<AssetInfoSheet> {
  late AssetData _asset = widget.asset;
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.asset.description ?? '');
  late final FocusNode _descriptionFocusNode = FocusNode()..addListener(_onDescriptionFocusChange);
  final TextEditingController _tagController = TextEditingController();
  List<TagData> _tags = [];
  List<_AssetFace> _peopleFaces = [];

  /// Welche Fassung der KI-Bildunterschrift gerade bearbeitet wird.
  ///
  /// Anfangs die, die auch angezeigt würde: bei deutscher Oberfläche die
  /// deutsche, sofern es sie gibt. Umschalten geht über die zwei Knöpfe
  /// neben der Beschriftung – nur so kommt man an das englische Original
  /// heran, wenn eine Übersetzung vorliegt (und umgekehrt an eine deutsche
  /// Fassung, die es noch gar nicht gibt).
  bool? _kiDeutsch;

  late final TextEditingController _ortController = TextEditingController();
  bool _ortSucheLaeuft = false;

  /// Die Vorschläge unter dem Suchfeld – höchstens sechs.
  List<OrtsTreffer> _ortVorschlaege = const [];
  late final TextEditingController _kiController = TextEditingController();
  late final FocusNode _kiFocusNode = FocusNode()..addListener(_onKiFocusChange);

  @override
  void initState() {
    super.initState();
    _loadTags();
    _loadPeople();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    _kiController.dispose();
    _kiFocusNode.dispose();
    _tagController.dispose();
    _ortController.dispose();
    super.dispose();
  }

  /// Die Sprache, die beim Öffnen gezeigt wird – siehe [_kiDeutsch].
  bool _kiSpracheVorgabe(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'de' &&
      (_asset.aiCaptionDe ?? '').trim().isNotEmpty;

  String _kiText(bool deutsch) =>
      ((deutsch ? _asset.aiCaptionDe : _asset.aiCaption) ?? '').trim();

  void _onKiFocusChange() {
    if (!_kiFocusNode.hasFocus) _saveKiBeschreibung();
  }

  Future<void> _saveKiBeschreibung() async {
    final deutsch = _kiDeutsch;
    if (deutsch == null) return;
    final neu = _kiController.text.trim();
    if (neu == _kiText(deutsch)) return;
    await widget.db.setAiCaptionVonHand(_asset.id, neu, deutsch: deutsch);
    await _refresh();
  }

  /// Wechselt zwischen deutscher und englischer Fassung. Speichert vorher,
  /// damit ein Umschalten nicht wie ein Verwerfen wirkt.
  Future<void> _kiSpracheWechseln(bool deutsch) async {
    if (_kiDeutsch == deutsch) return;
    await _saveKiBeschreibung();
    if (!mounted) return;
    setState(() {
      _kiDeutsch = deutsch;
      _kiController.text = _kiText(deutsch);
    });
  }

  Future<void> _refresh() async {
    final updated = await widget.db.assetById(_asset.id);
    if (updated == null || !mounted) return;
    setState(() => _asset = updated);
    widget.onUpdated(updated);
  }

  /// Tags getrennt von [_refresh] geladen, da [AppDatabase.tagsForAsset]
  /// (anders als die restlichen Felder hier) über eine eigene Join-Abfrage
  /// läuft statt Teil der Assets-Zeile zu sein.
  Future<void> _loadTags() async {
    final tags = await widget.db.tagsForAsset(_asset.id);
    if (mounted) setState(() => _tags = tags);
  }

  Future<void> _loadPeople() async {
    final faces = await widget.db.facesForAsset(_asset.id);
    final people = await widget.db.peopleForAsset(_asset.id);
    final peopleById = {for (final p in people) p.id: p};
    final items = <_AssetFace>[];
    final seen = <String>{};
    for (final face in faces) {
      final personId = face.personId;
      if (personId == null) continue;
      final person = peopleById[personId];
      if (person == null || !seen.add(personId)) continue;
      items.add(_AssetFace(person, face.cropRelativePath));
    }
    if (mounted) setState(() => _peopleFaces = items);
  }

  Future<void> _addTag() async {
    final name = _tagController.text.trim();
    if (name.isEmpty) return;
    await widget.db.tagAsset(_asset.id, name);
    _tagController.clear();
    await _loadTags();
  }

  Future<void> _removeTag(TagData tag) async {
    await widget.db.untagAsset(_asset.id, tag.id);
    await _loadTags();
  }

  /// Ordnet das erste noch unbenannte Gesicht dieses Fotos einer (neuen oder
  /// bestehenden) Person zu. Bei mehreren unbenannten Gesichtern auf
  /// demselben Foto (mehrere Personen) lässt sich die Zuordnung durch
  /// erneutes Antippen von "+" fortsetzen.
  Future<void> _addPerson() async {
    // Vor dem ersten `await` geholt: Danach ist der Kontext nicht mehr
    // sicher da, und die Analyse mahnt das zu Recht an.
    final bibliothek = context.read<LibraryState>();
    final faces = await widget.db.facesForAsset(_asset.id);
    final unassigned = faces.where((f) => f.personId == null && !f.isIgnored).toList();
    if (unassigned.isEmpty) {
      if (mounted) {
        melde.hinweis(AppTexte.of(context).infoKeineUnbenannten,);
      }
      return;
    }
    final people = await widget.db.select(widget.db.people).get();
    final vorschlag =
        await bibliothek.personenvorschlag(unassigned.first.embedding);
    if (!mounted) return;
    final choice = await showPersonPickerDialog(context, people,
        paths: widget.paths,
        suggestedPerson: vorschlag,
        title: AppTexte.of(context).personZuordnenTitel);
    if (choice == null) return;

    String personId;
    if (choice.newName != null) {
      personId = const Uuid().v4();
      await widget.db.createPerson(PeopleCompanion.insert(id: personId, name: choice.newName!));
    } else {
      personId = choice.existingPersonId!;
    }
    await widget.db.assignFacesToPerson([unassigned.first.id], personId);
    await _loadPeople();
  }

  void _onDescriptionFocusChange() {
    if (!_descriptionFocusNode.hasFocus) _saveDescription();
  }

  Future<void> _saveDescription() async {
    if (_descriptionController.text.trim() == (_asset.description ?? '')) return;
    await widget.db.setDescription(_asset.id, _descriptionController.text.trim());
    await _refresh();
  }

  Future<void> _setRating(int rating) async {
    await widget.db.setRating(_asset.id, rating);
    await _refresh();
  }

  Future<void> _setColorLabel(String? colorLabel) async {
    await widget.db.setColorLabel(_asset.id, colorLabel);
    await _refresh();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _asset.fileCreatedAt,
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_asset.fileCreatedAt),
    );
    if (!mounted) return;
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? _asset.fileCreatedAt.hour,
      time?.minute ?? _asset.fileCreatedAt.minute,
    );
    // Über LibraryState, damit die Datei in den Ordner des neuen Monats
    // mitgeht (siehe [LibraryState.setzeAufnahmedatumVonHand]).
    await context.read<LibraryState>().setzeAufnahmedatumVonHand(
        [_asset.id], combined);
    await _refresh();
  }

  Future<void> _setLocation(double latitude, double longitude) async {
    // Über den Bibliothekszustand: Der trägt die Ortsnamen gleich nach.
    // Die Datenbankschicht allein leert sie nur (siehe
    // [AppDatabase.setLocation]), und bis zur nächsten Hintergrundaufgabe
    // stünde hier gar kein Ort mehr.
    await context
        .read<LibraryState>()
        .setzeOrtVonHand([_asset.id], latitude, longitude);
    await _refresh();
  }

  /// Setzt den Ort über seinen **Namen** statt über einen Klick auf die
  /// Karte.
  ///
  /// Für alles, was kein GPS mitbrachte – eingescannte Bilder, Fotos aus
  /// einer Kamera ohne Empfänger, Aufnahmen fremder Leute. Die Karte
  /// konnte das schon, aber nur, wenn man weiss, wo der Ort liegt; „Goslar"
  /// weiss man, 51,9° N / 10,4° O nicht.
  ///
  /// **Die Auswahl ist eine Vermutung, und die Meldung sagt das.** Gibt es
  /// den Namen mehrfach – „Springfield" über zwanzig Mal –, nennt die
  /// Antwort die Zahl der übrigen. Gewählt wird der nächstgelegene zum
  /// bisherigen Ort des Fotos, sonst der grösste; entscheidet
  /// [ReverseGeocoder.sucheOrt].
  /// Bei jedem Tastendruck: Vorschläge nachführen.
  ///
  /// Ohne Verzögerung und ohne Nebenläufigkeit – die Suche läuft auf
  /// einer Liste, die ohnehin im Speicher liegt, und braucht dafür
  /// Bruchteile einer Millisekunde. Ein Debounce wäre hier eine Lösung
  /// für ein Problem, das es nicht gibt.
  void _ortEingabe(String eingabe) {
    final geo = context.read<LibraryState>().geocoder;
    final text = eingabe.trim();
    if (geo == null || text.length < 2) {
      if (_ortVorschlaege.isNotEmpty) {
        setState(() => _ortVorschlaege = const []);
      }
      return;
    }
    // Erst die Orte zum getippten Namen. Sind es keine, den Namen selbst
    // vorschlagen – wer „Gos" tippt, meint vielleicht Goslar.
    var treffer = geo.sucheOrte(
      text,
      naheBreite: _asset.latitude,
      naheLaenge: _asset.longitude,
    );
    if (treffer.isEmpty) {
      treffer = [
        for (final name in geo.namensvorschlaege(text, hoechstens: 6))
          ...geo.sucheOrte(name,
              naheBreite: _asset.latitude,
              naheLaenge: _asset.longitude,
              hoechstens: 1)
      ];
    }
    setState(() => _ortVorschlaege = treffer);
  }

  /// Ein Vorschlag wurde angetippt.
  Future<void> _ortUebernehmen(OrtsTreffer treffer) async {
    await _setLocation(treffer.breite, treffer.laenge);
    if (!mounted) return;
    _ortController.clear();
    setState(() => _ortVorschlaege = const []);
    melde.erfolg(AppTexte.of(context).infoOrtGesetzt(
        treffer.herkunft.isEmpty
            ? treffer.name
            : '${treffer.name}, ${treffer.herkunft}'));
  }

  Future<void> _sucheOrt() async {
    final eingabe = _ortController.text.trim();
    if (eingabe.isEmpty || _ortSucheLaeuft) return;
    final t = AppTexte.of(context);
    final geo = context.read<LibraryState>().geocoder;
    if (geo == null) {
      melde.warnung(t.infoOrtKeinVerzeichnis);
      return;
    }
    setState(() => _ortSucheLaeuft = true);
    try {
      final treffer = geo.sucheOrt(
        eingabe,
        naheBreite: _asset.latitude,
        naheLaenge: _asset.longitude,
      );
      if (treffer == null) {
        melde.warnung(t.infoOrtNichtGefunden(eingabe));
        return;
      }
      await _setLocation(treffer.breite, treffer.laenge);
      if (!mounted) return;
      _ortController.clear();
      setState(() => _ortVorschlaege = const []);
      final bezeichnung = treffer.land == null
          ? treffer.name
          : '${treffer.name}, ${treffer.land}';
      melde.erfolg(treffer.weitere == 0
          ? t.infoOrtGesetzt(bezeichnung)
          : t.infoOrtGesetztMehrdeutig(bezeichnung, treffer.weitere));
    } finally {
      if (mounted) setState(() => _ortSucheLaeuft = false);
    }
  }

  Future<void> _clearLocation() async {
    await context.read<LibraryState>().setzeOrtVonHand([_asset.id], null, null);
    await _refresh();
  }

  /// Was an dieser Aufnahme bearbeitet ist, als Aufzaehlung.
  String _bearbeitungstext(AppTexte t) => [
        for (final art in bearbeitungsarten(_asset))
          switch (art) {
            Bearbeitungsart.entwickelt => t.infoBearbeitetEntwickelt,
            Bearbeitungsart.restauriert => t.infoBearbeitetRestauriert,
            Bearbeitungsart.zugeschnitten => t.infoBearbeitetZugeschnitten,
          }
      ].join(', ');

  /// Nimmt jede Bearbeitung dieser Aufnahme zurueck – siehe
  /// [originalWiederherstellen].
  ///
  /// Mit Rueckfrage: Die abgeleiteten Dateien verschwinden dabei von der
  /// Platte, und wer eine halbe Stunde an den Reglern gesessen hat, soll
  /// das nicht durch einen verrutschten Klick verlieren.
  Future<void> _originalWiederherstellen() async {
    final t = AppTexte.of(context);
    if (!await confirmDialog(
        context, t.infoOriginalHerstellen, t.infoOriginalHerstellenFrage,
        bestaetigen: t.infoOriginalHerstellen)) {
      return;
    }
    await originalWiederherstellen(
        db: widget.db, paths: widget.paths, asset: _asset);
    if (!mounted) return;
    melde.erfolg(t.infoOriginalHergestellt);
    await _refresh();
  }

  /// Löst eine Serien-Gruppierung wieder auf (siehe StackReviewScreen) – nur
  /// vom Titelbild aus erreichbar, da nur dessen Info-Panel überhaupt
  /// sichtbar ist (die übrigen Mitglieder sind aus der Rasteransicht
  /// ausgeblendet).
  Future<void> _unstack() async {
    final stackId = _asset.stackId;
    if (stackId == null) return;
    await widget.db.unstackAssets(stackId);
    await _refresh();
  }

  /// Öffnet den Serienvergleich für den Stapel dieses Titelbildes.
  Future<void> _serieVergleichen() async {
    final stackId = _asset.stackId;
    if (stackId == null) return;
    final library = context.read<LibraryState>();
    final serie = await widget.db.assetsInStack(stackId);
    if (!mounted) return;
    if (serie.length < 2) {
      melde.hinweis(AppTexte.of(context).serienvergleichZuKurz);
      return;
    }
    serie.sort((a, b) => a.fileCreatedAt.compareTo(b.fileCreatedAt));
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) =>
          SerienvergleichScreen(library: library, serie: serie),
    ));
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDuration(double seconds) {
    final total = seconds.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _fileDetailsSubtitle(AssetData asset) {
    final parts = <String>[];
    if (asset.type == 'IMAGE' && asset.widthPx != null && asset.heightPx != null) {
      final megapixels = asset.widthPx! * asset.heightPx! / 1000000;
      if (megapixels >= 0.1) {
        parts.add('${megapixels.toStringAsFixed(megapixels < 10 ? 1 : 0)} MP');
      }
      parts.add('${asset.widthPx} × ${asset.heightPx}');
    }
    if (asset.type == 'VIDEO' && asset.durationSeconds != null) {
      parts.add(_formatDuration(asset.durationSeconds!));
    }
    parts.add(_formatFileSize(asset.fileSizeBytes));
    // Das Formatkürzel (HEIC, DNG, JPG) gehört zu den Angaben, nach denen
    // man in dieser Ansicht sucht – bisher stand es nur als kleines
    // Abzeichen an der Kachel in der Übersicht.
    final format = assetFormatLabel(asset);
    if (format.isNotEmpty) parts.add(format);
    return parts.join('   ');
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    // Kamera und Aufnahmewerte, aufgeteilt wie in den Informationen von
    // macOS Fotos: oben das Gerät, darunter das Objektiv, darunter die
    // Werte-Zeile. Vorher standen Zeit/ISO in der einen und
    // Blende/Brennweite in einer zweiten Zeile mit eigenem Symbol – wer die
    // Aufnahme beurteilen wollte, musste sie aus zwei Zeilen
    // zusammensuchen, und die Belichtungskorrektur fehlte ganz.
    final kameraTitel = cameraLabel(asset);
    // Nur der Objektivname, ohne die Brennweite noch einmal daneben: An
    // einer echten iPhone-Aufnahme geprüft steht sie im Namen bereits drin
    // („iPhone 13 Pro back triple camera 5.7mm f/1.5"), und in der
    // Werte-Zeile darunter ohnehin.
    final objektiv = asset.lensModel != kameraTitel ? asset.lensModel : null;
    final werte = aufnahmewerte(asset);

    final hasLocation = asset.latitude != null && asset.longitude != null;
    final sprache = Localizations.localeOf(context).toString();

    // Welche Fassung der KI-Bildunterschrift bearbeitet wird.
    //
    // Das Beschreibungsmodell liefert ausschliesslich Englisch; die deutsche
    // Fassung steht in einer eigenen Spalte, sobald sie übersetzt wurde
    // (siehe LibraryState.uebersetzeBildbeschreibungen).
    //
    // Die Vorgabe wird beim ersten Aufbau festgehalten und danach nur noch
    // von den Umschaltknöpfen geändert – sonst spränge das Feld beim
    // Speichern zurück, sobald jemand die deutsche Fassung leert.
    final kiDeutsch = _kiDeutsch ??= _kiSpracheVorgabe(context);
    final kiVorhanden = (asset.aiCaption ?? '').trim().isNotEmpty ||
        (asset.aiCaptionDe ?? '').trim().isNotEmpty;
    if (!_kiFocusNode.hasFocus && _kiController.text != _kiText(kiDeutsch)) {
      _kiController.text = _kiText(kiDeutsch);
    }
    // Der Ortsdatensatz kennt Länder nur englisch; die Region kommt
    // unverändert durch (siehe [landAnzeige]).
    final regionParts = [
      asset.locationState,
      landAnzeige(asset.locationCountry,
          Localizations.localeOf(context).languageCode),
    ].whereType<String>().where((s) => s.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.close), tooltip: AppTexte.of(context).allgSchliessen, onPressed: widget.onClose),
              const SizedBox(width: 4),
              Text(AppTexte.of(context).infoTitel, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _descriptionController,
                        focusNode: _descriptionFocusNode,
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: AppTexte.of(context).infoBeschreibungHinzufuegen,
                          border: const UnderlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      if (kiVorhanden) ...[
                        const SizedBox(height: 12),
                        _KiBeschreibung(
                          controller: _kiController,
                          focusNode: _kiFocusNode,
                          deutsch: kiDeutsch,
                          vonHand: asset.aiCaptionEdited,
                          onSprache: _kiSpracheWechseln,
                        ),
                        // Bei einem Video ruht alles Erkannte auf einem
                        // einzigen Standbild. Das gehört dazugesagt: Wer
                        // „drei Personen" liest, nimmt sonst an, der ganze
                        // Film sei durchsucht worden.
                        if (asset.type == 'VIDEO') ...[
                          const SizedBox(height: 6),
                          Text(
                            AppTexte.of(context).infoVideoStandbild,
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
                      if ((asset.ocrText ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _ErkannterText(
                          text: asset.ocrText!.trim(),
                          stellen: textstellenAusJson(asset.ocrBoxen).length,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Semantics(
                            container: true,
                            label: AppTexte.of(context).infoBewertung,
                            child: StarRating(value: _asset.rating, onChanged: _setRating),
                          ),
                          const Spacer(),
                          Semantics(
                            container: true,
                            label: AppTexte.of(context).suchoptFarbmarkierung,
                            child: ColorLabelPicker(value: _asset.colorLabel, onChanged: _setColorLabel),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Expanded(child: _SectionLabel(AppTexte.of(context).navPersonen)),
                          IconButton(
                            icon: const Icon(Icons.add),
                            tooltip: AppTexte.of(context).personZuordnenTitel,
                            onPressed: _addPerson,
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 72,
                        child: _peopleFaces.isEmpty
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  AppTexte.of(context).infoNiemandZugeordnet,
                                  style: TextStyle(color: onSurfaceVariant, fontSize: 13),
                                ),
                              )
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _peopleFaces.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final item = _peopleFaces[index];
                                  return GestureDetector(
                                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => PersonDetailScreen(
                                        library: context.read<LibraryState>(),
                                        person: item.person,
                                      ),
                                    )),
                                    child: Column(
                                      children: [
                                        Profilbild(
                                          datei: item.cropRelativePath == null
                                              ? null
                                              : widget.paths.absolute(
                                                  item.cropRelativePath!),
                                          radius: 26,
                                          hintergrund: Colors.grey.shade800,
                                        ),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          width: 60,
                                          child: Text(
                                            item.person.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 16),

                      _SectionLabel(AppTexte.of(context).infoDetails),
                      const SizedBox(height: 4),
                      // Die Uhrzeit weicht der Auskunft, wenn das Datum
                      // geraten ist: Sie wäre die genaueste Angabe im
                      // ganzen Blatt und zugleich die einzige, die sicher
                      // nicht stimmt. Bei 948 Aufnahmen dieser Bibliothek
                      // stünde dort „00:00:00" – eine Sekundenangabe, die
                      // aus dem Dateisystem stammt.
                      _IconDetailRow(
                        icon: asset.datumGeschaetzt
                            ? Icons.event_busy_outlined
                            : Icons.calendar_today_outlined,
                        title: DateFormat.yMMMd(sprache).format(asset.fileCreatedAt),
                        // Die Zeitzone steht hinter der Uhrzeit, nicht
                        // statt ihrer: Der Zeitstempel ist und bleibt die
                        // ORTSZEIT der Kamera, und die ist die Zeit, an
                        // die man sich erinnert. Der Versatz sagt nur
                        // dazu, in welcher Zone sie galt - ob die
                        // Aufnahmen aus Mazar-e Sharif um 16 Uhr in
                        // Berlin oder um 18:30 vor Ort entstanden.
                        subtitle: asset.datumGeschaetzt
                            ? AppTexte.of(context).infoDatumGeschaetzt
                            : [
                                DateFormat.E(sprache)
                                    .addPattern(', ')
                                    .add_Hms()
                                    .format(asset.fileCreatedAt),
                                if (asset.zeitversatzMinuten case final v?)
                                  zeitversatzText(v),
                              ].join(' · '),
                        onEdit: _pickDate,
                      ),
                      _IconDetailRow(
                        icon: asset.type == 'VIDEO' ? Icons.videocam_outlined : Icons.image_outlined,
                        title: asset.originalFileName,
                        subtitle: _fileDetailsSubtitle(asset),
                      ),
                      // Der Weg zurueck. Nicht-destruktiv zu arbeiten
                      // heisst, dass es ihn gibt - nur stand er bisher
                      // allein in dem Werkzeug, das die Aenderung gemacht
                      // hat, und hiess dort "Zuruecksetzen". Wer eine
                      // Aufnahme vor sich hat, sieht hier, DASS sie
                      // bearbeitet ist, WAS an ihr bearbeitet ist und
                      // kommt mit einem Klick auf das Original zurueck.
                      if (bearbeitungsarten(_asset).isNotEmpty)
                        _IconDetailRow(
                          icon: Icons.auto_fix_high_outlined,
                          title: AppTexte.of(context).infoBearbeitet,
                          subtitle: AppTexte.of(context).infoOriginalUnberuehrt(
                              _bearbeitungstext(AppTexte.of(context))),
                          onEdit: _originalWiederherstellen,
                          editIcon: Icons.restore,
                          editTooltip:
                              AppTexte.of(context).infoOriginalHerstellen,
                        ),
                      if (kameraTitel != null || werte.isNotEmpty)
                        _Aufnahmeblock(
                          kamera: kameraTitel ?? asset.lensModel,
                          objektiv: objektiv,
                          werte: werte,
                        ),
                      // Ein geerbter Ort steht hier mit anderem Zeichen und
                      // sagt es in der Unterzeile: Er ist eine begruendete
                      // Vermutung aus den Nachbaraufnahmen, keine Messung.
                      // Die Region weicht dafuer – wer wissen will, wo das
                      // ungefaehr war, liest den Ortsnamen; wer wissen will,
                      // wie sicher das ist, braucht diesen Satz.
                      if (hasLocation)
                        _IconDetailRow(
                          icon: asset.ortGeerbt
                              ? Icons.share_location_outlined
                              : Icons.location_on_outlined,
                          title: asset.locationCity ?? AppTexte.of(context).infoStandortBekannt,
                          subtitle: asset.ortGeerbt
                              ? AppTexte.of(context).infoOrtGeerbt
                              : asset.locationCity != null
                                  ? (regionParts.isEmpty ? null : regionParts.join(', '))
                                  : AppTexte.of(context).infoOrtNichtAufgeloest,
                          onEdit: _clearLocation,
                          editIcon: Icons.close,
                          editTooltip: AppTexte.of(context).infoOrtEntfernen,
                        ),
                      if (asset.isStackCover && asset.stackSize != null) ...[
                        _IconDetailRow(
                          icon: Icons.filter_none_outlined,
                          title: AppTexte.of(context).infoSerie(asset.stackSize!),
                          subtitle: AppTexte.of(context).infoNurTitelbild,
                          onEdit: _unstack,
                          editIcon: Icons.close,
                          editTooltip: AppTexte.of(context).infoSerieAufloesen,
                        ),
                        // Der zweite Weg in den Vergleich – der erste liegt
                        // beim Zusammenfassen. Danach kommt man dort nicht
                        // mehr hin, und genau dann will man ihn: Wer eine
                        // Serie gestapelt hat, sucht später das beste Bild
                        // darin.
                        Padding(
                          padding: const EdgeInsets.only(left: 40, top: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _serieVergleichen,
                              icon: const Icon(
                                  Icons.face_retouching_natural, size: 18),
                              label: Text(AppTexte.of(context)
                                  .serienvergleichOeffnen),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      _SectionLabel(AppTexte.of(context).suchoptTagsTitel),
                      const SizedBox(height: 8),
                      if (_tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final tag in _tags)
                                InputChip(
                                  label: Text(tag.name),
                                  onDeleted: () => _removeTag(tag),
                                ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tagController,
                              decoration: InputDecoration(
                                hintText: AppTexte.of(context).infoTagHinzufuegenPlatzhalter,
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => _addTag(),
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.add), tooltip: AppTexte.of(context).auswTagHinzufuegen, onPressed: _addTag),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                // Über der Karte und nicht darunter: Wer den Ortsnamen
                // kennt, soll ihn eintippen können, ohne erst zu suchen,
                // wo auf der Karte er liegt.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ortController,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: AppTexte.of(context).infoOrtSuchen,
                            hintText: AppTexte.of(context).infoOrtSuchenBeispiel,
                            prefixIcon: const Icon(Icons.travel_explore, size: 20),
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: _ortEingabe,
                          onSubmitted: (_) => _sucheOrt(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton(
                        tooltip: AppTexte.of(context).infoOrtSuchen,
                        icon: _ortSucheLaeuft
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.search),
                        onPressed: _ortSucheLaeuft ? null : _sucheOrt,
                      ),
                    ],
                  ),
                ),
                // Die Vorschläge. **Der eigentliche Umbau**: Bis hierher
                // entschied die Suche sofort und sagte erst hinterher,
                // dass die Wahl eine Vermutung war („es gibt 23 weitere
                // gleichen Namens"). Wer den Ort seines Fotos kennt, will
                // ihn auswählen, nicht hinterher berichtigen.
                if (_ortVorschlaege.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                    child: Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final v in _ortVorschlaege)
                            ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: const Icon(Icons.place_outlined,
                                  size: 18),
                              title: Text(v.name),
                              subtitle: v.herkunft.isEmpty
                                  ? null
                                  : Text(v.herkunft),
                              // Die Einwohnerzahl beantwortet „welches
                              // Berlin?", ohne dass jemand die Landkarte
                              // im Kopf haben muss.
                              trailing: v.einwohner == 0
                                  ? null
                                  : Text(
                                      NumberFormat.compact(
                                              locale: Localizations.localeOf(
                                                      context)
                                                  .toString())
                                          .format(v.einwohner),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                    ),
                              onTap: () => _ortUebernehmen(v),
                            ),
                        ],
                      ),
                    ),
                  ),
                MiniLocationMap(
                  latitude: asset.latitude,
                  longitude: asset.longitude,
                  onLocationChanged: _setLocation,
                  height: 200,
                  borderRadius: BorderRadius.zero,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

/// Eine Detailzeile im Google-Fotos-Stil: Icon links, Titel + optionaler
/// grauer Untertext in der Mitte, optionales Icon-Button-Symbol rechts
/// (z.B. Stift zum Bearbeiten oder "X" zum Entfernen).
class _IconDetailRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onEdit;
  final IconData editIcon;
  final String? editTooltip;

  const _IconDetailRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onEdit,
    this.editIcon = Icons.edit_outlined,
    this.editTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: onSurfaceVariant),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(fontSize: 12, color: onSurfaceVariant)),
                ],
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              icon: Icon(editIcon, size: 18),
              tooltip: editTooltip ?? AppTexte.of(context).allgBearbeiten,
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}

/// Kamera, Objektiv und die Aufnahmewerte als ein Block – dieselbe
/// Gliederung wie in den Informationen von macOS Fotos.
///
/// Die Werte-Zeile bricht um, statt abgeschnitten zu werden: Das Bedienfeld
/// ist schmal, und fünf Werte nebeneinander passen darin nicht immer. Eine
/// abgeschnittene Verschlusszeit wäre schlimmer als eine zweite Zeile.
class _Aufnahmeblock extends StatelessWidget {
  final String? kamera;
  final String? objektiv;
  final List<String> werte;

  const _Aufnahmeblock({required this.kamera, required this.objektiv, required this.werte});

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.camera_alt_outlined, size: 20, color: farben.onSurfaceVariant),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kamera != null) Text(kamera!),
                if (objektiv != null) ...[
                  const SizedBox(height: 2),
                  Text(objektiv!,
                      style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant)),
                ],
                if (werte.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: farben.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        for (final wert in werte)
                          Text(
                            wert,
                            style: TextStyle(
                              fontSize: 12,
                              color: farben.onSurfaceVariant,
                              // Damit die Werte zweier Fotos untereinander
                              // fluchten, wenn man durch die Bibliothek geht.
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Die KI-Bildunterschrift – anders als früher nicht nur zu lesen.
///
/// Warum überhaupt bearbeitbar: Das Modell trifft den Inhalt oft, aber
/// nicht immer, und die Sätze sind durchsuchbar. Eine Zeile richtigzustellen
/// ist billiger, als ein ganzes Modell besser zu machen. Der Freitext
/// darüber bleibt davon getrennt – der gehört dem Nutzer, diese Zeile ist
/// eine korrigierte Maschinenausgabe.
///
/// Die beiden Sprachknöpfe stehen auch dann da, wenn es die andere Fassung
/// noch nicht gibt: Nur so lässt sich eine deutsche Bildunterschrift von
/// Hand anlegen, ohne erst das Übersetzungsmodell zu bemühen.
/// Der von der Texterkennung gelesene Text – markierbar und kopierbar.
///
/// Bis Schema 60 lag er ausschliesslich in der Datenbank und war
/// ausschliesslich durchsuchbar: 2406 von 7988 Aufnahmen dieser Bibliothek
/// trugen einen Text, den niemand lesen konnte. Das Anzeigen kostet nichts,
/// die Zeichenkette liegt längst da.
class _ErkannterText extends StatelessWidget {
  final String text;

  /// Wie viele Stellen im Bild dazu bekannt sind. Null heisst: Der Text
  /// stammt aus einem Lauf vor Schema 60 und hat noch keine Kästen – dann
  /// steht die Zeile nicht da, statt „0 Stellen" zu behaupten.
  final int stellen;

  const _ErkannterText({required this.text, required this.stellen});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.text_fields, size: 16, color: farben.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(child: _SectionLabel(t.infoErkannterText)),
            IconButton(
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              visualDensity: VisualDensity.compact,
              tooltip: t.infoTextKopieren,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                melde.erfolg(t.infoTextKopiert);
              },
            ),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: farben.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          // Markierbar und nicht nur lesbar: Der halbe Nutzen einer
          // Texterkennung ist, eine Telefonnummer vom Schild abzunehmen,
          // ohne sie abzutippen.
          child: SelectableText(
            text,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (stellen > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              t.infoTextStellen(stellen),
              style: TextStyle(fontSize: 11, color: farben.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _KiBeschreibung extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool deutsch;
  final bool vonHand;
  final void Function(bool deutsch) onSprache;

  const _KiBeschreibung({
    required this.controller,
    required this.focusNode,
    required this.deutsch,
    required this.vonHand,
    required this.onSprache,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                vonHand ? t.infoKiBeschreibungVonHand : t.infoKiBeschreibung,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: farben.onSurfaceVariant),
              ),
            ),
            for (final istDeutsch in [true, false])
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _Sprachknopf(
                  beschriftung: istDeutsch ? t.infoSpracheDe : t.infoSpracheEn,
                  aktiv: deutsch == istDeutsch,
                  onTap: () => onSprache(istDeutsch),
                ),
              ),
          ],
        ),
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: null,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: farben.onSurfaceVariant,
              ),
          decoration: InputDecoration(
            hintText: deutsch ? t.infoKiPlatzhalterDe : t.infoKiPlatzhalterEn,
            border: const UnderlineInputBorder(),
            isDense: true,
          ),
        ),
        if (vonHand) ...[
          const SizedBox(height: 4),
          Text(t.infoKiVonHandHinweis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: farben.onSurfaceVariant)),
        ],
      ],
    );
  }
}

/// „DE"/„EN" als kleiner, flacher Umschalter – ein SegmentedButton wäre für
/// zwei Kürzel neben einer Beschriftung deutlich zu wuchtig.
class _Sprachknopf extends StatelessWidget {
  final String beschriftung;
  final bool aktiv;
  final VoidCallback onTap;
  const _Sprachknopf({required this.beschriftung, required this.aktiv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          beschriftung,
          style: TextStyle(
            fontSize: 11,
            fontWeight: aktiv ? FontWeight.w700 : FontWeight.w400,
            color: aktiv ? farben.primary : farben.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
