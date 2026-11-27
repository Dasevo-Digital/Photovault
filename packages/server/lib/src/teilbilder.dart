import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

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
class Teilbilder {
  final _laufend = <String, Future<File?>>{};
  Future<void> _reihe = Future.value();

  /// Die bereinigte Fassung von [quelle], höchstens [kante] Punkte an der
  /// langen Seite, mit [wasserzeichen], sofern gegeben; `null`, wenn sich
  /// das Bild nicht lesen lässt.
  ///
  /// [wasserzeichen] muss ein Bild tragen ([Wasserzeichen.bild]). Lässt
  /// sich das nicht lesen, gibt es keine Fassung (`null`) statt einer ohne
  /// Zeichen: Wer ein Wasserzeichen gesetzt hat, soll sich darauf
  /// verlassen können.
  Future<File?> fassung(
    Directory speicher,
    String name,
    File quelle, {
    required int kante,
    Wasserzeichen? wasserzeichen,
  }) {
    final ziel = File(p.join(speicher.path, '$name.jpg'));
    return _laufend.putIfAbsent(ziel.path, () {
      final fertig = Completer<File?>();
      _reihe = _reihe.then((_) async {
        try {
          if (await ziel.exists() &&
              !(await ziel.lastModified()).isBefore(
                await quelle.lastModified(),
              )) {
            fertig.complete(ziel);
            return;
          }
          await speicher.create(recursive: true);
          final teil = File('${ziel.path}.teil');
          final bytes = await _imIsolat(quelle.path, kante, wasserzeichen);
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
}

/// Eigens auf oberster Ebene: Ein Abschluss innerhalb von [Teilbilder]
/// nähme seinen Kontext mit – samt Completer, und den kann kein Isolate
/// empfangen. Die Umwandlung scheiterte daran lautlos.
Future<List<int>?> _imIsolat(
  String pfad,
  int kante,
  Wasserzeichen? wasserzeichen,
) => Isolate.run(() => _bereinigt(pfad, kante, wasserzeichen));

List<int>? _bereinigt(String pfad, int kante, Wasserzeichen? wasserzeichen) {
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
  if (wasserzeichen != null) {
    final daten = wasserzeichen.bild;
    final zeichen = daten == null ? null : Wasserzeichenbild.lies(daten);
    if (zeichen == null) return null;
    bild = rechneWasserzeichenEin(bild, zeichen, wasserzeichen);
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
