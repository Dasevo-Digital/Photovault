import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/import_service.dart';

/// **Was die App herausrendert, trägt seinen Farbraum bei sich.**
///
/// Gemessen an der echten Bibliothek: Eine iPhone-HEIC in Display P3 mit
/// Apple-HDR-Gainmap ergab eine Vorschau **ohne jedes Farbprofil** – und
/// eine Datei ohne Profil liest jedes Programm als sRGB. Der Grund stand
/// an drei Stellen in `ImageConverter.swift`:
///
/// ```swift
/// guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
/// ```
///
/// ImageIO schreibt für sRGB gar kein Profil in die Datei; erst ein
/// anderer Raum wird eingebettet. Nachgemessen mit derselben API:
///
/// ```
/// gerendert nach sRGB        -> exiftool findet kein ProfileDescription
/// gerendert nach Display P3  -> „Display P3"
/// ```
///
/// Betroffen sind 42 von 80 geprüften iPhone-Aufnahmen (Display P3) und
/// alles, was aus RAW entwickelt wird – dort gibt es gar keinen Farbraum
/// in der Datei, der Renderer legt ihn fest.
///
/// Die Miniaturen waren nie das Problem: Das `image`-Paket trägt ein
/// vorhandenes ICC-Profil durch Dekodieren, Verkleinern und Kodieren
/// hindurch (nachgemessen an 25 iPhone-JPEGs: 18 mit Display P3 im
/// Original, 18 mit Display P3 in der Miniatur).
///
/// Dieser Prüfstand liest den Quelltext, weil das die Form des Fehlers
/// ist: nicht ein falsches Ergebnis, sondern eine Zeile, die an drei
/// Stellen dasselbe festlegte.
void main() {
  final quelle = File('macos/Runner/ImageConverter.swift').readAsStringSync();

  test('der Ausgabefarbraum ist Display P3', () {
    expect(
      quelle,
      contains('CGColorSpace(name: CGColorSpace.displayP3)'),
      reason: 'ohne einen weiten Ausgabefarbraum bettet ImageIO gar kein '
          'Profil ein, und jede Aufnahme wird als sRGB gelesen',
    );
  });

  test('jede Ausgabe geht über denselben Farbraum', () {
    // Der Fehler war nicht, dass sRGB falsch gewesen wäre – sondern dass
    // die Entscheidung dreimal getroffen wurde. Sie steht jetzt einmal.
    final stellen = 'ausgabefarbraum'.allMatches(quelle).length;
    expect(stellen, greaterThanOrEqualTo(4),
        reason: 'eine Erklärung und drei Verwendungen');

    // Und keine davon legt sich daneben noch einmal selbst fest.
    final rumpf = quelle.substring(quelle.indexOf('class ImageConverterChannel'));
    for (final stelle in _renderAufrufe(rumpf)) {
      expect(stelle, contains('colorSpace: colorSpace'),
          reason: 'createCGImage soll den gemeinsamen Raum nehmen:\n$stelle');
    }
  });

  test('der Arbeitsfarbraum von Kurve und Farbmischer bleibt sRGB', () {
    // **Nicht dasselbe wie der Ausgabefarbraum.** Er bestimmt, in welchem
    // Raum die Gradationskurve und der Farbmischer rechnen – und die
    // Dart-Seite stellt für die Shader-Vorschau dieselbe Rechnung an.
    // Stünde hier P3, zeigte die Vorschau beim Ziehen am Regler etwas
    // anderes als das gerenderte Ergebnis.
    final abschnitt = quelle.substring(
        quelle.indexOf('func applyCurveAndMixer'),
        quelle.indexOf('func applyCurveAndMixer') + 900);
    expect(abschnitt, contains('CGColorSpace(name: CGColorSpace.sRGB)'));
    expect(abschnitt, contains('Arbeitsfarbraum'),
        reason: 'der Unterschied muss dort stehen, wo er gilt');
  });

  test('die Swift-Liste der RAW-Endungen deckt sich weiter mit Dart', () {
    // Mitgeprüft, weil dieselbe Datei angefasst wurde: Die Swift-Seite
    // führt die Liste von Hand nach (sie kann die Dart-Datei nicht
    // importieren), und beide auseinanderlaufen zu lassen hiesse, dass ein
    // Format auf einem Weg entwickelt wird und auf dem anderen nicht.
    final dart = File('lib/services/raw_formats.dart').readAsStringSync();
    final dartEndungen = RegExp(r"'(\.[a-z0-9]+)'")
        .allMatches(dart.substring(dart.indexOf('rawImageExtensions'),
            dart.indexOf('/// Dieselben Endungen ohne Punkt')))
        .map((m) => m.group(1)!)
        .toSet();
    expect(dartEndungen.length, greaterThan(20), reason: 'Liste gefunden?');

    final swiftAbschnitt = quelle.substring(quelle.indexOf('rawExtensions'));
    final fehlend = [
      for (final e in dartEndungen)
        if (!swiftAbschnitt.contains('"${e.substring(1)}"')) e,
    ];
    expect(fehlend, isEmpty,
        reason: 'diese Endungen kennt nur die Dart-Seite: $fehlend');
  });

  group('Der Weg zur Miniatur behält das Profil', () {
    /// Ein Bild mit angehängtem Farbprofil. Der Inhalt des Profils spielt
    /// hier keine Rolle – geprüft wird, ob es die Kette übersteht.
    img.Image mitProfil() {
      final bild = img.Image(width: 900, height: 600);
      img.fill(bild, color: img.ColorRgb8(200, 120, 60));
      bild.iccProfile = img.IccProfile(
          'ICC_PROFILE', img.IccProfileCompression.none,
          Uint8List.fromList(List<int>.generate(538, (i) => i % 256)));
      return bild;
    }

    test('decodeAndResizeThumbnail wirft es nicht weg', () {
      final quelle = Uint8List.fromList(img.encodeJpg(mitProfil(), quality: 90));
      final ergebnis = decodeAndResizeThumbnail(quelle)!;
      final mini = img.decodeImage(ergebnis.jpegBytes)!;
      expect(mini.iccProfile, isNotNull,
          reason: 'sonst ist jede Miniatur eines P3-Fotos stillschweigend '
              'sRGB – und das Raster zeigt andere Farben als der Betrachter');
      expect(mini.iccProfile!.data.length, 538);
      // Und die Miniatur ist trotzdem eine Miniatur.
      expect(mini.width, 400);
    });

    test('ein Bild ohne Profil bekommt auch keins angedichtet', () {
      final ohne = img.Image(width: 900, height: 600);
      img.fill(ohne, color: img.ColorRgb8(10, 20, 30));
      final ergebnis = decodeAndResizeThumbnail(
          Uint8List.fromList(img.encodeJpg(ohne, quality: 90)))!;
      expect(img.decodeImage(ergebnis.jpegBytes)!.iccProfile, isNull);
    });
  });
}

/// Alle `createCGImage(...)`-Aufrufe samt Argumenten.
List<String> _renderAufrufe(String quelle) {
  final treffer = <String>[];
  var ab = 0;
  while (true) {
    final start = quelle.indexOf('createCGImage(', ab);
    if (start < 0) break;
    final ende = quelle.indexOf(')', start);
    treffer.add(quelle.substring(start, ende < 0 ? quelle.length : ende + 1));
    ab = start + 1;
  }
  return treffer;
}