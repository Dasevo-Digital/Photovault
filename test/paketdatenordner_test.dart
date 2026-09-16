// Wo die App im MSIX-Paket ihre Daten sucht.
//
// Windows meldet einem Paket einen anderen App-Support-Ordner als der
// ausgepackten Fassung. Ohne den Rückgriff auf den alten Ort stünde jeder,
// der vom Zip auf die Paketfassung wechselt, vor einer leeren App -
// während seine Bibliothek unauffindbar daneben liegt.
//
// Zwei Dinge werden getrennt geprüft: die Ableitung des alten Pfades
// (reine Zeichenkettenarbeit) und die Entscheidung, welcher der beiden
// Orte gewinnt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/library_location.dart';

void main() {
  setUpAll(() => LibraryLocation.pfadPruefungErzwingen = true);
  tearDownAll(() => LibraryLocation.pfadPruefungErzwingen = false);

  group('Ableitung des klassischen Ordners', () {
    test('aus einem echten Paketpfad', () {
      // Genau der Pfad, den die Windows-Sandbox gemeldet hat.
      const imPaket = r'C:\Users\WDAGUtilityAccount\AppData\Local\Packages'
          r'\PhotoVault.PhotoVault_c2mxqgqpdyab0\LocalCache\Roaming'
          r'\com.example\photo_vault';
      expect(
        LibraryLocation.klassischerDatenordner(imPaket),
        r'C:\Users\WDAGUtilityAccount\AppData\Roaming\com.example\photo_vault',
      );
    });

    test('Gross- und Kleinschreibung ist Windows egal', () {
      const imPaket = r'C:\Users\X\appdata\local\packages\PV_abc'
          r'\localcache\roaming\com.example\photo_vault';
      expect(
        LibraryLocation.klassischerDatenordner(imPaket),
        r'C:\Users\X\AppData\Roaming\com.example\photo_vault',
      );
    });

    test('ein gewoehnlicher Pfad ergibt null - da ist nichts umzuleiten', () {
      expect(
        LibraryLocation.klassischerDatenordner(
            r'C:\Users\X\AppData\Roaming\com.example\photo_vault'),
        isNull,
      );
    });

    test('halbe Uebereinstimmung ergibt null', () {
      // Packages ja, LocalCache\Roaming nein - das ist kein Behaelter,
      // aus dem sich ein alter Ort ableiten liesse.
      expect(
        LibraryLocation.klassischerDatenordner(
            r'C:\Users\X\AppData\Local\Packages\Irgendwas\LocalState'),
        isNull,
      );
    });
  });

  group('Welcher Ort gewinnt', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pv_datenordner'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Directory ordner(String name) => Directory(p.join(tmp.path, name));

    test('liegt am alten Ort eine location.json, gewinnt er', () async {
      final alt = ordner('alt')..createSync(recursive: true);
      File(p.join(alt.path, 'location.json')).writeAsStringSync('{}');
      final neu = ordner('neu');

      final gewaehlt = await LibraryLocation.waehleDatenordner(neu, alt);
      expect(gewaehlt.path, alt.path);
      // Und der Paketordner wird gar nicht erst angelegt.
      expect(neu.existsSync(), isFalse);
    });

    test('auch eine library.sqlite genuegt', () async {
      final alt = ordner('alt')..createSync(recursive: true);
      File(p.join(alt.path, 'library.sqlite')).writeAsBytesSync([1, 2, 3]);
      expect((await LibraryLocation.waehleDatenordner(ordner('neu'), alt)).path,
          alt.path);
    });

    test('und ein Modellordner ebenfalls - der ist teuer erkauft', () async {
      final alt = ordner('alt');
      Directory(p.join(alt.path, 'models')).createSync(recursive: true);
      expect((await LibraryLocation.waehleDatenordner(ordner('neu'), alt)).path,
          alt.path);
    });

    test('ein leerer alter Ordner zaehlt nicht', () async {
      // Er kann von einem abgebrochenen Lauf stammen. Ihn zu nehmen hiesse,
      // eine frische Installation an einen Ort zu binden, an dem nichts ist.
      final alt = ordner('alt')..createSync(recursive: true);
      final neu = ordner('neu');
      expect((await LibraryLocation.waehleDatenordner(neu, alt)).path, neu.path);
      expect(neu.existsSync(), isTrue);
    });

    test('gar kein alter Ort: der Paketordner entsteht', () async {
      final neu = ordner('neu');
      expect((await LibraryLocation.waehleDatenordner(neu, null)).path, neu.path);
      expect(neu.existsSync(), isTrue);
    });

    test('hat das Paket schon einen Ordner, bleibt es dabei', () async {
      // Sonst oeffnete die App je nach Tageslage eine andere Bibliothek.
      final alt = ordner('alt')..createSync(recursive: true);
      File(p.join(alt.path, 'location.json')).writeAsStringSync('{}');
      final neu = ordner('neu')..createSync(recursive: true);

      expect((await LibraryLocation.waehleDatenordner(neu, alt)).path, neu.path);
    });
  });
}
