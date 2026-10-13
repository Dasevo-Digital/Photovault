import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Einmalcodes nach RFC 6238 (TOTP): HMAC-SHA1, 30 Sekunden, sechs
/// Ziffern – das, was jede Authenticator-App ohne weitere Angaben kann.
class Totp {
  const Totp._();

  static const schrittSekunden = 30;
  static const stellen = 6;

  /// Ein neues Geheimnis: 160 Bit, wie RFC 4226 es empfiehlt.
  static List<int> neuesGeheimnis() {
    final zufall = Random.secure();
    return List<int>.generate(20, (_) => zufall.nextInt(256));
  }

  /// Der Zeitschritt zu [zeit].
  static int schritt(DateTime zeit) =>
      zeit.millisecondsSinceEpoch ~/ 1000 ~/ schrittSekunden;

  /// Der Code für [schritt].
  static String code(List<int> geheimnis, int schritt) {
    final zaehler = ByteData(8)..setInt64(0, schritt);
    final h = Hmac(sha1, geheimnis).convert(zaehler.buffer.asUint8List()).bytes;
    final o = h[h.length - 1] & 0x0f;
    final zahl =
        ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
    return (zahl % 1000000).toString().padLeft(stellen, '0');
  }

  /// Prüft [eingabe] zu [zeit] und gibt den Schritt zurück, zu dem sie
  /// passt – `null`, wenn keiner passt.
  ///
  /// Ein Schritt davor und danach gelten mit: Uhren gehen nicht genau, und
  /// wer den Code abtippt, braucht ein paar Sekunden. **Nur Schritte nach
  /// [letzterSchritt]**: Ein Code gilt einmal. Wer ihn mitliest, während er
  /// eingetippt wird, kann ihn nicht gleich danach selbst benutzen.
  static int? pruefe(
    List<int> geheimnis,
    String eingabe,
    DateTime zeit, {
    int letzterSchritt = 0,
  }) {
    final ziffern = eingabe.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(ziffern)) return null;
    final jetzt = schritt(zeit);
    int? treffer;
    // Alle drei Schritte prüfen, auch nach einem Treffer: Die Zeit der
    // Prüfung soll nicht verraten, welcher passte.
    for (final s in [jetzt - 1, jetzt, jetzt + 1]) {
      final passt = _gleich(code(geheimnis, s), ziffern);
      if (passt && s > letzterSchritt) treffer ??= s;
    }
    return treffer;
  }

  /// Die Adresse für den QR-Code (Key Uri Format).
  static String adresse(List<int> geheimnis, String konto) {
    final aussteller = Uri.encodeComponent('Photo Vault');
    return 'otpauth://totp/$aussteller:${Uri.encodeComponent(konto)}'
        '?secret=${base32(geheimnis)}&issuer=$aussteller'
        '&algorithm=SHA1&digits=$stellen&period=$schrittSekunden';
  }

  /// RFC 4648 ohne Auffüllzeichen – so lesen Authenticator-Apps es.
  static String base32(List<int> daten) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final aus = StringBuffer();
    var puffer = 0, bits = 0;
    for (final b in daten) {
      puffer = (puffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        aus.write(alphabet[(puffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
      // Nur die noch nicht geschriebenen Bits behalten – sonst liefe die
      // Zahl nach acht Bytes über.
      puffer &= (1 << bits) - 1;
    }
    if (bits > 0) aus.write(alphabet[(puffer << (5 - bits)) & 31]);
    return aus.toString();
  }

  static bool _gleich(String a, String b) {
    var u = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      u |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return u == 0;
  }
}
