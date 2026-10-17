import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/rasterzeile.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../lokal/lokalbetrachter.dart';
import '../lokal/ungesichert.dart';
import '../sitzung.dart';
import 'auswahl.dart';
import 'betrachter.dart';

/// Aufnahmen als Raster – auf Wunsch nach Monaten und Tagen gegliedert,
/// wie in der Zeitleiste. Ein Tipp öffnet den Betrachter mit genau dieser
/// Liste.
///
/// Ausgewählt wird wie in Immich: langes Drücken wählt eine Aufnahme, und
/// wer danach den Finger weiterzieht, nimmt alles bis dorthin mit. Ein
/// Tipp auf das Datum wählt den ganzen Tag. Solange etwas gewählt ist,
/// sammelt jeder Tipp weitere ein, und unten erscheint das Blatt mit den
/// Aktionen (Issue #128).
class AufnahmenRaster extends StatefulWidget {
  const AufnahmenRaster({
    super.key,
    required this.sitzung,
    required this.zeilen,
    this.nachTagen = false,
    this.kopf,
    this.lokal = const {},
  });

  final Sitzung sitzung;
  final List<Rasterzeile> zeilen;
  final bool nachTagen;

  /// Zeilen aus [zeilen], die nur auf dem Telefon liegen (Issue #127),
  /// nach ihrer Kennung – sie zeigen die Fotomediathek, nicht die
  /// Bibliothek, und lassen sich nicht auswählen.
  final Map<String, LokaleAufnahme> lokal;

  /// Etwas über dem Raster (z. B. das Suchfeld), das mitscrollt.
  final Widget? kopf;

  @override
  State<AufnahmenRaster> createState() => _AufnahmenRasterState();
}

/// Die Marke an jeder Kachel: Über sie findet das Ziehen heraus, welche
/// Kachel gerade unter dem Finger liegt.
class _Kachelmarke {
  const _Kachelmarke(this.index);
  final int index;
}

class _AufnahmenRasterState extends State<AufnahmenRaster> {
  static const _spalten = 4;

  /// Wie nah am oberen oder unteren Rand der Finger beim Ziehen stehen
  /// muss, damit das Raster von selbst weiterrollt.
  static const _rollrand = 72.0;

  final _auswahl = <String>{};
  final _scroll = ScrollController();
  final _flaeche = GlobalKey();

  // Das Ziehen nach langem Druck: von der ersten Kachel bis zu der unter
  // dem Finger wird gewählt – oder abgewählt, wenn die erste schon gewählt
  // war. Was vorher gewählt war, bleibt davon unberührt.
  int? _anker;
  int? _letzter;
  var _ziehWaehlt = true;
  var _vorDemZiehen = const <String>{};
  Offset? _finger;
  Timer? _rollen;

  bool get _waehlt => _auswahl.isNotEmpty;

  @override
  void dispose() {
    _rollen?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AufnahmenRaster alt) {
    super.didUpdateWidget(alt);
    // Was aus der Liste verschwand (Papierkorb, anderer Filter), ist auch
    // nicht mehr ausgewählt.
    final da = {for (final z in widget.zeilen) z.id};
    _auswahl.removeWhere((id) => !da.contains(id));
    if (_anker != null && _anker! >= widget.zeilen.length) _ziehEnde();
  }

  void _oeffne(int index) {
    final z = widget.zeilen[index];
    final l = widget.lokal[z.id];
    final Widget seite;
    if (l != null) {
      // Nur die vom Telefon, in der Reihenfolge des Rasters.
      final lokale = [for (final x in widget.zeilen) ?widget.lokal[x.id]];
      seite = Lokalbetrachter(
        sitzung: widget.sitzung,
        aufnahmen: lokale,
        start: lokale.indexOf(l),
      );
    } else {
      final server = [
        for (final x in widget.zeilen)
          if (!widget.lokal.containsKey(x.id)) x,
      ];
      seite = Betrachter(
        sitzung: widget.sitzung,
        zeilen: server,
        start: server.indexWhere((x) => x.id == z.id),
      );
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => seite));
  }

  /// Was nur auf dem Telefon liegt, lässt sich nicht wählen – es gibt
  /// dafür keinen Befehl.
  bool _waehlbar(Rasterzeile z) => !widget.lokal.containsKey(z.id);

  void _schalte(String id) {
    if (widget.lokal.containsKey(id)) return;
    setState(() {
      if (!_auswahl.remove(id)) _auswahl.add(id);
    });
  }

  List<String> _waehlbareIds(int von, int bis) => [
    for (var i = von; i < bis; i++)
      if (_waehlbar(widget.zeilen[i])) widget.zeilen[i].id,
  ];

  /// Der ganze Tag – sind schon alle gewählt, fallen sie wieder heraus.
  void _schalteTag(int von, int bis) {
    final ids = _waehlbareIds(von, bis);
    if (ids.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (ids.every(_auswahl.contains)) {
        _auswahl.removeAll(ids);
      } else {
        _auswahl.addAll(ids);
      }
    });
  }

  int? _indexBei(Offset global) {
    final box = _flaeche.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final ergebnis = BoxHitTestResult();
    box.hitTest(ergebnis, position: box.globalToLocal(global));
    for (final e in ergebnis.path) {
      final ziel = e.target;
      if (ziel is RenderMetaData && ziel.metaData is _Kachelmarke) {
        return (ziel.metaData as _Kachelmarke).index;
      }
    }
    return null;
  }

  void _ziehBeginn(int index) {
    final z = widget.zeilen[index];
    if (!_waehlbar(z)) return;
    HapticFeedback.selectionClick();
    _anker = index;
    _letzter = index;
    _ziehWaehlt = !_auswahl.contains(z.id);
    _vorDemZiehen = {..._auswahl};
    _wendeAn(index);
  }

  void _ziehWeiter(Offset global) {
    if (_anker == null) return;
    _finger = global;
    _folge(global);
    _pruefeRand();
  }

  void _folge(Offset global) {
    final i = _indexBei(global);
    if (i == null || i == _letzter) return;
    _letzter = i;
    HapticFeedback.selectionClick();
    _wendeAn(i);
  }

  void _wendeAn(int bis) {
    final anker = _anker!;
    final von = anker <= bis ? anker : bis;
    final zu = anker <= bis ? bis : anker;
    setState(() {
      _auswahl
        ..clear()
        ..addAll(_vorDemZiehen);
      for (var i = von; i <= zu; i++) {
        final z = widget.zeilen[i];
        if (!_waehlbar(z)) continue;
        if (_ziehWaehlt) {
          _auswahl.add(z.id);
        } else {
          _auswahl.remove(z.id);
        }
      }
    });
  }

  void _ziehEnde() {
    _anker = null;
    _letzter = null;
    _finger = null;
    _rollen?.cancel();
    _rollen = null;
  }

  /// -1 oben am Rand, 1 unten, sonst 0.
  int _randRichtung() {
    final box = _flaeche.currentContext?.findRenderObject();
    final f = _finger;
    if (box is! RenderBox || f == null) return 0;
    final y = box.globalToLocal(f).dy;
    if (y < _rollrand) return -1;
    if (y > box.size.height - _rollrand) return 1;
    return 0;
  }

  /// Am Rand rollt das Raster weiter, solange der Finger dort steht, und
  /// die Auswahl wächst mit.
  void _pruefeRand() {
    if (_randRichtung() == 0) {
      _rollen?.cancel();
      _rollen = null;
      return;
    }
    _rollen ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final r = _randRichtung();
      final f = _finger;
      if (r == 0 || f == null || !_scroll.hasClients) {
        _rollen?.cancel();
        _rollen = null;
        return;
      }
      final pos = _scroll.position;
      final ziel = (pos.pixels + r * 14).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      if (ziel == pos.pixels) return;
      _scroll.jumpTo(ziel);
      _folge(f);
    });
  }

  Widget _kachel(int i) {
    final z = widget.zeilen[i];
    final l = widget.lokal[z.id];
    final gewaehlt = _auswahl.contains(z.id);
    final farben = Theme.of(context).colorScheme;
    return MetaData(
      metaData: _Kachelmarke(i),
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onTap: () => _waehlt && l == null ? _schalte(z.id) : _oeffne(i),
        onLongPressStart: (_) => _ziehBeginn(i),
        onLongPressMoveUpdate: (d) => _ziehWeiter(d.globalPosition),
        onLongPressEnd: (_) => _ziehEnde(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Gewählt rückt die Kachel ein und rundet sich – wie in Immich.
            AnimatedPadding(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              padding: EdgeInsets.all(gewaehlt ? 10 : 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(gewaehlt ? 12 : 0),
                child: Miniatur(
                  paths: widget.sitzung.paths,
                  relativ: z.thumbnailRelativePath,
                  bild: l?.bild,
                  video: z.type == 'VIDEO',
                  favorit: z.isFavorite,
                ),
              ),
            ),
            if (l != null)
              const Positioned(
                right: 4,
                top: 4,
                child: Icon(
                  Icons.cloud_off_outlined,
                  color: Colors.white,
                  size: 18,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            if (_waehlt && l == null)
              Positioned(
                left: 4,
                top: 4,
                child: gewaehlt
                    ? DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle,
                          color: farben.primary,
                          size: 22,
                        ),
                      )
                    : const Icon(
                        Icons.circle_outlined,
                        color: Colors.white,
                        size: 22,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
              ),
          ],
        ),
      ),
    );
  }

  /// Der Kopf eines Tages: das Datum und der Kreis, der den ganzen Tag
  /// wählt. Antippen lässt sich die ganze Zeile, nicht nur der Kreis.
  Widget _tageskopf(String datum, int von, int bis) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final ids = _waehlbareIds(von, bis);
    final alle = ids.isNotEmpty && ids.every(_auswahl.contains);
    // Datum und Kreis sind zusammen ein Knopf – die Bedienhilfe liest das
    // Datum und sagt dazu, was ein Tipp tut.
    return Semantics(
      button: ids.isNotEmpty,
      selected: alle,
      hint: ids.isEmpty
          ? null
          : alle
          ? t.auswahlTagAbwaehlen
          : t.auswahlTagWaehlen,
      child: InkWell(
        onTap: ids.isEmpty ? null : () => _schalteTag(von, bis),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  datum,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (ids.isNotEmpty)
                Icon(
                  alle ? Icons.check_circle : Icons.circle_outlined,
                  size: 22,
                  color: alle ? farben.primary : farben.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  SliverGrid _gitter(int von, int bis) => SliverGrid(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: _spalten,
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
    ),
    delegate: SliverChildBuilderDelegate(
      (context, i) => _kachel(von + i),
      childCount: bis - von,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final zeilen = widget.zeilen;
    final slivers = <Widget>[
      if (widget.kopf != null) SliverToBoxAdapter(child: widget.kopf),
    ];
    if (!widget.nachTagen) {
      slivers.add(_gitter(0, zeilen.length));
    } else {
      final sprache = Localizations.localeOf(context).toLanguageTag();
      final monatFormat = DateFormat.yMMMM(sprache);
      final tagFormat = DateFormat.MMMMEEEEd(sprache);
      final monatStil = Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600);
      DateTime? monat;
      var von = 0;
      while (von < zeilen.length) {
        final tag = DateUtils.dateOnly(zeilen[von].fileCreatedAt.toLocal());
        var bis = von + 1;
        while (bis < zeilen.length &&
            DateUtils.dateOnly(zeilen[bis].fileCreatedAt.toLocal()) == tag) {
          bis++;
        }
        // Ein Monatskopf über dem ersten Tag jedes Monats, wie in Immich –
        // die Tage darunter brauchen dann kein Jahr mehr.
        final dieserMonat = DateTime(tag.year, tag.month);
        if (dieserMonat != monat) {
          monat = dieserMonat;
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
                child: Text(monatFormat.format(tag), style: monatStil),
              ),
            ),
          );
        }
        final tagVon = von, tagBis = bis;
        slivers
          ..add(
            SliverToBoxAdapter(
              child: _tageskopf(tagFormat.format(tag), tagVon, tagBis),
            ),
          )
          ..add(_gitter(von, bis));
        von = bis;
      }
    }
    // Unter dem letzten Rand bleibt Platz für die Leiste.
    slivers.add(
      SliverToBoxAdapter(child: SizedBox(height: _waehlt ? 300 : 24)),
    );
    return Stack(
      children: [
        CustomScrollView(key: _flaeche, controller: _scroll, slivers: slivers),
        if (_waehlt)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Auswahlleiste(
              sitzung: widget.sitzung,
              zeilen: [
                for (final z in zeilen)
                  if (_auswahl.contains(z.id)) z,
              ],
              aufheben: () => setState(_auswahl.clear),
            ),
          ),
      ],
    );
  }
}
