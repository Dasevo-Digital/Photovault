import 'dart:async';
import 'dart:convert';

import 'package:kern/protokoll.dart';
import 'package:shelf/shelf.dart';

import 'absender.dart';
import 'konten/kontodienst.dart';
import 'oidc.dart';

const _kontoSchluessel = 'pv.konto';
const _geraetSchluessel = 'pv.geraet';
const _browserSchluessel = 'pv.browser';

/// Das Cookie der Weboberfläche (siehe `Webapi`).
const webCookie = 'pv_web';

/// Ob die Anfrage mit dem Cookie der Weboberfläche angemeldet ist.
bool ausDemBrowser(Request anfrage) =>
    anfrage.context[_browserSchluessel] == true;

/// Der Wert des Cookies [name], falls der Browser eins schickt.
String? cookieWert(Request anfrage, String name) {
  final kopf = anfrage.headers['cookie'];
  if (kopf == null) return null;
  for (final teil in kopf.split(';')) {
    final t = teil.trim();
    if (t.startsWith('$name=')) return t.substring(name.length + 1);
  }
  return null;
}

/// Schutz vor Anfragen fremder Seiten mit dem Cookie (CSRF). Lesende
/// Anfragen dürfen – das Cookie geht mit `SameSite=Strict` fremd ohnehin
/// nicht mit, und lesen heisst lesen. Alles andere braucht den Kopf
/// `X-PV-Web`, den nur die eigene Oberfläche setzt (eine fremde Seite käme
/// damit nicht an der CORS-Vorabfrage vorbei, die der Server nie bejaht);
/// und sagt der Browser, woher die Anfrage kommt (`Origin`,
/// `Sec-Fetch-Site`), muss es dieselbe Seite sein.
bool anfrageAusDerOberflaeche(Request anfrage) {
  if (const {'GET', 'HEAD', 'OPTIONS'}.contains(anfrage.method)) return true;
  if (anfrage.headers['x-pv-web'] == null) return false;
  final sfs = anfrage.headers['sec-fetch-site'];
  if (sfs != null && sfs != 'same-origin' && sfs != 'none') return false;
  final herkunft = anfrage.headers['origin'];
  if (herkunft != null) {
    final h = Uri.tryParse(herkunft);
    final eigene = {
      anfrage.requestedUri.authority,
      ?anfrage.headers['host'],
      ?anfrage.headers['x-forwarded-host'],
    }..removeWhere((s) => s.isEmpty);
    if (h == null || !eigene.contains(h.authority)) return false;
  }
  return true;
}

/// Das Konto hinter einer angemeldeten Anfrage.
Konto kontoVon(Request anfrage) => anfrage.context[_kontoSchluessel]! as Konto;

/// Das Gerät hinter einer angemeldeten Anfrage.
Geraet geraetVon(Request anfrage) =>
    anfrage.context[_geraetSchluessel]! as Geraet;

/// Lässt nur Anfragen mit gültigem Geräte-Token durch; [offen] sind die
/// Pfade ohne (Lebenszeichen, Anmeldung).
Middleware anmeldungNoetig(
  Kontodienst konten,
  Absender absender, {
  Set<String> offen = const {},
  Set<String> offenPraefixe = const {},
}) =>
    (innerer) => (anfrage) {
      final pfad = anfrage.url.path;
      if (offen.contains(pfad) || offenPraefixe.any(pfad.startsWith)) {
        return innerer(anfrage);
      }
      final kopf = anfrage.headers['authorization'];
      final String? token;
      final bool browser;
      if (kopf != null && kopf.startsWith('Bearer ')) {
        token = kopf.substring(7).trim();
        browser = false;
      } else {
        token = cookieWert(anfrage, webCookie);
        browser = token != null;
      }
      final treffer = token == null
          ? null
          : konten.pruefeToken(token, absender.von(anfrage));
      if (treffer == null) {
        return Response(
          401,
          body: jsonEncode({'fehler': 'nicht angemeldet'}),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'cache-control': 'no-store',
            'www-authenticate': 'Bearer',
          },
        );
      }
      if (browser && !anfrageAusDerOberflaeche(anfrage)) {
        return Response(
          403,
          body: jsonEncode({'fehler': 'Anfrage nicht aus der Weboberfläche'}),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'cache-control': 'no-store',
          },
        );
      }
      return innerer(
        anfrage.change(
          context: {
            _kontoSchluessel: treffer.konto,
            _geraetSchluessel: treffer.geraet,
            _browserSchluessel: browser,
          },
        ),
      );
    };

/// Antworten der Anmeldung werden nie zwischengespeichert: Sie tragen
/// Tokens und Codes.
Response _json(Object? daten, {int status = 200, Duration? warte}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    if (warte != null) 'retry-after': '${warte.inSeconds + 1}',
  },
);

Future<Map<String, Object?>?> _koerper(Request anfrage) async {
  try {
    final j = jsonDecode(await anfrage.readAsString());
    return j is Map ? j.cast<String, Object?>() : null;
  } on FormatException {
    return null;
  }
}

/// Anmelden, abmelden, Geräte und das eigene Konto.
class Anmeldungsapi {
  Anmeldungsapi(this.konten, this.absender, this.oidc);

  final Kontodienst konten;
  final Absender absender;
  final Oidc? oidc;

  Response _ergebnis(Anmeldeergebnis e) => switch (e) {
    Angemeldet() => _json({
      'token': e.token,
      'geraet': e.geraet.alsJson(),
      if (e.wiederherstellungscodes != null)
        'wiederherstellungscodes': e.wiederherstellungscodes,
    }),
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

  /// `{name, passwort, geraet}` → Token oder der nächste Schritt.
  Future<Response> anmelden(Request anfrage) async {
    final k = await _koerper(anfrage);
    final name = k?['name'], passwort = k?['passwort'];
    if (name is! String || passwort is! String) {
      return _json({'fehler': 'name und passwort fehlen'}, status: 400);
    }
    return _ergebnis(
      await konten.anmelden(
        name,
        passwort,
        geraet: '${k!['geraet'] ?? ''}',
        adresse: absender.von(anfrage),
      ),
    );
  }

  /// `{name, passwort, geraet}` – legt das erste Konto an (es wird
  /// Verwalter) und meldet an wie [anmelden]; mit TOTP-Pflicht folgt die
  /// Einrichtung.
  ///
  /// **Nur, solange es kein Konto gibt, und nur aus dem Heimnetz:** Wer den
  /// Server zuerst erreicht, bekommt ihn. Von aussen – über den Proxy oder
  /// eine offene Portweiterleitung – soll das niemand sein. Danach geht der
  /// Weg zu; weitere Konten legt ein Verwalter an.
  Future<Response> einrichten(Request anfrage) async {
    if (konten.eingerichtet) {
      return _json({
        'fehler': 'Der Server ist schon eingerichtet.',
      }, status: 409);
    }
    if (!absender.ausDemHeimnetz(anfrage)) {
      return _json({
        'fehler':
            'Das erste Konto lässt sich nur aus dem Heimnetz anlegen, nicht '
            'von aussen.',
      }, status: 403);
    }
    final k = await _koerper(anfrage);
    final name = k?['name'], passwort = k?['passwort'];
    if (name is! String || passwort is! String) {
      return _json({'fehler': 'name und passwort fehlen'}, status: 400);
    }
    final Konto konto;
    try {
      konto = await konten.legeAn(name, passwort, nurAlsErstes: true);
    } on ArgumentError catch (f) {
      return _json({'fehler': '${f.message}'}, status: 400);
    } on StateError catch (f) {
      return _json({'fehler': f.message}, status: 409);
    }
    protokoll(
      'Erstes Konto „${konto.name}“ über die App angelegt '
      '(von ${absender.von(anfrage)})',
    );
    return _ergebnis(
      await konten.anmelden(
        name,
        passwort,
        geraet: '${k!['geraet'] ?? ''}',
        adresse: absender.von(anfrage),
      ),
    );
  }

  /// `{vorgang, code}` – der Code aus der Authenticator-App oder ein
  /// Wiederherstellungscode.
  Future<Response> totp(Request anfrage) async {
    final k = await _koerper(anfrage);
    final vorgang = k?['vorgang'], code = k?['code'];
    if (vorgang is! String || code is! String) {
      return _json({'fehler': 'vorgang und code fehlen'}, status: 400);
    }
    return _ergebnis(
      await konten.bestaetige(vorgang, code, adresse: absender.von(anfrage)),
    );
  }

  /// Meldet dieses Gerät ab.
  Response abmelden(Request anfrage) {
    konten.abmelden(kontoVon(anfrage).id, geraetVon(anfrage).id);
    return _json({'abgemeldet': true});
  }

  Response konto(Request anfrage) {
    final k = kontoVon(anfrage);
    return _json({
      'id': k.id,
      'name': k.name,
      'verwalter': k.verwalter,
      'totp': k.hatTotp,
      'wiederherstellungscodes': konten.uebrigeCodes(k.id),
      'oidc': konten.oidcAussteller(k.id),
      'geraet': geraetVon(anfrage).id,
    });
  }

  /// `{alt, neu, code?, andereAbmelden?}`
  Future<Response> passwort(Request anfrage) async {
    final k = await _koerper(anfrage);
    final alt = k?['alt'], neu = k?['neu'], code = k?['code'];
    if (alt is! String || neu is! String) {
      return _json({'fehler': 'alt und neu fehlen'}, status: 400);
    }
    try {
      final ok = await konten.aenderePasswort(
        kontoVon(anfrage).id,
        alt,
        neu,
        code: code is String ? code : null,
        behalteGeraet: geraetVon(anfrage).id,
        andereAbmelden: k!['andereAbmelden'] == true,
      );
      return ok
          ? _json({'geaendert': true})
          : _json({'fehler': 'Passwort oder Code stimmt nicht'}, status: 403);
    } on ArgumentError catch (f) {
      return _json({'fehler': '${f.message}'}, status: 400);
    }
  }

  /// `{code}` → zehn neue Wiederherstellungscodes; die alten gelten nicht
  /// mehr.
  Future<Response> codes(Request anfrage) async {
    final k = await _koerper(anfrage);
    final code = k?['code'];
    if (code is! String) return _json({'fehler': 'code fehlt'}, status: 400);
    final neu = await konten.erneuereWiederherstellungscodes(
      kontoVon(anfrage).id,
      code,
    );
    return neu == null
        ? _json({'fehler': 'Code stimmt nicht'}, status: 403)
        : _json({'wiederherstellungscodes': neu});
  }

  Response geraete(Request anfrage) => _json({
    'geraete': [
      for (final g in konten.geraete(kontoVon(anfrage).id)) g.alsJson(),
    ],
    'dieses': geraetVon(anfrage).id,
  });

  Response geraetAbmelden(Request anfrage, String id) =>
      konten.abmelden(kontoVon(anfrage).id, id)
      ? _json({'abgemeldet': true})
      : _json({'fehler': 'unbekannt'}, status: 404);

  // --- OIDC --------------------------------------------------------------

  Response _keinOidc() =>
      _json({'fehler': 'OIDC ist nicht eingerichtet'}, status: 404);

  /// Startadresse für den Browser:
  /// `?geraet=…&rueckweg=…&pruefwert=…&zustand=…`.
  Future<Response> oidcStart(Request anfrage) async {
    final o = oidc;
    if (o == null) return _keinOidc();
    final q = anfrage.url.queryParameters;
    final rueckweg = Uri.tryParse(q['rueckweg'] ?? '');
    try {
      final ziel = await o.beginne(
        absicht: OidcAbsicht.anmelden,
        geraet: q['geraet'] ?? '',
        rueckweg: rueckweg ?? Uri(),
        appPruefwert: q['pruefwert'] ?? '',
        appZustand: q['zustand'],
      );
      return Response.found(ziel, headers: {'cache-control': 'no-store'});
    } on OidcFehler catch (f) {
      return schlichteSeite(f.text, status: 400);
    }
  }

  /// `{rueckweg, pruefwert, zustand?}` → `{adresse}`: Diese Adresse öffnet
  /// die App im Browser, um die Anmeldung beim Anbieter mit dem eigenen
  /// Konto zu verknüpfen. Bestätigt wird über
  /// `POST /api/v1/anmelden/oidc/einloesen` mit dem Token dieses Kontos.
  Future<Response> oidcVerknuepfen(Request anfrage) async {
    final o = oidc;
    if (o == null) return _keinOidc();
    final k = await _koerper(anfrage);
    try {
      final ziel = await o.beginne(
        absicht: OidcAbsicht.verknuepfen,
        geraet: geraetVon(anfrage).name,
        rueckweg: Uri.tryParse('${k?['rueckweg'] ?? ''}') ?? Uri(),
        appPruefwert: '${k?['pruefwert'] ?? ''}',
        appZustand: k?['zustand'] as String?,
        kontoId: kontoVon(anfrage).id,
      );
      return _json({'adresse': ziel.toString()});
    } on OidcFehler catch (f) {
      return _json({'fehler': f.text}, status: 400);
    }
  }

  /// Der Rückweg vom Anbieter – leitet zur App weiter.
  Future<Response> oidcZurueck(Request anfrage) async {
    final o = oidc;
    if (o == null) return _keinOidc();
    try {
      final ziel = await o.zurueck(anfrage.url.queryParameters);
      return Response.found(ziel, headers: {'cache-control': 'no-store'});
    } on OidcFehler catch (f) {
      return schlichteSeite(f.text, status: 400);
    }
  }

  /// `{code, pruefer}` → Token (Anmeldung) oder `{verknuepft: true}`
  /// (Verknüpfung; dann mit dem Token des Kontos, das sie begonnen hat).
  Future<Response> oidcEinloesen(Request anfrage) async {
    final o = oidc;
    if (o == null) return _keinOidc();
    final adresse = absender.von(anfrage);
    final warte = konten.bremse.wartezeit(adresse);
    if (warte != null) {
      return _json(
        {'fehler': 'Zu viele Fehlversuche'},
        status: 429,
        warte: warte,
      );
    }
    final k = await _koerper(anfrage);
    final code = k?['code'], pruefer = k?['pruefer'];
    final e = code is String && pruefer is String
        ? o.loeseEin(code, pruefer)
        : null;
    if (e == null) {
      konten.bremse.fehlschlag(adresse);
      return _json({'fehler': 'Code ungültig oder abgelaufen'}, status: 401);
    }
    switch (e.absicht) {
      case OidcAbsicht.anmelden:
        final konto = konten.kontoFuerOidc(e.aussteller, e.subjekt);
        if (konto == null) {
          return _json({
            'fehler':
                'Diese Anmeldung ist mit keinem Konto verknüpft. Mit Passwort '
                'anmelden und unter „Konto“ verknüpfen.',
          }, status: 403);
        }
        return _ergebnis(konten.meldeAn(konto.id, e.geraet, adresse));
      case OidcAbsicht.verknuepfen:
        // Die Verknüpfung gilt nur für das Konto, das sie begonnen hat,
        // und nur, wenn es sie selbst einlöst.
        final kopf = anfrage.headers['authorization'];
        final wer = kopf != null && kopf.startsWith('Bearer ')
            ? konten.pruefeToken(kopf.substring(7).trim(), adresse)
            : null;
        if (wer == null || wer.konto.id != e.kontoId) {
          return _json({'fehler': 'nicht angemeldet'}, status: 401);
        }
        try {
          konten.verknuepfe(wer.konto.id, e.aussteller, e.subjekt);
        } on StateError catch (f) {
          return _json({'fehler': f.message}, status: 409);
        }
        return _json({'verknuepft': true});
    }
  }
}

/// Eine schlichte Seite für den Browser: wenn es bei der Anmeldung keinen
/// Weg zurück zur App gibt, und als Startseite des Servers.
Response schlichteSeite(
  String text, {
  int status = 200,
  String? linkZiel,
  String? linkText,
}) {
  final sicher = const HtmlEscape().convert(text);
  final link = linkZiel == null
      ? ''
      : '<p><a href="${const HtmlEscape(HtmlEscapeMode.attribute).convert(linkZiel)}">'
            '${const HtmlEscape().convert(linkText ?? linkZiel)}</a></p>';
  return Response(
    status,
    body:
        '<!doctype html><html lang="de"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width">'
        '<title>Photo Vault</title>'
        '<body style="font-family:system-ui;max-width:32em;margin:3em auto;'
        'padding:0 1em"><h1>Photo Vault</h1><p>$sicher</p>$link</body></html>',
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'content-security-policy':
          "default-src 'none'; style-src 'unsafe-inline'; "
          "frame-ancestors 'none'; base-uri 'none'",
    },
  );
}
