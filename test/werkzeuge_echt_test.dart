@TestOn('linux || windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/platform/desktop_image_tools.dart';

/// Der Ersatz für die nativen macOS-Funktionen war unter Linux
/// geschrieben, aber nie ausgeführt worden (docs/plan_linux.md, Phasen 2
/// und 4: „GESCHRIEBEN, UNGETESTET"). Diese Tests rufen ihn gegen echte
/// Dateien auf, erzeugt mit denselben Werkzeugen, die auch im Betrieb
/// gebraucht werden.
///
/// Läuft unter Linux und Windows – auf macOS gibt es weder heif-dec noch
/// dcraw_emu, und dort ist diese Schicht auch nicht im Einsatz.
///
/// **Diese Datei braucht echte Werkzeuge.** Fehlen sie, wird jeder
/// betroffene Test übersprungen statt zu scheitern: Eine Maschine ohne
/// ffmpeg soll die Suite nicht rot färben. Was übersprungen wurde, steht
/// in der Ausgabe – ein stiller Ausfall wäre das Gegenteil dessen, wofür
/// diese Datei da ist.
void main() {
  late Directory temp;

  /// Meldet den Test als übersprungen, wenn [werkzeug] fehlt.
  ///
  /// Nicht über `skip:`: Die Suche ist asynchron, `skip:` wird aber schon
  /// beim Einsammeln der Tests ausgewertet. Ohne diesen Handgriff wäre
  /// eine Maschine ohne libheif kein „übersprungen", sondern ein roter
  /// Test – und damit ununterscheidbar von einem echten Fund.
  Future<String?> hole(String werkzeug) async {
    final pfad = await DesktopImageTools.aufruf(werkzeug);
    if (pfad == null) markTestSkipped('$werkzeug ist auf dieser Maschine nicht installiert');
    return pfad;
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pv_linuxwerkzeuge_');
    DesktopImageTools.vergissWerkzeuge();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  group('HEIC', () {
    /// Eine echte HEIC-Datei als Vorlage.
    ///
    /// Nicht hier erzeugt: Die libheif der Linux-Maschine kann HEVC lesen, aber
    /// nicht schreiben („No HEVC encoder available") – ein Encoder ist ein
    /// eigenes Paket und für die App auch gar nicht nötig, sie muss HEIC nur
    /// lesen. Die Vorlage stammt deshalb von macOS (`sips -s format heic`)
    /// und zeigt dasselbe zweifarbige Muster: links rot,
    /// rechts grün, 1200x800. Damit lässt sich nach der Umwandlung prüfen,
    /// dass wirklich dieses Bild herauskam.
    final vorlage = File(p.join('test', 'fixtures', 'werkzeuge', 'probe.heic'));

    test('wird gelesen, skaliert und behält seinen Inhalt', () async {
      if (await hole('heif-dec') == null) return;
      final heic = File(p.join(temp.path, 'foto.heic'));
      heic.writeAsBytesSync(vorlage.readAsBytesSync());

      final jpeg = await DesktopImageTools.convertToJpeg(heic, maxDimension: 600);

      expect(jpeg, isNotNull, reason: 'HEIC blieb unlesbar – genau der Fall, '
          'in dem unter Linux jedes iPhone-Foto unsichtbar wäre');
      final zurueck = img.decodeImage(jpeg!)!;
      expect(zurueck.width, 600, reason: 'auf die längste Kante skaliert');
      expect(zurueck.height, 400);

      // Links rot, rechts grün – wenn das stimmt, ist es wirklich unser Bild.
      final links = zurueck.getPixel(60, 200);
      final rechts = zurueck.getPixel(540, 200);
      expect(links.r, greaterThan(150));
      expect(links.g, lessThan(120));
      expect(rechts.g, greaterThan(80));
      expect(rechts.r, lessThan(120));
    }, skip: !vorlage.existsSync() ? 'Vorlage fehlt' : null);
  });

  group('AVIF', () {
    /// 535 Bytes, links rot, rechts grün – mit ffmpeg und SVT-AV1 erzeugt.
    ///
    /// So klein, weil AV1 eine einfarbige Fläche fast umsonst kodiert. Sie
    /// darf deshalb im Repository liegen.
    final vorlage = File(p.join('test', 'fixtures', 'werkzeuge', 'probe.avif'));

    test('wird über libheif gelesen, nicht über den RAW-Entwickler', () async {
      if (await hole('heif-dec') == null) return;
      final avif = File(p.join(temp.path, 'foto.avif'));
      avif.writeAsBytesSync(vorlage.readAsBytesSync());

      final jpeg = await DesktopImageTools.convertToJpeg(avif, maxDimension: 400);

      expect(jpeg, isNotNull,
          reason: 'AVIF ohne Vorschau – genau der Zustand, in dem die Datei '
              'an dcraw_emu ging, der kein AVIF lesen kann');
      final zurueck = img.decodeImage(jpeg!)!;
      expect(zurueck.width, 400);

      // Links rot, rechts grün – sonst ist es irgendein Bild, nicht dieses.
      final links = zurueck.getPixel(40, 200);
      final rechts = zurueck.getPixel(360, 200);
      expect(links.r, greaterThan(120));
      expect(links.g, lessThan(100));
      expect(rechts.g, greaterThan(80));
      expect(rechts.r, lessThan(120));
    }, skip: !vorlage.existsSync() ? 'Vorlage fehlt' : null);
  });

  group('Aufnahmewerte aus RAW', () {
    /// Genau die Datei, an der der Fehler auffiel: eine Canon EOS R10 im
    /// CR3-Format. CC0 von raw.pixls.us, geholt von
    /// `tool/fetch_format_samples.sh`.
    ///
    /// Warum nicht die DNG-Probe von oben: DNG ist TIFF-basiert, dort hat
    /// `package:exif` immer gelesen. CR3 ist ein ISO-BMFF-Container wie
    /// MP4 – erst dort liefert es NULL Tags, und erst dort wird
    /// `raw-identify` gebraucht.
    final vorlage = File(p.join('test', 'fixtures', 'samples', 'canon_eos_r10.cr3'));

    test('raw-identify liefert Kamera, Objektiv und Aufnahmezeitpunkt', () async {
      if (await hole('raw-identify') == null) return;
      final quelle = File(p.join(temp.path, 'aufnahme.cr3'));
      quelle.writeAsBytesSync(vorlage.readAsBytesSync());

      final d = await DesktopImageTools.leseAufnahmedaten(quelle);

      // Dieselben Werte, die ImageIO auf macOS aus derselben Datei liest –
      // gegeneinander gehalten, damit die Bibliothek nicht davon abhängt,
      // auf welchem System importiert wurde.
      expect(d.kamera.model, 'Canon EOS R10');
      expect(d.kamera.make, 'Canon');
      expect(d.kamera.lensModel, 'EF50mm f/1.8 STM');
      expect(d.kamera.iso, 1600);
      expect(d.kamera.fNumber, closeTo(1.8, 0.001));
      expect(d.kamera.focalLengthMm, closeTo(50.0, 0.001));
      expect(d.zeitpunkt, DateTime(2022, 8, 19, 19, 19, 28));
    }, skip: !vorlage.existsSync()
        ? 'test/fixtures/samples/canon_eos_r10.cr3 fehlt – tool/fetch_format_samples.sh'
        : null);

    test('fehlt das Werkzeug, kommt Leeres zurück statt einer Ausnahme', () async {
      final unbekannt = File(p.join(temp.path, 'gibtsnicht.cr3'));
      final d = await DesktopImageTools.leseAufnahmedaten(unbekannt);
      expect(d.isEmpty, isTrue);
    });
  });

  group('RAW', () {
    /// Eine echte Kameradatei, nicht im Repository.
    ///
    /// RAW-Dateien sind 10–50 MB gross; zwei davon in der Historie wären
    /// mehr als der gesamte übrige Quelltext. `tool/fetch_format_samples.sh`
    /// lädt sie bei Bedarf von raw.pixls.us (CC0) und prüft die Prüfsumme.
    /// Fehlt die Datei, wird dieser Test übersprungen statt zu scheitern.
    final vorlage = File(p.join('test', 'fixtures', 'samples', 'iphone_6s_plus.dng'));

    test('wird entwickelt, skaliert und lässt das Original in Ruhe', () async {
      if (await hole('dcraw_emu') == null) return;
      final quelle = File(p.join(temp.path, 'aufnahme.dng'));
      quelle.writeAsBytesSync(vorlage.readAsBytesSync());
      final vorher = quelle.lengthSync();
      final nachbarn = temp.listSync().length;

      final jpeg = await DesktopImageTools.convertToJpeg(quelle, maxDimension: 800);

      expect(jpeg, isNotNull, reason: 'RAW blieb unlesbar');
      final bild = img.decodeImage(jpeg!)!;
      expect(bild.width == 800 || bild.height == 800, isTrue,
          reason: 'auf die längste Kante skaliert, war ${bild.width}x${bild.height}');

      // Das ist der Punkt, für den die Datei überhaupt erst in den
      // Temp-Ordner kopiert wird: dcraw_emu schreibt sein Ergebnis NEBEN
      // die Eingabe. Täte es das in der Bibliothek, läge dort zu jedem RAW
      // eine 36-MB-TIFF-Datei, die niemand bestellt hat.
      expect(quelle.lengthSync(), vorher, reason: 'Original verändert');
      expect(temp.listSync().length, nachbarn,
          reason: 'im Ordner der Eingabe ist etwas liegen geblieben');
    }, skip: !vorlage.existsSync()
        ? 'RAW-Vorlage fehlt (nicht im Repository, siehe oben)'
        : null);
  });

  group('Video', () {
    /// Legt ein Testvideo an – über denselben Pfad, den auch die Schicht
    /// benutzt. Der blosse Name „ffmpeg" genügte nicht: Unter Windows
    /// heisst die Datei `ffmpeg.exe`, und liegt sie im Programmordner
    /// statt im PATH, findet ein Aufruf über den Namen sie gar nicht.
    Future<File?> legeVideo(String name, {int sekunden = 4}) async {
      final ffmpeg = await hole('ffmpeg');
      if (ffmpeg == null) return null;
      final datei = File(p.join(temp.path, name));
      final r = await Process.run(ffmpeg, [
        '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'testsrc=size=640x480:rate=25:duration=$sekunden',
        // mpeg4 statt libx264: Das mitgelieferte ffmpeg ist die
        // LGPL-Fassung und hat gar keinen H.264-Encoder. Die App braucht
        // auch keinen – sie schneidet mit `-c copy` und schreibt
        // Vorschaubilder als JPEG. Mit libx264 prüfte dieser Test also
        // eine Fähigkeit, die im Paket weder vorhanden noch nötig ist,
        // und wurde rot, sobald das Paket im PATH stand.
        '-c:v', 'mpeg4', '-pix_fmt', 'yuv420p', datei.path,
      ]);
      expect(r.exitCode, 0, reason: 'ffmpeg: ${r.stderr}');
      return datei;
    }

    test('Vorschaubild und Länge', () async {
      final video = await legeVideo('film.mp4');
      if (video == null) return;
      // Die Länge kommt ausschliesslich von ffprobe. Es steht nicht ohne
      // Grund einzeln in der Werkzeugliste.
      if (await hole('ffprobe') == null) return;

      final ergebnis = await DesktopImageTools.videoThumbnail(video, maxDimension: 320);

      expect(ergebnis, isNotNull);
      final bild = img.decodeImage(ergebnis!.jpeg)!;
      expect(bild.width, 320);
      expect(ergebnis.dauerSekunden, closeTo(4.0, 0.3));

      // Nicht nur irgendein Bild, sondern ein sichtbares: der Testbild-
      // Generator liefert bunte Balken, ein schwarzer Frame wäre der Fehler,
      // gegen den die Sekunde-1-Regel überhaupt eingebaut wurde.
      var hell = 0;
      for (var x = 0; x < bild.width; x += 8) {
        for (var y = 0; y < bild.height; y += 8) {
          if (bild.getPixel(x, y).luminance > 40) hell++;
        }
      }
      expect(hell, greaterThan(0), reason: 'der Frame war vollständig schwarz');
    });

    test('Zuschnitt trifft die verlangte Länge', () async {
      final video = await legeVideo('lang.mp4', sekunden: 10);
      if (video == null) return;
      if (await hole('ffprobe') == null) return;
      final ziel = p.join(temp.path, 'kurz.mp4');

      final ok = await DesktopImageTools.trimVideo(video,
          startSekunden: 2, endSekunden: 6, zielPfad: ziel);

      expect(ok, isTrue);
      expect(File(ziel).existsSync(), isTrue);
      // Verlustfrei geschnitten wird an Schlüsselbildern – die Länge darf
      // deshalb um bis zu einen Schlüsselbild-Abstand abweichen, aber nicht
      // beliebig. Ein falsch gereihtes -ss/-to ergäbe hier die volle Länge
      // oder fast nichts.
      final dauer = await DesktopImageTools.videoDauer(File(ziel));
      expect(dauer, isNotNull);
      expect(dauer!, closeTo(4.0, 1.2), reason: 'gewünscht waren 4 Sekunden');
    });
  });
}
