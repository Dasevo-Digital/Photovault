import 'dart:io';

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
  '.mov': 'video/quicktime',
  '.mp4': 'video/mp4',
  '.m4v': 'video/x-m4v',
};

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
