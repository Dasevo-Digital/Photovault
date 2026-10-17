import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/kartengruppen.dart';
import 'package:kern/services/rueckblick.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'abgleich_api.dart';
import 'absender.dart';
import 'anmeldung_api.dart';
import 'bibliotheken.dart';
import 'dateiantwort.dart';
import 'fassung.dart';
import 'konten/kontodienst.dart';
import 'konten_api.dart';
import 'oidc.dart';
import 'rechnen.dart';
import 'sicherung.dart';
import 'speicher.dart';
import 'suche_api.dart';
import 'umzug.dart';
import 'web.dart';
import 'zeilen_json.dart';

/// Welche Fassung der Schnittstelle der Server spricht. Steigt, sobald sich
/// etwas so ändert, dass ein älterer Client es falsch verstünde.
///
/// 2: Konten und Geräte-Tokens statt des einen Schlüssels.
const protokollFassung = 2;

/// Die Schnittstelle unter `/api/v1`.
///
/// Ohne Anmeldung erreichbar sind nur das Lebenszeichen und die Wege der
/// Anmeldung selbst; alles andere braucht das Token eines Geräts und
/// arbeitet dann auf der Bibliothek von dessen Konto.
Handler baueApi({
  required Kontodienst konten,
  required Bibliotheken bibliotheken,
  Absender? absender,
  Oidc? oidc,
  Future<Map<String, Object?>> Function()? beschleunigerZustand,
  Speicherwaechter? speicher,
  Serversicherung? sicherung,
  Directory? web,
}) {
  final von = absender ?? Absender();
  final oberflaeche = web == null ? null : Webapi(konten, von, ordner: web);
  final anmeldung = Anmeldungsapi(konten, von, oidc);
  final api = _Api(bibliotheken, beschleunigerZustand);
  final abgleich = Abgleichsapi(bibliotheken);
  final umzug = Umzugsdienst(bibliotheken);
  final suche = Suchapi(bibliotheken);
  final rechnen = Rechenapi(bibliotheken);
  final kontenapi = Kontenapi(konten, bibliotheken);
  Future<Kontobereich> bereich(Request r) => bibliotheken.fuer(kontoVon(r).id);

  /// Bei vollem Speicher keine neuen Daten (siehe [Speicherwaechter]).
  Handler wennPlatz(Handler h) =>
      (r) => speicher?.voll ?? false ? _speicherVoll() : h(r);

  final r = Router()
    // Wer die Adresse im Browser öffnet, sah bisher nur „nicht angemeldet“
    // und hielt den Server für kaputt.
    ..get(
      '/',
      (Request _) => oberflaeche == null
          ? schlichteSeite(
              'Der Server läuft. Eine Weboberfläche hat er nicht: Verbunden '
              'wird über die App – am Rechner unter Einstellungen → Server, '
              'auf dem Telefon beim ersten Start – mit dieser Adresse.',
            )
          : schlichteSeite(
              'Der Server läuft. Verbunden wird über die App – am Rechner '
              'unter Einstellungen → Server, auf dem Telefon beim ersten '
              'Start – mit dieser Adresse. Oder im Browser:',
              linkZiel: '/app/',
              linkText: 'Weboberfläche öffnen',
            ),
    )
    ..get(
      '/api/v1/zustand',
      (Request r) => api.zustand(
        konten,
        oidc,
        einrichten: !konten.eingerichtet && von.ausDemHeimnetz(r),
      ),
    )
    ..post('/api/v1/einrichten', anmeldung.einrichten)
    ..get('/api/v1/konten', kontenapi.liste)
    ..post('/api/v1/konten', kontenapi.anlegen)
    ..post('/api/v1/konten/<id>/passwort', kontenapi.passwort)
    ..post(
      '/api/v1/konten/<id>/totp-zuruecksetzen',
      kontenapi.totpZuruecksetzen,
    )
    ..post('/api/v1/konten/<id>/entsperren', kontenapi.entsperren)
    ..delete('/api/v1/konten/<id>', kontenapi.entfernen)
    ..post('/api/v1/anmelden', anmeldung.anmelden)
    ..get(
      '/app',
      (Request _) => oberflaeche == null
          ? Response.notFound('nicht da')
          : Response.found('/app/', headers: {'cache-control': 'no-store'}),
    )
    ..get(
      '/app/',
      (Request r) => oberflaeche?.seite(r) ?? Response.notFound('nicht da'),
    )
    ..get(
      '/app/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name) ?? Response.notFound('nicht da'),
    )
    ..get(
      '/app/leaflet/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name, ordnerName: 'leaflet') ??
          Response.notFound('nicht da'),
    )
    ..get(
      '/app/leaflet/images/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name, ordnerName: 'leaflet/images') ??
          Response.notFound('nicht da'),
    )
    ..post(
      '/api/v1/web/anmelden',
      (Request r) => oberflaeche?.anmelden(r) ?? Response.notFound('nicht da'),
    )
    ..post(
      '/api/v1/web/anmelden/totp',
      (Request r) => oberflaeche?.totp(r) ?? Response.notFound('nicht da'),
    )
    ..post(
      '/api/v1/web/abmelden',
      (Request r) => oberflaeche?.abmelden(r) ?? Response.notFound('nicht da'),
    )
    ..get(
      '/api/v1/web/sitzung',
      (Request r) => oberflaeche?.sitzung(r) ?? Response.notFound('nicht da'),
    )
    ..post('/api/v1/anmelden/totp', anmeldung.totp)
    ..get('/api/v1/anmelden/oidc', anmeldung.oidcStart)
    ..get('/api/v1/anmelden/oidc/zurueck', anmeldung.oidcZurueck)
    ..post('/api/v1/anmelden/oidc/einloesen', anmeldung.oidcEinloesen)
    ..post('/api/v1/abmelden', anmeldung.abmelden)
    ..get('/api/v1/konto', anmeldung.konto)
    ..post('/api/v1/konto/passwort', anmeldung.passwort)
    ..post('/api/v1/konto/wiederherstellungscodes', anmeldung.codes)
    ..post('/api/v1/konto/oidc', anmeldung.oidcVerknuepfen)
    ..get('/api/v1/geraete', anmeldung.geraete)
    ..delete('/api/v1/geraete/<id>', anmeldung.geraetAbmelden)
    ..get('/api/v1/bibliothek', api.bibliothek)
    ..get('/api/v1/aufnahmen', api.aufnahmen)
    ..get('/api/v1/aufnahmen/<id>', api.aufnahme)
    ..get('/api/v1/aufnahmen/<id>/<art>', api.datei)
    ..post('/api/v1/pruefsummen', api.pruefsummen)
    ..post('/api/v1/befehle', abgleich.befehle)
    ..get('/api/v1/abgleich/stand', abgleich.stand)
    ..get('/api/v1/abgleich/aenderungen', abgleich.aenderungen)
    ..post('/api/v1/abgleich/zeilen', abgleich.zeilen)
    ..get('/api/v1/abgleich/abzug', abgleich.abzug)
    ..get('/api/v1/dateien/<pfad|.+>', abgleich.datei)
    ..put(
      '/api/v1/dateien/<pfad|.+>',
      wennPlatz((Request r) => abgleich.dateiAblegen(r, r.params['pfad']!)),
    )
    ..post('/api/v1/suche/text', suche.text)
    ..get('/api/v1/suche', suche.suche)
    ..get('/api/v1/reisen', api.reisen)
    ..get('/api/v1/reisen/<id>', api.reiseAufnahmen)
    ..get('/api/v1/orte', api.orte)
    ..post('/api/v1/aufnahmen/liste', api.liste)
    ..get('/api/v1/erinnerungen', api.erinnerungen)
    ..get('/api/v1/papierkorb', api.papierkorb)
    ..get('/api/v1/alben', api.alben)
    ..get('/api/v1/alben/<id>', api.album)
    ..get('/api/v1/personen', api.personen)
    ..get('/api/v1/personen/<id>', api.person)
    ..post('/api/v1/rechnen/auftraege', rechnen.auftraege)
    ..post('/api/v1/rechnen/ergebnis', rechnen.ergebnis)
    ..post('/api/v1/rechnen/zurueck', rechnen.zurueck)
    ..post('/api/v1/umzug/beginnen', umzug.beginnen)
    ..get('/api/v1/umzug/stand', umzug.stand)
    ..post('/api/v1/umzug/abschliessen', umzug.abschliessen)
    ..add(
      'OPTIONS',
      '/api/v1/umzug/hochladen',
      (Request r) => umzug.hochladen(r).optionen(r),
    )
    ..post(
      '/api/v1/umzug/hochladen',
      wennPlatz((Request r) => umzug.hochladen(r).anlegen(r)),
    )
    ..head(
      '/api/v1/umzug/hochladen/<id>',
      (Request r, String id) => umzug.hochladen(r).stand(r, id),
    )
    ..patch(
      '/api/v1/umzug/hochladen/<id>',
      (Request r, String id) => speicher?.voll ?? false
          ? _speicherVoll()
          : umzug.hochladen(r).anhaengen(r, id),
    )
    ..delete(
      '/api/v1/umzug/hochladen/<id>',
      (Request r, String id) => umzug.hochladen(r).verwerfen(r, id),
    )
    ..get(
      '/api/v1/speicher',
      (Request _) => _json(speicher?.alsJson() ?? const {'stufe': 'unbekannt'}),
    )
    ..get(
      '/api/v1/sicherung',
      (Request r) => _nurVerwalter(r, () async {
        return _json(
          sicherung == null ? const {'stufe': 'aus'} : await sicherung.stand(),
        );
      }),
    )
    ..post(
      '/api/v1/sicherung/einrichten',
      (Request r) => _nurVerwalter(r, () async {
        final s = sicherung;
        if (s == null) {
          return _json({
            'fehler': 'Kein Sicherungsziel eingestellt.',
          }, status: 409);
        }
        final k = jsonDecode(await r.readAsString());
        final pp = k is Map ? k['passphrase'] : null;
        if (pp is! String) {
          return _json({'fehler': 'passphrase fehlt'}, status: 400);
        }
        try {
          await s.einrichten(pp);
        } on ArgumentError catch (f) {
          return _json({'fehler': '${f.message}'}, status: 400);
        } on StateError catch (f) {
          return _json({'fehler': f.message}, status: 409);
        } on FileSystemException catch (f) {
          return _json({
            'fehler': 'Das Sicherungsziel ist nicht beschreibbar: ${f.message}',
          }, status: 409);
        }
        unawaited(s.jetzt());
        return _json(await s.stand());
      }),
    )
    ..post(
      '/api/v1/sicherung/ziel',
      (Request r) => _nurVerwalter(r, () async {
        final s = sicherung;
        if (s == null || !s.eingerichtet) {
          return _json({
            'fehler': 'Die Sicherung ist nicht eingerichtet.',
          }, status: 409);
        }
        try {
          await s.zielNeu();
        } on FileSystemException catch (f) {
          return _json({
            'fehler': 'Ziel nicht beschreibbar: ${f.message}',
          }, status: 409);
        }
        return _json(await s.stand());
      }),
    )
    ..post(
      '/api/v1/sicherung/jetzt',
      (Request r) => _nurVerwalter(r, () async {
        final s = sicherung;
        if (s == null || !s.eingerichtet) {
          return _json({
            'fehler': 'Die Sicherung ist nicht eingerichtet.',
          }, status: 409);
        }
        unawaited(s.jetzt());
        return _json(await s.stand(), status: 202);
      }),
    )
    ..get('/api/v1/auswertung', api.auswertung)
    ..post('/api/v1/auswertung', api.auswertungAnstossen)
    ..add(
      'OPTIONS',
      '/api/v1/hochladen',
      (Request r) async => (await bereich(r)).hochladen.optionen(r),
    )
    ..post(
      '/api/v1/hochladen',
      wennPlatz((Request r) async => (await bereich(r)).hochladen.anlegen(r)),
    )
    ..head(
      '/api/v1/hochladen/<id>',
      (Request r, String id) async => (await bereich(r)).hochladen.stand(r, id),
    )
    ..get(
      '/api/v1/hochladen/<id>',
      (Request r, String id) async =>
          (await bereich(r)).hochladen.status(r, id),
    )
    ..patch(
      '/api/v1/hochladen/<id>',
      (Request r, String id) async => speicher?.voll ?? false
          ? _speicherVoll()
          : (await bereich(r)).hochladen.anhaengen(r, id),
    )
    ..delete(
      '/api/v1/hochladen/<id>',
      (Request r, String id) async =>
          (await bereich(r)).hochladen.verwerfen(r, id),
    );
  return const Pipeline()
      .addMiddleware(_sicherheitskoepfe)
      .addMiddleware(
        anmeldungNoetig(
          konten,
          von,
          offen: {
            '',
            'api/v1/zustand',
            'api/v1/einrichten',
            'api/v1/anmelden',
            'api/v1/anmelden/totp',
            'api/v1/anmelden/oidc',
            'api/v1/anmelden/oidc/zurueck',
            'api/v1/anmelden/oidc/einloesen',
            'api/v1/web/anmelden',
            'api/v1/web/anmelden/totp',
            'app',
          },
          offenPraefixe: {'app/'},
        ),
      )
      .addHandler(r.call);
}

/// Was jede Antwort trägt: Der Browser soll nichts erraten, keine Adresse
/// weitergeben (die Rückwege der Anmeldung tragen Codes), nichts in eine
/// fremde Seite einbetten und nichts ausführen, was als Datei kommt – eine
/// JSON-Antwort oder ein Bild, direkt geöffnet, ist eine Seite ohne jedes
/// Recht. Die Oberfläche bringt ihre eigene, weitere Regel mit.
Middleware get _sicherheitskoepfe =>
    (innerer) => (anfrage) async {
      final antwort = await innerer(anfrage);
      final k = antwort.headers;
      final typ = k['content-type'] ?? '';
      return antwort.change(
        headers: {
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'no-referrer',
          'x-frame-options': 'DENY',
          'cross-origin-opener-policy': 'same-origin',
          'cross-origin-resource-policy': 'same-origin',
          if (!k.containsKey('content-security-policy'))
            'content-security-policy':
                "default-src 'none'; frame-ancestors 'none'; sandbox",
          if (!k.containsKey('cache-control') &&
              typ.startsWith('application/json'))
            'cache-control': 'no-store',
        },
      );
    };

/// Nur für Verwalter; sonst 403.
Future<Response> _nurVerwalter(
  Request r,
  Future<Response> Function() erlaubt,
) async => kontoVon(r).verwalter
    ? erlaubt()
    : _json({'fehler': 'Nur für Verwalter.'}, status: 403);

/// 507 Insufficient Storage – der Client bricht ab, statt es weiter zu
/// versuchen.
Response _speicherVoll() =>
    _json({'fehler': 'Der Speicher des Servers ist voll.'}, status: 507);

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Api {
  _Api(this.bibliotheken, this._beschleuniger);

  final Bibliotheken bibliotheken;
  final Future<Map<String, Object?>> Function()? _beschleuniger;

  Future<Kontobereich> _bereich(Request r) => bibliotheken.fuer(kontoVon(r).id);

  /// Lebenszeichen, ohne Anmeldung – für Docker, den Reverse Proxy und
  /// Clients, die wissen wollen, wie sie sich anmelden.
  /// Mit [einrichten], wenn es noch kein Konto gibt und die Anfrage aus
  /// dem Heimnetz kommt: Dann bietet die App an, das erste anzulegen.
  Response zustand(Kontodienst konten, Oidc? oidc, {bool einrichten = false}) =>
      _json({
        'dienst': 'photo-vault',
        'protokoll': protokollFassung,
        'fassung': serverFassung,
        if (serverCommit.isNotEmpty) 'commit': serverCommit,
        'anmeldung': {'totp': konten.totpPflicht, 'oidc': oidc != null},
        if (einrichten) 'einrichten': true,
      });

  Future<Response> bibliothek(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final anzahl = await db
        .customSelect(
          'SELECT count(*) AS n FROM assets WHERE $rasterSichtbar',
          readsFrom: {db.assets},
        )
        .getSingle();
    return _json({
      'schema': db.schemaVersion,
      'protokoll': protokollFassung,
      'aufnahmen': anzahl.read<int>('n'),
    });
  }

  /// Was die Auswertung gerade tut: `laeuft` und, wenn ja, die Stufe mit
  /// ihrem Fortschritt; dazu der Beschleuniger und seine Gegenproben.
  Future<Response> auswertung(Request anfrage) async {
    final d = (await _bereich(anfrage)).auswertung;
    return _json({
      'laeuft': d.laeuft,
      'stand': d.stand?.alsJson(),
      'beschleuniger': ?await _beschleuniger?.call(),
    });
  }

  /// Stösst einen Durchgang an, ohne die Ruhezeit abzuwarten. Antwortet
  /// sofort; der Durchgang läuft im Hintergrund.
  Future<Response> auswertungAnstossen(Request anfrage) async {
    unawaited((await _bereich(anfrage)).auswertung.jetzt());
    return _json({'laeuft': true}, status: 202);
  }

  /// Die Zeitleiste seitenweise, neueste zuerst.
  ///
  /// Weiterblättern über `nach` – den Wert `weiter` der vorigen Seite –
  /// statt über eine Seitenzahl: Kommt oben etwas dazu, verrutscht eine
  /// Seitenzahl, ein Lesezeichen auf die letzte Zeile nicht. Und die
  /// Abfrage bleibt in jeder Tiefe der Bibliothek gleich schnell.
  Future<Response> aufnahmen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final q = anfrage.url.queryParameters;
    final anzahl = (int.tryParse(q['anzahl'] ?? '') ?? 300).clamp(1, 1000);
    final nach = _Lesezeichen.lies(q['nach']);
    final zeilen = await db
        .customSelect(
          'SELECT $rasterSpalten FROM assets WHERE $rasterSichtbar'
          '${nach == null ? '' : ' AND (file_created_at < ? OR (file_created_at = ? AND id < ?))'}'
          ' ORDER BY file_created_at DESC, id DESC LIMIT ?',
          variables: [
            if (nach != null) ...[
              Variable<DateTime>(nach.zeit),
              Variable<DateTime>(nach.zeit),
              Variable<String>(nach.id),
            ],
            Variable<int>(anzahl),
          ],
          readsFrom: {db.assets},
        )
        .get();
    final liste = [for (final z in zeilen) Rasterzeile.ausZeile(z)];
    return _json({
      'aufnahmen': [for (final r in liste) zeileAlsJson(r)],
      'weiter': liste.length < anzahl
          ? null
          : _Lesezeichen(liste.last.fileCreatedAt, liste.last.id).text,
    });
  }

  /// Die Reisen mit Zeitraum, Anzahl und Titelbild – für den Browser.
  Future<Response> reisen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final liste = await (db.select(
      db.reisen,
    )..orderBy([(t) => OrderingTerm.desc(t.von)])).get();
    final anzahlen = await db.reiseAnzahlen();
    return _json({
      'reisen': [
        for (final r in liste)
          {
            'id': r.id,
            'name': r.name,
            'von': r.von.toIso8601String(),
            'bis': r.bis.toIso8601String(),
            'art': r.art,
            'anzahl': anzahlen[r.id] ?? 0,
            'titelbild': (await db.ersteAufnahmeDerReise(r.id))?.id,
          },
      ],
    });
  }

  Future<Response> reiseAufnahmen(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final r = await db.reise(id);
    if (r == null) return _json({'fehler': 'unbekannt'}, status: 404);
    return _json({
      'reise': {
        'id': r.id,
        'name': r.name,
        'von': r.von.toIso8601String(),
        'bis': r.bis.toIso8601String(),
        'notiz': r.notiz,
      },
      'aufnahmen': [
        for (final a in await db.aufnahmenDerReise(id))
          zeileAlsJson(Rasterzeile.aus(a)),
      ],
    });
  }

  /// Die Aufnahmen mit Ort als Punkte für die Karte im Browser, bei
  /// `?zoom=` zusammengefasst wie auf dem Telefon (siehe [kartengruppen]).
  Future<Response> orte(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final zoom =
        (double.tryParse(anfrage.url.queryParameters['zoom'] ?? '') ?? 4)
            .clamp(0, 20)
            .toDouble();
    final orte = [
      for (final a in await db.assetsWithLocation()) Rasterzeile.aus(a),
    ];
    return _json({
      'gruppen': [
        for (final g in kartengruppen(orte, zoom))
          {
            'breite': gruppenmitte(g).breite,
            'laenge': gruppenmitte(g).laenge,
            'anzahl': g.length,
            'ids': [for (final z in g) z.id],
          },
      ],
    });
  }

  /// `{ids}` → die Zeilen dazu, in dieser Reihenfolge – für eine Gruppe
  /// der Karte und alles, was Kennungen hat, aber keine Zeilen.
  Future<Response> liste(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final Object? k;
    try {
      k = jsonDecode(await anfrage.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    final ids = k is Map ? k['ids'] : null;
    if (ids is! List || ids.length > 5000) {
      return _json({'fehler': 'ids fehlen oder zu viele'}, status: 400);
    }
    final zeilen = await db.assetsByIds(ids.cast<String>());
    return _json({
      'aufnahmen': [
        for (final a in zeilen)
          if (!a.isTrashed && !a.isLocked) zeileAlsJson(Rasterzeile.aus(a)),
      ],
    });
  }

  /// „Vor x Jahren“ für den Browser – dieselbe Wahl wie am Rechner und auf
  /// dem Telefon (siehe `waehleRueckblick`).
  Future<Response> erinnerungen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final heute = DateTime.now();
    final amTag = await db.assetsOnThisDay(heute);
    final imMonat = amTag.isEmpty
        ? await db.assetsInDiesemMonat(heute)
        : const <AssetData>[];
    final r = waehleRueckblick(
      amTag: amTag,
      imMonat: imMonat,
      wann: (a) => a.fileCreatedAt.toLocal(),
      heute: heute,
    );
    return _json({
      'art': r.art.name,
      'monat': heute.month,
      'gruppen': [
        for (final g in r.gruppen)
          {
            'jahreHer': g.jahreHer,
            'aufnahmen': [
              for (final a in g.dinge) zeileAlsJson(Rasterzeile.aus(a)),
            ],
          },
      ],
    });
  }

  /// Der Papierkorb – zurückholen geht über den Befehl `ausDemPapierkorb`.
  Future<Response> papierkorb(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    return _json({
      'aufnahmen': [
        for (final a in await db.papierkorb()) zeileAlsJson(Rasterzeile.aus(a)),
      ],
    });
  }

  /// Die Alben mit Anzahl und Titelbild – für den Browser.
  Future<Response> alben(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final liste = await db.alleAlben();
    final anzahlen = await db.albumAnzahlen();
    return _json({
      'alben': [
        for (final a in liste)
          {
            'id': a.id,
            'name': a.name,
            'anzahl': anzahlen[a.id] ?? 0,
            'titelbild': (await db.albumTitelbild(a))?.id,
          },
      ],
    });
  }

  Future<Response> album(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final a = (await db.alleAlben()).where((x) => x.id == id).firstOrNull;
    if (a == null) return _json({'fehler': 'unbekannt'}, status: 404);
    return _json({
      'album': {'id': a.id, 'name': a.name},
      'aufnahmen': [
        for (final x in await db.albumAufnahmen(id))
          zeileAlsJson(Rasterzeile.aus(x)),
      ],
    });
  }

  /// Die Personen mit Anzahl und Gesichtsausschnitt (ein Pfad für
  /// `/api/v1/dateien/…`), die mit den meisten Aufnahmen zuerst.
  Future<Response> personen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final liste = await db.select(db.people).get();
    final anzahlen = await db.personenAnzahlen();
    final sortiert = [...liste]
      ..sort((a, b) => (anzahlen[b.id] ?? 0).compareTo(anzahlen[a.id] ?? 0));
    return _json({
      'personen': [
        for (final p in sortiert)
          {
            'id': p.id,
            'name': p.name,
            'anzahl': anzahlen[p.id] ?? 0,
            'bild': p.coverFaceCropPath,
          },
      ],
    });
  }

  Future<Response> person(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final p = await (db.select(
      db.people,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (p == null) return _json({'fehler': 'unbekannt'}, status: 404);
    return _json({
      'person': {'id': p.id, 'name': p.name},
      'aufnahmen': [
        for (final x in await db.assetsFuerPersonen([id]))
          zeileAlsJson(Rasterzeile.aus(x)),
      ],
    });
  }

  Future<Response> aufnahme(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final a = await db.assetById(id);
    if (a == null || a.isLocked) {
      return _json({'fehler': 'unbekannt'}, status: 404);
    }
    return _json(a.toJson());
  }

  /// Welche Dateien schon in der Bibliothek liegen: `{pruefsummen: [...]}`
  /// (SHA-256, hexadezimal) → `{vorhanden: {pruefsumme: kennung}}`.
  ///
  /// Für die Sicherung der Kamerarolle: Was schon da ist – etwa weil die
  /// Bibliothek vom Rechner umgezogen ist –, muss das Telefon nicht erst
  /// hochladen, damit der Server es als Dublette verwirft. Zählt auch,
  /// was im Papierkorb liegt; der Import nähme es ebenfalls nicht noch
  /// einmal.
  Future<Response> pruefsummen(Request anfrage) async {
    final k = jsonDecode(await anfrage.readAsString());
    final liste = k is Map ? k['pruefsummen'] : null;
    if (liste is! List || liste.length > 1000) {
      return _json({'fehler': 'pruefsummen fehlt oder zu viele'}, status: 400);
    }
    final summen = {
      for (final s in liste)
        if (s is String && _pruefsummeMuster.hasMatch(s)) s,
    }.toList();
    final db = (await _bereich(anfrage)).bibliothek.db;
    final vorhanden = <String, String>{};
    if (summen.isNotEmpty) {
      final zeilen =
          await (db.selectOnly(db.assets)
                ..addColumns([db.assets.checksum, db.assets.id])
                ..where(db.assets.checksum.isIn(summen)))
              .get();
      for (final z in zeilen) {
        vorhanden[z.read(db.assets.checksum)!] = z.read(db.assets.id)!;
      }
    }
    return _json({'vorhanden': vorhanden});
  }

  static final _pruefsummeMuster = RegExp(r'^[0-9a-f]{64}$');

  /// `miniatur`, `vorschau` oder `original` – mit Teilabruf (`Range`),
  /// damit sich ein Video abspielen lässt, ohne es ganz zu laden.
  Future<Response> datei(Request anfrage, String id, String art) async {
    final b = (await _bereich(anfrage)).bibliothek;
    final a = await b.db.assetById(id);
    if (a == null || a.isLocked) return Response.notFound(null);
    final relativ = switch (art) {
      'miniatur' => a.thumbnailRelativePath,
      'vorschau' =>
        a.previewRelativePath ??
            (a.type == 'IMAGE' ? a.relativePath : a.thumbnailRelativePath),
      'original' => a.relativePath,
      _ => null,
    };
    if (relativ == null) return Response.notFound(null);
    final datei = b.pfade.absolute(relativ);
    // Die Pfade stammen aus der eigenen Datenbank. Geprüft wird trotzdem:
    // Was ausgeliefert wird, liegt in der Bibliothek, nirgends sonst.
    if (!p.isWithin(b.pfade.root.path, datei.path) || !await datei.exists()) {
      return Response.notFound(null);
    }
    return dateiAntwort(anfrage, datei);
  }
}

/// Wo eine Seite der Zeitleiste endet: Zeitpunkt und Kennung der letzten
/// Aufnahme, als Text für die Adresse.
class _Lesezeichen {
  const _Lesezeichen(this.zeit, this.id);

  final DateTime zeit;
  final String id;

  String get text => '${zeit.millisecondsSinceEpoch}~$id';

  static _Lesezeichen? lies(String? text) {
    if (text == null) return null;
    final i = text.indexOf('~');
    if (i < 0) return null;
    final ms = int.tryParse(text.substring(0, i));
    if (ms == null) return null;
    return _Lesezeichen(
      DateTime.fromMillisecondsSinceEpoch(ms),
      text.substring(i + 1),
    );
  }
}
