import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import 'package:kern/db/database.dart';
import '../services/native_image_converter.dart';
import 'package:kern/services/storage_paths.dart';
import '../theme/app_spacing.dart';
import '../widgets/video_playback.dart';
import '../services/meldungsdienst.dart';

/// Nicht-destruktiver Video-Zuschnitt: Start-/Endpunkt über eine
/// Bereichsleiste wählen, "Speichern" schneidet nativ über AVFoundation
/// (siehe ImageConverter.swift `trimVideo`) und legt das Ergebnis als
/// separate Datei unter `Assets.trimmedRelativePath` ab – das Original wird
/// nie verändert, analog zu [DevelopScreen] für Fotos. Nicht für gesperrte
/// (verschlüsselte) Assets, aus demselben Grund wie dort.
class VideoTrimScreen extends StatefulWidget {
  final AssetData asset;
  final AppDatabase db;
  final StoragePaths paths;

  const VideoTrimScreen({
    super.key,
    required this.asset,
    required this.db,
    required this.paths,
  });

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  VideoPlaybackController? _controller;
  RangeValues? _range;
  String? _fehler;
  bool _saving = false;
  bool _hasExistingTrim = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlaybackController();
    _controller = controller;
    // Verbunden liegt das Original beim Server (#109). Ohne Netz bleibt
    // es bei der Meldung unten.
    var ok = false;
    try {
      ok = await controller.open(
        await widget.paths.bereit(widget.asset.relativePath),
      );
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      // Ohne diese Prüfung bliebe der Ladekreis für immer stehen, weil
      // _range nie gesetzt wird.
      setState(() => _fehler = AppTexte.of(context).videoNichtGeoeffnet);
      return;
    }

    final existing = await widget.db.videoTrimForAsset(widget.asset.id);
    final durationSeconds = controller.duration.inMilliseconds / 1000;
    if (!mounted) return;
    setState(() {
      _hasExistingTrim = existing != null;
      _range = RangeValues(
        existing?.startSeconds ?? 0,
        existing?.endSeconds ?? durationSeconds,
      );
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  double get _durationSeconds =>
      (_controller?.duration.inMilliseconds ?? 0) / 1000;

  String _formatSeconds(double seconds) {
    final duration = Duration(milliseconds: (seconds * 1000).round());
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final secs = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  Future<void> _save() async {
    final range = _range;
    if (range == null) return;
    setState(() => _saving = true);

    // Ein neuer Name je Schnitt, und das Original erst holen – verbunden
    // liegt es beim Server (#109).
    final outputRelativePath = widget.paths.neuerSchnittpfad(widget.asset.id);
    final outputFile = widget.paths.absolute(outputRelativePath);
    await outputFile.parent.create(recursive: true);
    final vorher = widget.asset.trimmedRelativePath;

    final File quelle;
    try {
      quelle = await widget.paths.bereit(widget.asset.relativePath);
    } on Exception {
      // Weder hier noch beim Server erreichbar: Sonst blieb der Knopf tot.
      if (mounted) {
        setState(() => _saving = false);
        melde.fehler(AppTexte.of(context).videoZuschneidenFehler);
      }
      return;
    }
    final success = await NativeImageConverter.trimVideo(
      quelle,
      startSeconds: range.start,
      endSeconds: range.end,
      outputPath: outputFile.path,
    );

    if (!success) {
      if (mounted) {
        setState(() => _saving = false);
        melde.fehler(AppTexte.of(context).videoZuschneidenFehler);
      }
      return;
    }

    try {
      await widget.paths.abgelegt(outputRelativePath);
    } catch (_) {
      if (await outputFile.exists()) await outputFile.delete();
      if (mounted) {
        setState(() => _saving = false);
        melde.fehler(AppTexte.of(context).videoZuschneidenFehler);
      }
      return;
    }
    await widget.db.fuehreAus(
      SchnittSpeichern(
        widget.asset.id,
        range.start,
        range.end,
        outputRelativePath,
      ),
    );
    // Der vorige Schnitt hier; am Server bleibt er liegen (siehe
    // legeEntwicklungAb).
    if (vorher != null && vorher != outputRelativePath) {
      final alt = widget.paths.absolute(vorher);
      if (await alt.exists()) await alt.delete();
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    final vorher = widget.asset.trimmedRelativePath;
    await widget.db.fuehreAus(SchnittZuruecksetzen(widget.asset.id));
    final trimmedFile = widget.paths.absolute(
      vorher ?? widget.paths.trimmedRelativePath(widget.asset.id),
    );
    if (await trimmedFile.exists()) await trimmedFile.delete();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final range = _range;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(AppTexte.of(context).videoZuschneiden),
        actions: [
          if (_hasExistingTrim)
            TextButton(
              onPressed: _saving ? null : _reset,
              child: Text(
                AppTexte.of(context).einstZuruecksetzen,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: AppTexte.of(context).allgSpeichern,
              onPressed: _save,
            ),
        ],
      ),
      body: SafeArea(
        child: _fehler != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    _fehler!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              )
            : controller == null || !controller.isReady || range == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: controller.aspectRatio,
                        child: VideoSurface(controller: controller),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.lg,
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatSeconds(range.start),
                              style: const TextStyle(color: Colors.white70),
                            ),
                            Text(
                              _formatSeconds(range.end),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                        RangeSlider(
                          values: range,
                          min: 0,
                          max: _durationSeconds > 0 ? _durationSeconds : 1,
                          onChanged: (v) => setState(() => _range = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
