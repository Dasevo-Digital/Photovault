import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'verbindung.dart';

/// Wie eine Verknüpfung ausging.
enum Oidcausgang {
  verknuepft,

  /// Beim Anbieter abgelehnt oder im Browser abgebrochen.
  abgelehnt,

  /// Nach [OidcVerknuepfung.frist] kam keine Antwort.
  zeitUm,

  /// Dieses Konto beim Anbieter gehört schon zu einem anderen Konto.
  vergeben,
}

/// Verknüpft das Server-Konto dieses Geräts mit der Anmeldung bei einem
/// Anbieter (OIDC), damit man sich künftig dort anmelden kann (Issue #110).
///
/// Der Weg: Der Server nennt die Adresse beim Anbieter, die App öffnet sie
/// im Browser; der Anbieter schickt zum Server zurück, der Server weiter zur
/// App – auf einen Port nur auf diesem Rechner (RFC 8252, „loopback“). Dort
/// wartet [verknuepfe], löst den Code mit dem Prüfer ein, den nur diese App
/// kennt (PKCE), und zwar mit dem Token dieses Geräts: Die Verknüpfung gilt
/// nur für das Konto, das sie begonnen hat.
class OidcVerknuepfung {
  OidcVerknuepfung(this.verbindung, {this.frist = const Duration(minutes: 5)});

  final Serververbindung verbindung;

  /// Wie lange auf die Rückkehr aus dem Browser gewartet wird.
  final Duration frist;

  /// Öffnet [oeffne] mit der Adresse beim Anbieter und wartet. [antwort]
  /// ist die Seite, die der Browser danach zeigt – in der Sprache der App.
  Future<Oidcausgang> verknuepfe({
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
      final rueckweg = Uri.parse('http://127.0.0.1:${rueckkehr.port}/oidc');
      final d = await verbindung.schicke('api/v1/konto/oidc', {
        'rueckweg': '$rueckweg',
        'pruefwert': pruefwert,
        'zustand': zustand,
      });
      final ankunft = rueckkehr
          .where((a) => a.uri.path == '/oidc')
          .first
          .timeout(frist);
      await oeffne(Uri.parse(d['adresse']! as String));
      final HttpRequest a;
      try {
        a = await ankunft;
      } on TimeoutException {
        return Oidcausgang.zeitUm;
      }
      final q = a.uri.queryParameters;
      a.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..headers.set('cache-control', 'no-store')
        ..write(_seite(antwort));
      await a.response.close();
      final code = q['code'];
      if (q['zustand'] != zustand || code == null) return Oidcausgang.abgelehnt;
      try {
        final e = await verbindung.schicke('api/v1/anmelden/oidc/einloesen', {
          'code': code,
          'pruefer': pruefer,
        });
        return e['verknuepft'] == true
            ? Oidcausgang.verknuepft
            : Oidcausgang.abgelehnt;
      } on Serverfehler catch (f) {
        if (f.status == 409) return Oidcausgang.vergeben;
        rethrow;
      }
    } finally {
      await rueckkehr.close(force: true);
    }
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
