import 'dart:io';

import 'package:shelf/shelf.dart';

/// Text geht gepackt hinaus, wenn die Gegenseite es annimmt.
///
/// **`autoCompress` am Server reichte nicht.** dart:io packt nur Antworten
/// ohne bekannte Länge, und shelf nennt die Länge jeder Antwort aus Text
/// oder Bytes – gepackt wurde also nie etwas: app.js ging mit 85 KB über
/// die Leitung statt mit gut 20, die Zeitleiste mit ihren 200 Einträgen
/// je Seite ebenso ungepackt. Die Telefon-App nimmt gzip von sich aus an
/// (dart:io), ihr Abgleich wird dadurch ebenso kleiner.
///
/// Nicht gepackt: Bilder, Videos und die Datenbank (packen kaum oder
/// brauchen ihre Länge), alles unter 1 KB, Fehlerantworten und was ein
/// Cookie setzt. Letzteres, weil gepackte Antworten mit Geheimnissen darin
/// der Ansatz für BREACH sind; die Anmeldeantworten sind ohnehin klein.
Middleware get packen =>
    (innerer) => (anfrage) async {
      final antwort = await innerer(anfrage);
      final laenge = antwort.contentLength;
      if (antwort.statusCode != 200 ||
          (laenge != null && laenge < 1024) ||
          antwort.headers.containsKey('content-encoding') ||
          antwort.headers.containsKey('set-cookie') ||
          !_packbar(antwort.mimeType) ||
          !(anfrage.headers['accept-encoding'] ?? '')
              .split(',')
              .any((e) => e.trim().split(';').first.toLowerCase() == 'gzip')) {
        return antwort;
      }
      final etag = antwort.headers['etag'];
      return antwort.change(
        body: antwort.read().transform(gzip.encoder),
        headers: {
          'content-encoding': 'gzip',
          'content-length': null,
          'vary': 'accept-encoding',
          // Eine andere Darstellung braucht ein anderes Etikett; wer es
          // zurückschickt, bekommt trotzdem sein 304 (siehe [etagPasst]).
          if (etag != null && etag.endsWith('"'))
            'etag': '${etag.substring(0, etag.length - 1)}-gz"',
        },
      );
    };

bool _packbar(String? typ) =>
    typ != null &&
    (typ.startsWith('text/') ||
        typ == 'application/json' ||
        typ == 'application/manifest+json' ||
        typ == 'image/svg+xml' ||
        typ == 'font/ttf');

/// Ob `If-None-Match` das Etikett [etag] nennt – auch in der gepackten
/// Fassung aus [packen].
bool etagPasst(Request anfrage, String etag) {
  final gesendet = anfrage.headers['if-none-match'];
  return gesendet != null && gesendet.replaceAll('-gz"', '"') == etag;
}
