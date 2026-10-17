import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/asset_display_path.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Der Weg in den Betrachter: durchsichtig, damit beim Wischen nach unten
/// das Raster dahinter erscheint, und mit einer Blende statt eines Schubs
/// von der Seite – wie in Immich.
Route<void> betrachterWeg(Widget seite) => PageRouteBuilder<void>(
  opaque: false,
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 180),
  reverseTransitionDuration: const Duration(milliseconds: 160),
  pageBuilder: (_, _, _) => seite,
  transitionsBuilder: (_, animation, _, kind) =>
      FadeTransition(opacity: animation, child: kind),
);

/// Eine Aufnahme nach der anderen: wischen, zoomen, abspielen – und das
/// Wenige, was man am Telefon tut: Favorit, Teilen, Angaben, Papierkorb.
///
/// Wie in Immich: nach unten wischen schliesst (das Bild folgt dem Finger,
/// der Hintergrund wird durchsichtig), nach oben wischen zeigt die Angaben.
/// Ist das Bild vergrössert, gehört das Wischen dem Verschieben.
class Betrachter extends StatefulWidget {
  const Betrachter({
    super.key,
    required this.sitzung,
    required this.zeilen,
    required this.start,
    this.imPapierkorb = false,
  });

  final Sitzung sitzung;
  final List<Rasterzeile> zeilen;
  final int start;

  /// Die Aufnahmen liegen im Papierkorb: zurückholen statt Favorit und
  /// Papierkorb.
  final bool imPapierkorb;

  @override
  State<Betrachter> createState() => _BetrachterState();
}

class _BetrachterState extends State<Betrachter> {
  late final _seiten = PageController(initialPage: widget.start);
  late int _index = widget.start;
  final _daten = <String, AssetData>{};
  var _leiste = true;

  // Das senkrechte Wischen: wie weit der Finger gezogen hat, ob er gerade
  // zieht (dann folgt das Bild ohne Verzögerung) und ob das Bild
  // vergrössert ist (dann wischt niemand).
  var _zug = 0.0;
  var _zieht = false;
  var _gezoomt = false;

  AppDatabase get _db => widget.sitzung.db;

  Future<AssetData?> _lade(String id) async {
    final schon = _daten[id];
    if (schon != null) return schon;
    final a = await _db.assetById(id);
    if (a != null) _daten[id] = a;
    return a;
  }

  @override
  void dispose() {
    _seiten.dispose();
    super.dispose();
  }

  String get _aktuell => widget.zeilen[_index].id;

  Future<void> _favorit() async {
    final a = await _lade(_aktuell);
    if (a == null) return;
    await _db.fuehreAus(FavoritSetzen([a.id], !a.isFavorite));
    _daten.remove(a.id);
    await _lade(a.id);
    if (mounted) setState(() {});
  }

  Future<void> _teile() async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    final a = await _lade(_aktuell);
    if (a == null) return;
    bote.showSnackBar(SnackBar(content: Text(t.betrachterLaedtOriginal)));
    try {
      final datei = await widget.sitzung.paths.bereit(a.relativePath);
      bote.hideCurrentSnackBar();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(datei.path)],
          fileNameOverrides: [a.originalFileName],
        ),
      );
    } catch (_) {
      bote
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t.betrachterNichtGeladen)));
    }
  }

  Future<void> _papierkorb() async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.betrachterPapierkorbTitel),
        content: Text(t.betrachterPapierkorbText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.betrachterPapierkorb),
          ),
        ],
      ),
    );
    if (ja != true) return;
    await _db.fuehreAus(InDenPapierkorb([_aktuell]));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _zurueckholen() async {
    await _db.fuehreAus(AusDemPapierkorb([_aktuell]));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _angaben() async {
    final a = await _lade(_aktuell);
    if (a == null || !mounted) return;
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final zeit = DateFormat.yMMMMEEEEd(
      sprache,
    ).add_Hm().format(a.fileCreatedAt.toLocal());
    final ort = [
      a.locationCity,
      a.locationState,
      a.locationCountry,
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    // Ohne Ortsnamen (der Server hat die Umkehr-Geokodierung nicht
    // eingerichtet) wenigstens die Koordinaten.
    final koordinaten = a.latitude == null || a.longitude == null
        ? null
        : '${a.latitude!.toStringAsFixed(5)}, '
              '${a.longitude!.toStringAsFixed(5)}';
    final kamera = [a.cameraMake, a.cameraModel].whereType<String>().join(' ');
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(zeit),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(a.originalFileName),
              subtitle: a.widthPx == null
                  ? null
                  : Text('${a.widthPx} × ${a.heightPx}'),
            ),
            if (ort.isNotEmpty || koordinaten != null)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(ort.isNotEmpty ? ort : koordinaten!),
                subtitle: ort.isNotEmpty && koordinaten != null
                    ? Text(koordinaten)
                    : null,
              ),
            if (kamera.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(kamera),
                subtitle: a.lensModel == null ? null : Text(a.lensModel!),
              ),
            if ((a.description ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: Text(a.description!),
              ),
            if ((a.aiCaption ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(a.aiCaption!),
                subtitle: Text(t.betrachterBeschreibungKi),
              ),
          ],
        ),
      ),
    );
  }

  void _zugWeiter(DragUpdateDetails d) => setState(() {
    _zieht = true;
    _zug += d.delta.dy;
  });

  void _zugEnde(DragEndDetails d) {
    final tempo = d.primaryVelocity ?? 0;
    final runter = _zug > 110 || tempo > 900;
    final hoch = _zug < -50 || tempo < -700;
    setState(() {
      _zieht = false;
      if (!runter) _zug = 0;
    });
    if (runter) {
      Navigator.of(context).pop();
    } else if (hoch) {
      _angaben();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final zeile = widget.zeilen[_index];
    final favorit = _daten[zeile.id]?.isFavorite ?? zeile.isFavorite;
    // Nach unten folgt das Bild dem Finger und wird kleiner; nach oben nur
    // ein Stück, als Andeutung, dass dort etwas kommt.
    final verschiebung = _zug > 0 ? _zug : _zug * 0.25;
    final anteil = (_zug / 400).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - anteil * 0.85),
      extendBodyBehindAppBar: true,
      appBar: _leiste && _zug == 0
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              // Vier Knöpfe rechts lassen wenig Platz: Datum in kleinerer
              // Schrift, damit es nicht abgeschnitten wird.
              titleTextStyle: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.white),
              titleSpacing: 0,
              title: Text(
                DateFormat.yMMMd(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(zeile.fileCreatedAt.toLocal()),
              ),
              actions: [
                if (!widget.imPapierkorb)
                  IconButton(
                    tooltip: t.betrachterFavorit,
                    icon: Icon(
                      favorit ? Icons.favorite : Icons.favorite_border,
                    ),
                    onPressed: _favorit,
                  ),
                IconButton(
                  tooltip: t.betrachterTeilen,
                  icon: const Icon(Icons.share_outlined),
                  onPressed: _teile,
                ),
                IconButton(
                  tooltip: t.betrachterAngaben,
                  icon: const Icon(Icons.info_outline),
                  onPressed: _angaben,
                ),
                if (widget.imPapierkorb)
                  IconButton(
                    tooltip: t.auswahlZurueckholen,
                    icon: const Icon(Icons.restore_from_trash_outlined),
                    onPressed: _zurueckholen,
                  )
                else
                  IconButton(
                    tooltip: t.betrachterPapierkorb,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _papierkorb,
                  ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _leiste = !_leiste),
        onVerticalDragUpdate: _gezoomt ? null : _zugWeiter,
        onVerticalDragEnd: _gezoomt ? null : _zugEnde,
        child: AnimatedContainer(
          duration: _zieht ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transformAlignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(0, verschiebung, 0, 1)
            ..scaleByDouble(1 - anteil * 0.3, 1 - anteil * 0.3, 1, 1),
          child: PhotoViewGallery.builder(
            pageController: _seiten,
            itemCount: widget.zeilen.length,
            backgroundDecoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            scaleStateChangedCallback: (zustand) => setState(
              () => _gezoomt = zustand != PhotoViewScaleState.initial,
            ),
            onPageChanged: (i) => setState(() {
              _index = i;
              _gezoomt = false;
            }),
            loadingBuilder: (_, _) => const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),
            builder: (context, i) {
              final z = widget.zeilen[i];
              if (z.type == 'VIDEO') {
                return PhotoViewGalleryPageOptions.customChild(
                  disableGestures: true,
                  child: _VideoSeite(
                    sitzung: widget.sitzung,
                    id: z.id,
                    lade: _lade,
                  ),
                );
              }
              return PhotoViewGalleryPageOptions.customChild(
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                child: _BildSeite(
                  sitzung: widget.sitzung,
                  zeile: z,
                  lade: _lade,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Ein Foto: zuerst die Miniatur, dann das Bild, das der Desktop zeigt
/// (restauriert, entwickelt, Vorschau oder Original).
class _BildSeite extends StatelessWidget {
  const _BildSeite({
    required this.sitzung,
    required this.zeile,
    required this.lade,
  });

  final Sitzung sitzung;
  final Rasterzeile zeile;
  final Future<AssetData?> Function(String id) lade;

  @override
  Widget build(BuildContext context) {
    final miniatur = zeile.thumbnailRelativePath == null
        ? const SizedBox.shrink()
        : Image(
            image: BibliotheksBild(sitzung.paths, zeile.thumbnailRelativePath!),
            fit: BoxFit.contain,
          );
    return FutureBuilder<AssetData?>(
      future: lade(zeile.id),
      builder: (context, snap) {
        final a = snap.data;
        if (a == null) return Center(child: miniatur);
        return Image(
          image: ResizeImage(
            BibliotheksBild(sitzung.paths, displayRelativePath(a)),
            width: 3000,
            height: 3000,
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false,
          ),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          frameBuilder: (context, kind, frame, sofort) =>
              frame == null && !sofort ? Center(child: miniatur) : kind,
          errorBuilder: (_, _, _) => Center(child: miniatur),
        );
      },
    );
  }
}

/// Ein Video: spielt vom Server mit Teilabruf, ohne es erst ganz zu laden;
/// liegt es schon hier, von hier.
class _VideoSeite extends StatefulWidget {
  const _VideoSeite({
    required this.sitzung,
    required this.id,
    required this.lade,
  });

  final Sitzung sitzung;
  final String id;
  final Future<AssetData?> Function(String id) lade;

  @override
  State<_VideoSeite> createState() => _VideoSeiteState();
}

class _VideoSeiteState extends State<_VideoSeite> {
  VideoPlayerController? _spieler;
  var _fehler = false;

  @override
  void initState() {
    super.initState();
    _starte();
  }

  Future<void> _starte() async {
    final a = await widget.lade(widget.id);
    if (a == null || !mounted) return;
    final rel = a.trimmedRelativePath ?? a.relativePath;
    final hier = widget.sitzung.paths.absolute(rel);
    final v = widget.sitzung.verbindung!;
    final spieler = await hier.exists()
        ? VideoPlayerController.file(File(hier.path))
        : VideoPlayerController.networkUrl(
            widget.sitzung.abgleich!.verbindung.adresse(
              'api/v1/dateien/${rel.split('/').map(Uri.encodeComponent).join('/')}',
            ),
            httpHeaders: {'authorization': 'Bearer ${v.token}'},
          );
    try {
      await spieler.initialize();
      await spieler.play();
      if (!mounted) {
        await spieler.dispose();
        return;
      }
      setState(() => _spieler = spieler);
    } catch (_) {
      await spieler.dispose();
      if (mounted) setState(() => _fehler = true);
    }
  }

  @override
  void dispose() {
    _spieler?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _spieler;
    if (_fehler) {
      return Center(
        child: Text(
          AppTexte.of(context).betrachterNichtGeladen,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    if (s == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => s.value.isPlaying ? s.pause() : s.play()),
      child: Center(
        child: AspectRatio(
          aspectRatio: s.value.aspectRatio,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              VideoPlayer(s),
              VideoProgressIndicator(s, allowScrubbing: true),
            ],
          ),
        ),
      ),
    );
  }
}
