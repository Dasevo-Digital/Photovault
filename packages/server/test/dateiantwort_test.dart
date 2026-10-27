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
}
