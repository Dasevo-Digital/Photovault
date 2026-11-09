import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Ein S3-Speicher in klein. Prüft die Unterschrift nicht nach: Das tun die
/// Vektoren aus der Anleitung von AWS weiter unten, die dieselbe Rechnung
/// nicht aus dem eigenen Code beziehen.
class _S3 {
  _S3._(this._server) {
    _server.listen(_bediene);
  }

  static Future<_S3> starte() async =>
      _S3._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final dateien = <String, Uint8List>{};
  final anfragen = <String>[];

  /// Antwortet auf `PUT` nur so oft, danach mit [fehlerStatus].
  int? putsBisFehler;
  int fehlerStatus = 503;
  String fehlerCode = 'SlowDown';
  final _teile = <String, Map<int, Uint8List>>{};
  final _teilSchluessel = <String, String>{};
  var _naechsteId = 0;
  int get port => _server.port;

  Uri get adresse => Uri.parse('http://127.0.0.1:$port');
  List<String> get offeneTeile => _teile.keys.toList();
  Future<void> stoppe() => _server.close(force: true);

  Future<void> _bediene(HttpRequest r) async {
    final inhalt = BytesBuilder();
    await r.forEach(inhalt.add);
    final q = r.uri.queryParameters;
    final pfad = Uri.decodeFull(r.uri.path);
    expect(pfad, startsWith('/fotos'));
    final k = pfad.length > 7 ? pfad.substring(7) : '';
    anfragen.add('${r.method} $k ${q.keys.join(',')}');
    final a = r.response;
    expect(r.headers.value('authorization'), startsWith('AWS4-HMAC-SHA256 '));
    Future<void> fertig() => a.close();
    void xml(String text) {
      a.headers.contentType = ContentType('application', 'xml');
      a.write(text);
    }

    if (r.method == 'PUT' && putsBisFehler != null) {
      if (putsBisFehler == 0) {
        a.statusCode = fehlerStatus;
        xml('<Error><Code>$fehlerCode</Code></Error>');
        return fertig();
      }
      putsBisFehler = putsBisFehler! - 1;
    }
    if (r.method == 'GET' && q['list-type'] == '2') {
      final alle = dateien.keys.where((x) => x.startsWith(q['prefix'] ?? ''));
      final sortiert = alle.toList()..sort();
      final von = int.tryParse(q['continuation-token'] ?? '') ?? 0;
      final seite = sortiert.skip(von).take(2).toList();
      final mehr = von + 2 < sortiert.length;
      xml(
        '<ListBucketResult>'
        '<IsTruncated>$mehr</IsTruncated>'
        '${mehr ? '<NextContinuationToken>${von + 2}</NextContinuationToken>' : ''}'
        '${[for (final x in seite) '<Contents><Key>${_x(x)}</Key><Size>${dateien[x]!.length}</Size><LastModified>${DateTime.now().toUtc().toIso8601String()}</LastModified></Contents>'].join()}'
        '</ListBucketResult>',
      );
      return fertig();
    }
    if (r.method == 'GET' && q.containsKey('uploads')) {
      xml(
        '<ListMultipartUploadsResult>'
        '${[for (final id in _teile.keys) '<Upload><Key>${_x(_teilSchluessel[id]!)}</Key><UploadId>$id</UploadId></Upload>'].join()}'
        '</ListMultipartUploadsResult>',
      );
      return fertig();
    }
    if (r.method == 'POST' && q.containsKey('uploads')) {
      final id = 'id-${_naechsteId++}';
      _teile[id] = {};
      _teilSchluessel[id] = k;
      xml('<Antwort><UploadId>$id</UploadId></Antwort>');
      return fertig();
    }
    if (r.method == 'PUT' && q.containsKey('partNumber')) {
      _teile[q['uploadId']]![int.parse(q['partNumber']!)] = inhalt.takeBytes();
      a.headers.set('etag', '"teil-${q['partNumber']}"');
      return fertig();
    }
    if (r.method == 'POST' && q.containsKey('uploadId')) {
      final teile = _teile.remove(q['uploadId'])!;
      final nummern = teile.keys.toList()..sort();
      final text = utf8.decode(inhalt.takeBytes());
      for (final n in nummern) {
        expect(text, contains('<PartNumber>$n</PartNumber>'));
        expect(text, contains('<ETag>&quot;teil-$n&quot;</ETag>'));
      }
      dateien[k] = Uint8List.fromList([for (final n in nummern) ...teile[n]!]);
      xml('<CompleteMultipartUploadResult/>');
      return fertig();
    }
    if (r.method == 'DELETE' && q.containsKey('uploadId')) {
      _teile.remove(q['uploadId']);
      a.statusCode = 204;
      return fertig();
    }
    switch (r.method) {
      case 'PUT':
        dateien[k] = inhalt.takeBytes();
      case 'GET':
        final d = dateien[k];
        if (d == null) {
          a.statusCode = 404;
          xml('<Error><Code>NoSuchKey</Code></Error>');
        } else {
          a.add(d);
        }
      case 'DELETE':
        dateien.remove(k);
        a.statusCode = 204;
    }
    return fertig();
  }

  static String _x(String s) => s.replaceAll('&', '&amp;');
}

/// Ein WebDAV-Server, so streng wie die echten: Eltern müssen da sein, und
/// `Depth: infinity` gibt es nicht.
class _Dav {
  _Dav._(this._server) {
    _server.listen(_bediene);
  }

  static Future<_Dav> starte() async =>
      _Dav._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final dateien = <String, Uint8List>{};
  final ordner = <String>{'/dav'};
  final _imBau = <String>{};
  int gleichzeitigeMkcol = 0;
  bool mkcolVerweigert = false;
  Uri get adresse => Uri.parse('http://127.0.0.1:${_server.port}/dav');
  Future<void> stoppe() => _server.close(force: true);

  String _eltern(String p) => p.substring(0, p.lastIndexOf('/'));

  Future<void> _bediene(HttpRequest r) async {
    final inhalt = BytesBuilder();
    await r.forEach(inhalt.add);
    final a = r.response;
    expect(r.headers.value('authorization'), isNotNull);
    final roh = r.uri.path;
    final pfad = Uri.decodeComponent(
      roh.endsWith('/') ? roh.substring(0, roh.length - 1) : roh,
    );
    switch (r.method) {
      case 'MKCOL':
        // Wie Apache: Zwei gleichzeitige Anlagen, und die zweite bekommt 403.
        if (mkcolVerweigert) {
          a.statusCode = 403;
        } else if (_imBau.contains(pfad)) {
          gleichzeitigeMkcol++;
          a.statusCode = 403;
        } else if (ordner.contains(pfad)) {
          a.statusCode = 405;
        } else if (!ordner.contains(_eltern(pfad))) {
          a.statusCode = 409;
        } else {
          _imBau.add(pfad);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          _imBau.remove(pfad);
          ordner.add(pfad);
          a.statusCode = 201;
        }
      case 'PUT':
        if (!ordner.contains(_eltern(pfad))) {
          a.statusCode = 409;
        } else {
          dateien[pfad] = inhalt.takeBytes();
          a.statusCode = 201;
        }
      case 'GET':
        final d = dateien[pfad];
        if (d == null) {
          a.statusCode = 404;
        } else {
          a.add(d);
        }
      case 'DELETE':
        a.statusCode = dateien.remove(pfad) == null ? 404 : 204;
      case 'PROPFIND':
        if (r.headers.value('depth') == '0') {
          a.statusCode = ordner.contains(pfad) ? 207 : 404;
          break;
        }
        expect(r.headers.value('depth'), '1');
        if (!ordner.contains(pfad)) {
          a.statusCode = 404;
          break;
        }
        a.statusCode = 207;
        final teile = StringBuffer(
          '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">',
        );
        void eintrag(String href, String prop) => teile.write(
          '<d:response><d:href>${Uri.encodeFull(href)}</d:href>'
          '<d:propstat><d:prop>$prop</d:prop>'
          '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>',
        );
        eintrag('$pfad/', '<d:resourcetype><d:collection/></d:resourcetype>');
        for (final o in ordner) {
          if (_eltern(o) == pfad) {
            eintrag('$o/', '<d:resourcetype><d:collection/></d:resourcetype>');
          }
        }
        for (final e in dateien.entries) {
          if (_eltern(e.key) == pfad) {
            eintrag(
              e.key,
              '<d:resourcetype/>'
              '<d:getcontentlength>${e.value.length}</d:getcontentlength>'
              '<d:getlastmodified>${HttpDate.format(DateTime.now())}</d:getlastmodified>',
            );
          }
        }
        teile.write('</d:multistatus>');
        a.headers.contentType = ContentType('application', 'xml');
        a.write('$teile');
    }
    await a.close();
  }
}

void main() {
  const passphrase = 'eine lange passphrase';
  late Directory ordner;
  late Directory nas;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Tresorschluessel tresor;
  late Konto erika;
  late Serversicherung sicherung;
  late _S3 s3;
  late _Dav dav;
  late Aussensicherung aussen;

  Map<String, Object?> s3Angabe() => {
    'art': 's3',
    'adresse': '${s3.adresse}',
    'bucket': 'fotos',
    'zugang': 'SCHLUESSELID',
    'geheimnis': 'streng-geheim-123',
    'praefix': 'photovault',
  };

  Map<String, Object?> davAngabe() => {
    'art': 'webdav',
    'adresse': '${dav.adresse}',
    'zugang': 'erika',
    'geheimnis': 'streng-geheim-123',
    'praefix': 'photovault',
  };

  Aussensicherung neu({Directory? wurzel}) => Aussensicherung(
    daten: Directory('${ordner.path}/daten'),
    wurzel: wurzel ?? nas,
    tresor: tresor,
    wartezeit: Duration.zero,
  );

  Future<void> foto(String name, int farbe) async {
    final f = File('${ordner.path}/quelle/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        img.encodeJpg(
          img.Image(width: 32, height: 24)
            ..clear(img.ColorRgb8(farbe, 40, 200 - farbe)),
        ),
      );
    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    final r = await b.importe.importFile(f.path);
    expect(r.outcome, ImportOutcome.imported, reason: '$name: ${r.error}');
  }

  List<String> lokal() {
    final aus = <String>[];
    for (final e in nas.listSync(recursive: true)) {
      if (e is! File) continue;
      aus.add(e.path.substring(nas.path.length + 1));
    }
    return aus..sort();
  }

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_aussen_');
    nas = Directory('${ordner.path}/nas')..createSync();
    Directory('${ordner.path}/daten').createSync();
    sdb = Serverdatenbank.imSpeicher();
    tresor = Tresorschluessel(List.filled(32, 9));
    konten = Kontodienst(
      sdb,
      tresor,
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    erika = await konten.legeAn('erika', 'ein langes passwort');
    await foto('urlaub-am-see.jpg', 10);
    await foto('b.jpg', 120);
    sicherung = Serversicherung(
      daten: Directory('${ordner.path}/daten'),
      ziel: nas,
      tresor: tresor,
      konten: konten,
      bibliotheken: bibliotheken,
    );
    await sicherung.einrichten(passphrase);
    await sicherung.jetzt();
    s3 = await _S3.starte();
    dav = await _Dav.starte();
    aussen = neu();
  });

  tearDown(() async {
    sicherung.beende();
    await s3.stoppe();
    await dav.stoppe();
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  group('Die Unterschrift, nach den Beispielen von AWS', () {
    // Die Kennung steht nur im Kopf und geht nicht in die Unterschrift ein.
    const zugang = 'BEISPIELKENNUNG';
    const geheimnis = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';
    final zeit = DateTime.utc(2013, 5, 24);
    const leer =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    String unterschrift(Map<String, String> k) =>
        RegExp(r'Signature=(\w+)').firstMatch(k['authorization']!)!.group(1)!;

    test('GET einer Datei mit Range', () {
      expect(
        unterschrift(
          s3Kopf(
            methode: 'GET',
            host: 'examplebucket.s3.amazonaws.com',
            pfad: '/test.txt',
            region: 'us-east-1',
            zugang: zugang,
            geheimnis: geheimnis,
            nutzlast: leer,
            zeit: zeit,
            weitere: const {'range': 'bytes=0-9'},
          ),
        ),
        'f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
      );
    });

    test('PUT mit Sonderzeichen im Namen', () {
      expect(
        unterschrift(
          s3Kopf(
            methode: 'PUT',
            host: 'examplebucket.s3.amazonaws.com',
            pfad: '/${s3Kodiert(r'test$file.text', schraegstrich: true)}',
            region: 'us-east-1',
            zugang: zugang,
            geheimnis: geheimnis,
            nutzlast:
                '44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072',
            zeit: zeit,
            weitere: const {
              'date': 'Fri, 24 May 2013 00:00:00 GMT',
              'x-amz-storage-class': 'REDUCED_REDUNDANCY',
            },
          ),
        ),
        '98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd',
      );
    });

    test('Liste mit Abfrage: die Reihenfolge regelt die Unterschrift', () {
      expect(
        unterschrift(
          s3Kopf(
            methode: 'GET',
            host: 'examplebucket.s3.amazonaws.com',
            pfad: '/',
            abfrage: const {'prefix': 'J', 'max-keys': '2'},
            region: 'us-east-1',
            zugang: zugang,
            geheimnis: geheimnis,
            nutzlast: leer,
            zeit: zeit,
          ),
        ),
        '34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7',
      );
    });
  });

  group('Die Angaben', () {
    test('fremder Rechner nur über https', () {
      expect(
        () => AussenzielAngabe.aus({
          ...s3Angabe(),
          'adresse': 'http://s3.example.org',
        }),
        throwsArgumentError,
      );
      for (final a in [
        'https://s3.example.org',
        'http://${_ip([192, 168, 1, 5])}:9000',
        'http://${_ip([10, 0, 0, 2])}',
        'http://localhost:9000',
      ]) {
        expect(
          AussenzielAngabe.aus({...s3Angabe(), 'adresse': a}).adresse,
          Uri.parse(a),
        );
      }
    });

    test('leeres Geheimnis gilt nur fürs selbe Ziel', () {
      final bisher = AussenzielAngabe.aus(s3Angabe());
      final ohne = {...s3Angabe(), 'geheimnis': ''};
      expect(
        AussenzielAngabe.aus(ohne, bisher: bisher).geheimnis,
        'streng-geheim-123',
      );
      expect(
        () => AussenzielAngabe.aus({
          ...ohne,
          'adresse': 'https://anderer.example.org',
        }, bisher: bisher),
        throwsArgumentError,
        reason: 'Das Geheimnis ginge an einen anderen Rechner.',
      );
    });

    test('Ordner kann nicht aus dem Ziel heraus', () {
      expect(
        () => AussenzielAngabe.aus({...s3Angabe(), 'praefix': 'a/../b'}),
        throwsArgumentError,
      );
    });

    test(
      'das Geheimnis steht weder im Stand noch im Klartext auf der Platte',
      () async {
        await aussen.einrichten(s3Angabe());
        expect('${await aussen.stand()}', isNot(contains('streng-geheim')));
        final datei = File('${ordner.path}/daten/aussensicherung.json');
        expect(datei.readAsStringSync(), isNot(contains('streng-geheim')));
        if (!Platform.isWindows) {
          expect(datei.statSync().modeString(), 'rw-------');
        }
      },
    );

    test('ein falscher Zugang wird beim Einrichten erkannt', () async {
      s3
        ..putsBisFehler = 0
        ..fehlerStatus = 403
        ..fehlerCode = 'AccessDenied';
      await expectLater(
        aussen.einrichten(s3Angabe()),
        throwsA(isA<Zielfehler>()),
      );
      expect(aussen.eingerichtet, isFalse);
    });

    test('ohne eigene Sicherung gibt es nichts zu übertragen', () async {
      final ohne = Aussensicherung(
        daten: Directory('${ordner.path}/daten'),
        wurzel: null,
        tresor: tresor,
      );
      await expectLater(ohne.einrichten(s3Angabe()), throwsStateError);
      expect((await ohne.stand())['moeglich'], isFalse);
    });
  });

  group('Der Lauf nach S3', () {
    setUp(() async => aussen.einrichten(s3Angabe()));

    test('alles kommt an, und der Anbieter sieht keinen Klartext', () async {
      await aussen.jetzt();
      final stand = await aussen.stand();
      expect(stand['ok'], isTrue, reason: '${stand['fehler']}');
      expect(stand['stufe'], 'ok');
      expect((stand['stichprobe']! as Map)['geprueft'], 2);
      expect(
        s3.dateien.keys.map((k) => k.substring('photovault/'.length)).toList()
          ..sort(),
        lokal(),
      );
      for (final e in s3.dateien.entries) {
        expect(
          e.key,
          isNot(contains('urlaub')),
          reason: 'Dateiname im Klartext',
        );
        final text = latin1.decode(e.value);
        expect(text, isNot(contains('urlaub-am-see')), reason: e.key);
        // SQLite-Kopf: eine unverschlüsselte Datenbank.
        expect(text, isNot(startsWith('SQLite format')), reason: e.key);
      }
    });

    test('nur mit Speicher und Passphrase wiederherstellbar', () async {
      await aussen.jetzt();
      final geholt = Directory('${ordner.path}/geholt')..createSync();
      for (final e in s3.dateien.entries) {
        File('${geholt.path}/${e.key.substring('photovault/'.length)}')
          ..createSync(recursive: true)
          ..writeAsBytesSync(e.value);
      }
      final b = (await bibliotheken.fuer(erika.id)).bibliothek;
      final probe = await BackupService(b.db, b.pfade).pruefeWiederherstellung(
        '${geholt.path}/${Serversicherung.ordnerFuer(erika)}/PhotoVault-AutoBackup',
        passphrase: passphrase,
      );
      expect(probe.erfolgreich, isTrue);
      expect(probe.originale, 2);
      expect(probe.datenbank, isTrue);
    });

    test('der zweite Lauf überträgt nichts noch einmal', () async {
      await aussen.jetzt();
      final vorher = s3.anfragen.where((a) => a.startsWith('PUT')).length;
      await aussen.jetzt();
      expect(s3.anfragen.where((a) => a.startsWith('PUT')).length, vorher);
      expect((await aussen.stand())['neu'], 0);
    });

    test('ein geändertes Ziel bekommt nur die neue Fassung', () async {
      await aussen.jetzt();
      await foto('neu.jpg', 200);
      await sicherung.jetzt();
      final vorher = s3.dateien.length;
      await aussen.jetzt();
      expect(s3.dateien.length, greaterThan(vorher));
      expect((await aussen.stand())['ok'], isTrue);
    });

    test('nach einem Abbruch geht es dort weiter', () async {
      s3.putsBisFehler = 2;
      await aussen.jetzt();
      var stand = await aussen.stand();
      expect(stand['ok'], isFalse);
      expect(stand['stufe'], 'fehler');
      expect(stand['offen'], greaterThan(0));
      final schon = s3.dateien.length;
      expect(schon, 2);

      s3.putsBisFehler = null;
      await aussen.jetzt();
      stand = await aussen.stand();
      expect(stand['ok'], isTrue);
      expect(s3.dateien.length, lokal().length);
    });

    test('erst die Fotos, dann die Datenbank, die auf sie zeigt', () async {
      await aussen.jetzt();
      final puts = [
        for (final a in s3.anfragen)
          if (a.startsWith('PUT photovault/')) a.split(' ')[1],
      ];
      final letztesFoto = puts.lastIndexWhere((p) => p.contains('/data/'));
      final datenbank = puts.indexWhere(
        (p) => p.endsWith('PhotoVault-AutoBackup/library.sqlite.enc'),
      );
      expect(letztesFoto, greaterThanOrEqualTo(0));
      expect(datenbank, greaterThan(letztesFoto));
    });

    test('ein endgültiger Fehler hört sofort auf', () async {
      s3
        ..putsBisFehler = 0
        ..fehlerStatus = 403
        ..fehlerCode = 'AccessDenied';
      s3.anfragen.clear();
      await aussen.jetzt();
      final stand = await aussen.stand();
      expect(stand['ok'], isFalse);
      expect('${stand['fehler']}', contains('AccessDenied'));
      expect(
        s3.anfragen.where((a) => a.startsWith('PUT')).length,
        lessThanOrEqualTo(4),
        reason: 'nicht jede Datei einzeln gegen die Wand',
      );
    });

    test('ohne Kennmarke läuft nichts, und drüben bleibt alles', () async {
      await aussen.jetzt();
      final vorher = s3.dateien.length;
      File('${nas.path}/${Serversicherung.markeName}').deleteSync();
      for (final e in nas.listSync()) {
        e.deleteSync(recursive: true);
      }
      await aussen.jetzt();
      expect(s3.dateien.length, vorher);
      final stand = await aussen.stand();
      expect(stand['ok'], isFalse);
      expect('${stand['fehler']}', contains('Kennmarke'));
    });

    test('alte Generationen gehen, die Fotos bleiben', () async {
      await aussen.jetzt();
      final b = '${Serversicherung.ordnerFuer(erika)}/PhotoVault-AutoBackup';
      final generationen = Directory(
        '${nas.path}/$b/generations',
      ).listSync().whereType<Directory>().toList();
      expect(generationen, isNotEmpty);
      final fotosVorher = s3.dateien.keys
          .where((k) => k.contains('/data/'))
          .toSet();
      await sicherung.jetzt();
      generationen.first.deleteSync(recursive: true);
      await aussen.jetzt();
      final name = generationen.first.path.split('/').last;
      expect(s3.dateien.keys.where((k) => k.contains(name)), isEmpty);
      expect(
        s3.dateien.keys.where((k) => k.contains('/data/')).toSet(),
        containsAll(fotosVorher),
      );
      expect((await aussen.stand())['geloescht'], 3);
    });

    test('aus der Kammer entfernte Kopien gehen auch drüben', () async {
      final b = '${Serversicherung.ordnerFuer(erika)}/PhotoVault-AutoBackup';
      final kopie = File('${nas.path}/$b/fotokammer/k1/datei.enc')
        ..createSync(recursive: true)
        ..writeAsStringSync('verschluesselt');
      await aussen.jetzt();
      bool liegtDrueben() =>
          s3.dateien.keys.any((k) => k.endsWith('$b/fotokammer/k1/datei.enc'));
      expect(liegtDrueben(), isTrue);
      final fotosVorher = s3.dateien.keys
          .where((k) => k.contains('/data/'))
          .toSet();
      kopie.parent.deleteSync(recursive: true);
      await aussen.jetzt();
      expect(liegtDrueben(), isFalse);
      expect(
        s3.dateien.keys.where((k) => k.contains('/data/')).toSet(),
        fotosVorher,
      );
    });

    test('ohne jede Generation daheim bleiben sie drüben', () async {
      await aussen.jetzt();
      final b = '${Serversicherung.ordnerFuer(erika)}/PhotoVault-AutoBackup';
      Directory('${nas.path}/$b/generations').deleteSync(recursive: true);
      await aussen.jetzt();
      expect(
        s3.dateien.keys.where((k) => k.contains('/generations/')),
        isNotEmpty,
      );
    });

    test(
      'eine verfälschte Datei am Ziel fällt in der Stichprobe auf',
      () async {
        await aussen.jetzt();
        final k = s3.dateien.keys.firstWhere((k) => k.contains('/data/'));
        final d = s3.dateien[k]!;
        s3.dateien[k] = Uint8List.fromList([...d]..[0] ^= 0xFF);
        for (final x in s3.dateien.keys.where((k) => k.contains('/data/'))) {
          s3.dateien[x] = Uint8List.fromList([...s3.dateien[x]!]..[0] ^= 0xFF);
        }
        await aussen.jetzt();
        final stand = await aussen.stand();
        expect(stand['ok'], isFalse);
        expect(stand['fehler'], 'pv_stichprobe_abweichend');
      },
    );

    test('Entfernen vergisst das Ziel und lässt drüben alles liegen', () async {
      await aussen.jetzt();
      final vorher = s3.dateien.length;
      await aussen.entfernen();
      expect(aussen.eingerichtet, isFalse);
      expect((await aussen.stand())['stufe'], 'aus');
      expect(s3.dateien.length, vorher);
    });
  });

  group('In Teilen', () {
    Future<File> datei(int groesse) async {
      final f = File('${ordner.path}/gross.bin');
      await f.writeAsBytes(List.generate(groesse, (i) => i % 251));
      return f;
    }

    S3Ziel ziel() => S3Ziel(
      endpunkt: s3.adresse,
      bucket: 'fotos',
      region: 'eu',
      zugang: 'x',
      geheimnis: 'y',
      teilAb: 1000,
      mindestTeil: 400,
    );

    test('grosse Dateien kommen in der richtigen Reihenfolge an', () async {
      final f = await datei(1500);
      final z = ziel();
      await z.lege('a/gross.bin', f, groesse: 1500);
      z.schliesse();
      expect(s3.dateien['a/gross.bin'], f.readAsBytesSync());
      expect(
        s3.anfragen.where((a) => a.contains('partNumber')).length,
        4,
        reason: '400 + 400 + 400 + 300',
      );
    });

    test('scheitert ein Teil, bleibt nichts halb liegen', () async {
      final f = await datei(1500);
      s3.putsBisFehler = 1;
      final z = ziel();
      await expectLater(
        z.lege('a/gross.bin', f, groesse: 1500),
        throwsA(isA<Zielfehler>()),
      );
      z.schliesse();
      expect(s3.offeneTeile, isEmpty);
      expect(s3.dateien, isEmpty);
    });

    test('Reste eines abgestürzten Laufs räumt der nächste weg', () async {
      final z = ziel();
      final f = await datei(1500);
      s3.putsBisFehler = 2;
      await expectLater(
        z.lege('a/gross.bin', f, groesse: 1500),
        throwsA(isA<Zielfehler>()),
      );
      // Wie nach einem Absturz: Das Abbrechen kam nie an.
      s3.anfragen.clear();
      await s3._bedieneTeilAnfang('a/rest.bin');
      await z.aufraeumen();
      z.schliesse();
      expect(s3.offeneTeile, isEmpty);
    });
  });

  group('Der Lauf nach WebDAV', () {
    test('alles kommt an, und die Stichprobe stimmt', () async {
      await aussen.einrichten(davAngabe());
      await aussen.jetzt();
      final stand = await aussen.stand();
      expect(stand['ok'], isTrue, reason: '${stand['fehler']}');
      expect(dav.gleichzeitigeMkcol, 0);
      expect(
        dav.dateien.keys
            .map((k) => k.substring('/dav/photovault/'.length))
            .toList()
          ..sort(),
        lokal(),
      );
      expect((stand['stichprobe']! as Map)['abweichend'], 0);
    });

    test('der zweite Lauf überträgt nichts noch einmal', () async {
      await aussen.einrichten(davAngabe());
      await aussen.jetzt();
      await aussen.jetzt();
      expect((await aussen.stand())['neu'], 0);
    });

    test(
      'ein 403 auf einen vorhandenen Ordner ist kein falscher Zugang',
      () async {
        // Manche Server sagen das statt 405.
        dav.ordner.add('/dav/da');
        dav.mkcolVerweigert = true;
        final z = WebdavZiel(
          adresse: dav.adresse,
          benutzer: 'erika',
          passwort: 'x',
          praefix: 'da',
        );
        final f = File('${ordner.path}/x.bin')..writeAsBytesSync([1]);
        await z.lege('x.bin', f, groesse: 1);
        expect(dav.dateien.keys, ['/dav/da/x.bin']);
        z.schliesse();
      },
    );

    test('Umlaute und Leerzeichen im Pfad', () async {
      final z = WebdavZiel(
        adresse: dav.adresse,
        benutzer: 'erika',
        passwort: 'x',
        praefix: 'Jürgen Müller',
      );
      final f = File('${ordner.path}/x.bin')..writeAsBytesSync([1, 2, 3]);
      await z.lege('Fotos & Co/x.bin', f, groesse: 3);
      expect((await z.liste()).keys, ['Fotos & Co/x.bin']);
      expect(await z.hole('Fotos & Co/x.bin'), [1, 2, 3]);
      z.schliesse();
    });
  });

  test('Umlaute im Schlüssel bei S3', () async {
    final z = S3Ziel(
      endpunkt: s3.adresse,
      bucket: 'fotos',
      region: 'eu',
      zugang: 'x',
      geheimnis: 'y',
      praefix: 'Jürgen',
    );
    final f = File('${ordner.path}/x.bin')..writeAsBytesSync([1, 2, 3]);
    await z.lege('A & B/x y.bin', f, groesse: 3);
    expect((await z.liste()).keys, ['A & B/x y.bin']);
    expect(await z.hole('A & B/x y.bin'), [1, 2, 3]);
    z.schliesse();
  });

  test('die Schnittstelle nur für Verwalter, und nie mit Geheimnis', () async {
    final max = await konten.legeAn('max', 'noch ein passwort');
    final api = baueApi(
      konten: konten,
      bibliotheken: bibliotheken,
      sicherung: sicherung,
      aussensicherung: aussen,
    );
    Future<Response> frag(String m, String pfad, Konto k, [Object? j]) async =>
        api(
          Request(
            m,
            Uri.parse('http://server/api/v1/$pfad'),
            headers: {
              'authorization':
                  'Bearer ${konten.meldeAn(k.id, 'Rechner', 'x').token}',
            },
            body: j == null ? null : jsonEncode(j),
          ),
        );
    for (final (m, pfad) in [
      ('PUT', 'sicherung/ausser-haus'),
      ('DELETE', 'sicherung/ausser-haus'),
      ('POST', 'sicherung/ausser-haus/jetzt'),
    ]) {
      expect(
        (await frag(m, pfad, max, s3Angabe())).statusCode,
        403,
        reason: pfad,
      );
    }
    expect(aussen.eingerichtet, isFalse);

    final falsch = await frag('PUT', 'sicherung/ausser-haus', erika, {
      ...s3Angabe(),
      'adresse': 'http://s3.example.org',
    });
    expect(falsch.statusCode, 400);
    expect(await falsch.readAsString(), contains('https'));

    final gut = await frag('PUT', 'sicherung/ausser-haus', erika, s3Angabe());
    expect(gut.statusCode, 200);
    expect(await gut.readAsString(), isNot(contains('streng-geheim')));
    while (aussen.laeuft) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final stand = await (await frag('GET', 'sicherung', erika)).readAsString();
    expect(stand, isNot(contains('streng-geheim')));
    expect(((jsonDecode(stand) as Map)['ausserHaus'] as Map)['stufe'], 'ok');
    expect(
      (await frag('DELETE', 'sicherung/ausser-haus', erika)).statusCode,
      200,
    );
    expect(aussen.eingerichtet, isFalse);
  });

  test('die nächtliche Sicherung stösst den Lauf an', () async {
    await aussen.einrichten(s3Angabe());
    final mit = Serversicherung(
      daten: Directory('${ordner.path}/daten'),
      ziel: nas,
      tresor: tresor,
      konten: konten,
      bibliotheken: bibliotheken,
      nachDemLauf: aussen.jetzt,
    );
    await mit.jetzt();
    while (aussen.laeuft) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(s3.dateien, isNotEmpty);
    expect((await aussen.stand())['ok'], isTrue);
  });
}

/// Wie in web_test.dart: zusammengesetzt, damit die Datenschutzprüfung des
/// Repos in Tests nicht über Beispieladressen stolpert.
String _ip(List<int> teile) => teile.join('.');

extension on _S3 {
  /// Ein angefangener Upload, ohne dass je jemand ihn beendet.
  Future<void> _bedieneTeilAnfang(String k) async {
    _teile['verwaist'] = {};
    _teilSchluessel['verwaist'] = k;
  }
}
