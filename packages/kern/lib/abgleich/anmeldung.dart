import 'dart:convert';

import 'package:http/http.dart' as http;

import 'verbindung.dart';

/// Was der Server auf eine Anmeldung antwortet.
sealed class Anmeldeschritt {
  const Anmeldeschritt();
}

/// Angemeldet: das Token dieses Geräts, beim Einrichten von TOTP dazu die
/// Wiederherstellungscodes (einmal zu zeigen).
final class AnmeldungFertig extends Anmeldeschritt {
  const AnmeldungFertig(this.token, {this.wiederherstellungscodes});
  final String token;
  final List<String>? wiederherstellungscodes;
}

/// Jetzt der Code aus der Authenticator-App.
final class AnmeldungCode extends Anmeldeschritt {
  const AnmeldungCode(this.vorgang);
  final String vorgang;
}

/// TOTP muss erst eingerichtet werden: [adresse] als QR-Code zeigen.
final class AnmeldungTotpEinrichten extends Anmeldeschritt {
  const AnmeldungTotpEinrichten(this.vorgang, this.geheimnis, this.adresse);
  final String vorgang;
  final String geheimnis;
  final String adresse;
}

/// Abgewiesen; mit [warte], wenn der Server bremst.
final class AnmeldungAbgewiesen extends Anmeldeschritt {
  const AnmeldungAbgewiesen({this.warte});
  final Duration? warte;
}

/// So lang muss das Passwort eines Kontos mindestens sein – die App prüft
/// es vorher, der Server ohnehin.
const passwortMindestlaenge = 12;

/// Ob [name] als Kontoname taugt: 2 bis 40 Buchstaben, Ziffern, Punkt,
/// Strich oder Unterstrich.
bool kontonameGueltig(String name) =>
    RegExp(r'^[\p{L}\p{N}._-]{2,40}$', unicode: true).hasMatch(name.trim());

/// Meldet ein Gerät bei einem Server an (siehe dort `Anmeldungsapi`).
class Anmeldung {
  Anmeldung(this.server, {http.Client? client})
    : _http = client ?? http.Client();

  final Uri server;
  final http.Client _http;

  Uri _adresse(String pfad) {
    final b = server.path.endsWith('/')
        ? server
        : server.replace(path: '${server.path}/');
    return b.resolve(pfad);
  }

  /// Ob unter [server] ein Photo Vault Server antwortet – und wie man sich
  /// dort anmeldet (`{protokoll, anmeldung: {totp, oidc}}`).
  Future<Map<String, Object?>> zustand() async {
    final r = await _schicke(() => _http.get(_adresse('api/v1/zustand')));
    final j = jsonDecode(r.body);
    if (r.statusCode != 200 || j is! Map || j['dienst'] != 'photo-vault') {
      throw Serverfehler(r.statusCode, r.body);
    }
    return j.cast<String, Object?>();
  }

  Future<Anmeldeschritt> anmelden(
    String name,
    String passwort, {
    required String geraet,
  }) => _schritt('api/v1/anmelden', {
    'name': name,
    'passwort': passwort,
    'geraet': geraet,
  });

  /// Legt das erste Konto an und meldet an wie [anmelden] – nur, solange
  /// der Server noch keines hat (`zustand()['einrichten']`) und nur aus dem
  /// Heimnetz. Sonst ein [Serverfehler]: 403 von aussen, 409 schon
  /// eingerichtet, 400 Name oder Passwort taugen nicht.
  Future<Anmeldeschritt> einrichten(
    String name,
    String passwort, {
    required String geraet,
  }) => _schritt('api/v1/einrichten', {
    'name': name,
    'passwort': passwort,
    'geraet': geraet,
  });

  Future<Anmeldeschritt> bestaetige(String vorgang, String code) =>
      _schritt('api/v1/anmelden/totp', {'vorgang': vorgang, 'code': code});

  Future<Anmeldeschritt> _schritt(String pfad, Map<String, Object?> k) async {
    final r = await _schicke(
      () => _http.post(
        _adresse(pfad),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(k),
      ),
    );
    if (r.statusCode == 401) return const AnmeldungAbgewiesen();
    if (r.statusCode == 429) {
      return AnmeldungAbgewiesen(
        warte: Duration(
          seconds: int.tryParse(r.headers['retry-after'] ?? '') ?? 60,
        ),
      );
    }
    if (r.statusCode != 200) throw Serverfehler(r.statusCode, r.body);
    final j = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)
        .cast<String, Object?>();
    return switch (j['schritt']) {
      'totp' => AnmeldungCode(j['vorgang']! as String),
      'totp_einrichten' => AnmeldungTotpEinrichten(
        j['vorgang']! as String,
        j['geheimnis']! as String,
        j['adresse']! as String,
      ),
      _ => AnmeldungFertig(
        j['token']! as String,
        wiederherstellungscodes: (j['wiederherstellungscodes'] as List?)
            ?.cast<String>(),
      ),
    };
  }

  Future<http.Response> _schicke(Future<http.Response> Function() f) async {
    try {
      return await f().timeout(const Duration(seconds: 20));
    } catch (e) {
      if (e is Serverfehler) rethrow;
      throw KeineVerbindung(e);
    }
  }

  void schliesse() => _http.close();
}
