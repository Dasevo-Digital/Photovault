import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';

/// Wer den Server benutzen darf – vorläufig.
///
/// Bis es Konten mit Passwort und TOTP gibt (Stufe 1a, Issue #100), gilt ein
/// einziger Schlüssel. Er entsteht beim ersten Start zufällig, steht in
/// `<PV_DATEN>/zugang.txt` (nur für den Besitzer lesbar) und muss jeder
/// Anfrage als `Authorization: Bearer …` beiliegen. Einen Server ohne
/// Schlüssel gibt es nicht: Ein vergessener Schalter darf nicht heissen,
/// dass jeder alles darf.
class Zugang {
  Zugang(this.schluessel) : _soll = utf8.encode(schluessel);

  final String schluessel;
  final List<int> _soll;

  /// Liest den Schlüssel aus [datei] oder legt ihn dort an.
  static Future<Zugang> ladeOderLegeAn(File datei) async {
    if (await datei.exists()) {
      final s = (await datei.readAsString()).trim();
      if (s.length >= 32) return Zugang(s);
    }
    final zufall = Random.secure();
    final bytes = List<int>.generate(32, (_) => zufall.nextInt(256));
    final s = base64Url.encode(bytes).replaceAll('=', '');
    await datei.parent.create(recursive: true);
    await datei.writeAsString('$s\n', flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', datei.path]);
    }
    return Zugang(s);
  }

  /// Ob [kopf] (der Wert von `Authorization`) den Schlüssel trägt.
  ///
  /// In gleicher Zeit für jede Eingabe: Ein Vergleich, der beim ersten
  /// falschen Zeichen aufhört, verrät über die Antwortzeit, wie viel davon
  /// stimmt.
  bool erlaubt(String? kopf) {
    if (kopf == null || !kopf.startsWith('Bearer ')) return false;
    final ist = utf8.encode(kopf.substring(7).trim());
    var unterschied = ist.length ^ _soll.length;
    for (var i = 0; i < _soll.length; i++) {
      unterschied |= _soll[i] ^ (i < ist.length ? ist[i] : 0);
    }
    return unterschied == 0;
  }

  /// Lässt nur Anfragen mit Schlüssel durch; [offen] sind Pfade ohne
  /// (die Lebenszeichen-Abfrage für Docker und Proxy).
  Middleware middleware({Set<String> offen = const {}}) =>
      (innerer) => (anfrage) {
        if (offen.contains(anfrage.url.path)) return innerer(anfrage);
        if (!erlaubt(anfrage.headers['authorization'])) {
          return Response(
            401,
            body: jsonEncode({'fehler': 'Schlüssel fehlt oder stimmt nicht'}),
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'www-authenticate': 'Bearer',
            },
          );
        }
        return innerer(anfrage);
      };
}
