import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../db/database.dart';
import '../services/native_image_converter.dart';
import '../services/storage_paths.dart';
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

  const VideoTrimScreen({super.key, required this.asset, required this.db, required this.paths});

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
    final ok = await controller.open(widget.paths.absolute(widget.asset.relativePath));
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

  double get _durationSeconds => (_controller?.duration.inMilliseconds ?? 0) / 1000;

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

    final outputRelativePath = widget.paths.trimmedRelativePath(widget.asset.id);
    final outputFile = widget.paths.absolute(outputRelativePath);
    await outputFile.parent.create(recursive: true);

    final success = await NativeImageConverter.trimVideo(
      widget.paths.absolute(widget.asset.relativePath),
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

    await widget.db.saveVideoTrim(
      widget.asset.id,
      startSeconds: range.start,
      endSeconds: range.end,
      trimmedRelativePath: outputRelativePath,
    );

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    await widget.db.resetVideoTrim(widget.asset.id);
    final trimmedFile = widget.paths.absolute(widget.paths.trimmedRelativePath(widget.asset.id));
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
              child: Text(AppTexte.of(context).einstZuruecksetzen, style: const TextStyle(color: Colors.white70)),
            ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(icon: const Icon(Icons.check), tooltip: AppTexte.of(context).allgSpeichern, onPressed: _save),
        ],
      ),
      body: SafeArea(
        child: _fehler != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Text(_fehler!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70)),
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
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatSeconds(range.start), style: const TextStyle(color: Colors.white70)),
                            Text(_formatSeconds(range.end), style: const TextStyle(color: Colors.white70)),
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
