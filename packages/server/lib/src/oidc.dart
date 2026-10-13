import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Wie der Server mit einem OIDC-Anbieter spricht (Authentik, Keycloak,
/// Pocket ID …).
class OidcEinstellungen {
  const OidcEinstellungen({
    required this.aussteller,
    required this.client,
    required this.oeffentlich,
    this.geheimnis,
    this.bereiche = 'openid profile',
  });

  /// `issuer` des Anbieters, z. B. `https://anmeldung.example.de/application/o/fotos/`.
  final Uri aussteller;
  final String client;

  /// Fehlt es, ist der Server ein öffentlicher Client (nur PKCE).
  final String? geheimnis;

  /// Unter welcher Adresse der Server von aussen erreichbar ist – der
  /// Anbieter schickt den Browser dorthin zurück.
  final Uri oeffentlich;
  final String bereiche;

  /// Die Adresse, die beim Anbieter als Weiterleitung eingetragen wird.
  Uri get rueckruf {
    final basis = oeffentlich.path.endsWith('/')
        ? oeffentlich
        : oeffentlich.replace(path: '${oeffentlich.path}/');
    return basis.resolve('api/v1/anmelden/oidc/zurueck');
  }
}

/// Wofür eine Anmeldung beim Anbieter gedacht ist.
enum OidcAbsicht { anmelden, verknuepfen }

/// Ein Fehler, den der Nutzer sehen darf.
class OidcFehler implements Exception {
  OidcFehler(this.kennung, this.text);

  /// Kurz, für den Rückweg zur App (`fehler=…`).
  final String kennung;
  final String text;

  @override
  String toString() => text;
}

/// Was nach dem Rückweg vom Anbieter zum Einlösen bereitliegt.
class OidcEinloesung {
  OidcEinloesung({
    required this.absicht,
    required this.geraet,
    required this.aussteller,
    required this.subjekt,
    required this.kontoId,
  });

  final OidcAbsicht absicht;
  final String geraet;
  final String aussteller;
  final String subjekt;

  /// Beim Verknüpfen: das Konto, das es begonnen hat.
  final String? kontoId;
}

class _Lauf {
  _Lauf({
    required this.absicht,
    required this.geraet,
    required this.rueckweg,
    required this.appPruefwert,
    required this.appZustand,
    required this.nonce,
    required this.pruefer,
    required this.ablauf,
    this.kontoId,
  });

  final OidcAbsicht absicht;
  final String geraet;
  final Uri rueckweg;
  final String appPruefwert;
  final String? appZustand;
  final String nonce;
  final String pruefer;
  final DateTime ablauf;
  final String? kontoId;
}

class _Code {
  _Code(this.einloesung, this.appPruefwert, this.ablauf);
  final OidcEinloesung einloesung;
  final String appPruefwert;
  final DateTime ablauf;
}

/// Anmelden über einen OIDC-Anbieter – Authorization Code mit PKCE.
///
/// **Der Weg.** Die App öffnet im Browser die Startadresse des Servers und
/// gibt dabei ihren Rückweg (Loopback oder das eigene Schema der App) und
/// den Prüfwert eines nur ihr bekannten Prüfers mit (PKCE, S256). Der
/// Server leitet zum Anbieter weiter; der schickt den Browser mit einem
/// Code zurück zum Server. Der Server löst ihn beim Anbieter ein, prüft
/// das ID-Token und leitet mit einem eigenen, einmaligen Code zum Rückweg
/// der App. Die App löst diesen mit ihrem Prüfer ein und bekommt ihr Token.
///
/// **Warum zwei Codes und ein Prüfer.** Wer einem anderen eine Startadresse
/// unterschiebt, bekommt nichts: Der Browser des Opfers kehrt zu dessen
/// eigenem Gerät zurück, nicht zu dem, der die Adresse gebaut hat, und der
/// Code taugt ohne den Prüfer nicht. Rückwege ins Netz lässt der Server
/// deshalb gar nicht zu.
///
/// **Das ID-Token wird nicht über seine Signatur geprüft**, sondern über
/// den Weg: Es kommt unmittelbar vom Token-Endpunkt des Anbieters über
/// TLS, und für genau diesen Fall erlaubt OIDC Core (3.1.3.7) das. Geprüft
/// werden Aussteller, Empfänger, Ablauf und `nonce`.
class Oidc {
  Oidc(this.e, {DateTime Function()? uhr, HttpClient? client})
    : _uhr = uhr ?? DateTime.now,
      _http = client ?? HttpClient();

  final OidcEinstellungen e;
  final DateTime Function() _uhr;
  final HttpClient _http;

  final _laeufe = <String, _Lauf>{};
  final _codes = <String, _Code>{};

  Map<String, Object?>? _entdeckt;
  DateTime? _entdecktAm;

  static const _laufDauer = Duration(minutes: 10);
  static const _codeDauer = Duration(minutes: 2);

  /// Die eigenen Schemata der App, über die ein Rückweg führen darf.
  static const schemata = {'photovault', 'de.dasevo.photovault'};

  /// Ob [rueckweg] zur App auf diesem Gerät führt – und nirgends sonst.
  static bool rueckwegErlaubt(Uri rueckweg) {
    if (schemata.contains(rueckweg.scheme)) return true;
    return rueckweg.scheme == 'http' &&
        const {
          '127.0.0.1',
          '::1',
          '[::1]',
          'localhost',
        }.contains(rueckweg.host) &&
        rueckweg.userInfo.isEmpty;
  }

  /// Der Weg zum Anbieter für eine neue Anmeldung.
  Future<Uri> beginne({
    required OidcAbsicht absicht,
    required String geraet,
    required Uri rueckweg,
    required String appPruefwert,
    String? appZustand,
    String? kontoId,
  }) async {
    if (!rueckwegErlaubt(rueckweg)) {
      throw OidcFehler('rueckweg', 'Dieser Rückweg ist nicht erlaubt.');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(appPruefwert)) {
      throw OidcFehler('pruefwert', 'Der Prüfwert fehlt oder taugt nicht.');
    }
    final d = await _entdecke();
    _raeumeAuf();
    final zustand = _zufall(32);
    final nonce = _zufall(32);
    final pruefer = _zufall(64);
    _laeufe[zustand] = _Lauf(
      absicht: absicht,
      geraet: geraet,
      rueckweg: rueckweg,
      appPruefwert: appPruefwert,
      appZustand: appZustand,
      nonce: nonce,
      pruefer: pruefer,
      ablauf: _uhr().add(_laufDauer),
      kontoId: kontoId,
    );
    final ziel = Uri.parse(d['authorization_endpoint']! as String);
    return ziel.replace(
      queryParameters: {
        ...ziel.queryParameters,
        'response_type': 'code',
        'client_id': e.client,
        'redirect_uri': e.rueckruf.toString(),
        'scope': e.bereiche,
        'state': zustand,
        'nonce': nonce,
        'code_challenge': s256(pruefer),
        'code_challenge_method': 'S256',
      },
    );
  }

  /// Der Rückweg vom Anbieter. Gibt die Adresse zurück, zu der der Browser
  /// weitergeleitet wird – zur App, mit Code oder Fehler. Wirft
  /// [OidcFehler], wenn nicht einmal der Rückweg der App bekannt ist.
  Future<Uri> zurueck(Map<String, String> parameter) async {
    _raeumeAuf();
    final zustand = parameter['state'];
    final lauf = zustand == null ? null : _laeufe.remove(zustand);
    if (lauf == null) {
      throw OidcFehler(
        'unbekannt',
        'Diese Anmeldung ist unbekannt oder abgelaufen. Bitte in der App '
            'neu beginnen.',
      );
    }
    Uri zurApp(Map<String, String> werte) => lauf.rueckweg.replace(
      queryParameters: {
        ...lauf.rueckweg.queryParameters,
        ...werte,
        if (lauf.appZustand != null) 'zustand': lauf.appZustand!,
      },
    );
    if (parameter['error'] != null) {
      return zurApp({'fehler': 'abgelehnt'});
    }
    final code = parameter['code'];
    if (code == null) return zurApp({'fehler': 'kein_code'});
    try {
      final angaben = await _loeseEin(code, lauf);
      final eigener = _zufall(32);
      _codes[eigener] = _Code(
        OidcEinloesung(
          absicht: lauf.absicht,
          geraet: lauf.geraet,
          aussteller: angaben.aussteller,
          subjekt: angaben.subjekt,
          kontoId: lauf.kontoId,
        ),
        lauf.appPruefwert,
        _uhr().add(_codeDauer),
      );
      return zurApp({'code': eigener});
    } on OidcFehler catch (f) {
      return zurApp({'fehler': f.kennung});
    }
  }

  /// Löst den Code der App mit ihrem [pruefer] ein – einmal.
  OidcEinloesung? loeseEin(String code, String pruefer) {
    _raeumeAuf();
    final c = _codes.remove(code);
    if (c == null) return null;
    if (s256(pruefer) != c.appPruefwert) return null;
    return c.einloesung;
  }

  Future<({String aussteller, String subjekt})> _loeseEin(
    String code,
    _Lauf lauf,
  ) async {
    final d = await _entdecke();
    final ziel = Uri.parse(d['token_endpoint']! as String);
    _pruefeSicher(ziel);
    final anfrage = await _http.postUrl(ziel);
    anfrage.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    anfrage.headers.set('accept', 'application/json');
    final geheimnis = e.geheimnis;
    if (geheimnis != null) {
      final paar =
          '${Uri.encodeQueryComponent(e.client)}:'
          '${Uri.encodeQueryComponent(geheimnis)}';
      anfrage.headers.set(
        'authorization',
        'Basic ${base64.encode(utf8.encode(paar))}',
      );
    }
    anfrage.write(
      Uri(
        queryParameters: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': e.rueckruf.toString(),
          'code_verifier': lauf.pruefer,
          if (geheimnis == null) 'client_id': e.client,
        },
      ).query,
    );
    final antwort = await anfrage.close().timeout(const Duration(seconds: 15));
    final text = await utf8.decodeStream(antwort);
    if (antwort.statusCode != 200) {
      throw OidcFehler('token', 'Der Anbieter hat den Code nicht eingelöst.');
    }
    final json = jsonDecode(text);
    final idToken = json is Map ? json['id_token'] : null;
    if (idToken is! String) {
      throw OidcFehler('token', 'Der Anbieter hat kein ID-Token geschickt.');
    }
    final angaben = _angabenAus(idToken);
    final aussteller = d['issuer']! as String;
    if (angaben['iss'] != aussteller) {
      throw OidcFehler(
        'token',
        'Das ID-Token kommt von einem anderen Aussteller.',
      );
    }
    final aud = angaben['aud'];
    final empfaenger = aud is List ? aud.cast<Object?>() : [aud];
    if (!empfaenger.contains(e.client) ||
        (empfaenger.length > 1 && angaben['azp'] != e.client)) {
      throw OidcFehler('token', 'Das ID-Token ist nicht für diesen Server.');
    }
    final exp = angaben['exp'];
    final jetzt = _uhr().millisecondsSinceEpoch ~/ 1000;
    if (exp is! num || exp < jetzt - 60) {
      throw OidcFehler('token', 'Das ID-Token ist abgelaufen.');
    }
    if (angaben['nonce'] != lauf.nonce) {
      throw OidcFehler(
        'token',
        'Das ID-Token gehört zu einer anderen Anmeldung.',
      );
    }
    final sub = angaben['sub'];
    if (sub is! String || sub.isEmpty) {
      throw OidcFehler('token', 'Das ID-Token nennt keinen Nutzer.');
    }
    return (aussteller: aussteller, subjekt: sub);
  }

  Map<String, Object?> _angabenAus(String jwt) {
    final teile = jwt.split('.');
    if (teile.length != 3) {
      throw OidcFehler('token', 'Das ID-Token ist unlesbar.');
    }
    try {
      final kopf = jsonDecode(_b64(teile[0])) as Map;
      if ('${kopf['alg']}'.toLowerCase() == 'none') {
        throw OidcFehler('token', 'Ein unsigniertes ID-Token gilt nicht.');
      }
      return (jsonDecode(_b64(teile[1])) as Map).cast<String, Object?>();
    } on OidcFehler {
      rethrow;
    } catch (_) {
      throw OidcFehler('token', 'Das ID-Token ist unlesbar.');
    }
  }

  static String _b64(String s) =>
      utf8.decode(base64Url.decode(s.padRight((s.length + 3) ~/ 4 * 4, '=')));

  /// Die Angaben des Anbieters (`/.well-known/openid-configuration`), eine
  /// Stunde lang zwischengespeichert.
  Future<Map<String, Object?>> _entdecke() async {
    final schon = _entdeckt;
    final am = _entdecktAm;
    if (schon != null &&
        am != null &&
        _uhr().difference(am) < const Duration(hours: 1)) {
      return schon;
    }
    final basis = e.aussteller.toString().endsWith('/')
        ? e.aussteller.toString()
        : '${e.aussteller}/';
    final ziel = Uri.parse('$basis.well-known/openid-configuration');
    _pruefeSicher(ziel);
    final Map<String, Object?> d;
    try {
      final anfrage = await _http.getUrl(ziel);
      final antwort = await anfrage.close().timeout(
        const Duration(seconds: 15),
      );
      if (antwort.statusCode != 200) throw StateError('${antwort.statusCode}');
      d = (jsonDecode(await utf8.decodeStream(antwort)) as Map)
          .cast<String, Object?>();
    } catch (fehler) {
      throw OidcFehler(
        'anbieter',
        'Der Anbieter ist nicht erreichbar ($fehler).',
      );
    }
    final issuer = d['issuer'];
    String ohneStrich(Object? s) => '$s'.replaceAll(RegExp(r'/+$'), '');
    if (issuer is! String ||
        ohneStrich(issuer) != ohneStrich(e.aussteller) ||
        d['authorization_endpoint'] is! String ||
        d['token_endpoint'] is! String) {
      throw OidcFehler(
        'anbieter',
        'Die Angaben des Anbieters passen nicht zum eingestellten Aussteller.',
      );
    }
    _pruefeSicher(Uri.parse(d['authorization_endpoint']! as String));
    _entdeckt = d;
    _entdecktAm = _uhr();
    return d;
  }

  /// Nur HTTPS – ausser zum eigenen Rechner, für Prüfstände und einen
  /// Anbieter auf derselben Maschine.
  static void _pruefeSicher(Uri u) {
    if (u.scheme == 'https') return;
    if (u.scheme == 'http' &&
        const {'127.0.0.1', '::1', 'localhost'}.contains(u.host)) {
      return;
    }
    throw OidcFehler(
      'anbieter',
      'Der Anbieter muss über HTTPS erreichbar sein.',
    );
  }

  void _raeumeAuf() {
    final jetzt = _uhr();
    _laeufe.removeWhere((_, l) => l.ablauf.isBefore(jetzt));
    _codes.removeWhere((_, c) => c.ablauf.isBefore(jetzt));
    if (_laeufe.length > 1000) _laeufe.clear();
  }

  /// PKCE S256: base64url(SHA-256(pruefer)) ohne Auffüllzeichen.
  static String s256(String pruefer) => base64Url
      .encode(sha256.convert(ascii.encode(pruefer)).bytes)
      .replaceAll('=', '');

  static String _zufall(int laenge) {
    final z = Random.secure();
    final b = List<int>.generate(laenge, (_) => z.nextInt(256));
    return base64Url.encode(b).replaceAll('=', '').substring(0, laenge);
  }

  void schliesse() => _http.close(force: true);
}
