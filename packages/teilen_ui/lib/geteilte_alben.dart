import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:path/path.dart' as p;

import 'l10n/teilen_texte.dart';

// Alben zwischen Konten teilen (#105) – wie im Browser (web/app.js,
// zeigeGeteiltesAlbum und oeffneKontenDialog), für Telefon und Rechner
// dieselbe Oberfläche (#289).
//
// Ein Album, das ein anderes Konto teilt, liegt nicht in der Kopie dieses
// Telefons: Es gehört zur Bibliothek des Besitzers. Raster und Betrachter
// holen deshalb alles direkt vom Server. Miniaturen und Ansichten bleiben
// danach unter `geteilt/<Teilung>/` liegen (#291) – im Zwischenspeicher
// der Kopie, mit seiner Grenze; ist ein Album nicht mehr geteilt, geht
// sein Ordner beim nächsten Blick auf die Albenliste.

String _k(String s) => Uri.encodeComponent(s);

/// Die Texte dieses Pakets – ohne dass die App sie anmelden muss: in der
/// Sprache, die gerade gilt.
TeilenTexte teilenTexte(BuildContext context) =>
    Localizations.of<TeilenTexte>(context, TeilenTexte) ??
    lookupTeilenTexte(_sprache(Localizations.localeOf(context)));

Locale _sprache(Locale l) =>
    TeilenTexte.supportedLocales.any((s) => s.languageCode == l.languageCode)
    ? Locale(l.languageCode)
    : const Locale('de');

/// Spielt ein Video aus einem geteilten Album – jede App mit ihrem eigenen
/// Spieler (video_player am Telefon, media_kit am Rechner).
typedef Videobauer = Widget Function(BuildContext context, Fernvideo video);

/// Was ein Spieler für ein Video vom Server braucht.
class Fernvideo {
  const Fernvideo({
    required this.wiedergabe,
    required this.kopf,
    required this.fassung,
  });

  /// Das Video, wie der Betrachter es zeigt (gekürzt, sonst das Original).
  final Uri wiedergabe;

  /// Die Anmeldung für jeden Abruf.
  final Map<String, String> kopf;

  /// Spielt das Gerät [wiedergabe] nicht (HEVC), wartet dies auf die
  /// H.264-Fassung des Servers und gibt ihre Adresse – `null`, wenn sie
  /// sich nicht erzeugen lässt oder [abgebrochen] es sagt.
  final Future<Uri?> Function({bool Function()? abgebrochen}) fassung;
}

/// Was eine App für geteilte Alben mitbringt.
class Teilungszugang {
  const Teilungszugang({
    required this.verbindung,
    this.ablage,
    this.waehle,
    this.video,
  });

  final Serververbindung verbindung;

  /// Wohin die Bilder kommen (`StoragePaths.geteiltDir`), oder `null`:
  /// dann nur in den Bildspeicher.
  final Directory? ablage;

  /// Wer die Dateien zum Beitragen wählt – die Fotomediathek am Telefon,
  /// der Dateidialog am Rechner. Ohne gibt es keinen Knopf dafür.
  final Future<List<Beitragsdatei>> Function(BuildContext context)? waehle;

  /// Ohne zeigt ein Video nur ein Zeichen.
  final Videobauer? video;
}

/// Ein Bild vom Server über [verbindung], das nicht in der Bibliothek
/// liegt – mit [ablage] einmal geholt und danach von dort.
class FernBild extends ImageProvider<FernBild> {
  const FernBild(this.verbindung, this.pfad, {this.ablage});

  final Serververbindung verbindung;
  final String pfad;
  final File? ablage;

  @override
  Future<FernBild> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<FernBild>(this);

  @override
  ImageStreamCompleter loadImage(FernBild key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _lade(key, decode),
        scale: 1,
        debugLabel: pfad,
      );

  Future<ui.Codec> _lade(FernBild key, ImageDecoderCallback decode) async {
    final a = ablage;
    try {
      if (a != null && await a.exists()) {
        // Die Zeit des Zugriffs entscheidet, was der Zwischenspeicher
        // zuerst räumt (siehe StoragePaths.bereit).
        unawaited(a.setLastModified(DateTime.now()).catchError((_) {}));
        return await decode(await ui.ImmutableBuffer.fromFilePath(a.path));
      }
      final r = await verbindung.anfrage('GET', pfad);
      if (r.statusCode != 200) throw Serverfehler(r.statusCode, '');
      if (a != null) {
        try {
          await a.parent.create(recursive: true);
          final teil = File('${a.path}.teil');
          await teil.writeAsBytes(r.bodyBytes, flush: true);
          await teil.rename(a.path);
        } on FileSystemException {
          // Kein Platz oder gerade geräumt: Das Bild zeigt sich trotzdem.
        }
      }
      return await decode(await ui.ImmutableBuffer.fromUint8List(r.bodyBytes));
    } catch (_) {
      // Offline: nicht im Bildspeicher behalten, der nächste Blick holt es.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FernBild &&
      other.pfad == pfad &&
      identical(other.verbindung, verbindung);

  @override
  int get hashCode => Object.hash(pfad, identityHashCode(verbindung));
}

/// Ein Album, das ein anderes Konto mit diesem teilt.
class GeteiltesAlbum {
  const GeteiltesAlbum({
    required this.id,
    required this.name,
    required this.besitzer,
    required this.beitragen,
    required this.anzahl,
    this.titelbild,
    this.titelstand,
  });

  factory GeteiltesAlbum.aus(Map<String, Object?> j) => GeteiltesAlbum(
    id: '${j['id']}',
    name: '${j['name'] ?? ''}',
    besitzer: '${j['besitzer'] ?? ''}',
    beitragen: j['beitragen'] == true,
    anzahl: (j['anzahl'] as num?)?.toInt() ?? 0,
    titelbild: j['titelbild'] as String?,
    titelstand: j['titelstand'] as String?,
  );

  /// Die Kennung der Teilung, nicht die des Albums.
  final String id;
  final String name;
  final String besitzer;
  final bool beitragen;
  final int anzahl;
  final String? titelbild;
  final String? titelstand;

  String datei(String aufnahme, String art, [String? stand]) =>
      'api/v1/geteilt/${_k(id)}/aufnahmen/${_k(aufnahme)}/$art'
      '${stand == null ? '' : '?v=${_k(stand)}'}';

  /// Das Bild [art] von [aufnahme]; mit [ablage] unter
  /// `<ablage>/<Teilung>/` vorgehalten. [stand] steckt im Dateinamen: Eine
  /// neue Fassung beim Besitzer ist eine neue Datei.
  FernBild bild(
    Serververbindung verbindung,
    Directory? ablage,
    String aufnahme,
    String art, [
    String? stand,
  ]) => FernBild(
    verbindung,
    datei(aufnahme, art, stand),
    ablage: ablage == null
        ? null
        : File(
            p.join(
              ablage.path,
              _sicher(id),
              '${_sicher(aufnahme)}.$art${stand == null ? '' : '.${_sicher(stand)}'}',
            ),
          ),
  );

  static String _sicher(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}

/// Eine Aufnahme darin – was die Liste des Servers über sie sagt.
class GeteilteAufnahme {
  const GeteilteAufnahme({
    required this.id,
    required this.video,
    required this.name,
    required this.aufgenommen,
    this.dauer,
    this.von,
    this.eigene = false,
    this.stand,
  });

  factory GeteilteAufnahme.aus(Map<String, Object?> j) => GeteilteAufnahme(
    id: '${j['id']}',
    video: j['art'] == 'video',
    name: '${j['name'] ?? ''}',
    aufgenommen:
        DateTime.tryParse('${j['aufgenommen']}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    dauer: (j['dauer'] as num?)?.toDouble(),
    von: j['von'] as String?,
    eigene: j['eigene'] == true,
    stand: j['stand'] as String?,
  );

  final String id;
  final bool video;
  final String name;
  final DateTime aufgenommen;
  final double? dauer;

  /// Wer sie beigetragen hat, wenn nicht der Besitzer.
  final String? von;

  /// Ob dieses Konto sie beigetragen hat – dann darf es sie wieder
  /// entfernen (#290).
  final bool eigene;
  final String? stand;
}

/// „Geteilt mit mir“ in der Albenliste: ein Abschnitt mit Überschrift,
/// oder nichts, solange nichts geteilt ist (oder der Server es nicht
/// kann, oder das Telefon offline ist).
class GeteilteAlben extends StatefulWidget {
  const GeteilteAlben({super.key, required this.zugang, required this.raster});

  /// `null` ohne Server.
  final Teilungszugang? zugang;
  final SliverGridDelegate raster;

  @override
  State<GeteilteAlben> createState() => _GeteilteAlbenState();
}

class _GeteilteAlbenState extends State<GeteilteAlben> {
  List<GeteiltesAlbum> _alben = const [];

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    final v = widget.zugang?.verbindung;
    if (v == null) return;
    try {
      final d = await v.hole('api/v1/geteilt');
      final liste = [
        for (final x in (d['alben'] as List? ?? const []))
          GeteiltesAlbum.aus((x as Map).cast<String, Object?>()),
      ];
      if (mounted) setState(() => _alben = liste);
      await _raeumeAuf(liste);
    } on KeineVerbindung {
      // Offline: Was geteilt ist, kommt beim nächsten Öffnen.
    } on Serverfehler {
      // Ein Server vor 3.53 kennt keine geteilten Alben.
    }
  }

  /// Was nicht mehr geteilt ist, hat auf diesem Telefon nichts mehr zu
  /// suchen: Es sind Bilder aus der Bibliothek eines anderen.
  Future<void> _raeumeAuf(List<GeteiltesAlbum> liste) async {
    final a = widget.zugang?.ablage;
    if (a == null || !await a.exists()) return;
    final noch = {for (final x in liste) GeteiltesAlbum._sicher(x.id)};
    await for (final e in a.list(followLinks: false)) {
      if (e is Directory && !noch.contains(p.basename(e.path))) {
        try {
          await e.delete(recursive: true);
        } on FileSystemException {
          // Beim nächsten Mal.
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = widget.zugang;
    if (z == null || _alben.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              teilenTexte(context).geteiltMitMir,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid.builder(
            gridDelegate: widget.raster,
            itemCount: _alben.length,
            itemBuilder: (context, i) =>
                _GeteilteKachel(zugang: z, album: _alben[i], geaendert: _lade),
          ),
        ),
      ],
    );
  }
}

class _GeteilteKachel extends StatelessWidget {
  const _GeteilteKachel({
    required this.zugang,
    required this.album,
    required this.geaendert,
  });

  final Teilungszugang zugang;
  final GeteiltesAlbum album;
  final VoidCallback geaendert;

  @override
  Widget build(BuildContext context) {
    final t = teilenTexte(context);
    final farben = Theme.of(context).colorScheme;
    final titel = album.titelbild;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GeteiltesAlbumSeite(zugang: zugang, album: album),
          ),
        );
        geaendert();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(
                child: titel == null
                    ? ColoredBox(color: farben.surfaceContainerHighest)
                    : _FernMiniatur(
                        album.bild(
                          zugang.verbindung,
                          zugang.ablage,
                          titel,
                          'miniatur',
                          album.titelstand,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            t.geteiltVon(album.besitzer),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Eine Miniatur vom Server, auf ihre Grösse dekodiert.
class _FernMiniatur extends StatelessWidget {
  const _FernMiniatur(this.bild);

  final ImageProvider bild;

  @override
  Widget build(BuildContext context) {
    final flaeche = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final breite = (c.maxWidth * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(64, 1024);
        return Image(
          image: ResizeImage(bild, width: breite),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => flaeche,
          frameBuilder: (context, kind, frame, sofort) =>
              frame == null && !sofort ? flaeche : kind,
        );
      },
    );
  }
}

/// Ein Album, das ein anderes Konto teilt: Raster, Betrachter und – mit
/// Recht zum Beitragen – eigene Fotos hinein.
class GeteiltesAlbumSeite extends StatefulWidget {
  const GeteiltesAlbumSeite({
    super.key,
    required this.zugang,
    required this.album,
  });

  final Teilungszugang zugang;
  final GeteiltesAlbum album;

  @override
  State<GeteiltesAlbumSeite> createState() => _GeteiltesAlbumSeiteState();
}

class _GeteiltesAlbumSeiteState extends State<GeteiltesAlbumSeite> {
  late GeteiltesAlbum _album = widget.album;
  List<GeteilteAufnahme>? _aufnahmen;
  Object? _fehler;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final d = await widget.zugang.verbindung.hole(
        'api/v1/geteilt/${_k(widget.album.id)}',
      );
      final a = (d['album'] as Map? ?? const {}).cast<String, Object?>();
      final liste = [
        for (final x in (d['aufnahmen'] as List? ?? const []))
          GeteilteAufnahme.aus((x as Map).cast<String, Object?>()),
      ];
      if (!mounted) return;
      setState(() {
        _album = GeteiltesAlbum(
          id: widget.album.id,
          name: '${a['name'] ?? widget.album.name}',
          besitzer: '${a['besitzer'] ?? widget.album.besitzer}',
          beitragen: a['beitragen'] == true,
          anzahl: liste.length,
        );
        _aufnahmen = liste;
        _fehler = null;
      });
    } on Serverfehler catch (e) {
      if (!mounted) return;
      if (e.status == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(teilenTexte(context).geteiltNichtMehr)),
        );
        Navigator.of(context).pop();
        return;
      }
      setState(() => _fehler = e);
    } on KeineVerbindung catch (e) {
      if (mounted) setState(() => _fehler = e);
    }
  }

  Future<void> _verlassen() async {
    final t = teilenTexte(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.geteiltVerlassenFrage(_album.name, _album.besitzer)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t.abbrechen),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.geteiltVerlassen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    final bote = ScaffoldMessenger.of(context);
    final weg = Navigator.of(context);
    try {
      await widget.zugang.verbindung.anfrage(
        'DELETE',
        'api/v1/geteilt/${_k(_album.id)}',
      );
      // Die Bilder gehören jemand anderem.
      final a = widget.zugang.ablage;
      final hier = a == null
          ? null
          : Directory(p.join(a.path, GeteiltesAlbum._sicher(_album.id)));
      if (hier != null && await hier.exists()) {
        await hier.delete(recursive: true).catchError((_) => hier);
      }
      weg.pop();
    } on KeineVerbindung {
      bote.showSnackBar(SnackBar(content: Text(t.geteiltOffline)));
    }
  }

  Future<void> _hinzufuegen() async {
    final t = teilenTexte(context);
    final bote = ScaffoldMessenger.of(context);
    final waehle = widget.zugang.waehle;
    if (waehle == null) return;
    final dateien = await waehle(context);
    if (dateien.isEmpty || !mounted) return;
    final stand = ValueNotifier<(int, double)>((0, 0));
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: ValueListenableBuilder<(int, double)>(
          valueListenable: stand,
          builder: (c, s, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.geteiltLaedtHoch(s.$1 + 1, dateien.length)),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: s.$2),
            ],
          ),
        ),
      ),
    );
    final weg = Navigator.of(context, rootNavigator: true);
    var gut = 0;
    String? meldung;
    for (var i = 0; i < dateien.length; i++) {
      stand.value = (i, 0);
      final d = dateien[i];
      try {
        final datei = await d.datei();
        if (datei == null) {
          meldung = t.geteiltFehler(d.name);
          continue;
        }
        await widget.zugang.verbindung.schickeDatei(
          'api/v1/geteilt/${_k(_album.id)}/beitrag',
          datei,
          parameter: {
            'name': d.name,
            'geaendert': '${d.geaendert.millisecondsSinceEpoch}',
          },
          fortschritt: (n, g) => stand.value = (i, g == 0 ? 0 : n / g),
        );
        gut++;
      } on Serverfehler catch (e) {
        if (e.status == 403 || e.status == 404) {
          meldung = t.geteiltNurAnsehen;
          break;
        }
        if (e.status == 507) {
          meldung = t.geteiltSpeicherVoll;
          break;
        }
        meldung = t.geteiltFehler(d.name);
      } on KeineVerbindung {
        meldung = t.geteiltOffline;
        break;
      }
    }
    weg.pop();
    await dialog;
    stand.dispose();
    bote.showSnackBar(
      SnackBar(content: Text(meldung ?? t.geteiltHinzugefuegt(gut))),
    );
    if (gut > 0) await _lade();
  }

  @override
  Widget build(BuildContext context) {
    final t = teilenTexte(context);
    final a = _aufnahmen;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              t.geteiltAlbumVon(_album.besitzer),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (_album.beitragen && widget.zugang.waehle != null)
            IconButton(
              tooltip: t.geteiltHinzufuegen,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _hinzufuegen,
            ),
          PopupMenuButton<void>(
            itemBuilder: (_) => [
              PopupMenuItem<void>(
                onTap: _verlassen,
                child: Text(t.geteiltVerlassen),
              ),
            ],
          ),
        ],
      ),
      body: a == null
          ? Center(
              child: _fehler == null
                  ? const CircularProgressIndicator()
                  : Text(t.geteiltOffline),
            )
          : RefreshIndicator(
              onRefresh: _lade,
              child: a.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(child: Text(t.geteiltLeer)),
                        ),
                      ],
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(2),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 130,
                            mainAxisSpacing: 2,
                            crossAxisSpacing: 2,
                          ),
                      itemCount: a.length,
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () async {
                          final geaendert = await Navigator.of(context)
                              .push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => GeteilterBetrachter(
                                    zugang: widget.zugang,
                                    album: _album,
                                    aufnahmen: a,
                                    start: i,
                                  ),
                                ),
                              );
                          if (geaendert == true) await _lade();
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _FernMiniatur(
                              _album.bild(
                                widget.zugang.verbindung,
                                widget.zugang.ablage,
                                a[i].id,
                                'miniatur',
                                a[i].stand,
                              ),
                            ),
                            if (a[i].video)
                              const Positioned(
                                right: 4,
                                bottom: 4,
                                child: Icon(
                                  Icons.play_circle_outline,
                                  color: Colors.white,
                                  size: 20,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
    );
  }
}

/// Die Aufnahmen eines geteilten Albums, eine nach der anderen.
class GeteilterBetrachter extends StatefulWidget {
  const GeteilterBetrachter({
    super.key,
    required this.zugang,
    required this.album,
    required this.aufnahmen,
    required this.start,
  });

  final Teilungszugang zugang;
  final GeteiltesAlbum album;
  final List<GeteilteAufnahme> aufnahmen;
  final int start;

  @override
  State<GeteilterBetrachter> createState() => _GeteilterBetrachterState();
}

class _GeteilterBetrachterState extends State<GeteilterBetrachter> {
  late final _seiten = PageController(initialPage: widget.start);
  late int _index = widget.start;

  @override
  void dispose() {
    _seiten.dispose();
    super.dispose();
  }

  Fernvideo _video(GeteilteAufnahme x) {
    final v = widget.zugang.verbindung;
    final pfad = widget.album.datei(x.id, 'abspielbar');
    return Fernvideo(
      wiedergabe: v.adresse(widget.album.datei(x.id, 'wiedergabe')),
      kopf: {'authorization': 'Bearer ${v.token}'},
      fassung: ({abgebrochen}) async {
        // Die Fassung entsteht beim ersten Abruf; der Server sagt 202,
        // solange er umwandelt.
        for (var i = 0; i < 900; i++) {
          if (abgebrochen?.call() ?? false) return null;
          final r = await v.anfrage('GET', '$pfad?pruefen=1');
          if (r.statusCode == 200) return v.adresse(pfad);
          if (r.statusCode != 202) return null;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        return null;
      },
    );
  }

  /// Den eigenen Beitrag wieder aus dem Album nehmen (#290). Beim
  /// Besitzer kommt er in den Papierkorb, solange er in keinem anderen
  /// seiner Alben liegt.
  Future<void> _entferne(GeteilteAufnahme a) async {
    final t = teilenTexte(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.geteiltEntfernenFrage(a.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t.abbrechen),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.geteiltEntfernen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    final bote = ScaffoldMessenger.of(context);
    final weg = Navigator.of(context);
    try {
      final r = await widget.zugang.verbindung.anfrage(
        'DELETE',
        'api/v1/geteilt/${_k(widget.album.id)}/aufnahmen/${_k(a.id)}',
      );
      if (r.statusCode != 200) throw Serverfehler(r.statusCode, r.body);
      bote.showSnackBar(SnackBar(content: Text(t.geteiltEntfernt)));
      weg.pop(true);
    } on Serverfehler {
      bote.showSnackBar(SnackBar(content: Text(t.geteiltFehler(a.name))));
    } on KeineVerbindung {
      bote.showSnackBar(SnackBar(content: Text(t.geteiltOffline)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = teilenTexte(context);
    final a = widget.aufnahmen[_index];
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final klein = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Colors.white70);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat.yMMMd(
                sprache,
              ).add_Hm().format(a.aufgenommen.toLocal()),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
            Text(
              a.von == null ? a.name : t.geteiltBeigetragenVon(a.von!),
              style: klein,
            ),
          ],
        ),
        actions: [
          if (a.eigene)
            IconButton(
              tooltip: t.geteiltEntfernen,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _entferne(a),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _seiten,
        itemCount: widget.aufnahmen.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final x = widget.aufnahmen[i];
          if (x.video) {
            return widget.zugang.video?.call(context, _video(x)) ??
                const Center(
                  child: Icon(
                    Icons.videocam_off_outlined,
                    color: Colors.white54,
                  ),
                );
          }
          return InteractiveViewer(
            maxScale: 6,
            child: Center(
              child: Image(
                image: widget.album.bild(
                  widget.zugang.verbindung,
                  widget.zugang.ablage,
                  x.id,
                  'ansicht',
                  x.stand,
                ),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                loadingBuilder: (context, kind, fortschritt) =>
                    fortschritt == null
                    ? kind
                    : Image(
                        image: widget.album.bild(
                          widget.zugang.verbindung,
                          widget.zugang.ablage,
                          x.id,
                          'miniatur',
                          x.stand,
                        ),
                        fit: BoxFit.contain,
                      ),
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- Beiträge --------------------------------------------------------------

/// Eine Datei, die in ein geteiltes Album soll. [datei] holt sie erst beim
/// Hochladen – aus der Fotomediathek kann das ein Download aus iCloud sein.
class Beitragsdatei {
  const Beitragsdatei({
    required this.name,
    required this.geaendert,
    required this.datei,
  });

  final String name;
  final DateTime geaendert;
  final Future<File?> Function() datei;
}

// --- Für den Besitzer ------------------------------------------------------

/// „Mit Konten teilen“ für das eigene Album [albumId].
Future<void> mitKontenTeilen(
  BuildContext context,
  Serververbindung? verbindung, {
  required String albumId,
  required String titel,
}) async {
  if (verbindung == null) return;
  final blatt = _KontenBlatt(
    verbindung: verbindung,
    albumId: albumId,
    titel: titel,
  );
  // Am Rechner ein Dialog, am Telefon ein Blatt von unten.
  if (MediaQuery.sizeOf(context).width >= 600) {
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                blatt,
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 12, 12),
                  child: TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text(teilenTexte(c).schliessen),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => blatt,
  );
}

class _Empfaenger {
  const _Empfaenger(this.konto, this.name, this.beitragen);

  final String konto;
  final String name;
  final bool beitragen;
}

class _KontenBlatt extends StatefulWidget {
  const _KontenBlatt({
    required this.verbindung,
    required this.albumId,
    required this.titel,
  });

  final Serververbindung verbindung;
  final String albumId;
  final String titel;

  @override
  State<_KontenBlatt> createState() => _KontenBlattState();
}

class _KontenBlattState extends State<_KontenBlatt> {
  List<_Empfaenger>? _geteilt;
  List<(String, String)> _andere = const [];
  String? _neu;
  var _neuBeitragen = false;
  String? _fehler;

  String get _pfad => 'api/v1/alben/${_k(widget.albumId)}/teilungen';

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final (d, k) = await (
        widget.verbindung.hole(_pfad),
        widget.verbindung.hole('api/v1/konten/andere'),
      ).wait;
      if (!mounted) return;
      final geteilt = [
        for (final x in (d['teilungen'] as List? ?? const []))
          if (x case {'konto': final konto, 'name': final name})
            _Empfaenger('$konto', '$name', x['beitragen'] == true),
      ];
      final schon = {for (final g in geteilt) g.konto};
      setState(() {
        _geteilt = geteilt;
        _andere = [
          for (final x in (k['konten'] as List? ?? const []))
            if (x case {'id': final id, 'name': final name})
              if (!schon.contains('$id')) ('$id', '$name'),
        ];
        _neu = _andere.isEmpty ? null : _andere.first.$1;
        _fehler = null;
      });
    } on ParallelWaitError<dynamic, dynamic> {
      if (mounted) {
        setState(() => _fehler = teilenTexte(context).geteiltOffline);
      }
    }
  }

  Future<void> _aendere(Future<void> Function() schritt) async {
    try {
      await schritt();
    } on Serverfehler catch (e) {
      if (mounted) setState(() => _fehler = e.text);
      return;
    } on KeineVerbindung {
      if (mounted) {
        setState(() => _fehler = teilenTexte(context).geteiltOffline);
      }
      return;
    }
    await _lade();
  }

  Future<void> _teile(String konto, bool beitragen) => _aendere(() async {
    final r = await widget.verbindung.anfrage(
      'PUT',
      '$_pfad/${_k(konto)}',
      kopf: {'content-type': 'application/json'},
      inhalt: '{"beitragen":$beitragen}'.codeUnits,
    );
    if (r.statusCode != 200) throw Serverfehler(r.statusCode, r.body);
  });

  Future<void> _entferne(String konto) => _aendere(() async {
    final r = await widget.verbindung.anfrage('DELETE', '$_pfad/${_k(konto)}');
    if (r.statusCode != 204) throw Serverfehler(r.statusCode, r.body);
  });

  @override
  Widget build(BuildContext context) {
    final t = teilenTexte(context);
    final geteilt = _geteilt;
    DropdownButton<bool> recht(bool wert, ValueChanged<bool> neu) =>
        DropdownButton<bool>(
          value: wert,
          underline: const SizedBox.shrink(),
          items: [
            DropdownMenuItem(value: false, child: Text(t.kontenAnsehen)),
            DropdownMenuItem(value: true, child: Text(t.kontenBeitragen)),
          ],
          onChanged: (w) => w == null ? null : neu(w),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.kontenTeilenTitel(widget.titel),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(t.kontenTeilenHinweis),
            const SizedBox(height: 12),
            if (geteilt == null && _fehler == null)
              const Center(child: CircularProgressIndicator())
            else if (geteilt != null) ...[
              if (geteilt.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(t.kontenNiemand),
                ),
              for (final g in geteilt)
                Row(
                  children: [
                    Expanded(child: Text(g.name)),
                    recht(g.beitragen, (w) => _teile(g.konto, w)),
                    IconButton(
                      tooltip: t.entfernen,
                      icon: const Icon(Icons.close),
                      onPressed: () => _entferne(g.konto),
                    ),
                  ],
                ),
              if (_andere.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _neu,
                        items: [
                          for (final (id, name) in _andere)
                            DropdownMenuItem(value: id, child: Text(name)),
                        ],
                        onChanged: (w) => setState(() => _neu = w),
                      ),
                    ),
                    const SizedBox(width: 8),
                    recht(
                      _neuBeitragen,
                      (w) => setState(() => _neuBeitragen = w),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _neu == null
                          ? null
                          : () => _teile(_neu!, _neuBeitragen),
                      child: Text(t.kontenTeilenKnopf),
                    ),
                  ],
                )
              else if (geteilt.isEmpty)
                Text(t.kontenKeineAnderen),
            ],
            if (_fehler case final f?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  f,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              t.kontenBeitragenHinweis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
