/// Was Import und Auswertungen von der Plattform brauchen, um an Pixel,
/// Aufnahmewerte und Ton einer Datei zu kommen.
///
/// Unter macOS liefert das ein nativer Kanal der App (ImageIO, AVFoundation,
/// Vision), unter Linux und Windows – und auf einem Server – die
/// Kommandozeilenwerkzeuge über [DesktopImageTools]. Der Kern kennt nur
/// diese Schnittstelle; welcher Weg gilt, entscheidet, wer ihn benutzt.
library;

import 'dart:io';
import 'dart:typed_data';

import 'raw_formats.dart';
import 'textstellen.dart';

import 'platform/desktop_image_tools.dart';
import 'raw_identify_parser.dart';

/// Formate, die Flutter (Skia) selbst nicht rendern kann und die das
/// Dart-Paket `image` auch nicht dekodieren kann – für diese wird immer
/// versucht, über [NativeImageConverter] eine JPEG-Vorschau zu erzeugen,
/// unabhängig davon, ob ein direkter Dekodierversuch zufällig teilweise
/// klappen würde.
const heicAndRawExtensions = {
  '.heic',
  '.heif',
  '.avif',
  '.avifs',
  ...rawImageExtensions,
};

/// Ein Standbild aus einem Video als JPEG samt der Videolänge, falls sie
/// sich ermitteln liess.
class VideoThumbnailResult {
  final Uint8List jpegBytes;
  final double? durationSeconds;
  const VideoThumbnailResult(this.jpegBytes, this.durationSeconds);
}

abstract interface class Bildwerkzeuge {
  /// Der Weg, den Import und Auswertungen nehmen, wenn niemand einen
  /// eigenen hereinreicht.
  ///
  /// Ohne Einrichtung derselbe wie bisher ohne nativen Kanal: unter macOS
  /// keiner (der Kanal gehört der App, die ihn beim Start einsetzt), sonst
  /// die Werkzeuge.
  static Bildwerkzeuge standard = Platform.isMacOS
      ? const KeineBildwerkzeuge()
      : const WerkzeugBildwerkzeuge();

  /// Die Datei als JPEG, auf [maxDimension] Pixel an der längeren Seite
  /// verkleinert (`null`: volle Grösse). `null`, wenn sie sich nicht
  /// wandeln liess.
  Future<Uint8List?> convertToJpegBytes(
    File file, {
    int? maxDimension = 2048,
    double quality = 0.9,
    bool objektivkorrektur = true,
  });

  /// Ein Standbild an der Stelle [anteil] (0 bis 1) der Laufzeit.
  Future<VideoThumbnailResult?> generateVideoThumbnail(
    File file, {
    int maxDimension = 800,
    double? anteil,
    bool hoheQualitaet = false,
  });

  /// Aufnahmewerte und -zeitpunkt für Dateien, aus denen `package:exif`
  /// nichts herausbekommt (CR3).
  Future<Aufnahmedaten> readCameraMetadata(File file);

  /// Die Tonspur als 16-kHz-Mono-PCM; `null` ohne lesbare Tonspur.
  Future<Int16List?> videoTon(File file, {int hoechstensSekunden = 0});

  /// Text im Bild über einen eigenen Weg der Plattform (macOS: Vision).
  /// `null` heisst: keiner da oder gescheitert – dann rechnet das Modell
  /// des Kerns.
  Future<List<Textstelle>?> recognizeText(File file);

  /// Ob [recognizeText] den Text liest, sodass die Texterkennung kein
  /// Modell braucht.
  bool get liestTextSelbst;
}

/// Linux, Windows, Server: die Kommandozeilenwerkzeuge.
class WerkzeugBildwerkzeuge implements Bildwerkzeuge {
  const WerkzeugBildwerkzeuge();

  /// Grösser als jeder Bildsensor – „nicht verkleinern".
  static const _ohneBegrenzung = 1 << 20;

  @override
  Future<Uint8List?> convertToJpegBytes(
    File file, {
    int? maxDimension = 2048,
    double quality = 0.9,
    bool objektivkorrektur = true,
  }) => DesktopImageTools.convertToJpeg(
    file,
    maxDimension: maxDimension ?? _ohneBegrenzung,
    quality: (quality * 100).round(),
    objektivkorrektur: objektivkorrektur,
  );

  @override
  Future<VideoThumbnailResult?> generateVideoThumbnail(
    File file, {
    int maxDimension = 800,
    double? anteil,
    bool hoheQualitaet = false,
  }) async {
    final r = await DesktopImageTools.videoThumbnail(
      file,
      maxDimension: maxDimension,
      anteil: anteil,
      hoheQualitaet: hoheQualitaet,
    );
    return r == null ? null : VideoThumbnailResult(r.jpeg, r.dauerSekunden);
  }

  @override
  Future<Aufnahmedaten> readCameraMetadata(File file) =>
      DesktopImageTools.leseAufnahmedaten(file);

  @override
  Future<Int16List?> videoTon(File file, {int hoechstensSekunden = 0}) async {
    final roh = await DesktopImageTools.videoTon(
      file,
      hoechstensSekunden: hoechstensSekunden,
    );
    return roh == null ? null : pcmAusBytes(roh);
  }

  @override
  Future<List<Textstelle>?> recognizeText(File file) async => null;

  @override
  bool get liestTextSelbst => false;
}

/// Kein Weg: Alles liefert „nicht möglich". Die Vorgabe unter macOS, solange
/// die App ihren Kanal nicht eingesetzt hat – so wie vorher, wenn der Kanal
/// fehlte.
class KeineBildwerkzeuge implements Bildwerkzeuge {
  const KeineBildwerkzeuge();

  @override
  Future<Uint8List?> convertToJpegBytes(
    File file, {
    int? maxDimension = 2048,
    double quality = 0.9,
    bool objektivkorrektur = true,
  }) async => null;

  @override
  Future<VideoThumbnailResult?> generateVideoThumbnail(
    File file, {
    int maxDimension = 800,
    double? anteil,
    bool hoheQualitaet = false,
  }) async => null;

  @override
  Future<Aufnahmedaten> readCameraMetadata(File file) async =>
      Aufnahmedaten.leer;

  @override
  Future<Int16List?> videoTon(File file, {int hoechstensSekunden = 0}) async =>
      null;

  @override
  Future<List<Textstelle>?> recognizeText(File file) async => null;

  @override
  bool get liestTextSelbst => false;
}

/// 16-Bit-Werte aus rohen Bytes (little endian, wie bestellt). Eine
/// ungerade Länge kann nur ein abgeschnittenes letztes Byte sein.
Int16List pcmAusBytes(Uint8List roh) {
  final werte = Int16List(roh.length ~/ 2);
  final sicht = ByteData.sublistView(roh);
  for (var i = 0; i < werte.length; i++) {
    werte[i] = sicht.getInt16(i * 2, Endian.little);
  }
  return werte;
}
