import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/asset_display_path.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'absender.dart';
import 'anmeldung_api.dart';
import 'bibliothek.dart';
import 'bibliotheken.dart';
import 'dateiantwort.dart';
import 'freigaben.dart';
import 'konten/bremse.dart';
import 'teilbilder.dart';
import 'videofassung.dart';
import 'web.dart';

Response _json(Object? daten, {int status = 200, Map<String, String>? kopf}) =>
    Response(
      status,
      body: jsonEncode(daten),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        ...?kopf,
      },
    );

/// Teilen nach aussen (Issue #106): Der Besitzer legt Freigaben für ein
/// Album oder eine Auswahl an; wer den Link hat, sieht genau diese
/// Aufnahmen – sonst nichts.
///
/// **Was ein Besucher bekommt:** Bilder, neu gerechnet und ohne
/// Metadaten (siehe [Teilbilder]), Videos als H.264 ohne Metadaten (siehe
/// [Videofassungen]); Originale nur, wenn der Besitzer Herunterladen
/// erlaubt hat. Keine Orte, keine Personen, keine Namen. Gesperrte
/// Aufnahmen und der Papierkorb kommen nie dazu, auch nicht über ein
/// Album.
///
/// **Was ihn aufhält:** Abgelaufene und gelöschte Freigaben antworten
/// wie unbekannte mit 404. Ein Passwort wird wie bei der Anmeldung je
/// Absender gebremst; danach gilt ein Cookie zwölf Stunden.
class Freigabeapi {
  Freigabeapi({
    required this.dienst,
    required this.bibliotheken,
    required this.absender,
    required this.video,
    this.webOrdner,
    this.oeffentlich,
    Bremse? bremse,
  }) : bremse = bremse ?? Bremse();

  final Freigabedienst dienst;
  final Bibliotheken bibliotheken;
  final Absender absender;
  final Videofassungen video;
  final Directory? webOrdner;

  /// Die Adresse von aussen (`PV_OEFFENTLICH`); sonst die der Anfrage.
  final Uri? oeffentlich;
  final Bremse bremse;
  final _teilbilder = Teilbilder();

  static const _keineSuche = {'x-robots-tag': 'noindex, nofollow'};

  // --- Für den Besitzer ----------------------------------------------------

  /// Wohin der Link zeigt: die Adresse von aussen – gesetzt, vom
  /// vertrauten Proxy gemeldet oder die, über die die Anfrage kam.
  String _basis(Request r) {
    final o = oeffentlich;
    if (o != null) {
      final s = o.toString();
      return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
    }
    final host = r.headers['x-forwarded-host'];
    if (host != null && host.isNotEmpty && absender.ueberVertrautenProxy(r)) {
      final proto = (r.headers['x-forwarded-proto'] ?? 'https')
          .split(',')
          .first
          .trim();
      return '$proto://${host.split(',').first.trim()}';
    }
    return r.requestedUri.origin;
  }

  Future<Map<String, Object?>> _alsJson(
    Request r,
    Freigabe f,
    String link,
    AppDatabase db,
  ) async {
    final anzahl = f.album != null
        ? (await db.albumAufnahmen(f.album!)).length
        : f.aufnahmen!.length;
    return {
      'id': f.id,
      'titel': f.titel,
      'link': '${_basis(r)}/teilen/$link',
      'art': f.album != null ? 'album' : 'auswahl',
      if (f.album != null) 'album': f.album,
      'anzahl': anzahl,
      'angelegt': f.angelegt.toUtc().toIso8601String(),
      'ablauf': f.ablauf?.toUtc().toIso8601String(),
      'passwort': f.mitPasswort,
      'herunterladen': f.herunterladen,
      'aufrufe': f.aufrufe,
      'zuletzt': f.zuletzt?.toUtc().toIso8601String(),
    };
  }

  /// `{titel, album | ids, tage?, passwort?, herunterladen?}` → die neue
  /// Freigabe mit ihrem Link.
  Future<Response> anlegen(Request r) async {
    final Object? k;
    try {
      k = jsonDecode(await r.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    if (k is! Map) return _json({'fehler': 'kein JSON'}, status: 400);
    final titel = '${k['titel'] ?? ''}'.trim();
    if (titel.isEmpty || titel.length > 200) {
      return _json({'fehler': 'Titel fehlt'}, status: 400);
    }
    final konto = kontoVon(r);
    final db = (await bibliotheken.fuer(konto.id)).bibliothek.db;
    final album = k['album'];
    final ids = k['ids'];
    List<String>? aufnahmen;
    if (album is String) {
      final da = (await db.alleAlben()).any((a) => a.id == album);
      if (!da) return _json({'fehler': 'Album unbekannt'}, status: 404);
    } else if (ids is List && ids.isNotEmpty) {
      if (ids.length > Freigabedienst.hoechstensAufnahmen) {
        return _json({'fehler': 'zu viele Aufnahmen'}, status: 400);
      }
      final gewollt = {for (final x in ids) '$x'};
      // Nur, was es gibt und was nicht gesperrt oder im Papierkorb ist.
      aufnahmen = [
        for (final a in await db.assetsByIds(gewollt.toList()))
          if (!a.isLocked && !a.isTrashed) a.id,
      ];
      if (aufnahmen.isEmpty) {
        return _json({'fehler': 'keine Aufnahmen'}, status: 400);
      }
    } else {
      return _json({'fehler': 'album oder ids fehlt'}, status: 400);
    }
    final tage = k['tage'];
    if (tage != null && (tage is! int || tage < 1 || tage > 3650)) {
      return _json({'fehler': 'tage: 1 bis 3650'}, status: 400);
    }
    final passwort = k['passwort'];
    if (passwort != null &&
        (passwort is! String ||
            (passwort.isNotEmpty && passwort.length < 4) ||
            passwort.length > 200)) {
      return _json({'fehler': 'Passwort: mindestens 4 Zeichen'}, status: 400);
    }
    final neu = await dienst.lege(
      konto: konto.id,
      titel: titel,
      album: album is String ? album : null,
      aufnahmen: aufnahmen,
      gueltig: tage is int ? Duration(days: tage) : null,
      passwortKlartext: passwort as String?,
      herunterladen: k['herunterladen'] == true,
    );
    final f = (await dienst.von(
      konto.id,
    )).firstWhere((x) => x.freigabe.id == neu.id);
    return _json(await _alsJson(r, f.freigabe, f.link, db), status: 201);
  }

  /// Die Freigaben des Kontos.
  Future<Response> liste(Request r) async {
    final konto = kontoVon(r);
    final db = (await bibliotheken.fuer(konto.id)).bibliothek.db;
    return _json({
      'freigaben': [
        for (final x in await dienst.von(konto.id))
          await _alsJson(r, x.freigabe, x.link, db),
      ],
    });
  }

  Future<Response> loeschen(Request r, String id) async =>
      dienst.widerrufe(kontoVon(r).id, id)
      ? _json({'geloescht': true})
      : _json({'fehler': 'unbekannt'}, status: 404);

  // --- Für Besucher --------------------------------------------------------

  Future<({Freigabe freigabe, Bibliothek bibliothek})?> _oeffne(
    String link,
  ) async {
    final f = dienst.fuer(link);
    if (f == null) return null;
    return (
      freigabe: f,
      bibliothek: (await bibliotheken.fuer(f.konto)).bibliothek,
    );
  }

  String _cookieName(Freigabe f) => 'pv_teilen_${f.id}';

  bool _zugelassen(Request r, Freigabe f) =>
      dienst.sitzungGilt(f, cookieWert(r, _cookieName(f)));

  Future<List<AssetData>> _aufnahmen(Freigabe f, AppDatabase db) async {
    if (f.album != null) return db.albumAufnahmen(f.album!);
    final liste = [
      for (final a in await db.assetsByIds(f.aufnahmen!))
        if (!a.isLocked && !a.isTrashed) a,
    ]..sort((a, b) => b.fileCreatedAt.compareTo(a.fileCreatedAt));
    return liste;
  }

  Future<bool> _gehoertDazu(Freigabe f, AppDatabase db, AssetData a) async {
    if (a.isLocked || a.isTrashed) return false;
    if (f.aufnahmen != null) return f.aufnahmen!.contains(a.id);
    final z =
        await (db.select(db.albumAssets)..where(
              (t) => t.albumId.equals(f.album!) & t.assetId.equals(a.id),
            ))
            .getSingleOrNull();
    return z != null;
  }

  /// Die Seite – dieselbe für jede Freigabe; was sie zeigt, holt sie sich.
  Future<Response> seite(Request r, String link) async {
    final ordner = webOrdner;
    final f = ordner == null ? null : File(p.join(ordner.path, 'teilen.html'));
    if (f == null || !await f.exists()) return Response.notFound('nicht da');
    return Response.ok(
      f.openRead(),
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
        'content-security-policy': Webapi.csp,
        ..._keineSuche,
      },
    );
  }

  /// `{titel, herunterladen, ablauf, aufnahmen}`; 401 `{passwort: true}`,
  /// solange das Passwort fehlt.
  Future<Response> inhalt(Request r, String link) async {
    final o = await _oeffne(link);
    if (o == null) {
      return _json({'fehler': 'unbekannt'}, status: 404, kopf: _keineSuche);
    }
    final f = o.freigabe;
    if (!_zugelassen(r, f)) {
      return _json({'passwort': true}, status: 401, kopf: _keineSuche);
    }
    dienst.aufgerufen(f);
    final liste = await _aufnahmen(f, o.bibliothek.db);
    return _json({
      'titel': f.titel,
      'herunterladen': f.herunterladen,
      'ablauf': f.ablauf?.toUtc().toIso8601String(),
      'aufnahmen': [
        for (final a in liste)
          {
            'id': a.id,
            'art': a.type == 'VIDEO' ? 'video' : 'bild',
            'aufgenommen': a.fileCreatedAt.toIso8601String(),
            if (a.widthPx != null) 'breite': a.widthPx,
            if (a.heightPx != null) 'hoehe': a.heightPx,
            if (a.durationSeconds != null) 'dauer': a.durationSeconds,
          },
      ],
    }, kopf: _keineSuche);
  }

  /// `{passwort}` → 204 mit Cookie; 401 bei falschem, 429 nach zu vielen.
  Future<Response> passwort(Request r, String link) async {
    final adresse = absender.von(r);
    final warten = bremse.wartezeit(adresse);
    if (warten != null) {
      return _json(
        {'fehler': 'zu viele Versuche', 'warten': warten.inSeconds},
        status: 429,
        kopf: {'retry-after': '${warten.inSeconds + 1}'},
      );
    }
    final o = await _oeffne(link);
    if (o == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final Object? k;
    try {
      k = jsonDecode(await r.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    final klartext = k is Map ? '${k['passwort'] ?? ''}' : '';
    if (klartext.isEmpty ||
        klartext.length > 200 ||
        !await dienst.passwortStimmt(o.freigabe, klartext)) {
      bremse.fehlschlag(adresse);
      return _json({'fehler': 'Passwort falsch'}, status: 401);
    }
    final sicher =
        r.requestedUri.scheme == 'https' ||
        (absender.ueberVertrautenProxy(r) &&
            (r.headers['x-forwarded-proto'] ?? '')
                    .split(',')
                    .first
                    .trim()
                    .toLowerCase() ==
                'https');
    return Response(
      204,
      headers: {
        'set-cookie': [
          '${_cookieName(o.freigabe)}=${dienst.sitzung(o.freigabe)}',
          'Path=/',
          'Max-Age=${Freigabedienst.sitzungsdauer.inSeconds}',
          'HttpOnly',
          'SameSite=Lax',
          if (sicher) 'Secure',
        ].join('; '),
        'cache-control': 'no-store',
      },
    );
  }

  /// `miniatur` und `ansicht` (Bilder, ohne Metadaten), `video` (H.264,
  /// sonst 202 wie bei `abspielbar`), `original` (nur mit Herunterladen).
  Future<Response> datei(Request r, String link, String id, String art) async {
    final o = await _oeffne(link);
    if (o == null) return Response.notFound(null, headers: _keineSuche);
    final f = o.freigabe;
    if (!_zugelassen(r, f)) return Response(401, headers: _keineSuche);
    final b = o.bibliothek;
    final a = await b.db.assetById(id);
    if (a == null || !await _gehoertDazu(f, b.db, a)) {
      return Response.notFound(null, headers: _keineSuche);
    }
    File? ausDer(String? relativ) {
      if (relativ == null) return null;
      final d = b.pfade.absolute(relativ);
      return p.isWithin(b.pfade.root.path, d.path) ? d : null;
    }

    final speicher = Directory(p.join(b.ordner.path, 'geteilt'));
    switch (art) {
      case 'miniatur':
        final q = ausDer(a.thumbnailRelativePath);
        if (q == null || !await q.exists()) return Response.notFound(null);
        final d = await _teilbilder.fassung(
          speicher,
          '${a.id}-m',
          q,
          kante: 512,
        );
        return d == null ? Response.notFound(null) : dateiAntwort(r, d);
      case 'ansicht':
        if (a.type == 'VIDEO') return Response.notFound(null);
        final q = ausDer(displayRelativePath(a));
        if (q == null || !await q.exists()) return Response.notFound(null);
        final d = await _teilbilder.fassung(
          speicher,
          '${a.id}-a',
          q,
          kante: 2560,
        );
        return d == null ? Response.notFound(null) : dateiAntwort(r, d);
      case 'video':
        if (a.type != 'VIDEO') return Response.notFound(null);
        final q = ausDer(a.trimmedRelativePath ?? a.relativePath);
        if (q == null || !await q.exists()) return Response.notFound(null);
        final name = a.trimmedRelativePath != null ? '${a.id}-gekuerzt' : a.id;
        final abspielbar = Directory(p.join(b.ordner.path, 'abspielbar'));
        final fertig = await video.bereit(abspielbar, name, q);
        if (fertig != null) {
          return r.url.queryParameters['pruefen'] != null
              ? _json({'bereit': true})
              : dateiAntwort(r, fertig);
        }
        return video.gescheitert.contains(
              Videofassungen.ziel(abspielbar, name).path,
            )
            ? _json({'bereit': false}, status: 422)
            : _json({'bereit': false}, status: 202);
      case 'original':
        if (!f.herunterladen) return Response.notFound(null);
        final q = ausDer(a.relativePath);
        if (q == null || !await q.exists()) return Response.notFound(null);
        final antwort = await dateiAntwort(r, q);
        final name = a.originalFileName.replaceAll(RegExp(r'["\\\r\n]'), '_');
        return antwort.change(
          headers: {'content-disposition': 'attachment; filename="$name"'},
        );
    }
    return Response.notFound(null);
  }
}
