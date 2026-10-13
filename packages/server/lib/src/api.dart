import 'dart:async';
import 'dart:convert';

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
import 'oidc.dart';
import 'suche_api.dart';
import 'umzug.dart';

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
}) {
  final von = absender ?? Absender();
  final anmeldung = Anmeldungsapi(konten, von, oidc);
  final api = _Api(bibliotheken);
  final abgleich = Abgleichsapi(bibliotheken);
  final umzug = Umzugsdienst(bibliotheken);
  final suche = Suchapi(bibliotheken);
  Future<Kontobereich> bereich(Request r) => bibliotheken.fuer(kontoVon(r).id);

  final r = Router()
    ..get('/api/v1/zustand', (Request _) => api.zustand(konten, oidc))
    ..post('/api/v1/anmelden', anmeldung.anmelden)
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
    ..post('/api/v1/befehle', abgleich.befehle)
    ..get('/api/v1/abgleich/stand', abgleich.stand)
    ..get('/api/v1/abgleich/aenderungen', abgleich.aenderungen)
    ..post('/api/v1/abgleich/zeilen', abgleich.zeilen)
    ..get('/api/v1/abgleich/abzug', abgleich.abzug)
    ..get('/api/v1/dateien/<pfad|.+>', abgleich.datei)
    ..post('/api/v1/suche/text', suche.text)
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
      (Request r) => umzug.hochladen(r).anlegen(r),
    )
    ..head(
      '/api/v1/umzug/hochladen/<id>',
      (Request r, String id) => umzug.hochladen(r).stand(r, id),
    )
    ..patch(
      '/api/v1/umzug/hochladen/<id>',
      (Request r, String id) => umzug.hochladen(r).anhaengen(r, id),
    )
    ..delete(
      '/api/v1/umzug/hochladen/<id>',
      (Request r, String id) => umzug.hochladen(r).verwerfen(r, id),
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
      (Request r) async => (await bereich(r)).hochladen.anlegen(r),
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
      (Request r, String id) async =>
          (await bereich(r)).hochladen.anhaengen(r, id),
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
            'api/v1/zustand',
            'api/v1/anmelden',
            'api/v1/anmelden/totp',
            'api/v1/anmelden/oidc',
            'api/v1/anmelden/oidc/zurueck',
            'api/v1/anmelden/oidc/einloesen',
          },
        ),
      )
      .addHandler(r.call);
}

/// Was jede Antwort trägt: Der Browser soll nichts erraten und keine
/// Adresse weitergeben – die Rückwege der Anmeldung tragen Codes.
Middleware get _sicherheitskoepfe =>
    (innerer) => (anfrage) async {
      final antwort = await innerer(anfrage);
      return antwort.change(
        headers: {
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'no-referrer',
        },
      );
    };

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Api {
  _Api(this.bibliotheken);

  final Bibliotheken bibliotheken;

  Future<Kontobereich> _bereich(Request r) => bibliotheken.fuer(kontoVon(r).id);

  /// Lebenszeichen, ohne Anmeldung – für Docker, den Reverse Proxy und
  /// Clients, die wissen wollen, wie sie sich anmelden.
  Response zustand(Kontodienst konten, Oidc? oidc) => _json({
    'dienst': 'photo-vault',
    'protokoll': protokollFassung,
    'anmeldung': {'totp': konten.totpPflicht, 'oidc': oidc != null},
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
  /// ihrem Fortschritt.
  Future<Response> auswertung(Request anfrage) async {
    final d = (await _bereich(anfrage)).auswertung;
    return _json({'laeuft': d.laeuft, 'stand': d.stand?.alsJson()});
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
