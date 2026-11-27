import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kern/services/wasserzeichen.dart';
import 'package:path/path.dart' as p;

/// Bilder für geteilte Links – neu gerechnet, ohne jede Metadaten.
///
/// **Warum nicht die vorhandenen Dateien.** Die Ansicht eines gewöhnlichen
/// JPEGs ist das Original, und das trägt seine EXIF-Angaben, darunter den
/// Ort. Wer einen Link bekommt, soll die Bilder sehen, nicht erfahren, wo
/// das Haus steht. Hier wird jedes Bild dekodiert, nach seiner Drehung
/// aufgerichtet und ohne Metadaten neu geschrieben – einmal, danach aus
/// dem Zwischenspeicher. Immer nur eines auf einmal, in einem eigenen
/// Isolate.
///
/// **Mit Wasserzeichen** (#497) wird es nach dem Verkleinern eingerechnet –
/// in der Grösse, die der Gast bekommt, damit es in Miniatur und Ansicht
/// gleich gross wirkt (es misst in Anteilen der Bildbreite). Der Aufrufer
/// gibt solchen Fassungen einen eigenen Namen (mit
/// [Wasserzeichen.kennung]); sonst bekäme ein Link ohne Zeichen die Datei
/// eines Links mit.
///
/// **Was nicht wartet.** Eine fertige Datei geht sofort hinaus, nicht erst,
/// wenn die Reihe bis zu ihr gekommen ist: Eine Seite mit zweihundert
/// Miniaturen, von denen eine neu zu rechnen ist, soll nicht zweihundertmal
/// auf diese eine warten. Und ein Zeichen wird je Kennung einmal gelesen
/// und vorbereitet ([Zeichenpixel]) und dann aus dem Speicher genommen,
/// statt für jedes Bild sein PNG neu zu dekodieren.
class Teilbilder {
  Teilbilder({Teilbildrechner? rechner}) : _rechner = rechner ?? _imIsolat;

  final Teilbildrechner _rechner;
  final _laufend = <String, Future<File?>>{};
  Future<void> _reihe = Future.value();

  /// Vorbereitete Zeichen nach ihrer Kennung, das zuletzt gebrauchte
  /// zuletzt. Der Server speichert ein Zeichen höchstens so gross, wie es
  /// in einer Ansicht wird (`Wasserzeichenbild.normalisiert`), meist ein
  /// paar hundert Kilobyte; die Grenze in Bytes fängt die seltenen grossen.
  final _vorbereitet = <String, Teilbildzeichenpixel>{};
  static const hoechstensZeichen = 8;
  static const hoechstensZeichenBytes = 64 * 1024 * 1024;

  /// Die bereinigte Fassung von [quelle], höchstens [kante] Punkte an der
  /// langen Seite, mit [zeichen], sofern gegeben; `null`, wenn sich das
  /// Bild nicht lesen lässt.
  ///
  /// [zeichen] trägt die Kennung und liest das Zeichen, wenn es nicht schon
  /// vorbereitet im Speicher liegt. Lässt es sich nicht lesen oder trägt es
  /// kein Bild, gibt es keine Fassung (`null`) statt einer ohne Zeichen: Wer
  /// ein Wasserzeichen gesetzt hat, soll sich darauf verlassen können.
  Future<File?> fassung(
    Directory speicher,
    String name,
    File quelle, {
    required int kante,
    Teilbildzeichen? zeichen,
  }) async {
    final ziel = File(p.join(speicher.path, '$name.jpg'));
    if (await _frisch(ziel, quelle)) return ziel;
    return _laufend.putIfAbsent(ziel.path, () {
      final fertig = Completer<File?>();
      _reihe = _reihe.then((_) async {
        try {
          // Inzwischen fertig – etwa von einer Anfrage vor dieser.
          if (await _frisch(ziel, quelle)) {
            fertig.complete(ziel);
            return;
          }
          Teilbildzeichenpixel? vorbereitet;
          if (zeichen != null) {
            vorbereitet = await _zeichen(zeichen);
            if (vorbereitet == null) {
              fertig.complete(null);
              return;
            }
          }
          await speicher.create(recursive: true);
          final teil = File('${ziel.path}.teil');
          final bytes = await _rechner(quelle.path, kante, vorbereitet);
          if (bytes == null) {
            fertig.complete(null);
            return;
          }
          await teil.writeAsBytes(bytes, flush: true);
          await teil.rename(ziel.path);
          fertig.complete(ziel);
        } catch (_) {
          fertig.complete(null);
        } finally {
          _laufend.remove(ziel.path);
        }
      });
      return fertig.future;
    });
  }

  static Future<bool> _frisch(File ziel, File quelle) async {
    try {
      return await ziel.exists() &&
          !(await ziel.lastModified()).isBefore(await quelle.lastModified());
    } on FileSystemException {
      return false;
    }
  }

  Future<Teilbildzeichenpixel?> _zeichen(Teilbildzeichen z) async {
    if (_vorbereitet.remove(z.kennung) case final v?) {
      return _vorbereitet[z.kennung] = v;
    }
    final w = z.laden();
    final daten = w?.bild;
    if (w == null || daten == null) return null;
    final pixel = await _pixelImIsolat(daten);
    if (pixel == null) return null;
    final v = (wasserzeichen: w, pixel: pixel);
    _vorbereitet[z.kennung] = v;
    var bytes = 0;
    for (final x in _vorbereitet.values) {
      bytes += x.pixel.rgba.length;
    }
    while (_vorbereitet.length > 1 &&
        (_vorbereitet.length > hoechstensZeichen ||
            bytes > hoechstensZeichenBytes)) {
      bytes -= _vorbereitet.remove(_vorbereitet.keys.first)!.pixel.rgba.length;
    }
    return v;
  }

  /// Wie viele Zeichen gerade vorbereitet im Speicher liegen – für Tests.
  int get vorbereitet => _vorbereitet.length;
}

/// Ein Zeichen für [Teilbilder.fassung]: seine Kennung
/// ([Wasserzeichen.kennung]) und wie es sich lesen lässt – `null`, wenn
/// nicht.
typedef Teilbildzeichen = ({String kennung, Wasserzeichen? Function() laden});

/// Ein gelesenes, vorbereitetes Zeichen: die Einstellungen und die Pixel.
typedef Teilbildzeichenpixel = ({
  Wasserzeichen wasserzeichen,
  Zeichenpixel pixel,
});

/// Rechnet eine Fassung: aus der Datei unter einem Pfad, höchstens so viele
/// Punkte an der langen Seite, mit einem Zeichen – als JPEG; `null`, wenn
/// sich das Bild nicht lesen lässt. Ersetzbar für Tests.
typedef Teilbildrechner =
    Future<List<int>?> Function(
      String pfad,
      int kante,
      Teilbildzeichenpixel? zeichen,
    );

/// Eigens auf oberster Ebene: Ein Abschluss innerhalb von [Teilbilder]
/// nähme seinen Kontext mit – samt Completer, und den kann kein Isolate
/// empfangen. Die Umwandlung scheiterte daran lautlos.
Future<List<int>?> _imIsolat(
  String pfad,
  int kante,
  Teilbildzeichenpixel? zeichen,
) => Isolate.run(() => _bereinigt(pfad, kante, zeichen));

Future<Zeichenpixel?> _pixelImIsolat(Uint8List daten) =>
    Isolate.run(() => Wasserzeichenbild.pixel(daten));

List<int>? _bereinigt(String pfad, int kante, Teilbildzeichenpixel? zeichen) {
  final roh = img.decodeImage(File(pfad).readAsBytesSync());
  if (roh == null) return null;
  // Erst aufrichten – danach fehlt die Angabe, wie herum es gehört.
  var bild = img.bakeOrientation(roh);
  final lang = math.max(bild.width, bild.height);
  if (lang > kante) {
    bild = bild.width >= bild.height
        ? img.copyResize(bild, width: kante)
        : img.copyResize(bild, height: kante);
  }
  if (zeichen != null) {
    bild = rechneZeichenpixelEin(bild, zeichen.pixel, zeichen.wasserzeichen);
  }
  bild.exif = img.ExifData();
  bild.iccProfile = null;
  return img.encodeJpg(bild, quality: 85);
}

/// Der Name einer Fassung im Ordner `geteilt`, ohne Endung: `<id>-m` für
/// die Miniatur, `<id>-a` für die Ansicht – mit Wasserzeichen (#497)
/// `<id>-<art>-<kennung>`, siehe [Wasserzeichen.kennung].
String teilbildName(String id, String art, [String? kennung]) =>
    kennung == null ? '$id-$art' : '$id-$art-$kennung';

/// Aufnahme und Kennung des Wasserzeichens aus dem Dateinamen einer
/// Fassung ([teilbildName] samt `.jpg`); `null` bei allem anderen.
///
/// Eindeutig, obwohl Kennungen von Aufnahmen selbst Bindestriche tragen:
/// Eine Fassung ohne Zeichen endet auf `-a.jpg` oder `-m.jpg`, eine mit
/// auf zwölf Hex-Zeichen.
({String id, String? kennung})? teilbildAusName(String dateiname) {
  final m = RegExp(
    r'^(.+)-[am](?:-([0-9a-f]{12}))?\.jpg$',
  ).firstMatch(dateiname);
  return m == null ? null : (id: m.group(1)!, kennung: m.group(2));
}
