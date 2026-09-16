/// **Der Videoschreiber, den macOS selbst mitbringt.**
///
/// Gegenstück zu `macos/Runner/ImageConverter.swift`s
/// `Flugvideoschreiber`. Hier steht nur die Anbindung – die Rechnung
/// steht drüben.
///
/// **Warum es ihn gibt.** Unter Linux und Windows liegt ffmpeg im Paket
/// und wird als Prozess gestartet. Unter macOS ging das nie, auch nicht
/// mit einem selbst installierten ffmpeg, und zwar aus zwei Gründen, die
/// unabhängig voneinander schon je für sich reichen:
///
///   1. **Der Sandkasten startet kein fremdes Programm.** An einem eigens
///      signierten Probebündel mit den Rechten der App gemessen: `stat()`
///      auf `/opt/homebrew/bin/ffmpeg` gelingt, `access(X_OK)` und
///      `posix_spawn` scheitern beide mit EPERM.
///   2. **Aus dem Dock gestartet fehlt Homebrew im `PATH`.** Was der
///      Finder startet, bekommt `/usr/bin:/bin:/usr/sbin:/sbin` und sonst
///      nichts – gemessen, indem dieselbe Probe einmal über `open` aus
///      einer Kommandozeile und einmal über den Finder lief.
///
/// Deshalb hier AVFoundation: im System vorhanden, im Sandkasten erlaubt,
/// kodiert über VideoToolbox in Hardware.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

class NativerVideoschreiber {
  NativerVideoschreiber._();

  /// Derselbe Kanal wie [NativeImageConverter] – eine Datei, eine
  /// Registrierung. Ein zweiter Kanal hiesse eine zweite Zeile in
  /// `MainFlutterWindow.swift`, und die einzubinden ist ein Handgriff in
  /// Xcode, den man beim nächsten Mal vergisst.
  @visibleForTesting
  static const kanal = MethodChannel('photo_vault/image_convert');

  static bool? _da;

  /// Verwirft das gemerkte Ergebnis – für Tests.
  @visibleForTesting
  static void vergiss() => _da = null;

  /// Ob dieser Bau den nativen Schreiber kennt.
  ///
  /// Gefragt wird nach `videoNativ` und nicht nach `ping`: Den `ping` gab
  /// es schon, bevor es die Videoausgabe gab. Eine Antwort darauf belegt
  /// also nur, dass der Kanal steht.
  static Future<bool> verfuegbar() async {
    if (_da != null) return _da!;
    if (!Platform.isMacOS) return _da = false;
    try {
      _da = await kanal.invokeMethod<bool>('videoNativ') ?? false;
    } on MissingPluginException {
      _da = false;
    } on PlatformException {
      _da = false;
    }
    return _da!;
  }

  /// Beginnt einen Lauf. Wirft eine [PlatformException], wenn
  /// AVFoundation die Datei nicht annimmt.
  static Future<void> beginne({
    required String ziel,
    required int breite,
    required int hoehe,
    required int bilderJeSekunde,
  }) =>
      kanal.invokeMethod<void>('videoStart', {
        'path': ziel,
        'breite': breite,
        'hoehe': hoehe,
        'bilderJeSekunde': bilderJeSekunde,
      });

  /// Hängt ein Bild an – rohe RGBA-Bildpunkte, Zeile für Zeile.
  static Future<void> bild(Uint8List rgba) =>
      kanal.invokeMethod<void>('videoBild', {'rgba': rgba});

  /// Schliesst die Datei ab.
  static Future<void> fertig() => kanal.invokeMethod<void>('videoFertig');

  /// Bricht ab und löscht die halbe Datei. Wirft nie – ein Abbruch soll
  /// nicht daran scheitern, dass das Aufräumen scheitert.
  static Future<void> verwirf() async {
    try {
      await kanal.invokeMethod<void>('videoVerwerfen');
    } catch (_) {
      // Nichts zu tun: Der Lauf ist ohnehin zu Ende.
    }
  }
}
