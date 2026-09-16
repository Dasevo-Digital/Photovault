/// **Einen Ort für eine benannte Menge von Aufnahmen setzen.**
///
/// Kein Teil der Prüfsuite. Ein Werkzeug für den Fall, dass eine ganze
/// Gruppe von Aufnahmen an denselben Ort gehört und die Oberfläche dafür
/// zu umständlich wäre – etwa alle Aufnahmen einer Kamera, die nur an
/// einem Ort im Einsatz war.
///
/// Geht **durch die App**, nicht an ihr vorbei: [LibraryState.setzeOrtVonHand]
/// setzt Koordinate und Namen zusammen, und die Namen kommen aus
/// demselben Ortsverzeichnis, mit dem die App auch sonst nachschlägt.
/// Von Hand geschriebenes SQL träfe die Namen vielleicht anders, und
/// dann fänden Foto und Katalog nicht mehr zusammen.
///
/// ```sh
/// PV_DB=/pfad/library.sqlite PV_GEO=/pfad/geodata \
///   PV_BREITE=36.70904 PV_LAENGE=67.11087 \
///   PV_WAHL="camera_model='TG-810'" \
///   PV_TROCKEN=1 flutter test tool/ort_setzen_test.dart
/// ```
///
/// Ohne `PV_TROCKEN` wird wirklich geschrieben.
///
/// **Achtung, und das hat mich beim ersten Lauf fast erwischt:** Dieses
/// Werkzeug öffnet die Datenbank mit dem Quelltext von *jetzt*. Steht der
/// auf einer höheren Schemafassung als die ausgelieferte App, **wandert
/// die Bibliothek beim Öffnen mit** – und danach ist sie der installierten
/// Fassung voraus. Einmal an einer Kopie ausprobiert: 73 rein, 74 raus.
///
/// Für eine Bibliothek, die eine ältere App noch benutzt, gilt deshalb:
/// erst hier an einer **Kopie** laufen lassen, die entstandenen Werte
/// ablesen und sie dann mit einer einzigen SQL-Anweisung in die echte
/// Bibliothek schreiben. Der Zweck des Werkzeugs bleibt derselbe – es
/// liefert die Namen, die das Ortsverzeichnis der App liefern würde, und
/// die trifft man von Hand nicht zuverlässig.
library;

// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/reverse_geocoder.dart';
import 'package:photo_vault/state/library_state.dart';

void main() {
  test('Ort setzen', () async {
    final dbPfad = Platform.environment['PV_DB'];
    final geo = Platform.environment['PV_GEO'];
    final wahl = Platform.environment['PV_WAHL'];
    final breite = double.tryParse(Platform.environment['PV_BREITE'] ?? '');
    final laenge = double.tryParse(Platform.environment['PV_LAENGE'] ?? '');
    if (dbPfad == null || geo == null || wahl == null ||
        breite == null || laenge == null) {
      markTestSkipped('PV_DB/PV_GEO/PV_WAHL/PV_BREITE/PV_LAENGE fehlen');
      return;
    }
    final trocken = Platform.environment['PV_TROCKEN'] != null;

    final db = AppDatabase(NativeDatabase(File(dbPfad)));
    addTearDown(db.close);
    final geocoder = await ReverseGeocoder.loadFromFiles(
      citiesFile: File('$geo/cities1000.txt'),
      admin1File: File('$geo/admin1CodesASCII.txt'),
      countryFile: File('$geo/countryInfo.txt'),
    );
    // `paths` bleibt ungesetzt: [LibraryState.setzeOrtVonHand] fasst
    // keine Datei an – es aendert Koordinate und Namen, sonst nichts.
    final library = LibraryState()
      ..db = db
      ..geocoder = geocoder;

    final treffer = geocoder.lookup(breite, laenge);
    print('Ziel: ${treffer?.city}, ${treffer?.state}, ${treffer?.country}');

    final ids = (await db
            .customSelect('SELECT id FROM assets WHERE $wahl')
            .map((r) => r.read<String>('id'))
            .get())
        .toList();
    print('${ids.length} Aufnahmen betroffen');

    final vorher = await db
        .customSelect(
            'SELECT location_country AS l, count(*) AS n FROM assets '
            'WHERE $wahl GROUP BY 1')
        .map((r) => '${r.read<String?>('l') ?? '(ohne)'}: ${r.read<int>('n')}')
        .get();
    print('vorher: ${vorher.join(' · ')}');

    if (trocken) {
      print('TROCKENLAUF – nichts geschrieben');
      return;
    }
    await library.setzeOrtVonHand(ids, breite, laenge);

    final nachher = await db
        .customSelect(
            'SELECT location_country AS l, location_state AS s, '
            'location_city AS o, count(*) AS n FROM assets '
            'WHERE $wahl GROUP BY 1,2,3')
        .map((r) =>
            '${r.read<String?>('o')}, ${r.read<String?>('s')}, '
            '${r.read<String?>('l')}: ${r.read<int>('n')}')
        .get();
    print('nachher: ${nachher.join(' · ')}');
  });
}
