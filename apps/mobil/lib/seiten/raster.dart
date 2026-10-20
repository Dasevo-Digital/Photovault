import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:kern/db/listenangaben.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/bildreihen.dart';
import 'package:kern/services/groessentext.dart';
import 'package:kern/services/listengliederung.dart';
import 'package:kern/services/listenspalten.dart';
import 'package:kern/services/rasterstufen.dart';

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
/// Was die Liste statt der Kacheln zeigt (Issue #195): die Angaben je
/// Aufnahme, wonach gegliedert und welche Spalten.
class Listenansicht {
  const Listenansicht({
    required this.angaben,
    required this.gliederung,
    required this.spalten,
  });

  final Map<String, Listenangaben> angaben;
  final ListenGruppierung gliederung;
  final Listenspaltenwahl spalten;
}

class AufnahmenRaster extends StatefulWidget {
  const AufnahmenRaster({
    super.key,
    required this.sitzung,
    required this.zeilen,
    this.nachTagen = false,
    this.kopf,
    this.lokal = const {},
    this.papierkorb = false,
    this.liste,
  });

  /// Statt Kacheln eine Liste (Issue #195) – wie am Rechner und im
  /// Browser. Auswahl, Ziehen und Betrachter bleiben dieselben.
  final Listenansicht? liste;

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

  // Form und Gliederung wie in der Ansichtsleiste gewählt (Issue #194) –
  // für jedes Raster dieses Geräts, wie im Browser.
  late var _reihen = widget.sitzung.form == Zeitleistenform.reihen;
  late var _nurMonate = widget.sitzung.nurMonate;

  void _sitzungGeaendert() {
    final s = widget.sitzung;
    final reihen = s.form == Zeitleistenform.reihen;
    if (reihen != _reihen || s.nurMonate != _nurMonate) {
      setState(() {
        _reihen = reihen;
        _nurMonate = s.nurMonate;
      });
    }
    // Die Knöpfe der Leiste; während zwei Finger ziehen, gilt das Ziehen.
    if (s.rasterspalten != _spalten && _kneifer.length < 2) {
      _setzeSpalten(s.rasterspalten);
    }
  }

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
  bool? _tageJeMonat;

  List<_Tag> _tageVon(List<Rasterzeile> zeilen) {
    // Ohne Gliederung (bündige Reihen ausserhalb der Zeitleiste) ist die
    // ganze Liste eine Gruppe.
    final jeMonat = widget.nachTagen ? _nurMonate : null;
    if (!identical(zeilen, _tageFuer) ||
        zeilen.length != _tageLaenge ||
        jeMonat != _tageJeMonat) {
      _tageCache = jeMonat == null
          ? [
              if (zeilen.isNotEmpty)
                (tag: DateTime(0), von: 0, bis: zeilen.length),
            ]
          : _tage(zeilen, jeMonat: jeMonat);
      _tageFuer = zeilen;
      _tageLaenge = zeilen.length;
      _tageJeMonat = jeMonat;
    }
    return _tageCache;
  }

  /// Die Zeilen der Liste nach Tagen – Monatsköpfe, Tagesköpfe und
  /// Kachelreihen –, neu nur für neue Tage oder eine andere Spaltenzahl.
  List<_Eintrag> _eintraege = const [];
  List<_Tag>? _eintraegeFuer;
  Object? _eintraegeSchluessel;

  /// [breite] zählt nur bei bündigen Reihen: Dort hängt die Aufteilung an
  /// ihr, bei Quadraten nur die Höhe.
  List<_Eintrag> _eintraegeVon(List<_Tag> tage, double breite) {
    final schluessel = (
      _spalten,
      _reihen,
      _nurMonate,
      widget.nachTagen,
      _reihen ? breite : 0.0,
    );
    if (!identical(tage, _eintraegeFuer) ||
        schluessel != _eintraegeSchluessel) {
      final liste = <_Eintrag>[];
      DateTime? monat;
      // Die Reihenhöhe: so hoch, wie eine quadratische Kachel breit wäre –
      // Grösser und Kleiner wirken in beiden Formen gleich (wie am Rechner).
      final zielhoehe = (breite - 2 * (_spalten - 1)) / _spalten;
      for (var t = 0; t < tage.length; t++) {
        final (:tag, :von, :bis) = tage[t];
        if (widget.nachTagen) {
          // Ein Monatskopf über dem ersten Tag jedes Monats, wie in Immich –
          // die Tage darunter brauchen dann kein Jahr mehr.
          final dieserMonat = DateTime(tag.year, tag.month);
          if (dieserMonat != monat) {
            monat = dieserMonat;
            liste.add((art: _Art.monat, tag: t, von: von, reihe: null));
          }
          if (!_nurMonate) {
            liste.add((art: _Art.tag, tag: t, von: von, reihe: null));
          }
        }
        if (_reihen) {
          for (final r in bildreihen(
            seitenverhaeltnisse: [
              for (var i = von; i < bis; i++)
                seitenverhaeltnisVon(widget.zeilen[i]),
            ],
            breite: breite,
            zielhoehe: zielhoehe,
            abstand: 2,
          )) {
            liste.add((art: _Art.reihe, tag: t, von: von, reihe: r));
          }
        } else {
          for (var i = von; i < bis; i += _spalten) {
            liste.add((art: _Art.reihe, tag: t, von: i, reihe: null));
          }
        }
      }
      _eintraege = liste;
      _eintraegeFuer = tage;
      _eintraegeSchluessel = schluessel;
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
    widget.sitzung.addListener(_sitzungGeaendert);
  }

  @override
  void dispose() {
    widget.sitzung.removeListener(_sitzungGeaendert);
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
            zeile: z,
            format: l == null,
            herz: !_waehlt,
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

  // --- Liste (Issue #195) --------------------------------------------------

  static const _farbpunkte = {
    'red': Color(0xFFE53935),
    'yellow': Color(0xFFFDD835),
    'green': Color(0xFF43A047),
    'blue': Color(0xFF1E88E5),
    'purple': Color(0xFF8E24AA),
  };

  /// Die Köpfe und Zeilen der Liste. Nach Kamera kommen die Zeilen schon
  /// geordnet an (siehe Zeitleiste); hier wird nur abgeteilt.
  List<({String? kopf, int index})> _listenEintraege(
    Listenansicht l,
    String Function(Rasterzeile z) gruppe,
  ) {
    final aus = <({String? kopf, int index})>[];
    String? letzte;
    for (var i = 0; i < widget.zeilen.length; i++) {
      if (l.gliederung != ListenGruppierung.keine) {
        final g = gruppe(widget.zeilen[i]);
        if (g != letzte) {
          letzte = g;
          aus.add((kopf: g, index: i));
        }
      }
      aus.add((kopf: null, index: i));
    }
    return aus;
  }

  /// Eine Zeile der Liste: das Bild, der Name und darunter die übrigen
  /// gewählten Spalten – schmal wie im Browser auf dem Telefon.
  Widget _listenzeile(int i, Listenansicht l, double hoehe) {
    final z = widget.zeilen[i];
    final lok = widget.lokal[z.id];
    final a = l.angaben[z.id] ?? const Listenangaben();
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final leise = TextStyle(color: farben.onSurfaceVariant);
    final teile = <InlineSpan>[];
    void dazu(InlineSpan s) {
      if (teile.isNotEmpty) teile.add(const TextSpan(text: ' · '));
      teile.add(s);
    }

    for (final s in l.spalten.spalten) {
      final text = switch (s) {
        Listenspalte.dateiname => '',
        // Die Uhrzeit weicht dem Vermerk, wenn das Datum geschätzt ist.
        Listenspalte.datum =>
          a.geschaetzt
              ? '${DateFormat.yMd(sprache).format(z.fileCreatedAt.toLocal())} '
                    '(${t.listeGeschaetzt})'
              : DateFormat.yMd(
                  sprache,
                ).add_Hm().format(z.fileCreatedAt.toLocal()),
        Listenspalte.kamera =>
          kamerabezeichnungAus(z.cameraMake, a.kameramodell) ?? '',
        Listenspalte.objektiv => a.objektiv ?? '',
        Listenspalte.belichtung => belichtungstext(
          brennweite: a.brennweite,
          blende: a.blende,
          zeit: a.zeit,
          iso: a.iso,
        ),
        Listenspalte.bewertung => z.rating > 0 ? '★' * z.rating : '',
        Listenspalte.farbe => '',
        Listenspalte.masse =>
          z.widthPx == null || z.heightPx == null
              ? ''
              : '${z.widthPx} × ${z.heightPx}',
        Listenspalte.groesse => a.bytes > 0 ? groessentext(a.bytes) : '',
        Listenspalte.art => z.type == 'VIDEO' ? t.listeVideo : t.listeFoto,
        Listenspalte.ort => ortstext(a.stadt, a.land),
      };
      if (s == Listenspalte.farbe && z.colorLabel != null) {
        dazu(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _farbpunkte[z.colorLabel] ?? farben.outlineVariant,
              ),
            ),
          ),
        );
      } else if (text.isNotEmpty) {
        dazu(
          TextSpan(
            text: text,
            style: s == Listenspalte.bewertung
                ? TextStyle(color: farben.primary)
                : null,
          ),
        );
      }
    }
    final mitName = l.spalten.zeigt(Listenspalte.dateiname);
    return MetaData(
      metaData: _Kachelmarke(i),
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onTap: () => _waehlt && lok == null ? _schalte(z.id) : _oeffne(i),
        onLongPressStart: (_) => _ziehBeginn(i),
        onLongPressMoveUpdate: (d) => _ziehWeiter(d.globalPosition),
        onLongPressEnd: (_) => _ziehEnde(),
        child: ListenableBuilder(
          listenable: _auswahlStand,
          builder: (context, _) {
            final gewaehlt = _auswahl.contains(z.id);
            return ColoredBox(
              color: gewaehlt ? farben.primaryContainer : Colors.transparent,
              child: SizedBox(
                height: hoehe,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        height: hoehe - 12,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Miniatur(
                            paths: widget.sitzung.paths,
                            relativ: z.thumbnailRelativePath,
                            bild: lok?.bild,
                            zeile: z,
                            format: false,
                            herz: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (mitName)
                              Text(
                                z.originalFileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (teile.isNotEmpty)
                              Text.rich(
                                TextSpan(children: teile),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.merge(leise),
                              ),
                          ],
                        ),
                      ),
                      if (_waehlt && lok == null)
                        Icon(
                          gewaehlt ? Icons.check_circle : Icons.circle_outlined,
                          color: gewaehlt
                              ? farben.primary
                              : farben.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Eine bündige Reihe: jedes Foto in seinem Format, alle gleich hoch.
  /// [basis] ist der erste Index der Gruppe; die Plätze zählen ab ihm.
  Widget _buendig(int basis, Bildreihe r, bool letzte) => Padding(
    padding: EdgeInsets.only(bottom: letzte ? 0 : 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (k, p) in r.plaetze.indexed) ...[
          if (k > 0) const SizedBox(width: 2),
          SizedBox(width: p.breite, child: _kachel(basis + p.index)),
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
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, c) => _baue(context, c.maxWidth));

  Widget _baue(BuildContext context, double breite) {
    final zeilen = widget.zeilen;
    final slivers = <Widget>[
      if (widget.kopf != null) SliverToBoxAdapter(child: widget.kopf),
    ];
    final l = widget.liste;
    if (l != null) {
      final sprache = Localizations.localeOf(context).toLanguageTag();
      final t = AppTexte.of(context);
      final themen = Theme.of(context).textTheme;
      final skala = MediaQuery.textScalerOf(context);
      double zeile(TextStyle? stil) {
        final maler = TextPainter(
          text: TextSpan(text: 'Ág', style: stil),
          textDirection: TextDirection.ltr,
          textScaler: skala,
        )..layout();
        final h = maler.height;
        maler.dispose();
        return h;
      }

      final monat = DateFormat.yMMMM(sprache);
      final tag = DateFormat.yMMMMEEEEd(sprache);
      final eintraege = _listenEintraege(l, switch (l.gliederung) {
        ListenGruppierung.monat => (z) => monat.format(
          z.fileCreatedAt.toLocal(),
        ),
        // Die Liste kennt keine Monatsköpfe darüber; der Tag nennt das
        // ganze Datum (wie am Rechner).
        ListenGruppierung.tag => (z) => tag.format(z.fileCreatedAt.toLocal()),
        ListenGruppierung.kamera =>
          (z) =>
              kamerabezeichnungAus(
                z.cameraMake,
                l.angaben[z.id]?.kameramodell,
              ) ??
              t.listeOhneKamera,
        ListenGruppierung.keine => (_) => '',
      });
      final kopfStil = themen.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      );
      final kopfHoehe = 22 + zeile(kopfStil);
      final zeilenHoehe = math.max(
        56.0,
        16 + zeile(themen.bodyMedium) + zeile(themen.bodySmall),
      );
      slivers.add(
        SliverVariedExtentList.builder(
          itemCount: eintraege.length,
          itemExtentBuilder: (i, _) => i >= eintraege.length
              ? null
              : eintraege[i].kopf != null
              ? kopfHoehe
              : zeilenHoehe,
          itemBuilder: (context, i) {
            final e = eintraege[i];
            final k = e.kopf;
            return k != null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                    child: Text(
                      k,
                      style: kopfStil,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : _listenzeile(e.index, l, zeilenHoehe);
          },
        ),
      );
    } else if (!widget.nachTagen && !_reihen) {
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
      final eintraege = _eintraegeVon(tage, breite);
      final spalten = _spalten;
      bool letzteReihe(_Eintrag e) {
        final r = e.reihe;
        return r == null
            ? e.von + spalten >= tage[e.tag].bis
            : e.von + r.letzterIndex >= tage[e.tag].bis - 1;
      }

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
                (e.reihe?.hoehe ??
                        (masse.crossAxisExtent - 2 * (spalten - 1)) / spalten) +
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
              _Art.reihe =>
                e.reihe == null
                    ? _reihe(e.von, bis, letzteReihe(e))
                    : _buendig(e.von, e.reihe!, letzteReihe(e)),
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
typedef _Eintrag = ({_Art art, int tag, int von, Bildreihe? reihe});

/// Die Tage der nach Zeit geordneten [zeilen], in der Ortszeit des Geräts.
List<_Tag> _tage(List<Rasterzeile> zeilen, {bool jeMonat = false}) {
  // Nur nach Monaten (Issue #194): eine Gruppe je Monat statt je Tag.
  DateTime gruppe(Rasterzeile z) {
    final d = z.fileCreatedAt.toLocal();
    return jeMonat ? DateTime(d.year, d.month) : DateUtils.dateOnly(d);
  }

  final tage = <_Tag>[];
  var von = 0;
  while (von < zeilen.length) {
    final tag = gruppe(zeilen[von]);
    var bis = von + 1;
    while (bis < zeilen.length && gruppe(zeilen[bis]) == tag) {
      bis++;
    }
    tage.add((tag: tag, von: von, bis: bis));
    von = bis;
  }
  return tage;
}
