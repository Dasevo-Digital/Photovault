import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../raw_identify_parser.dart';
import '../standort_parser.dart';

/// Die Bildfähigkeiten für alle Plattformen ohne Apples ImageIO – also
/// Linux und Windows.
///
/// Dort gibt es weder ImageIO noch AVFoundation. Statt eigene FFI-Wrapper
/// für libheif/LibRaw/libavcodec zu bauen (für keine dieser Bibliotheken
/// existiert ein brauchbares Dart-Paket, siehe docs/plan_linux.md), werden
/// die etablierten Kommandozeilenwerkzeuge aufgerufen. Ausgeliefert als
/// Flatpak bzw. im Windows-Programmordner sind sie mitgeliefert und damit
/// vorhanden.
///
/// Die beiden Plattformen unterscheiden sich an genau drei Stellen, und
/// alle drei stecken in der Werkzeugsuche: die Endung `.exe`, der Trenner
/// im `PATH` (`;` statt `:`) und das fehlende Ausführungsbit. Die Aufrufe
/// selbst sind gleich – sie laufen über `Process.run` mit Argumentlisten,
/// nicht über eine Shell, weshalb Leerzeichen und Laufwerksbuchstaben in
/// Pfaden bereits richtig behandelt sind.
///
/// Jede Funktion gibt `null`/`false` zurück, wenn das jeweilige Werkzeug
/// fehlt – die App bleibt dann benutzbar, nur diese eine Fähigkeit fehlt.
class DesktopImageTools {
  DesktopImageTools._();

  /// Wo die Werkzeuge gefunden wurden – `null`, wo keins gefunden wurde.
  static Map<String, String?>? _gefunden;

  /// Gebrauchte Werkzeuge und wofür.
  ///
  /// `ffprobe` steht einzeln dabei, obwohl es meist zusammen mit `ffmpeg`
  /// installiert wird: [videoDauer] ruft ausschliesslich ffprobe auf. Nur
  /// ffmpeg zu prüfen hiesse, eine Verfügbarkeit zu behaupten, die man
  /// nicht geprüft hat – und die Videolänge fiele still auf null zurück.
  static const werkzeuge = <String, String>{
    'heif-dec': 'HEIC/HEIF-Fotos (Linux: Paket libheif-examples)',
    'dcraw_emu': 'RAW-Fotos (Linux: Paket libraw-bin)',
    'raw-identify': 'Kamera/Objektiv aus RAW-Fotos (Linux: Paket libraw-bin)',
    'ffmpeg': 'Video-Vorschaubilder und Videoschnitt',
    'ffprobe': 'Videolänge (Teil von ffmpeg)',
  };

  /// Unter welchen Namen ein Werkzeug auftreten kann, in Suchreihenfolge.
  ///
  /// libheif hat sein Umwandlungsprogramm mit Fassung 1.18 von
  /// `heif-convert` in `heif-dec` umbenannt. Debian legt beim Einspielen
  /// noch einen Symlink unter dem alten Namen an – die MSYS2-Pakete für
  /// Windows nicht, dort gibt es ausschliesslich `heif-dec.exe`. Wer nur
  /// nach `heif-convert` sucht, findet unter Windows also gar nichts, und
  /// jedes iPhone-Foto bliebe unsichtbar.
  ///
  /// Genau dieser Symlink war unter Linux schon einmal die Ursache eines
  /// Ausfalls: Beim Aufräumen des Flatpak-Bündels fiel `heif-dec` weg und
  /// `heif-convert` zeigte ins Leere. Beide Namen zu kennen ist deshalb
  /// nicht nur eine Windows-Frage.
  @visibleForTesting
  static const alternativNamen = <String, List<String>>{
    'heif-dec': ['heif-dec', 'heif-convert'],
  };

  /// Welche Endungen über libheif laufen – und nicht über den
  /// RAW-Entwickler.
  ///
  /// Nicht nur HEIC: AVIF ist derselbe Container mit AV1 statt HEVC, und
  /// der dav1d-Dekoder liegt im selben Bündel. Vorher stand hier nur
  /// `.heic`/`.heif`, und alles andere ging an `dcraw_emu` – auch
  /// `.avif`, das in [heicAndRawExtensions] ausdrücklich aufgeführt ist.
  /// Ein RAW-Entwickler kann kein AVIF: gemessen kam `null` zurück, also
  /// gar keine Vorschau, während `heif-dec` dieselbe Datei anstandslos
  /// auspackte. Betrifft Linux genauso; unter macOS fällt es nicht auf,
  /// weil ImageIO AVIF selbst kann.
  static const libheifEndungen = {'.heic', '.heif', '.avif', '.avifs'};

  /// Liest Kamera, Objektiv, Aufnahmewerte und Aufnahmezeitpunkt aus einer
  /// RAW-Datei über `raw-identify` (LibRaw).
  ///
  /// Gebraucht wird das, weil `package:exif` nur TIFF/JPEG kann. Canons
  /// CR3 ist ein ISO-BMFF-Container wie MP4 – dort kamen gemessen NULL
  /// Tags heraus, und damit fehlten Kamera, Objektiv UND das
  /// Aufnahmedatum. `raw-identify` gehört zu demselben Paket wie
  /// `dcraw_emu`, war aus dem Flatpak aber ausdrücklich wegaufgeräumt.
  ///
  /// Gibt [Aufnahmedaten.leer] zurück, wenn das Werkzeug fehlt oder die
  /// Datei nichts hergibt – nie eine Ausnahme.
  static Future<Aufnahmedaten> leseAufnahmedaten(File datei) async {
    final pfad = await aufruf('raw-identify');
    if (pfad == null) return Aufnahmedaten.leer;
    try {
      final ergebnis = await Process.run(pfad, ['-v', datei.path]);
      if (ergebnis.exitCode != 0) return Aufnahmedaten.leer;
      return parseRawIdentify(ergebnis.stdout as String);
    } on ProcessException {
      return Aufnahmedaten.leer;
    }
  }

  /// Der Ortungshelfer, der neben der Anwendung liegt.
  ///
  /// Bewusst **nicht** in [werkzeuge]: Diese Liste ist die gemeinsame
  /// Werkzeugdiagnose für Linux und Windows. Den Helfer gibt es nur unter
  /// Windows – in der Linux-Diagnose stünde er auf ewig als „fehlt", und
  /// eine Prüfliste, die dauerhaft rot ist, liest irgendwann niemand mehr.
  static const standortHelfer = 'pv_standort';

  /// Der aktuelle Standort über Windows' eigene Ortung.
  ///
  /// `null` heisst „nicht zu ermitteln": kein Helfer, keine Erlaubnis,
  /// keine Antwort – oder eine Antwort, der nicht zu trauen ist. Die
  /// Beurteilung steckt in [parseStandort]; hier wird nur aufgerufen.
  ///
  /// Unter Linux gibt es das nicht. GeoClue wäre da, endet aber bei
  /// beacondb, und das kannte im Test keinen einzigen Zugangspunkt der
  /// Umgebung – siehe docs/ortung.md.
  static Future<Ortung?> standort() async {
    if (!Platform.isWindows) return null;
    final pfad = await _findePfad(standortHelfer);
    if (pfad == null) return null;
    try {
      // Der Helfer bricht nach zwölf Sekunden selbst ab; die Grenze hier
      // ist nur der Notnagel, falls er gar nicht erst hochkommt. Deshalb
      // genügt es, das Warten zu beenden – ein Prozess, der sich selbst
      // begrenzt, muss nicht auch noch erschlagen werden.
      final ergebnis = await Process.run(pfad, const <String>[])
          .timeout(const Duration(seconds: 20));
      return parseStandort(ergebnis.stdout as String);
    } on ProcessException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  /// Verwirft das gemerkte Ergebnis – für Tests und für den Fall, dass
  /// jemand ein Werkzeug nachinstalliert, ohne die App neu zu starten.
  static void vergissWerkzeuge() => _gefunden = null;

  /// Setzt das Suchergebnis von aussen – **nur für Tests**.
  ///
  /// Nötig, weil die echte Suche den `PATH` der Maschine liest, auf der
  /// der Test läuft. Ein Test, der behauptet „hier gibt es kein ffmpeg",
  /// prüfte auf einem Entwicklerrechner mit Homebrew genau nichts – er
  /// ginge durch, egal was der Quelltext tut. Genau daran ist mir die
  /// erste Fassung der Videoprüfung vorbeigelaufen.
  @visibleForTesting
  static void stelleWerkzeuge(Map<String, String?> werte) =>
      _gefunden = Map.of(werte);

  /// Sucht einmalig jedes Werkzeug und merkt sich, **wo** es liegt.
  ///
  /// Nicht nur ob: Ein Werkzeug im Programmordner steht nicht im `PATH`,
  /// ein Aufruf über den blossen Namen liefe dann ins Leere. Gemerkt wird
  /// deshalb der vollständige Pfad, und [Process.run] bekommt genau den.
  static Future<Map<String, String?>> _suche() async {
    if (_gefunden != null) return _gefunden!;
    final ergebnis = <String, String?>{};
    for (final werkzeug in werkzeuge.keys) {
      String? pfad;
      for (final name in alternativNamen[werkzeug] ?? [werkzeug]) {
        pfad = await _findePfad(name);
        if (pfad != null) break;
      }
      ergebnis[werkzeug] = pfad;
    }
    return _gefunden = ergebnis;
  }

  /// Welche Werkzeuge vorhanden sind – für die Anzeige und die Diagnose.
  static Future<Map<String, bool>> pruefeWerkzeuge() async => {
        for (final e in (await _suche()).entries) e.key: e.value != null,
      };

  /// Der vollständige Pfad, unter dem [werkzeug] gefunden wurde, oder
  /// `null`, wenn es fehlt.
  ///
  /// Die Aufrufe unten gehen alle hierdurch. Damit kann die Suche nichts
  /// finden, was der Aufruf nicht startet – und umgekehrt.
  ///
  /// **Nicht mehr nur für Tests.** Der Videoexport
  /// (`services/flugvideo.dart`) startet ffmpeg selbst und mit eigenen
  /// Schaltern; er braucht den Pfad, nicht einen weiteren Helfer hier.
  /// Der Weg über diese Stelle bleibt trotzdem der einzige – auch für
  /// ihn gilt: Was die Suche nicht findet, startet niemand.
  static Future<String?> aufruf(String werkzeug) async =>
      (await _suche())[werkzeug];

  /// Ob [befehl] aufrufbar ist – im Programmordner oder im `PATH`.
  ///
  /// Selbst nachgesehen statt `which` aufzurufen. `which` ist ein eigenes
  /// Programm (debianutils), kein eingebauter Befehl – in einem knapp
  /// geschnürten Flatpak- oder Container-Abbild fehlt es leicht. Dann
  /// meldete diese Prüfung „kein einziges Werkzeug vorhanden", obwohl alle
  /// da sind, und die halbe App schaltete sich grundlos ab. Unter Windows
  /// gäbe es ohnehin kein `which`. Nebenbei entfällt ein Prozessstart je
  /// Werkzeug.
  @visibleForTesting
  static Future<bool> imPfad(String befehl) async =>
      await _findePfad(befehl) != null;

  /// Der Dateiname, unter dem [befehl] auf dieser Plattform zu finden ist.
  ///
  /// Unter Windows heißt `ffmpeg` als Datei `ffmpeg.exe`. Suche und Aufruf
  /// benutzen beide diese Funktion – sonst könnte die Suche etwas finden,
  /// das der Aufruf nicht startet, oder umgekehrt. Eine bereits vorhandene
  /// Endung bleibt unangetastet, damit ein vollständiger Pfad nicht zu
  /// `ffmpeg.exe.exe` wird.
  @visibleForTesting
  static String dateiname(String befehl) =>
      Platform.isWindows && p.extension(befehl).isEmpty
          ? '$befehl$_windowsEndung'
          : befehl;

  /// Die einzige Endung, die hier als ausführbar gilt.
  ///
  /// Bewusst nicht `PATHEXT`: `.bat` und `.cmd` lassen sich mit
  /// `Process.run` gar nicht starten (Windows braucht dafür `cmd.exe`), und
  /// sie als gefunden zu melden hiesse, eine Fähigkeit zu behaupten, die
  /// beim ersten Aufruf scheitert.
  static const _windowsEndung = '.exe';

  /// Wo gesucht wird, in dieser Reihenfolge.
  ///
  /// Offen für Tests, weil der Programmordner-Zweig sonst unbelegt bliebe:
  /// `Platform.resolvedExecutable` zeigt unter `flutter test` auf den
  /// Testläufer, nicht auf die App – ein Werkzeug dorthin zu legen prüfte
  /// also nichts, was im Betrieb gilt.
  @visibleForTesting
  static List<String> suchpfade() => _suchpfade();

  static List<String> _suchpfade() {
    final ordner = <String>[];
    // Zuerst neben der Anwendung. Unter Windows gibt es keine Paketquelle,
    // aus der sich heif-convert nachinstallieren liesse – die Werkzeuge
    // liegen deshalb im Programmordner (siehe docs/plan_windows.md,
    // Phase 6). Unter Linux schadet der Blick nicht: Im Flatpak liegen sie
    // in /app/bin und damit ohnehin im PATH.
    try {
      final neben = p.dirname(Platform.resolvedExecutable);
      ordner..add(neben)..add(p.join(neben, 'tools'));
    } catch (_) {
      // Kein Programmpfad ermittelbar – dann eben nur der PATH.
    }
    final pfad = Platform.environment['PATH'];
    if (pfad != null && pfad.isNotEmpty) {
      // Windows trennt mit Semikolon. Mit Doppelpunkt zu trennen zerlegte
      // dort jeden Eintrag am Laufwerksbuchstaben („C", „\\Programme\\…").
      for (final teil in pfad.split(Platform.isWindows ? ';' : ':')) {
        // Einträge mit Leerzeichen stehen unter Windows gelegentlich in
        // Anführungszeichen. Blieben sie stehen, zeigte der Pfad ins Leere.
        final sauber = teil.trim().replaceAll('"', '');
        if (sauber.isNotEmpty) ordner.add(sauber);
      }
    }
    return ordner;
  }

  /// Wo [befehl] liegt, oder `null`.
  static Future<String?> _findePfad(String befehl) async {
    final datei = dateiname(befehl);
    // Ein Pfad im Namen wäre keine PATH-Suche mehr – dann direkt prüfen.
    // Beide Trenner, weil Windows auch Schrägstriche akzeptiert.
    if (datei.contains('/') || datei.contains(r'\')) {
      return await _istAusfuehrbar(datei) ? datei : null;
    }
    for (final ordner in _suchpfade()) {
      final voll = p.join(ordner, datei);
      if (await _istAusfuehrbar(voll)) return voll;
    }
    return null;
  }

  static Future<bool> _istAusfuehrbar(String pfad) async {
    try {
      // Vorhanden genügt nicht – ein Verzeichnis gleichen Namens darf nicht
      // als Werkzeug gelten. Symlinks werden dabei verfolgt: Im Flatpak ist
      // heif-convert einer.
      if (await FileSystemEntity.type(pfad) != FileSystemEntityType.file) {
        return false;
      }
      if (Platform.isWindows) {
        // Windows kennt kein Ausführungsbit; ausführbar ist, was die Endung
        // sagt. Sie steht durch [dateiname] normalerweise schon dran – hier
        // wird sie geprüft, damit ein absoluter Pfad auf eine Textdatei
        // nicht durchgeht.
        return p.extension(pfad).toLowerCase() == _windowsEndung;
      }
      final rechte = (await File(pfad).stat()).mode;
      return rechte & 0x49 != 0; // --x--x--x
    } catch (_) {
      return false;
    }
  }

  /// Wandelt HEIC/HEIF/AVIF oder RAW in JPEG-Bytes, skaliert auf
  /// [maxDimension].
  ///
  /// Die Werkzeuge können selbst nicht skalieren, deshalb wird die
  /// Zwischendatei anschließend mit dem `image`-Paket verkleinert – in
  /// einem Isolate, damit die UI nicht blockiert (Muster: der bestehende
  /// Thumbnail-Pfad in import_service.dart).
  /// **Zum Farbraum.** Was hier herauskommt, trägt das Profil, das das
  /// Werkzeug hineingeschrieben hat: `heif-dec` reicht das ICC-Profil einer
  /// HEIC durch, und das `image`-Paket trägt es beim Verkleinern und
  /// Kodieren weiter (nachgemessen). `dcraw_emu` dagegen entwickelt
  /// voreingestellt nach sRGB – RAW-Vorschauen sind auf Linux und Windows
  /// also sRGB, während sie auf macOS seit der Umstellung Display P3 sind
  /// (siehe `ausgabefarbraum` in ImageConverter.swift).
  ///
  /// Bewusst nicht angeglichen: `dcraw_emu -o 7` gäbe DCI-P3-Zahlen aus,
  /// und die TIFF-Ausgabe trägt kein Profil dazu. Weite Farben ohne Profil
  /// sind schlechter als enge mit – sie werden als sRGB gelesen und sehen
  /// dann falsch aus, statt nur blass.
  static Future<Uint8List?> convertToJpeg(
    File datei, {
    int maxDimension = 2048,
    int quality = 90,
  }) async {
    final endung = p.extension(datei.path).toLowerCase();

    Directory? temp;
    try {
      temp = await Directory.systemTemp.createTemp('pv_convert_');
      final ziel = p.join(temp.path, 'out.jpg');

      if (libheifEndungen.contains(endung)) {
        final werkzeug = await aufruf('heif-dec');
        if (werkzeug == null) return null;
        final r = await Process.run(werkzeug, [datei.path, ziel]);
        if (r.exitCode != 0) return null;
        // Enthält die Datei mehrere Bilder (Serienaufnahmen, Live Photos),
        // schreibt heif-dec nicht "out.jpg", sondern "out-1.jpg" usw.
        // Dann das erste davon nehmen, statt an der fehlenden out.jpg zu
        // scheitern.
        if (!await File(ziel).exists()) {
          final erstes = temp
              .listSync()
              .whereType<File>()
              .where((f) => p.basename(f.path).startsWith('out-'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
          if (erstes.isEmpty) return null;
          await erstes.first.rename(ziel);
        }
      } else {
        final werkzeug = await aufruf('dcraw_emu');
        if (werkzeug == null) return null;
        // -w Kamera-Weißabgleich, -T TIFF (dcraw_emu kann kein JPEG),
        // -Z - schreibt neben die Eingabe; deshalb in den Temp-Ordner
        // kopieren, damit die Bibliothek unangetastet bleibt.
        final kopie = p.join(temp.path, p.basename(datei.path));
        await datei.copy(kopie);
        final r = await Process.run(werkzeug, ['-w', '-T', kopie]);
        if (r.exitCode != 0) return null;
        final tiff = '$kopie.tiff';
        if (!await File(tiff).exists()) return null;
        await File(tiff).rename(ziel);
      }

      final rohBytes = await File(ziel).readAsBytes();
      // await ist wichtig: ohne würde das Future erst NACH dem catch
      // abgeschlossen und ein Fehler im Isolate entkäme der Fehlerbehandlung.
      return await compute(
          _skaliereUndKodiere, _SkalierAuftrag(rohBytes, maxDimension, quality));
    } catch (_) {
      return null;
    } finally {
      // Zwischendateien immer aufräumen, auch bei Fehlern.
      try {
        await temp?.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Extrahiert ein Vorschaubild aus einem Video plus dessen Länge.
  /// Ein Standbild aus einem Video.
  ///
  /// [anteil] ist die Stelle in der Laufzeit, 0 bis 1. Ohne Angabe wird
  /// wie bisher eine Sekunde hinein gegriffen; mit Angabe entstehen die
  /// weiteren Standbilder, aus denen die Auswertung eines laengeren
  /// Videos besteht (siehe `videostandbilder.dart`).
  static Future<({Uint8List jpeg, double? dauerSekunden})?> videoThumbnail(
    File datei, {
    int maxDimension = 800,
    double? anteil,
  }) async {
    final werkzeug = await aufruf('ffmpeg');
    if (werkzeug == null) return null;

    Directory? temp;
    try {
      temp = await Directory.systemTemp.createTemp('pv_thumb_');
      final ziel = p.join(temp.path, 'frame.jpg');
      // Eine Sekunde hinein statt bei 0: der allererste Frame ist bei
      // vielen Videos schwarz.
      Future<bool> greifeFrame(String position) async {
        final r = await Process.run(werkzeug, [
          '-y', '-ss', position, '-i', datei.path,
          '-frames:v', '1',
          '-vf', "scale='min($maxDimension,iw)':-2",
          ziel,
        ]);
        return r.exitCode == 0 && await File(ziel).exists();
      }

      if (anteil != null) {
        final dauer = await videoDauer(datei);
        if (dauer == null || dauer <= 0) return null;
        final stelle = (anteil.clamp(0, 1) * dauer);
        // `-ss` VOR `-i` ist der schnelle Sprung: ffmpeg setzt am
        // naechsten Keyframe auf, statt bis dorthin zu dekodieren.
        if (!await greifeFrame(stelle.toStringAsFixed(3))) return null;
        return (jpeg: await File(ziel).readAsBytes(), dauerSekunden: dauer);
      }

      // Sekunde 1 statt 0, weil der allererste Frame bei vielen Videos
      // schwarz ist – bei Videos unter einer Sekunde gibt es dort aber
      // keinen Frame mehr, dann von vorn.
      if (!await greifeFrame('1') && !await greifeFrame('0')) return null;
      final jpeg = await File(ziel).readAsBytes();
      return (jpeg: jpeg, dauerSekunden: await videoDauer(datei));
    } catch (_) {
      return null;
    } finally {
      try {
        await temp?.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Videolänge in Sekunden über ffprobe (Teil von ffmpeg).
  static Future<double?> videoDauer(File datei) async {
    final werkzeug = await aufruf('ffprobe');
    if (werkzeug == null) return null;
    try {
      final r = await Process.run(werkzeug, [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        datei.path,
      ]);
      if (r.exitCode != 0) return null;
      final d = double.tryParse((r.stdout as String).trim());
      return (d != null && d > 0) ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// Schneidet [datei] verlustfrei zwischen [startSekunden] und
  /// [endSekunden] – ohne Neukodierung (`-c copy`), entspricht damit dem
  /// nicht-destruktiven Verhalten unter macOS.
  static Future<bool> trimVideo(
    File datei, {
    required double startSekunden,
    required double endSekunden,
    required String zielPfad,
  }) async {
    final werkzeug = await aufruf('ffmpeg');
    if (werkzeug == null) return false;
    if (endSekunden <= startSekunden) return false;
    try {
      final r = await Process.run(werkzeug, [
        '-y',
        '-ss', startSekunden.toStringAsFixed(3),
        '-to', endSekunden.toStringAsFixed(3),
        '-i', datei.path,
        '-c', 'copy',
        zielPfad,
      ]);
      return r.exitCode == 0 && await File(zielPfad).exists();
    } catch (_) {
      return false;
    }
  }
}

class _SkalierAuftrag {
  final Uint8List bytes;
  final int maxDimension;
  final int quality;
  const _SkalierAuftrag(this.bytes, this.maxDimension, this.quality);
}

/// Top-Level-Funktion für `compute()` – verkleinert auf die längste Kante
/// und kodiert als JPEG.
Uint8List? _skaliereUndKodiere(_SkalierAuftrag a) {
  final bild = img.decodeImage(a.bytes);
  if (bild == null) return null;
  final laengsteKante = bild.width > bild.height ? bild.width : bild.height;
  final fertig = laengsteKante > a.maxDimension
      ? img.copyResize(
          bild,
          width: bild.width >= bild.height ? a.maxDimension : null,
          height: bild.height > bild.width ? a.maxDimension : null,
          interpolation: img.Interpolation.average,
        )
      : bild;
  return Uint8List.fromList(img.encodeJpg(fertig, quality: a.quality));
}
