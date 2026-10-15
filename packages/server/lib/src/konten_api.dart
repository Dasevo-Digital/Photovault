import 'dart:convert';

import 'package:kern/protokoll.dart';
import 'package:shelf/shelf.dart';

import 'anmeldung_api.dart';
import 'bibliotheken.dart';
import 'konten/kontodienst.dart';

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

/// `/api/v1/konten` – die Konten des Servers, nur für Verwalter: anlegen,
/// Passwort neu setzen, TOTP zurücksetzen, entsperren, entfernen. Dasselbe
/// wie `photo_vault_server konto …`, nur ohne Zugang zum Rechner.
class Kontenapi {
  Kontenapi(this.konten, this.bibliotheken);

  final Kontodienst konten;
  final Bibliotheken bibliotheken;

  Response? _nurVerwalter(Request anfrage) => kontoVon(anfrage).verwalter
      ? null
      : _json({'fehler': 'Nur für Verwalter.'}, status: 403);

  Map<String, Object?> _alsJson(Konto k, Request anfrage) => {
    'id': k.id,
    'name': k.name,
    'verwalter': k.verwalter,
    'totp': k.hatTotp,
    'gesperrt': k.gesperrtBis?.isAfter(DateTime.now()) ?? false,
    'geraete': konten.geraete(k.id).length,
    'angelegt': k.angelegt.toUtc().toIso8601String(),
    'du': k.id == kontoVon(anfrage).id,
  };

  Response liste(Request anfrage) =>
      _nurVerwalter(anfrage) ??
      _json({
        'konten': [for (final k in konten.alle()) _alsJson(k, anfrage)],
      });

  /// `{name, passwort, verwalter?}`
  Future<Response> anlegen(Request anfrage) async {
    if (_nurVerwalter(anfrage) case final nein?) return nein;
    final k = await _koerper(anfrage);
    final name = k?['name'], passwort = k?['passwort'];
    if (name is! String || passwort is! String) {
      return _json({'fehler': 'name und passwort fehlen'}, status: 400);
    }
    try {
      final neu = await konten.legeAn(
        name,
        passwort,
        verwalter: k!['verwalter'] == true,
      );
      protokoll('Konto „${neu.name}“ angelegt von „${kontoVon(anfrage).name}“');
      return _json(_alsJson(neu, anfrage), status: 201);
    } on ArgumentError catch (f) {
      return _json({'fehler': '${f.message}'}, status: 400);
    } on StateError catch (f) {
      return _json({'fehler': f.message}, status: 409);
    }
  }

  /// Das Konto [id], solange es ein anderes als das eigene ist – das eigene
  /// ändert jeder unter `/konto`.
  (Konto?, Response?) _anderes(Request anfrage, String id) {
    if (_nurVerwalter(anfrage) case final nein?) return (null, nein);
    final k = konten.konto(id);
    if (k == null) {
      return (null, _json({'fehler': 'Kein solches Konto.'}, status: 404));
    }
    if (k.id == kontoVon(anfrage).id) {
      return (
        null,
        _json({'fehler': 'Das eigene Konto nicht hier.'}, status: 409),
      );
    }
    return (k, null);
  }

  /// `{neu}` – setzt ein Passwort und meldet alle Geräte des Kontos ab.
  Future<Response> passwort(Request anfrage, String id) async {
    final (k, nein) = _anderes(anfrage, id);
    if (k == null) return nein!;
    final neu = (await _koerper(anfrage))?['neu'];
    if (neu is! String) return _json({'fehler': 'neu fehlt'}, status: 400);
    try {
      await konten.setzePasswort(k.id, neu);
    } on ArgumentError catch (f) {
      return _json({'fehler': '${f.message}'}, status: 400);
    }
    return _json(_alsJson(konten.konto(k.id)!, anfrage));
  }

  Response totpZuruecksetzen(Request anfrage, String id) {
    final (k, nein) = _anderes(anfrage, id);
    if (k == null) return nein!;
    konten.totpZuruecksetzen(k.id);
    return _json(_alsJson(konten.konto(k.id)!, anfrage));
  }

  Response entsperren(Request anfrage, String id) {
    final (k, nein) = _anderes(anfrage, id);
    if (k == null) return nein!;
    konten.entsperre(k.id);
    return _json(_alsJson(konten.konto(k.id)!, anfrage));
  }

  /// Entfernt das Konto; seine Bibliothek wird beiseitegelegt, nicht
  /// gelöscht (siehe [Bibliotheken.legeBeiseite]).
  Future<Response> entfernen(Request anfrage, String id) async {
    final (k, nein) = _anderes(anfrage, id);
    if (k == null) return nein!;
    konten.entferne(k.id);
    final beiseite = await bibliotheken.legeBeiseite(k.id);
    protokoll(
      'Konto „${k.name}“ entfernt von „${kontoVon(anfrage).name}“'
      '${beiseite == null ? '' : ' – Bibliothek liegt in ${beiseite.path}'}',
    );
    return _json({'entfernt': true, 'bibliothekBeiseite': beiseite != null});
  }

  static Future<Map<String, Object?>?> _koerper(Request anfrage) async {
    try {
      final j = jsonDecode(await anfrage.readAsString());
      return j is Map ? j.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }
}
