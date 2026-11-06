import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml_events.dart';

/// Eine Datei am Ziel ausser Haus.
class Zieldatei {
  const Zieldatei(this.groesse, this.geaendert);
  final int groesse;
  final DateTime? geaendert;
}

/// Ein Fehler des Ziels. [endgueltig]: Ein neuer Versuch ändert nichts,
/// etwa bei falschem Zugang oder vollem Speicher. Der Lauf hört dann auf,
/// statt tausend Dateien einzeln scheitern zu lassen.
class Zielfehler implements Exception {
  const Zielfehler(this.text, {this.endgueltig = false});
  final String text;
  final bool endgueltig;
  @override
  String toString() => text;
}

/// Wohin die fertig verschlüsselte Sicherung ausser Haus geht.
abstract interface class Aussenziel {
  /// Alles, was unter dem Ziel liegt, mit Pfaden relativ dazu.
  Future<Map<String, Zieldatei>> liste();

  /// Legt [groesse] Bytes aus [datei] unter [pfad] ab. [durch] sieht jedes
  /// Stück auf dem Weg, für die Drossel.
  Future<void> lege(
    String pfad,
    File datei, {
    required int groesse,
    Future<void> Function(int bytes)? durch,
  });

  Future<Uint8List> hole(String pfad);
  Future<void> loesche(String pfad);

  /// Räumt auf, was ein abgebrochener Lauf am Ziel hinterlassen hat.
  Future<void> aufraeumen();

  void schliesse();
}

/// Sendet eine Datei als Strom, ohne sie erst in den Speicher zu laden.
class _Stromanfrage extends http.BaseRequest {
  _Stromanfrage(super.method, super.url, this._strom, int laenge) {
    contentLength = laenge;
  }

  final Stream<List<int>> _strom;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_strom);
  }
}

Stream<List<int>> _gedrosselt(
  Stream<List<int>> strom,
  Future<void> Function(int bytes)? durch,
) => durch == null
    ? strom
    : strom.asyncMap((stueck) async {
        await durch(stueck.length);
        return stueck;
      });

/// Grosszügig, aber endlich: Ein Ziel, das mitten im Hochladen verstummt,
/// darf den Lauf nicht auf ewig festhalten.
Duration _frist(int bytes) =>
    const Duration(minutes: 5) + Duration(seconds: bytes ~/ (64 * 1024));

const _leererHash =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// Prozentkodierung nach RFC 3986, wie sie die Unterschrift verlangt.
String s3Kodiert(String text, {bool schraegstrich = false}) {
  final aus = StringBuffer();
  for (final b in utf8.encode(text)) {
    final erlaubt =
        (b >= 0x41 && b <= 0x5A) ||
        (b >= 0x61 && b <= 0x7A) ||
        (b >= 0x30 && b <= 0x39) ||
        b == 0x2D ||
        b == 0x2E ||
        b == 0x5F ||
        b == 0x7E ||
        (schraegstrich && b == 0x2F);
    if (erlaubt) {
      aus.writeCharCode(b);
    } else {
      aus.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return '$aus';
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int> _hmac(List<int> schluessel, String text) =>
    Hmac(sha256, schluessel).convert(utf8.encode(text)).bytes;

/// Die Kopfzeilen einer Anfrage mit Unterschrift nach AWS Signature
/// Version 4. Alle S3-Anbieter sprechen sie.
///
/// [pfad] ist schon kodiert. Gezeichnet werden `host`, `x-amz-*` und alles
/// aus [weitere]; die Reihenfolge der Abfrage regelt diese Funktion selbst.
Map<String, String> s3Kopf({
  required String methode,
  required String host,
  required String pfad,
  Map<String, String> abfrage = const {},
  required String region,
  required String zugang,
  required String geheimnis,
  required String nutzlast,
  required DateTime zeit,
  Map<String, String> weitere = const {},
}) {
  final z = zeit.toUtc();
  String zwei(int n) => n.toString().padLeft(2, '0');
  final tag = '${z.year}${zwei(z.month)}${zwei(z.day)}';
  final stempel = '${tag}T${zwei(z.hour)}${zwei(z.minute)}${zwei(z.second)}Z';
  final kopf = <String, String>{
    'host': host,
    'x-amz-content-sha256': nutzlast,
    'x-amz-date': stempel,
    for (final e in weitere.entries) e.key.toLowerCase(): e.value.trim(),
  };
  final namen = kopf.keys.toList()..sort();
  final gezeichnet = namen.join(';');
  final kanonisch = [
    methode,
    pfad,
    s3Abfrage(abfrage),
    for (final n in namen) '$n:${kopf[n]}',
    '',
    gezeichnet,
    nutzlast,
  ].join('\n');
  final bereich = '$tag/$region/s3/aws4_request';
  final zuZeichnen = [
    'AWS4-HMAC-SHA256',
    stempel,
    bereich,
    sha256.convert(utf8.encode(kanonisch)).toString(),
  ].join('\n');
  var k = _hmac(utf8.encode('AWS4$geheimnis'), tag);
  k = _hmac(k, region);
  k = _hmac(k, 's3');
  k = _hmac(k, 'aws4_request');
  final unterschrift = _hex(_hmac(k, zuZeichnen));
  return {
    ...kopf..remove('host'),
    'authorization':
        'AWS4-HMAC-SHA256 Credential=$zugang/$bereich,'
        'SignedHeaders=$gezeichnet,Signature=$unterschrift',
  };
}

String s3Abfrage(Map<String, String> abfrage) {
  final teile = [
    for (final e in abfrage.entries)
      '${s3Kodiert(e.key)}=${s3Kodiert(e.value)}',
  ]..sort();
  return teile.join('&');
}

/// Liest aus einer XML-Antwort alle Texte der [gesucht]en Elemente, je
/// [satz]-Element ein Eintrag. Über Ereignisse: Eine Liste kann Zehntausende
/// Einträge tragen, ein Baum davon kostete ein Vielfaches an Speicher.
List<Map<String, String>> _saetze(
  String xml,
  String satz,
  Set<String> gesucht,
) {
  final aus = <Map<String, String>>[];
  Map<String, String>? offen;
  String? feld;
  final text = StringBuffer();
  for (final e in parseEvents(xml)) {
    if (e is XmlStartElementEvent) {
      if (e.localName == satz) {
        offen = {};
        if (e.isSelfClosing) {
          aus.add(offen);
          offen = null;
        }
      } else if (offen != null && gesucht.contains(e.localName)) {
        if (e.isSelfClosing) {
          offen.putIfAbsent(e.localName, () => '');
        } else {
          feld = e.localName;
          text.clear();
        }
      }
    } else if (e is XmlTextEvent) {
      if (feld != null) text.write(e.value);
    } else if (e is XmlCDATAEvent) {
      if (feld != null) text.write(e.value);
    } else if (e is XmlEndElementEvent) {
      if (e.localName == feld) {
        offen?.putIfAbsent(feld!, () => '$text');
        feld = null;
      } else if (e.localName == satz && offen != null) {
        aus.add(offen);
        offen = null;
      }
    }
  }
  return aus;
}

/// Ein S3-Speicher: Amazon, Backblaze B2, Wasabi, Hetzner, Cloudflare R2,
/// MinIO. Dateien über [teilAb] gehen in Teilen, denn ein einzelnes `PUT`
/// endet bei 5 GB, und ein Abbruch kostete sonst die ganze Datei.
class S3Ziel implements Aussenziel {
  S3Ziel({
    required this.endpunkt,
    required this.bucket,
    required this.region,
    required this.zugang,
    required this.geheimnis,
    this.praefix = '',
    this.teilAb = 256 * 1024 * 1024,
    this.mindestTeil = 64 * 1024 * 1024,
    http.Client? client,
    DateTime Function()? uhr,
  }) : _client = client ?? http.Client(),
       _uhr = uhr ?? DateTime.now;

  final Uri endpunkt;
  final String bucket;
  final String region;
  final String zugang;
  final String geheimnis;
  final String praefix;
  final int teilAb;
  final int mindestTeil;
  final http.Client _client;
  final DateTime Function() _uhr;

  /// Amazon will den Bucket im Hostnamen, alle anderen nehmen ihn zuverlässig
  /// im Pfad, oft nur dort.
  bool get _imHost => endpunkt.host.endsWith('amazonaws.com');

  String get _host {
    final name = _imHost ? '$bucket.${endpunkt.host}' : endpunkt.host;
    return endpunkt.hasPort ? '$name:${endpunkt.port}' : name;
  }

  String _pfad(String schluessel) {
    final basis = endpunkt.path.endsWith('/')
        ? endpunkt.path.substring(0, endpunkt.path.length - 1)
        : endpunkt.path;
    final teil = _imHost ? '' : '/${s3Kodiert(bucket)}';
    return '$basis$teil/${s3Kodiert(schluessel, schraegstrich: true)}';
  }

  String _schluessel(String pfad) => praefix.isEmpty ? pfad : '$praefix/$pfad';

  Future<http.Response> _frag(
    String methode,
    String schluessel, {
    Map<String, String> abfrage = const {},
    Uint8List? inhalt,
    Duration frist = const Duration(minutes: 2),
  }) async {
    final pfad = _pfad(schluessel);
    final a = s3Abfrage(abfrage);
    final uri = Uri.parse(
      '${endpunkt.scheme}://$_host$pfad${a.isEmpty ? '' : '?$a'}',
    );
    final r = http.Request(methode, uri);
    r.headers.addAll(
      s3Kopf(
        methode: methode,
        host: _host,
        pfad: pfad,
        abfrage: abfrage,
        region: region,
        zugang: zugang,
        geheimnis: geheimnis,
        nutzlast: inhalt == null
            ? _leererHash
            : sha256.convert(inhalt).toString(),
        zeit: _uhr(),
      ),
    );
    if (inhalt != null) r.bodyBytes = inhalt;
    return http.Response.fromStream(
      await _client.send(r).timeout(frist),
    ).timeout(frist);
  }

  Future<http.StreamedResponse> _sende(
    String schluessel,
    Stream<List<int>> strom,
    int laenge, {
    Map<String, String> abfrage = const {},
  }) async {
    final pfad = _pfad(schluessel);
    final a = s3Abfrage(abfrage);
    final uri = Uri.parse(
      '${endpunkt.scheme}://$_host$pfad${a.isEmpty ? '' : '?$a'}',
    );
    final r = _Stromanfrage('PUT', uri, strom, laenge);
    r.headers.addAll(
      s3Kopf(
        methode: 'PUT',
        host: _host,
        pfad: pfad,
        abfrage: abfrage,
        region: region,
        zugang: zugang,
        geheimnis: geheimnis,
        // Über TLS sichert die Leitung den Inhalt; die Prüfsumme vorab
        // hiesse, jede Datei zweimal zu lesen.
        nutzlast: 'UNSIGNED-PAYLOAD',
        zeit: _uhr(),
      ),
    );
    return _client.send(r).timeout(_frist(laenge));
  }

  Zielfehler _fehler(int status, String text) {
    final code = RegExp(r'<Code>([^<]+)</Code>').firstMatch(text)?.group(1);
    final grund = code ?? 'HTTP $status';
    const endgueltig = {
      'AccessDenied',
      'InvalidAccessKeyId',
      'SignatureDoesNotMatch',
      'NoSuchBucket',
      'QuotaExceeded',
      'AccountProblem',
      'AllAccessDisabled',
      'InvalidBucketName',
      'RequestTimeTooSkewed',
    };
    return Zielfehler(
      'S3: $grund',
      endgueltig:
          status == 401 || status == 403 || endgueltig.contains(code ?? ''),
    );
  }

  http.Response _pruefe(http.Response r) {
    if (r.statusCode >= 300) throw _fehler(r.statusCode, r.body);
    return r;
  }

  @override
  Future<Map<String, Zieldatei>> liste() async {
    final aus = <String, Zieldatei>{};
    final vorn = praefix.isEmpty ? '' : '$praefix/';
    String? weiter;
    do {
      final r = _pruefe(
        await _frag(
          'GET',
          '',
          abfrage: {
            'list-type': '2',
            'prefix': vorn,
            'continuation-token': ?weiter,
          },
          frist: const Duration(minutes: 5),
        ),
      );
      final text = r.body;
      for (final s in _saetze(text, 'Contents', const {
        'Key',
        'Size',
        'LastModified',
      })) {
        final k = s['Key'] ?? '';
        if (!k.startsWith(vorn) || k.length == vorn.length) continue;
        aus[k.substring(vorn.length)] = Zieldatei(
          int.tryParse(s['Size'] ?? '') ?? -1,
          DateTime.tryParse(s['LastModified'] ?? ''),
        );
      }
      weiter = RegExp(
        r'<NextContinuationToken>([^<]+)</NextContinuationToken>',
      ).firstMatch(text)?.group(1);
      if (weiter != null) weiter = _xmlText(weiter);
    } while (weiter != null);
    return aus;
  }

  static String _xmlText(String roh) => roh
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  @override
  Future<void> lege(
    String pfad,
    File datei, {
    required int groesse,
    Future<void> Function(int bytes)? durch,
  }) async {
    final k = _schluessel(pfad);
    if (groesse >= teilAb) return _inTeilen(k, datei, groesse, durch);
    final r = await _sende(
      k,
      _gedrosselt(datei.openRead(0, groesse), durch),
      groesse,
    );
    final antwort = await http.Response.fromStream(r).timeout(_frist(0));
    _pruefe(antwort);
  }

  Future<void> _inTeilen(
    String k,
    File datei,
    int groesse,
    Future<void> Function(int bytes)? durch,
  ) async {
    // 10.000 Teile sind die Grenze aller Anbieter.
    var teil = mindestTeil;
    if (groesse ~/ teil >= 9000) teil = groesse ~/ 9000 + 1;
    final anfang = _pruefe(
      await _frag(
        'POST',
        k,
        abfrage: const {'uploads': ''},
        inhalt: Uint8List(0),
      ),
    );
    final kennung = RegExp(
      r'<UploadId>([^<]+)</UploadId>',
    ).firstMatch(anfang.body)?.group(1);
    if (kennung == null) throw const Zielfehler('S3: keine UploadId');
    final id = _xmlText(kennung);
    try {
      final marken = <String>[];
      var nummer = 1;
      for (var von = 0; von < groesse; von += teil, nummer++) {
        final bis = von + teil < groesse ? von + teil : groesse;
        final r = await _sende(
          k,
          _gedrosselt(datei.openRead(von, bis), durch),
          bis - von,
          abfrage: {'partNumber': '$nummer', 'uploadId': id},
        );
        final antwort = _pruefe(
          await http.Response.fromStream(r).timeout(_frist(0)),
        );
        final etag = antwort.headers['etag'];
        if (etag == null) throw const Zielfehler('S3: Teil ohne ETag');
        marken.add(etag);
      }
      final liste = StringBuffer('<CompleteMultipartUpload>');
      for (var i = 0; i < marken.length; i++) {
        final e = marken[i].replaceAll('"', '&quot;');
        liste.write(
          '<Part><PartNumber>${i + 1}</PartNumber><ETag>$e</ETag></Part>',
        );
      }
      liste.write('</CompleteMultipartUpload>');
      final fertig = await _frag(
        'POST',
        k,
        abfrage: {'uploadId': id},
        inhalt: utf8.encode('$liste'),
        frist: const Duration(minutes: 15),
      );
      // Auch mit 200 kann hier ein Fehler stehen: Die Antwort kommt, bevor
      // der Anbieter die Teile zusammengesetzt hat.
      if (fertig.statusCode >= 300 || fertig.body.contains('<Error>')) {
        throw _fehler(fertig.statusCode, fertig.body);
      }
    } catch (_) {
      try {
        await _frag('DELETE', k, abfrage: {'uploadId': id});
      } on Object {
        // Bleibt liegen, [aufraeumen] holt es beim nächsten Lauf.
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List> hole(String pfad) async {
    final r = _pruefe(
      await _frag('GET', _schluessel(pfad), frist: const Duration(minutes: 15)),
    );
    return r.bodyBytes;
  }

  @override
  Future<void> loesche(String pfad) async {
    _pruefe(await _frag('DELETE', _schluessel(pfad)));
  }

  /// Abgebrochene Teil-Uploads sind unsichtbar, kosten aber Speicher.
  @override
  Future<void> aufraeumen() async {
    final http.Response r;
    try {
      r = await _frag(
        'GET',
        '',
        abfrage: {'uploads': '', if (praefix.isNotEmpty) 'prefix': '$praefix/'},
      );
    } on TimeoutException {
      return;
    }
    // Nicht jeder Anbieter kann das; am Hochladen ändert es nichts.
    if (r.statusCode >= 300) return;
    for (final s in _saetze(r.body, 'Upload', const {'Key', 'UploadId'})) {
      final k = s['Key'], id = s['UploadId'];
      if (k == null || id == null) continue;
      await _frag('DELETE', k, abfrage: {'uploadId': id});
    }
  }

  @override
  void schliesse() => _client.close();
}

/// Ein WebDAV-Speicher: Nextcloud, Synology, Hetzner Storage Box.
///
/// Anmeldung über Basic: Darum nimmt [AussenzielAngabe] für fremde Rechner
/// nur `https`.
class WebdavZiel implements Aussenziel {
  WebdavZiel({
    required Uri adresse,
    required String benutzer,
    required String passwort,
    this.praefix = '',
    http.Client? client,
  }) : adresse = adresse.path.endsWith('/')
           ? adresse
           : adresse.replace(path: '${adresse.path}/'),
       _anmeldung =
           'Basic ${base64.encode(utf8.encode('$benutzer:$passwort'))}',
       _client = client ?? http.Client();

  final Uri adresse;
  final String praefix;
  final String _anmeldung;
  final http.Client _client;
  final _ordnerDa = <String>{};
  final _ordnerImBau = <String, Future<void>>{};

  static const _abfrage =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<D:propfind xmlns:D="DAV:"><D:prop>'
      '<D:resourcetype/><D:getcontentlength/><D:getlastmodified/>'
      '</D:prop></D:propfind>';

  String _kodiert(String pfad) =>
      pfad.split('/').map(Uri.encodeComponent).join('/');

  Uri _uri(String pfad, {bool ordner = false}) {
    final voll = [
      if (praefix.isNotEmpty) praefix,
      if (pfad.isNotEmpty) pfad,
    ].join('/');
    final hinten = ordner && voll.isNotEmpty ? '/' : '';
    return Uri.parse('$adresse${_kodiert(voll)}$hinten');
  }

  Future<http.Response> _frag(
    String methode,
    Uri uri, {
    Map<String, String> kopf = const {},
    String? inhalt,
    Duration frist = const Duration(minutes: 2),
  }) async {
    final r = http.Request(methode, uri)
      ..headers['authorization'] = _anmeldung
      ..headers.addAll(kopf);
    if (inhalt != null) {
      r.bodyBytes = utf8.encode(inhalt);
      r.headers['content-type'] = 'application/xml; charset=utf-8';
    }
    return http.Response.fromStream(
      await _client.send(r).timeout(frist),
    ).timeout(frist);
  }

  Zielfehler _fehler(int status) => Zielfehler(
    'WebDAV: HTTP $status',
    endgueltig: status == 401 || status == 403 || status == 507,
  );

  http.Response _pruefe(http.Response r) {
    if (r.statusCode >= 300) throw _fehler(r.statusCode);
    return r;
  }

  @override
  Future<Map<String, Zieldatei>> liste() async {
    final aus = <String, Zieldatei>{};
    final offen = <String>[''];
    await _legeOrdner(praefix);
    // Schritt für Schritt: `Depth: infinity` schalten viele Server ab.
    while (offen.isNotEmpty) {
      final ordner = offen.removeLast();
      final uri = _uri(ordner, ordner: true);
      final r = await _frag(
        'PROPFIND',
        uri,
        kopf: const {'depth': '1'},
        inhalt: _abfrage,
        frist: const Duration(minutes: 10),
      );
      if (r.statusCode == 404) continue;
      if (r.statusCode != 207) throw _fehler(r.statusCode);
      for (final s in _saetze(utf8.decode(r.bodyBytes), 'response', const {
        'href',
        'getcontentlength',
        'getlastmodified',
        'collection',
      })) {
        final href = s['href'];
        if (href == null) continue;
        final istOrdner = s.containsKey('collection') || href.endsWith('/');
        final pfad = _relativ(href);
        if (pfad == null || pfad.isEmpty || pfad == ordner) continue;
        if (istOrdner) {
          offen.add(pfad);
          _ordnerDa.add(praefix.isEmpty ? pfad : '$praefix/$pfad');
        } else {
          aus[pfad] = Zieldatei(
            int.tryParse(s['getcontentlength'] ?? '') ?? -1,
            _webdavDatum(s['getlastmodified']),
          );
        }
      }
    }
    return aus;
  }

  /// [href] relativ zum Ziel; `null`, wenn es ausserhalb liegt.
  String? _relativ(String href) {
    final Uri u;
    try {
      u = Uri.parse(href);
    } on FormatException {
      return null;
    }
    final pfad = Uri.decodeComponent(u.path);
    final wurzel = Uri.decodeComponent(_uri('', ordner: true).path);
    final mit = wurzel.endsWith('/') ? wurzel : '$wurzel/';
    final ganz = pfad.endsWith('/') ? pfad : '$pfad/';
    if (ganz == mit) return '';
    if (!pfad.startsWith(mit)) return null;
    final rest = pfad.substring(mit.length);
    return rest.endsWith('/') ? rest.substring(0, rest.length - 1) : rest;
  }

  static DateTime? _webdavDatum(String? text) {
    if (text == null) return null;
    try {
      return HttpDate.parse(text);
    } on FormatException {
      return null;
    } on HttpException {
      return null;
    }
  }

  Future<void> _legeOrdner(String pfad) async {
    if (pfad.isEmpty) return;
    final teile = pfad.split('/');
    for (var i = 1; i <= teile.length; i++) {
      final ordner = teile.take(i).join('/');
      if (_ordnerDa.contains(ordner)) continue;
      // Je Ordner nur einmal: Mehrere Übertragungen wollen denselben, und
      // Apache antwortet dem zweiten gleichzeitigen MKCOL mit 403. Das sähe
      // aus wie ein falscher Zugang und beendete den ganzen Lauf.
      await (_ordnerImBau[ordner] ??= _bauOrdner(ordner).whenComplete(() {
        // Ohne Rückgabewert: `remove` liefert genau diesen Future, und
        // `whenComplete` wartete dann auf sich selbst.
        _ordnerImBau.remove(ordner);
      }));
    }
  }

  Future<void> _bauOrdner(String ordner) async {
    final uri = Uri.parse('$adresse${_kodiert(ordner)}/');
    final r = await _frag('MKCOL', uri);
    // 405: gibt es schon. 301: dasselbe bei manchen Servern.
    if (r.statusCode >= 300 && r.statusCode != 405 && r.statusCode != 301) {
      // Nicht jeder Server sagt 405. Ob er wirklich fehlt, sagt die Nachfrage.
      final da = await _frag(
        'PROPFIND',
        uri,
        kopf: const {'depth': '0'},
        inhalt: _abfrage,
      );
      if (da.statusCode != 207) throw _fehler(r.statusCode);
    }
    _ordnerDa.add(ordner);
  }

  @override
  Future<void> lege(
    String pfad,
    File datei, {
    required int groesse,
    Future<void> Function(int bytes)? durch,
  }) async {
    // Auch der Ordner des Ziels selbst: Beim ersten Einrichten fehlt er noch.
    final schnitt = pfad.lastIndexOf('/');
    await _legeOrdner(
      [
        if (praefix.isNotEmpty) praefix,
        if (schnitt > 0) pfad.substring(0, schnitt),
      ].join('/'),
    );
    final r = _Stromanfrage(
      'PUT',
      _uri(pfad),
      _gedrosselt(datei.openRead(0, groesse), durch),
      groesse,
    )..headers['authorization'] = _anmeldung;
    final antwort = await http.Response.fromStream(
      await _client.send(r).timeout(_frist(groesse)),
    ).timeout(_frist(0));
    _pruefe(antwort);
  }

  @override
  Future<Uint8List> hole(String pfad) async {
    final r = _pruefe(
      await _frag('GET', _uri(pfad), frist: const Duration(minutes: 15)),
    );
    return r.bodyBytes;
  }

  @override
  Future<void> loesche(String pfad) async {
    final r = await _frag('DELETE', _uri(pfad));
    if (r.statusCode != 404) _pruefe(r);
  }

  @override
  Future<void> aufraeumen() async {}

  @override
  void schliesse() => _client.close();
}
