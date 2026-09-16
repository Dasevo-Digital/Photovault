import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';

import '../services/platform/folder_access.dart';
import '../services/second_library_scan_service.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import 'asset_viewer_screen.dart';
import '../services/meldungsdienst.dart';

enum _Phase { idle, scanning, loaded, error }

/// Formt eine Exception zu einem für Nutzer verständlichen Text – ohne
/// Dart-interne Präfixe wie "Bad state: " vor einer bereits selbst
/// verständlich formulierten [StateError]-Nachricht (siehe
/// loadExternalLibrary in second_library_scan_service.dart).
String _describeError(Object e) => e is StateError ? e.message : e.toString();

/// Vergleicht die eigene Bibliothek gegen eine zweite, unabhängige
/// PhotoVault-Bibliothek (z.B. auf einer externen Platte) per
/// CLIP-Bildähnlichkeit – "ist das schon in meiner Bibliothek?", bevor man
/// erneut importiert. Siehe second_library_scan_service.dart für den
/// Sicherheitsentwurf (Kopie statt Original, keine Vault-Entschlüsselung
/// nötig) und die Trennung von [loadExternalLibrary] (teuer, einmalig) und
/// [matchAgainstExternalLibrary] (günstig, bei jeder Schwellenwert-Änderung
/// wiederholbar) – analog zum Schieberegler in DuplicatesScreen, der hier
/// vorher fehlte (Audit-Fund).
/// Hoehe einer Vergleichszeile – zugleich die Dekodiergroesse der beiden
/// Vorschaubilder darin.
const double _zeilenHoehe = 120;

class SecondLibraryCompareScreen extends StatefulWidget {
  final LibraryState library;
  const SecondLibraryCompareScreen({super.key, required this.library});

  @override
  State<SecondLibraryCompareScreen> createState() => _SecondLibraryCompareScreenState();
}

class _SecondLibraryCompareScreenState extends State<SecondLibraryCompareScreen> {
  _Phase _phase = _Phase.idle;
  String? _error;
  double _threshold = 0.92;
  ExternalLibrary? _external;
  Map<String, Float32List> _ownEmbeddings = {};
  List<ExternalDuplicateMatch> _matches = [];

  Future<void> _pickAndScan() async {
    if (!widget.library.clipAvailable) {
      melde.warnung(AppTexte.of(context).allgClipNoetigKurz);
      return;
    }

    final picked = await FolderAccess.forCurrentPlatform()
        .pickFolder(message: AppTexte.of(context).zweitOrdnerWaehlen);
    if (picked == null || !mounted) return;

    setState(() {
      _phase = _Phase.scanning;
      _error = null;
    });
    try {
      _ownEmbeddings = await widget.library.cachedEmbeddings();
      _external = await loadExternalLibrary(Directory(picked.path));
      await _rematch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppTexte.of(context).zweitVergleichFehlgeschlagen(_describeError(e));
        _phase = _Phase.error;
      });
    }
  }

  /// Wertet den aktuellen [_threshold] gegen die bereits geladene [_external]
  /// aus – rein rechnerisch, keine erneute Dateisystem-/DB-Arbeit, siehe
  /// matchAgainstExternalLibrary.
  Future<void> _rematch() async {
    final external = _external;
    if (external == null) return;
    try {
      final matches = await matchAgainstExternalLibrary(
        ownDb: widget.library.db,
        ownEmbeddings: _ownEmbeddings,
        external: external,
        threshold: _threshold,
      );
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _phase = _Phase.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppTexte.of(context).zweitVergleichFehlgeschlagen(_describeError(e));
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppTexte.of(context).zweitTitel)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.idle:
        return _buildIdle();
      case _Phase.scanning:
        return const Center(child: CircularProgressIndicator());
      case _Phase.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? AppTexte.of(context).allgUnbekannterFehler,
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton(onPressed: _pickAndScan, child: Text(AppTexte.of(context).allgErneutVersuchen)),
              ],
            ),
          ),
        );
      case _Phase.loaded:
        return _buildLoaded();
    }
  }

  Widget _buildIdle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppTexte.of(context).zweitErklaerung,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _pickAndScan,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(AppTexte.of(context).zweitOrdnerKnopf),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoaded() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
          child: Row(
            children: [
              Text(AppTexte.of(context).duplAehnlichkeit),
              Expanded(
                child: Slider(
                  value: _threshold,
                  min: 0.80,
                  max: 0.99,
                  divisions: 19,
                  label: _threshold.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _threshold = v),
                  onChangeEnd: (_) => _rematch(),
                ),
              ),
              Text(_threshold.toStringAsFixed(2)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(
            AppTexte.of(context).zweitSchwelleHinweis,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const Divider(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _matches.isEmpty
                      ? AppTexte.of(context).zweitKeineTreffer
                      : AppTexte.of(context).zweitTreffer(_matches.length),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton(onPressed: _pickAndScan, child: Text(AppTexte.of(context).zweitAndererOrdner)),
            ],
          ),
        ),
        Expanded(child: _matches.isEmpty ? const SizedBox.shrink() : _buildMatchList()),
      ],
    );
  }

  Widget _buildMatchList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      itemCount: _matches.length,
      separatorBuilder: (_, __) => const Divider(height: AppSpacing.xxl),
      itemBuilder: (context, index) {
        final match = _matches[index];
        return SizedBox(
          height: 170,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppTexte.of(context).zweitAehnlichProzent((match.similarity * 100).toStringAsFixed(0)),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: AssetThumbnailTile(
                          asset: Rasterzeile.aus(match.ownAsset),
                          paths: widget.library.paths,
                          onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                            builder: (_) => AssetViewerScreen(
                              assets: [match.ownAsset],
                              initialIndex: 0,
                              paths: widget.library.paths,
                              db: widget.library.db,
                              library: widget.library,
                              onToggleFavorite: (a) => widget.library.db.setFavorite(a.id, !a.isFavorite),
                            ),
                          )),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Icon(Icons.compare_arrows, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              child: match.externalThumbnail.existsSync()
                                  ? Image.file(
                                      match.externalThumbnail,
                                      fit: BoxFit.cover,
                                      cacheWidth: (_zeilenHoehe *
                                              MediaQuery.devicePixelRatioOf(
                                                  context))
                                          .round(),
                                    )
                                  : Container(
                                      color: Colors.black26,
                                      child: const Icon(Icons.image_not_supported_outlined),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            match.externalFileName,
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          Text(AppTexte.of(context).zweitBibliothek,
                              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
