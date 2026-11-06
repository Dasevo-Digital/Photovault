import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import 'stand.dart';

/// Neue Fotos so schnell sichern, wie das System es zulässt – auch, wenn die
/// App nicht offen ist (#308).
///
/// **iOS:** die Erweiterung `Sofortsicherung` (ios/Sofortsicherung). Das
/// System startet sie, wenn Netz und Akku passen, und lädt selbst hoch; das
/// Foto erreicht den Server damit meist lange vor der nächsten
/// Hintergrundaufgabe der App, aber wann genau, bestimmt iOS. Mit „Im
/// Hintergrund nur beim Laden“ bleibt sie aus: Ihr lässt sich diese
/// Bedingung nicht mitgeben.
///
/// **Android:** Ein Wächter (`Fotowaechter.kt`) wartet auf neue Einträge im
/// MediaStore und startet einen Lauf, sobald die Bedingungen aus den
/// Einstellungen erfüllt sind. Das dauert Sekunden, auch wenn die App gar
/// nicht läuft. Nur eine App, die lange nicht geöffnet wurde, hält Android
/// zurück, gemessen an einem Android 16 um mehr als die 45 Sekunden des
/// Tests, nach seinen Einstellungen bis zu rund 31 Minuten. Nimmt der
/// Nutzer sie von der Akku-Optimierung aus ([akkuFreigeben]), entfällt das.
enum Sofortstand {
  /// Läuft.
  an,

  /// Die Sicherung ist aus.
  aus,

  /// iOS: aus, weil „Im Hintergrund nur beim Laden“ gilt.
  beimLaden,

  /// iOS: ohne vollen Zugriff auf die Fotos startet das System sie nicht.
  zugriff,

  /// iOS: Das System ist zu alt dafür.
  system,

  /// iOS: Der Server nimmt die Dateien noch nicht an.
  server,

  /// Das System hat das Einschalten abgelehnt.
  fehler,
}

/// Was die Erweiterung unter iOS zuletzt getan hat.
class Sofortbericht {
  const Sofortbericht({
    required this.zeit,
    required this.gesichert,
    required this.gescheitert,
    required this.unterwegs,
    this.fehler,
  });

  factory Sofortbericht.ausJson(Map<String, Object?> j) => Sofortbericht(
    zeit: DateTime.fromMillisecondsSinceEpoch(j['zeit']! as int),
    gesichert: j['gesichert'] as int? ?? 0,
    gescheitert: j['gescheitert'] as int? ?? 0,
    unterwegs: j['unterwegs'] as int? ?? 0,
    fehler: j['fehler'] as String?,
  );

  /// Wann iOS sie zuletzt gestartet hat.
  final DateTime zeit;

  /// So viele Dateien kamen seit dem Einschalten im Hintergrund an.
  final int gesichert;

  /// So viele scheiterten; die App holt sie nach.
  final int gescheitert;

  /// So viele warten gerade beim System.
  final int unterwegs;

  final String? fehler;
}

const _kanal = MethodChannel('de.dasevo.photovault/gemeinsam');

/// Stellt die Erweiterung bzw. den Wächter nach [e]. [serverKann]: Ob der
/// Server Dateien in einem Stück annimmt; das braucht nur iOS.
Future<Sofortstand> stelleSofort(
  Sicherungseinstellungen e, {
  required bool serverKann,
  @visibleForTesting bool? ios,
}) async {
  final aufIos = ios ?? Platform.isIOS;
  if (!aufIos && !Platform.isAndroid) return Sofortstand.aus;
  final iosGesperrt = aufIos && (e.nurBeimLaden || !serverKann);
  try {
    final stand = await _kanal.invokeMethod<String>('sofort', {
      'an': e.an && !iosGesperrt,
      'videos': e.videos,
      'nurWlan': e.nurWlan,
      'nurBeimLaden': e.nurBeimLaden,
      'alben': e.alben,
    });
    if (!e.an) return Sofortstand.aus;
    if (aufIos && !serverKann) return Sofortstand.server;
    if (aufIos && e.nurBeimLaden) return Sofortstand.beimLaden;
    return switch (stand) {
      'an' => Sofortstand.an,
      'aus' => Sofortstand.aus,
      'zugriff' => Sofortstand.zugriff,
      'system' => Sofortstand.system,
      _ => Sofortstand.fehler,
    };
  } on PlatformException {
    return Sofortstand.fehler;
  } on MissingPluginException {
    return Sofortstand.aus; // in Tests ohne Telefon
  }
}

/// Sagt der Erweiterung unter iOS, dass die App alles gesichert hat, was bis
/// [zeit] entstand: Das braucht sie nicht noch einmal zu schicken.
Future<void> meldeGeschafft(DateTime zeit) async {
  if (!Platform.isIOS) return;
  try {
    await _kanal.invokeMethod<void>(
      'sofortGeschafft',
      zeit.millisecondsSinceEpoch,
    );
  } on PlatformException {
    // Dann schickt sie es; der Server erkennt die Datei wieder.
  } on MissingPluginException {
    // In Tests und in der Hintergrund-Engine der Sicherung.
  }
}

/// Android: Ob die App von der Akku-Optimierung ausgenommen ist. Überall
/// sonst `true`: Da gibt es nichts freizugeben.
Future<bool> akkuFrei() async {
  if (!Platform.isAndroid) return true;
  try {
    return await _kanal.invokeMethod<bool>('akkuFrei') ?? true;
  } on PlatformException {
    return true;
  } on MissingPluginException {
    return true;
  }
}

/// Android: Fragt im Dialog des Systems nach der Ausnahme. Gibt zurück, ob
/// sie danach gilt.
Future<bool> akkuFreigeben() async {
  if (!Platform.isAndroid) return true;
  try {
    return await _kanal.invokeMethod<bool>('akkuFreigeben') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Der letzte Bericht der Erweiterung; `null`, wenn sie noch nie lief.
Future<Sofortbericht?> leseSofortbericht() async {
  if (!Platform.isIOS) return null;
  try {
    final text = await _kanal.invokeMethod<String>('sofortbericht');
    if (text == null) return null;
    return Sofortbericht.ausJson(
      (jsonDecode(text) as Map).cast<String, Object?>(),
    );
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  } on FormatException {
    return null;
  }
}
