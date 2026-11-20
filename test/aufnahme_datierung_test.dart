import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/xmp_writer.dart';
import 'package:photo_vault/services/xmp_reader.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';

void main() {
  test('Kalendergrenzen sind strikt, halboffen und ohne Uhrzeit', () {
    final d = AufnahmeDatierung.jahr(
      1985,
      quelle: Datierungsquelle.beschriftung,
      hinweis: 'Album',
    );
    expect(d.von, DateTime.utc(1985));
    expect(d.bis, DateTime.utc(1986));
    expect(
      AufnahmeDatierung.aus(
        jsonDecode(jsonEncode(d.alsJson())) as Map<String, dynamic>,
      ).alsJson(),
      d.alsJson(),
    );
    expect(() => AufnahmeDatierung.monat(1985, 13), throwsFormatException);
    expect(
      () => AufnahmeDatierung.aus({...d.alsJson(), 'von': '1985-02-30'}),
      throwsFormatException,
    );
    expect(
      () => AufnahmeDatierung.zeitraum(DateTime(1990), DateTime(1980)),
      throwsFormatException,
    );
    expect(
      () => AufnahmeDatierung.jahr(1985, hinweis: 'a\nb'),
      throwsFormatException,
    );
  });
  test(
    'Befehl, Kalender, XMP und Restore erhalten Bereich und Herkunft',
    () async {
      final temp = await Directory.systemTemp.createTemp('pv_kalender_');
      final db = AppDatabase(NativeDatabase.memory());
      final paths = await StoragePaths.forTesting(
        Directory('${temp.path}/lib'),
      );
      final imp = ImportService(db, paths);
      final file = File('${temp.path}/bild.jpg')..writeAsBytesSync([1, 2, 3]);
      final id = (await imp.importFile(file.path)).assetId!;
      final vorher = (await db.assetById(id))!;
      final d = AufnahmeDatierung.jahr(
        1985,
        quelle: Datierungsquelle.beschriftung,
        hinweis: 'Album',
      );
      final cmd = DatierungSetzen([id], d);
      await db.fuehreAus(Befehl.ausJson(cmd.alsJson()));
      final a = (await db.assetById(id))!;
      expect(a.fileCreatedAt, vorher.fileCreatedAt);
      expect(a.relativePath, vorher.relativePath);
      expect(a.kalenderdatierung!.alsJson(), d.alsJson());
      final raster = await db.alleRasterzeilen();
      expect(raster.single.datierung!.alsJson(), d.alsJson());
      expect(monatsgruppen(raster).schluessel, [198500]);
      expect((await db.assetCountsByYear())[1985], 1);
      expect((await db.assetCountsByMonth(1985))[0], 1);
      expect((await db.aufnahmenImMonat(1985, 0)).single.id, id);
      expect(await db.aufnahmenImMonat(1985, 1), isEmpty);
      expect(
        parseXmpContent(buildXmpPacket(a, []))!.datierung!.alsJson(),
        d.alsJson(),
      );
      final b = BackupService(db, paths);
      await b.performBackup('${temp.path}/backup').drain<void>();
      final restoredDb = AppDatabase(NativeDatabase.memory());
      final restoredPaths = await StoragePaths.forTesting(
        Directory('${temp.path}/restored'),
      );
      final restore = BackupService(restoredDb, restoredPaths);
      await restore
          .restoreFromBackup(
            '${temp.path}/backup/PhotoVault-Backup',
            ImportService(restoredDb, restoredPaths),
          )
          .drain<void>();
      final r = (await restoredDb.select(restoredDb.assets).get()).single;
      expect(r.kalenderdatierung!.alsJson(), d.alsJson());
      expect(r.fileCreatedAt, a.fileCreatedAt);
      await db.setAufnahmezeitpunkt(id, DateTime(1986, 4, 5, 12));
      expect((await db.assetById(id))!.kalenderdatierung, isNull);
      await restoredDb.close();
      await db.close();
      await temp.delete(recursive: true);
    },
  );
}
