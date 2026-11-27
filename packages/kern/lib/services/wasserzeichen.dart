/// Wasserzeichen (#497): ein Bild – ein Logo oder ein gezeichneter Text –,
/// das beim Export, im Fotobuch und in den Bildern geteilter Links in das
/// Foto eingerechnet wird.
///
/// **Eine Rechnung für alle drei Wege.** Die Einstellungen ([Wasserzeichen])
/// und das Einrechnen ([rechneWasserzeichenEin]) stehen hier im Kern, ohne
/// Flutter: Die App ruft sie beim Export und im Fotobuch in einem Isolate
/// auf, der Server für die Bilder der Gäste. So sitzt ein Wasserzeichen
/// unten rechts überall an derselben Stelle und in derselben Grösse.
///
/// **Text wird nicht hier gezeichnet.** Das Bildpaket kennt nur
/// Bitmap-Schriften (Arial in 14, 24 und 48 Punkt); vergrössert auf ein
/// Wasserzeichen in einem 2560 Pixel breiten Bild wären die Buchstaben
/// treppig und unscharf, und Zeichen ausserhalb von Latin-1 („ł“, „€“ in
/// manchen Fassungen, jede Schrift ausser Latein) fehlten ganz. Einen Text
/// zeichnet deshalb das Gerät, das ihn kennt – am Rechner und am Telefon
/// über dart:ui (`zierbild/wasserzeichen_text.dart`), im Browser über ein
/// Canvas – zu einem PNG mit Transparenz. Hier kommt nur noch ein Bild an.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import 'jpeg_icc.dart';

/// Die neun Ankerpunkte. [x] und [y] sagen, wo das Zeichen im freien Platz
/// innerhalb der Ränder steht: 0 links bzw. oben, 1 rechts bzw. unten.
enum Wasserzeichenlage {
  obenLinks(0, 0),
  oben(0.5, 0),
  obenRechts(1, 0),
  links(0, 0.5),
  mitte(0.5, 0.5),
  rechts(1, 0.5),
  untenLinks(0, 1),
  unten(0.5, 1),
  untenRechts(1, 1);

  const Wasserzeichenlage(this.x, this.y);
  final double x;
  final double y;
}

/// Was eingerechnet wird: ein Text (vom Gerät gezeichnet) oder ein Logo.
enum Wasserzeichenart { text, bild }

/// Die Einstellungen eines Wasserzeichens – gespeichert als JSON in der
/// Exportvorgabe (`export_presets.wasserzeichen`, seit Schema 104) und in
/// einer Freigabe des Servers (`freigaben.wasserzeichen`).
///
/// Alle Längen sind **Anteile der Bildbreite**, nicht Pixel: Dieselbe
/// Vorgabe soll an einem Bild für die E-Mail (1024 px) genauso aussehen wie
/// an einem in voller Auflösung, und ein Link liefert dasselbe Foto in zwei
/// Grössen aus (Miniatur und Ansicht).
class Wasserzeichen {
  const Wasserzeichen({
    this.art = Wasserzeichenart.text,
    this.text = '',
    this.bild,
    this.lage = Wasserzeichenlage.untenRechts,
    this.groesse = vorgabeGroesse,
    this.deckkraft = vorgabeDeckkraft,
    this.rand = vorgabeRand,
  });

  final Wasserzeichenart art;

  /// Der Text bei [Wasserzeichenart.text]. Bei einem Link steht er nur zur
  /// Anzeige daneben; eingerechnet wird [bild].
  final String text;

  /// Ein PNG mit Transparenz: bei [Wasserzeichenart.bild] das Logo, bei
  /// einem Link auch das am Gerät gezeichnete Textbild. Eine Exportvorgabe
  /// mit Text trägt keines – der Text wird beim Export in genau der Grösse
  /// gezeichnet, die das Bild braucht, und bleibt so scharf.
  final Uint8List? bild;

  final Wasserzeichenlage lage;

  /// Breite des Zeichens als Anteil der Bildbreite. Ist das Zeichen so
  /// hoch, dass es nicht ins Bild passte, wird es kleiner – nie
  /// beschnitten (siehe [wasserzeichenRechteck]).
  final double groesse;

  /// 0 unsichtbar … 1 deckend.
  final double deckkraft;

  /// Abstand zum Bildrand als Anteil der Bildbreite, waagerecht und
  /// senkrecht gleich viele Pixel.
  final double rand;

  static const vorgabeGroesse = 0.2;
  static const vorgabeDeckkraft = 0.6;
  static const vorgabeRand = 0.03;

  static const groesseMin = 0.03;
  static const groesseMax = 0.6;
  static const deckkraftMin = 0.1;
  static const deckkraftMax = 1.0;
  static const randMin = 0.0;
  static const randMax = 0.15;

  /// Höchstens so viele Zeichen Text – ein Wasserzeichen ist eine Zeile.
  static const hoechstensText = 120;

  /// Grenzen für [bild]. Ein Logo wird beim Wählen auf
  /// [Wasserzeichenbild.hoechstensKante] verkleinert; die Grenzen hier
  /// gelten für alles, was von aussen kommt (der Server prüft damit, was
  /// ein Link mitbringt), und halten Bomben ab: Ein PNG mit 60000 × 60000
  /// Pixeln ist wenige Kilobyte gross und dekodiert zu 14 Gigabyte.
  static const hoechstensBildBytes = 2 * 1024 * 1024;
  static const hoechstensBildKante = 4096;

  /// Ob sich damit etwas einrechnen lässt: ein Text, der nicht leer ist,
  /// oder ein Logo.
  bool get vollstaendig => switch (art) {
    Wasserzeichenart.text => text.trim().isNotEmpty,
    Wasserzeichenart.bild => bild != null,
  };

  Wasserzeichen kopieMit({
    Wasserzeichenart? art,
    String? text,
    Uint8List? bild,
    bool ohneBild = false,
    Wasserzeichenlage? lage,
    double? groesse,
    double? deckkraft,
    double? rand,
  }) => Wasserzeichen(
    art: art ?? this.art,
    text: text ?? this.text,
    bild: ohneBild ? null : (bild ?? this.bild),
    lage: lage ?? this.lage,
    groesse: groesse ?? this.groesse,
    deckkraft: deckkraft ?? this.deckkraft,
    rand: rand ?? this.rand,
  );

  Map<String, Object?> alsJson() => {
    'art': art.name,
    if (text.isNotEmpty) 'text': text,
    if (bild case final b?) 'bild': base64Encode(b),
    'lage': lage.name,
    'groesse': groesse,
    'deckkraft': deckkraft,
    'rand': rand,
  };

  String kodiert() => jsonEncode(alsJson());

  /// Liest [json] nachsichtig: Fehlt ein Wert oder liegt er ausserhalb der
  /// Grenzen, gilt die Vorgabe bzw. die nächste Grenze. `null` nur, wenn
  /// [json] gar keines ist oder nichts Einrechenbares beschreibt – dann
  /// gibt es eben kein Wasserzeichen, wie bei einer Vorgabe von vor
  /// Schema 104.
  static Wasserzeichen? ausJson(Object? json) {
    if (json is! Map) return null;
    final art = Wasserzeichenart.values.asNameMap()[json['art']];
    if (art == null) return null;
    Uint8List? bild;
    if (json['bild'] case final String b) {
      try {
        bild = base64Decode(b);
      } on FormatException {
        return null;
      }
    }
    double zahl(String feld, double vorgabe, double min, double max) =>
        switch (json[feld]) {
          final num n when n.isFinite => n.toDouble().clamp(min, max),
          _ => vorgabe,
        };
    final text = json['text'] is String ? json['text'] as String : '';
    final w = Wasserzeichen(
      art: art,
      text: text.length > hoechstensText
          ? text.substring(0, hoechstensText)
          : text,
      bild: bild,
      lage:
          Wasserzeichenlage.values.asNameMap()[json['lage']] ??
          Wasserzeichenlage.untenRechts,
      groesse: zahl('groesse', vorgabeGroesse, groesseMin, groesseMax),
      deckkraft: zahl(
        'deckkraft',
        vorgabeDeckkraft,
        deckkraftMin,
        deckkraftMax,
      ),
      rand: zahl('rand', vorgabeRand, randMin, randMax),
    );
    return w.vollstaendig || bild != null ? w : null;
  }

  /// [ausJson] aus dem gespeicherten Text; `null` bei `null` und bei
  /// allem, was sich nicht lesen lässt.
  static Wasserzeichen? ausKodiert(String? kodiert) {
    if (kodiert == null || kodiert.isEmpty) return null;
    try {
      return ausJson(jsonDecode(kodiert));
    } on FormatException {
      return null;
    }
  }

  /// Zwölf Zeichen, die sich ändern, sobald sich am Ergebnis etwas ändert –
  /// für die Namen zwischengespeicherter Bilder (der Server legt die
  /// Fassungen eines Links mit Wasserzeichen unter `<id>-a-<kennung>.jpg`
  /// ab, damit zwei Links mit verschiedenen Zeichen sich nicht gegenseitig
  /// ihre Bilder überschreiben).
  String get kennung =>
      sha256.convert(utf8.encode(kodiert())).toString().substring(0, 12);
}

/// Wo das Zeichen im Bild steht, in Pixeln – `null`, wenn dafür kein
/// Pixel übrig bleibt (ein winziges Bild, ein leeres Zeichen).
///
/// Die Breite ist [Wasserzeichen.groesse] mal Bildbreite, die Höhe folgt
/// dem Seitenverhältnis des Zeichens. Passt das nicht zwischen die Ränder
/// – ein hohes Logo auf einem Querformat, ein breites auf einem schmalen
/// Hochformat –, wird es im Ganzen kleiner: Abgeschnitten wäre ein Logo
/// kein Logo mehr.
///
/// Der Rand ist höchstens ein Viertel der kürzeren Seite, damit an einem
/// sehr kleinen oder sehr gestreckten Bild noch Platz für das Zeichen
/// bleibt.
({int x, int y, int breite, int hoehe})? wasserzeichenRechteck({
  required int bildBreite,
  required int bildHoehe,
  required int zeichenBreite,
  required int zeichenHoehe,
  required Wasserzeichen wasserzeichen,
}) {
  if (bildBreite <= 0 ||
      bildHoehe <= 0 ||
      zeichenBreite <= 0 ||
      zeichenHoehe <= 0) {
    return null;
  }
  final w = wasserzeichen;
  final rand = math.min(
    (w.rand.clamp(Wasserzeichen.randMin, Wasserzeichen.randMax) * bildBreite)
        .round(),
    math.min(bildBreite, bildHoehe) ~/ 4,
  );
  final platzBreite = bildBreite - 2 * rand;
  final platzHoehe = bildHoehe - 2 * rand;
  var breite =
      w.groesse.clamp(Wasserzeichen.groesseMin, Wasserzeichen.groesseMax) *
      bildBreite;
  var hoehe = breite * zeichenHoehe / zeichenBreite;
  final passt = math.min(
    1.0,
    math.min(platzBreite / breite, platzHoehe / hoehe),
  );
  breite *= passt;
  hoehe *= passt;
  final b = math.min(platzBreite, breite.round());
  final h = math.min(platzHoehe, hoehe.round());
  if (b < 1 || h < 1) return null;
  return (
    x: rand + ((platzBreite - b) * w.lage.x).round(),
    y: rand + ((platzHoehe - h) * w.lage.y).round(),
    breite: b,
    hoehe: h,
  );
}

/// Rechnet [zeichen] nach [wasserzeichen] in [bild] ein und gibt das
/// Ergebnis zurück – [bild] selbst, verändert, ausser es hatte eine
/// Farbpalette (dann eine Kopie ohne).
///
/// **Vormultipliziert skaliert.** Ein PNG speichert die Farbe auch dort,
/// wo es ganz durchsichtig ist, meist als Schwarz. Beim Verkleinern
/// mischte sich dieses unsichtbare Schwarz in die Kanten, und um ein
/// weisses Logo läge ein grauer Saum. Deshalb wird jede Farbe vorher mit
/// ihrer Deckung multipliziert, so skaliert und so eingerechnet
/// („über“-Mischung: Bild × (1 − α·d) + Farbe·α·d, d = Deckkraft).
img.Image rechneWasserzeichenEin(
  img.Image bild,
  img.Image zeichen,
  Wasserzeichen wasserzeichen,
) {
  final r = wasserzeichenRechteck(
    bildBreite: bild.width,
    bildHoehe: bild.height,
    zeichenBreite: zeichen.width,
    zeichenHoehe: zeichen.height,
    wasserzeichen: wasserzeichen,
  );
  if (r == null) return bild;
  final ziel = bild.hasPalette ? bild.convert(numChannels: 4) : bild;
  final deckkraft = wasserzeichen.deckkraft.clamp(
    Wasserzeichen.deckkraftMin,
    Wasserzeichen.deckkraftMax,
  );

  final vor = img.Image(
    width: zeichen.width,
    height: zeichen.height,
    numChannels: 4,
  );
  for (final p in zeichen) {
    final a = p.aNormalized;
    vor.setPixelRgba(
      p.x,
      p.y,
      (p.rNormalized * a * 255).round(),
      (p.gNormalized * a * 255).round(),
      (p.bNormalized * a * 255).round(),
      (a * 255).round(),
    );
  }
  final skaliert = r.breite == zeichen.width && r.hoehe == zeichen.height
      ? vor
      : img.copyResize(
          vor,
          width: r.breite,
          height: r.hoehe,
          interpolation: r.breite < zeichen.width
              ? img.Interpolation.average
              : img.Interpolation.linear,
        );

  final hoechst = ziel.maxChannelValue;
  final mitAlpha = ziel.hasAlpha;
  // Ganzzahlige Kanäle runden statt abschneiden: Abgeschnitten würde jede
  // gemischte Stelle um bis zu einen Wert dunkler.
  final ganz = ziel.formatType != img.FormatType.float;
  num wert(double v) => ganz ? v.round() : v;
  for (var y = 0; y < r.hoehe; y++) {
    for (var x = 0; x < r.breite; x++) {
      final q = skaliert.getPixel(x, y);
      final a = q.a / 255 * deckkraft;
      if (a <= 0) continue;
      final d = ziel.getPixel(r.x + x, r.y + y);
      final rest = 1 - a;
      d
        ..r = wert(d.r * rest + q.r / 255 * deckkraft * hoechst)
        ..g = wert(d.g * rest + q.g / 255 * deckkraft * hoechst)
        ..b = wert(d.b * rest + q.b / 255 * deckkraft * hoechst);
      if (mitAlpha) d.a = wert(d.a * rest + a * hoechst);
    }
  }
  return ziel;
}

/// Die Eingabe für [jpegMitWasserzeichen] – als ein Wert, damit sie mit
/// `compute` bzw. `Isolate.run` in ein Isolate geht.
typedef WasserzeichenAuftrag = ({
  Uint8List jpeg,
  Uint8List zeichen,
  Wasserzeichen wasserzeichen,
  int qualitaet,
});

/// [WasserzeichenAuftrag.jpeg] mit eingerechnetem Zeichen, wieder als
/// JPEG in [WasserzeichenAuftrag.qualitaet] (1–100).
///
/// Das Farbprofil bleibt, EXIF auch (die Aufnahmeangaben setzt der Export
/// danach ohnehin neu). Steht in den EXIF-Angaben eine Drehung, wird sie
/// vorher in die Pixel gerechnet: Sonst landete „unten rechts“ nach dem
/// Drehen beim Betrachter in einer anderen Ecke, und das Zeichen stünde
/// auf der Seite. Das Bildpaket tut das seit 4.12 schon beim Dekodieren
/// selbst; der eigene Schritt hält das Ergebnis unabhängig davon, welche
/// Fassung ein Paket auflöst.
///
/// Wirft [FormatException], wenn sich Foto oder Zeichen nicht lesen lassen
/// – der Aufrufer soll dann nicht stillschweigend ohne Zeichen ausliefern.
Uint8List jpegMitWasserzeichen(WasserzeichenAuftrag auftrag) {
  // Dieselbe Grenze gegen Bomben wie beim Verdecken von Gesichtern, nur
  // weiter: Ein Export in voller Auflösung hat bei heutigen Kameras gut
  // 60 Millionen Pixel.
  JpegIcc.masse(auftrag.jpeg, maxPixel: 120000000);
  final profil = JpegIcc.lesen(auftrag.jpeg);
  var bild = img.decodeJpg(auftrag.jpeg);
  if (bild == null) throw const FormatException('pv_wasserzeichen_foto');
  final zeichen = Wasserzeichenbild.lies(auftrag.zeichen);
  if (zeichen == null) throw const FormatException('pv_wasserzeichen_bild');
  if (bild.exif.imageIfd.hasOrientation &&
      bild.exif.imageIfd.orientation != 1) {
    bild = img.bakeOrientation(bild);
  }
  bild = rechneWasserzeichenEin(bild, zeichen, auftrag.wasserzeichen);
  bild.iccProfile = null;
  return JpegIcc.schreiben(
    Uint8List.fromList(
      img.encodeJpg(bild, quality: auftrag.qualitaet.clamp(1, 100)),
    ),
    profil,
  );
}

/// Prüfen, Lesen und Vorbereiten des PNG, das eingerechnet wird.
abstract final class Wasserzeichenbild {
  /// So gross wird ein gewähltes Logo höchstens gespeichert. Es reist in
  /// der Exportvorgabe mit (als Teil der Zeile, auch zu den anderen Geräten
  /// der Bibliothek); mehr braucht ein Zeichen, das selten breiter als ein
  /// Drittel des Bildes ist, auch bei einem Export in voller Auflösung
  /// nicht.
  static const hoechstensKante = 1600;

  /// Breite und Höhe aus dem Kopf eines PNG, ohne es zu dekodieren –
  /// `null`, wenn es keines ist.
  static ({int breite, int hoehe})? masse(Uint8List daten) {
    const signatur = [137, 80, 78, 71, 13, 10, 26, 10];
    if (daten.length < 24) return null;
    for (var i = 0; i < signatur.length; i++) {
      if (daten[i] != signatur[i]) return null;
    }
    // Der erste Abschnitt ist IHDR: Länge (4), Name (4), Breite, Höhe.
    if (String.fromCharCodes(daten.sublist(12, 16)) != 'IHDR') return null;
    int zahl(int ab) =>
        (daten[ab] << 24) |
        (daten[ab + 1] << 16) |
        (daten[ab + 2] << 8) |
        daten[ab + 3];
    final breite = zahl(16), hoehe = zahl(20);
    if (breite <= 0 || hoehe <= 0) return null;
    return (breite: breite, hoehe: hoehe);
  }

  /// Ob [daten] ein PNG innerhalb der Grenzen ist
  /// ([Wasserzeichen.hoechstensBildBytes], [Wasserzeichen.hoechstensBildKante]).
  /// Die Masse werden vor dem Dekodieren geprüft.
  static bool gueltig(Uint8List daten) => lies(daten) != null;

  /// [daten] als Bild, wenn es [gueltig] ist; sonst `null`.
  static img.Image? lies(Uint8List daten) {
    if (daten.length > Wasserzeichen.hoechstensBildBytes) return null;
    final m = masse(daten);
    if (m == null ||
        m.breite > Wasserzeichen.hoechstensBildKante ||
        m.hoehe > Wasserzeichen.hoechstensBildKante) {
      return null;
    }
    try {
      return img.decodePng(daten);
    } catch (_) {
      return null;
    }
  }

  /// Ein gewähltes Logo zum Speichern: höchstens [hoechstensKante] an der
  /// langen Seite, als PNG. `null`, wenn [daten] kein PNG ist, zu gross zum
  /// Lesen (über 40 MB oder 12000 Pixel an einer Seite) oder nach dem
  /// Verkleinern noch über [Wasserzeichen.hoechstensBildBytes].
  ///
  /// Bewusst nur PNG: Das Logo braucht Transparenz, und ein JPEG hätte
  /// stets einen weissen oder schwarzen Kasten um sich.
  static Uint8List? bereiteVor(Uint8List daten) {
    if (daten.length > 40 * 1024 * 1024) return null;
    final m = masse(daten);
    if (m == null || m.breite > 12000 || m.hoehe > 12000) return null;
    img.Image? bild;
    try {
      bild = img.decodePng(daten);
    } catch (_) {
      return null;
    }
    if (bild == null) return null;
    final lang = math.max(bild.width, bild.height);
    Uint8List ergebnis;
    if (lang <= hoechstensKante &&
        daten.length <= Wasserzeichen.hoechstensBildBytes) {
      ergebnis = daten;
    } else {
      final faktor = math.min(1.0, hoechstensKante / lang);
      final breite = math.max(1, (bild.width * faktor).round());
      final hoehe = math.max(1, (bild.height * faktor).round());
      ergebnis = img.encodePng(_verkleinert(bild, breite, hoehe));
    }
    return ergebnis.length > Wasserzeichen.hoechstensBildBytes
        ? null
        : ergebnis;
  }

  /// Verkleinert mit vormultiplizierter Deckung (siehe
  /// [rechneWasserzeichenEin]) und rechnet danach zurück, damit das
  /// gespeicherte PNG wieder gewöhnliche Farben trägt.
  static img.Image _verkleinert(img.Image bild, int breite, int hoehe) {
    final vor = img.Image(
      width: bild.width,
      height: bild.height,
      numChannels: 4,
    );
    for (final p in bild) {
      final a = p.aNormalized;
      vor.setPixelRgba(
        p.x,
        p.y,
        (p.rNormalized * a * 255).round(),
        (p.gNormalized * a * 255).round(),
        (p.bNormalized * a * 255).round(),
        (a * 255).round(),
      );
    }
    final klein = img.copyResize(
      vor,
      width: breite,
      height: hoehe,
      interpolation: img.Interpolation.average,
    );
    for (final p in klein) {
      final a = p.a;
      if (a <= 0) {
        p
          ..r = 0
          ..g = 0
          ..b = 0;
        continue;
      }
      p
        ..r = math.min(255, p.r * 255 / a)
        ..g = math.min(255, p.g * 255 / a)
        ..b = math.min(255, p.b * 255 / a);
    }
    return klein;
  }
}
