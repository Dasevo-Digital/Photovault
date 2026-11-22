import 'dart:io';

import 'package:photo_vault_server/src/dateiantwort.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Jedes Videoformat des Imports trägt seinen Medientyp (#232). Ohne ihn
/// lud der Browser eine MTS- oder MPG-Datei herunter, statt am Abspielen
/// zu scheitern – und holte deshalb nie die abspielbare Fassung.
void main() {
  late Directory ordner;
  setUp(() => ordner = Directory.systemTemp.createTempSync('pv_antwort_'));
  tearDown(() => ordner.deleteSync(recursive: true));

  for (final (endung, typ) in [
    ('.MTS', 'video/mp2t'),
    ('.mpg', 'video/mpeg'),
    ('.3gp', 'video/3gpp'),
    ('.wmv', 'video/x-ms-wmv'),
    ('.webm', 'video/webm'),
    ('.mkv', 'video/x-matroska'),
    ('.mov', 'video/quicktime'),
  ]) {
    test('$endung kommt als $typ', () async {
      final datei = File('${ordner.path}/clip$endung')
        ..writeAsBytesSync(List.filled(64, 0x47));
      final antwort = await dateiAntwort(
        Request('GET', Uri.parse('http://localhost/')),
        datei,
      );
      expect(antwort.headers['content-type'], typ);
    });
  }

  // #436: `bytes=-` und Zahlen, die nicht in int passen, warfen eine
  // FormatException – ein 500 ohne Anmeldung über jede Datei eines Links.
  group('Range, die nichts taugt', () {
    late File datei;
    setUp(() {
      datei = File('${ordner.path}/bild.jpg')
        ..writeAsBytesSync(List.generate(100, (i) => i));
    });
    Future<Response> mit(String range) => dateiAntwort(
      Request('GET', Uri.parse('http://localhost/'), headers: {'range': range}),
      datei,
    );
    const riesig = '99999999999999999999';

    test('bytes=- liefert die ganze Datei', () async {
      final r = await mit('bytes=-');
      expect(r.statusCode, 200);
      expect(r.headers['content-length'], '100');
    });
    test('ein Anfang jenseits jeder Datei: 416', () async {
      expect((await mit('bytes=$riesig-')).statusCode, 416);
    });
    test('ein Ende jenseits der Datei: bis zum Ende', () async {
      final r = await mit('bytes=10-$riesig');
      expect(r.statusCode, 206);
      expect(r.headers['content-range'], 'bytes 10-99/100');
    });
    test('mehr letzte Bytes, als es gibt: alle', () async {
      final r = await mit('bytes=-$riesig');
      expect(r.statusCode, 206);
      expect(r.headers['content-range'], 'bytes 0-99/100');
    });
  });
}
