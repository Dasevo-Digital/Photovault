import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../db/database.dart';
import '../services/xmp_reader.dart';
import '../services/xmp_regionen.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';

enum _XmpDiffField { rating, colorLabel, description, tags, location, gesichter }

class _XmpDiff {
  final AssetData asset;
  final _XmpDiffField field;
  final String currentValueDisplay;
  final String xmpValueDisplay;
  final XmpFields xmpFields;

  /// Nur bei [_XmpDiffField.gesichter]: welche Gesichts-Kennung welchen
  /// Namen bekommen soll. Wird schon beim Vergleichen ermittelt, nicht erst
  /// beim Übernehmen – sonst stünde in der Liste eine Zusage, die beim
  /// Anklicken vielleicht gar nicht mehr gilt.
  final List<({String faceId, String name})> zuordnung;

  const _XmpDiff({
    required this.asset,
    required this.field,
    required this.currentValueDisplay,
    required this.xmpValueDisplay,
    required this.xmpFields,
    this.zuordnung = const [],
  });
}

/// Gegenstück zum bestehenden XMP-Export (Werkzeuge → "XMP-Sidecars
/// schreiben"): liest vorhandene XMP-Daten (z.B. extern in Lightroom/
/// darktable/digiKam bearbeitet) und zeigt, welche Werte von der DB
/// abweichen – Bewertung, Farbmarkierung, Beschreibung, Tags, GPS-Position
/// und benannte Gesichter.
///
/// **Zwei Quellen, in dieser Reihenfolge:** der Beipackzettel `.xmp` daneben,
/// und – wenn es keinen gibt – das in die Bilddatei eingebettete Paket. Der
/// Beipackzettel gewinnt, weil er das Neuere ist: Wer eine Datei extern
/// bearbeitet, bekommt einen daneben, während das eingebettete Paket den
/// Stand beim Schreiben der Datei festhält.
///
/// Ohne den zweiten Weg kam alles, was mit eingebettetem XMP und ohne
/// `.xmp` daneben ankommt, ohne Schlagwörter, ohne Bewertung und ohne
/// Namen an – und man sah es der Datei nicht an.
///
/// Ohne gesperrte Assets (deren Klartext gerade nicht ohne Weiteres
/// zugänglich ist). Muster für die Review-UI: IntegrityCheckScreen.
class XmpImportScreen extends StatefulWidget {
  final LibraryState library;
  const XmpImportScreen({super.key, required this.library});

  @override
  State<XmpImportScreen> createState() => _XmpImportScreenState();
}

class _XmpImportScreenState extends State<XmpImportScreen> {
  bool _loading = true;
  String? _error;
  List<_XmpDiff> _diffs = [];
  int _sidecarsFound = 0;

  /// Wie viele davon aus dem eingebetteten Paket statt aus einem
  /// Beipackzettel stammen – die Zahl gehört in die Meldung, sonst sähe es
  /// nach „Beipackzettel gefunden" aus, wo gar keiner liegt.
  int _eingebettetFound = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final assets = await widget.library.db.allAssetsForIntegrityCheck();
      final diffs = <_XmpDiff>[];
      var sidecarsFound = 0;
      var eingebettetFound = 0;

      for (final asset in assets) {
        if (asset.isTrashed || asset.isLocked) continue;
        final sidecarPath = widget.library.paths.xmpSidecarPath(asset.relativePath);
        final sidecarFile = widget.library.paths.absolute(sidecarPath);
        var fields = parseXmpFile(sidecarFile);
        if (fields != null) {
          sidecarsFound++;
        } else {
          fields = parseEingebettetesXmp(
              widget.library.paths.absolute(asset.relativePath));
          if (fields != null) eingebettetFound++;
        }
        if (fields == null) continue;

        if (fields.rating != null && fields.rating != asset.rating) {
          diffs.add(_XmpDiff(
            asset: asset,
            field: _XmpDiffField.rating,
            currentValueDisplay: '${asset.rating}',
            xmpValueDisplay: '${fields.rating}',
            xmpFields: fields,
          ));
        }
        if (fields.colorLabel != null && fields.colorLabel != asset.colorLabel) {
          diffs.add(_XmpDiff(
            asset: asset,
            field: _XmpDiffField.colorLabel,
            currentValueDisplay: asset.colorLabel ?? '–',
            xmpValueDisplay: fields.colorLabel!,
            xmpFields: fields,
          ));
        }
        if (fields.description != null && fields.description != asset.description) {
          diffs.add(_XmpDiff(
            asset: asset,
            field: _XmpDiffField.description,
            currentValueDisplay: asset.description ?? '–',
            xmpValueDisplay: fields.description!,
            xmpFields: fields,
          ));
        }
        if (fields.tags != null) {
          final currentTags = (await widget.library.db.tagsForAsset(asset.id)).map((t) => t.name).toSet();
          final newTags = fields.tags!.where((t) => !currentTags.contains(t)).toList();
          if (newTags.isNotEmpty) {
            diffs.add(_XmpDiff(
              asset: asset,
              field: _XmpDiffField.tags,
              currentValueDisplay: currentTags.isEmpty ? '–' : currentTags.join(', '),
              xmpValueDisplay: newTags.join(', '),
              xmpFields: fields,
            ));
          }
        }
        if (fields.latitude != null && fields.longitude != null) {
          final samePosition = asset.latitude != null &&
              asset.longitude != null &&
              (asset.latitude! - fields.latitude!).abs() < 0.0001 &&
              (asset.longitude! - fields.longitude!).abs() < 0.0001;
          if (!samePosition) {
            diffs.add(_XmpDiff(
              asset: asset,
              field: _XmpDiffField.location,
              currentValueDisplay: asset.latitude != null
                  ? '${asset.latitude!.toStringAsFixed(5)}, ${asset.longitude!.toStringAsFixed(5)}'
                  : '–',
              xmpValueDisplay: '${fields.latitude!.toStringAsFixed(5)}, ${fields.longitude!.toStringAsFixed(5)}',
              xmpFields: fields,
            ));
          }
        }
        if (fields.gesichter.isNotEmpty) {
          final zuordnung = await _gesichterZuordnen(asset, fields.gesichter);
          if (zuordnung.isNotEmpty) {
            diffs.add(_XmpDiff(
              asset: asset,
              field: _XmpDiffField.gesichter,
              // Leer, und der Satz entsteht erst beim Zeichnen: Hier läuft
              // eine Schleife mit await darin, und AppTexte.of(context) über
              // eine solche Grenze hinweg zu holen ist genau das, wovor
              // use_build_context_synchronously warnt.
              currentValueDisplay: '',
              xmpValueDisplay: zuordnung.map((z) => z.name).join(', '),
              xmpFields: fields,
              zuordnung: zuordnung,
            ));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _diffs = diffs;
        _sidecarsFound = sidecarsFound;
        _eingebettetFound = eingebettetFound;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppTexte.of(context).xmpEinlesenFehlgeschlagen('$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Welche noch namenlosen Gesichter dieses Fotos zu welcher eingelesenen
  /// Region gehören.
  ///
  /// **Nur namenlose.** Ein Gesicht, dem hier schon jemand einen Namen
  /// gegeben hat, wird nicht überschrieben – die eigene Zuordnung ist die
  /// verlässlichere, und ein stilles Umbenennen wäre der Fehler, den man
  /// erst Monate später bemerkt.
  Future<List<({String faceId, String name})>> _gesichterZuordnen(
    AssetData asset,
    List<Gesichtsregion> regionen,
  ) async {
    final gesichter = (await widget.library.db.facesForAsset(asset.id))
        .where((g) => g.personId == null && !g.isIgnored)
        .toList();
    if (gesichter.isEmpty) return const [];
    final paare = regionenZuordnen(regionen, [
      for (final g in gesichter)
        (links: g.boxX, oben: g.boxY, breite: g.boxW, hoehe: g.boxH),
    ]);
    return [
      for (final (index, region) in paare)
        (faceId: gesichter[index].id, name: region.name),
    ];
  }

  /// Die Person zu einem Namen – vorhandene bevorzugt, sonst neu angelegt.
  ///
  /// Verglichen wird ohne Rücksicht auf Gross- und Kleinschreibung: Sonst
  /// stünden nach dem Einlesen „Anna" und „anna" als zwei Personen
  /// nebeneinander, und das Zusammenführen wäre wieder Handarbeit.
  Future<String> _personFuer(String name) async {
    final vorhanden = await widget.library.db.allePersonen();
    for (final p in vorhanden) {
      if (p.name.toLowerCase() == name.toLowerCase()) return p.id;
    }
    final id = const Uuid().v4();
    await widget.library.db.createPerson(PeopleCompanion.insert(id: id, name: name));
    return id;
  }

  Future<void> _apply(_XmpDiff diff) async {
    switch (diff.field) {
      case _XmpDiffField.rating:
        await widget.library.db.setRating(diff.asset.id, diff.xmpFields.rating!);
      case _XmpDiffField.colorLabel:
        await widget.library.db.setColorLabel(diff.asset.id, diff.xmpFields.colorLabel);
      case _XmpDiffField.description:
        await widget.library.db.setDescription(diff.asset.id, diff.xmpFields.description!);
      case _XmpDiffField.tags:
        final currentTags = (await widget.library.db.tagsForAsset(diff.asset.id)).map((t) => t.name).toSet();
        for (final tag in diff.xmpFields.tags!) {
          if (!currentTags.contains(tag)) await widget.library.db.tagAsset(diff.asset.id, tag);
        }
      case _XmpDiffField.location:
        await widget.library.db.setLocation(diff.asset.id, diff.xmpFields.latitude, diff.xmpFields.longitude);
      case _XmpDiffField.gesichter:
        for (final z in diff.zuordnung) {
          final personId = await _personFuer(z.name);
          await widget.library.db.assignFacesToPerson([z.faceId], personId);
        }
    }
    setState(() => _diffs = _diffs.where((d) => d != diff).toList());
  }

  Future<void> _applyAll() async {
    for (final diff in List<_XmpDiff>.from(_diffs)) {
      await _apply(diff);
    }
  }

  String _fieldLabel(AppTexte t, _XmpDiffField field) => switch (field) {
        _XmpDiffField.rating => t.xmpFeldBewertung,
        _XmpDiffField.colorLabel => t.xmpFeldFarbmarkierung,
        _XmpDiffField.description => t.xmpFeldBeschreibung,
        _XmpDiffField.tags => t.xmpFeldNeueTags,
        _XmpDiffField.location => t.xmpFeldStandort,
        _XmpDiffField.gesichter => t.xmpFeldGesichter,
      };

  /// Die Zeile unter dem Dateinamen. Gesichter fallen aus dem Schema
  /// „alt → neu": Dort steht links keine Angabe, sondern eine Zahl.
  String _diffZeile(AppTexte t, _XmpDiff diff) {
    final feld = _fieldLabel(t, diff.field);
    if (diff.field == _XmpDiffField.gesichter) {
      return '$feld: ${t.xmpGesichterOhneNamen(diff.zuordnung.length)} → '
          '"${diff.xmpValueDisplay}"';
    }
    return '$feld: "${diff.currentValueDisplay}" → "${diff.xmpValueDisplay}"';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppTexte.of(context).werkzXmpLesenTitel),
        actions: [
          if (_diffs.isNotEmpty)
            TextButton(
              onPressed: _applyAll,
              child: Text(AppTexte.of(context).xmpAlleUebernehmen, style: const TextStyle(color: Colors.white)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppTexte.of(context).xmpErneutEinlesen,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_diffs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                _sidecarsFound + _eingebettetFound == 0
                    ? AppTexte.of(context).xmpKeineSidecars
                    : AppTexte.of(context)
                        .xmpKeineAbweichungen(_sidecarsFound + _eingebettetFound),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _diffs.length,
      itemBuilder: (context, index) {
        final diff = _diffs[index];
        return Card(
          child: ListTile(
            title: Text(diff.asset.originalFileName),
            subtitle: Text(_diffZeile(AppTexte.of(context), diff)),
            trailing: TextButton(
              onPressed: () => _apply(diff),
              child: Text(AppTexte.of(context).allgUebernehmen),
            ),
          ),
        );
      },
    );
  }
}
