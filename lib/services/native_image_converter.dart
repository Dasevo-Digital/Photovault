import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'cube_lut.dart';
import 'develop_color.dart';
import 'develop_render.dart';
import 'exif_camera.dart';
import 'platform/desktop_image_tools.dart';
import 'textstellen.dart';
import 'raw_identify_parser.dart';
import 'raw_formats.dart';

/// Formate, die Flutter (Skia) selbst nicht rendern kann und die das
/// Dart-Paket `image` auch nicht dekodieren kann – für diese wird immer
/// versucht, über [NativeImageConverter] eine JPEG-Vorschau zu erzeugen,
/// unabhängig davon, ob ein direkter Dekodierversuch zufällig teilweise
/// klappen würde.
const heicAndRawExtensions = {'.heic', '.heif', '.avif', '.avifs', ...rawImageExtensions};

/// Was sich für ein Foto an Tiefendaten holen lässt.
///
/// Ein eigener Typ statt eines `bool` – aus demselben Grund wie bei
/// [Objektivkorrekturstand]: „dieses Foto hat keine Tiefenkarte" und
/// „dieses Foto hat eine, aber wir kommen hier nicht heran" sind für den
/// Nutzer zwei verschiedene Nachrichten. Ein `bool` könnte nur die erste
/// erzählen, und die wäre dann falsch.
///
/// Der Satz dazu entsteht erst im Bildschirm, nicht hier – dieselbe Regel
/// wie bei [Objektivkorrekturstand] und `RestaurierungsGrund`.
enum Tiefenmaskenstand {
  /// Die Datei bringt keine Tiefenkarte mit. Der Normalfall: Nur
  /// Porträtaufnahmen neuerer iPhones tragen eine.
  keineTiefendaten,

  /// Vorhanden und ausgewertet – die Maske liegt bereit.
  verfuegbar,

  /// Die Datei könnte eine tragen, aber diese Plattform liest sie nicht.
  ///
  /// Unter macOS kommen die Tiefendaten aus Apples ImageIO. Unter Linux
  /// und Windows läuft der Weg über LibRaw und libheif, und die geben das
  /// Hilfsbild nicht heraus. Deshalb wird der Eintrag dort **gezeigt und
  /// erklärt**, statt zu fehlen: Ein Foto, das die Funktion auf einem
  /// anderen Rechner hätte, soll das auch sagen.
  nichtAufDieserPlattform,

  /// Tiefenkarte vorhanden, Auswertung gescheitert – etwa weil alle Werte
  /// gleich sind und sich nichts normieren lässt.
  nichtLesbar,
}

/// Das Ergebnis einer Tiefenabfrage: der Zustand und, wenn es etwas gibt,
/// die fertige Maske als PNG.
typedef Tiefenmaske = ({Tiefenmaskenstand stand, Uint8List? png});

/// Wrapper um einen MethodChannel zur nativen macOS-Bildkonvertierung via
/// ImageIO (siehe native/macos_image_convert/ImageConverter.swift). Deckt
/// Formate ab, die Flutter selbst nicht anzeigen kann: HEIC/HEIF (Apples
/// Standardformat für iPhone-Fotos) und die meisten RAW-Formate wie DNG.
/// Was die Objektivkorrektur für eine konkrete Datei leisten kann.
///
/// Ein eigener Typ statt eines `bool`, weil „hier gibt es nichts zu
/// korrigieren" und „hier ginge etwas, aber wir können es nicht" für den
/// Nutzer zwei verschiedene Nachrichten sind. Der Satz dazu entsteht erst
/// im Bildschirm – dieselbe Regel wie bei `RestaurierungsGrund` und
/// `ModellDownloadFehler`.
enum Objektivkorrekturstand {
  /// Kein RAW – die Kamera hat bereits korrigiert.
  keinRaw,

  /// Apples Kamera-/Objektivdatenbank kennt die Kombination.
  verfuegbar,

  /// Gültiges RAW, aber keine Profile. Bei Apples ProRAW ist das richtig
  /// so: Die Korrektur steckt schon in der Datei.
  nichtInDatenbank,

  /// Die RAW-Daten lassen sich gar nicht öffnen. Dann greift auch der Rest
  /// der RAW-Entwicklung nicht.
  nichtLesbar,

  /// Kein nativer Kanal (Linux, Windows) oder die Abfrage schlug fehl.
  unbekannt,
}

class NativeImageConverter {
  static const _channel = MethodChannel('photo_vault/image_convert');

  static bool? _supported;

  /// Prüft (und cached), ob der native macOS-Kanal verfügbar ist (Swift-Datei
  /// muss dafür manuell ins Xcode-Projekt eingebunden sein, siehe README).
  ///
  /// Unter Linux und Windows gibt es diesen Kanal nicht – dort übernimmt
  /// [DesktopImageTools] über Kommandozeilenwerkzeuge, siehe
  /// [_ueberWerkzeuge].
  static Future<bool> isSupported() async {
    if (_supported != null) return _supported!;
    if (!Platform.isMacOS) {
      _supported = false;
      return false;
    }
    try {
      await _channel.invokeMethod('ping');
      _supported = true;
    } catch (_) {
      _supported = false;
    }
    return _supported!;
  }

  /// Ob auf dieser Plattform der Werkzeug-Weg gilt statt des nativen
  /// Kanals.
  ///
  /// Bewusst als Verneinung von macOS geschrieben und nicht als Aufzählung
  /// von Linux und Windows: Der native Kanal ist die Ausnahme, nicht die
  /// Regel. Stünde hier eine Aufzählung, hätte jede weitere Plattform
  /// stillschweigend gar keine Bildumwandlung – so wie Windows es bis
  /// hierher hatte.
  static bool get _ueberWerkzeuge => !Platform.isMacOS;

  /// Welche Fähigkeiten hier verfügbar sind – für Diagnose und um in der
  /// UI ehrlich anzuzeigen, was fehlt. Leere Map = alles über den nativen
  /// Kanal (macOS).
  static Future<Map<String, bool>> verfuegbareWerkzeuge() async =>
      _ueberWerkzeuge ? await DesktopImageTools.pruefeWerkzeuge() : const <String, bool>{};

  /// Ob die Bildumwandlung hier arbeiten kann – und was ihr gegebenenfalls
  /// fehlt.
  ///
  /// Der Werkzeuge-Bildschirm fragte dafür bisher [isSupported], und das
  /// liefert ausserhalb von macOS grundsätzlich `false`. Unter Linux stand
  /// dort deshalb „inaktiv", während HEIC, RAW und Video nachweislich
  /// funktionierten – eine falsche Auskunft, und noch dazu mit dem Rat,
  /// eine Swift-Datei ins Xcode-Projekt einzubinden. Unter Windows gilt
  /// seit der Werkzeugschicht dasselbe.
  static Future<({bool bereit, List<String> fehlende})>
      bildwerkzeugstand() async {
    if (_ueberWerkzeuge) {
      final vorhanden = await DesktopImageTools.pruefeWerkzeuge();
      final fehlende = [
        for (final e in vorhanden.entries)
          if (!e.value) e.key,
      ]..sort();
      return (bereit: fehlende.isEmpty, fehlende: fehlende);
    }
    return (bereit: await isSupported(), fehlende: const <String>[]);
  }

  /// Was die Objektivkorrektur für eine bestimmte Datei leisten kann.
  ///
  /// Gemessen an der echten Bibliothek war die bisherige Auskunft („nur
  /// wirksam für RAW-Fotos, deren Kamera unterstützt wird") für die meisten
  /// Fotos irreführend: Von vier Kameras mit RAW-Dateien kannte Apples
  /// Datenbank genau eine. Bei Apples ProRAW-DNGs ist das kein Mangel – die
  /// Korrektur steckt bereits in der Datei –, bei einer nicht lesbaren
  /// RAW-Datei dagegen schon.
  static Future<Objektivkorrekturstand> lensCorrectionStatus(File file) async {
    if (_ueberWerkzeuge || !await isSupported()) return Objektivkorrekturstand.unbekannt;
    try {
      final antwort = await _channel.invokeMethod<String>(
          'lensCorrectionStatus', {'path': file.path});
      return switch (antwort) {
        'keinRaw' => Objektivkorrekturstand.keinRaw,
        'verfuegbar' => Objektivkorrekturstand.verfuegbar,
        'nichtInDatenbank' => Objektivkorrekturstand.nichtInDatenbank,
        'nichtLesbar' => Objektivkorrekturstand.nichtLesbar,
        _ => Objektivkorrekturstand.unbekannt,
      };
    } on PlatformException {
      return Objektivkorrekturstand.unbekannt;
    } on MissingPluginException {
      return Objektivkorrekturstand.unbekannt;
    }
  }

  /// Welche Endungen überhaupt eine Tiefenkarte tragen können.
  ///
  /// Gebraucht, um unter Linux und Windows den richtigen Satz zu sagen:
  /// Dort lässt sich nicht nachsehen, ob eine Datei eine Tiefenkarte hat,
  /// also wird nach dem Format entschieden. Bei einem JPEG wäre der
  /// Hinweis „hier ginge etwas, nur nicht auf dieser Plattform" schlicht
  /// falsch – Tiefendaten kommen aus dem HEIC-Container der
  /// iPhone-Porträtaufnahme.
  static const tiefenFaehigeEndungen = {'.heic', '.heif'};

  /// Die Tiefenkarte eines Fotos als Maske.
  ///
  /// Nur unter macOS auswertbar (siehe [Tiefenmaskenstand]); anderswo
  /// kommt [Tiefenmaskenstand.nichtAufDieserPlattform] zurück, wenn die
  /// Datei überhaupt eine tragen könnte, sonst
  /// [Tiefenmaskenstand.keineTiefendaten].
  ///
  /// Das Ergebnis ist ein Graustufen-PNG, wie es `DevelopMasks` ohnehin
  /// erwartet – hell ist nah. Es entsteht also keine neue Maskenart, nur
  /// eine neue Quelle für dieselbe.
  static Future<Tiefenmaske> tiefenmaske(File file) async {
    final endung = p.extension(file.path).toLowerCase();
    if (!Platform.isMacOS || _ueberWerkzeuge) {
      return (
        stand: tiefenFaehigeEndungen.contains(endung)
            ? Tiefenmaskenstand.nichtAufDieserPlattform
            : Tiefenmaskenstand.keineTiefendaten,
        png: null,
      );
    }
    if (!await isSupported()) {
      return (stand: Tiefenmaskenstand.keineTiefendaten, png: null);
    }
    try {
      final antwort = await _channel
          .invokeMapMethod<String, dynamic>('depthMask', {'path': file.path});
      final stand = switch (antwort?['stand']) {
        'verfuegbar' => Tiefenmaskenstand.verfuegbar,
        'keineTiefendaten' => Tiefenmaskenstand.keineTiefendaten,
        _ => Tiefenmaskenstand.nichtLesbar,
      };
      // Ohne Bild ist „verfuegbar" gelogen – dann lieber „nicht lesbar".
      final png = antwort?['png'] as Uint8List?;
      if (stand == Tiefenmaskenstand.verfuegbar && png == null) {
        return (stand: Tiefenmaskenstand.nichtLesbar, png: null);
      }
      return (stand: stand, png: png);
    } on PlatformException {
      return (stand: Tiefenmaskenstand.nichtLesbar, png: null);
    } on MissingPluginException {
      return (stand: Tiefenmaskenstand.keineTiefendaten, png: null);
    }
  }

  /// Aufnahmewerte samt Aufnahmezeitpunkt über den nativen Weg.
  ///
  /// Der Rückfall für Dateien, aus denen `package:exif` nichts
  /// herausbekommt. Konkret: CR3, Canons neueres RAW-Format. Es ist ein
  /// ISO-BMFF-Container wie MP4, kein TIFF – `package:exif` liest dort
  /// NULL Tags, gemessen an echten Dateien. Die Folge war nicht nur eine
  /// leere Info-Ansicht: Auch das Aufnahmedatum fehlte und fiel auf den
  /// Zeitstempel der Datei zurück, was 56 % einer Beispielbibliothek in
  /// den falschen Monat einsortierte.
  ///
  /// macOS liest über ImageIO, Linux und Windows über `raw-identify`.
  /// Beide wurden an derselben Datei gegeneinander gehalten und liefern
  /// dieselben Werte – bis auf die Belichtungskorrektur, die
  /// `raw-identify` nicht ausgibt.
  static Future<Aufnahmedaten> readCameraMetadata(File file) async {
    if (_ueberWerkzeuge) return DesktopImageTools.leseAufnahmedaten(file);
    if (!await isSupported()) return Aufnahmedaten.leer;
    try {
      final antwort = await _channel
          .invokeMapMethod<String, dynamic>('cameraMetadata', {'path': file.path});
      if (antwort == null) return Aufnahmedaten.leer;
      return _ausImageIo(antwort);
    } on PlatformException {
      return Aufnahmedaten.leer;
    } on MissingPluginException {
      return Aufnahmedaten.leer;
    }
  }

  static Aufnahmedaten _ausImageIo(Map<String, dynamic> m) {
    String? text(String k) {
      final v = m[k];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    double? zahl(String k) => (m[k] as num?)?.toDouble();

    final kb = zahl('FocalLenIn35mmFilm');
    return Aufnahmedaten(
      CameraInfo(
        make: text('Make'),
        model: text('Model'),
        lensModel: text('LensModel'),
        focalLengthMm: zahl('FocalLength'),
        fNumber: zahl('FNumber'),
        iso: zahl('ISO')?.round(),
        exposureTimeSeconds: zahl('ExposureTime'),
        exposureBiasEv: zahl('ExposureBiasValue'),
        // 0 heisst hier „nicht überliefert", nicht „0 mm".
        focalLength35mm: (kb == null || kb == 0) ? null : kb,
      ),
      exifDatumAusText(text('DateTimeOriginal')),
    );
  }

  /// Ob diese Plattform den eigenen Standort ermitteln kann.
  ///
  /// macOS über CoreLocation, Windows über `Windows.Devices.Geolocation`
  /// (im Hilfsprogramm `pv_standort`, siehe [DesktopImageTools.standort]).
  ///
  /// **Linux fehlt mit Absicht.** GeoClue wäre da und ist sogar schon auf
  /// beacondb umgestellt, den Nachfolger der abgeschalteten
  /// Mozilla-Datenbank. Nur kannte beacondb am 25.08.2026 im Test keinen
  /// einzigen der 13 Zugangspunkte in der Umgebung – HTTP 404. Übrig
  /// bliebe der IP-Rückfall, und der lag 271 km daneben bei behaupteten
  /// 25 km. Ein Knopf, der zuverlässig die falsche Stadt zeigt, ist
  /// schlechter als keiner. Siehe docs/ortung.md.
  static bool get standortMoeglich => Platform.isMacOS || Platform.isWindows;

  /// Der aktuelle Standort, einmalig abgefragt.
  ///
  /// `null` heisst „nicht zu ermitteln" – kein Recht erteilt, keine
  /// Ortung verfügbar oder die Abfrage lief in ihre Zeitgrenze. Der
  /// Aufrufer sagt das dem Nutzer, statt es zu verschlucken.
  static Future<({double breite, double laenge, double genauigkeit})?>
      aktuellerStandort() async {
    if (!standortMoeglich) return null;
    if (Platform.isWindows) {
      final ort = await DesktopImageTools.standort();
      if (ort == null) return null;
      return (
        breite: ort.breite,
        laenge: ort.laenge,
        genauigkeit: ort.genauigkeit,
      );
    }
    if (!await isSupported()) return null;
    try {
      final antwort =
          await _channel.invokeMapMethod<String, dynamic>('currentLocation');
      if (antwort == null) return null;
      final breite = (antwort['breite'] as num?)?.toDouble();
      final laenge = (antwort['laenge'] as num?)?.toDouble();
      if (breite == null || laenge == null) return null;
      return (
        breite: breite,
        laenge: laenge,
        genauigkeit: (antwort['genauigkeit'] as num?)?.toDouble() ?? -1,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Grenze, die keine ist – grösser als jeder existierende Bildsensor.
  ///
  /// Beide nativen Wege verkleinern nur (`downscale` gibt das Bild
  /// unverändert zurück, wenn es ohnehin kleiner ist; der RAW-Weg deckelt
  /// `scaleFactor` auf 1). Ein hinreichend grosser Wert heisst dort also
  /// tatsächlich „nicht begrenzen", statt das Bild aufzublasen. Der Wert
  /// steht hier, damit die Aufrufer schlicht `null` übergeben können.
  static const _ohneBegrenzung = 1 << 20;

  /// Konvertiert eine Bilddatei (z.B. HEIC oder DNG) zu JPEG-Bytes, skaliert
  /// auf maximal [maxDimension] Pixel an der längeren Seite; `null` rendert
  /// in voller Auflösung. Gibt `null` zurück, falls die native Anbindung
  /// fehlt oder die Datei nicht dekodiert werden konnte.
  static Future<Uint8List?> convertToJpegBytes(
    File file, {
    int? maxDimension = 2048,
    double quality = 0.9,
  }) async {
    final grenze = maxDimension ?? _ohneBegrenzung;
    if (_ueberWerkzeuge) {
      return DesktopImageTools.convertToJpeg(file,
          maxDimension: grenze, quality: (quality * 100).round());
    }
    if (!await isSupported()) return null;
    try {
      final result = await _channel.invokeMethod<Uint8List>('convertToJpeg', {
        'path': file.path,
        'maxDimension': grenze,
        'quality': quality,
      });
      return result;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Rendert eine Bilddatei mit nicht-destruktiven Entwicklungs-Anpassungen
  /// (siehe DevelopScreen) zu JPEG-Bytes. Für RAW-Dateien über
  /// CIRAWFilter-Eigenschaften, für alle anderen Formate über eine
  /// äquivalente CIFilter-Kette – beides in [ImageConverter.swift]s
  /// `developImage`. [masks] (siehe MaskEditor/DevelopMasks) werden NACH
  /// [adjustments] der Reihe nach übereinandergelegt, jede wirksam nur
  /// innerhalb ihrer eigenen Alphamaske. Gibt `null` zurück, falls die
  /// native Anbindung fehlt oder die Datei nicht gerendert werden konnte.
  static Future<Uint8List?> developImage(
    File file, {
    required DevelopAdjustments adjustments,
    List<MaskAdjustmentLayer> masks = const [],
    int maxDimension = 2048,
    double quality = 0.9,
  }) async {
    // Ausserhalb von macOS gibt es kein Core Image. Dort rechnet derselbe
    // Shader, der auch die Live-Vorschau zeichnet – siehe DevelopRender.
    // Vorher war das der einzige Regler-Satz der App, der auf manchen
    // Plattformen schlicht wirkungslos blieb.
    if (DevelopRender.istMassgeblich) {
      return DevelopRender.rendere(
        file,
        adjustments: adjustments,
        masks: masks,
        maxDimension: maxDimension,
        quality: (quality * 100).round().clamp(1, 100),
      );
    }
    if (!await isSupported()) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('developImage', {
        'path': file.path,
        'maxDimension': maxDimension,
        'quality': quality,
        ...adjustments.toChannelMap(),
        'masks': masks.map((m) => m.toChannelMap()).toList(),
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Extrahiert einen Frame aus einer Videodatei (über AVFoundation) als
  /// JPEG-Thumbnail, inklusive der Videolänge. Gibt `null` zurück, falls die
  /// native Anbindung fehlt oder das Video nicht gelesen werden konnte.
  ///
  /// [anteil] ist die Stelle in der Laufzeit, 0 bis 1. Ohne Angabe wird
  /// wie bisher kurz nach dem Start gegriffen; mit Angabe entstehen die
  /// weiteren Standbilder eines laengeren Videos (siehe
  /// `services/videostandbilder.dart`).
  static Future<VideoThumbnailResult?> generateVideoThumbnail(
    File file, {
    int maxDimension = 800,
    double? anteil,
  }) async {
    if (_ueberWerkzeuge) {
      final r = await DesktopImageTools.videoThumbnail(file,
          maxDimension: maxDimension, anteil: anteil);
      return r == null ? null : VideoThumbnailResult(r.jpeg, r.dauerSekunden);
    }
    if (!await isSupported()) return null;
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('videoThumbnail', {
        'path': file.path,
        'maxDimension': maxDimension,
        if (anteil != null) 'anteil': anteil,
      });
      if (result == null) return null;
      final jpeg = result['jpeg'] as Uint8List?;
      if (jpeg == null) return null;
      final duration = (result['durationSeconds'] as num?)?.toDouble();
      return VideoThumbnailResult(jpeg, (duration != null && duration > 0) ? duration : null);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Erkennt Text in einer Bilddatei über Apples Vision-Framework (rein
  /// on-device, siehe `ImageConverter.swift`s `recognizeText`). Gibt bei
  /// keinem gefundenen Text eine leere Liste zurück, `null` nur, wenn die
  /// native Anbindung fehlt oder die Erkennung selbst fehlgeschlagen ist.
  ///
  /// Der Unterschied zwischen „leer" und `null` trägt: Ein Foto ohne Text ist
  /// fertig bearbeitet, ein fehlgeschlagener Aufruf muss erneut dran (siehe
  /// `LibraryState.backfillOcrText`).
  static Future<List<Textstelle>?> recognizeText(File file) async {
    if (!await isSupported()) return null;
    try {
      final roh = await _channel
          .invokeMapMethod<String, Object?>('recognizeText', {'path': file.path});
      if (roh == null) return null;
      final stellen = roh['stellen'];
      if (stellen is! List) return const [];
      return textstellenAusJson(jsonEncode(stellen));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Schneidet ein Video nicht-destruktiv auf [startSeconds, endSeconds] zu
  /// (über AVAssetExportSession, siehe `ImageConverter.swift`s `trimVideo`)
  /// und schreibt das Ergebnis nach [outputPath]. Gibt `true` bei Erfolg
  /// zurück, `false` falls die native Anbindung fehlt oder der Export
  /// fehlgeschlagen ist – der Export selbst kann je nach Videolänge einige
  /// Sekunden dauern, es gibt bewusst keine Fortschrittsanzeige (MVP).
  static Future<bool> trimVideo(
    File file, {
    required double startSeconds,
    required double endSeconds,
    required String outputPath,
  }) async {
    if (_ueberWerkzeuge) {
      return DesktopImageTools.trimVideo(file,
          startSekunden: startSeconds, endSekunden: endSeconds, zielPfad: outputPath);
    }
    if (!await isSupported()) return false;
    try {
      final success = await _channel.invokeMethod<bool>('trimVideo', {
        'path': file.path,
        'outputPath': outputPath,
        'startSeconds': startSeconds,
        'endSeconds': endSeconds,
      });
      return success ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Ergebnis der nativen Video-Frame-Extraktion: das Thumbnail als JPEG-Bytes
/// plus die Videolänge (falls vom Betriebssystem ermittelbar).
class VideoThumbnailResult {
  final Uint8List jpegBytes;
  final double? durationSeconds;
  const VideoThumbnailResult(this.jpegBytes, this.durationSeconds);
}

/// Regler-Werte des DevelopScreen für [NativeImageConverter.developImage] –
/// unveränderlich, damit sich ein Satz Einstellungen einfach speichern/
/// zurücksetzen lässt. `temperature`/`tint` sind bewusst nullable (statt
/// eines Zahlen-Default): `null` bedeutet "Kamera-Weißabgleich
/// unverändert lassen", nicht "auf 0 setzen" – anders als bei den übrigen
/// Reglern gibt es hier keinen sinnvollen neutralen Zahlenwert.
class DevelopAdjustments {
  final double exposure; // -3..3 EV
  final double? temperature; // 2000..12000 K, null = Kamera-Weißabgleich
  final double? tint; // -100..100, null = Kamera-Weißabgleich
  final double contrast; // -1..1
  final double shadows; // -1..1

  /// Lichter, -1..1 – das Gegenstück zu [shadows]. Negativ holt einen
  /// überstrahlten Himmel zurück.
  final double highlights;
  final double sharpness; // 0..1
  final double noiseReduction; // 0..1

  /// Lokaler Mikrokontrast, -1..1. Negativ weicht auf, positiv arbeitet
  /// Struktur heraus.
  final double clarity;

  /// Randabdunklung, -1..1. Negativ dunkelt ab, positiv hellt auf.
  final double vignette;

  final bool lensCorrectionEnabled;

  /// Tonwertkurve und Farbmischer (siehe develop_color.dart). Anders als
  /// die Regler darüber gehen sie nicht als Zahl über den Kanal, sondern
  /// als fertig ausgerechnete Nachschlagetabelle – die Mathematik liegt
  /// bewusst nur in Dart, nicht noch einmal in Swift.
  final ToneCurve toneCurve;
  final ColorMixer colorMixer;

  /// Eine importierte Farbtabelle und wie stark sie wirkt.
  ///
  /// Sie geht nicht als eigener Schritt über den Kanal: [buildColorCube]
  /// rechnet sie in denselben Würfel hinein, den der Mischer erzeugt.
  /// Beide Renderpfade bekommen dadurch weiterhin genau einen Würfel.
  final CubeLut? lut;
  final double lutStrength;

  const DevelopAdjustments({
    this.exposure = 0,
    this.temperature,
    this.tint,
    this.contrast = 0,
    this.shadows = 0,
    this.highlights = 0,
    this.sharpness = 0,
    this.noiseReduction = 0,
    this.clarity = 0,
    this.vignette = 0,
    this.lensCorrectionEnabled = true,
    this.toneCurve = ToneCurve.neutral,
    this.colorMixer = ColorMixer.neutral,
    this.lut,
    this.lutStrength = 1,
  });

  /// Ob überhaupt ein Farbwürfel gebraucht wird.
  ///
  /// Ein Look allein genügt dafür – ohne diese Prüfung liesse ein neutraler
  /// Mischer die Tabelle fallen, und die Datei hätte keine Wirkung.
  bool get brauchtFarbwuerfel =>
      !colorMixer.istNeutral || (lut != null && lutStrength > 0);

  /// Alle Regler auf "unverändert" – DevelopScreen zeigt bei fehlenden
  /// gespeicherten Einstellungen bewusst direkt die vorhandene Vorschau-/
  /// Originaldatei an, statt hierfür extra nativ neu zu rendern (siehe
  /// DevelopScreen._init).
  static const neutral = DevelopAdjustments();

  /// Neutrale Kurve bzw. neutraler Mischer werden gar nicht erst
  /// übertragen: Die native Seite lässt den jeweiligen Filter dann weg,
  /// statt eine Identität durch Core Image zu schicken.
  Map<String, Object?> toChannelMap() => {
        'exposure': exposure,
        'temperature': temperature,
        'tint': tint,
        'contrast': contrast,
        'shadows': shadows,
        'highlights': highlights,
        'sharpness': sharpness,
        'noiseReduction': noiseReduction,
        'clarity': clarity,
        'vignette': vignette,
        'lensCorrectionEnabled': lensCorrectionEnabled,
        if (!toneCurve.istNeutral) 'toneCurveLut': buildCurveLut(toneCurve),
        if (brauchtFarbwuerfel) ...{
          'colorCube':
              buildColorCube(colorMixer, lut: lut, lutStaerke: lutStrength),
          'colorCubeSize': colorCubeSize,
        },
      };
}

/// Ein vollständiger Satz Entwicklungswerte, losgelöst von einem Foto.
///
/// Gebraucht, weil zwei Quellen dasselbe liefern sollen: die
/// Zwischenablage („Einstellungen kopieren") und eine benannte
/// Entwicklungs-Vorgabe. Ohne diesen gemeinsamen Träger stünde der
/// Übertragungsweg zweimal da – und die zweite Fassung vergässe beim
/// nächsten neuen Regler etwas, ohne dass es auffiele.
///
/// [regler] ist das, was zum Rendern gebraucht wird (samt geladener
/// Farbtabelle); die drei Textfelder sind das, was zum Speichern gebraucht
/// wird. Beides getrennt, weil Kurve und Mischer als JSON in der
/// Datenbank stehen, aber ausgerechnet an den Renderer gehen.
class Entwicklungswerte {
  final DevelopAdjustments regler;

  /// Pfad der Farbtabelle relativ zur Bibliothek – wandert unverändert in
  /// die Zieleinstellungen, damit das Zielfoto dieselbe Datei benennt.
  final String? lutPath;
  final String? toneCurveJson;
  final String? colorMixerJson;

  /// Das Foto, von dem die Werte stammen – wird beim Übertragen
  /// übersprungen. Bei einer Vorgabe `null`: Sie gehört zu keinem Foto.
  final String? quellAssetId;

  const Entwicklungswerte({
    required this.regler,
    this.lutPath,
    this.toneCurveJson,
    this.colorMixerJson,
    this.quellAssetId,
  });
}

/// Eine KI-Objektmaske (siehe MaskEditor/DevelopMasks) für
/// [NativeImageConverter.developImage]: [maskFilePath] zeigt auf eine
/// Grauwert-PNG-Alphamaske, [adjustments] gilt nur innerhalb dieser Maske.
///
/// Tonwertkurve und Farbmischer bleiben hier bewusst neutral – Masken
/// führen sie nicht (siehe DevelopMasks in database.dart). Da
/// [DevelopAdjustments.toChannelMap] neutrale Werte ohnehin weglässt,
/// ergibt sich das von selbst, ohne Sonderfall.
class MaskAdjustmentLayer {
  final String maskFilePath;
  final DevelopAdjustments adjustments;

  const MaskAdjustmentLayer({required this.maskFilePath, required this.adjustments});

  Map<String, Object?> toChannelMap() => {
        'path': maskFilePath,
        ...adjustments.toChannelMap(),
      };
}
