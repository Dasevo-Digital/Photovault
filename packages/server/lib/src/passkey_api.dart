import 'dart:convert';
import 'dart:math';

import 'package:kern/protokoll.dart';
import 'package:shelf/shelf.dart';

import 'absender.dart';
import 'anmeldung_api.dart';
import 'konten/kontodienst.dart';
import 'konten/passkeys.dart';
import 'oidc.dart';

/// Die Wege zu den Passkeys (#277), siehe konten/passkeys.dart.
///
/// **Im Browser** meldet die Seite selbst an (web.dart, mit Cookie) und
/// verwaltet die Passkeys des Kontos über `api/v1/konto/passkeys`.
///
/// **Auf dem Telefon** fragt nicht die App nach dem Passkey, sondern eine
/// Seite des Servers im Browser der App (`/app/passkey.html`): Ein Passkey
/// gehört zu der Adresse, unter der er angelegt wurde, und eine App dürfte
/// ihn nur mit einer Zuordnung zu genau dieser Adresse benutzen – die es
/// für einen Server, den jeder selbst betreibt, nicht geben kann. Der Weg
/// ist derselbe wie bei OIDC: Die Seite schickt den Browser mit einem Code
/// an einen Port auf dem Telefon zurück, die App löst ihn mit ihrem Prüfer
/// ein (PKCE). Zum Anlegen holt die App vorher ein Einmalticket, damit die
/// Seite weiss, für welches Konto.
class Passkeyapi {
  Passkeyapi(this.konten, this.absender, {DateTime Function()? uhr})
    : _uhr = uhr ?? DateTime.now;

  final Kontodienst konten;
  final Absender absender;
  final DateTime Function() _uhr;

  final _codes =
      <
        String,
        ({String konto, String pruefwert, String geraet, DateTime ablauf})
      >{};
  final _tickets = <String, ({String konto, DateTime ablauf})>{};
  static const _dauer = Duration(minutes: 5);

  Passkeys get _passkeys => konten.passkeys;

  // --- Anmelden -------------------------------------------------------------

  /// Die Vorgaben für `navigator.credentials.get` – im Browser wie auf der
  /// Seite für das Telefon.
  Future<Response> anmeldeoptionen(Request anfrage) async {
    try {
      return _json({
        'optionen': _passkeys.anmeldeoptionen(
          rp: Passkeys.rpAus(anfrage.headers['origin']),
        ),
      });
    } on PasskeyFehler catch (f) {
      return _json({'fehler': f.text}, status: 400);
    }
  }

  /// `{antwort, pruefwert, rueckweg, zustand?, geraet}` von der Seite für
  /// das Telefon → `{weiter}`: wohin die Seite den Browser schickt.
  Future<Response> anmeldenFuerGeraet(Request anfrage) async {
    final k = await _koerper(anfrage);
    final antwort = k?['antwort'], pruefwert = k?['pruefwert'];
    final rueckweg = Uri.tryParse('${k?['rueckweg'] ?? ''}');
    if (antwort is! Map<String, Object?> ||
        pruefwert is! String ||
        pruefwert.length < 32 ||
        rueckweg == null ||
        !_aufDiesemGeraet(rueckweg)) {
      return _json({'fehler': 'Anfrage unvollständig'}, status: 400);
    }
    final adresse = absender.von(anfrage);
    final warte = konten.bremse.wartezeit(adresse);
    if (warte != null) {
      return _json({'fehler': 'Zu viele Fehlversuche'}, status: 429);
    }
    final String konto;
    try {
      konto = await _passkeys.pruefeAnmeldung(
        herkunft: anfrage.headers['origin'] ?? '',
        antwort: antwort,
      );
    } on PasskeyFehler catch (f) {
      konten.bremse.fehlschlag(adresse);
      return _json({'fehler': f.text}, status: 401);
    }
    _raeumeAuf();
    final code = _zufall(32);
    _codes[code] = (
      konto: konto,
      pruefwert: pruefwert,
      geraet: '${k?['geraet'] ?? ''}',
      ablauf: _uhr().add(_dauer),
    );
    final zustand = k?['zustand'];
    return _json({
      'weiter': rueckweg
          .replace(
            queryParameters: {
              ...rueckweg.queryParameters,
              'code': code,
              if (zustand is String) 'zustand': zustand,
            },
          )
          .toString(),
    });
  }

  /// `{code, pruefer}` → wie die Anmeldung mit Passwort: `{token, geraet}`.
  Future<Response> einloesen(Request anfrage) async {
    final k = await _koerper(anfrage);
    final code = k?['code'], pruefer = k?['pruefer'];
    if (code is! String || pruefer is! String) {
      return _json({'fehler': 'code und pruefer fehlen'}, status: 400);
    }
    _raeumeAuf();
    final c = _codes.remove(code);
    if (c == null || Oidc.s256(pruefer) != c.pruefwert) {
      return _json({'fehler': 'Code unbekannt oder abgelaufen'}, status: 401);
    }
    final e = await konten.meldeMitPasskeyAn(
      () async => c.konto,
      geraet: c.geraet,
      adresse: absender.von(anfrage),
    );
    if (e is! Angemeldet) {
      return _json({'fehler': 'Das Konto ist gesperrt'}, status: 401);
    }
    protokoll('Anmeldung mit Passkey: Gerät „${e.geraet.name}“');
    return _json({'token': e.token, 'geraet': e.geraet.alsJson()});
  }

  // --- Verwalten ------------------------------------------------------------

  /// `{passkeys: [{id, name, angelegt, zuletzt}]}` des eigenen Kontos.
  Response liste(Request anfrage) => _json({
    'passkeys': [
      for (final p in _passkeys.von(kontoVon(anfrage).id)) p.alsJson(),
    ],
  });

  /// Die Vorgaben für `navigator.credentials.create` – im Browser.
  Response anlegeoptionen(Request anfrage) =>
      _anlegeoptionen(anfrage, kontoVon(anfrage).id, kontoVon(anfrage).name);

  /// `{antwort, name}` → `{passkey}` – im Browser.
  Future<Response> anlegen(Request anfrage) async =>
      _lege(anfrage, kontoVon(anfrage).id);

  Response entfernen(Request anfrage, String id) {
    if (!_passkeys.entferne(kontoVon(anfrage).id, id)) {
      return _json({'fehler': 'unbekannt'}, status: 404);
    }
    return _json({'entfernt': true});
  }

  /// `{adresse}`: die Seite, auf der das Telefon im Browser einen Passkey
  /// für sein Konto anlegt. Das Ticket darin gilt fünf Minuten und einmal.
  Response ticket(Request anfrage) {
    _raeumeAuf();
    final t = _zufall(32);
    _tickets[t] = (konto: kontoVon(anfrage).id, ablauf: _uhr().add(_dauer));
    return _json({'adresse': '/app/passkey.html?ticket=$t'});
  }

  /// `{ticket}` → die Vorgaben zum Anlegen, für die Seite des Telefons.
  Future<Response> ticketoptionen(Request anfrage) async {
    final konto = _ticketkonto(await _koerper(anfrage), verbrauchen: false);
    if (konto == null) {
      return _json({'fehler': 'Ticket unbekannt oder abgelaufen'}, status: 401);
    }
    return _anlegeoptionen(anfrage, konto, konten.konto(konto)?.name ?? '');
  }

  /// `{ticket, antwort, name}` → `{passkey}`, für die Seite des Telefons.
  Future<Response> ticketanlegen(Request anfrage) async {
    final k = await _koerper(anfrage);
    final konto = _ticketkonto(k, verbrauchen: true);
    if (konto == null) {
      return _json({'fehler': 'Ticket unbekannt oder abgelaufen'}, status: 401);
    }
    return _lege(anfrage, konto, koerper: k);
  }

  String? _ticketkonto(Map<String, Object?>? k, {required bool verbrauchen}) {
    _raeumeAuf();
    final t = k?['ticket'];
    if (t is! String) return null;
    final eintrag = verbrauchen ? _tickets.remove(t) : _tickets[t];
    return eintrag?.konto;
  }

  Response _anlegeoptionen(Request anfrage, String kontoId, String name) {
    try {
      return _json({
        'optionen': _passkeys.anlegeoptionen(
          kontoId: kontoId,
          kontoName: name,
          rp: Passkeys.rpAus(anfrage.headers['origin']),
          servername: 'Photo Vault',
        ),
      });
    } on PasskeyFehler catch (f) {
      return _json({'fehler': f.text}, status: 400);
    }
  }

  Future<Response> _lege(
    Request anfrage,
    String kontoId, {
    Map<String, Object?>? koerper,
  }) async {
    final k = koerper ?? await _koerper(anfrage);
    final antwort = k?['antwort'];
    if (antwort is! Map<String, Object?>) {
      return _json({'fehler': 'Antwort fehlt'}, status: 400);
    }
    try {
      final p = await _passkeys.lege(
        kontoId: kontoId,
        herkunft: anfrage.headers['origin'] ?? '',
        antwort: antwort,
        name: '${k?['name'] ?? ''}',
      );
      protokoll('Passkey „${p.name}“ angelegt');
      return _json({'passkey': p.alsJson()});
    } on PasskeyFehler catch (f) {
      return _json({'fehler': f.text}, status: 400);
    }
  }

  void _raeumeAuf() {
    final jetzt = _uhr();
    _codes.removeWhere((_, c) => c.ablauf.isBefore(jetzt));
    _tickets.removeWhere((_, t) => t.ablauf.isBefore(jetzt));
  }

  /// Nur zurück auf das Telefon selbst, wie bei OIDC (RFC 8252).
  static bool _aufDiesemGeraet(Uri u) =>
      u.scheme == 'http' &&
      const {'127.0.0.1', '::1', 'localhost'}.contains(u.host);

  static String _zufall(int laenge) {
    final r = Random.secure();
    return base64Url
        .encode(List.generate(laenge, (_) => r.nextInt(256)))
        .replaceAll('=', '')
        .substring(0, laenge);
  }
}

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

Future<Map<String, Object?>?> _koerper(Request anfrage) async {
  try {
    final k = jsonDecode(await anfrage.readAsString());
    return k is Map<String, Object?> ? k : null;
  } on FormatException {
    return null;
  }
}
