import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Verschlüsselt, was in der Serverdatenbank nicht im Klartext stehen
/// soll – die TOTP-Geheimnisse. Mit ihnen allein liessen sich Codes
/// erzeugen; eine Sicherung oder Kopie von `server.sqlite` soll dafür
/// nicht reichen.
///
/// Der Schlüssel (256 Bit, AES-GCM) liegt in einer eigenen Datei, nur für
/// den Besitzer lesbar. Geht sie verloren, ist nichts verloren ausser den
/// TOTP-Einrichtungen: Die lassen sich je Konto neu anlegen
/// (`konto totp-zuruecksetzen`).
class Tresorschluessel {
  Tresorschluessel(List<int> schluessel) : _schluessel = SecretKey(schluessel);

  final SecretKey _schluessel;
  static final _aes = AesGcm.with256bits();

  /// Liest den Schlüssel aus [datei] oder legt dort einen neuen an.
  static Tresorschluessel ladeOderLegeAn(File datei) {
    if (datei.existsSync()) {
      final b = datei.readAsBytesSync();
      if (b.length == 32) return Tresorschluessel(b);
      throw StateError(
        '${datei.path} ist kein Schlüssel (${b.length} statt 32 Bytes)',
      );
    }
    final zufall = Random.secure();
    final b = List<int>.generate(32, (_) => zufall.nextInt(256));
    datei.parent.createSync(recursive: true);
    // Erst leer anlegen und einschränken, dann schreiben: Der Schlüssel
    // soll keinen Augenblick für andere lesbar auf der Platte liegen.
    datei.createSync();
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['600', datei.path]);
    }
    datei.writeAsBytesSync(b, flush: true);
    return Tresorschluessel(b);
  }

  /// [klartext] verschlüsselt, als Text für die Datenbank.
  Future<String> verschluessele(List<int> klartext) async {
    final kiste = await _aes.encrypt(klartext, secretKey: _schluessel);
    return base64.encode(kiste.concatenation());
  }

  /// Entschlüsselt, was [verschluessele] geschrieben hat. Wirft, wenn es
  /// mit einem anderen Schlüssel entstand oder verändert wurde.
  Future<List<int>> entschluessele(String text) async {
    final kiste = SecretBox.fromConcatenation(
      base64.decode(text),
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    return _aes.decrypt(kiste, secretKey: _schluessel);
  }
}
