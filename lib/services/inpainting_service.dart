import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/model_catalog.dart';
import 'package:kern/services/modellthreads.dart';

/// Entfernt Objekte aus einem Foto, indem es die markierte Stelle aus der
/// Umgebung neu erfindet (LaMa, siehe ModelCatalog.inpainting).
///
/// **Der Vertrag des Modells, nachgemessen statt angenommen:** Es nimmt
/// `image` als [1,3,512,512] in 0..1 und `mask` als [1,1,512,512] (1 =
/// füllen), liefert aber `output` in **0..255**. Diese Asymmetrie steht
/// nirgends geschrieben; mit 0..255 als Eingabe kommt sichtbarer Unsinn
/// heraus. An einem Farbverlauf mit ausgeschnittenem Fleck geprüft: Der
/// gefüllte Bereich weicht im Mittel um 1,8 von 255 vom Sollwert ab.
///
/// **Nur CPU, kein CoreML** – anders als [RestoreService]. Gemessen: 1267 ms
/// je Durchgang auf der CPU gegen 3509 ms mit CoreML. Von den 7956 Knoten
/// des Graphen kann CoreML nur 3699 übernehmen, und die daraus entstehenden
/// 621 Teilstücke kosten mehr an Hin- und Herschieben, als die
/// Beschleunigung einbringt.
class InpaintingService {
  InpaintingService._(this._session);

  final OrtSession _session;

  /// Kantenlänge, die das Modell fest verlangt.
  static const modellGroesse = 512;

  static bool isAvailable(String modelsDir) =>
      ModelCatalog.dateiVollstaendig(modelsDir, 'lama_fp32.onnx');

  static Future<InpaintingService> load(String modelsDir) async {
    final ort = OnnxRuntime();
    final session = await ort.createSession(
      '$modelsDir/lama_fp32.onnx',
      options: modelloptionen(providers: [OrtProvider.CPU]),
    );
    return InpaintingService._(session);
  }

  /// Entfernt alles, was in [maske] weiss ist, aus [quelle].
  ///
  /// [maske] muss dieselbe Grösse wie [quelle] haben; ausgewertet wird der
  /// Rotkanal (die Masken der App sind Graustufen).
  ///
  /// Gearbeitet wird auf einem Ausschnitt um die markierte Stelle, nicht auf
  /// dem ganzen Foto: Das Modell kann nur 512×512, und ein 24-Megapixel-Bild
  /// darauf zu schrumpfen hiesse, für einen Staubfleck die ganze Auflösung
  /// zu verlieren. Der Ausschnitt bekommt Rand mit, weil das Modell aus der
  /// Umgebung schliesst – ohne Kontext füllt es Matsch.
  ///
  /// **In Teilen, wenn die Markierung länger ist als die kurze Bildseite.**
  /// Der Ausschnitt ist quadratisch und kann nicht grösser werden als die
  /// kurze Seite des Fotos. Eine Leitung quer über ein Querformat passte
  /// deshalb nicht hinein, und ihre Enden blieben einfach stehen. Jetzt
  /// wird die Markierung entlang der langen Seite in Abschnitte geteilt
  /// (siehe [retuscheDurchgang]); jeder spätere sieht die schon gefüllten
  /// als Umgebung.
  ///
  /// **Im Isolat der Oberfläche läuft nur das Modell** (Plattformkanal).
  /// Das Absuchen der Maske, Ausschneiden, Zurückrechnen und Einsetzen
  /// geschieht über `compute()` – bei einem grossen Foto standen sonst
  /// Fenster und Warteanzeige für Sekunden still (Folge von #434).
  ///
  /// Gibt `null` zurück, wenn die Maske leer ist.
  Future<img.Image?> entferne(img.Image quelle, img.Image maske) async {
    img.Image? bild;
    var ab = 0;
    while (true) {
      final aktuell = bild ?? quelle;
      final d = await compute(retuscheDurchgang, (
        bild: aktuell,
        maske: maske,
        ab: ab,
      ));
      if (d == null) break;
      final ausgabe = await _durchlauf(d.bild, d.maske);
      bild = await compute(retuscheEinsetzen, (
        bild: aktuell,
        maske: maske,
        ausschnitt: d.ausschnitt,
        ab: ab,
        ausgabe: ausgabe,
      ));
      final weiter = d.weiter;
      if (weiter == null) break;
      ab = weiter;
    }
    return bild;
  }

  /// Der eine Lauf des Modells – das Einzige, was im Isolat der Oberfläche
  /// bleiben muss. Gibt die Ausgabe in 0..255 zurück (CHW, siehe
  /// Klassenkommentar).
  Future<Float32List> _durchlauf(
    Float32List bildDaten,
    Float32List maskenDaten,
  ) async {
    const n = modellGroesse;
    final bildTensor = await OrtValue.fromList(bildDaten, [1, 3, n, n]);
    final maskenTensor = await OrtValue.fromList(maskenDaten, [1, 1, n, n]);
    // Wie in RestoreService._inferTile: Alle Tensoren kommen in ein Set und
    // werden im finally freigegeben, damit auch ein Fehler mitten im Lauf
    // keine hunderte Megabyte liegen lässt.
    final lebend = <OrtValue>{bildTensor, maskenTensor};
    try {
      final ausgaben = await _session.run({
        'image': bildTensor,
        'mask': maskenTensor,
      });
      lebend.addAll(ausgaben.values);
      final roh = await ausgaben['output']!.asFlattenedList();
      return roh is Float32List
          ? roh
          : Float32List.fromList([for (final v in roh) (v as num).toDouble()]);
    } finally {
      for (final v in lebend) {
        try {
          await v.dispose();
        } catch (_) {
          // Bereits freigegeben – bestmöglich.
        }
      }
    }
  }

  Future<void> dispose() async => _session.close();
}

/// Ein Rechteck im Bild.
typedef Retuschekasten = ({int left, int top, int width, int height});

/// Was ein Durchgang der Retusche dem Modell gibt: der [ausschnitt] im
/// Foto, Bild und Maske darin in Modellgrösse (CHW, 0..1), und wo der
/// nächste Abschnitt beginnt – `null`, wenn dies der letzte ist.
typedef Retuschedurchgang = ({
  Retuschekasten ausschnitt,
  Float32List bild,
  Float32List maske,
  int? weiter,
});

/// So viel Umgebung bekommt ein Ausschnitt mindestens, auf jeder Seite.
const _mindestRand = 48;

/// Ob die Abschnitte einer langen Markierung nebeneinander liegen
/// (Querformat) oder untereinander (Hochformat). Im Quadrat passt jede
/// Markierung in einen Ausschnitt.
bool _quer(int breite, int hoehe) => breite >= hoehe;

/// Bereitet einen Durchgang der Retusche vor – über `compute()` in einem
/// Hintergrund-Isolat (siehe [InpaintingService.entferne]).
///
/// Betrachtet wird nur die Markierung ab [ab] entlang der langen Bildseite;
/// davor ist schon gefüllt und gilt jetzt als Umgebung. Passt der Rest in
/// einen Ausschnitt, ist dies der letzte Durchgang. Sonst wird ein
/// Abschnitt genommen, der mit [_mindestRand] Umgebung auf beiden Seiten
/// in einen Ausschnitt von der kurzen Bildseite passt, und
/// [Retuschedurchgang.weiter] sagt, wo der nächste beginnt. Gibt `null`
/// zurück, wenn ab [ab] nichts mehr markiert ist.
@visibleForTesting
Retuschedurchgang? retuscheDurchgang(
  ({img.Image bild, img.Image maske, int ab}) a,
) {
  final breite = a.bild.width, hoehe = a.bild.height;
  final quer = _quer(breite, hoehe);
  final kasten = maskenKasten(a.maske, ab: a.ab, quer: quer);
  if (kasten == null) return null;

  var teil = kasten;
  int? weiter;
  final grenze = math.min(breite, hoehe);
  if ((quer ? kasten.width : kasten.height) > grenze) {
    final schritt = grenze > 4 * _mindestRand
        ? grenze - 2 * _mindestRand
        : grenze;
    final anfang = quer ? kasten.left : kasten.top;
    weiter = anfang + schritt;
    // Nicht leer: Am Anfang des Kastens liegt ein markierter Punkt.
    teil = maskenKasten(a.maske, ab: anfang, bis: weiter, quer: quer)!;
  }

  // Rand: die Hälfte der Kastengrösse, mindestens [_mindestRand] Punkte.
  // Weniger Kontext liefert sichtbar schlechtere Füllungen, mehr
  // verschenkt Auflösung, weil der Ausschnitt auf 512 geschrumpft wird.
  final rand = math.max(_mindestRand, math.max(teil.width, teil.height) ~/ 2);
  final ausschnitt = quadratischerAusschnitt(teil, rand, breite, hoehe);

  final teilBild = img.copyCrop(
    a.bild,
    x: ausschnitt.left,
    y: ausschnitt.top,
    width: ausschnitt.width,
    height: ausschnitt.height,
  );
  final teilMaske = img.copyCrop(
    a.maske,
    x: ausschnitt.left,
    y: ausschnitt.top,
    width: ausschnitt.width,
    height: ausschnitt.height,
  );
  // Was ein früherer Abschnitt schon gefüllt hat, ist jetzt Umgebung und
  // wird nicht noch einmal erfunden.
  final erledigt = a.ab - (quer ? ausschnitt.left : ausschnitt.top);
  if (erledigt > 0) {
    img.fillRect(
      teilMaske,
      x1: 0,
      y1: 0,
      x2: (quer ? erledigt : ausschnitt.width) - 1,
      y2: (quer ? ausschnitt.height : erledigt) - 1,
      color: img.ColorRgb8(0, 0, 0),
    );
  }

  const n = InpaintingService.modellGroesse;
  final klein = img.copyResize(
    teilBild,
    width: n,
    height: n,
    interpolation: img.Interpolation.linear,
  );
  // Die Maske mit nächstem Nachbarn: Eine geglättete Maske bekäme
  // Grauwerte am Rand, und das Modell behandelt alles über 0 als „füllen".
  final kleineMaske = img.copyResize(
    teilMaske,
    width: n,
    height: n,
    interpolation: img.Interpolation.nearest,
  );

  final chw = Float32List(3 * n * n);
  var i = 0;
  for (var c = 0; c < 3; c++) {
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final p = klein.getPixel(x, y);
        // 0..1 – siehe Klassenkommentar.
        chw[i++] = (c == 0 ? p.r : (c == 1 ? p.g : p.b)) / 255.0;
      }
    }
  }
  final maskenDaten = Float32List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      maskenDaten[y * n + x] = kleineMaske.getPixel(x, y).r > 127 ? 1.0 : 0.0;
    }
  }
  return (
    ausschnitt: ausschnitt,
    bild: chw,
    maske: maskenDaten,
    weiter: weiter,
  );
}

/// Setzt die [ausgabe] des Modells (CHW, 0..255) in den Ausschnitt ein,
/// nur innerhalb der Maske und erst ab [ab] – über `compute()` in einem
/// Hintergrund-Isolat. Gibt ein neues Bild zurück; [bild] bleibt, wie es
/// ist.
@visibleForTesting
img.Image retuscheEinsetzen(
  ({
    img.Image bild,
    img.Image maske,
    Retuschekasten ausschnitt,
    int ab,
    Float32List ausgabe,
  })
  a,
) {
  const n = InpaintingService.modellGroesse;
  const kanal = n * n;
  final roh = a.ausgabe;
  final gefuellt = img.Image(width: n, height: n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final idx = y * n + x;
      // Ausgabe ist bereits 0..255 – hier NICHT noch einmal skalieren.
      gefuellt.setPixelRgb(
        x,
        y,
        roh[idx].round().clamp(0, 255),
        roh[kanal + idx].round().clamp(0, 255),
        roh[2 * kanal + idx].round().clamp(0, 255),
      );
    }
  }

  // Zurück auf die Ausschnittgrösse und nur innerhalb der Maske einsetzen.
  final s = a.ausschnitt;
  final zurueck = img.copyResize(
    gefuellt,
    width: s.width,
    height: s.height,
    interpolation: img.Interpolation.cubic,
  );
  final quer = _quer(a.bild.width, a.bild.height);
  final ergebnis = img.Image.from(a.bild);
  for (var y = 0; y < s.height; y++) {
    final by = s.top + y;
    if (!quer && by < a.ab) continue;
    for (var x = 0; x < s.width; x++) {
      final bx = s.left + x;
      if (quer && bx < a.ab) continue;
      final anteil = a.maske.getPixel(bx, by).r / 255.0;
      if (anteil <= 0) continue;
      final alt = a.bild.getPixel(bx, by);
      final neu = zurueck.getPixel(x, y);
      double misch(num a, num b) => a + (b - a) * anteil;
      ergebnis.setPixelRgb(
        bx,
        by,
        misch(alt.r, neu.r).round().clamp(0, 255),
        misch(alt.g, neu.g).round().clamp(0, 255),
        misch(alt.b, neu.b).round().clamp(0, 255),
      );
    }
  }
  return ergebnis;
}

/// Das umschliessende Rechteck aller markierten Punkte, oder `null` bei
/// leerer Maske.
///
/// Mit [ab] und [bis] nur die Punkte in diesem Bereich der Spalten
/// ([quer]) bzw. Zeilen – für die Abschnitte einer langen Markierung
/// (siehe [retuscheDurchgang]).
@visibleForTesting
Retuschekasten? maskenKasten(
  img.Image maske, {
  int ab = 0,
  int? bis,
  bool quer = true,
}) {
  final xVon = quer ? math.max(0, ab) : 0;
  final xBis = quer ? math.min(bis ?? maske.width, maske.width) : maske.width;
  final yVon = quer ? 0 : math.max(0, ab);
  final yBis = quer
      ? maske.height
      : math.min(bis ?? maske.height, maske.height);
  var links = maske.width, oben = maske.height, rechts = -1, unten = -1;
  for (var y = yVon; y < yBis; y++) {
    for (var x = xVon; x < xBis; x++) {
      if (maske.getPixel(x, y).r > 127) {
        if (x < links) links = x;
        if (x > rechts) rechts = x;
        if (y < oben) oben = y;
        if (y > unten) unten = y;
      }
    }
  }
  if (rechts < 0) return null;
  return (
    left: links,
    top: oben,
    width: rechts - links + 1,
    height: unten - oben + 1,
  );
}

/// Erweitert [kasten] um [rand], macht ihn quadratisch und hält ihn im Bild.
///
/// Quadratisch, weil das Modell 512×512 verlangt: Ein längliches Rechteck
/// darauf zu verzerren staucht das Motiv in einer Richtung, und das Modell
/// füllt dann entsprechend verzerrt.
/// Der Ausschnitt ist zudem NIE kleiner als [InpaintingService.modellGroesse].
///
/// Das ist der wichtigste Wert dieser Datei, und er ist gemessen: Ein
/// kleinerer Ausschnitt müsste auf 512 hochgerechnet werden, und darauf
/// arbeitet das Modell dramatisch schlechter. An einem Farbverlauf mit
/// 100 Punkten grossem Loch: mittlerer Fehler 62,8 von 255 bei einem
/// 300-Punkte-Ausschnitt, 1,2 bei 512. Herunterrechnen schadet dagegen
/// nicht.
@visibleForTesting
({int left, int top, int width, int height}) quadratischerAusschnitt(
  ({int left, int top, int width, int height}) kasten,
  int rand,
  int bildBreite,
  int bildHoehe,
) {
  var seite = math.max(kasten.width, kasten.height) + 2 * rand;
  seite = math.max(seite, InpaintingService.modellGroesse);
  seite = math.min(seite, math.min(bildBreite, bildHoehe));

  final mitteX = kasten.left + kasten.width / 2;
  final mitteY = kasten.top + kasten.height / 2;
  final links = (mitteX - seite / 2).round().clamp(0, bildBreite - seite);
  final oben = (mitteY - seite / 2).round().clamp(0, bildHoehe - seite);
  return (left: links, top: oben, width: seite, height: seite);
}
