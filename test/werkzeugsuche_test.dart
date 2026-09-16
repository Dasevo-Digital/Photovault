import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/native_image_converter.dart';
import 'package:photo_vault/services/platform/desktop_image_tools.dart';
import 'package:photo_vault/services/raw_formats.dart';

/// Die Fassung für Linux und Windows ruft Kommandozeilenwerkzeuge auf und
/// muss vorher wissen, welche davon es gibt. Diese Suche lief einmal über
/// `which` – ein eigenes Programm, das in einem knapp geschnürten Flatpak-
/// oder Container-Abbild fehlen kann. Fehlt es, meldete die Prüfung „kein
/// einziges Werkzeug vorhanden", obwohl alle da sind, und die halbe App
/// schaltete sich grundlos ab. Unter Windows gäbe es `which` ohnehin nicht.
///
/// Die Suche läuft deshalb selbst über den Programmordner und den `PATH`.
/// Genau dort sitzen auch die drei einzigen Unterschiede zwischen den
/// Plattformen: die Endung `.exe`, der Trenner `;` statt `:` und das
/// fehlende Ausführungsbit. Diese Datei prüft alle drei – jeweils dort, wo
/// sie gelten. Der plattformneutrale Teil läuft überall, auch auf macOS,
/// wo diese Schicht selbst nicht im Einsatz ist.
void main() {
  setUp(DesktopImageTools.vergissWerkzeuge);

  group('plattformneutral', () {
    test('findet nichts, wo nichts ist', () async {
      expect(
          await DesktopImageTools.imPfad('gibt-es-ganz-sicher-nicht-xyz'), isFalse);
    });

    test('ein gleichnamiges Verzeichnis gilt nicht als Werkzeug', () async {
      // Ohne diese Prüfung genügte ein Ordner namens „ffmpeg" im Suchpfad,
      // um die App glauben zu lassen, sie könne Videos verarbeiten.
      final temp = Directory.systemTemp.createTempSync('pv_pfad_');
      addTearDown(() => temp.deleteSync(recursive: true));
      // Unter Windows heisst das Werkzeug ffmpeg.exe – ein Verzeichnis mit
      // genau diesem Namen ist der Fall, den die Endungsprüfung allein
      // durchgehen liesse.
      final name = DesktopImageTools.dateiname('ffmpeg');
      Directory(p.join(temp.path, name)).createSync();

      // Der PATH lässt sich im Prozess nicht ändern – deshalb über den
      // absoluten Pfad, der denselben Zweig nimmt.
      expect(await DesktopImageTools.imPfad(p.join(temp.path, name)), isFalse);
    });

    test('neben der Anwendung wird zuerst gesucht', () async {
      // Unter Windows gibt es keine Paketquelle, aus der sich
      // heif-convert nachinstallieren liesse – die Werkzeuge liegen im
      // Programmordner (docs/plan_windows.md, Phase 6). Stünde der nicht
      // im Suchpfad, fände die App die mitgelieferten Werkzeuge nicht,
      // und zwar erst auf der Maschine des Nutzers.
      final pfade = DesktopImageTools.suchpfade();
      final neben = p.dirname(Platform.resolvedExecutable);
      expect(pfade.first, neben);
      expect(pfade[1], p.join(neben, 'tools'));

      // Und der PATH danach – sonst wäre die Suche auf den Programmordner
      // verengt und fände unter Linux nichts mehr.
      expect(pfade.length, greaterThan(2));
    });

    test('die Werkzeugliste nennt zu jedem Eintrag einen Zweck', () {
      // ffprobe muss einzeln dabeistehen: videoDauer ruft ausschliesslich
      // ffprobe auf, nur ffmpeg zu prüfen behauptete eine ungeprüfte
      // Verfügbarkeit.
      expect(DesktopImageTools.werkzeuge.keys,
          containsAll(['heif-dec', 'dcraw_emu', 'ffmpeg', 'ffprobe']));
      for (final zweck in DesktopImageTools.werkzeuge.values) {
        expect(zweck, isNotEmpty);
      }
    });

    test('AVIF geht an libheif, nicht an den RAW-Entwickler', () {
      // heicAndRawExtensions führt .avif ausdrücklich auf, die Verzweigung
      // in convertToJpeg prüfte aber nur .heic/.heif – alles andere ging
      // an dcraw_emu. Gemessen kam für eine echte AVIF-Datei `null`
      // zurück, also gar keine Vorschau, während heif-dec sie anstandslos
      // auspackte. Betrifft Linux genauso.
      for (final e in ['.heic', '.heif', '.avif', '.avifs']) {
        expect(DesktopImageTools.libheifEndungen, contains(e));
        expect(heicAndRawExtensions, contains(e),
            reason: 'sonst käme die Datei gar nicht erst hier an');
      }
      // Und umgekehrt: Nichts, was libheif nimmt, darf gleichzeitig als
      // RAW gelten – sonst entschiede die Reihenfolge der Prüfung.
      for (final e in DesktopImageTools.libheifEndungen) {
        expect(rawImageExtensions, isNot(contains(e)));
      }
    });

    test('heif-dec wird vor heif-convert gesucht', () {
      // libheif hat das Programm mit Fassung 1.18 umbenannt. Debian legt
      // noch einen Symlink unter dem alten Namen an, die MSYS2-Pakete für
      // Windows nicht – dort gibt es ausschliesslich heif-dec.exe. Wer nur
      // den alten Namen kennt, findet unter Windows nichts, und jedes
      // iPhone-Foto bliebe unsichtbar.
      expect(DesktopImageTools.alternativNamen['heif-dec'],
          ['heif-dec', 'heif-convert']);

      // Jeder alternative Name muss zu einem bekannten Werkzeug gehören –
      // sonst suchte die Schicht nach etwas, das sie nie aufruft.
      for (final werkzeug in DesktopImageTools.alternativNamen.keys) {
        expect(DesktopImageTools.werkzeuge.keys, contains(werkzeug));
      }
    });
  });

  group('Unix', () {
    test('findet ein Programm, das es überall gibt', () async {
      expect(await DesktopImageTools.imPfad('sh'), isTrue);
    });

    test('eine nicht ausführbare Datei gilt nicht als Werkzeug', () async {
      final temp = Directory.systemTemp.createTempSync('pv_pfad2_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final datei = File('${temp.path}/ffmpeg')..writeAsStringSync('kein Programm');

      expect(await DesktopImageTools.imPfad(datei.path), isFalse);

      // Mit gesetztem Ausführungsrecht dagegen schon.
      Process.runSync('chmod', ['+x', datei.path]);
      expect(await DesktopImageTools.imPfad(datei.path), isTrue);
    });

    test('der Name bleibt, wie er ist', () {
      expect(DesktopImageTools.dateiname('ffmpeg'), 'ffmpeg');
    });
  }, skip: Platform.isWindows ? 'gilt nur für Unix' : null);

  group('Windows', () {
    test('sucht nach der Endung .exe', () {
      expect(DesktopImageTools.dateiname('ffmpeg'), 'ffmpeg.exe');
      expect(DesktopImageTools.dateiname('heif-dec'), 'heif-dec.exe');
    });

    test('hängt keine zweite Endung an', () {
      // Suche und Aufruf gehen beide durch dateiname(). Ohne diese Regel
      // würde ein vollständiger Pfad zu „ffmpeg.exe.exe" und liefe ins
      // Leere – und zwar erst zur Laufzeit, nicht beim Bauen.
      expect(DesktopImageTools.dateiname(r'C:\Werkzeuge\ffmpeg.exe'),
          r'C:\Werkzeuge\ffmpeg.exe');
    });

    test('eine Datei ohne .exe gilt nicht als Werkzeug', () async {
      // Windows kennt kein Ausführungsbit. Bliebe die Endungsprüfung weg,
      // gälte jede beliebige gleichnamige Datei als das Werkzeug.
      final temp = Directory.systemTemp.createTempSync('pv_pfad3_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final text = File(p.join(temp.path, 'ffmpeg.txt'))
        ..writeAsStringSync('kein Programm');
      expect(await DesktopImageTools.imPfad(text.path), isFalse);
    });

    test('findet eine .exe im Suchpfad', () async {
      // Der Gegenbeweis zum Test darüber: Dieselbe Datei, nur mit der
      // richtigen Endung, muss gefunden werden. Sonst könnte die
      // Endungsprüfung schlicht alles ablehnen und beide Tests wären grün.
      final temp = Directory.systemTemp.createTempSync('pv_pfad4_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final exe = File(p.join(temp.path, 'ffmpeg.exe'))
        ..writeAsStringSync('kein echtes Programm, aber der Name zählt');
      expect(await DesktopImageTools.imPfad(exe.path), isTrue);
    });

    test('findet ein Programm, das es auf jedem Windows gibt', () async {
      // cmd liegt in %SystemRoot%\system32, und das steht im PATH. Damit
      // ist belegt, dass der Trenner stimmt: Mit Doppelpunkt getrennt
      // zerfiele jeder Eintrag am Laufwerksbuchstaben und die Suche fände
      // nichts.
      expect(await DesktopImageTools.imPfad('cmd'), isTrue);
    });
  }, skip: Platform.isWindows ? null : 'gilt nur für Windows');
}
