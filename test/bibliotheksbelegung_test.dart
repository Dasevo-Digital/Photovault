import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/storage_paths.dart';

/// **„Es werden nur Originale ausgewiesen."**
///
/// Aus dem Erstlauf-Bericht (A06): "Speicherbedarf wird mit 1,57 GB
/// angezeigt, real im Finder 1,75 GB". Gezaehlt wurde allein
/// `originals/` - Vorschauen, Miniaturen, Gesichtsausschnitte und die
/// Datenbank fehlten, also gerade das, was die App selbst anlegt.
void main() {
  late Directory wurzel;
  late StoragePaths paths;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_belegung_');
    paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'library')));
  });

  tearDown(() => wurzel.deleteSync(recursive: true));

  void lege(String relativ, int bytes) {
    final datei = File(p.join(paths.root.path, relativ));
    datei.parent.createSync(recursive: true);
    datei.writeAsBytesSync(List.filled(bytes, 7));
  }

  void legeNeben(String name, int bytes) {
    File(p.join(paths.root.parent.path, name))
        .writeAsBytesSync(List.filled(bytes, 7));
  }

  test('eine leere Bibliothek belegt nichts', () async {
    final b = await paths.belegung();
    expect(b.gesamt, 0);
    expect(b.posten, isEmpty);
  });

  test('jeder Ordner zaehlt fuer sich', () async {
    lege('originals/2026/03/a.jpg', 1000);
    lege('previews/a.jpg', 300);
    lege('thumbnails/a.jpg', 100);
    final b = await paths.belegung();
    expect(b.teile['originals'], 1000);
    expect(b.teile['previews'], 300);
    expect(b.teile['thumbnails'], 100);
    expect(b.gesamt, 1400);
  });

  test('die Datenbank liegt NEBEN der Bibliothek und zaehlt mit', () async {
    lege('originals/a.jpg', 500);
    legeNeben('library.sqlite', 200);
    legeNeben('library.sqlite-wal', 50);
    legeNeben('library.sqlite-shm', 10);
    final b = await paths.belegung();
    expect(b.datenbank, 260);
    expect(b.gesamt, 760);
  });

  test('was in keinen bekannten Ordner faellt, verschwindet nicht', () async {
    // Genau der Fehler von vorher: Wer nur die bekannten Ordner zaehlt,
    // meldet wieder eine zu kleine Summe.
    lege('vergessen/rest.bin', 999);
    final b = await paths.belegung();
    expect(b.sonstiges, 999);
    expect(b.gesamt, 999);
    expect(b.posten.map((e) => e.name), contains('sonstiges'));
  });

  test('die Aufstellung laesst leere Posten weg', () async {
    lege('originals/a.jpg', 10);
    final b = await paths.belegung();
    expect(b.posten.map((e) => e.name), ['originals']);
  });

  test('die Aufstellung steht in fester Reihenfolge', () async {
    lege('trash/x.jpg', 1);
    lege('originals/a.jpg', 1);
    lege('thumbnails/a.jpg', 1);
    legeNeben('library.sqlite', 1);
    final b = await paths.belegung();
    // Originale zuerst, Datenbank und Sonstiges zuletzt - unabhaengig
    // davon, in welcher Reihenfolge die Dateien gefunden wurden.
    expect(b.posten.map((e) => e.name),
        ['originals', 'thumbnails', 'trash', 'datenbank']);
  });

  test('die Summe stimmt mit dem ueberein, was auf der Platte liegt',
      () async {
    lege('originals/2026/03/a.jpg', 1234);
    lege('previews/a.jpg', 567);
    lege('faces/a.png', 89);
    lege('vergessen/rest.bin', 10);
    legeNeben('library.sqlite', 42);
    var vonHand = 0;
    for (final e in paths.root.listSync(recursive: true)) {
      if (e is File) vonHand += e.lengthSync();
    }
    vonHand += File(p.join(paths.root.parent.path, 'library.sqlite')).lengthSync();
    expect((await paths.belegung()).gesamt, vonHand);
  });
}
