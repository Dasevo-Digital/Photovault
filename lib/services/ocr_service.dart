import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'onnx_hardswish.dart';
import 'textstellen.dart';
import 'modellthreads.dart';

/// Texterkennung ohne Betriebssystem-Hilfe – zwei ONNX-Modelle aus der
/// PaddleOCR-Familie, dieselbe Zerlegung wie dort: erst finden, dann lesen.
///
/// **Warum überhaupt:** Bisher lief die Texterkennung ausschliesslich über
/// Apples Vision-Framework. Ausserhalb von macOS gab es sie schlicht nicht –
/// keine Textsuche in Fotos (siehe docs/plan_linux.md, Phase 5). Ein Modell
/// statt eines Systempakets passt zur Architektur der übrigen KI-Funktionen:
/// nichts wird mitgeliefert, alles ist nachladbar, und es funktioniert auf
/// jeder Plattform gleich.
///
/// **Warum trotzdem nicht auf macOS:** Vision ist dort besser, kostet keinen
/// Download und ist bereits eingebaut. Zwei Wege sind hier kein Versäumnis,
/// sondern die Entscheidung, auf jeder Plattform das Beste zu nehmen, was
/// sie hat.
///
/// **Die lateinische Zeichentabelle, nicht die chinesische.** Der
/// naheliegende Griff wäre `ch_PP-OCRv4_rec` gewesen – dessen Tabelle kennt
/// aber weder `ö` noch `Ä`, `Ö`, `ß` oder `€` (nachgesehen, nicht vermutet).
/// „Straße" wäre daraus als „Strae" herausgekommen. `latin_PP-OCRv3_rec`
/// deckt alle davon ab.
class OcrService {
  OcrService._(this._erkennung, this._lesung, this._zeichen);

  final OrtSession _erkennung;
  final OrtSession _lesung;

  /// Index 0 ist der CTC-Leerplatz, danach die Tabelle, zuletzt das
  /// Leerzeichen – die Reihenfolge, die PaddleOCR beim Training benutzt.
  final List<String> _zeichen;

  static const erkennungsDatei = 'ocr_det.onnx';
  static const lesungsDatei = 'ocr_rec.onnx';

  /// Die Zeichentabelle steht **in der Konfiguration des Modells**, nicht
  /// in einer eigenen Datei: `latin_PP-OCRv5_mobile_rec` liefert sie als
  /// `character_dict` in `inference.yml` aus, und eine zweite, von Hand
  /// gepflegte Liste daneben waere genau die zweite Wahrheit, die frueher
  /// oder spaeter von der ersten abweicht.
  static const zeichenDatei = 'ocr_rec.yml';

  /// Längste Kante, auf die das Bild für die Erkennung gebracht wird.
  /// Grösser findet mehr kleine Schrift und kostet quadratisch mehr Zeit.
  static const _maxSeite = 960;

  /// Ab welcher Wahrscheinlichkeit ein Pixel als Schrift gilt.
  static const _schwelle = 0.3;

  /// Kleinere Flecken sind Rauschen, keine Schrift.
  static const _minFlaeche = 20;

  /// DBNet lernt eine GESCHRUMPFTE Fläche – der Weg zurück ist
  /// `Fläche * Verhältnis / Umfang`.
  ///
  /// Das ist nicht kosmetisch: Mit einer pauschalen Aufweitung um ein
  /// Viertel der Höhe kamen an einer deutschen Testtafel „Offnungszeiter"
  /// und „Stra3e" heraus – abgeschnittene Umlautpunkte und ein fehlender
  /// letzter Buchstabe. Mit dieser Formel wurde daraus „Straße des 17. Juni
  /// 135", fehlerfrei.
  static const _aufweitung = 1.8;

  /// Obergrenze für die Zahl gelesener Stellen. Das Lesemodell läuft je
  /// Stelle einmal; ein Bild mit hunderten Schnipseln (Laub, Kies) würde
  /// sonst minutenlang beschäftigen, ohne dass Text dabei herauskommt.
  static const _maxStellen = 64;

  /// Höhe, auf die jede gefundene Stelle für das Lesen gebracht wird –
  /// vom Modell fest vorgegeben.
  static const _leseHoehe = 48;

  static bool isAvailable(String modelsDir) => [
    erkennungsDatei,
    lesungsDatei,
    zeichenDatei,
  ].every((n) => File('$modelsDir/$n').existsSync());

  /// Ablage der umgebauten Fassung des Lesemodells – siehe
  /// [lesemodellPfad].
  static const lesungUmgebaut = 'ocr_rec_ohne_hardswish.onnx';

  /// Liefert den Pfad, aus dem das Lesemodell wirklich geladen wird.
  ///
  /// Das heruntergeladene Modell enthält 27 `HardSwish`-Knoten, und die
  /// lieferten im Flutter-Prozess unter deutscher Spracheinstellung
  /// durchweg null (siehe [HardswishUmbau] und `docs/hardswish_fehler/`).
  /// Deshalb wird beim ersten Laden eine umgebaute Fassung daneben
  /// abgelegt, in der jeder dieser Knoten durch `HardSigmoid` und `Mul`
  /// ersetzt ist – rechnerisch dasselbe, nachgemessen bitgleich.
  ///
  /// Seit `flutter_onnxruntime` 1.8.4 ist die Ursache behoben und der
  /// Umbau nicht mehr zwingend. Er bleibt als Absicherung; die Begründung
  /// steht bei [HardswishUmbau].
  ///
  /// **Die heruntergeladene Datei bleibt unangetastet.** Sie ist durch ihre
  /// Prüfsumme gedeckt; die umgebaute Fassung ist eine abgeleitete Kopie
  /// und wird neu erzeugt, sobald das Original neuer ist – etwa nach einem
  /// erneuten Herunterladen.
  @visibleForTesting
  static Future<String> lesemodellPfad(String modelsDir) async {
    final quelle = File('$modelsDir/$lesungsDatei');
    final ziel = File('$modelsDir/$lesungUmgebaut');
    if (await ziel.exists() &&
        !(await ziel.lastModified()).isBefore(await quelle.lastModified())) {
      return ziel.path;
    }

    // Neun Megabyte zerlegen und neu zusammensetzen gehört nicht auf den
    // Faden, der die Oberfläche zeichnet.
    final umgebaut = await compute(_umbauen, await quelle.readAsBytes());
    if (umgebaut == null) {
      // Nichts umzubauen – seit `latin_PP-OCRv5` der Regelfall, das Modell
      // enthält keinen einzigen HardSwish-Knoten mehr (nachgesehen: 27 im
      // alten, 0 im neuen). Eine Fassung aus der Zeit davor liegt dann
      // aber noch da und wird nie wieder geladen; wer sie nicht wegräumt,
      // lässt neun Megabyte für immer liegen.
      if (await ziel.exists()) {
        try {
          await ziel.delete();
        } on FileSystemException catch (e) {
          debugPrint('Alte Umbau-Fassung blieb liegen: ${ziel.path}: $e');
        }
      }
      return quelle.path;
    }

    // Über eine Zwischendatei, damit ein Abbruch mittendrin kein halbes
    // Modell hinterlässt, das beim nächsten Start geladen würde.
    final zwischen = File('${ziel.path}.neu');
    await zwischen.writeAsBytes(umgebaut, flush: true);
    await zwischen.rename(ziel.path);
    return ziel.path;
  }

  /// Liest die Zeichentabelle aus der Modellkonfiguration.
  ///
  /// Ein enger Leser fuer genau die eine Stelle, die gebraucht wird - kein
  /// YAML-Verstaendnis. Gesucht wird der Block `character_dict:`, und
  /// danach jede Zeile der Form `  - X`, bis eine andere kommt.
  ///
  /// **Anfuehrungszeichen gehoeren dazu.** PaddleOCR quotiert die Zeichen,
  /// die YAML sonst missverstuende - Ziffern und Satzzeichen, 31 von 836
  /// in der lateinischen Tabelle. Ohne dieses Auspacken stuenden die
  /// Ziffern als DREI Zeichen in der Tabelle, alle Folgeindizes
  /// verschoeben sich, und das Modell laese durchweg Unsinn. Zwei
  /// Apostrophe hintereinander sind YAMLs Schreibweise fuer einen.
  ///
  /// Die Reihenfolge IST der Inhalt: Sie ordnet Klassennummern Zeichen zu.
  /// Leere Eintraege werden deshalb nicht uebersprungen - ein
  /// ausgelassener verschoebe alles dahinter.
  @visibleForTesting
  static List<String> zeichenAusKonfig(String inhalt) {
    final zeilen = const LineSplitter().convert(inhalt);
    final start = zeilen.indexWhere(
      (z) => z.trimRight() == '  character_dict:',
    );
    if (start < 0) return const [];
    final tabelle = <String>[];
    for (final zeile in zeilen.skip(start + 1)) {
      if (!zeile.startsWith('  - ')) break;
      var wert = zeile.substring(4).trimRight();
      if (wert.length >= 2 && wert.startsWith("'") && wert.endsWith("'")) {
        wert = wert.substring(1, wert.length - 1).replaceAll("''", "'");
      }
      tabelle.add(wert);
    }
    return tabelle;
  }

  static Future<OcrService> load(String modelsDir) async {
    final ort = OnnxRuntime();
    final erkennung = await ort.createSession(
      '$modelsDir/$erkennungsDatei',
      options: modelloptionen(),
    );
    final lesung = await ort.createSession(
      await lesemodellPfad(modelsDir),
      options: modelloptionen(),
    );
    final tabelle = zeichenAusKonfig(
      await File('$modelsDir/$zeichenDatei').readAsString(encoding: utf8),
    );
    // Leerplatz vorn, Leerzeichen hinten – genau so zählt PaddleOCR.
    return OcrService._(erkennung, lesung, ['', ...tabelle, ' ']);
  }

  Future<void> dispose() async {
    await _erkennung.close();
    await _lesung.close();
  }

  /// Liest den Text aus [bild]. Kein gefundener Text ergibt einen leeren
  /// String – das ist ein Ergebnis, kein Fehler.
  ///
  /// Wirft [LesungLiefertNichts], wenn Stellen mit Schrift gefunden wurden,
  /// aber KEINE einzige davon ein Zeichen ergab. Das ist kein „hier steht
  /// nichts", sondern das Bild eines kaputten Lesemodells – und es darf
  /// nicht als leeres Ergebnis in die Datenbank wandern. Täte es das,
  /// würden die Fotos als durchsucht vermerkt und nach einer Reparatur nie
  /// wieder angefasst.
  ///
  /// Genau dieser Zustand trat unter Linux auf, bis der `HardSwish`-Umbau
  /// ihn behob (siehe [lesemodellPfad] – dort steht auch, warum). Die
  /// Sicherung bleibt trotzdem: Sie kostet nichts und fängt den nächsten
  /// Fall dieser Art ebenso ab. Wie berechtigt das ist, hat sich gezeigt –
  /// die Ursache lag nicht dort, wo alle Messungen sie vermutet hatten,
  /// sondern in einer Textumwandlung unter deutscher Spracheinstellung.
  Future<String> erkenneText(img.Image bild) async =>
      textAusStellen(await erkenne(bild));

  /// Wie [erkenneText], aber mit dem Platz jeder Zeile im Bild.
  ///
  /// Die Kästen fielen bei der Erkennung immer schon an – bis Schema 60
  /// wurden sie nur weggeworfen. In Anteilen der Bildkante, nicht in Pixeln;
  /// warum, steht bei [Textstelle].
  Future<List<Textstelle>> erkenne(img.Image bild) async {
    final stellen = await _findeStellen(bild);
    if (stellen.isEmpty) return const [];

    final gelesen = <Textstelle>[];
    for (final stelle in stellen) {
      final text = await _liesStelle(bild, stelle);
      if (text.isEmpty) continue;
      gelesen.add(
        Textstelle(
          text: text,
          links: stelle.links(bild.width) / bild.width,
          oben: stelle.oben(bild.height) / bild.height,
          breite:
              (stelle.rechts(bild.width) - stelle.links(bild.width) + 1) /
              bild.width,
          hoehe:
              (stelle.unten(bild.height) - stelle.oben(bild.height) + 1) /
              bild.height,
        ),
      );
    }
    if (gelesen.isEmpty) throw LesungLiefertNichts(stellen.length);
    return gelesen;
  }

  /// Sucht die Stellen mit Schrift und gibt sie in Lesereihenfolge zurück.
  Future<List<OcrStelle>> _findeStellen(img.Image bild) async {
    final faktor = math.min(_maxSeite / math.max(bild.width, bild.height), 1.0);
    // Beide Kanten auf ein Vielfaches von 32 – das Netz faltet fünfmal um
    // den Faktor zwei; eine krumme Kante ergäbe eine krumme Ausgabekarte.
    final nw = math.max(32, ((bild.width * faktor) / 32).round() * 32);
    final nh = math.max(32, ((bild.height * faktor) / 32).round() * 32);
    final klein = img.copyResize(
      bild,
      width: nw,
      height: nh,
      interpolation: img.Interpolation.linear,
    );

    final eingabe = Float32List(3 * nh * nw);
    const mittel = [0.485, 0.456, 0.406];
    const streuung = [0.229, 0.224, 0.225];
    var i = 0;
    for (var kanal = 0; kanal < 3; kanal++) {
      for (var y = 0; y < nh; y++) {
        for (var x = 0; x < nw; x++) {
          final px = klein.getPixel(x, y);
          final wert = (kanal == 0 ? px.r : (kanal == 1 ? px.g : px.b)) / 255.0;
          eingabe[i++] = (wert - mittel[kanal]) / streuung[kanal];
        }
      }
    }

    final tensor = await OrtValue.fromList(eingabe, [1, 3, nh, nw]);
    List<double> karte;
    // Auch die Ausgaben gehören ins finally, nicht in den try-Rumpf: Wirft
    // asFlattenedList(), blieben sie sonst liegen (Prüfrunde 12).
    Map<String, OrtValue>? aus;
    try {
      aus = await _erkennung.run({_erkennung.inputNames.first: tensor});
      final roh = await aus.values.first.asFlattenedList();
      karte = roh.cast<num>().map((e) => e.toDouble()).toList();
    } finally {
      await tensor.dispose();
      for (final v in aus?.values ?? const <OrtValue>[]) {
        await v.dispose();
      }
    }

    final roh = _zusammenhaengendeFlecken(karte, nw, nh);
    final flecken = fuegeZeilenZusammen(roh, nw);
    // Zurück auf die Maße des Originals.
    final sx = bild.width / nw, sy = bild.height / nh;
    final stellen = [
      for (final f in flecken) stelleAusFleck(f, nw, sx, sy, _aufweitung),
    ];
    // Von oben nach unten, dann von links nach rechts – Lesereihenfolge.
    final w = bild.width, h = bild.height;
    stellen.sort(
      (a, b) => a.oben(h) != b.oben(h)
          ? a.oben(h) - b.oben(h)
          : a.links(w) - b.links(w),
    );
    if (stellen.length <= _maxStellen) return stellen;
    // Zu viele: die grössten behalten, das ist der Text und nicht das Laub.
    final nachGroesse = [...stellen]
      ..sort((a, b) => b.flaeche.compareTo(a.flaeche));
    final behalten = nachGroesse.take(_maxStellen).toSet();
    return stellen.where(behalten.contains).toList();
  }

  /// Zusammenhangskomponenten über die Wahrscheinlichkeitskarte – je
  /// Fleck die Indizes seiner Punkte in der Karte. Die Lage der Zeile
  /// bestimmt danach [stelleAusFleck].
  List<Int32List> _zusammenhaengendeFlecken(
    List<double> karte,
    int breite,
    int hoehe,
  ) {
    final gesehen = Uint8List(breite * hoehe);
    final flecken = <Int32List>[];
    final schlange = Queue<int>();

    for (var start = 0; start < karte.length; start++) {
      if (gesehen[start] == 1 || karte[start] <= _schwelle) continue;
      gesehen[start] = 1;
      schlange.add(start);
      final punkte = <int>[];

      while (schlange.isNotEmpty) {
        final p = schlange.removeFirst();
        punkte.add(p);
        final x = p % breite, y = p ~/ breite;
        for (final n in [
          if (x > 0) p - 1,
          if (x < breite - 1) p + 1,
          if (y > 0) p - breite,
          if (y < hoehe - 1) p + breite,
        ]) {
          if (gesehen[n] == 0 && karte[n] > _schwelle) {
            gesehen[n] = 1;
            schlange.add(n);
          }
        }
      }
      if (punkte.length >= _minFlaeche) flecken.add(Int32List.fromList(punkte));
    }
    return flecken;
  }

  /// Breite, auf die eine Stelle für das Lesen gebracht wird.
  ///
  /// Auf ein Vielfaches von acht aufgerundet. PaddleOCR füllt die Breite
  /// ohnehin auf eine feste Grösse auf; hier genügt die Rundung, und sie
  /// hält die Zeilen der Eingabe ausgerichtet.
  static int _lesebreite(int w, int h) {
    final roh = math.max(16, math.min(1000, (_leseHoehe * w / h).round()));
    return ((roh + 7) ~/ 8) * 8;
  }

  /// Liest eine einzelne Stelle.
  Future<String> _liesStelle(img.Image bild, OcrStelle s) async {
    final w = s.laenge.round(), h = s.hoehe.round();
    if (w < 4 || h < 4) return '';

    final zielBreite = _lesebreite(w, h);
    final skaliert = richteStelleAus(bild, s, zielBreite, _leseHoehe);

    final eingabe = Float32List(3 * _leseHoehe * zielBreite);
    var i = 0;
    for (var kanal = 0; kanal < 3; kanal++) {
      for (var y = 0; y < _leseHoehe; y++) {
        for (var x = 0; x < zielBreite; x++) {
          final px = skaliert.getPixel(x, y);
          final wert = (kanal == 0 ? px.r : (kanal == 1 ? px.g : px.b)) / 255.0;
          // Andere Normierung als bei der Erkennung – hier auf -1..1.
          eingabe[i++] = (wert - 0.5) / 0.5;
        }
      }
    }

    final tensor = await OrtValue.fromList(eingabe, [
      1,
      3,
      _leseHoehe,
      zielBreite,
    ]);
    Map<String, OrtValue>? aus;
    try {
      aus = await _lesung.run({_lesung.inputNames.first: tensor});
      final wert = aus.values.first;
      final form = wert.shape;
      final roh = (await wert.asFlattenedList()).cast<num>();
      // [1, Schritte, Klassen]
      final schritte = form.length >= 2 ? form[form.length - 2] : 0;
      final klassen = form.isNotEmpty ? form.last : 0;
      return _ctcEntschluesseln(roh, schritte, klassen);
    } catch (e) {
      debugPrint('Texterkennung: Lesen einer Stelle fehlgeschlagen: $e');
      return '';
    } finally {
      await tensor.dispose();
      for (final v in aus?.values ?? const <OrtValue>[]) {
        await v.dispose();
      }
    }
  }

  /// CTC-Entschlüsselung: je Schritt die wahrscheinlichste Klasse,
  /// Wiederholungen zusammenziehen, den Leerplatz (Index 0) weglassen.
  String _ctcEntschluesseln(List<num> werte, int schritte, int klassen) {
    if (schritte <= 0 || klassen <= 0) return '';
    final puffer = StringBuffer();
    var vorher = -1;
    for (var t = 0; t < schritte; t++) {
      var beste = 0;
      var bester = double.negativeInfinity;
      for (var k = 0; k < klassen; k++) {
        final v = werte[t * klassen + k].toDouble();
        if (v > bester) {
          bester = v;
          beste = k;
        }
      }
      if (beste != 0 && beste != vorher && beste < _zeichen.length) {
        puffer.write(_zeichen[beste]);
      }
      vorher = beste;
    }
    return puffer.toString().trim();
  }
}

/// Eine gefundene Textzeile im Original: ein Rechteck, das so gedreht ist
/// wie die Zeile.
///
/// [ox]/[oy] ist die Ecke oben links. [ux]/[uy] führt von dort an der
/// Zeile entlang zur Ecke oben rechts, [vx]/[vy] quer dazu zur Ecke unten
/// links.
@visibleForTesting
class OcrStelle {
  final double ox, oy, ux, uy, vx, vy;
  const OcrStelle(this.ox, this.oy, this.ux, this.uy, this.vx, this.vy);

  double get laenge => math.sqrt(ux * ux + uy * uy);
  double get hoehe => math.sqrt(vx * vx + vy * vy);

  /// Neigung der Zeile in Grad, im Uhrzeigersinn positiv.
  double get neigung => math.atan2(uy, ux) * 180 / math.pi;

  Iterable<double> get _xs => [ox, ox + ux, ox + vx, ox + ux + vx];
  Iterable<double> get _ys => [oy, oy + uy, oy + vy, oy + uy + vy];

  // Der umschliessende achsenparallele Kasten, auf das Bild begrenzt –
  // zum Sortieren und für die gespeicherten Textstellen.
  int links(int breite) => _xs.reduce(math.min).floor().clamp(0, breite - 1);
  int rechts(int breite) =>
      (_xs.reduce(math.max).ceil() - 1).clamp(0, breite - 1);
  int oben(int hoehe) => _ys.reduce(math.min).floor().clamp(0, hoehe - 1);
  int unten(int hoehe) => (_ys.reduce(math.max).ceil() - 1).clamp(0, hoehe - 1);

  int get flaeche => (laenge * hoehe).round();
}

/// Mitte, Richtung und Ausdehnung eines Flecks in der Karte, noch ohne
/// Aufweitung: [ux]/[uy] längs der Zeile, [vx]/[vy] quer dazu, die
/// Ausdehnung als Abstand von der Mitte.
class _Lage {
  final double mx, my, ux, uy, uMin, uMax, vMin, vMax;
  const _Lage(
    this.mx,
    this.my,
    this.ux,
    this.uy,
    this.uMin,
    this.uMax,
    this.vMin,
    this.vMax,
  );

  double get vx => -uy;
  double get vy => ux;
  double get laenge => uMax - uMin;
  double get hoehe => vMax - vMin;

  // Mitte des Kastens – nicht der Schwerpunkt, der bei einem Fleck mit
  // Unterlängen tiefer liegt.
  double get cx => mx + (uMin + uMax) / 2 * ux + (vMin + vMax) / 2 * vx;
  double get cy => my + (uMin + uMax) / 2 * uy + (vMin + vMax) / 2 * vy;

  factory _Lage.aus(Int32List punkte, int kartenBreite) {
    final n = punkte.length;
    var mx = 0.0, my = 0.0;
    for (final p in punkte) {
      mx += p % kartenBreite + 0.5;
      my += p ~/ kartenBreite + 0.5;
    }
    mx /= n;
    my /= n;
    var cxx = 0.0, cyy = 0.0, cxy = 0.0;
    for (final p in punkte) {
      final dx = p % kartenBreite + 0.5 - mx, dy = p ~/ kartenBreite + 0.5 - my;
      cxx += dx * dx;
      cyy += dy * dy;
      cxy += dx * dy;
    }
    var winkel = 0.5 * math.atan2(2 * cxy, cxx - cyy);
    final mitte = (cxx + cyy) / 2;
    final abstand = math.sqrt((cxx - cyy) * (cxx - cyy) / 4 + cxy * cxy);
    final lang = mitte + abstand, kurz = mitte - abstand;
    // Längs mindestens doppelt so weit gestreut wie quer, sonst keine Richtung.
    if (winkel.abs() > math.pi / 4 || lang < 4 * kurz || winkel.abs() < 0.005) {
      winkel = 0;
    }
    final ux = math.cos(winkel), uy = math.sin(winkel);
    final vx = -uy, vy = ux;

    var uMin = double.infinity, uMax = double.negativeInfinity;
    var vMin = double.infinity, vMax = double.negativeInfinity;
    for (final p in punkte) {
      final dx = p % kartenBreite + 0.5 - mx, dy = p ~/ kartenBreite + 0.5 - my;
      final u = dx * ux + dy * uy, v = dx * vx + dy * vy;
      if (u < uMin) uMin = u;
      if (u > uMax) uMax = u;
      if (v < vMin) vMin = v;
      if (v > vMax) vMax = v;
    }
    // Ein Punkt der Karte ist ein Quadrat, nicht seine Mitte.
    uMin -= 0.5;
    uMax += 0.5;
    vMin -= 0.5;
    vMax += 0.5;
    return _Lage(mx, my, ux, uy, uMin, uMax, vMin, vMax);
  }
}

/// Vereint Flecken, die Stücke derselben Zeile sind.
///
/// Die Erkennung trennt eine Zeile, wo die Lücke breit ist – zwischen den
/// Zifferngruppen einer Kartennummer etwa. Jedes Stück für sich gelesen,
/// fehlt danach der Zusammenhang, und weil beide Stücke aufgeweitet
/// werden, liest das linke die erste Ziffer des rechten mit: aus
/// „4111 1111 1111 1111“ wurden „4111 1111 1111 1“ und „1111“.
///
/// Zusammen gehören zwei Flecken, wenn sie gleich hoch sind, auf derselben
/// Linie liegen (gemessen in der Richtung des längeren) und die Lücke
/// zwischen ihnen höchstens [_zeilenluecke] Zeilenhöhen beträgt.
@visibleForTesting
List<Int32List> fuegeZeilenZusammen(List<Int32List> flecken, int kartenBreite) {
  if (flecken.length < 2) return flecken;
  final lagen = [for (final f in flecken) _Lage.aus(f, kartenBreite)];
  final eltern = List<int>.generate(flecken.length, (i) => i);
  int wurzel(int i) {
    while (eltern[i] != i) {
      eltern[i] = eltern[eltern[i]];
      i = eltern[i];
    }
    return i;
  }

  for (var i = 0; i < lagen.length; i++) {
    for (var j = i + 1; j < lagen.length; j++) {
      if (_selbeZeile(lagen[i], lagen[j])) eltern[wurzel(j)] = wurzel(i);
    }
  }
  final gruppen = <int, List<int>>{};
  for (var i = 0; i < flecken.length; i++) {
    (gruppen[wurzel(i)] ??= []).add(i);
  }
  return [
    for (final g in gruppen.values)
      g.length == 1
          ? flecken[g.single]
          : Int32List.fromList([for (final i in g) ...flecken[i]]),
  ];
}

/// Höchstens so viele Zeilenhöhen Lücke, und zwei Stücke gelten als eine
/// Zeile.
const _zeilenluecke = 1.5;

bool _selbeZeile(_Lage a, _Lage b) {
  final r = a.laenge >= b.laenge ? a : b;
  final hoch = math.max(a.hoehe, b.hoehe), flach = math.min(a.hoehe, b.hoehe);
  if (hoch > 1.6 * flach) return false;
  final dx = b.cx - a.cx, dy = b.cy - a.cy;
  if ((dx * r.vx + dy * r.vy).abs() > 0.4 * hoch) return false;
  final luecke = (dx * r.ux + dy * r.uy).abs() - (a.laenge + b.laenge) / 2;
  return luecke <= _zeilenluecke * hoch;
}

/// Die Lage einer Zeile aus ihrem Fleck in der Wahrscheinlichkeitskarte:
/// [punkte] sind Indizes in einer Karte der Breite [kartenBreite], [sx] und
/// [sy] der Weg zurück auf das Original.
///
/// **Gedreht, nicht achsenparallel.** Ein achsenparalleler Kasten um eine
/// um 2,5° geneigte, 1900 Pixel lange Zeile ist 80 Pixel höher als die
/// Schrift und schneidet Teile der Nachbarzeilen mit; aus der
/// maschinenlesbaren Zone eines Ausweises wurde so „IDD<2000293“ statt
/// „IDD<<T220001293<<<…“, aus einem Plakat „DER 34 04 052“. PaddleOCR
/// selbst nimmt das kleinste gedrehte Rechteck; hier gibt die Hauptachse
/// des Flecks die Richtung, das genügt für Zeilen.
///
/// Die Richtung gilt nur, wo sie verlässlich ist: Ein fast runder Fleck
/// (ein einzelnes Zeichen, ein kurzes Wort) hat keine, und steiler als 45°
/// steht keine waagerechte Zeile – beides bleibt achsenparallel wie
/// bisher. Aufgeweitet wird wie in DBNet um `Fläche · [aufweitung] /
/// Umfang`.
@visibleForTesting
OcrStelle stelleAusFleck(
  Int32List punkte,
  int kartenBreite,
  double sx,
  double sy,
  double aufweitung,
) {
  final lage = _Lage.aus(punkte, kartenBreite);
  final mx = lage.mx, my = lage.my, ux = lage.ux, uy = lage.uy;
  final vx = lage.vx, vy = lage.vy;
  var uMin = lage.uMin, uMax = lage.uMax;
  var vMin = lage.vMin, vMax = lage.vMax;
  final w = uMax - uMin, h = vMax - vMin;
  final d = w * h * aufweitung / (2 * (w + h));
  uMin -= d;
  uMax += d;
  vMin -= d;
  vMax += d;

  // Ecken in der Karte, dann aufs Original.
  final ex = mx + uMin * ux + vMin * vx, ey = my + uMin * uy + vMin * vy;
  final l = uMax - uMin, q = vMax - vMin;
  return OcrStelle(
    ex * sx,
    ey * sy,
    l * ux * sx,
    l * uy * sy,
    q * vx * sx,
    q * vy * sy,
  );
}

/// Schneidet [s] aus [bild] und bringt es auf [breite] × [hoehe], die
/// Zeile waagerecht. Ausserhalb des Bildes gilt der Rand.
@visibleForTesting
img.Image richteStelleAus(img.Image bild, OcrStelle s, int breite, int hoehe) {
  final ziel = img.Image(width: breite, height: hoehe);
  final maxX = bild.width - 1, maxY = bild.height - 1;
  for (var y = 0; y < hoehe; y++) {
    final fy = (y + 0.5) / hoehe;
    for (var x = 0; x < breite; x++) {
      final fx = (x + 0.5) / breite;
      // Mitte des Zielpunkts im Original, in Pixelmitten gerechnet.
      final px = (s.ox + fx * s.ux + fy * s.vx - 0.5).clamp(0.0, maxX * 1.0);
      final py = (s.oy + fx * s.uy + fy * s.vy - 0.5).clamp(0.0, maxY * 1.0);
      final x0 = px.floor(), y0 = py.floor();
      final x1 = math.min(x0 + 1, maxX), y1 = math.min(y0 + 1, maxY);
      final ax = px - x0, ay = py - y0;
      final a = bild.getPixel(x0, y0), b = bild.getPixel(x1, y0);
      final c = bild.getPixel(x0, y1), e = bild.getPixel(x1, y1);
      num misch(num p, num q, num r, num t) =>
          (p * (1 - ax) + q * ax) * (1 - ay) + (r * (1 - ax) + t * ax) * ay;
      ziel.setPixelRgb(
        x,
        y,
        (misch(a.rNormalized, b.rNormalized, c.rNormalized, e.rNormalized) *
                255)
            .round(),
        (misch(a.gNormalized, b.gNormalized, c.gNormalized, e.gNormalized) *
                255)
            .round(),
        (misch(a.bNormalized, b.bNormalized, c.bNormalized, e.bNormalized) *
                255)
            .round(),
      );
    }
  }
  return ziel;
}

/// Es wurde Schrift gefunden, aber keine einzige Stelle liess sich lesen.
///
/// Ein eigener Typ statt eines leeren Ergebnisses: Beides sähe in der
/// Datenbank gleich aus, ist aber grundverschieden. „Kein Text im Bild" ist
/// ein Ergebnis; „ich sehe Text, kann ihn aber nicht lesen" ist ein Defekt,
/// und die betroffenen Fotos müssen erneut drankommen, sobald er behoben
/// ist.
class LesungLiefertNichts implements Exception {
  /// Wie viele Stellen mit Schrift gefunden wurden – fürs Protokoll.
  ///
  /// Ohne eigenes `toString()`: Ein deutscher Satz an dieser Stelle wäre ein
  /// fester Text im Dienst, und die Aufrufstelle formuliert ohnehin selbst
  /// (siehe LibraryState.backfillOcrText).
  final int stellen;
  const LesungLiefertNichts(this.stellen);
}

/// Läuft in einem eigenen Isolat. `null` heisst: nichts zu tun oder die
/// Datei ist nicht deutbar – dann bleibt es beim Original.
Uint8List? _umbauen(Uint8List roh) {
  try {
    final neu = HardswishUmbau.schreibeUm(roh);
    return identical(neu, roh) ? null : neu;
  } on OnnxNichtLesbar {
    return null;
  }
}
