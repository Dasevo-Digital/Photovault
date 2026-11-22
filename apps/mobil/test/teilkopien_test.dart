// Kopien zum Teilen bleiben nicht liegen (#437).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_mobil/seiten/als_jpeg.dart';
import 'package:photo_vault_mobil/sicherung/dienst.dart';
import 'package:photo_vault_mobil/sicherung/kamerarolle.dart';
import 'package:photo_vault_mobil/sicherung/stand.dart';

/// Zählt nur, wie oft aufgeräumt wird.
class _Rolle implements Kamerarolle {
  var aufgeraeumt = 0;

  @override
  Future<List<Rolleneintrag>> eintraege({required bool videos}) async => [];

  @override
  Future<void> aufraeumen() async => aufgeraeumt++;

  @override
  Future<int> loesche(List<String> ids) async => 0;

  @override
  Future<List<String>> vorhanden(List<String> ids) async => ids;
}

void main() {
  test('JPEG-Kopien früherer Teilvorgänge gehen, anderes bleibt', () async {
    final wurzel = Directory.systemTemp.createTempSync('pv_teilkopien_');
    addTearDown(() => wurzel.deleteSync(recursive: true));
    for (final name in ['pv_jpeg_abc', 'pv_jpeg_def']) {
      File(p.join(wurzel.path, name, 'a1.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
    }
    final fremd = Directory(p.join(wurzel.path, 'etwas_anderes'))..createSync();
    final datei = File(p.join(wurzel.path, 'pv_jpeg_datei'))..createSync();

    await raeumeJpegKopienAuf(in_: wurzel);

    expect(
      [for (final e in wurzel.listSync()) p.basename(e.path)]..sort(),
      [p.basename(fremd.path), p.basename(datei.path)]..sort(),
    );
  });

  test('Kopien aus der Fotomediathek: weggeräumt, ausser ein Lauf hält die '
      'Sperre', () async {
    final ordner = Directory.systemTemp.createTempSync('pv_teilkopien_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final rolle = _Rolle();
    final d = Sicherungsdienst(
      ordner: ordner,
      server: Uri.parse('http://localhost:1/'),
      token: 'pv1_test',
      rolle: (_) => rolle,
    );
    addTearDown(d.dispose);

    await d.raeumeFotokopienAuf();
    expect(rolle.aufgeraeumt, 1);

    // Ein Lauf im Hintergrund lädt gerade aus dem Zwischenspeicher hoch.
    final stand = Sicherungsstand.oeffne(ordner);
    addTearDown(stand.schliesse);
    expect(stand.sperre('hintergrund-1'), isTrue);
    await d.raeumeFotokopienAuf();
    expect(rolle.aufgeraeumt, 1, reason: 'nicht unter dem Lauf weg');
    expect(stand.sperre('hintergrund-1'), isTrue, reason: 'Sperre unberührt');

    stand.gibFrei('hintergrund-1');
    await d.raeumeFotokopienAuf();
    expect(rolle.aufgeraeumt, 2);
    expect(stand.sperre('app'), isTrue, reason: 'danach wieder frei');
  });
}
