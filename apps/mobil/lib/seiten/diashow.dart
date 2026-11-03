import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gelaende/diashow.dart' as video;
import 'package:gelaende/flugvideo.dart' show Videoausgang;
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/asset_display_path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:zierbild/zierschrift.dart';

import '../bilder.dart';
import '../einfuegbares_menue.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'landschaft.dart' show HandyVideoschreiber;

/// Wie lange ein Foto steht – wie am Rechner (asset_viewer_screen.dart)
/// und im Browser (web/app.js, DIA_TAKT).
const diashowTakt = Duration(seconds: 4);

/// Wie lange zwei Fotos ineinander übergehen.
const diashowUeberblendung = Duration(milliseconds: 800);

/// Die Diashow (Issue #170) – wie im Browser: Fotos nacheinander mit
/// Überblendung und einem langsamen Zoom, Videos bleiben draussen. Ein
/// Tipp zeigt die Knöpfe, Wischen blättert, das Display bleibt an.
///
/// Gibt zurück, welches der [zeilen] zuletzt stand – der Betrachter
/// springt dorthin –, oder `null`, wenn es keine Fotos gab.
Future<int?> zeigeDiashow(
  BuildContext context,
  Sitzung sitzung,
  List<Rasterzeile> zeilen, {
  int ab = 0,
}) async {
  final fotos = [
    for (final z in zeilen)
      if (z.type != 'VIDEO') z,
  ];
  if (fotos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppTexte.of(context).diashowKeineFotos)),
    );
    return null;
  }
  // Steht der Betrachter auf einem Video, beginnt sie beim nächsten Foto.
  var start = 0;
  for (var i = ab.clamp(0, zeilen.length - 1); i < zeilen.length; i++) {
    final j = fotos.indexOf(zeilen[i]);
    if (j >= 0) {
      start = j;
      break;
    }
  }
  final zuletzt = await Navigator.of(context).push<Rasterzeile>(
    PageRouteBuilder(
      pageBuilder: (_, _, _) =>
          Diashow(sitzung: sitzung, fotos: fotos, start: start),
      transitionsBuilder: (_, animation, _, kind) =>
          FadeTransition(opacity: animation, child: kind),
    ),
  );
  return zuletzt == null ? null : zeilen.indexOf(zuletzt);
}

class Diashow extends StatefulWidget {
  const Diashow({
    super.key,
    required this.sitzung,
    required this.fotos,
    this.start = 0,
  });

  final Sitzung sitzung;
  final List<Rasterzeile> fotos;
  final int start;

  @override
  State<Diashow> createState() => _DiashowState();
}

class _DiashowState extends State<Diashow> {
  late int _index = widget.start;
  ImageProvider? _bild;
  var _laeuft = true;
  var _knoepfe = false;
  Timer? _takt;
  Timer? _knoepfeAus;
  int _lauf = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable().catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _zeige(_index));
  }

  @override
  void dispose() {
    _takt?.cancel();
    _knoepfeAus?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<ImageProvider> _fuer(Rasterzeile z) async {
    final a = await widget.sitzung.db.assetById(z.id);
    final relativ = a == null
        ? (z.thumbnailRelativePath ?? z.relativePath)
        : displayRelativePath(a);
    if (!mounted) return BibliotheksBild(widget.sitzung.paths, relativ);
    final m = MediaQuery.of(context);
    final kante = (m.size.longestSide * m.devicePixelRatio).ceil();
    return ResizeImage(
      BibliotheksBild(widget.sitzung.paths, relativ),
      width: kante,
      height: kante,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }

  /// Erst laden, dann zeigen – sonst blendete die Show in ein leeres Bild.
  Future<void> _zeige(int i) async {
    _takt?.cancel();
    final n = widget.fotos.length;
    final ziel = ((i % n) + n) % n;
    final lauf = ++_lauf;
    final bild = await _fuer(widget.fotos[ziel]);
    if (!mounted) return;
    // Fehlt die Datei, steht eben die Fläche – und es geht weiter.
    await precacheImage(bild, context, onError: (_, _) {});
    if (!mounted || lauf != _lauf) return;
    setState(() {
      _index = ziel;
      _bild = bild;
    });
    // Das nächste schon holen.
    final weiter = widget.fotos[(ziel + 1) % n];
    unawaited(
      _fuer(weiter).then((b) {
        if (mounted) precacheImage(b, context, onError: (_, _) {});
      }),
    );
    if (_laeuft) _takt = Timer(diashowTakt, () => _zeige(_index + 1));
  }

  void _pause() {
    setState(() => _laeuft = !_laeuft);
    _takt?.cancel();
    if (_laeuft) _takt = Timer(diashowTakt, () => _zeige(_index + 1));
  }

  void _zeigeKnoepfe() {
    setState(() => _knoepfe = !_knoepfe);
    _knoepfeAus?.cancel();
    if (_knoepfe) {
      _knoepfeAus = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _knoepfe = false);
      });
    }
  }

  /// Die Diashow als Video (#281) – wie am Rechner (Rückblick) und im
  /// Browser: Titelkarte, dann die Fotos mit Zoom und Überblendung, Full HD,
  /// höchstens 40 Fotos. Gemalt wird mit denselben Formeln
  /// ([video.Diashowbilder], im Paket `gelaende`), geschrieben über
  /// AVFoundation wie beim Flugvideo. Fertig heisst: weitergeben – in die
  /// Fotos sichern, in eine Nachricht.
  Future<void> _alsVideo() async {
    final t = AppTexte.of(context);
    if (_laeuft) _pause();
    final fotos = widget.fotos.take(video.diashowHoechstensBilder).toList();
    final angaben = await showDialog<({String titel, String? untertitel})>(
      context: context,
      builder: (_) =>
          _Videoangaben(anzahl: fotos.length, gesamt: widget.fotos.length),
    );
    if (angaben == null || !mounted) return;
    final stand = ValueNotifier<double?>(null);
    var abgebrochen = false;
    final navigator = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(t.diashowVideoWirdErstellt),
          content: ValueListenableBuilder(
            valueListenable: stand,
            builder: (_, wert, _) => LinearProgressIndicator(value: wert),
          ),
          actions: [
            TextButton(
              onPressed: () => abgebrochen = true,
              child: Text(t.abbrechen),
            ),
          ],
        ),
      ),
    );
    ({Videoausgang ausgang, String? meldung}) ergebnis;
    File? ziel;
    try {
      // Die Ansichten holen, wo sie fehlen – wie die Diashow selbst.
      final dateien = <File>[];
      for (final z in fotos) {
        final a = await widget.sitzung.db.assetById(z.id);
        final relativ = a == null
            ? (z.thumbnailRelativePath ?? z.relativePath)
            : displayRelativePath(a);
        try {
          dateien.add(await widget.sitzung.paths.bereit(relativ));
        } on Object {
          // Steht als schwarzes Bild da, das Video geht weiter.
          dateien.add(widget.sitzung.paths.absolute(relativ));
        }
        if (abgebrochen) break;
      }
      final bilder = video.Diashowbilder(
        dateien: dateien,
        titel: angaben.titel,
        untertitel: angaben.untertitel,
        schrift: zierschrift,
      );
      final name = angaben.titel.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-');
      ziel = File('${(await getTemporaryDirectory()).path}/$name.mp4');
      try {
        ergebnis = abgebrochen
            ? (ausgang: Videoausgang.abgebrochen, meldung: null)
            : await const HandyVideoschreiber().schreibe(
                ziel: ziel,
                breite: video.diashowBreite,
                hoehe: video.diashowHoehe,
                dauer: bilder.dauer,
                vorBild: bilder.vorBild,
                maleBild: bilder.maleBild,
                fortschritt: (a) => stand.value = a,
                abbruch: () => abgebrochen,
              );
      } finally {
        bilder.freigeben();
      }
    } on Object catch (x) {
      ergebnis = (ausgang: Videoausgang.fehler, meldung: '$x');
    } finally {
      navigator.pop();
      stand.dispose();
    }
    if (!mounted) return;
    switch (ergebnis.ausgang) {
      case Videoausgang.fertig:
        await SharePlus.instance.share(
          ShareParams(files: [XFile(ziel!.path, mimeType: 'video/mp4')]),
        );
      case Videoausgang.abgebrochen:
        break;
      case Videoausgang.keinWerkzeug:
      case Videoausgang.fehler:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.diashowVideoFehler(ergebnis.meldung ?? ''))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final bild = _bild;
    final bewegung = !MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _zeigeKnoepfe,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 200) return;
          _zeige(_index + (v < 0 ? 1 : -1));
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: diashowUeberblendung,
              child: bild == null
                  ? const SizedBox.expand(key: ValueKey('leer'))
                  : _Dia(
                      key: ValueKey(_lauf),
                      bild: bild,
                      // Abwechselnd in eine andere Ecke – wie im Browser.
                      ecke: _index.isOdd
                          ? Alignment.topLeft
                          : Alignment.bottomRight,
                      bewegung: bewegung,
                    ),
            ),
            AnimatedOpacity(
              opacity: _knoepfe ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_knoepfe,
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: IconTheme(
                          data: const IconThemeData(color: Colors.white),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: t.diashowVorige,
                                icon: const Icon(Icons.chevron_left_rounded),
                                onPressed: () => _zeige(_index - 1),
                              ),
                              IconButton(
                                tooltip: _laeuft
                                    ? t.diashowAnhalten
                                    : t.diashowWeiter,
                                icon: Icon(
                                  _laeuft
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                onPressed: _pause,
                              ),
                              IconButton(
                                tooltip: t.diashowNaechste,
                                icon: const Icon(Icons.chevron_right_rounded),
                                onPressed: () => _zeige(_index + 1),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  '${_index + 1} / ${widget.fotos.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              if (Platform.isIOS)
                                IconButton(
                                  tooltip: t.diashowAlsVideo,
                                  icon: const Icon(Icons.movie_outlined),
                                  onPressed: _alsVideo,
                                ),
                              IconButton(
                                tooltip: t.diashowBeenden,
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => Navigator.of(
                                  context,
                                ).pop(widget.fotos[_index]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Foto der Show mit langsamem Zoom.
class _Dia extends StatelessWidget {
  const _Dia({
    super.key,
    required this.bild,
    required this.ecke,
    required this.bewegung,
  });

  final ImageProvider bild;
  final Alignment ecke;
  final bool bewegung;

  @override
  Widget build(BuildContext context) {
    final foto = Image(
      image: bild,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.expand(),
    );
    if (!bewegung) return SizedBox.expand(child: foto);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 1.06),
      duration: diashowTakt + diashowUeberblendung,
      curve: Curves.easeOut,
      builder: (context, s, kind) =>
          Transform.scale(scale: s, alignment: ecke, child: kind),
      child: SizedBox.expand(child: foto),
    );
  }
}

/// Titel und Untertitel für das Video, und wie lang es wird.
class _Videoangaben extends StatefulWidget {
  const _Videoangaben({required this.anzahl, required this.gesamt});

  final int anzahl;
  final int gesamt;

  @override
  State<_Videoangaben> createState() => _VideoangabenState();
}

class _VideoangabenState extends State<_Videoangaben> {
  late final _titel = TextEditingController(text: AppTexte.of(context).diashow);
  final _untertitel = TextEditingController();

  @override
  void dispose() {
    _titel.dispose();
    _untertitel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final sekunden = video.diashowDauer(widget.anzahl).inSeconds;
    return AlertDialog(
      title: Text(t.diashowVideoTitel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.gesamt > widget.anzahl
                ? t.diashowVideoErste(widget.anzahl, widget.gesamt, sekunden)
                : t.diashowVideoUmfang(widget.anzahl, sekunden),
          ),
          TextField(
            controller: _titel,
            contextMenuBuilder: einfuegbaresMenue,
            decoration: InputDecoration(labelText: t.diashowVideoTitelfeld),
          ),
          TextField(
            controller: _untertitel,
            contextMenuBuilder: einfuegbaresMenue,
            decoration: InputDecoration(labelText: t.diashowVideoUntertitel),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.abbrechen),
        ),
        FilledButton(
          onPressed: () {
            final titel = _titel.text.trim();
            final unter = _untertitel.text.trim();
            Navigator.pop(context, (
              titel: titel.isEmpty ? t.diashow : titel,
              untertitel: unter.isEmpty ? null : unter,
            ));
          },
          child: Text(t.diashowVideoErstellen),
        ),
      ],
    );
  }
}
