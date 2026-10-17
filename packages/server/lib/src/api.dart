import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'abgleich_api.dart';
import 'absender.dart';
import 'anmeldung_api.dart';
import 'bibliotheken.dart';
import 'dateiantwort.dart';
import 'konten/kontodienst.dart';
import 'konten_api.dart';
import 'oidc.dart';
import 'rechnen.dart';
import 'sicherung.dart';
import 'speicher.dart';
import 'suche_api.dart';
import 'umzug.dart';
import 'web.dart';

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
    ..post('/api/v1/suche/text', suche.text)
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
      'aufnahmen': [for (final r in liste) _alsJson(r)],
      'weiter': liste.length < anzahl
          ? null
          : _Lesezeichen(liste.last.fileCreatedAt, liste.last.id).text,
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

Map<String, Object?> _alsJson(Rasterzeile r) => {
  'id': r.id,
  'art': r.type == 'VIDEO' ? 'video' : 'bild',
  'name': r.originalFileName,
  'aufgenommen': r.fileCreatedAt.toIso8601String(),
  if (r.durationSeconds != null) 'dauer': r.durationSeconds,
  if (r.isFavorite) 'favorit': true,
  if (r.rating > 0) 'bewertung': r.rating,
  if (r.colorLabel != null) 'farbe': r.colorLabel,
  if (r.widthPx != null) 'breite': r.widthPx,
  if (r.heightPx != null) 'hoehe': r.heightPx,
  if (r.latitude != null && r.longitude != null)
    'ort': {'breite': r.latitude, 'laenge': r.longitude},
  if (r.cameraMake != null) 'kamera': r.cameraMake,
  if (r.stackId != null)
    'serie': {'id': r.stackId, 'titel': r.isStackCover, 'groesse': r.stackSize},
  if (r.linkedAssetId != null) 'partner': r.linkedAssetId,
  'miniatur': r.thumbnailRelativePath != null,
};

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
