import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Ableitung der Dateinamen für verschlüsselte Backups.
///
/// Bei einem verschlüsselten Backup sollen die Dateien im Zielordner nichts
/// über den Inhalt verraten. Bisher blieb trotz verschlüsselter Bytes
/// sichtbar: der Aufnahmezeitraum (Ordner nach Jahr/Monat), das Dateiformat
/// (Endung) und über die Prüfsumme im Namen sogar, OB eine bestimmte,
/// anderweitig bekannte Datei enthalten ist.
///
/// Deshalb liegen verschlüsselte Backups flach unter `data/` mit einem
/// Namen, der sich nur MIT dem Schlüssel berechnen lässt: HMAC-SHA256 über
/// die Prüfsumme des Fotos. Deterministisch, damit ein erneuter Lauf
/// dieselbe Datei überschreibt statt eine zweite anzulegen.
class VerschluesselteNamen {
  VerschluesselteNamen._();

  /// Unterordner für die verschlüsselten Dateien.
  static const ordner = 'data';

  static Future<String> fuerPruefsumme(
    String pruefsumme,
    SecretKey schluessel,
  ) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(pruefsumme),
      secretKey: schluessel,
    );
    return mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
