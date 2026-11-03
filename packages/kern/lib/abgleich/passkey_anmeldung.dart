import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'anmeldung.dart';
import 'verbindung.dart';

/// Anmelden mit einem Passkey auf einem Gerät (#277, siehe dort
/// `passkey_api.dart`).
///
/// Nach dem Passkey fragt nicht die App, sondern eine Seite des Servers im
/// Browser der App: Ein Passkey gehört zu der Adresse, unter der er
/// angelegt wurde, und das ist die des Servers. Der Weg ist derselbe wie
/// bei der OIDC-Verknüpfung (oidc_verknuepfung.dart): Die Seite schickt den
/// Browser mit einem Code auf einen Port nur auf diesem Gerät zurück
/// (RFC 8252), und die App löst ihn mit einem Prüfer ein, den nur sie
/// kennt (PKCE).
class PasskeyAnmeldung {
  PasskeyAnmeldung(
    this.server, {
    http.Client? client,
    this.frist = const Duration(minutes: 5),
  }) : _http = client ?? http.Client();

  final Uri server;
  final http.Client _http;

  /// Wie lange auf die Rückkehr aus dem Browser gewartet wird.
  final Duration frist;

  /// Öffnet mit [oeffne] die Seite des Servers und wartet. [antwort] ist
  /// die Seite, die der Browser danach zeigt – in der Sprache der App.
  /// `null`, wenn im Browser abgebrochen wurde oder die Zeit um ist.
  Future<Anmeldeschritt?> melde({
    required String geraet,
    required Future<void> Function(Uri adresse) oeffne,
    required String antwort,
  }) async {
    final pruefer = _zufall(64);
    final zustand = _zufall(24);
    final pruefwert = base64Url
        .encode(sha256.convert(ascii.encode(pruefer)).bytes)
        .replaceAll('=', '');
    final rueckkehr = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final rueckweg = Uri.parse('http://127.0.0.1:${rueckkehr.port}/passkey');
      final ankunft = rueckkehr
          .where((a) => a.uri.path == '/passkey')
          .first
          .timeout(frist);
      await oeffne(
        _adresse('app/passkey.html').replace(
          queryParameters: {
            'pruefwert': pruefwert,
            'rueckweg': '$rueckweg',
            'zustand': zustand,
            'geraet': geraet,
          },
        ),
      );
      final HttpRequest a;
      try {
        a = await ankunft;
      } on TimeoutException {
        return null;
      }
      final q = a.uri.queryParameters;
      a.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..headers.set('cache-control', 'no-store')
        ..write(_seite(antwort));
      await a.response.close();
      final code = q['code'];
      if (q['zustand'] != zustand || code == null) return null;
      final r = await _http
          .post(
            _adresse('api/v1/anmelden/passkey/einloesen'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'code': code, 'pruefer': pruefer}),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 401) return const AnmeldungAbgewiesen();
      if (r.statusCode != 200) throw Serverfehler(r.statusCode, r.body);
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map || j['token'] is! String) {
        throw Serverfehler(r.statusCode, r.body);
      }
      return AnmeldungFertig(j['token'] as String);
    } on SocketException {
      throw KeineVerbindung('$server');
    } finally {
      await rueckkehr.close(force: true);
    }
  }

  void schliesse() => _http.close();

  Uri _adresse(String pfad) {
    final b = server.path.endsWith('/')
        ? server
        : server.replace(path: '${server.path}/');
    return b.resolve(pfad);
  }

  static String _seite(String text) {
    final sicher = const HtmlEscape().convert(text);
    return '<!doctype html><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width">'
        '<title>Photo Vault</title>'
        '<p style="font:16px system-ui;margin:3em auto;max-width:30em">'
        '$sicher</p>';
  }

  static String _zufall(int laenge) {
    const zeichen =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final r = Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < laenge; i++) zeichen.codeUnitAt(r.nextInt(64)),
    ]);
  }
}
