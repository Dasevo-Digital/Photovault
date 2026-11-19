import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/beschriftungsvorschlaege.dart';
import 'package:shelf/shelf.dart';

Response _json(Object? j, [int status = 200]) => Response(
  status,
  body: jsonEncode(j),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

/// Der Aufrufer hat den Zugriff auf das Album und seine sichtbaren Fotos geprüft.
Future<Response> beschriftungsAnfrage(
  Request request,
  AppDatabase db,
  String album, {
  required String konto,
  required String name,
  required bool besitzer,
  String? entscheidung,
}) async {
  final dienst = Beschriftungsdienst(db);
  final t = db.beschriftungsvorschlaege;
  Future<bool> sichtbar(String id) async =>
      (await (db.selectOnly(db.assets)
                ..addColumns([db.assets.id])
                ..where(
                  db.sichtbareAufnahmeImAlbum(album) & db.assets.id.equals(id),
                )
                ..limit(1))
              .get())
          .isNotEmpty;
  try {
    if (request.method == 'GET') {
      final aufnahme = request.url.queryParameters['aufnahme'];
      final seite = int.tryParse(request.url.queryParameters['seite'] ?? '0');
      if (seite == null || seite < 0 || seite > 100000) {
        return _json({'fehler': 'seite'}, 400);
      }
      if (aufnahme != null && !await sichtbar(aufnahme)) {
        return _json({'fehler': 'unbekannt'}, 404);
      }
      final q = db.select(t)
        ..where((t) => t.albumId.equals(album))
        ..where(
          (t) => t.assetId.isInQuery(
            db.selectOnly(db.assets)
              ..addColumns([db.assets.id])
              ..where(db.sichtbareAufnahmeImAlbum(album)),
          ),
        )
        ..where(
          (t) => aufnahme == null
              ? const Constant(true)
              : t.assetId.equals(aufnahme),
        )
        ..where((t) => besitzer ? const Constant(true) : t.von.equals(konto))
        ..orderBy([
          (t) => OrderingTerm.desc(t.angelegt),
          (t) => OrderingTerm.desc(t.id),
        ])
        ..limit(101, offset: seite * 100);
      final rows = await q.get();
      final result = <Map<String, Object?>>[];
      final staende = <String, String>{};
      for (final v in rows.take(100)) {
        if (!besitzer && v.von != konto) continue;
        final a = (await db.assetById(v.assetId))!;
        result.add({
          'id': v.id,
          'aufnahme': v.assetId,
          'art': v.art,
          'wert': v.wert,
          'gesicht': ?v.gesichtId,
          'von': v.vonName,
          'angelegt': v.angelegt.toUtc().toIso8601String(),
          'zustand': v.zustand,
          'entschieden': ?v.entschieden?.toUtc().toIso8601String(),
          if (besitzer)
            'stand': staende[v.assetId] ??= await dienst.stand(v.assetId),
          if (besitzer)
            'aktuell': switch (v.art) {
              'jahr' => '${a.fileCreatedAt.year}',
              'ort' => a.locationCity ?? '',
              _ => (await db.peopleForAsset(
                a.id,
              )).map((p) => p.name).join(', '),
            },
        });
      }
      final faces = aufnahme == null
          ? <FaceData>[]
          : await db.facesForAsset(aufnahme);
      return _json({
        'besitzer': besitzer,
        'vorschlaege': result,
        'mehr': rows.length > 100,
        'gesichter': [
          for (final f in faces)
            if (!f.isIgnored)
              {
                'id': f.id,
                'x': f.boxX,
                'y': f.boxY,
                'breite': f.boxW,
                'hoehe': f.boxH,
              },
        ],
        if (besitzer)
          'personen': [
            for (final p in await db.allePersonen())
              {'id': p.id, 'name': p.name, 'bild': p.coverFaceCropPath},
          ],
      });
    }
    final bytes = <int>[];
    await for (final block in request.read()) {
      if (bytes.length + block.length > 8192) {
        return _json({'fehler': 'umfang'}, 413);
      }
      bytes.addAll(block);
    }
    final body = utf8.decode(bytes);
    final j = (jsonDecode(body) as Map).cast<String, Object?>();
    if (entscheidung != null) {
      if (!besitzer) return _json({'fehler': 'unbekannt'}, 404);
      final row =
          await (db.select(t)..where(
                (t) => t.id.equals(entscheidung) & t.albumId.equals(album),
              ))
              .getSingleOrNull();
      if (row == null || !await sichtbar(row.assetId)) {
        return _json({'fehler': 'unbekannt'}, 404);
      }
      if (j['annehmen'] is! bool || j['stand'] is! String) {
        return _json({'fehler': 'entscheidung'}, 400);
      }
      await dienst.entscheiden(
        entscheidung,
        annehmen: j['annehmen'] as bool,
        erwartet: j['stand'] as String,
        personId: j['person'] as String?,
      );
      return _json({'erledigt': true});
    }
    final id = j['aufnahme'];
    if (id is! String || !await sichtbar(id)) {
      return _json({'fehler': 'unbekannt'}, 404);
    }
    final art = j['art'], wert = j['wert'];
    if (art is! String || wert is! String) {
      return _json({'fehler': 'wert'}, 400);
    }
    final kennung = await dienst.vorschlagen(
      id: id,
      album: album,
      von: konto,
      name: name,
      art: art,
      wert: wert,
      gesicht: j['gesicht'] as String?,
    );
    return _json({'id': kennung}, 201);
  } on FormatException catch (e) {
    return _json(
      {'fehler': e.message},
      e.message == 'pv_beschriftung_geaendert' ||
              e.message == 'pv_beschriftung_mehrdeutig' ||
              e.message == 'pv_beschriftung_entschieden'
          ? 409
          : 400,
    );
  } on TypeError {
    return _json({'fehler': 'format'}, 400);
  }
}
