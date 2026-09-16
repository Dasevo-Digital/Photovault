/// **Wer den Blöcken ihre scharfen Bilder holt.**
///
/// `gelaendetextur.dart` rechnet aus, welcher Block welche Stufe
/// braucht; `blockvorrat.dart` entscheidet, was davon im Speicher bleibt.
/// Hier kommt beides zusammen und trifft auf ein Netz, das langsam ist
/// und auf Server, die man nicht überrennen darf.
///
/// **Drei Regeln, und jede hat einen Grund ausserhalb der Technik.**
///
/// 1. **Nur was zu sehen ist.** Der Aufrufer sagt in jedem Bild, welche
///    Blöcke im Bild stehen und wie weit sie weg sind. Alles andere wird
///    weder geholt noch gehalten. Ein Flug über zwölf Kilometer berührt
///    über tausend Blöcke; auf einmal geladen wären das Gigabyte und
///    zehntausend Abrufe.
/// 2. **Das Nächste zuerst.** Die Wunschliste wird nach Entfernung
///    abgearbeitet. Wer im Flug nach vorn sieht, bekommt zuerst scharf,
///    was er anschaut.
/// 3. **Höflich.** Höchstens [gleichzeitig] Kacheln zur selben Zeit, und
///    der Kachelspeicher ist derselbe, den auch die Karten benutzen –
///    wer eine Tour zweimal ansieht, fragt beim zweiten Mal niemanden.
///
/// **Gröber ist besser als nichts.** Solange die feine Fassung lädt,
/// zeigt der Maler die gröbere aus dem Vorrat oder die Übersichtskarte.
/// Ohne diese Kette wäre die Landschaft während des Ladens stellenweise
/// leer, und Löcher fallen mehr auf als Unschärfe.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;


import 'package:flutter_map/flutter_map.dart' show MapCachingProvider;
import 'package:http/http.dart' as http;

import 'blockvorrat.dart';
import 'gelaende_laden.dart';
import 'gelaendeebenen.dart';
import 'gelaendekacheln.dart';
import 'gelaendetextur.dart';
import 'hoehenlinien.dart';

/// Was ein Block braucht – vom Maler her gesehen.
typedef Blockwunsch = ({Texturblock block, int stufe, double entfernung});

/// Wie viel Blocktextur höchstens im Speicher liegt.
///
/// Achtzig Megabyte. Ein Block auf Stufe 18 belegt 4 MB
/// (1024 × 1024 × 4); das sind zwanzig scharfe Blöcke oder achtzig auf
/// der Stufe darunter. Im Bild stehen bei einem Flug selten mehr als
/// dreissig, und was hinter der Kamera liegt, wird verdrängt, nicht
/// behalten.
///
/// Zum Vergleich: Der Bildspeicher der Zeitleiste steht auf 200 MB
/// (gemessen in `tool/messe_bildspeicher_test.dart`), und der trägt die
/// ganze Bibliothek. Die Landschaft ist ein Bildschirm von vielen.
const int blocktexturSpeicher = 80 * 1024 * 1024;

/// Wie viele Kachelabrufe gleichzeitig laufen dürfen.
///
/// Sechs. Ein Block auf Stufe 18 besteht aus sechzehn Kacheln; ohne
/// Deckelung stünden bei fünf Blöcken achtzig Anfragen gleichzeitig an
/// einem Server, der sie freiwillig ausliefert.
const int gleichzeitig = 6;

/// Holt und hält die Texturen der einzelnen Blöcke.
class Blocktexturlader {
  Blocktexturlader({
    required this.karte,
    required this.grundstufe,
    this.hoehen,
    http.Client? netz,
    MapCachingProvider? speicher,
    this.hoechstensBytes = blocktexturSpeicher,
    this.beiAenderung,
  })  : _netz = netz,
        _eigenerKlient = netz == null,
        _speicher = speicher {
    _vorrat = Blockvorrat<ui.Image>(
      hoechstensBytes: hoechstensBytes,
      freigeben: (bild) => bild.dispose(),
    );
  }

  /// Was auf der Landschaft liegen soll – Grund, Ebenen, Höhenlinien.
  final Gelaendekarte karte;

  /// Das Höhengitter – nur für die Höhenlinien, die daraus gerechnet
  /// werden statt geladen zu werden.
  final Hoehengitter? hoehen;

  /// Auf welcher Stufe die Blöcke abgesteckt sind – sie begrenzt, wie
  /// fein einer werden darf (siehe [hoechsteStufeFuer]).
  final int grundstufe;

  final int hoechstensBytes;

  /// Wird gerufen, sobald eine neue Textur bereitsteht – der Maler soll
  /// dann neu zeichnen.
  final void Function()? beiAenderung;

  http.Client? _netz;
  final bool _eigenerKlient;
  final MapCachingProvider? _speicher;

  late final Blockvorrat<ui.Image> _vorrat;

  /// Was zuletzt gewünscht wurde – die Grundlage der Verdrängung.
  var _wunsch = <Texturblock, Blockwunsch>{};

  /// Was gerade geholt wird, damit dieselbe Kachel nicht zweimal läuft.
  final _laeuft = <String>{};

  /// Was **nicht** zu holen war – und deshalb nicht wieder gefragt wird.
  ///
  /// **Ohne diese Liste dreht sich der Lader im Kreis**, und das war
  /// keine Vermutung: Beim ersten Lauf mit einem Server, der nichts
  /// liefert, fragte er denselben Block wieder und wieder, weil der
  /// Wunsch nach jedem Fehlschlag unverändert offen stand. Der Test lief
  /// in die Zeitgrenze statt abzustürzen – ein Fehler, der sich in der
  /// laufenden App als warmer Lüfter geäussert hätte.
  ///
  /// Kein zweiter Versuch innerhalb desselben Bildschirms: Der Abruf
  /// selbst wiederholt sich schon einmal (siehe [holeKachelRoh]), und
  /// dort, wo nichts ankommt, steht die gröbere Fassung oder die
  /// Übersichtskarte. Wer es noch einmal versuchen will, verlässt den
  /// Bildschirm und kommt wieder.
  final _vergeblich = <String>{};

  bool _arbeitet = false;
  bool _geschlossen = false;

  /// Die Bilder, so wie der Maler sie braucht.
  ///
  /// **Eine neue Karte bei jeder Änderung.** Der Maler vergleicht sie
  /// mit `!=`, um zu entscheiden, ob er neu zeichnet; dieselbe Karte
  /// verändert weiterzureichen hiesse, dass eine frisch geladene Textur
  /// erst beim nächsten Kameraruck sichtbar wird.
  Map<Texturblock, ui.Image> bilder = const {};

  /// Wie fein ein Block überhaupt werden darf.
  ///
  /// Drei Grenzen, und die kleinste gewinnt:
  ///
  /// * Was der Anbieter liefert. OpenTopoMap hört bei 17 auf und
  ///   antwortet darüber mit **200 und einer einfarbigen Kachel** – ein
  ///   Loch ohne Fehlermeldung.
  /// * [texturHoechsteStufe] – darüber belegte ein Block 16 MB.
  /// * Zwei Stufen über der Grundstufe. Ein Block ist dann 4 × 4
  ///   Kacheln, also 1024 × 1024 und 4 MB. Bei einer grossen Tour steht
  ///   die Grundstufe gröber (siehe `passendeGrundstufe`), und ohne diese
  ///   Grenze bräuchte ein einzelner Block dort 64 MB.
  int get hoechsteStufeFuer {
    var z = texturHoechsteStufe;
    final anbieter = karte.grund.hoechsteStufe;
    if (anbieter < z) z = anbieter;
    if (grundstufe + 2 < z) z = grundstufe + 2;
    return z;
  }

  /// Sagt, welche Blöcke gerade gebraucht werden.
  ///
  /// Darf in jedem Bild gerufen werden: Was schon da ist, kostet nichts,
  /// und der Lader arbeitet immer nur an einer Sache.
  void brauche(Iterable<Blockwunsch> wunsch) {
    if (_geschlossen) return;
    _wunsch = {for (final w in wunsch) w.block: w};
    _arbeite();
  }

  /// Was ein Block im Vorrat hat – die feinste vorhandene Fassung.
  ui.Image? bei(Texturblock block) => _vorrat.bestes(block)?.inhalt;

  /// Wie viele der [wieviele] nächstgelegenen gewünschten Blöcke ihre
  /// Zielstufe haben.
  ///
  /// **Das Mass, an dem sich Warten überhaupt beurteilen lässt.** Ob ein
  /// Bild scharf ist, entscheidet die Stufe, nicht die Anwesenheit einer
  /// Textur – ein Block trägt notfalls die Übersichtskarte, und die ist
  /// da, nur unschärfer. Gebraucht von `tool/messe_videolauf_test.dart`,
  /// das damit belegt, was die kurze Frist kostet.
  ({int scharf, int gesamt}) schaerfeNah(int wieviele) {
    var scharf = 0, gesamt = 0;
    for (final a in _auftraege()) {
      if (gesamt >= wieviele) break;
      gesamt++;
      final da = _vorrat.bestes(a.block);
      if (da != null && da.stufe >= a.stufe) scharf++;
    }
    return (scharf: scharf, gesamt: gesamt);
  }

  int get belegt => _vorrat.belegt;
  int get gehalten => _vorrat.anzahl;

  /// Ob gerade noch etwas zu holen ist.
  bool get beschaeftigt => _arbeitet;

  /// Wartet, bis alles Gewünschte da ist – höchstens [hoechstens].
  ///
  /// **Für den Videoexport, und dort ist es die Antwort auf einen echten
  /// Mangel.** Am Bildschirm holt der Lader nach, während man fliegt;
  /// ein Bild später ist es scharf, und niemand stört sich daran. Ein
  /// Video hat kein „ein Bild später": Was beim Aufzeichnen eines Bildes
  /// nicht da ist, fehlt darin für immer. Ohne dieses Warten nähme die
  /// Ausgabe die Texturen, die gerade zufällig im Vorrat lagen.
  ///
  /// Mit Frist und nicht unbegrenzt: Ein Server, der nicht antwortet,
  /// darf eine Ausgabe nicht anhalten. Dann steht dort die gröbere
  /// Fassung – unscharf, aber vorhanden.
  Future<void> ruhe({Duration hoechstens = const Duration(seconds: 3)}) async {
    final uhr = Stopwatch()..start();
    while (!_geschlossen &&
        (_arbeitet || _naechsterAuftrag() != null) &&
        uhr.elapsed < hoechstens) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Wartet, bis die [naechste] **nächstgelegenen** gewünschten Blöcke
  /// ihre Zielstufe haben – höchstens aber [hoechstens].
  ///
  /// **Warum nicht [ruhe].** [ruhe] wartet, bis der Lader gar nichts mehr
  /// zu tun hat. Das ist im Flug ein Zustand, der nie eintritt: Ein Bild
  /// von 1920 × 1080 will über fünfhundert Blöcke, in achtzig Megabyte
  /// passen hundertfünfzig Texturen, und mit jedem Bild verschiebt sich,
  /// welcher Block welche Stufe bekommt. Der Vorrat läuft also dauernd
  /// über, und die Ausgabe wartete jedes Mal die volle Frist ab.
  ///
  /// Gemessen an einem gestellten Netz, das **sofort** antwortet, über
  /// vierzig Bilder einer Flugbahn (`tool/messe_videolauf_test.dart`):
  ///
  /// ```
  /// ruhe(700 ms)   665 ms je Bild   39.525 Kachelabrufe für 40 Bilder
  /// ```
  ///
  /// Hochgerechnet auf einen Überflug von einer Minute: **zwanzig Minuten
  /// reines Warten**, und das mit einem Server, der nichts kostet.
  ///
  /// Gewartet wird deshalb nur auf das, was man auch sieht. Ein ferner
  /// Block trägt bis dahin die Übersichtskarte – die ist da, sie ist nur
  /// unschärfer, und in der Ferne ist genau das die Absicht.
  Future<void> ruheNah({
    int naechste = 24,
    Duration hoechstens = const Duration(milliseconds: 300),
  }) async {
    final uhr = Stopwatch()..start();
    while (!_geschlossen && uhr.elapsed < hoechstens && _offeneNahe(naechste)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Ob unter den [wieviele] nächstgelegenen gewünschten Blöcken noch
  /// einer auf seine Stufe wartet.
  ///
  /// Vergebliche werden übersprungen: Auf eine Kachel zu warten, die
  /// schon einmal nicht kam, ist Warten auf nichts.
  bool _offeneNahe(int wieviele) {
    var gezaehlt = 0;
    for (final a in _auftraege()) {
      if (gezaehlt++ >= wieviele) return false;
      if (_vergeblich.contains('${a.block}@${a.stufe}')) continue;
      final da = _vorrat.bestes(a.block);
      if (da == null || da.stufe < a.stufe) return true;
    }
    return false;
  }

  Future<void> _arbeite() async {
    if (_arbeitet || _geschlossen) return;
    _arbeitet = true;
    try {
      while (!_geschlossen) {
        final naechster = _naechsterAuftrag();
        if (naechster == null) break;
        await _hole(naechster.block, naechster.stufe);
      }
    } finally {
      _arbeitet = false;
    }
  }

  /// Die Aufträge, nach Entfernung geordnet und **auf das Budget
  /// beschnitten**.
  ///
  /// **Warum das Budget schon hier zuschlägt und nicht erst beim
  /// Verdrängen.** Der erste Anlauf holte einfach alles Gewünschte und
  /// liess den Vorrat aufräumen. Das Ergebnis war entweder gar keine
  /// Verdrängung (weil alles Gewünschte geschützt war – gemessen: acht
  /// Blöcke in einem Vorrat für zwei) oder ein Kreislauf: Der fernste
  /// Block wird geholt, verdrängt sich selbst, wird wieder gewünscht,
  /// wird wieder geholt.
  ///
  /// Wer vorher rechnet, hat beides nicht. Was nicht ins Budget passt,
  /// wird **gröber** genommen statt gar nicht – und passt auch das nicht
  /// mehr, bleibt dort die Übersichtskarte stehen. Sie ist da, sie ist
  /// nur unschärfer.
  List<({Texturblock block, int stufe})> _auftraege() {
    final sortiert = _wunsch.values.toList()
      ..sort((a, b) => a.entfernung.compareTo(b.entfernung));
    final aus = <({Texturblock block, int stufe})>[];
    var summe = 0;
    for (final w in sortiert) {
      var ziel = w.stufe.clamp(0, hoechsteStufeFuer);
      while (ziel >= 0 &&
          summe + w.block.speicherBytes(ziel) > hoechstensBytes) {
        ziel--;
      }
      if (ziel < 0) break;
      summe += w.block.speicherBytes(ziel);
      aus.add((block: w.block, stufe: ziel));
    }
    return aus;
  }

  /// Der nächste Auftrag: der **nächstgelegene** Block, dem seine Stufe
  /// noch fehlt.
  ///
  /// Nach jedem geholten Block neu gefragt und nicht einmal am Anfang
  /// eine Liste gebaut: Im Flug bewegt sich die Kamera weiter, während
  /// geladen wird, und eine Liste von vor zwei Sekunden führte die Arbeit
  /// hinter dem Betrachter her.
  ({Texturblock block, int stufe})? _naechsterAuftrag() {
    for (final a in _auftraege()) {
      final da = _vorrat.bestes(a.block);
      if (da != null && da.stufe >= a.stufe) continue;
      final marke = '${a.block}@${a.stufe}';
      if (_laeuft.contains(marke) || _vergeblich.contains(marke)) continue;
      return a;
    }
    return null;
  }

  Future<void> _hole(Texturblock block, int stufe) async {
    final marke = '$block@$stufe';
    _laeuft.add(marke);
    try {
      final bild = await _baueTextur(block, stufe);
      if (bild == null) {
        _vergeblich.add(marke);
        return;
      }
      if (_geschlossen) {
        bild.dispose();
        return;
      }
      _vorrat.lege(block, stufe, bild, block.speicherBytes(stufe));
      _raeumeAuf();
      _neueKarte();
      beiAenderung?.call();
    } catch (_) {
      // Ein Block, der nicht kommt, ist kein Grund, den Rest aufzugeben –
      // der Maler zeigt dort die gröbere Fassung.
      _vergeblich.add(marke);
    } finally {
      _laeuft.remove(marke);
    }
  }

  /// Verdrängt nach Entfernung.
  ///
  /// Was gar nicht mehr gewünscht ist, liegt unendlich weit weg und geht
  /// zuerst. Was gewünscht ist, muss nicht geschützt werden – [_auftraege]
  /// hat schon dafür gesorgt, dass es zusammen ins Budget passt.
  void _raeumeAuf() {
    _vorrat.raeume((b) => _wunsch[b]?.entfernung ?? double.infinity);
  }

  void _neueKarte() {
    final neu = <Texturblock, ui.Image>{};
    for (final b in _wunsch.keys) {
      final x = _vorrat.bestes(b);
      if (x != null) neu[b] = x.inhalt;
    }
    bilder = neu;
  }

  /// Setzt die Kacheln eines Blocks zu einem Bild zusammen.
  ///
  /// Fehlende Kacheln bleiben **leer** statt den ganzen Block zu
  /// verwerfen: Fünfzehn von sechzehn ergeben einen Block mit einem
  /// Loch, null Kacheln ergeben nichts. Kommt keine einzige an, ist das
  /// Ergebnis `null` und der Maler bleibt bei der gröberen Fassung.
  Future<ui.Image?> _baueTextur(Texturblock block, int stufe) async {
    final kante = block.texturkante(stufe);
    final sammler = ui.PictureRecorder();
    final leinwand = ui.Canvas(sammler);
    var etwasDa = false;

    // Die Liste einmal holen: `ebenen` baut bei jedem Zugriff eine neue
    // mit neuen Objekten, und `Kartenebene` hat kein eigenes
    // Gleichheitszeichen.
    final ebenen = karte.ebenen;
    for (var nr = 0; nr < ebenen.length; nr++) {
      final da =
          await _ebeneZeichnen(leinwand, ebenen[nr], block, stufe, kante);
      if (da && nr == 0) etwasDa = true;
      if (_geschlossen) break;
    }
    if (karte.hoehenlinien && hoehen != null) {
      _hoehenlinienZeichnen(leinwand, block, kante);
      etwasDa = true;
    }

    final fertig = sammler.endRecording();
    try {
      // **Kommt der Grund nicht an, gibt es gar kein Bild.** Ein Block
      // aus lauter Linien über durchsichtigem Grund sähe aus wie ein
      // Loch in der Landschaft; die Übersichtskarte darunter ist besser.
      if (!etwasDa || _geschlossen) return null;
      return await fertig.toImage(kante, kante);
    } finally {
      fertig.dispose();
    }
  }

  /// Zeichnet eine Ebene über den ganzen Block – und liefert, ob
  /// überhaupt etwas ankam.
  ///
  /// **Eine Ebene kann gröber sein als der Block.** Waymarked Trails hört
  /// bei Stufe 16 auf, weil ein ehrenamtlicher Dienst keine sechzehnfache
  /// Last verdient; der Block darunter kann auf 18 stehen. Dann deckt
  /// **eine** Kachel mehrere Blöcke ab, und dieser hier braucht nur ein
  /// Stück davon. Beide Fälle stehen hier: mehrere Kacheln je Block, oder
  /// ein Ausschnitt aus einer.
  Future<bool> _ebeneZeichnen(ui.Canvas leinwand, Kartenebene ebene,
      Texturblock block, int stufe, int kante) async {
    final z = math.min(stufe, ebene.hoechsteStufe);
    final klient = _netz ??= http.Client();
    final speicher = _speicher ?? gemeinsamerKachelspeicher();

    if (z < block.grundstufe) {
      // Eine Kachel deckt mehrere Blöcke – der Ausschnitt daraus.
      final f = 1 << (block.grundstufe - z);
      final x = block.spalte ~/ f;
      final y = block.zeile ~/ f;
      final bild = await _kachel(klient, speicher, ebene, z, x, y);
      if (bild == null) return false;
      final teil = kachelKante / f;
      leinwand.drawImageRect(
        bild,
        ui.Rect.fromLTWH((block.spalte % f) * teil, (block.zeile % f) * teil,
            teil, teil),
        ui.Rect.fromLTWH(0, 0, kante.toDouble(), kante.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      bild.dispose();
      return true;
    }

    final adressen = block.kacheln(z);
    final n = block.kachelnJeKante(z);
    final bilder = List<ui.Image?>.filled(adressen.length, null);
    var naechste = 0;
    Future<void> arbeiter() async {
      while (true) {
        final i = naechste++;
        if (i >= adressen.length || _geschlossen) return;
        final a = adressen[i];
        bilder[i] = await _kachel(klient, speicher, ebene, a.z, a.x, a.y);
      }
    }

    await Future.wait([
      for (var k = 0; k < gleichzeitig && k < adressen.length; k++) arbeiter(),
    ]);

    var etwas = false;
    final seite = kante / n;
    for (var i = 0; i < adressen.length; i++) {
      final bild = bilder[i];
      if (bild == null) continue;
      etwas = true;
      leinwand.drawImageRect(
        bild,
        ui.Rect.fromLTWH(0, 0, bild.width.toDouble(), bild.height.toDouble()),
        ui.Rect.fromLTWH((i % n) * seite, (i ~/ n) * seite, seite, seite),
        ui.Paint(),
      );
      bild.dispose();
    }
    return etwas;
  }

  Future<ui.Image?> _kachel(http.Client klient, MapCachingProvider speicher,
      Kartenebene ebene, int z, int x, int y) async {
    try {
      final roh = await holeKachelRoh(
        klient,
        speicher,
        kacheladresse(z, x, y, vorlage: ebene.urlVorlage),
        // Die Anbieter bitten ausdrücklich um eine aussagekräftige
        // Kennung statt der Vorgabe der Bibliothek.
        kopf: const {'User-Agent': 'com.example.photoVault'},
      );
      if (roh == null) return null;
      return await _bildAus(roh);
    } catch (_) {
      // Eine einzelne Kachel darf ausfallen, ohne den Block mitzunehmen.
      return null;
    }
  }

  /// Brennt die Höhenlinien in die Blocktextur ein.
  ///
  /// **Beim Aufbau eines Blocks und nicht in jedem Bild.** Sie ändern
  /// sich nie – sie hängen am Gitter, nicht an der Kamera. Als Pfad über
  /// die Landschaft gelegt müssten sie in jedem Bild neu projiziert
  /// werden, und dann läge jede Linie über dem Berg, hinter dem sie
  /// eigentlich verschwindet.
  void _hoehenlinienZeichnen(
      ui.Canvas leinwand, Texturblock block, int kante) {
    final g = hoehen;
    if (g == null) return;
    final spanne = g.spanne;
    zeichneHoehenlinien(
      leinwand,
      hoehenlinien(
        g,
        west: block.west,
        ost: block.ost,
        sued: block.sued,
        nord: block.nord,
        abstand: hoehenlinienAbstand(spanne.hoch - spanne.tief),
        grundstufe: block.grundstufe,
      ),
      kante.toDouble(),
      kante.toDouble(),
    );
  }

  Future<ui.Image> _bildAus(Uint8List roh) async {
    final codec = await ui.instantiateImageCodec(roh);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  /// Gibt alles frei – beim Verlassen des Bildschirms.
  ///
  /// Ohne den Aufruf bliebe der Speicher der Grafikkarte belegt: Achtzig
  /// Megabyte je geöffneter Landschaft.
  void schliessen() {
    _geschlossen = true;
    bilder = const {};
    _vorrat.leeren();
    if (_eigenerKlient) _netz?.close();
    _netz = null;
  }
}
