import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';

/// Kombiniert Hersteller + Modell zu einem Anzeigenamen, analog zu
/// [cameraLabel] in asset_format.dart – hier aber für rohe Strings statt
/// eines AssetData, da ein Preset (noch) keinem konkreten Foto zugeordnet
/// sein muss.
String _cameraDisplayName(String make, String model) {
  return model.toLowerCase().startsWith(make.toLowerCase()) ? model : '$make $model';
}

/// Verwaltung von Kamera-Presets: pro erkannter Kamera (Hersteller + Modell)
/// hinterlegte Aktionen, die bei jedem künftigen Import automatisch
/// angewendet werden (Zielalbum, Tags, automatisches Favorisieren) – analog
/// zu Digikams "Kamera für den Import voreinstellen". Angewendet wird das
/// beim Import selbst (siehe LibraryState._applyCameraPreset) sowie beim
/// nachträglichen "Kameradaten einlesen" in den Werkzeugen.
class CameraPresetsScreen extends StatefulWidget {
  final LibraryState library;
  const CameraPresetsScreen({super.key, required this.library});

  @override
  State<CameraPresetsScreen> createState() => _CameraPresetsScreenState();
}

class _CameraPresetsScreenState extends State<CameraPresetsScreen> {
  late final Future<List<(String, String)>> _knownCamerasFuture = widget.library.db.distinctCameras();

  Future<void> _editPreset({CameraPresetData? existing}) async {
    final albums = await widget.library.db.watchAlbums().first;
    final allTags = await widget.library.db.alleTags();
    final knownCameras = await _knownCamerasFuture;
    final existingTagIds = existing == null
        ? <String>{}
        : (await widget.library.db.tagIdsForCameraPreset(existing.id)).toSet();
    if (!mounted) return;

    final result = await showDialog<_PresetEditResult>(
      context: context,
      builder: (context) => _CameraPresetEditorDialog(
        existing: existing,
        knownCameras: knownCameras,
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

    final presetId = existing?.id ?? const Uuid().v4();
    await widget.library.db.upsertCameraPreset(CameraPresetsCompanion.insert(
      id: presetId,
      cameraMake: result.cameraMake,
      cameraModel: result.cameraModel,
      targetAlbumId: Value(albumId),
      autoFavorite: Value(result.autoFavorite),
    ));
    await widget.library.db.setCameraPresetTags(presetId, result.tagIds.toList());
  }

  Future<void> _deletePreset(CameraPresetData preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppTexte.of(context).presetLoeschenTitel),
        content: Text(
          AppTexte.of(context).presetLoeschenText(
              _cameraDisplayName(preset.cameraMake, preset.cameraModel)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppTexte.of(context).allgLoeschen)),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.library.db.deleteCameraPreset(preset.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppTexte.of(context).presetTitel)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editPreset(),
        tooltip: AppTexte.of(context).presetNeu,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<CameraPresetData>>(
        stream: widget.library.db.watchCameraPresets(),
        builder: (context, presetSnap) {
          if (!presetSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final presets = presetSnap.data!;
          if (presets.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Text(
                  AppTexte.of(context).presetLeer,
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
                    stream: widget.library.db.watchAllCameraPresetTagIds(),
                    builder: (context, presetTagSnap) {
                      final presetTagIds = presetTagSnap.data ?? const <String, List<String>>{};
                      return ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: presets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final preset = presets[index];
                          return _CameraPresetTile(
                            key: ValueKey(preset.id),
                            preset: preset,
                            albumName: preset.targetAlbumId != null ? albumNames[preset.targetAlbumId] : null,
                            tagLabels: [
                              for (final id in presetTagIds[preset.id] ?? const <String>[])
                                if (tagNames[id] != null) tagNames[id]!,
                            ],
                            onEdit: () => _editPreset(existing: preset),
                            onDelete: () => _deletePreset(preset),
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

/// Zeigt ein einzelnes Preset. Nimmt die Tag-Bezeichnungen bereits fertig
/// aufgelöst entgegen (siehe [CameraPresetsScreen.build]s
/// `watchAllCameraPresetTagIds()`) statt selbst eine Abfrage pro Kachel zu
/// stellen – vermeidet sowohl eine N+1-Abfrage bei jedem Rebuild der Liste
/// als auch das Risiko einer zwischengespeicherten, nach einer
/// Tag-Änderung veralteten Anzeige.
class _CameraPresetTile extends StatelessWidget {
  final CameraPresetData preset;
  final String? albumName;
  final List<String> tagLabels;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CameraPresetTile({
    super.key,
    required this.preset,
    required this.albumName,
    required this.tagLabels,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final parts = <String>[
      if (albumName != null) t.presetZeileAlbum(albumName!),
      if (preset.autoFavorite) t.presetFavorisieren,
      if (tagLabels.isNotEmpty) t.presetZeileTags(tagLabels.join(', ')),
    ];
    return Card(
      child: ListTile(
        leading: const Icon(Icons.camera_alt_outlined),
        title: Text(_cameraDisplayName(preset.cameraMake, preset.cameraModel)),
        subtitle: Text(parts.isEmpty ? t.presetKeineAktion : parts.join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: t.allgBearbeiten, onPressed: onEdit),
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: t.allgLoeschen, onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class _PresetEditResult {
  final String cameraMake;
  final String cameraModel;
  final String? existingAlbumId;
  final String? newAlbumName;
  final bool autoFavorite;
  final Set<String> tagIds;

  const _PresetEditResult({
    required this.cameraMake,
    required this.cameraModel,
    this.existingAlbumId,
    this.newAlbumName,
    required this.autoFavorite,
    required this.tagIds,
  });
}

class _CameraPresetEditorDialog extends StatefulWidget {
  final CameraPresetData? existing;
  final List<(String, String)> knownCameras;
  final List<AlbumData> albums;
  final List<TagData> allTags;
  final Set<String> initialTagIds;

  const _CameraPresetEditorDialog({
    required this.existing,
    required this.knownCameras,
    required this.albums,
    required this.allTags,
    required this.initialTagIds,
  });

  @override
  State<_CameraPresetEditorDialog> createState() => _CameraPresetEditorDialogState();
}

class _CameraPresetEditorDialogState extends State<_CameraPresetEditorDialog> {
  late final _makeCtrl = TextEditingController(text: widget.existing?.cameraMake ?? '');
  late final _modelCtrl = TextEditingController(text: widget.existing?.cameraModel ?? '');
  late final _newAlbumCtrl = TextEditingController();
  AlbumData? _selectedAlbum;
  late bool _autoFavorite = widget.existing?.autoFavorite ?? false;
  late Set<String> _tagIds = Set.of(widget.initialTagIds);
  String? _error;

  @override
  void initState() {
    super.initState();
    final targetId = widget.existing?.targetAlbumId;
    if (targetId != null) {
      final matches = widget.albums.where((a) => a.id == targetId);
      _selectedAlbum = matches.isEmpty ? null : matches.first;
    }
  }

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _newAlbumCtrl.dispose();
    super.dispose();
  }

  Future<void> _openTagPicker() async {
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
              FilledButton(onPressed: () => Navigator.pop(context, selection), child: Text(AppTexte.of(context).allgUebernehmen)),
            ],
          );
        },
      ),
    );
    if (result != null && mounted) setState(() => _tagIds = result);
  }

  void _save() {
    final make = _makeCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    if (make.isEmpty || model.isEmpty) {
      setState(() => _error = AppTexte.of(context).presetHerstellerModellNoetig);
      return;
    }
    final newAlbumName = _newAlbumCtrl.text.trim();
    Navigator.pop(
      context,
      _PresetEditResult(
        cameraMake: make,
        cameraModel: model,
        existingAlbumId: newAlbumName.isEmpty ? _selectedAlbum?.id : null,
        newAlbumName: newAlbumName.isEmpty ? null : newAlbumName,
        autoFavorite: _autoFavorite,
        tagIds: _tagIds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedTags = widget.allTags.where((t) => _tagIds.contains(t.id)).toList();
    return AlertDialog(
      title: Text(widget.existing == null
          ? AppTexte.of(context).presetNeuTitel
          : AppTexte.of(context).presetBearbeitenTitel),
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
              if (widget.knownCameras.isNotEmpty) ...[
                DropdownButtonFormField<(String, String)>(
                  initialValue: null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: AppTexte.of(context).presetBekannteKamera),
                  items: [
                    for (final cam in widget.knownCameras)
                      DropdownMenuItem(value: cam, child: Text(_cameraDisplayName(cam.$1, cam.$2))),
                  ],
                  onChanged: (cam) {
                    if (cam == null) return;
                    setState(() {
                      _makeCtrl.text = cam.$1;
                      _modelCtrl.text = cam.$2;
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _makeCtrl,
                decoration: InputDecoration(labelText: AppTexte.of(context).presetHersteller),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _modelCtrl,
                decoration: InputDecoration(labelText: AppTexte.of(context).presetModell),
              ),
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
                onTap: _openTagPicker,
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
