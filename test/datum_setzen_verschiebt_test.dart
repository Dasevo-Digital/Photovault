import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Ein von Hand gesetztes Datum nimmt die Datei mit.**
///
/// Der Fund an der echten Bibliothek: Bei **1102 von 7988 Aufnahmen**
/// widersprechen sich Ablagepfad und Aufnahmedatum – die Datei liegt in
/// `originals/2007/01/`, die Zeile sagt 2013. Davon stammen 948 aus einer
/// einzigen Sammelbearbeitung und 148 aus einer zweiten.
///
/// Die Ursache: `setFileCreatedAt` und `setFileCreatedAtBulk` schreiben
/// nur die Spalte. Der Weg, der die Datei mitnimmt, lag daneben und wurde
/// nur von der Datumskorrektur benutzt.
///
/// **Warum das zählt, obwohl in der App nichts falsch aussieht.** Die App
/// geht immer über den in der Zeile vermerkten Pfad, ihr fällt es nie auf.
/// Es fällt dem auf, der die Bibliothek im Dateimanager ansieht, ein
/// Backup einspielt oder die Ordner für das nimmt, was sie behaupten zu
/// sein. Ein Ablageschema, dem man nicht trauen kann, ist keines.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late ImportService imp;
  late LibraryState library;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_datum_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
    imp = ImportService(db, pfade);
    library = LibraryState()
      ..db = db
      ..paths = pfade
      ..importService = imp;
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  var farbe = 0;

  Future<AssetData> lege(String name, DateTime dateizeit) async {
    final rein = Directory(p.join(temp.path, 'rein'))
      ..createSync(recursive: true);
    // Jedes Bild eine andere Farbe: gleiche Bytes gelten als Duplikat und
    // kommen gar nicht erst herein.
    final bild = img.Image(width: 8, height: 8);
    img.fill(bild, color: img.ColorRgb8(10 + (farbe++ * 17) % 200, 20, 30));
    final datei = File(p.join(rein.path, name))
      ..writeAsBytesSync(Uint8List.fromList(img.encodeJpg(bild)))
      ..setLastModifiedSync(dateizeit);
    final erg = await imp.importFile(datei.path);
    expect(erg.outcome, ImportOutcome.imported, reason: 'Import von $name');
    return (await db.assetById(erg.assetId!))!;
  }

  test('die Datei zieht in den Ordner des neuen Monats um', () async {
    final asset = await lege('a.jpg', DateTime(2007, 1, 4, 20, 28));
    expect(asset.relativePath, contains(p.join('2007', '01')));
    final alt = pfade.absolute(asset.relativePath);

    await library.setzeAufnahmedatumVonHand([asset.id], DateTime(2013, 8, 27));

    final neu = (await db.assetById(asset.id))!;
    expect(neu.fileCreatedAt, DateTime(2013, 8, 27));
    expect(neu.relativePath, contains(p.join('2013', '08')),
        reason: 'der Pfad muss dem neuen Datum folgen');
    expect(File(pfade.absolute(neu.relativePath).path).existsSync(), isTrue);
    expect(alt.existsSync(), isFalse,
        reason: 'am alten Ort darf nichts liegen bleiben');
  });

  test('Pfad und Datum stimmen danach überein – auch bei mehreren', () async {
    // Der Fall der echten Bibliothek: 948 Aufnahmen auf einen Schlag.
    final assets = [
      await lege('b1.jpg', DateTime(2007, 1, 4)),
      await lege('b2.jpg', DateTime(2011, 5, 9)),
      await lege('b3.jpg', DateTime(2019, 12, 31)),
    ];
    await library.setzeAufnahmedatumVonHand(
        [for (final a in assets) a.id], DateTime(2006, 8, 27));

    for (final alt in assets) {
      final neu = (await db.assetById(alt.id))!;
      final jahrMonat = p.join('${neu.fileCreatedAt.year}',
          neu.fileCreatedAt.month.toString().padLeft(2, '0'));
      expect(neu.relativePath, contains(jahrMonat));
      expect(File(pfade.absolute(neu.relativePath).path).existsSync(), isTrue);
    }
  });

  test('bleibt der Monat gleich, wird nichts verschoben', () async {
    final asset = await lege('c.jpg', DateTime(2020, 4, 5, 8));
    final vorher = asset.relativePath;
    await library
        .setzeAufnahmedatumVonHand([asset.id], DateTime(2020, 4, 30, 23, 59));
    final neu = (await db.assetById(asset.id))!;
    expect(neu.relativePath, vorher);
    expect(neu.fileCreatedAt, DateTime(2020, 4, 30, 23, 59));
  });

  test('eine unbekannte Kennung wird übergangen, nicht geworfen', () async {
    final asset = await lege('d.jpg', DateTime(2020, 4, 5));
    await library.setzeAufnahmedatumVonHand(
        ['gibtesnicht', asset.id], DateTime(2021, 7));
    expect((await db.assetById(asset.id))!.relativePath,
        contains(p.join('2021', '07')));
  });

  test('kein Bildschirm setzt das Datum an der Datenbankschicht vorbei', () {
    // Der eigentliche Schutz. Die beiden kurzen Wege bleiben für
    // Prüfstände erhalten – aber wer sie aus der Oberfläche ruft, baut den
    // Fehler wieder ein, und das sieht man dem Aufruf nicht an.
    final verstoesse = <String>[];
    for (final ordner in ['lib/screens', 'lib/widgets']) {
      for (final datei in Directory(ordner)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final zeilen = datei.readAsLinesSync();
        for (var i = 0; i < zeilen.length; i++) {
          if (RegExp(r'\.setFileCreatedAt(Bulk)?\(').hasMatch(zeilen[i])) {
            verstoesse.add('${datei.path}:${i + 1}');
          }
        }
      }
    }
    expect(verstoesse, isEmpty,
        reason: 'stattdessen LibraryState.setzeAufnahmedatumVonHand rufen – '
            'sonst bleibt die Datei im Ordner des alten Datums liegen');
  });
}
