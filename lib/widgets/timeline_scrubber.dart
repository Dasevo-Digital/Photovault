import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../db/rasterzeile.dart';
import '../theme/app_theme.dart';
import 'timeline_grid_layout.dart';

/// Vertikaler "Schnell-Scroll"-Regler am rechten Rand der Timeline/des
/// Kalenders: Jahre als Beschriftung, Monate als Punkte, und an der
/// aktuellen Position eine Linie quer über die ganze Leiste mit dem Monat
/// darüber.
///
/// Die Leiste hat einen eigenen, halbdurchsichtigen Grund. Das ist keine
/// Zierde: Ohne ihn stünde weisse Schrift direkt auf den Fotos und wäre
/// über einem hellen Bild unlesbar – und die Fotos darunter wechseln beim
/// Scrollen ständig die Helligkeit. Mit dem Grund gilt derselbe Kontrast
/// wie auf den übrigen dunklen Arbeitsflächen (siehe [DunkleFlaeche]),
/// unabhängig davon, ob die App gerade hell oder dunkel läuft.
///
/// Statt einer Sprechblase neben dem Finger steht die Beschriftung IN der
/// Leiste: Beim Ziehen liegt der Finger genau dort, wo die Sprechblase
/// erschien, und verdeckte sie auf dem Trackpad-Bildschirm regelmässig.
/// Wie weit die Punktspalte vom rechten Rand entfernt sitzt.
const double _punktSpalte = 14;

/// Grund der Leiste. Dunkel und halbdurchsichtig, damit die Fotos daneben
/// durchscheinen, die Schrift darauf aber in jedem Helligkeitsmodus lesbar
/// bleibt – gegen diesen Grund gelten die Werte aus [DunkleFlaeche].
const Color _leistenGrund = Color(0xD9000000);

/// Platz, den eine Jahreszahl senkrecht braucht, samt Luft nach oben und
/// unten. Massgeblich dafür, welche Jahre überhaupt geschrieben werden.
const double _zeilenhoehe = 15;

/// Ab welchem Abstand zur aktuellen Position nichts mehr hervorgehoben wird.
///
/// Innerhalb dieses Bandes wachsen die Monatspunkte und die Jahreszahlen
/// werden heller – die Leiste öffnet sich dort, wo man hinsieht, ohne dass
/// sich irgendetwas verschiebt. Das ist der Unterschied zu einer Lupe, die
/// die Positionen dehnt: Hier bleibt jeder Punkt genau an der Stelle, zu
/// der ein Klick auch springt.
const double _naehe = 56;

/// Wie stark bei [abstand] Pixeln Abstand hervorgehoben wird: 1 direkt an
/// der Position, 0 ab [_naehe]. Quadratisch, weil der Übergang linear zu
/// abrupt einsetzt.
double _naehegrad(double abstand) {
  if (abstand >= _naehe) return 0;
  final t = 1 - abstand / _naehe;
  return t * t;
}

/// Welche Jahreszahlen tatsächlich geschrieben werden.
///
/// [obenNachUnten] sind die Y-Positionen aller Jahresanfänge in der
/// Reihenfolge der Leiste, [gesperrt] das Band, das die aktive Beschriftung
/// belegt. Zurück kommen die Indizes in [obenNachUnten], die Platz haben.
///
/// Ohne diese Auswahl schreiben sich Jahre mit wenigen Fotos gegenseitig
/// zu: Eine Bibliothek mit einem Schwerpunkt in den letzten Jahren drängt
/// 2006 bis 2014 auf wenige Pixel zusammen, und dort stand dann ein
/// schwarzer Klumpen statt sieben Zahlen. Die Punkte bleiben trotzdem alle
/// stehen – die Gliederung geht also nicht verloren, nur die Beschriftung
/// dünnt aus.
///
/// Als freie Funktion, weil genau hier die Rechnung sitzt, die man prüfen
/// will, ohne einen Bildschirm aufzubauen. Sie kennt nur Positionen und
/// keine Jahre – im Tagesbetrieb (siehe [TimelineScrubber.tageweise])
/// dünnt sie ebenso die Tagesbeschriftungen aus.
@visibleForTesting
List<int> sichtbareBeschriftungen(
  List<double> obenNachUnten, {
  required double von,
  required double bis,
  ({double oben, double unten})? gesperrt,
}) {
  final behalten = <int>[];
  // Vor dem ersten Eintrag: so weit oben, dass die erste Zahl immer passt.
  var letztesUnten = double.negativeInfinity;

  for (var i = 0; i < obenNachUnten.length; i++) {
    final oben = obenNachUnten[i] - _zeilenhoehe / 2;
    final unten = oben + _zeilenhoehe;

    // Aus der Leiste heraus gerutscht.
    if (unten < von || oben > bis) continue;
    // Die aktive Beschriftung hat Vorrang – sie sagt Monat UND Jahr und ist
    // damit ohnehin die genauere Angabe.
    if (gesperrt != null && oben < gesperrt.unten && unten > gesperrt.oben) {
      continue;
    }
    if (oben < letztesUnten) continue;

    behalten.add(i);
    letztesUnten = unten;
  }
  return behalten;
}

class TimelineScrubber extends StatefulWidget {
  /// Jahr*100+Monat-Schlüssel, absteigend sortiert (neueste zuerst) – exakt
  /// wie in [MonthGroupedAssetGrid] verwendet.
  final List<int> orderedKeys;
  final Map<int, List<Rasterzeile>> groups;
  final ScrollController controller;

  /// Breite, die der eigentlichen Foto-Grid-Spalte zur Verfügung steht
  /// (schon ohne die Breite des Scrubbers selbst) – für die Schätzung, wie
  /// viele Spalten das Grid hat und wie hoch eine Foto-Zeile ist.
  final double gridWidth;

  /// Ob die Gruppen Tage sind statt Monate.
  ///
  /// Ändert zweierlei: die Beschriftung (Tag statt Monat) und **was
  /// überhaupt beschriftet wird**. Über Monate sind es die Jahresanfänge –
  /// in einem einzelnen Monat gibt es davon genau einen, und die Leiste
  /// stünde ohne jede Orientierung da. Beschriftet werden deshalb alle
  /// Tage, so viele davon, wie nebeneinander Platz haben.
  final bool tageweise;

  /// Die eingestellte Kachelbreite (siehe [zeitleisteKachelstufen]) – der
  /// Sprung rechnet sonst mit einer anderen Zeilenhöhe als das Raster
  /// zeichnet und landet neben dem Monat, den er anpeilt.
  final double kachelbreite;

  /// Wie das Raster daneben anordnet. Aus demselben Grund wie
  /// [kachelbreite]: Bei bündigen Reihen ist eine Monatsgruppe anders hoch
  /// als bei Quadraten, und die Leiste zeigte sonst auf eine Stelle, an
  /// der der Monat gar nicht steht.
  final Zeitleistenform form;

  const TimelineScrubber({
    super.key,
    required this.orderedKeys,
    required this.groups,
    required this.controller,
    required this.gridWidth,
    this.tageweise = false,
    this.kachelbreite = timelineGridMaxCrossAxisExtent,
    this.form = zeitleisteFormVorgabe,
  });

  @override
  State<TimelineScrubber> createState() => _TimelineScrubberState();
}

class _TimelineScrubberState extends State<TimelineScrubber> {
  double? _dragFraction;
  double _scrollFraction = 0.0;

  /// Die Monatsgruppe, die zur aktuell angezeigten Position gehört – beim
  /// Ziehen die unter dem Finger, sonst die, in der die Ansicht gerade
  /// steht. Wird beim Aufbau ausgerechnet statt mitgeführt: Sonst laufen
  /// Marke und Beschriftung auseinander, sobald jemand mit dem Mausrad
  /// scrollt statt zu ziehen.
  int _aktiverIndex(double trackHeight) {
    final offsets = _cumulativeOffsets;
    final gesamt = offsets.last + timelineTrailingHeight;
    final ziel = (_dragFraction ?? _scrollFraction) * gesamt;
    var index = 0;
    for (var i = 0; i < widget.orderedKeys.length; i++) {
      if (offsets[i] <= ziel) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  /// Ob bei [index] ein neues Jahr beginnt – nur dort steht eine Jahreszahl.
  bool _istJahresbeginn(int index) {
    if (index == 0) return true;
    return widget.orderedKeys[index] ~/ 100 !=
        widget.orderedKeys[index - 1] ~/ 100;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant TimelineScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final maxExtent = widget.controller.position.maxScrollExtent;
    final fraction = maxExtent <= 0 ? 0.0 : (widget.controller.position.pixels / maxExtent).clamp(0.0, 1.0);
    if ((fraction - _scrollFraction).abs() > 0.001) {
      setState(() => _scrollFraction = fraction);
    }
  }

  double _monthHeight(int key) =>
      timelineMonthGroupHeight(widget.groups[key]!, widget.gridWidth,
          kachelbreite: widget.kachelbreite, form: widget.form);

  /// Kumulierte Pixel-Offsets für den Start jedes Monats (gleiche
  /// Reihenfolge wie [orderedKeys]), letzter Eintrag = geschätzte
  /// Gesamthöhe aller Monatsgruppen (ohne den abschließenden Leerraum).
  List<double> get _cumulativeOffsets {
    final offsets = <double>[0.0];
    var total = 0.0;
    for (final key in widget.orderedKeys) {
      total += _monthHeight(key);
      offsets.add(total);
    }
    return offsets;
  }

  void _handleDrag(double localY, double trackHeight) {
    if (widget.orderedKeys.isEmpty || !widget.controller.hasClients) return;
    final fraction = trackHeight <= 0 ? 0.0 : (localY / trackHeight).clamp(0.0, 1.0);
    final offsets = _cumulativeOffsets;
    final totalHeight = offsets.last + timelineTrailingHeight;
    final targetPixels = fraction * totalHeight;

    // Welche Monatsgruppe das ist, rechnet _aktiverIndex beim Aufbau aus –
    // hier wird nur gesprungen.
    final maxScroll = widget.controller.position.maxScrollExtent;
    widget.controller.jumpTo(targetPixels.clamp(0.0, maxScroll));
    setState(() => _dragFraction = fraction);
  }

  String _labelFor(int key) {
    final sprache = Localizations.localeOf(context).toString();
    final wann = widget.groups[key]!.first.fileCreatedAt;
    return widget.tageweise
        ? DateFormat.MMMd(sprache).format(wann)
        : DateFormat.yMMM(sprache).format(wann);
  }

  @override
  Widget build(BuildContext context) {
    // Bei sehr wenig Inhalt bringt ein Schnell-Scroll-Regler nichts außer
    // visueller Unruhe.
    if (widget.orderedKeys.length < 2) return const SizedBox.shrink();

    final offsets = _cumulativeOffsets;
    final totalHeight = offsets.last + timelineTrailingHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight;

        double topFor(int index) {
          final fraction = totalHeight <= 0 ? 0.0 : offsets[index] / totalHeight;
          return fraction * trackHeight;
        }

        final aktiv = _aktiverIndex(trackHeight);
        final aktivY =
            ((_dragFraction ?? _scrollFraction) * trackHeight).clamp(0.0, trackHeight);

        // Erst die Anwärter sammeln, dann auswählen, was hineinpasst:
        // über Monate die Jahresanfänge, über Tage jeder Tag.
        final jahresIndizes = [
          for (var i = 0; i < widget.orderedKeys.length; i++)
            if (widget.tageweise || _istJahresbeginn(i)) i,
        ];
        final beschriftet = sichtbareBeschriftungen(
          [for (final i in jahresIndizes) topFor(i)],
          von: 0,
          bis: trackHeight,
          // Das Band der aktiven Beschriftung: Sie sitzt über der Linie.
          gesperrt: (oben: aktivY - 18, unten: aktivY + 4),
        ).map((n) => jahresIndizes[n]).toSet();

        // Beim Ziehen soll die Marke am Finger kleben; beim Scrollen mit
        // dem Rad darf sie gleiten. Eine Animation während des Ziehens
        // fühlt sich an, als hinge die App hinterher.
        final dauer = _dragFraction != null
            ? Duration.zero
            : const Duration(milliseconds: 140);

        return Semantics(
          label: AppTexte.of(context).scrubberTooltip,
          value: _labelFor(widget.orderedKeys[aktiv]),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (d) => _handleDrag(d.localPosition.dy, trackHeight),
            onVerticalDragUpdate: (d) => _handleDrag(d.localPosition.dy, trackHeight),
            onVerticalDragEnd: (_) => setState(() => _dragFraction = null),
            onTapDown: (d) => _handleDrag(d.localPosition.dy, trackHeight),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: _leistenGrund),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Die Punktspalte: eine feine Linie, auf der die Monate
                  // sitzen.
                  const Positioned(
                    right: _punktSpalte,
                    top: 0,
                    bottom: 0,
                    child: SizedBox(
                      width: 1,
                      child: ColoredBox(color: DunkleFlaeche.linie),
                    ),
                  ),
                  for (var i = 0; i < widget.orderedKeys.length; i++) ...[
                    () {
                      final y = topFor(i);
                      final nah = _naehegrad((y - aktivY).abs());
                      final jahr = _istJahresbeginn(i);
                      // Nur die Grösse wächst, die Mitte bleibt: Ein Punkt,
                      // der zur Position hin wandert, zeigte auf einen
                      // anderen Monat als den, zu dem ein Klick springt.
                      final groesse = (jahr ? 5.0 : 3.0) + 3.0 * nah;
                      final farbe = Color.lerp(
                        jahr ? DunkleFlaeche.text : DunkleFlaeche.inaktiv,
                        DunkleFlaeche.text,
                        nah,
                      )!;
                      return Positioned(
                        right: _punktSpalte + 0.5 - groesse / 2,
                        top: (y - groesse / 2).clamp(0.0, trackHeight - groesse),
                        child: Container(
                          width: groesse,
                          height: groesse,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: farbe),
                        ),
                      );
                    }(),
                    if (beschriftet.contains(i))
                      () {
                        final y = topFor(i);
                        final nah = _naehegrad((y - aktivY).abs());
                        return Positioned(
                          right: _punktSpalte + 8,
                          top: (y - _zeilenhoehe / 2).clamp(0.0, trackHeight - _zeilenhoehe),
                          child: Text(
                            '${widget.orderedKeys[i] ~/ 100}',
                            style: TextStyle(
                              fontSize: 11 + nah,
                              height: 1.1,
                              // In der Nähe der Position heller – die
                              // Leiste öffnet sich dort, wo man hinsieht.
                              color: Color.lerp(
                                  DunkleFlaeche.hinweis, DunkleFlaeche.text, nah)!,
                              fontWeight: nah > 0.5 ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        );
                      }(),
                  ],
                  // Die aktuelle Position: eine Linie quer über die ganze
                  // Leiste, mit dem Monat direkt darüber.
                  AnimatedPositioned(
                    duration: dauer,
                    curve: Curves.easeOut,
                    left: 0,
                    right: 0,
                    top: aktivY.clamp(0.0, trackHeight - 1),
                    child: const SizedBox(
                      height: 1,
                      child: ColoredBox(color: DunkleFlaeche.text),
                    ),
                  ),
                  // Die aktive Beschriftung darf weiter nach rechts als die
                  // Jahreszahlen – "Nov. 2025" ist breiter als "2025", und
                  // sie liegt ohnehin obenauf.
                  AnimatedPositioned(
                    duration: dauer,
                    curve: Curves.easeOut,
                    right: 4,
                    left: 2,
                    top: (aktivY - 16).clamp(0.0, trackHeight - 16),
                    child: Text(
                      _labelFor(widget.orderedKeys[aktiv]),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        color: DunkleFlaeche.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
