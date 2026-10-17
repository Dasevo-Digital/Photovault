import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'absender.dart';
import 'anmeldung_api.dart';
import 'konten/kontodienst.dart';

/// Die Weboberfläche: ihre Dateien unter `/app/` und die Anmeldung im
/// Browser (Issue #133).
///
/// **Die Sitzung ist ein Gerät.** Der Browser bekommt dasselbe Token wie
/// die App, nur nicht in die Hand: Es steckt in einem Cookie, das nur der
/// Server liest (`HttpOnly`), nur an dieselbe Seite geht (`SameSite=Strict`)
/// und über HTTPS nur verschlüsselt reist (`Secure`). In der Geräteliste
/// steht es als „Browser (…)“ und lässt sich dort wie jedes Gerät
/// abmelden; Passwort neu setzen wirft es mit hinaus.
///
/// **Was mit dem Cookie kommt, muss aus der Oberfläche kommen.** Eine
/// fremde Seite könnte den Browser mit dem Cookie an diesen Server schicken
/// (CSRF). Dagegen stehen drei Dinge, jedes für sich genug: SameSite=Strict
/// lässt das Cookie fremd gar nicht mit; schreibende Anfragen brauchen den
/// Kopf `X-PV-Web`, den eine fremde Seite nur mit einer CORS-Vorabfrage
/// setzen könnte, die der Server nie bejaht; und steht eine Herkunft im
/// Kopf, muss es die eigene sein (siehe [anfrageAusDerOberflaeche]).
///
/// **Die Seite selbst führt nichts Fremdes aus.** Kein Skript und kein Stil
/// steht in der Seite, alles kommt aus eigenen Dateien; die
/// Content-Security-Policy lässt nichts anderes zu, auch kein Einbetten in
/// fremde Seiten. Was der Server an Daten liefert, ist JSON und wird im
/// Browser als Text eingesetzt, nie als HTML.
class Webapi {
  Webapi(this.konten, this.absender, {required this.ordner});

  final Kontodienst konten;
  final Absender absender;

  /// Wo `index.html`, `app.js` und `app.css` liegen.
  final Directory ordner;

  /// Was die Seite laden und tun darf – und sonst nichts.
  static const csp =
      "default-src 'none'; script-src 'self'; style-src 'self'; "
      "img-src 'self' blob: data: https://tile.openstreetmap.org; "
      "media-src 'self' blob:; connect-src 'self'; "
      "font-src 'self'; manifest-src 'self'; base-uri 'none'; "
      "form-action 'none'; frame-ancestors 'none'";

  // Ein schlichter Name: Buchstaben, Ziffern, Strich, eine Endung aus der
  // Liste. Kein Pfadtrenner, kein zweiter Punkt – damit ist `..` von
  // vornherein draussen.
  static final _name = RegExp(
    r'^[a-z0-9][a-z0-9_-]*\.(html|css|js|svg|png|jpg|ico|webmanifest|woff2|ttf)$',
  );

  static const _typen = {
    'html': 'text/html; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'ttf': 'font/ttf',
    'ico': 'image/x-icon',
    'webmanifest': 'application/manifest+json',
    'woff2': 'font/woff2',
  };

  Future<Response> seite(Request anfrage) => datei(anfrage, 'index.html');

  /// Die Unterordner, aus denen die Seite laden darf – mitgelieferte
  /// Bibliotheken, sonst nichts.
  static const unterordner = {
    'leaflet',
    'leaflet/images',
    'lebensbaum',
    'schrift',
  };

  /// Wo Vorlagenbilder und Schriften des Lebensbaums liegen, wenn der
  /// Server aus dem Quelltext läuft statt aus dem Bündel: in den Assets der
  /// App. Das Bündel bekommt sie beim Bau als web/lebensbaum und
  /// web/schrift (siehe Dockerfile).
  static const _ausDenAssets = {
    'lebensbaum': ('assets/lebensbaum', <String, String>{}),
    'schrift': (
      'assets/fonts',
      {
        'ebgaramond.ttf': 'EBGaramond-Variable.ttf',
        'greatvibes.ttf': 'GreatVibes-Regular.ttf',
      },
    ),
  };

  /// Eine Datei der Oberfläche, wahlweise aus einem [unterordner]. Geprüft
  /// wird der Name, und zur Sicherheit noch einmal, dass die Datei im
  /// Ordner liegt.
  Future<Response> datei(
    Request anfrage,
    String name, {
    String ordnerName = '',
  }) async {
    if (!_name.hasMatch(name)) return _nichtDa();
    if (ordnerName.isNotEmpty && !unterordner.contains(ordnerName)) {
      return _nichtDa();
    }
    var f = File(p.join(ordner.path, ordnerName, name));
    var wurzel = ordner;
    final asset = _ausDenAssets[ordnerName];
    if (asset != null && !await f.exists()) {
      // web/ liegt im Quelltext unter packages/server/web.
      wurzel = Directory(p.join(ordner.path, '..', '..', '..', asset.$1));
      f = File(p.join(wurzel.path, asset.$2[name] ?? name));
    }
    if (!p.isWithin(wurzel.absolute.path, f.absolute.path) ||
        !await f.exists()) {
      return _nichtDa();
    }
    final endung = name.substring(name.lastIndexOf('.') + 1);
    return Response.ok(
      f.openRead(),
      headers: {
        'content-type': _typen[endung]!,
        'content-length': '${await f.length()}',
        // Die Seite nie aus dem Speicher des Browsers (nach dem Abmelden
        // soll nichts zurückbleiben); die übrigen Dateien immer nachfragen.
        'cache-control': endung == 'html' ? 'no-store' : 'no-cache',
        if (endung == 'html') 'content-security-policy': csp,
        // Ein SVG kann Skript tragen – nur als Bild, nie als Seite.
        if (endung == 'svg')
          'content-security-policy':
              "default-src 'none'; style-src 'unsafe-inline'; sandbox",
      },
    );
  }

  static Response _nichtDa() => Response.notFound(
    'nicht da',
    headers: {'content-type': 'text/plain; charset=utf-8'},
  );

  // --- Anmeldung ----------------------------------------------------------

  /// `{name, passwort}` → Cookie, oder der nächste Schritt (TOTP).
  Future<Response> anmelden(Request anfrage) async {
    final k = await _koerper(anfrage);
    final name = k?['name'], passwort = k?['passwort'];
    if (name is! String || passwort is! String) {
      return _json({'fehler': 'name und passwort fehlen'}, status: 400);
    }
    return _ergebnis(
      anfrage,
      await konten.anmelden(
        name,
        passwort,
        geraet: _geraetName(anfrage),
        adresse: absender.von(anfrage),
      ),
    );
  }

  /// `{vorgang, code}` → Cookie.
  Future<Response> totp(Request anfrage) async {
    final k = await _koerper(anfrage);
    final vorgang = k?['vorgang'], code = k?['code'];
    if (vorgang is! String || code is! String) {
      return _json({'fehler': 'vorgang und code fehlen'}, status: 400);
    }
    return _ergebnis(
      anfrage,
      await konten.bestaetige(vorgang, code, adresse: absender.von(anfrage)),
    );
  }

  /// Meldet den Browser ab und nimmt ihm das Cookie.
  Response abmelden(Request anfrage) {
    konten.abmelden(kontoVon(anfrage).id, geraetVon(anfrage).id);
    return _json({'abgemeldet': true}, cookie: _cookie(anfrage, null));
  }

  /// Wer angemeldet ist – die Oberfläche fragt das beim Start.
  Response sitzung(Request anfrage) {
    final k = kontoVon(anfrage);
    return _json({
      'name': k.name,
      'verwalter': k.verwalter,
      'geraet': geraetVon(anfrage).id,
    });
  }

  Response _ergebnis(Request anfrage, Anmeldeergebnis e) => switch (e) {
    Angemeldet() => _json({
      'angemeldet': true,
      if (e.wiederherstellungscodes != null)
        'wiederherstellungscodes': e.wiederherstellungscodes,
    }, cookie: _cookie(anfrage, e.token)),
    TotpNoetig() => _json({'schritt': 'totp', 'vorgang': e.vorgang}),
    TotpEinrichten() => _json({
      'schritt': 'totp_einrichten',
      'vorgang': e.vorgang,
      'geheimnis': e.geheimnis,
      'adresse': e.adresse,
    }),
    Abgewiesen(:final warte) =>
      warte == null
          ? _json({
              'fehler': 'Name, Passwort oder Code stimmt nicht',
            }, status: 401)
          : _json(
              {
                'fehler':
                    'Zu viele Fehlversuche – bitte später erneut versuchen',
                'warte': warte.inSeconds + 1,
              },
              status: 429,
              warte: warte,
            ),
  };

  /// Das Cookie – oder mit `null` sein Ende.
  String _cookie(Request anfrage, String? token) => [
    '$webCookie=${token ?? ''}',
    'Path=/',
    'HttpOnly',
    'SameSite=Strict',
    'Max-Age=${token == null ? 0 : konten.geraetAblauf.inSeconds}',
    if (_verschluesselt(anfrage)) 'Secure',
  ].join('; ');

  /// Ob der Browser über HTTPS kam – direkt, oder über einen vertrauten
  /// Proxy, der es sagt. Nur dann trägt das Cookie `Secure`: Im Heimnetz
  /// über http nähme der Browser es sonst gar nicht erst an.
  bool _verschluesselt(Request anfrage) {
    if (anfrage.requestedUri.scheme == 'https') return true;
    if (!absender.ueberVertrautenProxy(anfrage)) return false;
    final proto = anfrage.headers['x-forwarded-proto'] ?? '';
    return proto.split(',').first.trim().toLowerCase() == 'https';
  }

  /// „Browser (Firefox)“ – was in der Geräteliste steht.
  static String _geraetName(Request anfrage) {
    final ua = anfrage.headers['user-agent'] ?? '';
    final b = ua.contains('Edg/')
        ? 'Edge'
        : ua.contains('OPR/')
        ? 'Opera'
        : ua.contains('Firefox/')
        ? 'Firefox'
        : ua.contains('Chrome/')
        ? 'Chrome'
        : ua.contains('Safari/')
        ? 'Safari'
        : null;
    return b == null ? 'Browser' : 'Browser ($b)';
  }

  static Future<Map<String, Object?>?> _koerper(Request anfrage) async {
    try {
      final j = jsonDecode(await anfrage.readAsString());
      return j is Map ? j.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }

  static Response _json(
    Object? daten, {
    int status = 200,
    Duration? warte,
    String? cookie,
  }) => Response(
    status,
    body: jsonEncode(daten),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      if (warte != null) 'retry-after': '${warte.inSeconds + 1}',
      'set-cookie': ?cookie,
    },
  );
}
