import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Teilt die Verbindung zum Server mit den Erweiterungen der App auf dem
/// iPhone – dem Widget „Vor x Jahren“ und „An Photo Vault“ im
/// Teilen-Menü. Sie liegt dort im gemeinsamen Schlüsselbund
/// (ios/Gemeinsam/GemeinsameVerbindung.swift); andere Plattformen haben
/// diese Erweiterungen nicht.
abstract final class Gemeinsam {
  static const _kanal = MethodChannel('de.dasevo.photovault/gemeinsam');

  static Future<void> setze(Uri server, String token) =>
      _rufe('setze', {'server': server.toString(), 'token': token});

  static Future<void> loesche() => _rufe('loesche');

  /// Ob die App-Sperre an ist (#467). Dann zeigt das Widget „Vor x Jahren“
  /// nur ein Schloss, kein Foto und kein Datum – sonst stünden die Fotos
  /// auf dem Home-Bildschirm, in der Heute-Ansicht und in StandBy, auch auf
  /// dem gesperrten iPhone. Ändert sich der Zustand, zeichnet iOS das
  /// Widget neu.
  static Future<void> setzeAppSperre(bool an) => _rufe('appSperre', an);

  static Future<void> _rufe(String methode, [Object? werte]) async {
    // defaultTargetPlatform statt Platform.isIOS: Es ist dasselbe, lässt
    // sich in Tests aber umstellen.
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _kanal.invokeMethod<void>(methode, werte);
    } on PlatformException {
      // Ohne gemeinsamen Schlüsselbund gehen nur Widget und Teilen nicht.
    } on MissingPluginException {
      // In Tests und in der Hintergrund-Engine der Sicherung.
    }
  }
}
