import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
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
    this.papierkorb = false,
  });

  /// Die Aufnahmen liegen im Papierkorb: Das Blatt holt zurück, statt
  /// wegzuwerfen, und der Betrachter ebenso.
  final bool papierkorb;

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
  /// Zwei Finger auseinander: weniger, grössere Kacheln; zusammen: mehr.
  /// Die Zahl gilt für dieses Gerät und bleibt (siehe Sitzung).
  late var _spalten = widget.sitzung.rasterspalten;
  static const _wenigsteSpalten = 2, _meisteSpalten = 6;
  final _kneifer = <int, Offset>{};
  double? _startAbstand;
  var _startSpalten = Sitzung.spaltenVorgabe;

  // Die Bildlaufleiste rechts: erscheint beim Rollen, verschwindet nach
  // einer Pause; beim Ziehen zeigt sie den Monat oben im Bild. Eigene
  // Benachrichtiger statt setState – siehe [_auswahlStand].
  final _leisteSichtbar = ValueNotifier(false);
  final _leisteGezogen = ValueNotifier(false);
  Timer? _leisteAus;
  final _leisteText = ValueNotifier<String?>(null);

  /// Wie nah am oberen oder unteren Rand der Finger beim Ziehen stehen
  /// muss, damit das Raster von selbst weiterrollt.
  static const _rollrand = 72.0;

  final _auswahl = <String>{};

  /// Zählt jede Änderung an [_auswahl]. Kacheln, Tagesköpfe und das Blatt
  /// hören darauf; neu gebaut wird nur, was gerade zu sehen ist.
  ///
  /// **Vorher baute jede Änderung das ganze Raster.** Ein Tipp auf einen
  /// Tag, jeder Schritt beim Ziehen und jedes Ein- und Ausblenden der
  /// Bildlaufleiste gruppierte alle Aufnahmen neu nach Tagen und legte für
  /// jeden Tag einen Kopf an – bei 8000 Aufnahmen im Test gut eine halbe
  /// Sekunde je Tipp.
  final _auswahlStand = ValueNotifier(0);

  /// Die Tage von [AufnahmenRaster.zeilen], einmal je Liste gerechnet –
  /// erkannt an der Liste selbst und ihrer Länge.
  List<_Tag> _tageCache = const [];
  List<Rasterzeile>? _tageFuer;
  var _tageLaenge = -1;

  List<_Tag> _tageVon(List<Rasterzeile> zeilen) {
    if (!identical(zeilen, _tageFuer) || zeilen.length != _tageLaenge) {
      _tageCache = _tage(zeilen);
      _tageFuer = zeilen;
      _tageLaenge = zeilen.length;
    }
    return _tageCache;
  }

  /// Die Zeilen der Liste nach Tagen – Monatsköpfe, Tagesköpfe und
  /// Kachelreihen –, neu nur für neue Tage oder eine andere Spaltenzahl.
  List<_Eintrag> _eintraege = const [];
  List<_Tag>? _eintraegeFuer;
  var _eintraegeSpalten = 0;

  List<_Eintrag> _eintraegeVon(List<_Tag> tage) {
    if (!identical(tage, _eintraegeFuer) || _spalten != _eintraegeSpalten) {
      final liste = <_Eintrag>[];
      DateTime? monat;
      for (var t = 0; t < tage.length; t++) {
        final (:tag, :von, :bis) = tage[t];
        // Ein Monatskopf über dem ersten Tag jedes Monats, wie in Immich –
        // die Tage darunter brauchen dann kein Jahr mehr.
        final dieserMonat = DateTime(tag.year, tag.month);
        if (dieserMonat != monat) {
          monat = dieserMonat;
          liste.add((art: _Art.monat, tag: t, von: von));
        }
        liste.add((art: _Art.tag, tag: t, von: von));
        for (var i = von; i < bis; i += _spalten) {
          liste.add((art: _Art.reihe, tag: t, von: i));
        }
      }
      _eintraege = liste;
      _eintraegeFuer = tage;
      _eintraegeSpalten = _spalten;
    }
    return _eintraege;
  }

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

  /// Ändert die Auswahl. Ein ganzer Neubau nur, wenn das Wählen damit
  /// beginnt oder endet (Kreise an den Kacheln, das Blatt unten).
  void _aendereAuswahl(VoidCallback aenderung) {
    final vorher = _waehlt;
    aenderung();
    _auswahlStand.value++;
    if (_waehlt != vorher) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_gerollt);
  }

  @override
  void dispose() {
    _rollen?.cancel();
    _leisteAus?.cancel();
    _scroll.dispose();
    _auswahlStand.dispose();
    _leisteSichtbar.dispose();
    _leisteGezogen.dispose();
    _leisteText.dispose();
    super.dispose();
  }

  // --- Zwei Finger ---------------------------------------------------------

  double _abstand() {
    final f = _kneifer.values.toList();
    return (f[0] - f[1]).distance;
  }

  void _fingerAb(PointerDownEvent e) {
    _kneifer[e.pointer] = e.position;
    if (_kneifer.length == 2) {
      _startAbstand = _abstand();
      _startSpalten = _spalten;
    }
  }

  void _fingerZug(PointerMoveEvent e) {
    if (!_kneifer.containsKey(e.pointer)) return;
    _kneifer[e.pointer] = e.position;
    final start = _startAbstand;
    if (_kneifer.length != 2 || start == null || start < 30) return;
    final ziel = (_startSpalten / (_abstand() / start)).round().clamp(
      _wenigsteSpalten,
      _meisteSpalten,
    );
    if (ziel != _spalten) {
      HapticFeedback.selectionClick();
      _setzeSpalten(ziel);
    }
  }

  void _fingerWeg(PointerEvent e) {
    _kneifer.remove(e.pointer);
    if (_kneifer.length < 2 && _startAbstand != null) {
      _startAbstand = null;
      unawaited(widget.sitzung.setzeRasterspalten(_spalten));
    }
  }

  /// Neue Spaltenzahl – und ungefähr dieselbe Stelle im Raster danach.
  void _setzeSpalten(int n) {
    final pos = _scroll.hasClients ? _scroll.position : null;
    final anteil = pos == null || pos.maxScrollExtent <= 0
        ? 0.0
        : pos.pixels / pos.maxScrollExtent;
    setState(() => _spalten = n);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      _scroll.jumpTo(
        (anteil * p.maxScrollExtent).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        ),
      );
    });
  }

  // --- Bildlaufleiste ------------------------------------------------------

  void _gerollt() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // Kurze Listen brauchen keine.
    if (pos.maxScrollExtent < pos.viewportDimension * 2) return;
    _leisteSichtbar.value = true;
    _leisteAus?.cancel();
    if (!_leisteGezogen.value) {
      _leisteAus = Timer(const Duration(milliseconds: 1500), () {
        if (mounted && !_leisteGezogen.value) _leisteSichtbar.value = false;
      });
    }
  }

  /// Der Monat der obersten sichtbaren Kachel.
  String? _monatOben() {
    final box = _flaeche.currentContext?.findRenderObject();
    if (box is! RenderBox) return null;
    for (var y = 8.0; y < 240; y += 24) {
      final i = _indexBei(box.localToGlobal(Offset(24, y)));
      if (i != null) {
        final sprache = Localizations.localeOf(context).toLanguageTag();
        return DateFormat.yMMMM(
          sprache,
        ).format(widget.zeilen[i].fileCreatedAt.toLocal());
      }
    }
    return null;
  }

  Widget _bildlaufleiste() => ListenableBuilder(
    listenable: Listenable.merge([
      _scroll,
      _leisteSichtbar,
      _leisteGezogen,
      _leisteText,
    ]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, c) {
        const griff = 44.0;
        final farben = Theme.of(context).colorScheme;
        final pos = _scroll.hasClients ? _scroll.position : null;
        final max = pos?.maxScrollExtent ?? 0;
        final spielraum = c.maxHeight - griff;
        final anteil = pos == null || max <= 0
            ? 0.0
            : (pos.pixels / max).clamp(0.0, 1.0);
        final oben = anteil * spielraum;
        void ziehe(Offset global) {
          final box = context.findRenderObject();
          if (box is! RenderBox || pos == null || max <= 0) return;
          final y = box.globalToLocal(global).dy;
          final a = ((y - griff / 2) / spielraum).clamp(0.0, 1.0);
          _scroll.jumpTo(a * max);
          _leisteText.value = _monatOben();
        }

        final text = _leisteText.value;
        final sichtbar = _leisteSichtbar.value || _leisteGezogen.value;
        return IgnorePointer(
          ignoring: !sichtbar,
          child: AnimatedOpacity(
            opacity: sichtbar ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Stack(
              children: [
                if (_leisteGezogen.value && text != null)
                  Positioned(
                    right: 52,
                    top: oben + 6,
                    child: Material(
                      color: farben.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: farben.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  top: oben,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (d) {
                      _leisteAus?.cancel();
                      HapticFeedback.selectionClick();
                      _leisteGezogen.value = true;
                      ziehe(d.globalPosition);
                    },
                    onVerticalDragUpdate: (d) => ziehe(d.globalPosition),
                    onVerticalDragEnd: (_) {
                      _leisteGezogen.value = false;
                      _leisteText.value = null;
                      _gerollt();
                    },
                    child: Container(
                      key: const ValueKey('bildlaufleiste'),
                      width: 40,
                      height: griff,
                      decoration: BoxDecoration(
                        color: farben.surfaceContainerHighest,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(22),
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4),
                        ],
                      ),
                      child: Icon(
                        Icons.unfold_more,
                        size: 20,
                        color: farben.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

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
        imPapierkorb: widget.papierkorb,
      );
    }
    Navigator.of(context).push(
      l != null
          ? MaterialPageRoute<void>(builder: (_) => seite)
          : betrachterWeg(seite),
    );
  }

  /// Was nur auf dem Telefon liegt, lässt sich nicht wählen – es gibt
  /// dafür keinen Befehl.
  bool _waehlbar(Rasterzeile z) => !widget.lokal.containsKey(z.id);

  void _schalte(String id) {
    if (widget.lokal.containsKey(id)) return;
    _aendereAuswahl(() {
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
    _aendereAuswahl(() {
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
    _aendereAuswahl(() {
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
    final farben = Theme.of(context).colorScheme;
    return MetaData(
      metaData: _Kachelmarke(i),
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onTap: () => _waehlt && l == null ? _schalte(z.id) : _oeffne(i),
        onLongPressStart: (_) => _ziehBeginn(i),
        onLongPressMoveUpdate: (d) => _ziehWeiter(d.globalPosition),
        onLongPressEnd: (_) => _ziehEnde(),
        child: ListenableBuilder(
          listenable: _auswahlStand,
          // Das Bild selbst bleibt beim Wählen, wie es ist.
          child: Miniatur(
            paths: widget.sitzung.paths,
            relativ: z.thumbnailRelativePath,
            bild: l?.bild,
            video: z.type == 'VIDEO',
            favorit: z.isFavorite,
            serie: z.isStackCover ? (z.stackSize ?? 0) : 0,
          ),
          builder: (context, bild) {
            final gewaehlt = _auswahl.contains(z.id);
            return Stack(
              fit: StackFit.expand,
              children: [
                // Gewählt rückt die Kachel ein und rundet sich – wie in Immich.
                AnimatedPadding(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.all(gewaehlt ? 10 : 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(gewaehlt ? 12 : 0),
                    child: bild,
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
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 4),
                            ],
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Der Kopf eines Tages: das Datum und der Kreis, der den ganzen Tag
  /// wählt. Antippen lässt sich die ganze Zeile, nicht nur der Kreis.
  Widget _tageskopf(String datum, int von, int bis) => ListenableBuilder(
    listenable: _auswahlStand,
    builder: (context, _) => _tageskopfInhalt(datum, von, bis),
  );

  Widget _tageskopfInhalt(String datum, int von, int bis) {
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

  /// Eine Reihe Kacheln eines Tages, von [von] bis höchstens [bis] – so
  /// breit und mit denselben Abständen wie im [SliverGrid] von [_gitter].
  Widget _reihe(int von, int bis, bool letzte) => Padding(
    padding: EdgeInsets.only(bottom: letzte ? 0 : 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var c = 0; c < _spalten; c++) ...[
          if (c > 0) const SizedBox(width: 2),
          Expanded(
            child: von + c < bis ? _kachel(von + c) : const SizedBox.shrink(),
          ),
        ],
      ],
    ),
  );

  SliverGrid _gitter(int von, int bis) => SliverGrid(
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
      // **Eine einzige Liste, gebaut wird nur, was zu sehen ist.** Vorher
      // war jeder Tag ein eigener Abschnitt mit eigenem Kopf, und Köpfe
      // baut Flutter sofort, auch weit ausserhalb des Bildes: bei 8000
      // Aufnahmen gut 2000 Tagesköpfe bei jedem Neubau, und jeder davon
      // hörte auf die Auswahl. Die Höhen stehen fest (die Köpfe aus ihrer
      // Schrift gerechnet), deshalb kennt die Liste ihre Länge genau und
      // die Bildlaufleiste springt dorthin, wo sie soll.
      final sprache = Localizations.localeOf(context).toLanguageTag();
      final monatFormat = DateFormat.yMMMM(sprache);
      final tagFormat = DateFormat.MMMMEEEEd(sprache);
      final themen = Theme.of(context).textTheme;
      final monatStil = themen.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      );
      final skala = MediaQuery.textScalerOf(context);
      double zeilenhoehe(TextStyle? stil) {
        final maler = TextPainter(
          text: TextSpan(text: 'Ág', style: stil),
          textDirection: TextDirection.ltr,
          textScaler: skala,
        )..layout();
        final h = maler.height;
        maler.dispose();
        return h;
      }

      final double monatHoehe = 20 + zeilenhoehe(monatStil);
      final double tagHoehe =
          18 + math.max(22.0, zeilenhoehe(themen.titleSmall));
      final tage = _tageVon(zeilen);
      final eintraege = _eintraegeVon(tage);
      final spalten = _spalten;
      bool letzteReihe(_Eintrag e) => e.von + spalten >= tage[e.tag].bis;
      slivers.add(
        SliverVariedExtentList.builder(
          itemCount: eintraege.length,
          itemExtentBuilder: (i, masse) {
            if (i >= eintraege.length) return null;
            final e = eintraege[i];
            return switch (e.art) {
              _Art.monat => monatHoehe,
              _Art.tag => tagHoehe,
              _Art.reihe =>
                (masse.crossAxisExtent - 2 * (spalten - 1)) / spalten +
                    (letzteReihe(e) ? 0.0 : 2.0),
            };
          },
          itemBuilder: (context, i) {
            final e = eintraege[i];
            final (:tag, :von, :bis) = tage[e.tag];
            return switch (e.art) {
              _Art.monat => Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
                child: Text(monatFormat.format(tag), style: monatStil),
              ),
              _Art.tag => _tageskopf(tagFormat.format(tag), von, bis),
              _Art.reihe => _reihe(e.von, bis, letzteReihe(e)),
            };
          },
        ),
      );
    }
    // Unter dem letzten Rand bleibt Platz für die Leiste.
    slivers.add(
      SliverToBoxAdapter(child: SizedBox(height: _waehlt ? 300 : 24)),
    );
    return Stack(
      children: [
        Listener(
          onPointerDown: _fingerAb,
          onPointerMove: _fingerZug,
          onPointerUp: _fingerWeg,
          onPointerCancel: _fingerWeg,
          child: CustomScrollView(
            key: _flaeche,
            controller: _scroll,
            slivers: slivers,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: _waehlt ? 300 : 0,
          width: 240,
          child: _bildlaufleiste(),
        ),
        if (_waehlt)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ListenableBuilder(
              listenable: _auswahlStand,
              builder: (context, _) => Auswahlleiste(
                sitzung: widget.sitzung,
                papierkorb: widget.papierkorb,
                zeilen: [
                  for (final z in zeilen)
                    if (_auswahl.contains(z.id)) z,
                ],
                aufheben: () => _aendereAuswahl(_auswahl.clear),
              ),
            ),
          ),
      ],
    );
  }
}

/// Ein Tag im Raster: die Aufnahmen [von] bis ausschliesslich [bis].
typedef _Tag = ({DateTime tag, int von, int bis});

enum _Art { monat, tag, reihe }

/// Eine Zeile der Liste nach Tagen: zum Tag Nummer [tag] in den Tagen, bei
/// einer Reihe ab der Aufnahme [von].
typedef _Eintrag = ({_Art art, int tag, int von});

/// Die Tage der nach Zeit geordneten [zeilen], in der Ortszeit des Geräts.
List<_Tag> _tage(List<Rasterzeile> zeilen) {
  final tage = <_Tag>[];
  var von = 0;
  while (von < zeilen.length) {
    final tag = DateUtils.dateOnly(zeilen[von].fileCreatedAt.toLocal());
    var bis = von + 1;
    while (bis < zeilen.length &&
        DateUtils.dateOnly(zeilen[bis].fileCreatedAt.toLocal()) == tag) {
      bis++;
    }
    tage.add((tag: tag, von: von, bis: bis));
    von = bis;
  }
  return tage;
}
