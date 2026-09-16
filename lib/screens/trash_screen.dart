import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../db/database.dart';
import '../services/groessentext.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/empty_state.dart';
import 'asset_viewer_screen.dart';
import '../widgets/stromhalter.dart';

/// Kantenlänge einer Kachel im Raster – zugleich die Grundlage dafür, wie
/// groß das Vorschaubild dekodiert wird (siehe `cacheWidth` unten). Als
/// Konstante, damit beide Stellen nicht auseinanderlaufen können.
const double _kachelBreite = 160;

class TrashScreen extends StatefulWidget {
  final LibraryState library;
  const TrashScreen({super.key, required this.library});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final Set<String> _selected = {};

  /// **Ein** Strom für beide Leser dieses Bildschirms – die Liste und die
  /// Belegungszahl in der Titelleiste. Vorher standen zwei getrennte
  /// `watchTrash()`-Aufrufe da: dieselbe Abfrage, zweimal ausgeführt, und
  /// bei jedem Neubau erneut. An 619 liegenden Aufnahmen 3,0 ms je Abfrage.
  /// Siehe [Stromhalter].
  final _papierkorb = Stromhalter<List<AssetData>>();

  Stream<List<AssetData>> get _papierkorbstrom =>
      _papierkorb.hole('alle', () => widget.library.db.watchTrash());

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppTexte.of(context).allgLoeschen),
          ),
        ],
      ),
    );
  }

  Future<void> _permanentlyDelete(List<AssetData> toDelete) async {
    for (final asset in toDelete) {
      await widget.library.deleteAssetFilesFromDisk(asset);
    }
    await widget.library.db.deleteAssetRows(toDelete.map((a) => a.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty
            ? AppTexte.of(context).papierkorbTitel
            : AppTexte.of(context).papierkorbAusgewaehlt(_selected.length)),
        // Wieviel hier liegt, stand bisher nirgends – weder hier noch in
        // den Einstellungen. An einer gewachsenen Bibliothek waren es
        // 6,01 GB, sieben Prozent des Bestands. Unter dem Titel und nicht
        // in der Liste, damit die Zahl auch dann dasteht, wenn gerade
        // etwas ausgewählt ist.
        bottom: _selected.isNotEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: StreamBuilder<List<AssetData>>(
                  stream: _papierkorbstrom,
                  builder: (context, papierkorb) {
                    final liegend = papierkorb.data ?? const <AssetData>[];
                    if (liegend.isEmpty) return const SizedBox(height: 20);
                    final platz = liegend.fold<int>(
                        0, (summe, a) => summe + a.fileSizeBytes);
                    return Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsets.only(
                            left: AppSpacing.md, bottom: AppSpacing.sm),
                        child: Text(
                          AppTexte.of(context).papierkorbUmfang(
                              liegend.length, groessentext(platz)),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    );
                  },
                ),
              ),
        actions: [
          if (_selected.isNotEmpty) ...[
            IconButton(
              tooltip: AppTexte.of(context).einstWiederherstellen,
              icon: const Icon(Icons.restore_from_trash_outlined),
              onPressed: () async {
                await widget.library.ausPapierkorbHolen(_selected.toList());
                if (!mounted) return;
                setState(() => _selected.clear());
              },
            ),
            IconButton(
              tooltip: AppTexte.of(context).bestaetigEndgueltigLoeschen,
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed: () async {
                final confirm = await _confirm(
                    AppTexte.of(context).papierkorbEndgueltigTitel, AppTexte.of(context).papierkorbEndgueltigText(_selected.length));
                if (confirm != true) return;
                // Gezielt und nicht die ganze Tabelle: Hier stand
                // `select(assets).get()` und danach ein Filter in Dart -
                // um drei Fotos zu entfernen, wurde die gesamte
                // Bibliothek in den Speicher geholt.
                final toDelete =
                    await widget.library.db.assetsByIds(_selected.toList());
                await _permanentlyDelete(toDelete);
                if (!mounted) return;
                setState(() => _selected.clear());
              },
            ),
          ],
        ],
      ),
      body: StreamBuilder<List<AssetData>>(
        stream: _papierkorbstrom,
        builder: (context, snapshot) {
          final assets = snapshot.data ?? [];
          if (assets.isEmpty) {
            return EmptyState(icon: Icons.delete_outline, message: AppTexte.of(context).papierkorbLeer);
          }
          return Column(
            children: [
              // Der Hinweis steht da, weil die Geste sonst niemand
              // findet – und weil ein Papierkorb ohne sichtbaren Ausgang
              // genau der Befund der 16. Prüfrunde war.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        AppTexte.of(context).papierkorbHinweis,
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _raster(assets)),
            ],
          );
        },
      ),
    );
  }

  Widget _raster(List<AssetData> assets) => GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _kachelBreite,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: assets.length,
            itemBuilder: (context, index) {
              final asset = assets[index];
              final isSelected = _selected.contains(asset.id);
              return GestureDetector(
                onLongPress: () => setState(
                    () => isSelected ? _selected.remove(asset.id) : _selected.add(asset.id)),
                onTap: () {
                  if (_selected.isNotEmpty) {
                    setState(() => isSelected ? _selected.remove(asset.id) : _selected.add(asset.id));
                  } else {
                    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                      builder: (_) => AssetViewerScreen(
                        assets: assets,
                        initialIndex: index,
                        paths: widget.library.paths,
                        db: widget.library.db,
                        library: widget.library,
                      ),
                    ));
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    asset.thumbnailRelativePath != null
                        ? Image.file(
                            widget.library.paths.absolute(asset.thumbnailRelativePath!),
                            fit: BoxFit.cover,
                            // Auf Kachelgröße dekodieren statt auf die
                            // volle Vorschaugröße: Die Vorschau ist 400 px
                            // breit, die Kachel höchstens 160. Ohne diese
                            // Angabe liegt das 2,4-Fache im Bildspeicher
                            // (gemessen an echten Vorschaubildern:
                            // 2,37x Speicher, 1,53x Dekodierzeit,
                            // Prüfrunde 8) – dasselbe, was das Raster der
                            // Zeitleiste längst tut.
                            cacheWidth: (_kachelBreite *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                            errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade900),
                          )
                        : Container(
                            color: Colors.grey.shade900,
                            child: const Icon(Icons.image_outlined, color: Colors.white24),
                          ),
                    if (isSelected)
                      Container(
                        color: Colors.black45,
                        child: const Icon(Icons.check_circle, color: Colors.white),
                      ),
                    // **Sichtbar, nicht versteckt.** Bis hierher gab es
                    // das Wiederherstellen nur nach einem langen Druck –
                    // eine Geste, die niemandem gesagt wird. Der
                    // Papierkorb sah damit aus wie eine Galerie ohne
                    // Ausgang. Die Auswahl über lange Drücken bleibt für
                    // mehrere Fotos auf einmal.
                    if (_selected.isEmpty)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Tooltip(
                          message: AppTexte.of(context).einstWiederherstellen,
                          child: Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => widget.library
                                  .ausPapierkorbHolen([asset.id]),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.restore_from_trash_outlined,
                                    size: 20, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
      );
}
