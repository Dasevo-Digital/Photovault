import 'dart:io';

import 'package:kern/services/videoformate.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'packen.dart';

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
  // Alle Videoformate des Imports (#232): Ohne den passenden Typ meldete
  // der Browser bei MTS oder MPG keinen Fehler, sondern lud die Datei
  // herunter – und holte nie die abspielbare Fassung.
  ...videoMedientypen,
};

/// Grösser als jede Datei, für Zahlen in `Range`, die nicht in int passen.
const _riesig = 1 << 62;

/// Antwortet mit [datei], auf Wunsch einem Teil davon (`Range`) – damit
/// sich ein Video abspielen lässt, ohne es ganz zu laden.
Future<Response> dateiAntwort(Request anfrage, File datei) async {
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
  if (etagPasst(anfrage, etag)) {
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
  // `bytes=-` nennt keinen Bereich: ganz, wie ohne Range (RFC 9110 14.2).
  // Vorher warf int.parse('') – ein 500 ohne Anmeldung über jede Datei
  // eines Links.
  if (a.isEmpty && e.isEmpty) {
    return Response.ok(
      datei.openRead(),
      headers: {...kopf, 'content-length': '$groesse'},
    );
  }
  // Nur Ziffern (siehe oben): Was nicht in int passt, ist grösser als
  // jede Datei.
  int zahl(String s) => int.tryParse(s) ?? _riesig;
  int von, bis;
  if (a.isEmpty) {
    // `bytes=-500`: die letzten 500 Bytes.
    final n = zahl(e);
    von = n >= groesse ? 0 : groesse - n;
    bis = groesse - 1;
  } else {
    von = zahl(a);
    bis = e.isEmpty ? groesse - 1 : zahl(e).clamp(0, groesse - 1);
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
