import 'dart:io';

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

  static Future<void> _rufe(String methode, [Object? werte]) async {
    if (!Platform.isIOS) return;
    try {
      await _kanal.invokeMethod<void>(methode, werte);
    } on PlatformException {
      // Ohne gemeinsamen Schlüsselbund gehen nur Widget und Teilen nicht.
    } on MissingPluginException {
      // In Tests und in der Hintergrund-Engine der Sicherung.
    }
  }
}
