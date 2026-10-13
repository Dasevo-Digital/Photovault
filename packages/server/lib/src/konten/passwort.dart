import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Passwörter als Argon2id-Prüfwert im PHC-Format
/// (`$argon2id$v=19$m=…,t=…,p=…$salz$wert`), so wie ihn auch andere
/// Programme lesen.
///
/// **Die Vorgabe ist die Empfehlung von OWASP:** 19 MiB Speicher, zwei
/// Durchgänge, ein Faden. In reinem Dart gemessen 60–80 ms je Prüfung auf
/// einem aktuellen Rechner – lang genug, dass Raten teuer wird, kurz genug
/// für eine Anmeldung. Gerechnet wird in einem eigenen Isolate, damit der
/// Server währenddessen weiter antwortet.
///
/// Ein Prüfwert mit schwächeren Werten als den aktuellen gilt als
/// [veraltet] und wird bei der nächsten erfolgreichen Anmeldung erneuert.
class Passwort {
  const Passwort({this.speicher = 19456, this.durchgaenge = 2});

  /// Speicher in KiB.
  final int speicher;
  final int durchgaenge;

  /// Kürzer ist ein Passwort nicht zu haben: Mit TOTP davor wird nicht
  /// mehr jedes Passwort geraten, aber eines aus einem fremden Datenleck
  /// soll trotzdem nicht reichen.
  static const mindestlaenge = 12;

  static const _praefix = r'$argon2id$v=19$';

  /// Der Prüfwert zu [passwort] mit frischem Salz.
  Future<String> pruefwertFuer(String passwort) async {
    final zufall = Random.secure();
    final salz = List<int>.generate(16, (_) => zufall.nextInt(256));
    final wert = await _rechne(passwort, salz, speicher, durchgaenge);
    return '$_praefix'
        'm=$speicher,t=$durchgaenge,p=1'
        '\$${_b64(salz)}\$${_b64(wert)}';
  }

  /// Ob [passwort] zu [pruefwert] passt. Ein unlesbarer Prüfwert passt nie.
  Future<bool> stimmt(String passwort, String pruefwert) async {
    final t = _lies(pruefwert);
    if (t == null) return false;
    final ist = await _rechne(passwort, t.salz, t.speicher, t.durchgaenge);
    return gleich(ist, t.wert);
  }

  /// Rechnet einmal ohne Ergebnis – für unbekannte Namen, damit die
  /// Antwort so lange dauert wie bei einem bekannten. Sonst verriete die
  /// Zeit, welche Namen es gibt.
  Future<void> rechneUmsonst(String passwort) =>
      _rechne(passwort, List.filled(16, 0), speicher, durchgaenge);

  /// Ob [pruefwert] mit schwächeren Werten als den aktuellen entstand.
  bool veraltet(String pruefwert) {
    final t = _lies(pruefwert);
    return t == null || t.speicher < speicher || t.durchgaenge < durchgaenge;
  }

  static Future<List<int>> _rechne(
    String passwort,
    List<int> salz,
    int speicher,
    int durchgaenge,
  ) => Isolate.run(() async {
    final kdf = Argon2id(
      parallelism: 1,
      memory: speicher,
      iterations: durchgaenge,
      hashLength: 32,
    );
    final schluessel = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passwort)),
      nonce: salz,
    );
    return schluessel.extractBytes();
  });

  static ({List<int> salz, List<int> wert, int speicher, int durchgaenge})?
  _lies(String pruefwert) {
    if (!pruefwert.startsWith(_praefix)) return null;
    final teile = pruefwert.substring(_praefix.length).split(r'$');
    if (teile.length != 3) return null;
    final werte = <String, int>{};
    for (final paar in teile[0].split(',')) {
      final i = paar.indexOf('=');
      if (i < 0) return null;
      final zahl = int.tryParse(paar.substring(i + 1));
      if (zahl == null) return null;
      werte[paar.substring(0, i)] = zahl;
    }
    final m = werte['m'], t = werte['t'];
    if (m == null || t == null || werte['p'] != 1) return null;
    try {
      return (
        salz: _ausB64(teile[1]),
        wert: _ausB64(teile[2]),
        speicher: m,
        durchgaenge: t,
      );
    } on FormatException {
      return null;
    }
  }

  static String _b64(List<int> b) => base64.encode(b).replaceAll('=', '');

  static List<int> _ausB64(String s) =>
      base64.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));
}

/// Vergleicht in gleicher Zeit, egal wo der erste Unterschied liegt.
bool gleich(List<int> a, List<int> b) {
  var unterschied = a.length ^ b.length;
  for (var i = 0; i < a.length && i < b.length; i++) {
    unterschied |= a[i] ^ b[i];
  }
  return unterschied == 0;
}
