import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'tile_processor.dart';

/// **Hochskalieren als eigenes Werkzeug (#500).**
///
/// Bis hierher vergrösserte Photo Vault nur nebenbei: Die KI-Restaurierung
/// rechnet mit Real-ESRGAN immer auf die vierfache Kantenlänge und legt das
/// Ergebnis als Anzeige über das Original. Wer ein Foto für einen grossen
/// Druck brauchte, bekam so immer das Vierfache, und keine eigene Aufnahme,
/// sondern eine Fassung, die das nächste Restaurieren wieder ersetzte.
///
/// Hier steht, was das Werkzeug rechnet, unabhängig von Oberfläche und
/// Datenbank: welche Faktoren es gibt, wo die Grenzen liegen, wie aus dem
/// vierfachen Ergebnis des Netzes ein zwei- oder dreifaches wird, und wie
/// Auftrag und neue Datei heissen. Das Rechnen selbst läuft im Isolat der
/// Restaurierung (siehe `RestoreService.starteHochskalieren`), die Aufträge
/// in ihrer Warteschlange (siehe `RestoreQueueService.hochskalieren`), das
/// Ablegen als Variante in `hochskalieren_ablegen.dart`.

/// Die angebotenen Faktoren. Real-ESRGAN x4 kennt nur den einen; 2× und 3×
/// entstehen aus seinem Ergebnis (siehe [hochskaliereInKacheln]).
const hochskalierFaktoren = [2, 3, 4];

/// Die längste Kante, die ein Ergebnis haben darf.
///
/// **Warum 16384.** Das hochskalierte Foto ist danach eine gewöhnliche
/// Aufnahme der Bibliothek: Man entwickelt es, exportiert es, rechnet
/// vielleicht noch einmal daran. 16384 Pixel Kante sind die grösste Textur,
/// die Metal auf den Apple-GPUs anlegt, auf denen Core Image das Entwickeln
/// rechnet; dieselbe Zahl gibt `RestoreQueueService.entwickeltesJpeg` als
/// Obergrenze der Vorlage vor. Der JPEG-Leser des `image`-Pakets, mit dem
/// ausserhalb von macOS Miniaturen und Auswertung lesen, nimmt ab Werk
/// höchstens 2^28 Bildpunkte an – ein Quadrat von 16384 Pixeln. Eine
/// längere Kante gäbe eine Datei, an der die App selbst an Grenzen stösst.
const hochskalierMaxKante = 16384;

/// Wie viele Bildpunkte ein Ergebnis höchstens haben darf.
///
/// **Warum 100 Megapixel, und warum zusätzlich zur Kante.** Die Kante
/// allein liesse ein Quadrat von 16384 × 16384 zu, 268 Megapixel: 805 MB
/// Ergebnis allein in der Zusammensetzung von `processInTiles`, und das
/// JPEG entsteht danach noch einmal daneben. Bei 100 Megapixeln sind es
/// höchstens 300 MB Ergebnis; mit Quelle, Überblendung und einer Kachel
/// bleibt die Zusammensetzung unter einem halben Gigabyte (siehe den Test
/// in `hochskalieren_test.dart`), das geht auch auf einem Rechner mit
/// 8 GB. Jedes spätere Dekodieren des Fotos (Miniatur, Entwickeln,
/// Auswertung) kostet dann 400 MB statt über einem Gigabyte. Mehr als
/// 100 Megapixel braucht kein Druck, der sich aus einem Kamerabild
/// sinnvoll vergrössern lässt.
const hochskalierMaxPixel = 100 * 1000 * 1000;

/// Warum ein Faktor gesperrt ist.
enum Hochskaliersperre {
  /// Die längste Kante läge über [hochskalierMaxKante].
  kante,

  /// Das Ergebnis hätte mehr als [hochskalierMaxPixel] Bildpunkte.
  pixel,
}

/// Grösse des Ergebnisses für einen Faktor – und ob er gesperrt ist.
typedef Hochskalierziel = ({int breite, int hoehe, Hochskaliersperre? sperre});

/// Was beim Hochskalieren von [breite] × [hoehe] um [faktor] herauskäme.
///
/// Die Kante zuerst: Ist sie zu lang, ist das der Grund, den man ändern
/// müsste – ein kleinerer Faktor hilft dann bei beiden.
Hochskalierziel hochskalierziel(int breite, int hoehe, int faktor) {
  final b = breite * faktor;
  final h = hoehe * faktor;
  final sperre = math.max(b, h) > hochskalierMaxKante
      ? Hochskaliersperre.kante
      : b * h > hochskalierMaxPixel
      ? Hochskaliersperre.pixel
      : null;
  return (breite: b, hoehe: h, sperre: sperre);
}

/// Megapixel für die Anzeige.
double megapixel(int breite, int hoehe) => breite * hoehe / 1e6;

/// Der grösste Faktor, der für [breite] × [hoehe] nicht gesperrt ist –
/// `null`, wenn es keinen gibt. Mit ihm öffnet der Dialog: Wer hochskaliert,
/// will in der Regel so gross wie möglich.
int? groessterHochskalierfaktor(int breite, int hoehe) {
  for (final f in hochskalierFaktoren.reversed) {
    if (hochskalierziel(breite, hoehe, f).sperre == null) return f;
  }
  return null;
}

// --- Aufträge ---------------------------------------------------------

/// Woran ein Auftrag der Restaurierungs-Warteschlange als Hochskalieren zu
/// erkennen ist.
///
/// **In der Kennung, nicht in einer neuen Spalte.** Eine Spalte hiesse
/// eine neue Schemafassung, und die prüfen Server und verbundene Geräte
/// gegeneinander: Für einen Auftrag, der nur auf diesem Rechner gilt
/// (`restore_jobs` gleicht niemand ab, siehe `Abgleichsplan.nurLokal`),
/// müsste der Server mit aktualisiert werden. Die Kennung ist frei gewählter
/// Text und wird einmal beim Anlegen geschrieben; sie trägt den Faktor
/// verlässlich durch Neustarts (siehe `resetStuckRunningRestoreJobs`).
const _auftragsPraefix = 'hochskalieren-';

/// Eine neue Kennung für einen Auftrag mit [faktor].
String hochskalierAuftragsId(int faktor) =>
    '$_auftragsPraefix${faktor}x-${const Uuid().v4()}';

/// Ob [auftragsId] ein Hochskalieren ist – auch mit einem Faktor, den
/// diese Fassung nicht kennt (siehe [hochskalierfaktor]).
bool istHochskalierauftrag(String auftragsId) =>
    auftragsId.startsWith(_auftragsPraefix);

/// Der Faktor eines Auftrags – `null` für eine gewöhnliche Restaurierung
/// und für einen Faktor, den diese Fassung nicht kennt. Welches von
/// beiden, sagt [istHochskalierauftrag]: Ein `hochskalieren-8x-…` einer
/// späteren Fassung darf nicht als Restaurierung laufen und die
/// vorhandene ersetzen.
int? hochskalierfaktor(String auftragsId) {
  if (!auftragsId.startsWith(_auftragsPraefix)) return null;
  final rest = auftragsId.substring(_auftragsPraefix.length);
  final ende = rest.indexOf('x-');
  if (ende <= 0) return null;
  final faktor = int.tryParse(rest.substring(0, ende));
  return hochskalierFaktoren.contains(faktor) ? faktor : null;
}

/// Der Dateiname des Ergebnisses, etwa „IMG_1234 (4×).jpg“.
///
/// Immer `.jpg`: Das Ergebnis ist ein neu kodiertes JPEG, gleich ob das
/// Original ein HEIC, ein RAW oder ein PNG war. Schrägstriche fallen weg wie
/// in `speichereBearbeitung` – der Name wird zum Dateinamen im
/// Arbeitsordner.
String hochskalierName(String originalName, int faktor) {
  final stamm = p
      .basenameWithoutExtension(originalName.replaceAll(RegExp(r'[/\\]'), '_'))
      .trim();
  return '${stamm.isEmpty ? 'IMG' : stamm} ($faktor×).jpg';
}

/// Breite und Höhe eines JPEG aus seinem Kopf, ohne die Bildpunkte zu
/// dekodieren – `null`, wenn es keines ist oder der Kopf nicht in [jpeg]
/// liegt.
///
/// **Nur bis zum Bildkopf.** `JpegDecoder.startDecode` las bis hierher die
/// ganze Datei Byte für Byte bis zu ihrem Ende, auch hinter den Bilddaten
/// – bei der Vorlage eines grossen Fotos Dutzende Megabyte auf dem Faden
/// der Oberfläche. Der Bildkopf (SOF) steht vor den Bilddaten; danach
/// kommt nichts mehr, was die Grösse sagt.
({int breite, int hoehe})? jpegMasse(Uint8List jpeg) {
  final n = jpeg.length;
  if (n < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return null;
  var i = 2;
  while (i < n) {
    if (jpeg[i] != 0xFF) return null;
    // Füllbytes vor dem Marker.
    while (i < n && jpeg[i] == 0xFF) {
      i++;
    }
    if (i >= n) return null;
    final marker = jpeg[i++];
    // Marker ohne Länge.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) continue;
    // Bilddaten oder Ende, ohne dass ein Bildkopf kam.
    if (marker == 0xD9 || marker == 0xDA || i + 2 > n) return null;
    final laenge = (jpeg[i] << 8) | jpeg[i + 1];
    if (laenge < 2) return null;
    final istKopf =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (istKopf) {
      if (i + 7 > n) return null;
      final hoehe = (jpeg[i + 3] << 8) | jpeg[i + 4];
      final breite = (jpeg[i + 5] << 8) | jpeg[i + 6];
      return breite > 0 && hoehe > 0 ? (breite: breite, hoehe: hoehe) : null;
    }
    i += laenge;
  }
  return null;
}

/// [jpegMasse] einer Datei, aus ihrem Anfang gelesen: Vor dem Bildkopf
/// stehen nur Anhänge wie EXIF und Farbprofil, selten mehr als einige
/// Dutzend Kilobyte. Erst wenn er dort nicht liegt, wird mehr gelesen.
Future<({int breite, int hoehe})?> jpegMasseAusDatei(File datei) async {
  final roh = await datei.open();
  try {
    final laenge = await roh.length();
    for (final menge in [256 * 1024, 4 * 1024 * 1024, laenge]) {
      await roh.setPosition(0);
      final kopf = await roh.read(math.min(menge, laenge));
      final masse = jpegMasse(kopf);
      if (masse != null || menge >= laenge) return masse;
    }
    return null;
  } finally {
    await roh.close();
  }
}

// --- Rechnen ----------------------------------------------------------

/// Kachelweise wie [processInTiles], mit einem Modell, das um
/// [modellfaktor] vergrössert, und einem Ergebnis in [zielfaktor].
///
/// **Wie 2× und 3× entstehen.** Real-ESRGAN rechnet nur vierfach. Die zwei
/// naheliegenden Wege waren:
///
/// * **Vorher verkleinern** (für 2× auf die Hälfte, für 3× auf drei
///   Viertel) und dann vierfach rechnen. Spart Rechenzeit und Speicher,
///   wirft aber vor dem Netz die Hälfte bzw. ein Viertel der Kantenauflösung
///   weg – genau die Einzelheiten, aus denen das Netz seine Vergrösserung
///   ableitet. Gleiche Qualität ist das nicht.
/// * **Vierfach rechnen und das ganze Ergebnis verkleinern.** Volle
///   Qualität, aber das vierfache Zwischenbild läge ganz im Speicher: bei
///   einem 2×-Auftrag viermal so viel wie das Ergebnis selbst. Die
///   Zusammensetzung stiesse damit schon bei rund 16 Megapixeln Quelle an
///   ihre Grenze (siehe `TileMemoryLimit`), 2× ist aber bis 25 erlaubt.
///
/// Hier geschieht das Zweite **je Kachel**: Jede Kachel kommt vierfach aus
/// dem Netz und wird sofort flächentreu ([verkleinereFlaechig]) auf den
/// Zielfaktor gebracht, erst dann überblendet und zusammengesetzt. Weil
/// Kachelanfänge auf ganzen Quellpixeln liegen, decken sich die Raster
/// beider Massstäbe an jeder Kachelgrenze; das Ergebnis gleicht dem
/// verkleinerten Gesamtbild (geprüft in `hochskalieren_test.dart`). Im
/// Speicher liegt dabei nur das Ergebnis in Zielgrösse – bei 2× ein Viertel,
/// bei 3× gut die Hälfte dessen, was ein vierfaches Zwischenbild belegte –
/// und eine einzige vierfache Kachel.
///
/// Alle Kacheln eines Bildes sind gleich gross (siehe `Kachelraster`); die
/// Anteile des Verkleinerns und sein Zwischenpuffer werden deshalb einmal
/// angelegt und für jede Kachel wieder benutzt. [vielfaches] siehe
/// `Kachelraster`.
Future<img.Image> hochskaliereInKacheln(
  img.Image quelle, {
  required int tileSize,
  required int overlap,
  required int modellfaktor,
  required int zielfaktor,
  required Future<img.Image> Function(img.Image kachel) infer,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
  int vielfaches = 1,
}) {
  if (zielfaktor < 1 || zielfaktor > modellfaktor) {
    throw ArgumentError('pv_zielfaktor');
  }
  _Verkleinerer? verkleinerer;
  return processInTiles(
    quelle,
    tileSize: tileSize,
    overlap: overlap,
    scaleFactor: zielfaktor,
    modellfaktor: modellfaktor,
    vielfaches: vielfaches,
    onProgress: onProgress,
    isCancelled: isCancelled,
    infer: (kachel) async {
      final gross = await infer(kachel);
      if (zielfaktor == modellfaktor) return gross;
      if (gross.width != kachel.width * modellfaktor ||
          gross.height != kachel.height * modellfaktor) {
        throw StateError('pv_kachel_ausgabe');
      }
      final breite = kachel.width * zielfaktor;
      final hoehe = kachel.height * zielfaktor;
      final v = verkleinerer;
      final passend =
          v != null &&
          v.quellBreite == gross.width &&
          v.quellHoehe == gross.height &&
          v.breite == breite &&
          v.hoehe == hoehe;
      return (passend
              ? v
              : verkleinerer = _Verkleinerer(
                  gross.width,
                  gross.height,
                  breite,
                  hoehe,
                ))
          .verkleinere(gross);
    },
  );
}

/// Verkleinert [bild] flächentreu auf [breite] × [hoehe].
///
/// Jedes Zielpixel ist das Mittel genau der Fläche, die es im Quellbild
/// überdeckt – auch angeschnittene Quellpixel zählen mit ihrem Anteil (wie
/// `INTER_AREA` in OpenCV). Beim Verkleinern um kleine Faktoren wie hier
/// (4 → 2, 4 → 3) gibt das kein Flimmern und, anders als Lanczos, keine
/// Säume an harten Kanten, die das Netz gerade sauber gezogen hat.
///
/// **Warum nicht `copyResize` aus dem `image`-Paket.** Dessen
/// `Interpolation.average` mittelt über ganze Pixel: Für 4 → 3 teilt es
/// jede Gruppe von vier Quellpixeln in Kästchen aus 1, 1 und 2 Pixeln, das
/// Ergebnis zieht feine Streifen über Kanten. Ausserdem schneidet es den
/// Mittelwert ab, statt zu runden, und dunkelt so um einen halben Wert ab.
/// `Interpolation.cubic` tastet nur Punkte ab, ohne über die Fläche zu
/// mitteln.
img.Image verkleinereFlaechig(img.Image bild, int breite, int hoehe) {
  if (breite <= 0 || hoehe <= 0 || breite > bild.width || hoehe > bild.height) {
    throw ArgumentError('pv_verkleinern');
  }
  if (breite == bild.width && hoehe == bild.height) return bild;
  return _Verkleinerer(
    bild.width,
    bild.height,
    breite,
    hoehe,
  ).verkleinere(bild);
}

/// [verkleinereFlaechig] für Bilder einer festen Grösse – die Anteile und
/// der Zwischenpuffer gelten für jedes davon.
class _Verkleinerer {
  _Verkleinerer(this.quellBreite, this.quellHoehe, this.breite, this.hoehe)
    : waagrecht = _Flaechenanteile(quellBreite, breite),
      senkrecht = _Flaechenanteile(quellHoehe, hoehe),
      zwischen = Float32List(quellHoehe * breite * 3);

  final int quellBreite, quellHoehe, breite, hoehe;
  final _Flaechenanteile waagrecht, senkrecht;
  final Float32List zwischen;

  img.Image verkleinere(img.Image bild) {
    if (bild.width != quellBreite || bild.height != quellHoehe) {
      throw ArgumentError('pv_verkleinern');
    }
    if (breite == quellBreite && hoehe == quellHoehe) return bild;
    final quelle = rgbBytes(bild);

    // Erst jede Zeile auf die Zielbreite, dann jede Spalte auf die Zielhöhe –
    // die Fläche zerfällt in beide Richtungen, das Ergebnis ist dasselbe wie
    // in einem Schritt, kostet aber je Pixel nur zwei kurze Summen.
    for (var y = 0; y < quellHoehe; y++) {
      final zeile = y * quellBreite * 3;
      final ziel = y * breite * 3;
      for (var x = 0; x < breite; x++) {
        final erstes = waagrecht.erstes[x];
        final basis = x * waagrecht.hoechstens;
        var r = 0.0, g = 0.0, b = 0.0;
        for (var k = 0; k < waagrecht.anzahl[x]; k++) {
          final w = waagrecht.gewicht[basis + k];
          final q = zeile + (erstes + k) * 3;
          r += quelle[q] * w;
          g += quelle[q + 1] * w;
          b += quelle[q + 2] * w;
        }
        final z = ziel + x * 3;
        zwischen[z] = r;
        zwischen[z + 1] = g;
        zwischen[z + 2] = b;
      }
    }

    final aus = Uint8List(hoehe * breite * 3);
    int kanal(double v) => (v + 0.5).floor().clamp(0, 255);
    for (var y = 0; y < hoehe; y++) {
      final erstes = senkrecht.erstes[y];
      final basis = y * senkrecht.hoechstens;
      final ziel = y * breite * 3;
      for (var x = 0; x < breite; x++) {
        var r = 0.0, g = 0.0, b = 0.0;
        for (var k = 0; k < senkrecht.anzahl[y]; k++) {
          final w = senkrecht.gewicht[basis + k];
          final q = ((erstes + k) * breite + x) * 3;
          r += zwischen[q] * w;
          g += zwischen[q + 1] * w;
          b += zwischen[q + 2] * w;
        }
        final z = ziel + x * 3;
        aus[z] = kanal(r);
        aus[z + 1] = kanal(g);
        aus[z + 2] = kanal(b);
      }
    }
    return img.Image.fromBytes(
      width: breite,
      height: hoehe,
      bytes: aus.buffer,
      numChannels: 3,
    );
  }
}

/// Welche Quellpixel einer Achse jedes Zielpixel überdeckt, und mit welchem
/// Anteil.
///
/// Gerechnet in Bruchteilen von `1 / ziel` eines Quellpixels: Zielpixel `i`
/// deckt dann `[i·quelle, (i+1)·quelle)` ab, Quellpixel `j` liegt bei
/// `[j·ziel, (j+1)·ziel)`. So bleiben die Grenzen ganzzahlig, und die
/// Anteile eines Zielpixels ergeben genau 1 – ohne Rundungsfehler, die
/// sonst über tausende Spalten eine Helligkeitsdrift ergäben.
class _Flaechenanteile {
  _Flaechenanteile(int quelle, int ziel)
    : hoechstens = (quelle + ziel - 1) ~/ ziel + 1,
      erstes = Int32List(ziel),
      anzahl = Int32List(ziel),
      gewicht = Float64List(ziel * ((quelle + ziel - 1) ~/ ziel + 1)) {
    for (var i = 0; i < ziel; i++) {
      final anfang = i * quelle;
      final ende = anfang + quelle;
      final j0 = anfang ~/ ziel;
      final j1 = (ende - 1) ~/ ziel;
      erstes[i] = j0;
      anzahl[i] = j1 - j0 + 1;
      for (var j = j0; j <= j1; j++) {
        final ueberdeckt =
            math.min(ende, (j + 1) * ziel) - math.max(anfang, j * ziel);
        gewicht[i * hoechstens + j - j0] = ueberdeckt / quelle;
      }
    }
  }

  /// Wie viele Quellpixel ein Zielpixel höchstens berührt.
  final int hoechstens;
  final Int32List erstes;
  final Int32List anzahl;
  final Float64List gewicht;
}
