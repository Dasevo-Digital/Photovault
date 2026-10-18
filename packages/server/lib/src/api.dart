import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/asset_display_path.dart';
import 'package:kern/services/aufnahmeangaben.dart';
import 'package:kern/services/bibliothekseinstellungen.dart';
import 'package:kern/services/cube_lut.dart';
import 'package:kern/services/develop_color.dart';
import 'package:kern/services/duplikatsuche.dart';
import 'package:kern/services/embedding_similarity.dart';
import 'package:kern/services/geometrie.dart' as g;
import 'package:kern/services/kartengruppen.dart';
import 'package:kern/services/laendernamen.dart';
import 'package:kern/services/lebensbaumansicht.dart';
import 'package:kern/services/lebensbaum_bild.dart';
import 'package:kern/services/reiseuebersicht.dart';
import 'package:kern/services/verwandtschaftsgrad.dart';
import 'package:kern/services/rueckblick.dart';
import 'package:kern/services/stammbaum.dart';
import 'package:kern/services/stammbaumansicht.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'abgleich_api.dart';
import 'absender.dart';
import 'anmeldung_api.dart';
import 'bibliothek.dart';
import 'bibliotheken.dart';
import 'dateiantwort.dart';
import 'fassung.dart';
import 'konten/kontodienst.dart';
import 'konten_api.dart';
import 'oidc.dart';
import 'packen.dart';
import 'rechnen.dart';
import 'sicherung.dart';
import 'speicher.dart';
import 'suche_api.dart';
import 'umzug.dart';
import 'videofassung.dart';
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
    ..get(
      '/app/lebensbaum/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name, ordnerName: 'lebensbaum') ??
          Response.notFound('nicht da'),
    )
    ..get(
      '/app/schrift/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name, ordnerName: 'schrift') ??
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
    ..get('/api/v1/aufnahmen/<id>/angaben', api.angaben)
    ..get('/api/v1/aufnahmen/<id>/<art>', api.datei)
    ..get('/api/v1/serien/<id>', api.serie)
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
    ..get('/api/v1/aktivitaeten/<id>', api.aktivitaet)
    ..get('/api/v1/orte', api.orte)
    ..get('/api/v1/statistik', api.statistik)
    ..get('/api/v1/einstellungen', api.einstellungen)
    ..get('/api/v1/entwickeln/<id>', api.entwickeln)
    ..get('/api/v1/stammbaum', api.stammbaum)
    ..get('/api/v1/lebensbaum', api.lebensbaum)
    ..get('/api/v1/duplikate', api.duplikate)
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
      .addMiddleware(packen)
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

  /// Für Browser, die ein Video nicht abspielen können.
  final videofassungen = Videofassungen();
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
  ///
  /// Mit `favoriten=1` nur die Favoriten – für die Bibliothek der
  /// Weboberfläche, wie auf dem Telefon.
  Future<Response> aufnahmen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final q = anfrage.url.queryParameters;
    final anzahl = (int.tryParse(q['anzahl'] ?? '') ?? 300).clamp(1, 1000);
    final nach = _Lesezeichen.lies(q['nach']);
    final nurFavoriten = q['favoriten'] == '1';
    final zeilen = await db
        .customSelect(
          'SELECT $rasterSpalten FROM assets WHERE $rasterSichtbar'
          '${nurFavoriten ? ' AND is_favorite = 1' : ''}'
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
  /// Reisen und Aktivitäten für die Seite „Reisen“ im Browser – dieselbe
  /// Rechnung wie auf dem Telefon (siehe reiseuebersicht.dart im Kern).
  /// `sprache` bestimmt die Ländernamen.
  Future<Response> reisen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final sprache = _sprache(anfrage);
    return _json({
      'reisen': [for (final k in await reisekarten(db)) _reiseJson(k, sprache)],
      'aktivitaeten': [
        for (final k in await aktivitaetskarten(db))
          _aktivitaetJson(k, sprache),
      ],
    });
  }

  Future<Response> reiseAufnahmen(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final r = await db.reise(id);
    if (r == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final sprache = _sprache(anfrage);
    final aufnahmen = await db.aufnahmenDerReise(id);
    return _json({
      'reise': {
        'id': r.id,
        'name': r.name,
        'von': r.von.toIso8601String(),
        'bis': r.bis.toIso8601String(),
        'notiz': r.notiz,
        'art': r.art,
        'anzahl': aufnahmen.length,
      },
      'aktivitaeten': [
        for (final k in await aktivitaetskarten(db, reiseId: id))
          _aktivitaetJson(k, sprache),
      ],
      'aufnahmen': [
        for (final a in aufnahmen) zeileAlsJson(Rasterzeile.aus(a)),
      ],
    });
  }

  /// Eine Aktivität: Angaben, Route aus den verorteten Aufnahmen, Strecke
  /// darauf und die Aufnahmen selbst.
  Future<Response> aktivitaet(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final a = await aktivitaetsansicht(db, id);
    if (a == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final k = a.aktivitaet;
    final reise = a.reise;
    return _json({
      'aktivitaet': {
        'id': k.id,
        'name': k.name,
        'art': k.art,
        'von': k.von.toIso8601String(),
        'bis': k.bis.toIso8601String(),
        'notiz': k.notiz,
        'reise': reise == null ? null : {'id': reise.id, 'name': reise.name},
        'anzahl': a.aufnahmen.length,
        'streckeKm': a.streckeKm,
        'ort': _ortJson(a.ort, _sprache(anfrage)),
      },
      'route': [
        for (final p in a.route)
          {
            'id': p.id,
            'breite': p.breite,
            'laenge': p.laenge,
            'zeit': p.zeit.toIso8601String(),
          },
      ],
      'aufnahmen': [
        for (final x in a.aufnahmen) zeileAlsJson(Rasterzeile.aus(x)),
      ],
    });
  }

  String _sprache(Request anfrage) =>
      anfrage.url.queryParameters['sprache'] == 'en' ? 'en' : 'de';

  /// Der Ort als Zeile ohne den Zusatz „weitere Orte“ – den setzt der
  /// Browser in seiner Sprache, er bekommt nur die Zahl.
  Map<String, Object?>? _ortJson(Ortsbezug? b, String sprache) {
    if (b == null) return null;
    final text = ortszeileText(
      (
        ort: b.ort,
        region: b.region,
        land: b.land,
        weitereOrte: 0,
        aufnahmen: b.aufnahmen,
      ),
      sprache,
      (_) => '',
    );
    return text == null ? null : {'text': text, 'weitere': b.weitereOrte};
  }

  Map<String, Object?> _reiseJson(Reisekarte k, String sprache) => {
    'id': k.reise.id,
    'name': k.reise.name,
    'von': k.reise.von.toIso8601String(),
    'bis': k.reise.bis.toIso8601String(),
    'art': k.reise.art,
    'anzahl': k.anzahl,
    'titelbild': k.titelbild?.id,
    'ort': _ortJson(k.ort, sprache),
  };

  Map<String, Object?> _aktivitaetJson(Aktivitaetskarte k, String sprache) => {
    'id': k.aktivitaet.id,
    'name': k.aktivitaet.name,
    'art': k.aktivitaet.art,
    'von': k.aktivitaet.von.toIso8601String(),
    'bis': k.aktivitaet.bis.toIso8601String(),
    'reiseId': k.aktivitaet.reiseId,
    'reisename': k.reisename,
    'anzahl': k.anzahl,
    'titelbild': k.titelbild?.id,
    'ort': _ortJson(k.ort, sprache),
  };

  /// Die Aufnahmen mit Ort als Punkte für die Karte im Browser, bei
  /// `?zoom=` zusammengefasst wie auf dem Telefon (siehe [kartengruppen]).
  /// Die Kennzahlen der Analyseseite des Rechners (LibraryStats) in Zahlen,
  /// damit der Browser dieselbe Statistik zeigt: Anzahl, Speicher, Aufnahmen
  /// je Jahr und Monat, häufigste Kameras.
  Future<Response> statistik(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final s = await db.loadLibraryStats();
    return _json({
      'insgesamt': s.totalCount,
      'fotos': s.imageCount,
      'videos': s.videoCount,
      'favoriten': s.favoriteCount,
      'papierkorb': s.trashedCount,
      'gesperrt': s.lockedCount,
      'bytes': s.totalSizeBytes,
      'proJahr': {for (final e in s.countsByYear.entries) '${e.key}': e.value},
      'proMonat': {
        for (final e in s.countsByMonth.entries) '${e.key}': e.value,
      },
      'kameras': [
        for (final k in s.topCameras) {'name': k.label, 'anzahl': k.count},
      ],
    });
  }

  /// Duplikatgruppen wie auf dem Rechner: dieselbe Suche
  /// ([findDuplicateGroups]) auf den Bildeinbettungen der Bibliothek, in
  /// einem eigenen Isolate, und je Gruppe das Foto, das die Regeln aus
  /// duplicate_selection.dart behalten würden.
  Future<Response> duplikate(Request anfrage) async {
    final schwelle =
        double.tryParse(anfrage.url.queryParameters['schwelle'] ?? '') ?? 0.92;
    if (schwelle < 0.5 || schwelle > 1) {
      return _json({'fehler': 'schwelle'}, status: 400);
    }
    final db = (await _bereich(anfrage)).bibliothek.db;
    final d = await sucheDuplikate(db, schwelle);
    return _json({
      'einbettungen': d.einbettungen,
      'ausnahmen': d.ausnahmen,
      'schwelle': d.schwelle,
      'gruppen': [
        for (final g in d.gruppen)
          {
            'aufnahmen': [
              for (final a in g.aufnahmen) zeileAlsJson(Rasterzeile.aus(a)),
            ],
            'behalten': g.behalten.id,
            'loeschbar': [for (final a in g.loeschbar) a.id],
          },
      ],
    });
  }

  /// Alles, was die Info-Ansicht des Rechners zu einer Aufnahme zeigt:
  /// Datei, Kamera, Ort, Personen, Schlagwörter, Alben, Beschreibung, Serie.
  /// Die Rasterzeile liegt darunter, damit der Browser dieselben Schlüssel
  /// wie in den Listen sieht; `ort` und `kamera` werden hier ausführlicher.
  Future<Response> angaben(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final angaben = await aufnahmeangaben(db, id);
    if (angaben == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final a = angaben.aufnahme;
    return _json({
      ...zeileAlsJson(Rasterzeile.aus(a)),
      'importiert': a.importedAt.toIso8601String(),
      'bytes': a.fileSizeBytes,
      'format': a.dateiformat,
      'beschreibung': a.description,
      // In der Sprache der Oberfläche, wie auf dem Telefon.
      'kiBeschreibung': _sprache(anfrage) == 'de'
          ? (a.aiCaptionDe ?? a.aiCaption)
          : a.aiCaption,
      'text': a.ocrText,
      'transkript': a.transkript,
      'datumGeschaetzt': a.datumGeschaetzt,
      'bearbeitet': angaben.bearbeitet,
      'kamera': {
        'hersteller': a.cameraMake,
        'modell': a.cameraModel,
        'objektiv': a.lensModel,
        'brennweite': a.focalLengthMm,
        'brennweite35': a.focalLength35mm,
        'blende': a.fNumber,
        'iso': a.iso,
        'belichtung': a.exposureTimeSeconds,
        'korrektur': a.exposureBiasEv,
      },
      if (a.latitude != null && a.longitude != null)
        'ort': {
          'breite': a.latitude,
          'laenge': a.longitude,
          'land': landAnzeige(a.locationCountry, _sprache(anfrage)),
          'region': a.locationState,
          'stadt': a.locationCity,
          'geerbt': a.ortGeerbt,
        },
      'personen': [
        for (final p in angaben.personen) {'id': p.id, 'name': p.name},
      ],
      'schlagwoerter': [
        for (final t in angaben.schlagwoerter) {'id': t.id, 'name': t.name},
      ],
      'alben': [
        for (final b in angaben.alben) {'id': b.id, 'name': b.name},
      ],
    });
  }

  /// Die Aufnahmen einer Serie (eines Stapels), Titelbild zuerst – im
  /// Raster steht nur das Titelbild, der Rest öffnet sich hierüber.
  Future<Response> serie(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final sichtbar = await serieZumAnsehen(db, id);
    if (sichtbar.isEmpty) return _json({'fehler': 'unbekannt'}, status: 404);
    return _json({
      'aufnahmen': [for (final a in sichtbar) zeileAlsJson(Rasterzeile.aus(a))],
    });
  }

  /// Der Stammbaum um eine Person, wie der Rechner ihn zeigt: dasselbe
  /// Geflecht aus dem Kern ([geflechtUm]) – Haushalte je Generationsband
  /// und die Elternhäuser jeder Person. Gezeichnet wird im Browser.
  ///
  /// Ohne `fokus` die zuletzt am Rechner gewählte Person, sonst die erste
  /// mit Verwandtschaft; alle Personen kommen für die Auswahl mit.
  Future<Response> stammbaum(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final s = await stammbaumansicht(
      db,
      fokus: anfrage.url.queryParameters['fokus'],
    );
    final g = s.geflecht;
    if (g == null) {
      return _json({'fokus': null, 'personen': [], 'haushalte': []});
    }
    return _json({
      'fokus': s.fokus,
      'personen': [
        for (final p in s.personen)
          {
            'id': p.id,
            'name': p.name,
            'geburt': p.geburtsdatum?.toIso8601String(),
            'tod': p.sterbedatum?.toIso8601String(),
            'bild': p.coverFaceCropPath,
            'geschlecht': p.geschlecht,
            'verwandt': s.verwandt.contains(p.id),
          },
      ],
      'haushalte': [
        for (final h in g.haushalte)
          {'id': h.id, 'personen': h.personen, 'band': g.band[h.id]},
      ],
      'elternhaeuser': g.elternhaeuserVon,
      'weitereOben': [
        for (final e in g.weitereOben.entries)
          if (e.value) e.key,
      ],
      'weitereUnten': [
        for (final e in g.weitereUnten.entries)
          if (e.value) e.key,
      ],
      'verschwiegen': g.verschwiegen,
      // Die Plätze, wie der Rechner sie rechnet (siehe stammbaumansicht).
      if (s.plan case final plan?)
        'plan': {
          'breite': plan.breite,
          'hoehe': plan.hoehe,
          'schilder': [
            for (final x in plan.schilder)
              {'id': x.personId, 'x': x.links, 'y': x.oben},
          ],
          'aeste': [
            for (final a in plan.aeste)
              {
                'id': a.personId,
                'x1': a.vonX,
                'y1': a.vonY,
                'x2': a.nachX,
                'y2': a.nachY,
              },
          ],
          'paare': [
            for (final b in plan.baender)
              {'x1': b.vonX, 'x2': b.nachX, 'y': b.y},
          ],
        },
    });
  }

  /// Die Einstellungen, die in der Bibliothek stehen und damit für jedes
  /// verbundene Gerät gelten – geändert wird über die Befehle.
  Future<Response> einstellungen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final e = await bibliothekseinstellungen(db);
    return _json({
      'papierkorbLeeren': e.papierkorbLeeren,
      'papierkorbTage': e.papierkorbTage,
      'gesichtsschwelle': e.gesichtsschwelle,
      'vorschlaegeAb': e.vorschlaegeAb,
      'auswertenNachImport': e.auswertenNachImport,
      'sucheUebersetzen': e.sucheUebersetzen,
      'angabenSchuetzen': e.angabenSchuetzen,
    });
  }

  /// Was der Browser zum Entwickeln braucht: die gespeicherten Regler –
  /// unter den Spaltennamen, die `entwicklungSpeichern` erwartet –, aus
  /// welcher Datei er rechnet, und Tonkurve und Farbwürfel als fertige
  /// Texturen. Die Tabellen baut derselbe Code wie am Rechner
  /// (develop_color.dart); der Browser schlägt nur nach, wie der Shader.
  ///
  /// Rohformate und HEIC kann ein Browser nicht lesen: Er rechnet dann aus
  /// der Vorschau (`quelle: vorschau`).
  Future<Response> entwickeln(Request anfrage, String id) async {
    final b = (await _bereich(anfrage)).bibliothek;
    final db = b.db;
    final a = await db.assetById(id);
    if (a == null || a.isLocked || a.type != 'IMAGE') {
      return _json({'fehler': 'unbekannt'}, status: 404);
    }
    final e = await db.developSettingsForAsset(id);
    final format =
        (a.dateiformat ?? p.extension(a.originalFileName).replaceFirst('.', ''))
            .toLowerCase();
    final browserTauglich = const {
      'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', //
    }.contains(format);

    final kurve = toneCurveAus(e?.toneCurveJson);
    final mischer = colorMixerAus(e?.colorMixerJson);
    CubeLut? lut;
    final lutPfad = e?.lutPath;
    if (lutPfad != null && (e?.lutStrength ?? 0) > 0) {
      try {
        lut = parseCubeLut(await b.pfade.absolute(lutPfad).readAsString());
      } catch (_) {
        // Eine fehlende oder kaputte Tabelle wirkt eben nicht.
      }
    }
    return _json({
      'aufnahme': zeileAlsJson(Rasterzeile.aus(a)),
      'quelle': browserTauglich ? 'original' : 'vorschau',
      'entwickelt': a.developedRelativePath != null,
      'einstellungen': e == null
          ? null
          : {
              'exposure': e.exposure,
              'temperature': e.temperature,
              'tint': e.tint,
              'contrast': e.contrast,
              'shadows': e.shadows,
              'highlights': e.highlights,
              'sharpness': e.sharpness,
              'noise_reduction': e.noiseReduction,
              'clarity': e.clarity,
              'vignette': e.vignette,
              'lut_path': e.lutPath,
              'lut_strength': e.lutStrength,
              'lens_correction_enabled': e.lensCorrectionEnabled,
              'tone_curve_json': e.toneCurveJson,
              'color_mixer_json': e.colorMixerJson,
            },
      if (!kurve.istNeutral)
        'kurve': base64Encode(packCurveLutForTexture(buildCurveLut(kurve))),
      if (!mischer.istNeutral || lut != null) ...{
        'wuerfel': base64Encode(
          packColorCubeForTexture(
            buildColorCube(mischer, lut: lut, lutStaerke: e?.lutStrength ?? 1),
          ),
        ),
        'wuerfelKante': colorCubeSize,
      },
    });
  }

  /// Der Lebensbaum, wie ihn der Rechner zeichnet: dieselbe Anordnung aus
  /// dem Kern (lebensbaumplan/passendeVorlage bzw. das Familienbild aus
  /// dem Geflecht), die Vorlage mit ihren Flächen und Farben, und je Person
  /// was auf ihrem Schild steht. Die Verwandtschaft kommt als Grad – die
  /// Bezeichnung („Großmutter“) setzt der Browser in seiner Sprache.
  ///
  /// Ohne Angaben gilt, was am Rechner zuletzt eingestellt war.
  Future<Response> lebensbaum(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final q = anfrage.url.queryParameters;
    final l = await lebensbaumansicht(
      db,
      fokus: q['fokus'],
      richtung: q['richtung'],
      stil: q['stil'],
      kreis: q['kreis'],
      generationen: int.tryParse(q['generationen'] ?? ''),
      oben: int.tryParse(q['oben'] ?? ''),
      unten: int.tryParse(q['unten'] ?? ''),
    );
    final bild = l.bild;
    if (bild == null) return _json({'fokus': null, 'personen': []});
    List<double> r(g.Rect x) => [x.left, x.top, x.right, x.bottom];
    Map<String, Object?> grad(Grad x) => {
      'art': x.art.name,
      if (x.aufwaerts != 0) 'aufwaerts': x.aufwaerts,
      if (x.abwaerts != 0) 'abwaerts': x.abwaerts,
      if (x.halb) 'halb': true,
      if (x.elternArt != null) 'elternArt': x.elternArt!.name,
    };
    bool hatPortrait(String id) =>
        l.personen[id]?.person.coverFaceCropPath != null;
    final v = bild.vorlage;
    String datei(String asset) => p.basename(asset);
    final o = l.optionen;
    return _json({
      'fokus': l.fokus,
      'optionen': {
        'richtung': o.richtung.name,
        'stil': o.stil.name,
        'generationen': o.generationen,
        'oben': o.oben,
        'unten': o.unten,
        'kreis': o.kreis.name,
      },
      'alle': [
        for (final x in l.alle)
          {'id': x.id, 'name': x.name, 'verwandt': l.verwandt.contains(x.id)},
      ],
      'nachname': l.nachname,
      'fokusName': l.alle.firstWhere((x) => x.id == l.fokus).name,
      'hintergrund': datei(bild.hintergrund),
      'verschwiegen': bild.verschwiegen,
      'vorlage': {
        'groesse': [v.groesse.width, v.groesse.height],
        'titel': r(v.titel),
        if (v.untertitel != null) 'untertitel': r(v.untertitel!),
        'schrift': v.schrift.css,
        'nebenschrift': v.nebenschrift.css,
        if (v.schildBild != null) 'schildBild': datei(v.schildBild!),
      },
      'plaetze': [
        for (final pl in bild.plaetze)
          {
            'rahmen': r(pl.rahmen),
            'schrift': r(pl.schrift),
            'schriftMitPortrait': r(schriftUnterPortraits(pl, hatPortrait)),
            'kreise': [
              for (final (k, id) in portraitKreise(pl, hatPortrait))
                {'kreis': r(k), 'id': id},
            ],
            'personen': pl.personen,
            if (pl.amStamm) 'amStamm': true,
            if (pl.zuSetzen) 'zuSetzen': true,
          },
      ],
      'personen': {
        for (final MapEntry(key: id, value: x) in l.personen.entries)
          id: {
            'name': x.person.name,
            'lebensspanne': x.lebensspanne,
            'bild': x.person.coverFaceCropPath,
            'geschlecht': x.person.geschlecht,
            if (x.grad != null) 'grad': grad(x.grad!),
            if (x.umweg case final u?)
              'umweg': {
                'name': u.ueber.name,
                'geschlecht': u.ueber.geschlecht,
                'schritt': grad(u.schritt),
                'ueberGrad': grad(u.ueberGrad),
              },
          },
      },
    });
  }

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
    if (art == 'abspielbar') return _abspielbar(anfrage, b, a);
    final relativ = switch (art) {
      'miniatur' => a.thumbnailRelativePath,
      // Was der Betrachter zeigt – wie in den Apps: restauriert,
      // entwickelt, gekürzt, Vorschau, Original (displayRelativePath).
      'ansicht' =>
        a.type == 'IMAGE'
            ? displayRelativePath(a)
            : (a.previewRelativePath ?? a.thumbnailRelativePath),
      'vorschau' =>
        a.previewRelativePath ??
            (a.type == 'IMAGE' ? a.relativePath : a.thumbnailRelativePath),
      'original' => a.relativePath,
      // Was der Betrachter abspielt – wie in den Apps: gekürzt, sonst das
      // Original.
      'wiedergabe' =>
        a.type == 'VIDEO' ? (a.trimmedRelativePath ?? a.relativePath) : null,
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

  /// Ein Video als H.264 (siehe [Videofassungen]): die fertige Fassung
  /// (mit `?pruefen=1` nur `{"bereit": true}`), sonst `202` mit
  /// `{"bereit": false}` – dann wird sie gerade erzeugt, und der Browser
  /// fragt gleich noch einmal. `422`, wenn sie sich nicht erzeugen lässt.
  Future<Response> _abspielbar(
    Request anfrage,
    Bibliothek b,
    AssetData a,
  ) async {
    if (a.type != 'VIDEO') return Response.notFound(null);
    // Aus dem, was der Betrachter zeigt: gekürzt, sonst das Original. Der
    // Name sagt, aus welchem – sonst bliebe nach dem Zurücknehmen einer
    // Kürzung die gekürzte Fassung liegen.
    final gekuerzt = a.trimmedRelativePath != null;
    final original = b.pfade.absolute(a.trimmedRelativePath ?? a.relativePath);
    if (!p.isWithin(b.pfade.root.path, original.path) ||
        !await original.exists()) {
      return Response.notFound(null);
    }
    final speicher = Directory(p.join(b.ordner.path, 'abspielbar'));
    final name = gekuerzt ? '${a.id}-gekuerzt' : a.id;
    final fertig = await videofassungen.bereit(speicher, name, original);
    // `?pruefen=1` fragt nur nach, ohne die Datei zu holen.
    if (fertig != null && anfrage.url.queryParameters['pruefen'] != null) {
      return _json({'bereit': true});
    }
    if (fertig != null) return dateiAntwort(anfrage, fertig);
    if (videofassungen.gescheitert.contains(
      Videofassungen.ziel(speicher, name).path,
    )) {
      return _json({
        'bereit': false,
        'fehler': 'nicht umwandelbar',
      }, status: 422);
    }
    return _json({'bereit': false}, status: 202);
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
