import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
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
class Teilbilder {
  final _laufend = <String, Future<File?>>{};
  Future<void> _reihe = Future.value();

  /// Die bereinigte Fassung von [quelle], höchstens [kante] Punkte an der
  /// langen Seite; `null`, wenn sich das Bild nicht lesen lässt.
  Future<File?> fassung(
    Directory speicher,
    String name,
    File quelle, {
    required int kante,
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
          final bytes = await _imIsolat(quelle.path, kante);
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
Future<List<int>?> _imIsolat(String pfad, int kante) =>
    Isolate.run(() => _bereinigt(pfad, kante));

List<int>? _bereinigt(String pfad, int kante) {
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
  bild.exif = img.ExifData();
  bild.iccProfile = null;
  return img.encodeJpg(bild, quality: 85);
}
