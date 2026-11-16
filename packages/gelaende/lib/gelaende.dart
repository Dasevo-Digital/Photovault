/// Die Landschaft – Dreiecke aus einem Höhengitter, mit `drawVertices`.
///
/// **Ohne 3D-Bibliothek und ohne Shader.** `Canvas.drawVertices` ist
/// Flutter selbst; was fehlt, ist allein die Kamera, und die steht als
/// reine Rechnung in `gelaendesicht.dart`. Bei MapLibre trug ein Paket
/// auf pub.dev einen grünen Haken für Linux und scheiterte dort trotzdem
/// – hier kommt nichts dazu, was scheitern könnte.
///
/// Die Karte liegt als Textur darauf: Geländehöhen sind keine Karte, und
/// eine Wanderung vor einer namenlosen Landschaft beantwortet keine
/// Frage.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show DisabledMapCachingProvider;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'texte.dart';
import 'gesten.dart' show istWischen;

import 'gelaendeflug.dart';
import 'abstaende.dart';
import 'flugstil.dart';
import 'flugtafeln.dart';

import 'gelaendekacheln.dart';
import 'blocktexturen.dart';
import 'gelaendetextur.dart';
import 'gelaendesicht.dart';
import 'lichtstimmung.dart';
import 'flugvideo.dart';
import 'package:kern/services/gelaendeebenen.dart';
import 'gelaendeschilder.dart';

part 'gelaende_netz.dart';
part 'gelaende_maler.dart';
part 'flugleiste.dart';

/// Wie dicht der Dunst in der Ferne höchstens wird.
///
/// Nicht 1: Auch der fernste Grat soll noch als Grat erkennbar sein und
/// nicht als Nebelbank. Am gerenderten Bild entschieden – 0,72 wusch die
/// Gipfelkette am oberen Rand weiss.
const double _dunstStaerke = 0.55;

/// Wie schnell der Dunst mit der Tiefe zunimmt.
///
/// **Warum eine Exponentialkurve und keine Potenz.** Der erste Versuch
/// nahm `t³`. In der Übersicht sah das gut aus, im Flug war der Dunst
/// unsichtbar: Dort liegt der fernste Eckpunkt des ganzen Gitters
/// fünfzehn Kilometer weit weg, der obere Bildrand aber nur fünf – und
/// `0,33³` sind drei Prozent. Eine Atmosphäre schluckt exponentiell, und
/// genau die Kurve gibt auch nahen Unterschieden Gewicht.
const double _dunstDichte = 2.2;

/// Höchstens so viele Gitterpunkte je Seite.
///
/// **Gemessen, nicht geschätzt** (`gelaende_messung_test.dart`, auf
/// einem Mac):
///
/// ```
/// Kante | Dreiecke | Zeichnen
///    32 |    1.922 |  0,24 ms
///    64 |    7.938 |  0,46 ms
///    96 |   18.050 |  0,86 ms
///   128 |   32.258 |  1,83 ms
///   192 |   72.962 |  2,82 ms
///   256 |  130.050 |  4,71 ms
/// ```
///
/// Gemessen ist dabei **nur die Rechnung in Dart** – das Aufzeichnen der
/// Dreiecke. Was die Grafikkarte daraus macht, steht hier nicht; das
/// zeigt erst die laufende App. Deshalb nicht 256, obwohl 4,71 ms in ein
/// Bild von 16,7 ms passen: Auf einer langsameren Maschine ist das ein
/// Vielfaches, und die Grafikkarte kommt obendrauf. 96 lässt Luft und
/// war am Bildschirm nicht von 192 zu unterscheiden.
const int gelaendeGitterkante = 96;

/// Die Farbe des Geländes **ohne** Karte darauf – ein sandiges Braun,
/// wie es Reliefkarten benutzen.
///
/// Liegt eine Karte darüber, muss stattdessen Weiss genommen werden:
/// `modulate` multipliziert Karte und Eckpunktfarbe, und eine gefärbte
/// Grundlage dunkelte die Karte ein zweites Mal ab. Am Bildschirm sah
/// das aus wie eine Landschaft bei Nacht.
const Color gelaendeGrundfarbe = Color(0xFFB0A99A);

/// Ein Punkt der Spur, so wie ihn die Geländeansicht braucht.
///
/// Die Zeit ist seit dem Flug dabei: Ohne sie gibt es kein Tempo, und ein
/// Flug, der nicht sagt, wie schnell jemand unterwegs war, lässt die
/// wichtigste Zahl der Aufzeichnung liegen. Sie darf fehlen – eine
/// geplante Route hat keine.
typedef Gelaendespurpunkt = ({
  double breite,
  double laenge,
  double? hoehe,
  DateTime? zeit,
});

/// Die Landschaft mit Ziehen zum Drehen und Kippen – und dem Flug an der
/// Spur entlang.
class Gelaendeansicht extends StatefulWidget {
  final Gelaendenetz netz;
  final List<Raumpunkt> spur;

  /// Echte Höhe und Zeit zu jedem Punkt aus [spur]. Leer heisst: Flug
  /// ohne Zahlen – möglich, aber wortkarg.
  final List<Flugwert> spurwerte;

  final ui.Image? karte;

  /// Die Tageszeit. Muss zu dem Netz passen, das hereingereicht wird:
  /// Das Relief steckt in den Eckpunktfarben und entsteht beim Bauen,
  /// Himmel und Dunst entstehen beim Zeichnen. Wer nur eines von beiden
  /// umstellt, bekommt einen Morgenhimmel über einer Mittagslandschaft.
  final Lichtstimmung stimmung;

  /// Was am unteren Rand über der Flugleiste stehen soll – Bedienung,
  /// Namensnennung.
  ///
  /// **Warum das hier hereingereicht wird und nicht darüber gelegt.**
  /// Die Flugleiste sitzt am unteren Rand dieser Ansicht, und wer
  /// draussen einen zweiten Stapel mit `bottom:` darüberlegt, landet
  /// genau darauf – die Erklärung stand über dem Flugzeugsymbol und
  /// verdeckte den einzigen Knopf, der den Flug startet. Beides in einer
  /// Spalte zu stapeln kann nur die Stelle, die beide kennt.
  final List<Widget> fussnoten;

  /// Was auf der Landschaft liegen soll – Grund, Ebenen, Höhenlinien.
  ///
  /// Dieselbe Wahl wie bei [karte]; die Übersicht ist nur der Rückfall,
  /// solange ein Block seine eigene Textur noch nicht hat.
  final Gelaendekarte auflage;

  /// Das Höhengitter – für die Höhenlinien, die daraus gerechnet werden
  /// statt geladen zu werden, und für die Sichtprüfung der Schilder.
  final Hoehengitter? hoehen;

  /// Gipfel, Hütten, Quellen – als aufrechte Schilder über der
  /// Landschaft.
  final List<Gelaendeschild> schilder;

  /// Die Namensnennung, die **ins Video** gebrannt wird.
  ///
  /// Am Bildschirm steht sie als Fussnote unter der Ansicht; ein Video
  /// geht aus der App heraus und muss sie mitnehmen. Keine Zierleiste,
  /// sondern eine Lizenzauflage.
  final String? namensnennung;

  /// Wohin das Video geschrieben wird – `null` heisst: kein Knopf dafür.
  ///
  /// Als Rückruf und nicht als Pfad: Wo eine Datei hinsoll, fragt man
  /// den, der sie haben will, und ein Dateiwähler gehört nicht in ein
  /// Widget, das eine Landschaft zeichnet.
  final Future<Videoauftrag?> Function(Duration vorgabe)? beimVideoZiel;

  /// Wer das Video schreibt – die App weiss, womit es auf ihrer Plattform
  /// geht. `null` heisst: kein Knopf dafür.
  final Videoschreiber? videoschreiber;

  /// Wird nach einem fertigen Video gerufen. Ohne diesen Rückruf meldet
  /// die Ansicht selbst, wo die Datei liegt.
  final Future<void> Function(File ziel)? beiVideoFertig;

  /// Wie die Ansicht etwas meldet – sonst als Hinweis am unteren Rand.
  final Gelaendemeldung? melde;

  /// Die Fotos der Aktivität, mit ihrer Stelle auf der Spur.
  ///
  /// **Das ist der Punkt, an dem sich eine Fotoverwaltung von einem
  /// Sportprogramm unterscheidet.** Strava und Relive fliegen dieselbe
  /// Spur ab; nur hier liegen die Bilder schon daneben und mussten nur
  /// noch hergereicht werden.
  final List<Flugfoto> fotos;

  /// Nur für Tests: Wer hier etwas hereinreicht, holt keine Kacheln aus
  /// dem Netz – und geht dann auch am gemeinsamen Kachelspeicher vorbei,
  /// damit ein Test nicht davon abhängt, was auf dieser Platte liegt.
  final http.Client? netzKlient;

  /// Wie der Flug die Spur zeigt – siehe `flugstil.dart`.
  ///
  /// **Muss zu [netz] und [spur] passen**, wie [stimmung]: Der Stil
  /// „Nah dran" fliegt über ein flacher überhöhtes Netz und eine Spur,
  /// die auf dem Gelände liegt. Beides baut der Bildschirm, der die
  /// Kacheln hat; hier wird nur geflogen.
  final Flugstil stil;

  /// Der Name der Tour – für die Titeltafel im Stil „Nah dran".
  final String? titel;

  /// Die Schrift von Schildern und Tafeln – nur für Bildwerkzeuge (siehe
  /// [Gelaendemaler.schriftart]). In der App bleibt sie `null`.
  final String? schriftart;

  const Gelaendeansicht({
    super.key,
    required this.netz,
    this.spur = const [],
    this.spurwerte = const [],
    this.karte,
    this.stimmung = stimmungMittag,
    this.fussnoten = const [],
    this.auflage = const Gelaendekarte(),
    this.hoehen,
    this.schilder = const [],
    this.fotos = const [],
    this.namensnennung,
    this.beimVideoZiel,
    this.videoschreiber,
    this.beiVideoFertig,
    this.melde,
    this.netzKlient,
    this.stil = Flugstil.ueberblick,
    this.titel,
    this.schriftart,
  });

  @override
  State<Gelaendeansicht> createState() => _GelaendeansichtState();
}

class _GelaendeansichtState extends State<Gelaendeansicht>
    with SingleTickerProviderStateMixin {
  /// Von Südsüdwest, leicht schräg – die Ansicht, in der man ein Tal als
  /// Tal erkennt. Genau von Süden wirkte die Landschaft flach, weil alle
  /// Kanten parallel zum Bildrand lägen.
  double _drehung = 0.35;

  /// Rund 55°. Senkrecht von oben ist eine Karte, waagerecht ist ein
  /// Strich.
  double _neigung = 0.95;

  double _zoom = 1;

  /// Wie schnell der Flug über Grund geht. Am Bildschirm eingestellt: Bei
  /// 150 m/s wirkt eine Tageswanderung wie eine Diaschau, bei 600 sieht
  /// man das Gelände nicht mehr.
  static const double _flugtempo = 300;

  /// Das Tempo dieses Fluges – im Stil „Nah dran" nach der Länge der
  /// Tour (siehe [nahDranTempo]), im Überblick fest.
  double get _tempo => _nah ? nahDranTempo(_flug.laengeMeter) : _flugtempo;

  bool get _nah => widget.stil == Flugstil.nahDran;

  /// Die Neigung des Verfolgerblicks – eigene Zahl, weil der Überblick
  /// mit 0,95 von oben blickt und der Verfolger mit 0,55 von hinten.
  /// Ziehen ändert im Flug „Nah dran" nur diese.
  double _nahNeigung = nahDranNeigung;

  /// Die Leisten am unteren Rand (Fussnote und Flugleiste) – zum
  /// Nachmessen ihrer Höhe.
  final _untenSchluessel = GlobalKey();

  /// Wie hoch die Leisten unten die Landschaft verdecken, in Punkten.
  /// Nur der Verfolger braucht das (siehe [_flugkamera]).
  double _unten = 0;

  void _untenMessen(Duration _) {
    if (!mounted) return;
    final kasten = _untenSchluessel.currentContext?.findRenderObject();
    if (kasten is! RenderBox || !kasten.hasSize) return;
    final hoehe = kasten.size.height;
    if ((hoehe - _unten).abs() > 0.5) setState(() => _unten = hoehe);
  }

  late final AnimationController _uhr;
  late Gelaendeflug _flug;

  /// Ob geflogen wird – auch angehalten bleibt die Flugkamera stehen, wo
  /// sie ist. Ohne diesen Merker spränge ein Pausieren zurück in die
  /// Übersicht.
  bool _imFlug = false;

  /// Was das Ziehen beim Flug verändert: nicht die Drehung selbst, die
  /// gehört dem Weg, sondern ein Versatz darauf. So kann man sich im
  /// Flug umsehen, ohne dass die Kamera danach den Weg verliert.
  ///
  /// **Die Neigung bleibt dagegen dieselbe wie in der Übersicht.** Die
  /// erste Fassung stellte sie beim Start um, in der Annahme, ein Flug
  /// wolle flacher sehen. An echtem Gelände durchprobiert (Grindelwald,
  /// 547 bis 4035 m) stimmt das nicht: Flacher als etwa 0,8 fliegt man
  /// in einem Alpental gegen eine Wand – bei dreifacher Überhöhung stehen
  /// die Hänge dreimal so steil wie in Wirklichkeit. Zwischen 0,85 und
  /// 1,05 liest sich das Bild gut, und 0,95 liegt mittendrin. Also keine
  /// eigene Zahl, keine Umschaltung und kein Merken – der Blickwinkel
  /// gehört durchweg dem Betrachter.
  double _flugversatz = 0;

  /// Der Lader für die scharfen Blocktexturen.
  ///
  /// **Gehört der Ansicht und nicht dem Bildschirm**, weil er die Kamera
  /// braucht: Welcher Block wie fein sein muss, hängt daran, wie weit er
  /// weg ist, und das weiss nur, wer die Kamera führt.
  Blocktexturlader? _lader;

  @override
  void initState() {
    super.initState();
    _flug = _baueFlug();
    _laderAufsetzen();
    _uhr = AnimationController(vsync: this, duration: _dauer())
      ..addListener(() => setState(() {}))
      ..addStatusListener((stand) {
        // Am Ende stehen bleiben und nicht in die Übersicht springen:
        // Der letzte Blick ist das Ziel, und danach will man es ansehen.
        if (stand == AnimationStatus.completed) setState(() {});
      });
  }

  @override
  void didUpdateWidget(Gelaendeansicht alt) {
    super.didUpdateWidget(alt);
    if (alt.spur != widget.spur ||
        alt.spurwerte != widget.spurwerte ||
        alt.stil != widget.stil) {
      _flug = _baueFlug();
      _uhr.duration = _dauer();
    }
    // Anderes Gelände oder andere Karte heisst andere Texturen. Der alte
    // Vorrat muss dabei **freigegeben** werden, sonst bliebe der Speicher
    // der Grafikkarte bei jedem Stilwechsel um achtzig Megabyte voller.
    if (alt.netz != widget.netz || alt.auflage != widget.auflage) {
      _lader?.schliessen();
      _laderAufsetzen();
    }
  }

  /// Der Flug über die Spur – im Stil „Nah dran" mit einer Blickglättung,
  /// die zu seinem langsameren Tempo passt (siehe
  /// [nahDranBlickglaettung]).
  Gelaendeflug _baueFlug() {
    final roh = Gelaendeflug(widget.spur, werte: widget.spurwerte);
    if (!_nah) return roh;
    return Gelaendeflug(
      widget.spur,
      werte: widget.spurwerte,
      blickglaettung: nahDranBlickglaettung(nahDranTempo(roh.laengeMeter)),
    );
  }

  void _laderAufsetzen() {
    _lader = Blocktexturlader(
      karte: widget.auflage,
      hoehen: widget.hoehen,
      grundstufe: widget.netz.grundstufe,
      netz: widget.netzKlient,
      speicher: widget.netzKlient == null
          ? null
          : const DisabledMapCachingProvider(),
      beiAenderung: () {
        if (mounted) setState(() {});
      },
    );
  }

  /// Die Geländehöhe an einer Stelle des Netzes, in Netzmetern.
  ///
  /// **Aus dem Höhengitter und nicht aus dem Netz.** Das Netz besteht aus
  /// Dreiecken und liesse sich nur durch Suchen abfragen; das Gitter kann
  /// es direkt und bilinear. Gebraucht wird es für die Sichtprüfung der
  /// Schilder – zwanzig Abfragen je Schild und Bild.
  double? _hoeheBei(double x, double y) {
    final g = widget.hoehen;
    final netz = widget.netz;
    if (g == null || netz.breiteMeter <= 0 || netz.hoeheMeter <= 0) return null;
    final laenge =
        netz.west + (x / netz.breiteMeter + 0.5) * (netz.ost - netz.west);
    final breite =
        netz.nord - (0.5 - y / netz.hoeheMeter) * (netz.nord - netz.sued);
    final h = g.anOrt(breite, laenge);
    if (h == null) return null;
    return (h - netz.mittlereHoehe) * netz.ueberhoehung;
  }

  /// Was die Übersichtskarte an dieser Stelle hergibt, in Metern je
  /// Bildpunkt – die Schwelle, ab der ein eigener Abruf sich lohnt.
  double? get _uebersichtAufloesung {
    final k = widget.karte;
    if (k == null || k.width == 0) return null;
    final mitte = (widget.netz.nord + widget.netz.sued) / 2;
    return (widget.netz.ost - widget.netz.west) *
        meterJeGradLaenge(mitte) /
        k.width;
  }

  /// Wie lange der Einflug dauert, als Anteil an der ganzen Vorführung.
  ///
  /// **Warum es ihn gibt.** Bisher stand die Kamera im ersten Bild
  /// mitten in der Landschaft, und man wusste nicht, wo. Der Einflug
  /// beantwortet die Frage, die vor allen anderen kommt: *wo sind wir
  /// überhaupt.* Er beginnt in der Übersicht, die man gerade noch
  /// gesehen hat, und geht von dort auf den Startpunkt zu – dieselbe
  /// Bewegung, die Strava und Relive an den Anfang stellen.
  ///
  /// Sieben Prozent im Überblick, acht im Stil „Nah dran" – und der
  /// Abspann am Ende (aufziehen und die Zahlen zeigen) zehn bzw.
  /// fünfzehn. Die Zahlen stehen bei [flugAnteile].
  double get _einflugAnteil => flugAnteile(widget.stil).einflug;

  double get _abspannAnteil => flugAnteile(widget.stil).abspann;

  Duration _dauer() {
    final flug = _flug.moeglich
        ? _flug.dauerBei(_tempo)
        : const Duration(seconds: 10);
    // Einflug und Abspann kommen oben drauf, statt vom Flug abzugehen:
    // Sonst wäre eine kurze Wanderung nach dem Einflug schon vorbei.
    return flug * (1 / (1 - _einflugAnteil - _abspannAnteil));
  }

  /// Wo in der Vorführung wir sind.
  ///
  /// Drei Abschnitte auf einer Uhr: Einflug, Flug, Abspann. Sie liegen
  /// auf **einer** Uhr und nicht auf dreien, damit der Regler unter dem
  /// Bild die ganze Vorführung zeigt und nicht nur ihren Mittelteil.
  ({double einflug, double flug, double abspann}) get _abschnitt =>
      _abschnittBei(_uhr.value);

  @override
  void dispose() {
    _lader?.schliessen();
    _uhr.dispose();
    for (final b in _tafelbilder.values) {
      b.dispose();
    }
    _tafelbilder.clear();
    super.dispose();
  }

  void _flugSchalten() {
    setState(() {
      if (!_imFlug) {
        _imFlug = true;
        _flugversatz = 0;
        _uhr.forward(from: 0);
      } else if (_uhr.isAnimating) {
        _uhr.stop();
      } else {
        // Am Ende noch einmal von vorn, sonst weiterlaufen.
        _uhr.forward(from: _uhr.value >= 1 ? 0 : _uhr.value);
      }
    });
  }

  void _flugBeenden() {
    setState(() {
      _uhr.stop();
      _imFlug = false;
    });
  }

  void _spulen(double wert) {
    setState(() {
      _uhr.stop();
      _uhr.value = wert.clamp(0.0, 1.0);
    });
  }

  /// Ob gerade ein Video geschrieben wird.
  bool _videoLaeuft = false;

  /// Vom Knopf gesetzt, vom Lauf vor jedem Bild gelesen.
  bool _videoAbbruch = false;

  /// Wie weit die Ausgabe ist, 0 bis 1.
  double _videoFortschritt = 0;

  /// Der Auftrag, der gerade läuft – für die Kachelvorschau, die seine
  /// Bildgrösse braucht.
  Videoauftrag? _videoauftrag;

  /// Wann die Ausgabe begann – für die Restzeit.
  DateTime? _videoBegann;

  /// Die breitesten Fassungen der Messwerte dieses Fluges – einmal vor
  /// dem Lauf gerechnet, siehe [_breitesteMesswerte].
  ({String hoehe, String tempo, String steigung})? _videoBreiteste;

  /// Wie lange die Ausgabe noch braucht – aus dem bisherigen Tempo.
  ///
  /// `null`, solange sich nichts rechnen lässt. **Eine geratene Restzeit
  /// wäre schlimmer als keine** – dieselbe Regel wie bei der
  /// KI-Restaurierung.
  Duration? get _videoRest {
    final begann = _videoBegann;
    if (begann == null || _videoFortschritt <= 0.02) return null;
    final her = DateTime.now().difference(begann).inMilliseconds;
    if (her <= 0) return null;
    final ganz = her / _videoFortschritt;
    return Duration(milliseconds: (ganz - her).round());
  }

  /// Schreibt den Flug als Video – oder bricht einen laufenden ab.
  void _melde(String text, {bool warnung = false}) {
    final eigen = widget.melde;
    if (eigen != null) return eigen(text, warnung: warnung);
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _videoAusgeben() async {
    if (_videoLaeuft) {
      setState(() => _videoAbbruch = true);
      return;
    }
    final t = gelaendeTexte(context);
    // **Nicht mehr „gibt es ffmpeg".** Unter macOS schreibt AVFoundation
    // das Video, unter Linux und Windows das mitgelieferte ffmpeg – die
    // Frage lautet also, ob hier irgendein Weg offen ist.
    final schreiber = widget.videoschreiber;
    if (schreiber == null || !await schreiber.moeglich()) {
      if (!mounted) return;
      _melde(t.flugVideoKeinWerkzeug, warnung: true);
      return;
    }
    if (!mounted) return;
    final auftrag = await widget.beimVideoZiel?.call(_uhr.duration ?? _dauer());
    if (auftrag == null || !mounted) return;
    final ziel = auftrag.ziel;

    // **Die Fotos vorher aufdecken.** Am Bildschirm lädt Flutter sie
    // selbst, während der Flug läuft; ein Video entsteht ohne
    // Widgetbaum, und ein Bild, das erst zur Hälfte des Fluges ankommt,
    // fehlte in den Bildern davor.
    final fotos = <double, ui.Image>{};
    for (final f in widget.fotos) {
      final bild = await _bildAufdecken(f.bild);
      if (bild != null) fotos[f.meter] = bild;
    }
    if (!mounted) {
      for (final b in fotos.values) {
        b.dispose();
      }
      return;
    }

    setState(() {
      _videoLaeuft = true;
      _videoAbbruch = false;
      _videoFortschritt = 0;
      _videoauftrag = auftrag;
      _videoBegann = DateTime.now();
      _videoBreiteste = _breitesteMesswerte();
    });
    try {
      final ergebnis = await schreiber.schreibe(
        ziel: ziel,
        breite: auftrag.breite,
        hoehe: auftrag.hoehe,
        dauer: auftrag.dauer,
        abbruch: () => _videoAbbruch || !mounted,
        // Der Fortschritt steht als Balken über der Flugleiste und nicht
        // als Meldung: Eine Meldung, die neunhundertmal aktualisiert
        // wird, ist keine Meldung mehr.
        fortschritt: (a) {
          if (mounted) setState(() => _videoFortschritt = a);
        },
        // **Vor jedem Bild die Kacheln holen, die darin stehen.** Ohne
        // das nähme die Ausgabe die Texturen, die gerade zufällig im
        // Vorrat lagen – am Bildschirm holt der Lader nach, während man
        // fliegt, ein Video hat dafür keine Gelegenheit mehr.
        vorBild: (zeit) => _videoKachelnHolen(zeit),
        maleBild: (leinwand, flaeche, zeit) =>
            _videobild(leinwand, flaeche, zeit, fotos),
      );
      if (!mounted) return;
      switch (ergebnis.ausgang) {
        case Videoausgang.fertig:
          final fertig = widget.beiVideoFertig;
          if (fertig != null) {
            await fertig(ziel);
          } else {
            _melde(t.flugVideoFertig(ziel.uri.pathSegments.last));
          }
        case Videoausgang.abgebrochen:
          _melde(t.flugVideoAbgebrochen);
        case Videoausgang.keinWerkzeug:
          _melde(t.flugVideoKeinWerkzeug, warnung: true);
        case Videoausgang.fehler:
          _melde(t.flugVideoFehler(ergebnis.meldung ?? '?'), warnung: true);
      }
    } finally {
      for (final b in fotos.values) {
        b.dispose();
      }
      if (mounted) {
        setState(() {
          _videoLaeuft = false;
          _videoAbbruch = false;
          _videoauftrag = null;
          _videoBegann = null;
          _videoBreiteste = null;
        });
      }
    }
  }

  /// Holt aus einem Bildanbieter ein fertiges `ui.Image`.
  Future<ui.Image?> _bildAufdecken(ImageProvider anbieter) {
    final fertig = Completer<ui.Image?>();
    final strom = anbieter.resolve(ImageConfiguration.empty);
    late ImageStreamListener horcher;
    horcher = ImageStreamListener(
      (info, _) {
        if (!fertig.isCompleted) fertig.complete(info.image.clone());
        info.dispose();
        strom.removeListener(horcher);
      },
      onError: (_, _) {
        // Ein Bild, das nicht kommt, nimmt das Video nicht mit.
        if (!fertig.isCompleted) fertig.complete(null);
        strom.removeListener(horcher);
      },
    );
    strom.addListener(horcher);
    return fertig.future;
  }

  /// Sagt dem Lader, was in diesem Videobild steht – und wartet kurz.
  Future<void> _videoKachelnHolen(double zeit) async {
    final lader = _lader;
    if (lader == null) return;
    final breite = (_videoauftrag?.breite ?? 1920).toDouble();
    final hoehe = (_videoauftrag?.hoehe ?? 1080).toDouble();
    lader.brauche(
      bloeckeImBild(
        widget.netz,
        _videokamera(zeit, breite, hoehe),
        Size(breite, hoehe),
        uebersichtAufloesung: _uebersichtAufloesung,
      ),
    );
    // **Nur auf das warten, was man sieht.** Vorher stand hier
    // `ruhe(700 ms)` – warten, bis der Lader gar nichts mehr zu tun hat.
    // Das tritt im Flug nie ein: Ein Bild will über fünfhundert Blöcke,
    // in den Vorrat passen hundertfünfzig, und mit jedem Bild verschiebt
    // sich die Zuteilung. Gemessen kostete das 665 ms je Bild – bei einem
    // Server, der sofort antwortet. Ein Überflug von einer Minute wäre
    // zwanzig Minuten Warten gewesen, und genau so sah es aus: als
    // täte die Ausgabe nichts.
    await lader.ruheNah(hoechstens: const Duration(milliseconds: 300));
  }

  /// Die Kamera für ein Videobild – dieselbe Rechnung wie am Bildschirm.
  Gelaendekamera _videokamera(double zeit, double breite, double hoehe) =>
      _flugkamera(zeit, breite, hoehe);

  /// Die Kamera zur Stelle [zeit] der Vorführung (0 bis 1) auf einer
  /// Fläche von [breite] mal [hoehe].
  ///
  /// **Eine Rechnung für Bildschirm und Video.** Bis 3.67 stand sie
  /// zweimal da, einmal im Aufbau der Ansicht und einmal für das Video,
  /// und die beiden unterschieden sich nur in Zoom und Versatz. Mit einem
  /// zweiten Flugstil wären es vier Fassungen geworden. [zoom] und
  /// [versatz] kommen von der Hand am Bildschirm; im Video sind sie
  /// neutral.
  ///
  /// [unten] ist der Teil der Fläche, den am Bildschirm die Leisten
  /// verdecken (Flugleiste und Fussnote). Der Verfolger rechnet seinen
  /// Leuchtpunkt über diesem Rand ein; mit der ganzen Höhe stand er
  /// mitten zwischen den Fussnoten, halb über der Flugleiste. Im Video
  /// verdeckt nichts.
  Gelaendekamera _flugkamera(
    double zeit,
    double breite,
    double hoehe, {
    double zoom = 1,
    double versatz = 0,
    double unten = 0,
  }) {
    // Der Abstand richtet sich nach der Ausdehnung: Eine
    // Zwölf-Kilometer-Wanderung und ein Mittelgebirge sollen beide
    // ins Bild passen, ohne dass jemand zoomt.
    final ausdehnung = math.max(
      widget.netz.breiteMeter,
      widget.netz.hoeheMeter,
    );
    final abschnitt = _abschnittBei(zeit);
    final stand = _flug.bei(abschnitt.flug);
    final brennweite = math.min(breite, hoehe) * 1.1;
    // Am Bildschirm eingestellt: Mit dem Faktor 1,6 lag die Landschaft
    // als Briefmarke in der Mitte eines schwarzen Fensters.
    final uebersicht = Gelaendekamera(
      drehung: _drehung,
      neigung: _neigung,
      entfernung: ausdehnung * 0.95 / zoom,
      brennweite: brennweite,
      mitte: Offset(breite / 2, hoehe * 0.5),
    );
    final flugkamera = _nah
        ? verfolgerkamera(
            stand: stand,
            breite: breite,
            hoehe: math.max(hoehe * 0.5, hoehe - unten),
            tempo: _tempo,
            neigung: _nahNeigung,
            zoom: zoom,
            versatz: versatz,
          )
        : Gelaendekamera(
            drehung: stand.drehung + versatz,
            neigung: _neigung,
            entfernung:
                Gelaendeflug.flugabstand(
                  ausdehnung: ausdehnung,
                  kante: gelaendeGitterkante,
                  brennweite: brennweite,
                ) /
                zoom,
            brennweite: brennweite,
            // Beim Flug höher angesetzt: Der Weg soll im unteren
            // Drittel liegen, damit oben die Landschaft steht, in die er
            // hineinführt.
            mitte: Offset(breite / 2, hoehe * 0.62),
            blickpunkt: stand.blickpunkt,
          );
    // Am Ende zieht der Überblick auf die ganze Landschaft auf; der
    // Verfolger hebt über dem Ziel zum Rundblick ab.
    final schluss = _nah ? panoramakamera(flugkamera) : uebersicht;

    // **Einflug und Abspann sind dieselbe Bewegung, rückwärts.** Am
    // Anfang von der Übersicht auf den Startpunkt zu, am Ende von der
    // letzten Stelle wieder auf. Eine Kurve dazwischen, damit es nicht
    // ruckt: `easeInOutCubic` beschleunigt und bremst, ein linearer
    // Übergang setzte an beiden Enden hart an.
    //
    // Und immer über dem Boden: Ein Video, das durch den Berg fliegt,
    // wäre derselbe Fehler in haltbar.
    if (abschnitt.einflug < 1) {
      return _ueberDemBoden(
        _zwischenKamera(
          uebersicht,
          flugkamera,
          Curves.easeInOutCubic.transform(abschnitt.einflug),
        ),
      );
    }
    if (abschnitt.abspann > 0) {
      return _ueberDemBoden(
        _zwischenKamera(
          flugkamera,
          schluss,
          Curves.easeInOutCubic.transform(abschnitt.abspann),
        ),
      );
    }
    return _ueberDemBoden(flugkamera);
  }

  /// Malt ein einzelnes Videobild – dieselbe Rechnung wie am Bildschirm,
  /// nur auf eine feste Leinwand statt in ein Fenster.
  void _videobild(
    ui.Canvas leinwand,
    ui.Size flaeche,
    double zeit,
    Map<double, ui.Image> fotos,
  ) {
    final abschnitt = _abschnittBei(zeit);
    final stand = _flug.bei(abschnitt.flug);
    final kamera = _videokamera(zeit, flaeche.width, flaeche.height);

    final foto = _fotoBei(stand.gefahrenMeter);
    final bild = foto == null ? null : fotos[foto.meter];

    if (_nah) {
      Gelaendemaler(
        netz: widget.netz,
        kamera: kamera,
        spur: widget.spur,
        karte: widget.karte,
        blocktexturen: _lader?.bilder,
        spurfarbe: const Color(0xFFFF6A00),
        stimmung: widget.stimmung,
        gefahrenBis: stand.gefahrenMeter,
        streckeJePunkt: _flug.streckeJePunkt,
        schilder: widget.schilder,
        hoeheBei: _hoeheBei,
        namensnennung: widget.namensnennung,
        schriftart: widget.schriftart,
        leuchtspur: true,
        kopf: _flug.punktBei(stand.gefahrenMeter),
        // Keine Messwerte und kein Abspann mit Zahlentafel: Das Video
        // dieses Stils erzählt mit Titel, Fotos und Ziel. Die Zahlen der
        // Tour stehen auf den beiden Tafeln.
        tafeln: _tafeln(
          zeit,
          gesamtSekunden:
              (_videoauftrag?.dauer ?? _dauer()).inMilliseconds / 1000,
          bild: (f) => fotos[f.meter],
        ),
      ).paint(leinwand, flaeche);
      return;
    }

    Gelaendemaler(
      netz: widget.netz,
      kamera: kamera,
      spur: widget.spur,
      karte: widget.karte,
      blocktexturen: _lader?.bilder,
      spurfarbe: const Color(0xFFFF5722),
      stimmung: widget.stimmung,
      gefahrenBis: stand.gefahrenMeter,
      streckeJePunkt: _flug.streckeJePunkt,
      schilder: widget.schilder,
      hoeheBei: _hoeheBei,
      flugbild: bild == null
          ? null
          : (
              bild: bild,
              deckkraft: _fotoDeckkraft(stand.gefahrenMeter),
              unterschrift: foto!.unterschrift,
            ),
      namensnennung: widget.namensnennung,
      schriftart: widget.schriftart,
      // Sie kommen mit dem Einflug und gehen mit dem Abspann: Was der
      // Flug gerade misst, hat neben den Zahlen der ganzen Tour nichts
      // mehr zu suchen.
      messwerte: (
        werte: _videomesswerte(stand),
        deckkraft:
            Curves.easeOut.transform(abschnitt.einflug) *
            (1 - Curves.easeIn.transform(abschnitt.abspann)),
      ),
      abspann: abschnitt.abspann <= 0
          ? null
          : (
              zeilen: _abspannzeilen(),
              deckkraft: Curves.easeIn.transform(abschnitt.abspann),
            ),
    ).paint(leinwand, flaeche);
  }

  /// Dieselbe Abschnittsrechnung wie [_abschnitt], nur für eine Zeit, die
  /// nicht von der Uhr kommt – beim Video läuft keine.
  ({double einflug, double flug, double abspann}) _abschnittBei(double t) {
    final a = _einflugAnteil;
    final b = 1 - _abspannAnteil;
    return (
      einflug: t < a ? (t / a).clamp(0.0, 1.0) : 1.0,
      flug: ((t - a) / (b - a)).clamp(0.0, 1.0),
      abspann: t <= b ? 0.0 : ((t - b) / (1 - b)).clamp(0.0, 1.0),
    );
  }

  /// Bergauf und bergab im Video – feste Farben, anders als am
  /// Bildschirm.
  ///
  /// Dort nimmt die Zeile `error` und `primary` aus dem Thema, und die
  /// sind für dessen Grund gemacht. Im Video liegen die Zahlen auf einer
  /// dunklen Tafel über wechselnder Landschaft; das dunkle Blau des
  /// hellen Themas wäre darauf nicht zu lesen. Die Farbe bleibt Beiwerk
  /// – das Vorzeichen sagt dasselbe (18. Prüfrunde).
  static const _videoBergauf = Color(0xFFFFAB91);
  static const _videoBergab = Color(0xFF80DEEA);

  /// Höhe, Tempo und Steigung für ein Videobild – in derselben
  /// Reihenfolge wie in der Zeile unter der Ansicht.
  List<Flugmesswert> _videomesswerte(Flugstand stand) {
    final breiteste = _videoBreiteste;
    if (breiteste == null) return const [];
    final t = gelaendeTexte(context);
    final eine = NumberFormat.decimalPatternDigits(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 1,
    );
    return [
      if (stand.hoeheMeter case final h?)
        (
          name: t.flugHoehe,
          wert: t.flugMeterProfil(h.round()),
          breitester: breiteste.hoehe,
          farbe: null,
        ),
      if (stand.tempoMeterJeSekunde case final v?)
        (
          name: t.flugTempo,
          wert: t.flugKmH(eine.format(v * 3.6)),
          breitester: breiteste.tempo,
          farbe: null,
        ),
      if (stand.steigungProzent case final st?)
        (
          name: t.flugSteigung,
          wert: t.flugProzent(eine.format(st)),
          breitester: breiteste.steigung,
          farbe: st.abs() < 1 ? null : (st > 0 ? _videoBergauf : _videoBergab),
        ),
    ];
  }

  /// Die breiteste Fassung, die jeder Messwert im Lauf dieses Fluges
  /// annimmt.
  ///
  /// **Der Vergleich nach Zeichenzahl ist hier genau und nicht
  /// ungefähr**: Innerhalb einer Spalte steht immer dasselbe Muster –
  /// dieselbe Einheit, eine Nachkommastelle – und die Ziffern sind im
  /// Bild gleich breit. Länger heisst dann breiter. Über Spalten hinweg
  /// gälte das nicht, und über sie hinweg wird auch nicht verglichen.
  ///
  /// Zweihundert Stellen und nicht jedes Bild: Der Flug ist stetig,
  /// zweihundert Stichproben treffen den Höchstwert auf die
  /// Nachkommastelle, und gerechnet wird das **einmal** vor dem Lauf
  /// statt neunhundertmal darin.
  ({String hoehe, String tempo, String steigung}) _breitesteMesswerte() {
    final t = gelaendeTexte(context);
    final eine = NumberFormat.decimalPatternDigits(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 1,
    );
    String laenger(String bisher, String neu) =>
        neu.length > bisher.length ? neu : bisher;
    var hoehe = '';
    var tempo = '';
    var steigung = '';
    for (var i = 0; i <= 200; i++) {
      final stand = _flug.bei(i / 200);
      if (stand.hoeheMeter case final h?) {
        hoehe = laenger(hoehe, t.flugMeterProfil(h.round()));
      }
      if (stand.tempoMeterJeSekunde case final v?) {
        tempo = laenger(tempo, t.flugKmH(eine.format(v * 3.6)));
      }
      if (stand.steigungProzent case final st?) {
        steigung = laenger(steigung, t.flugProzent(eine.format(st)));
      }
    }
    return (hoehe: hoehe, tempo: tempo, steigung: steigung);
  }

  List<String> _abspannzeilen() {
    final t = gelaendeTexte(context);
    final zahl = NumberFormat(
      '#,##0.0',
      Localizations.localeOf(context).toLanguageTag(),
    );
    final hoch = _flug.aufstiegMeter;
    final dauer = _flug.gesamtdauer;
    return [
      '${zahl.format(_flug.laengeMeter / 1000)} km',
      [
        if (hoch != null) '${hoch.round()} m ${t.flugAufstieg}',
        if (dauer != null)
          '${dauer.inHours > 0 ? '${dauer.inHours}:${(dauer.inMinutes % 60).toString().padLeft(2, '0')} h' : '${dauer.inMinutes} min'} ${t.flugUnterwegs}',
      ].join('   ·   '),
    ];
  }

  /// Über welchen Weg ein eben erschienenes Foto aufblendet, in Metern.
  ///
  /// **Als Anteil der Strecke und nicht als feste Zahl.** Bei einem
  /// Spaziergang von zwei Kilometern wären zweihundert Meter ein Zehntel
  /// des Weges; bei einer Radtour über hundert wären sie zwei
  /// Zehntelsekunden.
  double get _einblendweg => math.max(40.0, _flug.laengeMeter * 0.01);

  /// Welches Foto an dieser Stelle dran ist – das zuletzt erreichte.
  ///
  /// **Es bleibt stehen, bis das nächste kommt.** Vorher galt ein Fenster
  /// von sechs Prozent der Strecke um die Stelle herum; wer nicht
  /// gleichmässig fotografiert, sah dadurch fast nichts. An der Wanderung
  /// Ilsenburg–Ilsefälle–Plesseburg gemessen: 14 Fotos an drei Stellen
  /// einer 16-km-Runde, **22 % des Fluges mit Bild** – die ersten 28 %,
  /// also gerade der Anfang, ganz ohne. Dass dazwischen nicht
  /// fotografiert wurde, ist kein Grund, die Landschaft unbebildert zu
  /// lassen: Das letzte Bild gilt weiter, bis eines an seine Stelle
  /// tritt.
  ///
  /// **Vor dem ersten Foto bleibt es leer**, und das ist Absicht: Dort
  /// gab es keines, und ein vorgezogenes Bild behauptete eine Stelle, an
  /// der es nicht entstanden ist.
  ///
  /// [widget.fotos] ist nach `meter` sortiert (siehe
  /// `_fotosAufDieSpur`); mehrere Fotos an derselben Stelle sind durch
  /// das letzte von ihnen vertreten.
  Flugfoto? _fotoBei(double meter) {
    Flugfoto? erreicht;
    for (final f in widget.fotos) {
      if (f.meter > meter) break;
      erreicht = f;
    }
    return erreicht;
  }

  /// Wie deutlich es gerade zu sehen ist – aufblendend.
  ///
  /// Ein Bild, das hart erscheint, wirkt wie ein Fehler. Abgeblendet wird
  /// nicht mehr: Das Bild geht, wenn das nächste kommt, und den Wechsel
  /// blendet [_Flugbild] selbst über.
  double _fotoDeckkraft(double meter) {
    final f = _fotoBei(meter);
    if (f == null) return 0;
    return ((meter - f.meter) / _einblendweg).clamp(0.0, 1.0);
  }

  /// Die Fotos für die Tafeln am Bildschirm, nach ihrer Stelle auf der
  /// Spur – im Video deckt `_videoAusgeben` sie vorher alle auf.
  ///
  /// **Nur das, das gerade dran ist** – geholt, sobald es aufblendet,
  /// und weggeräumt, sobald ein anderes kommt. Eine Aktivität kann
  /// hundert Fotos haben; alle als fertige Bilder im Speicher der
  /// Grafikkarte zu halten, um je eines ein paar Sekunden zu zeigen,
  /// wäre ein Vielfaches dessen, was die Landschaft selbst belegt. Ein
  /// Vorschaubild ist da, bevor das Aufblenden (gut eine halbe Sekunde)
  /// vorbei ist.
  final Map<double, ui.Image> _tafelbilder = {};
  final Set<double> _tafelbilderUnterwegs = {};

  /// Das Bild zu [foto] für die Tafel am Bildschirm – `null`, solange es
  /// noch lädt. Stösst das Laden an und räumt auf, was nicht mehr dran
  /// ist.
  ui.Image? _tafelbild(Flugfoto foto) {
    final fertig = _tafelbilder[foto.meter];
    if (fertig != null) return fertig;
    if (_tafelbilderUnterwegs.add(foto.meter)) {
      _bildAufdecken(foto.bild).then((bild) {
        _tafelbilderUnterwegs.remove(foto.meter);
        if (bild == null) return;
        if (!mounted) {
          bild.dispose();
          return;
        }
        setState(() {
          _tafelbilder[foto.meter]?.dispose();
          _tafelbilder[foto.meter] = bild;
          // Behalten wird das neue und das, was gerade zu sehen ist.
          final jetzt = _imFlug
              ? _fotoBei(_flug.bei(_abschnitt.flug).gefahrenMeter)?.meter
              : null;
          _tafelbilder.removeWhere((meter, b) {
            final weg = meter != foto.meter && meter != jetzt;
            if (weg) b.dispose();
            return weg;
          });
        });
      });
    }
    return null;
  }

  /// Die Namen in der Landschaft, aus denen die Tafeln Start und Ziel
  /// nehmen.
  List<Ortsname> get _ortsnamen => [
    for (final s in widget.schilder)
      if (s.name case final n? when n.trim().isNotEmpty) (ort: s.ort, name: n),
  ];

  /// Wie weit ein Name vom Anfang oder Ende der Spur weg sein darf –
  /// 300 Meter, bei langen Touren ein Fünfundzwanzigstel.
  double get _namensgrenze => math.max(300.0, _flug.laengeMeter / 25);

  String? get _startname =>
      naechsterName(_ortsnamen, _flug.punktBei(0), _namensgrenze);

  String? get _zielname => naechsterName(
    _ortsnamen,
    _flug.punktBei(_flug.laengeMeter),
    _namensgrenze,
  );

  String _km(double meter) => NumberFormat(
    '#,##0.0',
    Localizations.localeOf(context).toLanguageTag(),
  ).format(meter / 1000);

  /// Eine Höhe, auf zehn Meter gerundet – „rund 1920 m". Auf den Meter
  /// genau wäre eine Behauptung, die weder GPS noch Höhenmodell hergeben.
  static int _aufZehn(double meter) => (meter / 10).round() * 10;

  /// Die Titeltafel: Name der Tour, Start und Ziel, Länge und Aufstieg.
  Flugtafel _titeltafel(double deckkraft) {
    final t = gelaendeTexte(context);
    final rund = istRundweg(_flug);
    final start = _startname;
    final ziel = _zielname;
    final hoch = _flug.aufstiegMeter;
    final strecke = [
      t.flugTafelStrecke(_km(_flug.laengeMeter)),
      if (hoch != null && hoch >= 10) t.flugTafelAufstieg(hoch.round()),
    ].join(' · ');
    final weg = rund
        ? (start == null ? null : t.flugTafelRundweg(start))
        : (start != null && ziel != null && start != ziel
              ? t.flugTafelVonBis(start, ziel)
              : null);
    final titel = (widget.titel ?? '').trim();
    final kopf = titel.isNotEmpty ? titel : (rund ? start : ziel);
    if (kopf == null) {
      return (titel: strecke, zeilen: [?weg], deckkraft: deckkraft);
    }
    return (titel: kopf, zeilen: [?weg, strecke], deckkraft: deckkraft);
  }

  /// Die Zieltafel: wo man angekommen ist, wie hoch – und die Bilanz.
  Flugtafel _zieltafel(double deckkraft) {
    final t = gelaendeTexte(context);
    final rund = istRundweg(_flug);
    final titel = (widget.titel ?? '').trim();
    final kopf = rund
        ? (titel.isNotEmpty ? titel : _startname)
        : (_zielname ?? (titel.isNotEmpty ? titel : null));
    final ende = _flug.hoeheBei(_flug.laengeMeter);
    double? hoechste;
    for (final p in _flug.hoehenprofil) {
      if (hoechste == null || p.hoehe > hoechste) hoechste = p.hoehe;
    }
    final hoch = _flug.aufstiegMeter;
    final dauer = _flug.gesamtdauer;
    final bilanz = [
      '${_km(_flug.laengeMeter)} km',
      if (hoch != null && hoch >= 10) t.flugTafelAufstieg(hoch.round()),
      if (dauer != null) '${_Abspann._dauerText(dauer)} ${t.flugUnterwegs}',
    ].join(' · ');
    final lage = rund
        ? (hoechste == null
              ? null
              : t.flugTafelHoechsterPunkt(_aufZehn(hoechste)))
        : (ende == null ? null : t.flugTafelHoehe(_aufZehn(ende)));
    if (kopf == null) {
      return (titel: bilanz, zeilen: [?lage], deckkraft: deckkraft);
    }
    return (titel: kopf, zeilen: [?lage, bilanz], deckkraft: deckkraft);
  }

  /// Was im Stil „Nah dran" an Tafeln über dem Bild liegt, zur Stelle
  /// [zeit] einer Vorführung von [gesamtSekunden].
  ///
  /// Höchstens eine Texttafel und ein Foto, und die Texttafel geht vor:
  /// Am Anfang steht der Titel, am Ende das Ziel, und ein Foto, das
  /// gerade dort fällig wäre, tritt so lange zurück. Zwei Tafeln
  /// übereinander wären eine Seite, kein Bild.
  ({Flugtafel? text, Fototafel? foto}) _tafeln(
    double zeit, {
    required double gesamtSekunden,
    required ui.Image? Function(Flugfoto foto) bild,
  }) {
    final abschnitt = _abschnittBei(zeit);
    final stand = _flug.bei(abschnitt.flug);
    final titel = titeltafelDeckkraft(
      sekunde: zeit * gesamtSekunden,
      einflugEnde: _einflugAnteil * gesamtSekunden,
    );
    final ziel = zieltafelDeckkraft(abschnitt.abspann);
    final text = ziel > 0
        ? _zieltafel(ziel)
        : (titel > 0 ? _titeltafel(titel) : null);

    Fototafel? foto;
    final f = _fotoBei(stand.gefahrenMeter);
    if (f != null) {
      final deck =
          fototafelDeckkraft(
            meter: stand.gefahrenMeter,
            fotoMeter: f.meter,
            einblendweg: _einblendweg,
            haltMeter: _tempo * 3.5,
          ) *
          (1 - titel) *
          (1 - ziel);
      final b = deck > 0.01 ? bild(f) : null;
      if (b != null) {
        foto = (bild: b, unterschrift: f.unterschrift, deckkraft: deck);
      }
    }
    return (text: text, foto: foto);
  }

  /// Mischt zwei Kameraeinstellungen – für Einflug und Abspann.
  ///
  /// **Die Drehung braucht Sonderbehandlung.** Sie ist ein Winkel, und
  /// zwischen 3,1 und −3,1 liegt kein halber Umlauf, sondern ein
  /// Fingerbreit. Ohne die Rechnung mit dem kürzeren Weg drehte sich die
  /// Landschaft beim Einflug einmal ganz herum – am Bild sofort zu
  /// sehen, in Zahlen nie.
  Gelaendekamera _zwischenKamera(
    Gelaendekamera von,
    Gelaendekamera nach,
    double t,
  ) {
    double misch(double a, double b) => a + (b - a) * t;
    var dd = nach.drehung - von.drehung;
    while (dd > math.pi) {
      dd -= 2 * math.pi;
    }
    while (dd < -math.pi) {
      dd += 2 * math.pi;
    }
    return Gelaendekamera(
      drehung: von.drehung + dd * t,
      neigung: misch(von.neigung, nach.neigung),
      entfernung: misch(von.entfernung, nach.entfernung),
      brennweite: misch(von.brennweite, nach.brennweite),
      mitte: Offset(
        misch(von.mitte.dx, nach.mitte.dx),
        misch(von.mitte.dy, nach.mitte.dy),
      ),
      blickpunkt: (
        x: misch(von.blickpunkt.x, nach.blickpunkt.x),
        y: misch(von.blickpunkt.y, nach.blickpunkt.y),
        z: misch(von.blickpunkt.z, nach.blickpunkt.z),
      ),
    );
  }

  /// Hebt die Kamera an, wenn sie sonst im Berg stünde – siehe
  /// [ueberDemBoden]. Die Rechnung liegt bei der Sicht, weil sie ohne
  /// ein Pixel auskommt; hier steht nur, woher die Höhen kommen.
  Gelaendekamera _ueberDemBoden(Gelaendekamera k) =>
      ueberDemBoden(k, hoeheBei: _hoeheBei);

  /// Der Zoom beim Beginn einer Wisch-/Kneifgeste.
  ///
  /// Fortgeschrieben wird daraus und nicht aus dem jeweils letzten Wert:
  /// `pan` und `scale` sind der Gesamtweg seit dem Beginn, nicht der Weg
  /// seit dem letzten Ereignis.
  double? _zoomBeginn;

  double _zoomGrenzen(double z) => z.clamp(0.4, 6.0);

  void _ziehen(DragUpdateDetails d) {
    setState(() {
      if (_imFlug) {
        _flugversatz += d.delta.dx * 0.01;
      } else {
        _drehung += d.delta.dx * 0.01;
      }
      if (_imFlug && _nah) {
        _nahNeigung = (_nahNeigung - d.delta.dy * 0.01).clamp(0.2, 1.4);
      } else {
        _neigung = (_neigung - d.delta.dy * 0.01).clamp(0.15, 1.45);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    // **Nicht `_uhr.value`, sondern der Anteil des Flugabschnitts.** Die
    // Uhr trägt Einflug, Flug und Abspann; die Spur kennt nur den Flug.
    // Ohne diese Umrechnung wäre die Wanderung schon zu sieben Prozent
    // gelaufen, bevor der Einflug überhaupt ankommt.
    final stand = _imFlug ? _flug.bei(_abschnitt.flug) : null;
    return LayoutBuilder(
      builder: (context, platz) {
        final breite = platz.maxWidth;
        final hoehe = platz.maxHeight;
        final kameraJetzt = stand == null
            ? _ueberDemBoden(
                Gelaendekamera(
                  drehung: _drehung,
                  neigung: _neigung,
                  entfernung:
                      math.max(
                        widget.netz.breiteMeter,
                        widget.netz.hoeheMeter,
                      ) *
                      0.95 /
                      _zoom,
                  brennweite: math.min(breite, hoehe) * 1.1,
                  mitte: Offset(breite / 2, hoehe * 0.5),
                ),
              )
            : _flugkamera(
                _uhr.value,
                breite,
                hoehe,
                zoom: _zoom,
                versatz: _flugversatz,
                unten: _unten,
              );
        final nahImFlug = _nah && stand != null;
        // Nach dem Bild nachmessen, wie hoch die Leisten unten sind –
        // erst dann steht es fest, und es ändert sich mit der Fussnote.
        if (_nah) WidgetsBinding.instance.addPostFrameCallback(_untenMessen);

        // **Sagen, was gebraucht wird – in jedem Bild.** Der Lader
        // arbeitet immer nur an einer Sache und fragt nach jedem
        // fertigen Block neu, was am nächsten liegt. Eine Liste von vor
        // zwei Sekunden führte die Arbeit hinter dem Betrachter her.
        //
        // Steht hier und nicht in einem Rückruf nach dem Bild: Der
        // Wunsch ändert nichts an der Oberfläche, er setzt nur einen
        // Merkposten und stösst eine Aufgabe an. Ein zweiter Durchlauf
        // dafür wäre ein Bild Verzögerung bei jeder Bewegung.
        _lader?.brauche(
          bloeckeImBild(
            widget.netz,
            kameraJetzt,
            Size(breite, hoehe),
            schaerfe: MediaQuery.devicePixelRatioOf(context),
            uebersichtAufloesung: _uebersichtAufloesung,
          ),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onPanUpdate: _ziehen,
                child: Listener(
                  onPointerSignal: (e) {
                    if (e is PointerScrollEvent) {
                      setState(
                        () => _zoom = _zoomGrenzen(
                          _zoom * (1 - e.scrollDelta.dy * 0.002),
                        ),
                      );
                    }
                  },
                  // **Eine Magic Mouse hat kein Rad.** macOS meldet das
                  // Wischen auf ihrer Tastfläche nicht als Radschritte,
                  // sondern als fortlaufende Geste – dieselbe Art
                  // Ereignis wie ein Trackpad. Hier kam bis dahin gar
                  // nichts an: kein Zoom mit der Maus, kein Zoom mit
                  // dem Trackpad (Erstlauf-Bericht, G12). Dieselbe
                  // Behandlung wie bei der Karte, siehe
                  // [WischZoom] – nur ohne den Kunstgriff mit der
                  // Mikroaufgabe, weil hier niemand dazwischenfunkt.
                  onPointerPanZoomStart: (_) => _zoomBeginn = _zoom,
                  onPointerPanZoomUpdate: (e) {
                    final beginn = _zoomBeginn;
                    if (beginn == null) return;
                    // Kneifen und Wischen sind hier beides Zoom: Der
                    // Flug wird mit dem Ziehen gedreht und geneigt, das
                    // Wischen ist also frei.
                    final neu = istWischen(e.scale)
                        ? beginn * math.exp(-e.pan.dy * 0.004)
                        : beginn * e.scale;
                    setState(() => _zoom = _zoomGrenzen(neu));
                  },
                  onPointerPanZoomEnd: (_) => _zoomBeginn = null,
                  child: CustomPaint(
                    size: Size(breite, hoehe),
                    painter: Gelaendemaler(
                      netz: widget.netz,
                      kamera: kameraJetzt,
                      spur: widget.spur,
                      karte: widget.karte,
                      blocktexturen: _lader?.bilder,
                      spurfarbe: farben.error,
                      stimmung: widget.stimmung,
                      // Beim Flug endet die volle Farbe dort, wo man
                      // gerade ist: Was hinter einem liegt, ist
                      // zurückgelegt, was davor liegt, kommt noch. Ohne
                      // diesen Schnitt sieht die Spur im Flug genauso aus
                      // wie im Stillstand, und man verliert, wo man ist.
                      gefahrenBis: stand?.gefahrenMeter,
                      streckeJePunkt: _imFlug ? _flug.streckeJePunkt : null,
                      schilder: widget.schilder,
                      hoeheBei: _hoeheBei,
                      schriftart: widget.schriftart,
                      leuchtspur: nahImFlug,
                      kopf: nahImFlug
                          ? _flug.punktBei(stand.gefahrenMeter)
                          : null,
                      tafeln: nahImFlug
                          ? _tafeln(
                              _uhr.value,
                              gesamtSekunden:
                                  (_uhr.duration ?? _dauer()).inMilliseconds /
                                  1000,
                              bild: _tafelbild,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            // Das Foto zur Stelle – oben rechts, damit es die Spur
            // unten und die Schilder in der Mitte nicht verdeckt.
            if (stand != null && !_nah)
              Positioned(
                top: AppSpacing.md,
                right: AppSpacing.md,
                child: _Flugbild(
                  foto: _fotoBei(stand.gefahrenMeter),
                  deckkraft: _fotoDeckkraft(stand.gefahrenMeter),
                ),
              ),
            if (stand != null && !_nah && _abschnitt.abspann > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Opacity(
                      opacity: Curves.easeIn.transform(
                        _abschnitt.abspann.clamp(0.0, 1.0),
                      ),
                      child: _Abspann(
                        key: _Abspann.schluessel,
                        flug: _flug,
                        tempo: _tempo,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                key: _untenSchluessel,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.fussnoten.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.sm,
                      ),
                      // Beide biegsam: Die linke Fussnote erklärt die
                      // Bedienung und ist lang, die rechte trägt die
                      // Namensnennung. Auf einem schmalen Fenster passen
                      // sie nicht nebeneinander, und ein starres `Row`
                      // lief dort um 413 Punkte über.
                      //
                      // Im Flug „Nah dran" nur die Namensnennung – sie
                      // ist eine Lizenzauflage, die Bedienung braucht
                      // man im Flug nicht. Zwei halbe Spalten standen
                      // dort fünf Zeilen hoch über dem Leuchtpunkt.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (nahImFlug && widget.fussnoten.length > 1)
                            Flexible(child: widget.fussnoten.last)
                          else ...[
                            Flexible(child: widget.fussnoten.first),
                            const SizedBox(width: AppSpacing.sm),
                            if (widget.fussnoten.length > 1)
                              Flexible(child: widget.fussnoten[1]),
                          ],
                        ],
                      ),
                    ),
                  if (_flug.moeglich)
                    Flugleiste(
                      flug: _flug,
                      stand: stand,
                      fortschritt: _uhr.value,
                      laeuft: _uhr.isAnimating,
                      imFlug: _imFlug,
                      beimSchalten: _flugSchalten,
                      beimBeenden: _flugBeenden,
                      beimSpulen: _spulen,
                      beimAusgeben:
                          widget.beimVideoZiel == null ||
                              widget.videoschreiber == null
                          ? null
                          : _videoAusgeben,
                      gibtAus: _videoLaeuft,
                      ausgabeFortschritt: _videoLaeuft
                          ? _videoFortschritt
                          : null,
                      ausgabeRest: _videoRest,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
