import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'
    show DisabledMapCachingProvider, MapCachingProvider;
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../services/gelaende_laden.dart';
import '../services/flugvideo.dart';
import '../services/gelaendeebenen.dart';
import '../services/gelaendeflug.dart';
import '../services/gelaendekacheln.dart';
import '../services/gelaendesicht.dart';
import '../services/lichtstimmung.dart';
import '../theme/app_spacing.dart';
import '../services/wanderobjekte.dart';
import '../widgets/gelaende.dart';
import '../widgets/gelaendeschilder.dart';
import '../widgets/mini_location_map.dart' show eigeneKarte;

/// Ein Foto der Aktivität, so wie der Geländebildschirm es braucht.
///
/// Mit Koordinaten und einem Bildanbieter – **nicht** mit einer Kennung
/// oder einem Dateipfad: Dieser Bildschirm kennt die Bibliothek nicht
/// und soll auch nicht wissen müssen, wie sie ihre Vorschauen ablegt.
typedef Gelaendefoto = ({
  double breite,
  double laenge,
  ImageProvider bild,
  String? unterschrift,
});

/// Eine Spur in der Landschaft.
///
/// **Das Abbruchkriterium dieser Stufe war:** Zeigt die Landschaft mehr
/// als Karte plus Profil? Sie zeigt eine Sache, die keines von beiden
/// zeigt – *wo im Gelände* der Weg verläuft: an einem Hang entlang, über
/// einen Kamm, in einem Talgrund. Die Karte weiss das auch, aber sie
/// verlangt, Höhenlinien zu lesen; das Profil weiss nur, wie steil es
/// war, nicht wo.
class GelaendeScreen extends StatefulWidget {
  /// Die Punkte der Spur, in der Reihenfolge der Aufzeichnung.
  final List<Gelaendespurpunkt> spur;

  final String titel;

  /// Nur für Tests: Wer hier etwas hereinreicht, holt keine Kacheln aus
  /// dem Netz – und geht dann auch am gemeinsamen Kachelspeicher vorbei,
  /// damit ein Test nicht davon abhängt, was auf dieser Platte liegt.
  final http.Client? netz;

  /// Was auf der Landschaft liegt – Grund, Ebenen, Höhenlinien.
  ///
  /// **Warum das von aussen kommt.** Dieser Bildschirm kennt die
  /// Bibliothek nicht und kann die gemerkte Wahl nicht selbst
  /// nachschlagen. Der Aufrufer reicht sie herein; umschalten lässt sie
  /// sich hier trotzdem, und was hier gewählt wird, geht über
  /// [beimKartenwechsel] zurück.
  final Gelaendekarte auflage;

  /// Wird gerufen, wenn hier eine andere Auflage gewählt wird.
  final ValueChanged<Gelaendekarte>? beimKartenwechsel;

  /// Holt Gipfel, Hütten und Quellen für einen Ausschnitt – aus der
  /// Bibliothek, sonst aus dem Netz.
  ///
  /// **Von aussen und nicht von hier**, wie alles, was die Bibliothek
  /// braucht: Dieser Bildschirm kennt sie nicht. Ohne diese Hilfe bleibt
  /// die Landschaft ohne Schilder – eine Zugabe, keine Voraussetzung.
  final Future<List<Wanderobjekt>> Function({
    required double sued,
    required double west,
    required double nord,
    required double ost,
  })? wanderobjekte;

  /// Die Fotos der Aktivität, mit Ort und Zeit.
  ///
  /// Sie kommen mit **Koordinaten** herein und nicht mit einer Stelle
  /// auf der Spur: Wo auf der Spur ein Foto liegt, kann erst gerechnet
  /// werden, wenn die Spur in Metern vorliegt – und das passiert hier.
  final List<Gelaendefoto> fotos;

  /// Die Tageszeit über der Landschaft.
  ///
  /// Kommt von aussen wie [stil] und aus demselben Grund: Dieser
  /// Bildschirm kennt die Bibliothek nicht und kann die gemerkte Wahl
  /// nicht selbst nachschlagen.
  final Tageszeit stimmung;

  /// Wird gerufen, wenn hier eine andere Tageszeit gewählt wird – damit
  /// der Aufrufer sie merken kann.
  final ValueChanged<Tageszeit>? beimStimmungswechsel;

  const GelaendeScreen({
    super.key,
    required this.spur,
    required this.titel,
    this.netz,
    this.auflage = const Gelaendekarte(),
    this.stimmung = lichtstimmungVorgabe,
    this.beimStimmungswechsel,
    this.beimKartenwechsel,
    this.wanderobjekte,
    this.fotos = const [],
  });

  @override
  State<GelaendeScreen> createState() => _GelaendeScreenState();
}

class _GelaendeScreenState extends State<GelaendeScreen> {
  Gelaendenetz? _netz;
  List<Raumpunkt> _spurImRaum = const [];
  List<Flugwert> _spurwerte = const [];
  ui.Image? _karte;
  bool _laedt = true;
  late Gelaendekarte _auflage = widget.auflage;
  late Tageszeit _stimmung = widget.stimmung;

  /// Höhengitter und Ausschnitt bleiben gemerkt, damit ein Wechsel der
  /// Textur nicht auch die Höhen noch einmal aus dem Netz holt.
  Hoehengitter? _gitter;
  ({double sued, double west, double nord, double ost})? _ausschnitt;

  /// Die Schilder – kommen nach der Landschaft und halten sie nicht auf.
  List<Gelaendeschild> _schilder = const [];

  /// Die Fotos, auf ihre Stelle auf der Spur umgerechnet.
  List<Flugfoto> _flugfotos = const [];

  @override
  void initState() {
    super.initState();
    _laden();
  }

  PopupMenuItem<_Kartenwahl> _grundEintrag(
          Gelaendegrund grund, IconData symbol, String name) =>
      PopupMenuItem(
        value: _Kartenwahl.grund(grund),
        child: Row(
          children: [
            Icon(symbol,
                size: 18,
                color: grund == _auflage.grund
                    ? Theme.of(context).colorScheme.primary
                    : null),
            const SizedBox(width: AppSpacing.sm),
            // Ohne `Flexible` laeuft „Strassen und Ortsnamen" ueber den
            // Rand des Menues - in der englischen Fassung noch weiter.
            Flexible(child: Text(name)),
          ],
        ),
      );

  /// Eine Ebene zum An- und Abschalten.
  ///
  /// **Ein Haken und kein zweites Menü.** Grund und Ebenen gehören
  /// zusammen: Wer aufs Luftbild wechselt, will im selben Griff sehen
  /// können, ob die Wege darauf liegen. Zwei getrennte Menüs zwängen
  /// dazu, zwischen ihnen hin und her zu gehen, um eine Wirkung zu
  /// beurteilen.
  PopupMenuItem<_Kartenwahl> _ebeneEintrag(
          _Ebenenschalter welche, bool an, String name) =>
      PopupMenuItem(
        value: _Kartenwahl.ebene(welche),
        child: Row(
          children: [
            Icon(an ? Icons.check_box_outlined : Icons.check_box_outline_blank,
                size: 18,
                color: an ? Theme.of(context).colorScheme.primary : null),
            const SizedBox(width: AppSpacing.sm),
            // Ohne `Flexible` laeuft „Strassen und Ortsnamen" ueber den
            // Rand des Menues - in der englischen Fassung noch weiter.
            Flexible(child: Text(name)),
          ],
        ),
      );

  PopupMenuItem<Tageszeit> _stimmungEintrag(
          Tageszeit zeit, IconData symbol, String name) =>
      PopupMenuItem(
        value: zeit,
        child: Row(
          children: [
            Icon(symbol,
                size: 18,
                color: zeit == _stimmung
                    ? Theme.of(context).colorScheme.primary
                    : null),
            const SizedBox(width: AppSpacing.sm),
            // Ohne `Flexible` laeuft „Strassen und Ortsnamen" ueber den
            // Rand des Menues - in der englischen Fassung noch weiter.
            Flexible(child: Text(name)),
          ],
        ),
      );

  /// Wechselt die Tageszeit – **ohne irgendetwas nachzuladen**.
  ///
  /// Das Relief steckt in den Eckpunktfarben und entsteht beim Bauen des
  /// Netzes; Himmel und Dunst entstehen beim Zeichnen. Beides braucht
  /// weder Höhen- noch Kartenkacheln, also wird nur das Netz aus dem
  /// gemerkten Gitter neu gerechnet. Ohne dieses Neubauen bekäme man
  /// einen Morgenhimmel über einer Mittagslandschaft.
  void _stimmungWechseln(Tageszeit neu) {
    if (neu == _stimmung) return;
    final gitter = _gitter;
    setState(() => _stimmung = neu);
    widget.beimStimmungswechsel?.call(neu);
    if (gitter == null) return;
    final gebaut = baueNetz(
      gitter,
      grundfarbe: _karte == null ? gelaendeGrundfarbe : const Color(0xFFFFFFFF),
      stimmung: stimmungFuer(neu),
      reliefstaerke: _auflage.reliefstaerke,
    );
    final gerechnet = _spurInMeter(gitter, gebaut);
    setState(() {
      _netz = gebaut;
      _spurImRaum = gerechnet.linie;
      _spurwerte = gerechnet.werte;
    });
  }

  /// Wechselt die Textur, **ohne das Höhengitter neu zu holen**.
  ///
  /// Das Gitter hängt am Ausschnitt und nicht am Kartenstil – es ein
  /// zweites Mal zu laden wären Sekunden für nichts, und bei einer
  /// grossen Spur sind es sechzehn Kacheln. Neu geholt wird allein das
  /// Kartenbild; das Netz wird aus dem gemerkten Gitter neu gebaut, weil
  /// seine Grundfarbe davon abhängt, ob überhaupt eine Karte darauf
  /// liegt (siehe [gelaendeGrundfarbe]).
  Future<void> _kartenwahl(_Kartenwahl wahl) => _auflageWechseln(switch (wahl) {
        _Kartenwahl(grund: final g?) => _auflage.kopieMit(grund: g),
        _Kartenwahl(ebene: _Ebenenschalter.wege) =>
          _auflage.kopieMit(wege: !_auflage.wege),
        _Kartenwahl(ebene: _Ebenenschalter.beschriftung) =>
          _auflage.kopieMit(beschriftung: !_auflage.beschriftung),
        _Kartenwahl(ebene: _Ebenenschalter.hoehenlinien) =>
          _auflage.kopieMit(hoehenlinien: !_auflage.hoehenlinien),
        _Kartenwahl(ebene: _Ebenenschalter.wanderobjekte) =>
          _auflage.kopieMit(wanderobjekte: !_auflage.wanderobjekte),
        _ => _auflage,
      });

  Future<void> _auflageWechseln(Gelaendekarte neu) async {
    if (neu == _auflage) return;
    final gitter = _gitter;
    final aus = _ausschnitt;
    final vorher = _auflage;
    setState(() => _auflage = neu);
    widget.beimKartenwechsel?.call(neu);
    // Abgeschaltet heisst sofort weg – und wieder angeschaltet heisst
    // holen, ohne die Landschaft neu zu laden.
    if (!neu.wanderobjekte) {
      setState(() => _schilder = const []);
    } else if (!vorher.wanderobjekte &&
        _gitter != null &&
        _netz != null &&
        _ausschnitt != null) {
      unawaited(_schilderHolen(
          gitter: _gitter!,
          netz: _netz!,
          sued: _ausschnitt!.sued,
          west: _ausschnitt!.west,
          nord: _ausschnitt!.nord,
          ost: _ausschnitt!.ost));
    }
    // Ohne gemerktes Gitter gab es noch keinen erfolgreichen Lauf – dann
    // ist der volle Weg der richtige.
    if (gitter == null || aus == null) return _laden();

    setState(() => _laedt = true);
    final netz = widget.netz ?? http.Client();
    final MapCachingProvider? speicher =
        widget.netz == null ? null : const DisabledMapCachingProvider();
    try {
      final karte = await ladeKartenbild(
          sued: aus.sued,
          west: aus.west,
          nord: aus.nord,
          ost: aus.ost,
          netz: netz,
          karte: neu,
          hoehen: gitter,
          speicher: speicher);
      if (!mounted) {
        karte?.dispose();
        return;
      }
      final gebaut = baueNetz(
        gitter,
        grundfarbe:
            karte == null ? gelaendeGrundfarbe : const Color(0xFFFFFFFF),
        stimmung: stimmungFuer(_stimmung),
        reliefstaerke: neu.reliefstaerke,
      );
      final gerechnet = _spurInMeter(gitter, gebaut);
      final alt = _karte;
      setState(() {
        _netz = gebaut;
        _karte = karte;
        _spurImRaum = gerechnet.linie;
        _spurwerte = gerechnet.werte;
        _laedt = false;
      });
      alt?.dispose();
    } finally {
      if (widget.netz == null) netz.close();
    }
  }

  @override
  void dispose() {
    _karte?.dispose();
    super.dispose();
  }

  /// Wie viel Rand um die Spur herum geladen wird.
  ///
  /// Ein Fünftel der Ausdehnung. Ohne Rand endete die Landschaft genau
  /// an der Spur, und ein Weg, der am Abgrund der Welt entlangläuft,
  /// sieht falsch aus.
  static const double _randanteil = 0.2;

  Future<void> _laden() async {
    setState(() => _laedt = true);
    final netz = widget.netz ?? http.Client();
    final MapCachingProvider? speicher =
        widget.netz == null ? null : const DisabledMapCachingProvider();
    try {
      var sued = double.infinity;
      var nord = double.negativeInfinity;
      var west = double.infinity;
      var ost = double.negativeInfinity;
      for (final p in widget.spur) {
        sued = math.min(sued, p.breite);
        nord = math.max(nord, p.breite);
        west = math.min(west, p.laenge);
        ost = math.max(ost, p.laenge);
      }
      if (!sued.isFinite) {
        if (mounted) setState(() => _laedt = false);
        return;
      }
      // Eine Mindestausdehnung, damit eine Spur, die auf der Stelle
      // aufgezeichnet wurde, kein Rechteck von null Grad ergibt.
      final randB = math.max((nord - sued) * _randanteil, 0.005);
      final randL = math.max((ost - west) * _randanteil, 0.005);
      sued -= randB;
      nord += randB;
      west -= randL;
      ost += randL;

      final gitter = await ladeHoehengitter(
          sued: sued,
          west: west,
          nord: nord,
          ost: ost,
          netz: netz,
          speicher: speicher);
      if (!mounted) return;
      if (gitter == null) {
        setState(() {
          _netz = null;
          _laedt = false;
        });
        return;
      }
      final karte = await ladeKartenbild(
          sued: sued,
          west: west,
          nord: nord,
          ost: ost,
          netz: netz,
          karte: _auflage,
          hoehen: gitter,
          speicher: speicher);
      if (!mounted) {
        karte?.dispose();
        return;
      }

      // Erst die Karte, dann das Netz: Liegt eine Karte darauf, muss
      // die Grundfarbe Weiss sein (siehe [gelaendeGrundfarbe]).
      final gebaut = baueNetz(
        gitter,
        grundfarbe: karte == null ? gelaendeGrundfarbe : const Color(0xFFFFFFFF),
        stimmung: stimmungFuer(_stimmung),
        reliefstaerke: _auflage.reliefstaerke,
      );
      final gerechnet = _spurInMeter(gitter, gebaut);
      setState(() {
        _gitter = gitter;
        _ausschnitt = (sued: sued, west: west, nord: nord, ost: ost);
        _netz = gebaut;
        _karte = karte;
        _spurImRaum = gerechnet.linie;
        _spurwerte = gerechnet.werte;
        _laedt = false;
      });
      // **Nach der Landschaft und ohne sie aufzuhalten.** Overpass
      // rechnet die Abfrage bei Bedarf und antwortet bei Andrang gar
      // nicht; eine Landschaft, die darauf wartet, erscheint nie.
      final flug = Gelaendeflug(gerechnet.linie, werte: gerechnet.werte);
      final fotos = _fotosAufDieSpur(gerechnet.linie, flug.streckeJePunkt);
      if (fotos.isNotEmpty && mounted) {
        setState(() => _flugfotos = fotos);
      }
      unawaited(_schilderHolen(
          gitter: gitter,
          netz: gebaut,
          sued: sued,
          west: west,
          nord: nord,
          ost: ost));
    } finally {
      if (widget.netz == null) netz.close();
    }
  }

  /// Holt die Wanderobjekte und rechnet sie in Netzmeter um.
  ///
  /// Die Höhe kommt aus dem Gitter und nicht aus OpenStreetMap, auch wo
  /// dort eine steht: Das Schild muss **auf dieser Landschaft** sitzen,
  /// und die ist aus Kacheln gebaut. Eine vermessene Gipfelhöhe von
  /// 1141 Metern über einem Gitter, das dort 1128 kennt, hinge dreizehn
  /// Meter in der Luft.
  Future<void> _schilderHolen({
    required Hoehengitter gitter,
    required Gelaendenetz netz,
    required double sued,
    required double west,
    required double nord,
    required double ost,
  }) async {
    final holen = widget.wanderobjekte;
    if (holen == null || !_auflage.wanderobjekte) return;
    final punkte =
        await holen(sued: sued, west: west, nord: nord, ost: ost);
    if (!mounted || punkte.isEmpty) return;
    final schilder = <Gelaendeschild>[];
    for (final p in punkte) {
      final h = gitter.anOrt(p.breite, p.laenge);
      if (h == null) continue;
      schilder.add(Gelaendeschild(
        art: p.art,
        beschriftung: _beschriftung(p),
        ort: (
          x: ((p.laenge - gitter.west) / (gitter.ost - gitter.west) - 0.5) *
              netz.breiteMeter,
          y: (0.5 - (gitter.nord - p.breite) / (gitter.nord - gitter.sued)) *
              netz.hoeheMeter,
          z: (h - netz.mittlereHoehe) * gelaendeUeberhoehung +
              schildHoeheMeter * gelaendeUeberhoehung,
        ),
      ));
    }
    setState(() => _schilder = schilder);
  }

  /// Fragt, **was** ausgegeben werden soll und **wohin**.
  ///
  /// **Der Dateiwähler steht hier und nicht in der Ansicht.** Die
  /// Landschaft zeichnet; wo eine Datei hinsoll, ist eine Frage an den,
  /// der sie haben will.
  ///
  /// **Und vorher die Einstellungen.** Bis 3.5.1 gab es nur den
  /// Speichern-Dialog: Grösse und Länge standen fest. Beides sind aber
  /// Fragen an den, der das Video weitergibt – ein Video für eine
  /// Nachricht darf klein sein, und wie lange jemand zusehen mag,
  /// entscheidet nicht die Länge der Wanderung.
  Future<Videoauftrag?> _videoAuftrag(Duration vorgabe) async {
    final t = AppTexte.of(context);
    final wahl = await showDialog<({int breite, int hoehe, int sekunden})>(
      context: context,
      builder: (_) => _VideoDialog(vorgabe: vorgabe),
    );
    if (wahl == null || !mounted) return null;

    final sauber = widget.titel
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final pfad = await FilePicker.platform.saveFile(
      dialogTitle: t.flugVideo,
      fileName: '${sauber.isEmpty ? 'ueberflug' : sauber}.mp4',
      type: FileType.custom,
      allowedExtensions: const ['mp4'],
    );
    if (pfad == null) return null;
    // Manche Dateiwähler geben die Endung nicht mit; ohne sie schreibt
    // ffmpeg nichts, weil es das Format am Namen erkennt.
    return (
      ziel: File(pfad.toLowerCase().endsWith('.mp4') ? pfad : '$pfad.mp4'),
      breite: wahl.breite,
      hoehe: wahl.hoehe,
      dauer: Duration(seconds: wahl.sekunden),
    );
  }

  /// Was auf dem Schild steht – `null` heisst: nur das Zeichen.
  ///
  /// **Die Höhe gehört dazu, wo es eine gibt.** „Rohnberg" allein sagt
  /// bei einem Überflug wenig; „Rohnberg 564 m" sagt, ob man oben war.
  /// Sie kommt aus OpenStreetMap, weil sie dort vermessen ist – anders
  /// als die aus dem Gitter, das bei einer Spitze zu tief liegt.
  ///
  /// 27 der 41 Punkte im Ilsetal sind Wegweiser, die meisten ohne Namen.
  /// Ein Kästchen mit leerem Text wäre für jeden von ihnen ein Fleck im
  /// Bild.
  String? _beschriftung(Wanderobjekt p) {
    final name = p.name;
    if (name == null) return null;
    final h = p.hoehe;
    return h == null ? name : '$name  ${h.round()} m';
  }

  /// Rechnet die Fotos auf ihre Stelle auf der Spur um.
  ///
  /// **Der nächste Spurpunkt gewinnt, aber nicht um jeden Preis.** Ein
  /// Foto, das drei Kilometer neben dem Weg entstanden ist, gehört nicht
  /// zu dieser Wanderung – es hat nur zufällig dasselbe Datum. Die
  /// Grenze richtet sich nach der Ausdehnung der Spur: ein Zwanzigstel,
  /// mindestens hundert Meter.
  List<Flugfoto> _fotosAufDieSpur(
      List<Raumpunkt> linie, List<double> streckeJePunkt) {
    if (linie.isEmpty || widget.fotos.isEmpty) return const [];
    final gitter = _gitter;
    final netz = _netz;
    if (gitter == null || netz == null) return const [];
    final grenze = math.max(
        100.0, math.max(netz.breiteMeter, netz.hoeheMeter) / 20);

    final aus = <Flugfoto>[];
    for (final f in widget.fotos) {
      final x = ((f.laenge - gitter.west) / (gitter.ost - gitter.west) - 0.5) *
          netz.breiteMeter;
      final y = (0.5 -
              (gitter.nord - f.breite) / (gitter.nord - gitter.sued)) *
          netz.hoeheMeter;
      var beste = double.infinity;
      var stelle = 0.0;
      for (var i = 0; i < linie.length; i++) {
        final dx = linie[i].x - x;
        final dy = linie[i].y - y;
        final d = dx * dx + dy * dy;
        if (d < beste) {
          beste = d;
          stelle = i < streckeJePunkt.length ? streckeJePunkt[i] : 0;
        }
      }
      if (math.sqrt(beste) > grenze) continue;
      aus.add((meter: stelle, bild: f.bild, unterschrift: f.unterschrift));
    }
    aus.sort((a, b) => a.meter.compareTo(b.meter));
    return aus;
  }

  /// Rechnet die Spur in dieselben Meter wie das Netz – und liefert die
  /// Zahlen dazu gleich mit.
  ///
  /// **Die Höhe kommt aus der Datei, nicht aus den Kacheln** – was das
  /// Gerät gemessen hat, ist die Aussage, die Kacheln sind die Kulisse.
  /// Nur wo die Datei keine Höhe führt, wird das Gelände gefragt.
  ///
  /// Zwei Meter Zugabe: Eine Linie genau auf der Oberfläche verschwindet
  /// halb darin, weil das Gitter zwischen den Stützpunkten gerade
  /// verläuft und der Berg gewölbt ist.
  ///
  /// Linie und Werte entstehen in einem Zug und sind damit
  /// zwangsläufig gleich lang.
  ///
  /// Getrennt gerechnet wäre es ein Fehler, der still bleibt: Punkte ohne
  /// jede Höhe fallen hier heraus, und eine zweite Schleife über
  /// `widget.spur` ergäbe eine um genau diese Punkte längere Werteliste.
  /// Jede Höhe und jedes Tempo stünde danach an der falschen Stelle,
  /// ohne dass irgendwo etwas abstürzt. Deshalb der gemeinsame Rückgabe-
  /// wert und der Merkposten in [Gelaendeflug].
  ({List<Raumpunkt> linie, List<Flugwert> werte}) _spurInMeter(
      Hoehengitter gitter, Gelaendenetz netz) {
    // **Der Nullpunkt kommt aus dem Netz.** Er wird dort aus dem ganzen
    // Gitter gerechnet; ihn hier ein zweites Mal aus einem anders
    // beschnittenen Gitter zu rechnen hiesse, die Spur um die Differenz
    // über oder unter den Boden zu legen.
    final g = gitter;
    final mittlereHoehe = netz.mittlereHoehe;
    final linie = <Raumpunkt>[];
    final werte = <Flugwert>[];
    for (final p in widget.spur) {
      final h = p.hoehe ?? g.anOrt(p.breite, p.laenge);
      if (h == null) continue;
      linie.add((
        x: ((p.laenge - g.west) / (g.ost - g.west) - 0.5) * netz.breiteMeter,
        y: (0.5 - (g.nord - p.breite) / (g.nord - g.sued)) * netz.hoeheMeter,
        z: (h + 2 - mittlereHoehe) * gelaendeUeberhoehung,
      ));
      // **Die Höhe der Datei, nicht die aus dem Gitter.** Wo die
      // Aufzeichnung eine trägt, ist sie die Aussage; das Gelände ist
      // nur eingesprungen, damit die Linie nicht abreisst. Für die
      // Anzeige zählt nur, was gemessen wurde – sonst stünde eine aus
      // Kacheln geratene Zahl neben einer echten, ununterscheidbar.
      werte.add((hoehe: p.hoehe, zeit: p.zeit));
    }
    return (linie: linie, werte: werte);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('${t.gelaendeTitel} · ${widget.titel}'),
        actions: [
          // Die Textur umschalten, ohne den Bildschirm zu verlassen.
          // Ein Luftbild beantwortet eine andere Frage als eine
          // Wanderkarte: „wie sah es dort aus" gegen „wie hiess der Weg".
          PopupMenuButton<_Kartenwahl>(
            tooltip: t.gelaendeKarte,
            icon: const Icon(Icons.layers_outlined),
            onSelected: _kartenwahl,
            itemBuilder: (context) => [
              _grundEintrag(Gelaendegrund.luftbild, Icons.satellite_alt_outlined,
                  t.karteLuftbild),
              _grundEintrag(Gelaendegrund.wanderkarte, Icons.terrain_outlined,
                  t.karteTopografie),
              _grundEintrag(
                  Gelaendegrund.hell, Icons.light_mode_outlined, t.karteHell),
              _grundEintrag(Gelaendegrund.dunkel, Icons.dark_mode_outlined,
                  t.karteDunkel),
              // Die eigene Quelle nur, wenn es eine gibt – ein Eintrag,
              // der auf OpenStreetMap zurückfiele, wäre eine Lüge.
              if (eigeneKarte != null)
                _grundEintrag(Gelaendegrund.eigene,
                    Icons.travel_explore_outlined, eigeneKarte!.name),
              const PopupMenuDivider(),
              _ebeneEintrag(_Ebenenschalter.wege, _auflage.wege,
                  t.gelaendeEbeneWege),
              _ebeneEintrag(_Ebenenschalter.beschriftung,
                  _auflage.beschriftung, t.gelaendeEbeneBeschriftung),
              _ebeneEintrag(_Ebenenschalter.hoehenlinien,
                  _auflage.hoehenlinien, t.gelaendeEbeneHoehenlinien),
              _ebeneEintrag(_Ebenenschalter.wanderobjekte,
                  _auflage.wanderobjekte, t.gelaendeEbeneWanderobjekte),
            ],
          ),
          // Die Tageszeit daneben, gleiche Machart. Sie beantwortet eine
          // dritte Frage: nicht „was liegt dort" und nicht „wie sah es
          // aus", sondern wie stark das Gelände hervortreten soll. Eine
          // flache Sonne zeigt jede Mulde, eine hohe lässt die Karte
          // lesbar.
          PopupMenuButton<Tageszeit>(
            tooltip: t.gelaendeStimmung,
            icon: const Icon(Icons.wb_twilight_outlined),
            onSelected: _stimmungWechseln,
            itemBuilder: (context) => [
              _stimmungEintrag(Tageszeit.morgen, Icons.wb_twilight_outlined,
                  t.stimmungMorgen),
              _stimmungEintrag(
                  Tageszeit.mittag, Icons.wb_sunny_outlined, t.stimmungMittag),
              _stimmungEintrag(Tageszeit.abend, Icons.wb_incandescent_outlined,
                  t.stimmungAbend),
              _stimmungEintrag(Tageszeit.blaueStunde,
                  Icons.nights_stay_outlined, t.stimmungBlaueStunde),
            ],
          ),
        ],
      ),
      body: _laedt
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppSpacing.lg),
                  Text(t.gelaendeLaedt,
                      style: TextStyle(color: farben.onSurfaceVariant)),
                ],
              ),
            )
          : _netz == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: SizedBox(
                      width: 420,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.gelaendeNichts,
                              textAlign: TextAlign.center),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton(
                            onPressed: _laden,
                            child: Text(t.gelaendeErneut),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              // Die Fussnoten gehen MIT hinein und liegen nicht darüber:
              // Die Flugleiste sitzt am unteren Rand der Ansicht, und ein
              // zweiter Stapel mit `bottom:` landete genau auf ihrem
              // Startknopf.
              : Gelaendeansicht(
                  // Ein neuer Schlüssel bei jedem Stilwechsel: Sonst
                  // behielte die Ansicht ihren Texturvorrat aus der
                  // alten Karte, und der Bildschirm zeigte
                  // Luftbildkacheln über einer Wanderkarte.
                  key: ValueKey(_auflage),
                  netz: _netz!,
                  spur: _spurImRaum,
                  spurwerte: _spurwerte,
                  karte: _karte,
                  auflage: _auflage,
                  hoehen: _gitter,
                  schilder: _schilder,
                  fotos: _flugfotos,
                  namensnennung:
                      '${t.gelaendeNamensnennung} · ${_auflage.nennung}',
                  beimVideoZiel: _videoAuftrag,
                  netzKlient: widget.netz,
                  stimmung: stimmungFuer(_stimmung),
                  fussnoten: [
                    _Fussnote([
                      t.gelaendeBedienung,
                      t.gelaendeUeberhoeht(
                          gelaendeUeberhoehung.toStringAsFixed(0)),
                    ].join(' · ')),
                    // Die Namensnennung sagt genau, was im Bild steht:
                    // Wer die Wegeebene abschaltet, soll Waymarked
                    // Trails nicht mehr genannt sehen. Eine
                    // Lizenzauflage ist keine Zierleiste.
                    _Fussnote(
                        '${t.gelaendeNamensnennung} · ${_auflage.nennung}'),
                  ],
                ),
    );
  }
}

/// Die beiden Zeilen am unteren Rand: links die Bedienung, rechts die
/// Quellen.
///
/// **Elf Punkte und nicht neun.** Links steht keine Namensnennung,
/// sondern die Anleitung – wie man dreht, kippt und zoomt. Neun Punkte
/// sind die Groesse, in der man Rechtevermerke wegschaut; sie war hier
/// zugleich die Groesse, in der die einzige Erklaerung der Bedienung
/// stand (15. Pruefrunde).
class _Fussnote extends StatelessWidget {
  static const double schriftgroesse = 11;

  final String text;
  const _Fussnote(this.text);

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context)
            .colorScheme
            .surface
            .withValues(alpha: 0.75),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            text,
            style: TextStyle(
              fontSize: schriftgroesse,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );
}

/// Welche Ebene ein Menüeintrag umschaltet.
enum _Ebenenschalter { wege, beschriftung, hoehenlinien, wanderobjekte }

/// Was ein Griff ins Kartenmenü bedeutet – ein anderer Grund oder eine
/// umgeschaltete Ebene.
///
/// Ein gemeinsamer Typ und nicht zwei Menüs: Grund und Ebenen gehören
/// zusammen, und wer aufs Luftbild wechselt, will im selben Griff sehen
/// können, ob die Wege darauf liegen.
class _Kartenwahl {
  const _Kartenwahl.grund(Gelaendegrund this.grund) : ebene = null;
  const _Kartenwahl.ebene(_Ebenenschalter this.ebene) : grund = null;

  final Gelaendegrund? grund;
  final _Ebenenschalter? ebene;
}

/// Was ausgegeben wird: Grösse und Länge, bevor der Speichern-Dialog
/// kommt.
///
/// **Warum ein eigener Dialog und nicht drei Knöpfe in der Leiste.** Die
/// Flugleiste ist schmal und trägt schon Steuerung, Messwerte und
/// Höhenprofil. Und die Frage stellt sich genau einmal – beim Ausgeben –,
/// nicht während man fliegt.
class _VideoDialog extends StatefulWidget {
  const _VideoDialog({required this.vorgabe});

  /// Wie lange der Flug am Bildschirm dauert. Das ist die Vorgabe, weil
  /// es die Länge ist, die man gerade gesehen hat.
  final Duration vorgabe;

  @override
  State<_VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<_VideoDialog> {
  /// **Drei Grössen und nicht die Fenstergrösse.** Ein Video, dessen
  /// Kantenlänge davon abhängt, wie gross gerade das Fenster war, ist
  /// beim Weitergeben eine Überraschung – und auf einem Bildschirm mit
  /// doppelter Punktdichte wäre es 3840 breit und viermal so teuer.
  static const _groessen = <(int, int)>[(1280, 720), (1920, 1080), (2560, 1440)];

  int _grad = 1;
  late double _sekunden;

  @override
  void initState() {
    super.initState();
    _sekunden = widget.vorgabe.inMilliseconds / 1000;
    if (_sekunden < 5) _sekunden = 20;
    if (_sekunden > 300) _sekunden = 300;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final (breite, hoehe) = _groessen[_grad];
    final bilder = (_sekunden * videoBilderJeSekunde).round();
    return AlertDialog(
      title: Text(t.flugVideoEinstellungen),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.flugVideoAufloesung,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<int>(
              segments: [
                for (var i = 0; i < _groessen.length; i++)
                  ButtonSegment(
                    value: i,
                    label: Text('${_groessen[i].$1}×${_groessen[i].$2}'),
                  ),
              ],
              selected: {_grad},
              showSelectedIcon: false,
              onSelectionChanged: (w) => setState(() => _grad = w.first),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(t.flugVideoDauer,
                style: Theme.of(context).textTheme.labelLarge),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _sekunden,
                    min: 5,
                    max: 300,
                    divisions: 59,
                    label: t.flugVideoDauerWert(_sekunden.round()),
                    onChanged: (w) => setState(() => _sekunden = w),
                  ),
                ),
                Text(t.flugVideoDauerWert(_sekunden.round()),
                    style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${t.flugVideoBilder(bilder)} · $breite×$hoehe',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(t.flugVideoWaehrenddessen,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
              (breite: breite, hoehe: hoehe, sekunden: _sekunden.round())),
          child: Text(t.flugVideoWeiter),
        ),
      ],
    );
  }
}
