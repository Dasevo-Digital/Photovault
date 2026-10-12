import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auswertungsdienst.dart';
import 'bibliothek.dart';
import 'hochladen.dart';
import 'zugang.dart';

/// Welche Fassung der Schnittstelle der Server spricht. Steigt, sobald sich
/// etwas so ändert, dass ein älterer Client es falsch verstünde.
const protokollFassung = 1;

/// Die Schnittstelle unter `/api/v1`.
Handler baueApi({
  required Bibliothek bibliothek,
  required Hochladen hochladen,
  required Zugang zugang,
  Auswertungsdienst? auswertung,
}) {
  final api = _Api(bibliothek, auswertung);
  final r = Router()
    ..get('/api/v1/zustand', api.zustand)
    ..get('/api/v1/bibliothek', api.bibliothek)
    ..get('/api/v1/aufnahmen', api.aufnahmen)
    ..get('/api/v1/aufnahmen/<id>', api.aufnahme)
    ..get('/api/v1/aufnahmen/<id>/<art>', api.datei)
    ..post('/api/v1/befehle', api.befehl)
    ..get('/api/v1/auswertung', api.auswertung)
    ..post('/api/v1/auswertung', api.auswertungAnstossen)
    ..add('OPTIONS', '/api/v1/hochladen', hochladen.optionen)
    ..post('/api/v1/hochladen', hochladen.anlegen)
    ..head('/api/v1/hochladen/<id>', hochladen.stand)
    ..get('/api/v1/hochladen/<id>', hochladen.status)
    ..patch('/api/v1/hochladen/<id>', hochladen.anhaengen)
    ..delete('/api/v1/hochladen/<id>', hochladen.verwerfen);
  return const Pipeline()
      .addMiddleware(zugang.middleware(offen: {'api/v1/zustand'}))
      .addHandler(r.call);
}

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Api {
  _Api(this.b, this.dienst);

  final Bibliothek b;
  final Auswertungsdienst? dienst;

  AppDatabase get db => b.db;

  /// Lebenszeichen, ohne Schlüssel – für Docker und den Reverse Proxy.
  Response zustand(Request anfrage) =>
      _json({'dienst': 'photo-vault', 'protokoll': protokollFassung});

  Future<Response> bibliothek(Request anfrage) async {
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
  Response auswertung(Request anfrage) => _json({
    'laeuft': dienst?.laeuft ?? false,
    'stand': dienst?.stand?.alsJson(),
  });

  /// Stösst einen Durchgang an, ohne die Ruhezeit abzuwarten. Antwortet
  /// sofort; der Durchgang läuft im Hintergrund.
  Response auswertungAnstossen(Request anfrage) {
    final d = dienst;
    if (d == null) return _json({'fehler': 'keine Auswertung'}, status: 503);
    unawaited(d.jetzt());
    return _json({'laeuft': true}, status: 202);
  }

  /// Die Zeitleiste seitenweise, neueste zuerst.
  ///
  /// Weiterblättern über `nach` – den Wert `weiter` der vorigen Seite –
  /// statt über eine Seitenzahl: Kommt oben etwas dazu, verrutscht eine
  /// Seitenzahl, ein Lesezeichen auf die letzte Zeile nicht. Und die
  /// Abfrage bleibt in jeder Tiefe der Bibliothek gleich schnell.
  Future<Response> aufnahmen(Request anfrage) async {
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
    final a = await db.assetById(id);
    if (a == null || a.isLocked) {
      return _json({'fehler': 'unbekannt'}, status: 404);
    }
    return _json(a.toJson());
  }

  /// `miniatur`, `vorschau` oder `original` – mit Teilabruf (`Range`),
  /// damit sich ein Video abspielen lässt, ohne es ganz zu laden.
  Future<Response> datei(Request anfrage, String id, String art) async {
    final a = await db.assetById(id);
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
    return _dateiAntwort(anfrage, datei);
  }

  /// Ein Befehl (siehe `package:kern/befehle`) als JSON: `{art, werte}`.
  Future<Response> befehl(Request anfrage) async {
    final Befehl<Object?> b;
    try {
      b = Befehl.ausJson(
        (jsonDecode(await anfrage.readAsString()) as Map)
            .cast<String, Object?>(),
      );
    } on Object catch (e) {
      return _json({'fehler': 'Befehl nicht lesbar: $e'}, status: 400);
    }
    final ergebnis = await db.fuehreAus(b);
    return _json({'ergebnis': _ergebnisAlsJson(ergebnis)});
  }
}

Object? _ergebnisAlsJson(Object? e) => switch (e) {
  null || bool() || num() || String() => e,
  DateTime() => e.toIso8601String(),
  Enum() => e.name,
  _ => e.toString(),
};

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

const _typen = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.heic': 'image/heic',
  '.heif': 'image/heif',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.tif': 'image/tiff',
  '.tiff': 'image/tiff',
  '.mov': 'video/quicktime',
  '.mp4': 'video/mp4',
  '.m4v': 'video/x-m4v',
};

Future<Response> _dateiAntwort(Request anfrage, File datei) async {
  final groesse = await datei.length();
  final geaendert = await datei.lastModified();
  final etag =
      '"${geaendert.millisecondsSinceEpoch.toRadixString(36)}-'
      '${groesse.toRadixString(36)}"';
  final kopf = {
    'content-type':
        _typen[p.extension(datei.path).toLowerCase()] ??
        'application/octet-stream',
    'accept-ranges': 'bytes',
    'etag': etag,
    'cache-control': 'private, max-age=86400',
  };
  if (anfrage.headers['if-none-match'] == etag) {
    return Response.notModified(headers: kopf);
  }
  final bereich = RegExp(
    r'^bytes=(\d*)-(\d*)$',
  ).firstMatch(anfrage.headers['range'] ?? '');
  if (bereich == null || groesse == 0) {
    return Response.ok(
      datei.openRead(),
      headers: {...kopf, 'content-length': '$groesse'},
    );
  }
  final a = bereich.group(1)!, e = bereich.group(2)!;
  int von, bis;
  if (a.isEmpty) {
    // `bytes=-500`: die letzten 500 Bytes.
    final n = int.parse(e);
    von = n >= groesse ? 0 : groesse - n;
    bis = groesse - 1;
  } else {
    von = int.parse(a);
    bis = e.isEmpty ? groesse - 1 : int.parse(e).clamp(0, groesse - 1);
  }
  if (von >= groesse || von > bis) {
    return Response(
      416,
      headers: {...kopf, 'content-range': 'bytes */$groesse'},
    );
  }
  return Response(
    206,
    body: datei.openRead(von, bis + 1),
    headers: {
      ...kopf,
      'content-range': 'bytes $von-$bis/$groesse',
      'content-length': '${bis - von + 1}',
    },
  );
}
