import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/asset_display_path.dart';
import 'package:kern/services/gesichtsuebersicht.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../bilder.dart';
import '../formate.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'angaben.dart';
import 'diashow.dart';
import 'entwickeln.dart';
import 'gesichter.dart';
import 'gesichtsebene.dart';
import 'videospieler.dart';

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

  // Gesichtsrahmen über dem Foto (Issue #190): eingeblendet bleiben sie
  // beim Blättern; beim Aufziehen gehört der Finger dem Rahmen, nicht dem
  // Zoomen und Blättern. [_gesichtsstand] lädt sie nach einer Änderung neu.
  var _gesichter = false;
  var _aufziehen = false;
  var _gesichtsstand = 0;

  // Die Gesichter des gezeigten Fotos – für die Zahlen im Menü (#192).
  List<FaceData> _hier = const [];
  String? _hierVon;

  AppDatabase get _db => widget.sitzung.db;

  Future<void> _zaehle() async {
    final id = _aktuell;
    final f = await _db.facesForAsset(id);
    if (!mounted || id != _aktuell) return;
    setState(() {
      _hier = f;
      _hierVon = id;
    });
  }

  /// Nach einer Änderung an den Gesichtern: Rahmen und Zahlen neu.
  void _gesichterNeu() {
    setState(() => _gesichtsstand++);
    _zaehle();
  }

  @override
  void initState() {
    super.initState();
    _zaehle();
  }

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

  Future<void> _angaben() => zeigeAngaben(context, widget.sitzung, _aktuell);

  /// Die unbenannten Gesichter dieses Fotos auf einmal ignorieren – wie
  /// im Menü der Gesichtsansicht am Rechner (#192).
  Future<void> _unbenannteIgnorieren() async {
    final ids = [
      for (final f in _hier)
        if (f.personId == null && !f.isIgnored) f.id,
    ];
    if (ids.isEmpty) return;
    await _db.fuehreAus(GesichterBeiseitelegen(ids, true));
    if (mounted) _gesichterNeu();
  }

  /// … oder löschen, auch die beiseitegelegten – für ein Bild, auf dem die
  /// Erkennung lauter Fehlgriffe gefunden hat.
  Future<void> _unbenannteLoeschen() async {
    final t = AppTexte.of(context);
    final ids = [
      for (final f in _hier)
        if (f.personId == null) f.id,
    ];
    if (ids.isEmpty) return;
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.betrachterUnbenannteLoeschenFrage(ids.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.gesichterLoeschen),
          ),
        ],
      ),
    );
    if (ja != true) return;
    await _db.fuehreAus(GesichterLoeschen(ids));
    if (mounted) _gesichterNeu();
  }

  /// Ein Foto, auf dem jeder Durchlauf neue „Gesichter" findet – eine
  /// Gemäldewand, ein Plakat –, von der Suche ausnehmen oder zurückholen
  /// (wie am Rechner und im Browser). Was schon erkannt ist, bleibt; die
  /// Ausnahme gilt dem Suchen.
  Future<void> _gesichtssucheUmschalten() async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    final a = await _lade(_aktuell);
    if (a == null) return;
    final aus = !a.faceScanExcluded;
    await _db.fuehreAus(GesichtssucheAusnehmen(a.id, aus));
    _daten.remove(a.id);
    await _lade(a.id);
    if (!mounted) return;
    setState(() {});
    bote
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            aus
                ? t.betrachterNichtMehrDurchsuchtHinweis
                : t.betrachterWiederDurchsuchtHinweis,
          ),
        ),
      );
  }

  Future<void> _gesichtGetippt(GesichtAufAufnahme g) async {
    final t = AppTexte.of(context);
    await benenneGesichter(
      context,
      widget.sitzung,
      titel: g.person?.name ?? t.gesichterWerIstDas,
      gesichter: [g.gesicht],
      person: g.person,
    );
    if (mounted) _gesichterNeu();
  }

  Future<void> _rahmenGezogen(Rect kasten) async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    // Eine stehende Meldung gleich ersetzen, nicht dahinter einreihen.
    bote.hideCurrentSnackBar();
    if (kasten.width < 0.01 || kasten.height < 0.01) {
      bote.showSnackBar(SnackBar(content: Text(t.betrachterRahmenZuKlein)));
      return;
    }
    setState(() => _aufziehen = false);
    FaceData? neu;
    try {
      neu = await gesichtAmServerAnlegen(widget.sitzung, _aktuell, kasten);
    } catch (_) {
      neu = null;
    }
    if (!mounted) return;
    _gesichterNeu();
    if (neu == null) {
      bote
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t.betrachterGesichtFehler)));
      return;
    }
    // Gleich benennen – wie am Rechner, wo die Person zuerst gefragt wird.
    await benenneGesichter(
      context,
      widget.sitzung,
      titel: t.gesichterWerIstDas,
      gesichter: [neu],
    );
    if (mounted) _gesichterNeu();
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
    final hier = _hierVon == zeile.id ? _hier : const <FaceData>[];
    final offene = hier.where((f) => f.personId == null && !f.isIgnored).length;
    final unbenannte = hier.where((f) => f.personId == null).length;
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
              // Kurz wie im Browser („12.09.2026“) – rechts stehen fünf
              // Knöpfe.
              title: Text(
                datumMittel(
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
                // Weniger Häufiges im Menü – oben ist kein Platz mehr,
                // ohne das Datum abzuschneiden (wie Immich).
                PopupMenuButton<String>(
                  tooltip: t.betrachterMehr,
                  onSelected: (w) async {
                    switch (w) {
                      case 'entwickeln':
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Entwickeln(
                              sitzung: widget.sitzung,
                              id: zeile.id,
                            ),
                          ),
                        );
                      case 'gesichter':
                        setState(() {
                          _gesichter = !_gesichter;
                          if (!_gesichter) _aufziehen = false;
                        });
                        if (_gesichter) _zaehle();
                      case 'aufziehen':
                        setState(() {
                          _gesichter = true;
                          _aufziehen = true;
                          _leiste = true;
                        });
                      case 'ausnehmen':
                        await _gesichtssucheUmschalten();
                      case 'unbenannteIgnorieren':
                        await _unbenannteIgnorieren();
                      case 'unbenannteLoeschen':
                        await _unbenannteLoeschen();
                      case 'diashow':
                        final i = await zeigeDiashow(
                          context,
                          widget.sitzung,
                          widget.zeilen,
                          ab: _index,
                        );
                        if (i != null && i >= 0 && mounted) {
                          _seiten.jumpToPage(i);
                        }
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'diashow',
                      child: ListTile(
                        leading: const Icon(Icons.slideshow_outlined),
                        title: Text(t.diashowAbHier),
                      ),
                    ),
                    if (zeile.type != 'VIDEO') ...[
                      PopupMenuItem(
                        value: 'gesichter',
                        child: ListTile(
                          leading: Icon(
                            _gesichter
                                ? Icons.face_retouching_off_outlined
                                : Icons.face_outlined,
                          ),
                          title: Text(
                            _gesichter
                                ? t.betrachterGesichterAus
                                : t.betrachterGesichterZeigen,
                          ),
                        ),
                      ),
                      if (!widget.imPapierkorb)
                        PopupMenuItem(
                          value: 'aufziehen',
                          child: ListTile(
                            leading: const Icon(Icons.crop_free_rounded),
                            title: Text(t.betrachterGesichtAufziehen),
                          ),
                        ),
                      // Wie im Browser nur bei eingeblendeten Rahmen: Dort
                      // sieht man, was die Erkennung gefunden hat.
                      if (_gesichter && !widget.imPapierkorb) ...[
                        PopupMenuItem(
                          value: 'unbenannteIgnorieren',
                          enabled: offene > 0,
                          child: ListTile(
                            leading: const Icon(Icons.visibility_off_outlined),
                            title: Text(
                              t.betrachterUnbenannteIgnorieren(offene),
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'unbenannteLoeschen',
                          enabled: unbenannte > 0,
                          child: ListTile(
                            leading: const Icon(Icons.delete_sweep_outlined),
                            title: Text(
                              t.betrachterUnbenannteLoeschen(unbenannte),
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'ausnehmen',
                          child: ListTile(
                            leading: Icon(
                              (_daten[zeile.id]?.faceScanExcluded ?? false)
                                  ? Icons.person_search_outlined
                                  : Icons.search_off_outlined,
                            ),
                            title: Text(
                              (_daten[zeile.id]?.faceScanExcluded ?? false)
                                  ? t.betrachterWiederDurchsuchen
                                  : t.betrachterNichtMehrDurchsuchen,
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (!widget.imPapierkorb && zeile.type != 'VIDEO')
                      PopupMenuItem(
                        value: 'entwickeln',
                        child: ListTile(
                          leading: const Icon(Icons.tune),
                          title: Text(t.entwTitel),
                        ),
                      ),
                  ],
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
      bottomNavigationBar: _aufziehen
          ? Material(
              color: Colors.black87,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.betrachterAufziehenHinweis,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _aufziehen = false),
                        child: Text(t.abbrechen),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      body: GestureDetector(
        onTap: _aufziehen ? null : () => setState(() => _leiste = !_leiste),
        onVerticalDragUpdate: _gezoomt || _aufziehen ? null : _zugWeiter,
        onVerticalDragEnd: _gezoomt || _aufziehen ? null : _zugEnde,
        child: AnimatedContainer(
          duration: _zieht ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transformAlignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(0, verschiebung, 0, 1)
            ..scaleByDouble(1 - anteil * 0.3, 1 - anteil * 0.3, 1, 1),
          child: PhotoViewGallery.builder(
            pageController: _seiten,
            scrollPhysics: _aufziehen
                ? const NeverScrollableScrollPhysics()
                : null,
            itemCount: widget.zeilen.length,
            backgroundDecoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            scaleStateChangedCallback: (zustand) => setState(
              () => _gezoomt = zustand != PhotoViewScaleState.initial,
            ),
            onPageChanged: (i) {
              setState(() {
                _index = i;
                _gezoomt = false;
              });
              _zaehle();
            },
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
                disableGestures: _aufziehen,
                child: _BildSeite(
                  sitzung: widget.sitzung,
                  zeile: z,
                  lade: _lade,
                  ebene: _gesichter
                      ? Gesichtsebene(
                          sitzung: widget.sitzung,
                          zeile: z,
                          stand: _gesichtsstand,
                          aufziehen: _aufziehen && i == _index,
                          beiTipp: _gesichtGetippt,
                          beiRahmen: _rahmenGezogen,
                        )
                      : null,
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
///
/// Ein Live Photo trägt unten links „LIVE“: Halten auf dem Bild (oder ein
/// Tipp auf die Marke) spielt den Bewegungsteil an seiner Stelle, wie im
/// Browser und in der Schwebevorschau des Rechners.
class _BildSeite extends StatefulWidget {
  const _BildSeite({
    required this.sitzung,
    required this.zeile,
    required this.lade,
    this.ebene,
  });

  final Sitzung sitzung;
  final Rasterzeile zeile;
  final Future<AssetData?> Function(String id) lade;

  /// Über dem Bild, mit ihm gezoomt – die Gesichtsrahmen (Issue #190).
  final Widget? ebene;

  @override
  State<_BildSeite> createState() => _BildSeiteState();
}

class _BildSeiteState extends State<_BildSeite> {
  VideoPlayerController? _live;
  var _laedt = false;
  var _lauf = 0;

  Future<void> _liveAn() async {
    final partner = widget.zeile.linkedAssetId;
    if (partner == null || _laedt || _live != null) return;
    final lauf = ++_lauf;
    setState(() => _laedt = true);
    try {
      final a = await widget.lade(partner);
      if (a == null) return;
      final c = await videospieler(
        widget.sitzung,
        a,
        abgebrochen: () => !mounted || lauf != _lauf,
      );
      if (!mounted || lauf != _lauf) {
        await c.dispose();
        return;
      }
      c.addListener(() {
        if (c.value.isCompleted && identical(_live, c)) _liveAus();
      });
      await c.play();
      setState(() => _live = c);
    } catch (_) {
      // Ohne Bewegungsteil bleibt das Foto stehen.
    } finally {
      if (mounted && lauf == _lauf) setState(() => _laedt = false);
    }
  }

  void _liveAus() {
    _lauf++;
    final c = _live;
    _live = null;
    _laedt = false;
    if (mounted) setState(() {});
    c?.dispose();
  }

  @override
  void dispose() {
    _lauf++;
    _live?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zeile = widget.zeile;
    final miniatur = zeile.thumbnailRelativePath == null
        ? const SizedBox.shrink()
        : Image(
            image: BibliotheksBild(
              widget.sitzung.paths,
              zeile.thumbnailRelativePath!,
            ),
            fit: BoxFit.contain,
          );
    final bild = FutureBuilder<AssetData?>(
      future: widget.lade(zeile.id),
      builder: (context, snap) {
        final a = snap.data;
        if (a == null) return Center(child: miniatur);
        return Image(
          image: ResizeImage(
            BibliotheksBild(widget.sitzung.paths, displayRelativePath(a)),
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
    final ebene = widget.ebene;
    if (zeile.linkedAssetId == null) {
      return ebene == null
          ? bild
          : Stack(fit: StackFit.expand, children: [bild, ebene]);
    }
    final live = _live;
    final aktiv = live != null || _laedt;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onLongPressStart: (_) => _liveAn(),
          onLongPressEnd: (_) => _liveAus(),
          child: bild,
        ),
        if (live != null)
          IgnorePointer(
            child: Center(
              child: AspectRatio(
                aspectRatio: live.value.aspectRatio,
                child: VideoPlayer(live),
              ),
            ),
          ),
        ?ebene,
        Positioned(
          left: 16,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
          child: Semantics(
            button: true,
            label: AppTexte.of(context).betrachterLiveAbspielen,
            child: GestureDetector(
              onTap: aktiv ? _liveAus : _liveAn,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: aktiv ? Colors.white : Colors.black38,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white70, width: 1.5),
                ),
                child: Text(
                  'LIVE',
                  style: TextStyle(
                    color: aktiv ? Colors.black : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
  var _wandelt = false;

  @override
  void initState() {
    super.initState();
    _starte();
  }

  Future<void> _starte() async {
    final a = await widget.lade(widget.id);
    if (a == null || !mounted) return;
    try {
      final spieler = await videospieler(
        widget.sitzung,
        a,
        wandelt: () {
          if (mounted) setState(() => _wandelt = true);
        },
        abgebrochen: () => !mounted,
      );
      if (!mounted) {
        await spieler.dispose();
        return;
      }
      await spieler.play();
      setState(() => _spieler = spieler);
    } catch (_) {
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white54),
            if (_wandelt)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  AppTexte.of(context).betrachterWirdUmgewandelt,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
          ],
        ),
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
