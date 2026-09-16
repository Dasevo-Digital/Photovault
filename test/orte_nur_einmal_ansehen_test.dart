import 'dart:async';
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

/// **„Orte einlesen" merkt sich, wo es schon nachgesehen hat.**
///
/// Der Lauf nahm bis Fassung 2.6 jede Aufnahme ohne Koordinate – an einer
/// echten Bibliothek 5756 von 7988 – und las sie **vollständig** ein, um
/// in den EXIF-Daten nachzusehen. Gemessen an 400 dieser Fotos: 3,3
/// Sekunden und 1215 MB für **null** Treffer, hochgerechnet rund 47
/// Sekunden und 17,5 GB je Lauf. Und beim nächsten Lauf wieder, denn ein
/// erfolgloser Blick hinterliess keine Spur.
///
/// Ein Screenshot trägt keinen Ort und wird auch beim zwanzigsten Lauf
/// keinen tragen.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState library;
  var farbe = 0;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_orte1x_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = pfade
      ..importService = ImportService(db, pfade);
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<AssetData> lege(String name) async {
    final rein = Directory(p.join(temp.path, 'rein'))
      ..createSync(recursive: true);
    final bild = img.Image(width: 8, height: 8);
    img.fill(bild, color: img.ColorRgb8(10 + (farbe++ * 29) % 200, 20, 30));
    final datei = File(p.join(rein.path, name))
      ..writeAsBytesSync(Uint8List.fromList(img.encodeJpg(bild)));
    final erg = await library.importService.importFile(datei.path);
    expect(erg.outcome, ImportOutcome.imported);
    return (await db.assetById(erg.assetId!))!;
  }

  test('der zweite Lauf hat nichts mehr zu tun', () async {
    await lege('a.jpg');
    await lege('b.jpg');
    expect(await db.countLocationBackfill(), 2);

    final erster = await library.backfillLocations().toList();
    expect(erster.last.done, 2);

    expect(await db.countLocationBackfill(), 0,
        reason: 'zweimal dieselben Dateien vollständig zu lesen bringt '
            'genau so viel wie einmal');
    final zweiter = await library.backfillLocations().toList();
    expect(zweiter.single.total, 0);
  });

  test('„Alle" sieht auch die wieder an, in denen schon gesucht wurde',
      () async {
    // Der Ausweg für Dateien, die ausserhalb der App nachträglich
    // Koordinaten bekommen haben.
    await lege('c.jpg');
    await library.backfillLocations().drain<void>();
    expect(await db.countLocationBackfill(), 0);
    expect(await db.countLocationBackfill(alle: true), 1);
    final erneut = await library.backfillLocations(alle: true).toList();
    expect(erneut.first.total, 1);
  });

  test('eine frisch importierte Aufnahme steht wieder an', () async {
    await lege('d.jpg');
    await library.backfillLocations().drain<void>();
    await lege('e.jpg');
    expect(await db.countLocationBackfill(), 1,
        reason: 'der Vermerk gilt der Datei, nicht der Bibliothek');
  });

  test('Zahl und Liste laufen nicht auseinander', () async {
    await lege('f.jpg');
    await lege('g.jpg');
    for (final alle in [false, true]) {
      expect(await db.countLocationBackfill(alle: alle),
          (await db.assetsForLocationBackfill(alle: alle)).length);
    }
    await library.backfillLocations().drain<void>();
    for (final alle in [false, true]) {
      expect(await db.countLocationBackfill(alle: alle),
          (await db.assetsForLocationBackfill(alle: alle)).length);
    }
  });

  test('ein Abbruch behält, was schon angesehen wurde', () async {
    // Der Vermerk wird blockweise geschrieben; den Rest muss der
    // `finally`-Block sichern. Ein gekündigtes Abonnement hält den
    // Generator beim nächsten `yield` an und läuft dort hindurch – ein
    // `onDone` kommt danach nicht mehr.
    for (var i = 0; i < 4; i++) {
      await lege('h$i.jpg');
    }
    final abgebrochen = Completer<void>();
    late StreamSubscription<ImportProgress> abo;
    var ereignisse = 0;
    abo = library.backfillLocations().listen((_) async {
      if (++ereignisse >= 3 && !abgebrochen.isCompleted) {
        abgebrochen.complete();
        await abo.cancel();
      }
    });
    await abgebrochen.future;
    await abo.cancel();

    final offen = await db.countLocationBackfill();
    expect(offen, lessThan(4),
        reason: 'was angesehen wurde, ist angesehen – auch nach Abbruch');
    expect(offen, greaterThan(0), reason: 'der Lauf war nicht durch');
  });
}
